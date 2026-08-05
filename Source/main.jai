BuildConfig :: enum {
    Debug;
    OptimizedDebug;
    Release;
}

Enable_Asserts :: Build_Config != .Release;
Enable_Debug_Print :: Build_Config != .Release;

#import "Common"()(Enable_Asserts=Enable_Asserts, Record_Allocations=Record_Allocations);
#import "Hash_Map";
#import "Hash_Set";

Basic :: #import "Basic"()(ENABLE_ASSERT=Enable_Asserts);
Math :: #import "Math";
File :: #import "File";
File_Utils :: #import "File_Utilities";
Process :: #import "Process";
String :: #import "String";
JaiC :: #import "Compiler";

#if !#exists(__Tracy) {
    Tracy :: #import "Tracy"(Import_Mode=.Client)(Enabled=false);
} else {
    Tracy :: __Tracy;
}

#load "error.jai";

#load "tokens.jai";
#load "ast.jai";
#load "parsing.jai";
#load "constant_eval.jai";
#load "scope.jai";
#load "dependency.jai";
#load "check_stmt.jai";
#load "check_expr.jai";
#load "types.jai";
#load "ir_codegen.jai";
#load "dotfile.jai";

#load "IR/ir.jai";
#load "Interpreter/interpreter.jai";

g_compiler_executable_filename : string;
g_compiler_root_directory : string;
g_initial_working_directory : string;

YalProgram :: struct {
    all_loaded_files : [..]*YalFile;
    newly_loaded_files : [..]*YalFile;
    module_search_directories : [..]string;
    imported_modules : [..]*YalModule;
    main_module : *YalModule;

    scope : *Scope;
    added_new_code : bool;
    modified_scopes : [..]*Scope;
    pending_compile_time_execution : [..]*AstNode;

    allocator_declaration : *AstDeclaration;
    context_declaration : *AstDeclaration;
    entry_point_declaration : *AstDeclaration;

    ir_builder : YalIRBuilder;

    Stats :: struct {
        num_expressions : int;
        num_declarations : int;
        num_struct_declarations : int;
        num_enum_declarations : int;
        num_variable_declarations : int;
        num_constant_declarations : int;
        num_function_declarations : int;
        num_statements : int;
    }

    parsing_stats : Stats;
    checking_stats : Stats;
    codegen_stats : Stats;
    total_lines_of_code : int;
    total_bytes_processed : int;
    num_scopes : int;
    num_dependency_nodes : int;
}

g_program : *YalProgram;

YalFile :: struct {
    using,except(name) lexer : YalLexer;
    using,only(program) scope : *Scope;

    add_statements_to_global_scope := true;
    source_node : *AstNode;

    statements : [..]*AstNode;
}

YalModule :: struct {
    name : string;
    filename : string;

    using,only(program) scope : *Scope;

    files : [..]*YalFile;
}

