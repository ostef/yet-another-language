#import "Common";

Basic :: #import "Basic";
using, only(.["+", "-", "*", "/"]) Basic;

#import "File";
#import "File_Utilities";
#import "Process";
#import "Metaprogram_Plugins";
#import "String";
#import "Compiler";

#load "Source/preload.jai";

Files_To_Benchmark :: string.[
    "Samples/breakout.yal",
];

Benchmark_Iterations :: 10;

Default_Plugins :: string.[
];

CleanupTestsDirectory :: (directory : string) {
    files := file_list(directory, recursive=true);
    for files {
        if path_extension(it) == {
        case "s"; #through;
        case "ssa"; #through;
        case "yair"; #through;
        case "gv"; #through;
        case "png"; #through;
        case "txt";
            file_delete(it);
        }
    }
}

TestsResult :: struct {
    failed_to_compile : int;
    failed_to_run_in_interpreter : int;
    failed : int;
    passed : int;
    total_tests : int;
}

ExecuteTests :: (directory : string, verbose : bool, using results : *TestsResult) {
    LogTestResult :: (color : string, header : string, msg : string, args : ..Any) {
        if g_console_logger.print_colors {
            LogMessage("%0%0%: %", color, header, None_Color_Str, TPrint(msg, ..args));
        } else {
            LogMessage("%: %", header, TPrint(msg, ..args));
        }
    }

    CleanupTestsDirectory(directory);

    test_timeout_in_seconds := 5;
    files := file_list(directory, recursive=true);
    QuickSort(files, StringCompare);

    for files {
        if path_extension(it) != "yal" {
            continue;
        }

        name := path_filename(it);
        compile_should_fail := StringEndsWith(name, ".fail_compile.yal");
        run_should_fail := StringEndsWith(name, ".fail.yal");
        no_run := StringEndsWith(name, ".no_run.yal");

        yal_command := ifx OS == .WINDOWS then "yal" else "./yal";
        exe_path := ifx OS == .WINDOWS then SPrint("%.exe", path_strip_extension(it)) else SPrint("./%.out", path_strip_extension(it));
        total_tests += 1;
        result, stdout, stderr, timeout := run_command(yal_command, "-module_dir", "Samples", "-output_ir", "-allow_no_entry_point", it, "-o", exe_path, capture_and_return_output=true, timeout_ms=test_timeout_in_seconds * 1000);
        if compile_should_fail {
            write_entire_file(SPrint("%.compile.stderr.txt", path_strip_extension(it)), stderr);
        }

        compile_crashed := result.type == .EXITED && result.exit_code != 0 && result.exit_code != 1 || result.type == .SIGNALED;
        compile_failed := result.type == .EXITED && result.exit_code == 1;
        if result.type != .EXITED || compile_failed != compile_should_fail || timeout || compile_crashed {
            failed += 1;
            failed_to_compile += 1;
            if timeout {
                LogTestResult(Error_Color_Str, "FAIL (compile timeout)", it);
            } else if compile_crashed {
                LogTestResult(Error_Color_Str, "FAIL (compile crash)", it);
            } else if compile_should_fail {
                LogTestResult(Error_Color_Str, "FAIL (compile OK)", it);
            } else {
                LogTestResult(Error_Color_Str, "FAIL (compile)", it);
            }

            if verbose {
                LogMessage("%", stderr);
            }

            if !compile_should_fail {
                write_entire_file(SPrint("%.compile.stderr.txt", path_strip_extension(it)), stderr);
            }

            continue;
        }

        if !no_run && !compile_should_fail {
            result, stdout, stderr, timeout = run_command(yal_command, "-module_dir", "Samples", "-allow_no_entry_point", "-interpreter", it, capture_and_return_output=true, timeout_ms=test_timeout_in_seconds * 1000);


            interp_crashed := result.type == .EXITED && result.exit_code != 0 && result.exit_code != 1 || result.type == .SIGNALED;
            interp_failed := result.type == .EXITED && result.exit_code == 1;
            if result.type != .EXITED || interp_failed != run_should_fail || timeout || interp_crashed {
                failed += 1;
                failed_to_run_in_interpreter += 1;
                if timeout {
                    LogTestResult(Error_Color_Str, "FAIL (interp timeout)", it);
                } else if interp_crashed {
                    LogTestResult(Error_Color_Str, "FAIL (interp crash)", it);
                } else if run_should_fail {
                    LogTestResult(Error_Color_Str, "FAIL (interp OK)", it);
                } else {
                    LogTestResult(Error_Color_Str, "FAIL (interp)", it);
                }

                if verbose {
                    LogMessage("%", stderr);
                }

                write_entire_file(SPrint("%.interpreter.stderr.txt", path_strip_extension(it)), stderr);
                write_entire_file(SPrint("%.interpreter.stdout.txt", path_strip_extension(it)), stdout);

                continue;
            }
        }

        passed += 1;
        LogTestResult(Info_Color_Str, "PASS", it);
    }
}

