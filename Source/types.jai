Use_Type_Cache :: true;

#import "Hash";

// This only count types cached in a hash set (array and pointer types for now)
g_dedup_types_count : s64;

// Some types will not get deduplicated even though they are equal, because
// they might point at types that have not been deduplicated and thus the
// hash and memcmp will be different

HashTypesIgnoringAsStringMember :: inline (type : *YalType, size : s64) -> u64 #must
{
    return fnv1a_hash (*type.kind, size - OffsetOf (YalType, "kind"));
}

MemcmpTypesIgnoringAsStringMember :: inline (a : *YalType, b : *YalType, size : s64) -> int #must
{
    return memcmp (*a.kind, *b.kind, size - OffsetOf (YalType, "kind"));
}

HashTypeProcedure :: (type : *YalTypeProcedure) -> u64 #must
{
    result := fnv1a_hash (cast (u64) type.node);

    for type.parameters
        result = fnv1a_hash (cast (u64) it, result);
    for type.results
        result = fnv1a_hash (cast (u64) it, result);

    return result;
}

ShallowCompareTypeProcedure :: (a : *YalTypeProcedure, b : *YalTypeProcedure) -> bool #must
{
    if a.node != b.node
        return false;

    if a.parameters.count != b.parameters.count
        return false;

    if a.results.count != b.results.count
        return false;

    for i : 0..a.parameters.count - 1 #no_abc
    {
        if a.parameters[i] != b.parameters[i]
            return false;
    }

    for i : 0..a.results.count - 1 #no_abc
    {
        if a.results[i] != b.results[i]
            return false;
    }

    return true;
}

g_pointer_type_cache : HashSet (
    *YalTypePointer,
    hash_func = (val) => HashTypesIgnoringAsStringMember (val, size_of (YalTypePointer)),
    comp_func = (a, b) => MemcmpTypesIgnoringAsStringMember (a, b, size_of (YalTypePointer)) == 0
);

g_array_type_cache : HashSet (
    *YalTypeArray,
    hash_func = (val) => HashTypesIgnoringAsStringMember (val, size_of (YalTypeArray)),
    comp_func = (a, b) => MemcmpTypesIgnoringAsStringMember (a, b, size_of (YalTypeArray)) == 0
);

// Not sure that this type cache will be very helpful since we take into account the procedure node
// which is probably unique everytime we call MakeTypeProcedure
g_proc_type_cache : HashSet (
    *YalTypeProcedure,
    hash_func = HashTypeProcedure,
    comp_func = ShallowCompareTypeProcedure
);

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

    // DISCLAIMER: do not change the layout of this! Some functions rely on it.
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
    if kind == .Invalid
    {
        if g_type_invalid
            return g_type_invalid;
    }
    else if kind == .Void
    {
        if g_type_void
            return g_type_void;
    }
    else if kind == .Float
    {
        if size == 4 && g_type_f32
            return g_type_f32;
        if size == 8 && g_type_f64
            return g_type_f64;
    }
    else if kind == .String
    {
        if g_type_string
            return g_type_string;
    }
    else if kind == .Bool
    {
        if g_type_bool
            return g_type_bool;
    }

    type := Alloc (YalType);
    type.kind = kind;
    type.size = size;
    SetTypeString (type);

    return type;
}

MakeTypeInteger :: (size : s64, is_signed : bool, node_for_debug : *AstNode = null) -> *YalTypeInteger #must
{
    if size ==
    {
    case 1;
        if is_signed
        {
            if g_type_s8
                return xx g_type_s8;
        }
        else
        {
            if g_type_u8
                return xx g_type_u8;
        }
    case 2;
        if is_signed
        {
            if g_type_s16
                return xx g_type_s16;
        }
        else
        {
            if g_type_u16
                return xx g_type_u16;
        }
    case 4;
        if is_signed
        {
            if g_type_s32
                return xx g_type_s32;
        }
        else
        {
            if g_type_u32
                return xx g_type_u32;
        }
    case 8;
        if is_signed
        {
            if g_type_s64
                return xx g_type_s64;
        }
        else
        {
            if g_type_u64
                return xx g_type_u64;
        }
    }

    type := Alloc (YalTypeInteger);
    type.size = size;
    type.is_signed = is_signed;
    SetTypeString (type);

    return type;
}

MakeTypePointer :: (pointed_type : *YalType, node_for_debug : *AstNode = null) -> *YalTypePointer #must
{
    type : YalTypePointer;
    type.size = 8;
    type.pointed_type = pointed_type;
    SetTypeString (*type);

    #if Use_Type_Cache
    {
        in_cache := HashSetGetPtr (*g_pointer_type_cache, *type);
        if in_cache
        {
            g_dedup_types_count += 1;
            return in_cache.*;
        }
    }

    result := Alloc (YalTypePointer, initialize = false);
    result.* = type;

    #if Use_Type_Cache
        HashSetInsert (*g_pointer_type_cache, result);

    return result;
}

