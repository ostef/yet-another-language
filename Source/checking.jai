SemanticMeaning :: enum u8
{
    Invalid;
    Type;
    Value;
    Mutable;
    Immutable;
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
