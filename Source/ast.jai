AstKind :: enum u8
{
    Invalid;

    Statements_Begin;

        Expressions_Begin;

            Identifier;
            Literal;
            Binary;
            Unary;

        Expressions_End;

    Statements_End;

    Count;
}

AstNode :: struct
{
    #as using range : TokenRange;
    #as kind : AstKind;
    is_parenthesized : bool;
}

IsExpression :: inline (kind : AstKind) -> bool #must
{
    return kind > .Expressions_Begin && kind < .Expressions_End;
}

IsStatement :: inline (kind : AstKind) -> bool #must
{
    return kind > .Statements_Begin && kind < .Statements_End;
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