ExecuteTests :: (verbose : bool) {
    using results : TestsResult;
    ExecuteTests("Tests", verbose, *results);

    Log := ifx passed < total_tests then LogError else LogMessage;
    Log("  %\% tests passed (%/%), % test% failed to compile, % test% failed to run in the interpreter",
        cast(int, (passed / cast(float, total_tests)) * 100),
        passed, total_tests,
        failed_to_compile, ifx failed_to_compile > 1 then "s",
        failed_to_run_in_interpreter, ifx failed_to_run_in_interpreter > 1 then "s"
    );

    if passed < total_tests {
        Basic.exit(1);
    }
}

BuildConfig :: enum {
    Debug;
    OptimizedDebug;
    Release;
}

SetBuildConfig :: (options : *Build_Options, config : BuildConfig) {
    if #complete config == {
    case .Debug;
        set_optimization(options, .DEBUG, preserve_debug_info=true);
        options.backend = .X64;
        options.stack_trace = true;
        options.array_bounds_check = .ON;
        options.cast_bounds_check  = .FATAL;
        options.null_pointer_check = .ON;
        options.arithmetic_overflow_check = .OFF;

    case .OptimizedDebug;
        set_optimization(options, .OPTIMIZED, preserve_debug_info=true);
        options.backend = .LLVM;
        options.stack_trace = true;
        options.array_bounds_check = .ON;
        options.cast_bounds_check  = .FATAL;
        options.null_pointer_check = .ON;
        options.arithmetic_overflow_check = .OFF;

    case .Release;
        set_optimization(options, .VERY_OPTIMIZED, preserve_debug_info=false);
        options.backend = .LLVM;
        options.stack_trace = false;
        options.array_bounds_check = .OFF;
        options.cast_bounds_check  = .OFF;
        options.null_pointer_check = .OFF;
        options.arithmetic_overflow_check = .OFF;
    }
}

ToLexicographicString :: (ct : Basic.Calendar_Time) -> string {
    using ct;

    DatePart :: #bake_arguments Basic.formatInt(minimum_digits=2);

    time_string := TPrint("%-%-%_%h%m%s_%", year, DatePart(month_starting_at_0 + 1), DatePart(day_of_month_starting_at_0 + 1), DatePart(hour), DatePart(minute), DatePart(second), ct.time_zone);
    return time_string;
}

