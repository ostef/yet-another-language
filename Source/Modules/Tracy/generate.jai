#run {
    set_build_options_dc(.{do_output=false});

    build := false;

    args := get_build_options().compile_time_command_line;
    for args {
        if it == {
        case "build";
            build = true;
        }
    }

    if build && !BuildTracyClient() {
        compiler_set_workspace_status(.FAILED);
        return;
    }

    if !GenerateBindings() {
        compiler_set_workspace_status(.FAILED);
        return;
    }
}

Defines :: string.[
    "TRACY_ENABLE",
    "TRACY_EXPORTS",
    "TRACY_IMPORTS",
];

// Should we use the CMakeLists instead?
// To know what build options CMake uses:
// $> cd Source
// $> cmake -B .build -DCMAKE_EXPORT_COMPILE_COMANDS=on
// $> cat .build/compile_commands.json
BuildTracyClient :: () -> bool {
    extra_args : [..]string;

    for Defines {
        array_add(*extra_args, tprint("-D%", it));
    }

    output_name : string;
    #if OS == .WINDOWS {
        output_name = "Lib/Windows/TracyClient";
    } else #if OS == .LINUX {
        output_name = "Lib/Linux/TracyClient";
    } else #if OS == .MACOS {
        array_add(*extra_args, "-std=c++11", "-Wno-deprecated-declarations", "-mmacos-version-min=11.0");
        output_name = "Lib/MacOS/TracyClient";
    } else {
        #assert false "Unsupported platform";
    }

    cpp_main_path := join(#filepath, "/Source/public/TracyClient.cpp");
    make_directory_if_it_does_not_exist(path_strip_filename(output_name), recursive=true);

    if !build_cpp_dynamic_lib(output_name, cpp_main_path, extra=extra_args) {
        return false;
    }

    return true;
}

GenerateBindings :: () -> bool {
    #if OS == .WINDOWS {
        output_filename := "tracy_windows.jai";
    } else #if OS == .LINUX {
        output_filename := "tracy_linux.jai";
    } else #if OS == .MACOS {
        output_filename := "tracy_macos.jai";
    } else {
        #assert false "Unsupported platform";
    }

    opts : Generate_Bindings_Options;

    #if OS == .WINDOWS {
        array_add(*opts.library_search_paths, "Lib/Windows");
    } else #if OS == .LINUX {
        array_add(*opts.library_search_paths, "Lib/Linux");
    } else #if OS == .MACOS {
        array_add(*opts.library_search_paths, "Lib/MacOS");
    }

    array_add(*opts.libraries, .{filename="TracyClient"});
    array_add(*opts.source_files, "Source/public/tracy/TracyC.h");


    for Defines {
        array_add(*opts.extra_clang_arguments, tprint("-D%", it));
    }

    array_add(*opts.extra_clang_arguments, "-x", "c");

    array_add(*opts.strip_prefixes, "TracyC");
    array_add(*opts.strip_prefixes, "Tracy");
    array_add(*opts.strip_prefixes, "__tracy");
    array_add(*opts.strip_prefixes, "___tracy");

    opts.auto_detect_enum_prefixes = true;
    opts.generate_compile_time_struct_checks = false;
    opts.strip_flags |= .INLINED_FUNCTIONS;

    opts.visitor = (decl : *Declaration, parent_decl : *Declaration) -> Declaration_Visit_Result {
        if decl.name == "TracyCFrameMark" {
            decl.decl_flags |= .OMIT_FROM_OUTPUT;
            return .STOP;
        }

        return .RECURSE;
    }

    return generate_bindings(opts, output_filename);
}

#import "Basic";
#import "String";
#import "File";
#import "BuildCpp";
#import "Compiler";
#import "Bindings_Generator";
