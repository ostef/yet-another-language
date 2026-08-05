// @Todo: redeclaring a variable in a function body does
// not give an identifier redeclaration error if the same
// name exists in the function signature.
// Should we handle that as an error ?

Scope :: struct {
    parent : *Scope;
    first_child : *Scope;
    prev : *Scope;
    next : *Scope;

    first_symbol : *Symbol;
    last_symbol : *Symbol;

    // Only the first declared symbol ends up here, if
    // a symbol is redeclared, it is not added to the table
    symbols : HashMap(string, *Symbol);
    imported_symbols : HashMap(string, *ImportedSymbol);

    importing_scopes : [..]ImportingScope; // When a symbol gets added, it also gets added to all the importing scopes, recursively

    all_statements : [..]*AstNode;
    all_dependency_nodes : [..]*DependencyNode;
    newly_added_statements : [..]*AstNode;

    program : *YalProgram;
    enclosing_statement : *AstNode;
    enclosing_function : *AstFunction;
    enclosing_struct : *AstStruct;
    enclosing_file : *YalFile;
    enclosing_module : *YalModule;

    union {
        file : *YalFile;
        module : *YalModule;
        function : *AstFunction;
        struct_node : *AstStruct;
        statement : *AstNode;
    };

    template_context : bool;
    kind : ScopeKind;
}

ScopeKind :: enum u8 {
    Invalid;

    Global;
    Module;
    File;
    Function;
    Struct;
    Statement;
}

IsTopLevelScope :: inline (scope : *Scope) -> bool {
    return IsTopLevelScope(scope.kind);
}

IsTopLevelScope :: inline (kind : ScopeKind) -> bool {
    return kind == .File || kind == .Module || kind == .Global;
}

GetNodeOfScope :: (scope : *Scope, kind : AstKind) -> *AstNode {
    if kind == .Struct && scope.kind == .Struct {
        return scope.statement;
    }
    if kind == .Function && scope.kind == .Function {
        return scope.statement;
    }

    if scope.kind != .Statement {
        return null;
    }

    if scope.statement.kind != .Block {
        return null;
    }

    block := cast(*AstBlock, scope.statement);
    if !block.parent_expr || block.parent_expr.kind != kind {
        return null;
    }

    return block.parent_expr;
}

GetStructOfScope :: inline (scope : *Scope) -> *AstStruct {
    return xx GetNodeOfScope(scope, .Struct);
}

GetEnumOfScope :: inline (scope : *Scope) -> *AstEnum {
    return xx GetNodeOfScope(scope, .Enum);
}

GetFunctionOfScope :: inline (scope : *Scope) -> *AstFunction {
    return xx GetNodeOfScope(scope, .Function);
}

GetFunctionOverloadSetOfScope :: inline (scope : *Scope) -> *AstFunctionOverloadSet {
    return xx GetNodeOfScope(scope, .FunctionOverloadSet);
}

ClearAddedCode :: (program : *YalProgram) {
    for program.modified_scopes {
        ArrayClear(*it.newly_added_statements);
    }

    ArrayClear(*program.modified_scopes);
    program.added_new_code = false;
}

AddStatement :: (scope : *Scope, node : *AstNode, insert_at_index := -1) {
    if !node {
        return;
    }

    DbgInfo(.Scopes, node, "Adding statement % to scope %", node, scope);

    #if Enable_Asserts {
        if ArrayFindFirst(scope.all_statements, node) >= 0 {
            Error(node, "Statement is already present in scope");
            if scope.kind == .Function || scope.kind == .Statement || scope.kind == .Struct {
                DbgInfo(.Scopes, scope.statement, "In this scope");
            }
            Panic();
        }
    }

    if insert_at_index < 0 {
        insert_at_index = scope.all_statements.count;
    }

    ArrayOrderedInsert(*scope.all_statements, insert_at_index, node);
    ArrayPush(*scope.newly_added_statements, node);

    scope.program.added_new_code = true;

    ArrayPushUnique(*scope.program.modified_scopes, scope);
}

