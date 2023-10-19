SemanticMeaning :: enum u8
{
    Invalid;
    Type;
    Value;
    Constant;
    Mutable;
}

// @Note: I would like to be able to have the check context in
// the Jai context, but since we generate TokenKind via a #insert,
// and the Check_Context indirectly depends on TokenKind, the #insert
// never gets executed because it needs the context to be finalized
// before doing so, which requires TokenKind to be declared (circular
// dependency situation)
// #add_context using check : CheckContext;

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
    Assert (block.scope == null);

    scope := ScopeCreate (parent, .Block);
    scope.block = block;
    block.scope = scope;

    return scope;
}

ScopeCreate :: inline (parent : *Scope, procedure : *AstProcedure) -> *Scope
{
    Assert (procedure.scope == null);

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
        Panic ("Invalid declaration kind %", decl.decl_kind);
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

ResolveIdentifiers :: (scope : *Scope, node : *$T)
#modify { return TypeIsAstNode (cast (*Type_Info) T); }
{
    if !node
        return;

    #if T == AstNode
    {
        inline ResolveIdentifiersForUntypedNode (scope, node);
    }
    #if T == AstIdentifier
    {
        if node.symbol
            return;

        node.symbol = ScopeLookup (scope, node.name);
        if !node.symbol
        {
            Error (node, "undeclared identifier '%'", node.name);
        }
    }
    else
    {
        #insert -> string
        {
            info := type_info (T);

            builder : StringBuilder;

            StringBuilderAppend (*builder, "// ResolveIdentifiers for %\n", T);
            for member : info.members
            {
                if member.name == "scope" && member.type == type_info (*Scope)
                    StringBuilderAppend (*builder, "scope = node.scope;\n");
            }

            for member : info.members
            {
                for note : member.notes
                {
                    if note == "NoResolveIdentifiers"
                    {
                        StringBuilderAppend (*builder, "// % is ignored\n", member.name);
                        continue member;
                    }
                }

                if member.type.type == .POINTER
                {
                    pointed_type := (cast (*Type_Info_Pointer) member.type).pointer_to;
                    if TypeIsAstNode (pointed_type)
                        StringBuilderAppend (*builder, "ResolveIdentifiers (scope, node.%);\n", member.name);
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
                        StringBuilderAppend (*builder, "    ResolveIdentifiers (scope, it);\n");
                    }
                }
            }

            return StringBuilderBuild (*builder);
        }
    }
}

ResolveIdentifiersForUntypedNode :: (scope : *Scope, node : *AstNode)
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
            StringBuilderAppend (*builder, "    ResolveIdentifiers (scope, cast (*");
            AppendAstStructName (*builder, kind);
            StringBuilderAppend (*builder, ") node);\n");
        }
        StringBuilderAppend (*builder, "}");

        return StringBuilderBuild (*builder);
    };
}

ResolveAllIdentifiersInFile :: (file : *YalFile)
{
    for file.declarations
        ResolveIdentifiers (file.scope, it);
}

