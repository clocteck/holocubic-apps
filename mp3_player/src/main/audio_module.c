#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include <string.h>

#include "module_abi.h"

#include "esp_chip_info.h"
#include "esp_audio_dec_default.h"
#include "esp_audio_simple_dec.h"
#include "esp_audio_simple_dec_default.h"
#include "esp_audio_types.h"
#include "dsps_biquad.h"

#define AUDIO_MODULE_EXPORT __attribute__((visibility("default"), used))
#define AUDIO_VERSION "1.12"
#define AUDIO_IN_CAP 2048u
#define AUDIO_PREFETCH_CAP (2u * 1024u * 1024u)
#define AUDIO_PREFETCH_READ_CHUNK 8192u
#define AUDIO_PREFETCH_LOW_BYTES (128u * 1024u)
#define AUDIO_PREFETCH_TARGET_BYTES (256u * 1024u)
#define AUDIO_MP3_PROBE_BYTES (64u * 1024u)
#define AUDIO_OUT_CAP 8192u
#define AUDIO_OUT_INIT 4608u
#define AUDIO_DEFAULT_READ 4096u
#define AUDIO_READ_CAP 8192u
#define AUDIO_I2S_PENDING_CAP AUDIO_READ_CAP
#define AUDIO_PCM_RING_CAP (256u * 1024u)
#define AUDIO_PCM_RING_LOW_BYTES (32u * 1024u)
#define AUDIO_PCM_RING_RESUME_BYTES (128u * 1024u)
#define AUDIO_PCM_RING_START_BYTES AUDIO_PCM_RING_RESUME_BYTES
#define AUDIO_PLAY_TASK_STACK 5120u
#define AUDIO_PRODUCER_TASK_STACK 6144u
#define AUDIO_PLAY_TASK_PRIORITY 8u
#define AUDIO_PRODUCER_TASK_PRIORITY 7u
#define AUDIO_PLAY_TASK_CORE 0
#define AUDIO_PLAY_TASK_CHUNK_BYTES 4096u
#define AUDIO_PLAY_TASK_TIMEOUT_MS 80u
#define AUDIO_PLAY_TASK_STOP_WAIT_MS 200u
#define AUDIO_EQ_MAX_BANDS 7u
#define AUDIO_DSP_CHUNK_SAMPLES 256u
#define AUDIO_EQ_MIN_GAIN_DB 0.05f
#define AUDIO_LOUDNESS_SEGMENTS 6u
#define AUDIO_LOUDNESS_SEGMENT_FRAMES 16384u
#define AUDIO_LOUDNESS_DEFAULT_TARGET_RMS 5000u
#define AUDIO_LOUDNESS_DEFAULT_MIN_Q15 14746
#define AUDIO_LOUDNESS_DEFAULT_MAX_Q15 81920
#define AUDIO_LIMITER_DEFAULT_PEAK 31000
#define AUDIO_PI 3.14159265358979323846f

#if defined(CONFIG_IDF_TARGET_ESP32S3)
#define AUDIO_DSPS_BIQUAD_F32 dsps_biquad_f32_aes3
#else
#define AUDIO_DSPS_BIQUAD_F32 dsps_biquad_f32
#endif

typedef struct audio_dsp_filter_t {
    float coeff[5];
    float w[2];
    uint8_t enabled;
} audio_dsp_filter_t;

typedef struct audio_instance_t {
    module_host_api_v1 host;
    void *file;
    void *i2s_stream;
    void *play_task;
    void *producer_task;
    esp_audio_simple_dec_handle_t decoder;
    uint8_t *in_buf;
    uint8_t *prefetch_buf;
    uint8_t *out_buf;
    uint8_t *read_buf;
    uint8_t *i2s_task_buf;
    uint8_t *i2s_pending_buf;
    uint8_t *pcm_ring_buf;
    float *dsp_buf;
    float *vbass_buf;
    size_t in_cap;
    size_t prefetch_cap;
    size_t prefetch_pos;
    size_t prefetch_len;
    size_t out_cap;
    size_t read_cap;
    size_t i2s_task_cap;
    size_t i2s_pending_cap;
    size_t i2s_pending_pos;
    size_t i2s_pending_len;
    size_t pcm_ring_cap;
    size_t pcm_ring_read_pos;
    size_t pcm_ring_write_pos;
    size_t pcm_ring_len;
    size_t dsp_cap;
    size_t vbass_cap;
    size_t pending_len;
    size_t pcm_pos;
    size_t pcm_len;
    uint8_t registered;
    uint8_t opened;
    uint8_t eof;
    uint8_t prefetch_eof;
    uint8_t info_ready;
    uint8_t output_channels;
    uint8_t source_channels;
    uint8_t bits_per_sample;
    uint32_t sample_rate;
    uint32_t bitrate;
    uint64_t file_size;
    int32_t volume_q15;
    uint8_t loudness_enabled;
    uint8_t loudness_ready;
    uint8_t loudness_segments;
    uint32_t loudness_target_rms;
    uint32_t loudness_rms;
    uint32_t loudness_peak;
    int32_t loudness_gain_q15;
    int32_t loudness_min_gain_q15;
    int32_t loudness_max_gain_q15;
    uint8_t eq_enabled;
    uint8_t eq_active;
    uint8_t hpf_enabled;
    uint8_t limiter_enabled;
    int32_t limiter_threshold;
    float hpf_freq;
    float hpf_q;
    float eq_freq[AUDIO_EQ_MAX_BANDS];
    float eq_gain[AUDIO_EQ_MAX_BANDS];
    float eq_q[AUDIO_EQ_MAX_BANDS];
    uint8_t vbass_enabled;
    float vbass_low_hpf;
    float vbass_low_lpf;
    float vbass_out_hpf;
    float vbass_out_lpf;
    float vbass_drive;
    float vbass_mix;
    float vbass_even;
    float vbass_odd;
    uint32_t limiter_active_samples;
    uint32_t limiter_total_samples;
    uint32_t i2s_short_writes;
    volatile uint8_t play_task_stop;
    volatile uint8_t play_task_running;
    volatile uint8_t play_task_eof;
    volatile uint8_t play_task_error;
    volatile uint8_t play_task_paused;
    volatile uint8_t play_task_buffering;
    volatile uint8_t producer_task_running;
    volatile uint8_t producer_task_eof;
    volatile uint8_t producer_task_error;
    volatile uint8_t pcm_ring_eof;
    volatile uint8_t pcm_ring_started;
    uint32_t play_task_chunk_bytes;
    uint32_t play_task_timeout_ms;
    uint32_t producer_task_chunk_bytes;
    uint32_t play_task_written_bytes;
    uint32_t play_task_iterations;
    uint32_t producer_task_iterations;
    uint32_t producer_task_decoded_bytes;
    uint32_t play_task_buffer_events;
    audio_dsp_filter_t hpf;
    audio_dsp_filter_t eq[AUDIO_EQ_MAX_BANDS];
    audio_dsp_filter_t vbass_low_hpf_filter;
    audio_dsp_filter_t vbass_low_lpf_filter;
    audio_dsp_filter_t vbass_out_hpf_filter;
    audio_dsp_filter_t vbass_out_lpf_filter;
    char type_name[8];
    char last_error[96];
} audio_instance_t;

static const module_host_api_v1 *s_host = NULL;
static void audio_play_task_stop_internal(audio_instance_t *inst, uint32_t wait_ms);
static void audio_play_task_exit(audio_instance_t *inst) __attribute__((noreturn));
static void audio_producer_task_exit(audio_instance_t *inst) __attribute__((noreturn));

static const module_manifest_t s_manifest = {
    MODULE_MANIFEST_MAGIC,
    MODULE_SDK_VERSION,
    sizeof(module_manifest_t),
    "audio",
    AUDIO_VERSION,
    "esp_audio_codec MP3/WAV decoder",
    0,
    MODULE_BOOTSTRAP_ABI_VERSION,
};

static int32_t audio_parse_q1000(const char *s, int32_t fallback)
{
    int sign = 1;
    int32_t whole = 0;
    int32_t frac = 0;
    int32_t scale = 100;
    int saw_digit = 0;

    if (!s) {
        return fallback;
    }
    while (*s == ' ' || *s == '\t') {
        ++s;
    }
    if (*s == '-') {
        sign = -1;
        ++s;
    } else if (*s == '+') {
        ++s;
    }
    while (*s >= '0' && *s <= '9') {
        saw_digit = 1;
        if (whole < 2000000) {
            whole = whole * 10 + (int32_t)(*s - '0');
        }
        ++s;
    }
    if (*s == '.') {
        ++s;
        while (*s >= '0' && *s <= '9' && scale > 0) {
            saw_digit = 1;
            frac += (int32_t)(*s - '0') * scale;
            scale /= 10;
            ++s;
        }
    }
    if (!saw_digit) {
        return fallback;
    }
    return sign * (whole * 1000 + frac);
}

/* 从 Lua table 读取 number 字段为 q1000，避免 dynmod 内部走 double helper。 */
static int32_t audio_lua_q1000_field(const module_host_api_v1 *host,
                                     lua_State *L,
                                     int table_idx,
                                     const char *key,
                                     int32_t fallback)
{
    int32_t out = fallback;
    const char *text = NULL;
    if (!host || !host->lua.getfield || !host->lua.settop || !host->lua.tostring) {
        return out;
    }
    host->lua.getfield(L, table_idx, key);
    if ((host->lua.isnumber && host->lua.isnumber(L, -1)) ||
        (host->lua.isstring && host->lua.isstring(L, -1))) {
        text = host->lua.tostring(L, -1);
        out = audio_parse_q1000(text, fallback);
    }
    host->lua.settop(L, table_idx);
    return out;
}

static float audio_q1000_to_float(int32_t q)
{
    return (float)q * 0.001f;
}

/* 从 Lua table 读取 bool 字段；缺省时返回 fallback。 */
static int audio_lua_bool_field(const module_host_api_v1 *host,
                                lua_State *L,
                                int table_idx,
                                const char *key,
                                int fallback)
{
    int out = fallback;
    if (!host || !host->lua.getfield || !host->lua.settop) {
        return out;
    }
    host->lua.getfield(L, table_idx, key);
    if (!host->lua.isnil(L, -1)) {
        out = host->lua.toboolean(L, -1) ? 1 : 0;
    }
    host->lua.settop(L, table_idx);
    return out;
}

/* 防御极端参数，避免窄带高增益把定点滤波器推爆。 */
static float audio_clampf(float v, float lo, float hi)
{
    if (v < lo) {
        return lo;
    }
    if (v > hi) {
        return hi;
    }
    return v;
}

/* 轻量限幅，避免 EQ boost 后把 I2S PCM 溢出。 */
static float audio_clipf(float v, float lo, float hi)
{
    if (v < lo) {
        return lo;
    }
    if (v > hi) {
        return hi;
    }
    return v;
}

/* 把 float 增益转成 q15，允许大于 1.0 用于曲目响度补偿。 */
static int32_t audio_gain_to_q15(float gain, int32_t min_q15, int32_t max_q15)
{
    int32_t out = 32768;
    if (gain < 0.0f) {
        gain = 0.0f;
    }
    out = (int32_t)(gain * 32768.0f + 0.5f);
    if (out < min_q15) {
        out = min_q15;
    } else if (out > max_q15) {
        out = max_q15;
    }
    return out;
}

/* 曲目 RMS 有效后重算固定 track_gain；播放时不再做动态修正。 */
static void audio_recompute_loudness_gain(audio_instance_t *inst)
{
    float gain = 1.0f;
    if (!inst) {
        return;
    }
    if (!inst->loudness_enabled || !inst->loudness_ready || inst->loudness_rms < 16u) {
        inst->loudness_gain_q15 = 32768;
        return;
    }
    gain = (float)inst->loudness_target_rms / (float)inst->loudness_rms;
    inst->loudness_gain_q15 = audio_gain_to_q15(gain,
                                                inst->loudness_min_gain_q15,
                                                inst->loudness_max_gain_q15);
}

/* 合并用户音量与曲目响度增益，避免每个 sample 重复算乘积。 */
static int32_t audio_combined_gain_q15(const audio_instance_t *inst)
{
    int64_t gain = 32768;
    if (!inst) {
        return 32768;
    }
    gain = ((int64_t)inst->volume_q15 * (int64_t)inst->loudness_gain_q15) >> 15;
    if (gain < 0) {
        gain = 0;
    } else if (gain > 196608) {
        gain = 196608;
    }
    return (int32_t)gain;
}

/* 记录 limiter 命中率；计数过大时衰减，避免长时间播放溢出。 */
static void audio_note_limiter(audio_instance_t *inst, uint32_t active, uint32_t total)
{
    if (!inst || total == 0u) {
        return;
    }
    if (!inst->limiter_enabled) {
        inst->limiter_active_samples = 0;
        inst->limiter_total_samples = 0;
        return;
    }
    if (inst->limiter_total_samples > 1000000000u) {
        inst->limiter_active_samples >>= 1u;
        inst->limiter_total_samples >>= 1u;
    }
    inst->limiter_active_samples += active;
    inst->limiter_total_samples += total;
}

/* uint64 整数平方根，避免 dynmod 额外依赖 sqrtf 导出符号。 */
static uint32_t audio_isqrt_u64(uint64_t x)
{
    uint64_t bit = 1ull << 62u;
    uint64_t res = 0;
    while (bit > x) {
        bit >>= 2u;
    }
    while (bit != 0) {
        if (x >= res + bit) {
            x -= res + bit;
            res = (res >> 1u) + bit;
        } else {
            res >>= 1u;
        }
        bit >>= 2u;
    }
    if (res > 0xffffffffull) {
        return 0xffffffffu;
    }
    return (uint32_t)res;
}

/* 拷贝 PCM 聚合缓冲，避免编译器在 dynmod 里生成外部 memcpy 依赖。 */
static void audio_copy_bytes(uint8_t *dst, const uint8_t *src, size_t n)
{
    size_t i = 0;
    if (!dst || !src) {
        return;
    }
    for (i = 0; i < n; ++i) {
        dst[i] = src[i];
    }
}

/* 重置一个 esp-dsp biquad 的历史状态。 */
static void audio_filter_reset(audio_dsp_filter_t *f)
{
    if (!f) {
        return;
    }
    f->w[0] = 0.0f;
    f->w[1] = 0.0f;
}

/* 设置 esp-dsp biquad 系数；a0 已在调用方归一化。 */
static void audio_filter_set(audio_dsp_filter_t *f,
                             float b0,
                             float b1,
                             float b2,
                             float a1,
                             float a2,
                             int enabled)
{
    if (!f) {
        return;
    }
    f->coeff[0] = b0;
    f->coeff[1] = b1;
    f->coeff[2] = b2;
    f->coeff[3] = a1;
    f->coeff[4] = a2;
    f->enabled = enabled ? 1 : 0;
    audio_filter_reset(f);
}

/* 清空 EQ/HPF 状态，切歌或重设参数时避免上一首的历史泄漏。 */
static void audio_reset_filter_state(audio_instance_t *inst)
{
    size_t i = 0;
    if (!inst) {
        return;
    }
    audio_filter_reset(&inst->hpf);
    for (i = 0; i < AUDIO_EQ_MAX_BANDS; ++i) {
        audio_filter_reset(&inst->eq[i]);
    }
    audio_filter_reset(&inst->vbass_low_hpf_filter);
    audio_filter_reset(&inst->vbass_low_lpf_filter);
    audio_filter_reset(&inst->vbass_out_hpf_filter);
    audio_filter_reset(&inst->vbass_out_lpf_filter);
}

/* 配置二阶高通滤波器。 */
static int audio_config_hpf(audio_dsp_filter_t *f, float sample_rate, float freq, float q)
{
    float w0 = 0.0f;
    float cw = 0.0f;
    float sw = 0.0f;
    float alpha = 0.0f;
    float a0 = 1.0f;
    float b0 = 0.0f;
    float b1 = 0.0f;
    float b2 = 0.0f;
    float a1 = 0.0f;
    float a2 = 0.0f;
    if (!f || sample_rate < 8000.0f) {
        return 0;
    }
    freq = audio_clampf(freq, 20.0f, sample_rate * 0.45f);
    q = audio_clampf(q, 0.25f, 4.0f);
    w0 = 2.0f * AUDIO_PI * freq / sample_rate;
    cw = cosf(w0);
    sw = sinf(w0);
    alpha = sw / (2.0f * q);
    b0 = (1.0f + cw) * 0.5f;
    b1 = -(1.0f + cw);
    b2 = (1.0f + cw) * 0.5f;
    a0 = 1.0f + alpha;
    a1 = -2.0f * cw;
    a2 = 1.0f - alpha;
    audio_filter_set(f, b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0, 1);
    return 1;
}

