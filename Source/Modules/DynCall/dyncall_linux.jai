//
// This file was auto-generated using the following command:
//
// jai generate.jai
//



DC_CALL_C_DEFAULT :: 0;
DC_CALL_C_DEFAULT_THIS :: 99;
DC_CALL_C_ELLIPSIS :: 100;
DC_CALL_C_ELLIPSIS_VARARGS :: 101;

DC_CALL_C_X86_CDECL :: 1;
DC_CALL_C_X86_WIN32_STD :: 2;
DC_CALL_C_X86_WIN32_FAST_MS :: 3;
DC_CALL_C_X86_WIN32_FAST_GNU :: 4;
DC_CALL_C_X86_WIN32_THIS_MS :: 5;
DC_CALL_C_X86_WIN32_THIS_GNU :: DC_CALL_C_X86_CDECL;
DC_CALL_C_X64_WIN64 :: 7;
DC_CALL_C_X64_WIN64_THIS :: 70;
DC_CALL_C_X64_SYSV :: 8;
DC_CALL_C_X64_SYSV_THIS :: DC_CALL_C_X64_SYSV;
DC_CALL_C_PPC32_DARWIN :: 9;
DC_CALL_C_PPC32_OSX :: DC_CALL_C_PPC32_DARWIN;
DC_CALL_C_ARM_ARM_EABI :: 10;
DC_CALL_C_ARM_THUMB_EABI :: 11;
DC_CALL_C_ARM_ARMHF :: 30;
DC_CALL_C_MIPS32_EABI :: 12;
DC_CALL_C_MIPS32_PSPSDK :: DC_CALL_C_MIPS32_EABI;
DC_CALL_C_PPC32_SYSV :: 13;
DC_CALL_C_PPC32_LINUX :: DC_CALL_C_PPC32_SYSV;
DC_CALL_C_ARM_ARM :: 14;
DC_CALL_C_ARM_THUMB :: 15;
DC_CALL_C_MIPS32_O32 :: 16;
DC_CALL_C_MIPS64_N32 :: 17;
DC_CALL_C_MIPS64_N64 :: 18;
DC_CALL_C_X86_PLAN9 :: 19;
DC_CALL_C_SPARC32 :: 20;
DC_CALL_C_SPARC64 :: 21;
DC_CALL_C_ARM64 :: 22;
DC_CALL_C_PPC64 :: 23;
DC_CALL_C_PPC64_LINUX :: DC_CALL_C_PPC64;

DC_CALL_SYS_DEFAULT :: 200;

DC_CALL_SYS_X86_INT80H_LINUX :: 201;
DC_CALL_SYS_X86_INT80H_BSD :: 202;
DC_CALL_SYS_X64_SYSCALL_SYSV :: 204;
DC_CALL_SYS_PPC32 :: 210;
DC_CALL_SYS_PPC64 :: 211;

DC_ERROR_NONE :: 0;
DC_ERROR_UNSUPPORTED_MODE :: -1;

DC_SYSV_MAX_NUM_CLASSES :: 8;
SYSVC_NONE :: 0;
SYSVC_INTEGER :: 1<<0;
SYSVC_SSE :: 1<<1;
SYSVC_SSEUP :: 1<<2;
SYSVC_X87 :: 1<<3;
SYSVC_X87UP :: 1<<4;
SYSVC_COMPLEX_X87 :: 1<<5;
SYSVC_MEMORY :: 1<<6;

DYNCALL_VERSION :: 0x140f;

DCTHUNK_X64_SIZE :: 24;

DCvoid :: void;
DCbool :: s32;
DCchar :: u8;
DCuchar :: u8;
DCshort :: s16;
DCushort :: u16;
DCint :: s32;
DCuint :: u32;
DClong :: s64;
DCulong :: u64;
DClonglong :: s64;
DCulonglong :: u64;
DCfloat :: float;
DCdouble :: float64;
DCpointer :: *void;
DCstring :: *u8;
DCsize :: u64;

DCsigchar :: u8;

DCCallVM :: DCCallVM_;
DCaggr :: DCaggr_;

dcNewCallVM :: (size: DCsize) -> *DCCallVM #foreign dyncall_s;
dcFree :: (vm: *DCCallVM) -> void #foreign dyncall_s;
dcReset :: (vm: *DCCallVM) -> void #foreign dyncall_s;

dcMode :: (vm: *DCCallVM, mode: DCint) -> void #foreign dyncall_s;

dcBeginCallAggr :: (vm: *DCCallVM, ag: *DCaggr) -> void #foreign dyncall_s;

