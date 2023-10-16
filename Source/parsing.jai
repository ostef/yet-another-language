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
    return g_files[g_file_id_counter];
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

        Println ("%:%   %", tok.line_start, tok.char_start, tok.kind);
    }
}
