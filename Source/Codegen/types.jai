IRType :: struct
{
    Kind :: enum u8
    {
        Invalid;
        Void;
        U8;
        S8;
        U16;
        S16;
        U32;
        S32;
        U64;
        S64;
        F32;
        F64;
        Bool;
        Label;
        Procedure;
        Pointer;
        Array;
        Struct;
    }

    #as kind : Kind;
    union
    {
        pointer : struct
        {
            type : *IRType;
        };
        array : struct
        {
            type : *IRType;
            count : s64;
        };
        procedure : struct
        {
            return_type : *IRType;
            param_types : []*IRType;
        };
        aggregate : struct
        {
            member_types : []*IRType;
        };
    };
}

HashIRType :: (type : *IRType) -> u64 #must
{
    return fnv1a_hash (type, size_of (IRType));
}

MemcmpIRTypes :: (a : *IRType, b : *IRType) -> int #must
{
    return memcmp (a, b, size_of (IRType));
}

HashIRTypeProcedure :: (type : *IRType) -> u64 #must
{
    Assert (type.kind == .Procedure);

    result := fnv1a_hash (cast (u64) type.procedure.return_type);

    for type.procedure.param_types
        result = fnv1a_hash (cast (u64) it, result);

    return result;
}

ShallowCompareIRTypeProcedure :: (a : *IRType, b : *IRType) -> bool #must
{
    Assert (a.kind == .Procedure);
    Assert (b.kind == .Procedure);

    if a.procedure.param_types.count != b.procedure.param_types.count
        return false;

    if a.procedure.return_type != b.procedure.return_type
        return false;

    for i : 0..a.procedure.param_types.count - 1
    #no_abc
    {
        if a.procedure.param_types[i] != b.procedure.param_types[i]
            return false;
    }

    return true;
}

IRTypeCache :: HashSet (
    *IRType,
    hash_func = (val) => HashIRType (val),
    comp_func = (a, b) => MemcmpIRTypes (a, b) == 0
);

g_ir_pointer_type_cache : IRTypeCache;
g_ir_array_type_cache : IRTypeCache;

g_ir_proc_type_cache :  HashSet (
    *IRType,
    hash_func = (val) => HashIRTypeProcedure (val),
    comp_func = (a, b) => ShallowCompareIRTypeProcedure (a, b)
);

IsPrimitiveType :: inline (kind : IRType.Kind) -> bool #must
{
    if kind ==
    {
    case .Void; #through;
    case .U8; #through;
    case .S8; #through;
    case .U16; #through;
    case .S16; #through;
    case .U32; #through;
    case .S32; #through;
    case .U64; #through;
    case .S64; #through;
    case .F32; #through;
    case .F64; #through;
    case .Bool;
        return true;
    }

    return false;
}

IsIntegerType :: inline (kind : IRType.Kind) -> bool #must
{
    if kind ==
    {
    case .U8; #through;
    case .S8; #through;
    case .U16; #through;
    case .S16; #through;
    case .U32; #through;
    case .S32; #through;
    case .U64; #through;
    case .S64;
        return true;
    }

    return false;
}

IsNumericType :: inline (kind : IRType.Kind) -> bool #must
{
    if kind ==
    {
    case .U8; #through;
    case .S8; #through;
    case .U16; #through;
    case .S16; #through;
    case .U32; #through;
    case .S32; #through;
    case .U64; #through;
    case .S64; #through;
    case .F32; #through;
    case .F64;
        return true;
    }

    return false;
}

IsIntegralType :: inline (kind : IRType.Kind) -> bool #must
{
    if kind ==
    {
    case .U8; #through;
    case .S8; #through;
    case .U16; #through;
    case .S16; #through;
    case .U32; #through;
    case .S32; #through;
    case .U64; #through;
    case .S64; #through;
    case .Bool;
        return true;
    }

    return false;
}

IsFirstClassType :: inline (kind : IRType.Kind) -> bool #must
{
    if kind ==
    {
    case .U8; #through;
    case .S8; #through;
    case .U16; #through;
    case .S16; #through;
    case .U32; #through;
    case .S32; #through;
    case .U64; #through;
    case .S64; #through;
    case .F32; #through;
    case .F64; #through;
    case .Pointer; #through;
    case .Bool;
        return true;
    }

    return false;
}