dcArgBool :: (vm: *DCCallVM, value: DCbool) -> void #foreign dyncall_s;
dcArgChar :: (vm: *DCCallVM, value: DCchar) -> void #foreign dyncall_s;
dcArgShort :: (vm: *DCCallVM, value: DCshort) -> void #foreign dyncall_s;
dcArgInt :: (vm: *DCCallVM, value: DCint) -> void #foreign dyncall_s;
dcArgLong :: (vm: *DCCallVM, value: DClong) -> void #foreign dyncall_s;
dcArgLongLong :: (vm: *DCCallVM, value: DClonglong) -> void #foreign dyncall_s;
dcArgFloat :: (vm: *DCCallVM, value: DCfloat) -> void #foreign dyncall_s;
dcArgDouble :: (vm: *DCCallVM, value: DCdouble) -> void #foreign dyncall_s;
dcArgPointer :: (vm: *DCCallVM, value: DCpointer) -> void #foreign dyncall_s;
dcArgAggr :: (vm: *DCCallVM, ag: *DCaggr, value: *void) -> void #foreign dyncall_s;

dcCallVoid :: (vm: *DCCallVM, funcptr: DCpointer) -> void #foreign dyncall_s;
dcCallBool :: (vm: *DCCallVM, funcptr: DCpointer) -> DCbool #foreign dyncall_s;
dcCallChar :: (vm: *DCCallVM, funcptr: DCpointer) -> DCchar #foreign dyncall_s;
dcCallShort :: (vm: *DCCallVM, funcptr: DCpointer) -> DCshort #foreign dyncall_s;
dcCallInt :: (vm: *DCCallVM, funcptr: DCpointer) -> DCint #foreign dyncall_s;
dcCallLong :: (vm: *DCCallVM, funcptr: DCpointer) -> DClong #foreign dyncall_s;
dcCallLongLong :: (vm: *DCCallVM, funcptr: DCpointer) -> DClonglong #foreign dyncall_s;
dcCallFloat :: (vm: *DCCallVM, funcptr: DCpointer) -> DCfloat #foreign dyncall_s;
dcCallDouble :: (vm: *DCCallVM, funcptr: DCpointer) -> DCdouble #foreign dyncall_s;
dcCallPointer :: (vm: *DCCallVM, funcptr: DCpointer) -> DCpointer #foreign dyncall_s;
dcCallAggr :: (vm: *DCCallVM, funcptr: DCpointer, ag: *DCaggr, ret: DCpointer) -> DCpointer #foreign dyncall_s;

dcGetError :: (vm: *DCCallVM) -> DCint #foreign dyncall_s;

dcNewAggr :: (maxFieldCount: DCsize, size: DCsize) -> *DCaggr #foreign dyncall_s;
dcFreeAggr :: (ag: *DCaggr) -> void #foreign dyncall_s;

/* if type == DC_SIGCHAR_AGGREGATE, pass DCaggr* of nested struct/union in ...  */
dcAggrField :: (ag: *DCaggr, type: DCsigchar, offset: DCint, array_len: DCsize, __args: ..Any) -> void #foreign dyncall_s;
dcCloseAggr :: (ag: *DCaggr) -> void #foreign dyncall_s;

/* returns respective mode for callconv sig char (w/o checking if mode exists */
/* on current platform), or DC_ERROR_UNSUPPORTED_MODE if char isn't a sigchar */
dcGetModeFromCCSigChar :: (sig_char: DCsigchar) -> DCint #foreign dyncall_s;

DCfield_ :: struct {
    offset:    DCsize;
    size:      DCsize;
    alignment: DCsize;
    array_len: DCsize;
    type:      DCsigchar;
    sub_aggr:  *DCaggr;
}

DCfield :: DCfield_;

DCaggr_ :: struct {
    size:         DCsize;
    n_fields:     DCsize;
    alignment:    DCsize;

    sysv_classes: [8] DCuchar; /* !code relies on this to be 64 bits! */

//     fields:       *DCfield;// Incomplete array in C (zero-sized)
}

DCValue :: DCValue_;

DCValue_ :: union {
    B: DCbool;
    c: DCchar;
    C: DCuchar;
    s: DCshort;
    S: DCushort;
    i: DCint;
    I: DCuint;

    j: DClong;
    J: DCulong;
    l: DClonglong;
    L: DCulonglong;

    f: DCfloat;

    d: DCdouble;
    p: DCpointer;
    Z: DCstring;
}

