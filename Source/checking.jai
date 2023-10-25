SemanticMeaning :: enum u8
{
    Invalid;
    Type;
    Value;
    Constant;
    Mutable;
}

CheckContext :: struct
{
    enclosing_proc : *AstProcedure;
    enclosing_while : *AstWhile;
    declaration_stack : [..]*AstDeclaration;
    enum_value_counter : int;
}

#add_context check : CheckContext;

ScopeKind :: enum u8
{
    Invalid;

    File;
    Block;
    Procedure;
}

Scope :: struct
{
    parent : *Scope;
    first_child : *Scope;
    prev : *Scope;
    next : *Scope;

    first_symbol : *Symbol;
    last_symbol : *Symbol;

    // Only the first declared symbol ends up here, if
    // a symbol is redeclared, it is not added to the table
    symbols : HashMap (string, *Symbol);

    declarations : [..]*AstDeclaration;

    kind : ScopeKind;
    union
    {
        file : *YalFile;
        block : *AstBlock;
        procedure : *AstProcedure;
    };
}

CheckStatus :: enum u8
{
    Unchecked;
    Checking;
    Checked;
}

SymbolKind :: enum u8
{
    Invalid;
    Variable;
    Constant;
    Type;
    Procedure;
}

SymbolFlags :: enum_flags u8
{
    Redeclaration;
}

Symbol :: struct
{
    scope : *Scope;
    prev, next : *Symbol;

    name : string;
    decl : *AstDeclaration;
    kind : SymbolKind;
    flags : SymbolFlags;
}

ScopeCreate :: (parent : *Scope, kind : ScopeKind) -> *Scope #must
{
    scope := Alloc (Scope);
    scope.kind = kind;

    scope.parent = parent;
    if parent
    {
        if !parent.first_child
        {
            parent.first_child = scope;
        }
        else
        {
            sibling := parent.first_child;
            while sibling && sibling.next
                sibling = sibling.next;

            sibling.next = scope;
            scope.prev = sibling;
        }
    }

    return scope;
}

ScopeCreate :: inline (file : *YalFile) -> *Scope
{
    Assert (file.scope == null);

    scope := ScopeCreate (null, .File);
    scope.file = file;
    file.scope = scope;

    return scope;
}

ScopeCreate :: inline (parent : *Scope, block : *AstBlock) -> *Scope
{
    Assert (block, block.scope == null, "block scope has already been created");

    scope := ScopeCreate (parent, .Block);
    scope.block = block;
    block.scope = scope;

    return scope;
}

ScopeCreate :: inline (parent : *Scope, procedure : *AstProcedure) -> *Scope
{
    Assert (procedure, procedure.scope == null, "procedure scope has already been created");

    scope := ScopeCreate (parent, .Procedure);
    scope.procedure = procedure;
    procedure.scope = scope;

    return scope;
}

ScopeInsert :: (using scope : *Scope, symbol_kind : SymbolKind, ident : *AstIdentifier, decl : *AstDeclaration) -> *Symbol
{
    Assert (scope != null);
    Assert (ident != null);

    if StringStartsWith (ident.name, "Yal__")
    {
        Error (ident, "identifiers starting with Yal__ are reserved");
    }

    symbol := Alloc (Symbol);
    symbol.scope = scope;
    symbol.name = ident.name;
    symbol.kind = symbol_kind;
    symbol.decl = decl;
    ident.symbol = symbol;

    if last_symbol
    {
        symbol.prev = last_symbol;
        last_symbol.next = symbol;
        last_symbol = symbol;
    }
    else
    {
        first_symbol = symbol;
        last_symbol = symbol;
    }

    original := ScopeLookupCurrent (scope, ident.name);
    if original
    {
        Error (decl, "redeclaration of identifier '%'", ident.name);
        Info (original.decl, "here is the first declaration of '%'", ident.name);
        symbol.flags |= .Redeclaration;
    }
    else
    {
        HashMapInsert (*symbols, ident.name, symbol);
    }

    return symbol;
}

ScopeInsert :: (scope : *Scope, decl : *AstDeclaration)
{
    // File scope declarations array was filled during parsing
    if decl && scope.kind != .File
        ArrayPush (*scope.declarations, decl);

    if !decl || decl.identifier_count == 0
        return;

    symbol_kind : SymbolKind;
    if #complete decl.decl_kind ==
    {
    case .Variable; #through;
    case .Field;
        symbol_kind = .Variable;

    case .Constant;
        symbol_kind = .Constant;

    case .Procedure;
        symbol_kind = .Procedure;

    case .Struct; #through;
    case .Enum;
        symbol_kind = .Type;

    case .Enum_Member;
        symbol_kind = .Constant;

    case .Invalid;
        Panic (decl, "Invalid declaration kind %", decl.decl_kind);
    }

    for :Identifiers decl
    {
        if it.name == "Main" && scope.kind == .File && symbol_kind == .Procedure
            scope.file.entry_point_declaration = decl;

        ScopeInsert (scope, symbol_kind, it, decl);
    }
}

ScopeLookupCurrent :: inline (using scope : *Scope, name : string) -> *Symbol #must
{
    val, ok := HashMapGet (*symbols, name);
    if !ok
        return null;

    return val;
}

ScopeLookup :: (using scope : *Scope, name : string) -> *Symbol #must
{
    while scope
    {
        symbol := ScopeLookupCurrent (scope, name);
        if symbol
            return symbol;

        scope = scope.parent;
    }

    return null;
}

