YalIRBuilder :: struct {
    #as using base : IRBuilder;

    string_data_table : HashMap(string, *IRGlobalData);
    constant_struct_value_table : HashMap(ConstantStructValue, *IRGlobalData, hash_func=#bake_arguments HashConstantStructValue(h=FNV_64_OFFSET_BIAS), comp_func=CompareConstantStructValues);

    current_function_template_instantiation : *FunctionTemplateInstantiation;

    type_string : *IRTypedef;
    type_slice : *IRTypedef;
    type_dynamic_array : *IRTypedef;
    type_allocator : *IRTypedef;

    func_memset : *IRFunction;
    func_streq : *IRFunction;

    enclosing_loop : *AstNode;
    enclosing_loop_scope : *Scope;
    enclosing_loop_start_block : *IRBasicBlock;
    enclosing_loop_body_block : *IRBasicBlock;
    enclosing_loop_merge_block : *IRBasicBlock;

    DeferCallback :: struct {
        data : *void;
        callback : (builder: *YalIRBuilder, data: *void);
    }

    DeferScope :: struct {
        scope : *Scope;
        defers : [..]DeferCallback;
    }

    defer_scope_stack : [..]DeferScope;
}

IsIRRelatedType :: (type : *Type_Info) -> bool {
    if type.type == .STRUCT && StringStartsWith(cast(*Type_Info_Struct, type).name, "IR") {
        return true;
    }
    if type.type == .POINTER && IsIRRelatedType(cast(*Type_Info_Pointer, type).pointer_to) {
        return true;
    }
    if type == type_info(HashMapEntry(string, *IRSymbol)) {
        return true;
    }
    if type == type_info(HashMapEntry(string, *IRGlobalData)) {
        return true;
    }
    if type == type_info(HashMapEntry(ConstantStructValue, *IRGlobalData)) {
        return true;
    }
    if type == type_info(YalIRBuilder.DeferScope) || type == type_info(YalIRBuilder.DeferCallback) {
        return true;
    }

    return false;
}

HashConstantStructValue :: (v : ConstantStructValue, h := FNV_64_OFFSET_BIAS) -> u64 {
    h := fnv1a_hash(v.type, size_of(type_of(v.type)));

    for * v.values {
        if #complete it.kind == {
        case .String;
            h = fnv1a_hash(xx,no_check it.kind, h=h);
            h = fnv1a_hash(it.string_value.data, it.string_value.count, h);

        case .Struct;
            h = fnv1a_hash(xx,no_check it.kind, h=h);
            h = HashConstantStructValue(it.struct_value.*, h=h);

        case .Invalid; #through;
        case .Integer; #through;
        case .Boolean; #through;
        case .Float; #through;
        case .Pointer; #through;
        case .Function; #through;
        case .FunctionOverloadSet; #through;
        case .Module; #through;
        case .TypeId;
            h = fnv1a_hash(it, size_of(ConstantValue), h=h);

        case .TemplateParam;
            Panic("Template param in codegen");
        }
    }

    return h;
}

CompareConstantStructValues :: (a : ConstantStructValue, b : ConstantStructValue) -> bool {
    if a.type != b.type {
        return false;
    }

    if a.values.count != b.values.count {
        return false;
    }

    for i : 0..a.values.count - 1 {
        if a.values[i].kind != b.values[i].kind {
            return false;
        }

        if #complete a.values[i].kind == {
        case .String;
            if a.values[i].string_value != b.values[i].string_value {
                return false;
            }

        case .Struct;
            if !CompareConstantStructValues(a.values[i].struct_value.*, b.values[i].struct_value.*) {
                return false;
            }

        case .Invalid; #through;
        case .Integer; #through;
        case .Boolean; #through;
        case .Float; #through;
        case .Pointer; #through;
        case .Function; #through;
        case .FunctionOverloadSet; #through;
        case .Module; #through;
        case .TypeId;
            return memcmp(*a.values[i], *b.values[i], size_of(ConstantValue)) == 0;

        case .TemplateParam;
            Panic("Template param in codegen");
        }
    }

    return true;
}

InternString :: (builder : *YalIRBuilder, str : string) -> *IRGlobalData {
    if str.count == 0 {
        Warning("Interning empty string");
    }

    global_data := HashMapInsert(*builder.string_data_table, str);
    if global_data.* {
        return global_data.*;
    }

    global_data.* = CreateIRGlobalData(builder, "str");
    AddString(global_data.*, 1, str);
    AddConstValue(global_data.*, 1, .Int8, 0);

    return global_data.*;
}

AddConstantValue :: (builder : *YalIRBuilder, global_data : *IRGlobalData, alignment : int, type : *YalType, value : ConstantValue) {
    if #complete value.kind == {
    case .Invalid;
        AddZeroBytes(global_data, alignment, type.size);
    case .Integer;
        if type.kind == {
        case .Integer;
            int_type := cast(*YalTypeInteger, type);
            if int_type.is_signed {
                if int_type.size == {
                case 1; AddConstValue(global_data, alignment, .Int8,  xx,no_check ToS8(value.int_value));
                case 2; AddConstValue(global_data, alignment, .Int16, xx,no_check ToS16(value.int_value));
                case 4; AddConstValue(global_data, alignment, .Int32, xx,no_check ToS32(value.int_value));
                case 8; AddConstValue(global_data, alignment, .Int64, xx,no_check ToS64(value.int_value));
                }
            } else {
                if int_type.size == {
                case 1; AddConstValue(global_data, alignment, .Int8,  xx,no_check ToU8(value.int_value));
                case 2; AddConstValue(global_data, alignment, .Int16, xx,no_check ToU16(value.int_value));
                case 4; AddConstValue(global_data, alignment, .Int32, xx,no_check ToU32(value.int_value));
                case 8; AddConstValue(global_data, alignment, .Int64, xx,no_check ToU64(value.int_value));
                }
            }

        case .Float;
            if type.size == 4 {
                AddConstValue(global_data, alignment, .Float32, cast(*u32, *ToFloat32(value.int_value)).*);
            } else {
                AddConstValue(global_data, alignment, .Float64, cast(*u64, *ToFloat64(value.int_value)).*);
            }
        case;
            Panic("Unhandled case");
        }

    case .Boolean;
        Assert(type.kind == .Bool);

        AddConstValue(global_data, alignment, .Int8, xx value.bool_value);

    case .Float;
        Assert(type.kind == .Float);

        if type.size == 4 {
            AddConstValue(global_data, alignment, .Float32, cast(*u32, *cast(float32, value.float_value)).*);
        } else {
            AddConstValue(global_data, alignment, .Float64, cast(*u64, *value.float_value).*);
        }

    case .Struct;
        Assert(type == value.struct_value.type);

        if value.struct_value.type.is_union {
            Warning(value.struct_value.type.node, "Union constant values are not yet handled");
            AddZeroBytes(global_data, alignment, type.size);
            return;
        }

        for value.struct_value.values {
            member := value.struct_value.type.members[it_index];
            alignment := ifx it_index == 0 then value.struct_value.type.alignment else GetTypeAlignment(member.type);

            AddConstantValue(builder, global_data, alignment, member.type, it);
        }

    case .String;
        Assert(type.kind == .String);

        AddConstValue(global_data, alignment, .Int64, xx,no_check value.string_value.count);
        if value.string_value.count == 0 {
            AddConstValue(global_data, GetTypeAlignment(g_type_void_ptr), .Int64, 0);
        } else {
            str_symbol := InternString(builder, value.string_value);
            AddSymbolReference(global_data, GetTypeAlignment(g_type_void_ptr), str_symbol);
        }

    case .Function;
        Assert(type.kind == .Function);

        if value.function_node {
            AddSymbolReference(global_data, alignment, value.function_node.ir_function);
        } else {
            AddSymbolReference(global_data, alignment, null);
        }

    case .Pointer; #through;
    case .FunctionOverloadSet; #through;
    case .TypeId;
        Panic("Not yet handled");

    case .Module; #through;
    case .TemplateParam;
        Panic("Invalid value %", value.kind);
    }
}

InternConstantStructValue :: (builder : *YalIRBuilder, value : ConstantStructValue) -> *IRGlobalData {
    global_data := HashMapInsert(*builder.constant_struct_value_table, value);
    if global_data.* {
        return global_data.*;
    }

    global_data.* = CreateIRGlobalData(builder, "const_struct_value");
    global_data.*.align = value.type.alignment;

    AddConstantValue(builder, global_data.*, value.type.alignment, value.type, .{kind=.Struct, struct_value=*value});

    final_aligned_size := AlignForward(global_data.*.total_unaligned_size, global_data.*.align);

    Assert(final_aligned_size == value.type.size, "When emitting constant struct value global data, we ended up with an aligned size of % bytes but expected %", final_aligned_size, value.type.size);

    return global_data.*;
}

