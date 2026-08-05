//
// This file was auto-generated using the following command:
//
// jai generate.jai - build
//



TRACY_ENABLE :: 1;
TRACY_EXPORTS :: 1;
TRACY_IMPORTS :: 1;
TracyCIsStarted :: 1;

TRACY_CALLSTACK :: 0;

PlotFormatEnum :: enum u32 {
    Number     :: 0;
    Memory     :: 1;
    Percentage :: 2;
    Watt       :: 3;

    TracyPlotFormatNumber     :: Number;
    TracyPlotFormatMemory     :: Memory;
    TracyPlotFormatPercentage :: Percentage;
    TracyPlotFormatWatt       :: Watt;
}

set_thread_name :: (name: *u8) -> void #foreign tracyclient "___tracy_set_thread_name";

source_location_data :: struct {
    name:     *u8;
    function: *u8;
    file:     *u8;
    line:     u32;
    color:    u32;
}

c_zone_context :: struct {
    id:     u32;
    active: s32;
}

gpu_time_data :: struct {
    gpuTime:  s64;
    queryId:  u16;
    _context: u8;
}

gpu_zone_begin_data :: struct {
    srcloc:   u64;
    queryId:  u16;
    _context: u8;
}

gpu_zone_begin_callstack_data :: struct {
    srcloc:   u64;
    depth:    s32;
    queryId:  u16;
    _context: u8;
}

gpu_zone_end_data :: struct {
    queryId:  u16;
    _context: u8;
}

gpu_new_context_data :: struct {
    gpuTime:  s64;
    period:   float;
    _context: u8;
    flags:    u8;
    type:     u8;
}

gpu_context_name_data :: struct {
    _context: u8;
    name:     *u8;
    len:      u16;
}

gpu_calibration_data :: struct {
    gpuTime:  s64;
    cpuDelta: s64;
    _context: u8;
}

gpu_time_sync_data :: struct {
    gpuTime:  s64;
    _context: u8;
}

lockable_context_data :: struct {}

// Some containers don't support storing const types.
// This struct, as visible to user, is immutable, so treat it as if const was declared here.
ZoneCtx :: c_zone_context;

LockCtx :: *lockable_context_data;

alloc_srcloc :: (line: u32, source: *u8, sourceSz: u64, function: *u8, functionSz: u64, color: u32) -> u64 #foreign tracyclient "___tracy_alloc_srcloc";
alloc_srcloc_name :: (line: u32, source: *u8, sourceSz: u64, function: *u8, functionSz: u64, name: *u8, nameSz: u64, color: u32) -> u64 #foreign tracyclient "___tracy_alloc_srcloc_name";

emit_zone_begin :: (srcloc: *source_location_data, active: s32) -> ZoneCtx #foreign tracyclient "___tracy_emit_zone_begin";
emit_zone_begin_callstack :: (srcloc: *source_location_data, depth: s32, active: s32) -> ZoneCtx #foreign tracyclient "___tracy_emit_zone_begin_callstack";
emit_zone_begin_alloc :: (srcloc: u64, active: s32) -> ZoneCtx #foreign tracyclient "___tracy_emit_zone_begin_alloc";
emit_zone_begin_alloc_callstack :: (srcloc: u64, depth: s32, active: s32) -> ZoneCtx #foreign tracyclient "___tracy_emit_zone_begin_alloc_callstack";
emit_zone_end :: (ctx: ZoneCtx) -> void #foreign tracyclient "___tracy_emit_zone_end";
emit_zone_text :: (ctx: ZoneCtx, txt: *u8, size: u64) -> void #foreign tracyclient "___tracy_emit_zone_text";
emit_zone_name :: (ctx: ZoneCtx, txt: *u8, size: u64) -> void #foreign tracyclient "___tracy_emit_zone_name";
emit_zone_color :: (ctx: ZoneCtx, color: u32) -> void #foreign tracyclient "___tracy_emit_zone_color";
emit_zone_value :: (ctx: ZoneCtx, value: u64) -> void #foreign tracyclient "___tracy_emit_zone_value";

