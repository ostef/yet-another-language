#import "Basic";
#import "String";
#import "File";
#import "Compiler";
#import "Hash_Table";

#import,dir "jai-xml";

OpenGLEnumValue :: struct {
    name : string;
    value : string;
    outputted : bool;
}

OpenGLFunction :: struct {
    Param :: struct {
        name : string;
        type : string;
    }

    name : string;
    return_type : string;
    parameters : [..]Param;
    outputted : bool;
    is_function_pointer : bool;
}

g_functions : Table(string, OpenGLFunction);
g_enum_values : Table(string, OpenGLEnumValue);

#run {
    set_build_options_dc(.{do_output=false, write_added_strings=false});
}

node_children :: (node : *XMLNode, body : Code, flags : For_Flags) #expand {
    `it_index := 0;
    `it := node.first_child;
    while it {
        defer {
            it_index += 1;
            it = it.next_sibling;
        }

        #insert body;
    }
}

node_find_child_by_tag_recursive :: (node : *XMLNode, tag : string) -> *XMLNode {
    result := node_find_child_by_tag(node, tag);
    if result {
        return result;
    }

    for :node_children node {
        result = node_find_child_by_tag_recursive(it, tag);
        if result {
            return result;
        }
    }

    return null;
}

GetYalTypeFromGLType :: (gl_type : string) -> string {
    s := trim(gl_type);
    if !s {
        return "void";
    }

    if starts_with(s, "const") {
        s = advance(s, "const".count);
        s = trim(s);
    }

    if ends_with(s, "const") {
        s.count -= "const".count;
        s = trim(s);
    }

    if ends_with(s, "*") {
        pointer_to := s;
        pointer_to.count -= 1;
        pointer_to = trim(pointer_to);

        return sprint("*%", GetYalTypeFromGLType(pointer_to));
    }

    if s == {
    case "void"; return "void";
    case "char"; return "s8";
    case "unsigned char"; return "u8";
    case "short"; return "s16";
    case "unsigned short"; return "u16";
    case "int"; return "s32";
    case "unsigned int"; return "u32";
    case "float"; return "f32";
    case "double"; return "f64";
    case "khronos_int8_t"; return "s8";
    case "khronos_uint8_t"; return "u8";
    case "khronos_int16_t"; return "s16";
    case "khronos_uint16_t"; return "u16";
    case "khronos_int32_t"; return "s32";
    case "khronos_uint32_t"; return "u32";
    case "khronos_int64_t"; return "s64";
    case "khronos_uint64_t"; return "u64";
    case "khronos_ssize_t"; return "s64";
    case "khronos_size_t"; return "u64";
    case "khronos_intptr_t"; return "s64";
    case "khronos_float_t"; return "f32";
    }

    if starts_with(s, "struct ") {
        return advance(s, "struct ".count);
    }

    return s;
}

GetYalIdentifier :: (str : string) -> string {
    if str == "string" {
        return "string_";
    }
    if str == "func" {
        return "func_";
    }

    return str;
}

RemoveGLPrefix :: (str : string) -> string {
    s := str;
    if starts_with(str, "GL_") {
        s = advance(str, 3);
    } else if starts_with(str, "gl") {
        s = advance(str, 2);
    }

    if is_digit(s[0]) {
        s = sprint("_%", s);
    }

    return s;
}

Prelude :: #string Yal
const __GLsync = struct {}
const _cl_context = struct {}
const _cl_event = struct {}

#if Target_OS == .MacOS {
    const GLhandleARB = *void;
} else {
    const GLhandleARB = u32;
}

const GLDEBUGPROC = type_of(func @call("c") (source: GLenum, type: GLenum, id: GLuint, severity: GLenum, length: GLsizei, message: *u8, userParam: *void));
const GLDEBUGPROCARB = GLDEBUGPROC;
const GLDEBUGPROCKHR = GLDEBUGPROC;
const GLDEBUGPROCAMD = GLDEBUGPROC;
const GLVULKANPROCNV = type_of(func @call("c") ());

