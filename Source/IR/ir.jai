#load "instructions.jai";
#load "ir_to_string.jai";
#load "validation.jai";

IRFile :: struct {
    scope : IRScope;

    typedefs : [..]*IRTypedef;
    global_data : [..]*IRGlobalData;
    functions : [..]*IRFunction;
}

IRScope :: struct {
    symbol_suffix_counter : HashMap(string, u32);
    symbols : HashMap(string, *IRSymbol);
}

IRSymbolKind :: enum u8 {
    Invalid;
    GlobalData;
    Typedef;
    Function;
    Parameter;
    Temporary;
    BasicBlock;
}

IRSymbol :: struct {
    enclosing_scope : *IRScope;

    name : string;
    type : IRType;
    kind : IRSymbolKind;
}

IRGlobalDataField :: struct {
    kind : enum {
        String;
        ZeroBytes;
        ConstValue;
        SymbolReference;
    };

    string_value : string;
    num_zero_bytes : int;
    const_type : IRTypeKind;
    const_value : u64;
    referenced_symbol : *IRSymbol;
}

IRGlobalData :: struct {
    #as using,except(kind) symbol : IRSymbol;
    symbol.kind = .GlobalData;
    type = .{kind=.Pointer};

    align : int;
    total_unaligned_size : int;
    fields : [..]IRGlobalDataField;
}

IRAggregateMember :: struct {
    offset : u32 = 0xffffffff;
    type : IRType;
    num_elements := 1;
}

IRTypedef :: struct {
    #as using,except(kind) symbol : IRSymbol;
    symbol.kind = .Typedef;

    align : int;
    size := -1;
    is_union : bool;
    members : []IRAggregateMember;
}

IRFunctionFlags :: enum_flags u8 {
    External;
    CVariadic;
}

IRFunction :: struct {
    #as using,except(kind) symbol : IRSymbol;
    symbol.type = .{kind=.Pointer};
    symbol.kind = .Function;

    scope : IRScope;

    library_name : string;
    result_type : IRType;
    parameters : [..]IRSymbol;
    flags : IRFunctionFlags;
    calling_convention : CallingConvention;
    basic_blocks : [..]*IRBasicBlock;
}

IRBasicBlock :: struct {
    #as using,except(kind) symbol : IRSymbol;
    symbol.kind = .BasicBlock;

    func : *IRFunction;
    instructions : [..]*IRInstr;
}

IRTypeKind :: enum u8 {
    Invalid;

    Void;
    Int8;
    Int16;
    Int32;
    Int64;
    Float32;
    Float64;
    Pointer;
    Typedef;
}

IRType :: struct {
    #as kind : IRTypeKind;
    typedef : *IRTypedef;
}

operator== :: (a : IRType, b : IRType) -> bool {
    return a.kind == b.kind && a.typedef == b.typedef;
}

GetSize :: (type : IRTypeKind) -> int {
    if type == {
    case .Int8;
        return 1;
    case .Int16;
        return 2;
    case .Int32; #through;
    case .Float32;
        return 4;
    case .Pointer; #through;
    case .Typedef; #through;
    case .Int64; #through;
    case .Float64;
        return 8;
    }

    return 0;
}

DecayPointer :: (type : IRType) -> IRType {
    if type.kind == .Typedef {
        return .{kind=.Pointer};
    }

    return type;
}

IsPointer :: (type : IRType) -> bool {
    return type.kind == .Pointer || type.kind == .Typedef;
}

IsInteger :: (type : IRType) -> bool {
    return type.kind == .Int8
        || type.kind == .Int16
        || type.kind == .Int32
        || type.kind == .Int64;
}

IsFloat :: (type : IRType) -> bool {
    return type.kind == .Float32 || type.kind == .Float64;
}

IsTemporary :: (type : IRType) -> bool {
    return IsInteger(type) || IsFloat(type) || type.kind == .Pointer;
}

IROperand :: struct {
    type : IRType;
    #as symbol : *IRSymbol;
    value : u64;
}

IsBasicBlock :: inline (symbol : *IRSymbol) -> bool {
    return symbol != null && symbol.kind == .BasicBlock;
}

