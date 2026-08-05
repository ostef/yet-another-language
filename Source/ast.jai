AstKind :: enum u8 {
    Invalid;

    Attribute;

    StatementsBegin;

        Declaration;

        Block;
        Assignment;
        If;
        While;
        For;
        Defer;
        Return;
        FlowControl;   // break, continue, fallthrough
        Include;
        Assert;
        Insert;

        ExpressionsBegin;

            Context;
            Identifier;
            Literal;
            StructLiteral;
            Binary;
            Unary;
            FieldAccess;
            FunctionCall;
            Subscript;
            Cast;
            SizeOf;
            TypeOf;
            Function;
            FunctionOverloadSet;
            Struct;
            Enum;
            TypePointer;
            TypeArray;
            TypePrimitive;
            Range;
            Argument;

            Run;
            Import;

        ExpressionsEnd;

    StatementsEnd;

    Count;
}

AstNode :: struct {
    Flags :: enum u8 {
        Parenthesized;
        StatementLevelExpression;
        TemplateInstantiated;
        Using;
    }

    #as using range : TokenRange;
    enclosing_scope : *Scope;
    type : *YalType; @NoCopy
    dependency_node : *DependencyNode;
    attributes : []*AstAttribute;
    inherited_attributes : []*AstAttribute; @NoClone
    value : ConstantValue; @NoCopy // @Todo: make this a pointer?
    parent_statement : *AstNode; @NoCopy @NoCollectSymbols
    semantic_meaning : SemanticMeaning; @NoCopy
    flags : Flags;

    #as kind : AstKind;
}

AstAttribute :: struct {
    #as using base : AstNode;
    base.kind = .Attribute;

    name_tok : Token;
    name : string;
    arguments : []*AstNode;
}

MakeAstAttribute :: inline (name : Token, arguments : []*AstNode, close_paren_tok : Token) -> *AstAttribute {
    node := Alloc(AstAttribute);
    node.name_tok = name;
    node.name = StringAdvance(TokenToString(name), 1);
    node.arguments = arguments;
    node.range = TokenRangeJoin(name, close_paren_tok);

    return node;
}

IsExpression :: inline (kind : AstKind) -> bool {
    return kind > .ExpressionsBegin && kind < .ExpressionsEnd;
}

IsStatement :: inline (kind : AstKind) -> bool {
    return kind > .StatementsBegin && kind < .StatementsEnd;
}

TypeIsAstNode :: (info : *Type_Info) -> bool {
    if info == type_info(AstNode) {
        return true;
    }

    if info.type != .STRUCT {
        return false;
    }

    info_struct := cast(*Type_Info_Struct) info;

    for info_struct.members {
        if it.name == "base" && it.type == type_info(AstNode)
        && it.flags & .USING && it.flags & .AS {
            return true;
        }
    }

    return false;
}

AstBlock :: struct {
    #as using base : AstNode;
    base.kind = .Block;

    scope : *Scope;

    using parent_node : union {
        parent_expr : *AstNode;
        parent_func : *AstFunction;
        parent_func_overload_set : *AstFunctionOverloadSet;
        parent_enum : *AstEnum;
        parent_struct : *AstStruct;
    }; @NoCopy

    statements : [..]*AstNode; @CollectStatement
}

GetStatementIndex :: (block : *AstBlock, stmt : *AstNode) -> int {
    for block.statements {
        if it == stmt {
            return it_index;
        }
    }

    return -1;
}

MakeAstBlock :: inline (open_brace_tok : Token, close_brace_tok : Token, statements : [..]*AstNode) -> *AstBlock {
    node := Alloc(AstBlock);
    node.statements = statements;
    node.range = TokenRangeJoin(open_brace_tok, close_brace_tok);

    return node;
}

AstAssignment :: struct {
    #as using base : AstNode;
    base.kind = .Assignment;

    left : *AstNode;
    right : *AstNode;
    op : Token;
}

MakeAstAssignment :: inline (op : Token, left : *AstNode, right : *AstNode) -> *AstAssignment {
    node := Alloc(AstAssignment);
    node.op = op;
    node.left = left;
    node.right = right;
    node.range = TokenRangeJoin(left, right);

    return node;
}