CollectDeclaredSymbols :: (scope : *Scope, node : *$T)
#modify { return TypeIsAstNode (cast (*Type_Info) T); }
{
    if !node
        return;

    node.enclosing_scope = scope;

    #if T == AstNode
    {
        inline CollectDeclaredSymbolsForUntypedNode (scope, node);
    }
    else
    {
        #if T == AstDeclaration
            ScopeInsert (scope, node);

        #insert -> string
        {
            info := type_info (T);

            builder : StringBuilder;

            StringBuilderAppend (*builder, "// CollectDeclaredSymbols for %\n", T);
            for member : info.members
            {
                if member.name == "scope" && member.type == type_info (*Scope)
                    StringBuilderAppend (*builder, "scope = ScopeCreate (scope, node);\n");
            }

            for member : info.members
            {
                for note : member.notes
                {
                    if note == "NoCollectSymbols"
                    {
                        StringBuilderAppend (*builder, "// % is ignored\n", member.name);
                        continue member;
                    }
                }

                if member.type.type == .POINTER
                {
                    pointed_type := (cast (*Type_Info_Pointer) member.type).pointer_to;
                    if TypeIsAstNode (pointed_type)
                        StringBuilderAppend (*builder, "CollectDeclaredSymbols (scope, node.%);\n", member.name);
                }
                else if member.type.type == .ARRAY
                {
                    element_type := (cast (*Type_Info_Array) member.type).element_type;
                    pointed_type : *Type_Info;
                    if element_type.type == .POINTER
                        pointed_type = (cast (*Type_Info_Pointer) element_type).pointer_to;

                    if pointed_type && TypeIsAstNode (pointed_type)
                    {
                        StringBuilderAppend (*builder, "for node.%\n", member.name);
                        StringBuilderAppend (*builder, "    CollectDeclaredSymbols (scope, it);\n");
                    }
                }
            }

            return StringBuilderBuild (*builder);
        }
    }
}

CollectDeclaredSymbolsForUntypedNode :: (scope : *Scope, node : *AstNode)
{
    Ignore_Kinds :: AstKind.[
        .Invalid,
        .Statements_Begin,
        .Bad_Declaration,
        .Expressions_Begin,
        .Expressions_End,
        .Statements_End,
        .Types_Begin,
        .Types_End,
        .Count
    ];

    #insert -> string
    {
        AppendAstStructName :: (builder : *StringBuilder, kind : AstKind)
        {
            StringBuilderAppend (builder, "Ast");

            name := type_info (AstKind).names[kind];
            for i : 0..name.count - 1
            {
                if name[i] == #char "_"
                    continue;

                StringBuilderAppendByte (builder, name[i]);
            }
        }

        builder : StringBuilder;

        StringBuilderAppend (*builder, "if node.kind ==\n{\n");
        for i : 0..AstKind.Count - 1
        {
            kind := cast (AstKind) i;
            for Ignore_Kinds
            {
                if it == kind
                    continue i;
            }

            StringBuilderAppend (*builder, "case .%;\n", kind);
            StringBuilderAppend (*builder, "    CollectDeclaredSymbols (scope, cast (*");
            AppendAstStructName (*builder, kind);
            StringBuilderAppend (*builder, ") node);\n");
        }
        StringBuilderAppend (*builder, "}");

        return StringBuilderBuild (*builder);
    };
}

CollectAllSymbolsInFile :: (file : *YalFile)
{
    ProfileBlock ();

    for file.declarations
        CollectDeclaredSymbols (file.scope, it);
}

SetDeclarationType :: (decl : *AstDeclaration, type : *YalType)
{
    Assert (decl, decl.type == null, "declaration alread has a type");

    decl.type = type;
    for :Identifiers decl
        it.type = type;
}

ReportCircularDependencyErrorAndExit :: (decl : *AstDeclaration)
{
    file := GetFile (decl.file_id);
    Assert (file != null);

    ErrorNoSquiggles (decl, "circular dependency detected");

    builder : StringBuilder;

    StringBuilderAppend (*builder, "Here are the declarations we were checking (most recent first):\n\n");
    for < context.check.declaration_stack
    {
        file := GetFile (it.file_id);
        Assert (file != null);

        StringBuilderAppend (*builder, "%:%:%\n", file.filename, it.line_start, it.char_start);
        PrintTokenLine (*builder, it, print_squiggles = false);
    }

    Print (StringBuilderBuild (*builder), to_stderr = true);

    SetOutputColor (.Error);
    Println ("Exiting...", to_stderr = true);
    SetOutputColor (.None);

    PrintProfilingResults ();

    Basic.exit (1);
}

