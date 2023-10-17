#import "Lexer";

FileId :: s16;

YalFile :: struct
{
    using lexer : YalLexer;
}

g_files : [..]*YalFile;
g_file_id_counter : s16;

GetFile :: inline (file_id : FileId) -> *YalFile #must
{
    return g_files[file_id];
}

AddFile :: (filename : string) -> *YalFile
{
    contents, ok := File.read_entire_file (filename, zero_terminated = true, log_errors = false);
    if !ok
    {
        Error ("could not read file '%'", filename);
        return null;
    }

    file := Alloc (YalFile);
    file.file_id = g_file_id_counter;
    file.filename = filename;
    file.text = contents;

    ArrayPush (*g_files, file);
    g_file_id_counter += 1;

    return file;
}

Recover :: (using file : *YalFile, stop_at : ..TokenKind)
{
    if MatchToken (*lexer, .EOF, .Semicolon)
        return;

    if NextTokenIs (*lexer, ..stop_at)
        return;

    ConsumeToken (*lexer);

    while !MatchToken (*lexer, .EOF)
    {
        if MatchToken (*lexer, .Semicolon)
            break;

        if NextTokenIs (*lexer,
            .Var, .Const, .Struct, .Enum, .Proc,
            .If, .Else, .For, .While, .Continue, .Break,
            .Switch, .Case, .Fallthrough, .Defer, .Using
        )
            break;

        if NextTokenIs (*lexer, ..stop_at)
            break;

        ConsumeToken (*lexer);
    }
}

MatchExpect :: (using file : *YalFile, kinds : ..TokenKind) -> bool #must
{
    match := MatchToken (*lexer, ..kinds);
    if match
        return true;

    ExpectedError (PrevToken (lexer), NextToken (*lexer), ..kinds);

    return false;
}

