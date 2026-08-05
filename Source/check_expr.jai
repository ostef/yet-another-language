EnsureTypeValue :: (using expr : *AstNode) -> bool {
    if type == g_type_invalid {
        return false;
    }

    if type != g_type_type_id {
        Error(expr, "Expression is not a type (it's %)", ToString(type));
        return false;
    }

    if semantic_meaning != .Constant {
        Error(expr, "Expression is not constant for type slot");
        return false;
    }

    Assert(expr, value.kind == .TemplateParam || value.kind == .TypeId, "Expected TypeId value but got %", value.kind);

    return true;
}

GetTypeHint :: (subexpr : DependencyNode.SubexpressionCommand) -> *YalType {
    Assert(subexpr.kind == .PushTypeHint);

    if subexpr.type_hint.type_ptr {
        return subexpr.type_hint.type_ptr.*;
    }

    if subexpr.type_hint.callback {
        return subexpr.type_hint.callback(subexpr.type_hint.callback_node, subexpr.type_hint.callback_index);
    }

    return null;
}

GetSubexpressionTypeHint :: (dep : *DependencyNode, index : int) -> *YalType, has_type_hint : bool {
    type_hint_stack : [..]*YalType;
    if dep.type_hint {
        ArrayPush(*type_hint_stack, dep.type_hint.*);
    }

    for i : 0..index - 1 {
        it := dep.subexpression_commands[i];

        if it.kind == {
        case .PushTypeHint;
            hint := GetTypeHint(it);
            ArrayPush(*type_hint_stack, hint);

        case .PopTypeHint;
            ArrayPop(*type_hint_stack);
        }
    }

    return ifx type_hint_stack.count > 0 then ArrayTop(type_hint_stack).*, type_hint_stack.count > 0;
}

CheckSubexpressions :: (dep : *DependencyNode) {
    DbgInfo(.Checking, dep.ast_node, "Checking all subexpressions");

    node := dep.ast_node;

    prev_expr := context.check.enclosing_expr;
    defer context.check.enclosing_expr = prev_expr;
    context.check.enclosing_expr = node;

    if node.flags & .StatementLevelExpression {
        CheckStatementLevel(node);
    }

    prev_type_hint := context.check.type_hint;
    defer context.check.type_hint = prev_type_hint;

    if dep.type_hint {
        context.check.type_hint = dep.type_hint.*;
    }

    type_hint_stack : [..]*YalType;
    for dep.subexpression_commands {
        if #complete it.kind == {
        case .PushTypeHint;
            hint := GetTypeHint(it);
            ArrayPush(*type_hint_stack, hint);
            context.check.type_hint = hint;

            DbgInfo(.Checking, node, "Type hint: %", ToString(hint));

        case .PopTypeHint;
            ArrayPop(*type_hint_stack);

            if type_hint_stack.count > 0 {
                hint := ArrayTop(type_hint_stack).*;
                context.check.type_hint = hint;
            } else {
                context.check.type_hint = prev_type_hint;
            }

        case .CheckExpression;
            if it_index <= dep.last_checked_subexpression {
                continue;
            }

            if !CheckSubexpression(it.expr) {
                DbgInfo(.Checking, it.expr, "Could not check this expression");
                return;
            }

            dep.last_checked_subexpression = xx it_index;
        }
    }

    if IsExpression(node.kind) && !CheckSubexpression(node) {
        DbgInfo(.Checking, node, "Could not check this expression");
        return;
    }

    dep.check_status = .Checked;

    if node.flags & .Using && node.type && node.type != g_type_invalid {
        accessed_scope := GetAccessedScope(node);

        if accessed_scope {
            ImportScope(node.enclosing_scope, accessed_scope, node);
        }
    }
}

GetAccessedScope :: (expr : *AstNode) -> *Scope, has_scope : bool {
    if !expr.type || expr.type == g_type_invalid {
        return null, true;
    }

    if expr.type.kind == {
    case .Struct; #through;
    case .Enum; #through;
    case .String; #through;
    case .Array; #through;
    case .Pointer;
        scope := GetAccessedScope(expr.enclosing_scope.program, expr.type);
        return scope, scope != null;

    case .Module;
        if expr.value.kind == .Module {
            return expr.value.module.scope, true;
        }

    case .TypeId;
        if expr.value.kind == .TypeId {
            type := expr.value.type_value;

            if type.kind == {
            case .Struct;
                type_struct := cast(*YalTypeStruct, type);
                return type_struct.node.body.scope, true;
            case .Enum;
                type_enum := cast(*YalTypeEnum, type);
                return type_enum.node.body.scope, true;
            }
        }
    }

    return null, false;
}

GetAccessedScope :: (program : *YalProgram, type : *YalType) -> *Scope {
    if type.kind == {
    case .Pointer;
        type_pointer := cast(*YalTypePointer, type);
        if type_pointer.pointed_type.kind != .Struct {
            return null;
        }

        return GetAccessedScope(program, type_pointer.pointed_type);
    case .Struct;
        type_struct := cast(*YalTypeStruct, type);
        return type_struct.node.body.scope;
    case .Enum;
        type_enum := cast(*YalTypeEnum, type);
        return type_enum.node.body.scope;
    }

    return null;
}

CheckSubexpression :: (expr : *AstNode) -> should_continue : bool {
    DbgInfo(.Checking, expr, "Checking subexpression");

    // Under certain circumstances (like enums and struct), the type has already been assigned
    // in the dependency collection phase, so make sure we don't reassign it here
    if !expr.type {
        expr.type = g_type_invalid;
    }

    // defer if expr.type != g_type_invalid {
    //     Assert(expr, expr.semantic_meaning != .Invalid, "This expression has been checked but has invalid semantic meaning");
    // }

    if expr.kind == {
    case .Identifier;
        ident := cast(*AstIdentifier, expr);

        if !ident.symbol && !(ident.ident_flags & .DoNotResolve) && !(ident.ident_flags & .ResolvedToPrimitiveTypeField) && !(ident.ident_flags & .TemplateParam) {
            return false;
        }

        CheckIdentifier(ident);

    case .Context;
        context_decl := expr.enclosing_scope.program.context_declaration;
        Assert(context_decl, context_decl.value.kind == .TypeId, "Does not declare a type id");

        expr.semantic_meaning = .Mutable;
        expr.type = context_decl.value.type_value;

    case .Binary;
        CheckBinary(xx expr);
    case .Unary;
        CheckUnary(xx expr);
    case .Literal;
        CheckLiteral(xx expr);
    case .StructLiteral;
        CheckStructLiteral(xx expr);
    case .FunctionCall;
        return CheckFunctionCall(xx expr);
    case .Subscript;
        CheckSubscript(xx expr);
    case .FieldAccess;
        CheckFieldAccess(xx expr);
    case .Cast;
        CheckCast(xx expr);
    case .SizeOf;
        CheckSizeOf(xx expr);
    case .TypeOf;
        CheckTypeOf(xx expr);
    case .Struct;
        CheckStruct(xx expr);
    case .Enum;
        CheckEnum(xx expr);
    case .Function;
        CheckFunctionSignature(xx expr);
    case .FunctionOverloadSet;
        CheckFunctionOverloadSet(xx expr);

    case .TypePointer;
        type_pointer := cast(*AstTypePointer, expr);

        if !EnsureTypeValue(type_pointer.pointed_type) {
            return false;
        }

        expr.type = g_type_type_id;
        expr.semantic_meaning = .Constant;
        expr.value = .{kind=.TypeId, type_value=MakeTypePointer(type_pointer.pointed_type.value.type_value, expr)};

    case .TypeArray;
        type_array := cast(*AstTypeArray, expr);

        if !EnsureTypeValue(type_array.element_type) {
            return false;
        }

        array_count := -1;
        if type_array.element_count {
            count := type_array.element_count;

            if count.type == g_type_invalid {
                return false;
            }

            if count.type.kind != .Integer {
                Error(count, "Array count must be a positive constant integer");
                return false;
            }

            if count.semantic_meaning != .Constant {
                Error(count, "Array count must be constant");
                return false;
            }

            Assert(count, count.value.kind == .Integer, "Expected integer for constant value, got %", count.value);

            if count.value.int_value < ToS128(0) {
                Error(count, "Array count must be a positive integer (is %)", count.value.int_value);
                return false;
            }

            if count.value.int_value > ToS128(Math.S64_MAX) {
                Error(count, "Array count exceeds maximum value of s64 (is %)", count.value.int_value);
                return false;
            }

            array_count = cast,no_check(s64, count.value.int_value.low);
        }

        expr.type = g_type_type_id;
        expr.semantic_meaning = .Constant;
        expr.value = .{kind=.TypeId, type_value=MakeTypeArray(type_array.array_kind, type_array.element_type.value.type_value, array_count, expr)};

    case .TypePrimitive;
        type_primitive := cast(*AstTypePrimitive, expr);

        expr.type = g_type_type_id;
        expr.semantic_meaning = .Constant;

        if type_primitive.primitive_kind == {
        case .S8;     expr.value = .{kind=.TypeId, type_value=g_type_s8};
        case .U8;     expr.value = .{kind=.TypeId, type_value=g_type_u8};
        case .S16;    expr.value = .{kind=.TypeId, type_value=g_type_s16};
        case .U16;    expr.value = .{kind=.TypeId, type_value=g_type_u16};
        case .S32;    expr.value = .{kind=.TypeId, type_value=g_type_s32};
        case .U32;    expr.value = .{kind=.TypeId, type_value=g_type_u32};
        case .S64;    expr.value = .{kind=.TypeId, type_value=g_type_s64};
        case .U64;    expr.value = .{kind=.TypeId, type_value=g_type_u64};
        case .Int;    expr.value = .{kind=.TypeId, type_value=g_type_s64};
        case .Uint;   expr.value = .{kind=.TypeId, type_value=g_type_u64};
        case .Float;  expr.value = .{kind=.TypeId, type_value=g_type_f32};
        case .F32;    expr.value = .{kind=.TypeId, type_value=g_type_f32};
        case .F64;    expr.value = .{kind=.TypeId, type_value=g_type_f64};
        case .Bool;   expr.value = .{kind=.TypeId, type_value=g_type_bool};
        case .String; expr.value = .{kind=.TypeId, type_value=g_type_string};
        case .Void;   expr.value = .{kind=.TypeId, type_value=g_type_void};
        case .TypeId; expr.value = .{kind=.TypeId, type_value=g_type_type_id};
        case;
            Panic(expr, "Invalid primitive type %", type_primitive.primitive_kind);
        }

    case .Run;
        CheckRun(xx expr);

    case .Import;
        CheckImport(xx expr);

    case .Range;
        CheckRange(xx expr);

    case .Argument;
        arg := cast(*AstArgument, expr);
        arg.type = arg.expr.type;
        arg.semantic_meaning = arg.expr.semantic_meaning;
        arg.value = arg.expr.value;

    case;
        Panic(expr, "Invalid or unhandled expression kind (%)", expr.kind);
    }

    return true;
}