CheckDeclaration :: (using decl : *AstDeclaration)
{
    if check_status == .Checking
        ReportCircularDependencyErrorAndExit (decl);

    if check_status == .Checked
        return;

    check_status = .Checking;
    defer check_status = .Checked;

    ArrayPush (*context.check.declaration_stack, decl);
    defer ArrayPop (*context.check.declaration_stack);

    defer if !type then SetDeclarationType (decl, g_type_invalid);

    if #complete decl_kind ==
    {
    case .Invalid;
        type = g_type_invalid;

    case .Variable; #through;
    case .Constant; #through;
    case .Field;
        if type_node
        {
            CheckType (type_node);
            SetDeclarationType (decl, type_node.type);
        }

        if expr
        {
            CheckExpression (expr);

            if expr.type != g_type_invalid
            {
                CheckInitAssignment (decl);

                if !type_node
                    SetDeclarationType (decl, expr.type);
            }
        }
        else if decl_kind == .Constant
        {
            Error (decl, "uninitialized constant");
        }

    case .Procedure;
        CheckProcedureDeclaration (decl);

    case .Struct;
        name := ifx identifier_count == 1 then decl.single_identifier.name else "";
        CheckStruct (cast (*AstStruct) expr, name);
        SetDeclarationType (decl, expr.type);

    case .Enum;
        name := ifx identifier_count == 1 then decl.single_identifier.name else "";
        CheckEnum (cast (*AstEnum) expr, name);
        SetDeclarationType (decl, expr.type);

    case .Enum_Member;
        Assert (decl, type != null, "enum member type isn't set");

        if expr
        {
            CheckExpression (expr);
            if expr.type == g_type_invalid
            {
                type = g_type_invalid;
                return;
            }

            CheckInitAssignment (decl);
        }
        else
        {
            value = .{int_value = context.check.enum_value_counter, kind = .Integer};
        }

        context.check.enum_value_counter += 1;
    }
}

CheckInitAssignment :: (using decl : *AstDeclaration)
{
    if expr.semantic_meaning == .Type
    {
        Error (expr, "assignment of a type");
        return;
    }

    if (decl_kind == .Constant || decl_kind == .Enum_Member) && expr.semantic_meaning != .Constant
    {
        Error (expr, "assigning non constant expression to a constant");
        return;
    }

    if type && !TypeCanImplicitlyCastTo (expr.type, type)
    {
        Error (expr, "invalid type for assignment (left type: %, right type: %)",
            type.as_string, expr.type.as_string);
        return;
    }

    if decl_kind == .Constant || decl_kind == .Enum_Member
        value = expr.value;
}

CheckProcedureSignature :: (using proc : *AstProcedure)
{
    type = g_type_invalid;

    type_parameters : [..]*YalType;
    type_results : [..]*YalType;

    for parameters
    {
        CheckDeclaration (it);
        if it.type == g_type_invalid
            return;

        ArrayPush (*type_parameters, it.type);
    }

    for results
    {
        CheckDeclaration (it);
        if it.type == g_type_invalid
            return;

        ArrayPush (*type_results, it.type);
    }

    type = MakeTypeProcedure (proc, type_parameters, type_results);
}

CheckProcedureDeclaration :: (decl : *AstDeclaration)
{
    proc := cast (*AstProcedure) decl.expr;

    CheckProcedureSignature (proc);
    SetDeclarationType (decl, proc.type);

    if decl.type == g_type_invalid
        return;

    enclosing_proc := context.check.enclosing_proc;
    context.check.enclosing_proc = proc;
    CheckBlock (proc.body);
    context.check.enclosing_proc = enclosing_proc;
}

CheckStruct :: (using node : *AstStruct, name := "")
{
    type = MakeTypeStruct (node, name);
    CheckBlock (body);
}

CheckEnum :: (using node : *AstEnum, name := "")
{
    type_base_type : *YalType;
    if base_type
    {
        CheckType (base_type);
        if base_type.type == g_type_invalid
            return;

        type_base_type = base_type.type;
    }
    else
    {
        type_base_type = g_type_s64;
    }

    if type_base_type.kind != .Integer
    {
        Error (base_type, "invalid type for enum base type. Should be an integer but got %", type_base_type.as_string);

        // Set base type to something valid so this error does not cascade
        type_base_type = g_type_s64;
    }

    type_enum := MakeTypeEnum (node, name, type_base_type);
    type = type_enum;

    // Set the type of all the enum members, so we can typecheck enum member init assignments
    for body.statements
    {
        // There technically should only be enum members here since anything else would be a parsing error

        decl := cast (*AstDeclaration) it;

        Assert (it, it.kind == .Declaration, "this should be a declaration");
        Assert (decl, decl.decl_kind == .Enum_Member, "this should be an enum member declaration");

        decl.type = type;
    }

    prev_counter := context.check.enum_value_counter;
    context.check.enum_value_counter = 0;

    CheckBlock (body);

    context.check.enum_value_counter = prev_counter;

    type_enum.members = AllocArray (YalTypeEnumMember, body.statements.count, initialize = false);
    i := 0;
    for body.statements
    {
        if it.type == g_type_invalid
            continue;

        member_decl := cast (*AstDeclaration) it;

        Assert (member_decl, member_decl.identifier_count == 1, "enum member have invalid number of identifiers");
        Assert (member_decl, member_decl.value.kind == .Integer, "enum member has non integer value");

        type_enum.members[i].name = member_decl.single_identifier.name;
        type_enum.members[i].value = member_decl.value.int_value;
        i += 1;
    }

    type_enum.members.count = i;
}