CreateBenchmarkCSVCompilation :: () {
    files := file_list("Benchmarks");
    QuickSort(files, StringCompare);

    date_and_times : [..]string;

    for files {
        if path_extension(it) == "csv" {
            continue;
        }

        ArrayPush(*date_and_times, path_basename(it));
    }

    commit_ids := AllocArray(string, date_and_times.count);

    BenchmarkedFile :: struct {
        filename : string;
        lines_processed : []int;
        timings : [][4]float64;
    }

    benchmarked_files : [..]BenchmarkedFile;

    for files {
        if path_extension(it) == "csv"{
            continue;
        }

        contents := read_entire_file(it);
        lines := split(contents, "\n");

        date_and_time := path_basename(it);

        date_index := ArrayFindFirst(date_and_times, date_and_time);
        Assert(date_index >= 0);

        for l : lines {
            line := trim(l);
            if line.count == 0 {
                continue;
            }

            if StringStartsWith(line, "Commit id: ") {
                commit_id := StringAdvance(line, "Commit id: ".count);
                commit_id.count = Min(commit_id.count, 7);
                commit_ids[date_index] = commit_id;
            } else if StringStartsWith(line, "Compiler version: ") {
                version := StringAdvance(line, "Compiler version: ".count);
                if !contains(version, "Release") {
                    LogWarning("Ignoring benchmark file '%' because it was not compiled in Release config", it);
                    continue it;
                }

                if contains(version, "Tracy") {
                    LogWarning("Ignoring benchmark file '%' because it was compiled with Tracy client", it);
                    continue it;
                }
            } else {
                space_index := find_index_from_left(line, "\t");
                filename := string.{count=space_index, data=line.data};
                timings := StringAdvance(line, space_index + 1);
                _, lines:,  timings = split_from_left(timings, "/");
                _, min:,    timings = split_from_left(timings, "/");
                _, max:,    timings = split_from_left(timings, "/");
                _, avg:,    timings = split_from_left(timings, "/");
                _, median:, timings = split_from_left(timings, "/");

                bench : *BenchmarkedFile;
                for * benchmarked_files {
                    if it.filename == filename {
                        bench = it;
                        break;
                    }
                }

                if !bench {
                    bench = ArrayPush(*benchmarked_files);
                    bench.filename = filename;
                    bench.timings = AllocArray([4]float64, date_and_times.count);
                    bench.lines_processed = AllocArray(int, date_and_times.count);
                }

                bench.lines_processed[date_index] = Basic.string_to_int(lines);

                bench.timings[date_index][0] = Basic.string_to_float64(min);
                bench.timings[date_index][1] = Basic.string_to_float64(max);
                bench.timings[date_index][2] = Basic.string_to_float64(avg);
                bench.timings[date_index][3] = Basic.string_to_float64(median);
            }
        }
    }

    CompileBenchmarks :: (filename : string, headers : []string, files : []BenchmarkedFile, timing_index : int) {
        builder : StringBuilder;

        if timing_index == {
        case 0; Append(*builder, "Min LOC/s,");
        case 1; Append(*builder, "Max LOC/s,");
        case 2; Append(*builder, "Avg LOC/s,");
        case 3; Append(*builder, "Median LOC/s,");
        }

        for files {
            Append(*builder, "%,", it.filename);
        }
        Append(*builder, "\n");

        for header, index : headers {
            Append(*builder, "%,", header);

            for files {
                time := it.timings[index][timing_index];
                if time > 0 {
                    Append(*builder, "%,", cast(int, it.lines_processed[index] / (time / 1000.0)));
                } else {
                    Append(*builder, ",");
                }
            }

            Append(*builder, "\n");
        }

        write_entire_file(filename, *builder);
        LogMessage("Outputted benchmarks compilation to '%'", filename);
    }

    CompileBenchmarks("Benchmarks/compilation_max.csv", commit_ids, benchmarked_files, 0);
    CompileBenchmarks("Benchmarks/compilation_min.csv", commit_ids, benchmarked_files, 1);
    CompileBenchmarks("Benchmarks/compilation_avg.csv", commit_ids, benchmarked_files, 2);
    CompileBenchmarks("Benchmarks/compilation_median.csv", commit_ids, benchmarked_files, 3);
}

// You probably did not expect to see this function, but we need it because
// benchmarks are not as good when a laptop is on battery, so we prevent
// execution of benchmarks in that case
LaptopIsOnBattery :: () -> bool {
    #if OS == .WINDOWS {
        SYSTEM_POWER_STATUS :: struct {
            ACLineStatus : u8;
            BatteryFlag : u8;
            BatteryLifePercent : u8;
            SystemStatusFlag : u8;
            BatteryLifeTime : u32;
            BatteryFullLifeTime : u32;
        }

        Kernel32 :: #system_library "Kernel32";
        GetSystemPowerStatus :: (lpSystemPowerStatus : *SYSTEM_POWER_STATUS) -> s32 #foreign Kernel32;

        status : SYSTEM_POWER_STATUS;
        if GetSystemPowerStatus(*status) {
            return status.ACLineStatus == 0;
        }

        return false;
    } else #if OS == .LINUX {
        #import "POSIX";

        Sys_Dir :: "/sys/class/power_supply";
        dir := opendir(Sys_Dir);
        if !dir {
            return false;
        }

        dirent := readdir(dir);
        while dirent {
            defer dirent = readdir(dir);

            dir_name := MakeString(dirent.d_name.data);
            if !StringStartsWith(dir_name, "BAT") {
                continue;
            }

            status_filename := SPrint("%/%/status", Sys_Dir, dir_name);
            contents := read_entire_file(status_filename);
            if trim(contents) == {
            case "Discharging"; return true;
            case "Full"; return false; // Does full means charging also?
            case "Charging"; return false;
            }
        }

        return false;
    } else {
        #assert false "@Todo";
    }
}

