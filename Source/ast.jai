AstKind :: enum u8
{
    Invalid;

    Statements_Begin;

        Bad_Declaration;
        Declaration;

        Block;

        Expressions_Begin;

            Identifier;
            Literal;
            Binary;
            Unary;

        Expressions_End;

    Statements_End;

    Types_Begin;
        Type_Pointer;
        Type_Array;
        Type_Named;
        Type_Primitive;
        Procedure;
        Struct;
        Enum;
    Types_End;

    Count;
}

AstNode :: struct
{
    #as using range : TokenRange;
    #as kind : AstKind;
    is_parenthesized : bool;
}

IsType :: inline (kind : AstKind) -> bool #must
{
    return kind > .Types_Begin && kind < .Types_End;
}

IsExpression :: inline (kind : AstKind) -> bool #must
{
    return kind > .Expressions_Begin && kind < .Expressions_End;
}

IsStatement :: inline (kind : AstKind) -> bool #must
{
    return kind > .Statements_Begin && kind < .Statements_End;
}

AstBlock :: struct
{
    #as using base : AstNode;
    base.kind = .Block;

    statements : []*AstNode;
}

MakeAstBlock :: inline (open_brace_tok : Token, close_brace_tok : Token, statements : []*AstNode) -> *AstBlock #must
{
    node := Alloc (AstBlock);
    node.statements = statements;
    node.range = TokenRangeJoin (open_brace_tok, close_brace_tok);

    return node;
}

DeclarationKind :: enum u8
{
    Invalid;
    Variable;
    Constant;
    Field;
    Procedure;
}

AstDeclaration :: struct
{
    #as using base : AstNode;
    base.kind = .Declaration;

    identifier_count : s64;
    single_identifier : *AstIdentifier;

    #place identifier_count;
    identifiers : []*AstIdentifier;

    type_node : *AstNode;
    expr : *AstNode;

    decl_kind : DeclarationKind;
}

MakeAstBadDeclaration :: inline (range : TokenRange) -> *AstDeclaration #must
{
    node := Alloc (AstDeclaration);
    node.kind = .Bad_Declaration;
    node.range = range;

    return node;
}

MakeAstDeclaration :: inline (begin_tok : Token, ident : *AstIdentifier, type_node : *AstNode, expr : *AstNode, decl_kind : DeclarationKind) -> *AstDeclaration #must
{
    node := Alloc (AstDeclaration);

    if ident
        node.identifier_count = 1;

    node.single_identifier = ident;
    node.decl_kind = decl_kind;
    node.type_node = type_node;
    node.expr = expr;

    if expr
        node.range = TokenRangeJoin (begin_tok, expr);
    else if type_node
        node.range = TokenRangeJoin (begin_tok, type_node);
    else if ident
        node.range = TokenRangeJoin (begin_tok, ident);
    else // This probably should not happen but just in case
        node.range = begin_tok;

    return node;
}

MakeAstDeclarationMultiple :: inline (begin_tok : Token, idents : []*AstIdentifier, type_node : *AstNode, expr : *AstNode, decl_kind : DeclarationKind) -> *AstDeclaration #must
{
    node := Alloc (AstDeclaration);
    node.identifiers = idents;
    node.decl_kind = decl_kind;
    node.type_node = type_node;
    node.expr = expr;

    if expr
        node.range = TokenRangeJoin (begin_tok, expr);
    else if type_node
        node.range = TokenRangeJoin (begin_tok, type_node);
    else
        node.range = TokenRangeJoin (begin_tok, idents[idents.count - 1]);

    return node;
}

AstIdentifier :: struct
{
    #as using base : AstNode;
    base.kind = .Identifier;

    name : string;
}

MakeAstIdentifier :: inline (tok : Token) -> *AstIdentifier #must
{
    node := Alloc (AstIdentifier);
    node.name = TokenToString (tok);
    node.range = tok.range;

    return node;
}

AstLiteral :: struct
{
    #as using base : AstNode;
    base.kind = .Literal;

    literal_kind : TokenKind;
}

MakeAstLiteral :: inline (tok : Token) -> *AstLiteral #must
{
    node := Alloc (AstLiteral);
    node.literal_kind = tok.kind;
    node.range = tok.range;

    return node;
}

AstUnary :: struct
{
    #as using base : AstNode;
    base.kind = .Unary;

    op : Token;
    expr : *AstNode;
}

