#import "DynCall";

#load "ir_to_bytecode.jai";

BytecodeFile :: struct {
    symbol_name_to_address : HashMap(string, BytecodeAddress);
    address_to_symbol_name : HashMap(BytecodeAddress, string);

    addresses_to_translate : [..]BytecodeAddress;
    external_libraries : [..]BytecodeExternalLibrary;
    dyncall_aggregates : [..]BytecodeDynCallAggr;

    data : []u8;
    code : []u8;
}

BytecodeAddress :: u64;
Bytecode_Address_Offset_Bits :: 60;
Bytecode_Address_Offset_Mask :: 0x0fffffffffffffff;
Bytecode_Address_Type_Bits :: 2;
Bytecode_Address_Type_Mask :: 0b11;

BytecodeAddressType :: enum u8 {
    DirectAddress :: 0;
    StackAddress  :: 1;
    DataAddress   :: 2;
    CodeAddress   :: 3;
}

BytecodeExternalLibrary :: struct {
    library_name : string;
    // When loaded, this is iterated upon to fixup all the addresses in the bytecode
    referenced_symbols : HashMap(string, [..]BytecodeAddress);
}

FindOrAddExternalLibrary :: (file : *BytecodeFile, name : string) -> *BytecodeExternalLibrary {
    for * file.external_libraries {
        if it.library_name == name {
            return it;
        }
    }

    lib := ArrayPush(*file.external_libraries);
    lib.library_name = name;

    return lib;
}

AddExternalSymbolReference :: (lib : *BytecodeExternalLibrary, symbol_name : string, addr : BytecodeAddress) {
    references := HashMapInsert(*lib.referenced_symbols, symbol_name);
    ArrayPush(references, addr);
}

BytecodeDynCallAggrField :: struct {
    type : DCsigchar;
    offset : u32 = 0xffffffff;
    array_length : u64;
    nested_aggr_address : BytecodeAddress;
}

BytecodeDynCallAggr :: struct {
    // When loading up the bytecode file, we store the *DCaggr at that address
    runtime_address : BytecodeAddress;
    size : u64;
    fields : []BytecodeDynCallAggrField;
}

BytecodeInterpreter :: struct {
    file : *BytecodeFile;
    source_file_id : FileId = -1;
    source_line : u32;

    stack : []u8;
    stack_frame : *BytecodeStackFrame;

    using,only(
        stack_pointer,
        instruction_pointer,
        register_base_pointer,
    ) stack_frame;

    data : []u8;
    code : []u8;

    dyncall_vm : *DCCallVM;
    dyncall_aggregates : HashMap(u64, *DCaggr);
    external_libraries : HashMap(string, BytecodeLoadedLibrary);
}

BytecodeLoadedLibrary :: struct {
    handle : *DLLib;
    symbols : HashMap(string, *void);
}

LoadExternalSymbol :: (interp : *BytecodeInterpreter, library_name : string, symbol_name : string) -> *void {
    lib := HashMapInsert(*interp.external_libraries, library_name);
    if !lib.handle {
        lib.handle = dlLoadLibrary(CStringClone(library_name));

        if !lib.handle {
            Error("Could not load library '%'", library_name);
            Basic.exit(1);
        }
    }

    symbol := HashMapInsert(*lib.symbols, symbol_name);
    if !symbol.* {
        symbol.* = dlFindSymbol(lib.handle, CStringClone(symbol_name));

        if !symbol.* {
            Error("Could not find symbol '%' in library '%'", symbol_name, library_name);
            Basic.exit(1);
        }
    }

    return symbol.*;
}

// Memory layout of function calls:
// | stack allocated result | stack frame | parameters and registers | function stack |
BytecodeStackFrame :: struct {
    prev : *BytecodeStackFrame;
    func_addr : BytecodeAddress;
    prev_block : u32; // Relative to func_addr
    current_block : u32; // Relative to func_addr
    register_base_pointer : u64;
    stack_pointer : u64;
    instruction_pointer : u64;
    return_value_addr : u64;
    return_value_stack_size : u64;
    return_value_register_index : u32;
    num_registers : u32;
    source_line : u32;
    source_file_id : FileId = -1;
}

MakeBytecodeAddress :: inline (type : BytecodeAddressType, offset : u64) -> BytecodeAddress {
    return (cast(u64, type) << Bytecode_Address_Offset_Bits) | (offset & Bytecode_Address_Offset_Mask);
}

GetAddressOffset :: inline (addr : BytecodeAddress) -> u64 {
    return addr & Bytecode_Address_Offset_Mask;
}

GetAddressType :: inline (addr : BytecodeAddress) -> BytecodeAddressType {
    return cast(BytecodeAddressType, (addr >> Bytecode_Address_Offset_Bits) & Bytecode_Address_Type_Mask);
}

IsDirectAddress :: inline (addr : BytecodeAddress) -> bool {
    return GetAddressType(addr) == .DirectAddress;
}

IsCodeAddress :: inline (addr : BytecodeAddress) -> bool {
    return GetAddressType(addr) == .CodeAddress;
}

IsStackAddress :: inline (addr : BytecodeAddress) -> bool {
    return GetAddressType(addr) == .StackAddress;
}

IsDataAddress :: inline (addr : BytecodeAddress) -> bool {
    return GetAddressType(addr) == .DataAddress;
}

TranslateAddress :: inline (interp : *BytecodeInterpreter, addr : BytecodeAddress) -> *void {
    result : *void;
    if #complete GetAddressType(addr) == {
    case .CodeAddress;
        // It's fine to refer to data right at the end of the block (for zero sized data for example)
        InterpAssert(interp, GetAddressOffset(addr) <= xx interp.code.count, "Code address out of bounds");
        result = interp.code.data + GetAddressOffset(addr);
    case .StackAddress;
        // It's fine to refer to data right at the end of the block (for zero sized data for example)
        InterpAssert(interp, GetAddressOffset(addr) <= xx interp.stack.count, "Stack address out of bounds");
        result = interp.stack.data + GetAddressOffset(addr);
    case .DataAddress;
        // It's fine to refer to data right at the end of the block (for zero sized data for example)
        InterpAssert(interp, GetAddressOffset(addr) <= xx interp.data.count, "Data address out of bounds");
        result = interp.data.data + GetAddressOffset(addr);
    case .DirectAddress;
        result = cast(*void, GetAddressOffset(addr));
    case;
        InterpPanic(interp, "Invalid address type");
    }

    DbgPrintln(.Interpreter, "Translated address % to %", FormatIntHex(addr), FormatIntHex(cast(u64, result)));

    return result;
}

TranslateToCodeAddress :: inline (interp : *BytecodeInterpreter, ptr : *void) -> BytecodeAddress {
    if ptr < interp.code.data || ptr >= interp.code.data + interp.code.count {
        DbgPrintln(.Interpreter, "Could not translate address %", FormatIntHex(cast(u64, ptr)));
        return 0;
    }

    offset := cast(u64, ptr - interp.code.data);
    addr := MakeBytecodeAddress(.CodeAddress, offset);
    DbgPrintln(.Interpreter, "Translated address % to %", FormatIntHex(cast(u64, ptr)), FormatIntHex(addr));

    return addr;
}

BytecodeOpcode :: enum u8 {
    Invalid;

    Add;
    Sub;
    Mul;
    Div;
    Rem;
    UDiv;
    URem;
    Neg;
    Not;
    And;
    Or;
    Xor;
    Shl;
    Shr;
    Sar;

    CmpEq;
    CmpNe;
    CmpFLt;
    CmpFLe;
    CmpFGt;
    CmpFGe;
    CmpSLt;
    CmpSLe;
    CmpSGt;
    CmpSGe;
    CmpULt;
    CmpULe;
    CmpUGt;
    CmpUGe;

    SExtToI16;
    SExtToI32;
    SExtToI64;
    ZExtToI16;
    ZExtToI32;
    ZExtToI64;
    TruncToI32;
    TruncToI16;
    TruncToI8;
    ExtToF64;
    TruncToF32;
    IToF32;
    IToF64;
    UToF32;
    UToF64;
    FToI64;
    FToU64;
    BitCastToI32;
    BitCastToI64;
    BitCastToF32;
    BitCastToF64;

    Alloc4;
    Alloc8;
    Alloc16;
    Load8;
    Load16;
    Load32;
    Load64;
    Store;
    Blit;

    Phi;
    Jmp;
    Jnz;
    Call;
    Ret;

    DbgBrk;
    DbgSetFile;
    DbgSetLine;
}

