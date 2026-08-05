SemanticMeaning :: enum u8 {
    Invalid;
    Value;
    Constant;
    Mutable;
}

CheckStatus :: enum u8 {
    Unchecked;
    Checking;
    Checked;
    Emitted;
    Executed;
}

CheckContext :: struct {
    enclosing_expr : *AstNode;
    type_hint : *YalType;
    template_args : []ConstantValue;
}

SetTypeHint :: (hint : *YalType) -> prev : *YalType {
    prev := context.check.type_hint;
    context.check.type_hint = hint;

    return prev;
}

ScopeTypeHint :: (hint : *YalType) #expand {
    prev := context.check.type_hint;
    context.check.type_hint = hint;
    `defer context.check.type_hint = prev;
}

#add_context check : CheckContext;

SetDeclarationType :: (decl : *AstDeclaration, type : *YalType) {
    // Changing the type after it has been set can lead to unexpected behavior, because
    // other nodes might have set their type to this declaration's type already
    Assert(decl != null, "Declaration is null");
    Assert(decl, decl.type == null, "Declaration already has a type");

    decl.type = type;
    if decl.identifier {
        decl.identifier.type = type;
    }
}

CheckAttribute :: (using attr : *AstAttribute) {
    EnsureNotChecked(attr);

    DbgInfo(.Checking, attr, "Checking attribute (% arguments)", attr.arguments.count);

    Assert(attr, enclosing_scope != null, "Enclosing scope is null");

    CheckSubexpressions(dependency_node);

    if dependency_node.check_status == .Checked {
        for attr.arguments {
            if it.type != g_type_invalid && it.semantic_meaning != .Constant {
                Error(it, "Attribute argument is not constant");
            }
        }
    }
}

DeclarationModifiers :: struct {
    flags : DeclarationFlags;
    library_name : string;
    symbol_name : string;
    function_calling_convention : CallingConvention;
}

CheckDeclarationAttributes :: (decl : *AstDeclaration) {
    CheckDeclarationAttributes(*decl.modifiers, decl.attributes);
    CheckDeclarationAttributes(*decl.modifiers, decl.inherited_attributes);
    PostCheckDeclarationModifiers(*decl.modifiers);
}

PostCheckDeclarationModifiers :: (modifiers : *DeclarationModifiers) {
    if modifiers.function_calling_convention == .Unknown {
        if modifiers.flags & .External {
            modifiers.function_calling_convention = .C;
        } else {
            modifiers.function_calling_convention = .Yal;
        }
    }
}

CheckDeclarationAttributes :: (modifiers : *DeclarationModifiers, attributes : []*AstAttribute) {
    for attr : attributes {
        for attr.arguments {
            Assert(it, it.type != null, "Not checked");
        }

        if attr.name == {
        case "external";
            if attr.arguments.count != 0 {
                Error(attr, "Expected no argument for @external attribute");
            }

            modifiers.flags |= .External;
        case "call";
            if attr.arguments.count != 1 {
                Error(attr, "Expected 1 argument for @call attribute");
            }

            if attr.arguments.count > 0 {
                conv := attr.arguments[0];
                if conv.value.kind != .String {
                    Error(conv, "Expected a constant string value for argument 1 of @call");
                } else if conv.value.string_value == {
                case "c"; #through;
                case "C";
                    modifiers.function_calling_convention = .C;
                case "yal"; #through;
                case "Yal";
                    modifiers.function_calling_convention = .Yal;
                case;
                    Error(conv, "Unknown calling convention '%'", conv.value.string_value);
                }
            }

        case "library";
            if attr.arguments.count != 1 {
                Error(attr, "Expected 1 argument for @library attribute");
            }

            if attr.arguments.count > 0 {
                name := attr.arguments[0];
                if name.value.kind != .String {
                    Error(name, "Expected a constant string value for argument 1 of @library");
                } else {
                    modifiers.library_name = name.value.string_value;
                }
            }

        case "symbol";
            if attr.arguments.count != 1 {
                Error(attr, "Expected 1 argument for @symbol attribute");
            }

            if attr.arguments.count > 0 {
                name := attr.arguments[0];
                if name.value.kind != .String {
                    Error(name, "Expected a constant string value for argument 1 of @symbol");
                } else {
                    modifiers.symbol_name = name.value.string_value;
                }
            }
        }
    }
}

GetTemplateParamDeclarationInfo :: (using decl : *AstDeclaration) -> *TemplateInstantiation, value_index : int {
    template_inst : *TemplateInstantiation;
    value_index := -1;

    if enclosing_scope.kind == {
    case .Function;
        enclosing_func := enclosing_scope.function;

        if enclosing_func.template_instantiation_index >= 0 {
            template_inst = *enclosing_func.template_source.template_instantiations[enclosing_func.template_instantiation_index];
        }

        value_index = ArrayFindFirst(enclosing_func.template_params, .{decl=decl}, (a, b) => a.decl == b.decl);
        Assert(decl, value_index >= 0, "Could not find the template parameter inside the enclosing function");

    case .Struct;
        enclosing_struct := enclosing_scope.struct_node;

        if enclosing_struct.template_instantiation_index >= 0 {
            Assert(enclosing_struct, enclosing_struct.template_source != null, "Struct template source is null");
            template_inst = *enclosing_struct.template_source.template_instantiations[enclosing_struct.template_instantiation_index];
        }

        value_index = ArrayFindFirst(enclosing_struct.template_params, .{decl=decl}, (a, b) => a.decl == b.decl);
        Assert(decl, value_index >= 0, "Could not find the template parameter inside the enclosing struct");
    }

    return template_inst, value_index;
}

CheckDeclaration :: (using decl : *AstDeclaration) {
    EnsureNotChecked(decl);

    enclosing_scope.program.checking_stats.num_declarations += 1;

    defer if !type then SetDeclarationType(decl, g_type_invalid);

    CheckDeclarationAttributes(decl);

    if #complete decl_kind == {
    case .Invalid;
        type = g_type_invalid;

    case .TemplateParam;
        if enclosing_scope.kind != .Function && enclosing_scope.kind != .Struct {
            Error(decl, "Attempt to declare a template value where it is not allowed");
            return;
        }

        if identifier != null && identifier.ident_flags & .ImplicitDeclaration {
            Assert(decl, type != null, "Implicit declaration should've been checked by now");
            return;
        }

        template_inst, value_index := GetTemplateParamDeclarationInfo(decl);

        if type_node {
            if !EnsureTypeValue(type_node) {
                return;
            }

            SetDeclarationType(decl, type_node.value.type_value);

            if template_inst {
                decl.value = template_inst.template_arguments[value_index];
            } else if decl.type == g_type_type_id {
                name := ifx identifier then identifier.name else "???";
                decl.value = .{kind=.TypeId, type_value=MakeTypeTemplateParam(name, value_index)};
            } else {
                decl.value = .{kind=.TemplateParam};
            }
        } else {
            if context.check.type_hint {
                SetDeclarationType(decl, context.check.type_hint);
            } else {
                SetDeclarationType(decl, g_type_type_id);
            }

            if template_inst {
                decl.value = template_inst.template_arguments[value_index];

                Assert(decl, decl.value.kind == .TypeId, "Template argument is not a type_id");
            } else {
                name := ifx identifier then identifier.name else "???";
                decl.value = .{kind=.TypeId, type_value=MakeTypeTemplateParam(name, value_index)};
            }
        }

    case .Variable; #through;
    case .Constant; #through;
    case .Field; #through;
    case .ForLoopIndex;
        if decl_kind == .Variable {
            enclosing_scope.program.checking_stats.num_variable_declarations += 1;
        } else if decl_kind == .Constant {
            enclosing_scope.program.checking_stats.num_constant_declarations += 1;
        }

        if type_node {
            if !EnsureTypeValue(type_node) {
                return;
            }

            SetDeclarationType(decl, type_node.value.type_value);
        }

        if expr {
            CheckInitAssignment(decl);

            if !type {
                SetDeclarationType(decl, expr.type);
            }

            if decl_kind == .Constant {
                decl.value = expr.value;
            }
        } else if decl_kind == .Constant {
            Error(decl, "Uninitialized constant");
        }

    case .EnumMember;
        CheckEnumMember(decl);
    }

    if decl == enclosing_scope.program.allocator_declaration {
        CheckBuiltinStructDeclaration(decl, 16, 8);
    }

    if flags & .Using && type && type != g_type_invalid {
        accessed_scope : *Scope;
        if expr {
            accessed_scope = GetAccessedScope(expr);
        } else {
            accessed_scope = GetAccessedScope(enclosing_scope.program, type);
        }

        if accessed_scope {
            ImportScope(enclosing_scope, accessed_scope, decl);
        }
    }
}

CheckBuiltinStructDeclaration :: (decl : *AstDeclaration, expected_size : int, expected_alignment : int) {
    name := ifx decl.identifier then decl.identifier.name else "<unnamed>";

    if decl.decl_kind != .Constant || decl.value.kind != .TypeId {
        Error(decl, "'%' does not define a constant type", name);
    } else {
        type := decl.value.type_value;
        if type.kind != .Struct {
            Error(decl, "'%' does not define a struct", name);
        }
        if GetTypeAlignment(type) != expected_alignment {
            Error(decl, "'%' does not define an 8-byte aligned struct (it is %-byte aligned)", name, GetTypeAlignment(type));
        }
        if type.size != expected_size {
            Error(decl, "'%' does not define a 16-byte struct (it is % bytes)", name, type.size);
        }
    }
}

CheckInitAssignment :: (using decl : *AstDeclaration) -> bool {
    EnsureNotChecked(decl);

    if decl_kind == .Variable && IsTopLevelScope(decl.enclosing_scope) && expr.semantic_meaning != .Constant {
        Error(expr, "Global variables must be initialized to a constant value");
        return false;
    }

    if decl_kind == .Constant && expr.semantic_meaning != .Constant {
        Error(expr, "Assigning non constant expression to a constant");
        return false;
    }

    if type && !ExprCanImplicitlyCastTo(expr, decl, "init assignment") {
        return false;
    }

    if decl_kind == .Constant {
        value = expr.value;
    }

    return true;
}

CheckAssignment :: (using assign : *AstAssignment) {
    EnsureNotChecked(assign);

    if left.type == g_type_invalid || right.type == g_type_invalid {
        return;
    }

    if left.semantic_meaning == {
    case .Value;
        Error(left, "Assigning to an r-value");
        return;
    case .Constant;
        Error(left, "Assigning to a constant");
        return;
    }

    // @Cleanup @Hack: AstAssignment and AstBinary have the same memory layout, so we use
    // the routines to check binary expressions for assignments, which may lead
    // to unexpected behavior
    #assert size_of(AstAssignment) == size_of(AstBinary);

    if op.kind == {
    case .PlusEqu; #through;
    case .MinusEqu; #through;
    case .StarEqu; #through;
    case .SlashEqu;
        CheckArithmeticOperation(cast(*AstBinary) assign);

    case .PercentEqu;
        CheckModulo(cast(*AstBinary) assign);

    case .AmpersandEqu; #through;
    case .PipeEqu; #through;
    case .CaretEqu; #through;
    case .LessLessEqu; #through;
    case .GreaterGreaterEqu;
        CheckBitOperation(cast(*AstBinary) assign);

    case;
        if !ExprCanImplicitlyCastTo(right, left, "assignment") {
            return;
        }
    }

    // Reset the type and semantic meaning, plain statements don't have those
    type = null;
    semantic_meaning = .Invalid;
}

CheckIf :: (using if_stmt : *AstIf) {
    EnsureNotChecked(if_stmt);

    if condition.type == g_type_invalid {
        return;
    }

    if !ExprCanImplicitlyCastTo(condition, g_type_bool, null, "condition of if statement", is_binary_expr=false) {
        return;
    }

    if is_compile_time {
        if condition.value.kind == .Invalid {
            Error(condition, "Condition expression in #if is not constant");
            return;
        }

        is_true := ConstantCast(condition.value, g_type_bool).bool_value;
        statement := ifx is_true then body else else_stmt;
        if !statement {
            return;
        }

        index_in_scope_statements := ArrayFindFirst(enclosing_scope.all_statements, if_stmt);
        Assert(if_stmt, index_in_scope_statements >= 0, "Could not find this #if node in enclosing_scope.all_statements");

        if statement.kind == .Block {
            block := cast(*AstBlock, statement);
            for block.statements {
                AddStatement(enclosing_scope, it, index_in_scope_statements + 1 + it_index);
            }
        } else {
            AddStatement(enclosing_scope, statement, index_in_scope_statements + 1);
        }
    }
}

CheckWhile :: (using while_stmt : *AstWhile) {
    EnsureNotChecked(while_stmt);

    if condition.type == g_type_invalid {
        return;
    }

    if !ExprCanImplicitlyCastTo(condition, g_type_bool, null, "condition of while statement", is_binary_expr=false) {
        return;
    }
}

CheckFor :: (using for_stmt : *AstFor) {
    EnsureNotChecked(for_stmt);

    iterator_expr : *AstNode;

    if iterator.kind == .Declaration {
        iterator_expr = cast(*AstDeclaration, iterator).expr;
    } else if iterator.kind == .Assignment {
        iterator_expr = cast(*AstAssignment, iterator).right;
    } else {
        Panic(iterator, "Unexpected ast node kind % in for iterator", iterator.kind);
        return;
    }

    if iterator_expr.kind != .Range {
        Error(iterator_expr, "Expression cannot be iterated on (type is %)", ToString(iterator_expr.type));
    }
}

CheckReturn :: (using return_stmt : *AstReturn) {
    EnsureNotChecked(return_stmt);

    enclosing_func := enclosing_scope.enclosing_function;
    if !enclosing_func {
        Error(return_stmt, "return statements are only allowed in functions");
        return;
    }

    func_type := cast(*YalTypeFunction, enclosing_func.type);
    if !func_type {
        Error(enclosing_func, "Enclosing function type is null");
        Info(return_stmt, "When checking this return statement");
        Panic();
    }

    if func_type.result != g_type_void && !return_stmt.expr {
        Error(return_stmt, "Expected a value of type % for return statement", ToString(func_type.result));
        Info(enclosing_func.signature_range, "Here is the signature of the enclosing function");
        return;
    }

    if return_stmt.expr {
        if return_stmt.expr.type == g_type_invalid {
            return;
        }

        if !ExprCanImplicitlyCastTo(return_stmt.expr, enclosing_func.result, "return value", is_binary_expr=false) {
            Info(enclosing_func.signature_range, "Here is the signature of the enclosing function");
        }
    }
}

CheckAssert :: (using assert : *AstAssert) {
    EnsureNotChecked(assert);

    if expr.type == g_type_invalid {
        return;
    }

    if !ExprCanImplicitlyCastTo(expr, g_type_bool, null, "assertion", is_binary_expr=false) {
        return;
    }

    if expr.value.kind == .Invalid {
        Error(expr, "Condition expression in #assert is not constant");
        return;
    }

    is_true := ConstantCast(expr.value, g_type_bool).bool_value;

    message_str : string;
    if message {
        if message.type != g_type_string {
            Error(message, "Message expression in #assert is not a string");
        } else if message.value.kind == .Invalid {
            Error(message, "Message expression in #assert is not constant");
        } else if message.type != g_type_invalid {
            message_str = message.value.string_value;
        }
    }

    if !is_true {
        if message_str {
            Error(assert, "Compile time assertion failed: %", message_str);
        } else {
            Error(assert, "Compile time assertion failed");
        }

        Basic.exit(1);
    }
}

IsCompileTimeStatement :: inline (stmt : *AstNode) -> bool {
    if stmt.kind == {
    case .Assert;
        return true;
    case .Insert;
        return true;
    case .Run;
        return true;
    case .If;
        if_stmt := cast(*AstIf, stmt);
        return if_stmt.is_compile_time;
    }

    return false;
}

IsTopLevelStatement :: inline (stmt : *AstNode) -> bool {
    if stmt.kind == {
    case .Declaration;
        return true;
    case .Assert;
        return true;
    case .Include;
        return true;
    case .Insert;
        return true;
    case .Run;
        return true;
    case .Block;
        return true;
    case .If;
        if_stmt := cast(*AstIf, stmt);
        return if_stmt.is_compile_time;
    }

    return false;
}

IsNormalLevelStatement :: inline (stmt : *AstNode) -> bool {
    if stmt.kind == {
    case .Include;
        return false;
    }

    return true;
}

CheckStatementLevel :: (stmt : *AstNode) {
    if IsTopLevelScope(stmt.enclosing_scope) {
        if !IsTopLevelStatement(stmt) {
            Error(stmt, "This statement is not allowed at file level");
            return;
        }
    } else {
        if !IsNormalLevelStatement(stmt) {
            Error(stmt, "This statement is not allowed at this level");
            return;
        }
    }
}

// @Todo: warn about statements after return
CheckStatement :: (stmt : *AstNode) {
    EnsureNotChecked(stmt);

    CheckStatementLevel(stmt);

    if stmt.kind != .Declaration {
        stmt.enclosing_scope.program.checking_stats.num_statements += 1;
    }

    if stmt.kind == {
    case .Declaration;
        CheckDeclaration(xx stmt);
    case .Assignment;
        CheckAssignment(xx stmt);
    case .If;
        CheckIf(xx stmt);
    case .While;
        CheckWhile(xx stmt);
    case .For;
        CheckFor(xx stmt);
    case .Block;
        CheckBlock(xx stmt);
    case .FlowControl;
        flow_control := cast(*AstFlowControl, stmt).control;
        if flow_control == {
        case .Break; #through;
        case .Continue;
            enclosing_scope := stmt.enclosing_scope;
            while enclosing_scope.kind == .Statement && enclosing_scope.statement.kind != .While {
                enclosing_scope = enclosing_scope.parent;
            }

            if enclosing_scope.kind != .Statement || enclosing_scope.statement.kind != .While {
                Error(stmt, "% is only allowed in while loops", Token_Names[flow_control]);
                return;
            }
        case .Fallthrough;
            Error(stmt, "'fallthrough' is only allowed in case statements");
        }

    case .Defer;

    case .Return;
        CheckReturn(cast(*AstReturn, stmt));

    case .Assert;
        CheckAssert(cast(*AstAssert, stmt));

    case .Include;
        include := cast(*AstInclude, stmt);
        if include.enclosing_scope.enclosing_module {
            AddSourceFile(include.enclosing_scope.enclosing_module, include.filename, include);
        } else {
            AddSourceFile(include.enclosing_scope.program, include.filename, include);
        }

    case .Insert;
        CheckInsert(xx stmt);

    case;
        Panic(stmt, "Invalid statement or not yet handled");
    }
}

CheckBlock :: (using block: *AstBlock) {
    if !parent_expr {
        return;
    }

    is_declarative := parent_expr.kind == .Struct || parent_expr.kind == .Enum;
    error := false;

    if is_declarative {
        for statements {
            if it.kind != .Declaration && !IsCompileTimeStatement(it) {
                Error(it, "Only declarations are allowed in this block");
                error = true;
            }
        }
    }

    if error {
        Info(block, "When checking this block");
    }
}

CheckInsert :: (insert : *AstInsert) {
    Assert(insert.expr, insert.expr.type != null, "Type is null");

    if insert.expr.type == g_type_invalid {
        return;
    }

    if insert.expr.type != g_type_string {
        Error(insert.expr, "Invalid type for #insert expression (expected a string, got %)", ToString(insert.expr.type));
        return;
    }

    if insert.expr.semantic_meaning != .Constant {
        Error(insert.expr, "#insert expression is not constant");
        return;
    }

    if insert.expr.value.kind == .String {
        AddSourceCode(insert.enclosing_scope, insert, insert.expr.value.string_value);
    }
}

CheckEntryPointSignature :: (func : *AstFunction) {
    type := cast(*YalTypeFunction, func.type);
    Assert(type.kind == .Function);

    error := false;
    if type.result != g_type_s32 {
        error = true;
    } else if type.parameters.count > 1 {
        error = true;
    } else if type.parameters.count == 1 && !TypesAreEqual(type.parameters[0], MakeTypeArray(.Slice, g_type_string, -1)) {
        error = true;
    }

    if error {
        Error(func.signature_range, "Invalid signature for entry point. Expected func([]string) -> s32 or func() -> s32");
    }
}

EnsureNotChecked :: (node : *AstNode) {
    Assert(node, !node.dependency_node || node.dependency_node.check_status == .Checking, "Dependency node check status is % but expected Checking", node.dependency_node.check_status);
}

CheckDependencyNode :: (dep : *DependencyNode) {
    Assert(dep.ast_node, dep.check_status != .Checked, "Node has already been checked");

    dep.check_status = .Checking;

    defer if !g_build_settings.report_all_errors {
        ExitIfError();
    }

    defer if dep.check_status >= .Checked && dep.num_pending_template_instantiations > 0 {
        Error(dep.ast_node, "This node is still waiting for % template(s) to be instantiated", dep.num_pending_template_instantiations);
    }

    if IsExpression(dep.ast_node.kind) {
        CheckSubexpressions(dep);
    } else {
        node := dep.ast_node;

        DbgInfo(.Checking, node, "Checking %", node.kind);

        if node.kind == {
        case .Invalid; #through;
        case .StatementsBegin; #through;
        case .StatementsEnd; #through;
        case .ExpressionsBegin; #through;
        case .ExpressionsEnd; #through;
        case .Count;
            Panic(node, "Invalid node kind %", node.kind);

        case .Declaration; #through;
        case .Assignment; #through;
        case .If; #through;
        case .While; #through;
        case .For; #through;
        case .Defer; #through;
        case .Return; #through;
        case .FlowControl; #through;
        case .Assert; #through;
        case .Include; #through;
        case .Insert; #through;
        case .Block;
            CheckStatement(node);
            dep.check_status = .Checked;

        case;
            Panic(node, "Unhandled case % in CheckDependencyNode", node.kind);

        case .Attribute;
            CheckAttribute(xx node);
        }
    }
}
