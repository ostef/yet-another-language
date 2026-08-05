#import "Hash";

// This only count types cached in a hash set (array and pointer types for now)
g_dedup_types_count : s64;

// Some types will not get deduplicated even though they are equal, because
// they might point at types that have not been deduplicated and thus the
// hash and memcmp will be different

HashType :: inline (type : *YalType, size : s64) -> u64 {
    return fnv1a_hash(type, size);
}

MemcmpTypes :: inline (a : *YalType, b : *YalType, size : s64) -> int {
    return memcmp(a, b, size);
}

HashTypeFunction :: (type : *YalTypeFunction) -> u64 {
    result := fnv1a_hash(cast(u8, type.calling_convention));

    for type.parameters {
        result = fnv1a_hash(cast(u64, it), result);
    }
    result = fnv1a_hash(cast(u64, type.result), result);

    return result;
}

ShallowCompareTypeFunction :: (a : *YalTypeFunction, b : *YalTypeFunction) -> bool {
    if a.calling_convention != b.calling_convention {
        return false;
    }

    if a.parameters.count != b.parameters.count {
        return false;
    }

    if a.result != b.result {
        return false;
    }

    for i : 0..a.parameters.count - 1 #no_abc {
        if a.parameters[i] != b.parameters[i] {
            return false;
        }
    }

    return true;
}

HashTypeFunctionOverloadSet :: (type : *YalTypeFunctionOverloadSet) -> u64 {
    result := fnv1a_hash(cast(u64, type.node));

    for type.overload_types {
        result = fnv1a_hash(cast(u64, it), result);
    }

    return result;
}

ShallowCompareTypeFunctionOverloadSet :: (a : *YalTypeFunctionOverloadSet, b : *YalTypeFunctionOverloadSet) -> bool {
    if a.node != b.node {
        return false;
    }

    if a.overload_types.count != b.overload_types.count {
        return false;
    }

    for i : 0..a.overload_types.count - 1 #no_abc {
        if a.overload_types[i] != b.overload_types[i] {
            return false;
        }
    }

    return true;
}

g_pointer_type_cache : HashSet(
    *YalTypePointer,
    hash_func = (val) => HashType(val, size_of(YalTypePointer)),
    comp_func = (a, b) => MemcmpTypes(a, b, size_of(YalTypePointer)) == 0
);

g_array_type_cache : HashSet(
    *YalTypeArray,
    hash_func = (val) => HashType(val, size_of(YalTypeArray)),
    comp_func = (a, b) => MemcmpTypes(a, b, size_of(YalTypeArray)) == 0
);

g_func_type_cache : HashSet(
    *YalTypeFunction,
    hash_func = HashTypeFunction,
    comp_func = ShallowCompareTypeFunction
);