FlattenDependencyGraphForCodegen :: (graph : *FlattenedDependencyGraph, dependency : Dependency) -> bool {
    ShouldPushNode :: (node : *AstNode) -> bool {
        if node.kind == {
        case .Run;
            return true;

        case .Function;
            func := cast(*AstFunction, node);
            return !IsFunctionTemplate(func) && IsCallable(func);

        case .Declaration;
            decl := cast(*AstDeclaration, node);

            if decl.decl_kind == .Variable {
                if decl.enclosing_scope.kind != .Global && decl.enclosing_scope.kind != .File {
                    return false;
                }
            } else if decl.decl_kind == .Constant {
                return ShouldPushNode(decl.expr);
            } else {
                return false;
            }

            return true;

        case .Struct;
            return !IsStructTemplate(xx node);
        }

        return false;
    }

    if ArrayFindLast(graph.node_stack, dependency, (a, b) => a.node == b.node) >= 0 {
        return dependency.node.check_status >= .Checked;
    }

    ast_node := dependency.node.ast_node;
    visited := GetVisitedNode(graph, dependency.node);
    if visited {
        pass := !ShouldPushNode(ast_node) || visited.index >= 0;
        if !pass {
            DbgInfo(.Codegen, ast_node, "Could not flatten graph");
        }

        return pass;
    }

    if dependency.node.check_status >= .Emitted {
        return true;
    }

    MarkNodeAsVisited(graph, dependency.node);

    ArrayPush(*graph.node_stack, dependency);
    defer ArrayPop(*graph.node_stack);

    blocked := dependency.node.check_status < .Checked;
    for dependency.node.dependencies {
        blocked |= !FlattenDependencyGraphForCodegen(graph, it);
    }

    if blocked {
        DbgInfo(.Codegen, ast_node, "Could not flatten graph");
        return false;
    }

    node := ast_node;
    if !ShouldPushNode(node) {
        return true;
    }

    if node.kind == .Function {
        func := cast(*AstFunction, node);
        if func.body && !FlattenDependencyGraphForCodegen(graph, .{node=func.body.dependency_node}) {
            DbgInfo(.Codegen, ast_node, "Could not flatten graph");
            return false;
        }
    }

    PushVisitedNode(graph, dependency.node);

    return true;
}

EmitIRForDependencyGraph :: (builder : *YalIRBuilder, dependency : *DependencyNode) -> bool {
    flattened_graph : FlattenedDependencyGraph;
    // Flattening uses up a lot of memory and is only used once, so we want to free it at the end
    SetAllocators(*flattened_graph, g_heap_allocator);
    defer FreeGraph(*flattened_graph);

    all_flattened := FlattenDependencyGraphForCodegen(*flattened_graph, .{node=dependency});

    DbgPrintln(.Codegen, "Nodes to emit (all_flattened=%):", all_flattened);
    DbgPrintDependencyNodes(.Codegen, flattened_graph.nodes);

    for flattened_graph.nodes {
        if it.ast_node.kind == {
        case .Struct;
            EmitStruct(builder, xx it.ast_node);
        case .Declaration;
            EmitDeclaration(builder, xx it.ast_node);
        case .Function;
            EmitFunction(builder, xx it.ast_node);
        case .Run;
            EmitRun(builder, xx it.ast_node);
        case;
            Panic(it.ast_node, "Unexpected node kind % in dependency chain", it.ast_node.kind);
        }
    }

    return all_flattened;
}

EmitBuiltins :: (builder : *YalIRBuilder) {
    builder.type_string = CreateIRTypedef(builder, "builtin.string");
    {
        using builder.type_string;
        size = 16;

        members = AllocArray(IRAggregateMember, 2);
        members[0] = .{type=.{kind=.Int64}, num_elements=1, offset=0}; // count
        members[1] = .{type=.{kind=.Pointer}, num_elements=1, offset=8}; // data
    }

    builder.type_slice = CreateIRTypedef(builder, "builtin.slice");
    {
        using builder.type_slice;
        size = 16;

        members = AllocArray(IRAggregateMember, 2);
        members[0] = .{type=.{kind=.Int64}, num_elements=1, offset=0}; // count
        members[1] = .{type=.{kind=.Pointer}, num_elements=1, offset=8}; // data
    }

    builder.type_allocator = CreateIRTypedef(builder, "builtin.allocator");
    {
        using builder.type_allocator;
        size = 16;

        members = AllocArray(IRAggregateMember, 2);
        members[0] = .{type=.{kind=.Pointer}, num_elements=1, offset=0}; // data
        members[1] = .{type=.{kind=.Pointer}, num_elements=1, offset=8}; // func
    }

    builder.type_dynamic_array = CreateIRTypedef(builder, "builtin.dynamic_array");
    {
        using builder.type_dynamic_array;
        size = 40;

        members = AllocArray(IRAggregateMember, 4);
        members[0] = .{type=.{kind=.Int64}, num_elements=1, offset=0}; // count
        members[1] = .{type=.{kind=.Pointer}, num_elements=1, offset=8}; // data
        members[2] = .{type=.{kind=.Int64}, num_elements=1, offset=16}; // capacity
        members[3] = .{type=.{kind=.Typedef, typedef=builder.type_allocator}, num_elements=1, offset=24}; // allocator
    }

    builder.func_memset = CreateIRFunction(builder, "builtin.memset");
    {
        func := builder.func_memset;
        prev_func := SetCurrentFunction(builder, func);
        defer SetCurrentFunction(builder, prev_func);

        ArrayReserve(*func.parameters, 3);
        dst   := IROpSymbol(AddParameter(func, "dst", .{kind=.Pointer}));
        value := IROpSymbol(AddParameter(func, "value", .{kind=.Int8}));
        size  := IROpSymbol(AddParameter(func, "size", .{kind=.Int64}));

        entry_block := CreateIRBasicBlock(builder, "start");
        InsertBlock(builder, entry_block);

        while_block := CreateIRBasicBlock(builder, "while");
        while_end_block := CreateIRBasicBlock(builder, "while.end");

        prev_block := GetCurrentBlock(builder);
        SetCurrentBlock(builder, entry_block);
        // var i := 0;
        i := EmitAlloc(builder, 8, IROpU64(8), "i");
        EmitStore(builder, IROpU64(0), i);
        {
            // while i < size
            cond := EmitCmpSLt(builder, IROpU64(0), IROpSymbol(size), "cond");
            EmitJnz(builder, cond, IROpSymbol(while_block), IROpSymbol(while_end_block));
        }

        InsertBlock(builder, while_block);
        SetCurrentBlock(builder, while_block);
        {
            // ptr[i] = value;
            v_i := EmitLoad(builder, i, .Int64, "i.v");
            ptr_i := EmitAdd(builder, dst, v_i, "ptr_i");
            EmitStore(builder, value, ptr_i);
            v_i = EmitAdd(builder, v_i, IROpU64(1), "i.v");
            EmitStore(builder, v_i, i);
            cond := EmitCmpSLt(builder, v_i, IROpSymbol(size), "cond");
            EmitJnz(builder, cond, IROpSymbol(while_block), IROpSymbol(while_end_block));
        }

        InsertBlock(builder, while_end_block);
        SetCurrentBlock(builder, while_end_block);
        EmitRet(builder);

        SetCurrentBlock(builder, prev_block);

        ValidateFunction(func);
    }

    builder.func_streq = CreateIRFunction(builder, "builtin.streq");
    {
        func := builder.func_streq;
        func.result_type = .{kind=.Int8};
        prev_func := SetCurrentFunction(builder, func);
        defer SetCurrentFunction(builder, prev_func);

        ArrayReserve(*func.parameters, 4);
        a     := IROpSymbol(AddParameter(func, "a", .{kind=.Pointer}));
        b     := IROpSymbol(AddParameter(func, "b", .{kind=.Pointer}));
        a_len := IROpSymbol(AddParameter(func, "a_len", .{kind=.Int64}));
        b_len := IROpSymbol(AddParameter(func, "b_len", .{kind=.Int64}));

        ptr_check_block := CreateIRBasicBlock(builder, "ptr_check");
        loop_prelude_block := CreateIRBasicBlock(builder, "loop.prelude");
        loop_block := CreateIRBasicBlock(builder, "loop");
        loop_cond_block := CreateIRBasicBlock(builder, "loop.cond");
        equal_block := CreateIRBasicBlock(builder, "equal");
        not_equal_block := CreateIRBasicBlock(builder, "not_equal");

        prev_block := GetCurrentBlock(builder);

        entry_block := CreateIRBasicBlock(builder, "start");

        InsertBlock(builder, entry_block);
        SetCurrentBlock(builder, entry_block);
        {
            a_cmp_b_len := EmitCmpEq(builder, a_len, b_len, "a_cmp_b_len");
            EmitJnz(builder, a_cmp_b_len, IROpSymbol(ptr_check_block), IROpSymbol(not_equal_block));
        }

        InsertBlock(builder, ptr_check_block);
        SetCurrentBlock(builder, ptr_check_block);
        {
            a_cmp_b := EmitCmpEq(builder, a, b, "a_cmp_b");
            EmitJnz(builder, a_cmp_b, IROpSymbol(equal_block), IROpSymbol(loop_prelude_block));
        }

        InsertBlock(builder, loop_prelude_block);
        SetCurrentBlock(builder, loop_prelude_block);

        // var i := 0;
        i := EmitAlloc(builder, 8, IROpU64(8), "i");
        EmitStore(builder, IROpU64(0), i);
        {
            // while i < a_len
            cond := EmitCmpSLt(builder, IROpU64(0), a_len, "cond");
            EmitJnz(builder, cond, IROpSymbol(loop_block), IROpSymbol(equal_block));
        }

        InsertBlock(builder, loop_block);
        SetCurrentBlock(builder, loop_block);
        {
            // if a[i] != b[i] return false;
            v_i := EmitLoad(builder, i, .Int64, "i.v");

            a_i_ptr := EmitAdd(builder, a, v_i, "a_i.ptr");
            a_i := EmitLoad(builder, a_i_ptr, .Int8, "a_i");

            b_i_ptr := EmitAdd(builder, b, v_i, "b_i.ptr");
            b_i := EmitLoad(builder, b_i_ptr, .Int8, "b_i");

            a_ne_b := EmitCmpNe(builder, a_i, b_i, "a_ne_b");

            EmitJnz(builder, a_ne_b, IROpSymbol(not_equal_block), IROpSymbol(loop_cond_block));
        }

        InsertBlock(builder, loop_cond_block);
        SetCurrentBlock(builder, loop_cond_block);
        {
            v_i := EmitLoad(builder, i, .Int64, "i.v");
            v_i = EmitAdd(builder, v_i, IROpU64(1), "i.v");
            EmitStore(builder, v_i, i);

            // while i < a_len
            cond := EmitCmpSLt(builder, v_i, a_len, "cond");
            EmitJnz(builder, cond, IROpSymbol(loop_block), IROpSymbol(equal_block));
        }

        InsertBlock(builder, equal_block);
        SetCurrentBlock(builder, equal_block);
        EmitRet(builder, IROpU8(1));

        InsertBlock(builder, not_equal_block);
        SetCurrentBlock(builder, not_equal_block);
        EmitRet(builder, IROpU8(0));

        SetCurrentBlock(builder, prev_block);

        ValidateFunction(func);
    }
}

