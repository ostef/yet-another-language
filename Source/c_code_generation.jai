CodegenStatus :: enum u8
{
    Not_Generated;
    Generating_Forward_Decl;
    Generated_Forward_Decl;
    Generating;
    Generated;
}

C_Header :: #string C
// ======= Yal typedefs =======

typedef          char      s8;
typedef unsigned char      u8;
typedef          short     s16;
typedef unsigned short     u16;
typedef          int       s32;
typedef unsigned int       u32;
typedef          long long s64;
typedef unsigned long long u64;
typedef float  f32;
typedef double f64;
typedef u8 bool;

typedef struct Yal__String
{
    s64 count;
    u8 *data;
} Yal__String;

typedef struct Yal__Slice
{
    s64 count;
    void *data;
} Yal__Slice;

typedef void *(*Yal__AllocatorProc) (s64, void *, void *);

typedef struct Yal__Allocator
{
    void *data;
    Yal__AllocatorProc proc_ptr;
} Yal__Allocator;

typedef struct Yal__DynamicArray
{
    s64 count;
    void *data;
    s64 capacity;
    Yal__Allocator allocator;
} Yal__DynamicArray;

C

EmitForwardDeclaration :: (builder : *SourceCodeBuilder, decl : *AstDeclaration)
{
    Assert (decl, decl.codegen_status != .Generating_Forward_Decl && decl.codegen_status != .Generating, "circular dependency when emitting C code");

    if decl.codegen_status != .Not_Generated
        return;

    if #complete decl.decl_kind ==
    {
    case .Invalid;
    case .Variable; #through;
    case .Field;
        decl.codegen_status = .Generating;
        defer decl.codegen_status = .Generated;

        EmitVariableDeclaration (builder, decl);
        Append (builder, ";\n");

    case .Constant;
        decl.codegen_status = .Generating;
        defer decl.codegen_status = .Generated;

        // We don't generate constant declarations because we emit the value directly when a constant is used
        Append (builder, "/* omitting % */\n", TokenRangeToString (decl));

    case .Procedure;
        decl.codegen_status = .Generating_Forward_Decl;
        defer decl.codegen_status = .Generated_Forward_Decl;

        Assert (decl.identifier_count < 2);

        name := ifx decl.single_identifier then decl.single_identifier.name else "";
        EmitProcedureSignature (builder, cast (*AstProcedure) decl.expr, name);
        Append (builder, ";\n");
    }
}

EmitVariableDeclaration :: (builder : *SourceCodeBuilder, decl : *AstDeclaration)
{
    Assert (decl, decl.identifier_count < 2, "multiple identifiers are not yet handled for C codegen");

    EmitTypePrefix (builder, decl.type);

    if decl.single_identifier
        Append (builder, " %", decl.single_identifier.name);

    EmitTypeSuffix (builder, decl.type);

    if decl.expr
    {
        Append (builder, " = ");
        EmitExpression (builder, decl.expr);
    }
}

EmitDeclaration :: (builder : *SourceCodeBuilder, decl : *AstDeclaration)
{
    Assert (decl, decl.codegen_status != .Generating_Forward_Decl && decl.codegen_status != .Generating, "circular dependency when emitting C code");

    if decl.codegen_status == .Generated
        return;

    decl.codegen_status = .Generating;
    defer decl.codegen_status = .Generated;

    if #complete decl.decl_kind ==
    {
    case .Invalid;
    case .Variable; #through;
    case .Field;
        EmitVariableDeclaration (builder, decl);

    case .Constant;
    case .Procedure;
        Assert (decl.identifier_count < 2);

        name := ifx decl.single_identifier then decl.single_identifier.name else "";
        EmitProcedure (builder, cast (*AstProcedure) decl.expr, name);
    }
}

EmitProcedureSignature :: (builder : *SourceCodeBuilder, proc : *AstProcedure, name := "")
{
    Assert (proc, proc.results.count < 2, "multiple return values are not yet handled for C codegen");

    if proc.results.count == 0
        Append (builder, "void");
    else
        EmitFullType (builder, proc.results[0].type);

    if name
        Append (builder, " % ", name);

    Append (builder, "(");
    for proc.parameters
    {
        if it_index != 0
            Append (builder, ", ");
        EmitVariableDeclaration (builder, it);
    }
    Append (builder, ")");
}

/*

var foo : [10]*int -> int* foo[10]
var bar : [1][2][3]*int -> int* bar[3][2][1]

*/