GetFilenameRelativeToNode :: (node : *AstNode, filename : string) -> string {
    result := filename;

    if node && !String.is_absolute_path(result) {
        node_file := GetFile(node.file_id);
        if node_file {
            result = String.path_join(String.path_strip_filename(node_file.filename), filename, separator=#char "/");
        }
    }

    result = File.get_absolute_path(result);
    String.path_overwrite_separators(result, #char "/");

    return result;
}

ImportModule :: (program : *YalProgram, name : string, import_file := false, node : *AstNode = null) -> *YalModule {
    if !name {
        if node {
            Error(node, "Failed to import module '%'", name);
        } else {
            Error("Failed to import module '%'", name);
        }

        return null;
    }

    for program.imported_modules {
        if it.name == name {
            return it;
        }
    }

    module_filename : string;
    if import_file {
        module_filename = GetFilenameRelativeToNode(node, name);
    } else {
        for < program.module_search_directories {
            filename := String.path_join(it, name, "module.yal", separator=#char "/");
            if File_Utils.file_exists(filename) {
                module_filename = filename;
                break;
            }
        }

        if !module_filename {
            if node {
                Error(node, "Could not find 'module.yal' file for module '%' in any of the module search directories", name);
            } else {
                Error("Could not find 'module.yal' file for module '%' in any of the module search directories", name);
            }

            Println("Here are the directories we searched in order:");
            for < program.module_search_directories {
                Println("  '%'", it);
            }

            return null;
        }
    }

    module := Alloc(YalModule);
    module.name = name;
    module.filename = module_filename;
    ScopeCreate(program, module);
    ArrayPush(*program.imported_modules, module);

    AddSourceFile(module, module_filename, node);

    return module;
}

FileId :: s16;

CreateProgram :: (main_filename : string) -> *YalProgram {
    program := Alloc(YalProgram);
    program.scope = ScopeCreate(null, .Global);
    program.scope.program = program;
    program.num_scopes += 1;
    ArrayPush(*program.module_search_directories, g_compiler_root_directory);

    program.ir_builder.file = Alloc(IRFile);
    EmitBuiltins(*program.ir_builder);

    AddSourceFile(program, "Source/preload.yal");

    added_code := SPrint(#string YAL
const Target_OS = OperatingSystem.%1;
YAL
, g_build_settings.target_os);
    AddSourceCode(program, "<compiler added code>", added_code);

    filename, ok := File.get_absolute_path(main_filename ,, logger=IgnoreLogger);
    if !ok {
        Error("Could not read file '%'", main_filename);
        return null;
    }

    String.path_overwrite_separators(filename, #char "/");

    ArrayPush(*program.module_search_directories, String.path_strip_filename(filename));

    program.main_module = ImportModule(program, filename, import_file=true);
    if !program.main_module {
        return null;
    }

    return program;
}

GetFile :: inline (file_id : FileId) -> *YalFile {
    if file_id < 0 || file_id >= g_program.all_loaded_files.count {
        return null;
    }

    return g_program.all_loaded_files[file_id];
}

AddSourceCode :: (program : *YalProgram, filename : string, text : string) -> *YalFile {
    DbgPrintln(.Parsing, "Adding source code '%'", filename);

    Assert(program.all_loaded_files.count < Math.S16_MAX, "Too many loaded files (max is %)", Math.S16_MAX);

    file := Alloc(YalFile);
    file.file_id = xx program.all_loaded_files.count;
    file.filename = filename;
    file.text = text;
    ScopeCreate(program, file);

    ArrayPush(*program.all_loaded_files, file);
    ArrayPush(*program.newly_loaded_files, file);

    program.added_new_code = true;

    return file;
}

AddSourceCode :: (module : *YalModule, filename : string, text : string) -> *YalFile {
    DbgPrintln(.Parsing, "Adding source code '%' to module '%'", filename, module.name);

    Assert(module != null, "Module is null");
    Assert(module.program.all_loaded_files.count < Math.S16_MAX, "Too many loaded files (max is %)", Math.S16_MAX);

    file := Alloc(YalFile);
    file.file_id = xx module.program.all_loaded_files.count;
    file.filename = filename;
    file.text = text;
    ScopeCreate(module, file);

    ArrayPush(*module.program.all_loaded_files, file);
    ArrayPush(*module.program.newly_loaded_files, file);

    module.program.added_new_code = true;

    return file;
}

AddSourceCode :: (scope : *Scope, source_node : *AstNode, text : string) -> *YalFile {
    DbgInfo(.Parsing, source_node, "Adding source code");

    Assert(scope.program.all_loaded_files.count < Math.S16_MAX, "Too many loaded files (max is %)", Math.S16_MAX);

    file := Alloc(YalFile);
    file.file_id = xx scope.program.all_loaded_files.count;
    file.filename = "<added source code>";
    file.text = text;
    file.scope = scope;
    file.add_statements_to_global_scope = false;
    file.source_node = source_node;

    ArrayPush(*scope.program.all_loaded_files, file);
    ArrayPush(*scope.program.newly_loaded_files, file);

    scope.program.added_new_code = true;

    return file;
}

AddSourceFile :: (program : *YalProgram, filename : string, node : *AstNode = null) -> *YalFile {
    absolute_filename := GetFilenameRelativeToNode(node, filename);

    contents, ok := File.read_entire_file(absolute_filename, zero_terminated = true, log_errors = false);
    if !ok {
        if node {
            Error(node, "Could not read file '%'", absolute_filename);
        } else {
            Error("Could not read file '%'", absolute_filename);
        }

        return null;
    }

    return AddSourceCode(program, absolute_filename, contents);
}

AddSourceFile :: (module : *YalModule, filename : string, node : *AstNode = null) -> *YalFile {
    absolute_filename := GetFilenameRelativeToNode(node, filename);

    contents, ok := File.read_entire_file(absolute_filename, zero_terminated = true, log_errors = false);
    if !ok {
        if node {
            Error(node, "Could not read file '%'", absolute_filename);
        } else {
            Error("Could not read file '%'", absolute_filename);
        }

        return null;
    }

    return AddSourceCode(module, absolute_filename, contents);
}

QueueCompileTimeExecution :: (program : *YalProgram, node : *AstNode) {
    ArrayPush(*program.pending_compile_time_execution, node);
}

OperatingSystem :: enum u8 {
    Freestanding;
    Linux;
    Windows;
    MacOS;
} @Preload

BuildSettings :: struct {
    #if OS == .WINDOWS {
        target_os := OperatingSystem.Windows;
    } else #if OS == .LINUX {
        target_os := OperatingSystem.Linux;
    } else #if OS == .MACOS {
        target_os := OperatingSystem.MacOS;
    } else {
        target_os := OperatingSystem.Freestanding;
    }

    output_filename : string;
    report_all_errors := false;
    max_errors := 20;
    max_reported_lines := 8;
    tab_size := 4;
    output_colors := true;
    quiet := false;
    interpreter := false;
    output_ir := false;
    dotfile := false;
    break_on_ir_validation_error := true;
    allow_no_entry_point := false;
    show_extended_stats := false;

    #if Enable_Debug_Print {
        debug_log : DebugLogChannel;
    } else {
        // Constant so the compiler can optimize out easily
        debug_log : DebugLogChannel : 0;
    }

    #if Build_Config != .Release {
        block_compiler_passes := false;
    } else {
        // Constant so the compiler can optimize out easily
        block_compiler_passes :: false;
    }
}

