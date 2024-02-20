SourceCodeBuilder :: struct
{
    using base : StringBuilder;
    auto_indent_increment := true;
    auto_indent := true;
    max_consecutive_empty_lines := 1;
    current_indent_level : int;
    empty_lines_above : int;
    current_line : int;
    current_char : int;

    write_byte :: (builder : *SourceCodeBuilder, byte : u8)
    {
        if builder && byte
            AppendByte (builder, byte);
    }

}

Indent :: inline (using builder : *SourceCodeBuilder)
{
    current_indent_level += 1;
}

Unindent :: inline (using builder : *SourceCodeBuilder)
{
    Assert (current_indent_level > 0, "Mismatching number of Indent/Unindent calls");

    current_indent_level -= 1;
}

AppendByte :: (using builder : *SourceCodeBuilder, byte : u8)
{
    if auto_indent_increment
    {
        if byte ==
        {
        case #char "]"; #through;
        case #char "}"; #through;
        case #char ")";
            Unindent (builder);
        }
    }

    if current_char == 0 && auto_indent
    {
        for i : 0..current_indent_level - 1
            current_char += StringBuilderAppend (*base, "    ");
    }

    if byte == #char "\n"
    {
        if empty_lines_above < max_consecutive_empty_lines
            current_char += StringBuilderAppendByte (*base, byte);

        if current_char == 0
            empty_lines_above += 1;
        current_line += 1;
        current_char = 0;

        return;
    }

    if auto_indent_increment
    {
        if byte ==
        {
        case #char "["; #through;
        case #char "{"; #through;
        case #char "(";
            Indent (builder);
        }
    }

    current_char += StringBuilderAppendByte (*base, byte);

    empty_lines_above = 0;
}

Append :: (using builder : *SourceCodeBuilder, str : string)
{
    for i : 0..str.count - 1
        AppendByte (builder, str[i]);
}

AppendStringLiteral :: (using builder : *SourceCodeBuilder, str : string)
{
    StringBuilderAppendStringLiteral (*base, str);
}

Append :: (using builder : *SourceCodeBuilder, format_string : string, args : ..Any)
{
    // @Speed
    formatted := SPrint (format_string, ..args,, Temp);
    Append (builder, formatted);
}
@PrintLike

Build :: inline (builder : *SourceCodeBuilder, reset_builder := true) -> string #must
{
    str := StringBuilderBuild (*builder.base, reset_builder);

    if reset_builder
    {
        builder.current_indent_level = 0;
        builder.empty_lines_above = 0;
        builder.current_line = 0;
        builder.current_char = 0;
    }

    return str;
}