MakeAstUnary :: inline (op : Token, expr : *AstNode) -> *AstUnary #must
{
    node := Alloc (AstUnary);
    node.op = op;
    node.expr = expr;
    node.range = TokenRangeJoin (op, expr);

    return node;
}

AstBinary :: struct
{
    #as using base : AstNode;
    base.kind = .Binary;

    op : Token;
    left : *AstNode;
    right : *AstNode;
}

MakeAstBinary :: inline (op : Token, left : *AstNode, right : *AstNode) -> *AstBinary #must
{
    node := Alloc (AstBinary);
    node.op = op;
    node.left = left;
    node.right = right;
    node.range = TokenRangeJoin (left, right);

    return node;
}

AstTypePointer :: struct
{
    #as using base : AstNode;
    base.kind = .Type_Pointer;

    pointed_type : *AstNode;
}

MakeAstTypePointer :: inline (star_tok : Token, pointed_type : *AstNode) -> *AstTypePointer #must
{
    node := Alloc (AstTypePointer);
    node.pointed_type = pointed_type;
    node.range = TokenRangeJoin (star_tok, pointed_type);

    return node;
}

ArrayKind :: enum u8
{
    Invalid;
    Slice;
    Dynamic;
    Static;
}

AstTypeArray :: struct
{
    #as using base : AstNode;
    base.kind = .Type_Array;

    element_type : *AstNode;
    element_count : *AstNode;
    array_kind : ArrayKind;
}

MakeAstTypeArray :: inline (open_bracket_tok : Token, element_type : *AstNode, element_count : *AstNode, is_dynamic : bool) -> *AstTypeArray #must
{
    node := Alloc (AstTypeArray);

    if is_dynamic
        node.array_kind = .Dynamic;
    else if element_count
        node.array_kind = .Static;
    else
        node.array_kind = .Slice;

    node.element_type = element_type;
    node.element_count = element_count;
    node.range = TokenRangeJoin (open_bracket_tok, element_type);

    return node;
}

AstTypeNamed :: struct
{
    #as using base : AstNode;
    base.kind = .Type_Named;

    identifier : *AstIdentifier;
}


MakeAstTypeNamed :: inline (ident : *AstIdentifier) -> *AstTypeNamed #must
{
    node := Alloc (AstTypeNamed);
    node.identifier = ident;
    node.range = ident.range;

    return node;
}

AstTypePrimitive :: struct
{
    #as using base : AstNode;
    base.kind = .Type_Primitive;

    primitive_kind : TokenKind;
}

MakeAstTypePrimitive :: inline (tok : Token) -> *AstTypePrimitive #must
{
    node := Alloc (AstTypePrimitive);
    node.primitive_kind = tok.kind;
    node.range = tok.range;

    return node;
}

AstStruct :: struct
{
    #as using base : AstNode;
    base.kind = .Struct;

    body : *AstBlock;
}

MakeAstStruct :: inline (struct_tok : Token, body : *AstBlock) -> *AstStruct #must
{
    node := Alloc (AstStruct);
    node.body = body;
    node.range = TokenRangeJoin (struct_tok, body);

    return node;
}

AstEnum :: struct
{
    #as using base : AstNode;
    base.kind = .Enum;

    base_type : *AstNode;
    body : *AstBlock;
}

MakeAstEnum :: inline (enum_tok : Token, base_type : *AstNode, body : *AstBlock) -> *AstEnum #must
{
    node := Alloc (AstEnum);
    node.base_type = base_type;
    node.body = body;
    node.range = TokenRangeJoin (enum_tok, body);

    return node;
}

AstProcedure :: struct
{
    #as using base : AstNode;
    base.kind = .Procedure;

    parameters : []*AstDeclaration;
    results : []*AstDeclaration;
    body : *AstBlock;
}

MakeAstProcedure :: inline (proc_tok : Token, close_paren_tok : Token, parameters : []*AstDeclaration, results : []*AstDeclaration, body : *AstBlock = null) -> *AstProcedure #must
{
    node := Alloc (AstProcedure);
    node.parameters = parameters;
    node.results = results;
    node.body = body;

    if body
        node.range = TokenRangeJoin (proc_tok, body);
    else if results.count > 0
        node.range = TokenRangeJoin (proc_tok, results[results.count - 1]);
    else
        node.range = TokenRangeJoin (proc_tok, close_paren_tok);

    return node;
}