Children :: (scope : *Scope, body : Code, flags : For_Flags) #expand {
    `it := scope.first_child;
    `it_index := 0;
    while it {
        next := it.next;
        defer {
            it_index += 1;
            it = next;
        }

        #insert body;
    }
}

SymbolKind :: enum u8 {
    Invalid;
    Variable;
    Constant;
    TemplateParam;
}

Symbol :: struct {
    scope : *Scope;
    prev, next : *Symbol;

    name : string;
    ir_symbol : *IRSymbol;
    decl : *AstDeclaration;
    kind : SymbolKind;
    template_param_index : s8;
}

ScopeCreate :: (parent : *Scope, kind : ScopeKind) -> *Scope {
    if kind != .Global {
        Assert(parent != null);
    }

    scope := Alloc(Scope);
    scope.kind = kind;

    scope.parent = parent;
    if parent {
        scope.template_context = parent.template_context;

        if !parent.first_child {
            parent.first_child = scope;
        } else {
            sibling := parent.first_child;
            while sibling && sibling.next {
                sibling = sibling.next;
            }

            sibling.next = scope;
            scope.prev = sibling;
        }

        scope.program = parent.program;
        Assert(scope.program != null);

        scope.program.num_scopes += 1;

        if parent.kind == .Module {
            scope.enclosing_module = parent.module;
        } else {
            scope.enclosing_module = parent.enclosing_module;
        }

        if parent.kind == .File {
            scope.enclosing_file = parent.file;
        } else {
            scope.enclosing_file = parent.enclosing_file;
        }

        if parent.kind == .Statement {
            scope.enclosing_statement = parent.statement;
        } else {
            scope.enclosing_statement = parent.enclosing_statement;
        }

        if parent.kind == .Function {
            scope.enclosing_function = parent.function;
        } else {
            scope.enclosing_function = parent.enclosing_function;
        }

        if parent.kind == .Struct {
            scope.enclosing_struct = parent.struct_node;
        } else {
            scope.enclosing_struct = parent.enclosing_struct;
        }
    }

    return scope;
}

ScopeCreate :: inline (program : *YalProgram, module : *YalModule) -> *Scope {
    Assert(module.scope == null);

    scope := ScopeCreate(program.scope, .Module);
    scope.module = module;
    scope.enclosing_module = module;
    module.scope = scope;

    return scope;
}

ScopeCreate :: inline (program : *YalProgram, file : *YalFile) -> *Scope {
    Assert(file.scope == null);

    scope := ScopeCreate(program.scope, .File);
    scope.file = file;
    file.scope = scope;

    return scope;
}

ScopeCreate :: inline (module : *YalModule, file : *YalFile) -> *Scope {
    Assert(file.scope == null);

    scope := ScopeCreate(module.scope, .File);
    scope.file = file;
    file.scope = scope;

    return scope;
}

ScopeCreate :: inline (parent : *Scope, if_stmt : *AstIf) {
    Assert(if_stmt, if_stmt.if_scope == null, "if scope has already been created");
    Assert(if_stmt, if_stmt.else_scope == null, "else scope has already been created");
    Assert(parent != null);

    scope := ScopeCreate(parent, .Statement);
    scope.statement = if_stmt;
    if_stmt.if_scope = scope;
    DbgInfo(.Scopes, if_stmt, "ScopeCreate");

    if if_stmt.else_stmt {
        else_scope := ScopeCreate(parent, .Statement);
        else_scope.statement = if_stmt;
        if_stmt.else_scope = else_scope;
        DbgInfo(.Scopes, if_stmt, "ScopeCreate");
    }
}

ScopeCreate :: inline (parent : *Scope, while_stmt : *AstWhile) -> *Scope {
    Assert(while_stmt, while_stmt.scope == null, "while scope has already been created");
    Assert(parent != null);

    scope := ScopeCreate(parent, .Statement);
    scope.statement = while_stmt;
    while_stmt.scope = scope;
    DbgInfo(.Scopes, while_stmt, "ScopeCreate");

    return scope;
}

