// ======= Yal typedefs =======

typedef          char      s8;
typedef unsigned char      u8;
typedef          short     s16;
typedef unsigned short     u16;
typedef          int       s32;
typedef unsigned int       u32;
typedef          long long s64;
typedef unsigned long long u64;
typedef float  f32;
typedef double f64;
typedef u8 bool;

typedef struct Yal__String
{
    s64 count;
    u8 *data;
} Yal__String;

typedef struct Yal__Slice
{
    s64 count;
    void *data;
} Yal__Slice;

typedef void *(*Yal__AllocatorProc) (s64, void *, void *);

typedef struct Yal__Allocator
{
    void *data;
    Yal__AllocatorProc proc_ptr;
} Yal__Allocator;

typedef struct Yal__DynamicArray
{
    s64 count;
    void *data;
    s64 capacity;
    Yal__Allocator allocator;
} Yal__DynamicArray;

// ======= Forward declarations =======

/* omitting const Pi := 3.1415926 */
s64* foo[3][2][1];
f32 ToRads (f32 x);
f32 ToDegs (f32 x);
f32 Min (f32 a, f32 b);
f32 Max (f32 a, f32 b);
f32 Abs (f32 x);
f32 Sign (f32 x);

// ======= Procedure definitions =======

f32 ToRads (f32 x)
{
    return x * 3.1415926f / 180.0000000f;
}

f32 ToDegs (f32 x)
{
    return x * 180.0000000f / 3.1415926f;
}

f32 Min (f32 a, f32 b)
{
    if (a < b)
        return a;
    return b;
}

f32 Max (f32 a, f32 b)
{
    if (a > b)
        return a;
    return b;
}

f32 Abs (f32 x)
{
    if (x < 0.0000000f)
        return -x;
    return x;
}

f32 Sign (f32 x)
{
    if (x < 0.0000000f)
        return -1.0000000f;
    return 1.0000000f;
}