EmitTypePrefix :: (builder : *SourceCodeBuilder, type : *YalType)
{
    if #complete type.kind ==
    {
    case .Invalid;
    case .Void;
        Append (builder, "void");
    case .Integer;
        if (cast (*YalTypeInteger) type).is_signed
            Append (builder, "s");
        else
            Append (builder, "u");
        Append (builder, "%", type.size * 8);
    case .Float;
        if type.size == 4
            Append (builder, "f32");
        else
            Append (builder, "f64");
    case .Bool;
        Append (builder, "bool");
    case .String;
        Append (builder, "Yal__String");
    case .Pointer;
        type_ptr := cast (*YalTypePointer) type;
        EmitTypePrefix (builder, type_ptr.pointed_type);
        Append (builder, "*");

    case .Array;
        type_array := cast (*YalTypeArray) type;
        if type_array.array_kind ==
        {
        case .Dynamic;
            Append (builder, "Yal__DynamicArray");
        case .Slice;
            Append (builder, "Yal__Slice");
        case .Static;
            EmitTypePrefix (builder, type_array.element_type);
        }

    case .Procedure;
        type_proc := cast (*YalTypeProcedure) type;

        Assert (type_proc.results.count < 2, "Multiple return values are not yet handled");

        if type_proc.results.count == 0
            Append (builder, "void");
        else
            EmitFullType (builder, type_proc.results[0]);
    }
}

EmitTypeSuffix :: (builder : *SourceCodeBuilder, type : *YalType)
{
    if type.kind ==
    {
    case .Pointer;
        type_ptr := cast (*YalTypePointer) type;
        EmitTypeSuffix (builder, type_ptr.pointed_type);

    case .Array;
        type_array := cast (*YalTypeArray) type;

        EmitTypeSuffix (builder, type_array.element_type);

        if type_array.array_kind == .Static
            Append (builder, "[%]", type_array.count);

    case .Procedure;
        type_proc := cast (*YalTypeProcedure) type;

        Append (builder, "(");
        for type_proc.parameters
        {
            if it_index != 0
                Append (builder, ", ");
            EmitFullType (builder, it);
        }
        Append (builder, ")");
    }
}

EmittedStatementShouldEndInSemicolon :: inline (node : *AstNode) -> bool #must
{
    if node.kind == .Block || node.kind == .If || node.kind == .While || node.kind == .Defer
        return false;
    if node.kind == .Declaration
    {
        decl := cast (*AstDeclaration) node;
        if decl.decl_kind == .Procedure || decl.decl_kind == .Constant
            return false;
    }

    return true;
}

EmitFullType :: inline (builder : *SourceCodeBuilder, type : *YalType)
{
    EmitTypePrefix (builder, type);
    EmitTypeSuffix (builder, type);
}

EmitStatement :: (builder : *SourceCodeBuilder, node : *AstNode)
{
    EmitAstNode (builder, node);

    if EmittedStatementShouldEndInSemicolon (node)
        Append (builder, ";");
}

EmitAstNode :: (builder : *SourceCodeBuilder, node : *AstNode)
{
    if #complete node.kind ==
    {
    case .Invalid;
    case .Statements_Begin;

    case .Bad_Declaration;
    case .Declaration;
        EmitDeclaration (builder, cast (*AstDeclaration) node);

    case .Block;
        block := cast (*AstBlock) node;

        Append (builder, "{\n");

        for block.statements
        {
            EmitStatement (builder, it);
            Append (builder, "\n");
        }

        Append (builder, "}");

    case .If;
        if_stmt := cast (*AstIf) node;
        Append (builder, "if (");
        EmitExpression (builder, if_stmt.condition);
        Append (builder, ")\n");

        if EmittedStatementShouldEndInSemicolon (if_stmt.body)
            Indent (builder);

        EmitStatement (builder, if_stmt.body);

        if EmittedStatementShouldEndInSemicolon (if_stmt.body)
            Unindent (builder);

        if if_stmt.else_stmt
        {
            Append (builder, "\nelse ");

            if if_stmt.else_stmt.kind != .If && if_stmt.else_stmt.kind != .While
                Append (builder, "\n");

            if EmittedStatementShouldEndInSemicolon (if_stmt.else_stmt)
                Indent (builder);

            EmitStatement (builder, if_stmt.else_stmt);

            if EmittedStatementShouldEndInSemicolon (if_stmt.else_stmt)
                Unindent (builder);
        }

    case .While;
        while_stmt := cast (*AstWhile) node;
        Append (builder, "while (");
        EmitExpression (builder, while_stmt.condition);
        Append (builder, ")\n");

        if EmittedStatementShouldEndInSemicolon (while_stmt.body)
            Indent (builder);

        EmitStatement (builder, while_stmt.body);

        if EmittedStatementShouldEndInSemicolon (while_stmt.body)
            Unindent (builder);

    case .Defer;
        def := cast (*AstDefer) node;
        Append (builder, "defer ");
        EmitStatement (builder, def.stmt);

    case .Return;
        ret := cast (*AstReturn) node;
        Append (builder, "return");

        Assert (ret, ret.return_values.count < 2, "multiple return values are not yet handled for codegen");

        for ret.return_values
        {
            if it_index == 0
                Append (builder, " ");
            else
                Append (builder, ", ");

            EmitExpression (builder, it);
        }

    case .Flow_Control;
        Append (builder, "%", TokenRangeToString (node.range));

    case .Assignment;
        assign := cast (*AstAssignment) node;
        EmitExpression (builder, assign.left);
        Append (builder, " % ", TokenToString (assign.op));
        EmitExpression (builder, assign.right);

    case .Expressions_Begin;

    case .Identifier; #through;
    case .Literal; #through;
    case .Binary; #through;
    case .Unary; #through;
    case .Subscript; #through;
    case .Field_Access; #through;
    case .Procedure_Call;
        EmitExpression (builder, node);

    case .Expressions_End;
    case .Statements_End;
    case .Types_Begin;
    case .Type_Pointer;
    case .Type_Array;
    case .Type_Named;
    case .Type_Primitive;
    case .Procedure;
        EmitProcedure (builder, cast (*AstProcedure) node);
    case .Struct;
    case .Enum;
    case .Types_End;
    case .Count;
    }
}

