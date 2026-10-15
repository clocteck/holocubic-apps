/* Opus allocations stay in PSRAM. No firmware libc heap objects cross the ABI. */
typedef struct { void *raw; size_t bytes; } xz_alloc_header;
void *malloc(size_t bytes)
{
    if(!s_host || !bytes || bytes>SIZE_MAX-16-sizeof(xz_alloc_header))return NULL;
    void *raw=s_host->heap.malloc(bytes+16+sizeof(xz_alloc_header),MODULE_HEAP_PSRAM|MODULE_HEAP_8BIT);
    if(!raw)return NULL;
    uintptr_t addr=((uintptr_t)raw+sizeof(xz_alloc_header)+15)&~(uintptr_t)15;
    xz_alloc_header *h=(xz_alloc_header*)addr-1;
    h->raw=raw;h->bytes=bytes;return (void*)addr;
}
void *calloc(size_t n,size_t bytes)
{
    if(bytes && n>SIZE_MAX/bytes)return NULL;
    void *p=malloc(n*bytes);if(p)memset(p,0,n*bytes);return p;
}
void free(void *p){if(p)s_host->heap.free(((xz_alloc_header*)p-1)->raw);}
void *realloc(void *p,size_t bytes)
{
    if(!p)return malloc(bytes);
    if(!bytes){free(p);return NULL;}
    xz_alloc_header *h=(xz_alloc_header*)p-1;
    void *q=malloc(bytes);
    if(q){memcpy(q,p,bytes<h->bytes?bytes:h->bytes);free(p);}return q;
}