#if Target_OS == .Windows {
    const Lib_GL = "OpenGL32.dll";

    @external @library(Lib_GL)
    const wglGetProcAddress = func(name: *u8) -> *void;
} else #if Target_OS == .Linux {
    const Lib_GL = "libGL.so";

    @external @library(Lib_GL)
    const glXGetProcAddress = func(name: *u8) -> *void;
} else #if Target_OS == .MacOS {
    const Lib_GL = "OpenGL.dylib";
} else {
    #assert false, "Unsupported target OS";
}

Yal

ParseAndAppendTypes :: (builder : *String_Builder, root : *XMLNode) {
    types_node := node_find_child_by_tag_recursive(root, "types");
    assert(types_node != null, "Could not find types node");

    for :node_children type_node : types_node {
        if type_node.name != "type" {
            continue;
        }

        name_node := node_find_child_by_tag(type_node, "name");
        if !name_node || !name_node.first_child {
            continue;
        }

        name := name_node.first_child.value;

        is_struct := starts_with(name, "struct ");
        if is_struct {
            continue;
        }

        type := ifx type_node.first_child && type_node.first_child.type == .pcdata
            then type_node.first_child.value else "void";

        // @Todo: function pointer type
        if ends_with(type, "(") {
            continue;
        }

        if starts_with(type, "typedef ") {
            type = advance(type, "typedef ".count);
        }

        type = trim_right(type);

        type = GetYalTypeFromGLType(type);

        print_to_builder(builder, "const % = %;\n", GetYalIdentifier(name), type);
    }
}

ParseEnums :: (root : *XMLNode) {
    for :node_children root {
        if it.name != "enums" {
            continue;
        }

        for :node_children member : it {
            name := attribute_get_value(member, "name");
            if !name {
                continue;
            }

            value := attribute_get_value(member, "value");
            if !value {
                continue;
            }

            api := attribute_get_value(member, "api", default="gl");
            if api != "gl" {
                continue;
            }

            enum_value : OpenGLEnumValue;
            enum_value.name = name;
            enum_value.value = value;
            table_set(*g_enum_values, name, enum_value);
        }
    }
}

ParseType :: (node : *XMLNode) -> string {
    str : string;
    for :node_children node {
        if it.type == .pcdata {
            str = sprint("%1%2", str, it.value);
        } else if it.name == "ptype" {
            str = sprint("%1%2", str, it.first_child.value);
        } else if it.name == "name" {
            continue;
        }
    }

    return GetYalTypeFromGLType(str);
}

ParseFunctions :: (root : *XMLNode) {
    commands_node := node_find_child_by_tag(root, "commands");
    assert(commands_node != null, "Could not find commands node");

    for :node_children command_node : commands_node {
        if command_node.name != "command" {
            continue;
        }

        proto_node := node_find_child_by_tag(command_node, "proto");
        if !proto_node {
            continue;
        }

        result_type := ParseType(proto_node);

        name_node := node_find_child_by_tag(proto_node, "name");
        name := name_node.first_child.value;

        function : OpenGLFunction;
        function.name = name;
        function.return_type = result_type;

        for :node_children param_node : command_node {
            if param_node.name != "param" {
                continue;
            }

            param_type := ParseType(param_node);

            name_node := node_find_child_by_tag(param_node, "name");
            name := name_node.first_child.value;

            array_add(*function.parameters, .{name=GetYalIdentifier(name), type=param_type});
        }

        table_set(*g_functions, name, function);
    }
}

AppendEnumValue :: (builder : *String_Builder, name : string) {
    value := table_find_pointer(*g_enum_values, name);
    if !value || value.outputted {
        return;
    }

    value.outputted = true;

    print_to_builder(builder, "const % = %;\n", RemoveGLPrefix(value.name), value.value);
}

