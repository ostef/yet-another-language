BytecodeBuilder :: struct {
    symbol_address_table : HashMap(*IRSymbol, BytecodeAddress);
    typedef_dyncall_aggr_address_table : HashMap(*IRTypedef, BytecodeAddress);
    file : *BytecodeFile;
}

CalculateTotalBytecodeDataSizeAndCollectSymbols :: (using builder : *BytecodeBuilder, ir_file : *IRFile) -> int {
    total_data_size := 0;
    for ir_file.global_data {
        if it.align > 0 {
            total_data_size = AlignForward(total_data_size, it.align);
        }

        symbol_address := MakeBytecodeAddress(.DataAddress, cast(u64, total_data_size));
        HashMapInsert(*builder.symbol_address_table, *it.symbol, symbol_address);
        HashMapInsert(*file.symbol_name_to_address, it.symbol.name, symbol_address);
        HashMapInsert(*file.address_to_symbol_name, symbol_address, it.symbol.name);

        total_data_size += it.total_unaligned_size;
    }

    return total_data_size;
}

GetBytecodeOperandSize :: (op : IROperand) -> int {
    if !op.symbol {
        return GetSize(op.type);
    } else if op.symbol.kind == .Temporary || op.symbol.kind == .Parameter {
        return size_of(u32); // Register
    } else {
        return size_of(u64); // Pointer
    }
}

