IRInstr :: struct {
    symbol : IRSymbol;
    symbol.kind = .Temporary;

    opcode : IROpcode;
}

IROpcode :: enum u8 {
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
    BitCastToPtr;

    Alloc4;
    Alloc8;
    Alloc16;
    LoadI8;
    LoadI16;
    LoadI32;
    LoadI64;
    LoadF32;
    LoadF64;
    LoadPtr;
    Store;
    Blit;

    Call;

    Phi;
    Jmp;
    Jnz;
    Ret;

    DbgBrk;
    DbgSetFile;
    DbgSetLine;
}

#insert -> string {
    builder : StringBuilder;

    Append(*builder, "IR_Opcode_Mnemonics :: string.[\n");
    names := type_info(IROpcode).names;
    for name : names {
        Append(*builder, "\"");
        for name {
            StringBuilderAppendByte(*builder, Basic.to_lower(it));
        }
        Append(*builder, "\",\n");
    }

    Append(*builder, "];\n");

    return StringBuilderBuild(*builder);
}

IRInstrBinary :: struct {
    #as using _ : IRInstr;

    left : IROperand;
    right : IROperand;
}

IRInstrUnary :: struct {
    #as using _ : IRInstr;

    value : IROperand;
}

IRInstrAlloc :: struct {
    #as using _ : IRInstr;

    size : IROperand;
}

IRInstrLoad :: struct {
    #as using _ : IRInstr;

    src_addr : IROperand;
}

IRInstrStore :: struct {
    #as using _ : IRInstr;
    opcode = .Store;

    src : IROperand;
    dst_addr : IROperand;
}

IRInstrBlit :: struct {
    #as using _ : IRInstr;
    opcode = .Blit;

    src_addr : IROperand;
    dst_addr : IROperand;
    size : IROperand;
}

IRInstrCall :: struct {
    #as using _ : IRInstr;
    opcode = .Call;

    result_type : IRType;
    calling_convention : CallingConvention;
    callee : IROperand;
    arguments : []IROperand;
    first_c_variadic_argument_index := -1;
}

IRInstrPhi :: struct {
    #as using _ : IRInstr;
    opcode = .Phi;

    Value :: struct {
        block : IROperand;
        value : IROperand;
    }

    values : []Value;
}

IRInstrJmp :: struct {
    #as using _ : IRInstr;
    opcode = .Jmp;

    block : IROperand;
}

IRInstrJnz :: struct {
    #as using _ : IRInstr;
    opcode = .Jnz;

    value : IROperand;
    if_true  : IROperand;
    if_false : IROperand;
}

IRInstrRet :: struct {
    #as using _ : IRInstr;
    opcode = .Ret;

    value : IROperand;
}

IRInstrDbgSet :: struct {
    #as using _ : IRInstr;

    value : IROperand;
}

IsTerminator :: (instr : *IRInstr) -> bool {
    return instr.opcode == .Jnz || instr.opcode == .Jmp || instr.opcode == .Ret;
}

EmitInstrBinary :: (builder : *IRBuilder, opcode : IROpcode, left : IROperand, right : IROperand, result_name : string) -> IROperand {
    instr := Alloc(IRInstrBinary);
    instr.opcode = opcode;
    instr.left = left;
    instr.right = right;
    instr.symbol.type = left.type;
    InsertSymbol(*builder.current_block.func.scope, *instr.symbol, result_name, "%");
    PushInstr(builder, instr);

    return .{type=instr.symbol.type, symbol=*instr.symbol};
}

EmitAdd  :: #bake_arguments EmitInstrBinary(opcode=.Add);
EmitSub  :: #bake_arguments EmitInstrBinary(opcode=.Sub);
EmitMul  :: #bake_arguments EmitInstrBinary(opcode=.Mul);
EmitDiv  :: #bake_arguments EmitInstrBinary(opcode=.Div);
EmitRem  :: #bake_arguments EmitInstrBinary(opcode=.Rem);
EmitUDiv :: #bake_arguments EmitInstrBinary(opcode=.UDiv);
EmitURem :: #bake_arguments EmitInstrBinary(opcode=.URem);
EmitAnd  :: #bake_arguments EmitInstrBinary(opcode=.And);
EmitOr   :: #bake_arguments EmitInstrBinary(opcode=.Or);
EmitXor  :: #bake_arguments EmitInstrBinary(opcode=.Xor);
EmitShl  :: #bake_arguments EmitInstrBinary(opcode=.Shl);
EmitShr  :: #bake_arguments EmitInstrBinary(opcode=.Shr);
EmitSar  :: #bake_arguments EmitInstrBinary(opcode=.Sar);

