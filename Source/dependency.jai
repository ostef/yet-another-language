Dependency :: struct {
    using node : *DependencyNode;
    flags : DependencyFlags;
}

UnresolvedIdentifier :: struct {
    identifier : *AstIdentifier;

    // Some unresolved identifiers like Allocator for dynamic arrays are implicit and not represented in the AST
    name : string;

    // For field access, the rhs needs to keep track of the parent expression so it knows in what scope to look
    parent_field_access : *AstFieldAccess;

    // For now only used for builtin types like Allocator that are defined in preload so we don't mistakenly
    // resolve to a user defined Allocator (though redefining the name Allocator is certainly a bad idea!)
    look_in_scope : *Scope;

    flags : DependencyFlags;
}

DependencyFlags :: enum_flags u8 {
    // Weak dependencies do not cause circular dependencies.
    // They indeed force the system to compile things in a specific order, but if
    // the dependency is present in the stack when pushing it then we just ignore it
    // instead of reporting a circular dependency error.
    // This is important for e.g. pointer/array types to structs, where we know
    // the type of the struct gets created before typechecking and will be available,
    // we still want things to be typechecked as if they are dependent on each other
    // but we do not want it to create a circular cycle
    Weak;
    // Special case for function callees: make sure when we resolve the identifier,
    // the dependency is taken on the function signature and not the whole declaration
    Callee;
    // When this is set, the dependency resolution phase will block until compile time
    // execution of the node is done.
    ForExecution;

    FieldAccessRHS;
}

DependencyNode :: struct {
    SubexpressionCommand :: struct {
        union {
            type_hint : struct {
                type_ptr : **YalType;
                callback_node : *AstNode;
                callback_index : int;
                callback : (node : *AstNode, index : int) -> *YalType;
            };
            expr : *AstNode;
        };

        kind : enum u8 {
            CheckExpression;
            PushTypeHint;
            PopTypeHint;
        };
    }

    ast_node : *AstNode;

    // In an expression, all child expressions in the tree are put in a linear to be checked.
    subexpression_commands : [..]SubexpressionCommand;
    type_hint : **YalType;

    dependencies : [..]Dependency;
    unresolved_identifiers : [..]UnresolvedIdentifier; // When resolved, adds a dependency to the dependencies array

    num_pending_template_instantiations : s32;
    last_checked_subexpression : s32 = -1;

    check_status : CheckStatus;
}

GetUnresolvedIdentifier :: inline (dep : *DependencyNode, identifier : *AstIdentifier) -> *UnresolvedIdentifier {
    index := ArrayFindFirst(dep.unresolved_identifiers, .{identifier=identifier}, (a, b) => a.identifier == b.identifier);
    if index < 0 {
        return null;
    }

    return *dep.unresolved_identifiers[index];
}

AddUnresolvedIdentifier :: (node : *DependencyNode, identifier : *AstIdentifier, flags : DependencyFlags, parent_field_access : *AstFieldAccess = null, look_in_scope : *Scope = null) {
    Assert(node.ast_node, identifier != null, "Adding unresolved identifier but it is null");

    DbgInfo(.Dependencies, node.ast_node, "Unresolved identifier '%', flags=%", identifier.name, flags);
    if parent_field_access {
        DbgInfo(.Dependencies, parent_field_access, "Parent field access", identifier.name, flags);
    }

    if flags & .FieldAccessRHS {
        identifier.ident_flags |= .FieldAccessRHS;
    }

    ArrayPush(*node.unresolved_identifiers, .{flags=flags, identifier=identifier, name=identifier.name, parent_field_access=parent_field_access, look_in_scope=look_in_scope});
}

AddUnresolvedIdentifier :: (node : *DependencyNode, name : string, flags : DependencyFlags, parent_field_access : *AstFieldAccess = null, look_in_scope : *Scope = null) {
    DbgInfo(.Dependencies, node.ast_node, "Implicit unresolved identifier '%', flags=%", name, flags);
    ArrayPush(*node.unresolved_identifiers, .{flags=flags, identifier=null, name=name, parent_field_access=parent_field_access, look_in_scope=look_in_scope});
}

AddDependency :: (node : *DependencyNode, dep : *DependencyNode, flags : DependencyFlags) {
    Assert(node.ast_node, dep != null, "Adding dependency but it is null");

    DbgInfo(.Dependencies, node.ast_node, "Dependency on '%' flags=%", TokenRangeToStringFirstLine(dep.ast_node), flags);
    ArrayPush(*node.dependencies, .{flags=flags, node=dep});
}

