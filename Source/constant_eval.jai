ConstantKind :: enum u8 {
    Invalid;
    Integer;
    Boolean;
    Float;
    String;
    Pointer;
    Function;
    FunctionOverloadSet;
    TypeId;
    Struct;
    Module;
    TemplateParam;
}

ConstantStructValue :: struct {
    type : *YalTypeStruct;
    values : []ConstantValue;
}

ConstantValue :: struct {
    union {
        int_value : S128;
        bool_value : bool;
        float_value : float64;
        string_value : string;
        pointer_value : u64;
        function_node : *AstFunction;
        overload_set : struct {
            node : *AstFunctionOverloadSet;
            selected_overload_index := -1;
        };
        type_value : *YalType;
        struct_value : *ConstantStructValue; // A pointer because it's big
        module : *YalModule;
    };

    kind : ConstantKind;
}

ToString :: (value : ConstantValue) -> string {
    if #complete value.kind == {
    case .Invalid;
        return StringClone("<invalid>");
    case .Integer;
        return SPrint("%", value.int_value);
    case .Float;
        return SPrint("%", value.float_value);
    case .Boolean;
        return SPrint("%", value.bool_value);
    case .String;
        builder : StringBuilder;
        StringBuilderAppendStringLiteral(*builder, value.string_value);

        return StringBuilderBuild(*builder);
    case .Pointer;
        return SPrint("%", cast(*void) value.pointer_value);
    case .Function;
        return SPrint("%", value.function_node);
    case .FunctionOverloadSet;
        return SPrint("%", value.overload_set.node);
    case .TypeId;
        return ToString(value.type_value);
    case .Struct;
        return StringClone("<struct value>");
    case .Module;
        return SPrint("<module '%'>", value.module.name);
    case .TemplateParam;
        return SPrint("<template param>");
    }
}

IsTemplateValue :: inline (value : ConstantValue) -> bool {
    return value.kind == .TemplateParam || (value.kind == .TypeId && value.type_value.kind == .TemplateParam);
}

// @Cleanup: the way we do constant eval and casting can have different results from
// runtime stuff because it relies on the behavior of the host language (although our
// interpreter does the same, so for now it's probably not causing problems).
// We might want to look at a better and less error-prone way of doing things down the line

ConstantCast :: (value : ConstantValue, dest_type : *YalType) -> ConstantValue {
    if dest_type.kind == {
    case .Module;
        if value.kind == {
        case .Module;
            return value;
        }

    case .TypeId;
        if value.kind == {
        case .TypeId;
            return value;
        }

    case .Enum; #through;
    case .Integer;
        if value.kind == {
        case .Integer;
            int_type := ifx dest_type.kind == .Integer
                then cast(*YalTypeInteger, dest_type)
                else cast(*YalTypeEnum, dest_type).base_type;
            if int_type.is_signed {
                if int_type.size == {
                case 1; return .{kind=.Integer, int_value=ToS128(cast,no_check(s8, value.int_value.low))};
                case 2; return .{kind=.Integer, int_value=ToS128(cast,no_check(s16, value.int_value.low))};
                case 4; return .{kind=.Integer, int_value=ToS128(cast,no_check(s32, value.int_value.low))};
                case 8; return .{kind=.Integer, int_value=ToS128(cast,no_check(s64, value.int_value.low))};
                case;
                    Panic("Invalid integer type size %", int_type.size);
                }
            } else {
                if int_type.size == {
                case 1; return .{kind=.Integer, int_value=ToS128(cast,no_check(u8, value.int_value.low))};
                case 2; return .{kind=.Integer, int_value=ToS128(cast,no_check(u16, value.int_value.low))};
                case 4; return .{kind=.Integer, int_value=ToS128(cast,no_check(u32, value.int_value.low))};
                case 8; return .{kind=.Integer, int_value=ToS128(cast,no_check(u64, value.int_value.low))};
                case;
                    Panic("Invalid integer type size %", int_type.size);
                }
            }
        case .Boolean;
            return .{kind=.Integer, int_value=ToS128(cast(int, value.bool_value))};
        case .Float;
            // @Todo: make sure casting to s64 then to the appropriate integer is the best way to do this
            return ConstantCast(.{kind=.Integer, int_value=ToS128(cast(int, value.float_value))}, dest_type);
        case .Pointer;
            return ConstantCast(.{kind=.Integer, int_value=ToS128(cast(u64, value.pointer_value))}, dest_type);
        }

    case .Bool;
        if value.kind == {
        case .Integer;
            return .{kind=.Boolean, bool_value=value.int_value != ToS128(0)};
        case .Boolean;
            return value;
        case .Float;
            return .{kind=.Boolean, bool_value=value.float_value != 0};
        case .String;
            return .{kind=.Boolean, bool_value=value.string_value.count != 0};
        case .Pointer;
            return .{kind=.Boolean, bool_value=value.pointer_value != 0};
        case .Function;
            return .{kind=.Boolean, bool_value=true};
        }

    case .Float;
        if value.kind == {
        case .Integer;
            return .{kind=.Float, float_value=ToFloat64(value.int_value)};
        case .Boolean;
            return .{kind=.Float, float_value=cast(float64, value.bool_value)};
        case .Float;
            return value;
        }

    case .String;
        if value.kind == {
        case .String;
            return value;
        }

    case .Pointer;
        if value.kind == {
        case .Integer;
            return .{kind=.Pointer, pointer_value=value.int_value.low};
        case .Pointer;
            return value;
        }

    case .Function;
        if value.kind == .Pointer {
            Assert(value.pointer_value == 0, "Only null pointer values can be constant casted to functions");
            return .{kind=.Function, function_node=null};
        }
    }

    Panic("Cannot constant cast % to %", value.kind, ToString(dest_type));
    return .{};
}