AstIf :: struct {
    #as using base : AstNode;
    base.kind = .If;

    if_scope : *Scope;
    else_scope : *Scope;

    condition : *AstNode;
    body : *AstNode; @CollectStatement
    else_stmt : *AstNode; @CollectStatement
    is_compile_time : bool;
}

MakeAstIf :: inline (if_tok : Token, condition : *AstNode, body : *AstNode, else_stmt : *AstNode, is_compile_time : bool) -> *AstIf {
    node := Alloc(AstIf);
    node.condition = condition;
    node.body = body;
    node.else_stmt = else_stmt;
    node.is_compile_time = is_compile_time;
    node.range = TokenRangeJoin(if_tok, body);

    return node;
}

AstWhile :: struct {
    #as using base : AstNode;
    base.kind = .While;

    scope : *Scope;

    condition : *AstNode;
    body : *AstNode; @CollectStatement
}

MakeAstWhile :: inline (while_tok : Token, condition : *AstNode, body : *AstNode) -> *AstWhile {
    node := Alloc(AstWhile);
    node.condition = condition;
    node.body = body;
    node.range = TokenRangeJoin(while_tok, body);

    return node;
}

AstFor :: struct {
    #as using base : AstNode;
    base.kind = .For;

    scope : *Scope;

    // Can be either a declaration or an assignment
    iterator : *AstNode; @CollectStatement
    body : *AstNode; @CollectStatement
}

MakeAstFor :: inline (for_tok : Token, iterator : *AstNode, body : *AstNode) -> *AstFor {
    node := Alloc(AstFor);
    node.iterator = iterator;
    node.body = body;
    node.range = TokenRangeJoin(for_tok, body);

    return node;
}

AstRange :: struct {
    #as using base : AstNode;
    base.kind = .Range;

    start : *AstNode;
    end : *AstNode;
    inclusive : bool;
    reverse : bool;
}

MakeAstRange :: inline (start : *AstNode, end : *AstNode, inclusive : bool, reverse : bool) -> *AstRange {
    node := Alloc(AstRange);
    node.start = start;
    node.end = end;
    node.inclusive = inclusive;
    node.reverse = reverse;
    node.range = TokenRangeJoin(start, end);

    return node;
}

AstArgument :: struct {
    #as using base : AstNode;
    base.kind = .Argument;

    name : *AstIdentifier;
    expr : *AstNode;
    resolved_index := -1;
}

MakeAstArgument :: inline (name : *AstIdentifier, expr : *AstNode) -> *AstArgument {
    node := Alloc(AstArgument);
    node.name = name;
    node.expr = expr;
    if name {
        node.range = TokenRangeJoin(name, expr);
    } else {
        node.range = expr.range;
    }

    return node;
}

AstDefer :: struct {
    #as using base : AstNode;
    base.kind = .Defer;

    scope : *Scope;
    stmt : *AstNode; @CollectStatement
}

MakeAstDefer :: inline (defer_tok : Token, stmt : *AstNode) -> *AstDefer {
    node := Alloc(AstDefer);
    node.stmt = stmt;
    node.range = TokenRangeJoin(defer_tok, stmt);

    return node;
}

AstReturn :: struct {
    #as using base : AstNode;
    base.kind = .Return;

    expr : *AstNode;
}

MakeAstReturn :: inline (return_tok : Token, expr : *AstNode) -> *AstReturn {
    node := Alloc(AstReturn);
    node.expr = expr;
    if expr {
        node.range = TokenRangeJoin(return_tok, expr);
    } else {
        node.range = return_tok;
    }

    return node;
}

AstFlowControl :: struct {
    #as using base : AstNode;
    base.kind = .FlowControl;

    control : TokenKind;
}

MakeAstFlowControl :: inline (tok : Token) -> *AstFlowControl {
    node := Alloc(AstFlowControl);
    node.control = tok.kind;
    node.range = tok;

    return node;
}

AstInclude :: struct {
    #as using base : AstNode;
    base.kind = .Include;

    filename : string;
}

MakeAstInclude :: inline (include_tok : Token, filename_tok : Token, filename : string) -> *AstInclude {
    node := Alloc(AstInclude);
    node.filename = filename;
    node.range = TokenRangeJoin(include_tok, filename_tok);

    return node;
}

AstAssert :: struct {
    #as using base : AstNode;
    base.kind = .Assert;

    expr : *AstNode;
    message : *AstNode;
}

