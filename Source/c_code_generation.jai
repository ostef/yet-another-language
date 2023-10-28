// @Todo: mangle names

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

#include <assert.h>
#include <stdio.h>
#include <malloc.h>

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

enum
{
    false = 0,
    true = 1,
};

#define null ((void*)0)

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

void Yal__WriteString (Yal__String str)
{
    printf ("%.*s", (int)str.count, str.data);
}

void *Yal__malloc (u64 size)
{
    return malloc (size);
}

void *Yal__realloc (void *ptr, u64 new_size)
{
    return realloc (ptr, new_size);
}

void Yal__free (void *ptr)
{
    free (ptr);
}
C

C_Entry_Point :: #string C

// ======= Entry point =======

int main (int argc, char **argv)
{
    (void)argc;
    (void)argv;

    Main ();

    return 0;
}
C

C_Entry_Point_With_Arguments :: #string C

// ======= Entry point =======

int main (int argc, char **argv)
{
    Yal__Slice args;
    args.count = argc;
    args.data = (Yal__String*)alloca (sizeof (Yal__String) * argc);

    for (int i = 0; i < argc; i += 1)
    {
        ((Yal__String *)args.data)[i].data = argv[i];

        int len = 0;
        while (argv[i][len])
            len += 1;

        ((Yal__String *)args.data)[i].count = len;
    }

    Main (args);

    return 0;
}
C

EmitDependenciesForwardDeclaration :: (builder : *SourceCodeBuilder, node : *$T)
#modify { return TypeIsAstNode (cast (*Type_Info) T); }
{
    if !node
        return;

    #if T == AstNode
    {
        inline EmitDependenciesForwardDeclarationForUntypedNode (builder, node);
    }
    else #if T == AstDeclaration
    {
        if node.decl_kind ==
        {
        case .Variable; #through;
        case .Field;
            EmitDependenciesForwardDeclaration (builder, node.type_node);
            EmitDependenciesForwardDeclaration (builder, node.expr);

        case .Procedure;
            proc_node := cast (*AstProcedure) node.expr;
            for proc_node.parameters
                EmitDependenciesForwardDeclaration (builder, it);

            for proc_node.results
                EmitDependenciesForwardDeclaration (builder, it);

        // case .Typedef;
        //     EmitDependenciesForwardDeclaration (builder, node.expr);
        }
    }
    else #if T == AstIdentifier
    {
        if node.symbol
            EmitForwardDeclaration (builder, node.symbol.decl);
    }
    else
    {
        #insert -> string
        {
            info := type_info (T);

            builder : StringBuilder;

            StringBuilderAppend (*builder, "// EmitDependenciesForwardDeclaration for %\n", T);

            for member : info.members
            {
                for note : member.notes
                {
                    if note == "NoCollectSymbols"
                    {
                        StringBuilderAppend (*builder, "// % is ignored\n", member.name);
                        continue member;
                    }
                }

                if member.type.type == .POINTER
                {
                    pointed_type := (cast (*Type_Info_Pointer) member.type).pointer_to;
                    if TypeIsAstNode (pointed_type)
                        StringBuilderAppend (*builder, "EmitDependenciesForwardDeclaration (builder, node.%);\n", member.name);
                }
                else if member.type.type == .ARRAY
                {
                    element_type := (cast (*Type_Info_Array) member.type).element_type;
                    pointed_type : *Type_Info;
                    if element_type.type == .POINTER
                        pointed_type = (cast (*Type_Info_Pointer) element_type).pointer_to;

                    if pointed_type && TypeIsAstNode (pointed_type)
                    {
                        StringBuilderAppend (*builder, "for node.%\n", member.name);
                        StringBuilderAppend (*builder, "    EmitDependenciesForwardDeclaration (builder, it);\n");
                    }
                }
            }

            return StringBuilderBuild (*builder);
        }
    }
}

