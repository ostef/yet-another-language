// Helpful macros and functions to interface with the C api

#if Enabled {
    #if OS == .WINDOWS {
        #load "tracy_windows.jai";
    } else #if OS == .LINUX {
        #load "tracy_linux.jai";
    } else #if OS == .MACOS {
        #load "tracy_macos.jai";
    } else {
        #assert false "Unsupported platform";
    }

#scope_file

    g_profiling := false;

#scope_export

    IsProfiling :: inline () -> bool {
        return g_profiling;
    }

    EnableProfiling :: inline () {
        g_profiling = true;
    }

    DisableProfiling :: inline () {
        g_profiling = false;
    }

    // Call this every frame
    FrameMark :: () #expand #no_debug {
        if g_profiling {
            emit_frame_mark(null);
        }
    }

    // Call this at the start of the scope you want to profile
    ZoneScoped :: (name := "", text := "", color : u32 = 0, value : u64 = 0, location := #caller_location) #expand #no_debug {
        // In case g_profiling is modified in between start and end
        running := g_profiling;

        tracy_ctx: ZoneCtx;
        if running {
            zone_name := ifx name then name else #procedure_name(#this);
            if !zone_name {
                zone_name = "<anonymous>";
            }

            loc := ifx location.fully_pathed_filename
                then location
                else #location(#this);

            tracy_loc := alloc_srcloc(xx loc.line_number, loc.fully_pathed_filename.data, xx loc.fully_pathed_filename.count, zone_name.data, xx zone_name.count, color);
            tracy_ctx = emit_zone_begin_alloc(tracy_loc, 1);

            if text  {
                emit_zone_text(tracy_ctx, text.data, cast(u64, text.count));
            }
            if color {
                emit_zone_color(tracy_ctx, color);
            }
            if value {
                emit_zone_value(tracy_ctx, value);
            }
        }

        `defer if running {
            emit_zone_end(tracy_ctx);
        }
    }

    EmitMessage :: (msg : string, args : ..Any, color : u32 = 0) #expand {
        if g_profiling {
            #import "Basic";
            s := tprint(msg, ..args);

            if color {
                emit_messageC(s.data, xx s.count, color, xx ifx context.stack_trace then context.stack_trace.call_depth);
            } else {
                emit_message(s.data, xx s.count, xx ifx context.stack_trace then context.stack_trace.call_depth);
            }
        }
    }
} else {

    IsProfiling :: inline () -> bool { return false; }
    EnableProfiling :: inline () {}
    DisableProfiling :: inline () {}
    FrameMark :: () #expand #no_debug {}
    ZoneScoped :: (name := "", text := "", color: u32 = 0, value: u64 = 0, location := #caller_location) #expand #no_debug {}
    EmitMessage :: (#discard msg : string, #discard args : ..Any, #discard color : u32 = 0)  #expand #no_debug {}
}