EmitStruct :: (builder : *YalIRBuilder, node : *AstStruct) {
    if node.dependency_node.check_status >= .Emitted {
        return;
    }

    defer node.dependency_node.check_status = .Emitted;

    type := node.defined_type;
    if type.ir_typedef {
        return;
    }

    DbgInfo(.Codegen, node, "Emitting typedef");

    members := AllocArray(IRAggregateMember, type.members.count);
    for member : type.members {
        member_type := member.type;
        num_elements := 1;
        if member.type.kind == .Array {
            // Handle static arrays of static arrays
            array_type := cast(*YalTypeArray, member.type);
            while array_type.kind == .Array && array_type.array_kind == .Static {
                num_elements *= array_type.count;
                array_type = xx array_type.element_type;
            }

            member_type = array_type;
        }

        members[it_index] = .{type=MakeIRType(builder, member_type), num_elements=num_elements, offset=xx member.byte_offset};
    }

    name := ifx type.name then type.name else ifx type.is_union then "union" else "struct";
    type.ir_typedef = CreateIRTypedef(builder, name);
    type.ir_typedef.is_union = type.is_union;
    type.ir_typedef.members = members;
    type.ir_typedef.size = type.size;

    if !type.ir_default_value {
        DbgInfo(.Codegen, node, "Emitting default value");

        type.ir_default_value = InternConstantStructValue(builder, node.default_value);
    }
}

EmitDeclaration :: (builder : *YalIRBuilder, decl : *AstDeclaration) {
    Assert(decl != null, "Declaration is null");

    if decl.dependency_node.check_status >= .Emitted {
        return;
    }

    defer decl.dependency_node.check_status = .Emitted;

    DbgInfo(.Codegen, decl, "Emitting declaration");

    decl.enclosing_scope.program.codegen_stats.num_declarations += 1;

    if #complete decl.decl_kind == {
    case .Invalid;
        Panic(decl, "Invalid declaration");

    case .ForLoopIndex; #through;
    case .Variable;
        decl.enclosing_scope.program.codegen_stats.num_variable_declarations += 1;

        if decl.enclosing_scope.enclosing_function {
            EmitVariableDecl(builder, decl);
        } else {
            EmitGlobalVariableDecl(builder, decl);
        }

    case .Constant;
        decl.enclosing_scope.program.codegen_stats.num_constant_declarations += 1;

        if decl.expr.kind == {
        case .Function;
            func := cast(*AstFunction, decl.expr);
            Assert(func, func.ir_function != null, "Function should have been emitted by now");
        }

    case .TemplateParam; #through;
    case .EnumMember; #through;
    case .Field;
        // Nothing to emit!
    }
}

EmitRun :: (builder : *YalIRBuilder, run : *AstRun) {
    if run.dependency_node.check_status >= .Emitted {
        return;
    }

    defer run.dependency_node.check_status = .Emitted;

    if run.ir_function {
        return;
    }

    DbgInfo(.Codegen, run, "Emitting #run");

    ir_func := CreateIRFunction(builder, "compile_time_run");
    ir_func.calling_convention = .Yal;

    AddParameter(ir_func, "context", IRType.{kind=.Pointer});

    run.ir_function = ir_func;

    prev_func := SetCurrentFunction(builder, ir_func);
    defer SetCurrentFunction(builder, prev_func);

    ir_func.result_type = MakeIRType(builder, run.type);

    prev_block := GetCurrentBlock(builder);
    defer SetCurrentBlock(builder, prev_block);

    stack_allocs_block := CreateIRBasicBlock(builder, "stack_allocs");
    InsertBlock(builder, stack_allocs_block);
    SetCurrentBlock(builder, stack_allocs_block);

    EmitDbgSetFile(builder, run.file_id);

    entry_block := CreateIRBasicBlock(builder, "start");
    InsertBlock(builder, entry_block);
    SetCurrentBlock(builder, entry_block);

    if run.type == g_type_void {
        EmitExpression(builder, run.expr, "v");

        if !IsTerminated(builder.current_block) {
            EmitDefaultReturn(builder, run.type);
        }
    } else {
        value := EmitArgumentRValue(builder, run.expr, run.type, "v");
        EmitRet(builder, value);
    }

    SetCurrentBlock(builder, stack_allocs_block);
    EmitJmp(builder, IROpSymbol(entry_block));

    ValidateFunction(ir_func);
}

EmitAllocAtFunctionEntry :: (builder : *YalIRBuilder, align : int, size : IROperand, result_name : string) -> IROperand {
    prev_block := SetCurrentBlock(builder, builder.current_func.basic_blocks[0]);
    defer SetCurrentBlock(builder, prev_block);

    return EmitAlloc(builder, align, size, result_name);
}

CreateIRFunction :: (builder : *YalIRBuilder, func : *AstFunction) {
    if func.ir_function {
        return;
    }

    Assert(func, !IsFunctionTemplate(func), "Cannot emit function template");

    func_type := cast(*YalTypeFunction, func.type);

    name := ifx func.symbol_name then func.symbol_name else ifx func.decl then func.decl.identifier.name else "anonymous_func";

    ir_func := CreateIRFunction(builder, name);
    ir_func.calling_convention = func.calling_convention;
    if func.is_c_variadic {
        ir_func.flags |= .CVariadic;
    }
    if func.is_external {
        ir_func.flags |= .External;
        ir_func.library_name = func.library_name;
    }

    ir_func.result_type = MakeIRType(builder, func_type.result);
    ArrayReserve(*ir_func.parameters, func.parameters.count + 1);

    if func.calling_convention == .Yal {
        AddParameter(ir_func, "context", IRType.{kind=.Pointer});
    }

    for func.parameters {
        if it.decl_kind == .TemplateParam {
            continue;
        }

        param_name := it.identifier.name;
        param_type := MakeIRType(builder, it.type, it);
        it.identifier.symbol.ir_symbol = AddParameter(ir_func, param_name, param_type);
    }

    func.ir_function = ir_func;

    if func.decl {
        func.decl.identifier.symbol.ir_symbol = ir_func;
    }
}

EmitFunction :: (builder : *YalIRBuilder, func : *AstFunction) {
    if func.dependency_node.check_status >= .Emitted {
        return;
    }

    defer func.dependency_node.check_status = .Emitted;

    DbgInfo(.Codegen, func, "Emitting function");

    CreateIRFunction(builder, func);

    Assert(func, func.ir_function.basic_blocks.count == 0, "Function has already been emitted");

    prev_func := SetCurrentFunction(builder, func.ir_function);
    defer SetCurrentFunction(builder, prev_func);

    if func.body {
        func_type := cast(*YalTypeFunction, func.type);

        prev_block := GetCurrentBlock(builder);
        defer SetCurrentBlock(builder, prev_block);

        stack_allocs_block := CreateIRBasicBlock(builder, "stack_allocs");
        InsertBlock(builder, stack_allocs_block);
        SetCurrentBlock(builder, stack_allocs_block);

        EmitDbgSetFile(builder, func.file_id);

        for func.parameters {
            if it.decl_kind == .TemplateParam {
                continue;
            }

            if it.type.kind == {
            case .Struct; #through;
            case .Array; #through;
            case .String;
                continue;
            }

            param_name := SPrint("%.ptr", it.identifier.name);
            alignment := GetIRTypeAlignment(it.type);
            ptr := EmitAlloc(builder, alignment, IROpU64(xx it.type.size), param_name);
            EmitStore(builder, IROpSymbol(it.identifier.symbol.ir_symbol), ptr);

            it.identifier.symbol.ir_symbol = ptr.symbol;
        }

        entry_block := CreateIRBasicBlock(builder, "start");
        InsertBlock(builder, entry_block);
        SetCurrentBlock(builder, entry_block);

        EmitStatement(builder, func.body);

        if !IsTerminated(builder.current_block) {
            EmitDefaultReturn(builder, func_type.result);
        }

        SetCurrentBlock(builder, stack_allocs_block);
        EmitJmp(builder, IROpSymbol(entry_block));

        ValidateFunction(func.ir_function);
    }
}

EmitStringLiteralToString :: (builder : *YalIRBuilder, dst_string : IROperand, literal : IROperand, literal_value : ConstantValue) {
    count_ptr := dst_string;
    EmitStore(builder, IROpU64(xx literal_value.string_value.count), count_ptr);
    data_ptr := EmitAdd(builder, dst_string, IROpU64(8), "data_ptr");
    EmitStore(builder, literal, data_ptr);
}

EmitAssignment :: (builder : *YalIRBuilder, lhs : IROperand, lhs_type : *YalType, rhs : IROperand, rhs_expr : *AstNode) {
    if lhs_type == g_type_string && rhs_expr.value.kind == .String {
        EmitStringLiteralToString(builder, lhs, rhs, rhs_expr.value);
    } else {
        EmitStoreOrBlit(builder, rhs, lhs, rhs_expr.type);
    }
}

