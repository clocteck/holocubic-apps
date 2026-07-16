#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "module_abi.h"

#if defined(WAKE_USE_ESP_SR) && WAKE_USE_ESP_SR
#include "esp_wn_iface.h"
#include "esp_wn_models.h"
#include "model_path.h"
#endif

#define WAKE_MODULE_EXPORT __attribute__((visibility("default"), used))
#define WAKE_VERSION "0.3.0"
#define WAKE_ENGINE "WakeNet9s"
#define WAKE_MODEL "wn9s_nihaoxiaozhi"
#define WAKE_WORD "你好小智"
#define WAKE_STRINGIFY_INNER(value) #value
#define WAKE_STRINGIFY(value) WAKE_STRINGIFY_INNER(value)
#ifndef WAKE_MODEL_PATH
#define WAKE_MODEL_PATH /sd/apps/xiaozhi/wake
#endif
#define WAKE_MODEL_PATH_STRING WAKE_STRINGIFY(WAKE_MODEL_PATH)
#define WAKE_MODEL_DIR WAKE_MODEL_PATH_STRING "/" WAKE_MODEL
#define WAKE_MODEL_INDEX_FILE WAKE_MODEL_DIR "/wn9_index"
#define WAKE_MODEL_DATA_FILE WAKE_MODEL_DIR "/wn9_data"
#define WAKE_SAMPLE_RATE 16000u
#define WAKE_BITS_PER_SAMPLE 16u
#define WAKE_CHANNELS 1u
#define WAKE_SYNTH_CHUNKS 64u
#define WAKE_CAPTURE_DEFAULT_STACK 8192u
#define WAKE_CAPTURE_DEFAULT_PRIORITY 2u
#define WAKE_CAPTURE_DEFAULT_CORE 0
#define WAKE_CAPTURE_DEFAULT_TIMEOUT_MS 100u

#if defined(WAKE_USE_ESP_SR) && WAKE_USE_ESP_SR
#define WAKE_REAL_BACKEND 1
#else
#define WAKE_REAL_BACKEND 0
#endif

typedef struct wake_instance_t {
    const module_host_api_v2 *host;
    uint32_t created_ms;
    uint32_t selftest_count;
    uint32_t feed_count;
    uint32_t frames_fed;
    uint32_t samples_fed;
    int32_t last_state;
    uint8_t last_detected;
    uint8_t real_backend;
    int32_t sample_rate;
    int32_t chunk_samples;
    int32_t channel_count;
    int32_t word_count;
    int32_t model_count;
    int16_t *chunk_scratch;
    size_t chunk_scratch_bytes;
    void *capture_stream;
    void *capture_task;
    uint8_t *capture_raw;
    size_t capture_raw_bytes;
    size_t capture_raw_fill;
    volatile uint8_t capture_running;
    volatile uint8_t capture_stop;
    volatile uint32_t capture_detections;
    uint32_t capture_reported_detections;
    uint32_t capture_frames;
    uint32_t capture_read_timeout_ms;
    int capture_gain_shift;
    char capture_pack[4];
    char last_error[128];
#if WAKE_REAL_BACKEND
    srmodel_list_t *models;
    const esp_wn_iface_t *iface;
    model_iface_data_t *model_data;
#endif
} wake_instance_t;

static const module_host_api_v2 *s_host = NULL;
#if WAKE_REAL_BACKEND
static srmodel_list_t *s_wake_static_srmodels = NULL;
#endif

static void wake_capture_stop(wake_instance_t *inst);

#define WAKE_ALLOC_MAGIC 0x57414C4Cu
#define WAKE_FILE_MAGIC 0x57464C45u
#define WAKE_QUEUE_MAGIC 0x57514D54u
#define WAKE_MALLOC_CAP_32BIT (1u << 1)
#define WAKE_MALLOC_CAP_8BIT (1u << 2)
#define WAKE_MALLOC_CAP_DMA (1u << 3)
#define WAKE_MALLOC_CAP_SPIRAM (1u << 10)
#define WAKE_MALLOC_CAP_INTERNAL (1u << 11)
#define WAKE_PD_PASS 1
#define WAKE_PD_FAIL 0

typedef struct wake_alloc_header_t {
    uint32_t magic;
    void *raw;
} wake_alloc_header_t;

typedef struct wake_queue_t {
    uint32_t magic;
} wake_queue_t;

typedef struct wake_file_t {
    uint32_t magic;
    void *handle;
} wake_file_t;

char _ctype_[257];
static int s_wake_errno;

int *__errno(void)
{
    return &s_wake_errno;
}

static uint32_t wake_heap_caps_from_idf(uint32_t caps)
{
    uint32_t out_caps = MODULE_HEAP_DEFAULT;
    if (caps & WAKE_MALLOC_CAP_INTERNAL) {
        out_caps |= MODULE_HEAP_INTERNAL;
    }
    if (caps & WAKE_MALLOC_CAP_SPIRAM) {
        out_caps |= MODULE_HEAP_PSRAM;
    }
    if (caps & WAKE_MALLOC_CAP_DMA) {
        out_caps |= MODULE_HEAP_DMA;
    }
    if (caps & WAKE_MALLOC_CAP_8BIT) {
        out_caps |= MODULE_HEAP_8BIT;
    }
    if (caps & WAKE_MALLOC_CAP_32BIT) {
        out_caps |= MODULE_HEAP_32BIT;
    }
    return out_caps;
}

static int wake_heap_ready(void)
{
    return s_host && s_host->heap.malloc && s_host->heap.calloc && s_host->heap.realloc && s_host->heap.free;
}

static void *wake_heap_malloc(size_t size, uint32_t caps)
{
    void *ptr = NULL;
    uint32_t requested_caps = MODULE_HEAP_DEFAULT;
    if (size == 0) {
        size = 1;
    }
    if (!wake_heap_ready()) {
        return NULL;
    }
    requested_caps = wake_heap_caps_from_idf(caps);
    /* ESP-SR asks for several non-DMA work buffers with INTERNAL set.  They
     * are ordinary cached inference data, so prefer PSRAM for those blocks.
     * Keep real DMA allocations in internal RAM and retain the exact request
     * as the fallback for compatibility. */
    if ((caps & WAKE_MALLOC_CAP_INTERNAL) && !(caps & WAKE_MALLOC_CAP_DMA)) {
        uint32_t psram_caps = MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT;
        if (caps & WAKE_MALLOC_CAP_32BIT) {
            psram_caps |= MODULE_HEAP_32BIT;
        }
        ptr = s_host->heap.malloc(size, psram_caps);
    }
    if (!ptr) {
        ptr = s_host->heap.malloc(size, requested_caps);
    }
    if (!ptr) {
        ptr = s_host->heap.malloc(size, MODULE_HEAP_DEFAULT);
    }
    return ptr;
}

static int wake_is_aligned_alloc(const void *ptr, wake_alloc_header_t **out_header)
{
    wake_alloc_header_t *hdr = NULL;
    if (!ptr) {
        return 0;
    }
    hdr = ((wake_alloc_header_t *)ptr) - 1;
    if (hdr->magic == WAKE_ALLOC_MAGIC && hdr->raw) {
        if (out_header) {
            *out_header = hdr;
        }
        return 1;
    }
    return 0;
}

void *memcpy(void *dst, const void *src, size_t n)
{
    unsigned char *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;
    while (n--) {
        *d++ = *s++;
    }
    return dst;
}

void *memmove(void *dst, const void *src, size_t n)
{
    unsigned char *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;
    if (d == s || n == 0) {
        return dst;
    }
    if (d < s) {
        return memcpy(dst, src, n);
    }
    d += n;
    s += n;
    while (n--) {
        *--d = *--s;
    }
    return dst;
}

void *memset(void *dst, int value, size_t n)
{
    unsigned char *d = (unsigned char *)dst;
    while (n--) {
        *d++ = (unsigned char)value;
    }
    return dst;
}

int memcmp(const void *a, const void *b, size_t n)
{
    const unsigned char *pa = (const unsigned char *)a;
    const unsigned char *pb = (const unsigned char *)b;
    while (n--) {
        if (*pa != *pb) {
            return (int)*pa - (int)*pb;
        }
        ++pa;
        ++pb;
    }
    return 0;
}

void bzero(void *dst, size_t n)
{
    (void)memset(dst, 0, n);
}

size_t strlen(const char *s)
{
    const char *p = s;
    if (!s) {
        return 0;
    }
    while (*p) {
        ++p;
    }
    return (size_t)(p - s);
}

char *strcpy(char *dst, const char *src)
{
    char *out = dst;
    while ((*dst++ = *src++) != '\0') {
    }
    return out;
}

char *strncpy(char *dst, const char *src, size_t n)
{
    size_t i = 0;
    for (; i < n && src[i]; ++i) {
        dst[i] = src[i];
    }
    for (; i < n; ++i) {
        dst[i] = '\0';
    }
    return dst;
}

char *strcat(char *dst, const char *src)
{
    char *out = dst;
    dst += strlen(dst);
    while ((*dst++ = *src++) != '\0') {
    }
    return out;
}

char *strchr(const char *s, int c)
{
    char needle = (char)c;
    if (!s) {
        return NULL;
    }
    while (*s) {
        if (*s == needle) {
            return (char *)s;
        }
        ++s;
    }
    return needle == '\0' ? (char *)s : NULL;
}

char *strrchr(const char *s, int c)
{
    char needle = (char)c;
    const char *last = NULL;
    if (!s) {
        return NULL;
    }
    do {
        if (*s == needle) {
            last = s;
        }
    } while (*s++);
    return (char *)last;
}

