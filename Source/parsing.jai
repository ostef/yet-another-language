#import "Lexer";

FileId :: s16;

YalFile :: struct
{
    using lexer : YalLexer;
    using, only (declarations) scope : *Scope;
    entry_point_declaration : *AstDeclaration;
    emitted_c_code : string;
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
        Error ("Could not read file '%'", filename);
        return null;
    }

    file := Alloc (YalFile);
    file.file_id = g_file_id_counter;
    file.filename = filename;
    file.text = contents;
    ScopeCreate (file);

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
    ProfileBlock ();

    while !MatchToken (*lexer, .EOF)
    {
        decl := ParseDeclaration (file);
        if !decl
        {
            Recover (file);
            continue;
        }

        ArrayPush (*declarations, decl);
    }

    /*
    builder : SourceCodeBuilder;
    for declarations
    {
        more_newlines := !ShouldStatementEndInSemicolon (it);

        if it_index != 0 && more_newlines
            Append (*builder, "\n");

        PrintAstNode (*builder, it);

        if ShouldStatementEndInSemicolon (it)
            Append (*builder, ";\n");
        else
            Append (*builder, "\n");

        if it_index != declarations.count - 1 && more_newlines
            Append (*builder, "\n");
    }

    Println ("Ast print-back for file %:", filename);
    Println (Build (*builder));
    */
}

ParseStatement :: (using file : *YalFile) -> *AstNode #must
{
    if NextTokenIs (*lexer, .Var, .Const, .Proc)
    {
        return ParseDeclaration (file);
    }
    else if MatchToken (*lexer, .If)
    {
        return ParseIf (file);
    }
    else if MatchToken (*lexer, .While)
    {
        return ParseWhile (file);
    }
    else if MatchToken (*lexer, .Defer)
    {
        defer_tok := PrevToken (lexer);
        stmt := ParseStatement (file);
        if !stmt
            return null;

        return MakeAstDefer (defer_tok, stmt);
    }
    else if MatchToken (*lexer, .Return)
    {
        return ParseReturn (file);
    }
    else if MatchToken (*lexer, .Break, .Continue, .Fallthrough)
    {
        tok := PrevToken (lexer);
        Expect (file, .Semicolon);

        return MakeAstFlowControl (tok);
    }
    else if NextTokenIs (*lexer, .Open_Curly)
    {
        return ParseBlock (file);
    }
    else
    {
        expr := ParseExpression (file);
        if !expr
            return null;

        if MatchToken (*lexer, ..Tokens_Assignment)
        {
            op := PrevToken (lexer);

            right := ParseExpression (file);
            if !right
                return null;

            if MatchToken (*lexer, ..Tokens_Assignment)
            {
                SyntaxError (PrevToken (lexer), "Chaining of assignment statements");
                return null;
            }

            expr = MakeAstAssignment (op, expr, right);
        }

        if !MatchExpect (file, .Semicolon)
        {
            if NextTokenIs (*lexer, .Colon)
                Info (NextToken (*lexer), "This looks like a variable or constant declaration, but the 'var' or 'const' keyword is missing");

            return null;
        }

        return expr;
    }

    return null;
}

ParseBlock :: (using file : *YalFile) -> *AstBlock #must
{
    Expect (file, .Open_Curly);
    open_brace_tok := PrevToken (lexer);

    statements : [..]*AstNode;

    while !MatchToken (*lexer, .EOF, .Close_Curly)
    {
        stmt := ParseStatement (file);
        if !stmt
        {
            Recover (file, .Close_Curly);
            continue;
        }

        ArrayPush (*statements, stmt);
    }

    if PrevToken (lexer).kind != .Close_Curly
    {
        ExpectedError (PrevToken (lexer, 1), PrevToken (lexer), .Close_Curly);

        return null;
    }

    return MakeAstBlock (open_brace_tok, PrevToken (lexer), statements);
}

ParseIf :: (using file : *YalFile) -> *AstIf #must
{
    if_tok := PrevToken (lexer);

    condition := ParseExpression (file);
    if !condition
        return null;

    body := ParseStatement (file);
    if !body
        return null;

    else_stmt : *AstNode;
    if MatchToken (*lexer, .Else)
    {
        else_stmt = ParseStatement (file);
        if !else_stmt
            return null;
    }

    return MakeAstIf (if_tok, condition, body, else_stmt);
}