g_func_overload_set_type_cache : HashSet(
    *YalTypeFunctionOverloadSet,
    hash_func = HashTypeFunctionOverloadSet,
    comp_func = ShallowCompareTypeFunctionOverloadSet
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
g_type_type_id : *YalType;
g_type_module : *YalType;

YalType :: struct {
    Kind :: enum u8 {
        Invalid;
        Void;
        Integer;
        Float;
        Bool;
        String;
        TypeId;
        Pointer;
        Array;
        Function;
        Struct;
        Enum;
        FunctionOverloadSet;
        Module;
        TemplateParam;
    }

    kind : Kind;
    size := -1;
} @Preload

YalTypeInteger :: struct {
    #as using base : YalType;
    base.kind = .Integer;

    is_signed : bool;
} @Preload

YalTypePointer :: struct {
    #as using base : YalType;
    base.kind = .Pointer;
    base.size = 8;

    pointed_type : *YalType;
} @Preload

YalTypeArray :: struct {
    #as using base : YalType;
    base.kind = .Array;

    array_kind : ArrayKind;
    element_type : *YalType;
    count : s64;
} @Preload

YalTypeFunction :: struct {
    #as using base : YalType;
    base.kind = .Function;
    base.size = 8;

    parameters : []*YalType;
    result : *YalType;
    calling_convention : CallingConvention;
    is_c_variadic : bool;
} @Preload

YalTypeFunctionOverloadSet :: struct {
    #as using base : YalType;
    base.kind = .FunctionOverloadSet;
    base.size = 0;

    node : *AstFunctionOverloadSet; @PreloadOpaque
    overload_types : []*YalTypeFunction;
} @Preload

YalTypeStructMember :: struct {
    node : *AstDeclaration; @PreloadOpaque
    name : string;
    byte_offset := -1;
    type : *YalType;
} @Preload

YalTypeStruct :: struct {
    #as using base : YalType;
    base.kind = .Struct;

    alignment : s8 = -1;
    is_union : bool;
    ir_typedef : *IRTypedef; @PreloadOpaque
    ir_default_value : *IRGlobalData; @PreloadOpaque
    node : *AstStruct; @PreloadOpaque
    name : string;
    template_source : *YalTypeStruct;
    parameters : []*YalType;
    members : []YalTypeStructMember;
} @Preload

YalTypeEnumMember :: struct {
    name : string;
    value : s64;
} @Preload

YalTypeEnum :: struct {
    #as using base : YalType;
    base.kind = .Enum;

    node : *AstEnum; @PreloadOpaque
    base_type : *YalTypeInteger;
    name : string;
    members : []YalTypeEnumMember;
} @Preload

YalTypeTemplateParam :: struct {
    #as using base : YalType;
    base.kind = .TemplateParam;

    name : string;
    param_index := -1;
} @Preload

MakeType :: (kind : YalType.Kind, size : s64, node_for_debug : *AstNode = null) -> *YalType {
    if kind == {
    case .Invalid;
        if g_type_invalid {
            return g_type_invalid;
        }
    case .Void;
        if g_type_void {
            return g_type_void;
        }
    case .Float;
        if size == 4 && g_type_f32 {
            return g_type_f32;
        }
        if size == 8 && g_type_f64 {
            return g_type_f64;
        }
    case .String;
        if g_type_string {
            return g_type_string;
        }
    case .TypeId;
        if g_type_type_id {
            return g_type_type_id;
        }
    case .Bool;
        if g_type_bool {
            return g_type_bool;
        }
    }

    type := Alloc(YalType);
    type.kind = kind;
    type.size = size;

    return type;
}

MakeTypeInteger :: (size : s64, is_signed : bool, node_for_debug : *AstNode = null) -> *YalTypeInteger {
    if size == {
    case 1;
        if is_signed {
            if g_type_s8 {
                return xx g_type_s8;
            }
        } else {
            if g_type_u8 {
                return xx g_type_u8;
            }
        }
    case 2;
        if is_signed {
            if g_type_s16 {
                return xx g_type_s16;
            }
        } else {
            if g_type_u16 {
                return xx g_type_u16;
            }
        }
    case 4;
        if is_signed {
            if g_type_s32 {
                return xx g_type_s32;
            }
        } else {
            if g_type_u32 {
                return xx g_type_u32;
            }
        }
    case 8;
        if is_signed {
            if g_type_s64 {
                return xx g_type_s64;
            }
        } else {
            if g_type_u64 {
                return xx g_type_u64;
            }
        }
    }

    type := Alloc(YalTypeInteger);
    type.size = size;
    type.is_signed = is_signed;

    return type;
}

MakeTypePointer :: (pointed_type : *YalType, node_for_debug : *AstNode = null) -> *YalTypePointer {
    type : YalTypePointer;
    type.size = 8;
    type.pointed_type = pointed_type;

    in_cache := HashSetGetPtr(*g_pointer_type_cache, *type);
    if in_cache {
        g_dedup_types_count += 1;
        return in_cache.*;
    }

    result := Alloc(YalTypePointer, initialize = false);
    result.* = type;

    HashSetInsert(*g_pointer_type_cache, result);

    return result;
}

MakeTypeArray :: (array_kind : ArrayKind, element_type : *YalType, count : s64, node_for_debug : *AstNode = null) -> *YalTypeArray {
    type : YalTypeArray;
    type.array_kind = array_kind;

    if array_kind == .Static {
        if element_type.size == -1 {
            if node_for_debug {
                Panic(node_for_debug, "Array element type is unsized for static array, so we cannot calculate array size");
            } else {
                Panic("Array element type is unsized for static array, so we cannot calculate array size");
            }
        }

        type.size = element_type.size * count;
    } else if array_kind == .Dynamic {
        type.size = 8 + 8 + 8 + 16;  // capacity + count + data + allocator
    } else if array_kind == .Slice {
        type.size = 8 + 8;  // count + data
    }

    type.element_type = element_type;
    type.count = count;

    in_cache := HashSetGetPtr(*g_array_type_cache, *type);
    if in_cache {
        g_dedup_types_count += 1;
        return in_cache.*;
    }

    result := Alloc(YalTypeArray, initialize = false);
    result.* = type;

    HashSetInsert(*g_array_type_cache, result);

    return result;
}

MakeTypeFunction :: (parameters : []*YalType, result : *YalType, calling_convention : CallingConvention, is_c_variadic : bool) -> *YalTypeFunction {
    type : YalTypeFunction;
    type.size = 8;
    type.parameters = parameters;
    type.result = result;
    type.calling_convention = calling_convention;
    type.is_c_variadic = is_c_variadic;

    in_cache := HashSetGetPtr(*g_func_type_cache, *type);
    if in_cache {
        g_dedup_types_count += 1;
        return in_cache.*;
    }

    func_type := Alloc(YalTypeFunction, initialize = false);
    func_type.* = type;

    HashSetInsert(*g_func_type_cache, func_type);

    return func_type;
}

MakeTypeFunctionOverloadSet :: (node : *AstFunctionOverloadSet, overload_types : []*YalTypeFunction) -> *YalTypeFunctionOverloadSet {
    type : YalTypeFunctionOverloadSet;
    type.size = 0;
    type.node = node;
    type.overload_types = overload_types;

    in_cache := HashSetGetPtr(*g_func_overload_set_type_cache, *type);
    if in_cache {
        g_dedup_types_count += 1;
        return in_cache.*;
    }

    set_type := Alloc(YalTypeFunctionOverloadSet, initialize = false);
    set_type.* = type;

    HashSetInsert(*g_func_overload_set_type_cache, set_type);

    return set_type;
}

MakeTypeStruct :: (node : *AstStruct, name : string, is_union : bool) -> *YalTypeStruct {
    type := Alloc(YalTypeStruct);
    type.node = node;
    type.name = name;
    type.is_union = is_union;

    return type;
}

MakeTypeEnum :: (node : *AstEnum, name : string, base_type : *YalTypeInteger) -> *YalTypeEnum {
    type := Alloc(YalTypeEnum);
    type.node = node;
    type.name = name;
    if base_type {
        type.base_type = base_type;
        type.size = base_type.size;
    }

    return type;
}

MakeTypeTemplateParam :: (name : string, index : int) -> *YalTypeTemplateParam {
    type := Alloc(YalTypeTemplateParam);
    type.name = name;
    type.param_index = index;

    return type;
}

UnwrapTemplate :: (type : *YalType) -> *YalType {
    if !type {
        return null;
    }

    if type.kind == .TemplateParam {
        concrete_type := GetTemplateConcreteType(xx type);
        if concrete_type {
            return concrete_type;
        }
    }

    return type;
}

GetTemplateConcreteType :: (template : *YalTypeTemplateParam) -> *YalType {
    if template.param_index < 0 || template.param_index >= context.check.template_args.count {
        return null;
    }

    arg := context.check.template_args[template.param_index];
    if arg.kind != .TypeId {
        return null;
    }

    return arg.type_value;
}

TypeIsYalType :: (info : *Type_Info) -> bool {
    if info == type_info(YalType) {
        return true;
    }

    if info.type != .STRUCT {
        return false;
    }

    info_struct := cast(*Type_Info_Struct) info;

    for info_struct.members {
        if it.name == "base" && it.type == type_info(YalType)
        && it.flags & .USING && it.flags & .AS {
            return true;
        }
    }

    return false;
}

IsTemplatedType :: (type : *YalType) -> bool {
    if #complete type.kind == {
    case .Invalid; #through;
    case .Void; #through;
    case .Integer; #through;
    case .Float; #through;
    case .Bool; #through;
    case .String; #through;
    case .TypeId; #through;
    case .Enum; #through;
    case .FunctionOverloadSet; #through;
    case .Module;
        return false;

    case .Pointer;
        type_pointer := cast(*YalTypePointer, type);
        return IsTemplatedType(type_pointer.pointed_type);

    case .Array;
        type_array := cast(*YalTypeArray, type);
        return IsTemplatedType(type_array.element_type);

    case .Function;
        type_func := cast(*YalTypeFunction, type);

        if IsTemplatedType(type_func.result) {
            return true;
        }

        for type_func.parameters {
            if IsTemplatedType(it) {
                return true;
            }
        }

        return false;

    case .Struct;
        type_struct := cast(*YalTypeStruct, type);
        return type_struct.parameters.count > 0 && type_struct.template_source == null;

    case .TemplateParam;
        return true;
    }

    return false;
}

