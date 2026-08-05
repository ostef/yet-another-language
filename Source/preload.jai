AddPreloadDeclaration :: (decl : *Code_Declaration) {
    ArrayPushUnique(*g_preload_declarations, decl);
}

#scope_file

g_preload_declarations : [..]*Code_Declaration;

Preload_Hard_Coded :: #string Yal
// This file was auto-generated when building the compiler
// CAUTION: You are not supposed to change this file!
Yal

AppendName :: (builder : *StringBuilder, name : string) {
    str := name;
    if StringStartsWith(str, "YalType") {
        str = SPrint("TypeInfo%", StringAdvance(str, "YalType".count));
    } else if StringStartsWith(str, "Yal") && str.count > "Yal".count {
        str = StringAdvance(str, "Yal".count);
    }

    Append(builder, "%", str);
}

Indent :: (builder : *StringBuilder, indent : int) {
    for i : 1..indent {
        Append(builder, "    ");
    }
}

NeedsSemicolon :: (node : *Code_Node) -> bool {
    if node.kind == {
    case .DECLARATION;
        decl := cast(*Code_Declaration, node);
        if !decl.expression {
            return true;
        }

        return decl.expression.kind != .STRUCT && decl.expression.kind != .ENUM;

    case .BLOCK;
        return false;

    case;
        return true;
    }
}

NeedsAdditionalNewline :: (node : *Code_Node) -> bool {
    if node.kind == {
    case .DECLARATION;
        decl := cast(*Code_Declaration, node);
        if decl.flags & .IS_CONSTANT {
            return true;
        }
    }

    return false;
}

IsDeclaration :: (node : *Code_Node) -> bool {
    if node.kind == .USING {
        using_node := cast(*Code_Using, node);
        return IsDeclaration(using_node.expression);
    }

    return node.kind == .DECLARATION || node.kind == .IDENT;
}

IsOpaqueDeclaration :: (node : *Code_Node) -> bool {
    if node.kind != .DECLARATION {
        return false;
    }

    decl := cast(*Code_Declaration, node);
    for decl.notes {
        if it.text == "PreloadOpaque" {
            return true;
        }
    }

    return false;
}

AppendExpr :: (builder : *StringBuilder, expr : *Code_Node, indent : int) {
    if !expr {
        return;
    }

    if expr.kind == {
    case .DECLARATION;
        AppendDeclaration(builder, xx expr, indent);

    case .IDENT;
        ident := cast(*Code_Ident, expr);
        AppendName(builder, ident.name);

    case .LITERAL;
        lit := cast(*Code_Literal, expr);
        if #complete lit.value_type == {
        case .NUMBER;

            if lit.value_flags & .FLOAT {
                Append(builder, "%", lit.values._float64);
            } else if lit.value_flags & .HEX {
                Append(builder, "0x%", FormatInt.{value=lit.values._u64, base=16});
            } else if lit.value_flags & .BINARY {
                Append(builder, "0b%", FormatInt.{value=lit.values._u64, base=2});
            } else if lit.value_flags & .MINUS_SIGN {
                Append(builder, "%", lit.values._s64);
            } else {
                Append(builder, "%", lit.values._u64);
            }

        case .BOOLEAN;
            if lit.values._u64 == 0 {
                Append(builder, "false");
            } else {
                Append(builder, "true");
            }

        case .POINTER;
            Append(builder, "null");

        case .STRING; #through;
        case .ARRAY; #through;
        case .STRUCT; #through;
        case .TYPE_INFO; #through;
        case .UNINITIALIZED;
            Panic("Unhandled literal kind %", lit.value_type);
        }

    case .BLOCK;
        block := cast(*Code_Block, expr);
        opaque_index := 0;
        Appendln(builder, "{");
        for block.statements {
            Indent(builder, indent + 1);

            if !IsDeclaration(it) {
                Append(builder, "// ");
            }

            if IsOpaqueDeclaration(it) {
                AppendOpaqueDeclaration(builder, xx it, opaque_index, indent + 1);
                opaque_index += 1;
            } else {
                AppendExpr(builder, it, indent + 1);
            }

            if NeedsSemicolon(it) {
                Append(builder, ";\n");
            } else {
                Append(builder, "\n");
            }

            if NeedsAdditionalNewline(it) {
                Append(builder, "\n");
            }
        }

        Indent(builder, indent);
        Append(builder, "}");

    case .STRUCT;
        struct_node := cast(*Code_Struct, expr);
        if struct_node.textual_flags & .UNION {
            Append(builder, "union ");
        } else {
            Append(builder, "struct ");
        }

        AppendExpr(builder, struct_node.block, indent);

    case .ENUM;
        enum_node := cast(*Code_Enum, expr);
        Append(builder, "enum ");
        if enum_node.internal_type_inst {
            AppendTypeInst(builder, enum_node.internal_type_inst, indent);
            Append(builder, " ");
        }

        AppendExpr(builder, enum_node.block, indent);

    case .USING;
        using_expr := cast(*Code_Using, expr);
        AppendExpr(builder, using_expr.expression, indent);

    case .BINARY_OPERATOR;
        binary := cast(*Code_Binary_Operator, expr);
        AppendExpr(builder, binary.left, indent);

        str : string;
        char : u8;
        if binary.operator_type <= 127 {
            char = xx binary.operator_type;
            str.data = *char;
            str.count = 1;
        } else {
            str = operator_to_string(binary.operator_type);
        }

        if binary.operator_type == {
        case #char ".";
            Append(builder, "%", str);
        case;
            Append(builder, " % ", str);
        }

        AppendExpr(builder, binary.right, indent);

    case .UNARY_OPERATOR;
        unary := cast(*Code_Unary_Operator, expr);

        str : string;
        char : u8;
        if unary.operator_type <= 127 {
            char = xx unary.operator_type;
            str.data = *char;
            str.count = 1;
        } else {
            str = operator_to_string(unary.operator_type);
        }

        if unary.operator_type == {
        case .POSTFIX_DEREFERENCE;
            AppendExpr(builder, unary.subexpression, indent);
            Append(builder, "%", str);

        case;
            Append(builder, "%", str);
            AppendExpr(builder, unary.subexpression, indent);
        }

    case .TYPE_INSTANTIATION;
        AppendTypeInst(builder, xx expr, indent);

    case .PROCEDURE_HEADER;
        proc := cast(*Code_Procedure_Header, expr);
        Append(builder, "func");
        if proc.procedure_flags & .C_CALL {
            Append(builder, " @call(\"C\") ");
        }

        Append(builder, "(");
        for proc.arguments {
            if it_index > 0 {
                Append(builder, ", ");
            }

            AppendFunctionParameter(builder, it, indent + 1);
        }
        Append(builder, ")");

        if proc.returns.count > 0 {
            Assert(proc.returns.count == 1, "Yal function only allow a single return value");

            Append(builder, " -> ");
            AppendFunctionParameter(builder, proc.returns[0], indent + 1);
        }

    case;
        Panic("Unhandled expr kind %", expr.kind);
    }
}

