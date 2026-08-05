Token_Keywords :: string.[
    "var", "const", "func", "struct", "union", "enum",
    "import", "if", "else", "for", "while",
    "continue", "break", "switch", "case", "fallthrough",
    "defer", "using", "cast", "bitcast", "auto", "size_of", "type_of",
    "return", "debug_break",
    "context",
    "true", "false", "null", "void", "bool", "string", "int", "uint",
    "s8", "u8", "s16", "u16", "s32", "u32", "s64", "u64", "type_id",
    "float", "f32", "f64",
    "#import", "#import_file", "#include", "#if", "#assert", "#run", "#insert",
];

// Symbol tokens should be declared in the order of longest to shortest,
// since longest tokens have priority over shortest tokens when lexing
// i.e. you want "==" to be declared before "=" so that we try scanning
// "==" before "=", and we don't invalidly get two "=" instead of a "=="

Token_Symbols :: string.[
    "LessLessEqu", "<<=",
    "GreaterGreaterEqu", ">>=",
    "DotDotDot", "...",
    "DotDotLess", "..<",
    "DotDotEqu", "..=",
    "GreaterDotDot", ">..",
    "EquDotDot", "=..",
    "DotStar", ".*",
    "Arrow", "->",
    "DotDot", "..",
    "EquEqu", "==",
    "BangEqu", "!=",
    "LessEqu", "<=",
    "GreaterEqu", ">=",
    "PlusEqu", "+=",
    "MinusEqu", "-=",
    "StarEqu", "*=",
    "SlashEqu", "/=",
    "PercentEqu", "%=",
    "AmpersandEqu", "&=",
    "PipeEqu", "|=",
    "Tilde_Equ", "~=",
    "CaretEqu", "^=",
    "LessLess", "<<",
    "GreaterGreater", ">>",
    "AmpersandAmpersand", "&&",
    "PipePipe", "||",
    "DotOpenCurly", ".{",
    "DotOpenBracket", ".[",
    "Equal", "=",
    "Bang", "!",
    "Less", "<",
    "Greater", ">",
    "Plus", "+",
    "Minus", "-",
    "Star", "*",
    "Slash", "/",
    "Percent", "%",
    "Ampersand", "&",
    "Pipe", "|",
    "Caret", "^",
    "Tilde", "~",
    "OpenParen", "(",
    "CloseParen", ")",
    "OpenBracket", "[",
    "CloseBracket", "]",
    "OpenCurly", "{",
    "CloseCurly", "}",
    "Colon", ":",
    "Semicolon", ";",
    "Dot", ".",
    "Comma", ",",
    "Dollar", "$",
];

// Check that our Token_Symbols array is ordered
#run {
    for i : 1..(Token_Symbols.count / 2) - 1 {
        a := Token_Symbols[i * 2 + 1];
        b := Token_Symbols[i * 2 - 1];
        if a.count > b.count {
            message := SPrint("Token_Symbols should be sorted by longest to shortest (symbol % is after % even though it is longer)", a, b);

            JaiC.compiler_report(message, #location(Token_Symbols));
        }
    }
}

#placeholder TokenKind;

#insert -> string {
    builder : StringBuilder;

    Appendln(*builder, "TokenKind :: enum u8 {");
    Appendln(*builder, "    Invalid;");
    Appendln(*builder, "    Comment;");
    Appendln(*builder, "    SymbolsBegin;");

    for i : 0..(Token_Symbols.count / 2) - 1 {
        Appendln(*builder, "    %;", Token_Symbols[i * 2]);
    }

    Appendln(*builder, "    SymbolsEnd;");
    Appendln(*builder, "    KeywordsBegin;");

    for kw : Token_Keywords {
        Append(*builder, "    ");

        capitalize := true;
        for i : 0..kw.count - 1 {
            if kw[i] == #char "#" {
                Append(*builder, "Directive");
                continue;
            }

            if !Basic.is_alnum(kw[i]) {
                continue;
            }

            if kw[i] == #char "_" {
                capitalize = true;
            } else {
                if capitalize {
                    StringBuilderAppendByte(*builder, Basic.to_upper(kw[i]));
                } else {
                    StringBuilderAppendByte(*builder, kw[i]);
                }

                capitalize = false;
            }
        }

        Append(*builder, ";\n");
    }

    Appendln(*builder, "    KeywordsEnd;");
    Appendln(*builder, "    Identifier;");
    Appendln(*builder, "    Attribute;");
    Appendln(*builder, "    IntLiteral;");
    Appendln(*builder, "    FloatLiteral;");
    Appendln(*builder, "    StringLiteral;");
    Appendln(*builder, "    HereString;");
    Appendln(*builder, "    CharLiteral;");
    Appendln(*builder, "    EOF;");
    Appendln(*builder, "    Count;");
    Appendln(*builder, "}");

    return StringBuilderBuild(*builder);
}