CheckFunctionSignature :: (using func : *AstFunction) {
    EnsureNotChecked(func);

    decl_modifiers : DeclarationModifiers;
    if decl {
        CheckDeclarationAttributes(*decl_modifiers, decl.attributes);
        CheckDeclarationAttributes(*decl_modifiers, decl.inherited_attributes);
    }

    CheckDeclarationAttributes(*decl_modifiers, attributes);
    CheckDeclarationAttributes(*decl_modifiers, inherited_attributes);

    PostCheckDeclarationModifiers(*decl_modifiers);

    calling_convention = decl_modifiers.function_calling_convention;

    if decl_modifiers.flags & .External {
        is_external = true;
    }

    library_name = decl_modifiers.library_name;
    symbol_name = decl_modifiers.symbol_name;

    if is_c_variadic && calling_convention != .C {
        Error(func, "Expected C calling convention for C variadic function but got %", calling_convention);
    }

    if calling_convention == .C && body != null {
        Error(func, "Cannot implement functions with the C calling convention");
    }

    type = g_type_invalid;
    semantic_meaning = .Constant;
    value = .{kind=.Function, function_node=func};

    found_optional_param := false;
    parameter_types : [..]*YalType;
    for parameters {
        // if it.type == g_type_invalid {
        //     return;
        // }

        Assert(it, it.type != null, "Type is null");
        if it.decl_kind != .TemplateParam {
            ArrayPush(*parameter_types, it.type);
        }

        if it.expr {
            found_optional_param = true;

            if it.expr.semantic_meaning != .Constant {
                Error(it.expr, "Function parameter default value should be constant", it.expr.semantic_meaning);
            }

            if is_c_variadic {
                Error(it, "C variadic functions cannot have optional parameters");
            }
        } else if found_optional_param {
            Error(it, "All parameters after the first optional parameter must also be optional");
        }
    }

    result_type : *YalType;
    if result {
        Assert(result, result.type != null, "Type is null");

        // if result.type == g_type_invalid {
        //     return;
        // }

        result_type = result.type;
    } else {
        result_type = g_type_void;
    }

    type = MakeTypeFunction(parameter_types, result_type, calling_convention, is_c_variadic);

    if decl {
        SetDeclarationType(decl, type);
        decl.value = value;

        if decl == scope.program.entry_point_declaration {
            CheckEntryPointSignature(func);
        }
    }
}

CheckFunctionOverloadSet :: (using set : *AstFunctionOverloadSet) {
    EnsureNotChecked(set);

    decl_modifiers : DeclarationModifiers;
    if decl {
        CheckDeclarationAttributes(*decl_modifiers, decl.attributes);
        CheckDeclarationAttributes(*decl_modifiers, decl.inherited_attributes);
    }

    CheckDeclarationAttributes(*decl_modifiers, attributes);
    CheckDeclarationAttributes(*decl_modifiers, inherited_attributes);

    PostCheckDeclarationModifiers(*decl_modifiers);

    type = g_type_invalid;
    semantic_meaning = .Constant;
    value = .{kind=.FunctionOverloadSet, overload_set=.{node=set}};

    overloads : [..]*AstNode;
    overload_types : [..]*YalTypeFunction;
    ArrayReserve(*overload_types, body.scope.all_statements.count);

    DbgPrintln(.Checking, "Generating function overload set");

    for body.scope.all_statements {
        if it.kind == {
        case .Insert; #through;
        case .Run;
            continue;

        case .If;
            if_stmt := cast(*AstIf, it);
            if if_stmt.is_compile_time {
                continue;
            }
        }

        if it.value.kind != .Function {
            Error(it, "Expected a constant function for overload set");
            continue;
        }

        Assert(it, it.value.function_node != null, "Function is null");

        DbgPrintln(.Checking, "  overload type %", ToString(it.value.function_node.type));
        ArrayPush(*overload_types, xx it.value.function_node.type);
        ArrayPush(*overloads, xx it);
    }

    type = MakeTypeFunctionOverloadSet(set, overload_types);
    final_overloads = overloads;

    if decl {
        SetDeclarationType(decl, type);
        decl.value = value;
    }
}

CheckStruct :: (using node : *AstStruct) {
    EnsureNotChecked(node);

    Assert(node, defined_type != null, "Struct defined type should have been created and set during the dependency collection phase");

    type = g_type_type_id;
    semantic_meaning = .Constant;
    value = .{kind=.TypeId, type_value=defined_type};

    parameter_types : [..]*YalType;
    ArrayReserve(*parameter_types, template_params.count);

    for template_params {
        DbgPrintln(.Checking, "  param %", ToString(it.decl.type));
        ArrayPush(*parameter_types, it.decl.type);
    }

    defined_type.parameters = parameter_types;

    if IsStructTemplate(node) {
        default_value = .{type=defined_type};

        return;
    }

    default_values : [..]ConstantValue;
    ArrayReserve(*default_values, body.scope.all_statements.count);

    members : [..]YalTypeStructMember;
    ArrayReserve(*members, body.scope.all_statements.count);

    DbgPrintln(.Checking, "Generating struct type '%'", defined_type.name);

    max_alignment := 1;
    member_byte_offset := 0;
    size := 0;
    for body.scope.all_statements {
        if it.kind != .Declaration {
            continue;
        }

        member_decl := cast(*AstDeclaration, it);
        if member_decl.decl_kind != .Variable {
            continue;
        }

        if member_decl.identifier {
            if member_decl.type == g_type_invalid {
                return;
            }

            Assert(member_decl, member_decl.type != null, "Type is null");

            member_default_value := ArrayPush(*default_values);
            if member_decl.expr {
                member_default_value.* = member_decl.expr.value;
            }

            alignment := GetTypeAlignment(member_decl.type);
            max_alignment = Max(max_alignment, alignment);

            member := ArrayPush(*members);
            member.node = member_decl;
            member.name = member_decl.identifier.name;
            member.byte_offset = AlignForward(member_byte_offset, alignment);
            member.type = member_decl.type;

            DbgPrintln(.Checking, "  % : % (offset %, % bytes)", member.name, ToString(member.type), member.byte_offset, member.type.size);

            Assert(member_decl.identifier, member_decl.type.size != -1, "When generating struct type, this member was not sized");

            if is_union {
                size = Max(size, member.byte_offset + member.type.size);
            } else {
                member_byte_offset = member.byte_offset + member_decl.type.size;
                size = member.byte_offset + member_decl.type.size;
            }
        }
    }

    defined_type.members = members;
    defined_type.size = AlignForward(size, max_alignment);
    defined_type.alignment = xx max_alignment;

    if template_source {
        defined_type.template_source = template_source.defined_type;
    }

    default_value = .{type=defined_type, values=default_values};

    DbgPrintln(.Checking, "Final size=%, alignment=%", defined_type.size, defined_type.alignment);
}

