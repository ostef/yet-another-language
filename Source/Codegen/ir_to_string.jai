AppendIRType :: (builder : *StringBuilder, type : IRType.Kind)
{
    if type ==
    {
    case .Invalid;
        StringBuilderAppend (builder, "invalid");
    case .Void;
        StringBuilderAppend (builder, "void");
    case .U8;
        StringBuilderAppend (builder, "u8");
    case .S8;
        StringBuilderAppend (builder, "s8");
    case .U16;
        StringBuilderAppend (builder, "u16");
    case .S16;
        StringBuilderAppend (builder, "s16");
    case .U32;
        StringBuilderAppend (builder, "u32");
    case .S32;
        StringBuilderAppend (builder, "s32");
    case .U64;
        StringBuilderAppend (builder, "u64");
    case .S64;
        StringBuilderAppend (builder, "s64");
    case .F32;
        StringBuilderAppend (builder, "f32");
    case .F64;
        StringBuilderAppend (builder, "f64");
    case .Bool;
        StringBuilderAppend (builder, "bool");
    case .Label;
        StringBuilderAppend (builder, "label");
    case;
        Panic ();
    }
}

AppendIRType :: (builder : *StringBuilder, type : IRType)
{
    if #complete type.kind ==
    {
    case .Invalid;
        StringBuilderAppend (builder, "invalid");
    case .Void;
        StringBuilderAppend (builder, "void");
    case .U8;
        StringBuilderAppend (builder, "u8");
    case .S8;
        StringBuilderAppend (builder, "s8");
    case .U16;
        StringBuilderAppend (builder, "u16");
    case .S16;
        StringBuilderAppend (builder, "s16");
    case .U32;
        StringBuilderAppend (builder, "u32");
    case .S32;
        StringBuilderAppend (builder, "s32");
    case .U64;
        StringBuilderAppend (builder, "u64");
    case .S64;
        StringBuilderAppend (builder, "s64");
    case .F32;
        StringBuilderAppend (builder, "f32");
    case .F64;
        StringBuilderAppend (builder, "f64");
    case .Bool;
        StringBuilderAppend (builder, "bool");
    case .Label;
        StringBuilderAppend (builder, "label");

    case .Procedure;
        StringBuilderAppend (builder, "(");

        for type.procedure.param_types
        {
            if it_index != 0
                StringBuilderAppend (builder, ", ");

            AppendIRType (builder, it);
        }

        StringBuilderAppend (builder, ") ");
        AppendIRType (builder, type.procedure.return_type);

    case .Pointer;
        StringBuilderAppend (builder, "*");
        AppendIRType (builder, type.pointer.type);

    case .Array;
        StringBuilderAppend (builder, "[%]", type.array.count);
        AppendIRType (builder, type.array.type);

    case .Struct;
        StringBuilderAppend (builder, "{");

        for type.aggregate.member_types
        {
            if it_index != 0
                StringBuilderAppend (builder, ", ");

            AppendIRType (builder, it);
        }

        StringBuilderAppend (builder, "}");
    }
}

AppendIROperand :: (builder : *StringBuilder, op : IROperand)
{
    AppendIRType (builder, op.type);

    if #complete op.kind ==
    {
    case .Named_Value;
        if IsGlobalSymbol (op.symbol)
            StringBuilderAppend (builder, " @%", op.symbol.name);
        else
            StringBuilderAppend (builder, " \%%", op.symbol.name);

    case .Immediate_Value;
        if op.type.kind ==
        {
        case .Void;
        case .Bool; StringBuilderAppend (builder, " %", op.bool_value);
        case .U8;   StringBuilderAppend (builder, " %", op.u8_value);
        case .S8;   StringBuilderAppend (builder, " %", op.s8_value);
        case .U16;  StringBuilderAppend (builder, " %", op.u16_value);
        case .S16;  StringBuilderAppend (builder, " %", op.s16_value);
        case .U32;  StringBuilderAppend (builder, " %", op.u32_value);
        case .S32;  StringBuilderAppend (builder, " %", op.s32_value);
        case .U64;  StringBuilderAppend (builder, " %", op.u64_value);
        case .S64;  StringBuilderAppend (builder, " %", op.s64_value);
        case .F32;  StringBuilderAppend (builder, " %", op.f32_value);
        case .F64;  StringBuilderAppend (builder, " %", op.f64_value);
        case;
            Panic ("Invalid type % for immediate value operand", op.type.kind);
        }
    }
}

AppendIRInstrBinop :: (builder : *StringBuilder, instr : IRInstrBinop)
{
    name := "";

    if instr.kind ==
    {
    case .Add; name = "add";
    case .Sub; name = "sub";
    case .Mul; name = "mul";
    case .Div; name = "div";
    case .Rem; name = "rem";
    case .And; name = "and";
    case .Or; name = "or";
    case .Xor; name = "xor";
    case .Shift_Left; name = "shiftl";
    case .Shift_Right; name = "shiftr";
    case .Comp_Eq; name = "compeq";
    case .Comp_Ne; name = "compne";
    case .Comp_Lt; name = "complt";
    case .Comp_Gt; name = "compgt";
    case .Comp_Le; name = "comple";
    case .Comp_Ge; name = "compge";
    }

    StringBuilderAppend (builder, "% ", name);
    AppendIROperand (builder, instr.left);
    StringBuilderAppend (builder, ", ");
    AppendIROperand (builder, instr.right);
}

