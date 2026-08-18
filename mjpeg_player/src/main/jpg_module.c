#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>

#ifndef JPG_USE_ESP_NEW_JPEG
#define JPG_USE_ESP_NEW_JPEG 1
#endif
#ifndef JPG_ROM_SCALE
#define JPG_ROM_SCALE 0
#endif

#if JPG_USE_ESP_NEW_JPEG
#include "esp_jpeg_dec.h"
#endif
#include "module_abi.h"

#if defined(CONFIG_JD_USE_ROM) && CONFIG_JD_USE_ROM
#include "esp32s3/rom/tjpgd.h"
#endif

#define JPG_MODULE_EXPORT __attribute__((visibility("default"), used))
#define JPG_VERSION "0.2.0"
#define JPG_MODULE_NAME "jpg"
#define JPG_MODULE_DESCRIPTION "JPEG to RGB565 decoder for Lua LVGL canvas"
#define JPG_DMA_ROWS 24u
#define JPG_DMA_MIN_ROWS 1u
#define JPG_DMA_BUFFERS 2u
#define JPG_ASYNC_RGB_BUFFERS 2u
#define JPG_IMAGE_POOL_SLOTS 1u
#define JPG_IMAGE_POOL_HOLD_FRAMES 3u
#define JPG_IMAGE_POOL_WIDTH 320u
#define JPG_IMAGE_POOL_HEIGHT 240u
#define JPG_IMAGE_POOL_BYTES (JPG_IMAGE_POOL_WIDTH * JPG_IMAGE_POOL_HEIGHT * 2u)
#define JPG_IMAGE_POOL_GUARD_BYTES 32u
#define JPG_IMAGE_POOL_ALLOC_BYTES (JPG_IMAGE_POOL_BYTES + (JPG_IMAGE_POOL_GUARD_BYTES * 2u))
#define JPG_DECODE_TASK_STACK_BYTES (8u * 1024u)
#define JPG_ENABLE_LVGL_USERDATA 1
#define JPG_LV_IMG_CF_TRUE_COLOR 4u
#define JPG_CLOSE_NEW_DECODER_ON_DESTROY 0

#define JPG_IMAGE_SLOT_FREE 0u
#define JPG_IMAGE_SLOT_DECODING 1u
#define JPG_IMAGE_SLOT_READY 2u
#define JPG_IMAGE_SLOT_HELD 3u

#ifndef MALLOC_CAP_EXEC
#define MALLOC_CAP_EXEC (1u << 0)
#endif
#ifndef MALLOC_CAP_32BIT
#define MALLOC_CAP_32BIT (1u << 1)
#endif
#ifndef MALLOC_CAP_8BIT
#define MALLOC_CAP_8BIT (1u << 2)
#endif
#ifndef MALLOC_CAP_DMA
#define MALLOC_CAP_DMA (1u << 3)
#endif
#ifndef MALLOC_CAP_SPIRAM
#define MALLOC_CAP_SPIRAM (1u << 10)
#endif
#ifndef MALLOC_CAP_INTERNAL
#define MALLOC_CAP_INTERNAL (1u << 11)
#endif
#ifndef MALLOC_CAP_DEFAULT
#define MALLOC_CAP_DEFAULT (1u << 12)
#endif

typedef struct jpg_lv_img_header_t {
    uint32_t cf : 5;
    uint32_t always_zero : 3;
    uint32_t reserved : 2;
    uint32_t w : 11;
    uint32_t h : 11;
} jpg_lv_img_header_t;

typedef struct jpg_lv_img_dsc_t {
    jpg_lv_img_header_t header;
    uint32_t data_size;
    const uint8_t *data;
} jpg_lv_img_dsc_t;

#if defined(CONFIG_JD_USE_ROM) && CONFIG_JD_USE_ROM
#define JPG_WORK_BUFFER_SIZE 4096u
#elif defined(CONFIG_JD_FASTDECODE) && (CONFIG_JD_FASTDECODE == 2)
#define JPG_WORK_BUFFER_SIZE 65536u
#else
#define JPG_WORK_BUFFER_SIZE 4096u
#endif

typedef struct jpg_instance_t {
    module_host_api_v2 host;
    lua_State *lua_state;
    uint8_t *jpeg;
    size_t jpeg_cap;
    size_t jpeg_len;
    uint8_t *rgb565_raw;
    uint8_t *rgb565;
    size_t rgb565_cap;
    uint8_t *work;
    size_t work_cap;
    uint8_t *dma[JPG_DMA_BUFFERS];
    size_t dma_cap[JPG_DMA_BUFFERS];
    uint8_t *async_pending_jpeg;
    size_t async_pending_jpeg_cap;
    size_t async_pending_jpeg_len;
    uint8_t *async_decode_jpeg;
    size_t async_decode_jpeg_cap;
    uint8_t *async_rgb_raw[JPG_ASYNC_RGB_BUFFERS];
    uint8_t *async_rgb[JPG_ASYNC_RGB_BUFFERS];
    size_t async_rgb_cap[JPG_ASYNC_RGB_BUFFERS];
    uint32_t async_rgb_len[JPG_ASYNC_RGB_BUFFERS];
    uint32_t async_rgb_frame_id[JPG_ASYNC_RGB_BUFFERS];
    uint32_t async_rgb_input_bytes[JPG_ASYNC_RGB_BUFFERS];
    jpg_lv_img_dsc_t *image_pool_dsc[JPG_IMAGE_POOL_SLOTS];
    uint8_t *image_pool_raw[JPG_IMAGE_POOL_SLOTS];
    uint8_t *image_pool_pixels[JPG_IMAGE_POOL_SLOTS];
    int image_pool_ref[JPG_IMAGE_POOL_SLOTS];
    uint32_t image_pool_next;
    uint32_t image_pool_corrupt_count;
    uint8_t image_pool_state[JPG_IMAGE_POOL_SLOTS];
    uint32_t image_pool_frame_id[JPG_IMAGE_POOL_SLOTS];
    uint32_t image_pool_input_bytes[JPG_IMAGE_POOL_SLOTS];
    uint32_t image_pool_output_bytes[JPG_IMAGE_POOL_SLOTS];
    uint32_t image_pool_display_seq[JPG_IMAGE_POOL_SLOTS];
    uint32_t image_pool_present_seq;
    uint32_t image_pool_no_slot_count;
    uint32_t image_pool_forced_reuse_count;
    uint8_t image_pool_ready;
    struct jpg_aligned_alloc_t *aligned_allocs;
#if JPG_USE_ESP_NEW_JPEG
    jpeg_dec_handle_t new_dec;
#else
    void *new_dec;
#endif
    uint8_t new_dec_swap;
    void *display_surface;
    uint8_t display_write_active;
    uint32_t decode_count;
    uint32_t last_decode_ms;
    uint32_t last_decode_us;
    uint32_t last_push_ms;
    uint32_t last_push_us;
    uint32_t last_width;
    uint32_t last_height;
    uint32_t last_output_bytes;
    uint32_t last_chunk_us;
    uint32_t chunk_count;
    uint8_t swap_color_bytes;
    volatile int async_lock;
    void *async_task;
    volatile uint8_t async_running;
    volatile uint8_t async_stop;
    volatile int async_ready_index;
    volatile int async_presenting_index;
    volatile int async_decode_index;
    volatile int image_pool_current_slot;
    volatile uint32_t async_pending_seq;
    volatile uint32_t async_consumed_seq;
    uint32_t async_pending_frame_id;
    uint32_t async_pending_overwrites;
    uint32_t async_submit_count;
    uint32_t async_decode_count;
    uint32_t async_present_count;
    uint32_t async_error_count;
    uint32_t async_no_buffer_count;
    uint32_t async_ready_overwrites;
    uint32_t async_last_ready_frame_id;
    uint32_t async_last_present_frame_id;
    uint32_t async_last_input_bytes;
    uint32_t async_last_output_bytes;
} jpg_instance_t;

typedef struct jpg_decode_ctx_t {
    jpg_instance_t *inst;
    const uint8_t *input;
    size_t input_len;
    uint8_t *output;
    size_t output_cap;
    size_t read;
    uint8_t swap;
    uint8_t scale_factor;
} jpg_decode_ctx_t;

typedef struct jpg_aligned_alloc_t {
    void *aligned;
    void *raw;
    struct jpg_aligned_alloc_t *next;
} jpg_aligned_alloc_t;

static jpg_instance_t *s_instance;

#define JPG_LOCAL_SYMBOL __attribute__((visibility("hidden")))

static uint64_t jpg_now_us(const module_host_api_v2 *host);
static int jpg_present_rgb565(jpg_instance_t *inst, const uint8_t *rgb565, uint32_t width, uint32_t height);

#if defined(CONFIG_JD_USE_ROM) && CONFIG_JD_USE_ROM
static UINT jpg_rom_input_cb(JDEC *jd, BYTE *buff, UINT nbyte);
static UINT jpg_rom_output_cb(JDEC *jd, void *bitmap, JRECT *rect);
#endif

#if defined(CONFIG_JD_USE_ROM) && CONFIG_JD_USE_ROM
typedef JRESULT (*jpg_rom_jd_prepare_fn)(JDEC *, UINT (*)(JDEC *, BYTE *, UINT), void *, UINT, void *);
typedef JRESULT (*jpg_rom_jd_decomp_fn)(JDEC *, UINT (*)(JDEC *, void *, JRECT *), BYTE);

JPG_LOCAL_SYMBOL __attribute__((noinline)) JRESULT jd_prepare(JDEC *jd,
                                    UINT (*infunc)(JDEC *, BYTE *, UINT),
                                    void *pool,
                                    UINT sz_pool,
                                    void *dev)
{
    volatile uintptr_t entry = (uintptr_t)0x40000858u;
    const jpg_rom_jd_prepare_fn fn = (jpg_rom_jd_prepare_fn)entry;
    return fn(jd, infunc, pool, sz_pool, dev);
}

JPG_LOCAL_SYMBOL __attribute__((noinline)) JRESULT jd_decomp(JDEC *jd, UINT (*outfunc)(JDEC *, void *, JRECT *), BYTE scale)
{
    volatile uintptr_t entry = (uintptr_t)0x40000864u;
    const jpg_rom_jd_decomp_fn fn = (jpg_rom_jd_decomp_fn)entry;
    return fn(jd, outfunc, scale);
}
#endif

JPG_LOCAL_SYMBOL void esp_log_write(int level, const char *tag, const char *format, ...)
{
    (void)level;
    (void)tag;
    (void)format;
}

JPG_LOCAL_SYMBOL void esp_log_writev(int level, const char *tag, const char *format, void *args)
{
    (void)level;
    (void)tag;
    (void)format;
    (void)args;
}

JPG_LOCAL_SYMBOL uint32_t esp_log_timestamp(void)
{
    jpg_instance_t *inst = s_instance;
    if (inst && inst->host.time.millis) {
        return inst->host.time.millis();
    }
    return 0;
}

JPG_LOCAL_SYMBOL uint32_t esp_log_early_timestamp(void)
{
    return esp_log_timestamp();
}

JPG_LOCAL_SYMBOL char *esp_log_system_timestamp(void)
{
    return "";
}

JPG_LOCAL_SYMBOL void *memset(void *dst, int value, size_t len)
{
    uint8_t *p = (uint8_t *)dst;
    while (len--) {
        *p++ = (uint8_t)value;
    }
    return dst;
}