CheckEnum :: (using node : *AstEnum) {
    EnsureNotChecked(node);

    Assert(node, defined_type != null, "Enum defined type should have been created and set during the dependency collection phase");
    Assert(node, semantic_meaning == .Constant, "Enum should have been assigned a semantic meaning during the dependency collection phase");
    Assert(node, value.kind == .TypeId, "Enum should have been assigned a value during the dependency collection phase");
    Assert(node, type == g_type_type_id, "Enum should have been assigned type type_id during the dependency collection phase (type is %)", ToString(type));

    type_base_type : *YalType;
    if base_type {
        if !EnsureTypeValue(base_type) {
            return;
        }

        type_base_type = base_type.value.type_value;
    } else {
        type_base_type = g_type_s64;
    }

    if type_base_type.kind != .Integer {
        Error(base_type, "Invalid type for enum base type. Should be an integer but got %", ToString(type_base_type));

        // Set base type to something valid so this error does not cascade
        type_base_type = g_type_s64;
    }

    Assert(node, defined_type.base_type == null, "Enum type base type should not be set yet");
    defined_type.base_type = xx type_base_type;
    defined_type.size = type_base_type.size;

    members : [..]YalTypeEnumMember;
    ArrayReserve(*members, body.scope.all_statements.count);

    i := 0;
    for body.scope.all_statements {
        if it.kind != .Declaration {
            continue;
        }

        if it.type == g_type_invalid {
            continue;
        }

        member_decl := cast(*AstDeclaration, it);
        Assert(member_decl, member_decl.identifier != null, "Enum member have no identifier");
        Assert(member_decl, member_decl.value.kind == .Integer, "Enum member has non integer value");

        member := ArrayPush(*members);
        member.name = member_decl.identifier.name;
        member.value = cast,no_check(s64, member_decl.value.int_value.low);
    }

    defined_type.members = members;
}

CheckEnumMember :: (using decl : *AstDeclaration) {
    body := cast(*AstBlock, decl.enclosing_scope.statement);
    Assert(decl, body != null, "Body is null");
    Assert(body, body.kind == .Block, "Expected a block as enum body");

    enum_node := body.parent_enum;
    Assert(enum_node, enum_node.kind == .Enum, "Expected an enum");

    Assert(decl, enum_node.defined_type != null, "Enum defined type is null");
    type = enum_node.defined_type;

    if expr {
        if expr.type == g_type_invalid {
            type = g_type_invalid;
            return;
        }

        value = .{int_value=ToS128(0), kind=.Integer};

        base_type : *YalType;
        if enum_node.base_type {
            base_type = enum_node.base_type.value.type_value;
            Assert(enum_node.base_type, base_type != null, "The enum base type node has not been checked yet");
        } else {
            base_type = g_type_s64;
        }

        if expr.semantic_meaning != .Constant {
            Error(expr, "Assigning non constant expression to enum value");
            return;
        }

        if expr.value.kind != .Integer {
            Error(expr, "Expected an integer constant value for enum member assignment");
            return;
        }

        if !UntypedIntegerValueCanImplicitlyCastTo(expr.value, base_type) {
            Error(expr, "This integer value does not fit into a % (value is %)", ToString(base_type), expr.value.int_value);
            return;
        }

        value = expr.value;
    } else {
        statement_index := GetStatementIndex(body, decl);
        if statement_index > 0 {
            prev_enum_member := body.statements[statement_index - 1];
            value = .{int_value=prev_enum_member.value.int_value + ToS128(1), kind=.Integer};
        } else {
            value = .{int_value=ToS128(0), kind=.Integer};
        }
    }
}

CheckLogicalComposition :: (using binary : *AstBinary) {
    Assert(binary, op.kind == .AmpersandAmpersand || op.kind == .PipePipe, "Invalid op");

    if !ExprCanImplicitlyCastTo(left, g_type_bool, null, "logical operator", is_binary_expr=false)
    || !ExprCanImplicitlyCastTo(right, g_type_bool, null, "logical operator", is_binary_expr=false) {
        return;
    }

    type = g_type_bool;

    if left.semantic_meaning == .Constant && right.semantic_meaning == .Constant {
        semantic_meaning = .Constant;
        lhs := ConstantCast(left.value, g_type_bool);
        rhs := ConstantCast(right.value, g_type_bool);
        value = ConstantEvaluate(lhs, rhs, op, binary);
    } else {
        semantic_meaning = .Value;
    }
}

CheckEquality :: (using binary : *AstBinary) {
    Assert(binary, op.kind == .EquEqu || op.kind == .BangEqu, "Invalid op");

    if !ExprCanImplicitlyCastTo(right, left, "comparison") {
        return;
    }

    type = g_type_bool;
    if left.semantic_meaning == .Constant && right.semantic_meaning == .Constant {
        semantic_meaning = .Constant;
        rhs := ConstantCast(right.value, left.type);
        value = ConstantEvaluate(left.value, rhs, op, binary);
    } else {
        semantic_meaning = .Value;
    }
}

CheckArithmeticComparison :: (using binary : *AstBinary) {
    Assert(binary, op.kind == .Less || op.kind == .LessEqu || op.kind == .Greater || op.kind == .GreaterEqu, "Invalid op");

    if left.type.kind != .Integer && left.type.kind != .Float {
        Error(binary, "Invalid type for comparison (left is: %, right is: %)", ToString(left.type), ToString(right.type));
        return;
    }

    if !ExprCanImplicitlyCastTo(right, left, "comparison") {
        return;
    }

    type = g_type_bool;

    if left.semantic_meaning == .Constant && right.semantic_meaning == .Constant {
        semantic_meaning = .Constant;
        rhs := ConstantCast(right.value, left.type);
        value = ConstantEvaluate(left.value, rhs, op, binary);
    } else {
        semantic_meaning = .Value;
    }
}

CheckBitOperation :: (using binary : *AstBinary) {
    Assert(binary,
        op.kind == .Pipe || op.kind == .Ampersand || op.kind == .Caret
        || op.kind == .PipeEqu || op.kind == .AmpersandEqu || op.kind == .CaretEqu
        || op.kind == .LessLess || op.kind == .GreaterGreater
        || op.kind == .LessLessEqu || op.kind == .GreaterGreaterEqu,
        "Invalid op"
    );

    if left.type.kind != .Integer {
        Error(binary, "Invalid type for bit operation (left is: %, right is: %)",
            ToString(left.type), ToString(right.type));
        return;
    }

    if !ExprCanImplicitlyCastTo(right, left, "bit operation") {
        return;
    }

    type = left.type;

    if left.semantic_meaning == .Constant && right.semantic_meaning == .Constant {
        semantic_meaning = .Constant;
        rhs := ConstantCast(right.value, left.type);
        value = ConstantEvaluate(left.value, rhs, op, binary);
    } else {
        semantic_meaning = .Value;
    }
}

CheckModulo :: (using binary : *AstBinary) {
    Assert(binary, op.kind == .Percent || op.kind == .PercentEqu, "Invalid op");

    if left.type.kind != .Integer {
        Error(binary, "Invalid type for operator % (left is: %, right is: %)",
            Token_Names[op.kind], ToString(left.type), ToString(right.type));
        return;
    }

    if !ExprCanImplicitlyCastTo(right, left, "operator %") {
        return;
    }

    type = left.type;

    if left.semantic_meaning == .Constant && right.semantic_meaning == .Constant {
        semantic_meaning = .Constant;
        rhs := ConstantCast(right.value, left.type);
        value = ConstantEvaluate(left.value, rhs, op, binary);
    } else {
        semantic_meaning = .Value;
    }
}

CheckPointerArithmeticOperation :: (using binary : *AstBinary) {
    type_pointer := cast(*YalTypePointer) left.type;
    if type_pointer.pointed_type.kind == .Void {
        Error(binary, "Cannot perform pointer arithmetic on *void");
        return;
    }

    if binary.op.kind == {
    case .Plus; #through;
    case .PlusEqu; #through;
    case .Minus; #through;
    case .MinusEqu;

    case;
        Error(binary, "Invalid type for arithmetic operation (left is: %, right is: %)",
            ToString(left.type), ToString(right.type));
        return;
    }

    if right.type.kind != .Integer {
        Error(binary, "Invalid type for arithmetic operation (left is: %, right is: %)",
            ToString(left.type), ToString(right.type));
        return;
    }

    type = left.type;

    /* @Todo
    if left.semantic_meaning == .Constant && right.semantic_meaning == .Constant {
        semantic_meaning = .Constant;
        value = ConstantEvaluate(left.value, right.value, op, binary);
    } else */
    {
        semantic_meaning = .Value;
    }
}

