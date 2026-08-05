# Overview
{LANG} is a statically typed systems programming language inspired by C and Jai. In this chapter we will discuss the main features of {LANG} as well as lay out common programming concepts and how they exist in {LANG}.

## Variables and constants
Variables in {LANG} are declared using the `var` or `const` keyword. Contrary to many programming languages, {LANG} does not have a way to express mutability, and every variable is mutable. Constants in {LANG} are compile time known.
```lang
const main = func() {
    var x = "Hello World";
    Std.Println(x);

    x = "Goodbye";
    Std.Println(x);
}
```

In this program you can see that we declare the `main` function as `const`. Because `main` is `const`, a value **must** be assigned to it right away, and that value will never change. Inside the body of that function we declared the variable `x` and immediately assign the value `"Hello World"` to it. After printing the value of `x`, we set it to `"Goodbye"` and print it again.

### Inference and typing
In the program above, both the `main` function and `x` variable have their types inferred based on the value they are assigned to. Because {LANG} is a statically typed language, the type of `x` is set to `string` and can never change. In some cases though, such as declaring a variable without assigning a value to it, specifying the type manually is useful. To do so, use the following syntax: `var x: TYPE [= value];` or `const x: TYPE = value;`.

If we were to specify all types, the program we wrote above would look like this:
```lang
const main: type_of(func()) = func() {
    var x: string = "Hello World";
    Std.Println(x);

    x = "Goodbye";
    Std.Println(x);
}
```

### Declaration order
In {LANG}, the order of declaration is important in certain contexts.
For constants, the order never matters, so declaring `const A` then `const B` or `const B` then `const A` is semantically the same.
For variables however, the order of declaration matters except at toplevel (global variables). In function bodies for example, it is not possible to use a variable before it is declared. For example, the following code does not compile:
```lang
const main = func() {
    var x = y;
    var y = 5;
}
```
Compiler output:
```
Docs/test.yal:2:13, Error: Identifier 'y' is used before it is declared

 2 |     var x = y;
                 ~
Docs/test.yal:3:5, Info: Here is the declaration of 'y'

 3 |     var y = 5;
         ~~~~~~~~~
There were errors, exiting...
```

### Scoping
Named declarations are bound to a scope. Scopes are organised into a tree, with the root being referred to as the program scope. Inside a child scope, it is possible to re-declare names that were declared in the parent scope, shadowing the previous declaration. It is not possible however to declare the same name more than once inside a scope. Inside imperative scopes such as function bodies, it is possible to open a block of code with its own scope.

```lang
const Str = "Hello World";

const main = func() {
    var x = Str;

    {
        var x = 11;
        var y = x;
    }

    // y = 5;
}
```
If we uncomment the `y = 5` line, the compiler reports an error:
```
Docs/test.yal:10:5, Error: Unresolved identifier 'y'

 10 |     y = 2;
          ~
There were errors, exiting...
```

## Data types
The type system in {LANG} is simple. We've already seen that immutability cannot be expressed in this language, which reduces the type system's complexity, but we also do not have references or non-nullable pointers.

The primitive types are:
* void
* bool
* string
* type_id
Integer types:
* s8, u8
* s16, u16
* s32, u32
* s64, u64
* int, uint (aliases for s64 and u64)
Floating point types:
* f32
* f64
* float (alias for f32)

More complex data types:
* pointers: `*TYPE`
* static arrays: `[SIZE]TYPE`
* slices: `[]TYPE`
* dynamic arrays: `[..]TYPE`
* functions
* overload sets
* enums
* structs and unions

### Void
### Boolean type
### Strings
### Integer types
### Floating point types
### Pointers and arrays
### Enums
Enums
### Structs and unions
Structs are aggregate constructs that allow grouping variables together. They also act as a namespace, which means just about anything can be declared in a struct.
```lang
const Entity = struct {
    const Flags = enum {
        Inactive = 1 << 0;
        Invisible = 1 << 1;
    }

    var position: [3]float;
    var rotation: [3]float;
    var flags: Flags;
}

const main = func() {
    var entity: Entity;
    entity.position = .[1, 2, 3];
    entity.flags = .Invisible;
}
```

## Functions
We've used functions previously, we might as well give them a real introduction. Functions in this language are first class, meaning you can assign a variable to a function written inline.

