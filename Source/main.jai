#import "Common";
#import "Array";
#import "Hash_Map";
#import "String_Builder";

Basic :: #import "Basic";
Math :: #import "Math";
File :: #import "File";
JaiC :: #import "Compiler";

#load "tokens.jai";
#load "ast.jai";
#load "ast_print.jai";
#load "source_code_builder.jai";
#load "parsing.jai";
#load "error.jai";
#load "constant_eval.jai";
#load "checking.jai";

BuildSettings :: struct
{
    max_errors := 20;
    max_reported_lines := 8;
    tab_size := 4;
    output_colors := true;
}

g_stdout_has_colors, g_stderr_has_colors : bool;
g_build_settings : BuildSettings;

PlatformInit :: ()
{
    Kernel32 :: #system_library "Kernel32";
    GetStdHandle :: (nStdHandle : s32) -> *void #foreign Kernel32;
    GetConsoleMode :: (hConsoleHandle : *void, lpMode : *u32) -> s32 #foreign Kernel32;
    SetConsoleMode :: (hConsoleHandle : *void, dwMode : u32) -> s32 #foreign Kernel32;

    std_out := GetStdHandle (-11);
    std_err := GetStdHandle (-12);

    mode : u32;
    if GetConsoleMode (std_out, *mode)
        SetConsoleMode (std_out, mode | 0x04);

    if mode & 0x04
        g_stdout_has_colors = true;

    mode = 0;
    if GetConsoleMode (std_err, *mode)
        SetConsoleMode (std_err, mode | 0x04);

    if mode & 0x04
        g_stderr_has_colors = true;
}

PrintUsage :: ()
{
    SetOutputColor (.Info);
    write_string ("Usage: ", to_standard_error = true);
    SetOutputColor (.None);

    write_string ("yal [options*] filename\n", to_standard_error = true);
    write_string ("Valid options are:\n", to_standard_error = true);
    write_string ("  -no_colors: disable ANSI terminal colors\n", to_standard_error = true);
}

ExitIfError :: ()
{
    if g_error_counter > 0
    {
        SetOutputColor (.Error);
        write_string ("There were errors, exiting...\n", to_standard_error = true);
        SetOutputColor (.None);
        Basic.exit (1);
    }
}

main :: ()
{
    context.allocator = Temp;

    PlatformInit ();

    filenames : [..]string;

    args := Basic.get_command_line_arguments ();

    arg_error := false;
    for args
    {
        if it_index == 0
            continue;

        if it[0] != #char "-"
        {
            ArrayPush (*filenames, it);
        }
        else if it ==
        {
        case "-no_colors";
            g_build_settings.output_colors = false;

        case;
            Error ("%: unknown option", it);
            arg_error = true;
        }
    }

    if arg_error
    {
        PrintUsage ();
        Basic.exit (1);
    }

    if filenames.count == 0
    {
        Error ("no file provided");
        PrintUsage ();
        Basic.exit (1);
    }

    file_error := false;
    for filenames
    {
        if !AddFile (it)
        {
            file_error = true;
        }
    }

    if file_error
        Basic.exit (1);

    for g_files
    {
        ParseFile (it);
    }

    ExitIfError ();

    for g_files
    {
        CollectAllSymbolsInFile (it);
        ResolveAllIdentifiersInFile (it);
    }

    for g_files
    {
        PrintScope :: (scope : *Scope, indent_level := 0)
        {
            symbol := scope.first_symbol;
            while symbol
            {
                for 0..indent_level - 1
                    Print ("  ");

                Println ("% : % (%)", symbol.name, symbol.kind, symbol.flags);

                symbol = symbol.next;
            }

            for 0..indent_level - 1
                Print ("  ");
            Println ("{");

            child := scope.first_child;
            while child
            {
                PrintScope (child, indent_level + 1);
                child = child.next;
            }

            for 0..indent_level - 1
                Print ("  ");
            Println ("}");
        }

        Println ("Declared symbols in file %:", it.filename);
        PrintScope (it.scope);
        Print ("\n");
    }

    ExitIfError ();
}

#run
{
    JaiC.set_build_options_dc (.{output_executable_name="yal", output_path="../"});
}