ConstantBitCast :: (value : ConstantValue, dest_type : *YalType) -> ConstantValue {
    if dest_type.kind == {
    case .Enum; #through;
    case .Integer;
        int_type := ifx dest_type.kind == .Integer
            then cast(*YalTypeInteger, dest_type)
            else cast(*YalTypeEnum, dest_type).base_type;
        if value.kind == {
        case .Integer;
            if int_type.is_signed {
                if int_type.size == {
                case 1; return .{kind=.Integer, int_value=ToS128(cast,no_check(s8, value.int_value.low))};
                case 2; return .{kind=.Integer, int_value=ToS128(cast,no_check(s16, value.int_value.low))};
                case 4; return .{kind=.Integer, int_value=ToS128(cast,no_check(s32, value.int_value.low))};
                case 8; return .{kind=.Integer, int_value=ToS128(cast,no_check(s64, value.int_value.low))};
                case;
                    Panic("Invalid integer type size %", int_type.size);
                }
            } else {
                if int_type.size == {
                case 1; return .{kind=.Integer, int_value=ToS128(cast,no_check(u8, value.int_value.low))};
                case 2; return .{kind=.Integer, int_value=ToS128(cast,no_check(u16, value.int_value.low))};
                case 4; return .{kind=.Integer, int_value=ToS128(cast,no_check(u32, value.int_value.low))};
                case 8; return .{kind=.Integer, int_value=ToS128(cast,no_check(u64, value.int_value.low))};
                case;
                    Panic("Invalid integer type size %", int_type.size);
                }
            }

            return value;
        case .Boolean;
            if int_type.is_signed {
                return .{kind=.Integer, int_value=ToS128(cast,no_check(s8, value.bool_value))};
            } else {
                return .{kind=.Integer, int_value=ToS128(cast,no_check(u8, value.bool_value))};
            }
        case .Float;
            if dest_type.size == 4 {
                return ConstantBitCast(.{kind=.Integer, int_value=ToS128(cast(*u32, *cast(float32, value.float_value)).*)}, dest_type);
            } else {
                return ConstantBitCast(.{kind=.Integer, int_value=ToS128(cast(*u64, *value.float_value).*)}, dest_type);
            }
        case .Pointer;
            return ConstantBitCast(.{kind=.Integer, int_value=ToS128(cast(u64, value.pointer_value))}, dest_type);
        }

    case .Bool;
        if value.kind == {
        case .Integer;
            return .{kind=.Boolean, bool_value=cast,no_check(bool, value.int_value.low)};
        case .Boolean;
            return value;
        }

    case .Float;
        if value.kind == {
        case .Integer;
            // @Todo: represent 32-bit floating point values correctly, otherwise bitcasts will not be correct!
            if dest_type.size == 4 {
                return .{kind=.Float, float_value=cast(*float32, *cast,no_check(u32, value.int_value.low)).*};
            } else {
                return .{kind=.Float, float_value=cast(*float64, *cast,no_check(u64, value.int_value.low)).*};
            }
        case .Float;
            return value;
        }

    case .Pointer;
        if value.kind == {
        case .Integer;
            return .{kind=.Pointer, pointer_value=value.int_value.low};
        case .Pointer;
            return value;
        }
    }

    Panic("Cannot constant bitcast % to %", value.kind, ToString(dest_type));
    return .{};
}

