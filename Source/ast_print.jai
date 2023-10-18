PrintValueDeclaration :: (builder : *StringBuilder, decl : *AstDeclaration, indent_level : int)
{
    if decl.identifier_count == 0
    {
        PrintAstNode (builder, decl.type_node);
        return;
    }
    else if decl.identifier_count == 1
    {
        StringBuilderAppend (builder, decl.single_identifier.name);
    }
    else
    {
        for decl.identifiers
        {
            if it_index != 0
               StringBuilderAppend (builder, ", ");
            StringBuilderAppend (builder, it.name);
        }
    }

    StringBuilderAppend (builder, " :");
    if decl.type_node
    {
        StringBuilderAppend (builder, " ");
        PrintAstNode (builder, decl.type_node);
        if decl.expr
            StringBuilderAppend (builder, " ");
    }

    if decl.expr
    {
        StringBuilderAppend (builder, "= ");
        PrintAstNode (builder, decl.expr, indent_level);
    }
}

PrintProcedure :: (builder : *StringBuilder, proc : *AstProcedure, name : string, indent_level : int)
{
    StringBuilderAppend (builder, "proc ");
    if name
        StringBuilderAppend (builder, name);

    StringBuilderAppend (builder, " (");
    for proc.parameters
    {
        if it_index != 0
            StringBuilderAppend (builder, ", ");
        PrintValueDeclaration (builder, it, indent_level);
    }
    StringBuilderAppend (builder, ")");

    if proc.results.count > 0
        StringBuilderAppend (builder, " -> ");

    if proc.results.count > 1
        StringBuilderAppend (builder, "(");

    for proc.results
    {
        if it_index != 0
            StringBuilderAppend (builder, ", ");
        PrintValueDeclaration (builder, it, indent_level);
    }

    if proc.results.count > 1
        StringBuilderAppend (builder, ")");

    if proc.body
    {
        StringBuilderAppend (builder, "\n");
        PrintStatement (builder, proc.body, indent_level);
    }
}

PrintStatement :: (builder : *StringBuilder, node : *AstNode, indent_level := 0)
{
    ShouldStatementEndInSemicolon :: inline (node : *AstNode) -> bool #must
    {
        if node.kind == .Block
            return false;
        if node.kind == .Declaration
        {
            decl := cast (*AstDeclaration) node;
            if decl.decl_kind == .Procedure
                return false;
        }

        return true;
    }

    for 0..indent_level - 1
        StringBuilderAppend (builder, "    ");

    PrintAstNode (builder, node, indent_level);

    if ShouldStatementEndInSemicolon (node)
        StringBuilderAppend (builder, ";");
}

PrintAstNode :: (builder : *StringBuilder, node : *AstNode, indent_level := 0)
{
    if node.is_parenthesized
        StringBuilderAppend (builder, "(");

    defer if node.is_parenthesized
        StringBuilderAppend (builder, ")");

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
            StringBuilderAppend (builder, "var ");
            PrintValueDeclaration (builder, decl, indent_level);
        case .Constant;
            StringBuilderAppend (builder, "const ");
            PrintValueDeclaration (builder, decl, indent_level);
        case .Field;
            PrintValueDeclaration (builder, decl, indent_level);
        case .Procedure;
            if decl.identifier_count == 0
                PrintProcedure (builder, cast (*AstProcedure) decl.expr, "", indent_level);
            else
                PrintProcedure (builder, cast (*AstProcedure) decl.expr, decl.single_identifier.name, indent_level);
        }

    case .Block;
        block := cast (*AstBlock) node;

        StringBuilderAppend (builder, "{\n");
        for block.statements
        {
            more_newlines := it.kind == .Declaration && (cast (*AstDeclaration) it).decl_kind == .Procedure;

            if it_index != 0 && more_newlines
                StringBuilderAppend (builder, "\n");

            PrintStatement (builder, it, indent_level + 1);

            StringBuilderAppend (builder, "\n");

            if it_index != block.statements.count -1 && more_newlines
                StringBuilderAppend (builder, "\n");
        }

        for 0..indent_level - 1
            StringBuilderAppend (builder, "    ");

        StringBuilderAppend (builder, "}");

    case .Assignment;
        assign := cast (*AstAssignment) node;
        PrintAstNode (builder, assign.left, indent_level);
        StringBuilderAppend (builder, " % ", TokenToString (assign.op));
        PrintAstNode (builder, assign.right, indent_level);

    case .Expressions_Begin;
    case .Identifier;
        ident := cast (*AstIdentifier) node;
        StringBuilderAppend (builder, ident.name);

    case .Literal;
        StringBuilderAppend (builder, TokenRangeToString (node.range));

    case .Binary;
        binary := cast (*AstBinary) node;
        PrintAstNode (builder, binary.left, indent_level);
        StringBuilderAppend (builder, " % ", TokenToString (binary.op));
        PrintAstNode (builder, binary.right, indent_level);

    case .Unary;
        unary := cast (*AstUnary) node;
        info := UnaryOperatorInfo (unary.op);

        if info.flags & .Prefix
            StringBuilderAppend (builder, "%", TokenToString (unary.op));

        PrintAstNode (builder, unary.expr, indent_level);

        if info.flags & .Postfix
            StringBuilderAppend (builder, "%", TokenToString (unary.op));

    case .Expressions_End;
    case .Statements_End;
    case .Types_Begin;
    case .Type_Pointer;
        pointer := cast (*AstTypePointer) node;
        StringBuilderAppend (builder, "*");
        PrintAstNode (builder, pointer.pointed_type, indent_level);

    case .Type_Array;
        array := cast (*AstTypeArray) node;

        StringBuilderAppend (builder, "[");

        if array.array_kind ==
        {
        case .Dynamic;
            StringBuilderAppend (builder, "..");
        case .Static;
            PrintAstNode (builder, array.element_count, indent_level);
        }

        StringBuilderAppend (builder, "]");

        PrintAstNode (builder, array.element_type, indent_level);

    case .Type_Named;
        named := cast (*AstTypeNamed) node;
        StringBuilderAppend (builder, named.identifier.name);

    case .Type_Primitive;
        StringBuilderAppend (builder, TokenRangeToString (node));

    case .Procedure;
        PrintProcedure (builder, cast (*AstProcedure) node, "", indent_level);
    case .Struct;
    case .Enum;
    case .Types_End;
    case .Count;
    }
}
