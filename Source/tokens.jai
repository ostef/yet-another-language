Token_Keywords :: string.[
    "var", "const", "proc", "struct", "union", "enum",
    "typedef", "import", "if", "else", "for", "while",
    "continue", "break", "switch", "case", "fallthrough",
    "defer", "using", "cast", "size_of", "return",
    "true", "false", "null", "void", "bool", "string", "int", "uint",
    "s8", "u8", "s16", "u16", "s32", "u32", "s64", "u64",
    "float", "f32", "f64", "external",
];

// Symbol tokens should be declared in the order of longest to shortest,
// since longest tokens have priority over shortest tokens when lexing
// i.e. you want "==" to be declared before "=" so that we try scanning
// "==" before "=", and we don't invalidly get two "=" instead of a "=="

Token_Symbols :: string.[
    "Less_Less_Equ", "<<=",
    "Greater_Greater_Equ", ">>=",
    "Arrow", "->",
    "Dot_Dot", "..",
    "Equ_Equ", "==",
    "Bang_Equ", "!=",
    "Less_Equ", "<=",
    "Greater_Equ", ">=",
    "Plus_Equ", "+=",
    "Minus_Equ", "-=",
    "Star_Equ", "*=",
    "Slash_Equ", "/=",
    "Percent_Equ", "%=",
    "Ampersand_Equ", "&=",
    "Pipe_Equ", "|=",
    "Tilde_Equ", "~=",
    "Caret_Equ", "^=",
    "Less_Less", "<<",
    "Greater_Greater", ">>",
    "Ampersand_Ampersand", "&&",
    "Pipe_Pipe", "||",
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
    "Open_Paren", "(",
    "Close_Paren", ")",
    "Open_Bracket", "[",
    "Close_Bracket", "]",
    "Open_Curly", "{",
    "Close_Curly", "}",
    "Colon", ":",
    "Semicolon", ";",
    "Dot", ".",
    "Comma", ",",
];

// Check that our Token_Symbols array is ordered
#run {
    for i : 1..(Token_Symbols.count / 2) - 1
    {
        a := Token_Symbols[i * 2 + 1];
        b := Token_Symbols[i * 2 - 1];
        if a.count > b.count
        {
            message := FormatString ("Token_Symbols should be sorted by longest to shortest (symbol % is after % even though it is longer)", a, b);

            JaiC.compiler_report (message, #location (Token_Symbols));
        }
    }
}

#placeholder TokenKind;

#insert -> string
{
    builder : StringBuilder;

    StringBuilderAppendLine (*builder, "TokenKind :: enum u8\n{");
    StringBuilderAppendLine (*builder, "    Invalid;");
    StringBuilderAppendLine (*builder, "    Comment;");
    StringBuilderAppendLine (*builder, "    Symbols_Begin;");

    for i : 0..(Token_Symbols.count / 2) - 1
    {
        StringBuilderAppendLine (*builder, "    %;", Token_Symbols[i * 2]);
    }

    StringBuilderAppendLine (*builder, "    Symbols_End;");
    StringBuilderAppendLine (*builder, "    Keywords_Begin;");

    for kw : Token_Keywords
    {
        StringBuilderAppend (*builder, "    ");

        capitalize := true;
        for i : 0..kw.count - 1
        {
            if capitalize
                StringBuilderAppendByte (*builder, Basic.to_upper (kw[i]));
            else
                StringBuilderAppendByte (*builder, kw[i]);

            capitalize = false;

            if kw[i] == #char "_"
                capitalize = true;
        }

        StringBuilderAppend (*builder, ";\n");
    }

    StringBuilderAppendLine (*builder, "    Keywords_End;");
    StringBuilderAppendLine (*builder, "    Identifier;");
    StringBuilderAppendLine (*builder, "    Int_Literal;");
    StringBuilderAppendLine (*builder, "    Float_Literal;");
    StringBuilderAppendLine (*builder, "    String_Literal;");
    StringBuilderAppendLine (*builder, "    Char_Literal;");
    StringBuilderAppendLine (*builder, "    EOF;");
    StringBuilderAppendLine (*builder, "    Count;");
    StringBuilderAppendLine (*builder, "}");

    return StringBuilderBuild (*builder);
}