ConstantEvaluate :: (left : ConstantValue, right : ConstantValue, op : TokenKind, node_for_debug : *AstNode = null) -> ConstantValue {
    if op == {
    case .EquEqu;
        if #complete left.kind == {
        case .Invalid;
        case .Integer;
            return .{bool_value=left.int_value == right.int_value, kind=.Boolean};
        case .Float;
            return .{bool_value=left.float_value == right.float_value, kind=.Boolean};
        case .Boolean;
            return .{bool_value=left.bool_value == right.bool_value, kind=.Boolean};
        case .String;
            return .{bool_value=left.string_value == right.string_value, kind=.Boolean};
        case .Pointer;
            return .{bool_value=left.pointer_value == right.pointer_value, kind=.Boolean};
        case .Function;
            return .{bool_value=left.function_node == right.function_node, kind=.Boolean};
        case .FunctionOverloadSet;
            return .{bool_value=left.overload_set.node == right.overload_set.node, kind=.Boolean};
        case .TypeId;
            return .{bool_value=left.type_value == right.type_value, kind=.Boolean};
        case .Struct;
            Assert(node_for_debug, right.kind == .Struct, "RHS is not a struct value");
            return .{bool_value=CompareConstantStructValues(left.struct_value.*, right.struct_value.*), kind=.Boolean};
        case .Module;
            Assert(node_for_debug, right.kind == .Module, "RHS is not a module value");
            return .{bool_value=left.module == right.module, kind=.Boolean};
        case .TemplateParam;
            return .{bool_value=false, kind=.Boolean};
        }
    case .BangEqu;
        if #complete left.kind == {
        case .Invalid;
        case .Integer;
            return .{bool_value=left.int_value != right.int_value, kind=.Boolean};
        case .Float;
            return .{bool_value=left.float_value != right.float_value, kind=.Boolean};
        case .Boolean;
            return .{bool_value=left.bool_value != right.bool_value, kind=.Boolean};
        case .String;
            return .{bool_value=left.string_value != right.string_value, kind=.Boolean};
        case .Pointer;
            return .{bool_value=left.pointer_value != right.pointer_value, kind=.Boolean};
        case .Function;
            return .{bool_value=left.function_node != right.function_node, kind=.Boolean};
        case .FunctionOverloadSet;
            return .{bool_value=left.overload_set.node != right.overload_set.node, kind=.Boolean};
        case .TypeId;
            return .{bool_value=left.type_value != right.type_value, kind=.Boolean};
        case .Struct;
            Assert(node_for_debug, right.kind == .Struct, "RHS is not a struct value");
            return .{bool_value=!CompareConstantStructValues(left.struct_value.*, right.struct_value.*), kind=.Boolean};
        case .Module;
            Assert(node_for_debug, right.kind == .Module, "RHS is not a module value");
            return .{bool_value=left.module != right.module, kind=.Boolean};
        case .TemplateParam;
            return .{bool_value=false, kind=.Boolean};
        }
    case .PipePipe;
        Assert(left.kind == .Boolean);
        return .{bool_value=left.bool_value || right.bool_value, kind=.Boolean};
    case .AmpersandAmpersand;
        Assert(left.kind == .Boolean);
        return .{bool_value=left.bool_value && right.bool_value, kind=.Boolean};
    case .Less;
        if left.kind == {
        case .Integer;
            return .{bool_value=left.int_value < right.int_value, kind=.Boolean};
        case .Float;
            return .{bool_value=left.float_value < right.float_value, kind=.Boolean};
        }
    case .LessEqu;
        if left.kind == {
        case .Integer;
            return .{bool_value=left.int_value <= right.int_value, kind=.Boolean};
        case .Float;
            return .{bool_value=left.float_value <= right.float_value, kind=.Boolean};
        }
    case .Greater;
        if left.kind == {
        case .Integer;
            return .{bool_value=left.int_value > right.int_value, kind=.Boolean};
        case .Float;
            return .{bool_value=left.float_value > right.float_value, kind=.Boolean};
        }
    case .GreaterEqu;
        if left.kind == {
        case .Integer;
            return .{bool_value=left.int_value >= right.int_value, kind=.Boolean};
        case .Float;
            return .{bool_value=left.float_value >= right.float_value, kind=.Boolean};
        }
    case .Plus;
        if left.kind == {
        case .Integer;
            return .{int_value=left.int_value + right.int_value, kind=.Integer};
        case .Float;
            return .{float_value=left.float_value + right.float_value, kind=.Float};
        }
    case .Minus;
        if left.kind == {
        case .Integer;
            return .{int_value=left.int_value - right.int_value, kind=.Integer};
        case .Float;
            return .{float_value=left.float_value - right.float_value, kind=.Float};
        }
    case .Star;
        if left.kind == {
        case .Integer;
            return .{int_value=left.int_value * right.int_value, kind=.Integer};
        case .Float;
            return .{float_value=left.float_value * right.float_value, kind=.Float};
        }
    case .Slash;
        if left.kind == {
        case .Integer;
            return .{int_value=left.int_value / right.int_value, kind=.Integer};
        case .Float;
            return .{float_value=left.float_value / right.float_value, kind=.Float};
        }
    case .Percent;
        if left.kind == {
        case .Integer;
            return .{int_value=left.int_value % right.int_value, kind=.Integer};
        }
    case .Pipe;
        if left.kind == {
        case .Integer;
            return .{int_value=left.int_value | right.int_value, kind=.Integer};
        }
    case .Caret;
        if left.kind == {
        case .Integer;
            return .{int_value=left.int_value ^ right.int_value, kind=.Integer};
        }
    case .Ampersand;
        if left.kind == {
        case .Integer;
            return .{int_value=left.int_value & right.int_value, kind=.Integer};
        }
    case .LessLess;
        if left.kind == {
        case .Integer;
            return .{int_value=left.int_value << cast(u8, right.int_value.low), kind=.Integer};
        }
    case .GreaterGreater;
        if left.kind == {
        case .Integer;
            return .{int_value=left.int_value >> cast(u8, right.int_value.low), kind=.Integer};
        }
    }

    if node_for_debug {
        Panic(node_for_debug, "Invalid or unhandled case in constant eval (% % %)", left.kind, Token_Lexemes[op], right.kind);
    } else {
        Panic("Invalid or unhandled case in constant eval (% % %)", left.kind, Token_Lexemes[op], right.kind);
    }

    return .{};
}