Token_Lexemes :: #insert -> string {
    builder : StringBuilder;

    Appendln(*builder, "string.[");

    for i : 0..TokenKind.Count - 1 {
        if i != 0 {
            Appendln(*builder, ",\n");
        }

        if i > TokenKind.SymbolsBegin && i < TokenKind.SymbolsEnd {
            index := (cast(int) i - cast(int) TokenKind.SymbolsBegin - 1) * 2 + 1;
            Append(*builder, "\"%\"", Token_Symbols[index]);
        } else if i > TokenKind.KeywordsBegin && i < TokenKind.KeywordsEnd {
            index := cast(int) i - cast(int) TokenKind.KeywordsBegin - 1;
            Append(*builder, "\"%\"", Token_Keywords[index]);
        } else {
            Append(*builder, "\"\"");
        }
    }

    Appendln(*builder, "\n];");

    return StringBuilderBuild(*builder);
}

Token_Names :: #insert -> string {
    builder : StringBuilder;

    Appendln(*builder, "string.[");

    for i : 0..TokenKind.Count - 1 {
        if i != 0 {
            Append(*builder, ",\n");
        }

        if i == .EOF {
            Append(*builder, "\"end of file\"");
        } else if Token_Lexemes[i] {
            Append(*builder, "\"'%'\"", Token_Lexemes[i]);
        } else {
            Append(*builder, "\"");

            name_index := -1;
            for ii : 0..type_info (TokenKind).values.count {
                if cast(int) i == type_info (TokenKind).values[ii] {
                    name_index = ii;
                    break;
                }
            }

            Assert(name_index > -1);

            name := type_info (TokenKind).names[name_index];
            for ii : 0..name.count - 1 {
                if name[ii] == #char "_" {
                    StringBuilderAppendByte(*builder, #char " ");
                } else {
                    is_upper :: (byte : u8) -> bool {
                        if byte >= #char "A" && byte <= #char "Z" {
                            return true;
                        }

                        return false;
                    }

                    StringBuilderAppendByte(*builder, Basic.to_lower(name[ii]));

                    if ii != name.count - 1 && !is_upper(name[ii]) && is_upper(name[ii + 1]) {
                        StringBuilderAppendByte(*builder, #char " ");
                    }
                }
            }

            Append(*builder, "\"");
        }
    }

    Appendln(*builder, "\n];");

    return StringBuilderBuild(*builder);
}

Tokens_Assignment :: TokenKind.[
    .Equal,
    .PlusEqu,
    .MinusEqu,
    .StarEqu,
    .SlashEqu,
    .PercentEqu,
    .AmpersandEqu,
    .PipeEqu,
    .CaretEqu,
    .LessLessEqu,
    .GreaterGreaterEqu,
];

GetBinaryOperatorOfAssignment :: inline (token : TokenKind) -> TokenKind {
    if token == {
    case .PlusEqu;
        return .Plus;
    case .MinusEqu;
        return .Minus;
    case .StarEqu;
        return .Star;
    case .SlashEqu;
        return .Slash;
    case .PercentEqu;
        return .Percent;
    case .AmpersandEqu;
        return .Ampersand;
    case .PipeEqu;
        return .Pipe;
    case .CaretEqu;
        return .Caret;
    case .LessLessEqu;
        return .LessLess;
    case .GreaterGreaterEqu;
        return .GreaterGreater;
    }
    return .Invalid;
}

