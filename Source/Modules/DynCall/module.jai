#if OS == .WINDOWS {
    #load "dyncall_windows.jai";
    #load "dynload_windows.jai";
} else #if OS == .MACOS {
    #load "dyncall_macos.jai";
    #load "dynload_macos.jai";
} else #if OS == .LINUX {
    #load "dyncall_linux.jai";
    #load "dynload_linux.jai";
} else {
    #assert false "Unsupported OS";
}

DC_POINTER :: *void;

DC_SIGCHAR_VOID         :: #char "v";
DC_SIGCHAR_BOOL         :: #char "B";
DC_SIGCHAR_CHAR         :: #char "c";
DC_SIGCHAR_UCHAR        :: #char "C";
DC_SIGCHAR_SHORT        :: #char "s";
DC_SIGCHAR_USHORT       :: #char "S";
DC_SIGCHAR_INT          :: #char "i";
DC_SIGCHAR_UINT         :: #char "I";
DC_SIGCHAR_LONG         :: #char "j";
DC_SIGCHAR_ULONG        :: #char "J";
DC_SIGCHAR_LONGLONG     :: #char "l";
DC_SIGCHAR_ULONGLONG    :: #char "L";
DC_SIGCHAR_FLOAT        :: #char "f";
DC_SIGCHAR_DOUBLE       :: #char "d";
DC_SIGCHAR_POINTER      :: #char "p";
DC_SIGCHAR_STRING       :: #char "Z";
DC_SIGCHAR_AGGREGATE    :: #char "A";
DC_SIGCHAR_ENDARG       :: #char ")";

DC_SIGCHAR_CC_PREFIX           :: #char "_";
DC_SIGCHAR_CC_DEFAULT          :: #char ":";
DC_SIGCHAR_CC_THISCALL         :: #char "*";
DC_SIGCHAR_CC_ELLIPSIS         :: #char "e";
DC_SIGCHAR_CC_ELLIPSIS_VARARGS :: #char ".";
DC_SIGCHAR_CC_CDECL            :: #char "c";
DC_SIGCHAR_CC_STDCALL          :: #char "s";
DC_SIGCHAR_CC_FASTCALL_MS      :: #char "F";
DC_SIGCHAR_CC_FASTCALL_GNU     :: #char "f";
DC_SIGCHAR_CC_THISCALL_MS      :: #char "+";
DC_SIGCHAR_CC_THISCALL_GNU     :: #char "#";
DC_SIGCHAR_CC_ARM_ARM          :: #char "A";
DC_SIGCHAR_CC_ARM_THUMB        :: #char "a";
DC_SIGCHAR_CC_SYSCALL          :: #char "$";