EmitVariableInit :: (builder : *YalIRBuilder, op : IROperand, type : *YalType) {
    if type.kind == {
    case .Bool; #through;
    case .Pointer; #through;
    case .Integer; #through;
    case .Float; #through;
    case .Enum;
        EmitStore(builder, .{type=MakeIRType(builder, type), value=0}, op);

    case .Struct;
        type_struct := cast(*YalTypeStruct, type);
        if type_struct.ir_default_value {
            EmitBlit(builder, IROpSymbol(type_struct.ir_default_value), op, .{type=.{kind=.Int64}, value=xx type.size});
        } else {
            memset_args := AllocArray(IROperand, 3);
            memset_args[0] = op;
            memset_args[1] = .{type=.{kind=.Int8}, value=0};
            memset_args[2] = .{type=.{kind=.Int64}, value=xx type.size};
            EmitCall(builder, .Yal, IROpSymbol(builder.func_memset), memset_args, .{kind=.Void}, "v");
        }
    case;
        memset_args := AllocArray(IROperand, 3);
        memset_args[0] = op;
        memset_args[1] = .{type=.{kind=.Int8}, value=0};
        memset_args[2] = .{type=.{kind=.Int64}, value=xx type.size};
        EmitCall(builder, .Yal, IROpSymbol(builder.func_memset), memset_args, .{kind=.Void}, "v");
    }
}

EmitVariableDecl :: (builder : *YalIRBuilder, decl : *AstDeclaration) {
    alignment := GetIRTypeAlignment(decl.type, decl);

    if decl.identifier {
        decl.identifier.symbol.ir_symbol = EmitAllocAtFunctionEntry(builder, alignment, IROpU64(xx decl.type.size), decl.identifier.name);
    }

    if decl.expr {
        expr_op := EmitRValue(builder, decl.expr, "v");

        if decl.identifier {
            EmitAssignment(builder, IROpSymbol(decl.identifier.symbol.ir_symbol), decl.type, expr_op, decl.expr);
        }
    } else {
        if decl.identifier {
            EmitVariableInit(builder, IROpSymbol(decl.identifier.symbol.ir_symbol), decl.type);
        }
    }
}

EmitGlobalVariableDecl :: (builder : *YalIRBuilder, decl : *AstDeclaration) {
    DbgInfo(.Codegen, decl, "Emitting global variable decl");

    name := ifx decl.identifier then decl.identifier.name else "global_var";

    global_data := CreateIRGlobalData(builder, name);
    global_data.align = GetTypeAlignment(decl.type);

    if decl.expr && decl.expr.value.kind != .Invalid {
        AddConstantValue(builder, global_data, global_data.align, decl.type, decl.expr.value);
    } else {
        if decl.type.kind == .Struct {
            struct_type := cast(*YalTypeStruct, decl.type);
            AddConstantValue(builder, global_data, global_data.align, struct_type, .{kind=.Struct, struct_value=*struct_type.node.default_value});
        } else {
            AddZeroBytes(global_data, global_data.align, decl.type.size);
        }
    }

    final_aligned_size := AlignForward(global_data.*.total_unaligned_size, global_data.*.align);

    Assert(final_aligned_size == decl.type.size, "When emitting global variable data, we ended up with an aligned size of % bytes but expected %", final_aligned_size, decl.type.size);

    decl.identifier.symbol.ir_symbol = global_data;
}

GetIRTypeAlignment :: (type : *YalType, node_for_debug : *AstNode = null) -> int {
    alignment := GetTypeAlignment(type);
    Assert(ifx node_for_debug then node_for_debug.range, alignment > 0, "Invalid alignment % for type %", alignment, ToString(type));

    alignment = Max(alignment, 4);
    if alignment > 4 {
        alignment = Max(alignment, 8);
    }
    if alignment > 8 {
        alignment = Max(alignment, 16);
    }
    Assert(ifx node_for_debug then node_for_debug.range, alignment <= 16, "Invalid alignment % for type %", alignment, ToString(type));

    return alignment;
}

MakeIRType :: (builder : *YalIRBuilder, type : *YalType, node_for_debug : *AstNode = null) -> IRType {
    if #complete type.kind == {
    case .Invalid;
        return .{};
    case .FunctionOverloadSet;
        return .{kind=.Void};
    case .Module;
        return .{kind=.Void};
    case .Void;
        return .{kind=.Void};
    case .Integer;
        if type.size == {
        case 1; return .{kind=.Int8};
        case 2; return .{kind=.Int16};
        case 4; return .{kind=.Int32};
        case 8; return .{kind=.Int64};
        }
    case .Float;
        if type.size == {
        case 4; return .{kind=.Float32};
        case 8; return .{kind=.Float64};
        }
    case .Bool;
        return .{kind=.Int8};
    case .String;
        return .{kind=.Typedef, typedef=builder.type_string};

    case .Function; #through;
    case .TypeId; #through;
    case .Pointer;
        return .{kind=.Pointer};

    case .Array;
        array_type := cast(*YalTypeArray, type);
        if array_type.array_kind == {
        case .Static;
            return .{kind=.Pointer};
        case .Dynamic;
            return .{kind=.Typedef, typedef=builder.type_dynamic_array};
        case .Slice;
            return .{kind=.Typedef, typedef=builder.type_slice};
        }
    case .Struct;
        struct_type := cast(*YalTypeStruct, type);
        Assert(ifx node_for_debug then node_for_debug.range, struct_type.ir_typedef != null, "Struct type IR typedef is null");

        return .{kind=.Typedef, typedef=struct_type.ir_typedef};

    case .Enum;
        return MakeIRType(builder, cast(*YalTypeEnum, type).base_type, node_for_debug);

    case .TemplateParam;
        template_param := cast(*YalTypeTemplateParam, type);
        Assert(ifx node_for_debug then node_for_debug.range, builder.current_function_template_instantiation != null, "Not in a template instantiation (template param is %, index %)", template_param.name, template_param.param_index);

        param := cast(*YalTypeTemplateParam, type);
        value := builder.current_function_template_instantiation.template_arguments[param.param_index];
    }

    Panic(ifx node_for_debug then node_for_debug.range, "Invalid type");

    return .{};
}

EmitStoreOrBlit :: (builder : *YalIRBuilder, src : IROperand, dst : IROperand, type : *YalType) {
    use_blit := type.kind == .Struct || type.kind == .Array || type.kind == .String;
    if use_blit {
        EmitBlit(builder, src, dst, IROpU64(xx type.size));
    } else {
        EmitStore(builder, src, dst);
    }
}

EmitStatement :: (builder : *YalIRBuilder, stmt : *AstNode) {
    Assert(stmt != null);

    DbgInfo(.Codegen, stmt, "Emitting statement");

    EmitDbgSetLine(builder, xx stmt.line_start);

    if stmt.kind != .Declaration {
        stmt.enclosing_scope.program.codegen_stats.num_statements += 1;
    }

    if IsExpression(stmt.kind) {
        EmitExpression(builder, stmt, "v");
        return;
    }

    if stmt.kind == {
    case .Declaration;
        EmitDeclaration(builder, xx stmt);

    case .Block;
        block := cast(*AstBlock, stmt);

        PushDeferScope(builder, block.scope);
        defer PopDeferScope(builder);

        for block.scope.all_statements {
            EmitStatement(builder, it);

            // Do not emit statements after return
            if it.kind == .Return {
                return;
            }
        }

        // If the block does not end with a return, emit defers declared in the block's scope
        EmitDefersForScope(builder, block.scope);

    case .Assignment;
        assign := cast(*AstAssignment, stmt);

        if assign.op.kind == .Equal {
            lhs := EmitExpression(builder, assign.left, "v");
            rhs := EmitRValue(builder, assign.right, "v");
            EmitAssignment(builder, lhs, assign.left.type, rhs, assign.right);
        } else {
            op := GetBinaryOperatorOfAssignment(assign.op);
            lhs_rvalue, lhs := EmitRValue(builder, assign.left, "v");
            rhs := EmitRValue(builder, assign.right, "v");
            rhs = EmitBinary(builder, assign, lhs_rvalue, rhs, assign.left.type, assign.right.type, op, "v");

            EmitStoreOrBlit(builder, rhs, lhs, assign.left.type);
        }

    case .If;
        EmitIfStatement(builder, xx stmt);

    case .While;
        EmitWhileStatement(builder, xx stmt);

    case .For;
        EmitForStatement(builder, xx stmt);

    case .Defer;
        PushDefer(builder, xx stmt);

    case .Return;
        EmitReturnStatement(builder, xx stmt);

    case .FlowControl;
        flow_control := cast(*AstFlowControl, stmt);
        if flow_control.control == {
        case .DebugBreak;
            EmitDbgBrk(builder);

        case .Continue;
            Assert(builder.enclosing_loop_start_block != null, "Enclosing while start block is null");
            EmitDefersForScope(builder, builder.enclosing_loop_scope);
            EmitJmp(builder, IROpSymbol(builder.enclosing_loop_start_block));

        case .Break;
            Assert(builder.enclosing_loop_merge_block != null, "Enclosing while merge block is null");
            EmitDefersForScope(builder, builder.enclosing_loop_scope);
            EmitJmp(builder, IROpSymbol(builder.enclosing_loop_merge_block));

        case .Fallthrough;
            Panic(stmt, "Not yet handled");
        case;
            Panic(stmt, "Invalid or unhandled flow control node");
        }

    // Nothing to do
    case .Assert;
    case .Insert;
    case .Run;

    case;
        Panic(stmt, "Not yet handled");
    }
}

EmitIfStatement :: (builder : *YalIRBuilder, if_stmt : *AstIf) {
    if if_stmt.is_compile_time {
        return;
    }

    // https://llvm.org/docs/tutorial/MyFirstLanguageFrontend/LangImpl05.html
    // We don't emit a phi node because we emit a statement and not an expression

    cond_op := EmitRValue(builder, if_stmt.condition, "if.cond");
    then_block := CreateIRBasicBlock(builder, "if.then");
    else_block := ifx if_stmt.else_stmt
        then CreateIRBasicBlock(builder, "if.else");
    merge_block := CreateIRBasicBlock(builder, "if.end");

    if if_stmt.else_stmt {
        EmitJnz(builder, cond_op, IROpSymbol(then_block), IROpSymbol(else_block));
    } else {
        EmitJnz(builder, cond_op, IROpSymbol(then_block), IROpSymbol(merge_block));
    }

    InsertBlock(builder, then_block);
    SetCurrentBlock(builder, then_block);
    EmitStatement(builder, if_stmt.body);

    then_block = GetCurrentBlock(builder);
    if !IsTerminated(then_block) {
        EmitJmp(builder, IROpSymbol(merge_block));
    }

    if if_stmt.else_stmt {
        InsertBlock(builder, else_block);
        SetCurrentBlock(builder, else_block);
        EmitStatement(builder, if_stmt.else_stmt);

        else_block = GetCurrentBlock(builder);
        if !IsTerminated(else_block) {
            EmitJmp(builder, IROpSymbol(merge_block));
        }
    }

    InsertBlock(builder, merge_block);
    SetCurrentBlock(builder, merge_block);
}