Token_Statements :: TokenKind.[
    .Var, .Const,
    .If, .Else, .For, .While, .Continue, .Break, .Switch,
    .Case, .Fallthrough, .Defer, .Using,
];

TokenLocation :: struct {
    byte_offset : s64;
    line : s32;
    char : s32;
    file_id : FileId;
}

TokenRange :: struct {
    byte_offset : s64;
    line_start, line_end : s32;
    char_start, char_end : s32;
    file_id : FileId = -1;
}

Token :: struct {
    #as using range : TokenRange;
    #as kind : TokenKind;
}

SetStart :: inline (using tok : *Token, lexer : *YalLexer) {
    file_id = lexer.file_id;
    line_start = xx lexer.line;
    char_start = xx lexer.column;
    byte_offset = lexer.byte_index;
}

SetEnd :: inline (using tok : *Token, lexer : *YalLexer) {
    line_end = xx lexer.line;
    char_end = xx lexer.column;
}

CompareLineColumnPairs :: inline (l0 : s32, c0 : s32, l1 : s32, c1 : s32) -> int {
    if l0 < l1 {
        return -1;
    }
    if l0 > l1 {
        return 1;
    }
    if c0 < c1 {
        return -1;
    }
    if c0 > c1 {
        return 1;
    }
    return 0;
}

TokenRangeJoin :: (a : TokenRange, b : TokenRange) -> TokenRange {
    Assert(a.file_id == b.file_id);

    result : TokenRange = ---;
    result.file_id = a.file_id;

    start, end : *TokenRange;
    if CompareLineColumnPairs(a.line_start, a.char_start, b.line_start, b.char_start) < 0 {
        start = *a;
    } else {
        start = *b;
    }

    if CompareLineColumnPairs(a.line_end, a.char_end, b.line_end, b.char_end) > 0 {
        end = *a;
    } else {
        end = *b;
    }

    result.line_start = start.line_start;
    result.char_start = start.char_start;
    result.line_end = end.line_end;
    result.char_end = end.char_end;
    result.byte_offset = start.byte_offset;

    return result;
}

TokenRangeToString :: (using range : TokenRange) -> string {
    file := GetFile(file_id);
    Assert(file != null);

    curr_line := line_start;
    curr_char := char_start;
    start := file.text.data + byte_offset;
    end := start;
    while end < file.text.data + file.text.count {
        if curr_line == line_end && curr_char == char_end {
            break;
        }

        if end.* == #char "\n" {
            curr_line += 1;
            curr_char = 0;
        }

        curr_char += 1;
        end += 1;
    }

    return .{end - start, start};
}