ScopeCreate :: inline (parent : *Scope, for_stmt : *AstFor) -> *Scope {
    Assert(for_stmt, for_stmt.scope == null, "for scope has already been created");
    Assert(parent != null);

    scope := ScopeCreate(parent, .Statement);
    scope.statement = for_stmt;
    for_stmt.scope = scope;
    DbgInfo(.Scopes, for_stmt, "ScopeCreate");

    return scope;
}

ScopeCreate :: inline (parent : *Scope, block : *AstBlock) -> *Scope {
    Assert(block, block.scope == null, "Block scope has already been created");
    Assert(parent != null);

    scope := ScopeCreate(parent, .Statement);
    scope.statement = block;
    block.scope = scope;
    DbgInfo(.Scopes, block, "ScopeCreate");

    return scope;
}

ScopeCreate :: inline (parent : *Scope, defer_stmt : *AstDefer) -> *Scope {
    Assert(defer_stmt, defer_stmt.scope == null, "defer scope has already been created");
    Assert(parent != null);

    scope := ScopeCreate(parent, .Statement);
    scope.statement = defer_stmt;
    defer_stmt.scope = scope;
    DbgInfo(.Scopes, defer_stmt, "ScopeCreate");

    return scope;
}

ScopeCreate :: inline (parent : *Scope, run : *AstRun) -> *Scope {
    Assert(run, run.scope == null, "#run scope has already been created");
    Assert(parent != null);

    scope := ScopeCreate(parent, .Statement);
    scope.statement = run;
    run.scope = scope;
    DbgInfo(.Scopes, run, "ScopeCreate");

    return scope;
}

ScopeCreate :: inline (parent : *Scope, insert : *AstInsert) -> *Scope {
    Assert(insert, insert.scope == null, "#insert scope has already been created");
    Assert(parent != null);

    scope := ScopeCreate(parent, .Statement);
    scope.statement = insert;
    insert.scope = scope;
    DbgInfo(.Scopes, insert, "ScopeCreate");

    return scope;
}

ScopeCreate :: inline (parent : *Scope, function : *AstFunction) -> *Scope {
    Assert(function, function.scope == null, "Function scope has already been created");
    Assert(parent != null);

    scope := ScopeCreate(parent, .Function);
    scope.function = function;
    function.scope = scope;
    DbgInfo(.Scopes, function, "ScopeCreate");

    return scope;
}

ScopeCreate :: inline (parent : *Scope, struct_node : *AstStruct) -> *Scope {
    Assert(struct_node, struct_node.scope == null, "Struct scope has already been created");
    Assert(parent != null);

    scope := ScopeCreate(parent, .Struct);
    scope.struct_node = struct_node;
    struct_node.scope = scope;
    DbgInfo(.Scopes, struct_node, "ScopeCreate");

    return scope;
}

InsertSymbol :: (scope : *Scope, symbol : *Symbol, parent_statement : *AstNode) {
    Assert(symbol.scope == scope, "Scope mismatch");

    SetTemplateContextFlag :: (scope : *Scope) {
        scope.template_context = true;

        for :Children scope {
            SetTemplateContextFlag(it);
        }
    }

    if scope.last_symbol {
        symbol.prev = scope.last_symbol;
        scope.last_symbol.next = symbol;
        scope.last_symbol = symbol;
    } else {
        scope.first_symbol = symbol;
        scope.last_symbol = symbol;
    }

    if symbol.kind == .TemplateParam {
        if !scope.template_context {
            SetTemplateContextFlag(scope);
        }

        param_index := ArrayFindFirst(scope.all_statements, parent_statement);
        Assert(symbol.decl, param_index >= 0, "Could not find the parent statement in the scope's all_statements array");

        if scope.kind == {
        case .Function;
            symbol.template_param_index = xx scope.function.template_params.count;
            ArrayPush(*scope.function.template_params, .{param_index=xx param_index, decl=symbol.decl});
        case .Struct;
            symbol.template_param_index = xx scope.struct_node.template_params.count;
            ArrayPush(*scope.struct_node.template_params, .{param_index=xx param_index, decl=symbol.decl});
        }
    }

    if scope.kind == .Function || scope.kind == .Struct || scope.kind == .Statement {
        DbgInfo(.Scopes, scope.statement, "InsertSymbol '%'", symbol.name);
    } else {
        DbgPrintln(.Scopes, "InsertSymbol '%'", symbol.name);
    }

    if !CheckRedeclaration(scope, symbol) {
        return;
    }

    HashMapInsert(*scope.symbols, symbol.name, symbol);

    // Export the symbol to the importing scopes
    for scope.importing_scopes {
        ImportSymbol(it.scope, symbol, it.source_using);
    }
}