EmitNeg :: (builder : *IRBuilder, value : IROperand, result_name : string) -> IROperand {
    instr := Alloc(IRInstrUnary);
    instr.opcode = .Neg;
    instr.value = value;
    instr.symbol.type = value.type;
    InsertSymbol(*builder.current_block.func.scope, *instr.symbol, result_name, "%");
    PushInstr(builder, instr);

    return .{type=instr.symbol.type, symbol=*instr.symbol};
}

EmitNot :: (builder : *IRBuilder, value : IROperand, result_name : string) -> IROperand {
    instr := Alloc(IRInstrUnary);
    instr.opcode = .Not;
    instr.value = value;
    instr.symbol.type = value.type;
    InsertSymbol(*builder.current_block.func.scope, *instr.symbol, result_name, "%");
    PushInstr(builder, instr);

    return .{type=instr.symbol.type, symbol=*instr.symbol};
}

EmitInstrCmp :: (builder : *IRBuilder, opcode : IROpcode, left : IROperand, right : IROperand, result_name : string) -> IROperand {
    instr := Alloc(IRInstrBinary);
    instr.opcode = opcode;
    instr.left = left;
    instr.right = right;
    instr.symbol.type = .{kind=.Int8};
    InsertSymbol(*builder.current_block.func.scope, *instr.symbol, result_name, "%");
    PushInstr(builder, instr);

    return .{type=instr.symbol.type, symbol=*instr.symbol};
}

EmitCmpEq  :: #bake_arguments EmitInstrCmp(opcode=.CmpEq);
EmitCmpNe  :: #bake_arguments EmitInstrCmp(opcode=.CmpNe);
EmitCmpFLt :: #bake_arguments EmitInstrCmp(opcode=.CmpFLt);
EmitCmpFLe :: #bake_arguments EmitInstrCmp(opcode=.CmpFLe);
EmitCmpFGt :: #bake_arguments EmitInstrCmp(opcode=.CmpFGt);
EmitCmpFGe :: #bake_arguments EmitInstrCmp(opcode=.CmpFGe);
EmitCmpSLt :: #bake_arguments EmitInstrCmp(opcode=.CmpSLt);
EmitCmpSLe :: #bake_arguments EmitInstrCmp(opcode=.CmpSLe);
EmitCmpSGt :: #bake_arguments EmitInstrCmp(opcode=.CmpSGt);
EmitCmpSGe :: #bake_arguments EmitInstrCmp(opcode=.CmpSGe);
EmitCmpULt :: #bake_arguments EmitInstrCmp(opcode=.CmpULt);
EmitCmpULe :: #bake_arguments EmitInstrCmp(opcode=.CmpULe);
EmitCmpUGt :: #bake_arguments EmitInstrCmp(opcode=.CmpUGt);
EmitCmpUGe :: #bake_arguments EmitInstrCmp(opcode=.CmpUGe);

EmitInstrCast :: (builder : *IRBuilder, opcode : IROpcode, result_type : IRTypeKind, value : IROperand, result_name : string) -> IROperand {
    instr := Alloc(IRInstrUnary);
    instr.opcode = opcode;
    instr.value = value;
    instr.symbol.type = .{kind=result_type};
    InsertSymbol(*builder.current_block.func.scope, *instr.symbol, result_name, "%");
    PushInstr(builder, instr);

    return .{type=instr.symbol.type, symbol=*instr.symbol};
}

EmitSExt :: (builder : *IRBuilder, result_type : IRType, value : IROperand, result_name : string) -> IROperand {
    instr := Alloc(IRInstrUnary);
    if result_type.kind == {
    case .Int16; instr.opcode = .SExtToI16;
    case .Int32; instr.opcode = .SExtToI32;
    case .Int64; instr.opcode = .SExtToI64;
    case; Panic("Invalid result type % for sign extend instruction", result_type.kind);
    }
    instr.value = value;
    instr.symbol.type = result_type;
    InsertSymbol(*builder.current_block.func.scope, *instr.symbol, result_name, "%");
    PushInstr(builder, instr);

    return .{type=instr.symbol.type, symbol=*instr.symbol};
}

EmitZExt :: (builder : *IRBuilder, result_type : IRType, value : IROperand, result_name : string) -> IROperand {
    instr := Alloc(IRInstrUnary);
    if result_type.kind == {
    case .Int16; instr.opcode = .ZExtToI16;
    case .Int32; instr.opcode = .ZExtToI32;
    case .Int64; instr.opcode = .ZExtToI64;
    case; Panic("Invalid result type % for zero extend instruction", result_type.kind);
    }
    instr.value = value;
    instr.symbol.type = result_type;
    InsertSymbol(*builder.current_block.func.scope, *instr.symbol, result_name, "%");
    PushInstr(builder, instr);

    return .{type=instr.symbol.type, symbol=*instr.symbol};
}