SetDeclarationType :: (decl : *AstDeclaration, type : *YalType)
{
    Assert (decl.type == null);

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

CheckDeclaration :: (decl : *AstDeclaration)
{
    defer if !decl.type then SetDeclarationType (decl, g_type_invalid);

    if #complete decl.decl_kind ==
    {
    case .Invalid;
        decl.type = g_type_invalid;

    case .Variable; #through;
    case .Constant; #through;
    case .Field;
        if decl.type_node
        {
            CheckType (decl.type_node);
            SetDeclarationType (decl, decl.type_node.type);
        }

        if decl.expr
        {
            CheckExpression (decl.expr);

            if decl.expr.type != g_type_invalid
            {
                if !decl.type_node
                    SetDeclarationType (decl, decl.expr.type);
                else
                    CheckInitAssignment (decl);
            }
        }
        else if decl.decl_kind == .Constant
        {
            Error (decl, "uninitialized constant");
        }

    case .Procedure;
        CheckProcedureDeclaration (decl);
    }
}

CheckInitAssignment :: (decl : *AstDeclaration)
{
    if decl.expr.semantic_meaning == .Type
    {
        Error (decl.expr, "assignment of a type");
        return;
    }

    if decl.decl_kind == .Constant && decl.expr.semantic_meaning != .Constant
    {
        Error (decl.expr, "expression is not constant");
        return;
    }

    if !TypeCanImplicitlyCastTo (decl.expr.type, decl.type)
    {
        Error (decl.expr, "invalid type for assignment (left type: %, right type: %)",
            decl.type.as_string, decl.expr.type.as_string);
        return;
    }
}

CheckProcedureSignature :: (proc : *AstProcedure)
{
    proc.type = g_type_invalid;

    parameters : [..]*YalType;
    results : [..]*YalType;

    for proc.parameters
    {
        CheckDeclaration (it);
        if it.type == g_type_invalid
            return;

        ArrayPush (*parameters, it.type);
    }

    for proc.results
    {
        CheckDeclaration (it);
        if it.type == g_type_invalid
            return;

        ArrayPush (*results, it.type);
    }

    proc.type = MakeTypeProcedure (proc, parameters, results);
}

CheckProcedureDeclaration :: (decl : *AstDeclaration)
{
    proc := cast (*AstProcedure) decl.expr;

    CheckProcedureSignature (proc);
    SetDeclarationType (decl, proc.type);

    if decl.type == g_type_invalid
        return;

    CheckBlock (proc.body);
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
        Panic ("Invalid ast kind (%)", type.kind);
    }
}

CheckBinary :: (binary : *AstBinary)
{
    Error (binary, "not yet handled");
    binary.type = g_type_invalid;
}

CheckUnary :: (unary : *AstUnary)
{
    Error (unary, "not yet handled");
    unary.type = g_type_invalid;
}

CheckIdentifier :: (ident : *AstIdentifier)
{
    ident.type = g_type_invalid;

    if !ident.symbol
        return;

    if !ident.symbol.decl.type
        CheckDeclaration (ident.symbol.decl);

    ident.type = ident.symbol.decl.type;

    if #complete ident.symbol.kind ==
    {
    case .Invalid;
    case .Variable;
        ident.semantic_meaning = .Mutable;

    case .Constant;
        ident.semantic_meaning = .Constant;
        ident.value = ident.symbol.decl.expr.value;

    case .Procedure;
        ident.semantic_meaning = .Constant;
        ident.value = .{
            procedure_node = cast (*AstProcedure) ident.symbol.decl.expr,
            kind = .Procedure
        };

    case .Type;
        ident.semantic_meaning = .Type;
    }
}

CheckLiteral :: inline (lit : *AstLiteral)
{
    lit.semantic_meaning = .Constant;
    lit.value, lit.type = MakeConstantValue (.{range=lit.range, kind=lit.literal_kind});
}