GetStructMember :: (type : *YalTypeStruct, name : string) -> *YalTypeStructMember {
    for * type.members {
        if it.name == name {
            return it;
        }
    }

    return null;
}

InitBuiltinTypes :: () {
    g_type_invalid = MakeType(.Invalid, -1);
    g_type_void = MakeType(.Void, 0);
    g_type_void_ptr = MakeTypePointer(g_type_void);
    g_type_s64 = MakeTypeInteger(8, true);
    g_type_u64 = MakeTypeInteger(8, false);
    g_type_s32 = MakeTypeInteger(4, true);
    g_type_u32 = MakeTypeInteger(4, false);
    g_type_s16 = MakeTypeInteger(2, true);
    g_type_u16 = MakeTypeInteger(2, false);
    g_type_s8 = MakeTypeInteger(1, true);
    g_type_u8 = MakeTypeInteger(1, false);
    g_type_u8_ptr = MakeTypePointer(g_type_u8);
    g_type_f64 = MakeType(.Float, 8);
    g_type_f32 = MakeType(.Float, 4);
    g_type_bool = MakeType(.Bool, 1);
    g_type_string = MakeType(.String, 16);
    g_type_type_id = MakeType(.TypeId, 8);
    g_type_module = MakeType(.Module, 0);
}