CreateDependencyNode :: (parent_dep : *DependencyNode, node : *AstNode) {
    Assert(node, node.dependency_node == null, "Dependency node has already been created");
    Assert(node, node.enclosing_scope != null, "Node % does not have an enclosing scope", node.kind);

    node.dependency_node = Alloc(DependencyNode);
    node.dependency_node.ast_node = node;
    ArrayPush(*node.enclosing_scope.all_dependency_nodes, node.dependency_node);

    // Find parent statement
    if IsExpression(node.kind) && (node.flags & .StatementLevelExpression) {
        node.parent_statement = node;
    } else if parent_dep {
        parent_statement := parent_dep.ast_node;
        while parent_statement && IsExpression(parent_statement.kind) && !(parent_statement.flags & .StatementLevelExpression) {
            parent_statement = parent_statement.parent_statement;
        }

        Assert(node, parent_statement != null, "CreateDependencyNode: could not find the parent statement");
        DbgInfo(.Dependencies, node, "Found parent statement: %", TokenRangeToStringFirstLine(parent_statement));

        node.parent_statement = parent_statement;
    }

    DbgInfo(.Dependencies, node, "% attributes (% inherited)", node.attributes.count, node.inherited_attributes.count);

    for attr : node.attributes {
        CollectDependencyNodes(node.dependency_node, attr);
    }

    for attr : node.inherited_attributes {
        AddDependency(node.dependency_node, attr.dependency_node, 0);
    }

    node.enclosing_scope.program.num_dependency_nodes += 1;

    if parent_dep {
        flags : DependencyFlags;
        if node.kind == .Run {
            flags |= .ForExecution;
        }

        AddDependency(parent_dep, node.dependency_node, flags);
    }
}

LookupSymbol :: (scope : *Scope, dep : *DependencyNode, unresolved : *UnresolvedIdentifier) -> *Symbol {
    symbol : *Symbol;
    imported : *ImportedSymbol;
    if unresolved.look_in_scope {
        symbol, imported = ScopeLookupCurrent(unresolved.look_in_scope, unresolved.name);
    } else {
        symbol, imported = ScopeLookup(scope, unresolved.name);
    }

    if !symbol {
        return null;
    }

    if unresolved.identifier {
        unresolved.identifier.symbol = symbol;
        unresolved.identifier.imported_symbol = imported;
    }

    decl := symbol.decl;

    // Take a dependency on the function signature and not the full
    // declaration for function callees
    if unresolved.flags & .Callee && decl.decl_kind == .Constant && decl.expr && decl.expr.kind == .Function {
        func := cast(*AstFunction, decl.expr);
        AddDependency(dep, func.dependency_node, unresolved.flags);
    } else {
        AddDependency(dep, decl.dependency_node, unresolved.flags);
    }

    if imported {
        AddDependency(dep, imported.source_using.dependency_node, unresolved.flags);
    }

    return symbol;
}

ResolveInferredFieldAccessRHSIdentifier :: (scope : *Scope, dep : *DependencyNode, index : int) -> *Symbol {
    unresolved := *dep.unresolved_identifiers[index];

    Assert(dep.ast_node, unresolved.identifier != null, "Unresolved identifier node is null for inferred field access");

    subexpression_index := ArrayFindFirst(dep.subexpression_commands, .{kind=.CheckExpression, expr=unresolved.identifier}, (s1, s2) => s1.kind == .CheckExpression && s1.expr == s2.expr);
    Assert(unresolved.identifier, subexpression_index >= 0, "Could not find this unresolved identifier in the subexpressions array");

    Assert(unresolved.identifier, context.check.type_hint == null, "Type hint should be null, we are not in a typechecking context");

    type_hint, has_hint := GetSubexpressionTypeHint(dep, subexpression_index);
    if !has_hint {
        Error(unresolved.identifier, "Cannot infer the accessed type in this context");
        return null;
    }

    if !type_hint {
        return null;
    }

    accessed_scope := GetAccessedScope(scope.program, type_hint);

    if !accessed_scope {
        Error(unresolved.parent_field_access, "Inferred type % does not define a scope", ToString(type_hint));
        return null;
    }

    unresolved.look_in_scope = accessed_scope;

    return LookupSymbol(scope, dep, unresolved);
}

ResolveFieldAccessRHSIdentifier :: (scope : *Scope, dep : *DependencyNode, index : int) -> bool, *Symbol {
    unresolved := *dep.unresolved_identifiers[index];
    lhs := unresolved.parent_field_access.left;

    if !lhs {
        symbol := ResolveInferredFieldAccessRHSIdentifier(scope, dep, index);
        return symbol != null, symbol;
    }

    if !lhs.type || lhs.type == g_type_invalid {
        return false, null;
    }

    if lhs.type.kind == .Pointer {
        pointer := cast(*YalTypePointer, lhs.type).pointed_type;
        if pointer.kind == .String || pointer.kind == .Array {
            unresolved.identifier.ident_flags |= .ResolvedToPrimitiveTypeField;

            return true, null;
        }
    } else if lhs.type.kind == .String || lhs.type.kind == .Array {
        unresolved.identifier.ident_flags |= .ResolvedToPrimitiveTypeField;

        return true, null;
    }

    accessed_scope, has_scope := GetAccessedScope(lhs);
    if !accessed_scope {
        if !has_scope {
            Error(lhs, "This expression of type % does not define a scope", ToString(lhs.type));
        }

        return false, null;
    }

    unresolved.look_in_scope = accessed_scope;

    symbol := LookupSymbol(scope, dep, unresolved);
    return symbol != null, symbol;
}