ConstantEvaluate :: (value : ConstantValue, op : TokenKind, node_for_debug : *AstNode = null) -> ConstantValue {
    if op == {
    case .Minus;
        if value.kind == {
        case .Integer;
            return .{int_value=-value.int_value, kind=.Integer};
        case .Float;
            return .{float_value=-value.float_value, kind=.Float};
        }
    case .Bang;
        if value.kind == {
        case .Boolean;
            return .{bool_value=!value.bool_value, kind=.Boolean};
        }
    case .Caret;
        if value.kind == {
        case .Integer;
            return .{int_value=~value.int_value, kind=.Integer};
        }
    }

    if node_for_debug {
        Panic(node_for_debug, "Invalid or unhandled case in constant eval (% %)", Token_Lexemes[op], value.kind);
    } else {
        Panic("Invalid or unhandled case in constant eval (% %)", Token_Lexemes[op], value.kind);
    }

    return .{};
}

MakeConstantValue :: (token : Token, type_hint : *YalType) -> ConstantValue, *YalType, bool {
    if token.kind == {
    case .StringLiteral;
        val : ConstantValue;
        val.kind = .String;
        ok : bool;
        val.string_value, ok = ParseStringLiteral(token);

        return val, g_type_string, true;

    case .HereString;
        val : ConstantValue;
        val.kind = .String;
        ok : bool;
        val.string_value, ok = ParseHereString(token);

        return val, g_type_string, true;

    case .CharLiteral;
        val : ConstantValue;
        val.kind = .Integer;
        ok : bool;
        val.int_value, ok = ParseCharLiteral(token);

        type := ifx type_hint && UntypedIntegerValueCanImplicitlyCastTo(val, type_hint)
            then type_hint else g_type_s64;

        return val, type, true;

    case .IntLiteral;
        val : ConstantValue;
        val.kind = .Integer;
        ok : bool;
        val.int_value, ok = ParseIntLiteral(token);

        type := ifx type_hint && UntypedIntegerValueCanImplicitlyCastTo(val, type_hint)
            then type_hint else g_type_s64;

        if type.kind == .Float {
            int_value := val.int_value;
            val.kind = .Float;
            val.float_value = ToFloat64(val.int_value);
        }

        return val, type, true;

    case .FloatLiteral;
        val : ConstantValue;
        val.kind = .Float;
        ok : bool;
        val.float_value, ok = ParseFloatLiteral(token);

        type := ifx type_hint && type_hint.kind == .Float
            then type_hint else g_type_f32;

        return val, type, true;

    case .True;
        val : ConstantValue;
        val.kind = .Boolean;
        val.bool_value = true;

        return val, g_type_bool, true;

    case .False;
        val : ConstantValue;
        val.kind = .Boolean;
        val.bool_value = false;

        return val, g_type_bool, true;

    case .Null;
        val : ConstantValue;
        val.kind = .Pointer;
        val.pointer_value = 0;

        return val, g_type_void_ptr, true;

    case;
        Panic(token, "Invalid token kind % for literal", token.kind);
        return .{}, g_type_invalid, false;
    }

    Panic(token, "Invalid codepath (%)", token.kind);
    return .{}, g_type_invalid, false;
}