IROpSymbol :: inline (symbol : *IRSymbol) -> IROperand {
    return .{type=DecayPointer(symbol.type), symbol=symbol};
}

IROpNullPtr :: inline () -> IROperand {
    return .{type=.{kind=.Pointer}, value=0};
}

IROpU8 :: inline (value : u8) -> IROperand {
    return .{type=.{kind=.Int8}, value=value};
}

IROpU16 :: inline (value : u16) -> IROperand {
    return .{type=.{kind=.Int16}, value=value};
}

IROpU32 :: inline (value : u32) -> IROperand {
    return .{type=.{kind=.Int32}, value=value};
}

IROpU64 :: inline (value : u64) -> IROperand {
    return .{type=.{kind=.Int64}, value=value};
}

IROpF32 :: inline (value : float32) -> IROperand {
    return .{type=.{kind=.Float32}, value=cast(*u32, *value).*};
}

IROpF64 :: inline (value : float64) -> IROperand {
    return .{type=.{kind=.Float64}, value=cast(*u64, *value).*};
}

IRBuilder :: struct {
    file : *IRFile;
    current_func : *IRFunction;
    current_block : *IRBasicBlock;
}

MakeUniqueName :: (scope : *IRScope, name : string, prefix : string) -> string {
    // This function used to be a big bottleneck, so to speed it up we don't use
    // SPrint and we wrote our own WriteU32 that outputs directly to a buffer
    WriteU32 :: (buffer : *u8, value : u32) -> int {
        digits := 0;
        x := value;
        while digits == 0 || x {
            x /= 10;
            digits += 1;
        }

        for < i : 0..digits - 1 {
            c := #char "0" + (value % 10);
            value /= 10;
            buffer[i] = xx c;
        }

        return digits;
    }

    suffixed_name := StringJoin(prefix, name);
    counter_ptr := HashMapInsert(*scope.symbol_suffix_counter, suffixed_name);
    defer counter_ptr.* += 1;

    if counter_ptr.* == 0 {
        return suffixed_name;
    }

    suffix_buffer : [12]u8 = ---;
    suffix_str := string.{data=suffix_buffer.data};
    suffix_str.count = WriteU32(suffix_buffer.data, counter_ptr.*);
    suffixed_name = StringJoin(prefix, name, suffix_str);

    return suffixed_name;
}

InsertSymbol :: (scope : *IRScope, symbol : *IRSymbol, name : string, prefix : string) {
    Assert(scope != null);

    symbol.enclosing_scope = scope;
    symbol.name = MakeUniqueName(scope, name, prefix);
    _, was_present := HashMapInsert(*scope.symbols, symbol.name, symbol);
    Assert(!was_present, "Inserted a duplicate symbol '%'", symbol.name);
}

CreateIRGlobalData :: (builder : *IRBuilder, name : string) -> *IRGlobalData {
    data := Alloc(IRGlobalData);
    ArrayPush(*builder.file.global_data, data);
    InsertSymbol(*builder.file.scope, data, name, "$");

    return data;
}

AddZeroBytes :: (data : *IRGlobalData, align : int, num_zero_bytes : int) {
    num_padding_bytes := AlignForward(data.total_unaligned_size, align) - data.total_unaligned_size;
    if num_zero_bytes + num_padding_bytes == 0 {
        return;
    }

    field := ArrayPush(*data.fields);
    field.kind = .ZeroBytes;
    field.num_zero_bytes = num_zero_bytes + num_padding_bytes;

    data.total_unaligned_size += num_padding_bytes + num_zero_bytes;
}

AddString :: (data : *IRGlobalData, align : int, str : string) {
    num_padding_bytes := AlignForward(data.total_unaligned_size, align) - data.total_unaligned_size;
    if num_padding_bytes > 0 {
        zeroes := ArrayPush(*data.fields);
        zeroes.kind = .ZeroBytes;
        zeroes.num_zero_bytes = num_padding_bytes;
    }

    field := ArrayPush(*data.fields);
    field.kind = .String;
    field.string_value = str;

    data.total_unaligned_size += num_padding_bytes + str.count;
}

