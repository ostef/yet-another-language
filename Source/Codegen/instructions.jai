IRInstr :: struct
{
    #as symbol : *IRSymbol;
    #as kind : IRInstrKind;
}

IRInstrKind :: enum u8
{
    Invalid;

    Add;
    Sub;
    Mul;
    Div;
    Rem;

    And;
    Or;
    Xor;
    Shift_Left;
    Shift_Right;

    Comp_Eq;
    Comp_Ne;
    Comp_Lt;
    Comp_Gt;
    Comp_Le;
    Comp_Ge;

    Call;
    Branch;
    Return;

    Load;
    Store;
    Access;
    Alloca;

    Phi;
    Cast;
}

IRInstrBinop :: struct
{
    #as using base : IRInstr;

    left : IROperand;
    right : IROperand;
}

IRInstrCall :: struct
{
    #as using base : IRInstr;
    base.kind = .Call;

    callee : IROperand;
    args : []IROperand;
}

IRInstrBranch :: struct
{
    #as using base : IRInstr;
    base.kind = .Branch;

    condition : IROperand;
    label_true : IROperand;
    label_false : IROperand;
}

IRInstrReturn :: struct
{
    #as using base : IRInstr;
    base.kind = .Return;

    value : IROperand;
}

IRInstrLoad :: struct
{
    #as using base : IRInstr;
    base.kind = .Load;

    src_pointer : IROperand;
}

IRInstrStore :: struct
{
    #as using base : IRInstr;
    base.kind = .Store;

    src_value : IROperand;
    dst_pointer : IROperand;
}

IRInstrAccess :: struct
{
    #as using base : IRInstr;
    base.kind = .Access;

    pointer_value : IROperand;
    indices : []IROperand;
}

IRInstrAlloca :: struct
{
    #as using base : IRInstr;
    base.kind = .Alloca;

    type : *IRType;
    count : IROperand;
}

IRInstrPhi :: struct
{
    Input :: struct
    {
        from_label : IROperand;
        result_value : IROperand;
    }

    #as using base : IRInstr;
    base.kind = .Phi;

    inputs : []Input;
}

IRInstrCast :: struct
{
    #as using base : IRInstr;
    base.kind = .Cast;

    dst_type : *IRType;
    src_value : IROperand;
}

IsTerminatorInstruction :: inline (instr : IRInstrKind) -> bool #must
{
    if instr ==
    {
    case .Branch; #through;
    case .Return;
        return true;
    }

    return false;
}