Token_Lexemes :: #insert -> string
{
    builder : StringBuilder;

    StringBuilderAppendLine (*builder, "string.[");

    for i : 0..TokenKind.Count - 1
    {
        if i != 0
            StringBuilderAppendLine (*builder, ",\n");

        if i > TokenKind.Symbols_Begin && i < TokenKind.Symbols_End
        {
            index := (cast (int) i - cast (int) TokenKind.Symbols_Begin - 1) * 2 + 1;
            StringBuilderAppend (*builder, "\"%\"", Token_Symbols[index]);
        }
        else if i > TokenKind.Keywords_Begin && i < TokenKind.Keywords_End
        {
            index := cast (int) i - cast (int) TokenKind.Keywords_Begin - 1;
            StringBuilderAppend (*builder, "\"%\"", Token_Keywords[index]);
        }
        else
        {
            StringBuilderAppend (*builder, "\"\"");
        }
    }

    StringBuilderAppendLine (*builder, "\n];");

    return StringBuilderBuild (*builder);
}

Token_Names :: #insert -> string
{
    builder : StringBuilder;

    StringBuilderAppendLine (*builder, "string.[");

    for i : 0..TokenKind.Count - 1
    {
        if i != 0
            StringBuilderAppend (*builder, ",\n");

        if i == .EOF
        {
            StringBuilderAppend (*builder, "\"end of file\"");
        }
        else if Token_Lexemes[i]
        {
            StringBuilderAppend (*builder, "\"'%'\"", Token_Lexemes[i]);
        }
        else
        {
            StringBuilderAppend (*builder, "\"");

            name_index := -1;
            for ii : 0..type_info (TokenKind).values.count
            {
                if cast (int) i == type_info (TokenKind).values[ii]
                {
                    name_index = ii;
                    break;
                }
            }

            Assert (name_index > -1);

            name := type_info (TokenKind).names[name_index];
            for ii : 0..name.count - 1
            {
                if name[ii] == #char "_"
                    StringBuilderAppendByte (*builder, #char " ");
                else
                    StringBuilderAppendByte (*builder, Basic.to_lower (name[ii]));
            }

            StringBuilderAppend (*builder, "\"");
        }
    }

    StringBuilderAppendLine (*builder, "\n];");

    return StringBuilderBuild (*builder);
}

Tokens_Assignment :: TokenKind.[
    .Equal,
    .Plus_Equ,
    .Minus_Equ,
    .Star_Equ,
    .Slash_Equ,
    .Percent_Equ,
    .Ampersand_Equ,
    .Pipe_Equ,
    .Caret_Equ,
    .Less_Less_Equ,
    .Greater_Greater_Equ,
];

TokenLocation :: struct
{
    byte_offset : s64;
    line : s32;
    char : s32;
    file_id : FileId;
}

TokenRange :: struct
{
    byte_offset : s64;
    line_start, line_end : s32;
    char_start, char_end : s32;
    file_id : FileId;
}

Token :: struct
{
    #as using range : TokenRange;
    #as kind : TokenKind;
}

SetStart :: inline (using tok : *Token, lexer : *YalLexer)
{
    file_id = lexer.file_id;
    line_start = xx lexer.line;
    char_start = xx lexer.column;
    byte_offset = lexer.byte_index;
}

SetEnd :: inline (using tok : *Token, lexer : *YalLexer)
{
    line_end = xx lexer.line;
    char_end = xx lexer.column;
}

CompareLineColumnPairs :: inline (l0 : s32, c0 : s32, l1 : s32, c1 : s32) -> int #must
{
    if l0 < l1
        return -1;
    if l0 > l1
        return 1;
    if c0 < c1
        return -1;
    if c0 > c1
        return 1;
    return 0;
}

TokenRangeJoin :: (a : TokenRange, b : TokenRange) -> TokenRange #must
{
    Assert (a.file_id == b.file_id);

    result : TokenRange = ---;
    result.file_id = a.file_id;

    start, end : *TokenRange;
    if CompareLineColumnPairs (a.line_start, a.char_start, b.line_start, b.char_start) < 0
        start = *a;
    else
        start = *b;

    if CompareLineColumnPairs (a.line_end, a.char_end, b.line_end, b.char_end) > 0
        end = *a;
    else
        end = *b;

    result.line_start = start.line_start;
    result.char_start = start.char_start;
    result.line_end = end.line_end;
    result.char_end = end.char_end;
    result.byte_offset = start.byte_offset;

    return result;
}

TokenRangeToString :: (using range : TokenRange) -> string #must
{
    file := GetFile (file_id);
    Assert (file != null);

    curr_line := line_start;
    curr_char := char_start;
    start := file.text.data + byte_offset;
    end := start;
    while end < file.text.data + file.text.count
    {
        if curr_line == line_end && curr_char == char_end
            break;

        if end.* == #char "\n"
        {
            curr_line += 1;
            curr_char = 0;
        }

        curr_char += 1;
        end += 1;
    }

    return .{end - start, start};
}

TokenToString :: inline (tok : Token) -> string #must
{
    return TokenRangeToString (tok.range);
}

YalLexer :: struct
{
    #as using base : Lexer;
    file_id : FileId;
    next_token_index : s64;
    tokens : [..]Token;
}

PrevToken :: (using lexer : YalLexer, peek := 0) -> Token #must
{
    Assert (peek >= 0);

    index := Clamp (next_token_index - peek - 1, 0, tokens.count - 1);

    return tokens[index];
}

NextToken :: (using lexer : *YalLexer, peek := 0) -> Token #must
{
    Assert (peek >= 0);

    while next_token_index + peek >= tokens.count - 1
    {
        tok := ScanNextToken (lexer);
        if tok.kind == .EOF && tokens.count > 0 && tokens[tokens.count - 1].kind == .EOF
            break;

        ArrayPush (*tokens, tok);
    }

    index := Clamp (next_token_index + peek, 0, tokens.count - 1);

    return tokens[index];
}

ConsumeToken :: inline (using lexer : *YalLexer, count := 1)
{
    next_token_index = Min (next_token_index + count, tokens.count);
}

NextTokenIs :: (using lexer : *YalLexer, kinds : ..TokenKind) -> bool #must
{
    tok := NextToken (lexer);

    for kinds
    {
        if tok.kind == it
            return true;
    }

    return false;
}

MatchToken :: (using lexer : *YalLexer, kinds : ..TokenKind) -> bool #must
{
    if NextTokenIs (lexer, ..kinds)
    {
        ConsumeToken (lexer);

        return true;
    }

    return false;
}

ScanNumber :: (using lexer : *YalLexer, number_base : int) -> is_valid : bool, has_exponent : bool
{
    is_valid := true;
    has_exponent := false;

    while !LexerIsAtEnd (lexer) && Basic.is_alnum (text[byte_index])
    {
        // Handle float exponent
        if number_base == 10 && text[byte_index] == #char "e"
        {
            has_exponent = true;

            LexerAdvance (lexer);
            if LexerIsAtEnd (lexer)
                return false, true;

            sign := 1;
            if text[byte_index] == #char "-" || text[byte_index] == #char "+"
            {
                sign := ifx text[byte_index] == #char "-" then -1 else 1;
                LexerAdvance (lexer);
            }

            if LexerIsAtEnd (lexer)
                return false, has_exponent;

            while !LexerIsAtEnd (lexer) && Basic.is_alnum (text[byte_index])
            {
                if !Basic.is_digit (text[byte_index])
                    is_valid = false;

                LexerAdvance (lexer);
            }

            break;
        }

        valid_digit : bool = ---;
        digit := text[byte_index];
        if number_base == 16
        {
            valid_digit = digit >= #char "0" && digit <= #char "9"
                || digit >= #char "A" && digit <= #char "F"
                || digit >= #char "a" && digit <= #char "f"
                || digit == #char "_";
        }
        else
        {
            valid_digit = digit >= #char "0" && digit < #char "0" + number_base || digit == #char "_";
        }

        if !valid_digit
            is_valid = false;

        LexerAdvance (lexer);
    }

    return is_valid, has_exponent;
}

ScanNextToken :: (using lexer : *YalLexer) -> Token #must
{
    LexerSkipWhitespacesAndComments (lexer);

    tok : Token;
    SetStart (*tok, lexer);

    if LexerIsAtEnd (lexer)
    {
        tok.kind = .EOF;
        SetEnd (*tok, lexer);
        return tok;
    }

    if text[byte_index] == #char "\"" || text[byte_index] == #char "'"
    {
        closing_char := text[byte_index];
        LexerAdvance (lexer);

        has_newline := false;
        while !LexerIsAtEnd (lexer) && text[byte_index] != closing_char
        {
            if text[byte_index] == #char "\\"
            {
                LexerAdvance (lexer);
                if LexerIsAtEnd (lexer)
                    break;
            }

            if text[byte_index] == #char "\n"
                has_newline = true;

            LexerAdvance (lexer);
        }

        unclosed := LexerIsAtEnd (lexer);

        LexerAdvance (lexer);

        tok.kind = ifx closing_char == #char "'"
            then .Char_Literal
            else .String_Literal;

        SetEnd (*tok, lexer);

        if unclosed
            SyntaxError (tok, "Unclosed %", Token_Names[tok.kind]);
        else if has_newline
            SyntaxError (tok, "Newline in %", Token_Names[tok.kind]);

        return tok;
    }

    if Basic.is_digit (text[byte_index])
    {
        base : int = ---;
        if LexerMatchString (lexer, "0b")
            base = 2;
        else if LexerMatchString (lexer, "0o")
            base = 8;
        else if LexerMatchString (lexer, "0x")
            base = 16;
        else
            base = 10;

        decimal_valid, decimal_exp := ScanNumber (lexer, base);
        if !LexerIsAtEnd (lexer) && text[byte_index] == #char "."
        {
            LexerAdvance (lexer);

            fract_valid, fract_exp := ScanNumber (lexer, 10);

            // Can't have a non base 10 number followed by a fractional part
            // Can't have a number with exponent followed by a fractional part
            if base != 10 || decimal_exp
                fract_valid = false;

            tok.kind = .Float_Literal;
            SetEnd (*tok, lexer);

            if !decimal_valid || !fract_valid
                SyntaxError (tok, "Invalid float literal");
        }
        else
        {
            tok.kind = ifx decimal_exp
                then .Float_Literal
                else .Int_Literal;

            SetEnd (*tok, lexer);

            if !decimal_valid
                SyntaxError (tok, "Invalid %", Token_Names[tok.kind]);
        }

        return tok;
    }

    if Basic.is_alpha (text[byte_index]) || text[byte_index] == #char "_"
    {
        for i : TokenKind.Keywords_Begin + 1..TokenKind.Keywords_End - 1
        {
            if LexerMatchAlphaNumeric (lexer, Token_Lexemes[i])
            {
                tok.kind = i;
                SetEnd (*tok, lexer);

                return tok;
            }
        }

        tok.kind = .Identifier;
        while !LexerIsAtEnd (lexer) && Basic.is_alnum (text[byte_index])
            LexerAdvance (lexer);

        SetEnd (*tok, lexer);

        return tok;
    }

    for i : TokenKind.Symbols_Begin + 1..TokenKind.Symbols_End - 1
    {
        if LexerMatchString (lexer, Token_Lexemes[i])
        {
            tok.kind = i;
            SetEnd (*tok, lexer);

            return tok;
        }
    }

    if tok.kind == .Invalid
        LexerAdvance (lexer);

    SetEnd (*tok, lexer);

    return tok;
}
