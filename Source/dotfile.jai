AppendDotFile :: (builder : *StringBuilder, graph : *FlattenedDependencyGraph, dependency : Dependency) -> id : int {
    if ArrayFindFirst(graph.node_stack, dependency, (a, b) => a.node == b.node) != -1 {
        if dependency.flags & .Weak {
            visited := GetVisitedNode(graph, dependency.node);
            Assert(visited != null && visited.index >= 0);

            return visited.index;
        }

        ReportCircularDependencyErrorAndExit(graph, dependency.node.ast_node);
    }

    ArrayPush(*graph.node_stack, dependency);
    defer ArrayPop(*graph.node_stack);

    visited := GetVisitedNode(graph, dependency.node);
    if visited && visited.index >= 0 {
        return visited.index;
    }

    visited = MarkNodeAsVisited(graph, dependency.node);
    PushVisitedNode(graph, dependency.node);

    Append(builder, "  n% [", visited.index);

    // Put declarations in a different color
    if dependency.node.unresolved_identifiers.count > 0 {
        Append(builder, "style=filled fillcolor=red ");
    } else if dependency.node.ast_node.kind == .Declaration {
        Append(builder, "style=filled fillcolor=lightblue ");
    }

    Append(builder, "label=\"");

    token := TokenRangeToStringFirstLine(dependency.node.ast_node);
    for i : 0..token.count - 1 {
        if token[i] == "\"" {
            Append(builder, "\\");
        }

        StringBuilderAppendByte(builder, token[i]);
    }

    Append(builder, "\"");

    Appendln(builder, "];");

    for dependency.node.dependencies {
        dep_id := AppendDotFile(builder, graph, it);
        Append(builder, "  n% -> n%", visited.index, dep_id);
        if it.flags & .Weak {
            Append(builder, " [color=grey]");
        }
        Append(builder, "\n");
    }

    return visited.index;
}

AppendDotFile :: (builder : *StringBuilder, graph : *FlattenedDependencyGraph, scope : *Scope) {
    for scope.all_dependency_nodes {
        AppendDotFile(builder, graph, .{node=it});
    }

    for :Children scope {
        AppendDotFile(builder, graph, it);
    }
}

BuildDotFile :: (node : *AstNode) -> string {
    graph : FlattenedDependencyGraph;
    builder : StringBuilder;

    Appendln(*builder, "digraph G {");
    Appendln(*builder, "  node [shape=rect];");
    if node.dependency_node {
        AppendDotFile(*builder, *graph, .{node=node.dependency_node});
    }
    Appendln(*builder, "}");

    return StringBuilderBuild(*builder);
}

BuildDotFile :: (node : *DependencyNode) -> string {
    graph : FlattenedDependencyGraph;
    builder : StringBuilder;

    Appendln(*builder, "digraph G {");
    Appendln(*builder, "  node [shape=rect];");
    AppendDotFile(*builder, *graph, .{node=node});
    Appendln(*builder, "}");

    return StringBuilderBuild(*builder);
}

BuildDotFile :: (scope : *Scope, symbol : string) -> string {
    sym := ScopeLookup(scope, symbol);
    if sym {
        BuildDotFile(sym.decl);
    }

    return "";
}

BuildDotFile :: (scope : *Scope) -> string {
    graph : FlattenedDependencyGraph;
    builder : StringBuilder;

    Appendln(*builder, "digraph G {");
    Appendln(*builder, "  node [shape=rect];");
    AppendDotFile(*builder, *graph, scope);
    Appendln(*builder, "}");

    return StringBuilderBuild(*builder);
}

GenerateGraphImage :: (name : string, scope : *Scope) {
    dot := BuildDotFile(scope);
    File.write_entire_file(TPrint("%.gv", name), dot);
    result, dependencies_image := Process.run_command("dot", "-Tpng", TPrint("%.gv", name), capture_and_return_output=true);
    if result.type == .EXITED && result.exit_code == 0 {
        File.write_entire_file(TPrint("%.png", name), dependencies_image);
        Println("Generated graph image '%'", name);
    } else {
        Warning("Could not generate graph image '%'", name);
    }
}