emit_gpu_zone_begin :: (unknown0: gpu_zone_begin_data) -> void #foreign tracyclient "___tracy_emit_gpu_zone_begin";
emit_gpu_zone_begin_callstack :: (unknown0: gpu_zone_begin_callstack_data) -> void #foreign tracyclient "___tracy_emit_gpu_zone_begin_callstack";
emit_gpu_zone_begin_alloc :: (unknown0: gpu_zone_begin_data) -> void #foreign tracyclient "___tracy_emit_gpu_zone_begin_alloc";
emit_gpu_zone_begin_alloc_callstack :: (unknown0: gpu_zone_begin_callstack_data) -> void #foreign tracyclient "___tracy_emit_gpu_zone_begin_alloc_callstack";
emit_gpu_zone_end :: (data: gpu_zone_end_data) -> void #foreign tracyclient "___tracy_emit_gpu_zone_end";
emit_gpu_time :: (unknown0: gpu_time_data) -> void #foreign tracyclient "___tracy_emit_gpu_time";
emit_gpu_new_context :: (unknown0: gpu_new_context_data) -> void #foreign tracyclient "___tracy_emit_gpu_new_context";
emit_gpu_context_name :: (unknown0: gpu_context_name_data) -> void #foreign tracyclient "___tracy_emit_gpu_context_name";
emit_gpu_calibration :: (unknown0: gpu_calibration_data) -> void #foreign tracyclient "___tracy_emit_gpu_calibration";
emit_gpu_time_sync :: (unknown0: gpu_time_sync_data) -> void #foreign tracyclient "___tracy_emit_gpu_time_sync";

emit_gpu_zone_begin_serial :: (unknown0: gpu_zone_begin_data) -> void #foreign tracyclient "___tracy_emit_gpu_zone_begin_serial";
emit_gpu_zone_begin_callstack_serial :: (unknown0: gpu_zone_begin_callstack_data) -> void #foreign tracyclient "___tracy_emit_gpu_zone_begin_callstack_serial";
emit_gpu_zone_begin_alloc_serial :: (unknown0: gpu_zone_begin_data) -> void #foreign tracyclient "___tracy_emit_gpu_zone_begin_alloc_serial";
emit_gpu_zone_begin_alloc_callstack_serial :: (unknown0: gpu_zone_begin_callstack_data) -> void #foreign tracyclient "___tracy_emit_gpu_zone_begin_alloc_callstack_serial";
emit_gpu_zone_end_serial :: (data: gpu_zone_end_data) -> void #foreign tracyclient "___tracy_emit_gpu_zone_end_serial";
emit_gpu_time_serial :: (unknown0: gpu_time_data) -> void #foreign tracyclient "___tracy_emit_gpu_time_serial";
emit_gpu_new_context_serial :: (unknown0: gpu_new_context_data) -> void #foreign tracyclient "___tracy_emit_gpu_new_context_serial";
emit_gpu_context_name_serial :: (unknown0: gpu_context_name_data) -> void #foreign tracyclient "___tracy_emit_gpu_context_name_serial";
emit_gpu_calibration_serial :: (unknown0: gpu_calibration_data) -> void #foreign tracyclient "___tracy_emit_gpu_calibration_serial";
emit_gpu_time_sync_serial :: (unknown0: gpu_time_sync_data) -> void #foreign tracyclient "___tracy_emit_gpu_time_sync_serial";

connected :: () -> s32 #foreign tracyclient "___tracy_connected";