ScopeInsert :: (scope : *Scope, decl : *AstDeclaration, parent_statement : *AstNode) -> *Symbol {
    Assert(scope != null);

    if !decl || !decl.identifier {
        return null;
    }

    symbol_kind : SymbolKind;
    if decl.identifier.ident_flags & .TemplateParam {
        symbol_kind = .TemplateParam;
    } else if #complete decl.decl_kind == {
    case .Variable; #through;
    case .Field; #through;
    case .ForLoopIndex;
        symbol_kind = .Variable;

    case .Constant;
        symbol_kind = .Constant;

    case .EnumMember;
        symbol_kind = .Constant;

    case .TemplateParam;
        symbol_kind = .TemplateParam;

    case .Invalid;
        Panic(decl, "Invalid declaration kind %", decl.decl_kind);
    }

    if decl.identifier.name == "s128" || decl.identifier.name == "u128" {
        Error(decl.identifier, "This identifier is reserved for future use");
    }

    if StringStartsWith(decl.identifier.name, "Yal__") {
        Error(decl.identifier, "Identifiers starting with Yal__ are reserved");
    }

    if scope.kind == .Global {
        if decl.identifier.name == {
        case "Allocator";
            scope.program.allocator_declaration = decl;
        case "Context";
            scope.program.context_declaration = decl;
        }
    } else if scope == scope.program.main_module.scope {
        if decl.identifier.name == {
        case "main";
            scope.program.entry_point_declaration = decl;
        }
    }

    symbol := Alloc(Symbol);
    symbol.scope = scope;
    symbol.name = decl.identifier.name;
    symbol.kind = symbol_kind;
    symbol.decl = decl;
    decl.identifier.symbol = symbol;
    InsertSymbol(scope, symbol, parent_statement);

    return symbol;
}

ScopeInsert :: (scope : *Scope, ident : *AstIdentifier, parent_statement : *AstNode) -> *Symbol {
    Assert(ident, (ident.ident_flags & .ImplicitDeclaration) != 0, "Inserting new symbol for identifier that is not an implicit declaration");

    symbol := Alloc(Symbol);
    symbol.scope = scope;
    symbol.name = ident.name;

    if ident.ident_flags & .TemplateParam {
        symbol.kind = .TemplateParam;
        symbol.decl = MakeAstDeclaration(.{range=ident, kind=.Identifier}, ident, null, null, .TemplateParam);
    } else {
        symbol.kind = .Variable;
        symbol.decl = MakeAstDeclaration(.{range=ident, kind=.Identifier}, ident, null, null, .Variable);
    }

    SetEnclosingScopes(scope, symbol.decl);

    ident.symbol = symbol;
    InsertSymbol(scope, symbol, parent_statement);

    return symbol;
}

CheckRedeclaration :: (scope : *Scope, symbol : *Symbol, source_using : *AstNode = null) -> bool {
    original, imported := ScopeLookupCurrent(scope, symbol.name);
    if original {
        // Importing the same symbol is fine for constants and template params
        if original == symbol && (symbol.kind == .Constant || symbol.kind == .TemplateParam) {
            return false;
        }

        if source_using {
            Error(source_using, "`using` shadows identifier '%'", symbol.name);
        } else {
            Error(symbol.decl, "Redeclaration of identifier '%'", symbol.name);
        }

        if imported {
            Info(imported.source_using, "'%' was imported by this `using`", symbol.name);
        }

        if source_using {
            Info(original.decl, "Here is the declaration of '%' that is being shadowed", symbol.name);
            Info(symbol.decl, "Here is the declaration of '%' inside the scope being imported", symbol.name);
        } else {
            Info(original.decl, "Here is the first declaration of '%'", symbol.name);
        }

        return false;
    }

    return true;
}

