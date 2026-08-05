//
// This file was auto-generated using the following command:
//
// jai generate.jai
//



DLLib_ :: struct {}
/* shared library loading and explicit symbol resolving */
/* dlLoadLibrary will search for specified lib (e.g. as leaf name, only), */
/* following platforms' dynamic linking style, returns NULL on error */
DLLib :: DLLib_;

dlLoadLibrary :: (libPath: *u8) -> *DLLib #foreign dynload_s;
dlFreeLibrary :: (pLib: *DLLib) -> void #foreign dynload_s;
dlFindSymbol :: (pLib: *DLLib, pSymbolName: *u8) -> *void #foreign dynload_s;
dlGetLibraryPath :: (pLib: *DLLib, sOut: *u8, bufSize: s32) -> s32 #foreign dynload_s;

DLSyms_ :: struct {}
/* symbol table enumeration - only for symbol lookup, not resolve */
/* note that dlSymsInit does not search library paths */
DLSyms :: DLSyms_;

dlSymsInit :: (libPath: *u8) -> *DLSyms #foreign dynload_s;
dlSymsCleanup :: (pSyms: *DLSyms) -> void #foreign dynload_s;

dlSymsCount :: (pSyms: *DLSyms) -> s32 #foreign dynload_s;
dlSymsName :: (pSyms: *DLSyms, index: s32) -> *u8 #foreign dynload_s;
dlSymsNameFromValue :: (pSyms: *DLSyms, value: *void) -> *u8 #foreign dynload_s;

#scope_file

dynload_s :: #library,no_dll "windows/dynload_s";