IRTypesAreEqual :: (a : *IRType, b : *IRType) -> bool #must
{
    if a == b
        return true;

    if a.kind != b.kind
        return false;

    if IsPrimitiveType (a.kind)
        return true;

    if a.kind == .Pointer
        return IRTypesAreEqual (a.pointer.type, b.pointer.type);

    if a.kind == .Array
        return a.array.count == b.array.count && IRTypesAreEqual (a.array.type, b.array.type);

    if a.kind == .Procedure
    {
        if a.procedure.param_types.count != b.procedure.param_types.count
            return false;

        if !IRTypesAreEqual (a.procedure.return_type, b.procedure.return_type)
            return false;

        for a.procedure.param_types
        {
            if !IRTypesAreEqual (it, b.procedure.param_types[it_index])
                return false;
        }
    }

    if a.kind == .Struct
    {
        if a.aggregate.member_types.count != b.aggregate.member_types.count
            return false;

        for a.aggregate.member_types
        {
            if !IRTypesAreEqual (it, b.aggregate.member_types[it_index])
                return false;
        }
    }

    return false;
}

g_ir_type_invalid : *IRType;
g_ir_type_label : *IRType;
g_ir_type_void : *IRType;
g_ir_type_u8 : *IRType;
g_ir_type_s8 : *IRType;
g_ir_type_u16 : *IRType;
g_ir_type_s16 : *IRType;
g_ir_type_u32 : *IRType;
g_ir_type_s32 : *IRType;
g_ir_type_u64 : *IRType;
g_ir_type_s64 : *IRType;
g_ir_type_f32 : *IRType;
g_ir_type_f64 : *IRType;
g_ir_type_bool : *IRType;

InitIRTypes :: ()
{
    Make :: inline (kind : IRType.Kind) -> *IRType #must
    {
        result := Alloc (IRType);
        result.kind = kind;

        return result;
    }

    g_ir_type_invalid = Make (.Invalid);
    g_ir_type_label = Make (.Label);
    g_ir_type_void = Make (.Void);
    g_ir_type_u8 = Make (.U8);
    g_ir_type_s8 = Make (.S8);
    g_ir_type_u16 = Make (.U16);
    g_ir_type_s16 = Make (.S16);
    g_ir_type_u32 = Make (.U32);
    g_ir_type_s32 = Make (.S32);
    g_ir_type_u64 = Make (.U64);
    g_ir_type_s64 = Make (.S64);
    g_ir_type_f32 = Make (.F32);
    g_ir_type_f64 = Make (.F64);
    g_ir_type_bool = Make (.Bool);
}

MakeIRProcedureType :: inline (param_types : []*IRType, return_type : *IRType) -> *IRType #must
{
    type : IRType;
    type.kind = .Procedure;
    type.procedure.return_type = return_type;
    type.procedure.param_types = param_types;

    in_cache := HashSetGetPtr (*g_ir_proc_type_cache, *type);
    if in_cache
        return in_cache.*;

    result := Alloc (IRType);
    result.* = type;

    HashSetInsert (*g_ir_pointer_type_cache, result);

    return result;
}

MakeIRPointerType :: inline (pointed_type : *IRType) -> *IRType #must
{
    type : IRType;
    type.kind = .Pointer;
    type.pointer.type = pointed_type;

    in_cache := HashSetGetPtr (*g_ir_pointer_type_cache, *type);
    if in_cache
        return in_cache.*;

    result := Alloc (IRType);
    result.* = type;

    HashSetInsert (*g_ir_pointer_type_cache, result);

    return result;
}

MakeIRArrayType :: inline (element_type : *IRType, count : s64) -> *IRType #must
{
    type : IRType;
    type.kind = .Array;
    type.array.type = element_type;
    type.array.count = count;

    in_cache := HashSetGetPtr (*g_ir_array_type_cache, *type);
    if in_cache
        return in_cache.*;

    result := Alloc (IRType);
    result.* = type;

    HashSetInsert (*g_ir_array_type_cache, result);

    return result;
}
