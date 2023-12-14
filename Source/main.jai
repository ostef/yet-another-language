// I'm thinking about making enum values start at 1 unless specified otherwise, so 0 is by
// default used as an 'invalid' enum value, which is convenient because 0 is the default initialized value

// @Todo: implicit bool conversion of integers and pointers in if and while condition expr
// @Todo: autocast operator
// @Todo: what to do with pointer arithmetic of zero sized types

#import "Common";
#import "Hash_Map";
#import "Hash_Set";
#import "Profiling" (Enable_Profiling = false);

Basic :: #import "Basic";
using, only (.["+", "-", "*", "/"]) Basic;

Math :: #import "Math";
File :: #import "File";
Process :: #import "Process";
String :: #import "String";
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
#load "c_code_generation.jai";

BuildSettings :: struct
{
    max_errors := 20;
    max_reported_lines := 8;
    tab_size := 4;
    output_colors := true;
    use_gcc := false;
}

g_stdout_has_colors, g_stderr_has_colors : bool;
g_build_settings : BuildSettings;

#if OS == .WINDOWS
{

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

}
else
{

PlatformInit :: ()
{
    libc :: #system_library "libc";
    isatty :: (fd : s32) -> s32 #foreign libc;

    // @Todo: ensure stdout and stderr can handle colors
    g_stdout_has_colors = cast (bool) isatty (1);
    g_stderr_has_colors = cast (bool) isatty (2);
    g_build_settings.use_gcc = true;
}

}

