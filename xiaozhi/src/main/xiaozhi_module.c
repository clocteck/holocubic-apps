#include <stddef.h>
#include <stdint.h>

#include "module_abi.h"
#include "opus.h"

#define XZ_MODULE_EXPORT __attribute__((visibility("default"), used))
#define XZ_VERSION "0.5.0"
#ifndef XZ_MODULE_ID
#define XZ_MODULE_ID xiaozhi
#endif
#define XZ_STRINGIFY_INNER(x) #x
#define XZ_STRINGIFY(x) XZ_STRINGIFY_INNER(x)
#define XZ_NAME XZ_STRINGIFY(XZ_MODULE_ID)
#define XZ_DEFAULT_RATE 12000
#define XZ_DEFAULT_CHANNELS 1
#define XZ_DEFAULT_FRAME_MS 60
#define XZ_DEFAULT_BITRATE 12000
#define XZ_DEFAULT_COMPLEXITY 5
#define XZ_MAX_OPUS_BYTES 1500
#define XZ_CAPTURE_DEFAULT_QUEUE 6
#define XZ_CAPTURE_MAX_QUEUE 16
#define XZ_CAPTURE_DEFAULT_STACK 32768
#define XZ_CAPTURE_DEFAULT_PRIORITY 2
#define XZ_CAPTURE_DEFAULT_CORE 0
#define XZ_CAPTURE_DEFAULT_READ_TIMEOUT_MS 100

typedef struct playback_state playback_state;
typedef struct xz_instance_t {
    playback_state *playback;
    const module_host_api_v2 *host;
    uint32_t created_ms;

    int rate;
    int channels;
    int frame_ms;
    int frame_samples;
    int frame_pcm_bytes;
    int bitrate;
    int complexity;
    int tx_enabled;
    int rx_enabled;
    int hold_audio;
    int playback_volume;
    int started;

    OpusEncoder *encoder;
    OpusDecoder *decoder;
    void *audio_stream;
    int16_t *tx_pcm_scratch;
    size_t tx_pcm_scratch_bytes;
    uint8_t *tx_opus_scratch;
    size_t tx_opus_scratch_bytes;

    void *capture_stream;
    void *capture_task;
    volatile int capture_running;
    volatile int capture_stop;
    uint8_t *capture_raw;
    size_t capture_raw_bytes;
    size_t capture_raw_fill;
    uint8_t *capture_opus;
    uint8_t *capture_queue;
    uint16_t *capture_lens;
    volatile uint32_t capture_head;
    volatile uint32_t capture_tail;
    uint32_t capture_depth;
    uint32_t capture_dropped;
    uint32_t capture_read_timeout_ms;
    uint32_t capture_frames;
    int capture_gain_shift;
    char capture_pack[4];

    uint32_t encode_count;
    uint32_t decode_count;
    uint32_t play_count;
    uint32_t pcm_bytes_in;
    uint32_t pcm_bytes_out;
    uint32_t opus_bytes_in;
    uint32_t opus_bytes_out;
    char last_error[128];
} xz_instance_t;

static module_host_api_v2 s_host_store;
static const module_host_api_v2 *s_host;

#if defined(NONTHREADSAFE_PSEUDOSTACK)
extern char *scratch_ptr;
extern char *global_stack;
#endif

static void stop_capture(xz_instance_t *inst);
static void stop_playback(xz_instance_t *inst);
static void free_capture_buffers(xz_instance_t *inst);

static const module_manifest_t s_manifest = {
    MODULE_MANIFEST_MAGIC,
    MODULE_SDK_VERSION,
    sizeof(module_manifest_t),
    XZ_NAME,
    XZ_VERSION,
    "XiaoZhi voice/Opus dynamic module",
    0,
    MODULE_BOOTSTRAP_ABI_VERSION,
};

static uint64_t xz_u64_divmod(uint64_t num, uint64_t den, uint64_t *rem)
{
    uint64_t quo = 0;
    if (den == 0) {
        if (rem) {
            *rem = num;
        }
        return 0;
    }
    for (int bit = 63; bit >= 0; --bit) {
        if ((num >> bit) >= den) {
            num -= den << bit;
            quo |= 1ULL << bit;
        }
    }
    if (rem) {
        *rem = num;
    }
    return quo;
}

static uint64_t xz_i64_abs_u64(int64_t value)
{
    uint64_t bits = (uint64_t)value;
    return value < 0 ? (~bits + 1ULL) : bits;
}

int64_t __divdi3(int64_t num, int64_t den) __attribute__((used, noinline));
int64_t __divdi3(int64_t num, int64_t den)
{
    const int negative = (num < 0) ^ (den < 0);
    uint64_t quo = xz_u64_divmod(xz_i64_abs_u64(num), xz_i64_abs_u64(den), NULL);
    if (negative) {
        quo = ~quo + 1ULL;
    }
    return (int64_t)quo;
}

/*
 * Small libc shims for dynmod safety.  Some third-party codec objects may
 * reference these symbols, while the firmware does not promise to export them.
 */
#include "xz_memory.inc"

void *memmove(void *dst, const void *src, size_t n)
{
    unsigned char *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;
    if (d == s || n == 0) {
        return dst;
    }
    if (d < s) {
        size_t i = 0;
        for (i = 0; i < n; ++i) {
            d[i] = s[i];
        }
    } else {
        size_t i = n;
        while (i > 0) {
            --i;
            d[i] = s[i];
        }
    }
    return dst;
}


int memcmp(const void *a, const void *b, size_t n)
{
    const unsigned char *pa = (const unsigned char *)a;
    const unsigned char *pb = (const unsigned char *)b;
    size_t i = 0;
    for (i = 0; i < n; ++i) {
        if (pa[i] != pb[i]) {
            return (int)pa[i] - (int)pb[i];
        }
    }
    return 0;
}

size_t strlen(const char *s)
{
    size_t n = 0;
    if (!s) {
        return 0;
    }
    while (s[n]) {
        ++n;
    }
    return n;
}

int strcmp(const char *a, const char *b)
{
    size_t i = 0;
    if (!a) {
        a = "";
    }
    if (!b) {
        b = "";
    }
    while (a[i] && b[i] && a[i] == b[i]) {
        ++i;
    }
    return (int)(unsigned char)a[i] - (int)(unsigned char)b[i];
}

int strncmp(const char *a, const char *b, size_t n)
{
    size_t i = 0;
    if (!a) {
        a = "";
    }
    if (!b) {
        b = "";
    }
    for (i = 0; i < n; ++i) {
        if (a[i] != b[i] || !a[i] || !b[i]) {
            return (int)(unsigned char)a[i] - (int)(unsigned char)b[i];
        }
    }
    return 0;
}

#include "xz_alloc.inc"

static void xz_set_error(xz_instance_t *inst, const char *msg)
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

static int push_error(lua_State *L, const module_host_api_v2 *host, const char *msg)
{
    host->lua.pushnil(L);
    host->lua.pushstring(L, msg ? msg : "xiaozhi failed");
    return 2;
}