AppendType :: (builder : *StringBuilder, type : *YalType) {
    if !type {
        Append(builder, "<null>");
        return;
    }

    type = UnwrapTemplate(type);

    if #complete type.kind == {
    case .Invalid;
        Append(builder, "<invalid>");
    case .Void;
        Append(builder, "void");
    case .Integer;
        if cast(*YalTypeInteger, type).is_signed {
            Append(builder, "s%", type.size * 8);
        } else {
            Append(builder, "u%", type.size * 8);
        }
    case .Float;
        if type.size == 4 {
            Append(builder, "f32");
        } else {
            Append(builder, "f64");
        }
    case .Bool;
        Append(builder, "bool");
    case .String;
        Append(builder, "string");
    case .TypeId;
        Append(builder, "type_id");
    case .Module;
        Append(builder, "module");

    case .Pointer;
        Append(builder, "*");
        AppendType(builder, (cast(*YalTypePointer) type).pointed_type);

    case .Array;
        array_type := cast(*YalTypeArray) type;

        Append(builder, "[");
        if array_type.array_kind == {
        case .Dynamic;
            Append(builder, "..");
        case .Static;
            Append(builder, "%", array_type.count);
        }
        Append(builder, "]");
        AppendType(builder, array_type.element_type);

    case .Function;
        func_type := cast(*YalTypeFunction) type;

        Append(builder, "func(");

        for param : func_type.parameters {
            if it_index != 0 {
                Append(builder, ", ");
            }
            AppendType(builder, param);
        }

        Append(builder, ")");

        if func_type.result != g_type_void {
            Append(builder, " -> ");
            AppendType(builder, func_type.result);
        }

    case .FunctionOverloadSet;
        Append(builder, "<func overload set>");

    case .Struct;
        type_struct := cast(*YalTypeStruct) type;
        if !type_struct.name {
            Append(builder, "% <anonymous>", ifx type_struct.is_union then "union" else "struct");
        } else {
            Append(builder, "% %", ifx type_struct.is_union then "union" else "struct", type_struct.name);
        }

    case .Enum;
        type_enum := cast(*YalTypeEnum) type;
        if !type_enum.name {
            Append(builder, "enum <anonymous>");
        } else {
            Append(builder, "enum %", type_enum.name);
        }

    case .TemplateParam;
        type_template_param := cast(*YalTypeTemplateParam, type);
        Append(builder, "$%", type_template_param.name);
    }
}

