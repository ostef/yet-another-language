// This intermediate representation follows closely LLVM's

#add_context ir_assertion_failed := AssertionFailed;

IROperand :: struct
{
    Kind :: enum u8
    {
        Named_Value;
        Immediate_Value;
    }

    kind : Kind;
    type : *IRType;

    union
    {
        symbol : *IRSymbol;
        bool_value : bool;
        u8_value : u8;
        s8_value : s8;
        u16_value : u16;
        s16_value : s16;
        u32_value : u32;
        s32_value : s32;
        u64_value : u64;
        s64_value : s64;
        f32_value : float32;
        f64_value : float64;
    };
}

Op :: MakeIROperand;

MakeIROperand :: inline (symbol : *IRSymbol) -> IROperand #must
{
    Assert (symbol != null);
    return .{kind=.Named_Value, type=symbol.type, symbol=symbol};
}

MakeIROperand :: inline (value : bool) -> IROperand #must
{
    return .{kind=.Immediate_Value, type=g_ir_type_bool, bool_value=value};
}

MakeIROperand :: inline (value : u8) -> IROperand #must
{
    return .{kind=.Immediate_Value, type=g_ir_type_u8, u8_value=value};
}

MakeIROperand :: inline (value : s8) -> IROperand #must
{
    return .{kind=.Immediate_Value, type=g_ir_type_s8, s8_value=value};
}

MakeIROperand :: inline (value : u16) -> IROperand #must
{
    return .{kind=.Immediate_Value, type=g_ir_type_u16, u16_value=value};
}

MakeIROperand :: inline (value : s16) -> IROperand #must
{
    return .{kind=.Immediate_Value, type=g_ir_type_s16, s16_value=value};
}

MakeIROperand :: inline (value : u32) -> IROperand #must
{
    return .{kind=.Immediate_Value, type=g_ir_type_u32, u32_value=value};
}

MakeIROperand :: inline (value : s32) -> IROperand #must
{
    return .{kind=.Immediate_Value, type=g_ir_type_s32, s32_value=value};
}

MakeIROperand :: inline (value : u64) -> IROperand #must
{
    return .{kind=.Immediate_Value, type=g_ir_type_u64, u64_value=value};
}

MakeIROperand :: inline (value : s64) -> IROperand #must
{
    return .{kind=.Immediate_Value, type=g_ir_type_s64, s64_value=value};
}

MakeIROperand :: inline (value : float32) -> IROperand #must
{
    return .{kind=.Immediate_Value, type=g_ir_type_f32, f32_value=value};
}

MakeIROperand :: inline (value : float64) -> IROperand #must
{
    return .{kind=.Immediate_Value, type=g_ir_type_f64, f64_value=value};
}

IRSymbolKind :: enum u8
{
    Invalid;
    Global_Value;
    Local_Value;
    Procedure_Param;
    Procedure;
    Basic_Block;
    Type;
}

IRSymbol :: struct
{
    name : string;
    type : *IRType;
    symbol_kind : IRSymbolKind;
    // Based on symbol_kind, one of the following is valid.
    // - if it's a global symbol then `module` is valid,
    // - if it's a basic block then `proc` is valid,
    // - if it's a local value then `block` is valid.
    union
    {
        module : *IRModule;
        proc : *IRProcedure;
        block : *IRBasicBlock;
    };
}

VerifyName :: (name : string, user_defined := true) -> bool
{
    if !IRAssert (name.count > 0, "Empty name")
        return false;

    if user_defined && Basic.is_digit (name[0])
    {
        IRPanic ("%: user defined names cannot start with a digit", name);
        return false;
    }

    for i : 0..name.count - 1
    {
        if !Basic.is_alnum (name[i])
        {
            IRPanic ("%: names must contain alpha numeric characters", name);
            return false;
        }
    }

    return true;
}

IsGlobalSymbol :: (using symbol : *IRSymbol) -> bool #must
{
    if symbol_kind ==
    {
    case .Global_Value; #through;
    case .Procedure; #through;
    case .Type;
        return true;
    }

    return false;
}

IRSymbolTable :: HashMap (string, *IRSymbol);

IRModule :: struct
{
    symbol_table : IRSymbolTable;

    types : HashMap (string, *IRType);
    procedures : HashMap (string, *IRProcedure);
}

GetType :: inline (module : *IRModule, name : string) -> *IRType #must
{
    return HashMapGet (*module.types, name);
}

GetProcedure :: inline (module : *IRModule, name : string) -> *IRProcedure #must
{
    return HashMapGet (*module.procedures, name);
}

IRBasicBlock :: struct
{
    #as using symbol : IRSymbol;
    symbol.symbol_kind = .Basic_Block;

    instructions : [..]IRInstr;
}

IRProcedure :: struct
{
    #as using symbol : IRSymbol;
    symbol.symbol_kind = .Procedure;

    entry_block : *IRBasicBlock;
    basic_blocks : [..]*IRBasicBlock;
    symbol_table : IRSymbolTable;
    param_symbols : []IRSymbol;
}

IRBuilder :: struct
{
    module : *IRModule;
    current_basic_block : *IRBasicBlock;
}

