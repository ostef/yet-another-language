// @Todo: handle circular dependencies
// @Todo: handle integer literal conversions to smaller and unsigned integers as well as floats

#import "Common";
#import "Array";
#import "Hash_Map";
#import "String_Builder";
#import "Profiling" (Enable_Profiling = false);

Basic :: #import "Basic";
using, only (.["+", "-", "*", "/"]) Basic;

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
#load "types.jai";

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

#scope_file

PrintProfilingResults :: ()
{
    AddGlobalProfilingData (*context.profiling_entries);
    entries := LockGlobalProfilingData ();
    defer UnlockGlobalProfilingData ();

    if entries.count > 0
    {
        builder : StringBuilder;
        PrintProfilingData (*builder, entries);
        LogMessage ("\nProfiling results:\n%", StringBuilderBuild (*builder));
    }
}

#scope_export

ExitIfError :: ()
{
    if g_error_counter > 0
    {
        SetOutputColor (.Error);
        write_string ("There were errors, exiting...\n", to_standard_error = true);
        SetOutputColor (.None);

        PrintProfilingResults ();

        Basic.exit (1);
    }
}

main :: ()
{
    context.allocator = Temp;
    context.assertion_failed = AssertionFailed;

    PlatformInit ();
    ProfilingInit ();

    defer PrintProfilingResults ();

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

    InitBuiltinTypes ();

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

    parsing_start := Basic.current_time_monotonic ();

    total_lines_of_code := 0;
    for g_files
    {
        ParseFile (it);
        total_lines_of_code += it.line;
    }

    parsing_end := Basic.current_time_monotonic ();
    total_parsing_time := Basic.to_float64_seconds (parsing_end - parsing_start);

    ExitIfError ();

    checking_start := Basic.current_time_monotonic ();

    for g_files
    {
        CollectAllSymbolsInFile (it);

        ExitIfError ();

        CheckAllDeclarationsInFile (it);
    }

    checking_end := Basic.current_time_monotonic ();
    total_checking_time := Basic.to_float64_seconds (checking_end - checking_start);

    ExitIfError ();

    {
        // We don't sample the total time so the percentages add up to 1
        total_time := total_parsing_time + total_checking_time;
        total_time_ms := total_time * 1000.0;

        parsing_time_ms := total_parsing_time * 1000.0;
        parsing_time_percent := ifx total_time_ms < 0.00001 then 0.0 else parsing_time_ms / total_time_ms;

        checking_time_ms := total_checking_time * 1000.0;
        checking_time_percent := ifx total_time_ms < 0.00001 then 0.0 else checking_time_ms / total_time_ms;

        max_leading_digits := DecimalLength (cast (u64) Max (Max (parsing_time_ms, checking_time_ms), total_time_ms));

        Println ("Timing information (processed % lines of code):", total_lines_of_code);
        Println ("  Parsing:  {:*.2} ms, {:6.2}%% of total time", max_leading_digits + 3, parsing_time_ms, 100 * parsing_time_percent);
        Println ("  Checking: {:*.2} ms, {:6.2}%% of total time", max_leading_digits + 3, checking_time_ms, 100 * checking_time_percent);
        Println ("  Total:    {:*.2} ms", max_leading_digits + 3, total_time_ms);

        memory_usage := context.temporary_storage.high_water_mark;
        if memory_usage < 1000
            Println ("\nTotal memory used by the compiler: % bytes", memory_usage);
        else if memory_usage < 1000_000
            Println ("\nTotal memory used by the compiler: {:.2} kilo-bytes", memory_usage / 1000.0);
        else if memory_usage < 1000_000_000
            Println ("\nTotal memory used by the compiler: {:.2} mega-bytes", memory_usage / 1000_000.0);
        else if memory_usage < 1000_000_000_000
            Println ("\nTotal memory used by the compiler: {:.2} giga-bytes", memory_usage / 1000_000_000.0);
    }
}

#run
{
    JaiC.set_build_options_dc (.{output_executable_name="yal", output_path="../"});
}
