#include <stdint.h>

#define EXPORT __declspec(dllexport)

struct U64Pair
{
    uint64_t a;
    uint64_t b;
};

EXPORT void sysenc_decode_latin1(uint32_t *dst, const uint8_t *src,
    struct U64Pair *pair, uint64_t count);

void sysenc_decode_latin1(uint32_t *dst, const uint8_t *src,
    struct U64Pair *pair, uint64_t count)
{
    dst += pair->a;
    src += pair->b;

    for(uint64_t i = 0; i < count; ++i)
        dst[i] = src[i];

    pair->a += count;
    pair->b += count;
}