int strcmp(const char *a, const char *b)
{
    const unsigned char *pa = (const unsigned char *)a;
    const unsigned char *pb = (const unsigned char *)b;
    while (*pa && *pa == *pb) {
        ++pa;
        ++pb;
    }
    return (int)*pa - (int)*pb;
}

int strncmp(const char *a, const char *b, size_t n)
{
    const unsigned char *pa = (const unsigned char *)a;
    const unsigned char *pb = (const unsigned char *)b;
    while (n--) {
        if (*pa != *pb || *pa == 0 || *pb == 0) {
            return (int)*pa - (int)*pb;
        }
        ++pa;
        ++pb;
    }
    return 0;
}

char *strstr(const char *haystack, const char *needle)
{
    size_t nlen = strlen(needle);
    if (!needle || nlen == 0) {
        return (char *)haystack;
    }
    while (haystack && *haystack) {
        if (strncmp(haystack, needle, nlen) == 0) {
            return (char *)haystack;
        }
        ++haystack;
    }
    return NULL;
}

static int wake_is_space_char(char c)
{
    return c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\v' || c == '\f';
}

static int wake_is_digit_char(char c)
{
    return c >= '0' && c <= '9';
}

double strtod(const char *nptr, char **endptr)
{
    const char *p = nptr;
    double sign = 1.0;
    double value = 0.0;
    double scale = 0.1;
    if (!p) {
        if (endptr) {
            *endptr = (char *)nptr;
        }
        return 0.0;
    }
    while (wake_is_space_char(*p)) {
        ++p;
    }
    if (*p == '-' || *p == '+') {
        sign = (*p == '-') ? -1.0 : 1.0;
        ++p;
    }
    while (wake_is_digit_char(*p)) {
        value = value * 10.0 + (double)(*p - '0');
        ++p;
    }
    if (*p == '.') {
        ++p;
        while (wake_is_digit_char(*p)) {
            value += (double)(*p - '0') * scale;
            scale *= 0.1;
            ++p;
        }
    }
    if (endptr) {
        *endptr = (char *)p;
    }
    return sign * value;
}

float strtof(const char *nptr, char **endptr)
{
    return (float)strtod(nptr, endptr);
}

char *strtok(char *str, const char *delim)
{
    static char *next;
    char *start = str ? str : next;
    if (!start || !delim) {
        return NULL;
    }
    while (*start && strchr(delim, *start)) {
        ++start;
    }
    if (!*start) {
        next = NULL;
        return NULL;
    }
    next = start;
    while (*next && !strchr(delim, *next)) {
        ++next;
    }
    if (*next) {
        *next++ = '\0';
    }
    return start;
}

void *malloc(size_t size)
{
    return wake_heap_malloc(size, WAKE_MALLOC_CAP_SPIRAM | WAKE_MALLOC_CAP_8BIT);
}

