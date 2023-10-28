OutputColor :: enum
{
    None;
    Highlight;
    Info;
    Warning;
    Error;
    Fatal_Error;
}

g_error_counter : int;

DecimalLength :: inline (val : u64) -> int #must
{
    if !val
        return 1;

    i := 0;
    while val
    {
        i += 1;
        val /= 10;
    }

    return i;
}

AppendIndentation :: (builder : *StringBuilder, col : int, size : int, char : u8 = #char " ") -> int
{
    count := size - (col % size);
    for i : 0..count - 1
        StringBuilderAppendByte (builder,  char);

    return count;
}

#add_context print_squiggles := true;

PrintTokenLine :: (builder : *StringBuilder, range : TokenRange, print_squiggles := context.print_squiggles)
{
    file := GetFile (range.file_id);
    Assert (file != null);

    range_length := TokenRangeToString (range).count;

    str := file.text;
    line_start := range.byte_offset;
    while line_start > 0 && str[line_start - 1] != #char "\n"
        line_start -= 1;

    printed_ellipsis := false;
    current_line := range.line_start;
    line_digits := DecimalLength (cast (u64) range.line_end);

    while true
    {
        defer current_line += 1;

        line_len := 0;
        while line_start + line_len < str.count && str[line_start + line_len] != #char "\n"
            line_len += 1;

        line_str := MakeString (line_len, str.data + line_start);

        if current_line == range.line_end || current_line >= range.line_start && current_line < range.line_start + g_build_settings.max_reported_lines - 1
        {
            StringBuilderAppend (builder, " {:*} | ", line_digits, current_line);

            if line_start > range.byte_offset && line_start < range.byte_offset + range_length
                SetColor (builder, .Highlight);

            column := 0;
            for j : 0..line_len - 1
            {
                if line_start + j == range.byte_offset
                    SetColor (builder, .Highlight);

                if line_str[j] == #char "\t"
                {
                    column += AppendIndentation (builder, column, g_build_settings.tab_size);
                }
                else
                {
                    StringBuilderAppendByte (builder, line_str[j]);
                    column += 1;
                }

                if line_start + j == range.byte_offset + range_length - 1
                    SetColor (builder, .None);
            }

            StringBuilderAppend (builder, "\n");
            SetColor (builder, .None);
        }
        else if !printed_ellipsis
        {
            StringBuilderAppend (builder, "(...)\n");
            printed_ellipsis = true;
        }

        if line_start + line_len < str.count && str[line_start + line_len] == #char "\n"
            line_len += 1;

        if print_squiggles
        {
            if (current_line >= range.line_start && current_line < range.line_start + g_build_settings.max_reported_lines - 1) || current_line == range.line_end
            {
                for j : 0..line_digits - 1
                    StringBuilderAppend (builder, " ");
                StringBuilderAppend (builder, "    ");
                SetColor (builder, .Highlight);

                column := 0;
                for j : 0..line_len - 1
                {
                    if line_start + j >= range.byte_offset && line_start + j < range.byte_offset + range_length
                    {
                        if j < line_str.count && line_str[j] == #char "\t"
                        {
                            column += AppendIndentation (builder, column, g_build_settings.tab_size, #char "~");
                        }
                        else
                        {
                            StringBuilderAppend (builder, "~");
                            column += 1;
                        }
                    }
                    else if j < line_str.count && line_str[j] == #char "\t"
                    {
                        column += AppendIndentation (builder, column, g_build_settings.tab_size);
                    }
                    else
                    {
                        StringBuilderAppend (builder, " ");
                        column += 1;
                    }
                }

                StringBuilderAppend (builder, "\n");
                SetColor (builder, .None);
            }
        }

        line_start += line_len;

        if line_start >= range.byte_offset + range_length
            break;
    }

    if !print_squiggles
        StringBuilderAppend (builder, "\n");
}

IncrementErrorCounter :: inline ()
{
    if g_error_counter >= g_build_settings.max_errors
    {
        SetOutputColor (.Error);
        write_string ("Found too many errors, exiting...\n", to_standard_error = true);
        SetOutputColor (.None);
        Basic.exit (1);
    }

    g_error_counter += 1;
}

Highlight_Color_Str :: "\x1b[0;36m";
Info_Color_Str      :: "\x1b[1;32m";
Warning_Color_Str   :: "\x1b[1;33m";
Error_Color_Str     :: "\x1b[1;31m";
Fatal_Color_Str     :: "\x1b[1;35m";

SetOutputColor :: (color : OutputColor, stderr := true)
{
    if !g_build_settings.output_colors
        return;

    if stderr && !g_stderr_has_colors
        return;

    if !stderr && !g_stdout_has_colors
        return;

    if #complete color ==
    {
    case .None;
        write_string ("\x1b[0m", to_standard_error = stderr);
    case .Highlight;
        write_string (Highlight_Color_Str, to_standard_error = stderr);
    case .Info;
        write_string (Info_Color_Str, to_standard_error = stderr);
    case .Warning;
        write_string (Warning_Color_Str, to_standard_error = stderr);
    case .Error;
        write_string (Error_Color_Str, to_standard_error = stderr);
    case .Fatal_Error;
        write_string (Fatal_Color_Str, to_standard_error = stderr);
    }
}

SetColor :: (builder : *StringBuilder, color : OutputColor, stderr := true)
{
    if !g_build_settings.output_colors
        return;

    if stderr && !g_stderr_has_colors
        return;

    if !stderr && !g_stdout_has_colors
        return;

    if #complete color ==
    {
    case .None;
        StringBuilderAppend (builder, "\x1b[0m");
    case .Highlight;
        StringBuilderAppend (builder, Highlight_Color_Str);
    case .Info;
        StringBuilderAppend (builder, Info_Color_Str);
    case .Warning;
        StringBuilderAppend (builder, Warning_Color_Str);
    case .Error;
        StringBuilderAppend (builder, Error_Color_Str);
    case .Fatal_Error;
        StringBuilderAppend (builder, Fatal_Color_Str);
    }
}

Error :: (fmt_str : string, args : ..Any)
{
    builder : StringBuilder;

    SetColor (*builder, .Error);
    StringBuilderAppend (*builder, "Error: ");
    SetColor (*builder, .None);

    StringBuilderAppend (*builder, fmt_str, ..args);
    StringBuilderAppend (*builder, "\n");

    write_string (StringBuilderBuild (*builder), to_standard_error = true);

    IncrementErrorCounter ();
}

Report :: (range : TokenRange, color : OutputColor, category : string, fmt_str : string, args : ..Any)
{
    builder : StringBuilder;

    file := GetFile (range.file_id);
    Assert (file != null);

    StringBuilderAppend (*builder, "%:%:%, ", file.filename, range.line_start, range.char_start);

    SetColor (*builder, color);
    StringBuilderAppend (*builder, "%: ", category);
    SetColor (*builder, .None);

    StringBuilderAppend (*builder, fmt_str, ..args);
    StringBuilderAppend (*builder, "\n\n");

    PrintTokenLine (*builder, range);

    write_string (StringBuilderBuild (*builder), to_standard_error = true);
}

ReportWithoutSourceCode :: (range : TokenRange, color : OutputColor, category : string, fmt_str : string, args : ..Any)
{
    builder : StringBuilder;

    file := GetFile (range.file_id);
    Assert (file != null);

    StringBuilderAppend (*builder, "%:%:%, ", file.filename, range.line_start, range.char_start);

    SetColor (*builder, color);
    StringBuilderAppend (*builder, "%: ", category);
    SetColor (*builder, .None);

    StringBuilderAppend (*builder, fmt_str, ..args);
    StringBuilderAppend (*builder, "\n");

    write_string (StringBuilderBuild (*builder), to_standard_error = true);
}

Error :: inline (range : TokenRange, fmt_str : string, args : ..Any)
{
    Report (range, .Error, "Error", fmt_str, ..args);
    IncrementErrorCounter ();
}

ErrorNoSquiggles :: inline (range : TokenRange, fmt_str : string, args : ..Any)
{
    prev := context.print_squiggles;
    context.print_squiggles = false;
    Error (range, fmt_str, ..args);
    context.print_squiggles = prev;
}

Warning :: inline (range : TokenRange, fmt_str : string, args : ..Any)
{
    Report (range, .Warning, "Warning", fmt_str, ..args);
}

SyntaxError :: inline (range : TokenRange, fmt_str : string, args : ..Any)
{
    Report (range, .Error, "Syntax Error", fmt_str, ..args);
    IncrementErrorCounter ();
}

ExpectedError :: (prev : Token, tok : Token, kinds : ..TokenKind)
{
    err_builder : StringBuilder;

    if kinds.count == 1
    {
        StringBuilderAppend (*err_builder, "Expected %", Token_Names[kinds[0]]);
    }
    else
    {
        StringBuilderAppend (*err_builder, "Expected one of ");

        for kinds
        {
            if it_index == kinds.count - 1
                StringBuilderAppend (*err_builder, " or ");
            else if it_index != 0
                StringBuilderAppend (*err_builder, ", ");

            StringBuilderAppend (*err_builder, Token_Names[it]);
        }
    }

    StringBuilderAppend (*err_builder, " after %", Token_Names[prev.kind]);

    lexeme := Token_Lexemes[tok.kind];
    tok_string := TokenToString (tok);
    if !lexeme && tok_string.count > 0 && tok_string.count < 15
        StringBuilderAppend (*err_builder, ", but got % '%' instead", Token_Names[tok.kind], tok_string);
    else
        StringBuilderAppend (*err_builder, ", but got % instead", Token_Names[tok.kind]);

    Report (TokenRangeJoin (prev, tok), .Error, "Syntax Error", "%", StringBuilderBuild (*err_builder));
    IncrementErrorCounter ();
}

Info :: inline (range : TokenRange, fmt_str : string, args : ..Any)
{
    Report (range, .Info, "Info", fmt_str, ..args);
}

InfoWithoutSourceCode :: inline (range : TokenRange, fmt_str : string, args : ..Any)
{
    ReportWithoutSourceCode (range, .Info, "Info", fmt_str, ..args);
}

InfoNoSquiggles :: inline (range : TokenRange, fmt_str : string, args : ..Any)
{
    prev := context.print_squiggles;
    context.print_squiggles = false;
    Info (range, fmt_str, ..args);
    context.print_squiggles = prev;
}

AssertionFailed :: (location : Source_Code_Location, message : string)
{
    print_stack_trace :: (node: *Stack_Trace_Node) {  // @Cutnpaste from modules/Basic, but wihtout calling print.
        while node {
            // There are two different line numbers available.
            // node.info.location has a line number, but this is the location of
            // the start of the procedure. That may be useful in some cases, but often
            // what we really want is the line number of the procedure call, which is
            // stored in node.line_number. That's what we print in this case.

            if node.info {
                write_string(node.info.location.fully_pathed_filename, to_standard_error = true);
                write_string(":", to_standard_error = true);
                write_nonnegative_number(node.line_number, to_standard_error = true);
                write_string(": ", to_standard_error = true);
                if node.info.name write_string(node.info.name, to_standard_error = true);
                else write_string("(anonymous procedure)", to_standard_error = true);
                write_string("\n", to_standard_error = true);
            }

            node = node.next;
        }
    }

    SetOutputColor (.Fatal_Error);

    if context.panicking
        write_string ("Panic at file ", to_standard_error = true);
    else
        write_string ("Assertion failed at file ", to_standard_error = true);

    write_strings (location.fully_pathed_filename, ":", to_standard_error = true);
    write_number (location.line_number, to_standard_error = true);
    write_string (":", to_standard_error = true);
    write_number (location.character_number, to_standard_error = true);

    write_string ("\n", to_standard_error = true);
    SetOutputColor (.None);

    write_string (message, to_standard_error = true);

    if message.count > 0 && message[message.count - 1] != #char "\n"
        write_string ("\n", to_standard_error = true);

    write_string ("\n", to_standard_error = true);

    if context.stack_trace
    {
        write_string ("Stack trace:\n", to_standard_error = true);
        print_stack_trace (context.stack_trace);
    }

    __runtime_support_disable_stack_trace = true;
    debug_break();
}

#scope_file

AppendAssertFailureOrPanicMessage :: (builder : *StringBuilder, range : TokenRange, fmt_str : string, args : ..Any)
{
    file := GetFile (range.file_id);
    if !file
        StringBuilderAppend (builder, "<invalid file>, ");
    else
        StringBuilderAppend (builder, "%:%:%, ", file.filename, range.line_start, range.char_start);

    SetColor (builder, .Fatal_Error);
    StringBuilderAppend (builder, "Fatal Error: ");
    SetColor (builder, .None);

    StringBuilderAppend (builder, fmt_str, ..args);
    StringBuilderAppend (builder, "\n");

    if file
        PrintTokenLine (builder, range);
    else
        StringBuilderAppend (builder, "<cannot print token line because the file is invalid>\n");
}

#scope_export

Assert :: (range : TokenRange, assertion : bool, fmt_str : string, args : ..Any, location := #caller_location)
{
    if !assertion && !context.handling_assertion_failure
    {
        context.handling_assertion_failure = true;
        defer context.handling_assertion_failure = false;

        builder : StringBuilder;

        AppendAssertFailureOrPanicMessage (*builder, range, fmt_str, ..args);

        message := StringBuilderBuild (*builder);

        context.assertion_failed (location, message);
    }
}

Panic :: (range : TokenRange, fmt_str : string, args : ..Any, location := #caller_location)
{
    if !context.handling_assertion_failure
    {
        context.handling_assertion_failure = true;
        defer context.handling_assertion_failure = false;

        context.panicking = true;
        defer context.panicking = false;

        builder : StringBuilder;

        AppendAssertFailureOrPanicMessage (*builder, range, fmt_str, ..args);

        message := StringBuilderBuild (*builder);

        context.assertion_failed (location, message);
    }
}