MakeAstAssert :: inline (assert_tok : Token, expr : *AstNode, message : *AstNode) -> *AstAssert {
    node := Alloc(AstAssert);
    node.expr = expr;
    node.message = message;
    if message {
        node.range = TokenRangeJoin(assert_tok, message);
    } else {
        node.range = TokenRangeJoin(assert_tok, expr);
    }

    return node;
}

DeclarationKind :: enum u8 {
    Invalid;
    Variable;
    Constant;
    Field;
    EnumMember;
    TemplateParam;
    ForLoopIndex;
}

DeclarationFlags :: enum_flags u8 {
    External;
    CallingConventionSet;
}

CodegenStatus :: enum u8 {
    NotGenerated;
    Generating;
    Generated;
}

AstDeclaration :: struct {
    #as using base : AstNode;
    base.kind = .Declaration;

    identifier : *AstIdentifier; @NoCollectSymbols

    type_node : *AstNode;
    expr : *AstNode;

    decl_kind : DeclarationKind;
    codegen_status : CodegenStatus; @NoCopy

    modifiers : DeclarationModifiers; @NoCopy

    Clone_Postamble :: #string Jai
if result.expr {
    if result.expr.kind == {
    case .Struct;
        cast(*AstStruct, result.expr).decl = result;
    case .Enum;
        cast(*AstEnum, result.expr).decl = result;
    case .Function;
        cast(*AstFunction, result.expr).decl = result;
    case .FunctionOverloadSet;
        cast(*AstFunctionOverloadSet, result.expr).decl = result;
    }
}
Jai
}

MakeAstDeclaration :: inline (begin_tok : Token, ident : *AstIdentifier, type_node : *AstNode, expr : *AstNode, decl_kind : DeclarationKind) -> *AstDeclaration {
    node := Alloc(AstDeclaration);
    node.identifier = ident;
    node.decl_kind = decl_kind;
    node.type_node = type_node;
    node.expr = expr;

    if expr {
        node.range = TokenRangeJoin(begin_tok, expr);
    } else if type_node {
        node.range = TokenRangeJoin(begin_tok, type_node);
    } else if ident {
        node.range = TokenRangeJoin(begin_tok, ident);
    } else { // This probably should not happen but just in case
        node.range = begin_tok;
    }

    return node;
}

AstContext :: struct {
    #as using base : AstNode;
    base.kind = .Context;
}

MakeAstContext :: inline(tok : Token) -> *AstContext {
    node := Alloc(AstContext);
    node.range = tok;

    return node;
}

IdentifierFlags :: enum_flags u8 {
    TemplateParam;
    ImplicitDeclaration;
    FieldAccessRHS;
    ResolvedToPrimitiveTypeField;
    DoNotResolve;
}

AstIdentifier :: struct {
    #as using base : AstNode;
    base.kind = .Identifier;

    name : string;
    symbol : *Symbol;
    imported_symbol : *ImportedSymbol;
    ident_flags : IdentifierFlags;

    Clone_Postamble :: #string Jai
// These are set during the checking phase, so unset them
result.ident_flags &= ~.ResolvedToPrimitiveTypeField;
result.ident_flags &= ~.FieldAccessRHS;
Jai
}

MakeAstIdentifierTemplateParam :: inline(dollar_tok : Token, ident_tok : Token) -> *AstIdentifier {
    node := Alloc(AstIdentifier);
    node.name = TokenToString(ident_tok);
    node.ident_flags |= .TemplateParam;
    node.range = TokenRangeJoin(dollar_tok, ident_tok);

    return node;
}

MakeAstIdentifier :: inline (tok : Token) -> *AstIdentifier {
    node := Alloc(AstIdentifier);
    node.name = TokenToString(tok);
    node.range = tok.range;

    return node;
}

AstLiteral :: struct {
    #as using base : AstNode;
    base.kind = .Literal;

    literal_kind : TokenKind;
}

MakeAstLiteral :: inline (tok : Token) -> *AstLiteral {
    node := Alloc(AstLiteral);
    node.literal_kind = tok.kind;
    node.range = tok.range;

    return node;
}

AstStructLiteral :: struct {
    #as using base : AstNode;
    base.kind = .StructLiteral;

    type_node : *AstNode;
    values : [..]*AstNode;
}