void *calloc(size_t n, size_t size)
{
    if (size && n > ((size_t)-1) / size) {
        return NULL;
    }
    if (wake_heap_ready()) {
        void *ptr = s_host->heap.calloc(n, size, MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
        if (!ptr) {
            ptr = s_host->heap.calloc(n, size, MODULE_HEAP_DEFAULT);
        }
        return ptr;
    }
    return NULL;
}

void *realloc(void *ptr, size_t size)
{
    wake_alloc_header_t *hdr = NULL;
    if (!ptr) {
        return malloc(size);
    }
    if (size == 0) {
        free(ptr);
        return NULL;
    }
    if (wake_is_aligned_alloc(ptr, &hdr)) {
        (void)hdr;
        return NULL;
    }
    if (!wake_heap_ready()) {
        return NULL;
    }
    return s_host->heap.realloc(ptr, size, MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
}

void free(void *ptr)
{
    wake_alloc_header_t *hdr = NULL;
    if (!ptr || !wake_heap_ready()) {
        return;
    }
    if (wake_is_aligned_alloc(ptr, &hdr)) {
        hdr->magic = 0;
        s_host->heap.free(hdr->raw);
        return;
    }
    s_host->heap.free(ptr);
}

void *heap_caps_malloc(size_t size, uint32_t caps)
{
    return wake_heap_malloc(size, caps);
}

void *heap_caps_calloc(size_t n, size_t size, uint32_t caps)
{
    void *ptr = NULL;
    if (size && n > ((size_t)-1) / size) {
        return NULL;
    }
    if (!wake_heap_ready()) {
        return NULL;
    }
    ptr = wake_heap_malloc(n * size, caps);
    if (ptr) {
        memset(ptr, 0, n * size);
    }
    return ptr;
}

void *heap_caps_aligned_alloc(size_t alignment, size_t size, uint32_t caps)
{
    uintptr_t raw_addr = 0;
    uintptr_t aligned = 0;
    wake_alloc_header_t *hdr = NULL;
    void *raw = NULL;
    if (alignment < sizeof(void *)) {
        alignment = sizeof(void *);
    }
    if ((alignment & (alignment - 1u)) != 0) {
        return NULL;
    }
    raw = wake_heap_malloc(size + alignment + sizeof(wake_alloc_header_t), caps);
    if (!raw) {
        return NULL;
    }
    raw_addr = (uintptr_t)raw + sizeof(wake_alloc_header_t);
    aligned = (raw_addr + alignment - 1u) & ~(uintptr_t)(alignment - 1u);
    hdr = ((wake_alloc_header_t *)aligned) - 1;
    hdr->magic = WAKE_ALLOC_MAGIC;
    hdr->raw = raw;
    return (void *)aligned;
}

void heap_caps_free(void *ptr)
{
    free(ptr);
}

void heap_caps_aligned_free(void *ptr)
{
    free(ptr);
}

static uint32_t wake_file_mode_from_stdio(const char *mode)
{
    uint32_t out_mode = MODULE_FILE_READ;
    if (!mode) {
        return out_mode;
    }
    if (strchr(mode, 'w')) {
        out_mode = MODULE_FILE_WRITE | MODULE_FILE_CREATE | MODULE_FILE_TRUNC;
    } else if (strchr(mode, 'a')) {
        out_mode = MODULE_FILE_WRITE | MODULE_FILE_APPEND | MODULE_FILE_CREATE;
    }
    if (strchr(mode, '+')) {
        out_mode |= MODULE_FILE_READ | MODULE_FILE_WRITE;
    }
    return out_mode;
}

static int wake_file_open_path(const char *path, uint32_t mode, void **out_file)
{
    int32_t err = MODULE_ERR_UNSUPPORTED;
    if (!s_host || !s_host->sd.open || !path || !out_file) {
        return -1;
    }
    *out_file = NULL;
    err = s_host->sd.open(path, mode, out_file);
    if (err != MODULE_OK && strncmp(path, "/sd/", 4) == 0) {
        err = s_host->sd.open(path + 3, mode, out_file);
    }
    return err == MODULE_OK && *out_file ? 0 : -1;
}

FILE *fopen(const char *path, const char *mode)
{
    wake_file_t *file = NULL;
    void *handle = NULL;
    if (wake_file_open_path(path, wake_file_mode_from_stdio(mode), &handle) != 0) {
        return NULL;
    }
    file = (wake_file_t *)calloc(1, sizeof(*file));
    if (!file) {
        if (s_host && s_host->file.close) {
            s_host->file.close(handle);
        }
        return NULL;
    }
    file->magic = WAKE_FILE_MAGIC;
    file->handle = handle;
    return (FILE *)file;
}

size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream)
{
    wake_file_t *file = (wake_file_t *)stream;
    size_t out_read = 0;
    size_t bytes = 0;
    if (!file || file->magic != WAKE_FILE_MAGIC || !ptr || size == 0 || nmemb == 0) {
        return 0;
    }
    if (nmemb > ((size_t)-1) / size) {
        return 0;
    }
    bytes = size * nmemb;
    if (!s_host || !s_host->file.read ||
        s_host->file.read(file->handle, ptr, bytes, &out_read) != MODULE_OK) {
        return 0;
    }
    return out_read / size;
}

int fseek(FILE *stream, long offset, int whence)
{
    wake_file_t *file = (wake_file_t *)stream;
    uint32_t mode = MODULE_SEEK_SET;
    if (!file || file->magic != WAKE_FILE_MAGIC || !s_host || !s_host->file.seek) {
        return -1;
    }
    if (whence == SEEK_CUR) {
        mode = MODULE_SEEK_CUR;
    } else if (whence == SEEK_END) {
        mode = MODULE_SEEK_END;
    }
    return s_host->file.seek(file->handle, (int64_t)offset, mode) == MODULE_OK ? 0 : -1;
}

long ftell(FILE *stream)
{
    wake_file_t *file = (wake_file_t *)stream;
    uint64_t pos = 0;
    if (!file || file->magic != WAKE_FILE_MAGIC || !s_host || !s_host->file.position) {
        return -1;
    }
    if (s_host->file.position(file->handle, &pos) != MODULE_OK) {
        return -1;
    }
    return (long)pos;
}

int fclose(FILE *stream)
{
    wake_file_t *file = (wake_file_t *)stream;
    int ok = 0;
    if (!file || file->magic != WAKE_FILE_MAGIC) {
        return -1;
    }
    if (s_host && s_host->file.close) {
        ok = s_host->file.close(file->handle) == MODULE_OK;
    }
    file->magic = 0;
    free(file);
    return ok ? 0 : -1;
}

static void wake_write_text(const char *text)
{
    if (s_host && s_host->serial.print && text) {
        s_host->serial.print(text);
    }
}

static void wake_append_char(char *dst, size_t size, size_t *pos, char c)
{
    if (dst && size > 0 && *pos + 1 < size) {
        dst[*pos] = c;
    }
    (*pos)++;
}

static void wake_append_text(char *dst, size_t size, size_t *pos, const char *text)
{
    if (!text) {
        text = "(null)";
    }
    while (*text) {
        wake_append_char(dst, size, pos, *text++);
    }
}

static void wake_append_uint(char *dst, size_t size, size_t *pos, uint64_t value, unsigned base, int upper)
{
    char buf[32];
    size_t n = 0;
    const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    if (base < 2) {
        base = 10;
    }
    do {
        buf[n++] = digits[value % base];
        value /= base;
    } while (value && n < sizeof(buf));
    while (n) {
        wake_append_char(dst, size, pos, buf[--n]);
    }
}

static int wake_vformat(char *dst, size_t size, const char *fmt, va_list ap)
{
    size_t pos = 0;
    if (!fmt) {
        fmt = "";
    }
    while (*fmt) {
        if (*fmt != '%') {
            wake_append_char(dst, size, &pos, *fmt++);
            continue;
        }
        ++fmt;
        while (*fmt == '0' || (*fmt >= '1' && *fmt <= '9') || *fmt == '.' || *fmt == '-') {
            ++fmt;
        }
        if (*fmt == 'l') {
            ++fmt;
            if (*fmt == 'l') {
                ++fmt;
            }
        } else if (*fmt == 'z') {
            ++fmt;
        }
        switch (*fmt) {
        case 's':
            wake_append_text(dst, size, &pos, va_arg(ap, const char *));
            break;
        case 'c':
            wake_append_char(dst, size, &pos, (char)va_arg(ap, int));
            break;
        case 'd':
        case 'i': {
            int value = va_arg(ap, int);
            if (value < 0) {
                wake_append_char(dst, size, &pos, '-');
                wake_append_uint(dst, size, &pos, (uint64_t)(-(int64_t)value), 10, 0);
            } else {
                wake_append_uint(dst, size, &pos, (uint64_t)value, 10, 0);
            }
            break;
        }
        case 'u':
            wake_append_uint(dst, size, &pos, (uint64_t)va_arg(ap, unsigned int), 10, 0);
            break;
        case 'x':
            wake_append_uint(dst, size, &pos, (uint64_t)va_arg(ap, unsigned int), 16, 0);
            break;
        case 'X':
            wake_append_uint(dst, size, &pos, (uint64_t)va_arg(ap, unsigned int), 16, 1);
            break;
        case 'p':
            wake_append_text(dst, size, &pos, "0x");
            wake_append_uint(dst, size, &pos, (uintptr_t)va_arg(ap, void *), 16, 0);
            break;
        case '%':
            wake_append_char(dst, size, &pos, '%');
            break;
        case '\0':
            --fmt;
            break;
        default:
            wake_append_char(dst, size, &pos, '%');
            wake_append_char(dst, size, &pos, *fmt);
            break;
        }
        if (*fmt) {
            ++fmt;
        }
    }
    if (dst && size > 0) {
        dst[pos < size ? pos : size - 1u] = '\0';
    }
    return (int)pos;
}

int vsnprintf(char *str, size_t size, const char *fmt, va_list ap)
{
    return wake_vformat(str, size, fmt, ap);
}

int snprintf(char *str, size_t size, const char *fmt, ...)
{
    int n;
    va_list ap;
    va_start(ap, fmt);
    n = wake_vformat(str, size, fmt, ap);
    va_end(ap);
    return n;
}

int sprintf(char *str, const char *fmt, ...)
{
    int n;
    va_list ap;
    va_start(ap, fmt);
    n = wake_vformat(str, (size_t)-1, fmt, ap);
    va_end(ap);
    return n;
}

int printf(const char *fmt, ...)
{
    char buf[192];
    int n;
    va_list ap;
    va_start(ap, fmt);
    n = wake_vformat(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    wake_write_text(buf);
    return n;
}

int puts(const char *s)
{
    if (s_host && s_host->serial.println) {
        s_host->serial.println(s ? s : "");
    }
    return (int)strlen(s);
}

uint32_t esp_log_timestamp(void)
{
    return (s_host && s_host->time.millis) ? s_host->time.millis() : 0;
}

const char *esp_err_to_name(int err)
{
    (void)err;
    return "ESP_ERR";
}

void esp_log(uint32_t config, const char *tag, const char *format, ...)
{
    char buf[192];
    int n = 0;
    va_list ap;
    (void)config;
    if (tag) {
        wake_write_text(tag);
        wake_write_text(": ");
    }
    va_start(ap, format);
    n = wake_vformat(buf, sizeof(buf), format, ap);
    va_end(ap);
    (void)n;
    wake_write_text(buf);
    wake_write_text("\n");
}

void _esp_error_check_failed(int rc, const char *file, int line, const char *function, const char *expression)
{
    (void)rc;
    (void)file;
    (void)line;
    (void)function;
    (void)expression;
    if (s_host && s_host->serial.println) {
        s_host->serial.println("[wake.so] ESP_ERROR_CHECK failed");
    }
    for (;;) {
        if (s_host && s_host->time.delay) {
            s_host->time.delay(1000);
        }
    }
}

void __assert_func(const char *file, int line, const char *function, const char *expression)
{
    (void)file;
    (void)line;
    (void)function;
    (void)expression;
    if (s_host && s_host->serial.println) {
        s_host->serial.println("[wake.so] assert failed");
    }
    for (;;) {
        if (s_host && s_host->time.delay) {
            s_host->time.delay(1000);
        }
    }
}

uint32_t Cache_Start_DCache_Preload(uint32_t addr, uint32_t size, uint32_t order)
{
    (void)addr;
    (void)size;
    (void)order;
    return 0;
}

uint32_t Cache_DCache_Preload_Done(void)
{
    return 1;
}

QueueHandle_t xQueueCreateMutex(const uint8_t queue_type)
{
    wake_queue_t *queue = NULL;
    (void)queue_type;
    queue = (wake_queue_t *)calloc(1, sizeof(*queue));
    if (queue) {
        queue->magic = WAKE_QUEUE_MAGIC;
    }
    return (QueueHandle_t)queue;
}

void vQueueDelete(QueueHandle_t queue)
{
    wake_queue_t *q = (wake_queue_t *)queue;
    if (q && q->magic == WAKE_QUEUE_MAGIC) {
        q->magic = 0;
        free(q);
    }
}

BaseType_t xQueueGenericSend(QueueHandle_t queue,
                             const void * const item,
                             TickType_t ticks,
                             const BaseType_t copy_position)
{
    (void)item;
    (void)ticks;
    (void)copy_position;
    return queue ? WAKE_PD_PASS : WAKE_PD_FAIL;
}

BaseType_t xQueueSemaphoreTake(QueueHandle_t queue, TickType_t ticks)
{
    (void)ticks;
    return queue ? WAKE_PD_PASS : WAKE_PD_FAIL;
}

static const module_manifest_t s_manifest = {
    MODULE_MANIFEST_MAGIC,
    MODULE_SDK_VERSION,
    sizeof(module_manifest_t),
    "wake",
    WAKE_VERSION,
    "WakeNet9s nihaoxiaozhi dynamic module",
    0,
    MODULE_BOOTSTRAP_ABI_VERSION,
};

/**
 * @brief Write a short diagnostic line to the firmware serial log.
 */
static void wake_trace(wake_instance_t *inst, const char *msg)
{
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    if (host && host->serial.println && msg) {
        host->serial.println(msg);
    }
}

/**
 * @brief Copy a short status/error string into the instance.
 */
static void wake_set_error(wake_instance_t *inst, const char *msg)
{
    size_t i = 0;
    if (!inst) {
        return;
    }
    if (!msg) {
        msg = "";
    }
    while (msg[i] && i + 1 < sizeof(inst->last_error)) {
        inst->last_error[i] = msg[i];
        ++i;
    }
    inst->last_error[i] = '\0';
}

/**
 * @brief Push a NodeMCU-style `(nil, err)` result.
 */
static int push_error(lua_State *L, const module_host_api_v2 *host, const char *msg)
{
    host->lua.pushnil(L);
    host->lua.pushstring(L, msg ? msg : "wake failed");
    return 2;
}

/**
 * @brief Fetch the module instance captured by a Lua closure.
 */
static wake_instance_t *instance_from_lua(lua_State *L)
{
    if (!s_host || !s_host->lua.touserdata || !s_host->lua.upvalue_index) {
        return NULL;
    }
    return (wake_instance_t *)s_host->lua.touserdata(L, s_host->lua.upvalue_index(1));
}

/**
 * @brief Set a string field on the Lua table at stack top.
 */
static void set_string_field(lua_State *L, const module_host_api_v2 *host, const char *key, const char *value)
{
    host->lua.pushstring(L, value ? value : "");
    host->lua.setfield(L, -2, key);
}

/**
 * @brief Set an integer field on the Lua table at stack top.
 */
static void set_integer_field(lua_State *L, const module_host_api_v2 *host, const char *key, int64_t value)
{
    host->lua.pushinteger(L, value);
    host->lua.setfield(L, -2, key);
}

/**
 * @brief Set a boolean field on the Lua table at stack top.
 */
static void set_boolean_field(lua_State *L, const module_host_api_v2 *host, const char *key, int value)
{
    host->lua.pushboolean(L, value ? 1 : 0);
    host->lua.setfield(L, -2, key);
}

static int wake_read_int_field(lua_State *L,
                               const module_host_api_v2 *host,
                               int table_idx,
                               const char *key,
                               int fallback)
{
    int value = fallback;
    const int top = host->lua.gettop(L);
    host->lua.getfield(L, table_idx, key);
    if (host->lua.isnumber(L, -1)) {
        value = (int)host->lua.tointeger(L, -1);
    }
    host->lua.settop(L, top);
    return value;
}

static const char *wake_read_string_field(lua_State *L,
                                          const module_host_api_v2 *host,
                                          int table_idx,
                                          const char *key,
                                          const char *fallback)
{
    const char *value = fallback;
    const int top = host->lua.gettop(L);
    host->lua.getfield(L, table_idx, key);
    if (host->lua.isstring(L, -1)) {
        value = host->lua.tostring(L, -1);
    }
    host->lua.settop(L, top);
    return value ? value : fallback;
}

/**
 * @brief Register a Lua C closure that captures this module instance.
 */
static void set_function_field(lua_State *L,
                               const module_host_api_v2 *host,
                               const char *key,
                               module_lua_cfunction_t fn,
                               wake_instance_t *inst)
{
    host->lua.pushlightuserdata(L, inst);
    host->lua.pushcclosure(L, fn, 1);
    host->lua.setfield(L, -2, key);
}

/**
 * @brief Return true if the host Lua ABI has a field appended after v1.
 */
static int host_has_lua_field(const module_host_api_v2 *host, size_t offset, size_t field_size)
{
    return host && host->lua.size >= offset + field_size;
}

/**
 * @brief Generate deterministic 16 kHz s16 mono samples for wiring tests.
 */
static int16_t synth_sample(uint32_t index)
{
    const int32_t phase = (int32_t)(index % 96u);
    const int32_t tri = phase < 48 ? phase : (95 - phase);
    const int32_t centered = (tri * 2) - 47;
    return (int16_t)(centered * 220);
}

/**
 * @brief Return true when the real WakeNet model has been created.
 */
static int wake_is_initialized(wake_instance_t *inst)
{
#if WAKE_REAL_BACKEND
    return inst && inst->model_data;
#else
    (void)inst;
    return 0;
#endif
}

#if WAKE_REAL_BACKEND
/**
 * @brief Duplicate a small static model string into module-managed heap.
 */
static char *wake_strdup_model(const char *text)
{
    size_t len = strlen(text) + 1u;
    char *out = (char *)calloc(1, len);
    if (out) {
        memcpy(out, text, len);
    }
    return out;
}

/**
 * @brief Build the fixed WakeNet model list without pulling ESP-SR model_path I/O code.
 */
static srmodel_list_t *wake_create_builtin_model_list(void)
{
    srmodel_list_t *models = (srmodel_list_t *)calloc(1, sizeof(*models));
    if (!models) {
        return NULL;
    }
    models->model_name = (char **)calloc(1, sizeof(char *));
    models->model_info = (char **)calloc(1, sizeof(char *));
    if (!models->model_name || !models->model_info) {
        free(models->model_name);
        free(models->model_info);
        free(models);
        return NULL;
    }
    models->model_name[0] = wake_strdup_model(WAKE_MODEL);
    models->model_info[0] = wake_strdup_model("WakeNet9s_nihaoxiaozhi");
    if (!models->model_name[0] || !models->model_info[0]) {
        free(models->model_name[0]);
        free(models->model_info[0]);
        free(models->model_name);
        free(models->model_info);
        free(models);
        return NULL;
    }
    models->num = 1;
    s_wake_static_srmodels = models;
    return models;
}

/**
 * @brief Release the fixed model list allocated by wake_create_builtin_model_list().
 */
static void wake_destroy_builtin_model_list(srmodel_list_t *models)
{
    if (!models) {
        return;
    }
    if (models->num > 0) {
        for (int i = 0; i < models->num; ++i) {
            free(models->model_name ? models->model_name[i] : NULL);
            free(models->model_info ? models->model_info[i] : NULL);
        }
    }
    free(models->model_name);
    free(models->model_info);
    if (s_wake_static_srmodels == models) {
        s_wake_static_srmodels = NULL;
    }
    free(models);
}

/**
 * @brief Return the model index in a fixed ESP-SR model list.
 */
static int wake_model_exists(const srmodel_list_t *models, const char *model_name)
{
    if (!models || !model_name) {
        return -1;
    }
    for (int i = 0; i < models->num; ++i) {
        if (models->model_name && models->model_name[i] && strcmp(models->model_name[i], model_name) == 0) {
            return i;
        }
    }
    return -1;
}

/**
 * @brief Check one SD file through the host API without entering ESP-SR I/O.
 */
static int wake_sd_file_exists(wake_instance_t *inst, const char *path)
{
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    if (!host || !host->sd.exists || !path) {
        return 0;
    }
    return host->sd.exists(path) > 0;
}

/**
 * @brief Verify the WakeNet files that the prebuilt loader opens during create().
 */
static int wake_required_model_files_ready(wake_instance_t *inst, const char **out_missing)
{
    if (out_missing) {
        *out_missing = NULL;
    }
    if (inst && inst->host && inst->host->sd.begin) {
        (void)inst->host->sd.begin();
    }
    if (!wake_sd_file_exists(inst, WAKE_MODEL_INDEX_FILE)) {
        if (out_missing) {
            *out_missing = WAKE_MODEL_INDEX_FILE;
        }
        return 0;
    }
    if (!wake_sd_file_exists(inst, WAKE_MODEL_DATA_FILE)) {
        if (out_missing) {
            *out_missing = WAKE_MODEL_DATA_FILE;
        }
        return 0;
    }
    return 1;
}

/**
 * @brief ESP-SR compatibility entry used by WakeNet prebuilt objects.
 */
char *get_model_base_path(void)
{
    return (char *)WAKE_MODEL_PATH_STRING;
}

/**
 * @brief ESP-SR compatibility entry used by WakeNet prebuilt objects.
 */
srmodel_list_t *get_static_srmodels(void)
{
    return s_wake_static_srmodels;
}

/**
 * @brief Release the WakeNet runtime instance while keeping the SD model list cached.
 */
static void wake_deinit_backend(wake_instance_t *inst)
{
    if (!inst) {
        return;
    }
    if (inst->iface && inst->model_data) {
        inst->iface->destroy(inst->model_data);
    }
    inst->iface = NULL;
    inst->model_data = NULL;
    inst->sample_rate = 0;
    inst->chunk_samples = 0;
    inst->channel_count = 0;
    inst->word_count = 0;
    inst->real_backend = WAKE_REAL_BACKEND;
}

/**
 * @brief Release all ESP-SR resources when the module is being unloaded.
 */
static void wake_destroy_backend(wake_instance_t *inst)
{
    if (!inst) {
        return;
    }
    wake_deinit_backend(inst);
    if (inst->models) {
        wake_destroy_builtin_model_list(inst->models);
    }
    inst->models = NULL;
    inst->model_count = 0;
    if (inst->chunk_scratch) {
        inst->host->heap.free(inst->chunk_scratch);
        inst->chunk_scratch = NULL;
        inst->chunk_scratch_bytes = 0;
    }
}

/**
 * @brief Load the app-local WakeNet9s model and create the runtime instance.
 */
static int wake_init_backend(wake_instance_t *inst)
{
    int model_index = -1;
    const char *missing_file = NULL;
    if (!inst) {
        return MODULE_ERR_INVALID_ARG;
    }
    if (inst->model_data) {
        return MODULE_OK;
    }

    wake_set_error(inst, "");
    if (!inst->models) {
        inst->models = wake_create_builtin_model_list();
    }
    if (!inst->models || inst->models->num <= 0) {
        wake_set_error(inst, "wake: failed to create ESP-SR model list");
        wake_deinit_backend(inst);
        return MODULE_ERR_NOT_FOUND;
    }
    inst->model_count = inst->models->num;

    model_index = wake_model_exists(inst->models, WAKE_MODEL);
    if (model_index < 0) {
        wake_set_error(inst, "wake: wn9s_nihaoxiaozhi model missing");
        wake_deinit_backend(inst);
        return MODULE_ERR_NOT_FOUND;
    }

    if (!wake_required_model_files_ready(inst, &missing_file)) {
        char msg[128];
        snprintf(msg, sizeof(msg), "wake: missing %s", missing_file ? missing_file : "model files");
        wake_set_error(inst, msg);
        wake_deinit_backend(inst);
        return MODULE_ERR_NOT_FOUND;
    }

    inst->iface = esp_wn_handle_from_name(WAKE_MODEL);
    if (!inst->iface) {
        wake_set_error(inst, "wake: esp_wn_handle_from_name failed");
        wake_deinit_backend(inst);
        return MODULE_ERR_UNSUPPORTED;
    }

    inst->model_data = inst->iface->create(WAKE_MODEL, DET_MODE_90);
    if (!inst->model_data) {
        wake_set_error(inst, "wake: WakeNet create failed");
        wake_deinit_backend(inst);
        return MODULE_ERR_NO_MEMORY;
    }

    inst->sample_rate = inst->iface->get_samp_rate(inst->model_data);
    inst->chunk_samples = inst->iface->get_samp_chunksize(inst->model_data);
    inst->channel_count = inst->iface->get_channel_num(inst->model_data);
    inst->word_count = inst->iface->get_word_num(inst->model_data);
    if (inst->channel_count <= 0) {
        inst->channel_count = 1;
    }
    if (inst->chunk_samples <= 0 || inst->sample_rate <= 0) {
        wake_set_error(inst, "wake: invalid WakeNet audio geometry");
        wake_deinit_backend(inst);
        return MODULE_ERR_BAD_STATE;
    }

    inst->real_backend = 1;
    return MODULE_OK;
}

/**
 * @brief Reset the WakeNet history window before a controlled test.
 */
static void wake_clean_backend(wake_instance_t *inst)
{
    if (inst && inst->iface && inst->model_data && inst->iface->clean) {
        inst->iface->clean(inst->model_data);
    }
}

static int16_t wake_clip_s16(int32_t value)
{
    if (value > 32767) {
        return 32767;
    }
    if (value < -32768) {
        return -32768;
    }
    return (int16_t)value;
}

static int wake_ensure_chunk_scratch(wake_instance_t *inst, size_t chunk_bytes)
{
    int16_t *scratch = NULL;
    if (!inst || !inst->host || chunk_bytes == 0) {
        return MODULE_ERR_INVALID_ARG;
    }
    if (inst->chunk_scratch && inst->chunk_scratch_bytes >= chunk_bytes) {
        return MODULE_OK;
    }
    if (inst->chunk_scratch) {
        inst->host->heap.free(inst->chunk_scratch);
        inst->chunk_scratch = NULL;
        inst->chunk_scratch_bytes = 0;
    }
    scratch = (int16_t *)inst->host->heap.malloc(chunk_bytes, MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    if (!scratch) {
        scratch = (int16_t *)inst->host->heap.malloc(chunk_bytes, MODULE_HEAP_DEFAULT);
    }
    if (!scratch) {
        wake_set_error(inst, "wake.feed: chunk buffer alloc failed");
        return MODULE_ERR_NO_MEMORY;
    }
    inst->chunk_scratch = scratch;
    inst->chunk_scratch_bytes = chunk_bytes;
    return MODULE_OK;
}

static void wake_i2s_pack_offsets(const char *pack, int *lo_off, int *hi_off)
{
    if (pack && strcmp(pack, "b01") == 0) {
        *lo_off = 0;
        *hi_off = 1;
    } else if (pack && strcmp(pack, "b12") == 0) {
        *lo_off = 1;
        *hi_off = 2;
    } else {
        *lo_off = 2;
        *hi_off = 3;
    }
}

/**
 * @brief Feed one or more full WakeNet chunks from an s16 PCM byte buffer.
 */
static int wake_feed_pcm_bytes(wake_instance_t *inst,
                               const uint8_t *pcm,
                               size_t byte_len,
                               uint32_t *out_frames,
                               uint32_t *out_detected,
                               int32_t *out_state)
{
    const module_host_api_v2 *host = inst ? inst->host : NULL;
    uint32_t frames = 0;
    uint32_t detected = 0;
    int32_t state = WAKENET_NO_DETECT;
    size_t chunk_bytes = 0;
    size_t offset = 0;
    int err = MODULE_OK;

    if (!inst || !pcm || byte_len == 0 || !host) {
        return MODULE_ERR_INVALID_ARG;
    }
    err = wake_init_backend(inst);
    if (err != MODULE_OK) {
        return err;
    }

    chunk_bytes = (size_t)inst->chunk_samples * (size_t)inst->channel_count * sizeof(int16_t);
    if (chunk_bytes == 0 || byte_len < chunk_bytes) {
        wake_set_error(inst, "wake.feed: pcm is shorter than one WakeNet chunk");
        return MODULE_ERR_INVALID_ARG;
    }

    err = wake_ensure_chunk_scratch(inst, chunk_bytes);
    if (err != MODULE_OK) {
        return err;
    }

    while (offset + chunk_bytes <= byte_len) {
        memcpy(inst->chunk_scratch, pcm + offset, chunk_bytes);
        state = inst->iface->detect(inst->model_data, inst->chunk_scratch);
        frames++;
        inst->frames_fed++;
        inst->samples_fed += (uint32_t)(chunk_bytes / sizeof(int16_t));
        if (state == WAKENET_DETECTED || state > 0) {
            detected++;
            inst->last_detected = 1;
        }
        inst->last_state = state;
        offset += chunk_bytes;
    }

    if (out_frames) {
        *out_frames = frames;
    }
    if (out_detected) {
        *out_detected = detected;
    }
    if (out_state) {
        *out_state = state;
    }
    return MODULE_OK;
}

static int wake_feed_i2s32_bytes(wake_instance_t *inst,
                                 const uint8_t *raw,
                                 size_t byte_len,
                                 const char *pack,
                                 int gain_shift,
                                 uint32_t *out_frames,
                                 uint32_t *out_detected,
                                 int32_t *out_state)
{
    const module_host_api_v2 *host = inst ? inst->host : NULL;
    uint32_t frames = 0;
    uint32_t detected = 0;
    int32_t state = WAKENET_NO_DETECT;
    size_t chunk_samples = 0;
    size_t chunk_pcm_bytes = 0;
    size_t chunk_raw_bytes = 0;
    size_t offset = 0;
    int lo_off = 2;
    int hi_off = 3;
    int err = MODULE_OK;

    if (!inst || !raw || byte_len == 0 || !host) {
        return MODULE_ERR_INVALID_ARG;
    }
    err = wake_init_backend(inst);
    if (err != MODULE_OK) {
        return err;
    }

    chunk_samples = (size_t)inst->chunk_samples * (size_t)inst->channel_count;
    chunk_pcm_bytes = chunk_samples * sizeof(int16_t);
    chunk_raw_bytes = chunk_samples * 4U;
    if (chunk_raw_bytes == 0 || byte_len < chunk_raw_bytes) {
        wake_set_error(inst, "wake.feed_i2s: raw32 is shorter than one WakeNet chunk");
        return MODULE_ERR_INVALID_ARG;
    }

    err = wake_ensure_chunk_scratch(inst, chunk_pcm_bytes);
    if (err != MODULE_OK) {
        return err;
    }
    if (gain_shift > 8) {
        gain_shift = 8;
    } else if (gain_shift < -8) {
        gain_shift = -8;
    }
    wake_i2s_pack_offsets(pack, &lo_off, &hi_off);

    while (offset + chunk_raw_bytes <= byte_len) {
        for (size_t i = 0; i < chunk_samples; ++i) {
            const size_t base = offset + i * 4U;
            int32_t v = (int32_t)raw[base + (size_t)lo_off] |
                        ((int32_t)raw[base + (size_t)hi_off] << 8);
            if (v >= 32768) {
                v -= 65536;
            }
            if (gain_shift > 0) {
                v <<= gain_shift;
            } else if (gain_shift < 0) {
                v >>= -gain_shift;
            }
            inst->chunk_scratch[i] = wake_clip_s16(v);
        }

        state = inst->iface->detect(inst->model_data, inst->chunk_scratch);
        frames++;
        inst->frames_fed++;
        inst->samples_fed += (uint32_t)chunk_samples;
        if (state == WAKENET_DETECTED || state > 0) {
            detected++;
            inst->last_detected = 1;
        }
        inst->last_state = state;
        offset += chunk_raw_bytes;
    }

    if (out_frames) {
        *out_frames = frames;
    }
    if (out_detected) {
        *out_detected = detected;
    }
    if (out_state) {
        *out_state = state;
    }
    return MODULE_OK;
}

/**
 * @brief Generate synthetic PCM inside the module and feed it to WakeNet.
 */
static int wake_selftest_backend(wake_instance_t *inst,
                                 uint32_t chunks,
                                 uint32_t *out_frames,
                                 uint32_t *out_detected,
                                 int32_t *out_state)
{
    const module_host_api_v2 *host = inst ? inst->host : NULL;
    int16_t *scratch = NULL;
    uint32_t frames = 0;
    uint32_t detected = 0;
    uint32_t sample_index = 0;
    int32_t state = WAKENET_NO_DETECT;
    size_t chunk_samples = 0;
    int err = MODULE_OK;

    if (!inst || !host) {
        return MODULE_ERR_INVALID_ARG;
    }
    err = wake_init_backend(inst);
    if (err != MODULE_OK) {
        return err;
    }
    wake_trace(inst, "[wake.so] selftest begin");
    wake_trace(inst, "[wake.so] selftest skip clean");

    if (chunks == 0) {
        chunks = WAKE_SYNTH_CHUNKS;
    }
    chunk_samples = (size_t)inst->chunk_samples * (size_t)inst->channel_count;
    scratch = (int16_t *)host->heap.malloc(chunk_samples * sizeof(int16_t),
                                           MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT);
    if (!scratch) {
        scratch = (int16_t *)host->heap.malloc(chunk_samples * sizeof(int16_t), MODULE_HEAP_DEFAULT);
    }
    if (!scratch) {
        wake_set_error(inst, "wake.selftest: chunk buffer alloc failed");
        return MODULE_ERR_NO_MEMORY;
    }

    for (uint32_t frame = 0; frame < chunks; ++frame) {
        for (size_t i = 0; i < chunk_samples; ++i) {
            scratch[i] = synth_sample(sample_index++);
        }
        if (frame == 0) {
            wake_trace(inst, "[wake.so] selftest before detect");
        }
        state = inst->iface->detect(inst->model_data, scratch);
        if (frame == 0) {
            wake_trace(inst, "[wake.so] selftest after detect");
        }
        frames++;
        inst->frames_fed++;
        inst->samples_fed += (uint32_t)chunk_samples;
        if (state == WAKENET_DETECTED || state > 0) {
            detected++;
            inst->last_detected = 1;
        }
        inst->last_state = state;
    }

    host->heap.free(scratch);
    if (out_frames) {
        *out_frames = frames;
    }
    if (out_detected) {
        *out_detected = detected;
    }
    if (out_state) {
        *out_state = state;
    }
    return MODULE_OK;
}
#else
/**
 * @brief Keep the module loadable when ESP-SR is not linked into the .so build.
 */
static int wake_init_backend(wake_instance_t *inst)
{
    wake_set_error(inst, "wake: built without ESP-SR backend");
    return inst ? MODULE_ERR_UNSUPPORTED : MODULE_ERR_INVALID_ARG;
}

/**
 * @brief Synthetic fallback for manual ABI smoke tests.
 */
static int wake_selftest_backend(wake_instance_t *inst,
                                 uint32_t chunks,
                                 uint32_t *out_frames,
                                 uint32_t *out_detected,
                                 int32_t *out_state)
{
    uint32_t energy = 0;
    uint32_t sample_count = chunks ? chunks * 160u : WAKE_SYNTH_CHUNKS * 160u;
    if (!inst) {
        return MODULE_ERR_INVALID_ARG;
    }
    for (uint32_t i = 0; i < sample_count; ++i) {
        const int16_t s = synth_sample(i);
        energy += (uint32_t)((s < 0 ? -s : s) >> 8);
    }
    inst->last_state = 0;
    inst->last_detected = 0;
    if (out_frames) {
        *out_frames = chunks ? chunks : WAKE_SYNTH_CHUNKS;
    }
    if (out_detected) {
        *out_detected = 0;
    }
    if (out_state) {
        *out_state = (int32_t)energy;
    }
    wake_set_error(inst, "wake: synthetic fallback, not real WakeNet");
    return MODULE_OK;
}

/**
 * @brief No-op fallback deinit.
 */
static void wake_deinit_backend(wake_instance_t *inst)
{
    if (inst) {
        inst->real_backend = 0;
    }
}

/**
 * @brief No-op fallback unload cleanup.
 */
static void wake_destroy_backend(wake_instance_t *inst)
{
    wake_deinit_backend(inst);
}

/**
 * @brief No-op fallback clean.
 */
static void wake_clean_backend(wake_instance_t *inst)
{
    (void)inst;
}

/**
 * @brief Reject external PCM when ESP-SR is not linked.
 */
static int wake_feed_pcm_bytes(wake_instance_t *inst,
                               const uint8_t *pcm,
                               size_t byte_len,
                               uint32_t *out_frames,
                               uint32_t *out_detected,
                               int32_t *out_state)
{
    (void)pcm;
    (void)byte_len;
    (void)out_frames;
    (void)out_detected;
    (void)out_state;
    wake_set_error(inst, "wake.feed: built without ESP-SR backend");
    return MODULE_ERR_UNSUPPORTED;
}

static int wake_feed_i2s32_bytes(wake_instance_t *inst,
                                 const uint8_t *raw,
                                 size_t byte_len,
                                 const char *pack,
                                 int gain_shift,
                                 uint32_t *out_frames,
                                 uint32_t *out_detected,
                                 int32_t *out_state)
{
    (void)raw;
    (void)byte_len;
    (void)pack;
    (void)gain_shift;
    (void)out_frames;
    (void)out_detected;
    (void)out_state;
    wake_set_error(inst, "wake.feed_i2s: built without ESP-SR backend");
    return MODULE_ERR_UNSUPPORTED;
}
#endif

static void wake_copy_pack(char out[4], const char *pack)
{
    if (!pack || (strcmp(pack, "b01") != 0 && strcmp(pack, "b12") != 0 && strcmp(pack, "b23") != 0)) {
        pack = "b23";
    }
    out[0] = pack[0];
    out[1] = pack[1];
    out[2] = pack[2];
    out[3] = '\0';
}

static void wake_capture_task_entry(void *arg)
{
    wake_instance_t *inst = (wake_instance_t *)arg;
    const module_host_api_v2 *host = inst ? inst->host : NULL;
    if (!inst || !host || !host->i2s.read) {
        return;
    }
    if (host->serial.println) {
        host->serial.println("[wake.so] capture task start");
    }

    while (!inst->capture_stop) {
        size_t got = 0;
        const size_t need = inst->capture_raw_bytes - inst->capture_raw_fill;
        uint32_t frames = 0;
        uint32_t detected = 0;
        int32_t state = 0;
        int err = MODULE_OK;

        if (host->diag.heartbeat) {
            host->diag.heartbeat();
        }
        if (!inst->capture_stream || !inst->capture_raw || need == 0) {
            break;
        }
        err = host->i2s.read(inst->capture_stream,
                             inst->capture_raw + inst->capture_raw_fill,
                             need,
                             &got,
                             inst->capture_read_timeout_ms);
        if (err != MODULE_OK) {
            wake_set_error(inst, "wake.capture: i2s read failed");
            break;
        }
        if (got == 0) {
            if (host->task.delay) {
                host->task.delay(1);
            }
            continue;
        }
        inst->capture_raw_fill += got;
        if (inst->capture_raw_fill < inst->capture_raw_bytes) {
            continue;
        }

        err = wake_feed_i2s32_bytes(inst,
                                    inst->capture_raw,
                                    inst->capture_raw_bytes,
                                    inst->capture_pack,
                                    inst->capture_gain_shift,
                                    &frames,
                                    &detected,
                                    &state);
        inst->capture_raw_fill = 0;
        if (err != MODULE_OK) {
            break;
        }
        inst->feed_count++;
        inst->capture_frames += frames;
        if (detected > 0) {
            inst->capture_detections += detected;
        }
        if (host->task.yield) {
            host->task.yield();
        }
    }

    /* Release I2S before publishing the stopped state.  capture_stop() may run
     * on the Lua task; making the worker perform the normal release closes the
     * window where Lua observes capture_running == 0 while the port is still
     * owned by this module. */
    if (inst->capture_stream && host->i2s.end) {
        void *stream = inst->capture_stream;
        inst->capture_stream = NULL;
        if (host->i2s.end(stream) != MODULE_OK) {
            wake_set_error(inst, "wake.capture: i2s release failed");
        }
    }
    inst->capture_running = 0;
    if (host->serial.println) {
        host->serial.println("[wake.so] capture task stop");
    }
    /* The host task trampoline owns task unregister/delete after return. */
}

static void wake_capture_stop(wake_instance_t *inst)
{
    const module_host_api_v2 *host = inst ? inst->host : NULL;
    uint32_t start_ms = 0;
    if (!inst || !host) {
        return;
    }
    inst->capture_stop = 1;
    start_ms = host->time.millis ? host->time.millis() : 0;
    while (inst->capture_running && inst->capture_task) {
        const uint32_t now = host->time.millis ? host->time.millis() : start_ms + 1000u;
        if (now - start_ms > 1500u) {
            if (host->task.remove && inst->capture_task) {
                host->task.remove(inst->capture_task);
            }
            inst->capture_running = 0;
            inst->capture_task = NULL;
            break;
        }
        if (host->task.delay) {
            host->task.delay(10);
        } else if (host->time.delay) {
            host->time.delay(10);
        } else {
            break;
        }
    }
    if (inst->capture_stream && host->i2s.end) {
        void *stream = inst->capture_stream;
        inst->capture_stream = NULL;
        if (host->i2s.end(stream) != MODULE_OK) {
            wake_set_error(inst, "wake.capture_stop: i2s release failed");
        }
    }
    inst->capture_task = NULL;
    if (inst->capture_raw && host->heap.free) {
        host->heap.free(inst->capture_raw);
    }
    inst->capture_raw = NULL;
    inst->capture_raw_bytes = 0;
    inst->capture_raw_fill = 0;
    inst->capture_stop = 0;
}

/**
 * @brief Push a status table shared by info(), feed(), and selftest().
 */
static void push_status_table(lua_State *L, const module_host_api_v2 *host, wake_instance_t *inst)
{
    host->lua.createtable(L, 0, 24);
    set_string_field(L, host, "version", WAKE_VERSION);
    set_string_field(L, host, "engine", WAKE_ENGINE);
    set_string_field(L, host, "model", WAKE_MODEL);
    set_string_field(L, host, "word", WAKE_WORD);
    set_string_field(L, host, "model_path", WAKE_MODEL_PATH_STRING);
    set_string_field(L, host, "backend", WAKE_REAL_BACKEND ? "esp-sr" : "synthetic");
    set_boolean_field(L, host, "real_backend", WAKE_REAL_BACKEND);
    set_boolean_field(L, host, "initialized", wake_is_initialized(inst));
    set_integer_field(L, host, "sample_rate", inst && inst->sample_rate ? inst->sample_rate : WAKE_SAMPLE_RATE);
    set_integer_field(L, host, "bits_per_sample", WAKE_BITS_PER_SAMPLE);
    set_integer_field(L, host, "channels", inst && inst->channel_count ? inst->channel_count : WAKE_CHANNELS);
    set_integer_field(L, host, "chunk_samples", inst ? inst->chunk_samples : 0);
    set_integer_field(L, host, "word_count", inst ? inst->word_count : 0);
    set_integer_field(L, host, "model_count", inst ? inst->model_count : 0);
    set_integer_field(L, host, "created_ms", inst ? inst->created_ms : 0);
    set_integer_field(L, host, "selftest_count", inst ? inst->selftest_count : 0);
    set_integer_field(L, host, "feed_count", inst ? inst->feed_count : 0);
    set_integer_field(L, host, "frames_fed", inst ? inst->frames_fed : 0);
    set_integer_field(L, host, "samples_fed", inst ? inst->samples_fed : 0);
    set_integer_field(L, host, "last_state", inst ? inst->last_state : 0);
    set_boolean_field(L, host, "last_detected", inst && inst->last_detected);
    set_boolean_field(L, host, "capture_running", inst && inst->capture_running);
    set_integer_field(L, host, "capture_frames", inst ? inst->capture_frames : 0);
    set_integer_field(L, host, "capture_detections", inst ? inst->capture_detections : 0);
    set_string_field(L, host, "last_error", inst ? inst->last_error : "");
}

/**
 * @brief Lua: wake.info() -> table.
 */
static int l_info(lua_State *L)
{
    wake_instance_t *inst = instance_from_lua(L);
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    if (!host) {
        return 0;
    }
    push_status_table(L, host, inst);
    return 1;
}

/**
 * @brief Lua: wake.start() / wake.init() -> true | nil, err.
 */
static int l_start(lua_State *L)
{
    wake_instance_t *inst = instance_from_lua(L);
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    int err = MODULE_OK;
    if (!host || !inst) {
        return 0;
    }
    err = wake_init_backend(inst);
    if (err != MODULE_OK) {
        return push_error(L, host, inst->last_error);
    }
    host->lua.pushboolean(L, 1);
    return 1;
}

/**
 * @brief Lua: wake.stop() -> true.
 */
static int l_stop(lua_State *L)
{
    wake_instance_t *inst = instance_from_lua(L);
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    if (!host || !inst) {
        return 0;
    }
    wake_capture_stop(inst);
    wake_deinit_backend(inst);
    host->lua.pushboolean(L, 1);
    return 1;
}

/**
 * @brief Lua: wake.reset() -> true | nil, err.
 */
static int l_reset(lua_State *L)
{
    wake_instance_t *inst = instance_from_lua(L);
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    int err = MODULE_OK;
    if (!host || !inst) {
        return 0;
    }
    err = wake_init_backend(inst);
    if (err != MODULE_OK) {
        return push_error(L, host, inst->last_error);
    }
    wake_clean_backend(inst);
    inst->last_detected = 0;
    inst->last_state = 0;
    host->lua.pushboolean(L, 1);
    return 1;
}

/**
 * @brief Lua: wake.selftest([chunks]) -> table.
 */
static int l_selftest(lua_State *L)
{
    wake_instance_t *inst = instance_from_lua(L);
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    uint32_t chunks = WAKE_SYNTH_CHUNKS;
    uint32_t frames = 0;
    uint32_t detected = 0;
    int32_t state = 0;
    int err = MODULE_OK;
    if (!host || !inst) {
        return 0;
    }
    if (host->lua.gettop(L) >= 1 && host->lua.isnumber(L, 1)) {
        int64_t n = host->lua.tointeger(L, 1);
        if (n > 0 && n < 10000) {
            chunks = (uint32_t)n;
        }
    }

    err = wake_selftest_backend(inst, chunks, &frames, &detected, &state);
    inst->selftest_count++;

    host->lua.createtable(L, 0, 14);
    set_boolean_field(L, host, "ok", err == MODULE_OK);
    set_boolean_field(L, host, "detected", detected > 0);
    set_integer_field(L, host, "detections", detected);
    set_integer_field(L, host, "state", state);
    set_string_field(L, host, "word", WAKE_WORD);
    set_string_field(L, host, "engine", WAKE_ENGINE);
    set_string_field(L, host, "model", WAKE_MODEL);
    set_string_field(L, host, "model_path", WAKE_MODEL_PATH_STRING);
    set_string_field(L, host, "backend", WAKE_REAL_BACKEND ? "esp-sr" : "synthetic");
    set_boolean_field(L, host, "real_backend", WAKE_REAL_BACKEND);
    set_integer_field(L, host, "sample_rate", inst->sample_rate ? inst->sample_rate : WAKE_SAMPLE_RATE);
    set_integer_field(L, host, "chunk_samples", inst->chunk_samples);
    set_integer_field(L, host, "frames", frames);
    set_string_field(L, host, "note", WAKE_REAL_BACKEND ? "synthetic PCM was fed to real WakeNet; it should normally not wake" : inst->last_error);
    if (err != MODULE_OK) {
        set_string_field(L, host, "error", inst->last_error);
    }
    return 1;
}

/**
 * @brief Lua: wake.feed(pcm_string) -> table | nil, err.
 */
static int l_feed(lua_State *L)
{
    wake_instance_t *inst = instance_from_lua(L);
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    const char *pcm = NULL;
    size_t byte_len = 0;
    uint32_t frames = 0;
    uint32_t detected = 0;
    int32_t state = 0;
    int err = MODULE_OK;
    if (!host || !inst) {
        return 0;
    }
    if (!host_has_lua_field(host,
                            offsetof(module_lua_api_t, checklstring),
                            sizeof(host->lua.checklstring)) ||
        !host->lua.checklstring) {
        return push_error(L, host, "wake.feed: host lua.checklstring API missing");
    }

    pcm = host->lua.checklstring(L, 1, &byte_len);
    if (!pcm || byte_len == 0 || (byte_len & 1u) != 0) {
        return push_error(L, host, "wake.feed: expected non-empty s16le PCM string");
    }

    err = wake_feed_pcm_bytes(inst, (const uint8_t *)pcm, byte_len, &frames, &detected, &state);
    if (err != MODULE_OK) {
        return push_error(L, host, inst->last_error);
    }
    inst->feed_count++;

    host->lua.createtable(L, 0, 10);
    set_boolean_field(L, host, "ok", 1);
    set_boolean_field(L, host, "detected", detected > 0);
    set_integer_field(L, host, "detections", detected);
    set_integer_field(L, host, "state", state);
    set_integer_field(L, host, "frames", frames);
    set_integer_field(L, host, "bytes", (int64_t)byte_len);
    set_integer_field(L, host, "samples", (int64_t)(byte_len / sizeof(int16_t)));
    set_integer_field(L, host, "chunk_samples", inst->chunk_samples);
    set_integer_field(L, host, "sample_rate", inst->sample_rate);
    set_string_field(L, host, "model", WAKE_MODEL);
    return 1;
}

/**
 * @brief Lua: wake.feed_i2s(raw32_string[, pack[, gain_shift]]) -> table | nil, err.
 */
static int l_feed_i2s(lua_State *L)
{
    wake_instance_t *inst = instance_from_lua(L);
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    const char *raw = NULL;
    const char *pack = "b23";
    size_t byte_len = 0;
    int gain_shift = 0;
    uint32_t frames = 0;
    uint32_t detected = 0;
    int32_t state = 0;
    int err = MODULE_OK;
    if (!host || !inst) {
        return 0;
    }
    if (!host_has_lua_field(host,
                            offsetof(module_lua_api_t, checklstring),
                            sizeof(host->lua.checklstring)) ||
        !host->lua.checklstring) {
        return push_error(L, host, "wake.feed_i2s: host lua.checklstring API missing");
    }

    raw = host->lua.checklstring(L, 1, &byte_len);
    if (!raw || byte_len == 0 || (byte_len & 3u) != 0) {
        return push_error(L, host, "wake.feed_i2s: expected non-empty raw32 I2S string");
    }
    if (host->lua.gettop(L) >= 2 && host->lua.isstring(L, 2)) {
        pack = host->lua.tostring(L, 2);
    }
    if (host->lua.gettop(L) >= 3 && host->lua.isnumber(L, 3)) {
        gain_shift = (int)host->lua.tointeger(L, 3);
    }

    err = wake_feed_i2s32_bytes(inst,
                                (const uint8_t *)raw,
                                byte_len,
                                pack,
                                gain_shift,
                                &frames,
                                &detected,
                                &state);
    if (err != MODULE_OK) {
        return push_error(L, host, inst->last_error);
    }
    inst->feed_count++;

    host->lua.createtable(L, 0, 10);
    set_boolean_field(L, host, "ok", 1);
    set_boolean_field(L, host, "detected", detected > 0);
    set_integer_field(L, host, "detections", detected);
    set_integer_field(L, host, "state", state);
    set_integer_field(L, host, "frames", frames);
    set_integer_field(L, host, "bytes", (int64_t)byte_len);
    set_integer_field(L, host, "samples", (int64_t)(byte_len / 4u));
    set_integer_field(L, host, "chunk_samples", inst->chunk_samples);
    set_integer_field(L, host, "sample_rate", inst->sample_rate);
    set_string_field(L, host, "model", WAKE_MODEL);
    return 1;
}

/**
 * @brief Lua: wake.capture_start([config]) -> true | nil, err.
 *
 * The native task owns I2S RX and runs WakeNet. Lua only polls
 * capture_read(), so inference never blocks the Lua timer task.
 */
static int l_capture_start(lua_State *L)
{
    wake_instance_t *inst = instance_from_lua(L);
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    module_i2s_config_t cfg;
    void *stream = NULL;
    void *task = NULL;
    int cfg_idx = 0;
    int stack_bytes = (int)WAKE_CAPTURE_DEFAULT_STACK;
    int priority = (int)WAKE_CAPTURE_DEFAULT_PRIORITY;
    int core = WAKE_CAPTURE_DEFAULT_CORE;
    const char *pack = "b23";
    int err = MODULE_OK;

    if (!host || !inst) {
        return 0;
    }
    if (!host->i2s.begin || !host->i2s.read || !host->i2s.end ||
        !host->task.create_ex || !host->task.remove || !host->task.delay) {
        return push_error(L, host, "wake.capture_start: host i2s/task API missing");
    }
    if (inst->capture_running) {
        host->lua.pushboolean(L, 1);
        return 1;
    }
    err = wake_init_backend(inst);
    if (err != MODULE_OK) {
        return push_error(L, host, inst->last_error);
    }

    cfg_idx = host->lua.gettop(L) >= 1 && host->lua.istable(L, 1) ? 1 : 0;
    stack_bytes = cfg_idx ? wake_read_int_field(L, host, cfg_idx, "task_stack", stack_bytes) : stack_bytes;
    priority = cfg_idx ? wake_read_int_field(L, host, cfg_idx, "priority", priority) : priority;
    core = cfg_idx ? wake_read_int_field(L, host, cfg_idx, "core", core) : core;
    inst->capture_gain_shift = cfg_idx ? wake_read_int_field(L, host, cfg_idx, "gain_shift", 0) : 0;
    inst->capture_read_timeout_ms = (uint32_t)(cfg_idx ? wake_read_int_field(
        L, host, cfg_idx, "read_timeout_ms", (int)WAKE_CAPTURE_DEFAULT_TIMEOUT_MS)
        : (int)WAKE_CAPTURE_DEFAULT_TIMEOUT_MS);
    pack = cfg_idx ? wake_read_string_field(L, host, cfg_idx, "pack", "b23") : "b23";
    wake_copy_pack(inst->capture_pack, pack);

    if (stack_bytes < (int)WAKE_CAPTURE_DEFAULT_STACK) stack_bytes = (int)WAKE_CAPTURE_DEFAULT_STACK;
    if (priority < 1) priority = 1;
    if (priority > 10) priority = 10;
    if (core < -1 || core > 1) core = WAKE_CAPTURE_DEFAULT_CORE;
    if (inst->capture_read_timeout_ms < 1) inst->capture_read_timeout_ms = 1;
    inst->capture_raw_bytes = (size_t)inst->chunk_samples * (size_t)inst->channel_count * 4u;
    /* i2s_read copies out of the driver's internal DMA ring; this destination
     * is a CPU buffer and can live in PSRAM. */
    inst->capture_raw = (uint8_t *)host->heap.malloc(
        inst->capture_raw_bytes, MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    if (!inst->capture_raw) {
        inst->capture_raw = (uint8_t *)host->heap.malloc(
            inst->capture_raw_bytes, MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT);
    }
    if (!inst->capture_raw) {
        inst->capture_raw_bytes = 0;
        return push_error(L, host, "wake.capture_start: no capture buffer");
    }

    memset(&cfg, 0, sizeof(cfg));
    cfg.size = sizeof(cfg);
    cfg.port = (uint8_t)(cfg_idx ? wake_read_int_field(L, host, cfg_idx, "i2s_id", 0) : 0);
    cfg.mode = MODULE_I2S_MODE_RX;
    cfg.sample_rate = WAKE_SAMPLE_RATE;
    cfg.bits = (uint16_t)(cfg_idx ? wake_read_int_field(L, host, cfg_idx, "bits", 32) : 32);
    cfg.channels = 1;
    cfg.format = MODULE_I2S_FORMAT_I2S;
    cfg.channel_mode = MODULE_I2S_CHANNEL_MONO_LEFT;
    cfg.bclk_pin = (int16_t)(cfg_idx ? wake_read_int_field(L, host, cfg_idx, "bclk_pin", 41) : 41);
    cfg.ws_pin = (int16_t)(cfg_idx ? wake_read_int_field(L, host, cfg_idx, "ws_pin", 45) : 45);
    cfg.dout_pin = -1;
    cfg.din_pin = (int16_t)(cfg_idx ? wake_read_int_field(L, host, cfg_idx, "din_pin", 42) : 42);
    cfg.mclk_pin = -1;
    cfg.dma_buf_count = (uint16_t)(cfg_idx ? wake_read_int_field(L, host, cfg_idx, "buffer_count", 4) : 4);
    cfg.dma_buf_len = (uint16_t)(cfg_idx ? wake_read_int_field(
        L, host, cfg_idx, "buffer_len", inst->chunk_samples) : inst->chunk_samples);

    err = host->i2s.begin(&cfg, &stream);
    if (err != MODULE_OK || !stream) {
        host->heap.free(inst->capture_raw);
        inst->capture_raw = NULL;
        inst->capture_raw_bytes = 0;
        return push_error(L, host, "wake.capture_start: i2s busy or unavailable");
    }
    inst->capture_stream = stream;
    inst->capture_raw_fill = 0;
    inst->capture_stop = 0;
    inst->capture_running = 1;
    inst->capture_frames = 0;
    inst->capture_detections = 0;
    inst->capture_reported_detections = 0;
    wake_set_error(inst, "");

    err = host->task.create_ex("wake_capture",
                               wake_capture_task_entry,
                               inst,
                               (uint32_t)stack_bytes,
                               (uint32_t)priority,
                               core,
                               MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT,
                               &task);
    if (err != MODULE_OK || !task) {
        inst->capture_running = 0;
        wake_capture_stop(inst);
        return push_error(L, host, "wake.capture_start: task create failed");
    }
    inst->capture_task = task;
    host->lua.pushboolean(L, 1);
    return 1;
}

/** @brief Lua: wake.capture_read() -> status table. */
static int l_capture_read(lua_State *L)
{
    wake_instance_t *inst = instance_from_lua(L);
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    uint32_t total = 0;
    uint32_t detections = 0;
    if (!host || !inst) {
        return 0;
    }
    total = inst->capture_detections;
    detections = total - inst->capture_reported_detections;
    inst->capture_reported_detections = total;
    host->lua.createtable(L, 0, 8);
    set_boolean_field(L, host, "ok", inst->capture_running || inst->last_error[0] == '\0');
    set_boolean_field(L, host, "running", inst->capture_running);
    set_boolean_field(L, host, "detected", detections > 0);
    set_integer_field(L, host, "detections", detections);
    set_integer_field(L, host, "frames", inst->capture_frames);
    set_integer_field(L, host, "state", inst->last_state);
    set_string_field(L, host, "error", inst->last_error);
    return 1;
}

/** @brief Lua: wake.capture_stop() -> true. */
static int l_capture_stop(lua_State *L)
{
    wake_instance_t *inst = instance_from_lua(L);
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    if (!host || !inst) {
        return 0;
    }
    wake_capture_stop(inst);
    host->lua.pushboolean(L, 1);
    return 1;
}

WAKE_MODULE_EXPORT const module_manifest_t *module_query_v1(void)
{
    return &s_manifest;
}

static int32_t wake_module_create(const module_host_api_v2 *host,
                                  const module_open_info_t *info,
                                  void **out_instance)
{
    wake_instance_t *inst = NULL;
    (void)info;
    if (!host || !out_instance) {
        return MODULE_ERR_INVALID_ARG;
    }
    if (!host->heap.calloc || !host->heap.free || !host->lua.createtable) {
        return MODULE_ERR_UNSUPPORTED;
    }

    *out_instance = NULL;
    s_host = host;
    inst = (wake_instance_t *)host->heap.calloc(1,
                                                sizeof(wake_instance_t),
                                                MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT);
    if (!inst) {
        inst = (wake_instance_t *)host->heap.calloc(1, sizeof(wake_instance_t), MODULE_HEAP_DEFAULT);
    }
    if (!inst) {
        return MODULE_ERR_NO_MEMORY;
    }

    inst->host = host;
    inst->created_ms = host->time.millis ? host->time.millis() : 0;
    inst->sample_rate = WAKE_SAMPLE_RATE;
    inst->channel_count = WAKE_CHANNELS;
    inst->real_backend = WAKE_REAL_BACKEND;
    *out_instance = inst;

    if (host->serial.println) {
        host->serial.println("[wake.so] create WakeNet9s wn9s_nihaoxiaozhi sdcard");
    }
    return MODULE_OK;
}

WAKE_MODULE_EXPORT int32_t module_create_v2(module_host_resolve_v2_fn resolve,
                                            void *resolve_ctx,
                                            const module_open_info_t *info,
                                            void **out_instance)
{
    static module_host_api_v2 host = {0};
    int32_t err = module_sdk_resolve_host_v2(resolve, resolve_ctx, &host);
    if (err != MODULE_OK) {
        return err;
    }
    return wake_module_create(&host, info, out_instance);
}

WAKE_MODULE_EXPORT int32_t module_luaopen_v1(void *instance, lua_State *L)
{
    wake_instance_t *inst = (wake_instance_t *)instance;
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    if (!inst || !host || !L) {
        return MODULE_ERR_INVALID_ARG;
    }

    host->lua.createtable(L, 0, 20);
    set_string_field(L, host, "VERSION", WAKE_VERSION);
    set_string_field(L, host, "ENGINE", WAKE_ENGINE);
    set_string_field(L, host, "MODEL", WAKE_MODEL);
    set_string_field(L, host, "WORD", WAKE_WORD);
    set_string_field(L, host, "MODEL_PATH", WAKE_MODEL_PATH_STRING);
    set_boolean_field(L, host, "REAL_BACKEND", WAKE_REAL_BACKEND);
    set_integer_field(L, host, "SAMPLE_RATE", WAKE_SAMPLE_RATE);
    set_function_field(L, host, "info", l_info, inst);
    set_function_field(L, host, "init", l_start, inst);
    set_function_field(L, host, "start", l_start, inst);
    set_function_field(L, host, "stop", l_stop, inst);
    set_function_field(L, host, "reset", l_reset, inst);
    set_function_field(L, host, "selftest", l_selftest, inst);
    set_function_field(L, host, "feed", l_feed, inst);
    set_function_field(L, host, "feed_i2s", l_feed_i2s, inst);
    set_function_field(L, host, "capture_start", l_capture_start, inst);
    set_function_field(L, host, "capture_read", l_capture_read, inst);
    set_function_field(L, host, "capture_stop", l_capture_stop, inst);
    return MODULE_OK;
}

WAKE_MODULE_EXPORT void module_destroy_v1(void *instance)
{
    wake_instance_t *inst = (wake_instance_t *)instance;
    if (!inst) {
        return;
    }
    wake_capture_stop(inst);
    wake_destroy_backend(inst);
    if (inst->host && inst->host->serial.println) {
        inst->host->serial.println("[wake.so] destroy");
    }
    if (inst->host && inst->host->heap.free) {
        inst->host->heap.free(inst);
    }
}