/* 配置二阶低通滤波器。 */
static int audio_config_lpf(audio_dsp_filter_t *f, float sample_rate, float freq, float q)
{
    float w0 = 0.0f;
    float cw = 0.0f;
    float sw = 0.0f;
    float alpha = 0.0f;
    float a0 = 1.0f;
    float b0 = 0.0f;
    float b1 = 0.0f;
    float b2 = 0.0f;
    float a1 = 0.0f;
    float a2 = 0.0f;
    if (!f || sample_rate < 8000.0f) {
        return 0;
    }
    freq = audio_clampf(freq, 20.0f, sample_rate * 0.45f);
    q = audio_clampf(q, 0.25f, 4.0f);
    w0 = 2.0f * AUDIO_PI * freq / sample_rate;
    cw = cosf(w0);
    sw = sinf(w0);
    alpha = sw / (2.0f * q);
    b0 = (1.0f - cw) * 0.5f;
    b1 = 1.0f - cw;
    b2 = (1.0f - cw) * 0.5f;
    a0 = 1.0f + alpha;
    a1 = -2.0f * cw;
    a2 = 1.0f - alpha;
    audio_filter_set(f, b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0, 1);
    return 1;
}

/* 配置一个 RBJ peaking EQ 频段。 */
static int audio_config_peak(audio_dsp_filter_t *f, float sample_rate, float freq, float gain_db, float q)
{
    float amp = 1.0f;
    float w0 = 0.0f;
    float cw = 0.0f;
    float sw = 0.0f;
    float alpha = 0.0f;
    float a0 = 1.0f;
    float b0 = 1.0f;
    float b1 = 0.0f;
    float b2 = 0.0f;
    float a1 = 0.0f;
    float a2 = 0.0f;
    if (!f || sample_rate < 8000.0f) {
        return 0;
    }
    if (gain_db > -AUDIO_EQ_MIN_GAIN_DB && gain_db < AUDIO_EQ_MIN_GAIN_DB) {
        f->enabled = 0;
        audio_filter_reset(f);
        return 0;
    }
    freq = audio_clampf(freq, 20.0f, sample_rate * 0.45f);
    gain_db = audio_clampf(gain_db, -6.0f, 6.0f);
    q = audio_clampf(q, 0.25f, 4.0f);
    amp = powf(10.0f, gain_db / 40.0f);
    w0 = 2.0f * AUDIO_PI * freq / sample_rate;
    cw = cosf(w0);
    sw = sinf(w0);
    alpha = sw / (2.0f * q);
    b0 = 1.0f + alpha * amp;
    b1 = -2.0f * cw;
    b2 = 1.0f - alpha * amp;
    a0 = 1.0f + alpha / amp;
    a1 = -2.0f * cw;
    a2 = 1.0f - alpha / amp;
    audio_filter_set(f, b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0, 1);
    return 1;
}

/* 按当前采样率重建 EQ/HPF 系数。 */
static void audio_rebuild_filters(audio_instance_t *inst)
{
    size_t i = 0;
    float sr = 44100.0f;
    if (!inst) {
        return;
    }
    sr = (inst->sample_rate >= 8000u) ? (float)inst->sample_rate : 44100.0f;
    inst->eq_active = 0;
    if (inst->hpf_enabled) {
        if (!audio_config_hpf(&inst->hpf, sr, inst->hpf_freq, inst->hpf_q)) {
            inst->hpf.enabled = 0;
        }
    } else {
        inst->hpf.enabled = 0;
        audio_filter_reset(&inst->hpf);
    }
    if (!inst->eq_enabled) {
        for (i = 0; i < AUDIO_EQ_MAX_BANDS; ++i) {
            inst->eq[i].enabled = 0;
            audio_filter_reset(&inst->eq[i]);
        }
    } else {
        for (i = 0; i < AUDIO_EQ_MAX_BANDS; ++i) {
            if (audio_config_peak(&inst->eq[i], sr, inst->eq_freq[i], inst->eq_gain[i], inst->eq_q[i])) {
                inst->eq_active++;
            }
        }
    }
    if (!inst->vbass_enabled) {
        inst->vbass_low_hpf_filter.enabled = 0;
        inst->vbass_low_lpf_filter.enabled = 0;
        inst->vbass_out_hpf_filter.enabled = 0;
        inst->vbass_out_lpf_filter.enabled = 0;
        audio_filter_reset(&inst->vbass_low_hpf_filter);
        audio_filter_reset(&inst->vbass_low_lpf_filter);
        audio_filter_reset(&inst->vbass_out_hpf_filter);
        audio_filter_reset(&inst->vbass_out_lpf_filter);
        return;
    }
    if (!audio_config_hpf(&inst->vbass_low_hpf_filter, sr, inst->vbass_low_hpf, 0.707f) ||
        !audio_config_lpf(&inst->vbass_low_lpf_filter, sr, inst->vbass_low_lpf, 0.707f) ||
        !audio_config_hpf(&inst->vbass_out_hpf_filter, sr, inst->vbass_out_hpf, 0.707f) ||
        !audio_config_lpf(&inst->vbass_out_lpf_filter, sr, inst->vbass_out_lpf, 0.707f)) {
        inst->vbass_low_hpf_filter.enabled = 0;
        inst->vbass_low_lpf_filter.enabled = 0;
        inst->vbass_out_hpf_filter.enabled = 0;
        inst->vbass_out_lpf_filter.enabled = 0;
    }
}

/* 写入最后错误，Lua 层按 NodeMCU 风格返回 nil, err。 */
static void audio_set_error(audio_instance_t *inst, const char *msg)
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

/* 返回 Lua `(nil, err)`。 */
static int push_error(lua_State *L, const module_host_api_v1 *host, const char *msg)
{
    host->lua.pushnil(L);
    host->lua.pushstring(L, msg ? msg : "audio failed");
    return 2;
}

/* 从 closure upvalue 取模块实例。 */
static audio_instance_t *instance_from_lua(lua_State *L)
{
    if (!s_host || !s_host->lua.touserdata || !s_host->lua.upvalue_index) {
        return NULL;
    }
    return (audio_instance_t *)s_host->lua.touserdata(L, s_host->lua.upvalue_index(1));
}

/* 注册 Lua 函数，并捕获当前实例指针。 */
static void set_function_field(lua_State *L,
                               const module_host_api_v1 *host,
                               const char *key,
                               module_lua_cfunction_t fn,
                               audio_instance_t *inst)
{
    host->lua.pushlightuserdata(L, inst);
    host->lua.pushcclosure(L, fn, 1);
    host->lua.setfield(L, -2, key);
}

static void audio_reset_prefetch(audio_instance_t *inst)
{
    if (!inst) {
        return;
    }
    inst->prefetch_pos = 0;
    inst->prefetch_len = 0;
    inst->prefetch_eof = 0;
}

static int audio_prefetch_fill(audio_instance_t *inst, size_t target_bytes, size_t max_bytes)
{
    size_t total = 0;
    if (!inst || !inst->file || !inst->host.file.read || !inst->prefetch_buf ||
        inst->prefetch_cap == 0 || inst->prefetch_eof) {
        return 1;
    }
    if (target_bytes == 0 || target_bytes > inst->prefetch_cap) {
        target_bytes = inst->prefetch_cap;
    }
    if (max_bytes == 0) {
        max_bytes = AUDIO_PREFETCH_READ_CHUNK;
    }
    while (inst->prefetch_len < target_bytes && total < max_bytes) {
        size_t got = 0;
        size_t want = target_bytes - inst->prefetch_len;
        size_t free_bytes = inst->prefetch_cap - inst->prefetch_len;
        size_t write_pos = 0;
        size_t tail = 0;
        int32_t err = MODULE_OK;
        if (free_bytes == 0) {
            break;
        }
        if (want > free_bytes) {
            want = free_bytes;
        }
        if (want > AUDIO_PREFETCH_READ_CHUNK) {
            want = AUDIO_PREFETCH_READ_CHUNK;
        }
        if (want > max_bytes - total) {
            want = max_bytes - total;
        }
        if (want == 0) {
            break;
        }
        write_pos = (inst->prefetch_pos + inst->prefetch_len) % inst->prefetch_cap;
        tail = inst->prefetch_cap - write_pos;
        if (want > tail) {
            want = tail;
        }
        err = inst->host.file.read(inst->file,
                                   inst->prefetch_buf + write_pos,
                                   want,
                                   &got);
        if (err != MODULE_OK) {
            audio_set_error(inst, "audio: prefetch read failed");
            return 0;
        }
        if (got == 0) {
            inst->prefetch_eof = 1;
            break;
        }
        inst->prefetch_len += got;
        total += got;
    }
    return 1;
}

static size_t audio_prefetch_take(audio_instance_t *inst, uint8_t *dst, size_t max_bytes)
{
    size_t n = 0;
    size_t first = 0;
    if (!inst || !dst || !inst->prefetch_buf || max_bytes == 0 || inst->prefetch_len == 0) {
        return 0;
    }
    n = inst->prefetch_len;
    if (n > max_bytes) {
        n = max_bytes;
    }
    first = inst->prefetch_cap - inst->prefetch_pos;
    if (first > n) {
        first = n;
    }
    audio_copy_bytes(dst, inst->prefetch_buf + inst->prefetch_pos, first);
    if (n > first) {
        audio_copy_bytes(dst + first, inst->prefetch_buf, n - first);
    }
    inst->prefetch_pos = (inst->prefetch_pos + n) % inst->prefetch_cap;
    inst->prefetch_len -= n;
    if (inst->prefetch_len == 0) {
        inst->prefetch_pos = 0;
    }
    return n;
}

static int audio_prefetch_refill_low_water(audio_instance_t *inst)
{
    size_t low = AUDIO_PREFETCH_LOW_BYTES;
    size_t target = AUDIO_PREFETCH_TARGET_BYTES;
    size_t max_bytes = AUDIO_PREFETCH_TARGET_BYTES;
    if (!inst || !inst->prefetch_buf || inst->prefetch_cap == 0 || inst->prefetch_eof) {
        return 1;
    }
    if (low > inst->prefetch_cap) {
        low = inst->prefetch_cap;
    }
    if (target > inst->prefetch_cap) {
        target = inst->prefetch_cap;
    }
    if (target < low) {
        target = low;
    }
    if (inst->prefetch_len >= low) {
        return 1;
    }
    return audio_prefetch_fill(inst, target, max_bytes);
}

static int audio_build_open_path(audio_instance_t *inst,
                                 lua_State *L,
                                 char *out,
                                 size_t out_size)
{
    const module_host_api_v1 *host = inst ? &inst->host : s_host;
    const char *name = NULL;
    const char *dir = NULL;
    size_t name_len = 0;
    size_t dir_len = 0;
    if (!host || !out || out_size == 0) {
        return 0;
    }
    name = host->lua.checkstring(L, 1);
    if (!name || name[0] == '\0') {
        return 0;
    }
    if (name[0] == '/') {
        if (strlen(name) >= out_size) {
            return 0;
        }
        strcpy(out, name);
        return 1;
    }
    if (host->lua.istable(L, 2)) {
        host->lua.getfield(L, 2, "dir");
        if (host->lua.isstring(L, -1)) {
            dir = host->lua.tostring(L, -1);
        }
        host->lua.settop(L, 2);
    }
    if (!dir || dir[0] == '\0') {
        dir = "/sd/mp3";
    }
    dir_len = strlen(dir);
    name_len = strlen(name);
    if (dir_len + 1u + name_len >= out_size) {
        return 0;
    }
    memcpy(out, dir, dir_len);
    if (dir_len > 0 && dir[dir_len - 1u] == '/') {
        memcpy(out + dir_len, name, name_len + 1u);
    } else {
        out[dir_len] = '/';
        memcpy(out + dir_len + 1u, name, name_len + 1u);
    }
    return 1;
}

static int audio_build_alt_mp3_dir_path(const char *path, char *out, size_t out_size)
{
    const char *prefix = "/sd/mp3/";
    size_t prefix_len = strlen(prefix);
    size_t path_len = 0;
    if (!path || !out || out_size == 0) {
        return 0;
    }
    path_len = strlen(path);
    if (path_len <= prefix_len || path_len >= out_size) {
        return 0;
    }
    if (memcmp(path, prefix, prefix_len) != 0) {
        return 0;
    }
    memcpy(out, "/sd/MP3/", prefix_len);
    memcpy(out + prefix_len, path + prefix_len, path_len - prefix_len + 1u);
    return 1;
}

static void audio_reset_i2s_pending(audio_instance_t *inst)
{
    if (!inst) {
        return;
    }
    inst->i2s_pending_pos = 0;
    inst->i2s_pending_len = 0;
}

static void audio_reset_pcm_ring(audio_instance_t *inst)
{
    if (!inst) {
        return;
    }
    inst->pcm_ring_read_pos = 0;
    inst->pcm_ring_write_pos = 0;
    inst->pcm_ring_len = 0;
    inst->pcm_ring_eof = 0;
    inst->pcm_ring_started = 0;
    inst->play_task_paused = 0;
    inst->play_task_buffering = 0;
    inst->producer_task_running = 0;
    inst->producer_task_eof = 0;
    inst->producer_task_error = 0;
}

static size_t audio_frame_bytes(const audio_instance_t *inst)
{
    size_t channels = 1;
    size_t bits = 16;
    if (inst) {
        channels = inst->output_channels ? inst->output_channels : 1u;
        bits = inst->bits_per_sample ? inst->bits_per_sample : 16u;
    }
    return channels * (bits / 8u);
}

static size_t audio_align_pcm_bytes(const audio_instance_t *inst, size_t bytes)
{
    size_t frame = audio_frame_bytes(inst);
    if (frame == 0) {
        frame = 2u;
    }
    return (bytes / frame) * frame;
}

static size_t audio_pcm_ring_used(const audio_instance_t *inst)
{
    size_t read_pos = 0;
    size_t write_pos = 0;
    if (!inst || inst->pcm_ring_cap == 0) {
        return 0;
    }
    read_pos = inst->pcm_ring_read_pos;
    write_pos = inst->pcm_ring_write_pos;
    if (write_pos >= read_pos) {
        return write_pos - read_pos;
    }
    return inst->pcm_ring_cap - read_pos + write_pos;
}

static size_t audio_pcm_ring_free(const audio_instance_t *inst)
{
    size_t used = audio_pcm_ring_used(inst);
    size_t frame = audio_frame_bytes(inst);
    if (!inst || inst->pcm_ring_cap <= used + frame) {
        return 0;
    }
    return audio_align_pcm_bytes(inst, inst->pcm_ring_cap - used - frame);
}

static int audio_pcm_ring_push(audio_instance_t *inst, const uint8_t *data, size_t len)
{
    size_t first = 0;
    size_t free_bytes = 0;
    if (!inst || !inst->pcm_ring_buf || !data || len == 0) {
        return 1;
    }
    len = audio_align_pcm_bytes(inst, len);
    free_bytes = audio_pcm_ring_free(inst);
    if (len == 0) {
        return 1;
    }
    if (len > free_bytes) {
        audio_set_error(inst, "audio: pcm ring overflow");
        return 0;
    }
    first = inst->pcm_ring_cap - inst->pcm_ring_write_pos;
    if (first > len) {
        first = len;
    }
    audio_copy_bytes(inst->pcm_ring_buf + inst->pcm_ring_write_pos, data, first);
    if (len > first) {
        audio_copy_bytes(inst->pcm_ring_buf, data + first, len - first);
    }
    inst->pcm_ring_write_pos = (inst->pcm_ring_write_pos + len) % inst->pcm_ring_cap;
    inst->pcm_ring_len = audio_pcm_ring_used(inst);
    return 1;
}

static size_t audio_pcm_ring_pop(audio_instance_t *inst, uint8_t *dst, size_t max_bytes)
{
    size_t len = 0;
    size_t first = 0;
    if (!inst || !inst->pcm_ring_buf || !dst || max_bytes == 0) {
        return 0;
    }
    len = audio_pcm_ring_used(inst);
    if (len > max_bytes) {
        len = max_bytes;
    }
    len = audio_align_pcm_bytes(inst, len);
    if (len == 0) {
        return 0;
    }
    first = inst->pcm_ring_cap - inst->pcm_ring_read_pos;
    if (first > len) {
        first = len;
    }
    audio_copy_bytes(dst, inst->pcm_ring_buf + inst->pcm_ring_read_pos, first);
    if (len > first) {
        audio_copy_bytes(dst + first, inst->pcm_ring_buf, len - first);
    }
    inst->pcm_ring_read_pos = (inst->pcm_ring_read_pos + len) % inst->pcm_ring_cap;
    inst->pcm_ring_len = audio_pcm_ring_used(inst);
    return len;
}