EmitWhileStatement :: (builder : *YalIRBuilder, while_stmt : *AstWhile) {
    prev_loop := builder.enclosing_loop;
    defer builder.enclosing_loop = prev_loop;

    prev_loop_scope := builder.enclosing_loop_scope;
    defer builder.enclosing_loop_scope = prev_loop_scope;

    prev_loop_start_block := builder.enclosing_loop_start_block;
    defer builder.enclosing_loop_start_block = prev_loop_start_block;

    prev_loop_body_block := builder.enclosing_loop_body_block;
    defer builder.enclosing_loop_body_block = prev_loop_body_block;

    prev_loop_merge_block := builder.enclosing_loop_merge_block;
    defer builder.enclosing_loop_merge_block = prev_loop_merge_block;

    builder.enclosing_loop = while_stmt;
    builder.enclosing_loop_scope = while_stmt.scope;
    builder.enclosing_loop_start_block = CreateIRBasicBlock(builder, "while.start");
    builder.enclosing_loop_body_block = CreateIRBasicBlock(builder, "while.body");
    builder.enclosing_loop_merge_block = CreateIRBasicBlock(builder, "while.merge");

    EmitJmp(builder, IROpSymbol(builder.enclosing_loop_start_block));

    InsertBlock(builder, builder.enclosing_loop_start_block);
    SetCurrentBlock(builder, builder.enclosing_loop_start_block);

    cond_op := EmitRValue(builder, while_stmt.condition, "while.cond");
    EmitJnz(builder, cond_op, IROpSymbol(builder.enclosing_loop_body_block), IROpSymbol(builder.enclosing_loop_merge_block));

    InsertBlock(builder, builder.enclosing_loop_body_block);
    SetCurrentBlock(builder, builder.enclosing_loop_body_block);

    PushDeferScope(builder, builder.enclosing_loop_scope);

    EmitStatement(builder, while_stmt.body);

    PopDeferScope(builder);

    if !IsTerminated(GetCurrentBlock(builder)) {
        EmitJmp(builder, IROpSymbol(builder.enclosing_loop_start_block));
    }

    InsertBlock(builder, builder.enclosing_loop_merge_block);
    SetCurrentBlock(builder, builder.enclosing_loop_merge_block);
}

EmitForStatement :: (builder : *YalIRBuilder, for_stmt : *AstFor) {
    prev_loop := builder.enclosing_loop;
    defer builder.enclosing_loop = prev_loop;

    prev_loop_scope := builder.enclosing_loop_scope;
    defer builder.enclosing_loop_scope = prev_loop_scope;

    prev_loop_start_block := builder.enclosing_loop_start_block;
    defer builder.enclosing_loop_start_block = prev_loop_start_block;

    prev_loop_body_block := builder.enclosing_loop_body_block;
    defer builder.enclosing_loop_body_block = prev_loop_body_block;

    prev_loop_merge_block := builder.enclosing_loop_merge_block;
    defer builder.enclosing_loop_merge_block = prev_loop_merge_block;

    builder.enclosing_loop = for_stmt;
    builder.enclosing_loop_scope = for_stmt.scope;
    builder.enclosing_loop_start_block = CreateIRBasicBlock(builder, "for.start");
    builder.enclosing_loop_body_block = CreateIRBasicBlock(builder, "for.body");
    builder.enclosing_loop_merge_block = CreateIRBasicBlock(builder, "for.merge");

    // Range start and end are evaluated/emitted at the start of the for loop,
    // not at each iteration. We might change this because evaluating at each
    // iteration makes it possible to do the eval only at the start by storing
    // the results in variables, but doing the opposite makes it impossible to
    // evaluate at each iteration, and forces the user to use a while loop instead.
    range_expr : *AstRange;
    index_storage : IROperand;

    // @Todo @Cleanup: use EmitStatement to avoid duplicate code
    if for_stmt.iterator.kind == {
    case .Declaration;
        index_decl := cast(*AstDeclaration, for_stmt.iterator);
        range_expr = xx index_decl.expr;
        Assert(range_expr, range_expr.kind == .Range, "Not yet handled");

        EmitDeclaration(builder, index_decl);
        index_storage = IROpSymbol(index_decl.identifier.symbol.ir_symbol);

    case .Assignment;
        index_assign := cast(*AstAssignment, for_stmt.iterator);
        range_expr = xx index_assign.right;
        Assert(range_expr, range_expr.kind == .Range, "Not yet handled");

        index_storage = EmitExpression(builder, index_assign.left, "for.index");
        rhs := EmitRValue(builder, index_assign.right, "for.rhs");
        EmitAssignment(builder, index_storage, index_assign.left.type, rhs, index_assign.right);

    case;
        Panic(for_stmt.iterator, "Unexpected ast node kind %", for_stmt.iterator.kind);
    }

    range_type := range_expr.start.type;
    range_ir_type := MakeIRType(builder, range_type);

    end_op := EmitRValue(builder, range_expr.end, "for.range.end");

    EmitJmp(builder, IROpSymbol(builder.enclosing_loop_start_block));

    InsertBlock(builder, builder.enclosing_loop_start_block);
    SetCurrentBlock(builder, builder.enclosing_loop_start_block);

    index_op := EmitLoad(builder, index_storage, range_ir_type.kind, "for.index.val");
    cond_op : IROperand;

    compare_ops := TokenKind.[
        ifx range_expr.reverse then .GreaterEqu else .LessEqu,
        ifx range_expr.reverse then .Greater else .Less,
    ];
    if range_expr.inclusive {
        cond_op = EmitBinary(builder, range_expr, index_op, end_op, range_type, range_expr.end.type, compare_ops[0], "for.cond");
    } else {
        cond_op = EmitBinary(builder, range_expr, index_op, end_op, range_type, range_expr.end.type, compare_ops[1], "for.cond");
    }

    EmitJnz(builder, cond_op, IROpSymbol(builder.enclosing_loop_body_block), IROpSymbol(builder.enclosing_loop_merge_block));

    InsertBlock(builder, builder.enclosing_loop_body_block);
    SetCurrentBlock(builder, builder.enclosing_loop_body_block);

    ForDeferContext :: struct {
        for_stmt : *AstFor;
        range_expr : *AstRange;
        index_storage : IROperand;
    }

    defer_context := ForDeferContext.{for_stmt, range_expr, index_storage};

    PushDeferScope(builder, builder.enclosing_loop_scope);

    // Defer emit increment for the index
    PushDefer(builder, *defer_context, (builder : *YalIRBuilder, data : *void) {
        using defer_context := cast(*ForDeferContext, data);

        range_type := range_expr.start.type;
        range_ir_type := MakeIRType(builder, range_type);

        index_op := EmitLoad(builder, index_storage, range_ir_type.kind, "for.index.val");
        binary_op := ifx range_expr.reverse then TokenKind.Minus else .Plus;
        index_plus_one := EmitBinary(builder, range_expr, index_op, .{type=range_ir_type, value=1}, range_type, range_type, binary_op, "for.index.incr");
        EmitStore(builder, index_plus_one, index_storage);
    });

    EmitStatement(builder, for_stmt.body);
    EmitDefersForScope(builder, builder.enclosing_loop_scope);

    PopDeferScope(builder);

    if !IsTerminated(GetCurrentBlock(builder)) {
        EmitJmp(builder, IROpSymbol(builder.enclosing_loop_start_block));
    }

    InsertBlock(builder, builder.enclosing_loop_merge_block);
    SetCurrentBlock(builder, builder.enclosing_loop_merge_block);
}

EmitDefaultReturn :: (builder : *YalIRBuilder, type : *YalType) {
    if type.kind == {
    case .Invalid;
        Panic("Invalid type");
    case .Void;
        EmitRet(builder);
    case .Bool; #through;
    case .Pointer; #through;
    case .Integer; #through;
    case .Float; #through;
    case .Enum;
        EmitRet(builder, .{type=MakeIRType(builder, type), value=0});

    case;
        alignment := GetIRTypeAlignment(type);
        ptr := EmitAllocAtFunctionEntry(builder, alignment, IROpU64(xx type.size), "retval");
        EmitVariableInit(builder, ptr, type);

        EmitRet(builder, ptr);
    }
}

PushDeferScope :: inline (builder : *YalIRBuilder, scope : *Scope) -> int {
    index := builder.defer_scope_stack.count;
    ArrayPush(*builder.defer_scope_stack, .{scope=scope});

    return index;
}

PopDeferScope :: inline (builder : *YalIRBuilder) {
    ArrayPop(*builder.defer_scope_stack);
}

PushDefer :: inline (builder : *YalIRBuilder, stmt : *AstDefer) {
    scope := ArrayTop(builder.defer_scope_stack);
    ArrayPush(*scope.defers, .{data=stmt, callback=(builder : *YalIRBuilder, node : *void) { EmitStatement(builder, cast(*AstDefer, node).stmt); } });
}

PushDefer :: inline (builder : *YalIRBuilder, data : *void, callback : type_of(YalIRBuilder.DeferCallback.callback)) {
    scope := ArrayTop(builder.defer_scope_stack);
    ArrayPush(*scope.defers, .{data=data, callback=callback});
}