CheckType :: (type : *AstNode)
{
    type.type = g_type_invalid;

    if type.kind ==
    {
    case .Type_Pointer;
        type_pointer := cast (*AstTypePointer) type;

        CheckType (type_pointer.pointed_type);

        if type_pointer.pointed_type.type == g_type_invalid
            return;

        type.type = MakeTypePointer (type_pointer.pointed_type.type, type);

    case .Type_Array;
        type_array := cast (*AstTypeArray) type;

        CheckType (type_array.element_type);

        if type_array.element_type.type == g_type_invalid
            return;

        array_count := -1;
        if type_array.element_count
        {
            count := type_array.element_count;

            CheckExpression (count);

            if count.type == g_type_invalid
                return;

            if count.type.kind != .Integer
            {
                Error (count, "array count must be a positive constant integer");
                return;
            }

            if count.semantic_meaning != .Constant
            {
                Error (count, "array count must be constant");
                return;
            }

            if count.value.int_value < 0
            {
                Error (count, "array count must be a positive integer (is %)", count.value.int_value);
                // @Todo: handle number signedness
                InfoWithoutSourceCode (count, "for now, we only handle 64-bit signed integer values");
                return;
            }

            array_count = count.value.int_value;
        }

        type.type = MakeTypeArray (type_array.array_kind, type_array.element_type.type, array_count, type);

    case .Type_Named;
        type_named := cast (*AstTypeNamed) type;

        CheckIdentifier (type_named.identifier);
        if type_named.identifier.type == g_type_invalid
            return;

        if type_named.identifier.semantic_meaning != .Type
        {
            Error (type_named, "identifier is not a type");
            return;
        }

        type.type = type_named.identifier.type;

    case .Type_Primitive;
        type_primitive := cast (*AstTypePrimitive) type;
        if type_primitive.primitive_kind ==
        {
        case .S8; type.type = g_type_s8;
        case .U8; type.type = g_type_u8;
        case .S16; type.type = g_type_s16;
        case .U16; type.type = g_type_u16;
        case .S32; type.type = g_type_s32;
        case .U32; type.type = g_type_u32;
        case .S64; type.type = g_type_s64;
        case .U64; type.type = g_type_u64;
        case .Int; type.type = g_type_s64;
        case .Uint; type.type = g_type_u64;
        case .Float; type.type = g_type_f32;
        case .F32; type.type = g_type_f32;
        case .F64; type.type = g_type_f64;
        case .Bool; type.type = g_type_bool;
        case .String; type.type = g_type_string;
        case .Void; type.type = g_type_void;
        }

    case .Procedure;
        CheckProcedureSignature (cast (*AstProcedure) type);

    case .Struct;
        CheckStruct (cast (*AstStruct) type);
    case .Enum;
        CheckEnum (cast (*AstEnum) type);
    case;
        Panic (type, "Invalid ast kind (%)", type.kind);
    }
}

CheckLogicalComposition :: (using binary : *AstBinary)
{
    Assert (binary, op.kind == .Ampersand_Ampersand || op.kind == .Pipe_Pipe, "invalid op");

    if !TypeCanImplicitlyCastTo (left.type, g_type_bool)
    || !TypeCanImplicitlyCastTo (right.type, g_type_bool)
    {
        Error (binary.left, "invalid type for binary operator % (left is: %, right is: %)", Token_Names[op.kind], left.type.as_string, right.type.as_string);
        return;
    }

    type = g_type_bool;

    if left.semantic_meaning == .Constant && right.semantic_meaning == .Constant
    {
        semantic_meaning = .Constant;
        value = ConstantEvaluate (left.value, right.value, op, binary);
    }
    else
    {
        semantic_meaning = .Value;
    }
}

CheckEquality :: (using binary : *AstBinary)
{
    Assert (binary, op.kind == .Equ_Equ || op.kind == .Bang_Equ, "invalid op");

    if !TypeCanImplicitlyCastTo (right.type, left.type)
    {
        Error (binary.left, "invalid type for comparison (left is: %, right is: %)", left.type.as_string, right.type.as_string);
        return;
    }

    type = g_type_bool;
    if left.semantic_meaning == .Constant && right.semantic_meaning == .Constant
    {
        semantic_meaning = .Constant;
        value = ConstantEvaluate (left.value, right.value, op, binary);
    }
    else
    {
        semantic_meaning = .Value;
    }
}

CheckArithmeticComparison :: (using binary : *AstBinary)
{
    Assert (binary, op.kind == .Less || op.kind == .Less_Equ || op.kind == .Greater || op.kind == .Greater_Equ, "invalid op");

    if left.type.kind != .Integer && left.type.kind != .Float
    || !TypeCanImplicitlyCastTo (right.type, left.type)
    {
        Error (binary, "invalid type for comparison (left is: %, right is: %)", left.type.as_string, right.type.as_string);
        return;
    }

    type = g_type_bool;

    if left.semantic_meaning == .Constant && right.semantic_meaning == .Constant
    {
        semantic_meaning = .Constant;
        value = ConstantEvaluate (left.value, right.value, op, binary);
    }
    else
    {
        semantic_meaning = .Value;
    }
}

CheckBitOperation :: (using binary : *AstBinary)
{
    Assert (binary,
        op.kind == .Pipe || op.kind == .Ampersand || op.kind == .Caret
        || op.kind == .Pipe_Equ || op.kind == .Ampersand_Equ || op.kind == .Caret_Equ
        || op.kind == .Less_Less || op.kind == .Greater_Greater
        || op.kind == .Less_Less_Equ || op.kind == .Greater_Greater_Equ,
        "invalid op"
    );

    if left.type.kind != .Integer || !TypeCanImplicitlyCastTo (right.type, left.type)
    {
        Error (binary, "invalid type for bit operation (left is: %, right is: %)", left.type.as_string, right.type.as_string);
        return;
    }

    type = left.type;

    if left.semantic_meaning == .Constant && right.semantic_meaning == .Constant
    {
        semantic_meaning = .Constant;
        value = ConstantEvaluate (left.value, right.value, op, binary);
    }
    else
    {
        semantic_meaning = .Value;
    }
}