static void audio_i2s_stop_internal(audio_instance_t *inst)
{
    if (!inst || !inst->i2s_stream) {
        audio_play_task_stop_internal(inst, AUDIO_PLAY_TASK_STOP_WAIT_MS);
        return;
    }
    audio_play_task_stop_internal(inst, AUDIO_PLAY_TASK_STOP_WAIT_MS);
    if (inst->host.i2s.mute) {
        inst->host.i2s.mute(inst->i2s_stream);
    }
    if (inst->host.i2s.end) {
        inst->host.i2s.end(inst->i2s_stream);
    }
    inst->i2s_stream = NULL;
    audio_reset_i2s_pending(inst);
}

/* 释放模块持有的 decoder 和文件句柄。 */
static void audio_close_internal(audio_instance_t *inst)
{
    if (!inst) {
        return;
    }
    audio_i2s_stop_internal(inst);
    if (inst->decoder) {
        esp_audio_simple_dec_close(inst->decoder);
        inst->decoder = NULL;
    }
    if (inst->file && inst->host.file.close) {
        inst->host.file.close(inst->file);
        inst->file = NULL;
    }
    inst->opened = 0;
    inst->eof = 0;
    audio_reset_prefetch(inst);
    inst->info_ready = 0;
    inst->pending_len = 0;
    inst->pcm_pos = 0;
    inst->pcm_len = 0;
    inst->source_channels = 0;
    inst->bits_per_sample = 16;
    inst->bitrate = 0;
    inst->file_size = 0;
    inst->sample_rate = 0;
    inst->loudness_ready = 0;
    inst->loudness_segments = 0;
    inst->loudness_rms = 0;
    inst->loudness_peak = 0;
    inst->loudness_gain_q15 = 32768;
    inst->limiter_active_samples = 0;
    inst->limiter_total_samples = 0;
    inst->i2s_short_writes = 0;
    inst->play_task_stop = 0;
    inst->play_task_eof = 0;
    inst->play_task_error = 0;
    inst->play_task_paused = 0;
    inst->producer_task_eof = 0;
    inst->producer_task_error = 0;
    inst->play_task_written_bytes = 0;
    inst->play_task_iterations = 0;
    inst->producer_task_iterations = 0;
    inst->producer_task_decoded_bytes = 0;
    inst->play_task_buffer_events = 0;
    audio_reset_i2s_pending(inst);
    audio_reset_pcm_ring(inst);
    audio_reset_filter_state(inst);
}

/* 卸载默认 codec 注册表。 */
static void audio_unregister(audio_instance_t *inst)
{
    if (!inst || !inst->registered) {
        return;
    }
    esp_audio_simple_dec_unregister_default();
    esp_audio_dec_unregister_default();
    inst->registered = 0;
}