EmitExpression :: (builder : *SourceCodeBuilder, node : *AstNode)
{
    if node.semantic_meaning == .Constant
    {
        if node.value.kind ==
        {
        case .Integer;
            Append (builder, "%", node.value.int_value);
            return;
        case .Float;
            if node.type.size == 4
                Append (builder, "{:~.7}f", node.value.float_value);
            else
                Append (builder, "{:~.17}", node.value.float_value);
            return;
        case .Boolean;
            Append (builder, "%", node.value.bool_value);
            return;
        case .String;
            Append (builder, "{:'}", node.value.string_value);
            return;
        case .Pointer;
            Append (builder, "%", cast (*void) node.value.pointer_value);
            return;
        }
    }

    if node.is_parenthesized
        Append (builder, "(");

    defer if node.is_parenthesized
        Append (builder, ")");

    if node.kind ==
    {
    case .Identifier;
        ident := cast (*AstIdentifier) node;
        Append (builder, ident.name);

    case .Literal;
        lit := cast (*AstLiteral) node;
        Panic (lit, "this case should have been handled earlier");

    case .Binary;
        binary := cast (*AstBinary) node;
        EmitExpression (builder, binary.left);
        Append (builder, " % ", TokenToString (binary.op));
        EmitExpression (builder, binary.right);

    case .Unary;
        unary := cast (*AstUnary) node;
        info := UnaryOperatorInfo (unary.op);

        if info.flags & .Prefix
            Append (builder, "%", TokenToString (unary.op));

        EmitExpression (builder, unary.expr);

        if info.flags & .Postfix
            Append (builder, "%", TokenToString (unary.op));

    case .Subscript;
        subscript := cast (*AstSubscript) node;

        EmitExpression (builder, subscript.subscripted);
        Append (builder, "[");
        EmitExpression (builder, subscript.index);
        Append (builder, "]");

    case .Field_Access;
        access := cast (*AstFieldAccess) node;

        EmitExpression (builder, access.left);
        Append (builder, ".");
        EmitExpression (builder, access.right);

    case .Procedure_Call;
        call := cast (*AstProcedureCall) node;

        EmitExpression (builder, call.callee);
        Append (builder, " (");

        for call.passed_arguments
        {
            if it_index != 0
                Append (builder, ", ");

            EmitExpression (builder, it);
        }

        Append (builder, ")");

    case;
        Panic (node, "invalid expression kind %", node.kind);
    }
}

EmitProcedure :: (builder : *SourceCodeBuilder, proc : *AstProcedure, name := "")
{
    EmitProcedureSignature (builder, proc, name);

    if proc.body
    {
        Append (builder, "\n");
        EmitAstNode (builder, proc.body);
    }
}

EmitCCodeForFile :: (builder : *SourceCodeBuilder, file : *YalFile)
{
    {
        auto_indent := builder.auto_indent;
        builder.auto_indent = false;
        defer builder.auto_indent = auto_indent;

        Append (builder, C_Header);
    }

    Append (builder, "// ======= Forward declarations =======\n\n");

    for file.declarations
    {
        EmitForwardDeclaration (builder, it);
    }

    Append (builder, "\n// ======= Procedure definitions =======\n");

    for file.declarations
    {
        if it.codegen_status == .Generated
            continue;

        more_newlines := !EmittedStatementShouldEndInSemicolon (it);

        if it_index != 0 && more_newlines
            Append (builder, "\n");

        EmitDeclaration (builder, it);

        if EmittedStatementShouldEndInSemicolon (it)
            Append (builder, ";\n");
        else
            Append (builder, "\n");
    }

    Append (builder, "\nint Yal__EntryPoint (int argc, char **argv)\n{\n(void)argc;\n(void)argv;\nMain ();\nreturn 0;\n}\n");
}
