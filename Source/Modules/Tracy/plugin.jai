get_plugin :: () -> *Metaprogram_Plugin {
    p := New(TracyPlugin);

    p.init              = Initialize;
    p.finish            = Finish;
    p.shutdown          = Shutdown;
    p.before_intercept  = BeforeIntercept;
    p.add_source        = AddSource;
    p.message           = HandleMessage;
    p.log_help          = LogHelp;

    p.internal_prepend_zone_node = compiler_get_nodes(Prepend_Zone_Code);

    return p;
}

BeforeIntercept :: (p : *Metaprogram_Plugin, flags : *Intercept_Flags) {
    options := get_build_options(p.workspace);

    import_path: [..] string;
    array_add(*import_path, ..options.import_path);
    array_add(*import_path, tprint("%/..", path_strip_filename(#file)));

    options.import_path = import_path;

    set_build_options(options, p.workspace);
}

AddSource :: (p : *Metaprogram_Plugin) {
    plugin := cast(*TracyPlugin, p);
    assert(plugin.workspace >= 0);

    add_build_string(To_Insert, plugin.workspace);
}

Initialize :: (p : *Metaprogram_Plugin, options : [] string) -> bool {
    plugin := cast(*TracyPlugin, p);

    cursor := 0;
    while cursor < options.count {
        if options[cursor] == {
        case "-min_size";
            cursor += 1;
            if cursor == options.count {
                log_error("Tracy: expected an integer after -min_size option");
                return false;
            }

            str := options[cursor];
            cursor += 1;

            plugin.min_size = string_to_int(str);

        case "-no_modules";
            plugin.instrument_modules = false;
            cursor += 1;

        case;
            log_error("Tracy: unknown option '%'", options[cursor]);
            return false;
        }
    }

    return true;
}

LogHelp :: (p : *Metaprogram_Plugin) {
    log(#string Help
-min_size           Minimum number of expressions for a function to be auto-instrumented
-no_modules         Do not instrument modules.
Help);
}

HandleMessage :: (p : *Metaprogram_Plugin, message : *Message) {
    plugin := cast(*TracyPlugin, p);
    if message.kind != .TYPECHECKED {
        return;
    }

    m := cast(*Message_Typechecked, message);

    for * tc : m.procedure_bodies {
        body := tc.expression;

        if body.body_flags & .ALREADY_MODIFIED {
            continue;
        }

        h := body.header;
        assert(h != null);

        allow_flags : type_of(h.procedure_flags);
        allow_flags |= .DEBUG_DUMP | .SYMMETRIC | .SYNTACTICALLY_MARKED_AS_INLINE_NO;
        allow_flags |= .POLYMORPHIC;
        if h.procedure_flags & ~allow_flags {
            continue;
        }

        file := body.enclosing_load;

        if file && file.enclosing_import {
            import := file.enclosing_import;

            if import.module_type == {
                case .PRELOAD;
                    continue;
                case .RUNTIME_SUPPORT;
                    continue;

                case .MAIN_PROGRAM;    // Always OK
                case;
                    if !plugin.instrument_modules {
                        continue;
                    }

                    // Don't profile stuff that is in Tracy itself:
                    // @Robustness: Hardcoded module name for now.
                    if import.module_name == "Tracy" {
                        continue;
                    }
            }
        }

        if tc.subexpressions.count < plugin.min_size {
            continue;
        }

        if plugin.should_instrument != null && !plugin.should_instrument(body) {
            continue;
        }

        for h.notes {
            if it.text == "NoProfile" {
                continue;
            }
        }

        new_statements : [..] *Code_Node;

        array_reserve(*new_statements, body.block.statements.count + 1);
        array_add(*new_statements, plugin.internal_prepend_zone_node);
        array_add(*new_statements, ..body.block.statements);

        body.block.statements = new_statements;

        compiler_modify_procedure(message.workspace, body);
    }
}

Finish :: (p : *Metaprogram_Plugin) {
    plugin := cast(*TracyPlugin, p);
}

Shutdown :: (p : *Metaprogram_Plugin) {
    free(p);
}

// With To_Insert, we declare a global symbol that imports Tracy and then
// do an #add_context that binds to that symbol. This seems redundant, but
// if we just say #add_context :: #import "Tracy", the import won't happen
// until the context gets finalized, which then means that anything imported
// by Tracy would be unable to add any thing to the context.
//
// We add an entry to the context so submodules can see the import, and injected
// code works correctly.
To_Insert :: #string DONE
__Tracy :: #import "Tracy"(Import_Mode=.Client);
#add_context _Tracy :: __Tracy;
DONE

Prepend_Zone_Code :: #code context._Tracy.ZoneScoped(location=.{});

#scope_module

#import "Basic";
#import "Compiler";
#import "File";
#import "String";

TracyPlugin :: struct {
    #as using base: Metaprogram_Plugin;

    should_instrument : (body : *Code_Procedure_Body) -> bool;
    instrument_modules := true;
    min_size := 30;

    internal_prepend_zone_node : *Code_Node; // Not for the user to set!
}