MakeAstStructLiteral :: inline (type_node : *AstNode, open_tok : Token, values : [..]*AstNode, close_tok : Token) -> *AstStructLiteral {
    node := Alloc(AstStructLiteral);
    node.type_node = type_node;
    node.values = values;
    if node.type_node {
        node.range = TokenRangeJoin(type_node, close_tok);
    } else {
        node.range = TokenRangeJoin(open_tok, close_tok);
    }

    return node;
}

AstUnary :: struct {
    #as using base : AstNode;
    base.kind = .Unary;

    expr : *AstNode;
    op : Token;
}

MakeAstUnary :: inline (op : Token, expr : *AstNode) -> *AstUnary {
    node := Alloc(AstUnary);
    node.op = op;
    node.expr = expr;
    node.range = TokenRangeJoin(op, expr);

    return node;
}

AstBinary :: struct {
    #as using base : AstNode;
    base.kind = .Binary;

    left : *AstNode;
    right : *AstNode;
    op : Token;
}

MakeAstBinary :: inline (op : Token, left : *AstNode, right : *AstNode) -> *AstBinary {
    node := Alloc(AstBinary);
    node.op = op;
    node.left = left;
    node.right = right;
    node.range = TokenRangeJoin(left, right);

    return node;
}

AstFieldAccess :: struct {
    #as using base : AstNode;
    base.kind = .FieldAccess;

    left : *AstNode;
    right : *AstNode;

    accessed_struct_member_index  : s32 = -1; @NoCopy
    accessed_struct_member_offset : s32 = -1; @NoCopy
}

MakeAstFieldAccess :: inline (left : *AstNode, right : *AstNode) -> *AstFieldAccess {
    node := Alloc(AstFieldAccess);
    node.left = left;
    node.right = right;
    node.range = TokenRangeJoin(left, right);

    return node;
}

MakeAstFieldAccess :: inline (dot_tok : Token, right : *AstNode) -> *AstFieldAccess {
    node := Alloc(AstFieldAccess);
    node.right = right;
    node.range = TokenRangeJoin(dot_tok, right);

    return node;
}

AstFunctionCall :: struct {
    #as using base : AstNode;
    base.kind = .FunctionCall;

    callee : *AstNode;
    passed_arguments : []*AstArgument;
    ordered_arguments : []*AstNode;
}

MakeAstFunctionCall :: inline (callee : *AstNode, passed_arguments : []*AstArgument, close_paren_tok : Token) -> *AstFunctionCall {
    node := Alloc(AstFunctionCall);
    node.callee = callee;
    node.passed_arguments = passed_arguments;
    node.range = TokenRangeJoin(callee, close_paren_tok);

    return node;
}

AstSubscript :: struct {
    #as using base : AstNode;
    base.kind = .Subscript;

    subscripted : *AstNode;
    index : *AstNode;
}

MakeAstSubscript :: inline (subscripted : *AstNode, index : *AstNode, close_bracket_tok : Token) -> *AstSubscript {
    node := Alloc(AstSubscript);
    node.subscripted = subscripted;
    node.index = index;
    node.range = TokenRangeJoin(subscripted, close_bracket_tok);

    return node;
}

AstCast :: struct {
    #as using base : AstNode;
    base.kind = .Cast;

    type_node : *AstNode;
    expr : *AstNode;
    cast_kind : TokenKind;
}

MakeAstAutoCast :: inline (cast_tok : Token, expr : *AstNode) -> *AstCast {
    node := Alloc(AstCast);
    node.cast_kind = cast_tok.kind;
    node.type_node = null;
    node.expr = expr;
    node.range = TokenRangeJoin(cast_tok, expr);

    return node;
}

MakeAstCast :: inline (cast_tok : Token, type_node : *AstNode, expr : *AstNode, close_paren_tok : Token) -> *AstCast {
    node := Alloc(AstCast);
    node.cast_kind = cast_tok.kind;
    node.type_node = type_node;
    node.expr = expr;
    node.range = TokenRangeJoin(cast_tok, close_paren_tok);

    return node;
}

AstSizeOf :: struct {
    #as using base : AstNode;
    base.kind = .SizeOf;

    type_node : *AstNode;
}

MakeAstSizeOf :: inline (size_of_tok : Token, close_paren_tok : Token, type_node : *AstNode) -> *AstSizeOf {
    node := Alloc(AstSizeOf);
    node.type_node = type_node;
    node.range = TokenRangeJoin(size_of_tok, close_paren_tok);

    return node;
}