EmitIntTrunc :: (builder : *IRBuilder, result_type : IRType, value : IROperand, result_name : string) -> IROperand {
    instr := Alloc(IRInstrUnary);
    if result_type.kind == {
    case .Int8;  instr.opcode = .TruncToI8;
    case .Int16; instr.opcode = .TruncToI16;
    case .Int32; instr.opcode = .TruncToI32;
    case; Panic("Invalid result type % for integer truncate instruction", result_type.kind);
    }
    instr.value = value;
    instr.symbol.type = result_type;
    InsertSymbol(*builder.current_block.func.scope, *instr.symbol, result_name, "%");
    PushInstr(builder, instr);

    return .{type=instr.symbol.type, symbol=*instr.symbol};
}

EmitBitCast :: (builder : *IRBuilder, result_type : IRType, value : IROperand, result_name : string) -> IROperand {
    instr := Alloc(IRInstrUnary);
    if result_type.kind == {
    case .Int32;   instr.opcode = .BitCastToI32;
    case .Int64;   instr.opcode = .BitCastToI64;
    case .Float32; instr.opcode = .BitCastToI32;
    case .Float64; instr.opcode = .BitCastToI64;
    case .Pointer; instr.opcode = .BitCastToPtr;
    case; Panic("Invalid result type % for bitcast instruction", result_type.kind);
    }
    instr.value = value;
    instr.symbol.type = result_type;
    InsertSymbol(*builder.current_block.func.scope, *instr.symbol, result_name, "%");
    PushInstr(builder, instr);

    return .{type=instr.symbol.type, symbol=*instr.symbol};
}

EmitSExtToI16    :: #bake_arguments EmitInstrCast(opcode=.SExtToI16, result_type=.Int16);
EmitSExtToI32    :: #bake_arguments EmitInstrCast(opcode=.SExtToI32, result_type=.Int32);
EmitSExtToI64    :: #bake_arguments EmitInstrCast(opcode=.SExtToI64, result_type=.Int64);
EmitZExtToI16    :: #bake_arguments EmitInstrCast(opcode=.ZExtToI16, result_type=.Int16);
EmitZExtToI32    :: #bake_arguments EmitInstrCast(opcode=.ZExtToI32, result_type=.Int32);
EmitZExtToI64    :: #bake_arguments EmitInstrCast(opcode=.ZExtToI64, result_type=.Int64);
EmitTruncToI32   :: #bake_arguments EmitInstrCast(opcode=.TruncToI32, result_type=.Int32);
EmitTruncToI16   :: #bake_arguments EmitInstrCast(opcode=.TruncToI16, result_type=.Int16);
EmitTruncToI8    :: #bake_arguments EmitInstrCast(opcode=.TruncToI8, result_type=.Int8);
EmitExtToF64     :: #bake_arguments EmitInstrCast(opcode=.ExtToF64, result_type=.Float64);
EmitTruncToF32   :: #bake_arguments EmitInstrCast(opcode=.TruncToF32, result_type=.Float32);
EmitIToF32       :: #bake_arguments EmitInstrCast(opcode=.IToF32, result_type=.Float32);
EmitIToF64       :: #bake_arguments EmitInstrCast(opcode=.IToF64, result_type=.Float64);
EmitUToF32       :: #bake_arguments EmitInstrCast(opcode=.UToF32, result_type=.Float32);
EmitUToF64       :: #bake_arguments EmitInstrCast(opcode=.UToF64, result_type=.Float64);
EmitFToI64       :: #bake_arguments EmitInstrCast(opcode=.FToI64, result_type=.Int64);
EmitFToU64       :: #bake_arguments EmitInstrCast(opcode=.FToU64, result_type=.Int64);

EmitBitCastToI32 :: #bake_arguments EmitInstrCast(opcode=.BitCastToI32, result_type=.Int32);
EmitBitCastToI64 :: #bake_arguments EmitInstrCast(opcode=.BitCastToI64, result_type=.Int64);
EmitBitCastToF32 :: #bake_arguments EmitInstrCast(opcode=.BitCastToF32, result_type=.Float32);
EmitBitCastToF64 :: #bake_arguments EmitInstrCast(opcode=.BitCastToF64, result_type=.Float64);
EmitBitCastToPtr :: #bake_arguments EmitInstrCast(opcode=.BitCastToPtr, result_type=.Pointer);

EmitAlloc :: (builder : *IRBuilder, align : int, size : IROperand, result_name : string) -> IROperand {
    instr := Alloc(IRInstrAlloc);
    if align == 4 {
        instr.opcode = .Alloc4;
    } else if align == 8 {
        instr.opcode = .Alloc8;
    } else if align == 16 {
        instr.opcode = .Alloc16;
    } else {
        Panic("Invalid alignment for alloc instruction (%)", align);
    }

    instr.size = size;
    instr.symbol.type = .{kind=.Pointer};
    InsertSymbol(*builder.current_block.func.scope, *instr.symbol, result_name, "%");
    PushInstr(builder, instr);

    return .{type=instr.symbol.type, symbol=*instr.symbol};
}

