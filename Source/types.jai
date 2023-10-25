YalType :: struct
{
    Kind :: enum u8
    {
        Invalid;
        Void;
        Integer;
        Float;
        Bool;
        String;
        Pointer;
        Array;
        Procedure;
        Struct;
        Enum;
    }

    as_string : string;
    kind : Kind;
    size := -1;
}

YalTypeInteger :: struct
{
    #as using base : YalType;
    base.kind = .Integer;

    is_signed : bool;
}

YalTypePointer :: struct
{
    #as using base : YalType;
    base.kind = .Pointer;
    base.size = 8;

    pointed_type : *YalType;
}

YalTypeArray :: struct
{
    #as using base : YalType;
    base.kind = .Array;

    array_kind : ArrayKind;
    element_type : *YalType;
    count : s64;
}

YalTypeProcedure :: struct
{
    #as using base : YalType;
    base.kind = .Procedure;
    base.size = 8;

    node : *AstProcedure;
    parameters : []*YalType;
    results : []*YalType;
}

YalTypeStructMember :: struct
{
    name : string;
    byte_offset := -1;
    type : *YalType;
}

YalTypeStruct :: struct
{
    #as using base : YalType;
    base.kind = .Struct;

    node : *AstStruct;
    name : string;
    members : []YalTypeStructMember;
}

YalTypeEnumMember :: struct
{
    name : string;
    value : s64;
}

YalTypeEnum :: struct
{
    #as using base : YalType;
    base.kind = .Enum;

    node : *AstEnum;
    base_type : *YalType;
    name : string;
    members : []YalTypeEnumMember;
}

MakeType :: (kind : YalType.Kind, size : s64, node_for_debug : *AstNode = null) -> *YalType #must
{
    type := Alloc (YalType);
    type.kind = kind;
    type.size = size;
    SetTypeString (type);

    return type;
}

MakeTypeInteger :: (size : s64, is_signed : bool, node_for_debug : *AstNode = null) -> *YalTypeInteger #must
{
    type := Alloc (YalTypeInteger);
    type.size = size;
    type.is_signed = is_signed;
    SetTypeString (type);

    return type;
}

MakeTypePointer :: (pointed_type : *YalType, node_for_debug : *AstNode = null) -> *YalTypePointer #must
{
    type := Alloc (YalTypePointer);
    type.size = 8;
    type.pointed_type = pointed_type;
    SetTypeString (type);

    return type;
}

MakeTypeArray :: (array_kind : ArrayKind, element_type : *YalType, count : s64, node_for_debug : *AstNode = null) -> *YalTypeArray #must
{
    type := Alloc (YalTypeArray);
    type.array_kind = array_kind;

    if array_kind == .Static
    {
        if element_type.size == -1
        {
            if node_for_debug
                Panic (node_for_debug, "Array element type is unsized for static array, so we cannot calculate array size");
            else
                Panic ("Array element type is unsized for static array, so we cannot calculate array size");
        }

        type.size = element_type.size * count;
    }
    else if array_kind == .Dynamic
    {
        type.size = 8 + 8 + 8 + 16;  // capacity + count + data + allocator
    }
    else if array_kind == .Slice
    {
        type.size = 8 + 8;  // count + data
    }

    type.element_type = element_type;
    type.count = count;
    SetTypeString (type);

    return type;
}

MakeTypeProcedure :: (node : *AstProcedure, parameters : []*YalType, results : []*YalType) -> *YalTypeProcedure #must
{
    type := Alloc (YalTypeProcedure);
    type.size = 8;
    type.node = node;
    type.parameters = parameters;
    type.results = results;
    SetTypeString (type);

    return type;
}

MakeTypeStruct :: (node : *AstStruct, name : string) -> *YalTypeStruct #must
{
    type := Alloc (YalTypeStruct);
    type.node = node;
    type.name = name;
    SetTypeString (type);

    return type;
}

MakeTypeEnum :: (node : *AstEnum, name : string, base_type : *YalType) -> *YalTypeEnum #must
{
    type := Alloc (YalTypeEnum);
    type.node = node;
    type.name = name;
    type.base_type = base_type;
    type.size = base_type.size;
    SetTypeString (type);

    return type;
}

g_type_invalid : *YalType;
g_type_void : *YalType;
g_type_void_ptr : *YalType;
g_type_s64 : *YalType;
g_type_u64 : *YalType;
g_type_s32 : *YalType;
g_type_u32 : *YalType;
g_type_s16 : *YalType;
g_type_u16 : *YalType;
g_type_s8 : *YalType;
g_type_u8 : *YalType;
g_type_u8_ptr : *YalType;
g_type_f32 : *YalType;
g_type_f64 : *YalType;
g_type_bool : *YalType;
g_type_string : *YalType;

InitBuiltinTypes :: ()
{
    g_type_invalid = MakeType (.Invalid, -1);
    g_type_void = MakeType (.Void, 0);
    g_type_void_ptr =  MakeTypePointer (g_type_void);
    g_type_s64 = MakeTypeInteger (8, true);
    g_type_u64 = MakeTypeInteger (8, false);
    g_type_s32 = MakeTypeInteger (4, true);
    g_type_u32 = MakeTypeInteger (4, false);
    g_type_s16 = MakeTypeInteger (2, true);
    g_type_u16 = MakeTypeInteger (2, false);
    g_type_s8 = MakeTypeInteger (1, true);
    g_type_u8 = MakeTypeInteger (1, false);
    g_type_u8_ptr = MakeTypePointer (g_type_u8);
    g_type_f64 = MakeType (.Float, 8);
    g_type_f32 = MakeType (.Float, 4);
    g_type_bool = MakeType (.Bool, 1);
    g_type_string = MakeType (.String, 16);
}

