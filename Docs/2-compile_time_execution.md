# Compile time execution
In {LANG}, arbitrary compile time execution is at the core of the language.

## `#run`
You can execute any block of code at compile time using the `#run` directive:
```lang
const Sqrt2 = #run Sqrt(2); // Sqrt2 is a constant (known at compile-time) which value is the result of Sqrt(2): 1.41421356237
```

The only limitation for what code can be executed is code coming from a static library. If you want to use libraries at compile time they should be dynamic.
Provided you are not using any static libraries in your code, you can technically `#run` the entry point of your program.

> In general, there is no guarantee on the order of execution of multiple `#run`

There are also limitations on what types the compiler handles as the result of `#run` directives. Currently, only integral types such as boolean, integers, enums and floats as well as strings are handled, but in the future we will also handle arrays as well as structs.

The state of the interpreter for `#run` directives is kept the same in between invocations of `#run`. This means global variables exist and are usable by compile time code. However, modifying variables at compile time will not change the value that is emitted inside the final binary.

```lang
var x = 0;

#run {
    Std.Println("Block 1: %", x);
    x = 10;
}

#run {
    Std.Println("Block 2: %", x);
    x = 11;
}
```
Possible output:
```
Block 1: 0
Block 2: 10
```
Another possible output:
```
Block 2: 0
Block 1: 11
```

## `#insert`
`#insert` allows you to add a block of code in the form of a string. That block of code can of course be the result of a `#run`, which allows you to generate code based on other data:
```lang
const GenerateCosTable = func(name: string, size: int) -> string {
    var builder: Std.StringBuilder;

    Std.Appendln(&builder, "const % = float.[", name);
    for i: 0..<size {
        var x = (i / cast(float, size)) * 2 * Std.Pi;
        Std.Appendln(&builder, "    %,", Std.Cos(x));
    }
    Std.Appendln(&builder, "];");

    return Std.BuildString(&builder);
}

#insert #run GenerateCosTable("Cos_Table", 1000);
```
This will insert the following code:
```lang
const Cos_Table = float.[
    // 1000 values of Std.Cos(x) between 0 and 2*Pi
];
```
