// gcc external_c_variadic.c -shared -o external_c_variadic.so
// cl /nologo external_c_variadic.c /link /DLL /OUT:external_c_variadic.dll

#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>

#if defined(_WIN32)
#define DLL_EXPORT __declspec(dllexport)
#else
#define DLL_EXPORT
#endif

DLL_EXPORT
int Variadic(int num_params, ...) {
    va_list va;

    int result = 0;

    va_start(va, num_params);

    for (int i = 0; i < num_params; i += 1) {
        result += (int)va_arg(va, int);
    }

    va_end(va);

    return result;
}
