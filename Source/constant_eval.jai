// @Todo: handle unsigned numbers

ConstantKind :: enum u8
{
    Invalid;
    Integer;
    Boolean;
    Float;
    String;
    Pointer;
    Procedure;
}

ConstantValue :: struct
{
    union
    {
        int_value : s64;
        bool_value : bool;
        float_value : float64;
        string_value : string;
        pointer_value : s64;
        procedure_node : *AstProcedure;
    };

    kind : ConstantKind;
}

MakeConstantValue :: (token : Token) -> ConstantValue, *YalType, bool
{
    if token.kind ==
    {
    case .String_Literal;
        val : ConstantValue = ---;
        val.kind = .String;
        ok : bool;
        val.string_value, ok = ParseStringLiteral (token);

        return val, g_type_string, true;

    case .Char_Literal;
        val : ConstantValue = ---;
        val.kind = .Integer;
        ok : bool;
        val.int_value, ok = ParseCharLiteral (token);

        return val, g_type_s64, true;

    case .Int_Literal;
        val : ConstantValue = ---;
        val.kind = .Integer;
        ok : bool;
        val.int_value, ok = ParseIntLiteral (token);

        return val, g_type_s64, true;

    case .Float_Literal;
        val : ConstantValue = ---;
        val.kind = .Float;
        ok : bool;
        val.float_value, ok = ParseFloatLiteral (token);

        return val, g_type_f32, true;

    case .True;
        val : ConstantValue = ---;
        val.kind = .Boolean;
        val.bool_value = true;

        return val, g_type_bool, true;

    case .False;
        val : ConstantValue = ---;
        val.kind = .Boolean;
        val.bool_value = false;

        return val, g_type_bool, true;

    case .Null;
        val : ConstantValue = ---;
        val.kind = .Pointer;
        val.pointer_value = 0;

        return val, g_type_void_ptr, true;

    case;
        Panic ("Invalid token kind % for literal", token.kind);
        return .{}, null, false;
    }
}

ParseStringLiteral :: (token : Token) -> string, bool
{
    str := TokenToString (token);
    buffer := Alloc (u8, str.count);
    index := 0;

    str.data += 1;
    str.count -= 2;

    escape := false;
    for i : 0..str.count - 1
    {
        if escape
        {
            if str[i] ==
            {
            case #char "\\";
                buffer[index] = #char "\\";
            case #char "0";
                buffer[index] = 0;
            case #char "t";
                buffer[index] = #char "\t";
            case #char "n";
                buffer[index] = #char "\n";
            case #char "r";
                buffer[index] = #char "\r";
            case #char "'";
                buffer[index] = #char "'";
            case #char "\"";
                buffer[index] = #char "\"";

            case;
                SyntaxError (token, "invalid escape sequence in string literal");
                InfoWithoutSourceCode (token, "valid escape sequences are \\0, \\t, \\n, \\r, \\\\, \\', \\\"");
                return "", false;
            }

            index += 1;
            escape = false;

            continue;
        }

        if str[i] == #char "\\"
        {
            escape = true;
            continue;
        }

        buffer[index] = str[i];
        index += 1;
    }

    if escape
    {
        SyntaxError (token, "unfinished escaped sequence at then end of a string literal");
        return "", false;
    }

    return MakeString (index, buffer), true;
}

ParseCharLiteral :: (token : Token) -> s64, bool
{
    str := TokenToString (token);
    str.data += 1;
    str.count -= 2;

    if str ==
    {
    case "\\0";
        return 0, true;
    case "\\t";
        return #char "\t", true;
    case "\\n";
        return #char "\n", true;
    case "\\r";
        return #char "\r", true;
    case "\\\\";
        return #char "\\", true;
    case "\\'";
        return #char "'", true;
    case "\\\"";
        return #char "\"", true;
    }

    // @Todo: handle unicode escape sequences

    if str.count > 0 && str[0] == #char "\\"
    {
        SyntaxError (token, "invalid escape sequence in character literal");
        InfoWithoutSourceCode (token, "valid escape sequences are \\0, \\t, \\n, \\r, \\\\, \\', \\\"");
        return 0, false;
    }

    if str.count != 1
    {
        SyntaxError (token, "invalid character literal");
        return 0, false;
    }

    return cast (s64) str[0], true;
}

ParseIntLiteral :: (token : Token) -> s64, bool
{
    CharToDigit :: inline (char : u8) -> int #must
    {
        if char >= #char "a" && char <= #char "f"
            return 10 + char - #char "a";

        if char >= #char "A" && char <= #char "F"
            return 10 + char - #char "A";

        return char - #char "0";
    }

    str := TokenToString (token);
    base := 10;
    if str.count > 2
    {
        prefix := str;
        prefix.count = 2;
        if prefix ==
        {
        case "0b";
            str.data += 2;
            str.count -= 2;
            base = 2;
        case "0o";
            str.data += 2;
            str.count -= 2;
            base = 8;
        case "0x";
            str.data += 2;
            str.count -= 2;
            base = 16;
        }
    }

    // @Todo: handle overflow and underflow
    result : s64;
    for i : 0..str.count - 1
    {
        if str[i] == #char "_"
            continue;

        digit := CharToDigit (str[i]);
        result *= base;
        result += digit;
    }

    return result, true;
}

ParseFloatLiteral :: (token : Token) -> float64, bool
{
    TemporaryStorageScope ();

    str_with_underscores := TokenToString (token);
    str := Alloc (u8, str_with_underscores.count);
    index := 0;

    for i : 0..str_with_underscores.count - 1
    {
        if str_with_underscores[i] == #char "_"
            continue;

        str[index] = str_with_underscores[i];
        index += 1;
    }

    result, ok := Basic.string_to_float64 (MakeString (index, str));
    if !ok
        SyntaxError (token, "invalid float literal");

    return result, ok;
}

NegateValue :: (val : ConstantValue) -> ConstantValue #must
{
    result : ConstantValue;
    result.kind = val.kind;

    // @Todo: handle underflow
    if val.kind ==
    {
    case .Integer;
        result.int_value = -val.int_value;
    case .Float;
        result.float_value = -val.float_value;
    case;
        Panic ("invalid type for negation %", val.kind);
    }

    return result;
}