ResolveIdentifier :: (scope : *Scope, dep : *DependencyNode, index : int) -> bool {
    unresolved := *dep.unresolved_identifiers[index];
    symbol : *Symbol;
    defer if symbol && symbol.decl.expr {
        expr := symbol.decl.expr;

        if expr.kind == .Function && IsFunctionTemplate(xx expr) {
            dep.num_pending_template_instantiations += 1;
        } else if expr.kind == .Struct && IsStructTemplate(xx expr) {
            dep.num_pending_template_instantiations += 1;
        }
    }

    if unresolved.flags & .FieldAccessRHS {
        resolved:, symbol = ResolveFieldAccessRHSIdentifier(scope, dep, index);
        if !resolved {
            return false;
        }
    } else {
        symbol = LookupSymbol(scope, dep, unresolved);
        if !symbol {
            return false;
        }
    }

    ArrayRemove(*dep.unresolved_identifiers, index);

    return true;
}

ResolveIdentifiersInScope :: (scope : *Scope) -> all_resolved : bool, new_resolved : bool {
    all_resolved := true;
    new_resolved := false;
    for dep : scope.all_dependency_nodes {
        i := 0;
        while i < dep.unresolved_identifiers.count {
            resolved := ResolveIdentifier(scope, dep, i);
            if !resolved {
                i += 1;
            }

            all_resolved &= resolved;
            new_resolved |= resolved;
        }
    }

    return all_resolved, new_resolved;
}

ResolveIdentifiersInScopeAndChildren :: (scope : *Scope) -> all_resolved : bool, new_resolved : bool {
    all_resolved, new_resolved := ResolveIdentifiersInScope(scope);

    for :Children scope {
        all, new := ResolveIdentifiersInScopeAndChildren(it);
        all_resolved &= all;
        new_resolved |= new;
    }

    return all_resolved, new_resolved;
}

ReportUnresolvedIdentifiersInScope :: (scope : *Scope) {
    for dep : scope.all_dependency_nodes {
        for dep.unresolved_identifiers {
            // Do not report unresolved identifiers for field access RHS, when the LHS has not been checked
            if it.flags & .FieldAccessRHS && it.parent_field_access.left && (!it.parent_field_access.left.type || it.parent_field_access.left.type == g_type_invalid) {
                continue;
            }

            if it.identifier {
                Error(it.identifier, "Unresolved identifier '%'", it.name);
            } else {
                Error(dep.ast_node, "Unresolved identifier '%'", it.name);
            }

            if it.flags & .FieldAccessRHS && !it.look_in_scope {
                Assert(it.parent_field_access != null, "Parent field access is null for RHS");

                if it.parent_field_access.left {
                    Error(it.parent_field_access.left, "This expression of type % does not define a scope", ToString(it.parent_field_access.left.type));
                }
            }

            if it.look_in_scope && (it.look_in_scope.kind == .Statement || it.look_in_scope.kind == .Statement) {
                Info(it.look_in_scope.statement, "Here is the scope in which we tried to resolve the identifier");
            }
        }
    }
}

ReportUnresolvedIdentifiersInScopeAndChildren :: (scope : *Scope) {
    ReportUnresolvedIdentifiersInScope(scope);

    for :Children scope {
        ReportUnresolvedIdentifiersInScopeAndChildren(it);
    }
}

AddSubexpression :: inline (dependency_node : *DependencyNode, node : *AstNode) {
    if node != dependency_node.ast_node {
        ArrayPush(*dependency_node.subexpression_commands, .{kind=.CheckExpression, expr=node});
    }

    parent_statement := dependency_node.ast_node;
    while parent_statement && IsExpression(parent_statement.kind) && !(parent_statement.flags & .StatementLevelExpression) {
        parent_statement = parent_statement.parent_statement;
    }

    Assert(node, parent_statement != null, "parent_statement is not a statement");

    if node.parent_statement != null && node.parent_statement != parent_statement {
        DbgInfo(.Dependencies, node.parent_statement, "Current");
        DbgInfo(.Dependencies, parent_statement, "New");
        Panic(node, "parent_statement mismatch");
    }

    node.parent_statement = parent_statement;
}

PushTypeHint :: inline (dependency_node : *DependencyNode, node : *AstNode, index : int, callback : (*AstNode, int) -> *YalType) {
    ArrayPush(*dependency_node.subexpression_commands, .{kind=.PushTypeHint, type_hint=.{callback_node=node, callback_index=index, callback=callback}});
}

PushTypeHint :: inline (dependency_node : *DependencyNode, type_hint_ptr : **YalType) {
    ArrayPush(*dependency_node.subexpression_commands, .{kind=.PushTypeHint, type_hint=.{type_ptr=type_hint_ptr}});
}

PopTypeHint :: inline (dependency_node : *DependencyNode) {
    ArrayPush(*dependency_node.subexpression_commands, .{kind=.PopTypeHint});
}