CalculateBytecodeSize :: (instr : *IRInstr) -> int {
    if #complete instr.opcode == {
    case .Add; #through;
    case .Sub; #through;
    case .Mul; #through;
    case .Div; #through;
    case .Rem; #through;
    case .UDiv; #through;
    case .URem; #through;
    case .And; #through;
    case .Or; #through;
    case .Xor; #through;
    case .Shl; #through;
    case .Shr; #through;
    case .Sar; #through;
    case .CmpEq; #through;
    case .CmpNe; #through;
    case .CmpFLt; #through;
    case .CmpFLe; #through;
    case .CmpFGt; #through;
    case .CmpFGe; #through;
    case .CmpSLt; #through;
    case .CmpSLe; #through;
    case .CmpSGt; #through;
    case .CmpSGe; #through;
    case .CmpULt; #through;
    case .CmpULe; #through;
    case .CmpUGt; #through;
    case .CmpUGe;
        binary := cast(*IRInstrBinary, instr);
        size := size_of(BytecodeOpcode) + size_of(BytecodeOpcodeFlags);
        size += size_of(u32);
        size += GetBytecodeOperandSize(binary.left);
        size += GetBytecodeOperandSize(binary.right);
        return size;

    case .Neg; #through;
    case .Not; #through;
    case .SExtToI16; #through;
    case .SExtToI32; #through;
    case .SExtToI64; #through;
    case .ZExtToI16; #through;
    case .ZExtToI32; #through;
    case .ZExtToI64; #through;
    case .TruncToI32; #through;
    case .TruncToI16; #through;
    case .TruncToI8; #through;
    case .ExtToF64; #through;
    case .TruncToF32; #through;
    case .IToF32; #through;
    case .IToF64; #through;
    case .UToF32; #through;
    case .UToF64; #through;
    case .FToI64; #through;
    case .FToU64; #through;
    case .BitCastToI32; #through;
    case .BitCastToI64; #through;
    case .BitCastToF32; #through;
    case .BitCastToF64; #through;
    case .BitCastToPtr;
        unary := cast(*IRInstrUnary, instr);
        size := size_of(BytecodeOpcode) + size_of(BytecodeOpcodeFlags);
        size += size_of(u32);
        size += GetBytecodeOperandSize(unary.value);
        return size;

    case .Alloc4; #through;
    case .Alloc8; #through;
    case .Alloc16;
        alloc := cast(*IRInstrAlloc, instr);
        size := size_of(BytecodeOpcode);
        size += size_of(u32);
        size += size_of(u64);
        return size;

    case .LoadI8; #through;
    case .LoadI16; #through;
    case .LoadI32; #through;
    case .LoadI64; #through;
    case .LoadF32; #through;
    case .LoadF64; #through;
    case .LoadPtr;
        load := cast(*IRInstrLoad, instr);
        size := size_of(BytecodeOpcode) + size_of(BytecodeOpcodeFlags);
        size += size_of(u32);
        size += GetBytecodeOperandSize(load.src_addr);
        return size;

    case .Store;
        store := cast(*IRInstrStore, instr);
        size := size_of(BytecodeOpcode) + size_of(BytecodeOpcodeFlags);
        size += GetBytecodeOperandSize(store.src);
        size += GetBytecodeOperandSize(store.dst_addr);
        return size;

    case .Blit;
        blit := cast(*IRInstrBlit, instr);
        size := size_of(BytecodeOpcode) + size_of(BytecodeOpcodeFlags);
        size += GetBytecodeOperandSize(blit.src_addr);
        size += GetBytecodeOperandSize(blit.dst_addr);
        size += size_of(u64);
        return size;

    case .Phi;
        phi := cast(*IRInstrPhi, instr);
        size := size_of(BytecodeOpcode) + size_of(BytecodeOpcodeFlags);
        size += size_of(u32); // Register index
        size += size_of(u8); // Num values
        for phi.values {
            size += size_of(BytecodeOpcodeFlags);
            size += GetBytecodeOperandSize(it.block);
            size += GetBytecodeOperandSize(it.value);
        }
        return size;

    case .Jmp;
        return size_of(BytecodeOpcode) + size_of(BytecodeAddress);

    case .Jnz;
        jnz := cast(*IRInstrJnz, instr);
        size := size_of(BytecodeOpcode) + size_of(BytecodeOpcodeFlags);
        size += GetBytecodeOperandSize(jnz.value);
        size += size_of(BytecodeAddress) + size_of(BytecodeAddress);
        return size;

    case .Call;
        call := cast(*IRInstrCall, instr);
        size := size_of(BytecodeOpcode) + size_of(BytecodeOpcodeFlags);
        size += size_of(u32); // Register index
        size += GetBytecodeOperandSize(call.callee);
        size += size_of(CallingConvention);
        if call.calling_convention == .C {
            size += size_of(u8); // First C variadic argument index
        }
        size += size_of(BytecodeOperandType); // Result type
        size += size_of(u32); // Return value size to allocate on the stack
        size += size_of(u8); // Num parameters

        // DynCall aggregate info pointer
        if call.calling_convention == .C && call.result_type.kind == .Typedef {
            size += size_of(u64);
        }

        for call.arguments {
            size += size_of(BytecodeOpcodeFlags);
            size += GetBytecodeOperandSize(it);

            // DynCall aggregate info pointer
            if call.calling_convention == .C && it.type.kind == .Typedef {
                size += size_of(u64);
            }
        }

        return size;

    case .Ret;
        ret := cast(*IRInstrRet, instr);
        size := size_of(BytecodeOpcode) + size_of(BytecodeOpcodeFlags);
        if ret.value.type.kind != .Invalid && ret.value.type.kind != .Void {
            size += GetBytecodeOperandSize(ret.value);
        }

        return size;

    case .DbgBrk;
        return size_of(BytecodeOpcode);

    case .DbgSetFile; #through;
    case .DbgSetLine;
        return size_of(BytecodeOpcode) + size_of(u32);

    case .Invalid;
        Panic("Invalid instruction");
    case;
        Panic("Corrupt instruction");
    }

    Panic("Unhandled case");
    return 0;
}

CalculateBytecodeSizeAndCollectSymbols :: (using builder : *BytecodeBuilder, ir_func : *IRFunction, base_offset : u64) -> int {
    total_size := 0;

    if ir_func.calling_convention == .C {
        if ir_func.result_type.kind == .Typedef {
            total_size += xx InsertNewDynCallAggregate(builder, ir_func.result_type.typedef, base_offset + cast(u64, total_size));
        }

        for ir_func.parameters {
            if it.type.kind == .Typedef {
                total_size += xx InsertNewDynCallAggregate(builder, it.type.typedef, base_offset + cast(u64, total_size));
            }
        }
    }

    if ir_func.flags & .External {
        HashMapInsert(*builder.symbol_address_table, *ir_func.symbol, 0);
        return total_size;
    }

    symbol_addr := MakeBytecodeAddress(.CodeAddress, base_offset + cast(u64, total_size));
    HashMapInsert(*builder.symbol_address_table, *ir_func.symbol, symbol_addr);
    HashMapInsert(*file.symbol_name_to_address, ir_func.symbol.name, symbol_addr);
    HashMapInsert(*file.address_to_symbol_name, symbol_addr, ir_func.symbol.name);

    for block : ir_func.basic_blocks {
        block_offset := base_offset + cast(u64, total_size);
        block_addr := MakeBytecodeAddress(.CodeAddress, block_offset);
        HashMapInsert(*builder.symbol_address_table, *block.symbol, block_addr);

        for instr : block.instructions {
            total_size += CalculateBytecodeSize(instr);
        }
    }

    return total_size;
}

