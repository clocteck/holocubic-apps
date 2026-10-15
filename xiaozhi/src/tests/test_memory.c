#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <assert.h>
#define memcpy xz_test_memcpy
#define memset xz_test_memset
#include "../main/xz_memory.inc"
#undef memcpy
#undef memset
int main(void)
{
    unsigned char src[1100],expected[1100],actual[1100];
    for(unsigned i=0;i<sizeof(src);i++)src[i]=(unsigned char)(i*37);
    for(unsigned a=0;a<8;a++)for(unsigned b=0;b<8;b++)for(unsigned n=0;n<=1024;n++){
        memset(actual,0xA5,sizeof(actual));memset(expected,0xA5,sizeof(expected));
        memcpy(expected+a,src+b,n);assert(xz_test_memcpy(actual+a,src+b,n)==actual+a);
        assert(!memcmp(actual,expected,sizeof(actual)));
        memset(actual,0xA5,sizeof(actual));memset(expected,0xA5,sizeof(expected));
        memset(expected+a,(int)n,n);assert(xz_test_memset(actual+a,(int)n,n)==actual+a);
        assert(!memcmp(actual,expected,sizeof(actual)));
    }
    puts("PSRAM memory shims: alignment / lengths / canaries PASS");
    return 0;
}
