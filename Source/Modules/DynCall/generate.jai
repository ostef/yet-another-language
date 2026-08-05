#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";
#import "Bindings_Generator";

#if OS != .WINDOWS && OS != .LINUX && OS != .MACOS {
    #assert false "Only Windows, Linux and MacOS are supported for now.";
}

Source_Path :: "dyncall-1.4";

FlagsForSpecificDeclaration :: struct {
    name : string;
    flags : Declaration_Flags;
}

Global_Declarations_Flags :: FlagsForSpecificDeclaration.[
    .{"DC_BOOL", .OMIT_FROM_OUTPUT},
    .{"DC_POINTER", .OMIT_FROM_OUTPUT},
    .{"DC_TRUE", .OMIT_FROM_OUTPUT},
    .{"DC_FALSE", .OMIT_FROM_OUTPUT},
];

Defines :: string.[];

#run {
    #import "Compiler";

    set_build_options_dc(.{do_output = false});

    if !GenerateDynCallBindings() {
        compiler_set_workspace_status(.FAILED);
        return;
    }

    if !GenerateDynLoadBindings() {
        compiler_set_workspace_status(.FAILED);
        return;
    }
}

GenerateDynCallBindings :: () -> bool {
    #if OS == .WINDOWS {
        output_filename := "dyncall_windows.jai";
    } else #if OS == .LINUX {
        output_filename := "dyncall_linux.jai";
    } else #if OS == .MACOS {
        output_filename := "dyncall_macos.jai";
    }

    opts : Generate_Bindings_Options;

    #if OS == .WINDOWS {
        array_add(*opts.library_search_paths, "windows");
    } else #if OS == .LINUX {
        array_add(*opts.library_search_paths, "linux");
    } else #if OS == .MACOS {
        array_add(*opts.library_search_paths, "macos");
    }

    array_add(*opts.libraries, Library.{filename="dyncall_s"});
    array_add(*opts.include_paths, tprint("%/dyncall", Source_Path));

    array_add(*opts.source_files, tprint("%/dyncall/dyncall.h", Source_Path));
    array_add(*opts.source_files, tprint("%/dyncall/dyncall_aggregate.h", Source_Path));
    array_add(*opts.source_files, tprint("%/dyncall/dyncall_callf.h", Source_Path));
    array_add(*opts.source_files, tprint("%/dyncall/dyncall_callvm.h", Source_Path));
    // array_add(*opts.source_files, tprint("%/dyncall/dyncall_callvm_x64.h", Source_Path));
    array_add(*opts.source_files, tprint("%/dyncall/dyncall_config.h", Source_Path));
    array_add(*opts.source_files, tprint("%/dyncall/dyncall_macros.h", Source_Path));
    array_add(*opts.source_files, tprint("%/dyncall/dyncall_signature.h", Source_Path));
    array_add(*opts.source_files, tprint("%/dyncall/dyncall_types.h", Source_Path));
    array_add(*opts.source_files, tprint("%/dyncall/dyncall_utils.h", Source_Path));
    array_add(*opts.source_files, tprint("%/dyncall/dyncall_value.h", Source_Path));
    array_add(*opts.source_files, tprint("%/dyncall/dyncall_vector.h", Source_Path));
    array_add(*opts.source_files, tprint("%/dyncall/dyncall_version.h", Source_Path));

    array_add(*opts.libraries, Library.{filename="dyncallback_s"});
    array_add(*opts.include_paths, tprint("%/dyncallback", Source_Path));

    array_add(*opts.source_files, tprint("%/dyncallback/dyncall_alloc_wx.h", Source_Path));
    array_add(*opts.source_files, tprint("%/dyncallback/dyncall_args.h", Source_Path));
    // array_add(*opts.source_files, tprint("%/dyncallback/dyncall_args_x64.h", Source_Path));
    array_add(*opts.source_files, tprint("%/dyncallback/dyncall_callback.h", Source_Path));
    array_add(*opts.source_files, tprint("%/dyncallback/dyncall_thunk_x64.h", Source_Path));
    // array_add(*opts.source_files, tprint("%/dyncallback/dyncall_thunk.h", Source_Path));

    for Defines {
        array_add(*opts.extra_clang_arguments, tprint("-D%", it));
    }

    opts.auto_detect_enum_prefixes = false;
    opts.generate_compile_time_struct_checks = false;
    // opts.strip_flags |= .INLINED_FUNCTIONS;

    opts.visitor = HandleDeclaration;

    return generate_bindings(opts, output_filename);
}

GenerateDynLoadBindings :: () -> bool {
    #if OS == .WINDOWS {
        output_filename := "dynload_windows.jai";
    } else #if OS == .LINUX {
        output_filename := "dynload_linux.jai";
    } else #if OS == .MACOS {
        output_filename := "dynload_macos.jai";
    }

    opts : Generate_Bindings_Options;

    #if OS == .WINDOWS {
        array_add(*opts.library_search_paths, "windows");
    } else #if OS == .LINUX {
        array_add(*opts.library_search_paths, "linux");
    } else #if OS == .MACOS {
        array_add(*opts.library_search_paths, "macos");
    }

    array_add(*opts.libraries, Library.{filename="dynload_s"});
    array_add(*opts.include_paths, tprint("%/dynload", Source_Path));

    array_add(*opts.source_files, tprint("%/dynload/dynload.h", Source_Path));
    array_add(*opts.source_files, tprint("%/dynload/dynload_alloc.h", Source_Path));

    for Defines {
        array_add(*opts.extra_clang_arguments, tprint("-D%", it));
    }

    opts.auto_detect_enum_prefixes = false;
    opts.generate_compile_time_struct_checks = false;
    // opts.strip_flags |= .INLINED_FUNCTIONS;

    opts.visitor = HandleDeclaration;

    return generate_bindings(opts, output_filename);
}

HandleDeclaration :: (decl : *Declaration, parent_decl : *Declaration) -> Declaration_Visit_Result {
    if !parent_decl {
        for Global_Declarations_Flags {
            if decl.name == it.name {
                decl.decl_flags |= it.flags;

                print("% : %\n", decl.name, decl.decl_flags);

                if decl.decl_flags | .OMIT_FROM_OUTPUT {
                    return .STOP;
                }
            }
        }
    }

    return .RECURSE;
}