EmitDependenciesForwardDeclarationForUntypedNode :: (builder : *SourceCodeBuilder, node : *AstNode)
{
    Ignore_Kinds :: AstKind.[
        .Invalid,
        .Statements_Begin,
        .Bad_Declaration,
        .Expressions_Begin,
        .Expressions_End,
        .Statements_End,
        .Types_Begin,
        .Types_End,
        .Count
    ];

    #insert -> string
    {
        AppendAstStructName :: (builder : *StringBuilder, kind : AstKind)
        {
            StringBuilderAppend (builder, "Ast");

            name := type_info (AstKind).names[kind];
            for i : 0..name.count - 1
            {
                if name[i] == #char "_"
                    continue;

                StringBuilderAppendByte (builder, name[i]);
            }
        }

        builder : StringBuilder;

        StringBuilderAppend (*builder, "if node.kind ==\n{\n");
        for i : 0..AstKind.Count - 1
        {
            kind := cast (AstKind) i;
            for Ignore_Kinds
            {
                if it == kind
                    continue i;
            }

            StringBuilderAppend (*builder, "case .%;\n", kind);
            StringBuilderAppend (*builder, "    EmitDependenciesForwardDeclaration (builder, cast (*");
            AppendAstStructName (*builder, kind);
            StringBuilderAppend (*builder, ") node);\n");
        }
        StringBuilderAppend (*builder, "}");

        return StringBuilderBuild (*builder);
    };
}

EmitForwardDeclaration :: (builder : *SourceCodeBuilder, decl : *AstDeclaration)
{
    Assert (decl, decl.codegen_status != .Generating_Forward_Decl && decl.codegen_status != .Generating, "Circular dependency when emitting C code");

    if decl.codegen_status != .Not_Generated
        return;

    EmitDependenciesForwardDeclaration (builder, decl);

    if #complete decl.decl_kind ==
    {
    case .Invalid;
    case .Variable;;
        decl.codegen_status = .Generating;
        defer decl.codegen_status = .Generated;

        EmitVariableDeclaration (builder, decl);
        Append (builder, ";\n");

    case .Field;
        decl.codegen_status = .Generated_Forward_Decl;

    case .Constant;
        decl.codegen_status = .Generated;

        // We don't generate constant declarations because we emit the value directly when a constant is used
        Append (builder, "/* omitting % */\n", TokenRangeToString (decl));

    case .Procedure;
        // Technically we don't need to emit anything for external proc, since external means
        // "this declaration is from C world", but this allows us to have the C typechecker
        // check our external proc's signature against the one that is already declared.

        if decl.decl_flags & .External
           decl.codegen_status = .Generating;
        else
           decl.codegen_status = .Generating_Forward_Decl;

        defer if decl.decl_flags & .External
            decl.codegen_status = .Generated;
        else
            decl.codegen_status = .Generated_Forward_Decl;

        Assert (decl.identifier_count == 1);

        name := decl.single_identifier.name;
        if decl.decl_flags & .External
            name = StringJoin ("Yal__", name);

        EmitProcedureSignature (builder, cast (*AstProcedure) decl.expr, name);
        Append (builder, ";\n");

    case .Struct;
        decl.codegen_status = .Generating_Forward_Decl;
        defer decl.codegen_status = .Generated_Forward_Decl;

        Assert (decl.identifier_count == 1);

        Append (builder, "struct %;\n", decl.single_identifier.name);

    case .Enum;
        decl.codegen_status = .Generating_Forward_Decl;
        defer decl.codegen_status = .Generated_Forward_Decl;

        Assert (decl.identifier_count == 1);

        Append (builder, "typedef ");

        enum_type := cast (*YalTypeEnum) decl.type;
        if enum_type.base_type
            EmitFullType (builder, enum_type.base_type);
        else
            Append (builder, "s64");

        Append (builder, " %", decl.single_identifier.name);

        Append (builder, ";\n");

    case .Enum_Member;
        // Enum member cannot be forward declared

    case .Typedef;
    // @Todo: handle type emission for struct typedefs, right now they do not get deduplicated
    // We don't need to emit anything for typedefs
    //     EmitTypedefDeclaration (builder, decl);
    }
}

EmitTypedefDeclaration :: (builder : *SourceCodeBuilder, decl : *AstDeclaration)
{
    decl.codegen_status = .Generating;
    defer decl.codegen_status = .Generated;

    Assert (decl.identifier_count == 1);

    Append (builder, "typedef ");
    EmitTypePrefix (builder, decl.type);
    Append (builder, " %", decl.single_identifier.name);
    EmitTypeSuffix (builder, decl.type);
    Append (builder, ";\n");
}

EmitVariableDeclaration :: (builder : *SourceCodeBuilder, decl : *AstDeclaration, index_in_list := -1)
{
    Assert (decl, decl.identifier_count < 2, "Multiple identifiers are not yet handled for C codegen");

    if decl.type.kind == .Invalid
        Panic (decl, "Invalid type for declaration");

    EmitTypePrefix (builder, decl.type);

    if decl.single_identifier
        Append (builder, " %", decl.single_identifier.name);
    else if index_in_list != -1
        Append (builder, " Yal__unnamed%", index_in_list);

    EmitTypeSuffix (builder, decl.type);

    if decl.expr
    {
        Append (builder, " = ");
        EmitExpression (builder, decl.expr);
    }
}