ToString :: inline (type : *YalType) -> string {
    builder : StringBuilder;
    builder.allocator = context.default_allocator;

    AppendType(*builder, type);

    return StringBuilderBuild(*builder);
}

TypesAreEqual :: (a : *YalType, b : *YalType) -> bool {
    if a == b {
        return true;
    }

    a = UnwrapTemplate(a);
    b = UnwrapTemplate(b);

    if a.kind != b.kind {
        return false;
    }

    if a.size != b.size {
        return false;
    }

    if #complete a.kind == {
    case .Pointer;
        a_pointer := cast(*YalTypePointer) a;
        b_pointer := cast(*YalTypePointer) b;

        return TypesAreEqual(a_pointer.pointed_type, b_pointer.pointed_type);

    case .Array;
        a_array := cast(*YalTypeArray) a;
        b_array := cast(*YalTypeArray) b;

        if a_array.array_kind != b_array.array_kind {
            return false;
        }

        if a_array.array_kind == .Static && a_array.count != b_array.count {
            return false;
        }

        return TypesAreEqual(a_array.element_type, b_array.element_type);

    case .Integer;
        a_integer := cast(*YalTypeInteger) a;
        b_integer := cast(*YalTypeInteger) b;

        return a_integer.is_signed == b_integer.is_signed;

    case .Function;
        a_func := cast(*YalTypeFunction) a;
        b_func := cast(*YalTypeFunction) b;

        if a_func.parameters.count != b_func.parameters.count {
            return false;
        }

        if !TypesAreEqual(a_func.result, b_func.result) {
            return false;
        }

        for i : 0..a_func.parameters.count - 1 {
            if !TypesAreEqual(a_func.parameters[i], b_func.parameters[i]) {
                return false;
            }
        }

        return true;

    case .FunctionOverloadSet;
        a_set := cast(*YalTypeFunctionOverloadSet) a;
        b_set := cast(*YalTypeFunctionOverloadSet) b;

        if a_set.overload_types.count != b_set.overload_types.count {
            return false;
        }

        for i : 0..a_set.overload_types.count - 1 {
            if !TypesAreEqual(a_set.overload_types[i], b_set.overload_types[i]) {
                return false;
            }
        }

        return true;

    case .Invalid; #through;
    case .Void; #through;
    case .String; #through;
    case .Bool; #through;
    case .TypeId; #through;
    case .Module; #through;
    case .Float;
        return true;

    case .Struct;
        return a == b;

    case .Enum;
        return a == b;

    case .TemplateParam;
        return a == b;
    }
}

