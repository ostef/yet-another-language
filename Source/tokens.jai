Token_Keywords :: string.[
    "var", "const", "proc", "struct", "union", "enum",
    "typedef", "import", "if", "else", "for", "while",
    "continue", "break", "switch", "case", "fallthrough",
    "defer", "using", "cast", "size_of", "return",
    "true", "false", "null", "void", "bool", "string", "int", "uint",
    "s8", "u8", "s16", "u16", "s32", "u32", "s64", "u64",
    "float", "f32", "f64",
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

    StringBuilderAppendLine (*builder, "TokenKind :: enum u8\n{{");
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
    StringBuilderAppendLine (*builder, "    End_Of_Input;");
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

        if Token_Lexemes[i]
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