CalculateTotalBytecodeCodeSizeAndCollectSymbols :: (using builder : *BytecodeBuilder, ir_file : *IRFile) -> int {
    total_size := 0;
    for ir_file.functions {
        total_size += CalculateBytecodeSizeAndCollectSymbols(builder, it, xx total_size);
    }

    return total_size;
}

InsertNewDynCallAggregate :: (using builder : *BytecodeBuilder, typedef : *IRTypedef, base_offset : u64) -> code_size : u64, address : BytecodeAddress {
    addr, exists := HashMapInsert(*typedef_dyncall_aggr_address_table, typedef);
    if exists {
        return 0, addr.*;
    }

    addr.* = MakeBytecodeAddress(.CodeAddress, base_offset);
    total_code_size : u64 = 8;
    base_offset += total_code_size;

    dyncall_aggr : BytecodeDynCallAggr;
    dyncall_aggr.size = xx typedef.size;
    dyncall_aggr.runtime_address = addr.*;
    dyncall_aggr.fields = AllocArray(BytecodeDynCallAggrField, typedef.members.count);

    for typedef.members {
        field := *dyncall_aggr.fields[it_index];

        if it.type.kind == {
        case .Void;    field.type = DC_SIGCHAR_VOID;
        case .Int8;    field.type = DC_SIGCHAR_UCHAR;
        case .Int16;   field.type = DC_SIGCHAR_USHORT;
        case .Int32;   field.type = DC_SIGCHAR_UINT;
        case .Int64;   field.type = DC_SIGCHAR_ULONGLONG;
        case .Float32; field.type = DC_SIGCHAR_FLOAT;
        case .Float64; field.type = DC_SIGCHAR_DOUBLE;
        case .Pointer; field.type = DC_SIGCHAR_POINTER;
        case .Typedef; field.type = DC_SIGCHAR_AGGREGATE;
        }

        Assert(it.offset != 0xffffffff, "Offset is not set");
        field.offset = it.offset;
        field.array_length = xx it.num_elements;

        if it.type.kind == .Typedef {
            code_size, member_addr := InsertNewDynCallAggregate(builder, it.type.typedef, base_offset);
            base_offset += code_size;
            total_code_size += code_size;

            field.nested_aggr_address = member_addr;
        } else {
            field.nested_aggr_address = 0;
        }
    }

    ArrayPush(*file.dyncall_aggregates, dyncall_aggr);

    return total_code_size, addr.*;
}

CompileIRToBytecode :: (ir_file : *IRFile) -> BytecodeFile {
    result : BytecodeFile;
    builder : BytecodeBuilder;
    builder.file = *result;

    total_data_size := CalculateTotalBytecodeDataSizeAndCollectSymbols(*builder, ir_file);
    total_code_size := CalculateTotalBytecodeCodeSizeAndCollectSymbols(*builder, ir_file);
    buffer := Alloc(u8, total_data_size + total_code_size);

    result.data = .{count=total_data_size, data=buffer};
    result.code = .{count=total_code_size, data=buffer + total_data_size};

    cursor := 0;
    for ir_file.global_data {
        cursor = CompileIRGlobalDataToBytecode(*builder, it, cursor);
        Assert(cursor <= total_data_size, "Data cursor overrun (cursor is %, size is %)", cursor, total_data_size);
    }

    if cursor < total_data_size {
        Warning("Unexpected trailing bytes after compiling data (cursor is %, size is %)", cursor, total_data_size);
    }

    cursor = 0;
    for ir_file.functions {
        cursor = CompileIRFunctionToBytecode(*builder, it, cursor);
        Assert(cursor <= total_code_size, "Code cursor overrun (cursor is %, size is %)", cursor, total_code_size);
    }

    if cursor < total_code_size {
        Warning("Unexpected trailing bytes after compiling code (cursor is %, size is %)", cursor, total_code_size);
    }

    return result;
}