emit_memory_alloc :: (ptr: *void, size: u64, secure: s32) -> void #foreign tracyclient "___tracy_emit_memory_alloc";
emit_memory_alloc_callstack :: (ptr: *void, size: u64, depth: s32, secure: s32) -> void #foreign tracyclient "___tracy_emit_memory_alloc_callstack";
emit_memory_free :: (ptr: *void, secure: s32) -> void #foreign tracyclient "___tracy_emit_memory_free";
emit_memory_free_callstack :: (ptr: *void, depth: s32, secure: s32) -> void #foreign tracyclient "___tracy_emit_memory_free_callstack";
emit_memory_alloc_named :: (ptr: *void, size: u64, secure: s32, name: *u8) -> void #foreign tracyclient "___tracy_emit_memory_alloc_named";
emit_memory_alloc_callstack_named :: (ptr: *void, size: u64, depth: s32, secure: s32, name: *u8) -> void #foreign tracyclient "___tracy_emit_memory_alloc_callstack_named";
emit_memory_free_named :: (ptr: *void, secure: s32, name: *u8) -> void #foreign tracyclient "___tracy_emit_memory_free_named";
emit_memory_free_callstack_named :: (ptr: *void, depth: s32, secure: s32, name: *u8) -> void #foreign tracyclient "___tracy_emit_memory_free_callstack_named";
emit_memory_discard :: (name: *u8, secure: s32) -> void #foreign tracyclient "___tracy_emit_memory_discard";
emit_memory_discard_callstack :: (name: *u8, secure: s32, depth: s32) -> void #foreign tracyclient "___tracy_emit_memory_discard_callstack";

emit_message :: (txt: *u8, size: u64, callstack_depth: s32) -> void #foreign tracyclient "___tracy_emit_message";
emit_messageL :: (txt: *u8, callstack_depth: s32) -> void #foreign tracyclient "___tracy_emit_messageL";
emit_messageC :: (txt: *u8, size: u64, color: u32, callstack_depth: s32) -> void #foreign tracyclient "___tracy_emit_messageC";
emit_messageLC :: (txt: *u8, color: u32, callstack_depth: s32) -> void #foreign tracyclient "___tracy_emit_messageLC";

emit_frame_mark :: (name: *u8) -> void #foreign tracyclient "___tracy_emit_frame_mark";
emit_frame_mark_start :: (name: *u8) -> void #foreign tracyclient "___tracy_emit_frame_mark_start";
emit_frame_mark_end :: (name: *u8) -> void #foreign tracyclient "___tracy_emit_frame_mark_end";
emit_frame_image :: (image: *void, w: u16, h: u16, offset: u8, flip: s32) -> void #foreign tracyclient "___tracy_emit_frame_image";

emit_plot :: (name: *u8, val: float64) -> void #foreign tracyclient "___tracy_emit_plot";
emit_plot_float :: (name: *u8, val: float) -> void #foreign tracyclient "___tracy_emit_plot_float";
emit_plot_int :: (name: *u8, val: s64) -> void #foreign tracyclient "___tracy_emit_plot_int";
emit_plot_config :: (name: *u8, type: s32, step: s32, fill: s32, color: u32) -> void #foreign tracyclient "___tracy_emit_plot_config";
emit_message_appinfo :: (txt: *u8, size: u64) -> void #foreign tracyclient "___tracy_emit_message_appinfo";

announce_lockable_ctx :: (srcloc: *source_location_data) -> *lockable_context_data #foreign tracyclient "___tracy_announce_lockable_ctx";
terminate_lockable_ctx :: (lockdata: *lockable_context_data) -> void #foreign tracyclient "___tracy_terminate_lockable_ctx";
before_lock_lockable_ctx :: (lockdata: *lockable_context_data) -> s32 #foreign tracyclient "___tracy_before_lock_lockable_ctx";
after_lock_lockable_ctx :: (lockdata: *lockable_context_data) -> void #foreign tracyclient "___tracy_after_lock_lockable_ctx";
after_unlock_lockable_ctx :: (lockdata: *lockable_context_data) -> void #foreign tracyclient "___tracy_after_unlock_lockable_ctx";
after_try_lock_lockable_ctx :: (lockdata: *lockable_context_data, acquired: s32) -> void #foreign tracyclient "___tracy_after_try_lock_lockable_ctx";
mark_lockable_ctx :: (lockdata: *lockable_context_data, srcloc: *source_location_data) -> void #foreign tracyclient "___tracy_mark_lockable_ctx";
custom_name_lockable_ctx :: (lockdata: *lockable_context_data, name: *u8, nameSz: u64) -> void #foreign tracyclient "___tracy_custom_name_lockable_ctx";

#scope_file

tracyclient :: #library "Lib/Linux/TracyClient";