CheckArithmeticOperation :: (using binary : *AstBinary) {
    EnsureNotChecked(binary);

    Assert(binary,
        op.kind == .Plus || op.kind == .Minus || op.kind == .Star || op.kind == .Slash
        || op.kind == .PlusEqu || op.kind == .MinusEqu || op.kind == .StarEqu || op.kind == .SlashEqu,
        "Invalid op"
    );

    if left.type.kind == .Pointer {
        CheckPointerArithmeticOperation(binary);
        return;
    }

    if left.type.kind != .Integer && left.type.kind != .Float {
        Error(binary, "Invalid type for arithmetic operation (left is: %, right is: %)",
            ToString(left.type), ToString(right.type));
        return;
    }

    if !ExprCanImplicitlyCastTo(right, left, "arithmetic operation") {
        return;
    }

    type = left.type;

    if left.semantic_meaning == .Constant && right.semantic_meaning == .Constant {
        semantic_meaning = .Constant;
        rhs := ConstantCast(right.value, left.type);
        value = ConstantEvaluate(left.value, rhs, op, binary);
    } else {
        semantic_meaning = .Value;
    }
}

CheckRange :: (using range_expr : *AstRange) {
    if start.type.kind != .Integer {
        Error(start, "Invalid type for range, expected an integer but got %", ToString(start.type));
        return;
    }

    if end.type.kind != .Integer {
        Error(end, "Invalid type for range, expected an integer but got %", ToString(end.type));
        return;
    }

    if !ExprCanImplicitlyCastTo(end, start, "range") {
        return;
    }

    type = start.type;
    semantic_meaning = .Value;
}

CheckBinary :: (using binary : *AstBinary) {
    EnsureNotChecked(binary);

    type = g_type_invalid;

    if left.type == g_type_invalid || right.type == g_type_invalid {
        return;
    }

    if op.kind == {
    case .PipePipe; #through;
    case .AmpersandAmpersand;
        CheckLogicalComposition(binary);

    case .EquEqu; #through;
    case .BangEqu;
        CheckEquality(binary);

    case .Less; #through;
    case .LessEqu; #through;
    case .Greater; #through;
    case .GreaterEqu;
        CheckArithmeticComparison(binary);

    case .Pipe; #through;
    case .Caret; #through;
    case .Ampersand; #through;
    case .LessLess; #through;
    case .GreaterGreater;
        CheckBitOperation(binary);

    case .Plus; #through;
    case .Minus; #through;
    case .Star; #through;
    case .Slash;
        CheckArithmeticOperation(binary);

    case .Percent;
        CheckModulo(binary);

    case;
        Panic(op, "Invalid or unhandled binary operator");
        return;
    }

    if semantic_meaning == .Constant {
        Assert(binary, value.kind != .Invalid,
            "This constant expression did not get constant evaluated");
    }
}

CheckNegation :: (using unary : *AstUnary) {
    if expr.type.kind == {
    case .Integer;
        type_int := cast(*YalTypeInteger) expr.type;
        if !type_int.is_signed {
            Error(unary, "Cannot negate an unsigned integer (type is: %)", ToString(expr.type));
            return;
        }

        type = expr.type;

    case .Float;
        type = expr.type;
    case;
        Error(unary, "Invalid type for unary operator % (type is: %)", Token_Names[op.kind], ToString(expr.type));
        return;
    }

    if expr.semantic_meaning == .Constant {
        semantic_meaning = .Constant;
        value = ConstantEvaluate(expr.value, op, unary);
    } else {
        semantic_meaning = .Value;
    }
}

CheckLogicalNot :: (using unary : *AstUnary) {
    if expr.type.kind != .Bool {
        Error(unary, "Invalid type for unary operator % (type is: %)", Token_Names[op.kind], ToString(expr.type));
        return;
    }

    type = expr.type;

    if expr.semantic_meaning == .Constant {
        semantic_meaning = .Constant;
        value = ConstantEvaluate(expr.value, op, unary);
    } else {
        semantic_meaning = .Value;
    }
}

CheckBitNot :: (using unary : *AstUnary) {
    // For now we only allow integers to be bit operated on
    if expr.type.kind != .Integer {
        Error(unary, "Invalid type for unary operator % (type is: %, only integer types are allowed in bit operations)",
            Token_Names[op.kind], ToString(expr.type));
        return;
    }

    type = expr.type;

    if expr.semantic_meaning == .Constant {
        semantic_meaning = .Constant;
        value = ConstantEvaluate(expr.value, op, unary);
    } else {
        semantic_meaning = .Value;
    }
}

CheckAddressOf :: (using unary : *AstUnary) {
    is_function := expr.semantic_meaning == .Constant && expr.type.kind == .Function;
    if expr.semantic_meaning != .Mutable && !is_function {
        Error(unary, "Taking address of non-addressable expression");
        return;
    }

    semantic_meaning = .Value;
    type = MakeTypePointer(expr.type, unary);
}

CheckDeref :: (using unary : *AstUnary) {
    if expr.type.kind != .Pointer {
        Error(unary, "Expected a pointer for dereference but got %", ToString(expr.type));
        return;
    }

    if expr.semantic_meaning == .Constant {
        Error(unary, "Cannot dereference a constant");
        return;
    }

    semantic_meaning = .Mutable;
    type = (cast(*YalTypePointer) expr.type).pointed_type;
}

CheckUnary :: (using unary : *AstUnary) {
    EnsureNotChecked(unary);

    type = g_type_invalid;

    if expr.type == g_type_invalid {
        return;
    }

    if op.kind == {
    case .Minus;
        CheckNegation(unary);
    case .Bang;
        CheckLogicalNot(unary);
    case .Caret;
        CheckBitNot(unary);
    case .Ampersand;
        CheckAddressOf(unary);
    case .DotStar;
        CheckDeref(unary);
    case;
        Error(op, "Invalid or unhandled unary operator");
        return;
    }

    if semantic_meaning == .Constant {
        Assert(unary, value.kind != .Invalid, "It seems a constant unary operation did not get constant evaluated");
    }
}

CheckImplicitTemplateParamDecl :: (using ident : *AstIdentifier) {
    Assert(ident, symbol.decl.type == null, "Template param implicit declaration has already been checked");

    template_inst, value_index := GetTemplateParamDeclarationInfo(symbol.decl);

    semantic_meaning = .Constant;

    if context.check.type_hint {
        type = context.check.type_hint;

        if template_inst {
            value = template_inst.template_arguments[value_index];
        } else {
            value = .{kind=.TemplateParam};
        }
    } else {
        type = g_type_type_id;

        if template_inst {
            value = template_inst.template_arguments[value_index];
        } else {
            value = .{kind=.TypeId, type_value=MakeTypeTemplateParam(name, value_index)};
        }
    }

    SetDeclarationType(symbol.decl, type);
    symbol.decl.value = value;
}