ExecuteBenchmarks :: () {
    if LaptopIsOnBattery() {
        LogError("Benchmarks are disabled for laptops on battery");
        return;
    }

    LogMessage("Executing benchmarks");

    prev_format_float := context.print_style.default_format_float;
    defer context.print_style.default_format_float = prev_format_float;

    context.print_style.default_format_float.trailing_width = 2;
    context.print_style.default_format_float.zero_removal = .NO;

    yal_command := ifx OS == .WINDOWS then "yal" else "./yal";

    builder : StringBuilder;

    _, commit_id := run_command("git", "rev-parse", "HEAD", capture_and_return_output=true);
    commit_id = trim(commit_id);
    Appendln(*builder, "Commit id: %", commit_id);

    _, yal_version := run_command(yal_command, "-version", capture_and_return_output=true);
    yal_version = trim(yal_version);
    Appendln(*builder, "Compiler version: %", yal_version);
    Append(*builder, "\n");

    timings : [Benchmark_Iterations]Basic.Apollo_Time;
    for filename : Files_To_Benchmark {
        failed := false;
        total_time : Basic.Apollo_Time;
        lines_processed := 0;
        for i : 0..Benchmark_Iterations - 1 {
            start := Basic.current_time_monotonic();
            result, stdout := run_command(yal_command, filename, capture_and_return_output=true);
            end := Basic.current_time_monotonic();

            timings[i] = end - start;
            total_time += timings[i];

            if result.type != .EXITED || result.exit_code != 0 {
                failed = true;
                LogError("Compilation failed for benchmark '%'", filename);
                break;
            }

            index := find_index_from_left(stdout, "(processed ");
            if index >= 0 {
                str := StringAdvance(stdout, index + "(processed ".count);
                lines_processed = Basic.string_to_int(str);
            }
        }

        if failed {
            Appendln(*builder, "%\tFAILED", filename);
        } else {
            QuickSort(timings, Basic.compare_apollo_times);

            avg := 1000 * Basic.to_float64_seconds(total_time / Benchmark_Iterations);
            median := ifx timings.count % 2 == 0
                then 1000 * 0.5 * (Basic.to_float64_seconds(timings[timings.count / 2 - 1] + timings[timings.count / 2]))
                else 1000 * Basic.to_float64_seconds(timings[timings.count / 2]);
            min := 1000 * Basic.to_float64_seconds(timings[0]);
            max := 1000 * Basic.to_float64_seconds(timings[timings.count - 1]);

            Appendln(*builder, "%\t%/%/%/%/% ms (lines processed/min/max/avg/median)", filename, lines_processed, min, max, avg, median);
        }
    }

    str := StringBuilderBuild(*builder);
    Print(str);

    make_directory_if_it_does_not_exist("Benchmarks");

    current_time := Basic.current_time_consensus();
    calendar := Basic.to_calendar(current_time, .UTC);
    filename := TPrint("Benchmarks/%.txt", ToLexicographicString(calendar));
    write_entire_file(filename, str);

    LogMessage("Outputted benchmark results to '%'", filename);
    CreateBenchmarkCSVCompilation();
}

g_console_logger : ConsoleLogger;