static xz_instance_t *instance_from_lua(lua_State *L)
{
    if (!s_host || !s_host->lua.touserdata || !s_host->lua.upvalue_index) {
        return NULL;
    }
    return (xz_instance_t *)s_host->lua.touserdata(L, s_host->lua.upvalue_index(1));
}

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

static void set_function_field(lua_State *L,
                               const module_host_api_v2 *host,
                               const char *key,
                               module_lua_cfunction_t fn,
                               xz_instance_t *inst)
{
    host->lua.pushlightuserdata(L, inst);
    host->lua.pushcclosure(L, fn, 1);
    host->lua.setfield(L, -2, key);
}

static int read_int_field(lua_State *L,
                          const module_host_api_v2 *host,
                          int table_idx,
                          const char *key,
                          int fallback)
{
    int value = fallback;
    int top = host->lua.gettop(L);
    host->lua.getfield(L, table_idx, key);
    if (host->lua.isnumber(L, -1)) {
        value = (int)host->lua.tointeger(L, -1);
    }
    host->lua.settop(L, top);
    return value;
}

static int read_bool_field(lua_State *L,
                           const module_host_api_v2 *host,
                           int table_idx,
                           const char *key,
                           int fallback)
{
    int value = fallback;
    int top = host->lua.gettop(L);
    host->lua.getfield(L, table_idx, key);
    if (!host->lua.isnil(L, -1)) {
        value = host->lua.toboolean(L, -1) ? 1 : 0;
    }
    host->lua.settop(L, top);
    return value;
}

static const char *read_string_field(lua_State *L,
                                     const module_host_api_v2 *host,
                                     int table_idx,
                                     const char *key,
                                     const char *fallback)
{
    const char *value = fallback;
    int top = host->lua.gettop(L);
    host->lua.getfield(L, table_idx, key);
    if (host->lua.isstring(L, -1)) {
        value = host->lua.tostring(L, -1);
    }
    host->lua.settop(L, top);
    return value ? value : "";
}

static int is_supported_rate(int rate)
{
    return rate == 8000 || rate == 12000 || rate == 16000 || rate == 24000 || rate == 48000;
}

static int normalize_config(xz_instance_t *inst)
{
    if (!inst) {
        return MODULE_ERR_INVALID_ARG;
    }
    if (!is_supported_rate(inst->rate)) {
        xz_set_error(inst, "voice.start: rate must be 8000/12000/16000/24000/48000");
        return MODULE_ERR_INVALID_ARG;
    }
    if (inst->channels != 1 && inst->channels != 2) {
        xz_set_error(inst, "voice.start: channels must be 1 or 2");
        return MODULE_ERR_INVALID_ARG;
    }
    if (inst->frame_ms != 10 && inst->frame_ms != 20 &&
        inst->frame_ms != 40 && inst->frame_ms != 60) {
        xz_set_error(inst, "voice.start: frame_ms must be 10/20/40/60");
        return MODULE_ERR_INVALID_ARG;
    }
    if (inst->complexity < 0) {
        inst->complexity = 0;
    } else if (inst->complexity > 10) {
        inst->complexity = 10;
    }
    if (inst->bitrate < 6000) {
        inst->bitrate = 6000;
    } else if (inst->bitrate > 128000) {
        inst->bitrate = 128000;
    }
    inst->frame_samples = (inst->rate * inst->frame_ms) / 1000;
    inst->frame_pcm_bytes = inst->frame_samples * inst->channels * (int)sizeof(int16_t);
    return MODULE_OK;
}

static void close_audio(xz_instance_t *inst)
{
    if (inst && inst->audio_stream && inst->host && inst->host->audio.end) {
        inst->host->audio.end(inst->audio_stream);
    }
    if (inst) {
        inst->audio_stream = NULL;
    }
}

static void destroy_codecs(xz_instance_t *inst)
{
    if (!inst) {
        return;
    }
    stop_playback(inst);
    stop_capture(inst);
    free_capture_buffers(inst);
    close_audio(inst);
    if (inst->encoder) {
        opus_encoder_destroy(inst->encoder);
        inst->encoder = NULL;
    }
    if (inst->decoder) {
        opus_decoder_destroy(inst->decoder);
        inst->decoder = NULL;
    }
    if (inst->tx_pcm_scratch) {
        inst->host->heap.free(inst->tx_pcm_scratch);
        inst->tx_pcm_scratch = NULL;
        inst->tx_pcm_scratch_bytes = 0;
    }
    if (inst->tx_opus_scratch) {
        inst->host->heap.free(inst->tx_opus_scratch);
        inst->tx_opus_scratch = NULL;
        inst->tx_opus_scratch_bytes = 0;
    }
    inst->started = 0;
}

static int16_t xz_clip_s16(int32_t value)
{
    if (value > 32767) {
        return 32767;
    }
    if (value < -32768) {
        return -32768;
    }
    return (int16_t)value;
}

