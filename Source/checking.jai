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
    scope.kind = .Block;

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

ScopeInsert :: (using scope : *Scope, decl : *AstDeclaration)
{
    ArrayPush (*declarations, decl);

    if !decl || decl.identifier_count == 0
        return;

    symbol_kind : SymbolKind;
    if decl.decl_kind ==
    {
    case .Variable; #through;
    case .Field;
        symbol_kind = .Variable;

    case .Constant;
        symbol_kind = .Constant;

    case .Procedure;
        symbol_kind = .Procedure;

    case;
        Assert (false, "Invalid declaration kind %", decl.decl_kind);
    }

    if decl.identifier_count > 1
    {
        for decl.identifiers
            ScopeInsert (scope, symbol_kind, it, decl);
    }
    else
    {
        ScopeInsert (scope, symbol_kind, decl.single_identifier, decl);
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