ParseHereString :: (token : Token) -> string, bool {
    str := TokenToString(token);
    if !StringStartsWith(str, "\"\"\"") {
        SyntaxError(token, "Here-string does not start with \"\"\"");
        return str, false;
    }

    str = StringAdvance(str, 3);

    ident := string.{data=str.data};
    while ident.count < str.count && str[ident.count] != #char "\r" && str[ident.count] != #char "\n" {
        ident.count += 1;
    }

    if ident.count == 0 {
        SyntaxError(token, "Here-string does not have an end ident");
        return str, false;
    }

    valid := true;
    str = StringAdvance(str, ident.count);
    if StringStartsWith(str, "\r\n") {
        str = StringAdvance(str, 2);
    } else if StringStartsWith(str, "\n") {
        str = StringAdvance(str, 1);
    } else {
        SyntaxError(token, "Expected a newline after here-string end identifier");
        valid = false;
    }

    str.count -= ident.count;
    if str.count < 0 {
        str.count = 0;
        return str, false;
    }

    if StringEndsWith(str, "\r\n") {
        str.count -= 2;
    } else if StringEndsWith(str, "\n") {
        str.count -= 1;
    } else {
        valid = false;
        SyntaxError(token, "Expected a newline before the end of here-string");
    }

    return str, valid;
}

ParseEscapeSequence :: (token : Token, str : string, byte_offset : *int) -> bool, utf8 : [4]u8, utf8_length : int, utf32 : u32 {
    utf8 : [4]u8;

    if byte_offset.* == str.count {
        SyntaxError(token, "Unfinished escape sequence at then end of this string literal");
        return false, utf8, 0, 0;
    }

    if str[byte_offset.*] == {
    case #char "\\";
        byte_offset.* += 1;
        utf8[0] = #char "\\";
        return true, utf8, 1, utf8[0];
    case #char "0";
        byte_offset.* += 1;
        utf8[0] = 0;
        return true, utf8, 1, utf8[0];
    case #char "t";
        byte_offset.* += 1;
        utf8[0] = #char "\t";
        return true, utf8, 1, utf8[0];
    case #char "n";
        byte_offset.* += 1;
        utf8[0] = #char "\n";
        return true, utf8, 1, utf8[0];
    case #char "r";
        byte_offset.* += 1;
        utf8[0] = #char "\r";
        return true, utf8, 1, utf8[0];
    case #char "'";
        byte_offset.* += 1;
        utf8[0] = #char "'";
        return true, utf8, 1, utf8[0];
    case #char "\"";
        byte_offset.* += 1;
        utf8[0] = #char "\"";
        return true, utf8, 1, utf8[0];

    case #char "x";
        byte_offset.* += 1;

        if byte_offset.* + 2 > str.count {
            SyntaxError(token, "Unfinished escape sequence at then end of this string literal");
            return false, utf8, 0, 0;
        }

        digits := string.{2, str.data + byte_offset.*};
        byte_offset.* += 2;

        value, ok, remainder := Basic.string_to_int(digits, base=16, T=u8);
        if !ok || remainder.count > 0 {
            SyntaxError(token, "Invalid \\x escape sequence in this string literal");
        }

        utf8[0] = value;
        return true, utf8, 1, utf8[0];

    case #char "u"; #through;
    case #char "U";
        escape := str[byte_offset.*];
        byte_offset.* += 1;

        num_digits := ifx escape == #char "u" then 4 else 8;
        if byte_offset.* + num_digits > str.count {
            SyntaxError(token, "Unfinished escape sequence at then end of this string literal");
            return false, utf8, 0, 0;
        }

        digits := string.{num_digits, str.data + byte_offset.*};
        byte_offset.* += num_digits;

        utf32, ok, remainder := Basic.string_to_int(digits, base=16, T=u32);
        if !ok || remainder.count > 0 {
            SyntaxError(token, "Invalid \\% escape sequence in this string literal", escape);
        }

        utf8_length := EncodeCharacterAsUtf8(utf32, utf8, 0);
        return true, utf8, utf8_length, utf32;

    case;
        SyntaxError(token, "Invalid escape sequence in string literal");
        InfoWithoutSourceCode(token, "Valid escape sequences are \\0, \\t, \\n, \\r, \\\\, \\', \\\", \\xhh, \\uhhhh, \\Uhhhhhhhh where h is a hexadecimal digit");
        return false, utf8, 0, 0;
    }
}