static int ensure_tx_pcm_scratch(xz_instance_t *inst)
{
    int16_t *pcm = NULL;
    const size_t need = inst ? (size_t)inst->frame_pcm_bytes : 0;
    if (!inst || !inst->host || need == 0) {
        return MODULE_ERR_INVALID_ARG;
    }
    if (inst->tx_pcm_scratch && inst->tx_pcm_scratch_bytes >= need) {
        return MODULE_OK;
    }
    if (inst->tx_pcm_scratch) {
        inst->host->heap.free(inst->tx_pcm_scratch);
        inst->tx_pcm_scratch = NULL;
        inst->tx_pcm_scratch_bytes = 0;
    }
    pcm = (int16_t *)inst->host->heap.malloc(need, MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    if (!pcm) {
        pcm = (int16_t *)inst->host->heap.malloc(need, MODULE_HEAP_DEFAULT);
    }
    if (!pcm) {
        xz_set_error(inst, "voice.encode_i2s: no memory");
        return MODULE_ERR_NO_MEMORY;
    }
    inst->tx_pcm_scratch = pcm;
    inst->tx_pcm_scratch_bytes = need;
    return MODULE_OK;
}

static int ensure_tx_opus_scratch(xz_instance_t *inst)
{
    uint8_t *opus = NULL;
    if (!inst || !inst->host) {
        return MODULE_ERR_INVALID_ARG;
    }
    if (inst->tx_opus_scratch && inst->tx_opus_scratch_bytes >= XZ_MAX_OPUS_BYTES) {
        return MODULE_OK;
    }
    if (inst->tx_opus_scratch) {
        inst->host->heap.free(inst->tx_opus_scratch);
        inst->tx_opus_scratch = NULL;
        inst->tx_opus_scratch_bytes = 0;
    }
    opus = (uint8_t *)inst->host->heap.malloc(XZ_MAX_OPUS_BYTES,
                                              MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    if (!opus) {
        opus = (uint8_t *)inst->host->heap.malloc(XZ_MAX_OPUS_BYTES, MODULE_HEAP_DEFAULT);
    }
    if (!opus) {
        xz_set_error(inst, "voice.encode: no opus scratch memory");
        return MODULE_ERR_NO_MEMORY;
    }
    inst->tx_opus_scratch = opus;
    inst->tx_opus_scratch_bytes = XZ_MAX_OPUS_BYTES;
    return MODULE_OK;
}

static int ensure_audio(xz_instance_t *inst, int for_start)
{
    module_audio_desc_t desc;
    void *stream = NULL;
    int32_t err = MODULE_OK;
    if (!inst || !inst->host) {
        return MODULE_ERR_INVALID_ARG;
    }
    if (inst->audio_stream) {
        return MODULE_OK;
    }
    if (!inst->host->audio.begin || !inst->host->audio.write || !inst->host->audio.end) {
        xz_set_error(inst, for_start ? "voice.start: host audio API missing" : "voice.play: host audio API missing");
        return MODULE_ERR_UNSUPPORTED;
    }
    desc.size = sizeof(desc);
    desc.sample_rate = (uint32_t)inst->rate;
    desc.bits_per_sample = 16;
    desc.channels = (uint16_t)inst->channels;
    desc.flags = 0;
    err = inst->host->audio.begin(&desc, &stream);
    if (err != MODULE_OK || !stream) {
        xz_set_error(inst,
                     for_start ? "voice.start: audio output busy or unavailable"
                               : "voice.play: audio output busy or unavailable");
        return MODULE_ERR_BUSY;
    }
    inst->audio_stream = stream;
    return MODULE_OK;
}

static int voice_start_from_table(xz_instance_t *inst, lua_State *L, int cfg_idx)
{
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    int err = MODULE_OK;
    int opus_err = OPUS_OK;
    if (!inst || !host) {
        return MODULE_ERR_INVALID_ARG;
    }

    destroy_codecs(inst);
    inst->rate = XZ_DEFAULT_RATE;
    inst->channels = XZ_DEFAULT_CHANNELS;
    inst->frame_ms = XZ_DEFAULT_FRAME_MS;
    inst->bitrate = XZ_DEFAULT_BITRATE;
    inst->complexity = XZ_DEFAULT_COMPLEXITY;
    inst->tx_enabled = 1;
    inst->rx_enabled = 1;
    inst->hold_audio = 1;

    if (cfg_idx > 0 && host->lua.istable(L, cfg_idx)) {
        inst->rate = read_int_field(L, host, cfg_idx, "rate", inst->rate);
        inst->channels = read_int_field(L, host, cfg_idx, "channels", inst->channels);
        inst->frame_ms = read_int_field(L, host, cfg_idx, "frame_ms", inst->frame_ms);
        inst->bitrate = read_int_field(L, host, cfg_idx, "bitrate", inst->bitrate);
        inst->complexity = read_int_field(L, host, cfg_idx, "complexity", inst->complexity);
        inst->tx_enabled = read_bool_field(L, host, cfg_idx, "tx", inst->tx_enabled);
        inst->rx_enabled = read_bool_field(L, host, cfg_idx, "rx", inst->rx_enabled);
        inst->hold_audio = read_bool_field(L, host, cfg_idx, "hold_audio", inst->hold_audio);
        inst->hold_audio = read_bool_field(L, host, cfg_idx, "audio", inst->hold_audio);
    }

    err = normalize_config(inst);
    if (err != MODULE_OK) {
        return err;
    }

    if (inst->tx_enabled) {
        inst->encoder = opus_encoder_create(inst->rate, inst->channels, OPUS_APPLICATION_VOIP, &opus_err);
        if (!inst->encoder || opus_err != OPUS_OK) {
            xz_set_error(inst, "voice.start: opus encoder create failed");
            destroy_codecs(inst);
            return MODULE_ERR_FAILED;
        }
        opus_encoder_ctl(inst->encoder, OPUS_SET_COMPLEXITY(inst->complexity));
        opus_encoder_ctl(inst->encoder, OPUS_SET_BITRATE(inst->bitrate));
        opus_encoder_ctl(inst->encoder, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
    }

    if (inst->rx_enabled) {
        inst->decoder = opus_decoder_create(inst->rate, inst->channels, &opus_err);
        if (!inst->decoder || opus_err != OPUS_OK) {
            xz_set_error(inst, "voice.start: opus decoder create failed");
            destroy_codecs(inst);
            return MODULE_ERR_FAILED;
        }
    }

    if (inst->hold_audio) {
        err = ensure_audio(inst, 1);
        if (err != MODULE_OK) {
            destroy_codecs(inst);
            return err;
        }
    }

    inst->started = 1;
    xz_set_error(inst, "");
    return MODULE_OK;
}

static int encode_current_frame(xz_instance_t *inst,
                                const uint8_t *pcm,
                                size_t pcm_len,
                                uint8_t *out,
                                size_t out_cap,
                                int *out_len)
{
    int encoded = 0;
    if (!inst || !inst->started || !inst->encoder) {
        xz_set_error(inst, "voice.encode: encoder not started");
        return MODULE_ERR_BAD_STATE;
    }
    if (!pcm || pcm_len != (size_t)inst->frame_pcm_bytes) {
        xz_set_error(inst, "voice.encode: expected exactly one configured PCM frame");
        return MODULE_ERR_INVALID_ARG;
    }
    encoded = opus_encode(inst->encoder,
                          (const opus_int16 *)pcm,
                          inst->frame_samples,
                          out,
                          (opus_int32)out_cap);
    if (encoded <= 0) {
        xz_set_error(inst, "voice.encode: opus_encode failed");
        return MODULE_ERR_FAILED;
    }
    *out_len = encoded;
    inst->encode_count++;
    inst->pcm_bytes_in += (uint32_t)pcm_len;
    inst->opus_bytes_out += (uint32_t)encoded;
    return MODULE_OK;
}

static void i2s_pack_offsets(const char *pack, int *lo_off, int *hi_off)
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

static int convert_i2s32_frame_to_pcm16(xz_instance_t *inst,
                                        const uint8_t *raw,
                                        size_t raw_len,
                                        const char *pack,
                                        int gain_shift,
                                        int16_t **out_pcm,
                                        size_t *out_pcm_bytes)
{
    int lo_off = 2;
    int hi_off = 3;
    const size_t samples = inst ? (size_t)inst->frame_samples * (size_t)inst->channels : 0;
    size_t i = 0;
    if (!inst || !raw || !out_pcm || !out_pcm_bytes) {
        return MODULE_ERR_INVALID_ARG;
    }
    if (inst->channels != 1) {
        xz_set_error(inst, "voice.encode_i2s: only mono I2S input is supported");
        return MODULE_ERR_UNSUPPORTED;
    }
    if (raw_len != samples * 4U) {
        xz_set_error(inst, "voice.encode_i2s: expected exactly one raw32 frame");
        return MODULE_ERR_INVALID_ARG;
    }
    if (ensure_tx_pcm_scratch(inst) != MODULE_OK) {
        return MODULE_ERR_NO_MEMORY;
    }
    if (gain_shift > 8) {
        gain_shift = 8;
    } else if (gain_shift < -8) {
        gain_shift = -8;
    }
    i2s_pack_offsets(pack, &lo_off, &hi_off);
    for (i = 0; i < samples; ++i) {
        const size_t base = i * 4U;
        int32_t v = (int32_t)raw[base + (size_t)lo_off] |
                    ((int32_t)raw[base + (size_t)hi_off] << 8);
        if (v >= 32768) {
            v -= 65536;
        }
        if (gain_shift > 0) {
            v *= (1 << gain_shift);
        } else if (gain_shift < 0) {
            v >>= -gain_shift;
        }
        inst->tx_pcm_scratch[i] = xz_clip_s16(v);
    }
    *out_pcm = inst->tx_pcm_scratch;
    *out_pcm_bytes = samples * sizeof(int16_t);
    return MODULE_OK;
}

static void copy_pack_name(char out[4], const char *pack)
{
    if (!pack || (strcmp(pack, "b01") != 0 && strcmp(pack, "b12") != 0 && strcmp(pack, "b23") != 0)) {
        pack = "b23";
    }
    out[0] = pack[0];
    out[1] = pack[1];
    out[2] = pack[2];
    out[3] = '\0';
}

static void free_capture_buffers(xz_instance_t *inst)
{
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    if (!inst || !host || !host->heap.free) {
        return;
    }
    if (inst->capture_raw) {
        host->heap.free(inst->capture_raw);
        inst->capture_raw = NULL;
    }
    if (inst->capture_opus) {
        host->heap.free(inst->capture_opus);
        inst->capture_opus = NULL;
    }
    if (inst->capture_queue) {
        host->heap.free(inst->capture_queue);
        inst->capture_queue = NULL;
    }
    if (inst->capture_lens) {
        host->heap.free(inst->capture_lens);
        inst->capture_lens = NULL;
    }
    inst->capture_raw_bytes = 0;
    inst->capture_raw_fill = 0;
    inst->capture_depth = 0;
    inst->capture_head = 0;
    inst->capture_tail = 0;
}

static int alloc_capture_buffers(xz_instance_t *inst, uint32_t depth, int need_raw)
{
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    const size_t raw_bytes = inst && need_raw ? (size_t)inst->frame_pcm_bytes * 2U : 0;
    if (!inst || !host || !host->heap.malloc || !host->heap.calloc) {
        return MODULE_ERR_INVALID_ARG;
    }
    if (depth < 2) {
        depth = 2;
    } else if (depth > XZ_CAPTURE_MAX_QUEUE) {
        depth = XZ_CAPTURE_MAX_QUEUE;
    }
    free_capture_buffers(inst);
    /* host i2s.read() copies from the driver's DMA ring into this CPU buffer,
     * so it does not need DMA/internal capability. */
    inst->capture_raw = raw_bytes ? (uint8_t *)host->heap.malloc(raw_bytes, MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT) : NULL;
    if (raw_bytes && !inst->capture_raw) {
        inst->capture_raw = (uint8_t *)host->heap.malloc(raw_bytes, MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT);
    }
    inst->capture_opus = (uint8_t *)host->heap.malloc(XZ_MAX_OPUS_BYTES,
                                                      MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    if (!inst->capture_opus) {
        inst->capture_opus = (uint8_t *)host->heap.malloc(XZ_MAX_OPUS_BYTES,
                                                          MODULE_HEAP_DEFAULT);
    }
    inst->capture_queue = (uint8_t *)host->heap.malloc((size_t)depth * XZ_MAX_OPUS_BYTES,
                                                       MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    if (!inst->capture_queue) {
        inst->capture_queue = (uint8_t *)host->heap.malloc((size_t)depth * XZ_MAX_OPUS_BYTES,
                                                           MODULE_HEAP_DEFAULT);
    }
    inst->capture_lens = (uint16_t *)host->heap.calloc(depth,
                                                       sizeof(uint16_t),
                                                       MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    if ((need_raw && !inst->capture_raw) || !inst->capture_opus || !inst->capture_queue || !inst->capture_lens) {
        free_capture_buffers(inst);
        xz_set_error(inst, "voice.capture_start: no memory");
        return MODULE_ERR_NO_MEMORY;
    }
    inst->capture_raw_bytes = raw_bytes;
    inst->capture_raw_fill = 0;
    inst->capture_depth = depth;
    inst->capture_head = 0;
    inst->capture_tail = 0;
    return MODULE_OK;
}

static void capture_push_opus(xz_instance_t *inst, const uint8_t *opus, int opus_len)
{
    uint32_t head = 0;
    uint32_t next = 0;
    if (!inst || !opus || opus_len <= 0 || opus_len > XZ_MAX_OPUS_BYTES ||
        !inst->capture_queue || !inst->capture_lens || inst->capture_depth == 0) {
        return;
    }
    head = inst->capture_head;
    next = (head + 1U) % inst->capture_depth;
    if (next == __atomic_load_n(&inst->capture_tail, __ATOMIC_ACQUIRE)) {
        inst->capture_dropped++;
        return;
    }
    memcpy(inst->capture_queue + ((size_t)head * XZ_MAX_OPUS_BYTES), opus, (size_t)opus_len);
    inst->capture_lens[head] = (uint16_t)opus_len;
    __atomic_store_n(&inst->capture_head, next, __ATOMIC_RELEASE);
}

static int capture_queue_full(xz_instance_t *inst)
{
    uint32_t next = 0;
    if (!inst || inst->capture_depth == 0) {
        return 0;
    }
    next = (inst->capture_head + 1U) % inst->capture_depth;
    return next == inst->capture_tail;
}

static void capture_task_entry(void *arg)
{
    xz_instance_t *inst = (xz_instance_t *)arg;
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    if (!inst || !host || !host->i2s.read) {
        return;
    }
    if (host->serial.println) {
        host->serial.println("[xiaozhi.so] capture task start");
    }

    while (!inst->capture_stop) {
        size_t got = 0;
        size_t need = 0;
        int32_t err = MODULE_OK;
        if (host->diag.heartbeat) {
            host->diag.heartbeat();
        }
        if (!inst->capture_stream || !inst->capture_raw || inst->capture_raw_fill >= inst->capture_raw_bytes) {
            host->task.delay(1);
            continue;
        }
        need = inst->capture_raw_bytes - inst->capture_raw_fill;
        err = host->i2s.read(inst->capture_stream,
                             inst->capture_raw + inst->capture_raw_fill,
                             need,
                             &got,
                             inst->capture_read_timeout_ms);
        if (err != MODULE_OK) {
            xz_set_error(inst, "voice.capture: i2s read failed");
            break;
        }
        if (got == 0) {
            host->task.delay(1);
            continue;
        }
        inst->capture_raw_fill += got;
        if (inst->capture_raw_fill >= inst->capture_raw_bytes) {
            int16_t *pcm = NULL;
            size_t pcm_len = 0;
            int opus_len = 0;
            if (capture_queue_full(inst)) {
                inst->capture_raw_fill = 0;
                inst->capture_dropped++;
                if (host->task.delay) {
                    host->task.delay(1);
                } else if (host->task.yield) {
                    host->task.yield();
                }
                continue;
            }
            err = convert_i2s32_frame_to_pcm16(inst,
                                               inst->capture_raw,
                                               inst->capture_raw_bytes,
                                               inst->capture_pack,
                                               inst->capture_gain_shift,
                                               &pcm,
                                               &pcm_len);
            if (err == MODULE_OK) {
                if (inst->capture_opus) {
                    err = encode_current_frame(inst,
                                               (const uint8_t *)pcm,
                                               pcm_len,
                                               inst->capture_opus,
                                               XZ_MAX_OPUS_BYTES,
                                               &opus_len);
                } else {
                    xz_set_error(inst, "voice.capture: no opus buffer");
                    err = MODULE_ERR_NO_MEMORY;
                }
            }
            inst->capture_raw_fill = 0;
            if (err != MODULE_OK) {
                break;
            }
            capture_push_opus(inst, inst->capture_opus, opus_len);
            inst->capture_frames++;
            if (host->task.delay) {
                host->task.delay(1);
            } else if (host->task.yield) {
                host->task.yield();
            }
        }
    }

    /* Complete normal I2S teardown in the worker before capture_running is
     * cleared, so a following wake/capture owner cannot race the old stream. */
    if (inst->capture_stream && host->i2s.end) {
        void *stream = inst->capture_stream;
        inst->capture_stream = NULL;
        if (host->i2s.end(stream) != MODULE_OK) {
            xz_set_error(inst, "voice.capture: i2s release failed");
        }
    }
    if (host->serial.println) {
        host->serial.println("[xiaozhi.so] capture task stop");
    }
    __atomic_store_n(&inst->capture_running, 0, __ATOMIC_RELEASE);
    /* Returning lets the host trampoline unregister and delete the task once.
     * Calling remove(NULL) here and then keeping an infinite fallback loop can
     * leave a suspended task behind on hosts whose self-delete is deferred. */
}

static void stop_capture(xz_instance_t *inst)
{
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    uint32_t start_ms = 0;
    if (!inst || !host) {
        return;
    }
    inst->capture_stop = 1;
    start_ms = host->time.millis ? host->time.millis() : 0;
    while (__atomic_load_n(&inst->capture_running, __ATOMIC_ACQUIRE) && inst->capture_task) {
        uint32_t now = host->time.millis ? host->time.millis() : start_ms + 1000;
        if (now - start_ms > 1500U) {
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
            xz_set_error(inst, "voice.capture_stop: i2s release failed");
        }
    }
    inst->capture_task = NULL;
    inst->capture_stop = 0;
    inst->capture_raw_fill = 0;
    inst->capture_head = 0;
    inst->capture_tail = 0;
    free_capture_buffers(inst);
}

static int decode_current_frame(xz_instance_t *inst,
                                const uint8_t *opus,
                                size_t opus_len,
                                int16_t **out_pcm,
                                size_t *out_pcm_bytes)
{
    int decoded = 0;
    int16_t *pcm = NULL;
    size_t pcm_cap = 0;
    if (!inst || !inst->started || !inst->decoder) {
        xz_set_error(inst, "voice.decode: decoder not started");
        return MODULE_ERR_BAD_STATE;
    }
    if (!opus || opus_len == 0) {
        xz_set_error(inst, "voice.decode: expected opus packet");
        return MODULE_ERR_INVALID_ARG;
    }
    pcm_cap = (size_t)inst->frame_samples * (size_t)inst->channels * sizeof(int16_t);
    pcm = (int16_t *)inst->host->heap.malloc(pcm_cap, MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    if (!pcm) {
        pcm = (int16_t *)inst->host->heap.malloc(pcm_cap, MODULE_HEAP_DEFAULT);
    }
    if (!pcm) {
        xz_set_error(inst, "voice.decode: no memory");
        return MODULE_ERR_NO_MEMORY;
    }

    decoded = opus_decode(inst->decoder,
                          opus,
                          (opus_int32)opus_len,
                          pcm,
                          inst->frame_samples,
                          0);
    if (decoded <= 0) {
        inst->host->heap.free(pcm);
        xz_set_error(inst, "voice.decode: opus_decode failed");
        return MODULE_ERR_FAILED;
    }

    for (int i=0;i<decoded*inst->channels;i++) pcm[i]=(int16_t)((int32_t)pcm[i]*inst->playback_volume/100);
    *out_pcm = pcm;
    *out_pcm_bytes = (size_t)decoded * (size_t)inst->channels * sizeof(int16_t);
    inst->decode_count++;
    inst->opus_bytes_in += (uint32_t)opus_len;
    inst->pcm_bytes_out += (uint32_t)*out_pcm_bytes;
    return MODULE_OK;
}

static int write_pcm(xz_instance_t *inst, const uint8_t *pcm, size_t pcm_len)
{
    size_t written = 0;
    int32_t err = MODULE_OK;
    if (!inst || !pcm || pcm_len == 0) {
        return MODULE_ERR_INVALID_ARG;
    }
    err = ensure_audio(inst, 0);
    if (err != MODULE_OK) {
        return err;
    }
    err = inst->host->audio.write(inst->audio_stream, pcm, pcm_len, &written);
    if (err != MODULE_OK || written != pcm_len) {
        xz_set_error(inst, "voice.play: audio write failed");
        return MODULE_ERR_IO;
    }
    inst->play_count++;
    return MODULE_OK;
}

static int l_voice_info(lua_State *L)
{
    xz_instance_t *inst = instance_from_lua(L);
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    if (!host || !inst) {
        return 0;
    }
    host->lua.createtable(L, 0, 32);
    set_string_field(L, host, "version", XZ_VERSION);
    set_boolean_field(L, host, "started", inst->started);
    set_boolean_field(L, host, "tx", inst->tx_enabled);
    set_boolean_field(L, host, "rx", inst->rx_enabled);
    set_boolean_field(L, host, "hold_audio", inst->hold_audio);
    set_boolean_field(L, host, "audio_open", inst->audio_stream != NULL);
    set_integer_field(L, host, "rate", inst->rate);
    set_integer_field(L, host, "channels", inst->channels);
    set_integer_field(L, host, "frame_ms", inst->frame_ms);
    set_integer_field(L, host, "frame_samples", inst->frame_samples);
    set_integer_field(L, host, "frame_pcm_bytes", inst->frame_pcm_bytes);
    set_integer_field(L, host, "bitrate", inst->bitrate);
    set_integer_field(L, host, "complexity", inst->complexity);
    set_integer_field(L, host, "encode_count", inst->encode_count);
    set_integer_field(L, host, "decode_count", inst->decode_count);
    set_integer_field(L, host, "play_count", inst->play_count);
    set_integer_field(L, host, "pcm_bytes_in", inst->pcm_bytes_in);
    set_integer_field(L, host, "pcm_bytes_out", inst->pcm_bytes_out);
    set_integer_field(L, host, "opus_bytes_in", inst->opus_bytes_in);
    set_integer_field(L, host, "opus_bytes_out", inst->opus_bytes_out);
    set_boolean_field(L, host, "capture_running", inst->capture_running);
    set_integer_field(L, host, "capture_frames", inst->capture_frames);
    set_integer_field(L, host, "capture_dropped", inst->capture_dropped);
    set_integer_field(L, host, "capture_depth", inst->capture_depth);
    set_integer_field(L, host, "capture_head", inst->capture_head);
    set_integer_field(L, host, "capture_tail", inst->capture_tail);
    set_integer_field(L, host, "capture_raw_bytes", inst->capture_raw_bytes);
    set_integer_field(L, host, "capture_read_timeout_ms", inst->capture_read_timeout_ms);
    set_string_field(L, host, "capture_pack", inst->capture_pack);
    set_string_field(L, host, "last_error", inst->last_error);
    return 1;
}

static int l_voice_start(lua_State *L)
{
    xz_instance_t *inst = instance_from_lua(L);
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    int err = MODULE_OK;
    if (!host || !inst) {
        return 0;
    }
    err = voice_start_from_table(inst, L, (host->lua.gettop(L) >= 1 && host->lua.istable(L, 1)) ? 1 : 0);
    if (err != MODULE_OK) {
        return push_error(L, host, inst->last_error);
    }
    host->lua.pushboolean(L, 1);
    return 1;
}

static int l_voice_stop(lua_State *L)
{
    xz_instance_t *inst = instance_from_lua(L);
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    if (!host || !inst) {
        return 0;
    }
    destroy_codecs(inst);
    host->lua.pushboolean(L, 1);
    return 1;
}

static int l_voice_encode(lua_State *L)
{
    xz_instance_t *inst = instance_from_lua(L);
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    const char *pcm = NULL;
    size_t pcm_len = 0;
    int opus_len = 0;
    int err = MODULE_OK;
    if (!host || !inst) {
        return 0;
    }
    pcm = host->lua.checklstring(L, 1, &pcm_len);
    err = ensure_tx_opus_scratch(inst);
    if (err == MODULE_OK) {
        err = encode_current_frame(inst, (const uint8_t *)pcm, pcm_len,
                                   inst->tx_opus_scratch, inst->tx_opus_scratch_bytes,
                                   &opus_len);
    }
    if (err != MODULE_OK) {
        return push_error(L, host, inst->last_error);
    }
    host->lua.pushlstring(L, (const char *)inst->tx_opus_scratch, (size_t)opus_len);
    return 1;
}

static int l_voice_encode_i2s(lua_State *L)
{
    xz_instance_t *inst = instance_from_lua(L);
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    const char *raw = NULL;
    const char *pack = "b23";
    size_t raw_len = 0;
    int gain_shift = 0;
    int16_t *pcm = NULL;
    size_t pcm_len = 0;
    int opus_len = 0;
    int err = MODULE_OK;
    if (!host || !inst) {
        return 0;
    }
    raw = host->lua.checklstring(L, 1, &raw_len);
    if (host->lua.gettop(L) >= 2 && host->lua.isstring(L, 2)) {
        pack = host->lua.tostring(L, 2);
    }
    if (host->lua.gettop(L) >= 3 && host->lua.isnumber(L, 3)) {
        gain_shift = (int)host->lua.tointeger(L, 3);
    }
    err = convert_i2s32_frame_to_pcm16(inst,
                                       (const uint8_t *)raw,
                                       raw_len,
                                       pack,
                                       gain_shift,
                                       &pcm,
                                       &pcm_len);
    if (err != MODULE_OK) {
        return push_error(L, host, inst->last_error);
    }
    err = ensure_tx_opus_scratch(inst);
    if (err == MODULE_OK) {
        err = encode_current_frame(inst, (const uint8_t *)pcm, pcm_len,
                                   inst->tx_opus_scratch, inst->tx_opus_scratch_bytes,
                                   &opus_len);
    }
    if (err != MODULE_OK) {
        return push_error(L, host, inst->last_error);
    }
    host->lua.pushlstring(L, (const char *)inst->tx_opus_scratch, (size_t)opus_len);
    return 1;
}

static int l_voice_decode(lua_State *L)
{
    xz_instance_t *inst = instance_from_lua(L);
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    const char *opus = NULL;
    size_t opus_len = 0;
    int16_t *pcm = NULL;
    size_t pcm_len = 0;
    int err = MODULE_OK;
    if (!host || !inst) {
        return 0;
    }
    opus = host->lua.checklstring(L, 1, &opus_len);
    err = decode_current_frame(inst, (const uint8_t *)opus, opus_len, &pcm, &pcm_len);
    if (err != MODULE_OK) {
        return push_error(L, host, inst->last_error);
    }
    host->lua.pushlstring(L, (const char *)pcm, pcm_len);
    host->heap.free(pcm);
    return 1;
}

static int l_voice_play(lua_State *L)
{
    xz_instance_t *inst = instance_from_lua(L);
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    const char *data = NULL;
    size_t data_len = 0;
    const char *mode = NULL;
    int force_pcm = 0;
    int force_opus = 0;
    int err = MODULE_OK;
    if (!host || !inst) {
        return 0;
    }

    data = host->lua.checklstring(L, 1, &data_len);
    if (host->lua.gettop(L) >= 2 && host->lua.isstring(L, 2)) {
        mode = host->lua.tostring(L, 2);
        force_pcm = strcmp(mode, "pcm") == 0;
        force_opus = strcmp(mode, "opus") == 0;
    }

    if (force_pcm || (!force_opus && data_len >= (size_t)inst->frame_pcm_bytes)) {
        err = write_pcm(inst, (const uint8_t *)data, data_len);
        if (err != MODULE_OK) {
            return push_error(L, host, inst->last_error);
        }
    } else {
        int16_t *pcm = NULL;
        size_t pcm_len = 0;
        err = decode_current_frame(inst, (const uint8_t *)data, data_len, &pcm, &pcm_len);
        if (err == MODULE_OK) {
            err = write_pcm(inst, (const uint8_t *)pcm, pcm_len);
            host->heap.free(pcm);
        }
        if (err != MODULE_OK) {
            return push_error(L, host, inst->last_error);
        }
    }

    host->lua.pushboolean(L, 1);
    return 1;
}

#include "playback.inc"

static int l_voice_capture_start(lua_State *L)
{
    xz_instance_t *inst = instance_from_lua(L);
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    module_i2s_config_t cfg;
    void *stream = NULL;
    void *task = NULL;
    int32_t err = MODULE_OK;
    int cfg_idx = 0;
    int queue_depth = XZ_CAPTURE_DEFAULT_QUEUE;
    int stack_bytes = XZ_CAPTURE_DEFAULT_STACK;
    int priority = XZ_CAPTURE_DEFAULT_PRIORITY;
    int core = XZ_CAPTURE_DEFAULT_CORE;
    const char *pack = "b23";

    if (!host || !inst) {
        return 0;
    }
    if (!inst->started || !inst->encoder) {
        xz_set_error(inst, "voice.capture_start: encoder not started");
        return push_error(L, host, inst->last_error);
    }
    if (!host->i2s.begin || !host->i2s.read || !host->i2s.end ||
        !host->task.create_ex || !host->task.remove || !host->task.delay) {
        xz_set_error(inst, "voice.capture_start: host i2s/task API missing");
        return push_error(L, host, inst->last_error);
    }
    if (inst->capture_running) {
        host->lua.pushboolean(L, 1);
        return 1;
    }

    stop_playback(inst);
    stop_capture(inst);
    opus_encoder_ctl(inst->encoder, OPUS_RESET_STATE);
    cfg_idx = (host->lua.gettop(L) >= 1 && host->lua.istable(L, 1)) ? 1 : 0;
    queue_depth = cfg_idx ? read_int_field(L, host, cfg_idx, "queue_depth", queue_depth) : queue_depth;
    stack_bytes = cfg_idx ? read_int_field(L, host, cfg_idx, "task_stack", stack_bytes) : stack_bytes;
    priority = cfg_idx ? read_int_field(L, host, cfg_idx, "priority", priority) : priority;
    core = cfg_idx ? read_int_field(L, host, cfg_idx, "core", core) : core;
    inst->capture_gain_shift = cfg_idx ? read_int_field(L, host, cfg_idx, "gain_shift", 0) : 0;
    inst->capture_read_timeout_ms = (uint32_t)(cfg_idx ? read_int_field(L, host, cfg_idx, "read_timeout_ms", XZ_CAPTURE_DEFAULT_READ_TIMEOUT_MS)
                                                       : XZ_CAPTURE_DEFAULT_READ_TIMEOUT_MS);
    pack = cfg_idx ? read_string_field(L, host, cfg_idx, "pack", "b23") : "b23";
    copy_pack_name(inst->capture_pack, pack);

    if (stack_bytes < XZ_CAPTURE_DEFAULT_STACK) {
        stack_bytes = XZ_CAPTURE_DEFAULT_STACK;
    }
    if (priority < 1) {
        priority = 1;
    }
    if (priority > 10) {
        priority = 10;
    }
    if (core < -1 || core > 1) {
        core = XZ_CAPTURE_DEFAULT_CORE;
    }
    if (inst->capture_read_timeout_ms < 1) {
        inst->capture_read_timeout_ms = 1;
    }

    err = alloc_capture_buffers(inst, (uint32_t)queue_depth, 1);
    if (err != MODULE_OK) {
        return push_error(L, host, inst->last_error);
    }

    memset(&cfg, 0, sizeof(cfg));
    cfg.size = sizeof(cfg);
    cfg.port = (uint8_t)(cfg_idx ? read_int_field(L, host, cfg_idx, "i2s_id", 0) : 0);
    cfg.mode = MODULE_I2S_MODE_RX;
    cfg.sample_rate = (uint32_t)(cfg_idx ? read_int_field(L, host, cfg_idx, "rate", inst->rate) : inst->rate);
    cfg.bits = (uint16_t)(cfg_idx ? read_int_field(L, host, cfg_idx, "bits", 32) : 32);
    cfg.channels = 1;
    cfg.format = MODULE_I2S_FORMAT_I2S;
    cfg.channel_mode = MODULE_I2S_CHANNEL_MONO_LEFT;
    cfg.bclk_pin = (int16_t)(cfg_idx ? read_int_field(L, host, cfg_idx, "bclk_pin", 41) : 41);
    cfg.ws_pin = (int16_t)(cfg_idx ? read_int_field(L, host, cfg_idx, "ws_pin", 45) : 45);
    cfg.dout_pin = -1;
    cfg.din_pin = (int16_t)(cfg_idx ? read_int_field(L, host, cfg_idx, "din_pin", 42) : 42);
    cfg.mclk_pin = -1;
    cfg.dma_buf_count = (uint16_t)(cfg_idx ? read_int_field(L, host, cfg_idx, "buffer_count", 8) : 8);
    cfg.dma_buf_len = (uint16_t)(cfg_idx ? read_int_field(L, host, cfg_idx, "buffer_len", inst->frame_samples) : inst->frame_samples);
    cfg.flags = 0;

    err = host->i2s.begin(&cfg, &stream);
    if (err != MODULE_OK || !stream) {
        free_capture_buffers(inst);
        xz_set_error(inst, "voice.capture_start: i2s busy or unavailable");
        return push_error(L, host, inst->last_error);
    }
    inst->capture_stream = stream;
    inst->capture_stop = 0;
    inst->capture_running = 1;
    inst->capture_frames = 0;
    inst->capture_dropped = 0;

    err = host->task.create_ex("xz_capture",
                               capture_task_entry,
                               inst,
                               (uint32_t)stack_bytes,
                               (uint32_t)priority,
                               core,
                               MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT,
                               &task);
    if (err != MODULE_OK || !task) {
        inst->capture_running = 0;
        if (inst->capture_stream) {
            host->i2s.end(inst->capture_stream);
            inst->capture_stream = NULL;
        }
        free_capture_buffers(inst);
        xz_set_error(inst, "voice.capture_start: task create failed");
        return push_error(L, host, inst->last_error);
    }
    inst->capture_task = task;
    xz_set_error(inst, "");
    host->lua.pushboolean(L, 1);
    return 1;
}

static int l_voice_capture_read(lua_State *L)
{
    xz_instance_t *inst = instance_from_lua(L);
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    uint32_t tail = 0;
    uint16_t len = 0;
    if (!host || !inst) {
        return 0;
    }
    if (!inst->capture_queue || !inst->capture_lens || inst->capture_tail == __atomic_load_n(&inst->capture_head, __ATOMIC_ACQUIRE)) {
        host->lua.pushnil(L);
        return 1;
    }
    tail = inst->capture_tail;
    len = inst->capture_lens[tail];
    if (len == 0 || len > XZ_MAX_OPUS_BYTES) {
        inst->capture_tail = (tail + 1U) % inst->capture_depth;
        host->lua.pushnil(L);
        return 1;
    }
    host->lua.pushlstring(L,
                          (const char *)(inst->capture_queue + ((size_t)tail * XZ_MAX_OPUS_BYTES)),
                          (size_t)len);
    inst->capture_lens[tail] = 0;
    __atomic_store_n(&inst->capture_tail, (tail + 1U) % inst->capture_depth, __ATOMIC_RELEASE);
    return 1;
}

static int l_voice_capture_stop(lua_State *L)
{
    xz_instance_t *inst = instance_from_lua(L);
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    if (!host || !inst) {
        return 0;
    }
    stop_playback(inst);
    stop_capture(inst);
    host->lua.pushboolean(L, 1);
    return 1;
}

static int l_xz_open(lua_State *L)
{
    return l_voice_start(L);
}

static int l_xz_send_pcm(lua_State *L)
{
    return l_voice_encode(L);
}

static int l_xz_send_i2s(lua_State *L)
{
    return l_voice_encode_i2s(L);
}

static int l_xz_on_binary(lua_State *L)
{
    xz_instance_t *inst = instance_from_lua(L);
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    const char *data = NULL;
    size_t data_len = 0;
    int16_t *pcm = NULL;
    size_t pcm_len = 0;
    int err = MODULE_OK;
    if (!host || !inst) {
        return 0;
    }
    data = host->lua.checklstring(L, 1, &data_len);
    err = decode_current_frame(inst, (const uint8_t *)data, data_len, &pcm, &pcm_len);
    if (err == MODULE_OK) {
        err = write_pcm(inst, (const uint8_t *)pcm, pcm_len);
        host->heap.free(pcm);
    }
    if (err != MODULE_OK) {
        return push_error(L, host, inst->last_error);
    }
    host->lua.pushboolean(L, 1);
    return 1;
}

static int l_xz_close(lua_State *L)
{
    return l_voice_stop(L);
}

static int l_xz_info(lua_State *L)
{
    return l_voice_info(L);
}

static void push_voice_table(lua_State *L, const module_host_api_v2 *host, xz_instance_t *inst)
{
    host->lua.createtable(L, 0, 15);
    set_string_field(L, host, "VERSION", XZ_VERSION);
    set_integer_field(L, host, "DEFAULT_RATE", XZ_DEFAULT_RATE);
    set_integer_field(L, host, "DEFAULT_CHANNELS", XZ_DEFAULT_CHANNELS);
    set_integer_field(L, host, "DEFAULT_FRAME_MS", XZ_DEFAULT_FRAME_MS);
    set_function_field(L, host, "start", l_voice_start, inst);
    set_function_field(L, host, "encode", l_voice_encode, inst);
    set_function_field(L, host, "encode_i2s", l_voice_encode_i2s, inst);
    set_function_field(L, host, "capture_start", l_voice_capture_start, inst);
    set_function_field(L, host, "playback_start", l_playback_start, inst);
    set_function_field(L, host, "playback_write", l_playback_write, inst);
    set_function_field(L, host, "playback_status", l_playback_status, inst);
    set_function_field(L, host, "playback_finish", l_playback_finish, inst);
    set_function_field(L, host, "playback_stop", l_playback_stop, inst);
    set_function_field(L, host, "set_volume", l_set_volume, inst);
    set_function_field(L, host, "capture_read", l_voice_capture_read, inst);
    set_function_field(L, host, "capture_stop", l_voice_capture_stop, inst);
    set_function_field(L, host, "decode", l_voice_decode, inst);
    set_function_field(L, host, "play", l_voice_play, inst);
    set_function_field(L, host, "stop", l_voice_stop, inst);
    set_function_field(L, host, "info", l_voice_info, inst);
}

static void push_xz_table(lua_State *L, const module_host_api_v2 *host, xz_instance_t *inst)
{
    host->lua.createtable(L, 0, 10);
    set_string_field(L, host, "VERSION", XZ_VERSION);
    set_function_field(L, host, "open", l_xz_open, inst);
    set_function_field(L, host, "send_pcm", l_xz_send_pcm, inst);
    set_function_field(L, host, "send_i2s", l_xz_send_i2s, inst);
    set_function_field(L, host, "on_binary", l_xz_on_binary, inst);
    set_function_field(L, host, "close", l_xz_close, inst);
    set_function_field(L, host, "info", l_xz_info, inst);
}

XZ_MODULE_EXPORT const module_manifest_t *module_query_v1(void)
{
    return &s_manifest;
}

XZ_MODULE_EXPORT int32_t module_create_v2(module_host_resolve_v2_fn resolve,
                                          void *resolve_ctx,
                                          const module_open_info_t *info,
                                          void **out_instance)
{
    xz_instance_t *inst = NULL;
    int32_t err = MODULE_OK;
    (void)info;
    if (!resolve || !out_instance) {
        return MODULE_ERR_INVALID_ARG;
    }
    *out_instance = NULL;

    err = module_sdk_resolve_host_v2(resolve, resolve_ctx, &s_host_store);
    if (err != MODULE_OK) {
        return err;
    }
    s_host = &s_host_store;
    if (!s_host->heap.calloc || !s_host->heap.free || !s_host->lua.createtable ||
        !s_host->lua.checklstring || !s_host->lua.pushlstring) {
        return MODULE_ERR_UNSUPPORTED;
    }

    inst = (xz_instance_t *)s_host->heap.calloc(1,
                                                sizeof(xz_instance_t),
                                                MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    if (!inst) {
        inst = (xz_instance_t *)s_host->heap.calloc(1, sizeof(xz_instance_t), MODULE_HEAP_DEFAULT);
    }
    if (!inst) {
        return MODULE_ERR_NO_MEMORY;
    }

    inst->host = s_host;
    inst->created_ms = s_host->time.millis ? s_host->time.millis() : 0;
    inst->rate = XZ_DEFAULT_RATE;
    inst->channels = XZ_DEFAULT_CHANNELS;
    inst->frame_ms = XZ_DEFAULT_FRAME_MS;
    inst->bitrate = XZ_DEFAULT_BITRATE;
    inst->complexity = XZ_DEFAULT_COMPLEXITY;
    inst->tx_enabled = 1;
    inst->rx_enabled = 1;
    inst->hold_audio = 1;
    copy_pack_name(inst->capture_pack, "b23");
    inst->playback_volume = 0; /* Lua supplies the current firmware volume before playback. */
    inst->capture_read_timeout_ms = XZ_CAPTURE_DEFAULT_READ_TIMEOUT_MS;
    normalize_config(inst);
    *out_instance = inst;

    if (s_host->serial.println) {
        s_host->serial.println("[xiaozhi.so] create voice opus module");
    }
    return MODULE_OK;
}

XZ_MODULE_EXPORT int32_t module_luaopen_v1(void *instance, lua_State *L)
{
    xz_instance_t *inst = (xz_instance_t *)instance;
    const module_host_api_v2 *host = inst ? inst->host : s_host;
    if (!inst || !host || !L) {
        return MODULE_ERR_INVALID_ARG;
    }

    host->lua.createtable(L, 0, 10);
    set_string_field(L, host, "VERSION", XZ_VERSION);
    set_string_field(L, host, "NAME", XZ_NAME);
    set_function_field(L, host, "info", l_voice_info, inst);

    push_voice_table(L, host, inst);
    host->lua.pushvalue(L, -1);
    host->lua.setglobal(L, "voice");
    host->lua.setfield(L, -2, "voice");

    push_xz_table(L, host, inst);
    host->lua.pushvalue(L, -1);
    host->lua.setglobal(L, "xz");
    host->lua.setfield(L, -2, "xz");

    return MODULE_OK;
}

XZ_MODULE_EXPORT void module_destroy_v1(void *instance)
{
    xz_instance_t *inst = (xz_instance_t *)instance;
    if (!inst) {
        return;
    }
    destroy_codecs(inst);
#if defined(NONTHREADSAFE_PSEUDOSTACK)
    if (scratch_ptr && inst->host && inst->host->heap.free) {
        inst->host->heap.free(scratch_ptr);
        scratch_ptr = NULL;
        global_stack = NULL;
    }
#endif
    if (inst->host && inst->host->heap.free) {
        inst->host->heap.free(inst);
    }
}