AstTypeOf :: struct {
    #as using base : AstNode;
    base.kind = .TypeOf;

    expr : *AstNode;
}

MakeAstTypeOf :: inline (size_of_tok : Token, close_paren_tok : Token, expr : *AstNode) -> *AstTypeOf {
    node := Alloc(AstTypeOf);
    node.expr = expr;
    node.range = TokenRangeJoin(size_of_tok, close_paren_tok);

    return node;
}

AstTypePointer :: struct {
    #as using base : AstNode;
    base.kind = .TypePointer;

    pointed_type : *AstNode;
}

MakeAstTypePointer :: inline (star_tok : Token, pointed_type : *AstNode) -> *AstTypePointer {
    node := Alloc(AstTypePointer);
    node.pointed_type = pointed_type;
    node.range = TokenRangeJoin(star_tok, pointed_type);

    return node;
}

ArrayKind :: enum u8 {
    Invalid;
    Slice;
    Dynamic;
    Static;
} @Preload

AstTypeArray :: struct {
    #as using base : AstNode;
    base.kind = .TypeArray;

    element_type : *AstNode;
    element_count : *AstNode;
    array_kind : ArrayKind;
}

MakeAstTypeArray :: inline (open_bracket_tok : Token, element_type : *AstNode, element_count : *AstNode, is_dynamic : bool) -> *AstTypeArray {
    node := Alloc(AstTypeArray);

    if is_dynamic {
        node.array_kind = .Dynamic;
    } else if element_count {
        node.array_kind = .Static;
    } else {
        node.array_kind = .Slice;
    }

    node.element_type = element_type;
    node.element_count = element_count;
    node.range = TokenRangeJoin(open_bracket_tok, element_type);

    return node;
}

AstTypePrimitive :: struct {
    #as using base : AstNode;
    base.kind = .TypePrimitive;

    primitive_kind : TokenKind;
}

MakeAstTypePrimitive :: inline (tok : Token) -> *AstTypePrimitive {
    node := Alloc(AstTypePrimitive);
    node.primitive_kind = tok.kind;
    node.range = tok.range;

    return node;
}

TemplateInstantiation :: struct {
    template_arguments : []ConstantValue;
    // When creating a template instantiation, we don't get the chance to
    // set the dependency right away because the graph gets created on the
    // next pass. This array contains nodes that depend on the instantiation
    // so we can add the dependency when creating the graph
    dependents : [..]*DependencyNode;
}

StructTemplateInstantiation :: struct {
    #as using base : TemplateInstantiation;
    instantiation : *AstStruct;
}

AstStruct :: struct {
    #as using base : AstNode;
    base.kind = .Struct;

    TemplateParam :: struct {
        param_index : s32;
        decl : *AstDeclaration;
    }

    decl : *AstDeclaration; @NoCopy @NoCollectSymbols
    defined_type : *YalTypeStruct;
    scope : *Scope;
    template_params : [..]TemplateParam; @NoCopy @NoCollectSymbols
    parameters : []*AstDeclaration; @CollectStatement
    body : *AstBlock;
    default_value : ConstantStructValue; @NoCopy
    template_instantiations : [..]StructTemplateInstantiation; @NoCopy @NoCollectSymbols
    template_source : *AstStruct; @NoCopy @NoCollectSymbols
    template_instantiation_index : s32 = -1; @NoCopy
    is_union : bool;

    Clone_Postamble :: #string Jai
if result.body {
    result.body.parent_struct = result;
}
Jai
}

InstantiateStructTemplate :: (from : *AstNode, struct_node : *AstStruct, arguments : []ConstantValue) -> *AstStruct {
    DbgInfo(.Templates, struct_node, "Instantiating struct template: %", arguments);
    DbgInfo(.Templates, from, "From here");

    for struct_node.template_instantiations {
        same_values := true;
        for other_arg, arg_index : it.template_arguments {
            arg := arguments[arg_index];

            comparison := ConstantEvaluate(arg, other_arg, .EquEqu);
            if !comparison.bool_value {
                same_values = false;
                break;
            }
        }

        if same_values {
            DbgInfo(.Templates, struct_node, "Using already instantiated struct template: %", arguments);
            return it.instantiation;
        }
    }

    inst := ArrayPush(*struct_node.template_instantiations, .{template_arguments=arguments});
    inst.instantiation = CloneAst(struct_node);
    inst.instantiation.template_source = struct_node;
    inst.instantiation.parent_statement = struct_node.parent_statement; // Kind of hacky, but it also kind of makes sense...

    inst.instantiation.template_instantiation_index = xx (struct_node.template_instantiations.count - 1);

    AddStatement(struct_node.enclosing_scope, inst.instantiation);

    return inst.instantiation;
}