CompileIRGlobalDataToBytecode :: (using builder : *BytecodeBuilder, data : *IRGlobalData, cursor : int) -> cursor : int {
    if data.align > 0 {
        cursor = AlignForward(cursor, data.align);
    }

    for field : data.fields {
        if #complete field.kind == {
        case .String;
            memcpy(file.data.data + cursor, field.string_value.data, field.string_value.count);
            cursor += field.string_value.count;
        case .ZeroBytes;
            memset(file.data.data + cursor, 0, field.num_zero_bytes);
            cursor += field.num_zero_bytes;
        case .ConstValue;
            if field.const_type == {
            case .Int8;
                cast(*u8, file.data.data + cursor).* = cast(*u8, *field.const_value).*;
                cursor += size_of(u8);
            case .Int16;
                cast(*u16, file.data.data + cursor).* = cast(*u16, *field.const_value).*;
                cursor += size_of(u16);
            case .Int32;
                cast(*u32, file.data.data + cursor).* = cast(*u32, *field.const_value).*;
                cursor += size_of(u32);
            case .Int64;
                cast(*u64, file.data.data + cursor).* = cast(*u64, *field.const_value).*;
                cursor += size_of(u64);
            case .Float32;
                cast(*float32, file.data.data + cursor).* = cast(*float32, *field.const_value).*;
                cursor += size_of(float32);
            case .Float64;
                cast(*float64, file.data.data + cursor).* = cast(*float64, *field.const_value).*;
                cursor += size_of(float64);
            case;
                Panic("Invalid type %", field.const_type);
            }

        case .SymbolReference;
            addr := MakeBytecodeAddress(.DataAddress, cast(u64, cursor));

            symbol_addr : BytecodeAddress;
            if field.referenced_symbol {
                symbol_addr=, ok := HashMapGet(*builder.symbol_address_table, field.referenced_symbol);
                Assert(ok, "Could not find symbol %", field.referenced_symbol.name);

                if field.referenced_symbol.kind == .Function && cast(*IRFunction, field.referenced_symbol).flags & .External {
                    // We don't know the address yet, so put null and we'll fix it up when we load the program
                    lib_name := cast(*IRFunction, field.referenced_symbol).library_name;
                    if lib_name {
                        lib := FindOrAddExternalLibrary(file, lib_name);
                        external_func_name := StringAdvance(field.referenced_symbol.name, 1);
                        AddExternalSymbolReference(lib, external_func_name, addr);
                    }
                } else {
                    ArrayPush(*file.addresses_to_translate, addr);
                }
            }

            cast(*u64, file.data.data + cursor).* = symbol_addr;
            cursor += size_of(u64);
        }
    }

    return cursor;
}

PushBytecodeOpcode :: (buffer : *[..]u8, value : BytecodeOpcode) {
    ArrayPush(buffer, xx value);
}

PushBytecodeOpcodeFlags :: (buffer : *[..]u8, value : BytecodeOpcodeFlags) {
    ArrayPush(buffer, xx value);
}

PushU8 :: (buffer : *[..]u8, value : u8) {
    ArrayPush(buffer, value);
}

PushU16 :: (buffer : *[..]u8, value : u16) {
    Assert(buffer.count + size_of(u16) <= buffer.allocated);
    cast(*u16, buffer.data + buffer.count).* = value;
    buffer.count += size_of(u16);
}

PushU32 :: (buffer : *[..]u8, value : u32) {
    Assert(buffer.count + size_of(u32) <= buffer.allocated);
    cast(*u32, buffer.data + buffer.count).* = value;
    buffer.count += size_of(u32);
}

PushU64 :: (buffer : *[..]u8, value : u64) {
    Assert(buffer.count + size_of(u64) <= buffer.allocated);
    cast(*u64, buffer.data + buffer.count).* = value;
    buffer.count += size_of(u64);
}

