/* Aligned 32-bit copies avoid four byte load/store pairs in PSRAM-heavy codecs.
 * Byte fallback handles arbitrary alignment; no unaligned Xtensa word accesses.
 * Prevent loop-to-libcall rewriting from recursively calling these libc shims. */
#if defined(__GNUC__)
typedef uint32_t xz_alias_word __attribute__((__may_alias__));
#define XZ_MEMORY_FN __attribute__((optimize("no-tree-loop-distribute-patterns")))
#else
typedef uint32_t xz_alias_word;
#define XZ_MEMORY_FN
#endif
XZ_MEMORY_FN void *memcpy(void *dst,const void *src,size_t n)
{
    unsigned char *d=dst;const unsigned char *s=src;
    if(!(((uintptr_t)d|(uintptr_t)s)&3u)){
        xz_alias_word *dw=(xz_alias_word*)d;
        const xz_alias_word *sw=(const xz_alias_word*)s;
        while(n>=4){*dw++=*sw++;n-=4;}
        d=(unsigned char*)dw;s=(const unsigned char*)sw;
    }
    while(n--)*d++=*s++;
    return dst;
}
XZ_MEMORY_FN void *memset(void *dst,int value,size_t n)
{
    unsigned char *d=dst;unsigned char b=(unsigned char)value;
    while(n&&((uintptr_t)d&3u)){*d++=b;n--;}
    xz_alias_word *dw=(xz_alias_word*)d;
    uint32_t word=(uint32_t)b*0x01010101u;
    while(n>=4){*dw++=word;n-=4;}
    d=(unsigned char*)dw;
    while(n--)*d++=b;
    return dst;
}
#undef XZ_MEMORY_FN