Functions have a list of parameters and a return type, which if not specified defaults to `void`. A parameter can optionally be assigned a value, in which case when calling the function it is optional to specify this parameter. When calling a function, it is also possible to pass arguments by specifying their name, in which case they do not have to be provided in the declaration order.

Examples:
```lang
const Foo = func(a: int, b: string) -> int {
    Std.Println(b);
    return a * 2;
}

const Bar = func(a: int, b=10, c="Hello World") -> int {
    Std.Println(c);
    return a * b;
}

const main = func() {
    var a = Foo(10, "Cowabunga");
    Std.Println("%", a);

    var b = Bar(3, c="Hello");
    Std.Println("%", b);
}
```
Output:
```
Cowabunga
20
Hello
30
```

* `main` is a function with no parameter and of `void` result type
* `Foo` is a function with two parameters, the first of type `int` and the second of type `string`. It returns an `int`
* `Bar` is a function with three parameters, the first of type `int`, the second is optional and of type `int` and the third is optional and of type `string`. It returns an `int`

When calling `Bar`, the parameter `c` is specified using its name and `b` is kept with the default value because it is not specified.

## Control flow
{LANG} provides the basic control flow constructs anyone expects to find in a programming language in the form of `if` statements, `while` and `for` loops.

### If and else statements
If evaluates the condition, which must be of type bool. If true it executes the code inside its body. Otherwise, if an else statement is present it will evaluate the else's body, which can be another if statement:
```lang
const main = func() {
    var x = 10;
    if x == 10 {
        Std.Println("x is 10");
    } else if x > 10 {
        Std.Println("x is above 10");
    } else {
        Std.Println("x is below 10");
    }
}
```
Output:
```
x is 10
```

### While loops
While will execute the code inside its body as long as the specified condition is met:
```lang
const main = func() {
    var i = 0;
    while i < 10 {
        Std.Println("Loop");
        i += 1;
    }
}
```
Output:
```
Loop
Loop
Loop
Loop
Loop
Loop
Loop
Loop
Loop
Loop
```

### For loops
For loops allow you to express iteration more safely and conveniently than while loops, because the increment statement does not have to be explicitly written. There are many subtle features around for loops, such as declaring or not the index variable, specifying whether the range of iteration is inclusive or not and specifying whether the for loop increments or decrements the index variable:
```lang
const main = func() {
    // This loop iterates forward from [0; 10[ (exclusive) and declares the index only in the for scope
    Std.Print("Loop 1:");
    for i: 0..<10 {
        Std.Print("  %", i);
    }
    Std.Print("\n");

    // This loop iterates forward from [0; 10] (inclusive) and declares the index only in the for scope
    Std.Print("Loop 2:");
    for i: 0..=10 {
        Std.Print(" %", i);
    }
    Std.Print("\n");

    // This loop iterates backwards from [10; 0] (inclusive) and declares the index only in the for scope
    Std.Print("Loop 3:");
    for i: 0=..10 {
        Std.Print(" %", i);
    }
    Std.Print("\n");

    // This loop iterates backwards from [10; 0[ (exclusive) and declares the index only in the for scope
    Std.Print("Loop 4:");
    for i: 0>..10 {
        Std.Print(" %", i);
    }
    Std.Print("\n");

    var i: int;

    // This loop does not declare the index, and instead uses `i` declared above
    Std.Print("Loop 5:");
    for i= 0..<10 {
        Std.Print(" %", i);
    }
    Std.Print("\n");

    Std.Println("After loop 5, i is %", i); // Will print 10
}
```
Output:
```
Loop 1: 0  1  2  3  4  5  6  7  8  9
Loop 2: 0  1  2  3  4  5  6  7  8  9  10
Loop 3: 10  9  8  7  6  5  4  3  2  1  0
Loop 4: 10  9  8  7  6  5  4  3  2  1
Loop 5: 0  1  2  3  4  5  6  7  8  9
After loop 5, i is 10
```

## Entry point
When compiling an executable, {LANG} expects an entry point do be defined. That entry point must be called `main` and must have one of the following signatures:
* `func()`
* `func(args: []string)`
* `func() -> exit_code: s32`
* `func(args: []string) -> exit_code: s32`
