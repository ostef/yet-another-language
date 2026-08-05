#import "Lexer";

ParserContext :: struct {
    attributes : [..]*AstAttribute;
}

#add_context parser : ParserContext;

Recover :: (using file : *YalFile, stop_at : ..TokenKind) {
    if MatchToken(*lexer, .EOF, .Semicolon) {
        return;
    }

    if NextTokenIs(*lexer, ..stop_at) {
        return;
    }

    ConsumeToken(*lexer);

    while !MatchToken(*lexer, .EOF) {
        if MatchToken(*lexer, .Semicolon) {
            break;
        }

        if NextTokenIs(*lexer, ..Token_Statements) {
            break;
        }

        if NextTokenIs(*lexer, ..stop_at) {
            break;
        }

        ConsumeToken(*lexer);
    }
}

MatchExpect :: (using file : *YalFile, kinds : ..TokenKind) -> bool {
    match := MatchToken(*lexer, ..kinds);
    if match {
        return true;
    }

    ExpectedError(PrevToken(lexer), NextToken(*lexer), ..kinds);

    return false;
}

Expect :: (file : *YalFile, kinds : ..TokenKind) #expand {
    if !MatchExpect(file, ..kinds) {
        `return null;
    }
}

ParseFile :: (using file : *YalFile) {
    insert_index := ifx source_node && source_node.enclosing_scope == scope
        then ArrayFindFirst(scope.all_statements, source_node)
        else -1;

    while !MatchToken(*lexer, .EOF) {
        stmt := ParseStatement(file);
        if !stmt {
            Recover(file);
        } else {
            if add_statements_to_global_scope {
                if scope.enclosing_module {
                    AddStatement(scope.enclosing_module.scope, stmt);
                } else {
                    AddStatement(program.scope, stmt);
                }
            } else if insert_index >= 0 {
                AddStatement(scope, stmt, insert_index + 1 + statements.count);
            } else {
                AddStatement(scope, stmt);
            }

            ArrayPush(*statements, stmt);
        }
    }
}

ParseAttribute :: (using file : *YalFile) -> *AstAttribute {
    if !MatchToken(*lexer, .Attribute) {
        return null;
    }

    name := PrevToken(lexer);

    arguments : [..]*AstNode;
    if MatchToken(*lexer, .OpenParen) {
        first := true;
        while !MatchToken(*lexer, .EOF, .CloseParen) {
            defer first = false;

            if !first {
                if !MatchExpect(file, .Comma) {
                    return null;
                }

                if MatchToken(*lexer, .CloseParen) {
                    SyntaxError(PrevToken(lexer), "Expected expression after ',', but got ')' instead");

                    return null;
                }
            }

            arg := ParseExpression(file);
            if !arg {
                return null;
            }

            ArrayPush(*arguments, arg);
        }

        if PrevToken(lexer).kind != .CloseParen {
            ExpectedError(PrevToken(lexer, 1), PrevToken(lexer), .CloseParen);
            return null;
        }
    }

    return MakeAstAttribute(name, arguments, PrevToken(lexer));
}

ParseAttributes :: (using file : *YalFile) -> []*AstAttribute {
    attributes : [..]*AstAttribute;
    while NextTokenIs(*lexer, .Attribute) {
        attr := ParseAttribute(file);
        if !attr {
            Recover(file, .Attribute);
        } else {
            ArrayPush(*attributes, attr);
        }
    }

    return attributes;
}

ParseAssert :: (using file : *YalFile) -> *AstAssert {
    assert_tok := PrevToken(lexer);

    expr := ParseExpression(file);
    if !expr {
        return null;
    }

    message : *AstNode;
    if MatchToken(*lexer, .Comma) {
        message = ParseExpression(file);
        if !message {
            return null;
        }
    }

    if !MatchExpect(file, .Semicolon) {
        return null;
    }

    return MakeAstAssert(assert_tok, expr, message);
}

ParseInclude :: (using file : *YalFile) -> *AstInclude {
    include_tok := PrevToken(lexer);

    if !MatchExpect(file, .StringLiteral) {
        return null;
    }

    tok := PrevToken(lexer);
    include_filename, ok := ParseStringLiteral(tok);
    if !ok {
        return null;
    }

    if !MatchExpect(file, .Semicolon) {
        return null;
    }

    return MakeAstInclude(include_tok, tok, include_filename);
}

ParseRun :: (using file : *YalFile) -> *AstRun {
    run_tok := PrevToken(lexer);

    expr := ParseExpression(file);
    if !expr {
        return null;
    }

    return MakeAstRun(run_tok, expr);
}

ParseImport :: (using file : *YalFile) -> *AstImport {
    import_tok := PrevToken(lexer);

    expr := ParseExpression(file);
    if !expr {
        return null;
    }

    return MakeAstImport(import_tok, expr);
}

ParseInsert :: (using file : *YalFile) -> *AstInsert {
    insert_tok := PrevToken(lexer);

    expr := ParseExpression(file);
    if !expr {
        return null;
    }

    return MakeAstInsert(insert_tok, expr);
}

ParseStatement :: (using file : *YalFile) -> *AstNode {
    Parse :: (using file : *YalFile) -> *AstNode {
        program.parsing_stats.num_statements += 1;

        if MatchToken(*lexer, .DirectiveAssert) {
            return ParseAssert(file);
        } if MatchToken(*lexer, .DirectiveInclude) {
            return ParseInclude(file);
        } if MatchToken(*lexer, .DirectiveInsert) {
            return ParseInsert(file);
        } else if MatchToken(*lexer, .DebugBreak) {
            tok := PrevToken(lexer);
            Expect(file, .Semicolon);

            return MakeAstFlowControl(tok);
        } else if MatchToken(*lexer, .If, .DirectiveIf) {
            return ParseIf(file);
        } else if MatchToken(*lexer, .While) {
            return ParseWhile(file);
        } else if MatchToken(*lexer, .For) {
            return ParseFor(file);
        } else if MatchToken(*lexer, .Defer) {
            defer_tok := PrevToken(lexer);
            stmt := ParseStatement(file);
            if !stmt {
                return null;
            }

            return MakeAstDefer(defer_tok, stmt);
        } else if MatchToken(*lexer, .Return) {
            return ParseReturn(file);
        } else if MatchToken(*lexer, .Break, .Continue, .Fallthrough) {
            tok := PrevToken(lexer);
            Expect(file, .Semicolon);

            return MakeAstFlowControl(tok);
        } else {
            has_using := MatchToken(*lexer, .Using);
            using_tok : Token;
            if has_using {
                using_tok = PrevToken(lexer);
            }

            expr := ParseExpression(file);
            if !expr {
                return null;
            }

            if MatchToken(*lexer, ..Tokens_Assignment) {
                if has_using {
                    SyntaxError(using_tok, "Using can only be used on expressions and declarations");
                }

                op := PrevToken(lexer);

                right := ParseExpression(file);
                if !right {
                    return null;
                }

                if MatchToken(*lexer, ..Tokens_Assignment) {
                    SyntaxError(PrevToken(lexer), "Chaining of assignment statements");
                    return null;
                }

                expr = MakeAstAssignment(op, expr, right);
            } else {
                expr.flags |= .StatementLevelExpression;
            }

            if has_using {
                expr.range = TokenRangeJoin(using_tok, expr);
                expr.flags |= .Using;
            }

            if !MatchExpect(file, .Semicolon) {
                if NextTokenIs(*lexer, .Colon) {
                    Info(NextToken(*lexer), "This looks like a variable or constant declaration, but the 'var' or 'const' keyword is missing");
                }

                return null;
            }

            return expr;
        }

        return null;
    }

    // Consume trailing semicolons
    defer while MatchToken(*lexer, .Semicolon) {}

    attributes := ParseAttributes(file);

    peek := ifx NextTokenIs(*lexer, .Using) then 1 else 0;
    if NextTokenIs(*lexer, .Var, .Const, peek=peek) {
        return ParseDeclaration(file, attributes);
    } else if NextTokenIs(*lexer, .OpenCurly) {
        return ParseBlock(file, attributes);
    }

    stmt := Parse(file);
    if stmt {
        stmt.attributes = attributes;
        stmt.inherited_attributes = ArrayClone(context.parser.attributes);
    }

    return stmt;
}

ParseBlock :: (using,except(statements) file : *YalFile, attributes : []*AstAttribute = .[]) -> *AstBlock {
    inherited_attributes := ArrayClone(context.parser.attributes);

    for attributes {
        ArrayPush(*context.parser.attributes, it);
    }

    defer for attributes {
        ArrayPop(*context.parser.attributes);
    }

    Expect(file, .OpenCurly);
    open_brace_tok := PrevToken(lexer);

    statements : [..]*AstNode;

    while !MatchToken(*lexer, .EOF, .CloseCurly) {
        stmt := ParseStatement(file);
        if !stmt {
            Recover(file, .CloseCurly);
            continue;
        }

        ArrayPush(*statements, stmt);
    }

    if PrevToken(lexer).kind != .CloseCurly {
        ExpectedError(PrevToken(lexer, 1), PrevToken(lexer), .CloseCurly);

        return null;
    }

    block := MakeAstBlock(open_brace_tok, PrevToken(lexer), statements);
    block.attributes = attributes;
    block.inherited_attributes = inherited_attributes;

    return block;
}

ParseIf :: (using file : *YalFile) -> *AstIf {
    if_tok := PrevToken(lexer);
    is_compile_time := if_tok.kind == .DirectiveIf;

    condition := ParseExpression(file);
    if !condition {
        return null;
    }

    body := ParseStatement(file);
    if !body {
        return null;
    }

    else_stmt : *AstNode;
    if MatchToken(*lexer, .Else) {
        else_stmt = ParseStatement(file);
        if !else_stmt {
            return null;
        }
    }

    if_stmt := MakeAstIf(if_tok, condition, body, else_stmt, is_compile_time);
    if body.kind == .Block {
        cast(*AstBlock, body).parent_statement = if_stmt;
    }
    if else_stmt && else_stmt.kind == .Block {
        cast(*AstBlock, else_stmt).parent_statement = if_stmt;
    }

    return if_stmt;
}

ParseWhile :: (using file : *YalFile) -> *AstWhile {
    while_tok := PrevToken(lexer);

    condition := ParseExpression(file);
    if !condition {
        return null;
    }

    body := ParseStatement(file);
    if !body {
        return null;
    }

    while_stmt := MakeAstWhile(while_tok, condition, body);
    if body.kind == .Block {
        cast(*AstBlock, body).parent_statement = while_stmt;
    }

    return while_stmt;
}

ParseFor :: (using file : *YalFile) -> *AstFor {
    for_tok := PrevToken(lexer);

    Expect(file, .Identifier);
    begin_tok := PrevToken(lexer);

    ident := MakeAstIdentifier(PrevToken(lexer));

    Expect(file, .Equal, .Colon);
    colon_or_equal := PrevToken(lexer);
    is_declaration := colon_or_equal.kind == .Colon;

    expr := ParseExpression(file);
    if !expr {
        return null;
    }

    if MatchToken(*lexer, .DotDotEqu, .DotDotLess, .GreaterDotDot, .EquDotDot) {
        prev := PrevToken(lexer);
        inclusive := prev.kind == .DotDotEqu || prev.kind == .EquDotDot;
        reverse := prev.kind == .GreaterDotDot || prev.kind == .EquDotDot;

        rhs := ParseExpression(file);
        if !rhs {
            return null;
        }

        if reverse {
            expr = MakeAstRange(rhs, expr, inclusive, true);
        } else {
            expr = MakeAstRange(expr, rhs, inclusive, false);
        }
    }

    iterator : *AstNode;
    if is_declaration {
        iterator = MakeAstDeclaration(begin_tok, ident, null, expr, .ForLoopIndex);
    } else {
        iterator = MakeAstAssignment(colon_or_equal, ident, expr);
    }

    body := ParseStatement(file);
    if !body {
        return null;
    }

    for_stmt := MakeAstFor(for_tok, iterator, body);
    if body.kind == .Block {
        cast(*AstBlock, body).parent_statement = for_stmt;
    }

    return for_stmt;
}

ParseReturn :: (using file : *YalFile) -> *AstReturn {
    return_tok := PrevToken(lexer);

    expr : *AstNode;
    if !NextTokenIs(*lexer, .EOF, .Semicolon) {
        expr = ParseExpression(file);
        if !expr {
            return null;
        }
    }

    if !MatchToken(*lexer, .Semicolon) {
        ExpectedError(PrevToken(lexer, 1), PrevToken(lexer), .Semicolon);
        return null;
    }

    return MakeAstReturn(return_tok, expr);
}

OperatorInfo :: struct {
    Flags :: enum_flags u8 {
        NonAssociative;
        RightAssociative;
        Prefix;
        Postfix;
    }

    tok : TokenKind;
    precedence : int;
    flags : Flags;
}

// Must be sorted by order of precedence
Operators :: OperatorInfo.[
    .{ .PipePipe, 2, 0 }, // logical or

    .{ .AmpersandAmpersand, 3, 0 },  // logical and

    .{ .EquEqu,     4, .NonAssociative },
    .{ .BangEqu,    4, .NonAssociative },
    .{ .Less,       4, .NonAssociative },
    .{ .Greater,    4, .NonAssociative },
    .{ .LessEqu,    4, .NonAssociative },
    .{ .GreaterEqu, 4, .NonAssociative },

    .{ .LessLess,       5, 0 }, // bit shift left
    .{ .GreaterGreater, 5, 0 }, // bit shift right

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

    .{ .Cast,    12, .Prefix },
    .{ .Bitcast, 12, .Prefix },
    .{ .Auto,    12, .Prefix },
    .{ .SizeOf,  12, .Prefix },
    .{ .TypeOf,  12, .Prefix },

    .{ .Dot,          13, 0 }, // field access
    .{ .DirectiveRun, 13, .Prefix }, // #run
    .{ .DirectiveImport, 13, .Prefix }, // #import
    .{ .DirectiveImportFile, 13, .Prefix }, // #import_file
    .{ .Dot,          13, .Prefix }, // context aware field access (for enums)
    .{ .Star,         13, .Prefix }, // pointer type
    .{ .OpenBracket,  13, .Prefix }, // array type
    .{ .OpenBracket,  13, .Postfix }, // subscript
    .{ .OpenParen,    13, .Postfix }, // function call
    .{ .DotOpenCurly, 13, .Prefix }, // inferred struct literal
    .{ .DotOpenCurly, 13, .Postfix }, // struct literal
    .{ .DotStar,      13, .Postfix }, // dereference
];

// Check that our Operators array is ordered
#run {
    for i : 0..Operators.count - 2 {
        a := Operators[i];
        b := Operators[i + 1];
        if a.precedence > b.precedence {
            message := SPrint("Operators should be sorted by order of precedence");

            JaiC.compiler_report(message, #location(Token_Symbols));
        }
    }
}

BinaryOperatorInfo :: inline (tok : TokenKind) -> OperatorInfo {
    for Operators {
        if it.tok == tok && !(it.flags & .Prefix) && !(it.flags & .Postfix) {
            return it;
        }
    }

    return .{};
}

BinaryOrPostfixOperatorInfo :: inline (tok : TokenKind) -> OperatorInfo {
    for Operators {
        if it.tok == tok && !(it.flags & .Prefix) {
            return it;
        }
    }

    return .{};
}

UnaryOperatorInfo :: inline (tok : TokenKind) -> OperatorInfo {
    for Operators {
        if it.tok == tok && ((it.flags & .Prefix) || (it.flags & .Postfix)) {
            return it;
        }
    }

    return .{};
}

PrefixOperatorInfo :: inline (tok : TokenKind) -> OperatorInfo {
    for Operators {
        if it.tok == tok && (it.flags & .Prefix) {
            return it;
        }
    }

    return .{};
}

PostfixOperatorInfo :: inline (tok : TokenKind) -> OperatorInfo {
    for Operators {
        if it.tok == tok && (it.flags & .Postfix) {
            return it;
        }
    }

    return .{};
}

ParseExpression :: (using file : *YalFile, prec := 0) -> *AstNode {
    program.parsing_stats.num_expressions += 1;

    expr := ParsePrimaryExpression(file);
    if !expr {
        return null;
    }

    tok := NextToken(*lexer);
    op := BinaryOrPostfixOperatorInfo(tok.kind);

    last_non_associative_tok : Token;
    last_non_associative_op : OperatorInfo;
    last_non_associative_op.precedence = Math.S64_MIN;

    max_prec := Math.S64_MAX;
    while op.tok != .Invalid && prec <= op.precedence && op.precedence <= max_prec {
        ConsumeToken(*lexer);

        Assert(tok, expr != null, "When parsing expression, expr is null");

        if !(op.flags & .Postfix) {
            right_prec := ifx op.flags & .RightAssociative
                then op.precedence
                else op.precedence + 1;

            right := ParseExpression(file, right_prec);
            if !right {
                return null;
            }

            if op.tok == .Dot {
                expr = MakeAstFieldAccess(expr, right);
            } else {
                expr = MakeAstBinary(tok, expr, right);
            }
        } else if op.tok == .OpenBracket {   // Subscript
            index_expr := ParseExpression(file);
            if !index_expr {
                return null;
            }

            Expect(file, .CloseBracket);

            expr = MakeAstSubscript(expr, index_expr, PrevToken(lexer));
        } else if op.tok == .OpenParen {   // Function call
            expr = ParseFunctionCall(file, expr);
            if !expr {
                return null;
            }
        } else if op.tok == .DotOpenCurly { // Struct literal
            expr = ParseStructLiteral(file, expr);
            if !expr {
                return null;
            }
        } else {
            expr = MakeAstUnary(tok, expr);
        }

        if op.flags & .NonAssociative {
            last_non_associative_tok = tok;
            last_non_associative_op = op;
        }

        if (op.flags & .RightAssociative) || (op.flags & .NonAssociative) {
            max_prec = op.precedence - 1;
        } else {
            max_prec = op.precedence;
        }

        tok = NextToken(*lexer);
        op = BinaryOrPostfixOperatorInfo(tok.kind);
    }

    // Handle associativity errors
    if op.tok != .Invalid && op.precedence == last_non_associative_op.precedence {
        next := NextToken(*lexer);
        if next.kind == last_non_associative_op.tok {
            SyntaxError(next,
                "Chaining of non associative operator %", Token_Names[next.kind]);
        } else {
            SyntaxError(next,
                "Chaining of non associative operator % with operator % of same precedence",
                    Token_Names[last_non_associative_tok.kind], Token_Names[next.kind]);
        }

        InfoWithoutSourceCode(next, "You might want to use parentheses to fix this");
        Info(last_non_associative_tok, "Here is the first occurence of the non associative operator");
    }

    return expr;
}

ParsePrimaryExpression :: (using file : *YalFile) -> *AstNode {
    tok := NextToken(*lexer);
    op := PrefixOperatorInfo(tok.kind);

    if op.tok != .Invalid {
        ConsumeToken(*lexer);

        if tok.kind == {
        case .DirectiveRun;
            return ParseRun(file);

        case .DirectiveImport; #through;
        case .DirectiveImportFile;
            return ParseImport(file);

        case .Dot;
            Expect(file, .Identifier);

            expr := MakeAstIdentifier(PrevToken(lexer));

            return MakeAstFieldAccess(tok, expr);

        case .Auto;
            expr := ParseExpression(file);
            if !expr {
                return null;
            }

            return MakeAstAutoCast(tok, expr);

        case .Cast; #through;
        case .Bitcast;
            Expect(file, .OpenParen);

            type_node := ParseExpression(file);
            if !type_node {
                return null;
            }

            Expect(file, .Comma);

            expr := ParseExpression(file);
            if !expr {
                return null;
            }

            Expect(file, .CloseParen);

            return MakeAstCast(tok, type_node, expr, PrevToken(lexer));

        case .SizeOf;
            Expect(file, .OpenParen);

            type_node := ParseExpression(file);
            if !type_node {
                return null;
            }

            Expect(file, .CloseParen);

            return MakeAstSizeOf(tok, PrevToken(lexer), type_node);

        case .TypeOf;
            Expect(file, .OpenParen);

            expr := ParseExpression(file);
            if !expr {
                return null;
            }

            Expect(file, .CloseParen);

            return MakeAstTypeOf(tok, PrevToken(lexer), expr);

        case .OpenBracket;
            is_dynamic := false;
            element_count : *AstNode;

            if MatchToken(*lexer, .DotDot) {
                is_dynamic = true;
            } else if !NextTokenIs(*lexer, .CloseBracket) {
                element_count = ParseExpression(file);
                if !element_count {
                    return null;
                }
            }

            Expect(file, .CloseBracket);

            element_type := ParseExpression(file);
            if !element_type {
                return null;
            }

            return MakeAstTypeArray(tok, element_type, element_count, is_dynamic);

        case .Star;
            pointed_type := ParseExpression(file);
            if !pointed_type {
                return null;
            }

            return MakeAstTypePointer(tok, pointed_type);

        case .DotOpenCurly;
            return ParseStructLiteral(file, null);
        }

        expr := ParseExpression(file, op.precedence);
        if !expr {
            return null;
        }

        return MakeAstUnary(tok, expr);
    }

    if MatchToken(*lexer, .OpenParen) {
        open_paren_tok := PrevToken(lexer);

        expr := ParseExpression(file);
        if !expr {
            return null;
        }

        if NextTokenIs(*lexer, ..Tokens_Assignment) {
            SyntaxError(NextToken(*lexer), "Assignment in parenthesized expression");

            return null;
        }

        Expect(file, .CloseParen);

        expr.flags |= .Parenthesized;
        expr.range = TokenRangeJoin(open_paren_tok, PrevToken(lexer));

        return expr;
    }

    if MatchToken(*lexer, .Func) {
        if NextTokenIs(*lexer, .OpenCurly) {
            return ParseFunctionOverloadSet(file);
        } else {
            return ParseFunction(file);
        }
    }

    if MatchToken(*lexer, .Struct, .Union) {
        return ParseStruct(file);
    }

    if MatchToken(*lexer, .Enum) {
        return ParseEnum(file);
    }

    if MatchToken(*lexer, .Void, .Int, .Uint, .U8, .S8, .U16, .S16, .U32, .S32, .U64, .S64, .Float, .F32, .F64, .Bool, .String, .TypeId) {
        return MakeAstTypePrimitive(PrevToken(lexer));
    }

    if MatchToken(*lexer, .Dollar) {
        dollar_tok := tok;
        Expect(file, .Identifier);
        ident_tok := PrevToken(lexer);

        ident := MakeAstIdentifierTemplateParam(dollar_tok, ident_tok);
        if !ident {
            return null;
        }

        ident.ident_flags |= .ImplicitDeclaration;

        return ident;
    }

    if MatchToken(*lexer, .Identifier) {
        return MakeAstIdentifier(tok);
    }

    if MatchToken(*lexer, .Context) {
        return MakeAstContext(tok);
    }

    if MatchToken(*lexer, .IntLiteral, .FloatLiteral, .StringLiteral, .CharLiteral, .HereString, .True, .False, .Null) {
        return MakeAstLiteral(tok);
    }

    SyntaxError(tok, "Expected an expression, but got % instead", Token_Names[tok.kind]);

    return null;
}

ParseFunctionCall :: (using file : *YalFile, callee : *AstNode) -> *AstFunctionCall {
    open_paren_tok := PrevToken(lexer);

    arguments : [..]*AstArgument;
    first := true;
    while !MatchToken(*lexer, .EOF, .CloseParen) {
        defer first = false;

        if !first {
            if !MatchExpect(file, .Comma) {
                return null;
            }

            if MatchToken(*lexer, .CloseParen) {
                SyntaxError(PrevToken(lexer), "Expected expression after ',', but got ')' instead");

                return null;
            }
        }

        arg : *AstArgument;

        arg_or_name := ParseExpression(file);
        if !arg_or_name {
            return null;
        }

        if MatchToken(*lexer, .Equal) {
            if arg_or_name.kind != .Identifier {
                SyntaxError(arg_or_name, "Expected an identifier before '=' for argument");
                return null;
            }

            cast(*AstIdentifier, arg_or_name).ident_flags |= .DoNotResolve;

            expr := ParseExpression(file);
            if !expr {
                return null;
            }

            arg = MakeAstArgument(xx arg_or_name, expr);
        } else {
            arg = MakeAstArgument(null, arg_or_name);
        }

        ArrayPush(*arguments, arg);
    }

    if PrevToken(lexer).kind != .CloseParen {
        ExpectedError(PrevToken(lexer, 1), PrevToken(lexer), .CloseParen);
        return null;
    }

    return MakeAstFunctionCall(callee, arguments, PrevToken(lexer));
}

ParseStructLiteral :: (using file : *YalFile, type_node : *AstNode) -> *AstStructLiteral {
    open_tok := PrevToken(lexer);

    values : [..]*AstNode;
    first := true;
    while !MatchToken(*lexer, .EOF, .CloseCurly) {
        defer first = false;

        if !first {
            if !MatchExpect(file, .Comma) {
                return null;
            }

            if MatchToken(*lexer, .CloseCurly) {
                break;
            }
        }

        arg := ParseExpression(file);
        if !arg {
            return null;
        }

        ArrayPush(*values, arg);
    }

    if PrevToken(lexer).kind != .CloseCurly {
        ExpectedError(PrevToken(lexer, 1), PrevToken(lexer), .CloseCurly);
        return null;
    }

    return MakeAstStructLiteral(type_node, open_tok, values, PrevToken(lexer));
}

ParseFunction :: (using file : *YalFile) -> *AstFunction {
    func_tok := PrevToken(lexer);

    attributes := ParseAttributes(file);

    parameters : [..]*AstDeclaration;

    Expect(file, .OpenParen);
    params_ok, is_c_variadic := ParseParameterList(file, *parameters);
    if !params_ok {
        return null;
    }

    close_paren := PrevToken(lexer);

    result : *AstDeclaration;

    if MatchToken(*lexer, .Arrow) {
        result = ParseFieldDeclaration(file);
        if !result {
            return null;
        }
    }

    func := MakeAstFunction(func_tok, close_paren, parameters, result, is_c_variadic);
    func.attributes = attributes;
    func.inherited_attributes = ArrayClone(context.parser.attributes);

    if NextTokenIs(*lexer, .OpenCurly) {
        func.body = ParseBlock(file);
        if !func.body {
            return null;
        }

        func.body.parent_func = func;
        func.range = TokenRangeJoin(func, func.body);
    }

    return func;
}

ParseFunctionOverloadSet :: (using file : *YalFile) -> *AstFunctionOverloadSet {
    func_tok := PrevToken(lexer);

    body := ParseBlock(file);

    set := MakeAstFunctionOverloadSet(func_tok, body);
    set.inherited_attributes = ArrayClone(context.parser.attributes);
    body.parent_func_overload_set = set;

    return set;
}

ParseDeclaration :: (using file : *YalFile, attributes : []*AstAttribute) -> *AstDeclaration {
    program.parsing_stats.num_declarations += 1;

    has_using := MatchToken(*lexer, .Using);
    using_tok : Token;
    if has_using {
        using_tok = PrevToken(lexer);
    }

    if MatchToken(*lexer, .Var, .Const) {
        tok := PrevToken(lexer);
        decl_kind : DeclarationKind = ifx tok.kind == .Var then .Variable else .Constant;
        decl := ParseValueDeclaration(file, decl_kind, attributes);
        if !decl {
            return null;
        }

        if has_using {
            decl.range = TokenRangeJoin(using_tok, decl);
            decl.flags |= .Using;
        }

        if !decl.expr {
            Expect(file, .Semicolon);
        } else if decl.expr.kind == {
        case .Struct; #through;
        case .FunctionOverloadSet; #through;
        case .Enum;
            // No semicolon expected!

        case .Function;
            // Semicolon expected if the function has no body
            func := cast(*AstFunction, decl.expr);
            if !func.body {
                Expect(file, .Semicolon);
            }

        case;
            Expect(file, .Semicolon);
        }

        return decl;
    } else {
        SyntaxError(NextToken(*lexer), "Expected a declaration");

        if NextTokenIs(*lexer, .Identifier) && NextToken(*lexer, 1).kind == .Colon {
            Info(NextToken(*lexer), "This looks like a variable or constant declaration, but the 'var' or 'const' keyword is missing");
        }
    }

    return null;
}

ParseValueDeclaration :: (using file : *YalFile, kind : DeclarationKind, decl_attributes : []*AstAttribute = .[]) -> *AstDeclaration {
    begin_tok : Token;

    has_using : bool;
    if kind == .Variable {
        program.parsing_stats.num_variable_declarations += 1;
        begin_tok = PrevToken(lexer);
    } else if kind == .Constant {
        program.parsing_stats.num_constant_declarations += 1;
        begin_tok = PrevToken(lexer);
    } else {
        has_using = MatchToken(*lexer, .Using);
    }

    is_explicitly_a_template_param : bool;
    dollar_tok : Token;
    if (kind == .Field || kind == .TemplateParam) && MatchToken(*lexer, .Dollar) {
        dollar_tok = PrevToken(lexer);
        is_explicitly_a_template_param = true;
        kind = .TemplateParam;
    }

    Expect(file, .Identifier);

    if kind != .Variable && kind != .Constant {
        begin_tok = PrevToken(lexer);
    }

    identifier : *AstIdentifier;
    if is_explicitly_a_template_param {
        identifier = MakeAstIdentifierTemplateParam(dollar_tok, PrevToken(lexer));
    } else {
        identifier = MakeAstIdentifier(PrevToken(lexer));

        if kind == .TemplateParam {
            // I don't like setting this because I intended that flag specifically on the
            // identifier to mean that is has a dollar sign, but it's safer to set it even
            // when it's implicitly a template param
            identifier.ident_flags |= .TemplateParam;
        }
    }

    type_node, expr : *AstNode;
    {
        // Pass attributes down to the subexpressions
        ArrayPushMultiple(*context.parser.attributes, decl_attributes);

        defer for i : 0..decl_attributes.count - 1 {
            ArrayPop(*context.parser.attributes);
        }

        if MatchToken(*lexer, .Colon) {
            type_node = ParseExpression(file);
            if !type_node {
                return null;
            }
        }

        if MatchToken(*lexer, .Equal) {
            expr = ParseExpression(file);
            if !expr {
                return null;
            }
        } else if !type_node {
            ExpectedError(PrevToken(lexer), NextToken(*lexer), .Colon, .Equal);
        }
    }

    decl := MakeAstDeclaration(begin_tok, identifier, type_node, expr, kind);
    decl.attributes = decl_attributes;
    decl.inherited_attributes = ArrayClone(context.parser.attributes);

    if kind == .Constant && expr {
        if expr.kind == {
        case .Function;
            cast(*AstFunction, expr).decl = decl;
        case .FunctionOverloadSet;
            cast(*AstFunctionOverloadSet, expr).decl = decl;
        case .Struct;
            cast(*AstStruct, expr).decl = decl;
        case .Enum;
            cast(*AstEnum, expr).decl = decl;
        }
    }

    if has_using {
        decl.flags |= .Using;
    }

    return decl;
}

ParseFieldDeclaration :: (using file : *YalFile) -> *AstDeclaration {
    program.parsing_stats.num_declarations += 1;

    peek_offset := ifx NextTokenIs(*lexer, .Dollar) then 2 else 1;
    if NextToken(*lexer, peek_offset).kind != .Colon && NextToken(*lexer, peek_offset).kind != .Equal {
        begin_tok := NextToken(*lexer);

        type_node := ParseExpression(file);
        if !type_node {
            return null;
        }

        return MakeAstDeclaration(begin_tok, null, type_node, null, .Field);
    }

    return ParseValueDeclaration(file, .Field);
}

ParseParameterList :: (using file : *YalFile, results : *[..]*AstDeclaration) -> bool, is_c_variadic: bool {
    first := true;
    is_c_variadic := false;
    while !MatchToken(*lexer, .EOF, .CloseParen) {
        defer first = false;

        if !first {
            if !MatchExpect(file, .Comma) {
                Recover(file, .Comma, .CloseParen);
                continue;
            }

            if MatchToken(*lexer, .CloseParen) {
                SyntaxError(PrevToken(lexer), "Expected a field declaration after ',', but got ')' instead");

                // This is a minor error so we return true so as to not fuck up the state of the parser
                return true, is_c_variadic;
            }
        }

        if MatchToken(*lexer, .DotDotDot) {
            is_c_variadic = true;
            continue;
        }

        decl := ParseFieldDeclaration(file);
        if !decl {
            Recover(file, .Comma, .CloseParen);
            continue;
        }

        ArrayPush(results, decl);
    }

    if PrevToken(lexer).kind != .CloseParen {
        ExpectedError(PrevToken(lexer, 1), PrevToken(lexer), .CloseParen);

        return false, is_c_variadic;
    }

    return true, is_c_variadic;
}

ParseStruct :: (using file : *YalFile) -> *AstStruct {
    struct_tok := PrevToken(lexer);

    parameters : [..]*AstDeclaration;
    if MatchToken(*lexer, .OpenParen) {
        first := true;
        while !MatchToken(*lexer, .EOF, .CloseParen) {
            defer first = false;

            if !first {
                if !MatchExpect(file, .Comma) {
                    Recover(file, .Comma, .CloseParen);
                    continue;
                }

                if MatchToken(*lexer, .CloseParen) {
                    SyntaxError(PrevToken(lexer), "Expected a field declaration after ',', but got ')' instead");

                    // This is a minor error so we don't fail
                    break;
                }
            }

            decl := ParseValueDeclaration(file, .TemplateParam);
            if !decl {
                Recover(file, .Comma, .CloseParen);
                continue;
            }

            ArrayPush(*parameters, decl);
        }

        if PrevToken(lexer).kind != .CloseParen {
            ExpectedError(PrevToken(lexer, 1), PrevToken(lexer), .CloseParen);

            return null;
        }
    }

    body := ParseBlock(file);
    if !body {
        return null;
    }

    struct_node := MakeAstStruct(struct_tok, parameters,  body, struct_tok.kind == .Union);
    body.parent_struct = struct_node;

    return struct_node;
}

ParseEnum :: (using file : *YalFile) -> *AstEnum {
    enum_tok := PrevToken(lexer);

    base_type : *AstNode;
    if !NextTokenIs(*lexer, .OpenCurly) {
        base_type = ParseExpression(file);
        if !base_type {
            Recover(file, .OpenCurly);

            if !NextTokenIs(*lexer, .OpenCurly) {
                return null;
            }
        }
    }

    Expect(file, .OpenCurly);
    open_brace_tok := PrevToken(lexer);

    members : [..]*AstNode;

    while !MatchToken(*lexer, .EOF, .CloseCurly) {
        decl := ParseEnumMemberDeclaration(file);
        if !decl {
            Recover(file, .CloseCurly);
            continue;
        }

        ArrayPush(*members, decl);
    }

    if PrevToken(lexer).kind != .CloseCurly {
        ExpectedError(PrevToken(lexer, 1), PrevToken(lexer), .CloseCurly);
        return null;
    }

    body := MakeAstBlock(open_brace_tok, PrevToken(lexer), members);
    enum_node := MakeAstEnum(enum_tok, base_type, body);
    body.parent_enum = enum_node;

    return enum_node;
}

ParseEnumMemberDeclaration :: (using file : *YalFile) -> *AstDeclaration {
    Expect(file, .Identifier);

    ident := PrevToken(lexer);

    expr : *AstNode;
    if MatchToken(*lexer, .Equal) {
        expr = ParseExpression(file);
        if !expr {
            return null;
        }
    }

    Expect(file, .Semicolon);

    return MakeAstDeclaration(ident, MakeAstIdentifier(ident), null, expr, .EnumMember);
}