EmitDefersForAllScopes :: (builder : *YalIRBuilder) {
    scope_stack := builder.defer_scope_stack;
    defer builder.defer_scope_stack = scope_stack;

    Initialize(*builder.defer_scope_stack);

    PushDeferScope(builder, null);
    defer PopDeferScope(builder);

    for < scope_stack {
        for < it.defers {
            if IsTerminated(builder.current_block) {
                return;
            }

            it.callback(builder, it.data);
        }
    }
}

EmitDefersForScope :: (builder : *YalIRBuilder, scope : *Scope) {
    scope_stack := builder.defer_scope_stack;
    defer builder.defer_scope_stack = scope_stack;

    Initialize(*builder.defer_scope_stack);

    PushDeferScope(builder, null);
    defer PopDeferScope(builder);

    for < scope_stack {
        for < it.defers {
            if IsTerminated(builder.current_block) {
                return;
            }

            it.callback(builder, it.data);
        }

        if it.scope == scope {
            return;
        }
    }
}

EmitReturnStatement :: (builder : *YalIRBuilder, return_stmt : *AstReturn) {
    if return_stmt.expr {
        func_type := cast(*YalTypeFunction, return_stmt.enclosing_scope.enclosing_function.type);
        value := EmitArgumentRValue(builder, return_stmt.expr, func_type.result, "v");

        EmitDefersForAllScopes(builder);

        EmitRet(builder, value);
    } else {
        EmitDefersForAllScopes(builder);

        func := return_stmt.enclosing_scope.enclosing_function;
        func_type := cast(*YalTypeFunction, func.type);
        EmitDefaultReturn(builder, func_type.result);
    }
}

EmitRValue :: (builder : *YalIRBuilder, expr : *AstNode, value_name : string) -> IROperand, original_op : IROperand {
    original_op := EmitExpression(builder, expr, value_name);
    op := original_op;

    needs_load := expr.semantic_meaning == .Mutable
        && expr.type.kind != .Struct
        && expr.type.kind != .String
        && expr.type.kind != .Array;
    if op.symbol && op.symbol.kind == .Parameter {
        needs_load = false;
    }

    if needs_load {
        type := MakeIRType(builder, expr.type);
        Assert(type.kind != .Void && type.kind != .Invalid);
        type = DecayPointer(type);

        op = EmitLoad(builder, op, type, value_name);
    }

    return op, original_op;
}

EmitArgumentRValue :: (builder : *YalIRBuilder, expr : *AstNode, param_type : *YalType, value_name : string) -> IROperand, original_op : IROperand {
    if expr.value.kind == .String {
        str := EmitAllocAtFunctionEntry(builder, 8, IROpU64(16), value_name);
        str_lit := EmitRValue(builder, expr, "strlit");
        EmitStringLiteralToString(builder, str, str_lit, expr.value);

        str.type = MakeIRType(builder, param_type);

        return str, str;
    }

    op, original_op := EmitRValue(builder, expr, value_name);
    op.type = MakeIRType(builder, param_type, expr);

    return op, original_op;
}

MakeIROperandFromConstantValue :: (builder : *YalIRBuilder, expr : *AstNode) -> bool, IROperand {
    if #complete expr.value.kind == {
    case .Integer;
        int_type := cast(*YalTypeInteger) expr.type;
        return true, .{type=MakeIRType(builder, int_type), value=expr.value.int_value.low};

    case .Boolean;
        return true, IROpU8(cast(u8, expr.value.bool_value));

    case .Float;
        if expr.type.size == {
        case 4; return true, IROpF32(cast(float32, expr.value.float_value));
        case 8; return true, IROpF64(cast(float64, expr.value.float_value));
        case; Panic(expr, "Invalid size % for float type", expr.type.size);
        }

    case .Pointer;
        return true, IROpU64(xx,no_check(expr.value.pointer_value));

    case .String;
        if expr.value.string_value.count == 0 {
            return true, IROpNullPtr();
        }

        data := InternString(builder, expr.value.string_value);
        return true, IROpSymbol(data);

    case .Function;
        func := expr.value.function_node;
        if !func.ir_function {
            CreateIRFunction(builder, expr.value.function_node);
        }

        return true, IROpSymbol(func.ir_function);

    case .FunctionOverloadSet;
        if expr.value.overload_set.selected_overload_index < 0 {
            Panic(expr, "Unresolved function overload sets are not supposed to be emitted");
        }

        set := expr.value.overload_set.node;
        selected_overload := set.final_overloads[expr.value.overload_set.selected_overload_index];
        ok, op := MakeIROperandFromConstantValue(builder, selected_overload);

        return ok, op;

    case .TypeId;
        return true, IROpU64(xx,no_check(expr.value.type_value));

    case .Struct;
        data := InternConstantStructValue(builder, expr.value.struct_value.*);
        return true, IROpSymbol(data);

    case .Module; #through;
    case .TemplateParam;
        Panic(expr, "Emitting IR operand for a % value. This is not allowed", expr.value.kind);

    case .Invalid;
        Assert(expr, expr.semantic_meaning != .Constant, "Expression is constant but does not have a value");
    }

    return false, .{};
}

GetSymbolOfUsing :: (node : *AstNode) -> *Symbol {
    if node.kind == {
    case .Identifier;
        ident := cast(*AstIdentifier, node);
        return ident.symbol;

    case .Declaration;
        decl := cast(*AstDeclaration, node);
        Assert(decl.identifier != null, "Identifier is null");
        return decl.identifier.symbol;

    case;
        Panic("When emitting imported symbol: only identifiers or declarations are handled for node (got %)", node.kind);
    }

    return null;
}

EmitImportedSymbolAccess :: (builder : *YalIRBuilder, source_expr : IROperand, imported_symbol : *ImportedSymbol, emit_initial_using := false) -> IROperand {
    symbol : *Symbol;
    if emit_initial_using {
        symbol = GetSymbolOfUsing(imported_symbol.source_using);
    } else if imported_symbol.source_import {
        symbol = GetSymbolOfUsing(imported_symbol.source_import.source_using);
    } else {
        symbol = imported_symbol.final_symbol;
    }

    accessed_struct := GetStructOfScope(symbol.scope);
    Assert(symbol.decl, accessed_struct != null, "Unhandled case when emitting symbol imported via `using` (accessed struct is null)");

    member := GetStructMember(accessed_struct.defined_type, symbol.name);

    Assert(member != null, "No member named % in struct type", symbol.name);
    Assert(member.byte_offset >= 0, "Invalid member % byte offset %", member.name, member.byte_offset);

    result := EmitAdd(builder, source_expr, IROpU64(xx member.byte_offset), "v");

    if emit_initial_using {
        result = EmitImportedSymbolAccess(builder, result, imported_symbol, emit_initial_using=false);
    } else if imported_symbol.source_import {
        result = EmitImportedSymbolAccess(builder, result, imported_symbol.source_import);
    }

    return result;
}

EmitImportedSymbol :: (builder : *YalIRBuilder, imported_symbol : *ImportedSymbol) -> IROperand {
    symbol := GetSymbolOfUsing(imported_symbol.source_using);
    Assert(symbol != null, "Symbol is null");

    if !symbol.ir_symbol {
        EmitDeclaration(builder, symbol.decl);
    }

    Assert(symbol.ir_symbol != null, "IR symbol is null");
    source_expr := IROpSymbol(symbol.ir_symbol);

    return EmitImportedSymbolAccess(builder, source_expr, imported_symbol);
}

EmitExpression :: (builder : *YalIRBuilder, expr : *AstNode, value_name : string) -> IROperand {
    Assert(expr != null);
    Assert(expr, expr.type != null, "Expression has no type");
    Assert(expr, expr.type != g_type_invalid, "Expression has type invalid");

    expr.enclosing_scope.program.codegen_stats.num_expressions += 1;

    valid_constant, op := MakeIROperandFromConstantValue(builder, expr);
    if valid_constant {
        return op;
    }

    if expr.kind == {
    case .Context;
        context_param := GetParameter(GetCurrentFunction(builder), "%context");
        Assert(expr, context_param != null, "Could not get context parameter in IR function");
        return IROpSymbol(context_param);

    case .Identifier;
        ident := cast(*AstIdentifier) expr;

        if ident.imported_symbol {
            return EmitImportedSymbol(builder, ident.imported_symbol);
        }

        if !ident.symbol.ir_symbol {
            EmitDeclaration(builder, ident.symbol.decl);
        }

        Assert(ident.symbol.ir_symbol != null, "Identifier points to a null IR symbol");

        return IROpSymbol(ident.symbol.ir_symbol);

    case .FieldAccess;
        access := cast(*AstFieldAccess, expr);

        if !access.left || access.accessed_struct_member_offset < 0 {
            return EmitExpression(builder, access.right, value_name);
        }

        lhs := EmitExpression(builder, access.left, value_name);
        if access.left.type.kind == .Pointer {
            lhs = EmitLoad(builder, lhs, .Pointer, value_name);
        }

        ident := cast(*AstIdentifier, access.right);
        if ident.imported_symbol {
            return EmitImportedSymbolAccess(builder, lhs, ident.imported_symbol, emit_initial_using=true);
        }

        return EmitAdd(builder, lhs, IROpU64(xx access.accessed_struct_member_offset), value_name);

    case .Binary;
        return EmitBinary(builder, xx expr, value_name);

    case .Unary;
        return EmitUnary(builder, xx expr, value_name);

    // size_of and literals are constants so they have been handled earlier
    case .SizeOf; #through;
    case .Literal;
        Panic(expr, "This should have been handled above");

    case .Cast;
        cast_expr := cast(*AstCast, expr);
        op := EmitRValue(builder, cast_expr.expr, "cast.v");
        if cast_expr.cast_kind == .Bitcast {
            return EmitBitCast(builder, op, cast_expr.expr.type, expr.type, "v");
        } else {
            return EmitCast(builder, op, cast_expr.expr.type, expr.type, "v");
        }

    case .Subscript;
        return EmitSubscript(builder, xx expr, "v");

    case .FunctionCall;
        call := cast(*AstFunctionCall, expr);

        func_type := cast(*YalTypeFunction, call.callee.type);
        Assert(call.callee, func_type.kind == .Function, "Not a function");

        callee := EmitRValue(builder, call.callee, "callee");
        func_node := ifx call.callee.value.kind == .Function then call.callee.value.function_node;

        args : [..]IROperand;
        ArrayReserve(*args, call.ordered_arguments.count + 1);

        if func_type.calling_convention == .Yal {
            context_param := GetParameter(GetCurrentFunction(builder), "%context");
            Assert(expr, context_param != null, "Could not get context parameter in IR function");

            ArrayPush(*args, IROpSymbol(context_param));
        }

        for call.ordered_arguments {
            if func_node && func_node.parameters[it_index].decl_kind == .TemplateParam {
                continue;
            }

            param_type := ifx it_index >= func_type.parameters.count
                then it.type
                else func_type.parameters[it_index];
            op := EmitArgumentRValue(builder, it, param_type, "arg");
            ArrayPush(*args, op);
        }

        ir_result_type := MakeIRType(builder, func_type.result);
        first_c_variadic_argument_index := ifx func_type.is_c_variadic then func_type.parameters.count else -1;

        return EmitCall(builder, func_type.calling_convention, callee, args, ir_result_type, "v", first_c_variadic_argument_index);

    case .StructLiteral;
        lit := cast(*AstStructLiteral, expr);
        alignment := GetIRTypeAlignment(expr.type);
        storage := EmitAllocAtFunctionEntry(builder, alignment, IROpU64(xx expr.type.size), value_name);

        struct_type := cast(*YalTypeStruct, expr.type);

        for lit.values {
            member := struct_type.members[it_index];

            lhs := EmitAdd(builder, storage, IROpU64(xx member.byte_offset), "v");

            value := EmitRValue(builder, it, "v");

            EmitAssignment(builder, lhs, member.type, value, it);
        }

        return storage;

    case .Range;
        range_expr := cast(*AstRange, expr);
        return EmitRValue(builder, range_expr.start, "v");

    case;
        Panic(expr, "Unhandled case in EmitExpression: %", expr.kind);
    }

    return .{};
}