AddDependencyOnStructTemplateInstantiation :: (node : *DependencyNode, struct_node : *AstStruct) {
    if struct_node.dependency_node {
        AddDependency(node, struct_node.dependency_node, 0);
    } else {
        inst := *struct_node.template_source.template_instantiations[struct_node.template_instantiation_index];
        ArrayPush(*inst.dependents, node);
    }
}

IsStructTemplate :: inline (node : *AstStruct) -> bool {
    return node.template_params.count > 0 && node.template_instantiation_index < 0;
}

MakeAstStruct :: inline (struct_tok : Token, parameters : []*AstDeclaration, body : *AstBlock, is_union : bool) -> *AstStruct {
    node := Alloc(AstStruct);
    node.parameters = parameters;
    node.body = body;
    node.is_union = is_union;
    node.range = TokenRangeJoin(struct_tok, body);

    return node;
}

AstEnum :: struct {
    #as using base : AstNode;
    base.kind = .Enum;

    decl : *AstDeclaration; @NoCopy @NoCollectSymbols
    defined_type : *YalTypeEnum;
    base_type : *AstNode;
    body : *AstBlock;

    Clone_Postamble :: #string Jai
if result.body {
    result.body.parent_enum = result;
}
Jai
}

MakeAstEnum :: inline (enum_tok : Token, base_type : *AstNode, body : *AstBlock) -> *AstEnum {
    node := Alloc(AstEnum);
    node.base_type = base_type;
    node.body = body;
    node.range = TokenRangeJoin(enum_tok, body);

    return node;
}

CallingConvention :: enum u8 {
    Unknown;
    Yal;
    C;
} @Preload

FunctionTemplateInstantiation :: struct {
    #as using base : TemplateInstantiation;
    instantiation : *AstFunction;
}

AstFunction :: struct {
    #as using base : AstNode;
    base.kind = .Function;

    TemplateParam :: struct {
        param_index : s32;
        decl : *AstDeclaration;
    }

    decl : *AstDeclaration; @NoCopy @NoCollectSymbols
    ir_function : *IRFunction; @NoCopy
    signature_range : TokenRange;
    scope : *Scope;

    parameters : []*AstDeclaration; @CollectStatement
    result : *AstDeclaration; @CollectStatement
    body : *AstBlock; @CollectStatement

    library_name : string; @NoCopy
    symbol_name : string; @NoCopy

    template_params : [..]TemplateParam; @NoCopy @NoCollectSymbols
    template_instantiations : [..]FunctionTemplateInstantiation; @NoCopy @NoCollectSymbols
    template_source : *AstFunction; @NoCopy @NoCollectSymbols
    template_instantiation_index : s32 = -1; @NoCopy

    is_c_variadic : bool;

    calling_convention : CallingConvention; @NoCopy
    is_external : bool; @NoCopy

    Clone_Postamble :: #string Jai
if result.body {
    result.body.parent_func = result;
}
Jai
}

InstantiateFunctionTemplate :: (from : *AstNode, func : *AstFunction, arguments : []ConstantValue) -> *AstFunction {
    DbgInfo(.Templates, func, "Instantiating function template: %", arguments);
    DbgInfo(.Templates, from, "From here");

    for func.template_instantiations {
        same_values := true;
        for other_arg, arg_index : it.template_arguments {
            arg := arguments[arg_index];

            comparison := ConstantEvaluate(arg, other_arg, .EquEqu);
            if !comparison.bool_value {
                same_values = false;
                break;
            }
        }

        if same_values {
            DbgInfo(.Templates, func, "Using already instantiated function template: %", arguments);
            return it.instantiation;
        }
    }

    inst := ArrayPush(*func.template_instantiations, .{template_arguments=arguments});
    inst.instantiation = CloneAst(func);
    inst.instantiation.template_source = func;
    inst.instantiation.parent_statement = func.parent_statement; // Kind of hacky, but it also kind of makes sense...

    inst.instantiation.template_instantiation_index = xx (func.template_instantiations.count - 1);

    AddStatement(func.enclosing_scope, inst.instantiation);

    return inst.instantiation;
}