BytecodeOperandType :: enum u8 {
    Void    :: 0;
    Int8    :: 1;
    Int16   :: 2;
    Int32   :: 3;
    Int64   :: 4;
    Float32 :: 5;
    Float64 :: 6;
    DynCallAggr :: 7;
}

BytecodeOpcodeFlags :: enum_flags u8 {
    // 3 bits
    TypeInt8    :: 0b001;
    TypeInt16   :: 0b010;
    TypeInt32   :: 0b011;
    TypeInt64   :: 0b100;
    TypeFloat32 :: 0b101;
    TypeFloat64 :: 0b110;
    TypeDynCallAggr :: 0b111;
    Types       :: 0b111;
    // 2 bits
    Operand1IsReg :: 0b01_000;
    Operand2IsReg :: 0b10_000;
}

AppendStackTrace :: (builder : *StringBuilder, interp : *BytecodeInterpreter) {
    dummy := interp.stack_frame.*;
    dummy.source_file_id = interp.source_file_id;
    dummy.source_line = interp.source_line;
    dummy.prev = interp.stack_frame;

    curr := *dummy;
    while curr {
        file := GetFile(curr.source_file_id);
        filename := ifx file then ShortenFilename(file.filename) else "???";
        func_name := HashMapGet(*interp.file.address_to_symbol_name, curr.func_addr, "???   ");

        Append(builder, "    %", func_name);
        Func_Name_Length :: 40;
        for i : func_name.count..Func_Name_Length - 1 {
            Append(builder, " ");
        }

        if curr.source_line > 0 {
            Append(builder, " %:%\n", filename, curr.source_line);
        } else {
            Append(builder, " %:???\n", filename);
        }

        curr = curr.prev;
    }
}

AppendAssertFailureOrPanicMessage :: (builder : *StringBuilder, interp : *BytecodeInterpreter, fmt_str : string, args : ..Any) {
    SetColor(builder, .FatalError);
    Append(builder, "Fatal Error: ");
    SetColor(builder, .None);

    Append(builder, fmt_str, ..args);
    Append(builder, "\n");

    if interp.stack_frame {
        func_name := HashMapGet(*interp.file.address_to_symbol_name, interp.stack_frame.func_addr, "<could not find func symbol>");
        Append(builder, "IP: %, SP: %, Func: % (%)\n", FormatIntHex(interp.instruction_pointer), FormatIntHex(interp.stack_pointer), func_name, FormatIntHex(interp.stack_frame.func_addr));
    }

    Append(builder, "\nStack trace of the interpreted program:\n");
    AppendStackTrace(builder, interp);
    Append(builder, "\n");
}

InterpPanic :: (interp : *BytecodeInterpreter, fmt_str : string, args : ..Any, location := #caller_location) {
    if !context.handling_assertion_failure {
        context.handling_assertion_failure = true;
        defer context.handling_assertion_failure = false;

        context.panicking = true;
        defer context.panicking = false;

        builder : StringBuilder;

        AppendAssertFailureOrPanicMessage(*builder, interp, fmt_str, ..args);

        message := StringBuilderBuild(*builder);

        if context.assertion_failed(location, message) {
            debug_break();
        }
    }
}
@PrintLike

InterpAssert :: (interp : *BytecodeInterpreter, assertion : bool, fmt_str : string, args : ..Any, location := #caller_location) -> bool {
    if !assertion && !context.handling_assertion_failure {
        context.handling_assertion_failure = true;
        defer context.handling_assertion_failure = false;

        builder : StringBuilder;

        AppendAssertFailureOrPanicMessage(*builder, interp, fmt_str, ..args);

        message := StringBuilderBuild(*builder);

        if context.assertion_failed(location, message) {
            debug_break();
        }
    }

    return assertion;
}
@PrintLike

GetOperandTypes :: inline (flags : BytecodeOpcodeFlags) -> BytecodeOperandType {
    return xx(flags & .Types);
}

MakeBytecodeOpcodeFlags :: inline (type : IRTypeKind, op1 : IROperand) -> BytecodeOpcodeFlags {
    return MakeBytecodeOpcodeFlags(type, op1, .{});
}

MakeBytecodeOperandType :: inline (type : IRTypeKind) -> BytecodeOperandType {
    if type == {
    case .Void;    return .Void;
    case .Int8;    return .Int8;
    case .Int16;   return .Int16;
    case .Int32;   return .Int32;
    case .Pointer; #through;
    case .Int64;   return .Int64;
    case .Float32; return .Float32;
    case .Float64; return .Float64;
    case;
        Panic("Invalid type %", type);
    }

    return .Void;
}

MakeBytecodeOpcodeFlags :: inline (type : IRTypeKind, op1 : IROperand, op2 : IROperand) -> BytecodeOpcodeFlags {
    flags : BytecodeOpcodeFlags;
    if type == {
    case .Void;
    case .Int8;    flags |= .TypeInt8;
    case .Int16;   flags |= .TypeInt16;
    case .Int32;   flags |= .TypeInt32;
    case .Pointer; #through;
    case .Int64;   flags |= .TypeInt64;
    case .Float32; flags |= .TypeFloat32;
    case .Float64; flags |= .TypeFloat64;
    case;
        Panic("Invalid type %", type);
    }

    if op1.symbol && (op1.symbol.kind == .Temporary || op1.symbol.kind == .Parameter) {
        flags |= .Operand1IsReg;
    }

    if op2.symbol && (op2.symbol.kind == .Temporary || op2.symbol.kind == .Parameter) {
        flags |= .Operand2IsReg;
    }

    return flags;
}

GetOpcode :: inline (interp : *BytecodeInterpreter) -> BytecodeOpcode {
    return GetImmediateOperand(interp, BytecodeOpcode);
}

GetOpcodeFlags :: inline (interp : *BytecodeInterpreter) -> BytecodeOpcodeFlags {
    return GetImmediateOperand(interp, BytecodeOpcodeFlags);
}

GetImmediateOperand :: inline (interp : *BytecodeInterpreter, $T : Type) -> T #no_abc {
    InterpAssert(interp, interp.instruction_pointer + size_of(T) <= cast(u64, interp.code.count), "Invalid instruction encoding (overflow)");
    val := cast(*T, interp.code.data + interp.instruction_pointer).*;
    interp.instruction_pointer += size_of(T);

    return val;
}

GetRegisterOperand :: inline (interp : *BytecodeInterpreter) -> u32 {
    return GetImmediateOperand(interp, u32);
}

LoadRegisterOperand :: inline (interp : *BytecodeInterpreter, $T : Type) -> T #no_abc {
    register := GetRegisterOperand(interp);
    InterpAssert(interp, interp.register_base_pointer + (register + 1) * size_of(u64) <= xx interp.stack.count, "Register stack overflow");
    value := *interp.stack[interp.register_base_pointer + size_of(u64) * register];

    return cast(*T, value).*;
}

GetFirstOperand :: inline (interp : *BytecodeInterpreter, flags : BytecodeOpcodeFlags, $T : Type) -> T {
    result : T = ---;
    if flags & .Operand1IsReg {
        result = LoadRegisterOperand(interp, T);
    } else {
        result = GetImmediateOperand(interp, T);
    }

    #if #run type_info(T).type == .INTEGER {
        DbgPrintln(.Interpreter, "Op1 = % (0x%)", result, FormatIntHex(result));
    } else {
        DbgPrintln(.Interpreter, "Op1 = %", result);
    }

    return result;
}