AddConstValue :: (data : *IRGlobalData, align : int, type : IRTypeKind, value : u64) {
    num_padding_bytes := AlignForward(data.total_unaligned_size, align) - data.total_unaligned_size;
    if num_padding_bytes > 0 {
        zeroes := ArrayPush(*data.fields);
        zeroes.kind = .ZeroBytes;
        zeroes.num_zero_bytes = num_padding_bytes;
    }

    field := ArrayPush(*data.fields);
    field.kind = .ConstValue;
    field.const_type = type;
    field.const_value = value;

    type_size : int;
    if type == {
    case .Int8;    type_size = 1;
    case .Int16;   type_size = 2;
    case .Int32;   type_size = 4;
    case .Int64;   type_size = 8;
    case .Float32; type_size = 4;
    case .Float64; type_size = 8;
    case;
        Panic("Invalid type % for global data", type);
    }

    data.total_unaligned_size += num_padding_bytes + type_size;
}

AddSymbolReference :: (data : *IRGlobalData, align : int, symbol : *IRSymbol) {
    if symbol {
        Assert(symbol.kind == .GlobalData || symbol.kind == .Function, "Symbol of kind % cannot be referenced in global data", symbol.kind);
    }

    num_padding_bytes := AlignForward(data.total_unaligned_size, align) - data.total_unaligned_size;
    if num_padding_bytes > 0 {
        zeroes := ArrayPush(*data.fields);
        zeroes.kind = .ZeroBytes;
        zeroes.num_zero_bytes = num_padding_bytes;
    }

    field := ArrayPush(*data.fields);
    field.kind = .SymbolReference;
    field.referenced_symbol = symbol;

    data.total_unaligned_size += 8;
}

CreateIRTypedef :: (builder : *IRBuilder, name : string) -> *IRTypedef {
    typedef := Alloc(IRTypedef);
    ArrayPush(*builder.file.typedefs, typedef);
    InsertSymbol(*builder.file.scope, typedef, name, ":");

    return typedef;
}

CreateIRFunction :: (builder : *IRBuilder, name : string) -> *IRFunction {
    func := Alloc(IRFunction);
    func.result_type = .{kind=.Void};
    ArrayPush(*builder.file.functions, func);
    InsertSymbol(*builder.file.scope, func, name, "$");

    return func;
}

GetCurrentFunction :: inline (builder : *IRBuilder) -> *IRFunction {
    return builder.current_func;
}

SetCurrentFunction :: inline (builder : *IRBuilder, func : *IRFunction) -> *IRFunction {
    prev := builder.current_func;
    builder.current_func = func;

    return prev;
}

AddParameter :: (func : *IRFunction, name : string, type : IRType) -> *IRSymbol {
    param := ArrayPush(*func.parameters);
    param.type = type;
    param.kind = .Parameter;
    InsertSymbol(*func.scope, param, name, "%");

    return param;
}

GetParameter :: (func : *IRFunction, name : string) -> *IRSymbol {
    for * func.parameters {
        if it.name == name {
            return it;
        }
    }

    return null;
}

CreateIRBasicBlock :: (builder : *IRBuilder, name : string) -> *IRBasicBlock {
    bb := Alloc(IRBasicBlock);
    bb.func = builder.current_func;
    InsertSymbol(*builder.current_func.scope, bb, name, "@");

    return bb;
}

InsertBlock :: inline (builder : *IRBuilder, block : *IRBasicBlock) {
    ArrayPush(*builder.current_func.basic_blocks, block);
}

GetCurrentBlock :: inline (builder : *IRBuilder) -> *IRBasicBlock {
    return builder.current_block;
}

SetCurrentBlock :: inline (builder : *IRBuilder, block : *IRBasicBlock) -> *IRBasicBlock {
    prev := builder.current_block;
    builder.current_block = block;

    return prev;
}

IsTerminated :: inline (block : *IRBasicBlock) -> bool {
    return block.instructions.count > 0 && IsTerminator(block.instructions[block.instructions.count - 1]);
}

PushInstr :: inline (builder : *IRBuilder, instr : *IRInstr) {
    Assert(builder.current_block != null);
    Assert(!IsTerminated(builder.current_block), "When pushing new instruction, block % is terminated", builder.current_block.name);

    ArrayPush(*builder.current_block.instructions, instr);
    ValidateInstr(instr, builder.current_func);
}