CheckIdentifier :: (using ident : *AstIdentifier) {
    EnsureNotChecked(ident);

    if (ident_flags & .DoNotResolve) || (ident_flags & .ResolvedToPrimitiveTypeField) {
        return;
    }

    Assert(ident, enclosing_scope != null, "Enclosing scope is not set");
    Assert(ident, symbol != null, "Symbol '%' is not set", name);

    if (ident_flags & .TemplateParam) {
        CheckImplicitTemplateParamDecl(ident);
        return;
    }

    Assert(symbol.decl, symbol.decl.type != null, "Declaration is not checked (type is null)");

    type = symbol.decl.type;

    if #complete symbol.kind == {
    case .Invalid;
    case .Variable;
        semantic_meaning = .Mutable;

    case .TemplateParam; #through;
    case .Constant;
        semantic_meaning = .Constant;
        value = symbol.decl.value;
    }

    if ident_flags & .FieldAccessRHS {
        return;
    }

    value_decl : *AstDeclaration;
    if imported_symbol {
        if imported_symbol.source_using.kind == {
        case .Declaration;
            value_decl = xx imported_symbol.source_using;

        case .Identifier;
            using_ident := cast(*AstIdentifier, imported_symbol.source_using);
            if !using_ident.symbol {
                return;
            }

            value_decl = using_ident.symbol.decl;

        case;
            Error(imported_symbol.source_using, "Only identifiers or declarations are handled for now");
            return;
        }
    } else {
        value_decl = symbol.decl;
    }

    implicit_decl := value_decl.identifier != null && (value_decl.identifier.ident_flags & .ImplicitDeclaration) != 0;

    show_decl := false;
    defer if show_decl {
        Info(value_decl, "Here is the declaration of '%'", ident.name);
    }

    // Check use before declared and use of variable from outer stack frame
    // Looks ugly because we do lots of asserts, but we simply walk up the scope tree until we find the statement that
    // the identifier is nested in, and that is in the same scope as the declaration. Then we check the statement's
    // index in the scope's statements array and compare that with the declaration's.
    // @Todo: we only do the checking if the declaration is not implicit, because currently only template params
    // can have this flag. In the future there might be situations where that causes problems
    if !implicit_decl && symbol.kind == .Variable && !IsTopLevelScope(value_decl.enclosing_scope) {
        Assert(ident, parent_statement != null, "parent_statement is null");

        ancestor_node_in_decl_scope := ident.parent_statement;
        while ancestor_node_in_decl_scope && ancestor_node_in_decl_scope.enclosing_scope && ancestor_node_in_decl_scope.enclosing_scope != value_decl.enclosing_scope {
            if ancestor_node_in_decl_scope.enclosing_scope.kind != .Statement {
                Error(ident, "Accessing a variable from an outer stack frame");
                show_decl = true;
                return;
            }

            ancestor_node_in_decl_scope = ancestor_node_in_decl_scope.enclosing_scope.statement;
        }

        Assert(ident, ancestor_node_in_decl_scope != null, "Identifier refers to a declaration in a parent scope, but we did not find it when walking up the scope tree");
        Assert(ident, ancestor_node_in_decl_scope.enclosing_scope == value_decl.enclosing_scope, "Identifier refers to a declaration in a parent scope, but we did not find it when walking up the scope tree");

        decl_statement_index := ArrayFindFirst(value_decl.enclosing_scope.all_statements, value_decl);
        Assert(value_decl, decl_statement_index >= 0, "Could not find node inside the enclosing scope's statements array");

        ident_statement_index := ArrayFindFirst(ancestor_node_in_decl_scope.enclosing_scope.all_statements, ancestor_node_in_decl_scope);
        Assert(ident, ident_statement_index >= 0, "Could not find ancestor statement node inside the declaration's enclosing scope's statements array");

        if decl_statement_index >= ident_statement_index {
            Error(ident, "Identifier '%' is used before it is declared", ident.name);
            show_decl = true;
            return;
        }
    }
}

CheckLiteral :: inline (using lit : *AstLiteral) {
    EnsureNotChecked(lit);

    semantic_meaning = .Constant;
    value, type = MakeConstantValue(.{range=range, kind=literal_kind}, context.check.type_hint);
}

CheckStructLiteral :: (using lit : *AstStructLiteral) {
    EnsureNotChecked(lit);

    type = g_type_invalid;

    if !type_node {
        if !context.check.type_hint {
            Error(lit, "Cannot infer the type of this struct literal in this context");
            return;
        }

        type = context.check.type_hint;
    } else {
        if !EnsureTypeValue(type_node) {
            return;
        }

        type = type_node.value.type_value;
    }

    if type.kind != .Struct {
        Error(lit, "Expected a struct for struct literal but got %", ToString(type));
        return;
    }

    all_constants := true;
    has_errors := false;

    struct_type := cast(*YalTypeStruct, type);

    if values.count > struct_type.members.count {
        Error(lit, "Too many values in struct literal");
        has_errors = true;
    } else if values.count < struct_type.members.count {
        Error(lit, "Not enough values in struct literal");
        has_errors = true;
    }

    for i : 0..values.count - 1 {
        if i >= struct_type.members.count {
            break;
        }

        member_type := struct_type.members[i].type;
        value := values[i];

        if value.type == g_type_invalid {
            continue;
        }

        if value.semantic_meaning != .Constant {
            all_constants = false;
        }

        if !ExprCanImplicitlyCastTo(value, member_type, null, "struct literal value", is_binary_expr=false) {
            has_errors = true;
        }
    }

    if has_errors && struct_type.node {
        InfoNoSquiggles(struct_type.node, "Here is the struct that is being instantiated");
    }

    if all_constants {
        semantic_meaning = .Constant;

        if !has_errors {
            value.kind = .Struct;
            value.struct_value = Alloc(ConstantStructValue);
            value.struct_value.type = struct_type;
            value.struct_value.values = AllocArray(ConstantValue, values.count);
            for values {
                value.struct_value.values[it_index] = it.value;
            }
        }
    } else {
        semantic_meaning = .Value;
    }
}

GetOverloadMatchScore :: (using call : *AstFunctionCall, func_type : *YalTypeFunction) -> int {
    // @Todo: C variadic functions
    arity_match := passed_arguments.count == func_type.parameters.count;
    if !arity_match {
        return 0;
    }

    score := 1;
    for func_type.parameters {
        arg := passed_arguments[it_index];
        Assert(arg, arg.type != null, "Type is null");

        if it == arg.type {
            score += 100;
        } else if TypeCanImplicitlyCastTo(arg.type, it) {
            score += 10;
        } else {
            return 0;
        }
    }

    return score;
}

IsCallable :: inline (func : *AstFunction) -> bool {
    return func.body != null || func.is_external;
}

CheckOverloadedFunctionCall :: (using call : *AstFunctionCall) {
    OverloadTest :: struct {
        score : int;
        overload_index : int;
    }

    set_type := cast(*YalTypeFunctionOverloadSet, callee.type);

    tests := AllocArray(OverloadTest, set_type.overload_types.count);

    best_score := 0;
    best_overload_index := -1;
    ambiguous := false;
    for set_type.overload_types {
        score := GetOverloadMatchScore(call, it);
        tests[it_index] = .{score, it_index};

        if score > best_score {
            best_overload_index = it_index;
            best_score = score;
            ambiguous = false;
        } else if score == best_score {
            ambiguous = true;
        }
    }

    set := callee.value.overload_set.node;

    PrintOverloadScores :: (set : *AstFunctionOverloadSet, tests : []OverloadTest) {
        QuickSort(tests, (a, b) => b.score - a.score);

        for tests {
            overload := set.final_overloads[it.overload_index];
            if overload.value.kind == .Function {
                overload = overload.value.function_node;
            }

            Info(overload, "Considered overload has score %", it.score);
        }
    }

    if best_overload_index < 0 {
        builder : StringBuilder;
        for call.passed_arguments {
            if it_index > 0 {
                Append(*builder, ", ");
            }

            Append(*builder, "%", ToString(it.type));
        }

        Error(call, "Could not find a suitable overload for this function call. Argument types are: %", StringBuilderBuild(*builder));

        PrintOverloadScores(set, tests);
        return;
    }

    if ambiguous {
        Error(call, "Ambiguous function overload");
        PrintOverloadScores(set, tests);
        return;
    }

    best_overload := set.final_overloads[best_overload_index];
    func := best_overload.value.function_node;
    func_type := cast(*YalTypeFunction, func.type);

    callee.value = best_overload.value;
    callee.type = func_type;

    type = func_type.result;
    semantic_meaning = .Value;
}

MatchTemplatedType :: (args : *[..]ConstantValue, lhs : *YalType, rhs : *YalType) -> is_template : bool, matches : bool {
    if #complete lhs.kind == {
    case .Invalid;
        return false, TypesAreEqual(lhs, rhs);

    case .Void; #through;
    case .Integer; #through;
    case .Float; #through;
    case .Bool; #through;
    case .String; #through;
    case .TypeId; #through;
    case .Enum;
        return false, TypesAreEqual(lhs, rhs);

    case .Struct;
        lhs_struct := cast(*YalTypeStruct, lhs);
        if rhs && rhs.kind == .Struct {
            rhs_struct := cast(*YalTypeStruct, rhs);

            is_template := lhs_struct.parameters.count > 0 && lhs_struct.template_source != null;
            matches := rhs == lhs || rhs_struct.template_source == lhs_struct;

            if is_template && matches {
                arguments := rhs_struct.node.template_source.template_instantiations[rhs_struct.node.template_instantiation_index].template_arguments;
                ArrayPushMultiple(args, arguments);
            }

            return is_template, matches;
        } else {
            return lhs_struct.parameters.count > 0 && lhs_struct.template_source != null, false;
        }

    case .Pointer;
        lhs_ptr := cast(*YalTypePointer, lhs);

        if rhs && rhs.kind == .Pointer {
            rhs_ptr := cast(*YalTypePointer, rhs);
            is_template, matches := MatchTemplatedType(args, lhs_ptr.pointed_type, rhs_ptr.pointed_type);

            return is_template, matches;
        } else {
            return MatchTemplatedType(args, lhs_ptr.pointed_type, null), false;
        }

    case .Array;
        lhs_array := cast(*YalTypeArray, lhs);

        if rhs && rhs.kind == .Array {
            rhs_array := cast(*YalTypeArray, rhs);
            is_template, matches := MatchTemplatedType(args, lhs_array.element_type, rhs_array.element_type);

            return is_template, lhs_array.array_kind == rhs_array.array_kind && matches;
        } else {
            return MatchTemplatedType(args, lhs_array.element_type, null), false;
        }

    case .TemplateParam;
        lhs_param := cast(*YalTypeTemplateParam, lhs);
        ArrayPush(args, .{kind=.TypeId, type_value=rhs});
        return true, true;

    case .Function; #through;
    case .FunctionOverloadSet;  #through;
    case .Module;
        Panic("@Todo (I'm lazy)");
        return false, false;
    }
}