TokenRangeToStringFirstLine :: (range : TokenRange) -> string {
    str := TokenRangeToString(range);
    nl := String.find_index_from_left(str, #char "\n");
    if nl >= 0 {
        str.count = nl;
    }

    return str;
}

TokenToString :: inline (tok : Token) -> string {
    return TokenRangeToString(tok.range);
}

Max_Token_Storage :: 10;

CircularBuffer :: struct(T : Type, N : int) {
    performed_one_loop : bool;
    read_index : int;
    write_index : int;
    elements : [N]T;
}

Push :: (using buff : *CircularBuffer, value : buff.T, allow_overwrite := true) {
    elements[write_index] = value;
    write_index = (write_index + 1) % N;
    performed_one_loop |= write_index == 0;

    if write_index == read_index {
        Assert(allow_overwrite, "Circular buffer overflow");
        read_index = (read_index + 1) % N;
    }
}

NumAvailableElements :: inline (using buff : CircularBuffer) -> int {
    if read_index <= write_index {
        return write_index - read_index;
    } else {
        return write_index + N - read_index;
    }
}

Consume :: (using buff : *CircularBuffer, count := 1) -> consumed : int {
    Assert(count > 0);

    count = Min(count, NumAvailableElements(buff));
    read_index = (read_index + count) % N;

    return count;
}

PeekForward :: (using buff : *CircularBuffer, peek := 0) -> *buff.T {
    Assert(peek >= 0);

    if peek >= NumAvailableElements(buff) {
        return null;
    }

    index := (read_index + peek) % N;

    return *elements[index];
}

PeekBackwards :: (using buff : *CircularBuffer, peek := 0) -> *buff.T {
    Assert(peek >= 0);

    allowed_peek : int;
    if performed_one_loop {
        allowed_peek = (ifx read_index <= write_index
            then read_index + (N - write_index)
            else read_index - write_index);
    } else {
        allowed_peek = read_index;
    }

    if peek >= allowed_peek {
        return null;
    }

    index := (read_index - peek - 1);
    if index < 0 {
        index += N;
    }

    Assert(index >= 0 && index < N);

    return *elements[index];
}

#run {
    buff : CircularBuffer(string, 5);
    Assert(NumAvailableElements(buff) == 0);
    Assert(PeekForward(*buff) == null);
    Assert(PeekBackwards(*buff) == null);

    Push(*buff, "Hello");
    Assert(NumAvailableElements(buff) == 1);
    Assert(PeekForward(*buff, 1) == null);
    Assert(PeekForward(*buff) != null);
    Assert(PeekForward(*buff).* == "Hello");
    Assert(PeekBackwards(*buff) == null);

    Assert(Consume(*buff, 3) == 1);
    Assert(NumAvailableElements(buff) == 0);
    Assert(PeekForward(*buff) == null);
    Assert(PeekBackwards(*buff) != null);
    Assert(PeekBackwards(*buff).* == "Hello");
    Assert(PeekBackwards(*buff, 1) == null);

    Push(*buff, "Hello");
    Push(*buff, "World");
    Push(*buff, "One");
    Push(*buff, "Two");
    Assert(NumAvailableElements(buff) == 4);
    Assert(Consume(*buff, 5) == 4);
    Assert(PeekBackwards(*buff) != null);
    Assert(PeekBackwards(*buff).* == "Two");
    Assert(PeekBackwards(*buff, 1) != null);
    Assert(PeekBackwards(*buff, 1).* == "One");
    Assert(PeekBackwards(*buff, 2) != null);
    Assert(PeekBackwards(*buff, 2).* == "World");
    Assert(PeekBackwards(*buff, 3) != null);
    Assert(PeekBackwards(*buff, 3).* == "Hello");
    Assert(PeekBackwards(*buff, 4) != null);
    Assert(PeekBackwards(*buff, 4).* == "Hello");
    Assert(PeekBackwards(*buff, 5) == null);
}

YalLexer :: struct {
    #as using base : Lexer;
    file_id : FileId;
    tokens : CircularBuffer(Token, Max_Token_Storage);
}

PrevToken :: (using lexer : YalLexer, peek := 0) -> Token {
    tok := PeekBackwards(*tokens, peek);
    Assert(tok != null);

    return tok.*;
}

NextToken :: (using lexer : *YalLexer, peek := 0) -> Token {
    Assert(peek >= 0);

    while NumAvailableElements(tokens) < peek + 1 {
        tok := ScanNextToken(lexer);
        if tok.kind == .EOF {
            return tok;
        }

        Push(*tokens, tok, allow_overwrite=false);
    }

    return PeekForward(*tokens, peek);
}

ConsumeToken :: inline (using lexer : *YalLexer, count := 1) {
    Consume(*tokens, count);
}

NextTokenIs :: (using lexer : *YalLexer, kinds : ..TokenKind, peek := 0) -> bool {
    tok := NextToken(lexer, peek);

    for kinds {
        if tok.kind == it {
            return true;
        }
    }

    return false;
}

MatchToken :: (using lexer : *YalLexer, kinds : ..TokenKind) -> bool {
    if NextTokenIs(lexer, ..kinds) {
        ConsumeToken(lexer);

        return true;
    }

    return false;
}