ImportingScope :: struct {
    source_using : *AstNode;
    scope : *Scope;
}

ImportedSymbol :: struct {
    source_using : *AstNode;
    source_import : *ImportedSymbol;
    final_symbol : *Symbol;
}

ImportScope :: (into : *Scope, to_import : *Scope, source_using : *AstNode) {
    importing := ImportingScope.{scope=into, source_using=source_using};
    if ArrayFindFirst(to_import.importing_scopes, importing, (a, b) => memcmp(*a, *b, size_of(ImportingScope)) == 0) >= 0 {
        return;
    }

    ArrayPush(*to_import.importing_scopes, importing);

    for to_import.symbols {
        ImportSymbol(into, it, source_using);
    }

    for to_import.imported_symbols {
        ImportSymbol(into, it, source_using);
    }
}

ImportSymbol :: (into : *Scope, symbol : *Symbol, source_using : *AstNode) {
    if !CheckRedeclaration(into, symbol, source_using) {
        return;
    }

    imported := Alloc(ImportedSymbol);
    imported.final_symbol = symbol;
    imported.source_using = source_using;

    HashMapInsert(*into.imported_symbols, imported.final_symbol.name, imported);

    for into.importing_scopes {
        ImportSymbol(it.scope, imported, it.source_using);
    }
}

ImportSymbol :: (into : *Scope, source_import : *ImportedSymbol, source_using : *AstNode) {
    if !CheckRedeclaration(into, source_import.final_symbol, source_using) {
        return;
    }

    imported := Alloc(ImportedSymbol);
    imported.final_symbol = source_import.final_symbol;
    imported.source_import = source_import;
    imported.source_using = source_using;

    HashMapInsert(*into.imported_symbols, imported.final_symbol.name, imported);

    for into.importing_scopes {
        ImportSymbol(it.scope, imported, it.source_using);
    }
}

ScopeLookupCurrent :: inline (using scope : *Scope, name : string) -> *Symbol, *ImportedSymbol {
    symbol := HashMapGet(*symbols, name);
    if symbol {
        return symbol, null;
    }

    imported := HashMapGet(*imported_symbols, name);
    if imported {
        return imported.final_symbol, imported;
    }

    return null, null;
}

ScopeLookup :: (using scope : *Scope, name : string) -> *Symbol, *ImportedSymbol {
    Assert(scope != null, "Scope is null");

    while scope {
        symbol, imported := ScopeLookupCurrent(scope, name);
        if symbol {
            return symbol, imported;
        }

        scope = scope.parent;
    }

    return null, null;
}

HasOwnScope :: (type : *Type_Info_Struct) -> bool {
    if type == type_info(AstIf) || type == type_info(AstWhile) || type == type_info(AstFor) {
        return true;
    }

    for member : type.members {
        // If this node wants to create its own scope, bail out
        if member.name == "scope" && member.type == type_info(*Scope) {
            return true;
        }
    }

    return false;
}

