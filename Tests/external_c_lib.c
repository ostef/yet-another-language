// gcc external_c_lib.c -shared -o external_c_lib.so
// cl /nologo external_c_lib.c /link /DLL /OUT:external_c_lib.dll

#include <stdlib.h>
#include <stdio.h>

typedef struct {
    void *ptr;
} Bar;

typedef struct {
    unsigned char a;
    int b;
    Bar c;
} Foo;

#if defined(_WIN32)
#define DLL_EXPORT __declspec(dllexport)
#else
#define DLL_EXPORT
#endif

DLL_EXPORT
void TakesStringReturnsVoid(char *str) {
    printf("%p\n", str);
    printf("%s\n", str);
}

DLL_EXPORT
int TakesIntReturnsInt(int value) {
    return value;
}

DLL_EXPORT
int TakesStructReturnsInt(Foo foo) {
    return foo.b;
}

DLL_EXPORT
Foo TakesIntReturnsStruct(int value) {
    return (Foo){
        10,
        value,
        (Bar){NULL},
    };
}

DLL_EXPORT
Foo TakesStructReturnsStruct(Foo foo) {
    return foo;
}