PrintUsage :: ()
{
    SetOutputColor (.Info);
    write_string ("Usage: ", to_standard_error = true);
    SetOutputColor (.None);

    write_string ("yal [options*] filename\n", to_standard_error = true);
    write_string ("Valid options are:\n", to_standard_error = true);
    write_string ("  -no_colors: disable ANSI terminal colors\n", to_standard_error = true);
    write_string ("  -gcc: use GCC as the C compiler to invoke for generated files\n", to_standard_error = true);
    write_string ("  -print_ast: print the AST for all the files if parsing is successful\n", to_standard_error = true);
}

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

    print_ast := false;
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
        case "-gcc";
            g_build_settings.use_gcc = true;
        case "-print_ast";
            print_ast = true;

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
    total_bytes_processed := 0;
    for g_files
    {
        ParseFile (it);
        total_lines_of_code += it.line;
        total_bytes_processed += it.byte_index;
    }

    parsing_end := Basic.current_time_monotonic ();
    parsing_time := Basic.to_float64_seconds (parsing_end - parsing_start);

    if print_ast
    {
        for g_files
            PrintFile (it);
    }

    ExitIfError ();

    checking_start := Basic.current_time_monotonic ();

    for g_files
    {
        CollectAllSymbolsInFile (it);

        ExitIfError ();

        CheckAllDeclarationsInFile (it);
    }

    checking_end := Basic.current_time_monotonic ();
    checking_time := Basic.to_float64_seconds (checking_end - checking_start);

    ExitIfError ();

    #if Use_Type_Cache
        Println ("Deduplicated % types\n", g_dedup_types_count);

    codegen_start := Basic.current_time_monotonic ();

    total_emitted_lines_of_code := 0;
    total_emitted_bytes := 0;
    for g_files
    {
        builder : SourceCodeBuilder;

        EmitCCodeForFile (*builder, it);

        total_emitted_lines_of_code += builder.current_line;

        it.emitted_c_code = Build (*builder);

        total_emitted_bytes += it.emitted_c_code.count;
    }

    codegen_end := Basic.current_time_monotonic ();
    codegen_time := Basic.to_float64_seconds (codegen_end - codegen_start);

    ExitIfError ();

    c_compiler_start := Basic.current_time_monotonic ();

    for g_files
    {
        filename := String.path_strip_extension (it.filename);
        basename := String.path_filename (filename);
        c_filename := FormatString ("%.generated.c", filename);
        #if OS == .WINDOWS
           output_filename := FormatString ("%.exe", basename);
        else
           output_filename := basename;

        File.write_entire_file (c_filename, it.emitted_c_code);

        command : string;
        if g_build_settings.use_gcc
            command = FormatString ("gcc % -o %", c_filename, output_filename);
        else
            command = FormatString ("cl % /nologo /link /OUT:%", c_filename, output_filename);
        command_strings := Process.break_command_into_strings (command);

        Println ("> %", command);

        result, output, error_output := Process.run_command (..command_strings, capture_and_return_output = true);
        if result.type == .FAILED_TO_LAUNCH
        {
            Error ("Could not invoke command '%'", command);
            continue;
        }

        if !g_build_settings.use_gcc
            error_output = output;

        if result.type != .EXITED || result.exit_code != 0
        {
            Error ("C compiler failed with exit code %:\n\n%", result.exit_code, error_output);
            continue;
        }
    }

    c_compiler_end := Basic.current_time_monotonic ();
    c_compiler_time := Basic.to_float64_seconds (c_compiler_end - c_compiler_start);

    ExitIfError ();

    {
        ChooseTimeUnit :: (value : float64) -> multiplier : float64, unit : string
        {
            if value < 1 / (1000.0 * 1000.0)
                return 1000 * 1000 * 1000, "ns";
            if value < 1 / 1000.0
                return 1000 * 1000, "μs";
            if value < 1
                return 1000, "ms";

            return value, " s";
        }

        // We don't sample the total time so the percentages add up to 1
        yal_time := parsing_time + checking_time + codegen_time;
        total_time_sec := yal_time + c_compiler_time;
        total_time := total_time_sec;
        parsing_time_percent := cast (float) (ifx total_time < 0.00001 then 0.0 else parsing_time / total_time) * 100;
        checking_time_percent := cast (float) (ifx total_time < 0.00001 then 0.0 else checking_time / total_time) * 100;
        codegen_time_percent := cast (float) (ifx total_time < 0.00001 then 0.0 else codegen_time / total_time) * 100;
        yal_time_percent := cast (float) (ifx total_time < 0.00001 then 0.0 else yal_time / total_time) * 100;
        c_compiler_time_percent := cast (float) (ifx total_time < 0.00001 then 0.0 else c_compiler_time / total_time) * 100;

        time_unit_mult, time_unit := ChooseTimeUnit (total_time);
        parsing_time *= time_unit_mult;
        checking_time *= time_unit_mult;
        codegen_time *= time_unit_mult;
        c_compiler_time *= time_unit_mult;
        yal_time *= time_unit_mult;
        total_time *= time_unit_mult;

        max_leading_digits := DecimalLength (cast (u64) Max (Max (Max (parsing_time, checking_time), Max (codegen_time, total_time)), Max (yal_time, c_compiler_time)));

        Println ("\nTiming information (processed % lines of code):", total_lines_of_code);
        time_fmt := FormatFloat.{
            value=parsing_time,
            width=max_leading_digits + 3,
            trailing_width=2,
            zero_removal=.NO
        };
        time_percent_fmt := FormatInt.{
            value=cast (int) Round (parsing_time_percent),
            minimum_digits=4,
            padding=#char " "
        };

        Println ("  Parsing:    % %, %\% of total time", time_fmt, time_unit, time_percent_fmt);

        time_fmt.value = checking_time;
        time_percent_fmt.value = cast (int) Round (checking_time_percent);
        Println ("  Checking:   % %, %\% of total time", time_fmt, time_unit, time_percent_fmt);

        time_fmt.value = codegen_time;
        time_percent_fmt.value = cast (int) Round (codegen_time_percent);
        Println ("  Codegen:    % %, %\% of total time", time_fmt, time_unit, time_percent_fmt);

        time_fmt.value = yal_time;
        time_percent_fmt.value = cast (int) Round (yal_time_percent);
        Println ("  => Total:   % %, %\% of total time\n", time_fmt, time_unit, time_percent_fmt);

        time_fmt.value = c_compiler_time;
        time_percent_fmt.value = cast (int) Round (c_compiler_time_percent);
        Println ("  C compiler: % %, %\% of total time", time_fmt, time_unit, time_percent_fmt);

        Println ("  => Total:   % %, % lines of code per second\n", total_time, time_unit, cast (int) (total_lines_of_code / total_time_sec));

        Print ("Total lines of C code emitted: %", total_emitted_lines_of_code);
        if total_emitted_bytes > total_bytes_processed
        {
            Println (", emitted code is %\% bigger than source code",
                Round (total_emitted_bytes / cast (float) total_bytes_processed * 100) - 100);
        }
        else    // Honestly I don't even know how that would be possible but let's handle it anyway
        {
            Println (", emitted code is %\% smaller than source code",
                100 - Round (total_emitted_bytes / cast (float) total_bytes_processed * 100));
        }

        memory_usage := context.temporary_storage.high_water_mark;
        if memory_usage < 1000
            Println ("Total memory used by the compiler: % bytes", memory_usage);
        else if memory_usage < 1000_000
            Println ("Total memory used by the compiler: % kilo-bytes", memory_usage / 1000);
        else if memory_usage < 1000_000_000
            Println ("Total memory used by the compiler: % mega-bytes", memory_usage / 1000_000);
        else if memory_usage < 1000_000_000_000
            Println ("Total memory used by the compiler: % giga-bytes", memory_usage / 1000_000_000);
    }
}

#run
{
    JaiC.set_build_options_dc (.{output_executable_name="yal", output_path="../"});
}