dcArgF :: (vm: *DCCallVM, signature: *DCsigchar, __args: ..Any) -> void #foreign dyncall_s;

dcCallF :: (vm: *DCCallVM, result: *DCValue, funcptr: DCpointer, signature: *DCsigchar, __args: ..Any) -> void #foreign dyncall_s;

/* NOTE: if something changes in DCCallVM_, update offset marks in dyncall_call_sparc.S */
DCCallVM_vt :: DCCallVM_vt_;

DCCallVM_ :: struct {
    mVTpointer: *DCCallVM_vt;
    mError:     DCint;
}

DCCallVM_vt_ :: struct {
    free:         #type (vm: *DCCallVM) -> void #c_call;
    reset:        #type (vm: *DCCallVM) -> void #c_call;
    mode:         #type (vm: *DCCallVM, mode: DCint) -> void #c_call;
    argBool:      #type (vm: *DCCallVM, B: DCbool) -> void #c_call;
    argChar:      #type (vm: *DCCallVM, c: DCchar) -> void #c_call;
    argShort:     #type (vm: *DCCallVM, s: DCshort) -> void #c_call;
    argInt:       #type (vm: *DCCallVM, i: DCint) -> void #c_call;
    argLong:      #type (vm: *DCCallVM, l: DClong) -> void #c_call;
    argLongLong:  #type (vm: *DCCallVM, L: DClonglong) -> void #c_call;
    argFloat:     #type (vm: *DCCallVM, f: DCfloat) -> void #c_call;
    argDouble:    #type (vm: *DCCallVM, d: DCdouble) -> void #c_call;
    argPointer:   #type (vm: *DCCallVM, p: DCpointer) -> void #c_call;
    argAggr:      #type (vm: *DCCallVM, ag: *DCaggr, p: *void) -> void #c_call;
    callVoid:     #type (vm: *DCCallVM, funcptr: DCpointer) -> void #c_call;
    callBool:     #type (vm: *DCCallVM, funcptr: DCpointer) -> DCbool #c_call;
    callChar:     #type (vm: *DCCallVM, funcptr: DCpointer) -> DCchar #c_call;
    callShort:    #type (vm: *DCCallVM, funcptr: DCpointer) -> DCshort #c_call;
    callInt:      #type (vm: *DCCallVM, funcptr: DCpointer) -> DCint #c_call;
    callLong:     #type (vm: *DCCallVM, funcptr: DCpointer) -> DClong #c_call;
    callLongLong: #type (vm: *DCCallVM, funcptr: DCpointer) -> DClonglong #c_call;
    callFloat:    #type (vm: *DCCallVM, funcptr: DCpointer) -> DCfloat #c_call;
    callDouble:   #type (vm: *DCCallVM, funcptr: DCpointer) -> DCdouble #c_call;
    callPointer:  #type (vm: *DCCallVM, funcptr: DCpointer) -> DCpointer #c_call;
    callAggr:     #type (vm: *DCCallVM, funcptr: DCpointer, ag: *DCaggr, returnValue: DCpointer) -> void #c_call;
    beginAggr:    #type (vm: *DCCallVM, ag: *DCaggr) -> void #c_call;
}

DCvoidvmfunc :: #type (vm: *DCCallVM, funcptr: DCpointer) -> DCvoid #c_call;
DCboolvmfunc :: #type (vm: *DCCallVM, funcptr: DCpointer) -> DCbool #c_call;
DCcharvmfunc :: #type (vm: *DCCallVM, funcptr: DCpointer) -> DCchar #c_call;
DCshortvmfunc :: #type (vm: *DCCallVM, funcptr: DCpointer) -> DCshort #c_call;
DCintvmfunc :: #type (vm: *DCCallVM, funcptr: DCpointer) -> DCint #c_call;
DClongvmfunc :: #type (vm: *DCCallVM, funcptr: DCpointer) -> DClong #c_call;
DClonglongvmfunc :: #type (vm: *DCCallVM, funcptr: DCpointer) -> DClonglong #c_call;
DCfloatvmfunc :: #type (vm: *DCCallVM, funcptr: DCpointer) -> DCfloat #c_call;
DCdoublevmfunc :: #type (vm: *DCCallVM, funcptr: DCpointer) -> DCdouble #c_call;
DCpointervmfunc :: #type (vm: *DCCallVM, funcptr: DCpointer) -> DCpointer #c_call;
DCaggrvmfunc :: #type (vm: *DCCallVM, funcptr: DCpointer, ag: *DCaggr, returnValue: DCpointer) -> DCvoid #c_call;
DCbeginaggrvmfunc :: #type (vm: *DCCallVM, ag: *DCaggr) -> DCvoid #c_call;