EmitBitCast :: (builder : *YalIRBuilder, src_op : IROperand, src_type : *YalType, dst_type : *YalType, value_name : string) -> IROperand {
    Assert(src_type.size == dst_type.size, "When emitting bitcast, source and dest type size mismatches (% vs %)", ToString(src_type), ToString(dst_type));

    if src_type == dst_type {
        return src_op;
    }

    if src_type.kind == .Enum {
        src_type = cast(*YalTypeEnum, src_type).base_type;
    }

    if dst_type.kind == .Enum {
        dst_type = cast(*YalTypeEnum, dst_type).base_type;
    }

    if src_type.kind == .Pointer && dst_type.kind == .Pointer {
        return src_op;
    }

    // For integer <->, the only possibility is bitcast signed <-> unsigned, and we
    // don't care about signedness in the IR, so it's a noop
    if src_type.kind == .Integer && dst_type.kind == .Integer {
        return src_op;
    }

    if dst_type.kind == {
    case .Pointer;
        return EmitBitCastToPtr(builder, src_op, value_name);
    case .Integer;
        if dst_type.size == {
        case 4;
            return EmitBitCastToI32(builder, src_op, value_name);
        case 8;
            return EmitBitCastToI64(builder, src_op, value_name);
        }
    case .Float;
        if dst_type.size == {
        case 4;
            return EmitBitCastToF32(builder, src_op, value_name);
        case 8;
            return EmitBitCastToF64(builder, src_op, value_name);
        }
    }

    Panic("Unhandled case in EmitBitCast");

    return src_op;
}

EmitCast :: (builder : *YalIRBuilder, src_op : IROperand, src_type : *YalType, dst_type : *YalType, value_name : string) -> IROperand {
    if src_type == dst_type {
        return src_op;
    }

    if src_type.kind == .Enum {
        src_type = cast(*YalTypeEnum, src_type).base_type;
    }

    if dst_type.kind == .Enum {
        dst_type = cast(*YalTypeEnum, dst_type).base_type;
    }

    if src_type.kind == .Pointer && dst_type.kind == .Function
    || src_type.kind == .Function && dst_type.kind == .Pointer
    || src_type.kind == .Pointer && dst_type.kind == .Pointer {
        return src_op;
    } else if src_type.kind == .Integer && dst_type.kind == .Pointer {
        casted := src_op;
        if src_type.size < dst_type.size {
            casted = EmitZExtToI64(builder, src_op, "cast.v");
        } else if src_type.size > dst_type.size {
            Panic("When casting type % to a pointer, source type is larger than 8 bytes", ToString(src_type));
        }

        return EmitBitCastToPtr(builder, casted, value_name);
    } else if src_type.kind == .Pointer && dst_type.kind == .Integer {
        casted := EmitBitCastToI64(builder, src_op, value_name);
        if src_type.size > dst_type.size {
            casted = EmitIntTrunc(builder, MakeIRType(builder, dst_type), casted, value_name);
        } else if src_type.size < dst_type.size {
            Panic("When casting pointer type to %, dest type is larger than 8 bytes", ToString(dst_type));
        }

        return casted;
    } else if src_type.kind == .Float && dst_type.kind == .Float {
        if src_type.size < dst_type.size {
            return EmitExtToF64(builder, src_op, value_name);
        } else {
            return EmitTruncToF32(builder, src_op, value_name);
        }
    } else if src_type.kind == .Float && dst_type.kind == .Integer {
        dst_int := cast(*YalTypeInteger, dst_type);
        if dst_int.is_signed {
            casted := EmitFToI64(builder, src_op, value_name);
            if dst_int.size < 8 {
                casted = EmitIntTrunc(builder, MakeIRType(builder, dst_int), casted, value_name);
            }

            return casted;
        } else {
            casted := EmitFToU64(builder, src_op, value_name);
            if dst_int.size < 8 {
                casted = EmitIntTrunc(builder, MakeIRType(builder, dst_int), casted, value_name);
            }

            return casted;
        }
    } else if src_type.kind == .Integer && dst_type.kind == .Float {
        src_int := cast(*YalTypeInteger, src_type);
        if src_int.is_signed {
            if dst_type.size == 4 {
                return EmitIToF32(builder, src_op, value_name);
            } else {
                return EmitIToF64(builder, src_op, value_name);
            }
        } else {
            if dst_type.size == 4 {
                return EmitUToF32(builder, src_op, value_name);
            } else {
                return EmitUToF64(builder, src_op, value_name);
            }
        }
    } else if src_type.kind == .Integer && dst_type.kind == .Integer {
        src_int := cast(*YalTypeInteger, src_type);
        dst_int := cast(*YalTypeInteger, dst_type);
        if dst_int.size > src_int.size {
            sign_extend := src_int.is_signed && dst_int.is_signed;
            if sign_extend {
                return EmitSExt(builder, MakeIRType(builder, dst_type), src_op, value_name);
            } else {
                return EmitZExt(builder, MakeIRType(builder, dst_type), src_op, value_name);
            }
        } else if dst_int.size < src_int.size {
            return EmitIntTrunc(builder, MakeIRType(builder, dst_type), src_op, value_name);
        } else {
            return src_op;
        }
    }

    Panic("Unhandled case in EmitCast (src_type is %, dst_type is %)", ToString(src_type), ToString(dst_type));

    return src_op;
}

EmitSubscript :: (builder : *YalIRBuilder, subscript : *AstSubscript, value_name : string) -> IROperand {
    lhs := EmitExpression(builder, subscript.subscripted, "lhs");
    index := EmitRValue(builder, subscript.index, "idx");

    // Make sure the subscript index is a 64-bit integer
    if subscript.index.type.size < 8 {
        Assert(subscript.index, subscript.index.type.kind == .Integer, "Expected an integer for subscript");
        if cast(*YalTypeInteger, subscript.index.type).is_signed {
            index = EmitSExtToI64(builder, index, "idx");
        } else {
            index = EmitZExtToI64(builder, index, "idx");
        }
    }

    offset := ifx subscript.type.size > 1
        then EmitMul(builder, index, IROpU64(xx subscript.type.size), "off")
        else index;
    ptr : IROperand;

    type := subscript.subscripted.type;
    if type.kind == {
    case .Array;
        array_type := cast(*YalTypeArray, type);
        if #complete array_type.array_kind == {
        case .Invalid; Panic(subscript, "Invalid array type");

        // Slice and dynamic arrays are accessed like structs
        case .Slice; #through;
        case .Dynamic;
            // @Todo: bounds checking
            ptr = lhs;
            ptr = EmitAdd(builder, ptr, IROpU64(8), "lhs.data.ptr");
            ptr = EmitLoad(builder, ptr, .Pointer, "lhs.data");

        case .Static;
            ptr = lhs;
        }

    case .Pointer;
        ptr = EmitLoad(builder, lhs, .Pointer, "lhs");

    case .String;
        ptr = lhs;
        ptr = EmitAdd(builder, ptr, IROpU64(8), "lhs.data.ptr");
        ptr = EmitLoad(builder, ptr, .Pointer, "lhs.data");

    case;
        Panic(subscript, "Unhandled subscript type % for IR codegen", ToString(type));
    }

    return EmitAdd(builder, ptr, offset, value_name);
}