CheckFunctionTemplateCall :: (using call : *AstFunctionCall, func : *AstFunction) {
    if passed_arguments.count != func.parameters.count {
        Error(call, "Mismatching number of arguments passed to function (expected %, got %)", func.parameters.count, passed_arguments.count);
        Info(func, "Here is the function being called");
        return;
    }

    template_args := AllocArray(ConstantValue, func.template_params.count);

    found_named_argument := false;

    for arg : passed_arguments {
        if arg.type == g_type_invalid {
            continue;
        }

        param_index : int;
        if arg.name {
            found_named_argument = true;
            param_index = GetParameterIndex(func, arg.name.name);
        } else if found_named_argument {
            Error(arg, "Only named arguments can appear after a named argument");
            continue;
        } else {
            param_index = it_index;
        }

        param := func.parameters[param_index];
        if param.decl_kind == .TemplateParam {
            if arg.semantic_meaning != .Constant {
                Error(arg, "Argument should be constant for template parameter");
                Info(func, "Here is the function being called");
                return;
            }

            if !ExprCanImplicitlyCastTo(arg, param.type, param, "template argument", is_binary_expr=false) {
                Info(func, "Here is the function being called");
                return;
            }

            index := -1;
            for func.template_params {
                if it.decl == param {
                    index = it_index;
                    break;
                }
            }

            Assert(arg, index >= 0, "Could not find template parameter");

            template_args[index] = arg.value;
        }

        type_args : [..]ConstantValue;
        is_template, matches := MatchTemplatedType(*type_args, param.type, arg.type);
        if is_template {
            if !matches {
                Error(arg, "Argument of type % does not match template type %", ToString(arg.type), ToString(param.type));
                return;
            }

            start_index := -1;
            for func.template_params {
                if it.param_index == param_index {
                    if it.decl == param {
                        start_index = it_index + 1;
                    } else {
                        start_index = it_index;
                    }

                    break;
                }
            }

            Assert(arg, start_index >= 0, "Could not find template parameter");

            DbgInfo(.Templates, arg, "Matched templated type %: %", ToString(param.type), type_args);
            for type_args {
                template_args[start_index + it_index] = it;
            }
        }

        DbgInfo(.Templates, param, "Type args: %", type_args);
    }

    dependency := context.check.enclosing_expr.dependency_node;
    Assert(call, dependency.num_pending_template_instantiations > 0, "When instantiating template, the expression has no pending template instantiation");
    dependency.num_pending_template_instantiations -= 1;

    instantiated_func := InstantiateFunctionTemplate(call, func, template_args);
    AddDependencyOnFunctionTemplateInstantiation(dependency, instantiated_func);

    callee.flags |= .TemplateInstantiated;
    callee.value = .{kind=.Function, function_node=instantiated_func};
}

CheckTemplateTypeInstantiation :: (using call : *AstFunctionCall) -> should_continue : bool {
    if callee.semantic_meaning != .Constant {
        Error(callee, "Type in template instantiation is not constant");
        return false;
    }

    Assert(callee, callee.value.kind == .TypeId, "Not a type_id value");
    instantiated_type := callee.value.type_value;
    if instantiated_type.kind != .Struct {
        Error(callee, "Type in template instantiation is not a struct (type is %)", ToString(instantiated_type));
        return false;
    }

    struct_node := cast(*YalTypeStruct, instantiated_type).node;
    if !IsStructTemplate(struct_node) {
        Error(callee, "Type in template instantiation is not a template (type is %)", ToString(instantiated_type));
        return false;
    }

    // @Todo: unify with function call typechecking
    if passed_arguments.count != struct_node.parameters.count {
        Error(call, "Mismatching number of arguments for struct template instantiation (expected %, got %)", struct_node.parameters.count, passed_arguments.count);
        return false;
    }

    partial_instantiation := false;
    template_args := AllocArray(ConstantValue, struct_node.parameters.count);
    for arg : passed_arguments {
        if arg.type == g_type_invalid {
            continue;
        }

        if arg.semantic_meaning != .Constant {
            Error(arg, "Template argument should be constant");
            return false;
        }

        if !ExprCanImplicitlyCastTo(arg, struct_node.parameters[it_index].type, struct_node.parameters[it_index], "template argument", is_binary_expr=false) {
            return false;
        }

        template_args[it_index] = arg.value;

        if IsTemplateValue(arg.value) {
            partial_instantiation = true;
        }
    }

    if partial_instantiation {
        dependency := context.check.enclosing_expr.dependency_node;
        Assert(call, dependency.num_pending_template_instantiations > 0, "When instantiating template, the expression has no pending template instantiation");
        dependency.num_pending_template_instantiations -= 1;

        callee.flags |= .TemplateInstantiated;

        type = g_type_type_id;
        value = .{kind=.TypeId, type_value=instantiated_type};
        semantic_meaning = .Constant;

        return true;
    }

    instantiated_struct := InstantiateStructTemplate(call, struct_node, template_args);

    if !(callee.flags & .TemplateInstantiated) {
        dependency := context.check.enclosing_expr.dependency_node;
        Assert(call, dependency.num_pending_template_instantiations > 0, "When instantiating template, the expression has no pending template instantiation");
        dependency.num_pending_template_instantiations -= 1;

        AddDependencyOnStructTemplateInstantiation(dependency, instantiated_struct);

        callee.flags |= .TemplateInstantiated;
    }

    if !instantiated_struct.defined_type {
        return false;
    }

    type = g_type_type_id;
    value = .{kind=.TypeId, type_value=instantiated_struct.defined_type};
    semantic_meaning = .Constant;

    return true;
}