AppendIRInstr :: (builder : *StringBuilder, instr : IRInstr)
{
    if instr.symbol
    {
        if IsGlobalSymbol (instr.symbol)
            StringBuilderAppend (builder, "@% = ", instr.symbol.name);
        else
            StringBuilderAppend (builder, "\%% = ", instr.symbol.name);
    }

    if #complete instr.kind ==
    {
    case .Invalid;
        StringBuilderAppend (builder, "<invalid>");

    case .Add; #through;
    case .Sub; #through;
    case .Mul; #through;
    case .Div; #through;
    case .Rem; #through;
    case .And; #through;
    case .Or; #through;
    case .Xor; #through;
    case .Shift_Left; #through;
    case .Shift_Right; #through;
    case .Comp_Eq; #through;
    case .Comp_Ne; #through;
    case .Comp_Lt; #through;
    case .Comp_Gt; #through;
    case .Comp_Le; #through;
    case .Comp_Ge;
        AppendIRInstrBinop (builder, cast (*IRInstrBinop) *instr);

    case .Call;
        call := cast (*IRInstrCall) *instr;
        StringBuilderAppend (builder, "call ");
        AppendIROperand (builder, call.callee);

        for call.args
        {
            StringBuilderAppend (builder, ", ");
            AppendIROperand (builder, it);
        }

    case .Branch;
        branch := cast (*IRInstrBranch) *instr;
        StringBuilderAppend (builder, "branch ");
        AppendIROperand (builder, branch.condition);
        StringBuilderAppend (builder, ", ");
        AppendIROperand (builder, branch.label_true);
        StringBuilderAppend (builder, ", ");
        AppendIROperand (builder, branch.label_false);

    case .Return;
        ret := cast (*IRInstrReturn) *instr;
        StringBuilderAppend (builder, "return ");
        AppendIROperand (builder, ret.value);

    case .Load;
        load := cast (*IRInstrLoad) *instr;
        StringBuilderAppend (builder, "load ");
        AppendIROperand (builder, load.src_pointer);

    case .Store;
        store := cast (*IRInstrStore) *instr;
        StringBuilderAppend (builder, "store ");
        AppendIROperand (builder, store.src_value);
        AppendIROperand (builder, store.dst_pointer);

    case .Access;
        access := cast (*IRInstrAccess) *instr;
        StringBuilderAppend (builder, "access ");
        AppendIROperand (builder, access.pointer_value);

        for access.indices
        {
            StringBuilderAppend (builder, ", ");
            AppendIROperand (builder, it);
        }

    case .Alloca;
        alloca := cast (*IRInstrAlloca) *instr;
        StringBuilderAppend (builder, "alloca ");
        AppendIRType (builder, alloca.type);
        StringBuilderAppend (builder, ", ");
        AppendIROperand (builder, alloca.count);

    case .Phi;
        phi := cast (*IRInstrPhi) *instr;
        StringBuilderAppend (builder, "phi ");

        for phi.inputs
        {
            if it_index != 0
                StringBuilderAppend (builder, ", ");

            StringBuilderAppend (builder, "[");
            AppendIROperand (builder, it.from_label);
            StringBuilderAppend (builder, ", ");
            AppendIROperand (builder, it.result_value);
            StringBuilderAppend (builder, "]");
        }

    case .Cast;
        cast_instr := cast (*IRInstrCast) *instr;
        StringBuilderAppend (builder, "cast ");
        AppendIRType (builder, cast_instr.dst_type);
        StringBuilderAppend (builder, ", ");
        AppendIROperand (builder, cast_instr.src_value);
    }
}

AppendIRBasicBlock :: (builder : *StringBuilder, bb : IRBasicBlock)
{
    if bb.name
        StringBuilderAppend (builder, "\%%:\n", bb.name);

    for bb.instructions
    {
        StringBuilderAppend (builder, "  ");
        AppendIRInstr (builder, it);
        StringBuilderAppend (builder, "\n");
    }
}

AppendIRProcedure :: (builder : *StringBuilder, proc : IRProcedure)
{
    StringBuilderAppend (builder, "proc % (", proc.name);

    for proc.type.procedure.param_types
    {
        if it_index != 0
            StringBuilderAppend (builder, ", ");

        AppendIRType (builder, it);
    }

    StringBuilderAppend (builder, ") ");

    AppendIRType (builder, proc.type.procedure.return_type);

    StringBuilderAppend (builder, "\n{\n");

    for proc.basic_blocks
    {
        if it_index != 0
            StringBuilderAppend (builder, "\n");

        AppendIRBasicBlock (builder, it);
    }

    StringBuilderAppend (builder, "}");
}

AppendIRModule :: (builder : *StringBuilder, module : IRModule)
{
    for type, name : module.types
    {
        StringBuilderAppend (builder, "type @% = ", name);
        AppendIRType (builder, type);
    }

    for module.procedures
    {
        StringBuilderAppend (builder, "\n");
        AppendIRProcedure (builder, it);
        StringBuilderAppend (builder, "\n");
    }
}

IRInstrToString :: inline (instr : IRInstr, allocator := context.allocator) -> string #must
{
    builder : StringBuilder;
    builder.allocator = Temp;
    AppendIRInstr (*builder, instr);

    return StringBuilderBuild (*builder, allocator = allocator);
}

IRBasicBlockToString :: inline (bb : IRBasicBlock, allocator := context.allocator) -> string #must
{
    builder : StringBuilder;
    builder.allocator = Temp;
    AppendIRBasicBlock (*builder, bb);

    return StringBuilderBuild (*builder, allocator = allocator);
}

IRProcedureToString :: inline (proc : IRProcedure, allocator := context.allocator) -> string #must
{
    builder : StringBuilder;
    builder.allocator = Temp;
    AppendIRProcedure (*builder, proc);

    return StringBuilderBuild (*builder, allocator = allocator);
}
