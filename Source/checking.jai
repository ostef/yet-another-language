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
    if scope.kind != .File
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

    case .Invalid;
        Panic (decl, "Invalid declaration kind %", decl.decl_kind);
    }

    if decl.identifier_count == 1
    {
        ScopeInsert (scope, symbol_kind, decl.single_identifier, decl);
    }
    else
    {
        for decl.identifiers
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
    for file.declarations
        CollectDeclaredSymbols (file.scope, it);
}

SetDeclarationType :: (decl : *AstDeclaration, type : *YalType)
{
    Assert (decl, decl.type == null, "declaration alread has a type");

    decl.type = type;
    if decl.identifier_count > 1
    {
        for decl.identifiers
            it.type = type;
    }
    else if decl.single_identifier
    {
        decl.single_identifier.type = type;
    }
}

CheckDeclaration :: (using decl : *AstDeclaration)
{
    if type
        return;

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
    }
}

CheckInitAssignment :: (using decl : *AstDeclaration)
{
    if expr.semantic_meaning == .Type
    {
        Error (expr, "assignment of a type");
        return;
    }

    if decl_kind == .Constant && expr.semantic_meaning != .Constant
    {
        Error (expr, "assigning non constant expression to a constant");
        return;
    }

    if type_node && !TypeCanImplicitlyCastTo (expr.type, type)
    {
        Error (expr, "invalid type for assignment (left type: %, right type: %)",
            type.as_string, expr.type.as_string);
        return;
    }
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

        type.type = MakeTypePointer (type_pointer.pointed_type.type);

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

        type.type = MakeTypeArray (type_array.array_kind, type_array.element_type.type, array_count);

    case .Type_Named;
        type_named := cast (*AstTypeNamed) type;
        if !type_named.identifier.symbol
            return;

        CheckIdentifier (type_named.identifier);
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
    case .Enum;
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
    Assert (binary, op.kind == .Pipe || op.kind == .Ampersand || op.kind == .Caret
        || op.kind == .Less_Less || op.kind == .Greater_Greater, "invalid op");

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
    Assert (binary, op.kind == .Percent, "invalid op");

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
    Assert (binary, op.kind == .Plus || op.kind == .Minus || op.kind == .Star || op.kind == .Slash, "invalid op");

    if left.type.kind != .Integer && left.type.kind != .Float
    || !TypeCanImplicitlyCastTo (right.type, left.type)
    {
        Error (binary, "invalid type for arithmetic operation (left is: %, right is: %)", left.type.as_string, right.type.as_string);
        return;
    }

    if op.kind == .Minus && left.type.kind == .Integer && !(cast (*YalTypeInteger) left.type).is_signed
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
        Info (binary, "result is constant: left is %, right is %, result is %", ToString (left.value), ToString (right.value), ToString (value));
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
    type = MakeTypePointer (expr.type);
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
        Info (unary, "result is constant: expr is %, result is %", ToString (expr.value), ToString (value));
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

    if !symbol.decl.type
        CheckDeclaration (symbol.decl);

    type = symbol.decl.type;

    if #complete symbol.kind ==
    {
    case .Invalid;
    case .Variable;
        semantic_meaning = .Mutable;

    case .Constant;
        semantic_meaning = .Constant;
        value = symbol.decl.expr.value;

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
            "mismatching number of arguments passed in procedure  Expected % but got %",
            proc_type.parameters.count, passed_arguments.count
        );

        if proc_type.node
            Info (proc_type.node, "here is the declaration of the procedure being called");
    }

    for i : 0..passed_arguments.count - 1
    {
        arg := passed_arguments[i];

        CheckExpression (arg);
        if arg.type == g_type_invalid
            continue;

        param := proc_type.parameters[i];
        if !TypeCanImplicitlyCastTo (arg.type, param)
        {
            Error (arg, "type mismatch for argument %.\n    Expected % but got %", i + 1, param.as_string, arg.type.as_string);
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

CheckFieldAccess :: (using access : *AstFieldAccess)
{
    CheckExpression (left);
    CheckExpression (right);

    if left.type == g_type_invalid || right.type == g_type_invalid
        return;

    type = g_type_invalid;
    Error (access, "not yet handled");
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
    if left.type == g_type_invalid
        return;

    CheckExpression (right);
    if right.type == g_type_invalid
        return;

    if left.semantic_meaning ==
    {
    case .Type;
        Error (left,
            "assigning to a non addressable expression (expression is a type)"
        );
        return;
    case .Value;
        Error (left,
            "assigning to a non addressable expression (expression is an r-value)"
        );
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
            return;

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
        CheckStatement ((cast (*AstDefer) stmt).stmt);
    case .Return;
        CheckReturn (cast (*AstReturn) stmt);

    case;
        Error (stmt, "not yet handled");
    }
}

CheckAllDeclarationsInFile :: (file : *YalFile)
{
    for file.declarations
        CheckDeclaration (it);
}
