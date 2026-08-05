IRAppendAssertFailureOrPanicMessage :: (builder : *StringBuilder, elem : *$T, fmt_str : string, args : ..Any) {
    SetColor(builder, .FatalError);
    StringBuilderAppend(builder, "Fatal Error: ");
    SetColor(builder, .None);

    StringBuilderAppend(builder, fmt_str, ..args);
    StringBuilderAppend(builder, "\n");

    #if T == {
    case IRFile;
        StringBuilderAppend(builder, "File:\n%", IRFileToString(elem));
    case IRFunction;
        StringBuilderAppend(builder, "Function:\n%", IRFunctionToString(elem));
    case IRBasicBlock;
        StringBuilderAppend(builder, "Basic block:\n%\n", IRBasicBlockToString(elem));
        StringBuilderAppend(builder, "Function:\n%", IRFunctionToString(elem.func));
    case;
        StringBuilderAppend(builder, "Instruction:\n%", IRInstrToString(elem));
    }
}

IRPanic :: (elem : *$T, fmt_str : string, args : ..Any, location := #caller_location) {
    if !context.handling_assertion_failure {
        g_error_counter += 1;

        context.handling_assertion_failure = true;
        defer context.handling_assertion_failure = false;

        context.panicking = true;
        defer context.panicking = false;

        builder : StringBuilder;

        IRAppendAssertFailureOrPanicMessage(*builder, elem, fmt_str, ..args);

        message := StringBuilderBuild(*builder);

        if context.assertion_failed(location, message) && g_build_settings.break_on_ir_validation_error {
            debug_break();
        }
    }
}
@PrintLike

IRAssert :: (elem : *$T, assertion : bool, fmt_str : string, args : ..Any, location := #caller_location) -> bool {
    if !assertion && !context.handling_assertion_failure {
        g_error_counter += 1;

        context.handling_assertion_failure = true;
        defer context.handling_assertion_failure = false;

        builder : StringBuilder;

        IRAppendAssertFailureOrPanicMessage(*builder, elem, fmt_str, ..args);

        message := StringBuilderBuild(*builder);

        if context.assertion_failed(location, message) && g_build_settings.break_on_ir_validation_error {
            debug_break();
        }
    }

    return assertion;
}
@PrintLike

ValidateBasicBlock :: (block : *IRBasicBlock) -> bool {
    ok := true;
    ok &= IRAssert(block, block.instructions.count > 0, "Empty basic block");
    ok &= IRAssert(block, IsTerminator(block.instructions[block.instructions.count - 1]), "Basic block is not terminated");

    // Already validated in PushInstr
    // for block.instructions {
    //     ok &= ValidateInstr(it);
    // }

    return ok;
}

ValidateFunction :: (func : *IRFunction) -> bool {
    if !(func.flags & .External) {
        IRAssert(func, func.basic_blocks.count > 0, "Empty function");
    }

    if func.flags & .CVariadic {
        IRAssert(func, func.calling_convention == .C, "Expected C calling convention for C variadic function (got %)", func.calling_convention);
        IRAssert(func, func.flags & .External != 0, "C variadic functions can only be external for now");
    }

    ok := true;
    for func.basic_blocks {
        ok &= ValidateBasicBlock(it);
    }

    return ok;
}