PushBytecodeOperand :: (using builder : *BytecodeBuilder, buffer : *[..]u8, op : IROperand) {
    start_index := buffer.count;
    op_size := GetBytecodeOperandSize(op);
    defer Assert(buffer.count - start_index == op_size, "Mismatching encoding size for operand (got %, expected %)", buffer.count - start_index, op_size);

    if !op.symbol {
        if op.type.kind == {
        case .Int8;
            PushU8(buffer, cast(*u8, *op.value).*);
        case .Int16;
            PushU16(buffer, cast(*u16, *op.value).*);
        case .Int32; #through;
        case .Float32;
            PushU32(buffer, cast(*u32, *op.value).*);
        case .Int64; #through;
        case .Pointer; #through;
        case .Float64;
            PushU64(buffer, cast(*u64, *op.value).*);
        case;
            Panic("Invalid type %", op.type.kind);
        }
    } else if op.symbol.kind == .Temporary || op.symbol.kind == .Parameter {
        register, ok := HashMapGet(*builder.symbol_address_table, op.symbol);
        Assert(ok, "Could not find symbol %", op.symbol.name);
        PushU32(buffer, cast(u32, register));
    } else if op.symbol.kind == .Function && cast(*IRFunction, op.symbol).flags & .External {
        // We don't know the address yet, so put null and we'll fix it up when we load the program
        addr := MakeBytecodeAddress(.CodeAddress, cast(u64, buffer.count));
        PushU64(buffer, 0);

        lib_name := cast(*IRFunction, op.symbol).library_name;
        if lib_name {
            lib := FindOrAddExternalLibrary(file, lib_name);
            external_func_name := StringAdvance(op.symbol.name, 1);
            AddExternalSymbolReference(lib, external_func_name, addr);
        }
    } else {
        // For references to data, make sure the address gets translated, so
        // we can pass it around to foreign functions
        if op.symbol.kind == .GlobalData {
            addr := MakeBytecodeAddress(.CodeAddress, cast(u64, buffer.count));
            ArrayPush(*file.addresses_to_translate, addr);
        }

        symbol_addr, ok := HashMapGet(*builder.symbol_address_table, op.symbol);
        Assert(ok, "Could not find symbol %", op.symbol.name);

        PushU64(buffer, symbol_addr);
    }
}