ScanNumber :: (using lexer : *YalLexer, number_base : int) -> is_valid : bool, has_exponent : bool {
    is_valid := true;
    has_exponent := false;

    while !LexerIsAtEnd(lexer) && Basic.is_alnum(text[byte_index]) {
        // Handle float exponent
        if number_base == 10 && text[byte_index] == #char "e" {
            has_exponent = true;

            LexerAdvance(lexer);
            if LexerIsAtEnd(lexer) {
                return false, true;
            }

            sign := 1;
            if text[byte_index] == #char "-" || text[byte_index] == #char "+" {
                sign := ifx text[byte_index] == #char "-" then -1 else 1;
                LexerAdvance(lexer);
            }

            if LexerIsAtEnd(lexer) {
                return false, has_exponent;
            }

            while !LexerIsAtEnd(lexer) && Basic.is_alnum(text[byte_index]) {
                if !Basic.is_digit(text[byte_index]) {
                    is_valid = false;
                }

                LexerAdvance(lexer);
            }

            break;
        }

        valid_digit : bool = ---;
        digit := text[byte_index];
        if number_base == 16 {
            valid_digit = digit >= #char "0" && digit <= #char "9"
                || digit >= #char "A" && digit <= #char "F"
                || digit >= #char "a" && digit <= #char "f"
                || digit == #char "_";
        } else {
            valid_digit = digit >= #char "0" && digit < #char "0" + number_base || digit == #char "_";
        }

        if !valid_digit {
            is_valid = false;
        }

        LexerAdvance(lexer);
    }

    return is_valid, has_exponent;
}

SkipWhitespacesAndComments :: inline (using lexer : *YalLexer) {
    while !LexerIsAtEnd(lexer) {
        if Basic.is_space(text[byte_index]) {
            LexerAdvance(lexer);
        } else if LexerMatchString(lexer, "//") || LexerMatchString(lexer, "#!") {
            while !LexerIsAtEnd(lexer) && text[byte_index] != #char "\n" && text[byte_index] != #char "\r" {
                LexerAdvance(lexer);
            }
        } else if LexerEqualsString(lexer, "/*") {
            LexerAdvance(lexer, 2);

            level := 1;
            while !LexerIsAtEnd(lexer) && level > 0 {
                if LexerMatchString(lexer, "/*") {
                    level += 1;
                } else if LexerMatchString(lexer, "*/") {
                    level -= 1;
                } else {
                    LexerAdvance(lexer);
                }
            }
        } else {
            break;
        }
    }
}