CheckModulo :: (using binary : *AstBinary)
{
    Assert (binary, op.kind == .Percent || op.kind == .Percent_Equ, "invalid op");

    if left.type.kind != .Integer || !TypeCanImplicitlyCastTo (right.type, left.type)
    {
        Error (binary, "invalid type for operator % (left is: %, right is: %)", Token_Names[op.kind], left.type.as_string, right.type.as_string);
        return;
    }

    type = left.type;

    if left.semantic_meaning == .Constant && right.semantic_meaning == .Constant
    {
        semantic_meaning = .Constant;
        value = ConstantEvaluate (left.value, right.value, op, binary);
    }
    else
    {
        semantic_meaning = .Value;
    }
}

CheckArithmeticOperation :: (using binary : *AstBinary)
{
    Assert (binary,
        op.kind == .Plus || op.kind == .Minus || op.kind == .Star || op.kind == .Slash
        || op.kind == .Plus_Equ || op.kind == .Minus_Equ || op.kind == .Star_Equ || op.kind == .Slash_Equ,
        "invalid op"
    );

    if left.type.kind != .Integer && left.type.kind != .Float
    || !TypeCanImplicitlyCastTo (right.type, left.type)
    {
        Error (binary, "invalid type for arithmetic operation (left is: %, right is: %)", left.type.as_string, right.type.as_string);
        return;
    }

    if (op.kind == .Minus || op.kind == .Minus_Equ) && left.type.kind == .Integer && !(cast (*YalTypeInteger) left.type).is_signed
    {
        Error (binary, "cannot subtract unsigned integers (left is: %, right is: %)", left.type.as_string, right.type.as_string);
        return;
    }

    type = left.type;

    if left.semantic_meaning == .Constant && right.semantic_meaning == .Constant
    {
        semantic_meaning = .Constant;
        value = ConstantEvaluate (left.value, right.value, op, binary);
    }
    else
    {
        semantic_meaning = .Value;
    }
}

CheckBinary :: (using binary : *AstBinary)
{
    type = g_type_invalid;

    CheckExpression (left);
    CheckExpression (right);

    if left.type == g_type_invalid || right.type == g_type_invalid
        return;

    if op.kind ==
    {
    case .Pipe_Pipe; #through;
    case .Ampersand_Ampersand;
        CheckLogicalComposition (binary);

    case .Equ_Equ; #through;
    case .Bang_Equ;
        CheckEquality (binary);

    case .Less; #through;
    case .Less_Equ; #through;
    case .Greater; #through;
    case .Greater_Equ;
        CheckArithmeticComparison (binary);

    case .Pipe; #through;
    case .Caret; #through;
    case .Ampersand; #through;
    case .Less_Less; #through;
    case .Greater_Greater;
        CheckBitOperation (binary);

    case .Plus; #through;
    case .Minus; #through;
    case .Star; #through;
    case .Slash;
        CheckArithmeticOperation (binary);

    case .Percent;
        CheckModulo (binary);

    case;
        Error (op, "unhandled binary operator");
        return;
    }

    if semantic_meaning == .Constant
    {
        Assert (binary, value.kind != .Invalid, "It seems a constant binary operation did not get constant evaluated");
        // Info (binary, "result is constant: left is %, right is %, result is %", ToString (left.value), ToString (right.value), ToString (value));
    }
}

CheckNegation :: (using unary : *AstUnary)
{
    if expr.type.kind ==
    {
    case .Integer;
        type_int := cast (*YalTypeInteger) expr.type;
        if !type_int.is_signed
        {
            Error (unary, "cannot negate an unsigned integer (type is: %)", expr.type.as_string);
            return;
        }

        type = expr.type;

    case .Float;
        type = expr.type;
    case;
        Error (unary, "invalid type for unary operator % (type is: %)", Token_Names[op.kind], expr.type.as_string);
        return;
    }

    if expr.semantic_meaning == .Constant
    {
        semantic_meaning = .Constant;
        value = ConstantEvaluate (expr.value, op, unary);
    }
    else
    {
        semantic_meaning = .Value;
    }
}

CheckLogicalNot :: (using unary : *AstUnary)
{
    if expr.type.kind != .Bool
    {
        Error (unary, "invalid type for unary operator % (type is: %)", Token_Names[op.kind], expr.type.as_string);
        return;
    }

    type = expr.type;

    if expr.semantic_meaning == .Constant
    {
        semantic_meaning = .Constant;
        value = ConstantEvaluate (expr.value, op, unary);
    }
    else
    {
        semantic_meaning = .Value;
    }
}

CheckBitNot :: (using unary : *AstUnary)
{
    // For now we only allow integers to be bit operated on
    if expr.type.kind != .Integer
    {
        Error (unary, "invalid type for unary operator % (type is: %, only integer types are allowed in bit operations)", Token_Names[op.kind], expr.type.as_string);
        return;
    }

    type = expr.type;

    if expr.semantic_meaning == .Constant
    {
        semantic_meaning = .Constant;
        value = ConstantEvaluate (expr.value, op, unary);
    }
    else
    {
        semantic_meaning = .Value;
    }
}

CheckAddressOf :: (using unary : *AstUnary)
{
    if expr.semantic_meaning != .Mutable
    {
        Error (unary, "taking address of non-addressable expression");
        return;
    }

    semantic_meaning = .Value;
    type = MakeTypePointer (expr.type, unary);
}

CheckDeref :: (using unary : *AstUnary)
{
    if expr.type.kind != .Pointer
    {
        Error (unary, "expected a pointer for dereference but got %", expr.type.as_string);
        return;
    }

    if expr.semantic_meaning == .Constant
    {
        Error (unary, "cannot dereference a constant");
        return;
    }

    semantic_meaning = .Mutable;
    type = (cast (*YalTypePointer) expr.type).pointed_type;
}

