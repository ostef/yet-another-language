#import "Thread";
#import "File";

#add_context log_section : *Log_Section;

LogSectionScope :: (section : *Log_Section) #expand
{
    prev := context.log_section;
    context.log_section = section;
    `defer context.log_section = prev;
}

LoggerScope :: (data : *void, proc : Logger) #expand
{
    prev_data := context.logger_data;
    prev_logger := context.logger;

    context.logger_data = data;
    context.logger = proc;

    `defer context.logger_data = prev_data;
    `defer context.logger = prev_logger;
}

SetContextLogger :: inline (data : *void, proc : Logger)
{
    context.logger_data = data;
    context.logger = proc;
}

IgnoreLogger :: (message : string, data : *void, info : Log_Info)
{
}

MultiLogger :: struct
{
    DispatchTarget :: struct
    {
        data : *void;
        proc : Logger;
    }

    dispatch_targets : [..]DispatchTarget;
}

AddLogTarget :: (logger : *MultiLogger, data : *void, proc : Logger)
{
    ArrayPush(*logger.dispatch_targets, .{data, proc});
}

MultiLoggerProc :: (message : string, data : *void, info : Log_Info)
{
    using _ := cast(*MultiLogger) data;

    for dispatch_targets
    {
        it.proc(message, it.data, info);
    }
}

ConsoleLogger :: struct
{
    report_filenames := false;
    print_colors := false;
    print_stack_trace := false;
}

None_Color_Str    :: "\x1b[0m";
Info_Color_Str    :: "\x1b[1;32m";
Warning_Color_Str :: "\x1b[1;33m";
Error_Color_Str   :: "\x1b[1;31m";
Fatal_Color_Str   :: "\x1b[1;35m";

ConsoleColor :: enum
{
    None;
    Info;
    Warning;
    Error;
    Fatal;
}

AppendConsoleColor :: (builder : *StringBuilder, color : ConsoleColor)
{
    if #complete color ==
    {
    case .None;
        StringBuilderAppendString(builder, None_Color_Str);
    case .Info;
        StringBuilderAppendString(builder, Info_Color_Str);
    case .Warning;
        StringBuilderAppendString(builder, Warning_Color_Str);
    case .Error;
        StringBuilderAppendString(builder, Error_Color_Str);
    case .Fatal;
        StringBuilderAppendString(builder, Fatal_Color_Str);
    }
}

SetConsoleColor :: (color : ConsoleColor, to_standard_error := true)
{
    if #complete color ==
    {
    case .None;
        write_string(None_Color_Str, to_standard_error = to_standard_error);
    case .Info;
        write_string(Info_Color_Str, to_standard_error = to_standard_error);
    case .Warning;
        write_string(Warning_Color_Str, to_standard_error = to_standard_error);
    case .Error;
        write_string(Error_Color_Str, to_standard_error = to_standard_error);
    case .Fatal;
        write_string(Fatal_Color_Str, to_standard_error = to_standard_error);
    }
}

InitConsoleLogger :: (logger : *ConsoleLogger, print_colors := true)
{
    if !print_colors
        return;

    #if OS == .WINDOWS
    {
        CONSOLE_MODE :: enum_flags u32
        {
            ENABLE_PROCESSED_INPUT :: 1;
            ENABLE_LINE_INPUT :: 2;
            ENABLE_ECHO_INPUT :: 4;
            ENABLE_WINDOW_INPUT :: 8;
            ENABLE_MOUSE_INPUT :: 16;
            ENABLE_INSERT_MODE :: 32;
            ENABLE_QUICK_EDIT_MODE :: 64;
            ENABLE_EXTENDED_FLAGS :: 128;
            ENABLE_AUTO_POSITION :: 256;
            ENABLE_VIRTUAL_TERMINAL_INPUT :: 512;
            ENABLE_PROCESSED_OUTPUT :: 1;
            ENABLE_WRAP_AT_EOL_OUTPUT :: 2;
            ENABLE_VIRTUAL_TERMINAL_PROCESSING :: 4;
            DISABLE_NEWLINE_AUTO_RETURN :: 8;
            ENABLE_LVB_GRID_WORLDWIDE :: 16;
        }

        STD_INPUT_HANDLE :: 4294967286;
        STD_OUTPUT_HANDLE :: 4294967285;
        STD_ERROR_HANDLE :: 4294967284;

        Kernel32 :: #system_library "Kernel32";

        GetStdHandle :: (nStdHandle : u32) -> *void #foreign Kernel32;
        GetConsoleMode :: (hConsoleHandle : *void, lpMode : *CONSOLE_MODE) -> s32 #foreign Kernel32;
        SetConsoleMode :: (hConsoleHandle : *void, dwMode : CONSOLE_MODE) -> s32 #foreign Kernel32;

        std_out := GetStdHandle(STD_OUTPUT_HANDLE);
        std_err := GetStdHandle(STD_ERROR_HANDLE);

        std_out_colors, std_err_colors : bool;

        mode : CONSOLE_MODE;
        if GetConsoleMode(std_out, *mode)
        {
            if SetConsoleMode(std_out, mode | .ENABLE_VIRTUAL_TERMINAL_PROCESSING)
                std_out_colors = true;
        }

        mode = 0;
        if GetConsoleMode(std_err, *mode)
        {
            if SetConsoleMode(std_err, mode | .ENABLE_VIRTUAL_TERMINAL_PROCESSING)
                std_err_colors = true;
        }

        logger.print_colors = std_out_colors && std_err_colors;
    }
    else #if OS == .LINUX || OS == .MACOS
    {
        POSIX :: #import "POSIX";

        logger.print_colors = POSIX.isatty(POSIX.STDOUT_FILENO) && POSIX.isatty(POSIX.STDERR_FILENO);
    }
}

ConsoleLoggerProc :: (message : string, data : *void, info : Log_Info)
{
    if !message
        return;

    if info.common_flags & .TO_FILE_ONLY
        return;

    if context.log_level == .NORMAL
    && (info.common_flags & .VERBOSE_ONLY || info.common_flags & .VERY_VERBOSE_ONLY)
    {
        return;
    }

    if context.log_level == .VERBOSE
    && info.common_flags & .VERY_VERBOSE_ONLY
    {
        return;
    }

    using logger := cast(*ConsoleLogger) data;

    builder : StringBuilder;
    builder.allocator = Temp;

    if print_colors
    {
        if info.common_flags & .ERROR
            AppendConsoleColor(*builder, .Error);
        else if info.common_flags & .WARNING
            AppendConsoleColor(*builder, .Warning);
    }

    if info.section
        StringBuilderAppend(*builder, "[%] ", info.section.name);

    // @Todo: reduce filename
    if report_filenames
        StringBuilderAppend(*builder, "(%:%) ", info.location.fully_pathed_filename, info.location.line_number);

    StringBuilderAppendString(*builder, message);

    if message[message.count - 1] != #char "\n"
        StringBuilderAppendString(*builder, "\n");

    if print_colors
        AppendConsoleColor(*builder, .None);

    str := StringBuilderBuild(*builder,, Temp);

    to_stderr := (info.common_flags | .ERROR) != 0;

    write_string(str, to_standard_error = to_stderr);

    if print_stack_trace
    {
        Basic.print_stack_trace(context.stack_trace, to_standard_error=to_stderr);
    }
}

FileLogger :: struct
{
    report_filenames := false;
    file : File;
}

InitFileLogger :: (logger : *FileLogger, filename : string) -> bool
{
    ok : bool;
    logger.file, ok = file_open(filename, for_writing=true);

    return ok;
}

CloseFileLogger :: (logger : *FileLogger)
{
    file_close(*logger.file);
}

FileLoggerProc :: (message : string, data : *void, info : Log_Info)
{
    if !message
        return;

    if context.log_level == .NORMAL
    && (info.common_flags & .VERBOSE_ONLY || info.common_flags & .VERY_VERBOSE_ONLY)
    {
        return;
    }

    if context.log_level == .VERBOSE
    && info.common_flags & .VERY_VERBOSE_ONLY
    {
        return;
    }

    using logger := cast(*FileLogger) data;

    builder : StringBuilder;
    builder.allocator = Temp;

    if info.section
        StringBuilderAppend(*builder, "[%] ", info.section.name);

    // @Todo: reduce filename
    if report_filenames
        StringBuilderAppend(*builder, "(%:%) ", info.location.fully_pathed_filename, info.location.line_number);

    StringBuilderAppendString(*builder, message);

    if message[message.count - 1] != #char "\n"
        StringBuilderAppendString(*builder, "\n");

    file_write(*file, *builder);

    // Flush the file
    #if OS == .LINUX
    {
        libc :: #system_library "libc";
        fflush :: (file : *void) -> s32 #foreign libc;
        fflush(file.handle);
    }
    else #if OS == .WINDOWS
    {
        Kernel32 :: #system_library "Kernel32";
        FlushFileBuffers :: (hFile : *void) -> s32 #foreign Kernel32;
        FlushFileBuffers(file.handle);
    }
}

LogMessage :: inline (fmt_str : string, args : ..Any, location := #caller_location, flags := Log_Flags.NONE, user_flags : u32 = 0)
{
    msg := SPrint(fmt_str, ..args,, Temp);
    if msg.count == 0
        return;

    info : Log_Info;
    info.source_identifier = context.log_source_identifier;
    info.location     = location;
    info.common_flags = flags;
    info.user_flags   = user_flags;
    info.section      = context.log_section;

    context.logger(msg, context.logger_data, info);
}

LogWarning :: inline (fmt_str : string, args : ..Any, location := #caller_location, flags := Log_Flags.NONE, user_flags : u32 = 0)
{
    LogMessage(fmt_str, ..args, location, flags | .WARNING, user_flags);
}

LogError :: inline (fmt_str : string, args : ..Any, location := #caller_location, flags := Log_Flags.NONE, user_flags : u32 = 0)
{
    LogMessage(fmt_str, ..args, location, flags | .ERROR, user_flags);
}

LogContentMessage :: inline (fmt_str : string, args : ..Any, location := #caller_location, flags := Log_Flags.NONE, user_flags : u32 = 0)
{
    LogMessage(fmt_str, ..args, location, flags | .CONTENT, user_flags);
}

LogContentWarning :: inline (fmt_str : string, args : ..Any, location := #caller_location, flags := Log_Flags.NONE, user_flags : u32 = 0)
{
    LogContentMessage(fmt_str, ..args, location, flags | .WARNING, user_flags);
}

LogContentError :: inline (fmt_str : string, args : ..Any, location := #caller_location, flags := Log_Flags.NONE, user_flags : u32 = 0)
{
    LogContentMessage(fmt_str, ..args, location, flags | .ERROR, user_flags);
}