/* 扩大输出帧缓冲，避免 simple decoder 报 buffer not enough 后卡住。 */
static int audio_grow_out(audio_instance_t *inst, size_t needed)
{
    uint8_t *next = NULL;
    if (!inst || needed == 0 || needed > AUDIO_OUT_CAP) {
        return 0;
    }
    if (needed <= inst->out_cap) {
        return 1;
    }
    next = (uint8_t *)inst->host.heap.realloc(inst->out_buf, needed, MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    if (!next) {
        next = (uint8_t *)inst->host.heap.realloc(inst->out_buf, needed, MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT);
    }
    if (!next) {
        audio_set_error(inst, "audio: out buffer alloc failed");
        return 0;
    }
    inst->out_buf = next;
    inst->out_cap = needed;
    return 1;
}

/* 根据文件扩展名选择 simple decoder。 */
static esp_audio_simple_dec_type_t audio_type_from_path(const char *path, const char **out_name)
{
    const char *dot = NULL;
    const char *p = path;
    if (out_name) {
        *out_name = "unknown";
    }
    if (!path) {
        return ESP_AUDIO_SIMPLE_DEC_TYPE_NONE;
    }
    while (*p) {
        if (*p == '.') {
            dot = p;
        }
        ++p;
    }
    if (!dot || !dot[1]) {
        return ESP_AUDIO_SIMPLE_DEC_TYPE_NONE;
    }
    ++dot;
    if ((dot[0] == 'm' || dot[0] == 'M') &&
        (dot[1] == 'p' || dot[1] == 'P') &&
        dot[2] == '3' && dot[3] == '\0') {
        if (out_name) {
            *out_name = "mp3";
        }
        return ESP_AUDIO_SIMPLE_DEC_TYPE_MP3;
    }
    if ((dot[0] == 'w' || dot[0] == 'W') &&
        (dot[1] == 'a' || dot[1] == 'A') &&
        (dot[2] == 'v' || dot[2] == 'V') &&
        dot[3] == '\0') {
        if (out_name) {
            *out_name = "wav";
        }
        return ESP_AUDIO_SIMPLE_DEC_TYPE_WAV;
    }
    return ESP_AUDIO_SIMPLE_DEC_TYPE_NONE;
}

static uint32_t audio_mp3_synchsafe_size(const uint8_t *p)
{
    if (!p) {
        return 0;
    }
    return ((uint32_t)(p[0] & 0x7fu) << 21u) |
           ((uint32_t)(p[1] & 0x7fu) << 14u) |
           ((uint32_t)(p[2] & 0x7fu) << 7u) |
           (uint32_t)(p[3] & 0x7fu);
}

static uint32_t audio_mp3_bitrate_kbps(uint8_t version, uint8_t layer, uint8_t idx)
{
    static const uint16_t mpeg1_l1[16] = {0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448, 0};
    static const uint16_t mpeg1_l2[16] = {0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 0};
    static const uint16_t mpeg1_l3[16] = {0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0};
    static const uint16_t mpeg2_l1[16] = {0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256, 0};
    static const uint16_t mpeg2_l23[16] = {0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0};
    if (idx == 0 || idx == 15) {
        return 0;
    }
    if (version == 3u) {
        if (layer == 3u) {
            return mpeg1_l1[idx];
        }
        if (layer == 2u) {
            return mpeg1_l2[idx];
        }
        if (layer == 1u) {
            return mpeg1_l3[idx];
        }
    } else if (version == 2u || version == 0u) {
        if (layer == 3u) {
            return mpeg2_l1[idx];
        }
        if (layer == 2u || layer == 1u) {
            return mpeg2_l23[idx];
        }
    }
    return 0;
}

static int audio_parse_mp3_frame_header(const uint8_t *p,
                                        uint32_t *out_rate,
                                        uint8_t *out_channels,
                                        uint32_t *out_bitrate,
                                        uint32_t *out_frame_len,
                                        uint8_t *out_version,
                                        uint8_t *out_layer)
{
    static const uint16_t rate_mpeg1[4] = {44100, 48000, 32000, 0};
    static const uint16_t rate_mpeg2[4] = {22050, 24000, 16000, 0};
    static const uint16_t rate_mpeg25[4] = {11025, 12000, 8000, 0};
    uint8_t version = 0;
    uint8_t layer = 0;
    uint8_t bitrate_idx = 0;
    uint8_t rate_idx = 0;
    uint8_t padding = 0;
    uint8_t channel_mode = 0;
    uint32_t bitrate = 0;
    uint32_t rate = 0;
    uint32_t frame_len = 0;
    if (!p || p[0] != 0xffu || (p[1] & 0xe0u) != 0xe0u) {
        return 0;
    }
    version = (uint8_t)((p[1] >> 3u) & 0x03u);
    layer = (uint8_t)((p[1] >> 1u) & 0x03u);
    bitrate_idx = (uint8_t)((p[2] >> 4u) & 0x0fu);
    rate_idx = (uint8_t)((p[2] >> 2u) & 0x03u);
    padding = (uint8_t)((p[2] >> 1u) & 0x01u);
    channel_mode = (uint8_t)((p[3] >> 6u) & 0x03u);
    if (version == 1u || layer == 0u || rate_idx == 3u) {
        return 0;
    }
    bitrate = audio_mp3_bitrate_kbps(version, layer, bitrate_idx);
    if (bitrate == 0) {
        return 0;
    }
    if (version == 3u) {
        rate = rate_mpeg1[rate_idx];
    } else if (version == 2u) {
        rate = rate_mpeg2[rate_idx];
    } else {
        rate = rate_mpeg25[rate_idx];
    }
    if (rate == 0) {
        return 0;
    }
    if (layer == 3u) {
        frame_len = (((12u * bitrate * 1000u) / rate) + padding) * 4u;
    } else if (layer == 2u) {
        frame_len = ((144u * bitrate * 1000u) / rate) + padding;
    } else if (version == 3u) {
        frame_len = ((144u * bitrate * 1000u) / rate) + padding;
    } else {
        frame_len = ((72u * bitrate * 1000u) / rate) + padding;
    }
    if (frame_len < 24u) {
        return 0;
    }
    if (out_rate) {
        *out_rate = rate;
    }
    if (out_channels) {
        *out_channels = (channel_mode == 3u) ? 1u : 2u;
    }
    if (out_bitrate) {
        *out_bitrate = bitrate * 1000u;
    }
    if (out_frame_len) {
        *out_frame_len = frame_len;
    }
    if (out_version) {
        *out_version = version;
    }
    if (out_layer) {
        *out_layer = layer;
    }
    return 1;
}

static int audio_probe_mp3_info_from_buffer(audio_instance_t *inst, const uint8_t *buf, size_t len)
{
    size_t start = 0;
    size_t i = 0;
    if (!inst || !buf || len < 4u) {
        return 0;
    }
    if (len >= 10u && buf[0] == 'I' && buf[1] == 'D' && buf[2] == '3') {
        start = 10u + (size_t)audio_mp3_synchsafe_size(buf + 6u);
        if ((buf[5] & 0x10u) != 0u) {
            start += 10u;
        }
        if (start + 4u > len) {
            return 0;
        }
    }
    for (i = start; i + 4u <= len; ++i) {
        uint32_t rate = 0;
        uint32_t bitrate = 0;
        uint32_t frame_len = 0;
        uint8_t channels = 0;
        uint8_t version = 0;
        uint8_t layer = 0;
        if (!audio_parse_mp3_frame_header(buf + i, &rate, &channels, &bitrate, &frame_len, &version, &layer)) {
            continue;
        }
        if (i + frame_len + 4u <= len) {
            uint32_t next_rate = 0;
            uint32_t next_frame_len = 0;
            uint8_t next_version = 0;
            uint8_t next_layer = 0;
            if (!audio_parse_mp3_frame_header(buf + i + frame_len,
                                              &next_rate,
                                              NULL,
                                              NULL,
                                              &next_frame_len,
                                              &next_version,
                                              &next_layer) ||
                next_rate != rate || next_version != version || next_layer != layer) {
                continue;
            }
        }
        inst->sample_rate = rate;
        inst->source_channels = channels;
        inst->bitrate = bitrate;
        audio_rebuild_filters(inst);
        return 1;
    }
    return 0;
}

static int audio_probe_mp3_info(audio_instance_t *inst)
{
    uint8_t *scratch = NULL;
    size_t cap = 0;
    size_t got = 0;
    uint64_t saved_pos = 0;
    int have_saved_pos = 0;
    int found = 0;
    if (!inst || !inst->file || !inst->host.file.read || !inst->host.file.seek) {
        return 0;
    }
    scratch = inst->prefetch_buf ? inst->prefetch_buf : inst->in_buf;
    cap = inst->prefetch_buf ? inst->prefetch_cap : inst->in_cap;
    if (!scratch || cap < 512u) {
        return 0;
    }
    if (cap > AUDIO_MP3_PROBE_BYTES) {
        cap = AUDIO_MP3_PROBE_BYTES;
    }
    if (inst->host.file.position &&
        inst->host.file.position(inst->file, &saved_pos) == MODULE_OK) {
        have_saved_pos = 1;
    }
    if (inst->host.file.seek(inst->file, 0, MODULE_SEEK_SET) != MODULE_OK) {
        return 0;
    }
    if (inst->host.file.read(inst->file, scratch, cap, &got) == MODULE_OK && got > 0u) {
        found = audio_probe_mp3_info_from_buffer(inst, scratch, got);
        if (!found && got >= 10u && scratch[0] == 'I' && scratch[1] == 'D' && scratch[2] == '3') {
            uint32_t id3_total = 10u + audio_mp3_synchsafe_size(scratch + 6u);
            if ((scratch[5] & 0x10u) != 0u) {
                id3_total += 10u;
            }
            if ((inst->file_size == 0 || (uint64_t)id3_total < inst->file_size) &&
                id3_total > got &&
                inst->host.file.seek(inst->file, id3_total, MODULE_SEEK_SET) == MODULE_OK &&
                inst->host.file.read(inst->file, scratch, cap, &got) == MODULE_OK &&
                got > 0u) {
                found = audio_probe_mp3_info_from_buffer(inst, scratch, got);
            }
        }
    }
    if (have_saved_pos) {
        inst->host.file.seek(inst->file, (int64_t)saved_pos, MODULE_SEEK_SET);
    } else {
        inst->host.file.seek(inst->file, 0, MODULE_SEEK_SET);
    }
    return found;
}

/* 打开 simple decoder；分析和正式播放共用同一套配置。 */
static int audio_open_decoder(audio_instance_t *inst, esp_audio_simple_dec_type_t dec_type)
{
    esp_audio_simple_dec_cfg_t cfg;
    esp_audio_err_t ret = ESP_AUDIO_ERR_OK;
    if (!inst) {
        return 0;
    }
    if (inst->decoder) {
        esp_audio_simple_dec_close(inst->decoder);
        inst->decoder = NULL;
    }
    cfg.dec_type = dec_type;
    cfg.dec_cfg = NULL;
    cfg.cfg_size = 0;
    cfg.use_frame_dec = false;
    ret = esp_audio_simple_dec_open(&cfg, &inst->decoder);
    if (ret != ESP_AUDIO_ERR_OK || !inst->decoder) {
        audio_set_error(inst, "audio: decoder open failed");
        return 0;
    }
    return 1;
}

/* 重置压缩流和 PCM 缓存状态；seek 分析和重新播放前都会用到。 */
static void audio_reset_stream_state(audio_instance_t *inst)
{
    if (!inst) {
        return;
    }
    inst->eof = 0;
    audio_reset_prefetch(inst);
    inst->info_ready = 0;
    inst->pending_len = 0;
    inst->pcm_pos = 0;
    inst->pcm_len = 0;
    inst->source_channels = 0;
    inst->bits_per_sample = 16;
    inst->bitrate = 0;
    inst->file_size = 0;
    inst->sample_rate = 0;
}

/* 读取更多压缩数据到 pending buffer 尾部。 */
static int audio_fill_input(audio_instance_t *inst)
{
    size_t got = 0;
    size_t want = 0;
    int32_t err = MODULE_OK;
    if (!inst || inst->eof || !inst->file || inst->pending_len >= inst->in_cap) {
        return 1;
    }
    want = inst->in_cap - inst->pending_len;
    if (inst->prefetch_buf && inst->prefetch_cap > 0) {
        if (inst->prefetch_len == 0 && !inst->prefetch_eof) {
            if (!audio_prefetch_fill(inst, AUDIO_PREFETCH_READ_CHUNK, AUDIO_PREFETCH_READ_CHUNK)) {
                return 0;
            }
        }
        got = audio_prefetch_take(inst, inst->in_buf + inst->pending_len, want);
        if (got > 0) {
            inst->pending_len += got;
            return 1;
        }
        if (inst->prefetch_eof) {
            inst->eof = 1;
            return 1;
        }
    }
    err = inst->host.file.read(inst->file, inst->in_buf + inst->pending_len, want, &got);
    if (err != MODULE_OK) {
        audio_set_error(inst, "audio: file read failed");
        return 0;
    }
    if (got == 0) {
        inst->eof = 1;
        return 1;
    }
    inst->pending_len += got;
    return 1;
}

/* 丢弃 decoder 已消费的输入字节。 */
static void audio_consume_input(audio_instance_t *inst, size_t consumed)
{
    size_t i = 0;
    if (!inst || consumed == 0) {
        return;
    }
    if (consumed >= inst->pending_len) {
        inst->pending_len = 0;
        return;
    }
    for (i = 0; i < inst->pending_len - consumed; ++i) {
        inst->in_buf[i] = inst->in_buf[i + consumed];
    }
    inst->pending_len -= consumed;
}

/* 判断虚拟低音滤波链路是否可用。 */
static int audio_vbass_active(const audio_instance_t *inst)
{
    return inst && inst->vbass_enabled && inst->vbass_buf && inst->vbass_cap > 0 &&
           inst->vbass_mix > 0.0001f &&
           inst->vbass_low_hpf_filter.enabled &&
           inst->vbass_low_lpf_filter.enabled &&
           inst->vbass_out_hpf_filter.enabled &&
           inst->vbass_out_lpf_filter.enabled;
}

/* 判断是否需要走 esp-dsp 后处理。 */
static int audio_dsp_active(const audio_instance_t *inst)
{
    return inst && inst->output_channels == 1 &&
           (inst->hpf.enabled || inst->eq_active > 0 || audio_vbass_active(inst));
}

/* 对一段 mono s16le PCM 运行 esp-dsp EQ/HPF，并合并音量/限幅。 */
static void audio_apply_dsp_mono(audio_instance_t *inst, int16_t *s16, size_t frames)
{
    size_t pos = 0;
    size_t i = 0;
    size_t band = 0;
    float vol = 1.0f;
    float limit = 1.0f;
    int vbass_on = 0;
    if (!inst || !s16 || !inst->dsp_buf || inst->dsp_cap == 0) {
        return;
    }
    vbass_on = audio_vbass_active(inst);
    vol = (float)audio_combined_gain_q15(inst) / 32768.0f;
    if (inst->limiter_enabled && inst->limiter_threshold > 0) {
        limit = (float)inst->limiter_threshold / 32768.0f;
    }
    while (pos < frames) {
        size_t n = frames - pos;
        uint32_t limited = 0;
        if (n > inst->dsp_cap) {
            n = inst->dsp_cap;
        }
        if (vbass_on && n > inst->vbass_cap) {
            n = inst->vbass_cap;
        }
        for (i = 0; i < n; ++i) {
            float v = (float)s16[pos + i] * (1.0f / 32768.0f);
            inst->dsp_buf[i] = v;
            if (vbass_on) {
                inst->vbass_buf[i] = v;
            }
        }
        if (vbass_on) {
            AUDIO_DSPS_BIQUAD_F32(inst->vbass_buf, inst->vbass_buf, (int)n,
                                  inst->vbass_low_hpf_filter.coeff, inst->vbass_low_hpf_filter.w);
            AUDIO_DSPS_BIQUAD_F32(inst->vbass_buf, inst->vbass_buf, (int)n,
                                  inst->vbass_low_lpf_filter.coeff, inst->vbass_low_lpf_filter.w);
            for (i = 0; i < n; ++i) {
                float low = audio_clipf(inst->vbass_buf[i] * inst->vbass_drive, -1.0f, 1.0f);
                float even = fabsf(low) * inst->vbass_even;
                float odd = low * low * low * 4.0f * inst->vbass_odd;
                inst->vbass_buf[i] = even + odd;
            }
            AUDIO_DSPS_BIQUAD_F32(inst->vbass_buf, inst->vbass_buf, (int)n,
                                  inst->vbass_out_hpf_filter.coeff, inst->vbass_out_hpf_filter.w);
            AUDIO_DSPS_BIQUAD_F32(inst->vbass_buf, inst->vbass_buf, (int)n,
                                  inst->vbass_out_lpf_filter.coeff, inst->vbass_out_lpf_filter.w);
        }
        if (inst->hpf.enabled) {
            AUDIO_DSPS_BIQUAD_F32(inst->dsp_buf, inst->dsp_buf, (int)n, inst->hpf.coeff, inst->hpf.w);
        }
        for (band = 0; band < AUDIO_EQ_MAX_BANDS; ++band) {
            if (inst->eq[band].enabled) {
                AUDIO_DSPS_BIQUAD_F32(inst->dsp_buf, inst->dsp_buf, (int)n, inst->eq[band].coeff, inst->eq[band].w);
            }
        }
        for (i = 0; i < n; ++i) {
            float v = inst->dsp_buf[i] * vol;
            float clipped = 0.0f;
            int32_t out = 0;
            if (vbass_on) {
                v += inst->vbass_buf[i] * inst->vbass_mix * vol;
            }
            clipped = audio_clipf(v, -limit, limit);
            if (inst->limiter_enabled && clipped != v) {
                limited++;
            }
            v = clipped;
            if (v >= 0.0f) {
                out = (int32_t)(v * 32767.0f + 0.5f);
            } else {
                out = (int32_t)(v * 32768.0f - 0.5f);
            }
            if (out > 32767) {
                out = 32767;
            } else if (out < -32768) {
                out = -32768;
            }
            s16[pos + i] = (int16_t)out;
        }
        audio_note_limiter(inst, limited, (uint32_t)n);
        pos += n;
    }
}

/* 对 PCM 做后处理：默认 stereo -> mono，再按需应用 esp-dsp EQ、音量和限幅。 */
static void audio_postprocess_pcm(audio_instance_t *inst, uint8_t *buf, size_t *bytes)
{
    size_t frames = 0;
    size_t i = 0;
    int16_t *s16 = (int16_t *)buf;
    int32_t vol = 32768;
    int32_t limit = 32767;
    if (!inst || !buf || !bytes || *bytes == 0 || inst->bits_per_sample != 16) {
        return;
    }
    vol = audio_combined_gain_q15(inst);
    if (inst->limiter_enabled && inst->limiter_threshold > 0) {
        limit = inst->limiter_threshold;
    }
    if (inst->source_channels == 2 && inst->output_channels == 1) {
        frames = *bytes / 4u;
        for (i = 0; i < frames; ++i) {
            int32_t mixed = ((int32_t)s16[i * 2u] + (int32_t)s16[i * 2u + 1u]) / 2;
            s16[i] = (int16_t)mixed;
        }
        *bytes = frames * 2u;
    } else {
        frames = *bytes / 2u;
    }

    if (audio_dsp_active(inst)) {
        audio_apply_dsp_mono(inst, s16, frames);
        return;
    }

    if (vol != 32768 || inst->limiter_enabled) {
        uint32_t limited = 0;
        for (i = 0; i < frames; ++i) {
            int64_t scaled = ((int64_t)s16[i] * (int64_t)vol) >> 15;
            int32_t v = (int32_t)scaled;
            if (v > limit) {
                v = limit;
                limited++;
            } else if (v < -limit) {
                v = -limit;
                limited++;
            }
            s16[i] = (int16_t)v;
        }
        audio_note_limiter(inst, limited, (uint32_t)frames);
    }
}

/* 解一帧 PCM 到 out_buf；postprocess 为 0 时只给 RMS 分析用。 */
static int audio_decode_next(audio_instance_t *inst, size_t *out_bytes, int postprocess)
{
    esp_audio_err_t ret = ESP_AUDIO_ERR_OK;
    esp_audio_simple_dec_raw_t raw;
    esp_audio_simple_dec_out_t out;
    if (!inst || !out_bytes) {
        return 0;
    }
    *out_bytes = 0;
    while (1) {
        if (inst->pending_len == 0 && !inst->eof) {
            if (!audio_fill_input(inst)) {
                return -1;
            }
        }
        if (inst->pending_len == 0 && inst->eof) {
            return 0;
        }

        raw.buffer = inst->in_buf;
        raw.len = (uint32_t)inst->pending_len;
        raw.eos = inst->eof ? true : false;
        raw.consumed = 0;
        raw.frame_recover = ESP_AUDIO_SIMPLE_DEC_RECOVERY_NONE;
        out.buffer = inst->out_buf;
        out.len = (uint32_t)inst->out_cap;
        out.needed_size = 0;
        out.decoded_size = 0;

        ret = esp_audio_simple_dec_process(inst->decoder, &raw, &out);
        if (ret == ESP_AUDIO_ERR_BUFF_NOT_ENOUGH) {
            if (!audio_grow_out(inst, out.needed_size)) {
                return -1;
            }
            continue;
        }
        if (raw.consumed > 0) {
            audio_consume_input(inst, raw.consumed);
        }
        if (ret == ESP_AUDIO_ERR_DATA_LACK || ret == ESP_AUDIO_ERR_CONTINUE) {
            if (!inst->eof && audio_fill_input(inst)) {
                continue;
            }
        }
        if (ret != ESP_AUDIO_ERR_OK) {
            audio_set_error(inst, "audio: decode failed");
            return -1;
        }
        if (out.decoded_size > 0) {
            if (!inst->info_ready) {
                esp_audio_simple_dec_info_t info = {0};
                if (esp_audio_simple_dec_get_info(inst->decoder, &info) == ESP_AUDIO_ERR_OK) {
                    inst->sample_rate = info.sample_rate;
                    inst->source_channels = info.channel;
                    inst->bits_per_sample = info.bits_per_sample;
                    inst->bitrate = info.bitrate;
                    inst->info_ready = 1;
                    audio_rebuild_filters(inst);
                }
            }
            if (inst->source_channels == 0) {
                inst->source_channels = 2;
            }
            *out_bytes = out.decoded_size;
            if (postprocess) {
                audio_postprocess_pcm(inst, inst->out_buf, out_bytes);
            }
            return 1;
        }
        if (inst->pending_len < inst->in_cap && !inst->eof) {
            if (!audio_fill_input(inst)) {
                return -1;
            }
            continue;
        }
        if (inst->eof) {
            return 0;
        }
    }
}

/* 把原始 PCM 转成 mono 统计 RMS/peak；不改变 out_buf 内容。 */
static void audio_measure_pcm(audio_instance_t *inst,
                              const uint8_t *buf,
                              size_t bytes,
                              uint64_t *sum_sq,
                              uint32_t *peak,
                              uint32_t *count)
{
    const int16_t *s16 = (const int16_t *)buf;
    size_t frames = 0;
    size_t i = 0;
    if (!inst || !buf || !sum_sq || !peak || !count || bytes == 0 || inst->bits_per_sample != 16) {
        return;
    }
    if (inst->source_channels == 2) {
        frames = bytes / 4u;
        for (i = 0; i < frames; ++i) {
            int32_t v = ((int32_t)s16[i * 2u] + (int32_t)s16[i * 2u + 1u]) / 2;
            uint32_t a = (v < 0) ? (uint32_t)(-v) : (uint32_t)v;
            *sum_sq += (uint64_t)((int64_t)v * (int64_t)v);
            if (a > *peak) {
                *peak = a;
            }
            *count += 1u;
        }
    } else {
        frames = bytes / 2u;
        for (i = 0; i < frames; ++i) {
            int32_t v = (int32_t)s16[i];
            uint32_t a = (v < 0) ? (uint32_t)(-v) : (uint32_t)v;
            *sum_sq += (uint64_t)((int64_t)v * (int64_t)v);
            if (a > *peak) {
                *peak = a;
            }
            *count += 1u;
        }
    }
}

/* 小数组排序，取 70% 分位 RMS 作为整首歌代表响度。 */
static uint32_t audio_select_loudness_rms(uint32_t *values, uint8_t n)
{
    uint8_t i = 0;
    if (!values || n == 0) {
        return 0;
    }
    for (i = 1; i < n; ++i) {
        uint32_t v = values[i];
        int j = (int)i - 1;
        while (j >= 0 && values[j] > v) {
            values[j + 1] = values[j];
            --j;
        }
        values[j + 1] = v;
    }
    return values[((uint32_t)(n - 1u) * 7u) / 10u];
}

/* 播放前抽 6 段 PCM 统计 RMS，只生成固定 track_gain，不做实时动态修正。 */
static void audio_analyze_loudness(audio_instance_t *inst, esp_audio_simple_dec_type_t dec_type, uint64_t file_size)
{
    static const uint8_t pos_percent[AUDIO_LOUDNESS_SEGMENTS] = {8, 22, 36, 50, 68, 86};
    uint32_t rms_values[AUDIO_LOUDNESS_SEGMENTS];
    uint32_t peak_max = 0;
    uint8_t ok_segments = 0;
    uint8_t seg = 0;
    if (!inst || !inst->loudness_enabled || !inst->file || !inst->host.file.seek || file_size < 8192u) {
        return;
    }
    for (seg = 0; seg < AUDIO_LOUDNESS_SEGMENTS; ++seg) {
        uint64_t offset = (file_size * (uint64_t)pos_percent[seg]) / 100u;
        uint64_t sum_sq = 0;
        uint32_t peak = 0;
        uint32_t count = 0;
        uint32_t guard = 0;
        if (offset > 4096u) {
            offset -= 2048u;
        }
        if (offset >= file_size) {
            continue;
        }
        if (inst->host.file.seek(inst->file, (int64_t)offset, MODULE_SEEK_SET) != MODULE_OK) {
            continue;
        }
        audio_reset_stream_state(inst);
        if (!audio_open_decoder(inst, dec_type)) {
            continue;
        }
        while (count < AUDIO_LOUDNESS_SEGMENT_FRAMES && guard < 96u) {
            size_t out_bytes = 0;
            int decoded = audio_decode_next(inst, &out_bytes, 0);
            ++guard;
            if (decoded < 0 || decoded == 0) {
                break;
            }
            audio_measure_pcm(inst, inst->out_buf, out_bytes, &sum_sq, &peak, &count);
        }
        if (inst->decoder) {
            esp_audio_simple_dec_close(inst->decoder);
            inst->decoder = NULL;
        }
        if (count >= 2048u && sum_sq > 0) {
            uint32_t rms = audio_isqrt_u64(sum_sq / (uint64_t)count);
            rms_values[ok_segments++] = rms;
            if (peak > peak_max) {
                peak_max = peak;
            }
        }
    }
    audio_reset_stream_state(inst);
    inst->last_error[0] = '\0';
    if (ok_segments > 0) {
        inst->loudness_rms = audio_select_loudness_rms(rms_values, ok_segments);
        inst->loudness_peak = peak_max;
        inst->loudness_segments = ok_segments;
        inst->loudness_ready = 1;
        audio_recompute_loudness_gain(inst);
    }
}

/* audio.version()。 */
static int l_audio_version(lua_State *L)
{
    audio_instance_t *inst = instance_from_lua(L);
    const module_host_api_v1 *host = inst ? &inst->host : s_host;
    host->lua.pushstring(L, AUDIO_VERSION);
    return 1;
}

/* audio.set_effects(tbl)：解析 volume/HPF/7 段 EQ/limiter。 */
static int l_audio_set_effects(lua_State *L)
{
    static const char *freq_keys[AUDIO_EQ_MAX_BANDS] = {
        "eq1_freq", "eq2_freq", "eq3_freq", "eq4_freq", "eq5_freq", "eq6_freq", "eq7_freq",
    };
    static const char *gain_keys[AUDIO_EQ_MAX_BANDS] = {
        "eq1_gain", "eq2_gain", "eq3_gain", "eq4_gain", "eq5_gain", "eq6_gain", "eq7_gain",
    };
    static const char *q_keys[AUDIO_EQ_MAX_BANDS] = {
        "eq1_q", "eq2_q", "eq3_q", "eq4_q", "eq5_q", "eq6_q", "eq7_q",
    };
    audio_instance_t *inst = instance_from_lua(L);
    const module_host_api_v1 *host = inst ? &inst->host : s_host;
    int32_t volume_q = 1000;
    int32_t limiter_db_q = -500;
    int32_t limiter_peak_q = 0;
    int32_t target_rms_q = 5000000;
    int32_t min_gain_q = 450;
    int32_t max_gain_q = 2500;
    int32_t vbass_mix_q = 160;
    int32_t vbass_drive_q = 3000;
    int32_t vbass_even_q = 1200;
    int32_t vbass_odd_q = 800;
    int32_t qv = 0;
    size_t i = 0;
    if (!inst || !host) {
        return push_error(L, host, "audio: missing instance");
    }
    if (host->lua.istable(L, 1)) {
        volume_q = audio_lua_q1000_field(host, L, 1, "volume", 1000);
        if (volume_q < 0) {
            volume_q = 0;
        } else if (volume_q > 2000) {
            volume_q = 2000;
        }
        inst->volume_q15 = (int32_t)(((int64_t)volume_q * 32768) / 1000);

        inst->loudness_enabled = audio_lua_bool_field(host, L, 1, "loudness", inst->loudness_enabled);
        target_rms_q = audio_lua_q1000_field(host, L, 1, "loudness_target_rms",
                                             (int32_t)inst->loudness_target_rms * 1000);
        if (target_rms_q < 512000) {
            target_rms_q = 512000;
        } else if (target_rms_q > 12000000) {
            target_rms_q = 12000000;
        }
        inst->loudness_target_rms = (uint32_t)(target_rms_q / 1000);
        min_gain_q = audio_lua_q1000_field(host, L, 1, "loudness_min_gain", 450);
        max_gain_q = audio_lua_q1000_field(host, L, 1, "loudness_max_gain", 2500);
        if (min_gain_q < 100) {
            min_gain_q = 100;
        } else if (min_gain_q > 1000) {
            min_gain_q = 1000;
        }
        if (max_gain_q < 1000) {
            max_gain_q = 1000;
        } else if (max_gain_q > 4000) {
            max_gain_q = 4000;
        }
        if (max_gain_q < min_gain_q) {
            max_gain_q = min_gain_q;
        }
        inst->loudness_min_gain_q15 = (int32_t)(((int64_t)min_gain_q * 32768) / 1000);
        inst->loudness_max_gain_q15 = (int32_t)(((int64_t)max_gain_q * 32768) / 1000);
        audio_recompute_loudness_gain(inst);

        inst->hpf_enabled = audio_lua_bool_field(host, L, 1, "hpf", inst->hpf_enabled);
        inst->hpf_freq = audio_q1000_to_float(audio_lua_q1000_field(host, L, 1, "hpf_freq", 150000));
        inst->hpf_q = audio_q1000_to_float(audio_lua_q1000_field(host, L, 1, "hpf_q", 707));

        inst->eq_enabled = audio_lua_bool_field(host, L, 1, "eq", inst->eq_enabled);
        for (i = 0; i < AUDIO_EQ_MAX_BANDS; ++i) {
            static const int32_t default_freq_q[AUDIO_EQ_MAX_BANDS] = {160000, 250000, 420000, 780000, 1250000, 2800000, 4300000};
            static const int32_t default_gain_q[AUDIO_EQ_MAX_BANDS] = {2500, 5000, 2800, 0, -3800, -2500, 500};
            qv = audio_lua_q1000_field(host, L, 1, freq_keys[i], default_freq_q[i]);
            inst->eq_freq[i] = audio_q1000_to_float(qv);
            qv = audio_lua_q1000_field(host, L, 1, gain_keys[i], default_gain_q[i]);
            inst->eq_gain[i] = audio_q1000_to_float(qv);
            qv = audio_lua_q1000_field(host, L, 1, q_keys[i], 800);
            inst->eq_q[i] = audio_q1000_to_float(qv);
        }

        inst->vbass_enabled = audio_lua_bool_field(host, L, 1, "vbass", inst->vbass_enabled);
        inst->vbass_low_hpf = audio_q1000_to_float(audio_lua_q1000_field(host, L, 1, "vbass_low_hpf", 50000));
        inst->vbass_low_lpf = audio_q1000_to_float(audio_lua_q1000_field(host, L, 1, "vbass_low_lpf", 180000));
        inst->vbass_out_hpf = audio_q1000_to_float(audio_lua_q1000_field(host, L, 1, "vbass_out_hpf", 180000));
        inst->vbass_out_lpf = audio_q1000_to_float(audio_lua_q1000_field(host, L, 1, "vbass_out_lpf", 650000));
        inst->vbass_low_hpf = audio_clampf(inst->vbass_low_hpf, 40.0f, 220.0f);
        inst->vbass_low_lpf = audio_clampf(inst->vbass_low_lpf, inst->vbass_low_hpf + 20.0f, 260.0f);
        inst->vbass_out_hpf = audio_clampf(inst->vbass_out_hpf, 120.0f, 420.0f);
        inst->vbass_out_lpf = audio_clampf(inst->vbass_out_lpf, inst->vbass_out_hpf + 80.0f, 900.0f);
        vbass_drive_q = audio_lua_q1000_field(host, L, 1, "vbass_drive", 3000);
        vbass_mix_q = audio_lua_q1000_field(host, L, 1, "vbass_mix", 160);
        vbass_even_q = audio_lua_q1000_field(host, L, 1, "vbass_even", 1200);
        vbass_odd_q = audio_lua_q1000_field(host, L, 1, "vbass_odd", 800);
        inst->vbass_drive = audio_clampf(audio_q1000_to_float(vbass_drive_q), 0.1f, 4.0f);
        inst->vbass_mix = audio_clampf(audio_q1000_to_float(vbass_mix_q), 0.0f, 0.25f);
        inst->vbass_even = audio_clampf(audio_q1000_to_float(vbass_even_q), 0.0f, 2.0f);
        inst->vbass_odd = audio_clampf(audio_q1000_to_float(vbass_odd_q), 0.0f, 2.0f);

        inst->limiter_enabled = audio_lua_bool_field(host, L, 1, "limiter", inst->limiter_enabled);
        limiter_peak_q = audio_lua_q1000_field(host, L, 1, "limiter_peak", 0);
        if (limiter_peak_q > 0) {
            inst->limiter_threshold = limiter_peak_q / 1000;
        } else {
            limiter_db_q = audio_lua_q1000_field(host, L, 1, "limiter_dbfs", -500);
            limiter_db_q = audio_lua_q1000_field(host, L, 1, "limiter_db", limiter_db_q);
            if (limiter_db_q > 0) {
                limiter_db_q = 0;
            } else if (limiter_db_q < -24000) {
                limiter_db_q = -24000;
            }
            inst->limiter_threshold = AUDIO_LIMITER_DEFAULT_PEAK;
        }
        if (inst->limiter_threshold < 1024) {
            inst->limiter_threshold = 1024;
        } else if (inst->limiter_threshold > 32767) {
            inst->limiter_threshold = 32767;
        }
        if (inst->loudness_enabled && inst->limiter_threshold < AUDIO_LIMITER_DEFAULT_PEAK) {
            inst->limiter_threshold = AUDIO_LIMITER_DEFAULT_PEAK;
        }

        audio_rebuild_filters(inst);
    }
    host->lua.pushboolean(L, 1);
    return 1;
}

/* audio.open(path[, opts])。 */
static int l_audio_open(lua_State *L)
{
    audio_instance_t *inst = instance_from_lua(L);
    const module_host_api_v1 *host = inst ? &inst->host : s_host;
    const char *path = NULL;
    const char *type_name = "unknown";
    char path_buf[256];
    esp_audio_simple_dec_type_t dec_type = ESP_AUDIO_SIMPLE_DEC_TYPE_NONE;
    esp_audio_err_t ret = ESP_AUDIO_ERR_OK;
    int32_t err = MODULE_OK;
    uint64_t file_size = 0;
    if (!inst || !host) {
        return push_error(L, host, "audio: missing instance");
    }
    if (!audio_build_open_path(inst, L, path_buf, sizeof(path_buf))) {
        return push_error(L, host, "audio: invalid path");
    }
    path = path_buf;
    dec_type = audio_type_from_path(path, &type_name);
    if (dec_type == ESP_AUDIO_SIMPLE_DEC_TYPE_NONE) {
        return push_error(L, host, "audio: unsupported file type");
    }

    audio_close_internal(inst);
    inst->output_channels = 1;
    if (host->lua.istable(L, 2)) {
        host->lua.getfield(L, 2, "output_channels");
        if (host->lua.isnumber(L, -1)) {
            int64_t ch = host->lua.tointeger(L, -1);
            inst->output_channels = (ch == 2) ? 2 : 1;
        }
        host->lua.settop(L, 2);
    }

    if (!inst->registered) {
        ret = esp_audio_dec_register_default();
        if (ret != ESP_AUDIO_ERR_OK && ret != ESP_AUDIO_ERR_ALREADY_EXIST) {
            return push_error(L, host, "audio: register decoder failed");
        }
        ret = esp_audio_simple_dec_register_default();
        if (ret != ESP_AUDIO_ERR_OK && ret != ESP_AUDIO_ERR_ALREADY_EXIST) {
            esp_audio_dec_unregister_default();
            return push_error(L, host, "audio: register parser failed");
        }
        inst->registered = 1;
    }

    if (inst->loudness_enabled && host->file.seek && host->file.size_bytes) {
        err = host->sd.open(path, MODULE_FILE_READ, &inst->file);
        if ((err != MODULE_OK || !inst->file) && audio_build_alt_mp3_dir_path(path, path_buf, sizeof(path_buf))) {
            path = path_buf;
            err = host->sd.open(path, MODULE_FILE_READ, &inst->file);
        }
        if (err == MODULE_OK && inst->file) {
            if (host->file.size_bytes(inst->file, &file_size) == MODULE_OK) {
                audio_analyze_loudness(inst, dec_type, file_size);
            }
            if (inst->file) {
                host->file.close(inst->file);
                inst->file = NULL;
            }
        }
        audio_reset_stream_state(inst);
    }

    err = host->sd.open(path, MODULE_FILE_READ, &inst->file);
    if ((err != MODULE_OK || !inst->file) && audio_build_alt_mp3_dir_path(path, path_buf, sizeof(path_buf))) {
        path = path_buf;
        err = host->sd.open(path, MODULE_FILE_READ, &inst->file);
    }
    if (err != MODULE_OK || !inst->file) {
        audio_set_error(inst, "audio: file open failed");
        return push_error(L, host, inst->last_error);
    }
    if (host->file.size_bytes) {
        if (host->file.size_bytes(inst->file, &file_size) == MODULE_OK) {
            inst->file_size = file_size;
        }
    }
    if (dec_type == ESP_AUDIO_SIMPLE_DEC_TYPE_MP3) {
        audio_probe_mp3_info(inst);
    }

    if (!audio_open_decoder(inst, dec_type)) {
        audio_close_internal(inst);
        return push_error(L, host, "audio: decoder open failed");
    }

    inst->opened = 1;
    inst->bits_per_sample = 16;
    inst->type_name[0] = type_name[0];
    inst->type_name[1] = type_name[1];
    inst->type_name[2] = type_name[2];
    inst->type_name[3] = '\0';
    host->lua.pushboolean(L, 1);
    return 1;
}

/* audio.info()。 */
static int l_audio_info(lua_State *L)
{
    audio_instance_t *inst = instance_from_lua(L);
    const module_host_api_v1 *host = inst ? &inst->host : s_host;
    if (!inst || !host || !inst->opened) {
        return push_error(L, host, "audio: not open");
    }
    host->lua.newtable(L);
    host->lua.pushstring(L, inst->type_name);
    host->lua.setfield(L, -2, "type");
    host->lua.pushinteger(L, inst->sample_rate ? inst->sample_rate : 44100);
    host->lua.setfield(L, -2, "sample_rate");
    host->lua.pushinteger(L, inst->output_channels ? inst->output_channels : 1);
    host->lua.setfield(L, -2, "channels");
    host->lua.pushinteger(L, inst->bits_per_sample ? inst->bits_per_sample : 16);
    host->lua.setfield(L, -2, "bits_per_sample");
    host->lua.pushinteger(L, inst->source_channels ? inst->source_channels : 0);
    host->lua.setfield(L, -2, "source_channels");
    host->lua.pushinteger(L, inst->bitrate);
    host->lua.setfield(L, -2, "bitrate");
    host->lua.pushinteger(L, (int64_t)inst->file_size);
    host->lua.setfield(L, -2, "file_size");
    if (inst->bitrate > 0 && inst->file_size > 0) {
        host->lua.pushinteger(L, (int64_t)((inst->file_size * 8000u) / inst->bitrate));
    } else {
        host->lua.pushinteger(L, 0);
    }
    host->lua.setfield(L, -2, "duration_ms");
    return 1;
}

/* audio.prefetch([target_bytes[, max_bytes]]) -> cached, capacity, eof。 */
static int l_audio_prefetch(lua_State *L)
{
    audio_instance_t *inst = instance_from_lua(L);
    const module_host_api_v1 *host = inst ? &inst->host : s_host;
    size_t target = AUDIO_PREFETCH_CAP;
    size_t max_bytes = AUDIO_PREFETCH_READ_CHUNK;
    if (!inst || !host || !inst->opened) {
        return push_error(L, host, "audio: not open");
    }
    if (host->lua.isnumber(L, 1)) {
        int64_t v = host->lua.tointeger(L, 1);
        if (v > 0) {
            target = (size_t)v;
        }
    }
    if (host->lua.isnumber(L, 2)) {
        int64_t v = host->lua.tointeger(L, 2);
        if (v > 0) {
            max_bytes = (size_t)v;
        }
    }
    if (target > inst->prefetch_cap) {
        target = inst->prefetch_cap;
    }
    if (max_bytes > inst->prefetch_cap) {
        max_bytes = inst->prefetch_cap;
    }
    if (!audio_prefetch_fill(inst, target, max_bytes)) {
        return push_error(L, host, inst->last_error);
    }
    host->lua.pushinteger(L, (int64_t)inst->prefetch_len);
    host->lua.pushinteger(L, (int64_t)inst->prefetch_cap);
    host->lua.pushboolean(L, inst->prefetch_eof ? 1 : 0);
    return 3;
}

static int audio_read_pcm(audio_instance_t *inst, uint8_t *dst, size_t want, size_t *out_produced)
{
    size_t produced = 0;
    if (!inst || !dst || !out_produced || !inst->opened) {
        return -1;
    }
    *out_produced = 0;
    while (produced < want) {
        size_t avail = 0;
        size_t n = 0;
        int decoded = 0;
        if (inst->pcm_pos >= inst->pcm_len) {
            inst->pcm_pos = 0;
            inst->pcm_len = 0;
            decoded = audio_decode_next(inst, &inst->pcm_len, 1);
            if (decoded < 0) {
                return -1;
            }
            if (decoded == 0 || inst->pcm_len == 0) {
                break;
            }
        }
        avail = inst->pcm_len - inst->pcm_pos;
        n = want - produced;
        if (n > avail) {
            n = avail;
        }
        audio_copy_bytes(dst + produced, inst->out_buf + inst->pcm_pos, n);
        inst->pcm_pos += n;
        produced += n;
    }
    *out_produced = produced;
    return 0;
}

static int audio_pcm_ring_fill_once(audio_instance_t *inst, size_t chunk, size_t *out_produced)
{
    size_t free_bytes = 0;
    size_t want = 0;
    size_t produced = 0;
    if (out_produced) {
        *out_produced = 0;
    }
    if (!inst || inst->pcm_ring_eof) {
        return 1;
    }
    free_bytes = audio_pcm_ring_free(inst);
    want = chunk ? chunk : AUDIO_PLAY_TASK_CHUNK_BYTES;
    if (want > inst->read_cap) {
        want = inst->read_cap;
    }
    if (want > free_bytes) {
        want = free_bytes;
    }
    want = audio_align_pcm_bytes(inst, want);
    if (want == 0) {
        return 1;
    }
    if (audio_read_pcm(inst, inst->read_buf, want, &produced) < 0) {
        return 0;
    }
    if (produced == 0) {
        inst->pcm_ring_eof = 1;
        return 1;
    }
    produced = audio_align_pcm_bytes(inst, produced);
    if (produced > 0 && !audio_pcm_ring_push(inst, inst->read_buf, produced)) {
        return 0;
    }
    if (out_produced) {
        *out_produced = produced;
    }
    return 1;
}

static int audio_i2s_write_pcm(audio_instance_t *inst,
                               const uint8_t *data,
                               size_t len,
                               uint32_t timeout_ms,
                               size_t *out_written)
{
    size_t total_written = 0;
    size_t written = 0;
    int32_t err = MODULE_OK;
    if (!inst || !inst->i2s_stream || !inst->host.i2s.write || !out_written) {
        return 0;
    }
    *out_written = 0;

    if (inst->i2s_pending_len > 0) {
        err = inst->host.i2s.write(inst->i2s_stream,
                                   inst->i2s_pending_buf + inst->i2s_pending_pos,
                                   inst->i2s_pending_len,
                                   &written,
                                   timeout_ms);
        if (err != MODULE_OK) {
            audio_set_error(inst, "audio: i2s write failed");
            return 0;
        }
        if (written > inst->i2s_pending_len) {
            written = inst->i2s_pending_len;
        }
        inst->i2s_pending_pos += written;
        inst->i2s_pending_len -= written;
        total_written += written;
        if (inst->i2s_pending_len > 0) {
            *out_written = total_written;
            return 1;
        }
        inst->i2s_pending_pos = 0;
    }

    if (data && len > 0) {
        size_t remain = 0;
        written = 0;
        err = inst->host.i2s.write(inst->i2s_stream, data, len, &written, timeout_ms);
        if (err != MODULE_OK) {
            audio_set_error(inst, "audio: i2s write failed");
            return 0;
        }
        if (written > len) {
            written = len;
        }
        total_written += written;
        remain = len - written;
        if (remain > 0) {
            if (remain > inst->i2s_pending_cap) {
                audio_set_error(inst, "audio: i2s pending overflow");
                return 0;
            }
            audio_copy_bytes(inst->i2s_pending_buf, data + written, remain);
            inst->i2s_pending_pos = 0;
            inst->i2s_pending_len = remain;
            inst->i2s_short_writes++;
        }
    }

    *out_written = total_written;
    return 1;
}

static void audio_play_task_exit(audio_instance_t *inst)
{
    module_task_api_t task = {0};
    module_time_api_t time = {0};
    void *task_handle = NULL;
    if (inst) {
        task = inst->host.task;
        time = inst->host.time;
        task_handle = inst->play_task;
        inst->play_task_running = 0;
        inst->play_task_stop = 0;
        inst->play_task = NULL;
    } else if (s_host) {
        task = s_host->task;
        time = s_host->time;
    }

    if (task.remove) {
        task.remove(task_handle);
    }

    for (;;) {
        if (task.delay) {
            task.delay(1000);
        } else if (time.delay) {
            time.delay(1000);
        } else if (task.yield) {
            task.yield();
        }
    }
}

static void audio_producer_task_exit(audio_instance_t *inst)
{
    module_task_api_t task = {0};
    module_time_api_t time = {0};
    void *task_handle = NULL;
    if (inst) {
        task = inst->host.task;
        time = inst->host.time;
        task_handle = inst->producer_task;
        inst->producer_task_running = 0;
        inst->producer_task = NULL;
    } else if (s_host) {
        task = s_host->task;
        time = s_host->time;
    }

    if (task.remove) {
        task.remove(task_handle);
    }

    for (;;) {
        if (task.delay) {
            task.delay(1000);
        } else if (time.delay) {
            time.delay(1000);
        } else if (task.yield) {
            task.yield();
        }
    }
}

static void audio_i2s_producer_task_entry(void *arg)
{
    audio_instance_t *inst = (audio_instance_t *)arg;
    size_t chunk = 0;
    if (!inst) {
        audio_producer_task_exit(NULL);
    }
    inst->producer_task_running = 1;
    inst->producer_task_eof = 0;
    inst->producer_task_error = 0;
    chunk = inst->producer_task_chunk_bytes ? inst->producer_task_chunk_bytes : AUDIO_PLAY_TASK_CHUNK_BYTES;
    if (chunk > inst->read_cap) {
        chunk = inst->read_cap;
    }
    if (chunk > inst->i2s_task_cap) {
        chunk = inst->i2s_task_cap;
    }
    if (chunk == 0) {
        chunk = AUDIO_DEFAULT_READ;
    }

    while (!inst->play_task_stop) {
        size_t produced = 0;
        if (audio_pcm_ring_free(inst) < audio_align_pcm_bytes(inst, chunk)) {
            if (inst->host.task.delay) {
                inst->host.task.delay(1);
            } else if (inst->host.task.yield) {
                inst->host.task.yield();
            }
            continue;
        }

        /* Keep SD reads in a short refill phase; decode below consumes buffered bytes. */
        if (!audio_prefetch_refill_low_water(inst)) {
            inst->producer_task_error = 1;
            inst->play_task_error = 1;
            break;
        }

        if (!audio_pcm_ring_fill_once(inst, chunk, &produced)) {
            inst->producer_task_error = 1;
            inst->play_task_error = 1;
            break;
        }
        if (produced == 0) {
            if (inst->pcm_ring_eof) {
                inst->producer_task_eof = 1;
                break;
            }
            if (inst->host.task.delay) {
                inst->host.task.delay(1);
            }
            continue;
        }
        inst->producer_task_decoded_bytes += (uint32_t)produced;
        inst->producer_task_iterations++;
        if (inst->host.task.yield) {
            inst->host.task.yield();
        }
    }

    audio_producer_task_exit(inst);
}

static void audio_i2s_play_task_entry(void *arg)
{
    audio_instance_t *inst = (audio_instance_t *)arg;
    size_t chunk = 0;
    uint32_t timeout_ms = AUDIO_PLAY_TASK_TIMEOUT_MS;
    if (!inst) {
        audio_play_task_exit(NULL);
    }
    inst->play_task_running = 1;
    inst->play_task_eof = 0;
    inst->play_task_error = 0;
    inst->play_task_buffering = 0;
    chunk = inst->play_task_chunk_bytes ? inst->play_task_chunk_bytes : AUDIO_PLAY_TASK_CHUNK_BYTES;
    timeout_ms = inst->play_task_timeout_ms ? inst->play_task_timeout_ms : AUDIO_PLAY_TASK_TIMEOUT_MS;
    if (chunk > inst->read_cap) {
        chunk = inst->read_cap;
    }
    if (chunk == 0) {
        chunk = AUDIO_DEFAULT_READ;
    }

    while (!inst->play_task_stop) {
        size_t written = 0;
        size_t popped = 0;
        size_t used = audio_pcm_ring_used(inst);

        if (inst->play_task_paused) {
            inst->pcm_ring_len = used;
            if (inst->host.task.delay) {
                inst->host.task.delay(5);
            } else if (inst->host.task.yield) {
                inst->host.task.yield();
            }
            continue;
        }

        if (!inst->pcm_ring_started && !inst->pcm_ring_eof && used < AUDIO_PCM_RING_START_BYTES) {
            if (!inst->play_task_buffering) {
                inst->play_task_buffer_events++;
            }
            inst->play_task_buffering = 1;
        }

        if (inst->play_task_buffering) {
            used = audio_pcm_ring_used(inst);
            inst->pcm_ring_len = used;
            if (used >= AUDIO_PCM_RING_RESUME_BYTES || inst->pcm_ring_eof) {
                inst->play_task_buffering = 0;
                inst->pcm_ring_started = 1;
            } else {
                if (inst->host.task.delay) {
                    inst->host.task.delay(1);
                }
                continue;
            }
        }

        used = audio_pcm_ring_used(inst);
        inst->pcm_ring_len = used;
        if (used == 0 && inst->pcm_ring_eof) {
            inst->play_task_eof = 1;
            break;
        }

        if (!inst->pcm_ring_eof && inst->pcm_ring_started && used < AUDIO_PCM_RING_LOW_BYTES) {
            if (!inst->play_task_buffering) {
                inst->play_task_buffer_events++;
            }
            inst->play_task_buffering = 1;
            continue;
        }

        if (inst->i2s_pending_len > 0) {
            if (!audio_i2s_write_pcm(inst, NULL, 0, timeout_ms, &written)) {
                inst->play_task_error = 1;
                break;
            }
            inst->play_task_written_bytes += (uint32_t)written;
            inst->play_task_iterations++;
            if (inst->i2s_pending_len > 0) {
                if (inst->host.task.delay) {
                    inst->host.task.delay(1);
                }
                continue;
            }
        }

        popped = audio_pcm_ring_pop(inst, inst->i2s_task_buf, chunk);
        if (popped == 0) {
            if (inst->pcm_ring_eof) {
                inst->play_task_eof = 1;
                break;
            }
            if (!inst->play_task_buffering) {
                inst->play_task_buffer_events++;
            }
            inst->play_task_buffering = 1;
            continue;
        }
        if (!audio_i2s_write_pcm(inst, inst->i2s_task_buf, popped, timeout_ms, &written)) {
            inst->play_task_error = 1;
            break;
        }
        inst->play_task_written_bytes += (uint32_t)written;
        inst->play_task_iterations++;
        used = audio_pcm_ring_used(inst);
        inst->pcm_ring_len = used;
        if (!inst->pcm_ring_eof && used < AUDIO_PCM_RING_LOW_BYTES) {
            if (!inst->play_task_buffering) {
                inst->play_task_buffer_events++;
            }
            inst->play_task_buffering = 1;
        }
        if (inst->host.task.yield) {
            inst->host.task.yield();
        }
    }

    audio_play_task_exit(inst);
}

static void audio_play_task_stop_internal(audio_instance_t *inst, uint32_t wait_ms)
{
    uint32_t waited = 0;
    if (!inst) {
        return;
    }
    if (!inst->play_task && !inst->play_task_running &&
        !inst->producer_task && !inst->producer_task_running) {
        inst->play_task_stop = 0;
        return;
    }
    inst->play_task_stop = 1;
    while ((inst->play_task_running || inst->producer_task_running) && waited < wait_ms) {
        if (inst->host.task.delay) {
            inst->host.task.delay(1);
        } else if (inst->host.time.delay) {
            inst->host.time.delay(1);
        }
        waited++;
    }
    if (inst->producer_task && inst->producer_task_running && inst->host.task.remove) {
        inst->host.task.remove(inst->producer_task);
        inst->producer_task_running = 0;
    }
    if (inst->play_task && inst->play_task_running && inst->host.task.remove) {
        inst->host.task.remove(inst->play_task);
        inst->play_task_running = 0;
    }
    if (!inst->producer_task_running) {
        inst->producer_task = NULL;
    }
    if (!inst->play_task_running) {
        inst->play_task = NULL;
    }
    if (!inst->play_task_running && !inst->producer_task_running) {
        inst->play_task_stop = 0;
    }
}

/* audio.read([max_bytes]) -> PCM string。 */
static int l_audio_read(lua_State *L)
{
    audio_instance_t *inst = instance_from_lua(L);
    const module_host_api_v1 *host = inst ? &inst->host : s_host;
    size_t want = AUDIO_DEFAULT_READ;
    size_t produced = 0;
    if (!inst || !host || !inst->opened) {
        return push_error(L, host, "audio: not open");
    }
    if (host->lua.isnumber(L, 1)) {
        int64_t v = host->lua.tointeger(L, 1);
        if (v > 0) {
            want = (size_t)v;
        }
    }
    if (want > inst->read_cap) {
        want = inst->read_cap;
    }
    if (audio_read_pcm(inst, inst->read_buf, want, &produced) < 0) {
        return push_error(L, host, inst->last_error);
    }
    host->lua.pushlstring(L, (const char *)inst->read_buf, produced);
    return 1;
}

/* audio.i2s_start(opts)。 */
static int l_audio_i2s_start(lua_State *L)
{
    audio_instance_t *inst = instance_from_lua(L);
    const module_host_api_v1 *host = inst ? &inst->host : s_host;
    module_i2s_config_t cfg;
    int64_t v = 0;
    int32_t err = MODULE_OK;
    if (!inst || !host || !inst->opened) {
        return push_error(L, host, "audio: not open");
    }
    if (!host->i2s.begin || !host->i2s.end || !host->i2s.write) {
        return push_error(L, host, "audio: missing i2s host api");
    }

    audio_i2s_stop_internal(inst);
    audio_reset_i2s_pending(inst);
    memset(&cfg, 0, sizeof(cfg));
    cfg.size = sizeof(cfg);
    cfg.port = 0;
    cfg.mode = MODULE_I2S_MODE_TX;
    cfg.sample_rate = inst->sample_rate ? inst->sample_rate : 44100u;
    cfg.bits = inst->bits_per_sample ? inst->bits_per_sample : 16u;
    cfg.channels = inst->output_channels ? inst->output_channels : 1u;
    cfg.format = MODULE_I2S_FORMAT_I2S;
    cfg.channel_mode = (cfg.channels > 1u) ? MODULE_I2S_CHANNEL_STEREO : MODULE_I2S_CHANNEL_MONO_LEFT;
    cfg.bclk_pin = -1;
    cfg.ws_pin = -1;
    cfg.dout_pin = -1;
    cfg.din_pin = -1;
    cfg.mclk_pin = -1;
    cfg.dma_buf_count = 6;
    cfg.dma_buf_len = 512;
    cfg.flags = MODULE_I2S_FLAG_AUTO_CLEAR_TX;

    if (host->lua.istable(L, 1)) {
        host->lua.getfield(L, 1, "port");
        if (host->lua.isnumber(L, -1)) {
            v = host->lua.tointeger(L, -1);
            if (v >= 0 && v <= 255) {
                cfg.port = (uint8_t)v;
            }
        }
        host->lua.settop(L, 1);

        host->lua.getfield(L, 1, "sample_rate");
        if (host->lua.isnumber(L, -1)) {
            v = host->lua.tointeger(L, -1);
            if (v > 0) {
                cfg.sample_rate = (uint32_t)v;
            }
        }
        host->lua.settop(L, 1);

        host->lua.getfield(L, 1, "channels");
        if (host->lua.isnumber(L, -1)) {
            v = host->lua.tointeger(L, -1);
            cfg.channels = (v == 2) ? 2u : 1u;
            cfg.channel_mode = (cfg.channels > 1u) ? MODULE_I2S_CHANNEL_STEREO : MODULE_I2S_CHANNEL_MONO_LEFT;
        }
        host->lua.settop(L, 1);

        host->lua.getfield(L, 1, "dout_pin");
        if (host->lua.isnumber(L, -1)) {
            cfg.dout_pin = (int16_t)host->lua.tointeger(L, -1);
        }
        host->lua.settop(L, 1);

        host->lua.getfield(L, 1, "data_out_pin");
        if (host->lua.isnumber(L, -1)) {
            cfg.dout_pin = (int16_t)host->lua.tointeger(L, -1);
        }
        host->lua.settop(L, 1);

        host->lua.getfield(L, 1, "bclk_pin");
        if (host->lua.isnumber(L, -1)) {
            cfg.bclk_pin = (int16_t)host->lua.tointeger(L, -1);
        }
        host->lua.settop(L, 1);

        host->lua.getfield(L, 1, "ws_pin");
        if (host->lua.isnumber(L, -1)) {
            cfg.ws_pin = (int16_t)host->lua.tointeger(L, -1);
        }
        host->lua.settop(L, 1);

        host->lua.getfield(L, 1, "buffer_count");
        if (host->lua.isnumber(L, -1)) {
            v = host->lua.tointeger(L, -1);
            if (v > 0 && v <= 32) {
                cfg.dma_buf_count = (uint16_t)v;
            }
        }
        host->lua.settop(L, 1);

        host->lua.getfield(L, 1, "buffer_len");
        if (host->lua.isnumber(L, -1)) {
            v = host->lua.tointeger(L, -1);
            if (v > 0 && v <= 4096) {
                cfg.dma_buf_len = (uint16_t)v;
            }
        }
        host->lua.settop(L, 1);
    }

    err = host->i2s.begin(&cfg, &inst->i2s_stream);
    if (err != MODULE_OK || !inst->i2s_stream) {
        audio_set_error(inst, "audio: i2s begin failed");
        return push_error(L, host, inst->last_error);
    }
    host->lua.pushboolean(L, 1);
    return 1;
}

/* audio.play_i2s([max_bytes[, timeout_ms]]) -> written, produced, eof。 */
static int l_audio_play_i2s(lua_State *L)
{
    audio_instance_t *inst = instance_from_lua(L);
    const module_host_api_v1 *host = inst ? &inst->host : s_host;
    size_t want = AUDIO_DEFAULT_READ;
    size_t produced = 0;
    size_t written = 0;
    size_t total_written = 0;
    uint32_t timeout_ms = 0;
    int32_t err = MODULE_OK;
    if (!inst || !host || !inst->opened) {
        return push_error(L, host, "audio: not open");
    }
    if (!inst->i2s_stream || !host->i2s.write) {
        return push_error(L, host, "audio: i2s not started");
    }
    if (inst->play_task_running || inst->producer_task_running) {
        return push_error(L, host, "audio: play task running");
    }
    if (host->lua.isnumber(L, 1)) {
        int64_t v = host->lua.tointeger(L, 1);
        if (v > 0) {
            want = (size_t)v;
        }
    }
    if (want > inst->read_cap) {
        want = inst->read_cap;
    }
    if (host->lua.isnumber(L, 2)) {
        int64_t v = host->lua.tointeger(L, 2);
        if (v > 0 && v < 10000) {
            timeout_ms = (uint32_t)v;
        }
    }

    if (inst->i2s_pending_len > 0) {
        written = 0;
        err = host->i2s.write(inst->i2s_stream,
                              inst->i2s_pending_buf + inst->i2s_pending_pos,
                              inst->i2s_pending_len,
                              &written,
                              timeout_ms);
        if (err != MODULE_OK) {
            audio_set_error(inst, "audio: i2s write failed");
            return push_error(L, host, inst->last_error);
        }
        if (written > inst->i2s_pending_len) {
            written = inst->i2s_pending_len;
        }
        inst->i2s_pending_pos += written;
        inst->i2s_pending_len -= written;
        total_written += written;
        if (inst->i2s_pending_len > 0) {
            host->lua.pushinteger(L, (int64_t)total_written);
            host->lua.pushinteger(L, 0);
            host->lua.pushboolean(L, 0);
            return 3;
        }
        inst->i2s_pending_pos = 0;
    }

    if (audio_read_pcm(inst, inst->read_buf, want, &produced) < 0) {
        return push_error(L, host, inst->last_error);
    }
    if (produced > 0) {
        size_t remain = 0;
        err = host->i2s.write(inst->i2s_stream, inst->read_buf, produced, &written, timeout_ms);
        if (err != MODULE_OK) {
            audio_set_error(inst, "audio: i2s write failed");
            return push_error(L, host, inst->last_error);
        }
        if (written > produced) {
            written = produced;
        }
        total_written += written;
        remain = produced - written;
        if (remain > 0) {
            if (remain > inst->i2s_pending_cap) {
                audio_set_error(inst, "audio: i2s pending overflow");
                return push_error(L, host, inst->last_error);
            }
            audio_copy_bytes(inst->i2s_pending_buf, inst->read_buf + written, remain);
            inst->i2s_pending_pos = 0;
            inst->i2s_pending_len = remain;
            inst->i2s_short_writes++;
        }
    }
    host->lua.pushinteger(L, (int64_t)total_written);
    host->lua.pushinteger(L, (int64_t)produced);
    host->lua.pushboolean(L, (inst->eof && inst->pcm_pos >= inst->pcm_len) ? 1 : 0);
    return 3;
}

/* audio.i2s_play_start(opts)。producer decode 到 PCM ring，consumer 只负责写 I2S。 */
static int l_audio_i2s_play_start(lua_State *L)
{
    audio_instance_t *inst = instance_from_lua(L);
    const module_host_api_v1 *host = inst ? &inst->host : s_host;
    uint32_t stack_bytes = AUDIO_PLAY_TASK_STACK;
    uint32_t producer_stack_bytes = AUDIO_PRODUCER_TASK_STACK;
    uint32_t priority = AUDIO_PLAY_TASK_PRIORITY;
    uint32_t producer_priority = AUDIO_PRODUCER_TASK_PRIORITY;
    int32_t core = AUDIO_PLAY_TASK_CORE;
    int32_t producer_core = AUDIO_PLAY_TASK_CORE;
    int64_t v = 0;
    int32_t err = MODULE_OK;
    if (!inst || !host || !inst->opened) {
        return push_error(L, host, "audio: not open");
    }
    if (!inst->i2s_stream || !host->i2s.write) {
        return push_error(L, host, "audio: i2s not started");
    }
    if (!host->task.create) {
        return push_error(L, host, "audio: missing task host api");
    }
    if (inst->play_task_running || inst->producer_task_running) {
        host->lua.pushboolean(L, 1);
        return 1;
    }

    inst->play_task_chunk_bytes = AUDIO_PLAY_TASK_CHUNK_BYTES;
    inst->play_task_timeout_ms = AUDIO_PLAY_TASK_TIMEOUT_MS;
    if (host->lua.istable(L, 1)) {
        host->lua.getfield(L, 1, "chunk_bytes");
        if (host->lua.isnumber(L, -1)) {
            v = host->lua.tointeger(L, -1);
            if (v > 0 && v <= (int64_t)inst->read_cap && v <= (int64_t)inst->i2s_task_cap) {
                inst->play_task_chunk_bytes = (uint32_t)v;
            }
        }
        host->lua.settop(L, 1);

        host->lua.getfield(L, 1, "timeout_ms");
        if (host->lua.isnumber(L, -1)) {
            v = host->lua.tointeger(L, -1);
            if (v > 0 && v <= 1000) {
                inst->play_task_timeout_ms = (uint32_t)v;
            }
        }
        host->lua.settop(L, 1);

        host->lua.getfield(L, 1, "stack_bytes");
        if (host->lua.isnumber(L, -1)) {
            v = host->lua.tointeger(L, -1);
            if (v >= 4096 && v <= 32768) {
                stack_bytes = (uint32_t)v;
            }
        }
        host->lua.settop(L, 1);

        host->lua.getfield(L, 1, "producer_stack_bytes");
        if (host->lua.isnumber(L, -1)) {
            v = host->lua.tointeger(L, -1);
            if (v >= 4096 && v <= 32768) {
                producer_stack_bytes = (uint32_t)v;
            }
        }
        host->lua.settop(L, 1);

        host->lua.getfield(L, 1, "priority");
        if (host->lua.isnumber(L, -1)) {
            v = host->lua.tointeger(L, -1);
            if (v > 0 && v <= 24) {
                priority = (uint32_t)v;
            }
        }
        host->lua.settop(L, 1);

        host->lua.getfield(L, 1, "producer_priority");
        if (host->lua.isnumber(L, -1)) {
            v = host->lua.tointeger(L, -1);
            if (v > 0 && v <= 24) {
                producer_priority = (uint32_t)v;
            }
        }
        host->lua.settop(L, 1);

        host->lua.getfield(L, 1, "core");
        if (host->lua.isnumber(L, -1)) {
            v = host->lua.tointeger(L, -1);
            if (v >= -1 && v <= 1) {
                core = (int32_t)v;
            }
        }
        host->lua.settop(L, 1);

        host->lua.getfield(L, 1, "producer_core");
        if (host->lua.isnumber(L, -1)) {
            v = host->lua.tointeger(L, -1);
            if (v >= -1 && v <= 1) {
                producer_core = (int32_t)v;
            }
        }
        host->lua.settop(L, 1);
    }

    audio_play_task_stop_internal(inst, AUDIO_PLAY_TASK_STOP_WAIT_MS);
    inst->play_task_stop = 0;
    inst->play_task_eof = 0;
    inst->play_task_error = 0;
    inst->play_task_paused = 0;
    inst->play_task_buffering = 0;
    inst->producer_task_eof = 0;
    inst->producer_task_error = 0;
    inst->producer_task_chunk_bytes = inst->play_task_chunk_bytes;
    inst->play_task_written_bytes = 0;
    inst->play_task_iterations = 0;
    inst->producer_task_iterations = 0;
    inst->producer_task_decoded_bytes = 0;
    inst->play_task_buffer_events = 0;
    err = host->task.create("audio_fill", audio_i2s_producer_task_entry, inst,
                            producer_stack_bytes, producer_priority, producer_core, &inst->producer_task);
    if (err != MODULE_OK || !inst->producer_task) {
        inst->producer_task = NULL;
        audio_set_error(inst, "audio: producer task create failed");
        return push_error(L, host, inst->last_error);
    }
    err = host->task.create("audio_i2s", audio_i2s_play_task_entry, inst,
                            stack_bytes, priority, core, &inst->play_task);
    if (err != MODULE_OK || !inst->play_task) {
        inst->play_task = NULL;
        audio_play_task_stop_internal(inst, AUDIO_PLAY_TASK_STOP_WAIT_MS);
        audio_set_error(inst, "audio: play task create failed");
        return push_error(L, host, inst->last_error);
    }
    host->lua.pushboolean(L, 1);
    return 1;
}

static int l_audio_i2s_play_stop(lua_State *L)
{
    audio_instance_t *inst = instance_from_lua(L);
    const module_host_api_v1 *host = inst ? &inst->host : s_host;
    if (inst) {
        audio_play_task_stop_internal(inst, AUDIO_PLAY_TASK_STOP_WAIT_MS);
    }
    host->lua.pushboolean(L, 1);
    return 1;
}

static int l_audio_i2s_play_pause(lua_State *L)
{
    audio_instance_t *inst = instance_from_lua(L);
    const module_host_api_v1 *host = inst ? &inst->host : s_host;
    int pause = 1;
    if (!inst || !host) {
        return push_error(L, host, "audio: missing instance");
    }
    if (host->lua.gettop(L) >= 1) {
        pause = host->lua.toboolean(L, 1) ? 1 : 0;
    }
    inst->play_task_paused = pause ? 1 : 0;
    host->lua.pushboolean(L, 1);
    return 1;
}

static int l_audio_i2s_play_state(lua_State *L)
{
    audio_instance_t *inst = instance_from_lua(L);
    const module_host_api_v1 *host = inst ? &inst->host : s_host;
    if (!inst || !host) {
        return push_error(L, host, "audio: missing instance");
    }
    inst->pcm_ring_len = audio_pcm_ring_used(inst);
    host->lua.newtable(L);
    host->lua.pushinteger(L, inst->play_task_running ? 1 : 0);
    host->lua.setfield(L, -2, "running");
    host->lua.pushinteger(L, inst->play_task_eof ? 1 : 0);
    host->lua.setfield(L, -2, "eof");
    host->lua.pushinteger(L, (inst->play_task_error || inst->producer_task_error) ? 1 : 0);
    host->lua.setfield(L, -2, "error");
    host->lua.pushinteger(L, inst->play_task_paused ? 1 : 0);
    host->lua.setfield(L, -2, "paused");
    host->lua.pushinteger(L, inst->play_task_buffering ? 1 : 0);
    host->lua.setfield(L, -2, "buffering");
    host->lua.pushinteger(L, inst->producer_task_running ? 1 : 0);
    host->lua.setfield(L, -2, "producer_running");
    host->lua.pushinteger(L, inst->producer_task_eof ? 1 : 0);
    host->lua.setfield(L, -2, "producer_eof");
    host->lua.pushinteger(L, inst->producer_task_error ? 1 : 0);
    host->lua.setfield(L, -2, "producer_error");
    host->lua.pushinteger(L, (int64_t)inst->play_task_written_bytes);
    host->lua.setfield(L, -2, "written_bytes");
    host->lua.pushinteger(L, (int64_t)inst->play_task_iterations);
    host->lua.setfield(L, -2, "iterations");
    host->lua.pushinteger(L, (int64_t)inst->producer_task_iterations);
    host->lua.setfield(L, -2, "producer_iterations");
    host->lua.pushinteger(L, (int64_t)inst->producer_task_decoded_bytes);
    host->lua.setfield(L, -2, "producer_decoded_bytes");
    host->lua.pushinteger(L, (int64_t)inst->i2s_pending_len);
    host->lua.setfield(L, -2, "pending_bytes");
    host->lua.pushinteger(L, (int64_t)inst->pcm_ring_len);
    host->lua.setfield(L, -2, "pcm_buffer_bytes");
    host->lua.pushinteger(L, (int64_t)inst->pcm_ring_cap);
    host->lua.setfield(L, -2, "pcm_buffer_capacity");
    host->lua.pushinteger(L, AUDIO_PCM_RING_LOW_BYTES);
    host->lua.setfield(L, -2, "pcm_buffer_low_bytes");
    host->lua.pushinteger(L, AUDIO_PCM_RING_RESUME_BYTES);
    host->lua.setfield(L, -2, "pcm_buffer_resume_bytes");
    host->lua.pushinteger(L, inst->pcm_ring_eof ? 1 : 0);
    host->lua.setfield(L, -2, "pcm_buffer_eof");
    host->lua.pushinteger(L, inst->play_task_buffer_events);
    host->lua.setfield(L, -2, "buffer_events");
    host->lua.pushinteger(L, inst->i2s_short_writes);
    host->lua.setfield(L, -2, "short_writes");
    host->lua.pushstring(L, inst->last_error);
    host->lua.setfield(L, -2, "last_error");
    return 1;
}

static int l_audio_yield(lua_State *L)
{
    audio_instance_t *inst = instance_from_lua(L);
    const module_host_api_v1 *host = inst ? &inst->host : s_host;
    if (!host) {
        return 0;
    }
    if (host->task.yield) {
        host->task.yield();
    } else if (host->time.yield) {
        host->time.yield();
    }
    host->lua.pushboolean(L, 1);
    return 1;
}

static int l_audio_i2s_stop(lua_State *L)
{
    audio_instance_t *inst = instance_from_lua(L);
    const module_host_api_v1 *host = inst ? &inst->host : s_host;
    if (inst) {
        audio_i2s_stop_internal(inst);
    }
    host->lua.pushboolean(L, 1);
    return 1;
}

/* audio.close()。 */
static int l_audio_close(lua_State *L)
{
    audio_instance_t *inst = instance_from_lua(L);
    const module_host_api_v1 *host = inst ? &inst->host : s_host;
    if (inst) {
        audio_close_internal(inst);
    }
    host->lua.pushboolean(L, 1);
    return 1;
}

/* audio.stats() 用于串口/DevRun 粗略观察模块占用。 */
static int l_audio_stats(lua_State *L)
{
    audio_instance_t *inst = instance_from_lua(L);
    const module_host_api_v1 *host = inst ? &inst->host : s_host;
    if (!inst || !host) {
        return push_error(L, host, "audio: missing instance");
    }
    inst->pcm_ring_len = audio_pcm_ring_used(inst);
    host->lua.newtable(L);
    host->lua.pushinteger(L, inst->in_cap + inst->prefetch_cap + inst->out_cap + inst->read_cap +
                          inst->i2s_task_cap + inst->i2s_pending_cap + inst->pcm_ring_cap +
                          inst->dsp_cap * sizeof(float) + inst->vbass_cap * sizeof(float));
    host->lua.setfield(L, -2, "module_buffer_bytes");
    host->lua.pushinteger(L, inst->prefetch_cap);
    host->lua.setfield(L, -2, "prefetch_buffer_bytes");
    host->lua.pushinteger(L, inst->prefetch_len);
    host->lua.setfield(L, -2, "prefetch_bytes");
    host->lua.pushinteger(L, inst->prefetch_eof ? 1 : 0);
    host->lua.setfield(L, -2, "prefetch_eof");
    host->lua.pushinteger(L, inst->read_cap);
    host->lua.setfield(L, -2, "read_buffer_bytes");
    host->lua.pushinteger(L, inst->i2s_task_cap);
    host->lua.setfield(L, -2, "i2s_task_buffer_bytes");
    host->lua.pushinteger(L, inst->i2s_pending_len);
    host->lua.setfield(L, -2, "i2s_pending_bytes");
    host->lua.pushinteger(L, inst->pcm_ring_cap);
    host->lua.setfield(L, -2, "pcm_buffer_capacity");
    host->lua.pushinteger(L, inst->pcm_ring_len);
    host->lua.setfield(L, -2, "pcm_buffer_bytes");
    host->lua.pushinteger(L, AUDIO_PCM_RING_LOW_BYTES);
    host->lua.setfield(L, -2, "pcm_buffer_low_bytes");
    host->lua.pushinteger(L, AUDIO_PCM_RING_RESUME_BYTES);
    host->lua.setfield(L, -2, "pcm_buffer_resume_bytes");
    host->lua.pushinteger(L, inst->play_task_buffering ? 1 : 0);
    host->lua.setfield(L, -2, "i2s_task_buffering");
    host->lua.pushinteger(L, inst->play_task_buffer_events);
    host->lua.setfield(L, -2, "i2s_task_buffer_events");
    host->lua.pushinteger(L, inst->play_task_paused ? 1 : 0);
    host->lua.setfield(L, -2, "i2s_task_paused");
    host->lua.pushinteger(L, inst->i2s_short_writes);
    host->lua.setfield(L, -2, "i2s_short_writes");
    host->lua.pushinteger(L, inst->play_task_running ? 1 : 0);
    host->lua.setfield(L, -2, "i2s_task_running");
    host->lua.pushinteger(L, inst->play_task_eof ? 1 : 0);
    host->lua.setfield(L, -2, "i2s_task_eof");
    host->lua.pushinteger(L, inst->play_task_error ? 1 : 0);
    host->lua.setfield(L, -2, "i2s_task_error");
    host->lua.pushinteger(L, inst->producer_task_running ? 1 : 0);
    host->lua.setfield(L, -2, "i2s_producer_running");
    host->lua.pushinteger(L, inst->producer_task_eof ? 1 : 0);
    host->lua.setfield(L, -2, "i2s_producer_eof");
    host->lua.pushinteger(L, inst->producer_task_error ? 1 : 0);
    host->lua.setfield(L, -2, "i2s_producer_error");
    host->lua.pushinteger(L, (int64_t)inst->producer_task_decoded_bytes);
    host->lua.setfield(L, -2, "i2s_producer_decoded_bytes");
    host->lua.pushinteger(L, (int64_t)inst->producer_task_iterations);
    host->lua.setfield(L, -2, "i2s_producer_iterations");
    host->lua.pushinteger(L, inst->producer_task_chunk_bytes);
    host->lua.setfield(L, -2, "i2s_producer_chunk_bytes");
    host->lua.pushinteger(L, (int64_t)inst->play_task_written_bytes);
    host->lua.setfield(L, -2, "i2s_task_written_bytes");
    host->lua.pushinteger(L, (int64_t)inst->play_task_iterations);
    host->lua.setfield(L, -2, "i2s_task_iterations");
    host->lua.pushinteger(L, inst->play_task_chunk_bytes);
    host->lua.setfield(L, -2, "i2s_task_chunk_bytes");
    host->lua.pushinteger(L, inst->play_task_timeout_ms);
    host->lua.setfield(L, -2, "i2s_task_timeout_ms");
    host->lua.pushinteger(L, inst->dsp_cap * sizeof(float));
    host->lua.setfield(L, -2, "dsp_buffer_bytes");
    host->lua.pushinteger(L, inst->vbass_cap * sizeof(float));
    host->lua.setfield(L, -2, "vbass_buffer_bytes");
    host->lua.pushinteger(L, inst->eq_enabled ? 1 : 0);
    host->lua.setfield(L, -2, "eq_enabled");
    host->lua.pushinteger(L, inst->eq_active);
    host->lua.setfield(L, -2, "eq_active");
    host->lua.pushinteger(L, inst->hpf.enabled ? 1 : 0);
    host->lua.setfield(L, -2, "hpf_active");
    host->lua.pushinteger(L, inst->limiter_enabled ? 1 : 0);
    host->lua.setfield(L, -2, "limiter_enabled");
    host->lua.pushinteger(L, inst->limiter_threshold);
    host->lua.setfield(L, -2, "limiter_threshold");
    host->lua.pushinteger(L, inst->limiter_total_samples ?
                          (int64_t)(((uint64_t)inst->limiter_active_samples * 10000u) /
                                    inst->limiter_total_samples) : 0);
    host->lua.setfield(L, -2, "limiter_active_centipercent");
    host->lua.pushinteger(L, inst->vbass_enabled ? 1 : 0);
    host->lua.setfield(L, -2, "vbass_enabled");
    host->lua.pushinteger(L, audio_vbass_active(inst) ? 1 : 0);
    host->lua.setfield(L, -2, "vbass_active");
    host->lua.pushinteger(L, inst->loudness_enabled ? 1 : 0);
    host->lua.setfield(L, -2, "loudness_enabled");
    host->lua.pushinteger(L, inst->loudness_ready ? 1 : 0);
    host->lua.setfield(L, -2, "loudness_ready");
    host->lua.pushinteger(L, inst->loudness_segments);
    host->lua.setfield(L, -2, "loudness_segments");
    host->lua.pushinteger(L, inst->loudness_rms);
    host->lua.setfield(L, -2, "loudness_rms");
    host->lua.pushinteger(L, inst->loudness_peak);
    host->lua.setfield(L, -2, "loudness_peak");
    host->lua.pushinteger(L, inst->loudness_target_rms);
    host->lua.setfield(L, -2, "loudness_target_rms");
    host->lua.pushinteger(L, inst->loudness_gain_q15);
    host->lua.setfield(L, -2, "loudness_gain_q15");
    host->lua.pushinteger(L, host->heap.free_size(MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT));
    host->lua.setfield(L, -2, "internal_free");
    host->lua.pushinteger(L, host->heap.largest_free_block(MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT));
    host->lua.setfield(L, -2, "internal_largest");
    host->lua.pushinteger(L, host->heap.largest_free_block(MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT));
    host->lua.setfield(L, -2, "psram_largest");
    return 1;
}

AUDIO_MODULE_EXPORT const module_manifest_t *module_query_v1(void)
{
    return &s_manifest;
}

AUDIO_MODULE_EXPORT int32_t module_create_v2(module_host_resolve_v1_fn resolve,
                                             void *resolve_ctx,
                                             const module_open_info_t *info,
                                             void **out_instance)
{
    audio_instance_t *inst = NULL;
    module_host_api_v1 host;
    int32_t err = MODULE_OK;
    (void)info;
    if (!out_instance) {
        return MODULE_ERR_INVALID_ARG;
    }
    *out_instance = NULL;
    module_sdk_zero_host_v1(&host);
    err = module_sdk_resolve_host_v1(resolve, resolve_ctx, &host);
    if (err != MODULE_OK) {
        return err;
    }
    s_host = &host;
    inst = (audio_instance_t *)host.heap.calloc(1, sizeof(audio_instance_t), MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    if (!inst) {
        inst = (audio_instance_t *)host.heap.calloc(1, sizeof(audio_instance_t), MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT);
    }
    if (!inst) {
        return MODULE_ERR_NO_MEMORY;
    }
    inst->host = host;
    s_host = &inst->host;
    inst->in_cap = AUDIO_IN_CAP;
    inst->prefetch_cap = AUDIO_PREFETCH_CAP;
    inst->out_cap = AUDIO_OUT_INIT;
    inst->read_cap = AUDIO_READ_CAP;
    inst->i2s_task_cap = AUDIO_READ_CAP;
    inst->i2s_pending_cap = AUDIO_I2S_PENDING_CAP;
    inst->pcm_ring_cap = AUDIO_PCM_RING_CAP;
    inst->dsp_cap = AUDIO_DSP_CHUNK_SAMPLES;
    inst->vbass_cap = AUDIO_DSP_CHUNK_SAMPLES;
    inst->volume_q15 = 32768;
    inst->loudness_enabled = 1;
    inst->loudness_gain_q15 = 32768;
    inst->loudness_target_rms = AUDIO_LOUDNESS_DEFAULT_TARGET_RMS;
    inst->loudness_min_gain_q15 = AUDIO_LOUDNESS_DEFAULT_MIN_Q15;
    inst->loudness_max_gain_q15 = AUDIO_LOUDNESS_DEFAULT_MAX_Q15;
    inst->output_channels = 1;
    inst->bits_per_sample = 16;
    inst->limiter_enabled = 1;
    inst->limiter_threshold = AUDIO_LIMITER_DEFAULT_PEAK;
    inst->hpf_freq = 150.0f;
    inst->hpf_q = 0.707f;
    inst->vbass_enabled = 0;
    inst->vbass_low_hpf = 85.0f;
    inst->vbass_low_lpf = 170.0f;
    inst->vbass_out_hpf = 180.0f;
    inst->vbass_out_lpf = 620.0f;
    inst->vbass_drive = 1.5f;
    inst->vbass_mix = 0.08f;
    inst->vbass_even = 0.8f;
    inst->vbass_odd = 0.3f;
    {
        static const float default_freq[AUDIO_EQ_MAX_BANDS] = {230.0f, 420.0f, 720.0f, 1150.0f, 1800.0f, 3200.0f, 6200.0f};
        for (size_t i = 0; i < AUDIO_EQ_MAX_BANDS; ++i) {
            inst->eq_freq[i] = default_freq[i];
            inst->eq_gain[i] = 0.0f;
            inst->eq_q[i] = 0.8f;
        }
    }
    inst->in_buf = (uint8_t *)inst->host.heap.malloc(inst->in_cap, MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    inst->prefetch_buf = (uint8_t *)inst->host.heap.malloc(inst->prefetch_cap, MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    inst->out_buf = (uint8_t *)inst->host.heap.malloc(inst->out_cap, MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    inst->read_buf = (uint8_t *)inst->host.heap.malloc(inst->read_cap, MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    inst->i2s_task_buf = (uint8_t *)inst->host.heap.malloc(inst->i2s_task_cap,
                                                           MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    inst->i2s_pending_buf = (uint8_t *)inst->host.heap.malloc(inst->i2s_pending_cap,
                                                              MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    if (!inst->i2s_pending_buf) {
        inst->i2s_pending_buf = (uint8_t *)inst->host.heap.malloc(inst->i2s_pending_cap,
                                                                  MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT);
    }
    inst->pcm_ring_buf = (uint8_t *)inst->host.heap.malloc(inst->pcm_ring_cap,
                                                           MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    inst->dsp_buf = (float *)inst->host.heap.malloc(inst->dsp_cap * sizeof(float),
                                                    MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT);
    if (!inst->dsp_buf) {
        inst->dsp_buf = (float *)inst->host.heap.malloc(inst->dsp_cap * sizeof(float),
                                                        MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    }
    inst->vbass_buf = (float *)inst->host.heap.malloc(inst->vbass_cap * sizeof(float),
                                                      MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT);
    if (!inst->vbass_buf) {
        inst->vbass_buf = (float *)inst->host.heap.malloc(inst->vbass_cap * sizeof(float),
                                                          MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
    }
    if (!inst->in_buf || !inst->prefetch_buf || !inst->out_buf || !inst->read_buf ||
        !inst->i2s_task_buf || !inst->i2s_pending_buf || !inst->pcm_ring_buf ||
        !inst->dsp_buf || !inst->vbass_buf) {
        if (inst->in_buf) {
            inst->host.heap.free(inst->in_buf);
        }
        if (inst->prefetch_buf) {
            inst->host.heap.free(inst->prefetch_buf);
        }
        if (inst->out_buf) {
            inst->host.heap.free(inst->out_buf);
        }
        if (inst->read_buf) {
            inst->host.heap.free(inst->read_buf);
        }
        if (inst->i2s_task_buf) {
            inst->host.heap.free(inst->i2s_task_buf);
        }
        if (inst->i2s_pending_buf) {
            inst->host.heap.free(inst->i2s_pending_buf);
        }
        if (inst->pcm_ring_buf) {
            inst->host.heap.free(inst->pcm_ring_buf);
        }
        if (inst->dsp_buf) {
            inst->host.heap.free(inst->dsp_buf);
        }
        if (inst->vbass_buf) {
            inst->host.heap.free(inst->vbass_buf);
        }
        inst->host.heap.free(inst);
        return MODULE_ERR_NO_MEMORY;
    }
    *out_instance = inst;
    return MODULE_OK;
}

AUDIO_MODULE_EXPORT int32_t module_luaopen_v1(void *instance, lua_State *L)
{
    audio_instance_t *inst = (audio_instance_t *)instance;
    const module_host_api_v1 *host = inst ? &inst->host : s_host;
    if (!inst || !host) {
        return MODULE_ERR_INVALID_ARG;
    }
    s_host = host;
    host->lua.newtable(L);
    host->lua.pushstring(L, AUDIO_VERSION);
    host->lua.setfield(L, -2, "VERSION");
    set_function_field(L, host, "version", l_audio_version, inst);
    set_function_field(L, host, "yield", l_audio_yield, inst);
    set_function_field(L, host, "set_effects", l_audio_set_effects, inst);
    set_function_field(L, host, "open", l_audio_open, inst);
    set_function_field(L, host, "info", l_audio_info, inst);
    set_function_field(L, host, "prefetch", l_audio_prefetch, inst);
    set_function_field(L, host, "read", l_audio_read, inst);
    set_function_field(L, host, "i2s_start", l_audio_i2s_start, inst);
    set_function_field(L, host, "play_i2s", l_audio_play_i2s, inst);
    set_function_field(L, host, "i2s_play_start", l_audio_i2s_play_start, inst);
    set_function_field(L, host, "i2s_play_stop", l_audio_i2s_play_stop, inst);
    set_function_field(L, host, "i2s_play_pause", l_audio_i2s_play_pause, inst);
    set_function_field(L, host, "i2s_play_state", l_audio_i2s_play_state, inst);
    set_function_field(L, host, "i2s_stop", l_audio_i2s_stop, inst);
    set_function_field(L, host, "close", l_audio_close, inst);
    set_function_field(L, host, "stats", l_audio_stats, inst);
    set_function_field(L, host, "get_stats", l_audio_stats, inst);
    return MODULE_OK;
}

AUDIO_MODULE_EXPORT void module_destroy_v1(void *instance)
{
    audio_instance_t *inst = (audio_instance_t *)instance;
    if (!inst) {
        return;
    }
    audio_close_internal(inst);
    audio_unregister(inst);
    if (inst->in_buf) {
        inst->host.heap.free(inst->in_buf);
    }
    if (inst->prefetch_buf) {
        inst->host.heap.free(inst->prefetch_buf);
    }
    if (inst->out_buf) {
        inst->host.heap.free(inst->out_buf);
    }
    if (inst->read_buf) {
        inst->host.heap.free(inst->read_buf);
    }
    if (inst->i2s_task_buf) {
        inst->host.heap.free(inst->i2s_task_buf);
    }
    if (inst->i2s_pending_buf) {
        inst->host.heap.free(inst->i2s_pending_buf);
    }
    if (inst->pcm_ring_buf) {
        inst->host.heap.free(inst->pcm_ring_buf);
    }
    if (inst->dsp_buf) {
        inst->host.heap.free(inst->dsp_buf);
    }
    if (inst->vbass_buf) {
        inst->host.heap.free(inst->vbass_buf);
    }
    inst->host.heap.free(inst);
}

void *malloc(size_t size)
{
    if (!s_host || !s_host->heap.malloc) {
        return NULL;
    }
    return s_host->heap.malloc(size, MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
}

void *calloc(size_t n, size_t size)
{
    if (!s_host || !s_host->heap.calloc) {
        return NULL;
    }
    return s_host->heap.calloc(n, size, MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
}

void *realloc(void *ptr, size_t size)
{
    if (!s_host || !s_host->heap.realloc) {
        return NULL;
    }
    return s_host->heap.realloc(ptr, size, MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT);
}

void free(void *ptr)
{
    if (s_host && s_host->heap.free) {
        s_host->heap.free(ptr);
    }
}

void *memcpy(void *dst, const void *src, size_t n)
{
    uint8_t *d = (uint8_t *)dst;
    const uint8_t *s = (const uint8_t *)src;
    size_t i = 0;
    for (i = 0; i < n; ++i) {
        d[i] = s[i];
    }
    return dst;
}

void *memmove(void *dst, const void *src, size_t n)
{
    uint8_t *d = (uint8_t *)dst;
    const uint8_t *s = (const uint8_t *)src;
    size_t i = 0;
    if (d < s) {
        for (i = 0; i < n; ++i) {
            d[i] = s[i];
        }
    } else if (d > s) {
        for (i = n; i > 0; --i) {
            d[i - 1] = s[i - 1];
        }
    }
    return dst;
}

void *memset(void *dst, int value, size_t n)
{
    uint8_t *d = (uint8_t *)dst;
    size_t i = 0;
    for (i = 0; i < n; ++i) {
        d[i] = (uint8_t)value;
    }
    return dst;
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

char *strcpy(char *dst, const char *src)
{
    char *out = dst;
    while ((*dst++ = *src++) != '\0') {
    }
    return out;
}

int strcmp(const char *a, const char *b)
{
    while (*a && *a == *b) {
        ++a;
        ++b;
    }
    return (int)(unsigned char)*a - (int)(unsigned char)*b;
}

int strncmp(const char *a, const char *b, size_t n)
{
    size_t i = 0;
    for (i = 0; i < n; ++i) {
        unsigned char ca = (unsigned char)a[i];
        unsigned char cb = (unsigned char)b[i];
        if (ca != cb || ca == 0 || cb == 0) {
            return (int)ca - (int)cb;
        }
    }
    return 0;
}

int memcmp(const void *a, const void *b, size_t n)
{
    const uint8_t *pa = (const uint8_t *)a;
    const uint8_t *pb = (const uint8_t *)b;
    size_t i = 0;
    for (i = 0; i < n; ++i) {
        if (pa[i] != pb[i]) {
            return (int)pa[i] - (int)pb[i];
        }
    }
    return 0;
}

static float audio_wrap_pi(float x)
{
    const float two_pi = AUDIO_PI * 2.0f;
    while (x > AUDIO_PI) {
        x -= two_pi;
    }
    while (x < -AUDIO_PI) {
        x += two_pi;
    }
    return x;
}

float sinf(float x)
{
    float x2;
    x = audio_wrap_pi(x);
    x2 = x * x;
    return x * (1.0f - x2 * (1.0f / 6.0f) + x2 * x2 * (1.0f / 120.0f) -
                x2 * x2 * x2 * (1.0f / 5040.0f));
}

float cosf(float x)
{
    float x2;
    x = audio_wrap_pi(x);
    x2 = x * x;
    return 1.0f - x2 * 0.5f + x2 * x2 * (1.0f / 24.0f) -
           x2 * x2 * x2 * (1.0f / 720.0f);
}

float powf(float base, float exp)
{
    const float ln2 = 0.69314718056f;
    const float ln10 = 2.30258509299f;
    float z;
    float r;
    float r2;
    float y;
    int n;

    if (base <= 0.0f) {
        return 0.0f;
    }
    z = exp * ((base > 9.9f && base < 10.1f) ? ln10 : ln2);
    n = (int)(z / ln2);
    if (z < 0.0f && (float)n * ln2 > z) {
        --n;
    }
    r = z - (float)n * ln2;
    r2 = r * r;
    y = 1.0f + r + r2 * 0.5f + r2 * r * (1.0f / 6.0f) +
        r2 * r2 * (1.0f / 24.0f) + r2 * r2 * r * (1.0f / 120.0f);
    while (n > 0) {
        y *= 2.0f;
        --n;
    }
    while (n < 0) {
        y *= 0.5f;
        ++n;
    }
    return y;
}

uint32_t esp_log_timestamp(void)
{
    return 0;
}

unsigned long long __udivdi3(unsigned long long n, unsigned long long d)
{
    unsigned long long q = 0;
    unsigned long long bit = 1;
    if (d == 0) {
        return 0;
    }
    while ((d >> 63u) == 0 && d < n) {
        d <<= 1u;
        bit <<= 1u;
    }
    while (bit) {
        if (n >= d) {
            n -= d;
            q |= bit;
        }
        d >>= 1u;
        bit >>= 1u;
    }
    return q;
}

long long __divdi3(long long n, long long d)
{
    int neg = 0;
    unsigned long long un;
    unsigned long long ud;
    unsigned long long q;
    if (d == 0) {
        return 0;
    }
    if (n < 0) {
        neg = !neg;
        un = (unsigned long long)(-n);
    } else {
        un = (unsigned long long)n;
    }
    if (d < 0) {
        neg = !neg;
        ud = (unsigned long long)(-d);
    } else {
        ud = (unsigned long long)d;
    }
    q = __udivdi3(un, ud);
    return neg ? -(long long)q : (long long)q;
}

void esp_chip_info(esp_chip_info_t *out_info)
{
    if (!out_info) {
        return;
    }
    out_info->model = CHIP_ESP32S3;
    out_info->features = CHIP_FEATURE_WIFI_BGN | CHIP_FEATURE_BLE | CHIP_FEATURE_BT | CHIP_FEATURE_EMB_PSRAM;
    out_info->cores = 2;
    out_info->revision = 0;
}