MakeTypeArray :: (array_kind : ArrayKind, element_type : *YalType, count : s64, node_for_debug : *AstNode = null) -> *YalTypeArray #must
{
    type : YalTypeArray;
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
    SetTypeString (*type);

    #if Use_Type_Cache
    {
        in_cache := HashSetGetPtr (*g_array_type_cache, *type);
        if in_cache
        {
            g_dedup_types_count += 1;
            return in_cache.*;
        }
    }

    result := Alloc (YalTypeArray, initialize = false);
    result.* = type;

    #if Use_Type_Cache
        HashSetInsert (*g_array_type_cache, result);

    return result;
}

MakeTypeProcedure :: (node : *AstProcedure, parameters : []*YalType, results : []*YalType) -> *YalTypeProcedure #must
{
    type : YalTypeProcedure;
    type.size = 8;
    type.node = node;
    type.parameters = parameters;
    type.results = results;
    SetTypeString (*type);

    #if Use_Type_Cache
    {
        in_cache := HashSetGetPtr (*g_proc_type_cache, *type);
        if in_cache
        {
            g_dedup_types_count += 1;
            return in_cache.*;
        }
    }

    result := Alloc (YalTypeProcedure, initialize = false);
    result.* = type;

    #if Use_Type_Cache
        HashSetInsert (*g_proc_type_cache, result);

    return result;
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

UntypedIntegerValueCanImplicitlyCastTo :: (value : ConstantValue, to : *YalType) -> bool #must
{
    Assert (value.kind == .Integer);

    if to.kind == .Integer
    {
        to_integer := cast (*YalTypeInteger) to;

        if to_integer.is_signed
        {
            min, max : s64;
            if to_integer.size ==
            {
            case 1;
                min = Math.S8_MIN;
                max = Math.S8_MAX;
            case 2;
                min = Math.S16_MIN;
                max = Math.S16_MAX;
            case 4;
                min = Math.S32_MIN;
                max = Math.S32_MAX;
            case 8;
                min = Math.S64_MIN;
                max = Math.S64_MAX;
            }

            if value.int_value < min || value.int_value > max
                return false;

            return true;
        }
        else
        {
            max : u64;
            if to_integer.size ==
            {
            case 1;
                max = Math.U8_MAX;
            case 2;
                max = Math.U16_MAX;
            case 4;
                max = Math.U32_MAX;
            case 8;
                max = Math.U64_MAX;
            }

            // @Todo: handle signedness
            if value.int_value < 0 || cast (u64) value.int_value > max
                return false;

            return true;
        }
    }
    else if to.kind == .Float
    {
        return true;
    }

    return false;
}

TypeIntegerCanImplicitlyCastTo :: (type : *YalTypeInteger, to : *YalType) -> bool #must
{
    if to.kind == .Integer
    {
        to_integer := cast (*YalTypeInteger) to;

        if type.is_signed == to_integer.is_signed
            return type.size <= to_integer.size;
        else if !type.is_signed && to_integer.is_signed
            return type.size < to_integer.size;
        else
            return false;
    }

    return false;
}

TypeCanImplicitlyCastTo :: (type : *YalType, to : *YalType) -> bool #must
{
    if type.kind == .Integer
        return inline TypeIntegerCanImplicitlyCastTo (cast (*YalTypeInteger) type, to);

    if type.kind == .Pointer && to.kind == .Pointer
    {
        type_pointer := cast (*YalTypePointer) type;
        to_pointer := cast (*YalTypePointer) to;

        // Implicit cast is possible from *void to *T and from *T to *void
        if type_pointer.pointed_type.kind == .Void || to_pointer.pointed_type.kind == .Void
            return true;
    }

    return TypesAreEqual (type, to);
}

TypeCanExplicitlyCastTo :: (type : *YalType, to : *YalType) -> bool #must
{
    // All pointer types can explicitly cast to one another
    if type.kind == .Pointer && to.kind == .Pointer
        return true;

    // All pointer types can explicitly cast to integers and vice versa
    // @Robustness: maybe this isn't a good idea, and we should only allow
    // pointer cast to 64-bit integers?
    if type.kind == .Pointer && to.kind == .Integer
        return true;

    if to.kind == .Pointer && type.kind == .Integer
        return true;

    // All integer types can explicitly cast to one another
    if type.kind == .Integer && to.kind == .Integer
        return true;

    // All float types can explicitly cast to integers and vice versa
    if type.kind == .Float && to.kind == .Integer
        return true;

    if to.kind == .Float && type.kind == .Integer
        return true;

    // All integer types can explicitly cast to bool and vice versa
    if type.kind == .Integer && to.kind == .Bool
        return true;

    if to.kind == .Integer && type.kind == .Bool
        return true;

    return inline TypeCanImplicitlyCastTo (type, to);
}