PushBytecodeInstr :: (using builder : *BytecodeBuilder, buffer : *[..]u8, instr : *IRInstr, register_index : *u32) {
    start_index := buffer.count;
    instr_size := CalculateBytecodeSize(instr);
    defer Assert(buffer.count - start_index == instr_size, "Encoding size mismatch for instr % (got %, expected %)", instr.opcode, buffer.count - start_index, instr_size);

    if #complete instr.opcode == {
    case .Add; #through;
    case .Sub; #through;
    case .Mul; #through;
    case .Div; #through;
    case .Rem; #through;
    case .UDiv; #through;
    case .URem; #through;
    case .And; #through;
    case .Or; #through;
    case .Xor; #through;
    case .Shl; #through;
    case .Shr; #through;
    case .Sar; #through;
    case .CmpEq; #through;
    case .CmpNe; #through;
    case .CmpFLt; #through;
    case .CmpFLe; #through;
    case .CmpFGt; #through;
    case .CmpFGe; #through;
    case .CmpSLt; #through;
    case .CmpSLe; #through;
    case .CmpSGt; #through;
    case .CmpSGe; #through;
    case .CmpULt; #through;
    case .CmpULe; #through;
    case .CmpUGt; #through;
    case .CmpUGe;
        binary := cast(*IRInstrBinary, instr);
        PushBytecodeOpcode(buffer, Bytecode_Opcodes[instr.opcode]);
        type := binary.left.type.kind;
        flags := MakeBytecodeOpcodeFlags(type, binary.left, binary.right);
        PushBytecodeOpcodeFlags(buffer, flags);
        PushU32(buffer, register_index.*);
        PushBytecodeOperand(builder, buffer, binary.left);
        PushBytecodeOperand(builder, buffer, binary.right);

    case .Neg; #through;
    case .Not; #through;
    case .SExtToI16; #through;
    case .SExtToI32; #through;
    case .SExtToI64; #through;
    case .ZExtToI16; #through;
    case .ZExtToI32; #through;
    case .ZExtToI64; #through;
    case .TruncToI32; #through;
    case .TruncToI16; #through;
    case .TruncToI8; #through;
    case .ExtToF64; #through;
    case .TruncToF32; #through;
    case .IToF32; #through;
    case .IToF64; #through;
    case .UToF32; #through;
    case .UToF64; #through;
    case .FToI64; #through;
    case .FToU64; #through;
    case .BitCastToI32; #through;
    case .BitCastToI64; #through;
    case .BitCastToF32; #through;
    case .BitCastToF64; #through;
    case .BitCastToPtr;
        unary := cast(*IRInstrUnary, instr);
        PushBytecodeOpcode(buffer, Bytecode_Opcodes[instr.opcode]);
        flags := MakeBytecodeOpcodeFlags(unary.value.type, unary.value);
        PushBytecodeOpcodeFlags(buffer, flags);
        PushU32(buffer, register_index.*);
        PushBytecodeOperand(builder, buffer, unary.value);

    case .Alloc4; #through;
    case .Alloc8; #through;
    case .Alloc16;
        alloc := cast(*IRInstrAlloc, instr);
        PushBytecodeOpcode(buffer, Bytecode_Opcodes[instr.opcode]);
        PushU32(buffer, register_index.*);
        PushBytecodeOperand(builder, buffer, alloc.size);

    case .LoadI8; #through;
    case .LoadI16; #through;
    case .LoadI32; #through;
    case .LoadI64; #through;
    case .LoadF32; #through;
    case .LoadF64; #through;
    case .LoadPtr;
        load := cast(*IRInstrLoad, instr);
        PushBytecodeOpcode(buffer, Bytecode_Opcodes[instr.opcode]);
        flags := MakeBytecodeOpcodeFlags(.Void, load.src_addr);
        PushBytecodeOpcodeFlags(buffer, flags);
        PushU32(buffer, register_index.*);
        PushBytecodeOperand(builder, buffer, load.src_addr);

    case .Store;
        store := cast(*IRInstrStore, instr);
        PushBytecodeOpcode(buffer, Bytecode_Opcodes[instr.opcode]);
        type := store.src.type.kind;
        flags := MakeBytecodeOpcodeFlags(type, store.src, store.dst_addr);
        PushBytecodeOpcodeFlags(buffer, flags);
        PushBytecodeOperand(builder, buffer, store.src);
        PushBytecodeOperand(builder, buffer, store.dst_addr);

    case .Blit;
        blit := cast(*IRInstrBlit, instr);
        PushBytecodeOpcode(buffer, Bytecode_Opcodes[instr.opcode]);
        flags := MakeBytecodeOpcodeFlags(.Pointer, blit.src_addr, blit.dst_addr);
        PushBytecodeOpcodeFlags(buffer, flags);
        PushBytecodeOperand(builder, buffer, blit.src_addr);
        PushBytecodeOperand(builder, buffer, blit.dst_addr);
        PushBytecodeOperand(builder, buffer, blit.size);

    case .Call;
        call := cast(*IRInstrCall, instr);

        PushBytecodeOpcode(buffer, .Call);
        type := call.callee.type.kind;
        flags := MakeBytecodeOpcodeFlags(type, call.callee);
        PushBytecodeOpcodeFlags(buffer, flags);
        PushU32(buffer, register_index.*);
        PushBytecodeOperand(builder, buffer, call.callee);
        PushU8(buffer, xx call.calling_convention);
        if call.calling_convention == .C {
            PushU8(buffer, cast(u8, call.first_c_variadic_argument_index + 1));
        }

        result_stack_size : u32;
        if call.result_type.kind == {
        case;
            PushU8(buffer, xx BytecodeOperandType.Void);
        case .Int8;
            PushU8(buffer, xx BytecodeOperandType.Int8);
        case .Int16;
            PushU8(buffer, xx BytecodeOperandType.Int16);
        case .Int32;
            PushU8(buffer, xx BytecodeOperandType.Int32);
        case .Int64; #through;
        case .Pointer;
            PushU8(buffer, xx BytecodeOperandType.Int64);
        case .Typedef;
            result_stack_size = xx call.result_type.typedef.size;
            if call.calling_convention == .C {
                PushU8(buffer, xx BytecodeOperandType.DynCallAggr);
            } else {
                PushU8(buffer, xx BytecodeOperandType.Int64); // pointer
            }
        case .Float32;
            PushU8(buffer, xx BytecodeOperandType.Float32);
        case .Float64;
            PushU8(buffer, xx BytecodeOperandType.Float64);
        }

        PushU32(buffer, result_stack_size); // Result stack size // @Todo

        Assert(call.arguments.count < 256, "Too many arguments for function call");
        PushU8(buffer, xx call.arguments.count);

        if call.calling_convention == .C && call.result_type.kind == .Typedef {
            dyncall_aggr_addr := HashMapGet(*builder.typedef_dyncall_aggr_address_table, call.result_type.typedef);
            PushU64(buffer, dyncall_aggr_addr);
        }

        for call.arguments {
            type := it.type.kind;

            dyncall_aggregate := type == .Typedef && call.calling_convention == .C;
            arg_flags : BytecodeOpcodeFlags;
            if  dyncall_aggregate {
                arg_flags = MakeBytecodeOpcodeFlags(.Void, it);
                arg_flags |= .TypeDynCallAggr;
            } else {
                if type == .Typedef {
                    type = .Pointer;
                }
                arg_flags = MakeBytecodeOpcodeFlags(type, it);
            }

            PushBytecodeOpcodeFlags(buffer, arg_flags);
            PushBytecodeOperand(builder, buffer, it);

            if dyncall_aggregate {
                dyncall_aggr_addr := HashMapGet(*builder.typedef_dyncall_aggr_address_table, it.type.typedef);
                PushU64(buffer, dyncall_aggr_addr);
            }
        }

    case .Phi;
        phi := cast(*IRInstrPhi, instr);
        PushBytecodeOpcode(buffer, .Phi);
        flags := MakeBytecodeOpcodeFlags(phi.symbol.type.kind, .{});
        PushBytecodeOpcodeFlags(buffer, flags);
        PushU32(buffer, register_index.*);

        Assert(phi.values.count < 256, "Too many values for phi instruction");
        PushU8(buffer, xx phi.values.count);

        for phi.values {
            flags := MakeBytecodeOpcodeFlags(it.value.type.kind, it.block, it.value);
            PushBytecodeOpcodeFlags(buffer, flags);
            PushBytecodeOperand(builder, buffer, it.block);
            PushBytecodeOperand(builder, buffer, it.value);
        }

    case .Jmp;
        jmp := cast(*IRInstrJmp, instr);
        addr, found := HashMapGet(*builder.symbol_address_table, jmp.block.symbol);
        Assert(found, "Jmp address symbol not found in symbol address table");
        PushBytecodeOpcode(buffer, Bytecode_Opcodes[instr.opcode]);
        PushBytecodeOperand(builder, buffer, jmp.block);

    case .Jnz;
        jnz := cast(*IRInstrJnz, instr);
        true_addr, true_found := HashMapGet(*builder.symbol_address_table, jnz.if_true.symbol);
        Assert(true_found, "Jnz first address symbol not found in symbol address table");
        false_addr, false_found := HashMapGet(*builder.symbol_address_table, jnz.if_false.symbol);
        Assert(false_found, "Jnz second address symbol not found in symbol address table");

        PushBytecodeOpcode(buffer, Bytecode_Opcodes[instr.opcode]);
        type := jnz.value.type.kind;
        flags := MakeBytecodeOpcodeFlags(type, jnz.value);
        PushBytecodeOpcodeFlags(buffer, flags);
        PushBytecodeOperand(builder, buffer, jnz.value);
        PushBytecodeOperand(builder, buffer, jnz.if_true);
        PushBytecodeOperand(builder, buffer, jnz.if_false);

    case .Ret;
        ret := cast(*IRInstrRet, instr);
        PushBytecodeOpcode(buffer, Bytecode_Opcodes[instr.opcode]);
        type := ifx ret.value.type.kind == .Pointer || ret.value.type.kind == .Typedef
            then .Pointer
            else ifx ret.value.type.kind == .Invalid
            then .Void
            else ret.value.type.kind;
        flags := MakeBytecodeOpcodeFlags(type, ret.value);
        PushBytecodeOpcodeFlags(buffer, flags);
        if type != .Void {
            PushBytecodeOperand(builder, buffer, ret.value);
        }

    case .DbgBrk;
        PushBytecodeOpcode(buffer, .DbgBrk);

    case .DbgSetFile; #through;
    case .DbgSetLine;
        set := cast(*IRInstrDbgSet, instr);
        PushBytecodeOpcode(buffer, Bytecode_Opcodes[instr.opcode]);
        PushU32(buffer, xx,no_check set.value.value);

    case .Invalid;
        Panic("Invalid instruction");
    case;
        Panic("Corrupt instruction");
    }

    if instr.symbol.type.kind != .Invalid && instr.symbol.type.kind != .Void {
        HashMapInsert(*builder.symbol_address_table, *instr.symbol, register_index.*);
        register_index.* += 1;
    }
}

