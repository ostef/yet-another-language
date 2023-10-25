PrintValueDeclaration :: (builder : *SourceCodeBuilder, decl : *AstDeclaration)
{
    if decl.identifier_count == 0
    {
        PrintAstNode (builder, decl.type_node);
        return;
    }
    else
    {
        for :Identifiers decl
        {
            if it_index != 0
               Append (builder, ", ");
            Append (builder, it.name);
        }
    }

    Append (builder, " :");
    if decl.type_node
    {
        Append (builder, " ");
        PrintAstNode (builder, decl.type_node);
        if decl.expr
            Append (builder, " ");
    }

    if decl.expr
    {
        Append (builder, "= ");
        PrintAstNode (builder, decl.expr);
    }
}

PrintProcedure :: (builder : *SourceCodeBuilder, proc : *AstProcedure, name : string)
{
    Append (builder, "proc ");
    if name
        Append (builder, name);

    Append (builder, " (");
    for proc.parameters
    {
        if it_index != 0
            Append (builder, ", ");
        PrintValueDeclaration (builder, it);
    }
    Append (builder, ")");

    if proc.results.count > 0
        Append (builder, " -> ");

    if proc.results.count > 1
        Append (builder, "(");

    for proc.results
    {
        if it_index != 0
            Append (builder, ", ");
        PrintValueDeclaration (builder, it);
    }

    if proc.results.count > 1
        Append (builder, ")");

    if proc.body
    {
        Append (builder, "\n");
        PrintStatement (builder, proc.body);
    }
}

PrintStruct :: (builder : *SourceCodeBuilder, node : *AstStruct, name : string)
{
    Append (builder, "struct");
    if name
        Append (builder, " %", name);

    Append (builder, "\n");
    PrintStatement (builder, node.body);
}

PrintEnum :: (builder : *SourceCodeBuilder, node : *AstEnum, name : string)
{
    Append (builder, "enum");
    if name
        Append (builder, " %", name);

    if node.base_type
    {
        Append (builder, " ");
        PrintAstNode (builder, node.base_type);
    }

    Append (builder, "\n");
    PrintStatement (builder, node.body);
}

ShouldStatementEndInSemicolon :: inline (node : *AstNode) -> bool #must
{
    if node.kind == .Block || node.kind == .If || node.kind == .While || node.kind == .Defer
        return false;
    if node.kind == .Declaration
    {
        decl_kind := (cast (*AstDeclaration) node).decl_kind;
        if decl_kind == .Procedure || decl_kind == .Struct || decl_kind == .Enum
            return false;
    }

    return true;
}

PrintStatement :: (builder : *SourceCodeBuilder, node : *AstNode)
{
    PrintAstNode (builder, node);

    if ShouldStatementEndInSemicolon (node)
        Append (builder, ";");
}