ParseWhile :: (using file : *YalFile) -> *AstWhile #must
{
    while_tok := PrevToken (lexer);

    condition := ParseExpression (file);
    if !condition
        return null;

    body := ParseStatement (file);
    if !body
        return null;

    return MakeAstWhile (while_tok, condition, body);
}

ParseReturn :: (using file : *YalFile) -> *AstReturn #must
{
    return_tok := PrevToken (lexer);

    return_values : [..]*AstNode;
    first := true;
    while !MatchToken (*lexer, .EOF, .Semicolon)
    {
        defer first = false;

        if !first
        {
            if !MatchExpect (file, .Comma)
                return null;

            if MatchToken (*lexer, .Semicolon)
            {
                SyntaxError (PrevToken (lexer),
                    "Expected a return value after ',', but got ';' instead");
                return null;
            }
        }

        expr := ParseExpression (file);
        if !expr
            return null;

        ArrayPush (*return_values, expr);
    }

    if PrevToken (lexer).kind != .Semicolon
    {
        ExpectedError (PrevToken (lexer, 1), PrevToken (lexer), .Semicolon);
        return null;
    }

    return MakeAstReturn (return_tok, return_values);
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
    .{ .Pipe_Pipe, 2, 0 }, // logical or

    .{ .Ampersand_Ampersand, 3, 0 },  // logical and

    .{ .Equ_Equ,     4, .Non_Associative },
    .{ .Bang_Equ,    4, .Non_Associative },
    .{ .Less,        4, .Non_Associative },
    .{ .Greater,     4, .Non_Associative },
    .{ .Less_Equ,    4, .Non_Associative },
    .{ .Greater_Equ, 4, .Non_Associative },

    .{ .Less_Less,       5, 0 }, // bit shift left
    .{ .Greater_Greater, 5, 0 }, // bit shift right

    .{ .Pipe, 6, 0 },  // bit or

    .{ .Caret, 7, 0 },  // bit xor

    .{ .Ampersand, 8, 0 }, // bit and

    .{ .Plus,  9, 0 },
    .{ .Minus, 9, 0 },

    .{ .Star,    10, 0 },
    .{ .Slash,   10, 0 },
    .{ .Percent, 10, 0 }, // modulo

    .{ .Minus,     11, .Prefix },
    .{ .Bang,      11, .Prefix }, // logical not
    .{ .Caret,     11, .Prefix }, // bit not
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

            if op.tok == .Dot
                expr = MakeAstFieldAccess (expr, right);
            else
                expr = MakeAstBinary (tok, expr, right);
        }
        else if op.tok == .Open_Bracket   // Subscript
        {
            index_expr := ParseExpression (file);
            if !index_expr
                return null;

            Expect (file, .Close_Bracket);

            expr = MakeAstSubscript (expr, index_expr, PrevToken (lexer));
        }
        else if op.tok == .Open_Paren   // Procedure call
        {
            return ParseProcedureCall (file, expr);
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
                "Chaining of non associative operator %", Token_Names[next.kind]);
        }
        else
        {
            SyntaxError (next,
                "Chaining of non associative operator % with operator % of same precedence",
                    Token_Names[last_non_associative_tok.kind], Token_Names[next.kind]);
        }

        InfoWithoutSourceCode (next, "You might want to use parentheses to fix this");
        Info (last_non_associative_tok, "Here is the first occurence of the non associative operator");
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
            SyntaxError (NextToken (*lexer), "Assignment in parenthesized expression");

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

    SyntaxError (tok, "Expected an expression, but got % instead", Token_Names[tok.kind]);

    return null;
}

ParseProcedureCall :: (using file : *YalFile, callee : *AstNode) -> *AstProcedureCall #must
{
    open_paren_tok := PrevToken (lexer);

    arguments : [..]*AstNode;
    first := true;
    while !MatchToken (*lexer, .EOF, .Close_Paren)
    {
        defer first = false;

        if !first
        {
            if !MatchExpect (file, .Comma)
                return null;

            if MatchToken (*lexer, .Close_Paren)
            {
                SyntaxError (PrevToken (lexer),
                    "Expected expression after ',', but got ')' instead");

                return null;
            }
        }

        arg := ParseExpression (file);
        if !arg
            return null;

        ArrayPush (*arguments, arg);
    }

    if PrevToken (lexer).kind != .Close_Paren
    {
        ExpectedError (PrevToken (lexer, 1), PrevToken (lexer), .Close_Paren);
        return null;
    }

    return MakeAstProcedureCall (callee, arguments, PrevToken (lexer));
}

