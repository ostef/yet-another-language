# Yet-Another-Language
Systems programming language with manual memory management and arbitrary compile time execution.

> This project is a work in progress. While it hasn't been worked on in a while and might not get worked on for a while (if ever), it's not abandoned and stays in the back of my mind.
> 
> It is not in a usable state for anything serious.
> 
> I planned on keeping this private until I got a name for the language and a v0, but this might never happen

## General overview
The syntax is inspired by Zig, the philosophy and design by Jai. In this language, most things are first class (types, functions, modules, etc).
`const` in this language means the value is known at compile time (there is no immutability). `var` means the value is computed at runtime and has storage either on the stack or in global data (future optimizations potentially made by LLVM aside).

Here's a main function (names/modules are not final, Println does not exist yet with formatting, but you get the idea):
```zig
const std = #import "Std";

const main = func() {
    std.Println("Hello World!");

    var some_value = 10;
    std.Println("Here are % dimes for you.", some_value);
}
```

The important part of this language is the unorderliness of the code it compiles, as well as compile time execution (compile time execution is in reality sprinkles on top of the unorderliness part, which is the hard part). You've already seen an example of this in the code above with #import and modules, but it's not so obvious. Here's something more obvious:
```zig
const std = #import "Std";

const main = func() {
    std.Println("Hello World!");

    #insert "var some_value = 10;"

    std.Println("Here are % dimes for you.", some_value);
}
```
The last Println needs to resolve identifier `some_value` to typecheck, but for that we need to typecheck the `#insert`, take the string value and feed it back to the parser. This requires multiple compilation passes.

## How the compiler works
The compiler is currently single threaded and works in an indeterminate number of passes.
### Passes
A pass look like this:
```
while new_code_to_parse || total_unresolved_identifiers > 0 || resolved_at_least_one_identifier_last_pass:
1- parse all newly added files/code
2- create scopes and collect symbols for new code
3- create a dependency graph for new code
4- resolve as many identifiers as possible
5- flatten the dependency graph
6- iterate on each node in the flattened graph and typecheck
7- emit IR and bytecode for any pending compile time execution
8- interpret bytecode for compile time execution
```
When exiting the loop, we report any unresolved identifier, and if there are the compilation stops. Otherwise we generate IR then bytecode and interpret `main`.

### Scopes
Scopes form a tree like structure. Each scope contains a map of symbols that are declared inside said scope. It also contains a list of ordered statements. AST nodes such as blocks contain a list of statements too, but that list is purely syntactical. We cannot rely on that list to perform typechecking because compile time ifs and code insertion will want to add statements in an ordered manner, and these statements are syntactically "invisible".

### Dependency graph
Due to the unordered nature of the language (syntactically but more importantly semantically), when an unresolved identifier exists we assume it might be from code added later.
This means at every pass of compilation we need to advance as much as possible in each phase while keeping aside the nodes that are blocked (either by an unresolved identifier, or because they contain compile time execution/conditions).

For this reason we build a dependency graph. The graph is not a 1:1 mapping of AST nodes, especially expressions only create a dependency node for the whole expression tree (with exceptions), and the subexpressions are only collected in an array inside the dependency node, not as a subgraph.

This is roughly what a graph node looks like:
```jai
DependencyNode :: struct {
    ast_node : *AstNode;
    dependencies : [..]*DependencyNode;
    unresolved_identifiers : [..]UnresolvedIdentifier;

    subexpressions : [..]*AstNode; // In an expression, all child expressions in the tree are put in this array to be checked.
    last_checked_subexpressions := -1; // When checking subexpressions, it's possible we are blocked for some reason (usually unresolved identifier). This keeps track of where we left off
}

UnresolvedIdentifier :: struct {
    identifier : *AstIdentifier;
    name : string;
    look_in_scope : *Scope;
}
```

### Typechecking
As mentioned prior, typechecking is done by iterating on the flattened graph, and there is very little recursion going on. When typechecking expressions, we iterate over the list of subexpressions in the dependency node. When encountering a subexpression that we cannot typecheck (e.g. unresolved identifier, un-instantiated template), we keep track of the last subexpression we checked and bail out. The rest of the expression will be typechecked in one or more later compilation pass(es).