PrintAstNode :: (builder : *SourceCodeBuilder, node : *AstNode)
{
    if node.is_parenthesized
        Append (builder, "(");

    defer if node.is_parenthesized
        Append (builder, ")");

    if #complete node.kind ==
    {
    case .Invalid;
    case .Statements_Begin;

    case .Bad_Declaration;
    case .Declaration;
        decl := cast (*AstDeclaration) node;
        if #complete decl.decl_kind ==
        {
        case .Invalid;
        case .Variable;
            Append (builder, "var ");
            PrintValueDeclaration (builder, decl);
        case .Constant;
            Append (builder, "const ");
            PrintValueDeclaration (builder, decl);
        case .Field;
            PrintValueDeclaration (builder, decl);
        case .Procedure;
            if decl.identifier_count == 0
                PrintProcedure (builder, cast (*AstProcedure) decl.expr, "");
            else
                PrintProcedure (builder, cast (*AstProcedure) decl.expr, decl.single_identifier.name);

        case .Struct;
            if decl.identifier_count == 0
                PrintStruct (builder, cast (*AstStruct) decl.expr, "");
            else
                PrintStruct (builder, cast (*AstStruct) decl.expr, decl.single_identifier.name);

        case .Enum;
            if decl.identifier_count == 0
                PrintEnum (builder, cast (*AstEnum) decl.expr, "");
            else
                PrintEnum (builder, cast (*AstEnum) decl.expr, decl.single_identifier.name);

        case .Enum_Member;
            Assert (decl.identifier_count == 1);

            Append (builder, decl.single_identifier.name);
            if decl.expr
            {
                Append (builder, " = ");
                PrintAstNode (builder, decl.expr);
            }
        }

    case .Block;
        block := cast (*AstBlock) node;

        Append (builder, "{\n");
        for block.statements
        {
            more_newlines := !ShouldStatementEndInSemicolon (it);

            if it_index != 0 && more_newlines
                Append (builder, "\n");

            PrintStatement (builder, it);

            Append (builder, "\n");

            if it_index != block.statements.count - 1 && more_newlines
                Append (builder, "\n");
        }

        Append (builder, "}");

    case .If;
        if_stmt := cast (*AstIf) node;
        Append (builder, "if ");
        PrintAstNode (builder, if_stmt.condition);
        Append (builder, "\n");

        if ShouldStatementEndInSemicolon (if_stmt.body)
            Indent (builder);

        PrintStatement (builder, if_stmt.body);

        if ShouldStatementEndInSemicolon (if_stmt.body)
            Unindent (builder);

        if if_stmt.else_stmt
        {
            Append (builder, "\nelse ");

            if if_stmt.else_stmt.kind != .If && if_stmt.else_stmt.kind != .While
                Append (builder, "\n");

            if ShouldStatementEndInSemicolon (if_stmt.else_stmt)
                Indent (builder);

            PrintStatement (builder, if_stmt.else_stmt);

            if ShouldStatementEndInSemicolon (if_stmt.else_stmt)
                Unindent (builder);
        }

    case .While;
        while_stmt := cast (*AstWhile) node;
        Append (builder, "while ");
        PrintAstNode (builder, while_stmt.condition);
        Append (builder, "\n");

        if ShouldStatementEndInSemicolon (while_stmt.body)
            Indent (builder);

        PrintStatement (builder, while_stmt.body);

        if ShouldStatementEndInSemicolon (while_stmt.body)
            Unindent (builder);

    case .Defer;
        def := cast (*AstDefer) node;
        Append (builder, "defer ");
        PrintStatement (builder, def.stmt);

    case .Return;
        ret := cast (*AstReturn) node;
        Append (builder, "return");
        for ret.return_values
        {
            if it_index == 0
                Append (builder, " ");
            else
                Append (builder, ", ");

            PrintAstNode (builder, it);
        }

    case .Flow_Control;
        Append (builder, "%", TokenRangeToString (node.range));

    case .Assignment;
        assign := cast (*AstAssignment) node;
        PrintAstNode (builder, assign.left);
        Append (builder, " % ", TokenToString (assign.op));
        PrintAstNode (builder, assign.right);

    case .Expressions_Begin;
    case .Identifier;
        ident := cast (*AstIdentifier) node;
        Append (builder, ident.name);

    case .Literal;
        Append (builder, TokenRangeToString (node.range));

    case .Binary;
        binary := cast (*AstBinary) node;
        PrintAstNode (builder, binary.left);
        Append (builder, " % ", TokenToString (binary.op));
        PrintAstNode (builder, binary.right);

    case .Unary;
        unary := cast (*AstUnary) node;
        info := UnaryOperatorInfo (unary.op);

        if info.flags & .Prefix
            Append (builder, "%", TokenToString (unary.op));

        PrintAstNode (builder, unary.expr);

        if info.flags & .Postfix
            Append (builder, "%", TokenToString (unary.op));

    case .Subscript;
        subscript := cast (*AstSubscript) node;

        PrintAstNode (builder, subscript.subscripted);
        Append (builder, "[");
        PrintAstNode (builder, subscript.index);
        Append (builder, "]");

    case .Field_Access;
        access := cast (*AstFieldAccess) node;

        PrintAstNode (builder, access.left);
        Append (builder, ".");
        PrintAstNode (builder, access.right);

    case .Procedure_Call;
        call := cast (*AstProcedureCall) node;

        PrintAstNode (builder, call.callee);
        Append (builder, " (");

        for call.passed_arguments
        {
            if it_index != 0
                Append (builder, ", ");

            PrintAstNode (builder, it);
        }

        Append (builder, ")");

    case .Expressions_End;
    case .Statements_End;
    case .Types_Begin;
    case .Type_Pointer;
        pointer := cast (*AstTypePointer) node;
        Append (builder, "*");
        PrintAstNode (builder, pointer.pointed_type);

    case .Type_Array;
        array := cast (*AstTypeArray) node;

        Append (builder, "[");

        if array.array_kind ==
        {
        case .Dynamic;
            Append (builder, "..");
        case .Static;
            PrintAstNode (builder, array.element_count);
        }

        Append (builder, "]");

        PrintAstNode (builder, array.element_type);

    case .Type_Named;
        named := cast (*AstTypeNamed) node;
        Append (builder, named.identifier.name);

    case .Type_Primitive;
        Append (builder, TokenRangeToString (node));

    case .Procedure;
        PrintProcedure (builder, cast (*AstProcedure) node, "");
    case .Struct;
        PrintStruct (builder, cast (*AstStruct) node, "");
    case .Enum;
        PrintEnum (builder, cast (*AstEnum) node, "");
    case .Types_End;
    case .Count;
    }
}