EmitDeclaration :: (builder : *SourceCodeBuilder, decl : *AstDeclaration)
{
    Assert (decl, decl.codegen_status != .Generating_Forward_Decl && decl.codegen_status != .Generating, "Circular dependency when emitting C code");

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

    case .Struct;
        Append (builder, "typedef ");
        EmitStruct (builder, cast (*AstStruct) decl.expr, decl.single_identifier.name);
        Append (builder, " %", decl.single_identifier.name);

    case .Enum;
        // We don't emit enums since enum members are emitted directly as their value because they are constants
        //EmitEnum (builder, cast (*AstEnum) decl.expr, decl.single_identifier.name);
    case .Enum_Member;
        Append (builder, "% = ", decl.single_identifier.name);
        EmitValue (builder, decl.value, decl.type);

    case .Typedef;
        EmitTypedefDeclaration (builder, decl);
    }
}

EmitProcedureSignature :: (builder : *SourceCodeBuilder, proc : *AstProcedure, name := "")
{
    Assert (proc, proc.results.count < 2, "Multiple return values are not yet handled for C codegen");

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
        EmitVariableDeclaration (builder, it, it_index);
    }
    Append (builder, ")");
}

EmitStruct :: (builder : *SourceCodeBuilder, node : *AstStruct, name := "")
{
    Append (builder, "struct");
    if name
        Append (builder, " %", name);

    Append (builder, "\n");
    EmitAstNode (builder, node.body);
}

/*
EmitEnum :: (builder : *SourceCodeBuilder, node : *AstEnum, name := "")
{
    Append (builder, "enum");
    Append (builder, "\n");
    EmitAstNode (builder, node.body);
}
*/

EmitTypePrefix :: (builder : *SourceCodeBuilder, type : *YalType)
{
    if #complete type.kind ==
    {
    case .Invalid;
        Panic ("Invalid type");
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

        Append (builder, " (*");

    case .Struct;
        type_struct := cast (*YalTypeStruct) type;

        Assert (type_struct.name != "");
        Append (builder, "struct %", type_struct.name);

    case .Enum;
        type_enum := cast (*YalTypeEnum) type;

        Assert (type_enum.name != "");
        Append (builder, type_enum.name);
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

        Append (builder, ") (");
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
        if decl.decl_kind ==
        {
        case .Procedure; #through;
        case .Constant; #through;
        case .Field; #through;
        case .Enum; #through;
        case .Enum_Member;
            return false;
        }
    }

    return true;
}

EmittedStatementShouldEndInComma :: inline (node : *AstNode) -> bool #must
{
    if node.kind == .Declaration
    {
        decl := cast (*AstDeclaration) node;
        if decl.decl_kind == .Enum_Member
            return true;
    }

    return false;
}

EmitFullType :: inline (builder : *SourceCodeBuilder, type : *YalType)
{
    EmitTypePrefix (builder, type);
    EmitTypeSuffix (builder, type);
}

EmitStatement :: (builder : *SourceCodeBuilder, node : *AstNode)
{
    is_struct := node.kind == .Declaration && (cast (*AstDeclaration) node).decl_kind == .Struct;

    if is_struct
        Append (builder, "\n#pragma pack (push, 1)\n");

    EmitAstNode (builder, node);

    if EmittedStatementShouldEndInSemicolon (node)
        Append (builder, ";");
    else if EmittedStatementShouldEndInComma (node)
        Append (builder, ",");

    if is_struct
    {
        Append (builder, "\n#pragma pack (pop)\n");
        type_struct := cast (*YalTypeStruct) node.type;
        Append (builder, "static_assert (sizeof (%) == %, \"Mismatching size for emitted struct\");\n", type_struct.name, type_struct.size);
    }
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

        Assert (ret, ret.return_values.count < 2, "Multiple return values are not yet handled for codegen");

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
    case .Procedure_Call; #through;
    case .Cast; #through;
    case .Size_Of;
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
        EmitStruct (builder, cast (*AstStruct) node);
    case .Enum;
        // We don't emit enums since we unwrap enum member values, as they are constants
    case .Types_End;
    case .Count;
    }
}