AddDependencyOnFunctionTemplateInstantiation :: (node : *DependencyNode, func : *AstFunction) {
    if func.dependency_node {
        AddDependency(node, func.dependency_node, .Callee);
        AddDependency(node, func.body.dependency_node, 0);
    } else {
        inst := *func.template_source.template_instantiations[func.template_instantiation_index];
        ArrayPush(*inst.dependents, node);
    }
}

IsFunctionTemplate :: inline (func : *AstFunction) -> bool {
    return func.template_params.count > 0 && func.template_instantiation_index < 0;
}

MakeAstFunction :: inline (
    func_tok : Token,
    close_paren_tok : Token,
    parameters : []*AstDeclaration,
    result : *AstDeclaration,
    is_c_variadic : bool,
    body : *AstBlock = null
) -> *AstFunction {
    node := Alloc(AstFunction);
    node.parameters = parameters;
    node.result = result;
    node.body = body;
    node.is_c_variadic = is_c_variadic;

    if result {
        node.signature_range = TokenRangeJoin(func_tok, result);
    } else {
        node.signature_range = TokenRangeJoin(func_tok, close_paren_tok);
    }

    if body {
        node.range = TokenRangeJoin(func_tok, body);
    } else if result {
        node.range = TokenRangeJoin(func_tok, result);
    } else {
        node.range = TokenRangeJoin(func_tok, close_paren_tok);
    }

    return node;
}

GetParameterIndex :: (func : *AstFunction, name : string) -> int {
    for func.parameters {
        if it.identifier && it.identifier.name == name {
            return it_index;
        }
    }

    return -1;
}

AstFunctionOverloadSet :: struct {
    #as using base : AstNode;
    base.kind = .FunctionOverloadSet;

    decl : *AstDeclaration; @NoCopy @NoCollectSymbols
    body : *AstBlock;
    final_overloads : []*AstNode; @NoCopy @NoCollectSymbols // @Todo: move this to ConstantValue

    Clone_Postamble :: #string Jai
if result.body {
    result.body.parent_func_overload_set = result;
}
Jai
}

MakeAstFunctionOverloadSet :: inline (
    func_tok : Token,
    body : *AstBlock
) -> *AstFunctionOverloadSet {
    node := Alloc(AstFunctionOverloadSet);
    node.body = body;
    node.range = TokenRangeJoin(func_tok, body);

    return node;
}

AstRun :: struct {
    #as using base : AstNode;
    base.kind = .Run;

    ir_function : *IRFunction; @NoCopy
    scope : *Scope;
    expr : *AstNode;
}

MakeAstRun :: inline (run_tok : Token, expr : *AstNode) -> *AstRun {
    node := Alloc(AstRun);
    node.expr = expr;
    node.range = TokenRangeJoin(run_tok, expr);

    return node;
}

AstImport :: struct {
    #as using base : AstNode;
    base.kind = .Import;

    expr : *AstNode;
    is_import_file : bool;
}

MakeAstImport :: inline (import_tok : Token, expr : *AstNode) -> *AstImport {
    node := Alloc(AstImport);
    node.is_import_file = import_tok.kind == .DirectiveImportFile;
    node.expr = expr;
    node.range = TokenRangeJoin(import_tok, expr);

    return node;
}

AstInsert :: struct {
    #as using base : AstNode;
    base.kind = .Insert;

    scope : *Scope;
    expr : *AstNode;
}

MakeAstInsert :: inline (insert_tok : Token, expr : *AstNode) -> *AstInsert {
    node := Alloc(AstInsert);
    node.expr = expr;
    node.range = TokenRangeJoin(insert_tok, expr);

    return node;
}