g_build_settings : BuildSettings;

g_heap_allocator : Allocator;
g_stdout_has_colors, g_stderr_has_colors : bool;

Append :: StringBuilderAppend;
Appendln :: StringBuilderAppendLine;

#if OS == .WINDOWS {

PlatformInit :: () {
    Kernel32 :: #system_library "Kernel32";
    GetStdHandle :: (nStdHandle : s32) -> *void #foreign Kernel32;
    GetConsoleMode :: (hConsoleHandle : *void, lpMode : *u32) -> s32 #foreign Kernel32;
    SetConsoleMode :: (hConsoleHandle : *void, dwMode : u32) -> s32 #foreign Kernel32;
    GetModuleFileNameW :: (hModule : *void, lpFilename : *u16, nSize : u32) -> u32 #foreign Kernel32;

    std_out := GetStdHandle(-11);
    std_err := GetStdHandle(-12);

    mode : u32;
    if GetConsoleMode(std_out, *mode) {
        SetConsoleMode(std_out, mode | 0x04);
    }

    if mode & 0x04 {
        g_stdout_has_colors = true;
    }

    mode = 0;
    if GetConsoleMode(std_err, *mode) {
        SetConsoleMode(std_err, mode | 0x04);
    }

    if mode & 0x04 {
        g_stderr_has_colors = true;
    }

    exe_path : [4096]u16 = ---;
    if !GetModuleFileNameW(null, exe_path.data, exe_path.count) {
        Error("Could not get the filename of the currently running executable");
        Basic.exit(1);
    }

    WinUtf8 :: #import "Windows_Utf8";

    g_compiler_executable_filename=, success := WinUtf8.wide_to_utf8(exe_path.data);
    if !success {
        Error("Could not get the filename of the currently running executable");
        Basic.exit(1);
    }

    g_compiler_root_directory = String.path_strip_filename(g_compiler_executable_filename);
    g_initial_working_directory = StringClone(Basic.get_working_directory());
    String.path_overwrite_separators(g_initial_working_directory, #char "/");
}

} else {

PlatformInit :: () {
    libc :: #system_library "libc";
    isatty :: (fd : s32) -> s32 #foreign libc;

    g_stdout_has_colors = cast(bool, isatty(1));
    g_stderr_has_colors = cast(bool, isatty(2));

    POSIX :: #import "POSIX";

    exe_path : [4096]u8 = ---;
    exe_length := POSIX.readlink("/proc/self/exe", exe_path.data, exe_path.count);
    if exe_length < 0 {
        Error("Could not get the filename of the currently running executable");
        Basic.exit(1);
    }

    exe_filename := string.{count=exe_length, data=exe_path.data};
    g_compiler_executable_filename = StringClone(exe_filename);

    g_compiler_root_directory = String.path_strip_filename(g_compiler_executable_filename);
    g_initial_working_directory = StringClone(Basic.get_working_directory());
    String.path_overwrite_separators(g_initial_working_directory, #char "/");
}

}

PrintUsage :: () {
    SetOutputColor(.Info);
    write_string("Usage: ", to_standard_error=true);
    SetOutputColor(.None);

    write_string("yal [options*] filename\n", to_standard_error=true);
    write_string("Valid options are:\n", to_standard_error=true);
    write_string("  -version                print version information\n", to_standard_error=true);
    write_string("  -o {filename}           set output filename\n", to_standard_error=true);
    write_string("  -module_dir {path}      add a directory to the module search list\n", to_standard_error=true);
    write_string("  -quiet                  do not print timing information\n", to_standard_error=true);
    write_string("  -report_all_errors      continue typechecking even when there were errors\n", to_standard_error=true);
    write_string("  -no_colors              disable ANSI terminal colors\n", to_standard_error=true);
    write_string("  -force_colors           output ANSI terminal colors even if running outside a terminal\n", to_standard_error=true);
    write_string("  -output_ir              output the generated IR to a file\n", to_standard_error=true);
    write_string("  -interpreter            interpret the code instead of generating an executable\n", to_standard_error=true);

    #if Enable_Debug_Print {
        write_string("  -debug_log {channel}    enable debug logging. Channel can be 'parsing', 'scopes', 'deps', 'check', 'templates', 'codegen', 'interp' or 'all'\n", to_standard_error=true);
    }

    #if Build_Config != .Release {
        write_string("  -block_compiler_passes  wait until the user inputs something before continuing compilation after each pass\n", to_standard_error=true);
    }

    write_string("  -allow_no_entry_point   if no entry point is found, do not report an error\n", to_standard_error=true);
    write_string("  -show_extended_stats    print extended compilation statistics\n", to_standard_error=true);
    write_string("  -dotfile                generate dotfiles and dependency graph images for each compile passes\n", to_standard_error=true);
    write_string("  -no_profile             if the compiler was built with the Tracy client, use this options to disable profiling\n", to_standard_error=true);
}

ExitIfError :: () {
    if g_error_counter > 0 {
        SetOutputColor(.Error);
        write_string("There were errors, exiting...\n", to_standard_error=true);
        SetOutputColor(.None);

        Basic.exit(1);
    }
}