VerifyInstruction :: (instr : IRInstr) -> bool
{
    if #complete instr.kind ==
    {
    case .Invalid; #through;
    case;
        IRPanic (instr, "Invalid instruction");
        return false;

    case .Add; #through;
    case .Sub; #through;
    case .Mul; #through;
    case .Div; #through;
    case .Rem;
        binop := cast (*IRInstrBinop) *instr;
        if !IRAssert (instr, IsNumericType (binop.left.type.*), "Invalid type for instruction operands, should be numeric")
            return false;

        if !IRAssert (instr, TypesAreEqual (binop.left.type, binop.right.type), "Type mismatch for instruction operands")
            return false;

    case .And; #through;
    case .Or; #through;
    case .Xor;
        binop := cast (*IRInstrBinop) *instr;
        IRAssert (instr, IsIntegralType (binop.left.type.*),
            "Invalid type for instruction operands, should be integral");

        IRAssert (instr, TypesAreEqual (binop.left.type, binop.right.type),
            "Type mismatch for instruction operands");

    case .Comp_Eq; #through;
    case .Comp_Ne; #through;
    case .Comp_Lt; #through;
    case .Comp_Gt; #through;
    case .Comp_Le; #through;
    case .Comp_Ge;
        binop := cast (*IRInstrBinop) *instr;
        if !IRAssert (instr, IsFirstClassType (binop.left.type.*), "Invalid type for instruction operands, should be first class")
            return false;

        if !IRAssert (instr, TypesAreEqual (binop.left.type, binop.right.type), "Type mismatch for instruction operands")
            return false;

    case .Shift_Left; #through;
    case .Shift_Right;
        binop := cast (*IRInstrBinop) *instr;
        if !IRAssert (instr, IsIntegerType (binop.left.type.kind), "Invalid type for first operand, should be an integer")
            return false;

        if !IRAssert (instr, binop.right.type.kind == .U8, "Invalid type for second operand, should be a u8")
            return false;

    case .Call;
        call := cast (*IRInstrCall) *instr;

        if !IRAssert (instr, call.callee.type.kind == .Pointer,
            "Invalid type for callee operand, should be a pointer to a procedure")
            return false;

        if !IRAssert (instr, call.callee.type.pointer.type.kind == .Procedure,
            "Invalid type for callee operand, should be a pointer to a procedure")
            return false;

        proc_type := call.callee.type.pointer.type;

        if !IRAssert (instr, call.args.count == proc_type.procedure.param_types.count,
            "Invalid number of argument provided for procedure call, expected % but got %",
            proc_type.procedure.param_types.count,
            call.args.count
        )
            return false;

        for call.args
        {
            if !IRAssert (instr, TypesAreEqual (it.type, proc_type.procedure.param_types[it_index]), "Invalid type for argument %", it_index)
                return false;
        }

        return true;

    case .Branch;
        branch := cast (*IRInstrBranch) *instr;

        if !IRAssert (instr, branch.condition.type.kind == .Bool, "Invalid type for branch condition")
            return false;
        if !IRAssert (instr, branch.label_true.type.kind == .Label, "Invalid type for branch true label")
            return false;
        if !IRAssert (instr, branch.label_false.type.kind == .Label, "Invalid type for branch falsee label")
            return false;

    case .Return;
        ret := cast (*IRInstrReturn) *instr;

        if !IRAssert (instr, IsFirstClassType (ret.value.type.kind), "Invalid type for return value, should be a first class type")
            return false;

    case .Load;
        load := cast (*IRInstrLoad) *instr;

        if !IRAssert (instr, load.src_pointer.type.kind == .Pointer, "Invalid type for source operand, should be a pointer type")
            return false;

    case .Store;
        store := cast (*IRInstrStore) *instr;

        if !IRAssert (instr, store.dst_pointer.type.kind == .Pointer, "Invalid type for dest operand, should be a pointer type")
            return false;

        if !IRAssert (instr, TypesAreEqual (store.dst_pointer.type.pointer.type, store.src_value.type), "Type mismatch for instruction operands")
            return false;

    case .Access;
        IRPanic (instr, "Not yet handled");
        return false;

    case .Alloca;
        alloca := cast (*IRInstrAlloca) *instr;

        if !IRAssert (instr, alloca.count.type.kind == .S64, "Invalid type for count operand, should be s64")
            return false;

    case .Phi;
        phi := cast (*IRInstrPhi) *instr;

        for phi.inputs
        {
            if it_index != 0
            && !IRAssert (instr, TypesAreEqual (phi.inputs[0].result_value.type, it.result_value.type), "Type mismatch for result value")
                return false;

            if !IRAssert (instr, IsFirstClassType (it.result_value.type.kind), "Invalid type for result value, should be a first class type")
                return false;

            if !IRAssert (instr, it.from_label.type.kind == .Label, "Invalid type for label operand")
                return false;
        }

        return true;

    case .Cast;
        cast_instr := cast (*IRInstrCast) *instr;

        if !IRAssert (instr, IsFirstClassType (cast_instr.dst_type.kind), "Invalid type for cast, should be first class")
            return false;

        if !IRAssert (instr, IsFirstClassType (cast_instr.src_value.type.kind), "Invalid type for cast source operand, should be first class")
            return false;
    }

    return true;
}

GetResultType :: (using builder : *IRBuilder, instr : IRInstr) -> *IRType #must
{
    if #complete instr.kind ==
    {
    case .Invalid;
        return g_ir_type_invalid;

    case .Add; #through;
    case .Sub; #through;
    case .Mul; #through;
    case .Div; #through;
    case .Rem; #through;
    case .And; #through;
    case .Or; #through;
    case .Xor; #through;
    case .Shift_Left; #through;
    case .Shift_Right;
        binop := cast (*IRInstrBinop) *instr;
        return binop.left.type;

    case .Comp_Eq; #through;
    case .Comp_Ne; #through;
    case .Comp_Lt; #through;
    case .Comp_Gt; #through;
    case .Comp_Le; #through;
    case .Comp_Ge;
        return g_ir_type_bool;

    case .Call;
        call := cast (*IRInstrCall) *instr;
        return call.callee.type.procedure.return_type;

    case .Branch;
        return g_ir_type_void;

    case .Return;
        return g_ir_type_void;

    case .Load;
        load := cast (*IRInstrLoad) *instr;
        return load.src_pointer.type.pointer.type;

    case .Store;
        return g_ir_type_void;

    case .Access;
        IRPanic (instr, "Not yet handled");
        return g_ir_type_void;

    case .Alloca;
        alloca := cast (*IRInstrAlloca) *instr;
        return MakeIRPointerType (alloca.type);

    case .Phi;
        phi := cast (*IRInstrPhi) *instr;
        return phi.inputs[0].result_value.type;

    case .Cast;
        cast_instr := cast (*IRInstrCast) *instr;
        return cast_instr.dst_type;
    }
}

PushInstr :: (using builder : *IRBuilder, instr : IRInstr) -> *IRInstr
{
    Assert (current_basic_block != null);

    VerifyInstruction (instr);

    if instr.kind == .Phi && current_basic_block.instructions.count != 0
        IRPanic (instr, "Phi should be the first instruction in a basic block");

    return ArrayPush (*current_basic_block.instructions, instr);
}

