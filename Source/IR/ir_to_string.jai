IRFileToString :: (file : *IRFile, append_debug_info := false) -> string {
    builder : StringBuilder;
    AppendFile(*builder, file, append_debug_info);

    return StringBuilderBuild(*builder);
}

IRGlobalDataToString :: (data : *IRGlobalData) -> string {
    builder : StringBuilder;
    AppendGlobalData(*builder, data);

    return StringBuilderBuild(*builder);
}

IRFunctionToString :: (func : *IRFunction, append_debug_info := false) -> string {
    builder : StringBuilder;
    AppendFunction(*builder, func, append_debug_info);

    return StringBuilderBuild(*builder);
}

IRBasicBlockToString :: (block : *IRBasicBlock, append_debug_info := false) -> string {
    builder : StringBuilder;
    AppendBasicBlock(*builder, block, append_debug_info);

    return StringBuilderBuild(*builder);
}

IRInstrToString :: (instr : *IRInstr) -> string {
    builder : StringBuilder;
    AppendInstr(*builder, instr);

    return StringBuilderBuild(*builder);
}

AppendFile :: (builder : *StringBuilder, file : *IRFile, append_debug_info := false) {
    for file.global_data {
        AppendGlobalData(builder, it);
        Append(builder, "\n");
    }

    Append(builder, "\n");

    for file.typedefs {
        AppendTypedef(builder, it);
        Append(builder, "\n");
    }

    Append(builder, "\n");

    for file.functions {
        AppendFunction(builder, it, append_debug_info);
        Append(builder, "\n");
    }
}

AppendType :: (builder : *StringBuilder, type : *IRType) {
    if #complete type.kind == {
    case .Invalid;
        Append(builder, "<invalid>");
    case .Void;
        Append(builder, "void");
    case .Int8;
        Append(builder, "i8");
    case .Int16;
        Append(builder, "i16");
    case .Int32;
        Append(builder, "i32");
    case .Int64;
        Append(builder, "i64");
    case .Float32;
        Append(builder, "f32");
    case .Float64;
        Append(builder, "f64");
    case .Pointer;
        Append(builder, "ptr");
    case .Typedef;
        Append(builder, "%", type.typedef.symbol.name);
    case;
        Append(builder, "<corrupt>");
    }
}

AppendTypedef :: (builder : *StringBuilder, typedef : *IRTypedef) {
    Append(builder, "type %", typedef.name);

    if typedef.is_union {
        Append(builder, " union");
    }

    if typedef.align {
        Append(builder, " align %", typedef.align);
    }

    Append(builder, " {");
    for typedef.members {
        if it_index != 0 {
            Append(builder, ", ");
        }

        AppendType(builder, *it.type);

        if it.num_elements > 1 {
            Append(builder, " %", it.num_elements);
        }
    }
    Append(builder, "}");
}

AppendFunction :: (builder : *StringBuilder, func : *IRFunction, append_debug_info := false) {
    if func.flags & .External {
        Append(builder, "@external");
        if func.library_name {
            Append(builder, " @library \"%\"", func.library_name);
        }
        Append(builder, "\n");
    }

    Append(builder, "func %(", func.symbol.name);

    for func.parameters {
        if it_index != 0 {
            Append(builder, ", ");
        }

        AppendType(builder, *it.type);
        Append(builder, " %", it.name);
    }

    if func.flags & .CVariadic {
        if func.parameters.count > 0 {
            Append(builder, ", ");
        }

        Append(builder, "...");
    }

    Append(builder, ") ");
    AppendType(builder, *func.result_type);

    if func.flags & .External {
        Append(builder, "\n");
        return;
    } else {
        Append(builder, " {\n");

        for func.basic_blocks {
            AppendBasicBlock(builder, it, append_debug_info);
        }

        Append(builder, "}\n");
    }
}

AppendBasicBlock :: (builder : *StringBuilder, block : *IRBasicBlock, append_debug_info := false) {
    Append(builder, "%\n", block.symbol.name);
    for block.instructions {
        if !append_debug_info && (it.opcode == .DbgSetFile || it.opcode == .DbgSetLine) {
            continue;
        }

        AppendInstr(builder, it);
        Append(builder, "\n");
    }
}