ValidateInstr :: (instr : *IRInstr, func : *IRFunction) -> bool {
    if instr.opcode == {
    case .Invalid;
        IRPanic(instr, "Invalid instruction");
        return false;
    case .Add; #through;
    case .Sub; #through;
    case .Mul; #through;
    case .Div; #through;
    case .Rem;
        binary := cast(*IRInstrBinary, instr);
        ok := true;

        if (instr.opcode == .Add || instr.opcode == .Sub) && IsPointer(binary.left.type) {
            return IRAssert(binary, binary.right.type.kind == .Int64, "Pointer arithmetic only allows 64-bit integer operand");
        }

        ok &= IRAssert(binary, binary.left.type == binary.right.type, "Mismatching type for operands (%, %)", binary.left.type, binary.right.type);
        ok &= IRAssert(binary, IsInteger(binary.left.type) || IsFloat(binary.left.type), "Incorrect type for operands");

        return ok;

    case .UDiv; #through;
    case .URem; #through;
    case .And; #through;
    case .Or; #through;
    case .Xor; #through;
    case .Shl; #through;
    case .Shr; #through;
    case .Sar;
        binary := cast(*IRInstrBinary, instr);
        ok := true;
        ok &= IRAssert(binary, binary.left.type == binary.right.type, "Mismatching type for operands");
        ok &= IRAssert(binary, IsInteger(binary.left.type), "Incorrect type for operands");

        return ok;

    case .Neg;
        unary := cast(*IRInstrUnary, instr);
        ok := true;
        ok &= IRAssert(unary, IsInteger(unary.value.type) || IsFloat(unary.value.type), "Incorrect type for operand");

        return ok;

    case .Not;
        unary := cast(*IRInstrUnary, instr);
        ok := true;
        ok &= IRAssert(unary, IsInteger(unary.value.type), "Incorrect type for operand (should be integer)");

        return ok;

    case .CmpEq; #through;
    case .CmpNe;
        binary := cast(*IRInstrBinary, instr);
        ok := true;
        if binary.left.type.kind == .Pointer {
            ok &= IRAssert(binary, binary.left.type == binary.right.type || binary.right.type.kind == .Int64, "Mismatching type for operands");
        } else if binary.right.type.kind == .Pointer {
            ok &= IRAssert(binary, binary.left.type == binary.right.type || binary.left.type.kind == .Int64, "Mismatching type for operands");
        } else {
            ok &= IRAssert(binary, binary.left.type == binary.right.type, "Mismatching type for operands");
        }

        return ok;

    case .CmpFLt; #through;
    case .CmpFLe; #through;
    case .CmpFGt; #through;
    case .CmpFGe;
        binary := cast(*IRInstrBinary, instr);
        ok := true;
        ok &= IRAssert(binary, binary.left.type == binary.right.type, "Mismatching type for operands");
        ok &= IRAssert(binary, IsFloat(binary.left.type), "Incorrect type for operands (should be float)");

        return ok;

    case .CmpSLt; #through;
    case .CmpSLe; #through;
    case .CmpSGt; #through;
    case .CmpSGe; #through;
    case .CmpULt; #through;
    case .CmpULe; #through;
    case .CmpUGt; #through;
    case .CmpUGe;
        binary := cast(*IRInstrBinary, instr);
        ok := true;
        ok &= IRAssert(binary, binary.left.type == binary.right.type, "Mismatching type for operands");
        ok &= IRAssert(binary, IsInteger(binary.left.type), "Incorrect type for operands (should be integer)");

        return ok;

    case .SExtToI16; #through;
    case .ZExtToI16;
        unary := cast(*IRInstrUnary, instr);
        return IRAssert(unary, unary.value.type.kind == .Int8, "Incorrect type for operand (should be i8)");

    case .SExtToI32; #through;
    case .ZExtToI32;
        unary := cast(*IRInstrUnary, instr);
        return IRAssert(unary, unary.value.type.kind == .Int8 || unary.value.type.kind == .Int16, "Incorrect type for operand (should be i8 or i16)");

    case .SExtToI64; #through;
    case .ZExtToI64;
        unary := cast(*IRInstrUnary, instr);
        return IRAssert(unary, unary.value.type.kind == .Int8 || unary.value.type.kind == .Int16 || unary.value.type.kind == .Int32, "Incorrect type for operand (should be i8, i16 or i32)");

    case .TruncToI32;
        unary := cast(*IRInstrUnary, instr);
        return IRAssert(unary, unary.value.type.kind == .Int64, "Incorrect type for operand (should be i64)");

    case .TruncToI16;
        unary := cast(*IRInstrUnary, instr);
        return IRAssert(unary, unary.value.type.kind == .Int64 || unary.value.type.kind == .Int32, "Incorrect type for operand (should be i64 or i32)");

    case .TruncToI8;
        unary := cast(*IRInstrUnary, instr);
        return IRAssert(unary, unary.value.type.kind == .Int64 || unary.value.type.kind == .Int32 || unary.value.type.kind == .Int16, "Incorrect type for operand (should be i64, i32 or i16)");

    case .ExtToF64;
        unary := cast(*IRInstrUnary, instr);
        return IRAssert(unary, unary.value.type.kind == .Float32, "Incorrect type for operand (should be f32)");

    case .TruncToF32;
        unary := cast(*IRInstrUnary, instr);
        return IRAssert(unary, unary.value.type.kind == .Float64, "Incorrect type for operand (should be f64)");

    case .IToF32; #through;
    case .IToF64; #through;
    case .UToF32; #through;
    case .UToF64;
        unary := cast(*IRInstrUnary, instr);
        return IRAssert(unary, IsInteger(unary.value.type), "Incorrect type for operand (should be integer)");

    case .FToI64; #through;
    case .FToU64;
        unary := cast(*IRInstrUnary, instr);
        return IRAssert(unary, IsFloat(unary.value.type), "Incorrect type for operand (should be float)");

    case .BitCastToI32;
        unary := cast(*IRInstrUnary, instr);
        return IRAssert(unary, unary.value.type.kind == .Float32, "Incorrect type for operand (should be f32)");

    case .BitCastToI64;
        unary := cast(*IRInstrUnary, instr);
        return IRAssert(unary, unary.value.type.kind == .Float64 || unary.value.type.kind == .Pointer, "Incorrect type for operand (should be f64 or ptr)");

    case .BitCastToF32;
        unary := cast(*IRInstrUnary, instr);
        return IRAssert(unary, unary.value.type.kind == .Int32, "Incorrect type for operand (should be i32)");

    case .BitCastToF64;
        unary := cast(*IRInstrUnary, instr);
        return IRAssert(unary, unary.value.type.kind == .Int64 || unary.value.type.kind == .Pointer, "Incorrect type for operand (should be i64 or ptr)");

    case .BitCastToPtr;
        unary := cast(*IRInstrUnary, instr);
        return IRAssert(unary, unary.value.type.kind == .Int64 || unary.value.type.kind == .Float64, "Incorrect type for operand (should be i64 or f64)");

    case .Alloc4; #through;
    case .Alloc8; #through;
    case .Alloc16;
        alloc := cast(*IRInstrAlloc, instr);
        ok := true;
        ok &= IRAssert(alloc, alloc.size.type.kind == .Int64, "Invalid type % for alloc size operand", alloc.size.type.kind);
        ok &= IRAssert(alloc, alloc.size.symbol == null, "Size operand is not an immediate value");
        return ok;

    case .LoadI8; #through;
    case .LoadI16; #through;
    case .LoadI32; #through;
    case .LoadI64; #through;
    case .LoadF32; #through;
    case .LoadF64; #through;
    case .LoadPtr;
        load := cast(*IRInstrLoad, instr);
        ok := true;
        ok &= IRAssert(load, load.src_addr.type.kind == .Pointer, "Invalid type % for source operand", load.src_addr.type.kind);
        return ok;

    case .Store;
        store := cast(*IRInstrStore, instr);
        ok := true;
        ok &= IRAssert(store, IsTemporary(store.src.type), "Invalid type % for source operand", store.src.type.kind);
        ok &= IRAssert(store, store.dst_addr.type.kind == .Pointer, "Invalid type % for destination operand", store.dst_addr.type.kind);

        return ok;

    case .Blit;
        blit := cast(*IRInstrBlit, instr);
        ok := true;
        ok &= IRAssert(blit, blit.src_addr.type.kind == .Pointer, "Invalid type % for source operand", blit.src_addr.type.kind);
        ok &= IRAssert(blit, blit.dst_addr.type.kind == .Pointer, "Invalid type % for destination operand", blit.dst_addr.type.kind);
        ok &= IRAssert(blit, blit.size.type.kind == .Int64, "Invalid type % for size operand", blit.size.type.kind);
        ok &= IRAssert(blit, blit.size.symbol == null, "Size operand is not an immediate value");

        return ok;

    case .Call;
        call := cast(*IRInstrCall, instr);
        ok := true;
        ok &= IRAssert(call, call.callee.type.kind == .Pointer, "Callee operand in call instruction is not a pointer");

        if call.callee.symbol && call.callee.symbol.kind == .Function {
            func := cast(*IRFunction, call.callee.symbol);
            variadic := call.first_c_variadic_argument_index >= 0;
            arity_match := variadic && call.arguments.count >= func.parameters.count || call.arguments.count == func.parameters.count;
            ok &= IRAssert(call, arity_match, "Mismatching number of arguments in call instruction (expected %0%, got %)", ifx variadic then "at least ", func.parameters.count, call.arguments.count);
        }

    case .Phi;
        phi := cast(*IRInstrPhi, instr);
        ok := true;
        ok &= IRAssert(phi, phi.values.count > 1, "Phi must have at least two values");
        for phi.values {
            ok &= IRAssert(phi, IsBasicBlock(it.block), "Phi operand 0 for value % is not a basic block", it_index);
            ok &= IRAssert(phi, it.value.type == phi.symbol.type, "Mismatching type for phi operand 1 in value %: expected % but got %", it_index, phi.symbol.type, it.value.type);

            for other, j : phi.values {
                if it_index == j {
                    continue;
                }

                ok &= IRAssert(phi, it.block.symbol != other.block.symbol, "Block appears more than once in phi instruction");
            }
        }

        return ok;

    case .Jmp;
        jmp := cast(*IRInstrJmp, instr);
        ok := true;
        ok &= IRAssert(jmp, IsBasicBlock(jmp.block), "Block operand is not a basic block symbol");

        return ok;

    case .Jnz;
        jnz := cast(*IRInstrJnz, instr);
        ok := true;
        ok &= IRAssert(jnz, jnz.value.type.kind != .Void && jnz.value.type.kind != .Typedef, "Invalid type % for value operand", jnz.value.type.kind);
        ok &= IRAssert(jnz, IsBasicBlock(jnz.if_true), "'true' operand is not a basic block symbol");
        ok &= IRAssert(jnz, IsBasicBlock(jnz.if_false), "'false' operand is not a basic block symbol");

        return ok;

    case .Ret;
        ret := cast(*IRInstrRet, instr);

        ok := true;
        if func.result_type.kind == .Typedef {
            ok &= IRAssert(ret, ret.value.type == func.result_type || ret.value.type.kind == .Pointer, "Invalid type for return value");
        } else {
            ok &= IRAssert(ret, ret.value.type == func.result_type, "Invalid type for return value");
        }

        return ok;
    }

    return false;
}