SetEnclosingScopes :: (scope : *Scope, node : *$T) {
    if !node {
        return;
    }

    #if T == AstNode {
        inline SetEnclosingScopesForUntypedNode(scope, node);
    } else {
        node.enclosing_scope = scope;

        for node.attributes {
            SetEnclosingScopes(scope, it);
        }

        #insert -> string {
            info := type_info(T);

            builder : StringBuilder;

            Appendln(*builder, "// SetEnclosingScopes for %", T);

            // If the node has its own scope, then we set the enclosing scope for
            // all the subnodes except the ones marked with @CollectStatement
            has_own_scope := HasOwnScope(info);

            for member : info.members {
                collect_statement := false;
                no_collect_symbols := false;
                for note : member.notes {
                    if note == "CollectStatement" {
                        collect_statement = true;
                    }
                    if note == "NoCollectSymbols" {
                        no_collect_symbols = true;
                    }
                }

                if no_collect_symbols {
                    continue;
                }

                if has_own_scope && collect_statement {
                    continue;
                }

                if member.type.type == .POINTER {
                    pointed_type := cast(*Type_Info_Pointer, member.type).pointer_to;
                    if TypeIsAstNode(pointed_type) {
                        Appendln(*builder, "SetEnclosingScopes(scope, node.%);", member.name);
                    }
                } else if member.type.type == .ARRAY {
                    element_type := cast(*Type_Info_Array, member.type).element_type;
                    pointed_type : *Type_Info;
                    if element_type.type == .POINTER {
                        pointed_type = cast(*Type_Info_Pointer, element_type).pointer_to;
                    }

                    if pointed_type && TypeIsAstNode(pointed_type) {
                        Appendln(*builder, "for node.% {", member.name);
                        Appendln(*builder, "    SetEnclosingScopes(scope, it);");
                        Appendln(*builder, "}");
                    }
                }
            }

            return StringBuilderBuild(*builder);
        }
    }
}

SetEnclosingScopesForUntypedNode :: (scope : *Scope, node : *AstNode) {
    Ast_Kinds_To_Ignore :: AstKind.[
        .Invalid,
        .StatementsBegin,
        .ExpressionsBegin,
        .ExpressionsEnd,
        .StatementsEnd,
        .Count
    ];

    #insert -> string {
        builder : StringBuilder;

        StringBuilderAppend(*builder, "if node.kind == {\n");
        for i : 0..AstKind.Count - 1 {
            kind := cast(AstKind, i);
            for Ast_Kinds_To_Ignore {
                if it == kind {
                    continue i;
                }
            }

            StringBuilderAppend(*builder, "case .%;\n", kind);
            StringBuilderAppend(*builder, "    SetEnclosingScopes(scope, cast(*Ast%, node));\n", kind);
        }
        StringBuilderAppend(*builder, "}");

        return StringBuilderBuild(*builder);
    };
}