CheckUnary :: (using unary : *AstUnary)
{
    type = g_type_invalid;

    CheckExpression (expr);
    if expr.type == g_type_invalid
        return;

    if op.kind ==
    {
    case .Minus;
        CheckNegation (unary);
    case .Bang;
        CheckLogicalNot (unary);
    case .Caret;
        CheckBitNot (unary);
    case .Ampersand;
        CheckAddressOf (unary);
    case .Star;
        CheckDeref (unary);
    case;
        Error (op, "unhandled unary operator");
        return;
    }

    if semantic_meaning == .Constant
    {
        Assert (unary, value.kind != .Invalid, "It seems a constant unary operation did not get constant evaluated");
        // Info (unary, "result is constant: expr is %, result is %", ToString (expr.value), ToString (value));
    }
}

CheckIdentifier :: (using ident : *AstIdentifier)
{
    type = g_type_invalid;

    symbol = ScopeLookup (enclosing_scope, name);
    if !symbol
    {
        Error (ident, "undeclared identifier '%'", name);
        return;
    }

    if symbol.decl.file_id == ident.file_id && symbol.kind == .Variable && enclosing_scope.kind == .Block
    && CompareLineColumnPairs (symbol.decl.line_start, symbol.decl.char_start, ident.line_start, ident.char_start) >= 0
    {
        Error (ident, "identifier '%' is used before it is declared", ident.name);
        Info (symbol.decl, "here is the declaration of '%'", ident.name);
        return;
    }

    if symbol.decl.check_status != .Checked
        CheckDeclaration (symbol.decl);

    type = symbol.decl.type;

    if #complete symbol.kind ==
    {
    case .Invalid;
    case .Variable;
        semantic_meaning = .Mutable;

    case .Constant;
        semantic_meaning = .Constant;
        value = symbol.decl.value;
        Assert (value.kind != .Invalid);

    case .Procedure;
        semantic_meaning = .Constant;
        value = .{
            procedure_node = cast (*AstProcedure) symbol.decl.expr,
            kind = .Procedure
        };

    case .Type;
        semantic_meaning = .Type;
    }
}

CheckLiteral :: inline (using lit : *AstLiteral)
{
    semantic_meaning = .Constant;
    value, type = MakeConstantValue (.{range=range, kind=literal_kind});
}

CheckProcedureCall :: (using call : *AstProcedureCall)
{
    type = g_type_invalid;

    CheckExpression (callee);
    if callee.type == g_type_invalid
        return;

    if callee.type.kind != .Procedure
    {
        Error (callee, "callee in procedure call expression is not a procedure (type is: %)", callee.type.as_string);
        return;
    }

    proc_type := cast (*YalTypeProcedure) callee.type;
    if passed_arguments.count != proc_type.parameters.count
    {
        Error (call,
            "mismatching number of arguments passed in procedure. Expected % but got %",
            proc_type.parameters.count, passed_arguments.count
        );

        if proc_type.node
            Info (proc_type.node.signature_range, "here is the signature of the procedure being called");
    }

    for i : 0..passed_arguments.count - 1
    {
        arg := passed_arguments[i];

        CheckExpression (arg);
        if arg.type == g_type_invalid
            continue;

        if i >= proc_type.parameters.count
            continue;

        param := proc_type.parameters[i];
        if !TypeCanImplicitlyCastTo (arg.type, param)
        {
            Error (arg, "type mismatch for argument %. Expected % but got %", i + 1, param.as_string, arg.type.as_string);
        }
    }

    // @Todo: handle multiple results
    if proc_type.results.count == 0
        type = g_type_void;
    else
        type = proc_type.results[0];
}

CheckSubscript :: (using subscript : *AstSubscript)
{
    type = g_type_invalid;

    CheckExpression (subscripted);
    if subscripted.type == g_type_invalid
        return;

    if subscripted.type.kind != .Array && subscripted.type.kind != .Pointer && subscripted.type.kind != .String
    {
        Error (subscripted,
            "invalid type for subscript operator. Expected an array, a pointer or a string but got %",
            subscripted.type.as_string
        );
        return;
    }

    if subscripted.type.kind ==
    {
    case .Array;
        type = (cast (*YalTypeArray) subscripted.type).element_type;
    case .Pointer;
        type = (cast (*YalTypePointer) subscripted.type).pointed_type;
    case .String;
        type = g_type_u8;
    }

    CheckExpression (index);
    if index.type == g_type_invalid
        return;

    if index.type.kind != .Integer
    {
        Error (index,
            "invalid type for index of subscript operator. Expected an integer but got %",
            index.type.as_string
        );
        return;
    }

    semantic_meaning = subscripted.semantic_meaning;
    if semantic_meaning == .Constant && index.semantic_meaning != .Constant
        semantic_meaning = .Value;

    if index.semantic_meaning == .Constant
    && subscripted.type.kind == .Array && (cast (*YalTypeArray) subscripted.type).array_kind == .Static
    {
        array_count := (cast (*YalTypeArray) subscripted.type).count;
        index_value := index.value.int_value;

        if array_count == 0
        {
            Error (
                index,
                "static array subscript index out of bounds. Array is empty so no index is valid, the index is %",
                index_value
            );
        }

        if index_value < 0 || index_value >= array_count
        {
            Error (index,
                "static array subscript index out of bounds. Expected [0; %] but got %",
                array_count - 1, index_value
            );
        }
    }
}