CheckFunctionCall :: (using call : *AstFunctionCall) -> should_continue : bool {
    EnsureNotChecked(call);

    type = g_type_invalid;

    if callee.type == g_type_invalid {
        Info(callee, "Type is invalid");
        return false;
    }

    if callee.type == g_type_type_id {
        return CheckTemplateTypeInstantiation(call);
    }

    if callee.type.kind != .Function && callee.type.kind != .FunctionOverloadSet {
        Error(callee, "Callee in function call expression is not a function or overload set (type is: %)", ToString(callee.type));
        return false;
    }

    if callee.type.kind == .FunctionOverloadSet {
        CheckOverloadedFunctionCall(call);
        return false;
    }

    if callee.value.kind == .Function && !IsCallable(callee.value.function_node) {
        Error(callee, "Callee in function call refers to non callable function");
        Info(callee.value.function_node, "Here is the function being called");
    }

    if callee.value.kind == .Function && IsFunctionTemplate(callee.value.function_node) {
        CheckFunctionTemplateCall(call, callee.value.function_node);
        return false;
    }

    if callee.value.kind == .Function && callee.value.function_node.template_instantiation_index >= 0 {
        func := callee.value.function_node;
        func_type := cast(*YalTypeFunction, func.type);

        // Update the callee's type because it's probably not pointing to the instantiation yet
        callee.type = func_type;
    }

    show_function_signature := false;
    func_type := cast(*YalTypeFunction, callee.type);

    defer if show_function_signature {
        if callee.value.kind == .Function && callee.value.function_node {
            Info(callee.value.function_node.signature_range, "Here is the signature of the function being called");
        } else {
            Info(call, "The type of the function is %", ToString(callee.type));
        }
    }

    if callee.value.kind == .Function {
        func := callee.value.function_node;

        if passed_arguments.count > func.parameters.count && !func.is_c_variadic {
            Error(call, "Mismatching number of arguments passed to function. Expected % but got %");
            show_function_signature = true;

            return false;
        }

        ordered_arguments = AllocArray(*AstNode, Max(passed_arguments.count, func.parameters.count), initialize=true);

        found_named_argument := false;

        for arg : passed_arguments {
            if arg.type == g_type_invalid {
                continue;
            }

            param_index : int;
            if arg.name {
                found_named_argument = true;

                param_index = GetParameterIndex(func, arg.name.name);
                if param_index < 0 {
                    Error(arg.name, "No argument named '%' in function", arg.name.name);
                    show_function_signature = true;
                    continue;
                }
            } else if found_named_argument {
                Error(arg, "Only named arguments can appear after a named argument");
                continue;
            } else {
                param_index = it_index;
            }

            param := ifx param_index < func.parameters.count then func.parameters[param_index];

            if ordered_arguments[param_index] {
                Assert(arg, param != null, "Param is null");

                name := ifx param.identifier then param.identifier.name;
                if name {
                    Error(arg, "Argument '%' has already been supplied", name);
                } else {
                    Error(arg, "Argument % has already been supplied", param_index + 1);
                }

                continue;
            }

            ordered_arguments[param_index] = arg.expr;
            arg.resolved_index = param_index;

            if param && !ExprCanImplicitlyCastTo(arg.expr, param.type, null, "argument", is_binary_expr=false) {
                show_function_signature = true;
            }
        }

        for ordered_arguments {
            if it || it_index >= func.parameters.count {
                continue;
            }

            param := func.parameters[it_index];
            if !param.expr {
                name := ifx param.identifier then param.identifier.name;
                if name {
                    Error(call, "Missing non optional argument '%'", name);
                } else {
                    Error(call, "Missing non optional argument %", it_index + 1);
                }
                show_function_signature = true;
            } else {
                ordered_arguments[it_index] = param.expr;
            }
        }
    } else {
        arity_match := func_type.is_c_variadic && passed_arguments.count >= func_type.parameters.count
            || passed_arguments.count == func_type.parameters.count;

        if !arity_match {
            Error(call,
                "Mismatching number of arguments passed to function. Expected %0% but got %",
                ifx func_type.is_c_variadic then "at least " else "", func_type.parameters.count, passed_arguments.count
            );

            show_function_signature = true;
            return false;
        }

        ordered_arguments = AllocArray(*AstNode, passed_arguments.count, initialize=true);

        shown_named_argument_error := false;
        for i : 0..passed_arguments.count - 1 {
            param_type : *YalType = ifx i >= func_type.parameters.count then null else func_type.parameters[i];
            arg := passed_arguments[i];

            if arg.type == g_type_invalid {
                continue;
            }

            if arg.name {
                if !shown_named_argument_error {
                    Error(arg, "Callee does not retain argument name information, so named arguments are not valid");
                    shown_named_argument_error = true;
                }

                continue;
            }

            arg.resolved_index = i;
            ordered_arguments[i] = arg.expr;

            if param_type && !ExprCanImplicitlyCastTo(arg.expr, param_type, null, "argument", is_binary_expr=false) {
                show_function_signature = true;
            }
        }
    }

    // Should we set the type to invalid if there was an error when calling the function?
    type = func_type.result;
    semantic_meaning = .Value;

    return true;
}

CheckSubscript :: (using subscript : *AstSubscript) {
    EnsureNotChecked(subscript);

    type = g_type_invalid;

    if subscripted.type == g_type_invalid {
        return;
    }

    if subscripted.type.kind != .Array
    && subscripted.type.kind != .Pointer
    && subscripted.type.kind != .String {
        Error(subscripted,
            "Invalid type for subscript operator. Expected an array, a pointer or a string but got %",
            ToString(subscripted.type)
        );
        return;
    }

    if subscripted.type.kind == {
    case .Array;
        type = cast(*YalTypeArray, subscripted.type).element_type;
    case .Pointer;
        type = cast(*YalTypePointer, subscripted.type).pointed_type;
    case .String;
        type = g_type_u8;
    }

    if index.type == g_type_invalid {
        return;
    }

    if index.type.kind != .Integer {
        Error(index,
            "Invalid type for index of subscript operator. Expected an integer but got %",
            ToString(index.type)
        );
        return;
    }

    // Bounds check when indexing of a static array/string with a constant index
    static_bounds := -1;
    static_subscript_error := false;
    if subscripted.type.kind == .Array && cast(*YalTypeArray, subscripted.type).array_kind == .Static {
        static_bounds = cast(*YalTypeArray, subscripted.type).count;
    } else if subscripted.type.kind == .String && subscripted.semantic_meaning == .Constant {
        static_bounds = subscripted.value.string_value.count;
    }

    if index.semantic_meaning == .Constant && static_bounds >= 0 {
        index_value := index.value.int_value;

        if static_bounds == 0 {
            static_subscript_error = true;

            Error(
                index,
                "% subscript index out of bounds. The index is % but the % is empty so no index is valid",
                ifx subscripted.type.kind == .String then "Constant string" else "Static array",
                index_value,
                ifx subscripted.type.kind == .String then "string" else "array"
            );
        } else if index_value < ToS128(0) || index_value >= ToS128(static_bounds) {
            static_subscript_error = true;

            Error(index,
                "% subscript index out of bounds. Expected [0; %] but got %",
                ifx subscripted.type.kind == .String then "Constant string" else "Static array",
                static_bounds - 1, index_value
            );
        }
    }

    // Set the semantic meaning and if possible make it a constant value
    if subscripted.value.kind == .String && index.semantic_meaning == .Constant {
        semantic_meaning = .Constant;
        value.kind = .Integer;
        if static_subscript_error {
            value.int_value = ToS128(0);
        } else {
            value.int_value = ToS128(subscripted.value.string_value[index.value.int_value.low]);
        }
    } else {
        semantic_meaning = ifx subscripted.semantic_meaning == .Constant
            then .Value
            else .Mutable;
    }
}

CheckArrayFieldAccess :: (using access : *AstFieldAccess) {
    type_array : *YalTypeArray;
    if left.type.kind == .Pointer {
        type_array = xx cast(*YalTypePointer, left.type).pointed_type;
    } else {
        type_array = xx left.type;
    }

    Assert(access.left, type_array != null && type_array.kind == .Array, "Unexpected type %", ToString(type_array));

    ident := cast(*AstIdentifier, right);
    if ident.name == {
    case "count";
        type = g_type_s64;

        if type_array.array_kind == .Static {
            semantic_meaning = .Constant;
            value = .{int_value=ToS128(type_array.count), kind=.Integer};
        } else if left.semantic_meaning == .Constant {
            Warning(access, "This expression should be constant but we don't yet handle constant array values. The result of this expression is 0 for now");
            semantic_meaning = .Constant;
            value = .{int_value=ToS128(0), kind=.Integer};
        } else if left.semantic_meaning == .Mutable {
            semantic_meaning = .Mutable;
        } else {
            semantic_meaning = .Value;
        }

        accessed_struct_member_index = 0;
        accessed_struct_member_offset = 0;

    case "data";
        type = MakeTypePointer(type_array.element_type, access);

        if left.semantic_meaning == .Mutable {
            if type_array.array_kind == .Dynamic || type_array.array_kind == .Slice {
                semantic_meaning = .Mutable;
            } else {
                semantic_meaning = .Value;
            }
        } else {
            semantic_meaning == .Value;
        }

        accessed_struct_member_index = 1;
        accessed_struct_member_offset = 8;

    case "capacity";
        if type_array.array_kind != .Dynamic {
            Error(right, "'%' is not a member of type %", ident.name, ToString(left.type));
            return;
        }

        type = g_type_s64;
        if left.semantic_meaning == .Constant {
            Warning(access, "This expression should be constant but we don't yet handle constant array values. The result of this expression is 0 for now");
            semantic_meaning = .Constant;
            value = .{int_value=ToS128(0), kind=.Integer};
        } else if left.semantic_meaning == .Mutable {
            semantic_meaning = .Mutable;
        } else {
            semantic_meaning = .Value;
        }

        accessed_struct_member_index = 2;
        accessed_struct_member_offset = 16;

    case "allocator";
        if type_array.array_kind != .Dynamic {
            Error(right, "'%' is not a member of type %", ident.name, ToString(left.type));
            return;
        }

        Assert(access, enclosing_scope.program.allocator_declaration != null, "Allocator declaration is null");
        type = enclosing_scope.program.allocator_declaration.value.type_value;
        Assert(enclosing_scope.program.allocator_declaration, type != null, "Allocator type is null");

        if left.semantic_meaning == .Constant {
            Warning(access, "This expression should be constant but we don't yet handle constant array values, so it is set to null for now");
            semantic_meaning = .Constant;
            value = .{pointer_value = 0, kind = .Pointer};
        } else if left.semantic_meaning == .Mutable {
            semantic_meaning = .Mutable;
        } else {
            semantic_meaning = .Value;
        }

        accessed_struct_member_index = 3;
        accessed_struct_member_offset = 24;

    case;
        Error(right, "'%' is not a member of type %", ident.name, ToString(left.type));
        return;
    }
}