GetSecondOperand :: inline (interp : *BytecodeInterpreter, flags : BytecodeOpcodeFlags, $T : Type) -> T {
    result : T = ---;
    if flags & .Operand2IsReg {
        result = LoadRegisterOperand(interp, T);
    } else {
        result = GetImmediateOperand(interp, T);
    }

    #if #run type_info(T).type == .INTEGER {
        DbgPrintln(.Interpreter, "Op2 = % (0x%)", result, FormatIntHex(result));
    } else {
        DbgPrintln(.Interpreter, "Op2 = %", result);
    }

    return result;
}

StoreToRegister :: inline (interp : *BytecodeInterpreter, value : $T, register_index : u32) #no_abc {
    #assert size_of(T) <= size_of(u64);

    #if #run type_info(T).type == .INTEGER {
        DbgPrintln(.Interpreter, "r% = % (0x%)", register_index, value, FormatIntHex(value));
    } else {
        DbgPrintln(.Interpreter, "r% = %", register_index, value);
    }
    InterpAssert(interp, register_index < interp.stack_frame.num_registers, "Out of registers");
    InterpAssert(interp, interp.register_base_pointer + (register_index + 1) * size_of(u64) <= xx interp.stack.count, "Register stack overflow");
    cast(*T, *interp.stack[interp.register_base_pointer + register_index * size_of(u64)]).* = value;
}

LoadBytecodeFile :: (interp : *BytecodeInterpreter, name : string, file : *BytecodeFile, stack_size := 1024 * 1024) {
    DbgPrintln(.Interpreter, "Loading bytecode file '%'", name);

    if g_build_settings.debug_log & .Interpreter {
        for addr, name : file.symbol_name_to_address {
            DbgPrintln(.Interpreter, "Symbol '%' -> %", name, FormatIntHex(addr));
        }
    }

    interp.file = file;
    interp.stack = AllocArray(u8, stack_size);
    interp.data = AllocArray(u8, file.data.count);
    interp.code = AllocArray(u8, file.code.count);
    memcpy(interp.data.data, file.data.data, file.data.count);
    memcpy(interp.code.data, file.code.data, file.code.count);

    for file.addresses_to_translate {
        addr := cast(*BytecodeAddress, TranslateAddress(interp, it));
        addr.* = cast(u64, TranslateAddress(interp, addr.*));
    }

    for lib : file.external_libraries {
        for references, sym_name : lib.referenced_symbols {
            sym_ptr := LoadExternalSymbol(interp, lib.library_name, sym_name);

            for references {
                DbgPrintln(.Interpreter, "Lib '%', Sym '%' (%) referenced at %", lib.library_name, sym_name, sym_ptr, FormatIntHex(it));
                ptr := TranslateAddress(interp, it);
                cast(*u64, ptr).* = cast(u64, sym_ptr);
            }
        }
    }

    for file.dyncall_aggregates {
        aggr := dcNewAggr(xx it.fields.count, it.size);

        for field : it.fields {
            InterpAssert(interp, field.offset != 0xffffffff, "Offset is not set");

            if field.nested_aggr_address {
                nested_aggr := cast(**DCaggr, TranslateAddress(interp, field.nested_aggr_address)).*;
                dcAggrField(aggr, field.type, xx field.offset, field.array_length, nested_aggr);
            } else {
                dcAggrField(aggr, field.type, xx field.offset, field.array_length);
            }
        }

        dcCloseAggr(aggr);

        ptr : **DCaggr = TranslateAddress(interp, it.runtime_address);
        ptr.* = aggr;
    }

    interp.dyncall_vm = dcNewCallVM(4096);

    // Create dummy stack frame
    interp.stack_frame = cast(*BytecodeStackFrame, interp.stack.data);
    interp.stack_frame.* = .{};

    interp.stack_pointer += size_of(BytecodeStackFrame);

    interp.stack_frame.num_registers = 1;
    interp.stack_frame.register_base_pointer = interp.stack_pointer;

    interp.stack_pointer += size_of(u64) * interp.stack_frame.num_registers;
}

MakeConstantValueFromInterpreterReturnValue :: (interp : *BytecodeInterpreter, result_type : *YalType, register_index : u32) -> ConstantValue {
    return_value_ptr := *interp.stack[interp.register_base_pointer + size_of(u64) * register_index];
    result : ConstantValue;

    if #complete result_type.kind == {
    case .Invalid;
    case .Void;

    case .Integer;
        result.kind = .Integer;

        int_type := cast(*YalTypeInteger, result_type);
        if int_type.is_signed {
            if int_type.size == {
            case 1; result.int_value = ToS128(cast(*s8,  return_value_ptr).*);
            case 2; result.int_value = ToS128(cast(*s16, return_value_ptr).*);
            case 4; result.int_value = ToS128(cast(*s32, return_value_ptr).*);
            case 8; result.int_value = ToS128(cast(*s64, return_value_ptr).*);
            }
        } else {
            if int_type.size == {
            case 1; result.int_value = ToS128(cast(*u8,  return_value_ptr).*);
            case 2; result.int_value = ToS128(cast(*u16, return_value_ptr).*);
            case 4; result.int_value = ToS128(cast(*u32, return_value_ptr).*);
            case 8; result.int_value = ToS128(cast(*u64, return_value_ptr).*);
            }
        }

    case .Float;
        result.kind = .Float;

        if result_type.size == 4 {
            result.float_value = cast(*float, return_value_ptr).*;
        } else {
            result.float_value = cast(*float64, return_value_ptr).*;
        }

    case .Bool;
        result.kind = .Boolean;
        result.bool_value = cast(*bool, return_value_ptr).*;

    case .Enum;
        enum_type := cast(*YalTypeEnum, result_type);
        return MakeConstantValueFromInterpreterReturnValue(interp, enum_type.base_type, register_index);

    case .String;
        result.kind = .String;

        addr := cast(*BytecodeAddress, return_value_ptr).*;
        result.string_value = cast(*string, TranslateAddress(interp, addr)).*;

    case .Module; #through;
    case .TypeId; #through;
    case .Function; #through;
    case .FunctionOverloadSet; #through;
    case .Array; #through;
    case .Struct; #through;
    case .Pointer; #through;
    case .TemplateParam;
        Panic("Type % is not handled for compile time execution return value", ToString(result_type));

    }

    return result;
}

YalAllocator :: struct {
    Operation :: enum {
        Allocate;
        Reallocate;
        Free;
    }

    Callback :: #type (data : *void, op : Operation, ptr : *void, size : s64, old_size : s64) -> *void;

    data : *void;
    callback : Callback;
} @Preload

YalLogger :: struct {
    Callback :: #type (data : *void, message : string);

    data : *void;
    callback : Callback;
} @Preload

YalPanicHandler :: struct {
    Callback :: #type (data : *void, assertion_failure : bool, message : string);

    data : *void;
    callback : Callback;
} @Preload

YalContext :: struct {
    thread_id : u32;
    allocator : YalAllocator;
    temp_allocator : YalAllocator;
    logger : YalLogger;
    panic_handler : YalPanicHandler;
    handling_panic : bool;
} @Preload

RunFunction :: (interp : *BytecodeInterpreter, name : string, result_type : *YalType) -> ConstantValue {
    DbgPrintln(.Interpreter, "Running function %", name);

    func_address, found_func := HashMapGet(*interp.file.symbol_name_to_address, name);
    InterpAssert(interp, found_func, "Could not find entry point function in symbol address table");
    DbgPrintln(.Interpreter, "Function address: %", FormatIntHex(func_address));

    yal_context : YalContext;

    call : BytecodeFunctionCall;
    call.address = func_address;
    call.num_registers = 1000;
    call.num_parameters = 1;

    if result_type.kind == {
    case .String; #through;
    case .Array; #through;
    case .Struct;
        call.result_stack_size = xx result_type.size;
    }

    call.result_register_index = 0;
    CallYalFunction(interp, call);

    StoreToRegister(interp, cast(u64, *yal_context), 0);

    while interp.stack_frame.func_addr != 0 {
        InterpretNextInstruction(interp);
    }

    return MakeConstantValueFromInterpreterReturnValue(interp, result_type, call.result_register_index);
}

