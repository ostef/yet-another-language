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

TypesAreEqual :: (a : IRType, b : IRType) -> bool #must
{
    if a.kind != b.kind
        return false;

    if IsPrimitiveType (a)
        return true;

    if a.kind == .Pointer
        return TypesAreEqual (a.pointer.type, b.pointer.type);

    if a.kind == .Array
        return a.array.count == b.array.count && TypesAreEqual (a.array.type, b.array.type);

    if a.kind == .Procedure
    {
        if a.procedure.param_types.count != b.procedure.param_types.count
            return false;

        if !TypesAreEqual (a.procedure.return_type, b.procedure.return_type)
            return false;

        for a.procedure.param_types
        {
            if !TypesAreEqual (it, b.procedure.param_types[it_index])
                return false;
        }
    }

    if a.kind == .Struct
    {
        if a.aggregate.member_types.count != b.aggregate.member_types.count
            return false;

        for a.aggregate.member_types
        {
            if !TypesAreEqual (it, b.aggregate.member_types[it_index])
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
    result := Alloc (IRType);
    result.kind = .Procedure;
    result.procedure.return_type = return_type;
    result.procedure.param_types = param_types;

    return result;
}

MakeIRPointerType :: inline (type : *IRType) -> *IRType #must
{
    result := Alloc (IRType);
    result.kind = .Pointer;
    result.pointer.type = type;

    return result;
}