JPG_LOCAL_SYMBOL void *memcpy(void *dst, const void *src, size_t len)
{
    uint8_t *d = (uint8_t *)dst;
    const uint8_t *s = (const uint8_t *)src;
    while (len--) {
        *d++ = *s++;
    }
    return dst;
}

JPG_LOCAL_SYMBOL void *memmove(void *dst, const void *src, size_t len)
{
    uint8_t *d = (uint8_t *)dst;
    const uint8_t *s = (const uint8_t *)src;
    if (d == s || len == 0) {
        return dst;
    }
    if (d < s) {
        while (len--) {
            *d++ = *s++;
        }
    } else {
        d += len;
        s += len;
        while (len--) {
            *--d = *--s;
        }
    }
    return dst;
}

static uint32_t jpg_module_caps_from_idf(uint32_t caps)
{
    uint32_t out = 0;

    if (caps == 0 || (caps & MALLOC_CAP_DEFAULT)) {
        return MODULE_HEAP_DEFAULT;
    }
    if (caps & MALLOC_CAP_INTERNAL) {
        out |= MODULE_HEAP_INTERNAL;
    }
    if (caps & MALLOC_CAP_SPIRAM) {
        out |= MODULE_HEAP_PSRAM;
    }
    if (caps & MALLOC_CAP_DMA) {
        out |= MODULE_HEAP_DMA;
    }
    if (caps & MALLOC_CAP_EXEC) {
        out |= MODULE_HEAP_EXEC;
    }
    if (caps & MALLOC_CAP_8BIT) {
        out |= MODULE_HEAP_8BIT;
    }
    if (caps & MALLOC_CAP_32BIT) {
        out |= MODULE_HEAP_32BIT;
    }
    return out ? out : MODULE_HEAP_DEFAULT;
}

JPG_LOCAL_SYMBOL void *heap_caps_malloc(size_t size, uint32_t caps)
{
    jpg_instance_t *inst = s_instance;
    if (!inst || !inst->host.heap.malloc || size == 0) {
        return NULL;
    }
    return inst->host.heap.malloc(size, jpg_module_caps_from_idf(caps));
}

JPG_LOCAL_SYMBOL void *malloc(size_t size)
{
    return heap_caps_malloc(size, MALLOC_CAP_DEFAULT);
}

static void *jpg_heap_calloc_caps(size_t n, size_t size, uint32_t caps)
{
    jpg_instance_t *inst = s_instance;
    size_t total = 0;
    void *ptr = NULL;
    if (!inst || !inst->host.heap.calloc || n == 0 || size == 0) {
        return NULL;
    }
    if (n > ((size_t)-1) / size) {
        return NULL;
    }
    total = n * size;
    ptr = inst->host.heap.calloc(1, total, jpg_module_caps_from_idf(caps));
    return ptr;
}

JPG_LOCAL_SYMBOL void *calloc(size_t n, size_t size)
{
    return jpg_heap_calloc_caps(n, size, MALLOC_CAP_DEFAULT);
}

JPG_LOCAL_SYMBOL void *heap_caps_calloc(size_t n, size_t size, uint32_t caps)
{
    return jpg_heap_calloc_caps(n, size, caps);
}

JPG_LOCAL_SYMBOL void *heap_caps_calloc_prefer(size_t n, size_t size, size_t num, ...)
{
    void *ptr = NULL;
    va_list ap;

    va_start(ap, num);
    for (size_t i = 0; i < num; i++) {
        uint32_t caps = va_arg(ap, uint32_t);
        ptr = jpg_heap_calloc_caps(n, size, caps);
        if (ptr) {
            break;
        }
    }
    va_end(ap);
    return ptr ? ptr : calloc(n, size);
}

JPG_LOCAL_SYMBOL void *heap_caps_aligned_calloc(size_t alignment, size_t n, size_t size, uint32_t caps)
{
    jpg_instance_t *inst = s_instance;
    jpg_aligned_alloc_t *node = NULL;
    uintptr_t raw_addr = 0;
    uintptr_t aligned_addr = 0;
    size_t total = 0;
    size_t alloc_size = 0;
    void *raw = NULL;

    (void)caps;
    if (!inst || !inst->host.heap.calloc || !inst->host.heap.malloc || alignment == 0 || n == 0 || size == 0) {
        return NULL;
    }
    if ((alignment & (alignment - 1u)) != 0) {
        return NULL;
    }
    if (n > ((size_t)-1) / size) {
        return NULL;
    }
    total = n * size;
    if (total > ((size_t)-1) - alignment) {
        return NULL;
    }
    alloc_size = total + alignment;
    raw = inst->host.heap.calloc(1, alloc_size, jpg_module_caps_from_idf(caps));
    if (!raw) {
        return NULL;
    }
    node = (jpg_aligned_alloc_t *)inst->host.heap.malloc(sizeof(jpg_aligned_alloc_t),
                                                        MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT);
    if (!node) {
        inst->host.heap.free(raw);
        return NULL;
    }
    raw_addr = (uintptr_t)raw;
    aligned_addr = (raw_addr + (uintptr_t)alignment - 1u) & ~((uintptr_t)alignment - 1u);
    node->aligned = (void *)aligned_addr;
    node->raw = raw;
    node->next = inst->aligned_allocs;
    inst->aligned_allocs = node;
    return node->aligned;
}

JPG_LOCAL_SYMBOL void *realloc(void *ptr, size_t size)
{
    jpg_instance_t *inst = s_instance;
    if (!inst || !inst->host.heap.realloc) {
        return NULL;
    }
    return inst->host.heap.realloc(ptr, size, MODULE_HEAP_DEFAULT);
}

JPG_LOCAL_SYMBOL void *heap_caps_realloc(void *ptr, size_t size, uint32_t caps)
{
    jpg_instance_t *inst = s_instance;
    if (!inst || !inst->host.heap.realloc) {
        return NULL;
    }
    if (size == 0) {
        if (ptr && inst->host.heap.free) {
            inst->host.heap.free(ptr);
        }
        return NULL;
    }
    return inst->host.heap.realloc(ptr, size, jpg_module_caps_from_idf(caps));
}

JPG_LOCAL_SYMBOL void heap_caps_free(void *ptr)
{
    jpg_instance_t *inst = s_instance;
    jpg_aligned_alloc_t *prev = NULL;
    jpg_aligned_alloc_t *node = NULL;

    if (!inst || !inst->host.heap.free || !ptr) {
        return;
    }
    node = inst->aligned_allocs;
    while (node) {
        if (node->aligned == ptr) {
            if (prev) {
                prev->next = node->next;
            } else {
                inst->aligned_allocs = node->next;
            }
            inst->host.heap.free(node->raw);
            inst->host.heap.free(node);
            return;
        }
        prev = node;
        node = node->next;
    }
    inst->host.heap.free(ptr);
}

JPG_LOCAL_SYMBOL void free(void *ptr)
{
    heap_caps_free(ptr);
}

JPG_LOCAL_SYMBOL void __assert_func(const char *file, int line, const char *func, const char *expr)
{
    (void)file;
    (void)line;
    (void)func;
    (void)expr;
    for (;;) {
    }
}

static const module_manifest_t s_manifest = {
    MODULE_MANIFEST_MAGIC,
    MODULE_ABI_VERSION,
    sizeof(module_manifest_t),
    JPG_MODULE_NAME,
    JPG_VERSION,
    JPG_MODULE_DESCRIPTION,
    0,
    MODULE_BOOTSTRAP_ABI_VERSION,
};

static void zero_bytes(void *ptr, size_t len)
{
    uint8_t *p = (uint8_t *)ptr;
    if (!p) {
        return;
    }
    while (len--) {
        *p++ = 0;
    }
}

static void copy_bytes(void *dst, const void *src, size_t len)
{
    uint8_t *d = (uint8_t *)dst;
    const uint8_t *s = (const uint8_t *)src;
    if (!d || !s) {
        return;
    }
    while (len--) {
        *d++ = *s++;
    }
}

static void jpg_async_lock(jpg_instance_t *inst)
{
    if (!inst) {
        return;
    }
    while (__sync_lock_test_and_set(&inst->async_lock, 1)) {
        if (inst->host.task.yield) {
            inst->host.task.yield();
        }
    }
}

static void jpg_async_unlock(jpg_instance_t *inst)
{
    if (!inst) {
        return;
    }
    __sync_lock_release(&inst->async_lock);
}

static int jpg_display_release(jpg_instance_t *inst)
{
    int ok = 1;
    if (!inst || !inst->display_surface) {
        return 1;
    }
    if (inst->display_write_active && inst->host.display.endWrite) {
        if (inst->host.display.endWrite(inst->display_surface) != MODULE_OK) {
            ok = 0;
        }
        inst->display_write_active = 0;
    }
    if (!inst->host.display.release || inst->host.display.release(inst->display_surface) != MODULE_OK) {
        ok = 0;
    } else {
        inst->display_surface = NULL;
    }
    return ok;
}

static int jpg_display_acquire(jpg_instance_t *inst)
{
    module_display_desc_t desc;

    if (!inst) {
        return 0;
    }
    if (inst->display_surface) {
        return 1;
    }
    if (!inst->host.display.acquire || !inst->host.display.startWrite || !inst->host.display.endWrite) {
        return 0;
    }
    if (!inst->host.display.pushImageDMA &&
        (!inst->host.display.setAddrWindow || !inst->host.display.pushPixelsDMA)) {
        return 0;
    }

    zero_bytes(&desc, sizeof(desc));
    desc.size = sizeof(desc);
    desc.width = 320;
    desc.height = 240;
    desc.pixel_format = MODULE_PIXEL_RGB565;
    desc.flags = 0;

    if (inst->host.display.acquire("desktop_mirror", &desc, &inst->display_surface) != MODULE_OK ||
        !inst->display_surface) {
        inst->display_surface = NULL;
        return 0;
    }
    inst->display_write_active = 0;
    return 1;
}

static void *jpg_malloc(jpg_instance_t *inst, size_t size, uint32_t caps)
{
    void *ptr = NULL;
    if (!inst || !inst->host.heap.malloc || size == 0) {
        return NULL;
    }
    ptr = inst->host.heap.malloc(size, caps);
    if (!ptr && (caps & MODULE_HEAP_PSRAM)) {
        ptr = inst->host.heap.malloc(size, MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT);
    }
    return ptr;
}

static int jpg_reserve(jpg_instance_t *inst, uint8_t **buf, size_t *cap, size_t need, uint32_t caps)
{
    uint8_t *next = NULL;
    if (!inst || !buf || !cap) {
        return 0;
    }
    if (*cap >= need && *buf) {
        return 1;
    }
    next = (uint8_t *)jpg_malloc(inst, need, caps);
    if (!next) {
        return 0;
    }
    if (*buf) {
        inst->host.heap.free(*buf);
    }
    *buf = next;
    *cap = need;
    return 1;
}

static int jpg_reserve_aligned(jpg_instance_t *inst,
                               uint8_t **raw,
                               uint8_t **buf,
                               size_t *cap,
                               size_t need,
                               size_t align,
                               uint32_t caps)
{
    uintptr_t addr = 0;
    uint8_t *next = NULL;
    uint8_t *aligned = NULL;

    if (!inst || !raw || !buf || !cap || align == 0) {
        return 0;
    }
    if (*cap >= need && *buf && (((uintptr_t)*buf & (uintptr_t)(align - 1u)) == 0u)) {
        return 1;
    }
    next = (uint8_t *)jpg_malloc(inst, need + align - 1u, caps);
    if (!next) {
        return 0;
    }
    addr = ((uintptr_t)next + (uintptr_t)(align - 1u)) & ~((uintptr_t)(align - 1u));
    aligned = (uint8_t *)addr;
    if (*raw) {
        inst->host.heap.free(*raw);
    }
    *raw = next;
    *buf = aligned;
    *cap = need;
    return 1;
}