CreateScopesAndCollectStatementsAndSymbols :: (scope : *Scope, node : *$T, parent_statement : *AstNode) {
    if !node {
        return;
    }

    #if T == AstNode {
        inline CreateScopesAndCollectStatementsAndSymbolsForUntypedNode(scope, node, parent_statement);
    } else {
        DbgInfo(.Scopes, node, "CreateScopesAndCollectStatementsAndSymbols(%)", T);

        SetEnclosingScopes(scope, node);

        AddAllBlockStatements :: (scope : *Scope, node : *AstNode) {
            node.enclosing_scope = scope;

            if node.kind == .Block {
                for cast(*AstBlock, node).statements {
                    AddStatement(scope, it);
                    SetEnclosingScopes(scope, node);
                }
            } else {
                AddStatement(scope, node);
                SetEnclosingScopes(scope, node);
            }
        }

        #if T == AstIf {
            // Special case for if, because we have two scopes for if and else
            if node.is_compile_time {
                node.if_scope = node.enclosing_scope;

                if node.else_stmt {
                    node.else_scope = node.enclosing_scope;
                }
            } else {
                ScopeCreate(scope, node);

                Assert(node.if_scope != null);

                if node.else_stmt {
                    Assert(node.else_scope != null);
                }
            }

            if node.body.kind == .Block {
                cast(*AstBlock, node.body).scope = node.if_scope;
            }

            if node.else_stmt && node.else_stmt.kind == .Block {
                cast(*AstBlock, node.else_stmt).scope = node.else_scope;
            }

            if !node.is_compile_time {
                AddAllBlockStatements(node.if_scope, node.body);

                if node.else_stmt {
                    AddAllBlockStatements(node.else_scope, node.else_stmt);
                }
            }
        } else {
            #if T == AstIdentifier {
                if node.ident_flags & .ImplicitDeclaration {
                    ScopeInsert(scope, node, parent_statement);
                }
            } else #if T == AstDeclaration {
                ScopeInsert(scope, node, node);
            } else #if T == AstBlock {
                // For top-level lone blocks, they inherit their parent's scope
                if IsTopLevelScope(scope) && !node.parent_statement && !node.parent_expr {
                    node.scope = scope;
                    AddAllBlockStatements(scope, node);
                    return;
                }
            }

            #insert -> string {
                info := type_info(T);

                builder : StringBuilder;

                Appendln(*builder, "// CreateScopesAndCollectStatementsAndSymbols for %", T);

                if HasOwnScope(info) {
                    Appendln(*builder, "if !node.scope then ScopeCreate(scope, node);");
                    Appendln(*builder, "scope = node.scope;");
                }

                for member : info.members {
                    collect_statement := false;
                    no_collect_symbols := false;
                    for note : member.notes {
                        if note == "CollectStatement" {
                            collect_statement = true;
                        }
                        if note == "NoCollectSymbols" {
                            no_collect_symbols = true;
                        }
                    }

                    if no_collect_symbols {
                        continue;
                    }

                    if member.type.type == .POINTER {
                        pointed_type := cast(*Type_Info_Pointer, member.type).pointer_to;
                        if TypeIsAstNode(pointed_type) {
                            if collect_statement {
                                Appendln(*builder, "AddStatement(scope, node.%);", member.name);
                            } else {
                                Appendln(*builder, "CreateScopesAndCollectStatementsAndSymbols(scope, node.%, parent_statement);", member.name);
                            }
                        }
                    } else if member.type.type == .ARRAY {
                        element_type := cast(*Type_Info_Array, member.type).element_type;
                        pointed_type : *Type_Info;
                        if element_type.type == .POINTER {
                            pointed_type = cast(*Type_Info_Pointer, element_type).pointer_to;
                        }

                        if pointed_type && TypeIsAstNode(pointed_type) {
                            Appendln(*builder, "for node.% {", member.name);

                            if collect_statement {
                                Appendln(*builder, "    AddStatement(scope, it);");
                            } else {
                                Appendln(*builder, "    CreateScopesAndCollectStatementsAndSymbols(scope, it, parent_statement);");
                            }

                            Appendln(*builder, "}");
                        }
                    }
                }

                return StringBuilderBuild(*builder);
            }
        }
    }
}

CreateScopesAndCollectStatementsAndSymbolsForUntypedNode :: (scope : *Scope, node : *AstNode, parent_statement : *AstNode) {
    Ast_Kinds_To_Ignore :: AstKind.[
        .Invalid,
        .StatementsBegin,
        .ExpressionsBegin,
        .ExpressionsEnd,
        .StatementsEnd,
        .Count
    ];

    #insert -> string {
        builder : StringBuilder;

        StringBuilderAppend(*builder, "if node.kind == {\n");
        for i : 0..AstKind.Count - 1 {
            kind := cast(AstKind) i;
            for Ast_Kinds_To_Ignore {
                if it == kind {
                    continue i;
                }
            }

            StringBuilderAppend(*builder, "case .%;\n", kind);
            StringBuilderAppend(*builder, "    CreateScopesAndCollectStatementsAndSymbols(scope, cast(*Ast%, node), parent_statement);\n", kind);
        }
        StringBuilderAppend(*builder, "}");

        return StringBuilderBuild(*builder);
    };
}

CreateScopesAndCollectStatementsAndSymbolsForNewlyAddedCode :: (program : *YalProgram) {
    i := 0;
    while i < program.modified_scopes.count {
        defer i += 1;

        DbgPrintln(.Scopes, "Scope creation and statement collection, iteration %", i);

        scope := program.modified_scopes[i];
        j := 0;
        while j < scope.newly_added_statements.count {
            defer j += 1;

            stmt := scope.newly_added_statements[j];
            CreateScopesAndCollectStatementsAndSymbolsForUntypedNode(scope, stmt, stmt);
        }
    }
}