AppendInstr :: (builder : *StringBuilder, instr : *IRInstr) {
    Append(builder, "  ");

    if instr.symbol.type.kind != .Invalid && instr.symbol.type.kind != .Void {
        Append(builder, "% =", instr.symbol.name);
        AppendType(builder, *instr.symbol.type);
        Append(builder, " ");
    }

    Append(builder, "%", IR_Opcode_Mnemonics[instr.opcode]);

    if #complete instr.opcode == {
    case .Invalid;
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
        Append(builder, " ");
        AppendOp(builder, binary.left);
        Append(builder, ", ");
        AppendOp(builder, binary.right);

    case .Neg; #through;
    case .Not;
        unary := cast(*IRInstrUnary, instr);
        Append(builder, " ");
        AppendOp(builder, unary.value);

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
        c := cast(*IRInstrUnary, instr);
        Append(builder, " ");
        AppendOp(builder, c.value);

    case .Alloc4; #through;
    case .Alloc8; #through;
    case .Alloc16;
        alloc := cast(*IRInstrAlloc, instr);
        Append(builder, " ");
        AppendOp(builder, alloc.size);

    case .LoadI8; #through;
    case .LoadI16; #through;
    case .LoadI32; #through;
    case .LoadI64; #through;
    case .LoadF32; #through;
    case .LoadF64; #through;
    case .LoadPtr;
        load := cast(*IRInstrLoad, instr);
        Append(builder, " ");
        AppendOp(builder, load.src_addr);

    case .Store;
        store := cast(*IRInstrStore, instr);
        Append(builder, " ");
        AppendOp(builder, store.src);
        Append(builder, ", ");
        AppendOp(builder, store.dst_addr);

    case .Blit;
        blit := cast(*IRInstrBlit, instr);
        Append(builder, " ");
        AppendOp(builder, blit.src_addr);
        Append(builder, ", ");
        AppendOp(builder, blit.dst_addr);
        Append(builder, ", ");
        AppendOp(builder, blit.size);

    case .Call;
        call := cast(*IRInstrCall, instr);
        Append(builder, " ");

        if #complete call.calling_convention == {
        case .Unknown;
            IRPanic(instr, "Unknown calling convention");
            Append(builder, "\"?\" ");

        case .Yal;
        case .C;
            Append(builder, "\"c\" ");
        }

        AppendType(builder, *call.result_type);
        Append(builder, " ");
        AppendOp(builder, call.callee);
        Append(builder, "(");
        for call.arguments {
            if it_index > 0 {
                Append(builder, ", ");
            }
            if it_index == call.first_c_variadic_argument_index {
                Append(builder, "... ");
            }

            AppendType(builder, *it.type);
            Append(builder, " ");
            AppendOp(builder, it, append_type_if_immediate=false);
        }
        Append(builder, ")");

    case .Phi;
        phi := cast(*IRInstrPhi, instr);
        for phi.values {
            Append(builder, " [");
            AppendOp(builder, it.block);
            Append(builder, ", ");
            AppendOp(builder, it.value);
            Append(builder, "]");
        }

    case .Jmp;
        jmp := cast(*IRInstrJmp, instr);
        Append(builder, " ");
        AppendOp(builder, jmp.block);
    case .Jnz;
        jnz := cast(*IRInstrJnz, instr);
        Append(builder, " ");
        AppendOp(builder, jnz.value);
        Append(builder, ", ");
        AppendOp(builder, jnz.if_true);
        Append(builder, ", ");
        AppendOp(builder, jnz.if_false);
    case .Ret;
        ret := cast(*IRInstrRet, instr);

        if ret.value.type.kind != .Invalid && ret.value.type.kind != .Void {
            Append(builder, " ");
            AppendOp(builder, ret.value);
        }
    case .DbgBrk;
    case .DbgSetFile; #through;
    case .DbgSetLine;
        set := cast(*IRInstrDbgSet, instr);
        Append(builder, " ");
        Append(builder, "%", set.value.value);
    }
}

AppendOp :: (builder : *StringBuilder, op : IROperand, append_type_if_immediate := true) {
    if op.symbol {
        Append(builder, "%", op.symbol.name);
    } else {
        if append_type_if_immediate {
            AppendType(builder, *op.type);
            Append(builder, " ");
        }

        if op.type.kind == .Float32 {
            Append(builder, "0x%", FormatIntHex(cast,no_check(u32, op.value), digits=8));
        } else if op.type.kind == .Float64 {
            Append(builder, "0x%", FormatIntHex(op.value, digits=16));
        } else {
            Append(builder, "%", op.value);
        }
    }
}

AppendGlobalData :: (builder : *StringBuilder, data : *IRGlobalData) {
    Append(builder, "data %", data.name);
    if data.align > 0 {
        Append(builder, " align %", data.align);
    }
    Append(builder, " {");

    for data.fields {
        if it_index > 0 {
            Append(builder, ", ");
        }

        if #complete it.kind == {
        case .String;
            AppendType(builder, *(IRType.{kind=.Int8}));
            Append(builder, " ");
            StringBuilderAppendStringLiteral(builder, it.string_value);

        case .ZeroBytes;
            Append(builder, "z %", it.num_zero_bytes);

        case .ConstValue;
            AppendType(builder, *(IRType.{kind=it.const_type}));
            Append(builder, " %", it.const_value);

        case .SymbolReference;
            AppendType(builder, *(IRType.{kind=.Pointer}));
            if it.referenced_symbol {
                Append(builder, " %", it.referenced_symbol.name);
            } else {
                Append(builder, " 0");
            }
        }
    }
    Append(builder, "}");
}