Build :: () {
    InitConsoleLogger(*g_console_logger);
    SetContextLogger(*g_console_logger, ConsoleLoggerProc);

    set_build_options_dc(.{do_output=false, write_added_strings=false, interactive_bytecode_debugger=get_build_options().interactive_bytecode_debugger});

    ws := compiler_create_workspace("Yal");
    options := get_build_options(ws);
    options.interactive_bytecode_debugger = get_build_options().interactive_bytecode_debugger;

    args := get_build_options().compile_time_command_line;

    intercept_flags : Intercept_Flags;

    success:, plugins_to_create:, args = parse_plugin_arguments(args);
    if !success {
        Basic.exit(1);
    }

    build_config := BuildConfig.Debug;
    execute_tests := false;
    verbose_tests := false;
    clean := false;
    benchmark := false;
    record_allocations := false;
    for args {
        if it == {
        case "debug";
            build_config = .Debug;
        case "optimized";
            build_config = .OptimizedDebug;
        case "release";
            build_config = .Release;
        case "tests";
            execute_tests = true;
        case "verbose_tests";
            verbose_tests = true;
        case "clean";
            clean = true;
        case "benchmark";
            benchmark = true;
        case "record_allocations";
            record_allocations = true;
        case;
            LogError("Unknown option '%'", it);
            Basic.exit(1);
        }
    }

    for Default_Plugins {
        ArrayPush(*plugins_to_create, .{name=it});
    }

    compiled_with_tracy := false;
    for plugins_to_create {
        if it.name == "Tracy" {
            compiled_with_tracy = true;
        }
    }

    plugins : [..]*Metaprogram_Plugin;
    if !init_plugins(plugins_to_create, *plugins, ws) {
        LogError("A plugin failed to initialize");
        Basic.exit(1);
    }

    if clean {
        CleanupTestsDirectory("Tests");
        CleanupTestsDirectory("Samples");

        return;
    }

    if benchmark {
        ExecuteBenchmarks();

        return;
    }

    options.temporary_storage_size = 1 * 1024 * 1024; // 1 MiB per temporary storage page
    options.Commonly_Propagated = get_build_options().Commonly_Propagated;
    options.import_path = get_build_options().import_path;
    options.output_type = .EXECUTABLE;
    options.output_executable_name = "yal";
    options.intermediate_path = "Source/.build";
    options.write_added_strings = true;
    options.stack_trace = true;
    options.text_output_flags = 0;
    // Increase stack size on Windows, otherwise stack overflows happen very easily
    #if OS == .WINDOWS {
        options.additional_linker_arguments = .["/STACK:8388608"]; // 8 MiB
    }
    SetBuildConfig(*options, build_config);

    set_build_options(options, ws);

    for plugins {
        if it.before_intercept {
            it.before_intercept(it, *intercept_flags);
        }
    }

    failed := false;
    compiler_begin_intercept(ws, intercept_flags);

    time := Basic.current_time_consensus();
    calendar_time := Basic.to_calendar(time, .UTC);
    version_string : string;
    if !compiled_with_tracy {
        version_string = TPrint("Full_Version_String :: \"% dev, built on % %\";", build_config, Basic.calendar_to_string(calendar_time), calendar_time.time_zone);
    } else {
        version_string = TPrint("Full_Version_String :: \"% dev with Tracy client, built on % %\";", build_config, Basic.calendar_to_string(calendar_time), calendar_time.time_zone);
    }

    add_build_string(version_string, ws);
    add_build_string(TPrint("Build_Config :: BuildConfig.%;", build_config), ws);
    add_build_string(TPrint("Record_Allocations :: %;", record_allocations), ws);
    add_build_file("Source/main.jai", ws);

    for plugins {
        if it.add_source {
            it.add_source(it);
        }
    }

    while true {
        msg := compiler_wait_for_message();

        for plugins {
            if it.message {
                it.message(it, msg);
            }
        }

        if msg.kind == .TYPECHECKED {
            tc := cast(*Message_Typechecked, msg);
            for tc.declarations {
                decl := it.expression;

                for note : decl.notes {
                    if note.text == "Preload" {
                        AddPreloadDeclaration(decl);
                    }
                }
            }
        }

        if msg.kind == .COMPLETE && msg.workspace == ws {
            failed = cast(*Message_Complete, msg).error_code != .NONE;

            break;
        }
    }

    compiler_end_intercept(ws);

    for plugins {
        if it.finish {
            it.finish(it);
        }
    }

    for plugins {
        if it.shutdown {
            it.shutdown(it);
        }
    }

    if !failed {
        GeneratePreloadFile();
    }

    if !failed && execute_tests {
        ExecuteTests(verbose_tests);
    }
}

#run Build();