CollectSubexpressionsFromLeftToRight :: (dependency_node : *DependencyNode, node : *AstNode, flags : DependencyFlags, parent_field_access : *AstFieldAccess = null) {
    Assert(dependency_node != null);

    if !node {
        return;
    }

    Assert(node, IsExpression(node.kind), "Node is not an expression");

    // Collect attribute arguments at the end, because we only want to do so when the expression
    // does not create a dependency node itself
    defer if !node.dependency_node {
        for attr : node.attributes {
            CollectDependencyNodes(dependency_node, attr);
        }

        for attr : node.inherited_attributes {
            AddDependency(dependency_node, attr.dependency_node, 0);
        }
    }

    if node.kind == {
    case .TypePointer;
        pointer := cast(*AstTypePointer, node);
        CollectSubexpressionsFromLeftToRight(dependency_node, pointer.pointed_type, flags | .Weak);
        AddSubexpression(dependency_node, node);

    case .TypeArray;
        array := cast(*AstTypeArray, node);
        CollectSubexpressionsFromLeftToRight(dependency_node, array.element_type, flags | .Weak);
        CollectSubexpressionsFromLeftToRight(dependency_node, array.element_count, flags);
        AddSubexpression(dependency_node, node);

        if array.array_kind == .Dynamic {
            AddUnresolvedIdentifier(dependency_node, "Allocator", 0, parent_field_access=parent_field_access, look_in_scope=node.enclosing_scope.program.scope);
        }

    case .TypePrimitive;
        primitive := cast(*AstTypePrimitive, node);

        AddSubexpression(dependency_node, node);

    case .Run;
        run := cast(*AstRun, node);
        CollectDependencyNodes(dependency_node, run);

    case .Import;
        import := cast(*AstImport, node);

        CollectSubexpressionsFromLeftToRight(dependency_node, import.expr, flags);
        AddSubexpression(dependency_node, node);

    case .Function;
        func := cast(*AstFunction, node);
        CollectDependencyNodes(dependency_node, func);

    case .FunctionOverloadSet;
        set := cast(*AstFunctionOverloadSet, node);
        CollectDependencyNodes(dependency_node, set);

    case .Struct;
        struct_node := cast(*AstStruct, node);
        CollectDependencyNodes(dependency_node, struct_node);

    case .Enum;
        enum_node := cast(*AstEnum, node);
        CollectDependencyNodes(dependency_node, enum_node);

    case .Context;
        AddSubexpression(dependency_node, node);
        AddUnresolvedIdentifier(dependency_node, "Context", 0, parent_field_access=parent_field_access, look_in_scope=node.enclosing_scope.program.scope);

    case .Identifier;
        ident := cast(*AstIdentifier, node);

        AddSubexpression(dependency_node, node);

        if (ident.ident_flags & .ImplicitDeclaration) {
            Assert(ident, ident.symbol != null, "Identifier declares a symbol, but the symbol has not been created");
            decl := ident.symbol.decl;

            CollectDependencyNodes(null, decl);
            AddDependency(decl.dependency_node, dependency_node, 0);
        } else if !(ident.ident_flags & .DoNotResolve) {
            AddUnresolvedIdentifier(dependency_node, ident, flags, parent_field_access=parent_field_access);
        }

    case .Literal;
        AddSubexpression(dependency_node, node);

    case .StructLiteral;
        lit := cast(*AstStructLiteral, node);
        CollectSubexpressionsFromLeftToRight(dependency_node, lit.type_node, flags);

        for lit.values {
            CollectSubexpressionsFromLeftToRight(dependency_node, it, flags);
        }

        AddSubexpression(dependency_node, node);

    case .Binary;
        binary := cast(*AstBinary, node);
        CollectSubexpressionsFromLeftToRight(dependency_node, binary.left, flags);

        PushTypeHint(dependency_node, *binary.left.type);

        CollectSubexpressionsFromLeftToRight(dependency_node, binary.right, flags);

        PopTypeHint(dependency_node);

        AddSubexpression(dependency_node, node);

    case .Unary;
        unary := cast(*AstUnary, node);
        CollectSubexpressionsFromLeftToRight(dependency_node, unary.expr, flags);
        AddSubexpression(dependency_node, node);

    case .FieldAccess;
        access := cast(*AstFieldAccess, node);
        if access.left {
            CollectSubexpressionsFromLeftToRight(dependency_node, access.left, flags, parent_field_access=access);
        }

        CollectSubexpressionsFromLeftToRight(dependency_node, access.right, flags | .FieldAccessRHS, parent_field_access=access);

        AddSubexpression(dependency_node, node);

    case .FunctionCall;
        call := cast(*AstFunctionCall, node);
        CollectSubexpressionsFromLeftToRight(dependency_node, call.callee, flags | .Callee);

        for call.passed_arguments {
            PushTypeHint(dependency_node, call, it_index, (node : *AstNode, index : int) -> *YalType {
                call := cast(*AstFunctionCall, node);
                if !call.callee.type {
                    return null;
                }

                if call.callee.type.kind == {
                case .Function;
                    func_type := cast(*YalTypeFunction, call.callee.type);
                    if index >= func_type.parameters.count {
                        return null;
                    }

                    return func_type.parameters[index];

                case .TypeId;
                    if call.callee.value.kind != .TypeId {
                        return null;
                    }

                    inst_type := call.callee.value.type_value;
                    if inst_type.kind == .Struct {
                        struct_type := cast(*YalTypeStruct, inst_type);

                        if index >= struct_type.parameters.count {
                            return null;
                        }

                        return struct_type.parameters[index];
                    }
                }

                return null;
            });

            CollectSubexpressionsFromLeftToRight(dependency_node, it, flags);

            PopTypeHint(dependency_node);
        }

        AddSubexpression(dependency_node, node);

    case .Subscript;
        subscript := cast(*AstSubscript, node);
        CollectSubexpressionsFromLeftToRight(dependency_node, subscript.subscripted, flags);
        CollectSubexpressionsFromLeftToRight(dependency_node, subscript.index, flags);
        AddSubexpression(dependency_node, node);

    case .Cast;
        cast_expr := cast(*AstCast, node);
        CollectSubexpressionsFromLeftToRight(dependency_node, cast_expr.type_node, flags);
        CollectSubexpressionsFromLeftToRight(dependency_node, cast_expr.expr, flags);
        AddSubexpression(dependency_node, node);

    case .SizeOf;
        size_of_expr := cast(*AstSizeOf, node);
        CollectSubexpressionsFromLeftToRight(dependency_node, size_of_expr.type_node, flags);
        AddSubexpression(dependency_node, node);

    case .TypeOf;
        type_of_expr := cast(*AstTypeOf, node);
        CollectSubexpressionsFromLeftToRight(dependency_node, type_of_expr.expr, flags);
        AddSubexpression(dependency_node, node);

    case .Range;
        range_expr := cast(*AstRange, node);
        CollectSubexpressionsFromLeftToRight(dependency_node, range_expr.start, flags);

        PushTypeHint(dependency_node, *range_expr.start.type);

        CollectSubexpressionsFromLeftToRight(dependency_node, range_expr.end, flags);

        PopTypeHint(dependency_node);

        AddSubexpression(dependency_node, node);

    case .Argument;
        arg := cast(*AstArgument, node);
        CollectSubexpressionsFromLeftToRight(dependency_node, arg.name, flags);
        CollectSubexpressionsFromLeftToRight(dependency_node, arg.expr, flags);
        AddSubexpression(dependency_node, node);

    case;
        Panic(node, "Unhandled node kind %", node.kind);
    }
}