ParseStringLiteral :: (token : Token) -> string, bool {
    str := TokenToString(token);
    buffer : [..]u8;
    ArrayReserve(*buffer, str.count);
    index := 0;

    str.data += 1;
    str.count -= 2;

    escape := false;
    i := 0;
    while i < str.count {
        if str[i] == #char "\\" {
            i += 1;

            ok, utf8, utf8_length := ParseEscapeSequence(token, str, *i);
            if !ok {
                return cast(string, buffer), false;
            }

            for byte_index : 0..utf8_length - 1 {
                ArrayPush(*buffer, utf8[byte_index]);
            }
        } else {
            ArrayPush(*buffer, str[i]);
            i += 1;
        }
    }

    return cast(string, buffer), true;
}

ParseCharLiteral :: (token : Token) -> S128, bool {
    str := TokenToString(token);
    str.data += 1;
    str.count -= 2;

    if str.count == 0 {
        SyntaxError(token, "Invalid character literal");
        return ToS128(0), false;
    }

    if str[0] == #char "\\" {
        i := 1;
        ok, _, _, utf32 := ParseEscapeSequence(token, str, *i);
        if ok && i < str.count {
            SyntaxError(token, "Invalid character literal");
            ok = false;
        }

        return ToS128(utf32), ok;
    }

    if str.count != 1 {
        SyntaxError(token, "Invalid character literal");
        return ToS128(str[0]), false;
    }

    return ToS128(str[0]), true;
}

ParseIntLiteral :: (token : Token) -> S128, bool {
    CharToDigit :: inline (char : u8) -> int {
        if char >= #char "a" && char <= #char "f" {
            return 10 + char - #char "a";
        }

        if char >= #char "A" && char <= #char "F" {
            return 10 + char - #char "A";
        }

        return char - #char "0";
    }

    str := TokenToString(token);
    base := 10;
    if str.count > 2 {
        prefix := str;
        prefix.count = 2;
        if prefix == {
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

    result : S128;
    for i : 0..str.count - 1 {
        if str[i] == #char "_" {
            continue;
        }

        digit := CharToDigit(str[i]);
        result *= base;
        result += ToS128(digit);

        if result < ToS128(Math.S64_MIN) {
            Error(token, "Integer literal underflows minimum value of 64-bit signed integer");
            return result, false;
        }

        if result > ToS128(Math.U64_MAX) {
            Error(token, "Integer literal overflows maximum value of 64-bit unsigned integer");
            return result, false;
        }
    }

    return result, true;
}

ParseFloatLiteral :: (token : Token) -> float64, bool {
    TemporaryStorageScope();

    str_with_underscores := TokenToString(token);
    str := Alloc(u8, str_with_underscores.count);
    index := 0;

    for i : 0..str_with_underscores.count - 1 {
        if str_with_underscores[i] == #char "_" {
            continue;
        }

        str[index] = str_with_underscores[i];
        index += 1;
    }

    result, ok := Basic.string_to_float64(.{index, str});
    if !ok {
        SyntaxError(token, "Invalid float literal");
    }

    return result, ok;
}

using, only(.[
    "S128",
    "+", "-", "*", "/", "%",
    "<", ">", "<=", ">=", "==", "!",
    "|", "&", "^", "<<", ">>",
]) Basic;