AppendType :: (builder : *StringBuilder, type : *YalType)
{
    Assert (type != null);

    if type.as_string
    {
        StringBuilderAppend (builder, type.as_string);
        return;
    }

    if #complete type.kind ==
    {
    case .Invalid;
        StringBuilderAppend (builder, "<invalid>");
    case .Void;
        StringBuilderAppend (builder, "void");
    case .Integer;
        if (cast (*YalTypeInteger) type).is_signed
            StringBuilderAppend (builder, "s%", type.size * 8);
        else
            StringBuilderAppend (builder, "u%", type.size * 8);
    case .Float;
        if type.size == 4
            StringBuilderAppend (builder, "f32");
        else
            StringBuilderAppend (builder, "f64");
    case .Bool;
        StringBuilderAppend (builder, "bool");
    case .String;
        StringBuilderAppend (builder, "string");

    case .Pointer;
        StringBuilderAppend (builder, "*");
        AppendType (builder, (cast (*YalTypePointer) type).pointed_type);

    case .Array;
        array_type := cast (*YalTypeArray) type;

        StringBuilderAppend (builder, "[");
        if array_type.array_kind ==
        {
        case .Dynamic;
            StringBuilderAppend (builder, "..");
        case .Static;
            StringBuilderAppend (builder, "%", array_type.count);
        }
        StringBuilderAppend (builder, "]");
        AppendType (builder, array_type.element_type);

    case .Procedure;
        proc_type := cast (*YalTypeProcedure) type;

        StringBuilderAppend (builder, "proc (");

        for param : proc_type.parameters
        {
            if it_index != 0
                StringBuilderAppend (builder, ", ");
            AppendType (builder, param);
        }

        StringBuilderAppend (builder, ")");

        if proc_type.results.count > 0
            StringBuilderAppend (builder, " -> ");
        if proc_type.results.count > 1
            StringBuilderAppend (builder, "(");

        for result : proc_type.results
        {
            if it_index != 0
                StringBuilderAppend (builder, ", ");
            AppendType (builder, result);
        }

        if proc_type.results.count > 1
            StringBuilderAppend (builder, ")");

    case .Struct;
        type_struct := cast (*YalTypeStruct) type;
        if !type_struct.name
            StringBuilderAppend (builder, "struct <anonymous>");
        else
            StringBuilderAppend (builder, "struct %", type_struct.name);

    case .Enum;
        type_enum := cast (*YalTypeEnum) type;
        if !type_enum.name
            StringBuilderAppend (builder, "enum <anonymous>");
        else
            StringBuilderAppend (builder, "enum %", type_enum.name);
    }
}

SetTypeString :: inline (type : *YalType)
{
    builder : StringBuilder;
    builder.allocator = context.default_allocator;

    AppendType (*builder, type);
    type.as_string = StringBuilderBuild (*builder);
}

TypesAreEqual :: (a : *YalType, b : *YalType) -> bool #must
{
    if a == b
        return true;

    if a.kind != b.kind
        return false;

    if a.size != b.size
        return false;

    if #complete a.kind ==
    {
    case .Pointer;
        a_pointer := cast (*YalTypePointer) a;
        b_pointer := cast (*YalTypePointer) b;

        return TypesAreEqual (a_pointer.pointed_type, b_pointer.pointed_type);

    case .Array;
        a_array := cast (*YalTypeArray) a;
        b_array := cast (*YalTypeArray) b;

        if a_array.array_kind != b_array.array_kind
            return false;

        if a_array.array_kind == .Static && a_array.count != b_array.count
            return false;

        return TypesAreEqual (a_array.element_type, b_array.element_type);

    case .Integer;
        a_integer := cast (*YalTypeInteger) a;
        b_integer := cast (*YalTypeInteger) b;

        return a_integer.is_signed == b_integer.is_signed;

    case .Procedure;
        a_proc := cast (*YalTypeProcedure) a;
        b_proc := cast (*YalTypeProcedure) b;

        if a_proc.parameters.count != b_proc.parameters.count
            return false;

        if a_proc.results.count != b_proc.results.count
            return false;

        for i : 0..a_proc.parameters.count - 1
        {
            if !TypesAreEqual (a_proc.parameters[i], b_proc.parameters[i])
                return false;
        }

        for i : 0..a_proc.results.count - 1
        {
            if !TypesAreEqual (a_proc.results[i], b_proc.results[i])
                return false;
        }

        return true;

    case .Invalid; #through;
    case .Void; #through;
    case .String; #through;
    case .Bool; #through;
    case .Float;
        return true;

    case .Struct;
        return a == b;

    case .Enum;
        return a == b;
    }
}

TypeCanImplicitlyCastTo :: (type : *YalType, to : *YalType) -> bool #must
{
    return TypesAreEqual (type, to);
}