CollectDependencyNodes :: (parent_dep : *DependencyNode, node : *AstNode) {
    Assert(node != null);

    // Probably fine to assume revisiting nodes does not mean we fucked up
    if node.dependency_node {
        return;
    }

    DbgInfo(.Dependencies, node, "CollectDependencyNodes");

    if #complete node.kind == {
    case .Invalid; #through;
    case .StatementsBegin; #through;
    case .StatementsEnd; #through;
    case .ExpressionsBegin; #through;
    case .ExpressionsEnd; #through;
    case .Count;
        Panic(node, "Invalid node type %", node.kind);

    case .Declaration;
        decl := cast(*AstDeclaration, node);

        CreateDependencyNode(parent_dep, decl);

        if decl.decl_kind == .TemplateParam && decl.identifier && decl.identifier.ident_flags & .ImplicitDeclaration {
            return;
        }

        if #complete decl.decl_kind == {
        case .Invalid;
        case .ForLoopIndex; #through;
        case .TemplateParam; #through;
        case .Variable; #through;
        case .Constant; #through;
        case .Field;
            if decl.type_node {
                CollectDependencyNodes(decl.dependency_node, decl.type_node);
            }

            if decl.expr {
                CollectDependencyNodes(decl.dependency_node, decl.expr);

                if decl.type_node {
                    decl.expr.dependency_node.type_hint = *decl.type_node.value.type_value;
                    AddDependency(decl.expr.dependency_node, decl.type_node.dependency_node, 0);
                }
            }

        case .EnumMember;
            if decl.expr {
                CollectDependencyNodes(decl.dependency_node, decl.expr);

                body := cast(*AstBlock, parent_dep.ast_node);
                enum_node := body.parent_enum;

                if enum_node.base_type {
                    AddDependency(decl.expr.dependency_node, enum_node.base_type.dependency_node, 0);
                }
            } else {
                body := cast(*AstBlock, parent_dep.ast_node);
                statement_index := GetStatementIndex(body, decl);
                if statement_index > 0 {
                    // Make the enum member depend on the previous member
                    previous_statement := body.statements[statement_index - 1];
                    AddDependency(decl.dependency_node, previous_statement.dependency_node, 0);
                }
            }
        }

    case .If;
        if_stmt := cast(*AstIf, node);
        CreateDependencyNode(parent_dep, if_stmt);

        CollectDependencyNodes(if_stmt.dependency_node, if_stmt.condition);

        if !if_stmt.is_compile_time {
            CollectDependencyNodes(if_stmt.dependency_node, if_stmt.body);
            if if_stmt.else_stmt {
                CollectDependencyNodes(if_stmt.dependency_node, if_stmt.else_stmt);
            }
        }

    case .Block;
        block := cast(*AstBlock, node);

        CreateDependencyNode(parent_dep, block);

        for block.statements {
            CollectDependencyNodes(block.dependency_node, it);
        }

    case .While;
        while_stmt := cast(*AstWhile, node);
        CreateDependencyNode(parent_dep, while_stmt);

        CollectDependencyNodes(while_stmt.dependency_node, while_stmt.condition);
        CollectDependencyNodes(while_stmt.dependency_node, while_stmt.body);

    case .For;
        for_stmt := cast(*AstFor, node);
        CreateDependencyNode(parent_dep, for_stmt);

        CollectDependencyNodes(for_stmt.dependency_node, for_stmt.iterator);
        CollectDependencyNodes(for_stmt.dependency_node, for_stmt.body);

    case .Assignment;
        assign := cast(*AstAssignment, node);
        CreateDependencyNode(parent_dep, assign);

        CollectDependencyNodes(assign.dependency_node, assign.left);
        CollectDependencyNodes(assign.dependency_node, assign.right);

        AddDependency(assign.right.dependency_node, assign.left.dependency_node, 0);

        assign.right.dependency_node.type_hint = *assign.left.type;

    case .Defer;
        stmt := cast(*AstDefer, node);
        CreateDependencyNode(parent_dep, stmt);

        CollectDependencyNodes(stmt.dependency_node, stmt.stmt);

    case .Return;
        ret := cast(*AstReturn, node);
        CreateDependencyNode(parent_dep, ret);

        if ret.enclosing_scope.enclosing_function {
            AddDependency(ret.dependency_node, ret.enclosing_scope.enclosing_function.dependency_node, 0);
        }

        if ret.expr {
            CollectDependencyNodes(ret.dependency_node, ret.expr);

            // @Todo: type hint
        }

    case .FlowControl;
        CreateDependencyNode(parent_dep, node);

    case .Assert;
        assert := cast(*AstAssert, node);
        CreateDependencyNode(parent_dep, assert);

        CollectDependencyNodes(assert.dependency_node, assert.expr);

        if assert.message {
            CollectDependencyNodes(assert.dependency_node, assert.message);
        }

    case .Include;
        CreateDependencyNode(parent_dep, node);

    case .Run;
        run := cast(*AstRun, node);
        CreateDependencyNode(parent_dep, run);

        CollectDependencyNodes(run.dependency_node, run.expr);

    case .Insert;
        insert := cast(*AstInsert, node);
        CreateDependencyNode(parent_dep, insert);

        CollectDependencyNodes(insert.dependency_node, insert.expr);

    case .Enum;
        enum_node := cast(*AstEnum, node);

        decl : *AstDeclaration;
        if parent_dep && parent_dep.ast_node.kind == .Declaration && cast(*AstDeclaration, parent_dep.ast_node).expr == enum_node {
            decl = xx parent_dep.ast_node;
        }

        name := ifx decl then decl.identifier.name else "";
        // Create the type here so it's ready for the checking phase
        enum_node.defined_type = MakeTypeEnum(enum_node, name, null);

        enum_node.type = g_type_type_id;
        enum_node.semantic_meaning = .Constant;
        enum_node.value = .{kind=.TypeId, type_value=enum_node.defined_type};

        if decl {
            SetDeclarationType(decl, g_type_type_id);
            decl.value = enum_node.value;
        }

        CreateDependencyNode(parent_dep, enum_node);

        if enum_node.base_type {
            CollectDependencyNodes(enum_node.dependency_node, enum_node.base_type);
        }

        CollectDependencyNodes(enum_node.dependency_node, enum_node.body);

    case .Struct;
        struct_node := cast(*AstStruct, node);

        decl : *AstDeclaration;
        if parent_dep && parent_dep.ast_node.kind == .Declaration && cast(*AstDeclaration, parent_dep.ast_node).expr == struct_node {
            decl = xx parent_dep.ast_node;
        }

        name := ifx decl then decl.identifier.name else "";
        // Create the type here so it's ready for the checking phase
        struct_node.defined_type = MakeTypeStruct(struct_node, name, struct_node.is_union);

        struct_node.type = g_type_type_id;
        struct_node.semantic_meaning = .Constant;
        struct_node.value = .{kind=.TypeId, type_value=struct_node.defined_type};

        if decl {
            SetDeclarationType(decl, g_type_type_id);
            decl.value = struct_node.value;
        }

        CreateDependencyNode(parent_dep, struct_node);

        for struct_node.parameters {
            CollectDependencyNodes(struct_node.dependency_node, it);
        }

        if !IsStructTemplate(struct_node) {
            CollectDependencyNodes(struct_node.dependency_node, struct_node.body);
        }

        if struct_node.template_instantiation_index >= 0 {
            inst := *struct_node.template_source.template_instantiations[struct_node.template_instantiation_index];
            for inst.dependents {
                AddDependency(it, struct_node.dependency_node, 0);
            }

            ArrayClear(*inst.dependents);
        }

    case .Function;
        func := cast(*AstFunction, node);

        CreateDependencyNode(parent_dep, func);

        for func.parameters {
            CollectDependencyNodes(func.dependency_node, it);
        }
        if func.result {
            CollectDependencyNodes(func.dependency_node, func.result);
        }

        if func.body && !IsFunctionTemplate(func) {
            CollectDependencyNodes(parent_dep, func.body);
        }

        if func.template_instantiation_index >= 0 {
            inst := *func.template_source.template_instantiations[func.template_instantiation_index];
            for inst.dependents {
                AddDependency(it, func.dependency_node, .Callee);
                AddDependency(it, func.body.dependency_node, 0);
            }

            ArrayClear(*inst.dependents);
        }

    case .FunctionOverloadSet;
        set := cast(*AstFunctionOverloadSet, node);

        CreateDependencyNode(parent_dep, set);
        CollectDependencyNodes(set.dependency_node, set.body);

    case .Attribute;
        attr := cast(*AstAttribute, node);

        CreateDependencyNode(parent_dep, node);

        for attr.arguments {
            CollectSubexpressionsFromLeftToRight(node.dependency_node, it, 0);
        }

    case .TypeOf; #through;
    case .TypePointer; #through;
    case .TypeArray; #through;
    case .TypePrimitive; #through;
    case .Context; #through;
    case .Identifier; #through;
    case .Literal; #through;
    case .StructLiteral; #through;
    case .Binary; #through;
    case .Unary; #through;
    case .FieldAccess; #through;
    case .FunctionCall; #through;
    case .Subscript; #through;
    case .Cast; #through;
    case .Import; #through;
    case .Range; #through;
    case .Argument; #through;
    case .SizeOf;
        Assert(node, IsExpression(node.kind), "Should be an expression");

        CreateDependencyNode(parent_dep, node);

        CollectSubexpressionsFromLeftToRight(node.dependency_node, node, 0);
    }
}