ParseType :: (using file : *YalFile) -> *AstNode #must
{
    if MatchToken (*lexer, .Star)
    {
        star_tok := PrevToken (lexer);
        pointed_type := ParseType (file);
        if !pointed_type
            return null;

        return MakeAstTypePointer (star_tok, pointed_type);
    }

    if MatchToken (*lexer, .Open_Bracket)
    {
        open_bracket_tok := PrevToken (lexer);

        is_dynamic := false;
        element_count : *AstNode;

        if MatchToken (*lexer, .Dot_Dot)
        {
            is_dynamic = true;
        }
        else if !NextTokenIs (*lexer, .Close_Bracket)
        {
            element_count = ParseExpression (file);
            if !element_count
                return null;
        }

        Expect (file, .Close_Bracket);

        element_type := ParseType (file);
        if !element_type
            return null;

        return MakeAstTypeArray (open_bracket_tok, element_type, element_count, is_dynamic);
    }

    if MatchToken (*lexer, .Proc)
        return ParseProcedureSignature (file, PrevToken (lexer));

    if MatchToken (*lexer, .Struct)
        return ParseStruct (file, PrevToken (lexer));

    if MatchToken (*lexer, .Enum)
        return ParseEnum (file, PrevToken (lexer));

    if MatchToken (*lexer, .Identifier)
        return MakeAstTypeNamed (MakeAstIdentifier (PrevToken (lexer)));

    if !MatchToken (*lexer, .Void, .Int, .Uint,
        .U8, .S8, .U16, .S16, .U32, .S32, .U64, .S64,
        .Float, .F32, .F64,
        .Bool, .String
    )
    {
        SyntaxError (NextToken (*lexer),
            "Expected a type, but got % instead", Token_Names[NextToken (*lexer).kind]);

        return null;
    }

    return MakeAstTypePrimitive (PrevToken (lexer));
}

ParseProcedureSignature :: (using file : *YalFile, proc_tok : Token) -> *AstProcedure #must
{
    parameters : [..]*AstDeclaration;

    Expect (file, .Open_Paren);
    if !ParseFieldList (file, *parameters)
        return null;

    close_paren := PrevToken (lexer);

    results : [..]*AstDeclaration;
    results_close_paren : Token;

    if MatchToken (*lexer, .Arrow)
    {
        if MatchToken (*lexer, .Open_Paren)
        {
            if !ParseFieldList (file, *results)
                return null;

            results_close_paren = PrevToken (*lexer);
        }
        else
        {
            decl := ParseFieldDeclaration (file);
            if !decl
                return null;

            ArrayPush (*results, decl);
        }
    }

    return MakeAstProcedure (proc_tok, close_paren, parameters, results, results_close_paren);
}

ParseDeclaration :: (using file : *YalFile) -> *AstDeclaration #must
{
    if MatchToken (*lexer, .Var)
    {
        decl := ParseValueDeclaration (file, .Variable);
        if !decl
            return null;

        Expect (file, .Semicolon);

        return decl;
    }
    else if MatchToken (*lexer, .Const)
    {
        decl := ParseValueDeclaration (file, .Constant);
        if !decl
            return null;

        Expect (file, .Semicolon);

        return decl;
    }
    else if MatchToken (*lexer, .Typedef)
    {
        decl := ParseTypedefDeclaration (file);
        if !decl
            return null;

        Expect (file, .Semicolon);

        return decl;
    }
    else if MatchToken (*lexer, .Proc)
    {
        return ParseProcedureDeclaration (file);
    }
    else if MatchToken (*lexer, .Struct)
    {
        return ParseStructDeclaration (file);
    }
    else if MatchToken (*lexer, .Enum)
    {
        return ParseEnumDeclaration (file);
    }
    else if MatchToken (*lexer, .External)
    {
        return ParseExternalDeclaration (file);
    }
    else
    {
        SyntaxError (NextToken (*lexer), "Expected a declaration");

        // @Todo: maybe catch compound declarations where the 'var' keyword is missing?
        if NextTokenIs (*lexer, .Identifier) && NextToken (*lexer, 1).kind == .Colon
            Info (NextToken (*lexer), "This looks like a variable or constant declaration, but the 'var' or 'const' keyword is missing");
    }

    return null;
}