static void jpg_new_decoder_close(jpg_instance_t *inst)
{
#if JPG_USE_ESP_NEW_JPEG
    if (inst && inst->new_dec) {
        (void)jpeg_dec_close(inst->new_dec);
        inst->new_dec = NULL;
    }
#else
    (void)inst;
#endif
}

static int jpg_new_decoder_open(jpg_instance_t *inst, int swap)
{
#if JPG_USE_ESP_NEW_JPEG
    jpeg_dec_config_t config = DEFAULT_JPEG_DEC_CONFIG();
    if (!inst) {
        return 0;
    }
    if (inst->new_dec && inst->new_dec_swap == (uint8_t)(swap ? 1 : 0)) {
        return 1;
    }
    jpg_new_decoder_close(inst);
    config.output_type = swap ? JPEG_PIXEL_FORMAT_RGB565_BE : JPEG_PIXEL_FORMAT_RGB565_LE;
    config.rotate = JPEG_ROTATE_0D;
    config.block_enable = false;
    if (jpeg_dec_open(&config, &inst->new_dec) != JPEG_ERR_OK || !inst->new_dec) {
        inst->new_dec = NULL;
        return 0;
    }
    inst->new_dec_swap = swap ? 1 : 0;
    return 1;
#else
    (void)inst;
    (void)swap;
    return 0;
#endif
}

static int jpg_decode_into(jpg_instance_t *inst,
                           const uint8_t *jpeg,
                           size_t jpeg_len,
                           uint8_t *rgb565,
                           size_t rgb565_cap,
                           int swap,
                           uint32_t *out_w,
                           uint32_t *out_h,
                           uint32_t *out_len,
                           uint32_t *out_decode_us)
{
#if JPG_USE_ESP_NEW_JPEG
    jpeg_dec_io_t io;
    jpeg_dec_header_info_t header;
    jpeg_error_t jerr;
    uint64_t t0 = 0;
    uint64_t t1 = 0;

    if (!inst || !jpeg || jpeg_len < 4 || !rgb565 || rgb565_cap < 320u * 240u * 2u) {
        return 0;
    }
    if (!jpg_new_decoder_open(inst, swap)) {
        return 0;
    }

    zero_bytes(&io, sizeof(io));
    zero_bytes(&header, sizeof(header));
    io.inbuf = (uint8_t *)jpeg;
    io.inbuf_len = (int)jpeg_len;
    t0 = jpg_now_us(&inst->host);
    jerr = jpeg_dec_parse_header(inst->new_dec, &io, &header);
    if (jerr != JPEG_ERR_OK) {
        jpg_new_decoder_close(inst);
        return 0;
    }
    if (header.width != 320 || header.height != 240) {
        return 0;
    }
    io.outbuf = rgb565;
    io.out_size = 0;
    jerr = jpeg_dec_process(inst->new_dec, &io);
    t1 = jpg_now_us(&inst->host);
    if (jerr != JPEG_ERR_OK) {
        jpg_new_decoder_close(inst);
        return 0;
    }

    if (out_w) {
        *out_w = header.width;
    }
    if (out_h) {
        *out_h = header.height;
    }
    if (out_len) {
        *out_len = io.out_size > 0 && io.out_size <= (int)rgb565_cap ? (uint32_t)io.out_size : 320u * 240u * 2u;
    }
    if (out_decode_us) {
        *out_decode_us = t1 >= t0 ? (uint32_t)(t1 - t0) : 0;
    }
    return 1;
#elif defined(CONFIG_JD_USE_ROM) && CONFIG_JD_USE_ROM
    JDEC dec;
    JRESULT result;
    jpg_decode_ctx_t ctx;
    uint64_t t0 = 0;
    uint64_t t1 = 0;

    if (!inst || !jpeg || jpeg_len < 4 || !rgb565 || rgb565_cap < 320u * 240u * 2u) {
        return 0;
    }
    if (inst->work_cap < JPG_WORK_BUFFER_SIZE || !inst->work) {
        if (!jpg_reserve(inst, &inst->work, &inst->work_cap, JPG_WORK_BUFFER_SIZE,
                         MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT) &&
            !jpg_reserve(inst, &inst->work, &inst->work_cap, JPG_WORK_BUFFER_SIZE,
                         MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT)) {
            return 0;
        }
    }

    zero_bytes(&dec, sizeof(dec));
    zero_bytes(&ctx, sizeof(ctx));
    ctx.inst = inst;
    ctx.input = jpeg;
    ctx.input_len = jpeg_len;
    ctx.output = rgb565;
    ctx.output_cap = rgb565_cap;
    ctx.swap = swap ? 1 : 0;
    ctx.scale_factor = 1;

    t0 = jpg_now_us(&inst->host);
    result = jd_prepare(&dec, jpg_rom_input_cb, inst->work, (UINT)inst->work_cap, &ctx);
    if (result != JDR_OK) {
        return 0;
    }
    if (dec.width == 320 && dec.height == 240) {
        ctx.scale_factor = 1;
    } else if (dec.width == 160 && dec.height == 120) {
        ctx.scale_factor = 2;
    } else {
        return 0;
    }
    result = jd_decomp(&dec, jpg_rom_output_cb, JPG_ROM_SCALE);
    t1 = jpg_now_us(&inst->host);
    if (result != JDR_OK) {
        return 0;
    }
    if (out_w) *out_w = 320;
    if (out_h) *out_h = 240;
    if (out_len) *out_len = 320u * 240u * 2u;
    if (out_decode_us) *out_decode_us = t1 >= t0 ? (uint32_t)(t1 - t0) : 0;
    return 1;
#else
    (void)inst; (void)jpeg; (void)jpeg_len; (void)rgb565; (void)rgb565_cap;
    (void)swap; (void)out_w; (void)out_h; (void)out_len; (void)out_decode_us;
    return 0;
#endif
}

static int push_error(lua_State *L, const module_host_api_v2 *host, const char *msg)
{
    if (!host) {
        return 0;
    }
    host->lua.pushnil(L);
    host->lua.pushstring(L, msg ? msg : "jpg failed");
    return 2;
}

static uint8_t jpg_image_pool_pre_guard(uint32_t slot)
{
    return (uint8_t)(0xA5u ^ ((slot + 1u) * 17u));
}

static uint8_t jpg_image_pool_post_guard(uint32_t slot)
{
    return (uint8_t)(0x5Au ^ ((slot + 1u) * 29u));
}

static void jpg_fill_image_pool_guard(uint8_t *raw, uint32_t slot)
{
    uint8_t *tail = NULL;
    if (!raw) {
        return;
    }
    tail = raw + JPG_IMAGE_POOL_GUARD_BYTES + JPG_IMAGE_POOL_BYTES;
    for (uint32_t i = 0; i < JPG_IMAGE_POOL_GUARD_BYTES; i++) {
        raw[i] = jpg_image_pool_pre_guard(slot);
        tail[i] = jpg_image_pool_post_guard(slot);
    }
}

static int jpg_check_image_pool_guard(jpg_instance_t *inst, uint32_t slot)
{
    uint8_t *raw = NULL;
    uint8_t *tail = NULL;
    int ok = 1;

    if (!inst || slot >= JPG_IMAGE_POOL_SLOTS) {
        return 0;
    }
    raw = inst->image_pool_raw[slot];
    if (!raw) {
        return 0;
    }
    tail = raw + JPG_IMAGE_POOL_GUARD_BYTES + JPG_IMAGE_POOL_BYTES;
    for (uint32_t i = 0; i < JPG_IMAGE_POOL_GUARD_BYTES; i++) {
        if (raw[i] != jpg_image_pool_pre_guard(slot) ||
            tail[i] != jpg_image_pool_post_guard(slot)) {
            ok = 0;
            break;
        }
    }
    if (!ok) {
        inst->image_pool_corrupt_count++;
        if (inst->host.serial.println && inst->image_pool_corrupt_count <= 8u) {
            inst->host.serial.println("[jpg.so] image pool guard corrupted");
        }
    }
    return ok;
}

static void jpg_release_image_pool(jpg_instance_t *inst)
{
    if (!inst) {
        return;
    }
    for (uint32_t i = 0; i < JPG_IMAGE_POOL_SLOTS; i++) {
        if (inst->lua_state && inst->host.lua.registry_unref && inst->image_pool_ref[i] > 0) {
            inst->host.lua.registry_unref(inst->lua_state, inst->image_pool_ref[i]);
        }
        if (inst->image_pool_raw[i] && inst->host.heap.free) {
            inst->host.heap.free(inst->image_pool_raw[i]);
        }
        inst->image_pool_ref[i] = 0;
        inst->image_pool_dsc[i] = NULL;
        inst->image_pool_raw[i] = NULL;
        inst->image_pool_pixels[i] = NULL;
        inst->image_pool_state[i] = JPG_IMAGE_SLOT_FREE;
        inst->image_pool_frame_id[i] = 0;
        inst->image_pool_input_bytes[i] = 0;
        inst->image_pool_output_bytes[i] = 0;
        inst->image_pool_display_seq[i] = 0;
    }
    inst->image_pool_ready = 0;
    inst->image_pool_next = 0;
    inst->image_pool_present_seq = 0;
    inst->image_pool_no_slot_count = 0;
    inst->image_pool_forced_reuse_count = 0;
    inst->image_pool_current_slot = -1;
}