/* Common base functions for CallVM implementations. */
dc_callvm_base_init :: (pInstance: *DCCallVM, pVTable: *DCCallVM_vt) -> void #foreign dyncall_s;

DCVecHead :: struct {
    mTotal: DCsize;
    mSize:  DCsize;
}

dcVecAppend :: (pHead: *DCVecHead, source: *void, length: u64) -> void #foreign dyncall_s;

DCerror :: s32;

/* returns 0 on success */
dcAllocWX :: (size: DCsize, p: **void) -> DCerror #foreign dyncall_s;
dcInitExecWX :: (p: *void, size: DCsize) -> DCerror #foreign dyncall_s;
dcFreeWX :: (p: *void, size: DCsize) -> void #foreign dyncall_s;

DCArgs :: struct {}

/* functions to retrieve callback's params in callback handler */
dcbArgBool :: (p: *DCArgs) -> DCbool #foreign dyncall_s;
dcbArgChar :: (p: *DCArgs) -> DCchar #foreign dyncall_s;
dcbArgShort :: (p: *DCArgs) -> DCshort #foreign dyncall_s;
dcbArgInt :: (p: *DCArgs) -> DCint #foreign dyncall_s;
dcbArgLong :: (p: *DCArgs) -> DClong #foreign dyncall_s;
dcbArgLongLong :: (p: *DCArgs) -> DClonglong #foreign dyncall_s;
dcbArgUChar :: (p: *DCArgs) -> DCuchar #foreign dyncall_s;
dcbArgUShort :: (p: *DCArgs) -> DCushort #foreign dyncall_s;
dcbArgUInt :: (p: *DCArgs) -> DCuint #foreign dyncall_s;
dcbArgULong :: (p: *DCArgs) -> DCulong #foreign dyncall_s;
dcbArgULongLong :: (p: *DCArgs) -> DCulonglong #foreign dyncall_s;
dcbArgFloat :: (p: *DCArgs) -> DCfloat #foreign dyncall_s;
dcbArgDouble :: (p: *DCArgs) -> DCdouble #foreign dyncall_s;
dcbArgPointer :: (p: *DCArgs) -> DCpointer #foreign dyncall_s;

/* for trivial aggrs: 'target' points to space to copy aggr to, returns 'target'
for C++ non-trivial aggrs: target is ignored, returns ptr to aggr arg */
dcbArgAggr :: (p: *DCArgs, target: DCpointer) -> DCpointer #foreign dyncall_s;

/* helper func to put a to be returned struct-by-value into the 'result'
param of the callback handler; for C++ non-trivial aggrs, pass NULL in
'ret', then copy aggr into result->p */
dcbReturnAggr :: (args: *DCArgs, result: *DCValue, ret: DCpointer) -> void #foreign dyncall_s;

DCCallback :: struct {}

/* callback handler:
- handlers return value signature char (see dyncall_signature.h) of callback's return value type
- callback return value is written to the corresponding type's field of result
- if callback return value is an aggregate (by value), use dcbReturnAggr() as a helper to write to result
*/
DCCallbackHandler :: #type (pcb: *DCCallback, args: *DCArgs, result: *DCValue, userdata: *void) -> DCsigchar #c_call;

dcbNewCallback :: (signature: *DCsigchar, funcptr: DCCallbackHandler, userdata: *void) -> *DCCallback #foreign dyncall_s;
dcbNewCallback2 :: (signature: *DCsigchar, funcptr: DCCallbackHandler, userdata: *void, aggrs: **DCaggr) -> *DCCallback #foreign dyncall_s;
dcbInitCallback :: (pcb: *DCCallback, signature: *DCsigchar, handler: DCCallbackHandler, userdata: *void) -> void #foreign dyncall_s;
dcbInitCallback2 :: (pcb: *DCCallback, signature: *DCsigchar, handler: DCCallbackHandler, userdata: *void, aggrs: **DCaggr) -> void #foreign dyncall_s;
dcbFreeCallback :: (pcb: *DCCallback) -> void #foreign dyncall_s;
dcbGetUserData :: (pcb: *DCCallback) -> *void #foreign dyncall_s;

DCThunk_ :: struct {
    code: [2] u64;
}

#scope_file

dyncall_s :: #library,no_dll "linux/dyncall_s";
dyncallback_s :: #library,no_dll "linux/dyncallback_s";