AlignForward :: inline (x : s64, align : s64) -> s64 {
    Assert(align > 0);

    return ((x + align - 1) / align) * align;
}

AlignForward :: inline (x : u64, align : u64) -> u64 {
    Assert(align > 0);

    return ((x + align - 1) / align) * align;
}

WaitForInput :: () {
    #if OS == .LINUX {
        #import "POSIX";

        ptr : *u8;
        n : u64;
        getline(*ptr, *n, stdin);
    }
}

main :: () {
    g_heap_allocator = context.allocator;
    #if Record_Allocations {
        InitAllocationRecording(g_heap_allocator);
    }

    context.allocator = Temp;
    context.assertion_failed = AssertionFailed;
    context.print_style.struct_printer = (builder : *StringBuilder, any : Any, data : *void) -> bool {
        if any.type == type_info(S128) {
            AppendS128(builder, cast(*S128, any.value_pointer).*);
            return true;
        } else if any.type == type_info(ConstantValue) {
            value := cast(*ConstantValue, any.value_pointer);
            if #complete value.kind == {
            case .Invalid; Append(builder, "<invalid>");
            case .Integer; Append(builder, "<integer, %>", value.int_value);
            case .Boolean; Append(builder, "<bool, %>", value.bool_value);
            case .Float; Append(builder, "<float, %>", value.float_value);
            case .String; StringBuilderAppendStringLiteral(builder, value.string_value);
            case .Pointer; Append(builder, "<ptr, %>", FormatIntHex(value.pointer_value));
            case .Function; Append(builder, "<function, %>", GetFirstLine(value.function_node));
            case .FunctionOverloadSet; Append(builder, "<function overload set, %>", GetFirstLine(value.overload_set.node));
            case .TypeId; Append(builder, "<type, %>", ToString(value.type_value));
            case .Struct; Append(builder, "<struct value>");
            case .Module; Append(builder, "<module '%'>", value.module.name);
            case .TemplateParam; Append(builder, "<template param>");
            }

            return true;
        } else if any.type == type_info(IRType) {
            value := cast(*IRType, any.value_pointer);
            AppendType(builder, value);

            return true;
        }

        return false;
    }

    PlatformInit();

    filename : string;

    args := Basic.get_command_line_arguments();

    module_dirs : [..]string;
    no_profile := false;
    arg_error := false;
    output_version := false;
    arg_index := 1;
    while arg_index < args.count {
        it := args[arg_index];
        arg_index += 1;

        if it[0] != #char "-" {
            if filename {
                Error("more than one file was provided");
                arg_error = true;
            }

            filename = it;
        } else if it == {
        case "-version";
            output_version = true;
        case "-o";
            if arg_index == args.count {
                Error("Expected filename argument to -o option");
                arg_error = true;
            } else {
                g_build_settings.output_filename = args[arg_index];
                arg_index += 1;
            }
        case "-module_dir";
            if arg_index == args.count {
                Error("Expected filename argument to -o option");
                arg_error = true;
            } else {
                ArrayPush(*module_dirs, args[arg_index]);
                arg_index += 1;
            }
        case "-report_all_errors";
            g_build_settings.report_all_errors = true;
        case "-quiet";
            g_build_settings.quiet = true;
        case "-no_colors";
            g_build_settings.output_colors = false;
        case "-force_colors";
            g_build_settings.output_colors = true;
            g_stdout_has_colors = true;
            g_stderr_has_colors = true;
        case "-output_ir";
            g_build_settings.output_ir = true;
        case "-interpreter";
            g_build_settings.interpreter = true;
        case "-dotfile";
            g_build_settings.dotfile = true;
        case "-allow_no_entry_point";
            g_build_settings.allow_no_entry_point = true;
        case "-show_extended_stats";
            g_build_settings.show_extended_stats = true;
        case "-no_profile";
            no_profile = true;
        case "-debug_log";
            #if Enable_Debug_Print {
                if arg_index == args.count {
                    Error("Expected channel argument to -debug_log option");
                    arg_error = true;
                } else {
                    channel := args[arg_index];
                    arg_index += 1;

                    if channel == {
                    case "parsing";   g_build_settings.debug_log |= .Parsing;
                    case "scopes";    g_build_settings.debug_log |= .Scopes;
                    case "deps";      g_build_settings.debug_log |= .Dependencies;
                    case "check";     g_build_settings.debug_log |= .Checking;
                    case "templates"; g_build_settings.debug_log |= .Templates;
                    case "codegen";   g_build_settings.debug_log |= .Codegen;
                    case "interp";    g_build_settings.debug_log |= .Interpreter;
                    case "all";       g_build_settings.debug_log = .All;
                    case;
                        Error("Invalid debug log channel '%'", channel);
                        arg_error = true;
                    }
                }
            } else {
                Error("%: debug printing is disabled in release mode", it);
            }
        case "-block_compiler_passes";
            #if Build_Config != .Release {
                g_build_settings.block_compiler_passes = true;
            } else {
                Error("%: disabled in release mode", it);
            }
        case;
            Error("%: unknown option", it);
            arg_error = true;
        }
    }

    if g_stdout_has_colors && g_stderr_has_colors && g_build_settings.output_colors {
        context.print_squiggles = false;
    }

    if arg_error {
        PrintUsage();
        Basic.exit(1);
    }

    if output_version {
        Println("%", Full_Version_String);
        Basic.exit(0);
    }

    if !filename {
        Error("No file provided");
        PrintUsage();
        Basic.exit(1);
    }

    if !no_profile {
        Tracy.EnableProfiling();
        if Tracy.IsProfiling() {
            Println("Profiling is enabled");
        }
    }

    InitBuiltinTypes();

    file_error := false;
    g_program = CreateProgram(filename);
    if !g_program {
        Basic.exit(1);
    }

    for module_dirs {
        filename, ok := File.get_absolute_path(it);
        String.path_overwrite_separators(filename);

        ArrayPush(*g_program.module_search_directories, filename);
    }

    parsing_time_apollo : Basic.Apollo_Time;
    checking_time_apollo : Basic.Apollo_Time;
    codegen_time_apollo : Basic.Apollo_Time;
    interpreter_time_apollo : Basic.Apollo_Time;

    compilation_phase := 1;
    compilation_is_blocked_or_done := !g_program.added_new_code;
    checking_graph_flattening_result : FlattenDependencyGraphResult;
    resolved_all_identifiers := true;
    resolved_new_identifiers := false;
    while !compilation_is_blocked_or_done {
        defer compilation_phase += 1;

        DbgPrintln(.All, "~~~~~~~~~ Compilation Phase % ~~~~~~~~~", compilation_phase);
        Tracy.EmitMessage("Compilation Phase %", compilation_phase);

        parsing_start := Basic.current_time_monotonic();

        current_file := 0;
        DbgPrintln(.Parsing, "% new file(s) to parse", g_program.newly_loaded_files.count);
        while current_file < g_program.newly_loaded_files.count {
            file := g_program.newly_loaded_files[current_file];
            DbgPrintln(.Parsing, "  %", ShortenFilename(file.filename));
            ParseFile(file);

            g_program.total_lines_of_code += file.line;
            g_program.total_bytes_processed += file.byte_index;

            current_file += 1;
        }

        ExitIfError();
        DbgPrintln(.Parsing, "== Parsing done");

        parsing_end := Basic.current_time_monotonic();
        parsing_time_apollo += parsing_end - parsing_start;

        ArrayClear(*g_program.newly_loaded_files);

        checking_start := Basic.current_time_monotonic();

        CreateScopesAndCollectStatementsAndSymbolsForNewlyAddedCode(g_program);
        ExitIfError();

        DbgPrintln(.Scopes, "== Symbol and scope collection done");

        CreateDependencyGraphForNewlyAddedNodes(g_program);
        ExitIfError();

        DbgPrintln(.Dependencies, "== Dependency graph done");

        resolved_all_identifiers, resolved_new_identifiers = ResolveIdentifiersInScopeAndChildren(g_program.scope);
        ExitIfError();

        DbgPrintln(.Dependencies, "resolved_all_identifiers=%, resolved_new_identifiers=%", resolved_all_identifiers, resolved_new_identifiers);

        if !g_program.added_new_code && checking_graph_flattening_result == .BlockedByUnresolvedIdentifiers && !resolved_new_identifiers {
            compilation_is_blocked_or_done = true;
        }

        {
            flattened_graph : FlattenedDependencyGraph;
            // Flattening uses up a lot of memory and is only used once, so we want to free it at the end
            SetAllocators(*flattened_graph, g_heap_allocator);
            defer FreeGraph(*flattened_graph);

            checking_graph_flattening_result = FlattenDependencyGraphForChecking(*flattened_graph, g_program.scope);

            DbgPrintln(.Checking, "Pass %, nodes to check in order, %:", compilation_phase, checking_graph_flattening_result);
            DbgPrintDependencyNodes(.Checking, flattened_graph.nodes);

            checking_end := Basic.current_time_monotonic();
            checking_time_apollo += checking_end - checking_start;

            if g_build_settings.dotfile {
                dotfile_name := TPrint("%.phase%", String.path_strip_extension(filename), compilation_phase);
                GenerateGraphImage(dotfile_name, g_program.scope);
            }

            checking_start = Basic.current_time_monotonic();

            // Reset this before the checking phase, because this is where we potentially
            // add new code (conditional compilation, #includes, etc)
            ClearAddedCode(g_program);

            {
                Tracy.ZoneScoped("Typecheck");

                for flattened_graph.nodes {
                    CheckDependencyNode(it);
                }
            }

            ExitIfError();

            DbgPrintln(.Checking, "== Checking done");

            checking_end = Basic.current_time_monotonic();
            checking_time_apollo += checking_end - checking_start;
        }

        codegen_start := Basic.current_time_monotonic();

        DbgPrintln(.All, "% nodes pending for compile time execution", g_program.pending_compile_time_execution.count);

        if g_program.pending_compile_time_execution.count > 0 {
            DbgPrintln(.Codegen, "== Compile time execution - begin codegen");

            for g_program.pending_compile_time_execution {
                if it.kind != .Run {
                    continue;
                }

                EmitIRForDependencyGraph(*g_program.ir_builder, it.dependency_node);
            }

            bc_file := CompileIRToBytecode(g_program.ir_builder.file);

            DbgPrintln(.Codegen, "== Compile time execution - codegen done");

            codegen_end := Basic.current_time_monotonic();
            codegen_time_apollo += codegen_end - codegen_start;

            interpreter_start := Basic.current_time_monotonic();
            DbgPrintln(.Interpreter, "== Compile time execution - interpret");

            interp : BytecodeInterpreter;
            LoadBytecodeFile(*interp, "<compile time execution>", *bc_file);

            for g_program.pending_compile_time_execution {
                if it.kind != .Run {
                    continue;
                }

                func := cast(*AstRun, it).ir_function;
                if !func {
                    continue;
                }

                it.value = RunFunction(*interp, func.name, it.type);
                it.dependency_node.check_status = .Executed;
                DbgInfo(.Interpreter, it, "Compile time execution returned %", it.value);

                compilation_is_blocked_or_done = false;

                remove it;
            }

            interpreter_end := Basic.current_time_monotonic();
            interpreter_time_apollo += interpreter_end - interpreter_start;
        }

        if g_program.added_new_code {
            compilation_is_blocked_or_done = false;
        } else if checking_graph_flattening_result == 0 && g_program.pending_compile_time_execution.count == 0 {
            compilation_is_blocked_or_done = true;
        }

        if g_build_settings.block_compiler_passes {
            Print("Press return to continue compilation...");
            WaitForInput();
            Print("\n");
        }
    }

    DbgPrintln(.All, "~~~~~~~~~ End of compilation loop, performed % phases ~~~~~~~~~", compilation_phase - 1);

    parsing_time := Basic.to_float64_seconds(parsing_time_apollo);
    checking_time := Basic.to_float64_seconds(checking_time_apollo);

    if !resolved_all_identifiers {
        ReportUnresolvedIdentifiersInScopeAndChildren(g_program.scope);
        ExitIfError();
    }

    if !g_build_settings.allow_no_entry_point && !g_program.entry_point_declaration {
        Error("No entry point declaration was found");
        ExitIfError();
    }

    interpreter_exit_code : s32;

    codegen_time := Basic.to_float64_seconds(codegen_time_apollo);
    backend_time : float64;
    interpreter_time := Basic.to_float64_seconds(interpreter_time_apollo);

    codegen_start := Basic.current_time_monotonic();

    DbgPrintln(.Codegen, "~~~~~~~~~ Begin program codegen ~~~~~~~~~");
    Tracy.EmitMessage("Begin program codegen");

    if g_program.entry_point_declaration {
        ok := EmitIRForDependencyGraph(*g_program.ir_builder, g_program.entry_point_declaration.dependency_node);
        Assert(ok, "Could not flatten the full dependency graph for emitting the entry point");
    }

    codegen_end := Basic.current_time_monotonic();
    codegen_time += Basic.to_float64_seconds(codegen_end - codegen_start);

    if g_build_settings.output_ir {
        ir_string_builder : StringBuilder;
        AppendFile(*ir_string_builder, g_program.ir_builder.file);

        ir_filename := SPrint("%.yair", String.path_strip_extension(filename));
        File.write_entire_file(ir_filename, *ir_string_builder);
    }

    ExitIfError();

    if g_build_settings.show_extended_stats {
        PrintExtendedStats(g_program);
    }

    if !g_build_settings.quiet {
        PrintCompilationStatistics(g_program.total_lines_of_code, g_program.total_bytes_processed, parsing_time, checking_time, codegen_time, interpreter_time, backend_time);
    }

    if g_build_settings.interpreter {
        bc_file := CompileIRToBytecode(g_program.ir_builder.file);

        if g_program.entry_point_declaration {
            Assert(g_program.entry_point_declaration.expr && g_program.entry_point_declaration.expr.kind == .Function);

            interp : BytecodeInterpreter;
            entry_point := cast(*AstFunction, g_program.entry_point_declaration.expr).ir_function;
            Assert(entry_point != null, "Entry point IR function is null");

            LoadBytecodeFile(*interp, filename, *bc_file);
            entry_point_result := RunFunction(*interp, entry_point.name, g_type_s32);
            interpreter_exit_code = cast(s32, entry_point_result.int_value.low);
        } else {
            Error("Cannot run the interpreter because no entry point is defined");
        }
    }

    if g_error_counter > 0 {
        Basic.exit(1);
    } else if g_build_settings.interpreter {
        Basic.exit(interpreter_exit_code);
    }
}