CreateDependencyGraphForNewlyAddedNodes :: (program : *YalProgram) {
    for scope : program.modified_scopes {
        enclosing_func : *AstFunction;
        if scope.kind == .Function {
            enclosing_func = scope.function;
        } else {
            enclosing_func = scope.enclosing_function;
        }

        enclosing_struct : *AstStruct;
        if scope.kind == .Struct {
            enclosing_struct = scope.struct_node;
        } else {
            enclosing_struct = scope.enclosing_struct;
        }

        if enclosing_func && IsFunctionTemplate(enclosing_func) {
            continue;
        }

        if enclosing_struct && IsStructTemplate(enclosing_struct) {
            continue;
        }

        parent_dep : *DependencyNode;
        if scope.kind == .Struct || scope.kind == .Function || scope.kind == .Statement {
            parent_dep = scope.statement.dependency_node;
            Assert(scope.statement, parent_dep != null, "Dependency node is null");
        }

        for scope.newly_added_statements {
            CollectDependencyNodes(parent_dep, it);
        }
    }
}

FlattenedDependencyGraph :: struct {
    VisitedNode :: struct {
        node : *DependencyNode;
        flatten_result : FlattenDependencyGraphResult;
        index := -1;
    }

    node_stack : [..]Dependency;
    visited_nodes : HashSet(VisitedNode, hash_func=(n) => get_hash(n.node), comp_func=(a, b) => a.node == b.node);
    nodes : [..]*DependencyNode;
}