ParseExternalDeclaration :: (using file : *YalFile) -> *AstDeclaration #must
{
    external_tok := PrevToken (lexer);

    decl : *AstDeclaration;

    if MatchToken (*lexer, .Proc)
    {
        proc_tok := PrevToken (lexer);

        Expect (file, .Identifier);
        ident := PrevToken (lexer);

        signature := ParseProcedureSignature (file, proc_tok);
        if !signature
            return null;

        Expect (file, .Semicolon);

        decl = MakeAstDeclaration (external_tok, MakeAstIdentifier (ident), null, signature, .Procedure);
    }
    else
    {
        SyntaxError (NextToken (*lexer), "Expected a procedure signature");
    }

    if !decl
        return null;

    decl.range = TokenRangeJoin (external_tok, decl.range);
    decl.decl_flags |= .External;

    return decl;
}

ParseValueDeclaration :: (using file : *YalFile, kind : DeclarationKind) -> *AstDeclaration #must
{
    begin_tok : Token;

    if kind == .Variable || kind == .Constant
        begin_tok = PrevToken (lexer);

    Expect (file, .Identifier);

    if kind != .Variable && kind != .Constant
        begin_tok = PrevToken (lexer);

    first_ident := MakeAstIdentifier (PrevToken (lexer));

    multiple_decls := false;
    identifiers : [..]*AstIdentifier;

    while MatchToken (*lexer, .Comma)
    {
        if !multiple_decls
        {
            ArrayPush (*identifiers, first_ident);
            multiple_decls = true;
        }

        Expect (file, .Identifier);
        ident := MakeAstIdentifier (PrevToken (lexer));
        ArrayPush (*identifiers, ident);
    }

    Expect (file, .Colon);

    type_node : *AstNode;
    if !NextTokenIs (*lexer, .Equal)
    {
        type_node = ParseType (file);
        if !type_node
            return null;
    }

    expr : *AstNode;
    if MatchToken (*lexer, .Equal)
    {
        expr = ParseExpression (file);
        if !expr
            return null;
    }

    if multiple_decls
        return MakeAstDeclarationMultiple (begin_tok, identifiers, type_node, expr, kind);

    return MakeAstDeclaration (begin_tok, first_ident, type_node, expr, kind);
}

ParseFieldDeclaration :: (using file : *YalFile) -> *AstDeclaration #must
{
    if NextToken (*lexer, 1).kind != .Colon
    {
        begin_tok := NextToken (*lexer);

        type_node := ParseType (file);
        if !type_node
            return null;

        return MakeAstDeclaration (begin_tok, null, type_node, null, .Field);
    }

    return ParseValueDeclaration (file, .Field);
}

ParseFieldList :: (using file : *YalFile, results : *[..]*AstDeclaration) -> bool #must
{
    first := true;
    while !MatchToken (*lexer, .EOF, .Close_Paren)
    {
        defer first = false;

        if !first
        {
            if !MatchExpect (file, .Comma)
            {
                Recover (file, .Comma, .Close_Paren);
                continue;
            }

            if MatchToken (*lexer, .Close_Paren)
            {
                SyntaxError (PrevToken (lexer),
                    "Expected a field declaration after ',', but got ')' instead");

                // This is a minor error so we return true so as to not fuck up the state of the parser
                return true;
            }
        }

        decl := ParseFieldDeclaration (file);
        if !decl
        {
            Recover (file, .Comma, .Close_Paren);
            continue;
        }

        ArrayPush (results, decl);
    }

    if PrevToken (lexer).kind != .Close_Paren
    {
        ExpectedError (PrevToken (lexer, 1), PrevToken (lexer), .Close_Paren);

        return false;
    }

    return true;
}