Expect :: (file : *YalFile, kinds : ..TokenKind) #expand
{
    if !MatchExpect (file, ..kinds)
        `return null;
}

ParseFile :: (using file : *YalFile)
{
    while !MatchToken (*lexer, .EOF)
    {
        statement := ParseStatement (file);
        if !statement
        {
            Recover (file);
            continue;
        }
    }
}

ParseStatement :: (using file : *YalFile) -> *AstNode #must
{
    expr := ParseExpression (file);
    if !expr
        return null;

    Expect (file, .Semicolon);

    return expr;
}

OperatorInfo :: struct
{
    Flags :: enum_flags u8
    {
        Non_Associative;
        Right_Associative;
        Prefix;
        Postfix;
    }

    tok : TokenKind;
    precedence : int;
    flags : Flags;
}

// Must be sorted by order of precedence
Operators :: OperatorInfo.[
    .{ .Pipe_Pipe, 2, 0 },

    .{ .Ampersand_Ampersand, 3, 0 },

    .{ .Equ_Equ,   4, .Non_Associative },
    .{ .Bang_Equ,    4, .Non_Associative },
    .{ .Less,          4, .Non_Associative },
    .{ .Greater,       4, .Non_Associative },
    .{ .Less_Equ,    4, .Non_Associative },
    .{ .Greater_Equ, 4, .Non_Associative },

    .{ .Less_Less,       5, 0 },
    .{ .Greater_Greater, 5, 0 },

    .{ .Pipe, 6, 0 },

    .{ .Tilde, 7, 0 },

    .{ .Ampersand, 8, 0 },

    .{ .Plus,  9, 0 },
    .{ .Minus, 9, 0 },

    .{ .Star,    10, 0 },
    .{ .Slash,   10, 0 },
    .{ .Percent, 10, 0 },

    .{ .Minus,     11, .Prefix },
    .{ .Bang,      11, .Prefix },
    .{ .Tilde,     11, .Prefix },
    .{ .Ampersand, 11, .Prefix }, // address of
    .{ .Star,      11, .Prefix }, // dereference

    .{ .Cast,    12, .Prefix },
    .{ .Size_Of, 12, .Prefix },

    .{ .Dot,          13, 0 }, // field access
    .{ .Open_Bracket, 13, .Postfix }, // subscript
    .{ .Open_Paren,   13, .Postfix }, // procedure call
];

// Check that our Operators array is ordered
#run {
    for i : 0..Operators.count - 2
    {
        a := Operators[i];
        b := Operators[i + 1];
        if a.precedence > b.precedence
        {
            message := FormatString ("Operators should be sorted by order of precedence");

            JaiC.compiler_report (message, #location (Token_Symbols));
        }
    }
}

BinaryOperatorInfo :: inline (tok : TokenKind) -> OperatorInfo #must
{
    for Operators
    {
        if it.tok == tok && !(it.flags & .Prefix) && !(it.flags & .Postfix)
            return it;
    }

    return .{};
}

BinaryOrPostfixOperatorInfo :: inline (tok : TokenKind) -> OperatorInfo #must
{
    for Operators
    {
        if it.tok == tok && !(it.flags & .Prefix)
            return it;
    }

    return .{};
}

UnaryOperatorInfo :: inline (tok : TokenKind) -> OperatorInfo #must
{
    for Operators
    {
        if it.tok == tok && ((it.flags & .Prefix) || (it.flags & .Postfix))
            return it;
    }

    return .{};
}

PrefixOperatorInfo :: inline (tok : TokenKind) -> OperatorInfo #must
{
    for Operators
    {
        if it.tok == tok && (it.flags & .Prefix)
            return it;
    }

    return .{};
}

PostfixOperatorInfo :: inline (tok : TokenKind) -> OperatorInfo #must
{
    for Operators
    {
        if it.tok == tok && (it.flags & .Postfix)
            return it;
    }

    return .{};
}

ParseExpression :: (using file : *YalFile, prec := 0) -> *AstNode #must
{
    expr := ParsePrimaryExpression (file);
    if !expr
        return null;

    tok := NextToken (*lexer);
    op := BinaryOrPostfixOperatorInfo (tok.kind);

    last_non_associative_tok : Token;
    last_non_associative_op : OperatorInfo;
    last_non_associative_op.precedence = Math.S64_MIN;

    max_prec := Math.S64_MAX;
    while op.tok != .Invalid && prec <= op.precedence && op.precedence <= max_prec
    {
        ConsumeToken (*lexer);

        if !(op.flags & .Postfix)
        {
            right_prec := ifx op.flags & .Right_Associative
                then op.precedence
                else op.precedence + 1;

            right := ParseExpression (file, right_prec);
            if !right
                return null;

            expr = MakeAstBinary (tok, expr, right);
        }
        else
        {
            expr = MakeAstUnary (tok, expr);
        }

        if op.flags & .Non_Associative
        {
            last_non_associative_tok = tok;
            last_non_associative_op = op;
        }

        if (op.flags & .Right_Associative) || (op.flags & .Non_Associative)
            max_prec = op.precedence - 1;
        else
            max_prec = op.precedence;

        tok = NextToken (*lexer);
        op = BinaryOrPostfixOperatorInfo (tok.kind);
    }

    // Handle associativity errors
    if op.tok != .Invalid && op.precedence == last_non_associative_op.precedence
    {
        next := NextToken (*lexer);
        if next.kind == last_non_associative_op.tok
        {
            SyntaxError (next,
                "chaining of non associative operator %", Token_Names[next.kind]);
        }
        else
        {
            SyntaxError (next,
                "chaining of non associative operator % with operator % of same precedence",
                    Token_Names[last_non_associative_tok.kind], Token_Names[next.kind]);
        }

        InfoWithoutSourceCode (next, "you might want to use parentheses to fix this");
        Info (last_non_associative_tok, "here is the first occurence of the non associative operator");
    }

    return expr;
}

ParsePrimaryExpression :: (using file : *YalFile) -> *AstNode #must
{
    tok := NextToken (*lexer);
    op := PrefixOperatorInfo (tok.kind);

    if op.tok != .Invalid && (op.flags & .Prefix)
    {
        ConsumeToken (*lexer);

        expr := ParseExpression (file, op.precedence);
        if !expr
            return null;

        return MakeAstUnary (tok, expr);
    }
    else if MatchToken (*lexer, .Open_Paren)
    {
        open_paren_tok := PrevToken (lexer);

        expr := ParseExpression (file);
        if !expr
            return null;

        if NextTokenIs (*lexer, ..Tokens_Assignment)
        {
            SyntaxError (NextToken (*lexer), "assignment in parenthesized expression");

            return null;
        }

        Expect (file, .Close_Paren);

        expr.is_parenthesized = true;
        expr.range = TokenRangeJoin (open_paren_tok, PrevToken (lexer));

        return expr;
    }
    else if MatchToken (*lexer, .Identifier)
    {
        return MakeAstIdentifier (tok);
    }
    else if MatchToken (*lexer, .Int_Literal, .Float_Literal, .String_Literal,
        .Char_Literal, .True, .False, .Null)
    {
        return MakeAstLiteral (tok);
    }

    SyntaxError (tok, "expected an expression, but got % instead", Token_Names[tok.kind]);

    return null;
}
