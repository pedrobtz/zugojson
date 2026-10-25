#pragma once
#include <stdint.h>
typedef struct gs_stack gs_stack;
#pragma pack(push, 1)
typedef struct { uint8_t *base; int64_t len; } gs_rhdr;
typedef struct { gs_rhdr *hdr; gs_stack *stk; } gs_rref;
typedef struct { gs_rhdr *hdr; gs_stack *stk; gs_rhdr *fl; gs_stack *flstk; } gs_pref;

typedef struct { double e[23]; } a23_f64;

typedef struct { uint8_t *data; int64_t len; } sl_u8;

typedef struct { uint64_t e[20]; } a20_u64;

typedef struct { uint64_t e[28]; } a28_u64;

typedef struct { uint64_t e[1392]; } a1392_u64;

typedef struct { uint8_t e[20]; } a20_u8;

typedef struct json_Number_g4 json_Number_g4;
struct json_Number_g4 {
    double value_g;
    int64_t int_g;
    uint8_t is_int_g;
    int64_t end_g;
};

enum {
    Json_g_Null_g_k = 0,
    Json_g_Bool_g_k = 1,
    Json_g_Num_g_k = 2,
    Json_g_Str_g_k = 3,
    Json_g_Arr_g_k = 4,
    Json_g_Obj_g_k = 5,
};

typedef struct { double e[1]; } a1_f64;

typedef struct { uint8_t len; uint8_t e[32]; } l32_u8;

typedef struct { uint8_t e[17]; } a17_u8;

typedef struct { uint8_t len; uint8_t e[40]; } l40_u8;

typedef struct { uint32_t *data; int64_t len; } sl_u32;

typedef struct Json_g_Bool_p Json_g_Bool_p;
struct Json_g_Bool_p {
    uint8_t v_g;
};

typedef struct Json_g_Num_p Json_g_Num_p;
struct Json_g_Num_p {
    double v_g;
};

typedef struct { int64_t e[3]; } a3_i64;

typedef struct ByteSet_g ByteSet_g;
typedef struct { uint8_t e[256]; } a256_b;

typedef struct { uint8_t e[3]; } a3_u8;

typedef struct { uint8_t e[16]; } a16_u8;

struct ByteSet_g {
    a256_b members_g;
    uint8_t kind_g;
    uint8_t invert_g;
    a3_u8 bytes_g;
    a16_u8 lo_g;
    a16_u8 hi_g;
};

#pragma pack(pop)

#ifdef __cplusplus
extern "C" {
#endif
void goose_init(int argc, char **argv);
const uint8_t * zugojson_format(sl_u8 gs_export_arg0, int64_t gs_export_arg1, int64_t *gs_export_len);
const uint8_t * zugojson_check(sl_u8 gs_export_arg0_2, int64_t *gs_export_len_2);
int64_t zugojson_index_probe(int64_t gs_export_arg0_3);
#ifdef __cplusplus
}
#endif