CheckStringFieldAccess :: (using access : *AstFieldAccess) {
    ident := cast(*AstIdentifier, right);
    if ident.name == {
    case "count";
        type = g_type_s64;
        if left.semantic_meaning == .Constant {
            semantic_meaning = .Constant;
            value = .{int_value=ToS128(left.value.string_value.count), kind=.Integer};
        } else if left.semantic_meaning == .Mutable {
            semantic_meaning = .Mutable;
        } else {
            semantic_meaning = .Value;
        }

        accessed_struct_member_index = 0;
        accessed_struct_member_offset = 0;

    case "data";
        type = g_type_u8_ptr;
        if left.semantic_meaning == .Mutable {
            semantic_meaning = .Mutable;
        } else {
            semantic_meaning = .Value;
        }

        accessed_struct_member_index = 1;

        if left.semantic_meaning == .Constant {
            accessed_struct_member_offset = 0;
        } else {
            accessed_struct_member_offset = 8;
        }

    case;
        Error(right, "'%' is not a member of type %", ident.name, ToString(left.type));
        return;
    }
}

CheckFieldAccess :: (using access : *AstFieldAccess) {
    EnsureNotChecked(access);

    if right.kind != .Identifier {
        Error(right, "Invalid expression for rhs of field access operator (expected an identifier)");
        return;
    }

    rhs_ident := cast(*AstIdentifier, right);
    if rhs_ident.ident_flags & .ResolvedToPrimitiveTypeField {
        Assert(access, left != null, "LHS is null");
        Assert(access, left.type != null, "LHS type is null");

        accessed_type := left.type;
        if accessed_type.kind == .Pointer {
            accessed_type = cast(*YalTypePointer, accessed_type).pointed_type;
        }

        if accessed_type.kind == {
        case .String;
            CheckStringFieldAccess(access);
        case .Array;
            CheckArrayFieldAccess(access);
        }

        return;
    }

    Assert(rhs_ident, rhs_ident.symbol != null, "RHS of field access has not been resolved");

    accessed_scope := rhs_ident.symbol.decl.enclosing_scope;
    accessed_struct := GetStructOfScope(accessed_scope);

    if accessed_struct {
        type_struct := accessed_struct.defined_type;
        rhs_decl := rhs_ident.symbol.decl;

        if rhs_decl.decl_kind == .Variable {
            member : *YalTypeStructMember;
            for * type_struct.members {
                if it.name == rhs_ident.name {
                    member = it;
                    accessed_struct_member_index = xx it_index;
                    accessed_struct_member_offset = xx member.byte_offset;
                    break;
                }
            }

            if !member {
                Error(right, "'%' is not a member of type %", rhs_ident.name, ToString(left.type));
                if accessed_struct {
                    InfoNoSquiggles(accessed_struct, "Here is the declaration of %", ToString(type_struct));
                }

                return;
            }
        }
    }

    type = right.type;
    semantic_meaning = right.semantic_meaning;
    value = right.value;
}

CheckCast :: (using node : *AstCast) {
    EnsureNotChecked(node);

    type = g_type_invalid;

    if (type_node && !EnsureTypeValue(type_node)) || expr.type == g_type_invalid {
        return;
    }

    dest_type : *YalType;
    if cast_kind == .Auto {
        if !context.check.type_hint {
            Error(node, "Cannot determine the type for auto-cast");
            return;
        }

        dest_type = context.check.type_hint;
    } else {
        dest_type = type_node.value.type_value;
    }

    if cast_kind == .Bitcast {
        if dest_type.kind == {
        case .Enum;
        case .Integer;
        case .Float;
        case .Pointer;
        case .Function;
        case .Bool;
        case;
            Error(type_node, "Invalid type % for bitcast destination", ToString(dest_type));
        }

        if expr.type.kind == {
        case .Enum;
        case .Integer;
        case .Float;
        case .Pointer;
        case .Function;
        case .Bool;
        case;
            Error(expr, "Invalid type % for bitcast source", ToString(expr.type));
        }

        if dest_type.size != expr.type.size {
            Error(node, "Size mismatch for bitcast from % to %", ToString(expr.type), ToString(dest_type));
            return;
        }
    } else if !TypeCanExplicitlyCastTo(expr.type, dest_type) {
        Error(node, "Cannot cast from % to %", ToString(expr.type), ToString(dest_type));
        return;
    }

    type = dest_type;
    if expr.semantic_meaning == .Constant {
        if cast_kind == .Cast {
            if dest_type.kind == {
            case .Enum; #through;
            case .Integer; #through;
            case .Float; #through;
            case .Bool;
                semantic_meaning = .Constant;
                value = ConstantCast(expr.value, dest_type);

            case;
                semantic_meaning = .Value;
            }
        } else if cast_kind == .Bitcast {
            if dest_type.kind == {
            case .Enum; #through;
            case .Integer; #through;
            case .Float; #through;
            case .Bool;
                semantic_meaning = .Constant;
                value = ConstantBitCast(expr.value, dest_type);

            case;
                semantic_meaning = .Value;
            }
        }
    } else {
        semantic_meaning = .Value;
    }
}

CheckSizeOf :: (using node : *AstSizeOf) {
    EnsureNotChecked(node);

    if !EnsureTypeValue(type_node) {
        return;
    }

    size_of_type := type_node.value.type_value;
    type = g_type_s64;
    semantic_meaning = .Constant;
    value = .{int_value=ToS128(size_of_type.size), kind=.Integer};
    Assert(node, size_of_type.size >= 0, "In size_of expression, type is not sized");
}

CheckTypeOf :: (using node : *AstTypeOf) {
    EnsureNotChecked(node);

    type = g_type_type_id;
    semantic_meaning = .Constant;
    value = .{kind=.TypeId, type_value=expr.type};
}

CheckRun :: (using run : *AstRun) {
    type = expr.type;
    semantic_meaning = .Constant;

    if type.kind == {
    case .Invalid;
        return;

    case .TypeId; #through;
    case .Function; #through;
    case .Array; #through;
    case .Struct; #through;
    case .Pointer;
        Error(run, "#run cannot return type %", ToString(type));
        return;
    }

    QueueCompileTimeExecution(enclosing_scope.program, run);
}

CheckImport :: (using import : *AstImport) {
    EnsureNotChecked(import);

    if expr.type == g_type_invalid {
        return;
    }

    if expr.semantic_meaning != .Constant || expr.value.kind != .String {
        Error(expr, "Expected a constant string for #import");
        return;
    }

    module := ImportModule(enclosing_scope.program, expr.value.string_value, import_file=is_import_file, node=import);

    type = g_type_module;
    semantic_meaning = .Constant;
    value = .{kind=.Module, module=module};
}

ExprCanImplicitlyCastTo :: inline (
    expr : *AstNode,
    to_type : *YalType,
    to_node : *AstNode,
    reason : string,
    is_binary_expr := true
) -> bool {
    Assert(expr, expr.type != null, "The type of this node is null");

    if to_node {
        Assert(to_node, to_type != null, "The type of this node is null");
    } else {
        Assert(to_type != null);
    }

    if expr.semantic_meaning == .Constant && expr.type.kind != .Enum && expr.value.kind == .Integer {
        if !UntypedIntegerValueCanImplicitlyCastTo(expr.value, to_type) {
            if to_type.kind == .Integer {
                Error(expr, "This integer value does not fit into a % (value is %)", ToString(to_type), expr.value.int_value);
            } else if is_binary_expr {
                Error(expr, "Invalid type for % (left type: %, right type: %)", reason, ToString(to_type), ToString(expr.type));
            } else {
                Error(expr, "Invalid type for %. Expected % but got %", reason, ToString(to_type), ToString(expr.type));
            }

            return false;
        }
    } else if !TypeCanImplicitlyCastTo(expr.type, to_type) {
        if is_binary_expr {
            Error(expr, "Invalid type for % (left type: %, right type: %)",
                reason, ToString(to_type), ToString(expr.type));
        } else {
            Error(expr, "Invalid type for %. Expected % but got %",
                reason, ToString(to_type), ToString(expr.type));
        }

        return false;
    }

    return true;
}

ExprCanImplicitlyCastTo :: inline (
    expr : *AstNode,
    to : *AstNode,
    reason : string,
    is_binary_expr := true
) -> bool {
    return ExprCanImplicitlyCastTo(expr, to.type, to, reason, is_binary_expr);
}