CheckArrayFieldAccess :: (using access : *AstFieldAccess)
{
    type_array := cast (*YalTypeArray) left.type;
    ident := cast (*AstIdentifier) right;
    if ident.name ==
    {
    case "count";
        type = g_type_s64;

        if type_array.array_kind == .Static
        {
            semantic_meaning = .Constant;
            value = .{int_value = type_array.count, kind = .Integer};
        }
        else if left.semantic_meaning == .Constant
        {
            Warning (access, "this expression should be constant but we don't yet handle constant array values. The result of this expression is 0 for now");
            semantic_meaning = .Constant;
            value = .{int_value = 0, kind = .Integer};
        }
        else if left.semantic_meaning == .Mutable
        {
            semantic_meaning = .Mutable;
        }
        else
        {
            semantic_meaning = .Value;
        }

    case "capacity";
        if type_array.array_kind != .Dynamic
        {
            Error (right, "'%' is not a member of type %", ident.name, left.type.as_string);
            return;
        }

        type = g_type_s64;
        if left.semantic_meaning == .Constant
        {
            Warning (access, "this expression should be constant but we don't yet handle constant array values. The result of this expression is 0 for now");
            semantic_meaning = .Constant;
            value = .{int_value = 0, kind = .Integer};
        }
        else if left.semantic_meaning == .Mutable
        {
            semantic_meaning = .Mutable;
        }
        else
        {
            semantic_meaning = .Value;
        }

    case "allocator";
        if type_array.array_kind != .Dynamic
        {
            Error (right, "'%' is not a member of type %", ident.name, left.type.as_string);
            return;
        }

        Warning (access, "the type for this expression does not exist yet, so it is *void for now");

        type = g_type_void_ptr;
        if left.semantic_meaning == .Constant
        {
            Warning (access, "this expression should be constant but we don't yet handle constant array values, so it is set to null for now");
            semantic_meaning = .Constant;
            value = .{pointer_value = 0, kind = .Pointer};
        }
        else if left.semantic_meaning == .Mutable
        {
            semantic_meaning = .Mutable;
        }
        else
        {
            semantic_meaning = .Value;
        }

    case "data";
        type = MakeTypePointer (type_array.element_type, access);

    case;
        Error (right, "'%' is not a member of type %", ident.name, left.type.as_string);
        return;
    }
}

CheckStringFieldAccess :: (using access : *AstFieldAccess)
{
    ident := cast (*AstIdentifier) right;
    if ident.name ==
    {
    case "count";
        type = g_type_s64;
        if left.semantic_meaning == .Constant
        {
            semantic_meaning = .Constant;
            value = .{int_value = left.value.string_value.count, kind = .Integer};
        }
        else if left.semantic_meaning == .Mutable
        {
            semantic_meaning = .Mutable;
        }
        else
        {
            semantic_meaning = .Value;
        }

    case "data";
        type = g_type_u8_ptr;
        if left.semantic_meaning == .Mutable
        {
            semantic_meaning = .Mutable;
        }
        else
        {
            semantic_meaning = .Value;
        }

    case;
        Error (right, "'%' is not a member of type %", ident.name, left.type.as_string);
        return;
    }
}

CheckFieldAccess :: (using access : *AstFieldAccess)
{
    type = g_type_invalid;
    defer right.type = type;

    CheckExpression (left);

    if right.kind != .Identifier
    {
        Error (right, "invalid expression type for rhs of field access operator");
        return;
    }

    // Don't check the rhs since we don't actually want to resolve the identifier the normal way

    if left.type == g_type_invalid
        return;

    ident := cast (*AstIdentifier) right;
    if left.type.kind ==
    {
    case .Array;
        CheckArrayFieldAccess (access);

        if type == g_type_invalid
            return;

    case .String;
        CheckStringFieldAccess (access);

        if type == g_type_invalid
            return;

    case;
        Error (right, "'%' is not a member of type %", ident.name, left.type.as_string);
        return;
    }

    if semantic_meaning == .Constant
    {
        Assert (access, value.kind != .Invalid, "It seems a constant unary operation did not get constant evaluated");
        // Info (access, "result is constant: %", ToString (value));
    }
}

CheckExpression :: (expr : *AstNode)
{
    expr.type = g_type_invalid;

    if expr.kind ==
    {
    case .Binary;
        CheckBinary (cast (*AstBinary) expr);
    case .Unary;
        CheckUnary (cast (*AstUnary) expr);
    case .Literal;
        CheckLiteral (cast (*AstLiteral) expr);
    case .Identifier;
        CheckIdentifier (cast (*AstIdentifier) expr);
    case .Procedure_Call;
        CheckProcedureCall (cast (*AstProcedureCall) expr);
    case .Subscript;
        CheckSubscript (cast (*AstSubscript) expr);
    case .Field_Access;
        CheckFieldAccess (cast (*AstFieldAccess) expr);

    case;
        Panic (expr, "Invalid expression kind (%)", expr.kind);
    }
}

CheckBlock :: (using block : *AstBlock)
{
    for statements
    {
        CheckStatement (it);
    }
}