static int jpg_init_image_pool(lua_State *L, jpg_instance_t *inst)
{
    const size_t userdata_size = sizeof(jpg_lv_img_dsc_t);
    int top = 0;

    if (!L || !inst || !inst->host.lua.newuserdata ||
        !inst->host.lua.registry_ref || !inst->host.lua.registry_rawgeti ||
        !inst->host.heap.malloc || !inst->host.heap.free) {
        return 0;
    }
    if (inst->image_pool_ready) {
        return 1;
    }

    top = inst->host.lua.gettop ? inst->host.lua.gettop(L) : 0;
    inst->lua_state = L;
    for (uint32_t i = 0; i < JPG_IMAGE_POOL_SLOTS; i++) {
        jpg_lv_img_dsc_t *dsc = NULL;
        uint8_t *raw = NULL;
        uint8_t *pixels = NULL;
        int ref = 0;

        dsc = (jpg_lv_img_dsc_t *)inst->host.lua.newuserdata(L, userdata_size);
        if (!dsc) {
            if (inst->host.lua.settop) {
                inst->host.lua.settop(L, top);
            }
            jpg_release_image_pool(inst);
            return 0;
        }
        zero_bytes(dsc, userdata_size);

        raw = (uint8_t *)inst->host.heap.malloc(JPG_IMAGE_POOL_ALLOC_BYTES, MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
        if (!raw) {
            if (inst->host.lua.settop) {
                inst->host.lua.settop(L, top);
            }
            jpg_release_image_pool(inst);
            return 0;
        }

        pixels = raw + JPG_IMAGE_POOL_GUARD_BYTES;
        zero_bytes(pixels, JPG_IMAGE_POOL_BYTES);
        jpg_fill_image_pool_guard(raw, i);

        dsc->header.cf = JPG_LV_IMG_CF_TRUE_COLOR;
        dsc->header.always_zero = 0;
        dsc->header.reserved = 0;
        dsc->header.w = JPG_IMAGE_POOL_WIDTH;
        dsc->header.h = JPG_IMAGE_POOL_HEIGHT;
        dsc->data_size = JPG_IMAGE_POOL_BYTES;
        dsc->data = pixels;

        ref = inst->host.lua.registry_ref(L);
        if (ref <= 0) {
            inst->host.heap.free(raw);
            if (inst->host.lua.settop) {
                inst->host.lua.settop(L, top);
            }
            jpg_release_image_pool(inst);
            return 0;
        }

        inst->image_pool_dsc[i] = dsc;
        inst->image_pool_ref[i] = ref;
        inst->image_pool_raw[i] = raw;
        inst->image_pool_pixels[i] = pixels;
        inst->image_pool_state[i] = JPG_IMAGE_SLOT_FREE;
        inst->image_pool_frame_id[i] = 0;
        inst->image_pool_input_bytes[i] = 0;
        inst->image_pool_output_bytes[i] = 0;
        inst->image_pool_display_seq[i] = 0;
    }

    inst->image_pool_next = 0;
    inst->image_pool_present_seq = 0;
    inst->image_pool_no_slot_count = 0;
    inst->image_pool_forced_reuse_count = 0;
    inst->image_pool_current_slot = -1;
    inst->image_pool_ready = 1;
    return 1;
}

static int jpg_image_pool_slot_available_locked(jpg_instance_t *inst, uint32_t slot, int enforce_hold)
{
    uint32_t seq = 0;
    uint32_t last_seq = 0;
    uint32_t age = 0;

    if (!inst || slot >= JPG_IMAGE_POOL_SLOTS ||
        !inst->image_pool_ready || !inst->image_pool_pixels[slot] ||
        !inst->image_pool_dsc[slot] || inst->image_pool_ref[slot] <= 0) {
        return 0;
    }
    if ((int)slot == inst->async_decode_index ||
        (int)slot == inst->async_ready_index ||
        (int)slot == inst->async_presenting_index ||
        (int)slot == inst->image_pool_current_slot) {
        return 0;
    }
    if (inst->image_pool_state[slot] == JPG_IMAGE_SLOT_DECODING ||
        inst->image_pool_state[slot] == JPG_IMAGE_SLOT_READY) {
        return 0;
    }
    if (!enforce_hold) {
        return 1;
    }

    last_seq = inst->image_pool_display_seq[slot];
    if (last_seq == 0) {
        return 1;
    }
    seq = inst->image_pool_present_seq;
    age = seq >= last_seq ? seq - last_seq : 0;
    return age >= JPG_IMAGE_POOL_HOLD_FRAMES;
}

static int jpg_reserve_image_pool_decode_slot_locked(jpg_instance_t *inst)
{
    if (!inst || !inst->image_pool_ready) {
        return -1;
    }

    for (uint32_t pass = 0; pass < 2u; pass++) {
        int enforce_hold = pass == 0u ? 1 : 0;
        for (uint32_t step = 0; step < JPG_IMAGE_POOL_SLOTS; step++) {
            uint32_t slot = (inst->image_pool_next + step) % JPG_IMAGE_POOL_SLOTS;
            if (!jpg_image_pool_slot_available_locked(inst, slot, enforce_hold)) {
                continue;
            }
            inst->image_pool_next = (slot + 1u) % JPG_IMAGE_POOL_SLOTS;
            inst->image_pool_state[slot] = JPG_IMAGE_SLOT_DECODING;
            inst->async_decode_index = (int)slot;
            if (!enforce_hold) {
                inst->image_pool_forced_reuse_count++;
            }
            return (int)slot;
        }
    }

    inst->image_pool_no_slot_count++;
    return -1;
}

static int jpg_take_ready_image_slot(jpg_instance_t *inst,
                                     int *out_idx,
                                     uint32_t *out_frame_id,
                                     uint32_t *out_input_bytes,
                                     uint32_t *out_output_bytes)
{
    int idx = -1;
    if (!inst) {
        return 0;
    }

    jpg_async_lock(inst);
    idx = inst->async_ready_index;
    if (idx < 0 || idx >= (int)JPG_IMAGE_POOL_SLOTS) {
        jpg_async_unlock(inst);
        return 0;
    }
    inst->async_ready_index = -1;
    inst->async_presenting_index = idx;
    if (out_frame_id) {
        *out_frame_id = inst->image_pool_frame_id[idx];
    }
    if (out_input_bytes) {
        *out_input_bytes = inst->image_pool_input_bytes[idx];
    }
    if (out_output_bytes) {
        *out_output_bytes = inst->image_pool_output_bytes[idx];
    }
    inst->image_pool_present_seq++;
    inst->image_pool_display_seq[idx] = inst->image_pool_present_seq;
    inst->image_pool_state[idx] = JPG_IMAGE_SLOT_HELD;
    inst->image_pool_current_slot = idx;
    inst->async_presenting_index = -1;
    inst->async_present_count++;
    inst->async_last_present_frame_id = inst->image_pool_frame_id[idx];
    inst->async_last_input_bytes = inst->image_pool_input_bytes[idx];
    inst->async_last_output_bytes = inst->image_pool_output_bytes[idx];
    jpg_async_unlock(inst);

    if (out_idx) {
        *out_idx = idx;
    }
    return 1;
}

static int jpg_take_ready_rgb_buffer(jpg_instance_t *inst,
                                     int *out_idx,
                                     uint8_t **out_rgb,
                                     uint32_t *out_frame_id,
                                     uint32_t *out_input_bytes,
                                     uint32_t *out_output_bytes)
{
    int idx = -1;
    if (!inst) {
        return 0;
    }

    jpg_async_lock(inst);
    idx = inst->async_ready_index;
    if (idx < 0 || idx >= (int)JPG_ASYNC_RGB_BUFFERS) {
        jpg_async_unlock(inst);
        return 0;
    }

    inst->async_ready_index = -1;
    inst->async_presenting_index = idx;
    if (out_idx) {
        *out_idx = idx;
    }
    if (out_rgb) {
        *out_rgb = inst->async_rgb[idx];
    }
    if (out_frame_id) {
        *out_frame_id = inst->async_rgb_frame_id[idx];
    }
    if (out_input_bytes) {
        *out_input_bytes = inst->async_rgb_input_bytes[idx];
    }
    if (out_output_bytes) {
        *out_output_bytes = inst->async_rgb_len[idx];
    }
    jpg_async_unlock(inst);
    return 1;
}

static void jpg_finish_ready_rgb_buffer(jpg_instance_t *inst,
                                        int idx,
                                        uint32_t frame_id,
                                        uint32_t input_bytes,
                                        uint32_t output_bytes,
                                        uint32_t push_us,
                                        int ok)
{
    if (!inst) {
        return;
    }

    jpg_async_lock(inst);
    if (idx >= 0 && inst->async_presenting_index == idx) {
        inst->async_presenting_index = -1;
    }
    if (ok) {
        inst->async_present_count++;
        inst->async_last_present_frame_id = frame_id;
        inst->async_last_input_bytes = input_bytes;
        inst->async_last_output_bytes = output_bytes;
        inst->last_push_us = push_us;
        inst->last_push_ms = push_us / 1000u;
    } else {
        inst->async_error_count++;
    }
    jpg_async_unlock(inst);
}

static uint64_t jpg_now_us(const module_host_api_v2 *host)
{
    if (host && host->time.micros) {
        return host->time.micros();
    }
    if (host && host->time.millis) {
        return (uint64_t)host->time.millis() * 1000u;
    }
    return 0;
}

#if defined(CONFIG_JD_USE_ROM) && CONFIG_JD_USE_ROM
static UINT jpg_rom_input_cb(JDEC *jd, BYTE *buff, UINT nbyte)
{
    jpg_decode_ctx_t *ctx = jd ? (jpg_decode_ctx_t *)jd->device : NULL;
    jpg_instance_t *inst = ctx ? ctx->inst : NULL;
    size_t remain = 0;
    size_t take = nbyte;

    if (!ctx || !inst || !ctx->input || ctx->read >= ctx->input_len) {
        return 0;
    }

    remain = ctx->input_len - ctx->read;
    if (take > remain) {
        take = remain;
    }

    if (buff) {
        memcpy(buff, ctx->input + ctx->read, take);
    }
    ctx->read += take;
    return (UINT)take;
}

static UINT jpg_rom_output_cb(JDEC *jd, void *bitmap, JRECT *rect)
{
    jpg_decode_ctx_t *ctx = jd ? (jpg_decode_ctx_t *)jd->device : NULL;
    jpg_instance_t *inst = ctx ? ctx->inst : NULL;
    const uint8_t *src = (const uint8_t *)bitmap;
    uint32_t x_count = 0;
    uint32_t y_count = 0;
    uint32_t y = 0;
    uint32_t factor = 1;

    if (!ctx || !inst || !ctx->output || !bitmap || !rect) {
        return 0;
    }
    if (rect->right < rect->left || rect->bottom < rect->top) {
        return 0;
    }
    factor = ctx->scale_factor ? ctx->scale_factor : 1u;
    if (((uint32_t)rect->right + 1u) * factor > 320u ||
        ((uint32_t)rect->bottom + 1u) * factor > 240u) {
        return 0;
    }
    if ((((size_t)rect->bottom + 1u) * factor * 320u * 2u) > ctx->output_cap) {
        return 0;
    }

    x_count = (uint32_t)rect->right - (uint32_t)rect->left + 1u;
    y_count = (uint32_t)rect->bottom - (uint32_t)rect->top + 1u;

    for (y = 0; y < y_count; y++) {
        uint32_t x = 0;
        uint32_t dst_y = ((uint32_t)rect->top + y) * factor;
        if (factor == 2u) {
            uint32_t *row0 = (uint32_t *)(ctx->output + ((dst_y * 320u + (uint32_t)rect->left * 2u) * 2u));
            uint32_t *row1 = row0 + 160;
            for (x = 0; x < x_count; x++) {
                uint16_t color = (uint16_t)(((uint16_t)(src[0] & 0xF8u) << 8) |
                                            ((uint16_t)(src[1] & 0xFCu) << 3) |
                                            ((uint16_t)src[2] >> 3));
                uint32_t pair;
                if (ctx->swap) color = (uint16_t)((color << 8) | (color >> 8));
                pair = (uint32_t)color | ((uint32_t)color << 16);
                row0[x] = pair;
                row1[x] = pair;
                src += 3;
            }
            continue;
        }
        if (factor == 1u) {
            uint16_t *row = (uint16_t *)(ctx->output + ((dst_y * 320u + (uint32_t)rect->left) * 2u));
            for (x = 0; x < x_count; x++) {
                uint16_t color = (uint16_t)(((uint16_t)(src[0] & 0xF8u) << 8) |
                                            ((uint16_t)(src[1] & 0xFCu) << 3) |
                                            ((uint16_t)src[2] >> 3));
                if (ctx->swap) color = (uint16_t)((color << 8) | (color >> 8));
                row[x] = color;
                src += 3;
            }
            continue;
        }
        for (x = 0; x < x_count; x++) {
            uint16_t color = (uint16_t)(((uint16_t)(src[0] & 0xF8u) << 8) |
                                        ((uint16_t)(src[1] & 0xFCu) << 3) |
                                        ((uint16_t)src[2] >> 3));
            uint32_t dst_x = ((uint32_t)rect->left + x) * factor;
            uint32_t fy = 0;
            for (fy = 0; fy < factor; fy++) {
                uint8_t *dst8 = ctx->output + (((dst_y + fy) * 320u + dst_x) * 2u);
                uint32_t fx = 0;
                for (fx = 0; fx < factor; fx++) {
                    if (!ctx->swap) {
                        ((uint16_t *)dst8)[fx] = color;
                    } else {
                        dst8[fx * 2u] = (uint8_t)(color >> 8);
                        dst8[fx * 2u + 1u] = (uint8_t)(color & 0xFFu);
                    }
                }
            }
            src += 3;
        }
    }

    return 1;
}
#endif

static void set_string_field(lua_State *L, const module_host_api_v2 *host, const char *key, const char *value)
{
    host->lua.pushstring(L, value ? value : "");
    host->lua.setfield(L, -2, key);
}

static void set_integer_field(lua_State *L, const module_host_api_v2 *host, const char *key, int64_t value)
{
    host->lua.pushinteger(L, value);
    host->lua.setfield(L, -2, key);
}

static void set_boolean_field(lua_State *L, const module_host_api_v2 *host, const char *key, int value)
{
    host->lua.pushboolean(L, value ? 1 : 0);
    host->lua.setfield(L, -2, key);
}

static void set_closure_field(lua_State *L,
                              const module_host_api_v2 *host,
                              const char *key,
                              module_lua_cfunction_t fn,
                              void *upvalue)
{
    host->lua.pushlightuserdata(L, upvalue);
    host->lua.pushcclosure(L, fn, 1);
    host->lua.setfield(L, -2, key);
}

static jpg_instance_t *instance_from_lua(lua_State *L)
{
    if (!s_instance || !s_instance->host.lua.touserdata || !s_instance->host.lua.upvalue_index) {
        return NULL;
    }
    return (jpg_instance_t *)s_instance->host.lua.touserdata(L, s_instance->host.lua.upvalue_index(1));
}

static int read_bool_field(lua_State *L, const module_host_api_v2 *host, int table_index, const char *key, int fallback)
{
    int top = host->lua.gettop(L);
    int out = fallback;
    host->lua.getfield(L, table_index, key);
    if (!host->lua.isnil(L, -1)) {
        out = host->lua.toboolean(L, -1) ? 1 : 0;
    }
    host->lua.settop(L, top);
    return out;
}

static int64_t read_int_field(lua_State *L, const module_host_api_v2 *host, int table_index, const char *key, int64_t fallback)
{
    int top = host->lua.gettop(L);
    int64_t out = fallback;
    host->lua.getfield(L, table_index, key);
    if (!host->lua.isnil(L, -1) && host->lua.isnumber(L, -1)) {
        out = host->lua.tointeger(L, -1);
    }
    host->lua.settop(L, top);
    return out;
}

static void push_stats(lua_State *L, jpg_instance_t *inst)
{
    const module_host_api_v2 *host = &inst->host;
    host->lua.createtable(L, 0, 32);
    set_integer_field(L, host, "decode_count", inst->decode_count);
    set_integer_field(L, host, "decode_ms", inst->last_decode_ms);
    set_integer_field(L, host, "decode_us", inst->last_decode_us);
    set_integer_field(L, host, "push_ms", inst->last_push_ms);
    set_integer_field(L, host, "push_us", inst->last_push_us);
    set_integer_field(L, host, "width", inst->last_width);
    set_integer_field(L, host, "height", inst->last_height);
    set_integer_field(L, host, "output_bytes", inst->last_output_bytes);
    set_integer_field(L, host, "buffer_capacity", (int64_t)inst->rgb565_cap);
    set_integer_field(L, host, "chunk_us", inst->last_chunk_us);
    set_integer_field(L, host, "chunk_count", inst->chunk_count);
    set_boolean_field(L, host, "swap_color_bytes", inst->swap_color_bytes);
    set_string_field(L, host, "byte_order", inst->swap_color_bytes ? "be" : "le");
    set_boolean_field(L, host, "async_running", inst->async_running);
    set_boolean_field(L, host, "async_ready", inst->async_ready_index >= 0);
    set_integer_field(L, host, "async_submit_count", inst->async_submit_count);
    set_integer_field(L, host, "async_decode_count", inst->async_decode_count);
    set_integer_field(L, host, "async_present_count", inst->async_present_count);
    set_integer_field(L, host, "async_pending_seq", inst->async_pending_seq);
    set_integer_field(L, host, "async_consumed_seq", inst->async_consumed_seq);
    set_integer_field(L, host, "async_pending_overwrites", inst->async_pending_overwrites);
    set_integer_field(L, host, "async_ready_overwrites", inst->async_ready_overwrites);
    set_integer_field(L, host, "async_no_buffer_count", inst->async_no_buffer_count);
    set_integer_field(L, host, "async_error_count", inst->async_error_count);
    set_integer_field(L, host, "frame_id", inst->async_last_present_frame_id);
    set_integer_field(L, host, "ready_frame_id", inst->async_last_ready_frame_id);
    set_integer_field(L, host, "input_bytes", inst->async_last_input_bytes);
    set_integer_field(L, host, "image_pool_slots", JPG_IMAGE_POOL_SLOTS);
    set_integer_field(L, host, "image_pool_corrupt_count", inst->image_pool_corrupt_count);
    set_integer_field(L, host, "image_pool_hold_frames", JPG_IMAGE_POOL_HOLD_FRAMES);
    set_integer_field(L, host, "image_pool_current_slot", inst->image_pool_current_slot >= 0 ? inst->image_pool_current_slot + 1 : 0);
    set_integer_field(L, host, "image_pool_no_slot_count", inst->image_pool_no_slot_count);
    set_integer_field(L, host, "image_pool_forced_reuse_count", inst->image_pool_forced_reuse_count);
}

static int jpg_async_start(jpg_instance_t *inst);

static void jpg_async_decode_task(void *arg)
{
    jpg_instance_t *inst = (jpg_instance_t *)arg;
    const size_t out_cap = 320u * 240u * 2u;

    if (!inst) {
        return;
    }
    inst->async_running = 1;
    while (!inst->async_stop) {
        uint32_t seq = 0;
        uint32_t frame_id = 0;
        size_t jpeg_len = 0;
        int target = -1;
        uint32_t decoded_w = 0;
        uint32_t decoded_h = 0;
        uint32_t decoded_len = 0;
        uint32_t decode_us = 0;
        int ok = 0;

        jpg_async_lock(inst);
        if (inst->async_pending_seq == inst->async_consumed_seq || inst->async_pending_jpeg_len == 0) {
            jpg_async_unlock(inst);
            if (inst->host.task.delay) {
                inst->host.task.delay(1);
            }
            continue;
        }

        for (uint32_t i = 0; i < JPG_ASYNC_RGB_BUFFERS; i++) {
            if ((int)i != inst->async_ready_index &&
                (int)i != inst->async_presenting_index &&
                (int)i != inst->async_decode_index) {
                target = (int)i;
                break;
            }
        }
        if (target < 0) {
            inst->async_no_buffer_count++;
            jpg_async_unlock(inst);
            if (inst->host.task.delay) {
                inst->host.task.delay(1);
            }
            continue;
        }
        if (!jpg_reserve(inst,
                         &inst->async_decode_jpeg,
                         &inst->async_decode_jpeg_cap,
                         inst->async_pending_jpeg_len,
                         MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT) &&
            !jpg_reserve(inst,
                         &inst->async_decode_jpeg,
                         &inst->async_decode_jpeg_cap,
                         inst->async_pending_jpeg_len,
                         MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT)) {
            inst->async_error_count++;
            inst->async_decode_index = -1;
            jpg_async_unlock(inst);
            if (inst->host.task.delay) {
                inst->host.task.delay(2);
            }
            continue;
        }
        inst->async_decode_index = target;

        seq = inst->async_pending_seq;
        frame_id = inst->async_pending_frame_id;
        jpeg_len = inst->async_pending_jpeg_len;
        copy_bytes(inst->async_decode_jpeg, inst->async_pending_jpeg, jpeg_len);
        inst->async_consumed_seq = seq;
        jpg_async_unlock(inst);

        if (!jpg_reserve_aligned(inst,
                                 &inst->async_rgb_raw[target],
                                 &inst->async_rgb[target],
                                 &inst->async_rgb_cap[target],
                                 out_cap,
                                 16u,
                                 MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT) &&
            !jpg_reserve_aligned(inst,
                                 &inst->async_rgb_raw[target],
                                 &inst->async_rgb[target],
                                 &inst->async_rgb_cap[target],
                                 out_cap,
                                 16u,
                                 MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT)) {
            jpg_async_lock(inst);
            inst->async_error_count++;
            inst->async_decode_index = -1;
            jpg_async_unlock(inst);
            continue;
        }

        ok = jpg_decode_into(inst,
                             inst->async_decode_jpeg,
                             jpeg_len,
                             inst->async_rgb[target],
                             inst->async_rgb_cap[target],
                             inst->swap_color_bytes ? 1 : 0,
                             &decoded_w,
                             &decoded_h,
                             &decoded_len,
                             &decode_us);

        jpg_async_lock(inst);
        inst->async_decode_index = -1;
        if (ok) {
            if (inst->async_ready_index >= 0 && inst->async_ready_index != target) {
                inst->async_ready_overwrites++;
            }
            inst->async_rgb_len[target] = decoded_len;
            inst->async_rgb_frame_id[target] = frame_id;
            inst->async_rgb_input_bytes[target] = (uint32_t)jpeg_len;
            inst->async_ready_index = target;
            inst->async_last_ready_frame_id = frame_id;
            inst->async_last_input_bytes = (uint32_t)jpeg_len;
            inst->async_last_output_bytes = decoded_len;
            inst->last_decode_us = decode_us;
            inst->last_decode_ms = decode_us / 1000u;
            inst->last_width = decoded_w;
            inst->last_height = decoded_h;
            inst->last_output_bytes = decoded_len;
            inst->decode_count++;
            inst->async_decode_count++;
        } else {
            inst->async_error_count++;
        }
        jpg_async_unlock(inst);

        /* A continuously full 20 FPS queue otherwise keeps core 1 busy for
         * several seconds and trips the idle-task watchdog.  One scheduler
         * tick per decoded frame is enough for IDLE1 and stop requests while
         * adding negligible latency. */
        if (inst->host.task.delay) {
            inst->host.task.delay(1);
        }
    }
    /* Publish the joined state before returning to the host task wrapper.  The
     * stop path waits for this transition and never frees the instance while
     * the worker may still touch it.  Leave deletion/bookkeeping to the host,
     * as required by the module ABI. */
    inst->async_task = NULL;
    inst->async_running = 0;
}

static int jpg_async_start(jpg_instance_t *inst)
{
    void *task = NULL;
    int32_t err = MODULE_OK;
    if (!inst) {
        return 0;
    }
    if (inst->async_task || inst->async_running) {
        return 1;
    }
    if (!inst->host.task.create_ex || !inst->host.task.delay) {
        return 0;
    }
    inst->async_stop = 0;
    inst->async_ready_index = -1;
    inst->async_presenting_index = -1;
    inst->async_decode_index = -1;
    err = inst->host.task.create_ex("jpg_decode",
                                    jpg_async_decode_task,
                                    inst,
                                    JPG_DECODE_TASK_STACK_BYTES,
                                    3u,
                                    1,
                                    MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT,
                                    &task);
    if (err != MODULE_OK || !task) {
        inst->async_task = NULL;
        inst->async_running = 0;
        return 0;
    }
    inst->async_task = task;
    return 1;
}

static int l_jpg_submit(lua_State *L)
{
    jpg_instance_t *inst = instance_from_lua(L);
    module_host_api_v2 *host = inst ? &inst->host : NULL;
    const uint8_t *jpeg = NULL;
    size_t jpeg_len = 0;
    int swap = 0;
    int direct_present = 0;
    uint32_t frame_id = 0;

    if (!inst || !host) {
        return push_error(L, host, "jpg.submit: instance missing");
    }
    if (!host->lua.checklstring) {
        return push_error(L, host, "jpg.submit: host binary Lua API missing");
    }
    jpeg = (const uint8_t *)host->lua.checklstring(L, 1, &jpeg_len);
    if (!jpeg || jpeg_len < 4) {
        return push_error(L, host, "jpg.submit: empty jpeg");
    }
    if (host->lua.gettop(L) >= 2 && host->lua.istable(L, 2)) {
        swap = read_bool_field(L, host, 2, "swap_color_bytes", inst->swap_color_bytes);
        direct_present = read_bool_field(L, host, 2, "direct_present", 0);
        frame_id = (uint32_t)read_int_field(L, host, 2, "frame_id", 0);
    }
    if (!direct_present && !jpg_init_image_pool(L, inst)) {
        return push_error(L, host, "jpg.submit: image pool init failed");
    }
    if (!jpg_async_start(inst)) {
        return push_error(L, host, "jpg.submit: decode task create failed");
    }

    jpg_async_lock(inst);
    if (!jpg_reserve(inst,
                     &inst->async_pending_jpeg,
                     &inst->async_pending_jpeg_cap,
                     jpeg_len,
                     MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT) &&
        !jpg_reserve(inst,
                     &inst->async_pending_jpeg,
                     &inst->async_pending_jpeg_cap,
                     jpeg_len,
                     MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT)) {
        jpg_async_unlock(inst);
        return push_error(L, host, "jpg.submit: pending jpeg alloc failed");
    }
    if (inst->async_pending_seq != inst->async_consumed_seq) {
        inst->async_pending_overwrites++;
    }
    copy_bytes(inst->async_pending_jpeg, jpeg, jpeg_len);
    inst->async_pending_jpeg_len = jpeg_len;
    inst->async_pending_frame_id = frame_id;
    inst->swap_color_bytes = swap ? 1 : 0;
    inst->async_submit_count++;
    inst->async_pending_seq++;
    jpg_async_unlock(inst);

    host->lua.pushboolean(L, 1);
    push_stats(L, inst);
    return 2;
}

static int l_jpg_ready(lua_State *L)
{
    jpg_instance_t *inst = instance_from_lua(L);
    module_host_api_v2 *host = inst ? &inst->host : NULL;
    int ready = 0;
    if (!inst || !host) {
        return push_error(L, host, "jpg.ready: instance missing");
    }
    jpg_async_lock(inst);
    ready = inst->async_ready_index >= 0;
    jpg_async_unlock(inst);
    host->lua.pushboolean(L, ready);
    push_stats(L, inst);
    return 2;
}

static int l_jpg_read_ready(lua_State *L)
{
    jpg_instance_t *inst = instance_from_lua(L);
    module_host_api_v2 *host = inst ? &inst->host : NULL;
    int idx = -1;
    uint8_t *rgb = NULL;
    uint32_t frame_id = 0;
    uint32_t input_bytes = 0;
    uint32_t output_bytes = 0;
    uint64_t t0 = 0;
    uint64_t t1 = 0;

    if (!inst || !host) {
        return push_error(L, host, "jpg.read_ready: instance missing");
    }
    if (!host->lua.pushlstring) {
        return push_error(L, host, "jpg.read_ready: host binary Lua API missing");
    }

    if (!jpg_take_ready_rgb_buffer(inst, &idx, &rgb, &frame_id, &input_bytes, &output_bytes)) {
        host->lua.pushnil(L);
        return 1;
    }

    if (!rgb || output_bytes == 0) {
        jpg_finish_ready_rgb_buffer(inst, idx, frame_id, input_bytes, output_bytes, 0, 0);
        return push_error(L, host, "jpg.read_ready: decoded buffer missing");
    }

    t0 = jpg_now_us(host);
    host->lua.pushlstring(L, (const char *)rgb, output_bytes);
    t1 = jpg_now_us(host);

    jpg_finish_ready_rgb_buffer(inst,
                                idx,
                                frame_id,
                                input_bytes,
                                output_bytes,
                                t1 >= t0 ? (uint32_t)(t1 - t0) : 0,
                                1);

    host->lua.pushinteger(L, 320);
    host->lua.pushinteger(L, 240);
    push_stats(L, inst);
    return 4;
}

static int l_jpg_read_ready_image(lua_State *L)
{
    jpg_instance_t *inst = instance_from_lua(L);
    module_host_api_v2 *host = inst ? &inst->host : NULL;
    int idx = -1;
    uint8_t *rgb = NULL;
    uint32_t frame_id = 0;
    uint32_t input_bytes = 0;
    uint32_t output_bytes = 0;
    uint64_t t0 = 0;
    uint64_t t1 = 0;

    if (!inst || !host) {
        return push_error(L, host, "jpg.read_ready_image: instance missing");
    }

    if (!jpg_take_ready_rgb_buffer(inst, &idx, &rgb, &frame_id, &input_bytes, &output_bytes)) {
        host->lua.pushnil(L);
        return 1;
    }

    if (!rgb || output_bytes == 0 || output_bytes > JPG_IMAGE_POOL_BYTES ||
        !jpg_init_image_pool(L, inst) ||
        !inst->image_pool_pixels[0] ||
        inst->image_pool_ref[0] <= 0 ||
        !jpg_check_image_pool_guard(inst, 0)) {
        jpg_finish_ready_rgb_buffer(inst, idx, frame_id, input_bytes, output_bytes, 0, 0);
        return push_error(L, host, "jpg.read_ready_image: decoded buffer missing");
    }

    t0 = jpg_now_us(host);
    copy_bytes(inst->image_pool_pixels[0], rgb, output_bytes);
    if (!jpg_check_image_pool_guard(inst, 0)) {
        jpg_finish_ready_rgb_buffer(inst, idx, frame_id, input_bytes, output_bytes, 0, 0);
        return push_error(L, host, "jpg.read_ready_image: front buffer guard failed");
    }
    inst->image_pool_frame_id[0] = frame_id;
    inst->image_pool_input_bytes[0] = input_bytes;
    inst->image_pool_output_bytes[0] = output_bytes;
    inst->image_pool_current_slot = 0;
    inst->image_pool_state[0] = JPG_IMAGE_SLOT_HELD;
    inst->host.lua.registry_rawgeti(L, inst->image_pool_ref[0]);
    t1 = jpg_now_us(host);

    jpg_finish_ready_rgb_buffer(inst,
                                idx,
                                frame_id,
                                input_bytes,
                                output_bytes,
                                t1 >= t0 ? (uint32_t)(t1 - t0) : 0,
                                1);

    host->lua.pushinteger(L, 320);
    host->lua.pushinteger(L, 240);
    push_stats(L, inst);
    return 4;
}

static int l_jpg_read_ready_slot(lua_State *L)
{
    jpg_instance_t *inst = instance_from_lua(L);
    module_host_api_v2 *host = inst ? &inst->host : NULL;
    int idx = -1;
    uint32_t frame_id = 0;
    uint32_t input_bytes = 0;
    uint32_t output_bytes = 0;
    uint64_t t0 = 0;
    uint64_t t1 = 0;

    if (!inst || !host) {
        return push_error(L, host, "jpg.read_ready_slot: instance missing");
    }
    t0 = jpg_now_us(host);
    if (!jpg_take_ready_image_slot(inst, &idx, &frame_id, &input_bytes, &output_bytes)) {
        host->lua.pushnil(L);
        return 1;
    }
    t1 = jpg_now_us(host);

    if (idx < 0 || idx >= (int)JPG_IMAGE_POOL_SLOTS || output_bytes == 0) {
        return push_error(L, host, "jpg.read_ready_slot: decoded slot missing");
    }

    jpg_async_lock(inst);
    inst->async_last_present_frame_id = frame_id;
    inst->async_last_input_bytes = input_bytes;
    inst->async_last_output_bytes = output_bytes;
    inst->last_push_us = t1 >= t0 ? (uint32_t)(t1 - t0) : 0;
    inst->last_push_ms = inst->last_push_us / 1000u;
    jpg_async_unlock(inst);

    host->lua.pushinteger(L, idx + 1);
    host->lua.pushinteger(L, 320);
    host->lua.pushinteger(L, 240);
    push_stats(L, inst);
    return 4;
}

static int l_jpg_image_slot_count(lua_State *L)
{
    jpg_instance_t *inst = instance_from_lua(L);
    module_host_api_v2 *host = inst ? &inst->host : NULL;

    if (!inst || !host) {
        return push_error(L, host, "jpg.image_slot_count: instance missing");
    }
    if (!jpg_init_image_pool(L, inst)) {
        return push_error(L, host, "jpg.image_slot_count: image pool init failed");
    }
    host->lua.pushinteger(L, JPG_IMAGE_POOL_SLOTS);
    push_stats(L, inst);
    return 2;
}

static int l_jpg_image_slot(lua_State *L)
{
    jpg_instance_t *inst = instance_from_lua(L);
    module_host_api_v2 *host = inst ? &inst->host : NULL;
    int64_t slot_arg = 0;
    int idx = -1;

    if (!inst || !host) {
        return push_error(L, host, "jpg.image_slot: instance missing");
    }
    if (!host->lua.checkinteger || !host->lua.registry_rawgeti) {
        return push_error(L, host, "jpg.image_slot: host Lua API missing");
    }
    if (!jpg_init_image_pool(L, inst)) {
        return push_error(L, host, "jpg.image_slot: image pool init failed");
    }
    slot_arg = host->lua.checkinteger(L, 1);
    if (slot_arg < 1 || slot_arg > (int64_t)JPG_IMAGE_POOL_SLOTS) {
        return push_error(L, host, "jpg.image_slot: slot index out of range");
    }
    idx = (int)slot_arg - 1;
    if (inst->image_pool_ref[idx] <= 0) {
        return push_error(L, host, "jpg.image_slot: slot missing");
    }

    inst->host.lua.registry_rawgeti(L, inst->image_pool_ref[idx]);
    host->lua.pushinteger(L, 320);
    host->lua.pushinteger(L, 240);
    push_stats(L, inst);
    return 4;
}

static int l_jpg_present_ready(lua_State *L)
{
    jpg_instance_t *inst = instance_from_lua(L);
    module_host_api_v2 *host = inst ? &inst->host : NULL;
    int idx = -1;
    uint8_t *rgb = NULL;
    uint32_t frame_id = 0;
    uint32_t input_bytes = 0;
    uint32_t output_bytes = 0;

    if (!inst || !host) {
        return push_error(L, host, "jpg.present_ready: instance missing");
    }

    if (!jpg_take_ready_rgb_buffer(inst, &idx, &rgb, &frame_id, &input_bytes, &output_bytes)) {
        host->lua.pushboolean(L, 0);
        return 1;
    }

    if (!rgb || output_bytes == 0 || !jpg_present_rgb565(inst, rgb, 320u, 240u)) {
        jpg_finish_ready_rgb_buffer(inst, idx, frame_id, input_bytes, output_bytes, 0, 0);
        return push_error(L, host, "jpg.present_ready: display push failed");
    }

    jpg_finish_ready_rgb_buffer(inst,
                                idx,
                                frame_id,
                                input_bytes,
                                output_bytes,
                                inst->last_push_us,
                                1);

    host->lua.pushboolean(L, 1);
    push_stats(L, inst);
    return 2;
}

static void jpg_async_stop(jpg_instance_t *inst)
{
    if (!inst) {
        return;
    }
    inst->async_stop = 1;
    if (inst->async_task && inst->host.task.delay) {
        for (uint32_t i = 0; i < 100 && inst->async_running; i++) {
            inst->host.task.delay(1);
        }
    }
    /* Normal shutdown is cooperative: the worker clears async_task and returns
     * through the host wrapper.  Forced removal is only a final timeout guard;
     * never free a still-running worker's instance. */
    if (inst->async_task && inst->async_running && inst->host.task.remove) {
        inst->host.task.remove(inst->async_task);
        inst->async_task = NULL;
        inst->async_running = 0;
    }
}

static int l_jpg_decode(lua_State *L)
{
    jpg_instance_t *inst = instance_from_lua(L);
    module_host_api_v2 *host = inst ? &inst->host : NULL;
    const uint8_t *jpeg = NULL;
    size_t jpeg_len = 0;
    size_t out_cap = 0;
    uint32_t decoded_w = 0;
    uint32_t decoded_h = 0;
    uint32_t decoded_len = 0;
#if !JPG_USE_ESP_NEW_JPEG && !(defined(CONFIG_JD_USE_ROM) && CONFIG_JD_USE_ROM)
    esp_jpeg_image_cfg_t cfg;
    esp_jpeg_image_output_t out;
    esp_err_t err;
#endif
    uint64_t t0 = 0;
    uint64_t t1 = 0;
    uint64_t t2 = 0;
    int swap = 0;
    int chunked = 0;

    if (!inst || !host) {
        return push_error(L, host, "jpg.decode: instance missing");
    }
    if (!host->lua.checklstring || !host->lua.pushlstring) {
        return push_error(L, host, "jpg.decode: host binary Lua API missing");
    }

    jpeg = (const uint8_t *)host->lua.checklstring(L, 1, &jpeg_len);
    if (!jpeg || jpeg_len < 4) {
        return push_error(L, host, "jpg.decode: empty jpeg");
    }

    swap = 0;
    if (host->lua.gettop(L) >= 2 && host->lua.istable(L, 2)) {
        swap = read_bool_field(L, host, 2, "swap_color_bytes", swap);
        chunked = read_bool_field(L, host, 2, "chunked", chunked);
    }

    out_cap = 320u * 240u * 2u;
    if (!jpg_reserve(inst, &inst->jpeg, &inst->jpeg_cap, jpeg_len, MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT)) {
        return push_error(L, host, "jpg.decode: jpeg buffer alloc failed");
    }
    copy_bytes(inst->jpeg, jpeg, jpeg_len);
    inst->jpeg_len = jpeg_len;
#if !JPG_USE_ESP_NEW_JPEG
    if (inst->work_cap < JPG_WORK_BUFFER_SIZE || !inst->work) {
        if (!jpg_reserve(inst, &inst->work, &inst->work_cap, JPG_WORK_BUFFER_SIZE, MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT)) {
            (void)jpg_reserve(inst, &inst->work, &inst->work_cap, JPG_WORK_BUFFER_SIZE, MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
        }
    }
    if (!inst->work) {
        return push_error(L, host, "jpg.decode: work buffer alloc failed");
    }
#endif

#if JPG_USE_ESP_NEW_JPEG
    if (!jpg_reserve_aligned(inst,
                             &inst->rgb565_raw,
                             &inst->rgb565,
                             &inst->rgb565_cap,
                             out_cap,
                             16u,
                             MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT) &&
        !jpg_reserve_aligned(inst,
                             &inst->rgb565_raw,
                             &inst->rgb565,
                             &inst->rgb565_cap,
                             out_cap,
                             16u,
                             MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT)) {
        return push_error(L, host, "jpg.decode: rgb565 buffer alloc failed");
    }

    {
        jpeg_dec_io_t io;
        jpeg_dec_header_info_t header;
        jpeg_error_t jerr;

        if (!jpg_new_decoder_open(inst, swap)) {
            return push_error(L, host, "jpg.decode: esp_new_jpeg open failed");
        }

        zero_bytes(&io, sizeof(io));
        zero_bytes(&header, sizeof(header));
        io.inbuf = inst->jpeg;
        io.inbuf_len = (int)jpeg_len;
        t0 = jpg_now_us(host);
        jerr = jpeg_dec_parse_header(inst->new_dec, &io, &header);
        if (jerr != JPEG_ERR_OK) {
            jpg_new_decoder_close(inst);
            return push_error(L, host, "jpg.decode: esp_new_jpeg parse failed");
        }
        if (header.width != 320 || header.height != 240) {
            return push_error(L, host, "jpg.decode: unsupported jpeg size");
        }
        io.outbuf = inst->rgb565;
        io.out_size = 0;
        jerr = jpeg_dec_process(inst->new_dec, &io);
        t1 = jpg_now_us(host);
        if (jerr != JPEG_ERR_OK) {
            jpg_new_decoder_close(inst);
            return push_error(L, host, "jpg.decode: esp_new_jpeg process failed");
        }
        decoded_w = header.width;
        decoded_h = header.height;
        decoded_len = io.out_size > 0 && io.out_size <= (int)out_cap ? (uint32_t)io.out_size : (uint32_t)out_cap;
    }
#elif defined(CONFIG_JD_USE_ROM) && CONFIG_JD_USE_ROM
    if (!jpg_reserve(inst, &inst->rgb565, &inst->rgb565_cap, out_cap, MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT)) {
        return push_error(L, host, "jpg.decode: rgb565 buffer alloc failed");
    }

    {
        JDEC dec;
        JRESULT res;
        jpg_decode_ctx_t ctx;

        zero_bytes(&dec, sizeof(dec));
        zero_bytes(&ctx, sizeof(ctx));
        ctx.inst = inst;
        ctx.input = inst->jpeg;
        ctx.input_len = jpeg_len;
        ctx.output = inst->rgb565;
        ctx.output_cap = inst->rgb565_cap;
        ctx.swap = swap ? 1 : 0;
        ctx.scale_factor = 1;

        t0 = jpg_now_us(host);
        res = jd_prepare(&dec, jpg_rom_input_cb, inst->work, (UINT)inst->work_cap, &ctx);
        if (res != JDR_OK) {
            return push_error(L, host, "jpg.decode: jd_prepare failed");
        }
        if (dec.width == 320 && dec.height == 240) {
            ctx.scale_factor = 1;
        } else if (dec.width == 160 && dec.height == 120) {
            ctx.scale_factor = 2;
        } else {
            return push_error(L, host, "jpg.decode: unsupported jpeg size");
        }
        res = jd_decomp(&dec, jpg_rom_output_cb, JPG_ROM_SCALE);
        t1 = jpg_now_us(host);
        if (res != JDR_OK) {
            return push_error(L, host, "jpg.decode: jd_decomp failed");
        }
        decoded_w = 320;
        decoded_h = 240;
        decoded_len = out_cap;
    }
#else
    zero_bytes(&cfg, sizeof(cfg));
    zero_bytes(&out, sizeof(out));

    cfg.indata = inst->jpeg;
    cfg.indata_size = jpeg_len;
    cfg.out_format = JPEG_IMAGE_FORMAT_RGB565;
    cfg.out_scale = JPEG_IMAGE_SCALE_0;
    cfg.flags.swap_color_bytes = swap ? 1 : 0;

    if (!jpg_reserve(inst, &inst->rgb565, &inst->rgb565_cap, out_cap, MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT)) {
        return push_error(L, host, "jpg.decode: rgb565 buffer alloc failed");
    }

    cfg.outbuf = inst->rgb565;
    cfg.outbuf_size = inst->rgb565_cap;
    cfg.advanced.working_buffer = inst->work;
    cfg.advanced.working_buffer_size = inst->work ? inst->work_cap : 0;

    t0 = jpg_now_us(host);
    err = esp_jpeg_decode(&cfg, &out);
    t1 = jpg_now_us(host);
    if (err != ESP_OK) {
        return push_error(L, host, "jpg.decode: esp_jpeg_decode failed");
    }
    if (out.width != 320 || out.height != 240 || out.output_len == 0 || out.output_len > out_cap) {
        return push_error(L, host, "jpg.decode: unsupported output size");
    }
    decoded_w = out.width;
    decoded_h = out.height;
    decoded_len = out.output_len;
#endif

    inst->decode_count++;
    inst->last_decode_us = t1 >= t0 ? (uint32_t)(t1 - t0) : 0;
    inst->last_decode_ms = inst->last_decode_us / 1000u;
    inst->last_width = decoded_w;
    inst->last_height = decoded_h;
    inst->last_output_bytes = decoded_len;
    inst->last_chunk_us = 0;
    inst->chunk_count = 0;
    inst->swap_color_bytes = swap ? 1 : 0;

    if (chunked) {
        host->lua.pushboolean(L, 1);
        host->lua.pushinteger(L, decoded_w);
        host->lua.pushinteger(L, decoded_h);
        push_stats(L, inst);
        return 4;
    }

    host->lua.pushlstring(L, (const char *)inst->rgb565, inst->last_output_bytes);
    t2 = jpg_now_us(host);
    inst->last_push_us = t2 >= t1 ? (uint32_t)(t2 - t1) : 0;
    inst->last_push_ms = inst->last_push_us / 1000u;
    host->lua.pushinteger(L, decoded_w);
    host->lua.pushinteger(L, decoded_h);
    push_stats(L, inst);
    return 4;
}

static int l_jpg_chunk(lua_State *L)
{
    jpg_instance_t *inst = instance_from_lua(L);
    module_host_api_v2 *host = inst ? &inst->host : NULL;
    int64_t y = 0;
    int64_t rows = 0;
    size_t offset = 0;
    size_t len = 0;
    uint64_t t0 = 0;
    uint64_t t1 = 0;

    if (!inst || !host || !inst->rgb565 || inst->last_width == 0 || inst->last_height == 0) {
        return push_error(L, host, "jpg.chunk: no decoded frame");
    }
    if (!host->lua.checkinteger || !host->lua.pushlstring) {
        return push_error(L, host, "jpg.chunk: host Lua API missing");
    }

    y = host->lua.checkinteger(L, 1);
    rows = host->lua.checkinteger(L, 2);
    if (y < 0 || rows <= 0 || y >= (int64_t)inst->last_height || y + rows > (int64_t)inst->last_height) {
        return push_error(L, host, "jpg.chunk: range");
    }

    offset = (size_t)y * (size_t)inst->last_width * 2u;
    len = (size_t)rows * (size_t)inst->last_width * 2u;
    if (offset > inst->last_output_bytes || len > inst->last_output_bytes - offset) {
        return push_error(L, host, "jpg.chunk: overflow");
    }

    t0 = jpg_now_us(host);
    host->lua.pushlstring(L, (const char *)inst->rgb565 + offset, len);
    t1 = jpg_now_us(host);
    inst->last_chunk_us += t1 >= t0 ? (uint32_t)(t1 - t0) : 0;
    inst->chunk_count++;
    return 1;
}

static int jpg_present_rgb565(jpg_instance_t *inst, const uint8_t *rgb565, uint32_t width, uint32_t height)
{
    module_host_api_v2 *host = inst ? &inst->host : NULL;
    module_display_caps_t caps;
    uint64_t t0 = 0;
    uint64_t t1 = 0;
    int32_t ret = MODULE_OK;
    uint32_t y = 0;
    uint32_t chunk_index = 0;
    uint32_t dma_rows = JPG_DMA_ROWS;
    size_t dma_bytes = 0;
    uint32_t i = 0;
    int use_pixels_dma = 0;

    if (!inst || !host || !rgb565 || width == 0 || height == 0) {
        return 0;
    }
    if (width != 320 || height != 240) {
        return 0;
    }
    if (!jpg_display_acquire(inst)) {
        return 0;
    }
    if (!host->display.pushImageDMA && !(host->display.setAddrWindow && host->display.pushPixelsDMA)) {
        return 0;
    }

    zero_bytes(&caps, sizeof(caps));
    caps.size = sizeof(caps);
    if (host->display.get_caps &&
        host->display.get_caps(&caps) == MODULE_OK &&
        caps.max_dma_rows > 0 &&
        dma_rows > caps.max_dma_rows) {
        dma_rows = caps.max_dma_rows;
    }
    if (dma_rows > height) {
        dma_rows = height;
    }
    if (dma_rows < JPG_DMA_MIN_ROWS) {
        dma_rows = JPG_DMA_MIN_ROWS;
    }

    while (dma_rows >= JPG_DMA_MIN_ROWS) {
        int allocated = 1;
        dma_bytes = (size_t)width * (size_t)dma_rows * 2u;
        for (i = 0; i < JPG_DMA_BUFFERS; i++) {
            if (!jpg_reserve(inst,
                             &inst->dma[i],
                             &inst->dma_cap[i],
                             dma_bytes,
                             MODULE_HEAP_INTERNAL | MODULE_HEAP_DMA | MODULE_HEAP_8BIT)) {
                allocated = 0;
                break;
            }
        }
        if (allocated) {
            break;
        }
        dma_rows /= 2u;
    }
    if (dma_rows < JPG_DMA_MIN_ROWS) {
        return 0;
    }

    use_pixels_dma = host->display.setAddrWindow && host->display.pushPixelsDMA;

    t0 = jpg_now_us(host);
    ret = host->display.startWrite(inst->display_surface);
    if (ret != MODULE_OK) {
        return 0;
    }
    inst->display_write_active = 1;

    if (use_pixels_dma) {
        ret = host->display.setAddrWindow(inst->display_surface, 0, 0, (int32_t)width, (int32_t)height);
        if (ret != MODULE_OK) {
            (void)host->display.endWrite(inst->display_surface);
            inst->display_write_active = 0;
            return 0;
        }
    }

    while (y < height) {
        uint32_t rows = dma_rows;
        size_t bytes = 0;
        if (y + rows > height) {
            rows = height - y;
        }
        bytes = (size_t)width * (size_t)rows * 2u;
        i = chunk_index % JPG_DMA_BUFFERS;
        copy_bytes(inst->dma[i], rgb565 + ((size_t)y * (size_t)width * 2u), bytes);
        if (use_pixels_dma) {
            ret = host->display.pushPixelsDMA(inst->display_surface,
                                              (const uint16_t *)inst->dma[i],
                                              (size_t)width * (size_t)rows);
        } else {
            ret = host->display.pushImageDMA(inst->display_surface,
                                             0,
                                             (int16_t)y,
                                             (uint16_t)width,
                                             (uint16_t)rows,
                                             (const uint16_t *)inst->dma[i]);
        }
        if (ret != MODULE_OK) {
            (void)host->display.endWrite(inst->display_surface);
            inst->display_write_active = 0;
            return 0;
        }
        chunk_index++;
        y += rows;
    }

    ret = host->display.endWrite(inst->display_surface);
    inst->display_write_active = 0;
    t1 = jpg_now_us(host);
    if (ret != MODULE_OK) {
        return 0;
    }

    inst->last_push_us = t1 >= t0 ? (uint32_t)(t1 - t0) : 0;
    inst->last_push_ms = inst->last_push_us / 1000u;
    return 1;
}

static int l_jpg_present(lua_State *L)
{
    jpg_instance_t *inst = instance_from_lua(L);
    module_host_api_v2 *host = inst ? &inst->host : NULL;

    if (!inst || !host || !inst->rgb565 || inst->last_width == 0 || inst->last_height == 0) {
        return push_error(L, host, "jpg.present: no decoded frame");
    }
    if (!jpg_present_rgb565(inst, inst->rgb565, inst->last_width, inst->last_height)) {
        return push_error(L, host, "jpg.present: display push failed");
    }
    host->lua.pushboolean(L, 1);
    push_stats(L, inst);
    return 2;
}

static int l_jpg_release(lua_State *L)
{
    jpg_instance_t *inst = instance_from_lua(L);
    module_host_api_v2 *host = inst ? &inst->host : NULL;
    if (!inst || !host) {
        return push_error(L, host, "jpg.release: instance missing");
    }
    jpg_async_stop(inst);
    if (!jpg_display_release(inst)) {
        return push_error(L, host, "jpg.release: display release failed");
    }
    host->lua.pushboolean(L, 1);
    return 1;
}

static int l_jpg_stats(lua_State *L)
{
    jpg_instance_t *inst = instance_from_lua(L);
    if (!inst) {
        return 0;
    }
    push_stats(L, inst);
    return 1;
}

static int l_jpg_version(lua_State *L)
{
    jpg_instance_t *inst = instance_from_lua(L);
    module_host_api_v2 *host = inst ? &inst->host : NULL;
    if (!host) {
        return 0;
    }
    host->lua.pushstring(L, JPG_VERSION);
    return 1;
}

JPG_MODULE_EXPORT const module_manifest_t *module_query_v1(void)
{
    return &s_manifest;
}

JPG_MODULE_EXPORT int32_t module_create_v2(module_host_resolve_v2_fn resolve,
                                           void *resolve_ctx,
                                           const module_open_info_t *info,
                                           void **out_instance)
{
    int32_t rc;
    jpg_instance_t *inst = NULL;
    module_host_api_v2 host;
    (void)info;

    if (!out_instance) {
        return MODULE_ERR_INVALID_ARG;
    }
    *out_instance = NULL;
    rc = module_sdk_resolve_host_v2(resolve, resolve_ctx, &host);
    if (rc != MODULE_OK) {
        return rc;
    }
    if (!host.heap.calloc || !host.heap.free || !host.lua.checklstring ||
        !host.lua.pushlstring || !host.lua.newuserdata ||
        !host.lua.registry_ref || !host.lua.registry_unref || !host.lua.registry_rawgeti) {
        return MODULE_ERR_UNSUPPORTED;
    }

    inst = (jpg_instance_t *)host.heap.calloc(1, sizeof(jpg_instance_t), MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT);
    if (!inst) {
        return MODULE_ERR_NO_MEMORY;
    }
    inst->host = host;
    inst->async_ready_index = -1;
    inst->async_presenting_index = -1;
    inst->async_decode_index = -1;
    inst->image_pool_current_slot = -1;
    s_instance = inst;
    *out_instance = inst;
    if (host.serial.println) {
        host.serial.println("[jpg.so] created");
    }
    return MODULE_OK;
}

JPG_MODULE_EXPORT int32_t module_luaopen_v1(void *instance, lua_State *L)
{
    jpg_instance_t *inst = (jpg_instance_t *)instance;
    module_host_api_v2 *host = inst ? &inst->host : NULL;
    if (!inst || !host || !L) {
        return MODULE_ERR_INVALID_ARG;
    }

    inst->lua_state = L;
    host->lua.createtable(L, 0, 17);
    set_string_field(L, host, "VERSION", JPG_VERSION);
    set_string_field(L, host, "DESCRIPTION", JPG_MODULE_DESCRIPTION);
    set_string_field(L, host, "OUTPUT_FORMAT", "RGB565");
    set_string_field(L, host, "DEFAULT_BYTE_ORDER", "le");
    set_closure_field(L, host, "decode", l_jpg_decode, inst);
    set_closure_field(L, host, "chunk", l_jpg_chunk, inst);
    set_closure_field(L, host, "present", l_jpg_present, inst);
    set_closure_field(L, host, "submit", l_jpg_submit, inst);
    set_closure_field(L, host, "ready", l_jpg_ready, inst);
    set_closure_field(L, host, "read_ready", l_jpg_read_ready, inst);
    set_closure_field(L, host, "read_ready_image", l_jpg_read_ready_image, inst);
    set_closure_field(L, host, "read_ready_slot", l_jpg_read_ready_slot, inst);
    set_closure_field(L, host, "image_slot_count", l_jpg_image_slot_count, inst);
    set_closure_field(L, host, "image_slot", l_jpg_image_slot, inst);
    set_closure_field(L, host, "present_ready", l_jpg_present_ready, inst);
    set_closure_field(L, host, "release", l_jpg_release, inst);
    set_closure_field(L, host, "stats", l_jpg_stats, inst);
    set_closure_field(L, host, "version", l_jpg_version, inst);
    return MODULE_OK;
}

JPG_MODULE_EXPORT void module_destroy_v1(void *instance)
{
    jpg_instance_t *inst = (jpg_instance_t *)instance;
    if (!inst) {
        return;
    }
    jpg_async_stop(inst);
    jpg_release_image_pool(inst);
#if JPG_CLOSE_NEW_DECODER_ON_DESTROY
    jpg_new_decoder_close(inst);
#else
    inst->new_dec = NULL;
#endif
    (void)jpg_display_release(inst);
    if (inst->rgb565_raw) {
        inst->host.heap.free(inst->rgb565_raw);
    } else if (inst->rgb565) {
        inst->host.heap.free(inst->rgb565);
    }
    if (inst->jpeg) {
        inst->host.heap.free(inst->jpeg);
    }
    if (inst->async_pending_jpeg) {
        inst->host.heap.free(inst->async_pending_jpeg);
    }
    if (inst->async_decode_jpeg) {
        inst->host.heap.free(inst->async_decode_jpeg);
    }
    for (uint32_t i = 0; i < JPG_ASYNC_RGB_BUFFERS; i++) {
        if (inst->async_rgb_raw[i]) {
            inst->host.heap.free(inst->async_rgb_raw[i]);
        }
    }
    if (inst->work) {
        inst->host.heap.free(inst->work);
    }
    for (uint32_t i = 0; i < JPG_DMA_BUFFERS; i++) {
        if (inst->dma[i]) {
            inst->host.heap.free(inst->dma[i]);
        }
    }
    while (inst->aligned_allocs) {
        jpg_aligned_alloc_t *node = inst->aligned_allocs;
        inst->aligned_allocs = node->next;
        if (node->raw) {
            inst->host.heap.free(node->raw);
        }
        inst->host.heap.free(node);
    }
    if (inst->host.serial.println) {
        inst->host.serial.println("[jpg.so] destroyed");
    }
    if (s_instance == inst) {
        s_instance = NULL;
    }
    inst->host.heap.free(inst);
}

void app_main(void)
{
}