PushInstr :: (using builder : *IRBuilder, instr : IRInstr, value_name : string) -> IROperand
{
    result := inline PushInstr (builder, instr);

    unique_name := MakeUniqueName (*builder.current_basic_block.proc.symbol_table, value_name);

    result.symbol = Alloc (IRSymbol);
    result.symbol.name = unique_name;
    result.symbol.type = GetResultType (builder, instr);
    result.symbol.symbol_kind = .Local_Value;
    result.symbol.block = current_basic_block;

    InsertUniqueSymbol (*builder.current_basic_block.proc.symbol_table, result.symbol);
    InsertUniqueSymbol (*builder.current_basic_block.proc.symbol_table, result.symbol);

    return MakeIROperand (result.symbol);
}

EmitBinop :: inline (builder : *IRBuilder, kind : IRInstrKind, left : IROperand, right : IROperand, value_name : string) -> IROperand
{
    instr : IRInstrBinop;
    instr.kind = kind;
    instr.left = left;
    instr.right = right;

    return PushInstr (builder, instr, value_name);
}

EmitAdd :: #bake_arguments EmitBinop (kind = .Add);
EmitSub :: #bake_arguments EmitBinop (kind = .Sub);
EmitMul :: #bake_arguments EmitBinop (kind = .Mul);
EmitDiv :: #bake_arguments EmitBinop (kind = .Div);
EmitRem :: #bake_arguments EmitBinop (kind = .Rem);
EmitAnd :: #bake_arguments EmitBinop (kind = .And);
EmitOr :: #bake_arguments EmitBinop (kind = .Or);
EmitXor :: #bake_arguments EmitBinop (kind = .Xor);
EmitShiftLeft :: #bake_arguments EmitBinop (kind = .Shift_Left);
EmitShiftRight :: #bake_arguments EmitBinop (kind = .Shift_Right);
EmitCompEq :: #bake_arguments EmitBinop (kind = .Comp_Eq);
EmitCompNe :: #bake_arguments EmitBinop (kind = .Comp_Ne);
EmitCompLt :: #bake_arguments EmitBinop (kind = .Comp_Lt);
EmitCompGt :: #bake_arguments EmitBinop (kind = .Comp_Gt);
EmitCompLe :: #bake_arguments EmitBinop (kind = .Comp_Le);
EmitCompGe :: #bake_arguments EmitBinop (kind = .Comp_Ge);

EmitCall :: inline (builder : *IRBuilder, callee : IROperand, args : []IROperand, value_name : string) -> IROperand
{
    instr : IRInstrCall;
    instr.callee = callee;
    instr.args = args;

    return PushInstr (builder, instr, value_name);
}

EmitCall :: inline (builder : *IRBuilder, callee : IROperand, args : []IROperand)
{
    instr : IRInstrCall;
    instr.callee = callee;
    instr.args = args;

    PushInstr (builder, instr);
}

EmitBranch :: inline (builder : *IRBuilder, condition : IROperand, label_true : IROperand, label_false : IROperand)
{
    instr : IRInstrBranch;
    instr.condition = condition;
    instr.label_true = label_true;
    instr.label_false = label_false;

    PushInstr (builder, instr);
}

EmitReturn :: inline (builder : *IRBuilder, value : IROperand)
{
    instr : IRInstrReturn;
    instr.value = value;

    PushInstr (builder, instr);
}

EmitLoad :: inline (builder : *IRBuilder, src_pointer : IROperand, value_name : string) -> IROperand
{
    instr : IRInstrLoad;
    instr.src_pointer = src_pointer;

    return PushInstr (builder, instr, value_name);
}

EmitStore :: inline (builder : *IRBuilder, src_value : IROperand, dst_pointer : IROperand)
{
    instr : IRInstrStore;
    instr.src_value = src_value;
    instr.dst_pointer = dst_pointer;

    PushInstr (builder, instr);
}

EmitAccess :: inline (builder : *IRBuilder, pointer_value : IROperand, indices : []IROperand, value_name : string) -> IROperand
{
    instr : IRInstrAccess;
    instr.pointer_value = pointer_value;
    instr.indices = indices;

    return PushInstr (builder, instr, value_name);
}

EmitAlloca :: inline (builder : *IRBuilder, type : *IRType, count : IROperand, value_name : string) -> IROperand
{
    instr : IRInstrAlloca;
    instr.type = type;
    instr.count = count;

    return PushInstr (builder, instr, value_name);
}

EmitPhi :: inline (builder : *IRBuilder, inputs : []IRInstrPhi.Input, value_name : string) -> IROperand
{
    instr : IRInstrPhi;
    instr.inputs = inputs;

    return PushInstr (builder, instr, value_name);
}

EmitCast :: inline (builder : *IRBuilder, dst_type : *IRType, src_value : IROperand, value_name : string) -> IROperand
{
    instr : IRInstrCast;
    instr.dst_type = dst_type;
    instr.src_value = src_value;

    return PushInstr (builder, instr, value_name);
}