PrintExtendedStats :: (program : *YalProgram) {
    PrintStats :: (using stats : YalProgram.Stats) {
        Println("  Num expressions:  %", num_expressions);
        Println("  Num declarations: % (% structs, % enums, % variables, % constants, % functions)", num_declarations, num_struct_declarations, num_enum_declarations, num_variable_declarations, num_constant_declarations, num_function_declarations);
        Println("  Num statements:   %", num_statements);
    }

    Println("Num lines of code: %", program.total_lines_of_code);
    Println("Num bytes processed: %", program.total_bytes_processed);
    Println("Num files: %", program.all_loaded_files.count);
    Println("Num scopes: %", program.num_scopes);
    Println("Num dependency nodes: %", program.num_dependency_nodes);
    Println("Parsing:");
    PrintStats(program.parsing_stats);
    Println("Checking:");
    PrintStats(program.checking_stats);
    Println("Codegen:");
    PrintStats(program.codegen_stats);
}

PrintCompilationStatistics :: (
    total_lines_of_code : int,
    total_bytes_processed : int,
    parsing_time : float64,
    checking_time : float64,
    codegen_time : float64,
    interpreter_time : float64,
    backend_time : float64
) {
    ChooseTimeUnit :: (value : float64) -> multiplier : float64, unit : string {
        if value < 1 / (1000.0 * 1000.0) {
            return 1000 * 1000 * 1000, "ns";
        }
        if value < 1 / 1000.0 {
            return 1000 * 1000, "μs";
        }
        if value < 1 {
            return 1000, "ms";
        }

        return 1, " s";
    }

    ChooseMemoryUnit :: (value : float64) -> multiplier : float64, unit : string {
        if value >= 1000 * 1000 * 1000 {
            return 1.0 / (1000 * 1000 * 1000), "GB";
        }
        if value >= 1000 * 1000 {
            return 1.0 / (1000 * 1000), "MB";
        }
        if value >= 1000 {
            return 1.0 / 1000, "KB";
        }

        return 1, " B";
    }

    // We don't sample the total time so the percentages add up to 1
    total_time_sec := parsing_time + checking_time + codegen_time + interpreter_time + backend_time;
    total_time := total_time_sec;
    parsing_time_percent := cast(float, ifx total_time < 0.00001 then 0.0 else parsing_time / total_time) * 100;
    checking_time_percent := cast(float, ifx total_time < 0.00001 then 0.0 else checking_time / total_time) * 100;
    codegen_time_percent := cast(float, ifx total_time < 0.00001 then 0.0 else codegen_time / total_time) * 100;
    interpreter_time_percent := cast(float, ifx total_time < 0.00001 then 0.0 else interpreter_time / total_time) * 100;
    backend_time_percent := cast(float, ifx total_time < 0.00001 then 0.0 else backend_time / total_time) * 100;

    time_unit_mult, time_unit := ChooseTimeUnit(total_time);
    parsing_time *= time_unit_mult;
    checking_time *= time_unit_mult;
    codegen_time *= time_unit_mult;
    interpreter_time *= time_unit_mult;
    backend_time *= time_unit_mult;
    total_time *= time_unit_mult;

    max_leading_digits := DecimalLength(cast(u64, total_time));

    bytes_processed_mult, bytes_processed_unit := ChooseMemoryUnit(xx total_bytes_processed);
    bytes_processed := total_bytes_processed * bytes_processed_mult;
    Println("\nTiming information (processed % lines of code, % %):", total_lines_of_code, FormatFloat.{value=bytes_processed, trailing_width=2, zero_removal=.NO}, bytes_processed_unit);
    time_fmt := FormatFloat.{
        value=parsing_time,
        width=max_leading_digits + 3,
        trailing_width=2,
        zero_removal=.NO
    };
    time_percent_fmt := FormatInt.{
        value=cast(int, Round(parsing_time_percent)),
        minimum_digits=4,
        padding=#char " "
    };

    Println("  Parsing:      % %, %\% of total time", time_fmt, time_unit, time_percent_fmt);

    time_fmt.value = checking_time;
    time_percent_fmt.value = cast(int, Round(checking_time_percent));
    Println("  Checking:     % %, %\% of total time", time_fmt, time_unit, time_percent_fmt);

    time_fmt.value = codegen_time;
    time_percent_fmt.value = cast(int, Round(codegen_time_percent));
    Println("  Codegen:      % %, %\% of total time", time_fmt, time_unit, time_percent_fmt);

    time_fmt.value = interpreter_time;
    time_percent_fmt.value = cast(int, Round(interpreter_time_percent));
    Println("  Execution:    % %, %\% of total time", time_fmt, time_unit, time_percent_fmt);

    time_fmt.value = backend_time;
    time_percent_fmt.value = cast(int, Round(backend_time_percent));
    Println("  Backend:      % %, %\% of total time", time_fmt, time_unit, time_percent_fmt);

    Print("\n");

    time_fmt.value = total_time;
    Print("    Total:      % %, % LOC/s", time_fmt, time_unit, cast(int, total_lines_of_code / total_time_sec));

    bytes_per_sec := total_bytes_processed / total_time_sec;
    bytes_per_sec_mult, bytes_per_sec_unit := ChooseMemoryUnit(bytes_per_sec);
    Println(", % %/s", FormatFloat.{value=bytes_per_sec * bytes_per_sec_mult, trailing_width=2, zero_removal=.NO}, bytes_per_sec_unit);

    SizeFormat :: (size : int) -> string {
        if size < 1000 {
            return SPrint("% bytes", size);
        } else if size < 1000_000 {
            return SPrint("% KB", size / 1000);
        } else if size < 1000_000_000 {
            return SPrint("% MB", size / 1000_000);
        } else {
            return SPrint("% GB", size / 1000_000_000);
        }
    }

    memory_usage := context.temporary_storage.total_bytes_occupied;
    Println("Total permanent memory used by the compiler: %", SizeFormat(memory_usage));

    #if Record_Allocations {
        SetRecordingAllocations(false);

        allocs := GetRecordedAllocations();
        QuickSort(allocs, (a, b) => (b.count * b.type.runtime_size) - (a.count * a.type.runtime_size));

        token_allocs : [..]RecordedAllocation;
        ast_allocs : [..]RecordedAllocation;
        scopes_allocs : [..]RecordedAllocation;
        dependencies_allocs : [..]RecordedAllocation;
        types_allocs : [..]RecordedAllocation;
        ir_allocs : [..]RecordedAllocation;
        other_allocs : [..]RecordedAllocation;

        PrintAllocs :: (allocs : []RecordedAllocation) {
            for * allocs {
                size := it.count * it.type.runtime_size;
                Println("    Type %: %, % allocations", cast(*Type, *it.type).*, SizeFormat(size), it.count);
            }
            Print("\n");
        }

        total, total_count := 0;
        total_tokens, total_tokens_count := 0;
        total_ast, total_ast_count := 0;
        total_scopes, total_scopes_count := 0;
        total_dependencies, total_dependencies_count := 0;
        total_types, total_types_count := 0;
        total_ir, total_ir_count := 0;
        total_other, total_other_count := 0;
        for * allocs {
            size := it.count * it.type.runtime_size;

            total += size;
            total_count += it.count;

            if TypeIsAstNode(it.type) || it.type.type == .POINTER && TypeIsAstNode(cast(*Type_Info_Pointer, it.type).pointer_to) {
                total_ast += size;
                total_ast_count += it.count;
                ArrayPush(*ast_allocs, it);
            } else if TypeIsYalType(it.type) || it.type.type == .POINTER && TypeIsYalType(cast(*Type_Info_Pointer, it.type).pointer_to)
            || it.type == type_info(YalTypeStructMember) || it.type == type_info(YalTypeEnumMember)
            || it.type == type_info(HashSetEntry(*YalTypeFunction))
            || it.type == type_info(HashSetEntry(*YalTypeFunctionOverloadSet))
            || it.type == type_info(HashSetEntry(*YalTypeArray))
            || it.type == type_info(HashSetEntry(*YalTypePointer)) {
                total_types += size;
                total_types_count += it.count;
                ArrayPush(*types_allocs, it);
            } else if it.type == type_info(Token) {
                total_tokens += size;
                total_tokens_count += it.count;
                ArrayPush(*token_allocs, it);
            } else if it.type == type_info(Scope) || it.type == type_info(*Scope)
            || it.type == type_info(Symbol)
            || it.type == type_info(HashMapEntry(string, *Symbol)) {
                total_scopes += size;
                total_scopes_count += it.count;
                ArrayPush(*scopes_allocs, it);
            } else if it.type == type_info(Dependency)
            || it.type == type_info(DependencyNode)
            || it.type == type_info(*DependencyNode)
            || it.type == type_info(UnresolvedIdentifier)
            || it.type == type_info(DependencyNode.SubexpressionCommand)
            || it.type == type_info(HashSetEntry(FlattenedDependencyGraph.VisitedNode)) {
                total_dependencies += size;
                total_dependencies_count += it.count;
                ArrayPush(*dependencies_allocs, it);
            } else if IsIRRelatedType(it.type) {
                total_ir += size;
                total_ir_count += it.count;
                ArrayPush(*ir_allocs, it);
            } else {
                total_other += size;
                total_other_count += it.count;
                ArrayPush(*other_allocs, it);
            }
        }

        Println("\nRecorded memory usage:");
        Println("  Tokens: %, % allocations", SizeFormat(total_tokens), total_tokens_count);
        PrintAllocs(token_allocs);
        Println("  AST: %, % allocations", SizeFormat(total_ast), total_ast_count);
        PrintAllocs(ast_allocs);
        Println("  Scopes: %, % allocations", SizeFormat(total_scopes), total_scopes_count);
        PrintAllocs(scopes_allocs);
        Println("  Dependencies: %, % allocations", SizeFormat(total_dependencies), total_dependencies_count);
        PrintAllocs(dependencies_allocs);
        Println("  Types: %, % allocations", SizeFormat(total_types), total_types_count);
        PrintAllocs(types_allocs);
        Println("  IR: %, % allocations", SizeFormat(total_ir), total_ir_count);
        PrintAllocs(ir_allocs);
        Println("  Others: %, % allocations", SizeFormat(total_other), total_other_count);
        PrintAllocs(other_allocs);
        Println("  All: %, % allocations", SizeFormat(total), total_count);

        Println("\n% per million of lines of code", SizeFormat(cast(int, 1_000_000 * (memory_usage / cast(float, total_lines_of_code)))));
    }
}