SetAllocators :: (using graph : *FlattenedDependencyGraph, allocator : Allocator) {
    node_stack.allocator = allocator;
    visited_nodes.allocator = allocator;
    nodes.allocator = allocator;
}

FreeGraph :: (using graph : *FlattenedDependencyGraph) {
    ArrayFree(*node_stack);
    ArrayFree(*nodes);
    HashSetFree(*visited_nodes);
}

GetVisitedNode :: inline (graph : *FlattenedDependencyGraph, node : *DependencyNode) -> *FlattenedDependencyGraph.VisitedNode {
    return HashSetGetPtr(*graph.visited_nodes, .{node=node});
}

MarkNodeAsVisited :: inline (graph : *FlattenedDependencyGraph, node : *DependencyNode) -> *FlattenedDependencyGraph.VisitedNode, already_visited : bool {
    node, already_visited := HashSetInsert(*graph.visited_nodes, .{node=node});

    return node, already_visited;
}

PushVisitedNode :: inline (graph : *FlattenedDependencyGraph, node : *DependencyNode) {
    ptr := GetVisitedNode(graph, node);

    Assert(ptr != null && ptr.index < 0);
    ptr.index = graph.nodes.count;

    ArrayPush(*graph.nodes, node);
}

FlattenDependencyGraphResult :: enum_flags {
    BlockedByBlockingStatement; // Blocked by #if, #run, #insert etc
    BlockedByCompileTimeExecution; // Blocked because a depending #run has not been been executed yet
    BlockedByUnresolvedIdentifiers; // Blocked because some identifiers could not be resolved
    BlockedByPendingTemplateInstantiations; // Blocked because some template is referenced and needs to be instantiated
}