AppendTypeInst :: (builder : *StringBuilder, type_inst : *Code_Type_Instantiation, indent : int) {
    if type_inst.pointer_to {
        Append(builder, "*");
        AppendTypeInst(builder, type_inst.pointer_to, indent);
    } else if type_inst.array_element_type {
        Append(builder, "[");
        if type_inst.array_dimension {
            AppendExpr(builder, type_inst.array_dimension, indent);
        } else if type_inst.inst_flags & .RESIZABLE {
            Append(builder, "..");
        }

        Append(builder, "]");
        AppendTypeInst(builder, type_inst.array_element_type, indent);
    } else if type_inst.type_directive_target {
        Append(builder, "type_of(");
        AppendTypeInst(builder, type_inst.type_directive_target, indent);
        Append(builder, ")");
    } else {
        AppendExpr(builder, type_inst.type_valued_expression, indent);
    }
}

AppendOpaqueDeclaration :: (builder : *StringBuilder, decl : *Code_Declaration, index : int, indent := 0) {
    if decl.flags & .IS_CONSTANT {
        Append(builder, "const ");
    } else {
        Append(builder, "var ");
    }

    Append(builder, "reserved%: ", index);

    size := decl.type.runtime_size;
    if size % 8 == 0 {
        num_elems := size / 8;
        if num_elems == 1 {
            Append(builder, "u64");
        } else {
            Append(builder, "[%]u64", num_elems);
        }
    } else if size % 4 == 0 {
        num_elems := size / 4;
        if num_elems == 1 {
            Append(builder, "u32");
        } else {
            Append(builder, "[%]u32", num_elems);
        }
    } else if size % 2 == 0 {
        num_elems := size / 2;
        if num_elems == 1 {
            Append(builder, "u16");
        } else {
            Append(builder, "[%]u16", num_elems);
        }
    } else {
        num_elems := size;
        if num_elems == 1 {
            Append(builder, "u8");
        } else {
            Append(builder, "[%]u8", num_elems);
        }
    }
}

AppendFunctionParameter :: (builder : *StringBuilder, decl : *Code_Declaration, indent := 0) {
    AppendName(builder, decl.name);

    if decl.type_inst {
        if decl.name {
            Append(builder, ": ");
        }

        AppendTypeInst(builder, decl.type_inst, indent);
    }

    if decl.expression {
        Append(builder, " = ");
        AppendExpr(builder, decl.expression, indent);
    }
}

AppendDeclaration :: (builder : *StringBuilder, decl : *Code_Declaration, indent := 0) {
    if decl.flags & .IS_CONSTANT {
        Append(builder, "const ");
    } else {
        Append(builder, "var ");
    }

    AppendName(builder, decl.name);

    if decl.type_inst {
        Append(builder, ": ");
        AppendTypeInst(builder, decl.type_inst, indent);
    }

    if decl.expression {
        Append(builder, " = ");
        AppendExpr(builder, decl.expression, indent);
    }
}

#scope_export

GeneratePreloadFile :: () {
    QuickSort(g_preload_declarations, (a, b) => StringCompare(a.name, b.name));

    builder : StringBuilder;
    Appendln(*builder, Preload_Hard_Coded);

    for g_preload_declarations {
        AppendDeclaration(*builder, it);

        if NeedsSemicolon(it) {
            Append(*builder, ";\n");
        } else {
            Append(*builder, "\n");
        }

        if NeedsAdditionalNewline(it) {
            Append(*builder, "\n");
        }
    }

    write_entire_file("Source/preload.yal", *builder);
}