CheckAssignment :: (using assign : *AstAssignment)
{
    CheckExpression (left);
    CheckExpression (right);

    if left.type == g_type_invalid || right.type == g_type_invalid
        return;

    if left.semantic_meaning ==
    {
    case .Type;
        Error (left, "assigning to a type");
        return;
    case .Value;
        Error (left, "assigning to an r-value");
        return;
    case .Constant;
        Error (left, "assigning to a constant");
        return;
    }

    if right.semantic_meaning == .Type
    {
        Error (right, "rhs of assignment is a type");
        return;
    }

    if !TypeCanImplicitlyCastTo (right.type, left.type)
    {
        Error (right, "invalid type for assignment (left type: %, right type: %)",
            left.type.as_string, right.type.as_string);
        return;
    }

    // @Hack: AstAssignment and AstBinary have the same memory layout, so we use
    // the routines to check binary expressions for assignments, which may lead
    // to unexpected behavior
    if op.kind ==
    {
    case .Plus_Equ; #through;
    case .Minus_Equ; #through;
    case .Star_Equ; #through;
    case .Slash_Equ;
        CheckArithmeticOperation (cast (*AstBinary) assign);

    case .Percent_Equ;
        CheckModulo (cast (*AstBinary) assign);

    case .Ampersand_Equ; #through;
    case .Pipe_Equ; #through;
    case .Caret_Equ; #through;
    case .Less_Less_Equ; #through;
    case .Greater_Greater_Equ;
        CheckBitOperation (cast (*AstBinary) assign);
    }

    // Reset the type and semantic meaning, plain statements don't have those
    type = null;
    semantic_meaning = .Invalid;
}

CheckIf :: (using if_stmt : *AstIf)
{
    CheckExpression (condition);
    if condition.type == g_type_invalid
        return;

    if !TypeCanImplicitlyCastTo (condition.type, g_type_bool)
    {
        Error (condition, "invalid type for condition in if statement. Expected a bool but got %", condition.type.as_string);
        return;
    }

    CheckStatement (body);

    if else_stmt
        CheckStatement (else_stmt);
}

CheckWhile :: (using while_stmt : *AstWhile)
{
    CheckExpression (condition);
    if condition.type == g_type_invalid
        return;

    if !TypeCanImplicitlyCastTo (condition.type, g_type_bool)
    {
        Error (condition, "invalid type for condition in while statement. Expected a bool but got %", condition.type.as_string);
        return;
    }

    enclosing_while := context.check.enclosing_while;
    context.check.enclosing_while = while_stmt;
    CheckStatement (body);
    context.check.enclosing_while = enclosing_while;
}

CheckReturn :: (using return_stmt : *AstReturn)
{
    using context.check;

    if !enclosing_proc
    {
        Error (return_stmt, "return statements are only allowed in procedures");
        return;
    }

    if return_stmt.return_values.count != enclosing_proc.results.count
    {
        Error (return_stmt,
            "invalid number of return values. Expected % but got %",
            enclosing_proc.results.count, return_stmt.return_values.count
        );
        Info (enclosing_proc.signature_range, "here is the signature of the enclosing procedure");
        return;
    }

    for it, i : return_stmt.return_values
    {
        CheckExpression (it);
        if it.type == g_type_invalid
            continue;

        if i >= enclosing_proc.results.count
            continue;

        if !TypeCanImplicitlyCastTo (it.type, enclosing_proc.results[i].type)
        {
            Error (it,
                "invalid type for return value %. Expected % but got %",
                i + 1,
                enclosing_proc.results[i].type.as_string,
                it.type.as_string
            );
            Info (enclosing_proc.signature_range, "here is the signature of the enclosing procedure");
        }
    }
}

CheckStatement :: (stmt : *AstNode)
{
    if IsExpression (stmt.kind)
    {
        CheckExpression (stmt);
        return;
    }

    if stmt.kind ==
    {
    case .Declaration;
        CheckDeclaration (cast (*AstDeclaration) stmt);
    case .Block;
        CheckBlock (cast (*AstBlock) stmt);
    case .Assignment;
        CheckAssignment (cast (*AstAssignment) stmt);
    case .If;
        CheckIf (cast (*AstIf) stmt);
    case .While;
        CheckWhile (cast (*AstWhile) stmt);
    case .Flow_Control;
        flow_control := (cast (*AstFlowControl) stmt).control;
        if flow_control ==
        {
        case .Break; #through;
        case .Continue;
            if !context.check.enclosing_while
                Error (stmt, "% is only allowed in while loops", Token_Names[flow_control]);
        case .Fallthrough;
            Error (stmt, "'fallthrough' is only allowed in case statements");
        }

    case .Defer;
        // @Todo: create a scope for defer, handle non linear scopes
        CheckStatement ((cast (*AstDefer) stmt).stmt);
    case .Return;
        CheckReturn (cast (*AstReturn) stmt);

    case;
        Error (stmt, "not yet handled");
    }
}

CheckEntryPointSignature :: (decl : *AstDeclaration)
{
    proc := cast (*AstProcedure) decl.expr;
    type := cast (*YalTypeProcedure) decl.type;
    Assert (type.kind == .Procedure);

    error := false;
    if type.results.count == 1 && type.results[0].kind != .Void
        error = true;
    if type.results.count > 1
        error = true;
    else if type.parameters.count > 1
        error = true;
    else if type.parameters.count == 1 && !TypesAreEqual (type.parameters[0], MakeTypeArray (.Slice, g_type_string, -1))
        error = true;

    if error
        Error (proc.signature_range, "invalid signature for entry point. Expected proc ([]string) -> void or proc () -> void");
}

CheckAllDeclarationsInFile :: (file : *YalFile)
{
    ProfileBlock ();

    for file.declarations
        CheckDeclaration (it);

    if !file.entry_point_declaration
        Error ("no entry point was defined in file '%'", file.filename);
    else
        CheckEntryPointSignature (file.entry_point_declaration);
}