ScanNextToken :: (using lexer : *YalLexer) -> Token {
    SkipWhitespacesAndComments(lexer);

    tok : Token;
    SetStart(*tok, lexer);

    if LexerIsAtEnd(lexer) {
        tok.kind = .EOF;
        SetEnd(*tok, lexer);
        return tok;
    }

    for i : TokenKind.SymbolsBegin + 1..TokenKind.SymbolsEnd - 1 {
        if LexerMatchString(lexer, Token_Lexemes[i]) {
            tok.kind = i;
            SetEnd(*tok, lexer);

            return tok;
        }
    }

    if LexerMatchString(lexer, "\"\"\"") {
        tok.kind = .HereString;

        byte_offset_start := lexer.byte_index;

        while !LexerIsAtEnd(lexer) && Basic.is_alnum(text[byte_index]) {
            LexerAdvance(lexer);
        }

        byte_offset_end := lexer.byte_index;
        here_ident := string.{count=byte_offset_end-byte_offset_start, data=*text[byte_offset_start]};

        if byte_offset_start == byte_offset_end {
            SetEnd(*tok, lexer);
            SyntaxError(tok, "Expected an identifier for here-string");

            return tok;
        }

        if !LexerMatchString(lexer, "\r\n") && !LexerMatchString(lexer, "\n") {
            SetEnd(*tok, lexer);
            SyntaxError(tok, "Expected a newline after here-string ident");

            return tok;
        }

        found_end := false;
        while !LexerIsAtEnd(lexer) {
            if LexerMatchAlphaNumeric(lexer, here_ident) {
                found_end = true;
                break;
            }

            while !LexerIsAtEnd(lexer) && !LexerMatchString(lexer, "\r\n") && !LexerMatchString(lexer, "\n") {
                LexerAdvance(lexer);
            }
        }

        SetEnd(*tok, lexer);

        if !found_end {
            SyntaxError(tok, "Unclosed here-string");
        }

        return tok;
    }

    if text[byte_index] == #char "\"" || text[byte_index] == #char "'" {
        closing_char := text[byte_index];
        LexerAdvance(lexer);

        has_newline := false;
        while !LexerIsAtEnd(lexer) && text[byte_index] != closing_char {
            if text[byte_index] == #char "\\" {
                LexerAdvance(lexer);
                if LexerIsAtEnd(lexer) {
                    break;
                }
            }

            if text[byte_index] == #char "\n" {
                has_newline = true;
            }

            LexerAdvance(lexer);
        }

        unclosed := LexerIsAtEnd(lexer);

        LexerAdvance(lexer);

        tok.kind = ifx closing_char == #char "'"
            then .CharLiteral
            else .StringLiteral;

        SetEnd(*tok, lexer);

        if unclosed {
            SyntaxError(tok, "Unclosed %", Token_Names[tok.kind]);
        } else if has_newline {
            SyntaxError(tok, "Newline in %", Token_Names[tok.kind]);
        }

        return tok;
    }

    if Basic.is_digit(text[byte_index]) {
        base : int = ---;
        if LexerMatchString(lexer, "0b") {
            base = 2;
        } else if LexerMatchString(lexer, "0o") {
            base = 8;
        } else if LexerMatchString(lexer, "0x") {
            base = 16;
        } else {
            base = 10;
        }

        decimal_valid, decimal_exp := ScanNumber(lexer, base);
        if byte_index + 2 <= text.count && text[byte_index] == #char "." && Basic.is_digit(text[byte_index + 1]) {
            LexerAdvance(lexer);

            fract_valid, fract_exp := ScanNumber(lexer, 10);

            // Can't have a non base 10 number followed by a fractional part
            // Can't have a number with exponent followed by a fractional part
            if base != 10 || decimal_exp {
                fract_valid = false;
            }

            tok.kind = .FloatLiteral;
            SetEnd(*tok, lexer);

            if !decimal_valid || !fract_valid {
                SyntaxError(tok, "Invalid float literal");
            }
        } else {
            tok.kind = ifx decimal_exp
                then .FloatLiteral
                else .IntLiteral;

            SetEnd(*tok, lexer);

            if !decimal_valid {
                SyntaxError(tok, "Invalid %", Token_Names[tok.kind]);
            }
        }

        return tok;
    }

    if text[byte_index] == #char "#"
    || text[byte_index] == #char "@"
    || Basic.is_alpha(text[byte_index])
    || text[byte_index] == #char "_" {
        for i : TokenKind.KeywordsBegin + 1..TokenKind.KeywordsEnd - 1 {
            if LexerMatchAlphaNumeric(lexer, Token_Lexemes[i]) {
                tok.kind = i;
                SetEnd(*tok, lexer);

                return tok;
            }
        }

        is_compiler_directive := text[byte_index] == #char "#";
        is_attribute := text[byte_index] == #char "@";
        if is_compiler_directive || is_attribute {
            LexerAdvance(lexer);
        }

        if is_attribute {
            tok.kind = .Attribute;
        } else {
            tok.kind = .Identifier;
        }

        while !LexerIsAtEnd(lexer) && Basic.is_alnum(text[byte_index]) {
            LexerAdvance(lexer);
        }

        SetEnd(*tok, lexer);

        if is_compiler_directive {
            SyntaxError(tok, "Invalid compiler directive");
            tok.kind = .Invalid;
        }

        return tok;
    }

    if tok.kind == .Invalid {
        LexerAdvance(lexer);
    }

    SetEnd(*tok, lexer);

    return tok;
}