EmitValue :: (builder : *SourceCodeBuilder, value : ConstantValue, type : *YalType) -> emitted : bool
{
    if value.kind ==
    {
    case .Integer;
        Append (builder, "%", value.int_value);
        return true;
    case .Float;
        if type.size == 4
            Append (builder, "{:~.7}f", value.float_value);
        else
            Append (builder, "{:~.17}", value.float_value);
        return true;
    case .Boolean;
        Append (builder, "%", value.bool_value);
        return true;
    case .String;
        Append (builder, "(Yal__String){{ sizeof ({0:'}) - 1, {0:'} }", value.string_value);
        // Append (builder, "{:'}", value.string_value);
        return true;
    case .Pointer;
        Append (builder, "%", cast (*void) value.pointer_value);
        return true;
    }

    return false;
}

EmitExpression :: (builder : *SourceCodeBuilder, node : *AstNode)
{
    if node.semantic_meaning == .Constant
    {
        if EmitValue (builder, node.value, node.type)
            return;
    }

    if node.is_parenthesized
        Append (builder, "(");

    defer if node.is_parenthesized
        Append (builder, ")");

    if node.kind ==
    {
    case .Identifier;
        ident := cast (*AstIdentifier) node;

        if ident.symbol && ident.symbol.decl.decl_flags & .External
            Append (builder, "Yal__");

        Append (builder, ident.name);

    case .Literal;
        lit := cast (*AstLiteral) node;
        Panic (lit, "This case should have been handled earlier");

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
        EmitSubscript (builder, cast (*AstSubscript) node);

    case .Cast;
        cast_node := cast (*AstCast) node;

        Append (builder, "((");
        EmitFullType (builder, cast_node.type_node.type);
        Append (builder, ")");
        EmitExpression (builder, cast_node.expr);
        Append (builder, ")");

    case .Size_Of;
        size_of_node := cast (*AstSizeOf) node;

        Append (builder, "sizeof (");
        EmitFullType (builder, size_of_node.type_node.type);
        Append (builder, ")");

    case .Field_Access;
        access := cast (*AstFieldAccess) node;

        // Special case for accessing .data of a static array
        if access.left.type.kind == .Array && (cast (*YalTypeArray) access.left.type).array_kind == .Static
        {
            EmitExpression (builder, access.left);
            return;
        }

        // In some cases the C type we accessed does not match the original type in the Yal source code
        // This is the case for the data pointer of slices and dynamic arrays for example
        // When that happens, we cast the expression to the desired type
        needs_cast := access.type.kind == .Pointer;
        needs_arrow := access.left.type.kind == .Pointer;

        if needs_cast
        {
            Append (builder, "((");
            EmitFullType (builder, access.type);
            Append (builder, " *)&");
        }

        EmitExpression (builder, access.left);
        if needs_arrow
            Append (builder, "->");
        else
            Append (builder, ".");
        EmitExpression (builder, access.right);

        if needs_cast
            Append (builder, ")[0]");

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
        Panic (node, "Invalid expression kind %", node.kind);
    }
}

EmitSubscript :: (builder : *SourceCodeBuilder, using subscript : *AstSubscript)
{
    // @Todo: emit bounds checking

    if subscripted.type.kind ==
    {
    case .String;
        Append (builder, "(");
        EmitExpression (builder, subscripted);
        Append (builder, ").data");

    case .Array;
        type_array := cast (*YalTypeArray) subscripted.type;

        if type_array.array_kind ==
        {
        case .Slice; #through;
        case .Dynamic;
            Append (builder, "((");
            EmitFullType (builder, MakeTypePointer (type_array.element_type));
            Append (builder, ")");
            Append (builder, "(");
            EmitExpression (builder, subscripted);
            Append (builder, ").data)");

        case .Static;
            EmitExpression (builder, subscripted);
        }

    case .Pointer;
        EmitExpression (builder, subscripted);
    }

    Append (builder, "[");
    EmitExpression (builder, index);
    Append (builder, "]");
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

    Append (builder, "\n// ======= Full definitions =======\n\n");

    for file.declarations
    {
        if it.codegen_status == .Generated
            continue;

        more_newlines := !EmittedStatementShouldEndInSemicolon (it);

        if it_index != 0 && more_newlines
            Append (builder, "\n");

        EmitStatement (builder, it);

        Append (builder, "\n");

    }

    {
        auto_indent := builder.auto_indent;
        builder.auto_indent = false;
        defer builder.auto_indent = auto_indent;

        entry_point_type := cast (*YalTypeProcedure) file.entry_point_declaration.type;
        if entry_point_type.parameters.count > 0
            Append (builder, C_Entry_Point_With_Arguments);
        else
            Append (builder, C_Entry_Point);
    }
}