CompileIRFunctionToBytecode :: (using builder : *BytecodeBuilder, ir_func : *IRFunction, cursor : int) -> cursor : int {
    if ir_func.flags & .External {
        return cursor;
    }

    func_address := HashMapGet(*builder.symbol_address_table, *ir_func.symbol);
    cursor = xx GetAddressOffset(func_address);

    buffer : [..]u8;
    buffer.data = file.code.data;
    buffer.count = cursor;
    buffer.allocated = file.code.count;
    buffer.allocator = .{proc=TrapAllocatorProc};

    register_index : u32;
    for * ir_func.parameters {
        HashMapInsert(*builder.symbol_address_table, it, register_index);
        register_index += 1;
    }

    for block : ir_func.basic_blocks {
        for instr : block.instructions {
            PushBytecodeInstr(builder, *buffer, instr, *register_index);
        }
    }

    return buffer.count;
}

Bytecode_Opcodes :: BytecodeOpcode.[
    .Invalid, // Invalid
    .Add, // Add
    .Sub, // Sub
    .Mul, // Mul
    .Div, // Div
    .Rem, // Rem
    .UDiv, // UDiv
    .URem, // URem
    .Neg, // Neg
    .Not, // Not
    .And, // And
    .Or, // Or
    .Xor, // Xor
    .Shl, // Shl
    .Shr, // Shr
    .Sar, // Sar
    .CmpEq, // CmpEq
    .CmpNe, // CmpNe
    .CmpFLt, // CmpFLt
    .CmpFLe, // CmpFLe
    .CmpFGt, // CmpFGt
    .CmpFGe, // CmpFGe
    .CmpSLt, // CmpSLt
    .CmpSLe, // CmpSLe
    .CmpSGt, // CmpSGt
    .CmpSGe, // CmpSGe
    .CmpULt, // CmpULt
    .CmpULe, // CmpULe
    .CmpUGt, // CmpUGt
    .CmpUGe, // CmpUGe
    .SExtToI16, // SExtToI16
    .SExtToI32, // SExtToI32
    .SExtToI64, // SExtToI64
    .ZExtToI16, // ZExtToI16
    .ZExtToI32, // ZExtToI32
    .ZExtToI64, // ZExtToI64
    .TruncToI32, // TruncToI32
    .TruncToI16, // TruncToI16
    .TruncToI8, // TruncToI8
    .ExtToF64, // ExtToF64
    .TruncToF32, // TruncToF32
    .IToF32, // IToF32
    .IToF64, // IToF64
    .UToF32, // UToF32
    .UToF64, // UToF64
    .FToI64, // FToI64
    .FToU64, // FToU64
    .BitCastToI32, // BitCastToI32
    .BitCastToI64, // BitCastToI64
    .BitCastToF32, // BitCastToF32
    .BitCastToF64, // BitCastToF64
    .BitCastToI64, // BitCastToPtr
    .Alloc4, // Alloc4
    .Alloc8, // Alloc8
    .Alloc16, // Alloc16
    .Load8, // LoadI8
    .Load16, // LoadI16
    .Load32, // LoadI32
    .Load64, // LoadI64
    .Load32, // LoadF32
    .Load64, // LoadF64
    .Load64, // LoadPtr
    .Store, // Store
    .Blit, // Blit
    .Call, // Call
    .Phi, // Phi
    .Jmp, // Jmp
    .Jnz, // Jnz
    .Ret, // Ret
    .DbgBrk, // DbgBrk
    .DbgSetFile, // DbgSetFile
    .DbgSetLine, // DbgSetLine
];

#assert Bytecode_Opcodes.count == type_info(IROpcode).values.count;