CheckProcedureCall :: (call : *AstProcedureCall)
{
    call.type = g_type_invalid;

    CheckExpression (call.callee);
    if call.callee.type == g_type_invalid
        return;

    if call.callee.type.kind != .Procedure
    {
        Error (call.callee, "callee in procedure call expression is not a procedure (type is: %)", call.callee.type.as_string);
        return;
    }

    proc_type := cast (*YalTypeProcedure) call.callee.type;
    if call.passed_arguments.count != proc_type.parameters.count
    {
        Error (call,
            "mismatching number of arguments passed in procedure call. Expected % but got %",
            proc_type.parameters.count, call.passed_arguments.count
        );

        if proc_type.node
            Info (proc_type.node, "here is the declaration of the procedure being called");
    }

    for i : 0..call.passed_arguments.count - 1
    {
        arg := call.passed_arguments[i];

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
        call.type = g_type_void;
    else
        call.type = proc_type.results[0];
}

CheckSubscript :: (subscript : *AstSubscript)
{
    subscript.type = g_type_invalid;

    CheckExpression (subscript.subscripted);
    if subscript.subscripted.type == g_type_invalid
        return;

    subscript_type := subscript.subscripted.type;
    if subscript_type.kind != .Array && subscript_type.kind != .Pointer && subscript_type.kind != .String
    {
        Error (subscript.subscripted,
            "invalid type for subscript operator. Expected an array, a pointer or a string but got %",
            subscript_type.as_string
        );
        return;
    }

    if subscript_type.kind ==
    {
    case .Array;
        subscript.type = (cast (*YalTypeArray) subscript_type).element_type;
    case .Pointer;
        subscript.type = (cast (*YalTypePointer) subscript_type).pointed_type;
    case .String;
        subscript.type = g_type_u8;
    }

    CheckExpression (subscript.index);
    if subscript.index.type == g_type_invalid
        return;

    index_type := subscript.index.type;
    if index_type.kind != .Integer
    {
        Error (subscript.index,
            "invalid type for index of subscript operator. Expected an integer but got %",
            index_type.as_string
        );
        return;
    }

    subscript.semantic_meaning = subscript.subscripted.semantic_meaning;
    if subscript.semantic_meaning == .Constant && subscript.index.semantic_meaning != .Constant
        subscript.semantic_meaning = .Value;

    if subscript.index.semantic_meaning == .Constant
    && subscript_type.kind == .Array && (cast (*YalTypeArray) subscript_type).array_kind == .Static
    {
        array_count := (cast (*YalTypeArray) subscript_type).count;
        index_value := subscript.index.value.int_value;
        Info (subscript.index, "indexing static array with a constant % %", array_count, index_value);

        if array_count == 0
        {
           Error (subscript.index,
                "static array subscript index out of bounds. Array is empty so no index is valid");
        }

        if index_value < 0 || index_value >= array_count
        {
            Error (subscript.index,
                "static array subscript index out of bounds. Expected [0; %] but got %",
                array_count - 1, index_value
            );
        }
    }
}

CheckFieldAccess :: (access : *AstFieldAccess)
{
    Error (access, "not yet handled");
    access.type = g_type_invalid;
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
        Panic ("Invalid expression kind (%)", expr.kind);
    }
}

CheckBlock :: (block : *AstBlock)
{
    for block.statements
    {
        CheckStatement (it);
    }
}

CheckAssignment :: (assign : *AstAssignment)
{
    CheckExpression (assign.left);
    if assign.left.type == g_type_invalid
        return;

    CheckExpression (assign.right);
    if assign.right.type == g_type_invalid
        return;

    if assign.left.semantic_meaning ==
    {
    case .Type;
        Error (assign.left,
            "assigning to a non addressable expression (expression is a type)"
        );
        return;
    case .Value;
        Error (assign.left,
            "assigning to a non addressable expression (expression is an r-value)"
        );
        return;
    case .Constant;
        Error (assign.left, "assigning to a constant");
        return;
    }

    if assign.right.semantic_meaning == .Type
    {
        Error (assign.right, "rhs of assignment is a type");
        return;
    }

    if !TypeCanImplicitlyCastTo (assign.right.type, assign.left.type)
    {
        Error (assign.right, "invalid type for assignment (left type: %, right type: %)",
            assign.left.type.as_string, assign.right.type.as_string);
        return;
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

    case;
        Error (stmt, "not yet handled");
    /*
    case .If;
        CheckIf (cast (*AstIf) stmt);
    case .While;
        CheckIf (cast (*AstWhile) stmt);
    case .Defer;
        CheckStatment ((cast (*AstDefer) stmt).stmt);
    case .Return;
        CheckReturn (cast (*AstReturn) stmt);
    */
    }
}

CheckAllDeclarationsInFile :: (file : *YalFile)
{
    for file.declarations
        CheckDeclaration (it);
}