ToS128 :: inline (a : $T) -> S128
#modify { return cast(*Type_Info, T).type == .INTEGER; } {
    #if #run type_info(T).signed {
        return .{low=cast,no_check(u64, a), high=cast(s64, a) >> 63};
    } else {
        return .{low=cast,no_check(u64, a), high=0};
    }
}

AppendS128 :: (builder : *StringBuilder, value : S128) {
    v := value;
    if v < ToS128(0) {
        StringBuilderAppendByte(builder, #char "-");
        v = -v;
    }

    counter := v;
    len := 0;
    while len == 0 || counter != ToS128(0) {
        len += 1;
        counter /= 10;
    }

    digits : [128]u8 = ---;

    Ten :: #run ToS128(10);
    for < i : 0..len - 1 {
        digit := (v % Ten).low;
        v /= 10;
        digits[i] = cast(u8, #char "0" + digit);
    }

    StringBuilderAppendString(builder, .{count=len, data=digits.data});
}

operator% :: (dividend: S128, divisor: S128) -> S128 {
    Assert(divisor != .{0,0}, "Division by 0");
    _, rem := inline Basic.signed_divide_with_remainder(dividend, divisor);
    return rem;
}

operator| :: inline (a : S128, b : S128) -> S128 {
    return .{low=a.low | b.low, high=a.high | b.high};
}

operator& :: inline (a : S128, b : S128) -> S128 {
    return .{low=a.low & b.low, high=a.high & b.high};
}

operator^ :: inline (a : S128, b : S128) -> S128 {
    return .{low=a.low ^ b.low, high=a.high ^ b.high};
}

operator~ :: inline (a : S128) -> S128 {
    return .{low=~a.low, high=~a.high};
}

ToS8 :: inline (v : S128) -> s8 {
    Assert(v >= ToS128(Math.S8_MIN) && v <= ToS128(Math.S8_MAX), "128-integer value is out of bounds when converting to a s8");
    return xx,no_check v.low;
}

ToS16 :: inline (v : S128) -> s16 {
    Assert(v >= ToS128(Math.S16_MIN) && v <= ToS128(Math.S16_MAX), "128-integer value is out of bounds when converting to a s16");
    return xx,no_check v.low;
}

ToS32 :: inline (v : S128) -> s32 {
    Assert(v >= ToS128(Math.S32_MIN) && v <= ToS128(Math.S32_MAX), "128-integer value is out of bounds when converting to a s32");
    return xx,no_check v.low;
}

ToS64 :: inline (v : S128) -> s64 {
    Assert(v >= ToS128(Math.S64_MIN) && v <= ToS128(Math.S64_MAX), "128-integer value is out of bounds when converting to a s64");
    return xx,no_check v.low;
}

ToU8 :: inline (v : S128) -> u8 {
    Assert(v >= .{0,0} && v <= ToS128(Math.U8_MAX), "128-integer value is out of bounds when converting to a u8");

    return xx,no_check v.low;
}

ToU16 :: inline (v : S128) -> u16 {
    Assert(v >= .{0,0} && v <= ToS128(Math.U16_MAX), "128-integer value is out of bounds when converting to a u16");

    return xx,no_check v.low;
}

ToU32 :: inline (v : S128) -> u32 {
    Assert(v >= .{0,0} && v <= ToS128(Math.U32_MAX), "128-integer value is out of bounds when converting to a u32");

    return xx,no_check v.low;
}

ToU64 :: inline (v : S128) -> u64 {
    Assert(v >= .{0,0} && v <= ToS128(Math.U64_MAX), "128-integer value is out of bounds when converting to a u64");

    return xx,no_check v.low;
}

ToFloat64 :: inline (value : S128) -> float64 {
    v := value;
    result : float64;
    if v < ToS128(0) {
        v = -v;
        result = -cast(float64, v.low);
    } else {
        result = cast(float64, v.low);
    }

    return result;
}

ToFloat32 :: inline (v : S128) -> float32 {
    return xx ToFloat64(v);
}

// Basic int 128 tests
#run {
    Assert(ToS8(ToS128(cast(s8, -1))) == -1);
    Assert(ToS16(ToS128(cast(s16, -1))) == -1);
    Assert(ToS32(ToS128(cast(s32, -1))) == -1);
    Assert(ToS64(ToS128(cast(s64, -1))) == -1);
}