AppendAssertFailureOrPanicMessage :: (builder : *StringBuilder, instr : IRInstr, fmt_str : string, args : ..Any)
{
    SetColor (builder, .Fatal_Error);
    StringBuilderAppend (builder, "Fatal Error: ");
    SetColor (builder, .None);

    StringBuilderAppend (builder, fmt_str, ..args);
    StringBuilderAppend (builder, "\n");

    StringBuilderAppend (builder, "IR instruction: ");
    AppendIRInstr (builder, instr);
    StringBuilderAppend (builder, "\n");
}
@PrintLike

IRAssert :: (assertion : bool, format_string : string, args : ..Any, location := #caller_location) -> bool
{
    if !assertion && !context.handling_assertion_failure
    {
        context.handling_assertion_failure = true;
        defer context.handling_assertion_failure = false;

        builder : StringBuilder;

        AppendAssertFailureOrPanicMessage (*builder, format_string, ..args);

        message := StringBuilderBuild (*builder);

        if context.ir_assertion_failed (location, message)
            debug_break ();
    }

    return assertion;
}
@PrintLike

IRPanic :: (format_string : string, args : ..Any, location := #caller_location)
{
    if !context.handling_assertion_failure
    {
        context.handling_assertion_failure = true;
        defer context.handling_assertion_failure = false;

        context.panicking = true;
        defer context.panicking = false;

        builder : StringBuilder;

        AppendAssertFailureOrPanicMessage (*builder, format_string, ..args);

        message := StringBuilderBuild (*builder);

        if context.ir_assertion_failed (location, message)
            debug_break ();
    }
}
@PrintLike

IRAssert :: (instr : IRInstr, assertion : bool, format_string : string, args : ..Any, location := #caller_location) -> bool
{
    if !assertion && !context.handling_assertion_failure
    {
        context.handling_assertion_failure = true;
        defer context.handling_assertion_failure = false;

        builder : StringBuilder;

        AppendAssertFailureOrPanicMessage (*builder, instr, format_string, ..args);

        message := StringBuilderBuild (*builder);

        if context.ir_assertion_failed (location, message)
            debug_break ();
    }

    return assertion;
}
@PrintLike

IRPanic :: (instr : IRInstr, format_string : string, args : ..Any, location := #caller_location)
{
    if !context.handling_assertion_failure
    {
        context.handling_assertion_failure = true;
        defer context.handling_assertion_failure = false;

        context.panicking = true;
        defer context.panicking = false;

        builder : StringBuilder;

        AppendAssertFailureOrPanicMessage (*builder, instr, format_string, ..args);

        message := StringBuilderBuild (*builder);

        if context.ir_assertion_failed (location, message)
            debug_break ();
    }
}
@PrintLike

MakeUniqueName :: (table : *IRSymbolTable, name := "", allocator := context.allocator) -> string #must
{
    AllocatorScope (Temp);

    if name
        VerifyName (name);

    test_name := ifx name then name else "unnamed";
    number := 0;
    while true
    {
        if !HashMapGetPtr (table, test_name)
            break;

        test_name = ifx name
            then FormatString ("%.%", name, number)
            else FormatString ("unnamed.%", number);

        number += 1;
    }

    return StringClone (test_name, allocator);
}

InsertUniqueSymbol :: inline (table : *IRSymbolTable, symbol : *IRSymbol)
{
    _, exists := HashMapInsert (table, symbol.name, symbol);
    IRAssert (!exists, "Redeclaration of symbol '%'", symbol.name);
}

CreateIRProcedure :: (module : *IRModule, name : string, param_types : []*IRType, return_type : *IRType) -> *IRProcedure #must
{
    // @Todo: procedure name overloading
    VerifyName (name);

    IRAssert (
        IsFirstClassType (return_type.kind),
        "Procedure return types can only be first class types (got %)",
        IRTypeToString (return_type)
    );

    proc_ptr, exists := HashMapInsert (*module.procedures, name);
    if exists
        return null;

    proc := Alloc (IRProcedure);
    proc.module = module;
    proc.name = name;
    proc.type = MakeIRProcedureType (param_types, return_type);

    proc.param_symbols = AllocArray (IRSymbol, param_types.count);
    for * param, i : proc.param_symbols
    {
        param.name = FormatString ("%", i);
        param.type = param_types[i];
        param.symbol_kind = .Procedure_Param;
        param.proc = proc;
        InsertUniqueSymbol (*proc.symbol_table, param);
    }

    proc_ptr.* = proc;

    InsertUniqueSymbol (*module.symbol_table, proc);

    return proc;
}

GetParam :: inline (proc : *IRProcedure, index : int) -> IROperand #must
{
    IRAssert (
        index >= 0 && index < proc.type.procedure.param_types.count,
        "Invalid param index % for proc %", index, IRTypeToString (proc.type)
    );

    return MakeIROperand (*proc.param_symbols[index]);
}

CreateIRBasicBlock :: (proc : *IRProcedure, name : string) -> *IRBasicBlock #must
{
    VerifyName (name);

    block := Alloc (IRBasicBlock);
    block.proc = proc;
    block.name = MakeUniqueName (*proc.symbol_table, name);
    block.type = g_ir_type_label;

    ArrayPush (*proc.basic_blocks, block);

    InsertUniqueSymbol (*proc.symbol_table, block);

    return block;
}

ScopeBasicBlock :: (builder : *IRBuilder, block : *IRBasicBlock) #expand
{
    prev := builder.current_basic_block;
    builder.current_basic_block = block;
    `defer builder.current_basic_block = prev;
}