EmitLoad :: (builder : *IRBuilder, src_addr : IROperand, result_type : IRTypeKind, result_name : string) -> IROperand {
    instr := Alloc(IRInstrLoad);
    if result_type == {
    case .Int8;    instr.opcode = .LoadI8;
    case .Int16;   instr.opcode = .LoadI16;
    case .Int32;   instr.opcode = .LoadI32;
    case .Int64;   instr.opcode = .LoadI64;
    case .Float32; instr.opcode = .LoadF32;
    case .Float64; instr.opcode = .LoadF64;
    case .Pointer; instr.opcode = .LoadPtr;
    case;
        Panic("Invalid type % for load instruction", result_type);
    }

    instr.src_addr = src_addr;
    instr.symbol.type = .{kind=result_type};
    InsertSymbol(*builder.current_block.func.scope, *instr.symbol, result_name, "%");
    PushInstr(builder, instr);

    return .{type=instr.symbol.type, symbol=*instr.symbol};
}

EmitStore :: (builder : *IRBuilder, src : IROperand, dst_addr : IROperand) {
    instr := Alloc(IRInstrStore);
    instr.src = src;
    instr.dst_addr = dst_addr;
    instr.symbol.type = .{kind=.Void};
    PushInstr(builder, instr);
}

EmitBlit :: (builder : *IRBuilder, src_addr : IROperand, dst_addr : IROperand, size : IROperand) {
    instr := Alloc(IRInstrBlit);
    instr.src_addr = src_addr;
    instr.dst_addr = dst_addr;
    instr.size = size;
    instr.symbol.type = .{kind=.Void};
    PushInstr(builder, instr);
}

EmitCall :: (builder : *IRBuilder, calling_convention : CallingConvention, callee : IROperand, arguments : []IROperand, result_type : IRType, result_name : string, first_c_variadic_argument_index := -1) -> IROperand {
    instr := Alloc(IRInstrCall);
    instr.calling_convention = calling_convention;
    instr.result_type = result_type;
    instr.callee = callee;
    instr.arguments = arguments;
    instr.first_c_variadic_argument_index = first_c_variadic_argument_index;
    instr.symbol.type = ifx result_type.kind == .Typedef then .{kind=.Pointer} else result_type;
    if result_type.kind != .Void {
        InsertSymbol(*builder.current_block.func.scope, *instr.symbol, result_name, "%");
    }
    PushInstr(builder, instr);

    return .{type=instr.symbol.type, symbol=*instr.symbol};
}

EmitPhi :: (builder : *IRBuilder, values : []IRInstrPhi.Value, result_name : string) -> IROperand {
    instr := Alloc(IRInstrPhi);
    instr.values = values;
    if values.count > 0 {
        instr.symbol.type = values[0].value.type;
    }
    InsertSymbol(*builder.current_block.func.scope, *instr.symbol, result_name, "%");
    PushInstr(builder, instr);

    return .{type=instr.symbol.type, symbol=*instr.symbol};
}

EmitJmp :: (builder : *IRBuilder, block : IROperand) {
    instr := Alloc(IRInstrJmp);
    instr.block = block;
    PushInstr(builder, instr);
}

EmitJnz :: (builder : *IRBuilder, value : IROperand, if_true : IROperand, if_false : IROperand) {
    instr := Alloc(IRInstrJnz);
    instr.value = value;
    instr.if_true = if_true;
    instr.if_false = if_false;
    PushInstr(builder, instr);
}

EmitRet :: (builder : *IRBuilder, value : IROperand = .{type=.{kind=.Void}}) {
    instr := Alloc(IRInstrRet);
    instr.value = value;
    instr.symbol.type = .{kind=.Void};
    PushInstr(builder, instr);
}

EmitDbgBrk :: (builder : *IRBuilder) {
    instr := Alloc(IRInstr);
    instr.opcode = .DbgBrk;
    PushInstr(builder, instr);
}

EmitDbgSetFile :: (builder : *IRBuilder, file_id : FileId) {
    instr := Alloc(IRInstrDbgSet);
    instr.opcode = .DbgSetFile;
    instr.value = IROpU16(xx,no_check file_id);
    PushInstr(builder, instr);
}

EmitDbgSetLine :: (builder : *IRBuilder, line : u32) {
    instr := Alloc(IRInstrDbgSet);
    instr.opcode = .DbgSetLine;
    instr.value = IROpU32(line);
    PushInstr(builder, instr);
}