InterpretNextInstruction :: (interp : *BytecodeInterpreter) {
    ip := interp.instruction_pointer;
    opcode := GetOpcode(interp);

    if g_build_settings.debug_log & .Interpreter {
        SetOutputColor(.Info, false);
        DbgPrintln(.Interpreter, "IP: %, OP: %", FormatIntHex(ip), opcode);
        SetOutputColor(.None, false);
    }

    #insert -> string {
        builder : StringBuilder;

        Append(*builder, "if #complete opcode ==\n{\n");
        for type_info(BytecodeOpcode).names {
            Append(*builder, "case .%1; Interp%1(interp);\n", it);
        }
        Append(*builder, "case; Panic(\"Corrupt instruction stream\");\n");
        Append(*builder, "}\n");

        return StringBuilderBuild(*builder);
    }
}

InterpInvalid :: (interp : *BytecodeInterpreter) {
    InterpPanic(interp, "Invalid instruction opcode");
}

InterpAdd :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, u8) + GetSecondOperand(interp, flags, u8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, u16) + GetSecondOperand(interp, flags, u16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, u32) + GetSecondOperand(interp, flags, u32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, u64) + GetSecondOperand(interp, flags, u64);
        StoreToRegister(interp, result, register_index);
    case .Float32;
        result := GetFirstOperand(interp, flags, float32) + GetSecondOperand(interp, flags, float32);
        StoreToRegister(interp, result, register_index);
    case .Float64;
        result := GetFirstOperand(interp, flags, float64) + GetSecondOperand(interp, flags, float64);
        StoreToRegister(interp, result, register_index);
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for add");
    }
}

InterpSub :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, u8) - GetSecondOperand(interp, flags, u8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, u16) - GetSecondOperand(interp, flags, u16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, u32) - GetSecondOperand(interp, flags, u32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, u64) - GetSecondOperand(interp, flags, u64);
        StoreToRegister(interp, result, register_index);
    case .Float32;
        result := GetFirstOperand(interp, flags, float32) - GetSecondOperand(interp, flags, float32);
        StoreToRegister(interp, result, register_index);
    case .Float64;
        result := GetFirstOperand(interp, flags, float64) - GetSecondOperand(interp, flags, float64);
        StoreToRegister(interp, result, register_index);
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for sub");
    }
}

InterpMul :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, u8) * GetSecondOperand(interp, flags, u8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, u16) * GetSecondOperand(interp, flags, u16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, u32) * GetSecondOperand(interp, flags, u32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, u64) * GetSecondOperand(interp, flags, u64);
        StoreToRegister(interp, result, register_index);
    case .Float32;
        result := GetFirstOperand(interp, flags, float32) * GetSecondOperand(interp, flags, float32);
        StoreToRegister(interp, result, register_index);
    case .Float64;
        result := GetFirstOperand(interp, flags, float64) * GetSecondOperand(interp, flags, float64);
        StoreToRegister(interp, result, register_index);
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for mul");
    }
}

InterpDiv :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, u8) / GetSecondOperand(interp, flags, u8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, u16) / GetSecondOperand(interp, flags, u16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, u32) / GetSecondOperand(interp, flags, u32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, u64) / GetSecondOperand(interp, flags, u64);
        StoreToRegister(interp, result, register_index);
    case .Float32;
        result := GetFirstOperand(interp, flags, float32) / GetSecondOperand(interp, flags, float32);
        StoreToRegister(interp, result, register_index);
    case .Float64;
        result := GetFirstOperand(interp, flags, float64) / GetSecondOperand(interp, flags, float64);
        StoreToRegister(interp, result, register_index);
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for div");
    }
}

InterpRem :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, u8) % GetSecondOperand(interp, flags, u8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, u16) % GetSecondOperand(interp, flags, u16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, u32) % GetSecondOperand(interp, flags, u32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, u64) % GetSecondOperand(interp, flags, u64);
        StoreToRegister(interp, result, register_index);
    case .Float32; #through;
    case .Float64; #through;
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for rem");
    }
}

InterpUDiv :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, u8) / GetSecondOperand(interp, flags, u8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, u16) / GetSecondOperand(interp, flags, u16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, u32) / GetSecondOperand(interp, flags, u32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, u64) / GetSecondOperand(interp, flags, u64);
        StoreToRegister(interp, result, register_index);
    case .Float32; #through;
    case .Float64; #through;
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for udiv");
    }
}

InterpURem :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, u8) % GetSecondOperand(interp, flags, u8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, u16) % GetSecondOperand(interp, flags, u16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, u32) % GetSecondOperand(interp, flags, u32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, u64) % GetSecondOperand(interp, flags, u64);
        StoreToRegister(interp, result, register_index);
    case .Float32; #through;
    case .Float64; #through;
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for urem");
    }
}

InterpNeg :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := -GetFirstOperand(interp, flags, s8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := -GetFirstOperand(interp, flags, s16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := -GetFirstOperand(interp, flags, s32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := -GetFirstOperand(interp, flags, s64);
        StoreToRegister(interp, result, register_index);
    case .Float32;
        result := -GetFirstOperand(interp, flags, float32);
        StoreToRegister(interp, result, register_index);
    case .Float64;
        result := -GetFirstOperand(interp, flags, float64);
        StoreToRegister(interp, result, register_index);
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for neg");
    }
}

InterpNot :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := ~GetFirstOperand(interp, flags, u8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := ~GetFirstOperand(interp, flags, u16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := ~GetFirstOperand(interp, flags, u32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := ~GetFirstOperand(interp, flags, u64);
        StoreToRegister(interp, result, register_index);
    case .Float32; #through;
    case .Float64; #through;
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for not");
    }
}

InterpAnd :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, u8) & GetSecondOperand(interp, flags, u8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, u16) & GetSecondOperand(interp, flags, u16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, u32) & GetSecondOperand(interp, flags, u32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, u64) & GetSecondOperand(interp, flags, u64);
        StoreToRegister(interp, result, register_index);
    case .Float32; #through;
    case .Float64; #through;
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for and");
    }
}

InterpOr :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, u8) | GetSecondOperand(interp, flags, u8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, u16) | GetSecondOperand(interp, flags, u16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, u32) | GetSecondOperand(interp, flags, u32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, u64) | GetSecondOperand(interp, flags, u64);
        StoreToRegister(interp, result, register_index);
    case .Float32; #through;
    case .Float64; #through;
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for or");
    }
}

InterpXor :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, u8) ^ GetSecondOperand(interp, flags, u8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, u16) ^ GetSecondOperand(interp, flags, u16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, u32) ^ GetSecondOperand(interp, flags, u32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, u64) ^ GetSecondOperand(interp, flags, u64);
        StoreToRegister(interp, result, register_index);
    case .Float32; #through;
    case .Float64; #through;
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for xor");
    }
}

InterpShl :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, u8) << GetSecondOperand(interp, flags, u8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, u16) << GetSecondOperand(interp, flags, u16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, u32) << GetSecondOperand(interp, flags, u32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, u64) << GetSecondOperand(interp, flags, u64);
        StoreToRegister(interp, result, register_index);
    case .Float32; #through;
    case .Float64; #through;
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for shl");
    }
}

InterpShr :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, u8) >> GetSecondOperand(interp, flags, u8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, u16) >> GetSecondOperand(interp, flags, u16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, u32) >> GetSecondOperand(interp, flags, u32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, u64) >> GetSecondOperand(interp, flags, u64);
        StoreToRegister(interp, result, register_index);
    case .Float32; #through;
    case .Float64; #through;
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for shr");
    }
}