// Clone an ast
// Use @NoCopy note on members to leave the member with the default value
// Use @NoClone node on members of type pointer to ast or array of pointer to ast to just copy the pointer
// and not clone the whole subtree
// Semantic information such as dependency_nodes, scopes and types are hard-coded to not be copied,
// semantic_meaning and constant value are not copied either using the @NoCopy notes
CloneAst :: (node : *$T) -> *T #modify { return TypeIsAstNode(cast(*Type_Info, T)); } {
    if !node {
        return null;
    }

    result := Alloc(T);

    #if T == AstNode {
        #insert -> string {
            Ast_Kinds_To_Ignore :: AstKind.[
                .Invalid,
                .StatementsBegin,
                .ExpressionsBegin,
                .ExpressionsEnd,
                .StatementsEnd,
                .Count
            ];

            builder : StringBuilder;

            Appendln(*builder, "// CloneAst(T=%)", T);
            Appendln(*builder, "if node.kind == {");
            for i : 0..AstKind.Count - 1 {
                kind := cast(AstKind, i);
                for Ast_Kinds_To_Ignore {
                    if it == kind {
                        continue i;
                    }
                }

                Appendln(*builder, "case .%;", kind);
                Appendln(*builder, "    return CloneAst(cast(*Ast%, node));", kind);
            }
            Appendln(*builder, "}");

            return StringBuilderBuild(*builder);
        }
    } else {
        #insert -> string {
            CloneHelper :: (builder : *StringBuilder, name : string, info : *Type_Info_Struct) {
                for info.members {
                    if it.name == "" {
                        continue;
                    }

                    if it.offset_in_bytes < 0 {
                        continue;
                    }

                    no_copy := false;

                    // Don't copy semantic info such as scopes, types and symbols!
                    no_copy |= it.type == type_info(*Scope);
                    no_copy |= it.type == type_info(*Symbol);
                    no_copy |= it.type == type_info(*ImportedSymbol);
                    no_copy |= it.type == type_info(*DependencyNode);
                    no_copy |= it.type.type == .POINTER && TypeIsYalType(cast(*Type_Info_Pointer, it.type).pointer_to);

                    if no_copy {
                        continue;
                    }

                    no_clone := false;

                    for note : it.notes {
                        if note == "NoClone" {
                            no_clone = true;
                        } else if note == "NoCopy" {
                            no_copy = true;
                        }
                    }

                    if no_copy {
                        continue;
                    }

                    is_ast_node : bool;
                    {
                        element_type := it.type;

                        if element_type.type == .ARRAY {
                            element_type = cast(*Type_Info_Array, element_type).element_type;
                        }

                        if element_type.type == .POINTER {
                            element_type = cast(*Type_Info_Pointer, element_type).pointer_to;
                            is_ast_node = TypeIsAstNode(element_type);
                        }
                    }

                    if is_ast_node && !no_clone {
                        if it.type.type == .POINTER {
                            Appendln(builder, "result.%1%2 = CloneAst(node.%1%2);", name, it.name);
                        } else if it.type.type == .ARRAY {
                            array_type := cast(*Type_Info_Array, it.type);
                            if array_type.array_type == {
                            case .FIXED;
                            case .VIEW;
                                Appendln(builder, "result.%1%2 = AllocArray(%3, node.%1%2.count);", name, it.name, JaiC.get_type(array_type.element_type));
                            case .RESIZABLE;
                                Appendln(builder, "ArrayReserve(*result.%1%2, node.%1%2.count);", name, it.name);
                                Appendln(builder, "result.%1%2.count = node.%1%2.count;", name, it.name);
                            }

                            Appendln(builder, "for node.%1%2 {", name, it.name);
                            Appendln(builder, "    result.%1%2[it_index] = CloneAst(it);", name, it.name);
                            Appendln(builder, "}");
                        }
                    } else if it.type.type == .STRUCT {
                        CloneHelper(builder, SPrint("%1%2.", name, it.name), xx it.type);
                    } else {
                        Appendln(builder, "result.%1%2 = node.%1%2;", name, it.name);
                    }
                }
            }

            builder : StringBuilder;

            Appendln(*builder, "// CloneAst(T=%)", T);
            CloneHelper(*builder, "", type_info(T));
            #if #exists(T.Clone_Postamble) {
                Appendln(*builder, T.Clone_Postamble);
            }
            #if #exists(AstNode.Clone_Postamble) {
                Appendln(*builder, AstNode.Clone_Postamble);
            }

            return StringBuilderBuild(*builder);
        }
    }

    result.flags &= ~.TemplateInstantiated;

    return result;
}

CloneUntypedAstNode :: #bake_constants CloneAst(T=AstNode);
