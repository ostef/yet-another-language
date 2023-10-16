#import "Lexer";

FileId :: s16;

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

    if CompareLineColumnPairs (a.line_end, a.char_end, b.line_end, b.char_end) < 0
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

    return MakeString (end - start, start);
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
        if tok.kind == .End_Of_Input && tokens.count > 0 && tokens[tokens.count - 1].kind == .End_Of_Input
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
        tok.kind = .End_Of_Input;
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
                LexerAdvance (lexer);
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
            SyntaxError (tok, "unclosed %", Token_Names[tok.kind]);
        else if has_newline
            SyntaxError (tok, "newline in %", Token_Names[tok.kind]);

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
                SyntaxError (tok, "invalid float literal");
        }
        else
        {
            tok.kind = ifx decimal_exp
                then .Float_Literal
                else .Int_Literal;

            SetEnd (*tok, lexer);

            if !decimal_valid
                SyntaxError (tok, "invalid %", Token_Names[tok.kind]);
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
    if MatchToken (*lexer, .End_Of_Input, .Semicolon)
        return;

    if NextTokenIs (*lexer, ..stop_at)
        return;

    ConsumeToken (*lexer);

    while !MatchToken (*lexer, .End_Of_Input)
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
    Println ("File '%'", filename);

    while !MatchToken (*lexer, .End_Of_Input)
    {
        tok := NextToken (*lexer);
        ConsumeToken (*lexer);

        Print ("%:%   %", tok.line_start, tok.char_start, tok.kind);
        if !Token_Lexemes[tok.kind]
            Print ("    '%'", TokenToString (tok));
        Print ("\n");
    }
}