AppendFunction :: (builder : *String_Builder, name : string) {
    function := table_find_pointer(*g_functions, name);
    if !function || function.outputted {
        return;
    }

    function.outputted = true;

    print_to_builder(builder, "@symbol(\"%\")\n", function.name);
    print_to_builder(builder, "const % = func(", RemoveGLPrefix(function.name));

    for function.parameters {
        if it_index > 0 {
            append(builder, ", ");
        }

        print_to_builder(builder, "%: %", it.name, it.type);
    }

    append(builder, ")");
    if function.return_type && function.return_type != "void" {
        print_to_builder(builder, " -> %", function.return_type);
    }
    append(builder, ";\n");
}

AppendFunctionPointer :: (builder : *String_Builder, name : string) {
    function := table_find_pointer(*g_functions, name);
    if !function || function.outputted {
        return;
    }

    function.outputted = true;
    function.is_function_pointer = true;

    print_to_builder(builder, "var %: type_of(func @call(\"c\") (", RemoveGLPrefix(function.name));

    for function.parameters {
        if it_index > 0 {
            append(builder, ", ");
        }

        print_to_builder(builder, "%: %", it.name, it.type);
    }

    append(builder, ")");
    if function.return_type && function.return_type != "void" {
        print_to_builder(builder, " -> %", function.return_type);
    }
    append(builder, ");\n");
}

ParseAndAppendFeature :: (builder : *String_Builder, feature_node : *XMLNode) {
    api := attribute_get_value(feature_node, "api");
    if api != "gl" {
        return;
    }

    name := attribute_get_value(feature_node, "name");
    if name {
        print_to_builder(builder, "// %\n", name);
    }

    function_are_pointers := name != "GL_VERSION_1_0" && name != "GL_VERSION_1_1";

    for :node_children require : feature_node {
        if require.name != "require" {
            continue;
        }

        for :node_children node : require {
            if node.name == "enum" {
                enum_name := attribute_get_value(node, "name");
                AppendEnumValue(builder, enum_name);
            }
        }
    }

    append(builder, "\n");

    if !function_are_pointers {
        append(builder, "@external @library(Lib_GL) {\n\n");
    }

    for :node_children require : feature_node {
        if require.name != "require" {
            continue;
        }

        for :node_children node : require {
            if node.name == "command" {
                function_name := attribute_get_value(node, "name");
                if function_are_pointers {
                    AppendFunctionPointer(builder, function_name);
                } else {
                    AppendFunction(builder, function_name);
                }
            }
        }
    }

    if !function_are_pointers {
        append(builder, "\n}\n");
    }
    append(builder, "\n");
}

ParseAndAppendEnumAndFunctions :: (builder : *String_Builder, root : *XMLNode) {
    for :node_children root {
        if it.name == "feature" {
            ParseAndAppendFeature(builder, it);
        }
    }
}

AppendLoaderFunction :: (builder : *String_Builder) {

LoadGL_Prelude :: #string Yal
const Load = func() {
    #if Target_OS == .Windows {
        const GetGLProcAddress = wglGetProcAddress;
    } else #if Target_OS == .Linux {
        const GetGLProcAddress = glXGetProcAddress;
    } else {
        #assert false;
    }

Yal

    append(builder, LoadGL_Prelude);

    for g_functions {
        if !it.is_function_pointer || !it.outputted {
            continue;
        }

        print_to_builder(builder, "    %1 = cast(type_of(%1), GetGLProcAddress(\"%2\".data));\n", RemoveGLPrefix(it.name), it.name);
    }
    append(builder, "}\n");
}

#run {
    root, result := xml_parse_file("gl.xml");
    if result.status != .ok {
        return;
    }

    defer xml_free(root);

    registry := node_find_child_by_tag(root, "registry");

    ParseEnums(registry);
    ParseFunctions(registry);

    builder : String_Builder;

    append(*builder, "// Generated from gl.xml (https://github.com/KhronosGroup/OpenGL-Registry)\n\n");
    append(*builder, Prelude);
    ParseAndAppendTypes(*builder, registry);
    append(*builder, "\n");

    ParseAndAppendEnumAndFunctions(*builder, registry);

    AppendLoaderFunction(*builder);

    str := builder_to_string(*builder);
    // print(str);
    write_entire_file("module.yal", str);
}