InterpSar :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, u8) >>> GetSecondOperand(interp, flags, u8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, u16) >>> GetSecondOperand(interp, flags, u16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, u32) >>> GetSecondOperand(interp, flags, u32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, u64) >>> GetSecondOperand(interp, flags, u64);
        StoreToRegister(interp, result, register_index);
    case .Float32; #through;
    case .Float64; #through;
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for sar");
    }
}


InterpCmpEq :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, u8) == GetSecondOperand(interp, flags, u8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, u16) == GetSecondOperand(interp, flags, u16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, u32) == GetSecondOperand(interp, flags, u32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, u64) == GetSecondOperand(interp, flags, u64);
        StoreToRegister(interp, result, register_index);
    case .Float32;
        result := GetFirstOperand(interp, flags, float32) == GetSecondOperand(interp, flags, float32);
        StoreToRegister(interp, result, register_index);
    case .Float64;
        result := GetFirstOperand(interp, flags, float64) == GetSecondOperand(interp, flags, float64);
        StoreToRegister(interp, result, register_index);
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for cmpeq");
    }
}

InterpCmpNe :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, u8) != GetSecondOperand(interp, flags, u8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, u16) != GetSecondOperand(interp, flags, u16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, u32) != GetSecondOperand(interp, flags, u32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, u64) != GetSecondOperand(interp, flags, u64);
        StoreToRegister(interp, result, register_index);
    case .Float32;
        result := GetFirstOperand(interp, flags, float32) != GetSecondOperand(interp, flags, float32);
        StoreToRegister(interp, result, register_index);
    case .Float64;
        result := GetFirstOperand(interp, flags, float64) != GetSecondOperand(interp, flags, float64);
        StoreToRegister(interp, result, register_index);
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for cmpne");
    }
}

InterpCmpFLt :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Float32;
        result := GetFirstOperand(interp, flags, float32) < GetSecondOperand(interp, flags, float32);
        StoreToRegister(interp, result, register_index);
    case .Float64;
        result := GetFirstOperand(interp, flags, float64) < GetSecondOperand(interp, flags, float64);
        StoreToRegister(interp, result, register_index);
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for cmpflt");
    }
}

InterpCmpFLe :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Float32;
        result := GetFirstOperand(interp, flags, float32) <= GetSecondOperand(interp, flags, float32);
        StoreToRegister(interp, result, register_index);
    case .Float64;
        result := GetFirstOperand(interp, flags, float64) <= GetSecondOperand(interp, flags, float64);
        StoreToRegister(interp, result, register_index);
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for cmpfle");
    }
}

InterpCmpFGt :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Float32;
        result := GetFirstOperand(interp, flags, float32) > GetSecondOperand(interp, flags, float32);
        StoreToRegister(interp, result, register_index);
    case .Float64;
        result := GetFirstOperand(interp, flags, float64) > GetSecondOperand(interp, flags, float64);
        StoreToRegister(interp, result, register_index);
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for cmpfgt");
    }
}

InterpCmpFGe :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Float32;
        result := GetFirstOperand(interp, flags, float32) >= GetSecondOperand(interp, flags, float32);
        StoreToRegister(interp, result, register_index);
    case .Float64;
        result := GetFirstOperand(interp, flags, float64) >= GetSecondOperand(interp, flags, float64);
        StoreToRegister(interp, result, register_index);
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for cmpfge");
    }
}

InterpCmpSLt :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, s8) < GetSecondOperand(interp, flags, s8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, s16) < GetSecondOperand(interp, flags, s16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, s32) < GetSecondOperand(interp, flags, s32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, s64) < GetSecondOperand(interp, flags, s64);
        StoreToRegister(interp, result, register_index);
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for cmpslt");
    }
}

InterpCmpSLe :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, s8) <= GetSecondOperand(interp, flags, s8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, s16) <= GetSecondOperand(interp, flags, s16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, s32) <= GetSecondOperand(interp, flags, s32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, s64) <= GetSecondOperand(interp, flags, s64);
        StoreToRegister(interp, result, register_index);
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for cmpsle");
    }
}

InterpCmpSGt :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, s8) > GetSecondOperand(interp, flags, s8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, s16) > GetSecondOperand(interp, flags, s16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, s32) > GetSecondOperand(interp, flags, s32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, s64) > GetSecondOperand(interp, flags, s64);
        StoreToRegister(interp, result, register_index);
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for cmpsgt");
    }
}

InterpCmpSGe :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, s8) >= GetSecondOperand(interp, flags, s8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, s16) >= GetSecondOperand(interp, flags, s16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, s32) >= GetSecondOperand(interp, flags, s32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, s64) >= GetSecondOperand(interp, flags, s64);
        StoreToRegister(interp, result, register_index);
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for cmpsge");
    }
}

InterpCmpULt :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, u8) < GetSecondOperand(interp, flags, u8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, u16) < GetSecondOperand(interp, flags, u16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, u32) < GetSecondOperand(interp, flags, u32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, u64) < GetSecondOperand(interp, flags, u64);
        StoreToRegister(interp, result, register_index);
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for cmpult");
    }
}

InterpCmpULe :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, u8) <= GetSecondOperand(interp, flags, u8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, u16) <= GetSecondOperand(interp, flags, u16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, u32) <= GetSecondOperand(interp, flags, u32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, u64) <= GetSecondOperand(interp, flags, u64);
        StoreToRegister(interp, result, register_index);
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for cmpule");
    }
}

InterpCmpUGt :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, u8) > GetSecondOperand(interp, flags, u8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, u16) > GetSecondOperand(interp, flags, u16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, u32) > GetSecondOperand(interp, flags, u32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, u64) > GetSecondOperand(interp, flags, u64);
        StoreToRegister(interp, result, register_index);
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for cmpugt");
    }
}

InterpCmpUGe :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := GetFirstOperand(interp, flags, u8) >= GetSecondOperand(interp, flags, u8);
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := GetFirstOperand(interp, flags, u16) >= GetSecondOperand(interp, flags, u16);
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := GetFirstOperand(interp, flags, u32) >= GetSecondOperand(interp, flags, u32);
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := GetFirstOperand(interp, flags, u64) >= GetSecondOperand(interp, flags, u64);
        StoreToRegister(interp, result, register_index);
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for cmpuge");
    }
}

InterpSignedCast :: (interp : *BytecodeInterpreter, $T : Type) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := cast(T, GetFirstOperand(interp, flags, s8));
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := cast(T, GetFirstOperand(interp, flags, s16));
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := cast(T, GetFirstOperand(interp, flags, s32));
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := cast(T, GetFirstOperand(interp, flags, s64));
        StoreToRegister(interp, result, register_index);
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for signed integer cast");
    }
}

InterpUnsignedCast :: (interp : *BytecodeInterpreter, $T : Type) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Int8;
        result := cast(T, GetFirstOperand(interp, flags, u8));
        StoreToRegister(interp, result, register_index);
    case .Int16;
        result := cast(T, GetFirstOperand(interp, flags, u16));
        StoreToRegister(interp, result, register_index);
    case .Int32;
        result := cast(T, GetFirstOperand(interp, flags, u32));
        StoreToRegister(interp, result, register_index);
    case .Int64;
        result := cast(T, GetFirstOperand(interp, flags, u64));
        StoreToRegister(interp, result, register_index);
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for unsigned integer cast");
    }
}

InterpSExtToI16 :: (interp : *BytecodeInterpreter) {
    InterpSignedCast(interp, s16);
}

InterpSExtToI32 :: (interp : *BytecodeInterpreter) {
    InterpSignedCast(interp, s32);
}

InterpSExtToI64 :: (interp : *BytecodeInterpreter) {
    InterpSignedCast(interp, s64);
}