UntypedIntegerValueCanImplicitlyCastTo :: (value : ConstantValue, to : *YalType) -> bool {
    Assert(value.kind == .Integer);

    to = UnwrapTemplate(to);

    if to.kind == .Integer {
        to_integer := cast(*YalTypeInteger, to);

        if to_integer.is_signed {
            min, max : s64;
            if to_integer.size == {
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

            if value.int_value < ToS128(min) || value.int_value > ToS128(max) {
                return false;
            }

            return true;
        } else {
            max : u64;
            if to_integer.size == {
            case 1;
                max = Math.U8_MAX;
            case 2;
                max = Math.U16_MAX;
            case 4;
                max = Math.U32_MAX;
            case 8;
                max = Math.U64_MAX;
            }

            if value.int_value < ToS128(0) || value.int_value > ToS128(max) {
                return false;
            }

            return true;
        }
    } else if to.kind == .Float { // @Todo: range checks
        return true;
    }

    return false;
}

TypeIntegerCanImplicitlyCastTo :: (type : *YalTypeInteger, to : *YalType) -> bool {
    to = UnwrapTemplate(to);

    if to.kind == .Integer {
        to_integer := cast(*YalTypeInteger, to);

        if type.is_signed == to_integer.is_signed {
            return type.size <= to_integer.size;
        } else if !type.is_signed && to_integer.is_signed {
            return type.size < to_integer.size;
        } else {
            return false;
        }
    }

    return false;
}

TypeCanImplicitlyCastTo :: (type : *YalType, to : *YalType) -> bool {
    type = UnwrapTemplate(type);
    to = UnwrapTemplate(to);

    if type.kind == .Integer {
        return inline TypeIntegerCanImplicitlyCastTo(cast(*YalTypeInteger, type), to);
    }

    if type.kind == .Pointer && to.kind == .Pointer {
        type_pointer := cast(*YalTypePointer, type);
        to_pointer := cast(*YalTypePointer, to);

        // Implicit cast is possible from *void to *T and from *T to *void (but not from *A to *B!)
        if type_pointer.pointed_type.kind == .Void || to_pointer.pointed_type.kind == .Void {
            return true;
        }
    }

    if type.kind == .Function && to.kind == .Pointer {
        to_pointer := cast(*YalTypePointer, to);
        if to_pointer.pointed_type.kind == .Void {
            return true;
        }
    }

    if type.kind == .Pointer && to.kind == .Function {
        type_pointer := cast(*YalTypePointer, type);
        if type_pointer.pointed_type.kind == .Void {
            return true;
        }
    }

    return TypesAreEqual(type, to);
}

TypeCanExplicitlyCastTo :: (type : *YalType, to : *YalType) -> bool {
    type = UnwrapTemplate(type);
    to = UnwrapTemplate(to);

    // All pointer types can explicitly cast to one another
    if type.kind == .Pointer && to.kind == .Pointer {
        return true;
    }

    if type.kind == .Pointer && to.kind == .Function {
        return true;
    }

    if type.kind == .Function && to.kind == .Pointer {
        return true;
    }

    if type.kind == .Pointer && to.kind == .Integer && type.size == to.size {
        return true;
    }

    if to.kind == .Pointer && type.kind == .Integer && type.size == to.size {
        return true;
    }

    // All integer types can explicitly cast to one another
    if type.kind == .Integer && to.kind == .Integer {
        return true;
    }

    // All float types can explicitly cast to integers and vice versa
    if type.kind == .Float && to.kind == .Integer {
        return true;
    }

    if to.kind == .Float && type.kind == .Integer {
        return true;
    }

    // All integer types can explicitly cast to bool and vice versa
    if type.kind == .Integer && to.kind == .Bool {
        return true;
    }

    if to.kind == .Integer && type.kind == .Bool {
        return true;
    }

    if type.kind == .Enum && to.kind == .Integer {
        return true;
    }

    if type.kind == .Integer && to.kind == .Enum {
        return true;
    }

    return inline TypeCanImplicitlyCastTo(type, to);
}

GetTypeAlignment :: (type : *YalType) -> int {
    type = UnwrapTemplate(type);

    if #complete type.kind == {
    case .Invalid;
        return -1;
    case .Module;
        return 1;
    case .FunctionOverloadSet;
        return 1;
    case .Void;
        return 1;

    case .Integer; #through;
    case .Float; #through;
    case .Bool; #through;
    case .Pointer; #through;
    case .Function; #through;
    case .TypeId; #through;
    case .Enum;
        return type.size;

    case .String; #through;
    case .Array;
        return 8;

    case .Struct;
        return cast(*YalTypeStruct, type).alignment;
    case .TemplateParam;
        return -1;
    }

    return 1;
}