FlattenDependencyGraphForChecking :: (graph : *FlattenedDependencyGraph, scope : *Scope) -> FlattenDependencyGraphResult {
    result : FlattenDependencyGraphResult;
    for scope.all_dependency_nodes {
        result |= FlattenDependencyGraphForChecking(graph, .{node=it});
    }

    for :Children scope {
        result |= FlattenDependencyGraphForChecking(graph, it);
    }

    return result;
}

FlattenDependencyGraphForChecking :: (graph : *FlattenedDependencyGraph, dependency : Dependency, cumulative_flags : DependencyFlags = 0) -> FlattenDependencyGraphResult {
    // Not sure that cumulative_flags thing is always correct, but we'll see
    if dependency.flags & .Weak {
        cumulative_flags |= .Weak;
    }

    if ArrayFindLast(graph.node_stack, dependency, (a, b) => a.node == b.node) >= 0 {
        if cumulative_flags & .Weak {
            visited := GetVisitedNode(graph, dependency.node);
            Assert(visited != null);

            return visited.flatten_result;
        }

        ReportCircularDependencyErrorAndExit(graph, dependency.ast_node);
    }

    if dependency.node.check_status >= .Checked {
        if dependency.flags & .ForExecution && dependency.node.check_status != .Executed {
            return .BlockedByCompileTimeExecution;
        }

        return 0;
    }

    visited, already_visited := MarkNodeAsVisited(graph, dependency.node);
    if already_visited {
        return visited.flatten_result;
    }

    ArrayPush(*graph.node_stack, dependency);
    defer ArrayPop(*graph.node_stack);

    defer if visited.flatten_result != 0 {
        DbgInfo(.Dependencies, dependency.ast_node, "Blocked: %", visited.flatten_result);
    }

    if dependency.node.num_pending_template_instantiations > 0 {
        visited.flatten_result |= .BlockedByPendingTemplateInstantiations;
    }

    if dependency.node.unresolved_identifiers.count > 0 {
        for dependency.node.unresolved_identifiers {
            if it.identifier {
                DbgInfo(.Dependencies, it.identifier, "Unresolved");
            } else {
                DbgInfo(.Dependencies, dependency.ast_node, "Unresolved '%'", it.name);
            }
        }

        visited.flatten_result |= .BlockedByUnresolvedIdentifiers;
    }

    dependencies_flatten_result : FlattenDependencyGraphResult;
    for dependency.node.dependencies {
        dependencies_flatten_result |= FlattenDependencyGraphForChecking(graph, it, cumulative_flags);
    }

    visited = GetVisitedNode(graph, dependency.node);
    visited.flatten_result |= dependencies_flatten_result;

    if visited.flatten_result == 0 || (IsExpression(dependency.ast_node.kind) && dependencies_flatten_result == 0) {
        PushVisitedNode(graph, dependency.node);

        if dependency.ast_node.kind == {
        case .If;
            if_stmt := cast(*AstIf, dependency.ast_node);
            if if_stmt.is_compile_time {
                visited.flatten_result |= .BlockedByBlockingStatement;
            }

        case .Run; #through;
        case .Insert;
            visited.flatten_result |= .BlockedByBlockingStatement;
        }
    }

    return visited.flatten_result;
}

ReportCircularDependencyErrorAndExit :: (graph : *FlattenedDependencyGraph, node : *AstNode) {
    file := GetFile(node.file_id);
    Assert(file != null);

    ErrorNoSquiggles(node, "Circular dependency detected");

    builder : StringBuilder;

    Append(*builder, "Dependency chain (most recent first):\n\n");
    for < graph.node_stack {
        file := GetFile(it.node.ast_node.file_id);
        Assert(file != null);

        Append(*builder, "%:%:%\n", ShortenFilename(file.filename), it.node.ast_node.line_start, it.node.ast_node.char_start);
        PrintTokenLine(*builder, it.node.ast_node ,, print_squiggles=false);
    }

    Print(StringBuilderBuild(*builder), to_standard_error=true);

    SetOutputColor(.Error);
    Println("Exiting...", to_standard_error=true);
    SetOutputColor(.None);

    Basic.exit(1);
}

#if Enable_Debug_Print {

DbgPrintDependencyNodes :: ($channel : DebugLogChannel, nodes : [..]*DependencyNode) #expand {
    if !(g_build_settings.debug_log & channel) {
        return;
    }

    Println("% nodes", nodes.count);
    for nodes {
        str := TokenRangeToStringFirstLine(it.ast_node);

        if it.ast_node.kind == .Struct && IsStructTemplate(xx it.ast_node) {
            Println("  [%] template %", it_index, str);
        } else if it.ast_node.kind == .Function && IsFunctionTemplate(xx it.ast_node) {
            Println("  [%] template %", it_index, str);
        } else {
            Println("  [%] %", it_index, str);
        }
    }

    Print("\n");
}

} else {

DbgPrintDependencyNodes :: ($channel : DebugLogChannel, #discard nodes : [..]*DependencyNode) #expand {
}

}