InterpZExtToI16 :: (interp : *BytecodeInterpreter) {
    InterpUnsignedCast(interp, u16);
}

InterpZExtToI32 :: (interp : *BytecodeInterpreter) {
    InterpUnsignedCast(interp, u32);
}

InterpZExtToI64 :: (interp : *BytecodeInterpreter) {
    InterpUnsignedCast(interp, u64);
}

InterpTruncToI32 :: (interp : *BytecodeInterpreter) {
    InterpUnsignedCast(interp, u32);
}

InterpTruncToI16 :: (interp : *BytecodeInterpreter) {
    InterpUnsignedCast(interp, u16);
}

InterpTruncToI8 :: (interp : *BytecodeInterpreter) {
    InterpUnsignedCast(interp, u8);
}

InterpFloatCast :: (interp : *BytecodeInterpreter, $T : Type) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    if GetOperandTypes(flags) == {
    case .Float32;
        result := cast(T, GetFirstOperand(interp, flags, float32));
        StoreToRegister(interp, result, register_index);
    case .Float64;
        result := cast(T, GetFirstOperand(interp, flags, float64));
        StoreToRegister(interp, result, register_index);
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for trunctof32");
    }
}

InterpExtToF64 :: inline (interp : *BytecodeInterpreter) {
    InterpFloatCast(interp, float64);
}

InterpTruncToF32 :: inline (interp : *BytecodeInterpreter) {
    InterpFloatCast(interp, float32);
}

InterpIToF32 :: inline (interp : *BytecodeInterpreter) {
    InterpSignedCast(interp, float32);
}

InterpIToF64 :: inline (interp : *BytecodeInterpreter) {
    InterpSignedCast(interp, float64);
}

InterpUToF32 :: inline (interp : *BytecodeInterpreter) {
    InterpUnsignedCast(interp, float32);
}

InterpUToF64 :: inline (interp : *BytecodeInterpreter) {
    InterpUnsignedCast(interp, float64);
}

InterpFToI64 :: inline (interp : *BytecodeInterpreter) {
    InterpFloatCast(interp, s64);
}

InterpFToU64 :: inline (interp : *BytecodeInterpreter) {
    InterpFloatCast(interp, u64);
}

InterpBitCast :: (interp : *BytecodeInterpreter, $T : Type) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    result := GetFirstOperand(interp, flags, T);
    StoreToRegister(interp, result, register_index);
}

InterpBitCastToI32 :: inline (interp : *BytecodeInterpreter) {
    InterpBitCast(interp, u32);
}

InterpBitCastToI64 :: inline (interp : *BytecodeInterpreter) {
    InterpBitCast(interp, u64);
}

InterpBitCastToF32 :: inline (interp : *BytecodeInterpreter) {
    InterpBitCast(interp, float32);
}

InterpBitCastToF64 :: inline (interp : *BytecodeInterpreter) {
    InterpBitCast(interp, float64);
}

InterpAlloc :: inline (interp : *BytecodeInterpreter, $align : int) #no_abc {
    register_index := GetImmediateOperand(interp, u32);
    size := GetImmediateOperand(interp, u64);
    interp.stack_pointer = AlignForward(interp.stack_pointer, align);
    InterpAssert(interp, interp.stack_pointer < xx interp.stack.count, "Stack overflow");
    addr := cast(u64, *interp.stack[interp.stack_pointer]);
    interp.stack_pointer += size;

    DbgPrintln(.Interpreter, "r% = Alloc% %", register_index, align, FormatIntHex(addr));

    StoreToRegister(interp, addr, register_index);
}

InterpAlloc4 :: (interp : *BytecodeInterpreter) {
    InterpAlloc(interp, 4);
}

InterpAlloc8 :: (interp : *BytecodeInterpreter) {
    InterpAlloc(interp, 8);
}

InterpAlloc16 :: (interp : *BytecodeInterpreter) {
    InterpAlloc(interp, 16);
}

InterpLoad :: inline (interp : *BytecodeInterpreter, $T : Type) {
    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    addr := GetFirstOperand(interp, flags, BytecodeAddress);
    ptr := TranslateAddress(interp, addr);
    InterpAssert(interp, ptr != null, "Loading from null pointer");

    value := cast(*T, ptr).*;
    StoreToRegister(interp, value, register_index);
}

InterpLoad8 :: (interp : *BytecodeInterpreter) {
    InterpLoad(interp, u8);
}

InterpLoad16 :: (interp : *BytecodeInterpreter) {
    InterpLoad(interp, u16);
}

InterpLoad32 :: (interp : *BytecodeInterpreter) {
    InterpLoad(interp, u32);
}

InterpLoad64 :: (interp : *BytecodeInterpreter) {
    InterpLoad(interp, u64);
}

InterpStore :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    if GetOperandTypes(flags) == {
    case .Int8;
        value := GetFirstOperand(interp, flags, u8);
        addr := GetSecondOperand(interp, flags, BytecodeAddress);
        ptr := TranslateAddress(interp, addr);
        DbgPrintln(.Interpreter, "Store % (%) to %", value, GetOperandTypes(flags), FormatIntHex(cast(u64, ptr)));
        cast(*u8, ptr).* = value;

    case .Int16;
        value := GetFirstOperand(interp, flags, u16);
        addr := GetSecondOperand(interp, flags, BytecodeAddress);
        ptr := TranslateAddress(interp, addr);
        DbgPrintln(.Interpreter, "Store % (%) to %", value, GetOperandTypes(flags), FormatIntHex(cast(u64, ptr)));
        cast(*u16, ptr).* = value;

    case .Int32; #through;
    case .Float32;
        value := GetFirstOperand(interp, flags, u32);
        addr := GetSecondOperand(interp, flags, BytecodeAddress);
        ptr := TranslateAddress(interp, addr);
        DbgPrintln(.Interpreter, "Store % (%) to %", value, GetOperandTypes(flags), FormatIntHex(cast(u64, ptr)));
        cast(*u32, ptr).* = value;

    case .Int64; #through;
    case .Float64;
        value := GetFirstOperand(interp, flags, u64);
        addr := GetSecondOperand(interp, flags, BytecodeAddress);
        ptr := TranslateAddress(interp, addr);
        DbgPrintln(.Interpreter, "Store % (%) to %", value, GetOperandTypes(flags), FormatIntHex(cast(u64, ptr)));
        cast(*u64, ptr).* = value;

    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for store");
    }
}

InterpBlit :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    src_addr := GetFirstOperand(interp, flags, BytecodeAddress);
    dst_addr := GetSecondOperand(interp, flags, BytecodeAddress);
    size := GetImmediateOperand(interp, u64);
    src := TranslateAddress(interp, src_addr);
    dst := TranslateAddress(interp, dst_addr);
    memcpy(dst, src, xx size);
}