ParseTypedefDeclaration :: (using file : *YalFile) -> *AstDeclaration #must
{
    typedef_tok := PrevToken (lexer);

    Expect (file, .Identifier);

    ident := PrevToken (lexer);

    Expect (file, .Equal);

    type_node := ParseType (file);
    if !type_node
        return null;

    return MakeAstDeclaration (typedef_tok, MakeAstIdentifier (ident), null, type_node, .Typedef);
}

ParseProcedureDeclaration :: (using file : *YalFile) -> *AstDeclaration #must
{
    proc_tok := PrevToken (lexer);

    Expect (file, .Identifier);
    ident := MakeAstIdentifier (PrevToken (lexer));

    signature := ParseProcedureSignature (file, proc_tok);
    if !signature || !NextTokenIs (*lexer, .Open_Curly)
    {
        ExpectedError (PrevToken (lexer), NextToken (*lexer), .Open_Curly);
        if NextTokenIs (*lexer, .Comma)
            Info (NextToken (*lexer), "Multiple return values have to be enclosed in parentheses");

        // Not recovering and returning null can really fuck up the
        // parsing state, so we do that and return a Bad_Declaration
        Recover (file, .Open_Curly);

        if !NextTokenIs (*lexer, .Open_Curly)
            return null;
    }

    body := ParseBlock (file);
    if !body
        return null;

    if !signature
        return MakeAstBadDeclaration (TokenRangeJoin (proc_tok, body));

    signature.body = body;
    signature.range = TokenRangeJoin (signature, body);

    return MakeAstDeclaration (proc_tok, ident, null, signature, .Procedure);
}

ParseStructDeclaration :: (using file : *YalFile) -> *AstDeclaration #must
{
    struct_tok := PrevToken (lexer);

    Expect (file, .Identifier);
    ident := PrevToken (lexer);

    struct_node := ParseStruct (file, struct_tok);
    if !struct_node
        return null;

    return MakeAstDeclaration (struct_tok, MakeAstIdentifier (ident), null, struct_node, .Struct);
}

ParseStruct :: (using file : *YalFile, struct_tok : Token) -> *AstStruct #must
{
    body := ParseBlock (file);
    if !body
        return null;

    return MakeAstStruct (struct_tok, body);
}

ParseEnumDeclaration :: (using file : *YalFile) -> *AstDeclaration #must
{
    enum_tok := PrevToken (lexer);

    Expect (file, .Identifier);
    ident := PrevToken (lexer);

    enum_node := ParseEnum (file, enum_tok);
    if !enum_node
        return null;

    return MakeAstDeclaration (enum_tok, MakeAstIdentifier (ident), null, enum_node, .Enum);
}

ParseEnum :: (using file : *YalFile, enum_tok : Token) -> *AstEnum #must
{
    base_type : *AstNode;
    if !NextTokenIs (*lexer, .Open_Curly)
    {
        base_type = ParseType (file);
        if !base_type
        {
            Recover (file, .Open_Curly);

            if !NextTokenIs (*lexer, .Open_Curly)
                return null;
        }
    }

    Expect (file, .Open_Curly);
    open_brace_tok := PrevToken (lexer);

    members : [..]*AstNode;

    while !MatchToken (*lexer, .EOF, .Close_Curly)
    {
        decl := ParseEnumMemberDeclaration (file);
        if !decl
        {
            Recover (file, .Close_Curly);
            continue;
        }

        ArrayPush (*members, decl);
    }

    if PrevToken (lexer).kind != .Close_Curly
    {
        ExpectedError (PrevToken (lexer, 1), PrevToken (lexer), .Close_Curly);
        return null;
    }

    body := MakeAstBlock (open_brace_tok, PrevToken (lexer), members);

    return MakeAstEnum (enum_tok, base_type, body);
}

ParseEnumMemberDeclaration :: (using file : *YalFile) -> *AstDeclaration #must
{
    Expect (file, .Identifier);

    ident := PrevToken (lexer);

    expr : *AstNode;
    if MatchToken (*lexer, .Equal)
    {
        expr = ParseExpression (file);
        if !expr
            return null;
    }

    Expect (file, .Semicolon);

    return MakeAstDeclaration (ident, MakeAstIdentifier (ident), null, expr, .Enum_Member);
}
