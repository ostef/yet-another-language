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
    if MatchToken (*lexer, .EOI, .Semicolon)
        return;

    if NextTokenIs (*lexer, ..stop_at)
        return;

    ConsumeToken (*lexer);

    while !MatchToken (*lexer, .EOI)
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
    Println ("File '%':", filename);

    while !MatchToken (*lexer, .EOI)
    {
        tok := NextToken (*lexer);
        ConsumeToken (*lexer);
    }
}