EmitStringCmpEq :: (
    builder : *YalIRBuilder,
    lhs : IROperand, rhs : IROperand,
    lhs_expr : *AstNode, rhs_expr : *AstNode,
    value_name : string
) -> IROperand {

    args := AllocArray(IROperand, 4);
    if lhs_expr.value.kind == .String {
        args[0] = lhs;
        args[2] = IROpU64(xx lhs_expr.value.string_value.count);
    } else {
        lhs_data := EmitAdd(builder, lhs, IROpU64(8), "lhs.data.ptr");
        args[0] = EmitLoad(builder, lhs_data, .Pointer, "streq.a");
        args[2] = EmitLoad(builder, lhs, .Int64, "streq.a_len");
    }

    if rhs_expr.value.kind == .String {
        args[1] = rhs;
        args[3] = IROpU64(xx rhs_expr.value.string_value.count);
    } else {
        rhs_data := EmitAdd(builder, rhs, IROpU64(8), "rhs.data.ptr");
        args[1] = EmitLoad(builder, rhs_data, .Pointer, "streq.b");
        args[3] = EmitLoad(builder, rhs, .Int64, "streq.b_len");
    }

    return EmitCall(builder, .Yal, IROpSymbol(builder.func_streq), args, .{kind=.Int8}, value_name);
}

EmitStringCmpNe :: (
    builder : *YalIRBuilder,
    lhs : IROperand, rhs : IROperand,
    lhs_expr : *AstNode, rhs_expr : *AstNode,
    value_name : string
) -> IROperand {
    cmp_res := EmitStringCmpEq(builder, lhs, rhs, lhs_expr, rhs_expr, value_name);

    return EmitCmpEq(builder, cmp_res, IROpU8(0), value_name);
}

EmitBinary :: (
    builder : *YalIRBuilder,
    node : *AstNode,
    lhs : IROperand, rhs : IROperand,
    lhs_type : *YalType, rhs_type : *YalType,
    op : TokenKind,
    value_name : string
) -> IROperand {
    GetPointerArithmeticRHS :: () -> IROperand #expand {
        Assert(node, rhs_type.kind == .Integer, "Unexpected rhs type % for pointer arithmetic", ToString(rhs_type));

        if rhs_type.size != 8 {
            if cast(*YalTypeInteger, rhs_type).is_signed {
                return EmitSExtToI64(builder, rhs, value_name);
            } else {
                return EmitZExtToI64(builder, rhs, value_name);
            }
        }

        return rhs;
    }

    if op == {
    case .PipePipe; #through;
    case .AmpersandAmpersand;
        Panic(node, "Short circuit operators need special handling");

    case .EquEqu;
        if lhs_type == g_type_string && rhs_type == g_type_string {
            binary := cast(*AstBinary, node);
            Assert(node, binary.kind == .Binary, "Invalid or unhandled codepath (expected this to be AstBinary)");

            return EmitStringCmpEq(builder, lhs, rhs, binary.left, binary.right, value_name);
        }

        return EmitCmpEq(builder, lhs, rhs, value_name);
    case .BangEqu;
        if lhs_type == g_type_string && rhs_type == g_type_string {
            binary := cast(*AstBinary, node);
            Assert(node, binary.kind == .Binary, "Invalid or unhandled codepath (expected this to be AstBinary)");

            return EmitStringCmpNe(builder, lhs, rhs, binary.left, binary.right, value_name);
        }

        return EmitCmpNe(builder, lhs, rhs, value_name);
    case .Less;
        is_float := lhs_type.kind == .Float;
        is_signed_integer := lhs_type.kind == .Integer && cast(*YalTypeInteger, lhs_type).is_signed;
        if is_float {
            return EmitCmpFLt(builder, lhs, rhs, value_name);
        } else if is_signed_integer {
            return EmitCmpSLt(builder, lhs, rhs, value_name);
        } else {
            return EmitCmpULt(builder, lhs, rhs, value_name);
        }
    case .Greater;
        is_float := lhs_type.kind == .Float;
        is_signed_integer := lhs_type.kind == .Integer && cast(*YalTypeInteger, lhs_type).is_signed;
        if is_float {
            return EmitCmpFGt(builder, lhs, rhs, value_name);
        } else if is_signed_integer {
            return EmitCmpSGt(builder, lhs, rhs, value_name);
        } else {
            return EmitCmpUGt(builder, lhs, rhs, value_name);
        }
    case .LessEqu;
        is_float := lhs_type.kind == .Float;
        is_signed_integer := lhs_type.kind == .Integer && cast(*YalTypeInteger, lhs_type).is_signed;
        if is_float {
            return EmitCmpFLe(builder, lhs, rhs, value_name);
        } else if is_signed_integer {
            return EmitCmpSLe(builder, lhs, rhs, value_name);
        } else {
            return EmitCmpULe(builder, lhs, rhs, value_name);
        }
    case .GreaterEqu;
        is_float := lhs_type.kind == .Float;
        is_signed_integer := lhs_type.kind == .Integer && cast(*YalTypeInteger, lhs_type).is_signed;
        if is_float {
            return EmitCmpFGe(builder, lhs, rhs, value_name);
        } else if is_signed_integer {
            return EmitCmpSGe(builder, lhs, rhs, value_name);
        } else {
            return EmitCmpUGe(builder, lhs, rhs, value_name);
        }
    case .LessLess;
        return EmitShl(builder, lhs, rhs, value_name);
    case .GreaterGreater;
        return EmitShr(builder, lhs, rhs, value_name);
    case .Pipe;
        return EmitOr(builder, lhs, rhs, value_name);
    case .Caret;
        return EmitXor(builder, lhs, rhs, value_name);
    case .Ampersand;
        return EmitAnd(builder, lhs, rhs, value_name);
    case .Plus;
        right := rhs;

        is_pointer_arith := lhs_type.kind == .Pointer;
        if is_pointer_arith {
            right = GetPointerArithmeticRHS();
        }

        return EmitAdd(builder, lhs, right, value_name);
    case .Minus;
        right := rhs;

        is_pointer_arith := lhs_type.kind == .Pointer;
        if is_pointer_arith {
            right = GetPointerArithmeticRHS();
        }

        return EmitSub(builder, lhs, right, value_name);
    case .Star;
        return EmitMul(builder, lhs, rhs, value_name);
    case .Slash;
        is_unsigned_integer := lhs_type.kind == .Integer && !cast(*YalTypeInteger, lhs_type).is_signed;
        if is_unsigned_integer {
            return EmitUDiv(builder, lhs, rhs, value_name);
        } else {
            return EmitDiv(builder, lhs, rhs, value_name);
        }
    case .Percent;
        is_unsigned_integer := lhs_type.kind == .Integer && !cast(*YalTypeInteger, lhs_type).is_signed;
        if is_unsigned_integer {
            return EmitURem(builder, lhs, rhs, value_name);
        } else {
            return EmitRem(builder, lhs, rhs, value_name);
        }
    case;
        Panic(node, "Invalid or unhandled binary operator %", op);
    }

    Panic(node, "Invalid code path");

    return .{};
}

EmitBinary :: (builder : *YalIRBuilder, binop : *AstBinary, value_name : string) -> IROperand {
    if binop.op.kind == {
    case .PipePipe;
        original_block := GetCurrentBlock(builder);

        end_block := CreateIRBasicBlock(builder, "or.end");
        rhs_block := CreateIRBasicBlock(builder, "or.rhs");

        left_operand := EmitRValue(builder, binop.left, value_name);
        EmitJnz(builder, left_operand, IROpSymbol(end_block), IROpSymbol(rhs_block));

        InsertBlock(builder, rhs_block);
        SetCurrentBlock(builder, rhs_block);

        right_operand := EmitRValue(builder, binop.right, value_name);
        EmitJmp(builder, IROpSymbol(end_block));

        InsertBlock(builder, end_block);
        SetCurrentBlock(builder, end_block);

        phi_values := AllocArray(IRInstrPhi.Value, 2);
        phi_values[0] = .{block=IROpSymbol(original_block), value=IROpU8(1)};
        phi_values[1] = .{block=IROpSymbol(rhs_block), value=right_operand};

        return EmitPhi(builder, phi_values, "or");

    case .AmpersandAmpersand;
        original_block := GetCurrentBlock(builder);

        end_block := CreateIRBasicBlock(builder, "and.end");
        rhs_block := CreateIRBasicBlock(builder, "and.rhs");

        left_operand := EmitRValue(builder, binop.left, value_name);
        EmitJnz(builder, left_operand, IROpSymbol(rhs_block), IROpSymbol(end_block));

        InsertBlock(builder, rhs_block);
        SetCurrentBlock(builder, rhs_block);

        right_operand := EmitRValue(builder, binop.right, value_name);
        EmitJmp(builder, IROpSymbol(end_block));

        InsertBlock(builder, end_block);
        SetCurrentBlock(builder, end_block);

        phi_values := AllocArray(IRInstrPhi.Value, 2);
        phi_values[0] = .{block=IROpSymbol(original_block), value=IROpU8(0)};
        phi_values[1] = .{block=IROpSymbol(rhs_block), value=right_operand};

        return EmitPhi(builder, phi_values, "and");

    case;
        left_operand := EmitRValue(builder, binop.left, value_name);
        right_operand := EmitRValue(builder, binop.right, value_name);

        return EmitBinary(builder, binop, left_operand, right_operand, binop.left.type, binop.right.type, binop.op.kind, value_name);
    }
}

EmitUnary :: (builder : *YalIRBuilder, unary : *AstUnary, value_name : string) -> IROperand {
    if unary.op.kind == {
    case .Minus;
        expr_operand := EmitRValue(builder, unary.expr, value_name);
        return EmitNeg(builder, expr_operand, value_name);

    case .Bang;
        expr_operand := EmitRValue(builder, unary.expr, value_name);
        return EmitCmpEq(builder, expr_operand, .{type=expr_operand.type, value=0}, value_name);

    case .Caret;
        expr_operand := EmitRValue(builder, unary.expr, value_name);
        return EmitNot(builder, expr_operand, value_name);

    case .Ampersand;
        return EmitExpression(builder, unary.expr, value_name);

    case .DotStar;
        op := EmitExpression(builder, unary.expr, value_name);
        return EmitLoad(builder, op, .Pointer, value_name);

    case;
        Panic(unary, "Invalid or unhandled unary operator %", unary.op.kind);
    }

    Panic(unary, "Invalid code path");

    return .{};
}