InterpPhi :: (interp : *BytecodeInterpreter) {
    Helper :: ($T : Type) #expand {
        value := GetSecondOperand(`interp, `op_flags, T);
        if `addr == `prev_block_addr {
            StoreToRegister(`interp, value, `register_index);
            `found = true;
        }
    }

    flags := GetOpcodeFlags(interp);
    register_index := GetImmediateOperand(interp, u32);
    num_values := cast(int, GetImmediateOperand(interp, u8));

    prev_block_addr := interp.stack_frame.func_addr + interp.stack_frame.prev_block;
    found := false;
    for i : 0..num_values - 1 {
        op_flags := GetOpcodeFlags(interp);
        addr := GetFirstOperand(interp, op_flags, BytecodeAddress);
        if GetOperandTypes(flags) == {
        case .Int8;
            Helper(u8);
        case .Int16;
            Helper(u16);
        case .Int32;
            Helper(u32);
        case .Int64;
            Helper(u64);
        case .Float32;
            Helper(float32);
        case .Float64;
            Helper(float64);
        case;
            InterpPanic(interp, "Invalid type or corrupt encoding for phi");
        }
    }

    if !found {
        InterpPanic(interp, "Phi instruction interpretation failed");
    }
}

UpdateBlock :: inline (interp : *BytecodeInterpreter) {
    interp.stack_frame.prev_block = interp.stack_frame.current_block;
    interp.stack_frame.current_block = xx (interp.instruction_pointer - GetAddressOffset(interp.stack_frame.func_addr));
}

InterpJmp :: (interp : *BytecodeInterpreter) {
    addr := GetImmediateOperand(interp, BytecodeAddress);
    InterpAssert(interp, IsCodeAddress(addr), "Jump address is not a code address");

    DbgPrintln(.Interpreter, "Jmp %", FormatIntHex(addr));
    interp.instruction_pointer = xx GetAddressOffset(addr);

    UpdateBlock(interp);
}

InterpJnz :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);
    is_zero : bool;
    if GetOperandTypes(flags) == {
    case .Int8;
        is_zero = GetFirstOperand(interp, flags, u8) == 0;
    case .Int16;
        is_zero = GetFirstOperand(interp, flags, u16) == 0;
    case .Int32;
        is_zero = GetFirstOperand(interp, flags, u32) == 0;
    case .Int64;
        is_zero = GetFirstOperand(interp, flags, u64) == 0;
    case .Float32;
        is_zero = GetFirstOperand(interp, flags, float32) == 0;
    case .Float64;
        is_zero = GetFirstOperand(interp, flags, float64) == 0;
    case;
        InterpPanic(interp, "Invalid types or corrupt encoding for jnz");
    }

    if_true := GetImmediateOperand(interp, BytecodeAddress);
    if_false := GetImmediateOperand(interp, BytecodeAddress);
    InterpAssert(interp, IsCodeAddress(if_true), "Jump address is not a code address");
    InterpAssert(interp, IsCodeAddress(if_false), "Jump address is not a code address");

    if is_zero {
        DbgPrintln(.Interpreter, "Jnz %", FormatIntHex(if_false));
        interp.instruction_pointer = xx GetAddressOffset(if_false);
    } else {
        DbgPrintln(.Interpreter, "Jnz %", FormatIntHex(if_true));
        interp.instruction_pointer = xx GetAddressOffset(if_true);
    }

    UpdateBlock(interp);
}

BytecodeFunctionCall :: struct {
    address : BytecodeAddress;
    num_registers : u32;
    result_type : BytecodeOperandType;
    result_stack_size : u32;
    num_parameters : u8;
    result_register_index : u32;
    first_c_variadic_argument_index := -1;
    calling_convention := CallingConvention.Yal;
}

CallYalFunction :: (interp : *BytecodeInterpreter, call : BytecodeFunctionCall) {
    InterpAssert(interp, call.calling_convention == .Yal, "Not a Yal function");

    callee_addr := call.address;
    if !IsCodeAddress(callee_addr) {
        ptr := TranslateAddress(interp, callee_addr);
        callee_addr = TranslateToCodeAddress(interp, ptr);
        InterpAssert(interp, callee_addr != 0, "Invalid Yal function address %", FormatIntHex(callee_addr));
    }

    InterpAssert(interp, callee_addr != 0, "Calling null Yal function");

    total_stack_size := size_of(BytecodeStackFrame)
        + call.result_stack_size + 16
        + call.num_registers * size_of(u64);
    InterpAssert(interp, interp.stack_pointer + total_stack_size < xx interp.stack.count, "Stack overflow");

    result_addr : u64;
    if call.result_stack_size > 0 {
        interp.stack_pointer = AlignForward(interp.stack_pointer, 16);
        result_addr = MakeBytecodeAddress(.StackAddress, interp.stack_pointer);
        interp.stack_pointer += call.result_stack_size;
    }

    stack_pointer := AlignForward(interp.stack_pointer, 8);
    stack_frame := cast(*BytecodeStackFrame, *interp.stack[stack_pointer]);
    stack_frame.* = .{};
    stack_frame.num_registers = call.num_registers;
    stack_frame.source_file_id = interp.source_file_id;
    stack_frame.source_line = interp.source_line;
    stack_frame.func_addr = callee_addr;

    if call.result_stack_size > 0 {
        stack_frame.return_value_addr = result_addr;
        stack_frame.return_value_stack_size = call.result_stack_size;
    }

    stack_frame.return_value_register_index = call.result_register_index;

    stack_pointer += size_of(BytecodeStackFrame);

    stack_frame.register_base_pointer = stack_pointer;
    stack_pointer += size_of(u64) * call.num_registers;

    stack_frame.stack_pointer = stack_pointer;
    stack_frame.instruction_pointer = GetAddressOffset(callee_addr);

    stack_frame.prev = interp.stack_frame;
    interp.stack_frame = stack_frame;

    // Arguments are put in order into registers by the caller
}

CallCFunction :: (interp : *BytecodeInterpreter, call : BytecodeFunctionCall) {
    InterpAssert(interp, call.calling_convention == .C, "Not a C function");

    if call.first_c_variadic_argument_index >= 0 {
        dcMode(interp.dyncall_vm, DC_CALL_C_ELLIPSIS);
    } else {
        dcMode(interp.dyncall_vm, DC_CALL_C_DEFAULT);
    }

    dcReset(interp.dyncall_vm);

    result_addr : u64;
    result_aggr : *DCaggr;
    if call.result_type == .DynCallAggr {
        interp.stack_pointer = AlignForward(interp.stack_pointer, 16);
        result_addr = MakeBytecodeAddress(.StackAddress, interp.stack_pointer);
        interp.stack_pointer += call.result_stack_size;

        result_aggr_ptr := TranslateAddress(interp, GetImmediateOperand(interp, BytecodeAddress));
        InterpAssert(interp, result_aggr_ptr != null, "DynCall aggregate info is null");

        result_aggr = cast(**DCaggr, result_aggr_ptr).*;
        InterpAssert(interp, result_aggr != null, "DynCall aggregate info is null");

        dcBeginCallAggr(interp.dyncall_vm, result_aggr);
    }

    if call.num_parameters > 0 {
        for i : 0..call.num_parameters - 1 {
            if i == call.first_c_variadic_argument_index {
                dcMode(interp.dyncall_vm, DC_CALL_C_ELLIPSIS_VARARGS);
            }
            arg_flags := GetImmediateOperand(interp, BytecodeOpcodeFlags);

            if GetOperandTypes(arg_flags) == {
            case .Int8;
                arg := GetFirstOperand(interp, arg_flags, u8);
                dcArgChar(interp.dyncall_vm, xx,no_check arg);
            case .Int16;
                arg := GetFirstOperand(interp, arg_flags, u16);
                dcArgShort(interp.dyncall_vm, xx,no_check arg);
            case .Int32;
                arg := GetFirstOperand(interp, arg_flags, u32);
                dcArgInt(interp.dyncall_vm, xx,no_check arg);
            case .Int64;
                arg := GetFirstOperand(interp, arg_flags, u64);
                dcArgLongLong(interp.dyncall_vm, xx,no_check arg);
            case .Float32;
                arg := GetFirstOperand(interp, arg_flags, float32);
                dcArgFloat(interp.dyncall_vm, arg);
            case .Float64;
                arg := GetFirstOperand(interp, arg_flags, float64);
                dcArgDouble(interp.dyncall_vm, arg);
            case .DynCallAggr;
                arg := GetFirstOperand(interp, arg_flags, u64);

                aggr_ptr := TranslateAddress(interp, GetImmediateOperand(interp, BytecodeAddress));
                InterpAssert(interp, aggr_ptr != null, "DynCall aggregate info is null");

                aggr := cast(**DCaggr, aggr_ptr).*;
                InterpAssert(interp, aggr != null, "DynCall aggregate info is null");

                dcArgAggr(interp.dyncall_vm, aggr, cast(*void, arg));
            case;
                InterpPanic(interp, "Invalid or corrupt encoding for external call");
            }
        }
    }

    ptr := TranslateAddress(interp, call.address);
    InterpAssert(interp, ptr != null, "Calling null C function");
    if call.result_type == {
    case .Void;
        dcCallVoid(interp.dyncall_vm, ptr);
    case .Int8;
        result := dcCallChar(interp.dyncall_vm, ptr);
        StoreToRegister(interp, result, call.result_register_index);
    case .Int16;
        result := dcCallShort(interp.dyncall_vm, ptr);
        StoreToRegister(interp, result, call.result_register_index);
    case .Int32;
        result := dcCallInt(interp.dyncall_vm, ptr);
        StoreToRegister(interp, result, call.result_register_index);
    case .Int64;
        result := dcCallLongLong(interp.dyncall_vm, ptr);
        StoreToRegister(interp, result, call.result_register_index);
    case .Float32;
        result := dcCallFloat(interp.dyncall_vm, ptr);
        StoreToRegister(interp, result, call.result_register_index);
    case .Float64;
        result := dcCallDouble(interp.dyncall_vm, ptr);
        StoreToRegister(interp, result, call.result_register_index);
    case .DynCallAggr;
        InterpAssert(interp, result_aggr != null, "Invalid or corrupt encoding for C call (aggregate result description is null)");
        result_ptr := TranslateAddress(interp, result_addr);
        result := dcCallAggr(interp.dyncall_vm, ptr, result_aggr, result_ptr);
        StoreToRegister(interp, result, call.result_register_index);
    case;
        InterpPanic(interp, "Invalid or corrupt encoding for C call");
    }
}

InterpCall :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);

    call : BytecodeFunctionCall;
    call.result_register_index = GetImmediateOperand(interp, u32);
    call.address = GetFirstOperand(interp, flags, BytecodeAddress);
    call.calling_convention = GetImmediateOperand(interp, CallingConvention);

    if call.calling_convention == .C {
        call.first_c_variadic_argument_index = cast(s64, GetImmediateOperand(interp, u8)) - 1;
    }

    call.result_type = GetImmediateOperand(interp, BytecodeOperandType);
    call.result_stack_size = GetImmediateOperand(interp, u32);
    call.num_parameters = GetImmediateOperand(interp, u8);
    call.num_registers = 2000;

    if g_build_settings.debug_log & .Interpreter {
        name := HashMapGet(*interp.file.address_to_symbol_name, call.address, "<could not find func symbol>");
        DbgPrintln(.Interpreter, "Call %, %, conv=%", name, FormatIntHex(call.address), call.calling_convention);
    }

    if call.calling_convention == .C {
        CallCFunction(interp, call);
        return;
    }

    // Hugh... We need this because we want to get all the arguments before actually performing the call, because
    // we need the instruction pointer to be at the correct position (which it isn't anymore when we've performed
    // the call).
    argument_registers : [255]u64 = ---;

    if call.num_parameters > 0 {
        for i : 0..call.num_parameters - 1 {
            arg_flags := GetImmediateOperand(interp, BytecodeOpcodeFlags);

            if GetOperandTypes(arg_flags) == {
            case .Int8;
                cast(*u8, *argument_registers[i]).* = GetFirstOperand(interp, arg_flags, u8);
            case .Int16;
                cast(*u16, *argument_registers[i]).* = GetFirstOperand(interp, arg_flags, u16);
            case .Int32;
                cast(*u32, *argument_registers[i]).* = GetFirstOperand(interp, arg_flags, u32);
            case .Int64;
                cast(*u64, *argument_registers[i]).* = GetFirstOperand(interp, arg_flags, u64);
            case .Float32;
                cast(*float32, *argument_registers[i]).* = GetFirstOperand(interp, arg_flags, float32);
            case .Float64;
                cast(*float64, *argument_registers[i]).* = GetFirstOperand(interp, arg_flags, float64);
            case;
                InterpPanic(interp, "Invalid operand type % for function call argument %", GetOperandTypes(arg_flags), i);
            }
        }
    }

    CallYalFunction(interp, call);

    if call.num_parameters > 0 {
        for i : 0..call.num_parameters - 1 {
            StoreToRegister(interp, argument_registers[i], xx i);
        }
    }
}

InterpRet :: (interp : *BytecodeInterpreter) {
    flags := GetOpcodeFlags(interp);

    return_value_register_index := interp.stack_frame.return_value_register_index;
    if interp.stack_frame.return_value_stack_size > 0 {
        InterpAssert(interp, GetOperandTypes(flags) == .Int64, "Invalid operand type % for ret (return_value_stack_size is %)", GetOperandTypes(flags), interp.stack_frame.return_value_stack_size);
        addr := GetFirstOperand(interp, flags, BytecodeAddress);
        src := TranslateAddress(interp, addr);
        dst := TranslateAddress(interp, interp.stack_frame.return_value_addr);
        memcpy(dst, src, xx interp.stack_frame.return_value_stack_size);

        return_value_addr := interp.stack_frame.return_value_addr;
        interp.source_file_id = interp.stack_frame.source_file_id;
        interp.source_line = interp.stack_frame.source_line;
        interp.stack_frame = interp.stack_frame.prev;
        StoreToRegister(interp, return_value_addr, return_value_register_index);
    } else if GetOperandTypes(flags) == {
    case .Int8;
        value := GetFirstOperand(interp, flags, u8);
        interp.source_file_id = interp.stack_frame.source_file_id;
        interp.source_line = interp.stack_frame.source_line;
        interp.stack_frame = interp.stack_frame.prev;
        StoreToRegister(interp, value, return_value_register_index);
    case .Int16;
        value := GetFirstOperand(interp, flags, u16);
        interp.source_file_id = interp.stack_frame.source_file_id;
        interp.source_line = interp.stack_frame.source_line;
        interp.stack_frame = interp.stack_frame.prev;
        StoreToRegister(interp, value, return_value_register_index);
    case .Int32; #through;
    case .Float32;
        value := GetFirstOperand(interp, flags, u32);
        interp.source_file_id = interp.stack_frame.source_file_id;
        interp.source_line = interp.stack_frame.source_line;
        interp.stack_frame = interp.stack_frame.prev;
        StoreToRegister(interp, value, return_value_register_index);
    case .Int64; #through;
    case .Float64;
        value := GetFirstOperand(interp, flags, u64);
        interp.source_file_id = interp.stack_frame.source_file_id;
        interp.source_line = interp.stack_frame.source_line;
        interp.stack_frame = interp.stack_frame.prev;
        StoreToRegister(interp, value, return_value_register_index);
    case;
        interp.source_file_id = interp.stack_frame.source_file_id;
        interp.source_line = interp.stack_frame.source_line;
        interp.stack_frame = interp.stack_frame.prev;
    }
}

InterpDbgBrk :: (interp : *BytecodeInterpreter) {
    builder : StringBuilder;
    AppendAssertFailureOrPanicMessage(*builder, interp, "Breakpoint");
    Basic.write_builder(*builder, to_standard_error=true);
    Basic.exit(1); // Exit 1 because the test suite treats error codes != 1 as crashes
    // debug_break();
}

InterpDbgSetFile :: (interp : *BytecodeInterpreter) {
    file_id := cast,no_check(FileId, GetImmediateOperand(interp, u32));
    interp.source_file_id = file_id;
}

InterpDbgSetLine :: (interp : *BytecodeInterpreter) {
    line := GetImmediateOperand(interp, u32);
    interp.source_line = line;

    if g_build_settings.debug_log & .Interpreter {
        file := GetFile(interp.source_file_id);
        line := interp.source_line;
        str := GetLine(file.text, cast(int, line) - 1);
        DbgPrint(.Interpreter, "%:%: ", ShortenFilename(file.filename), line);

        SetOutputColor(.SourceCode, false);
        DbgPrintln(.Interpreter, "%", String.trim(str));
        SetOutputColor(.None, false);
    }
}
