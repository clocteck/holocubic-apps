/* Independent Radio module. Codec allocations are PSRAM-only. */
#include "esp_audio_dec_default.h"
#include "esp_audio_simple_dec.h"
#include "esp_chip_info.h"
#include "esp_ts_dec.h"
#include "module_abi.h"
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/reent.h>

#define EXPORT __attribute__((visibility("default"), used))
#define PS (MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT)
#define INTERNAL (MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT)
#define RING (256u * 1024u)
#define INPUT 8192u
#define OUTPUT_MAX (512u * 1024u)
#define PCM 1024u
#define RATE 16000u
typedef struct {
  float b0, b1, b2, a1, a2, z1, z2;
} biquad;
typedef struct {
  module_host_api_v1 host;
  esp_audio_simple_dec_handle_t decoder;
  void *task, *i2s;
  uint8_t *ring, *input, *output;
  int16_t *pcm;
  volatile uint32_t wr, rd;
  volatile uint32_t stop, running, eos, paused, gain;
  uint32_t queued, output_cap, source_rate, source_channels, source_bits,
      bitrate;
  uint32_t status, error, underflows, decoded_frames, written_bytes,
      rejected_bytes;
  uint32_t baseline_internal, min_internal, start_ms;
  uint64_t busy_us;
  uint32_t phase;
  float previous;
  biquad low[2], eq[2];
  char format[8];
} Radio;
static const module_host_api_v1 *H;
static const module_manifest_t manifest = {MODULE_MANIFEST_MAGIC,
                                           MODULE_SDK_VERSION,
                                           sizeof(module_manifest_t),
                                           "radio",
                                           "0.1.0",
                                           "Independent PSRAM radio decoder",
                                           0,
                                           MODULE_BOOTSTRAP_ABI_VERSION};

/* Local allocator binding also catches malloc inside the static codec libs. */
void *malloc(size_t n) { return H ? H->heap.malloc(n, PS) : NULL; }
void *calloc(size_t n, size_t size) {
  return H ? H->heap.calloc(n, size, PS) : NULL;
}
void *realloc(void *p, size_t n) {
  return H ? H->heap.realloc(p, n, PS) : NULL;
}
void free(void *p) {
  if (H && p)
    H->heap.free(p);
}
void *memcpy(void *d, const void *s, size_t n) {
  uint8_t *a = d;
  const uint8_t *b = s;
  while (n--)
    *a++ = *b++;
  return d;
}
void *memmove(void *d, const void *s, size_t n) {
  uint8_t *a = d;
  const uint8_t *b = s;
  if (a < b)
    return memcpy(d, s, n);
  while (n) {
    --n;
    a[n] = b[n];
  }
  return d;
}
void *memset(void *d, int v, size_t n) {
  uint8_t *a = d;
  while (n--)
    *a++ = (uint8_t)v;
  return d;
}
size_t strlen(const char *s) {
  size_t n = 0;
  while (s[n])
    n++;
  return n;
}
char *strcpy(char *d, const char *s) {
  char *o = d;
  while ((*d++ = *s++))
    ;
  return o;
}
int strcmp(const char *a, const char *b) {
  while (*a && *a == *b) {
    a++;
    b++;
  }
  return (unsigned char)*a - (unsigned char)*b;
}
int strncmp(const char *a, const char *b, size_t n) {
  while (n--) {
    int d = (unsigned char)*a - (unsigned char)*b;
    if (d || !*a)
      return d;
    a++;
    b++;
  }
  return 0;
}
int memcmp(const void *a, const void *b, size_t n) {
  const uint8_t *x = a, *y = b;
  while (n--) {
    int d = *x++ - *y++;
    if (d)
      return d;
  }
  return 0;
}
uint32_t esp_log_timestamp(void) { return H ? H->time.millis() : 0; }
/* FLAC's callback-stream path only uses stdio for diagnostics/optional FILE
 * cleanup. No FILE input is exposed by this module. These are isolated from
 * host stdio. */
static struct _reent radio_reent;
struct _reent *__getreent(void) { return &radio_reent; }
int puts(const char *s) {
  if (H)
    H->serial.println(s);
  return 0;
}
int fprintf(FILE *f, const char *fmt, ...) {
  (void)f;
  (void)fmt;
  return 0;
}
size_t fwrite(const void *p, size_t s, size_t n, FILE *f) {
  (void)p;
  (void)s;
  (void)n;
  (void)f;
  return 0;
}
int fclose(FILE *f) {
  (void)f;
  return 0;
}
void esp_chip_info(esp_chip_info_t *p) {
  memset(p, 0, sizeof(*p));
  p->model = CHIP_ESP32S3;
  p->cores = 2;
  p->features =
      CHIP_FEATURE_WIFI_BGN | CHIP_FEATURE_BLE | CHIP_FEATURE_EMB_PSRAM;
}

static float sine(float x) {
  float q = x * x;
  return x * (1 - q / 6 + q * q / 120 - q * q * q / 5040 +
              q * q * q * q / 362880 - q * q * q * q * q / 39916800);
}
static float cosine(float x) {
  float q = x * x;
  return 1 - q / 2 + q * q / 24 - q * q * q / 720 + q * q * q * q / 40320 -
         q * q * q * q * q / 3628800;
}
static float filter(biquad *b, float x) {
  float y = b->b0 * x + b->z1;
  b->z1 = b->b1 * x - b->a1 * y + b->z2;
  b->z2 = b->b2 * x - b->a2 * y;
  return y;
}
static void lowpass(biquad *b, float rate, float q) {
  float w = 6.283185307f * 6500.0f / rate, c = cosine(w), a = sine(w) / (2 * q),
        d = 1 + a;
  memset(b, 0, sizeof(*b));
  b->b0 = (1 - c) / (2 * d);
  b->b1 = (1 - c) / d;
  b->b2 = b->b0;
  b->a1 = -2 * c / d;
  b->a2 = (1 - a) / d;
}
static void peak(biquad *b, float hz, float q, float A) {
  float w = 6.283185307f * hz / RATE, c = cosine(w), a = sine(w) / (2 * q),
        d = 1 + a / A;
  memset(b, 0, sizeof(*b));
  b->b0 = (1 + a * A) / d;
  b->b1 = -2 * c / d;
  b->b2 = (1 - a * A) / d;
  b->a1 = b->b1;
  b->a2 = (1 - a / A) / d;
}
static uint32_t used(Radio *r) {
  return __atomic_load_n(&r->wr, __ATOMIC_ACQUIRE) -
         __atomic_load_n(&r->rd, __ATOMIC_ACQUIRE);
}
static uint32_t take(Radio *r, uint8_t *p, uint32_t n) {
  uint32_t a = used(r);
  if (n > a)
    n = a;
  uint32_t pos = r->rd & (RING - 1), first = RING - pos;
  if (first > n)
    first = n;
  memcpy(p, r->ring + pos, first);
  memcpy(p + first, r->ring, n - first);
  __atomic_store_n(&r->rd, r->rd + n, __ATOMIC_RELEASE);
  return n;
}
static Radio *self(lua_State *L) {
  return H->lua.touserdata(L, H->lua.upvalue_index(1));
}
static int fail(lua_State *L, const char *s) {
  H->lua.pushnil(L);
  H->lua.pushstring(L, s);
  return 2;
}
static void num(lua_State *L, const char *k, int64_t v) {
  H->lua.pushinteger(L, v);
  H->lua.setfield(L, -2, k);
}
static void sample_memory(Radio *r) {
  uint32_t n = r->host.heap.free_size(INTERNAL);
  if (n < r->min_internal)
    r->min_internal = n;
}
static bool flush(Radio *r, uint32_t n) {
  size_t sent = 0;
  while (sent < n * 2 && !r->stop) {
    size_t w = 0;
    int err = r->host.i2s.write(r->i2s, (uint8_t *)r->pcm + sent, n * 2 - sent,
                                &w, 120);
    if (err != MODULE_OK) {
      r->error = 8;
      return false;
    }
    sent += w;
    r->written_bytes += w;
    if (!w)
      r->host.task.delay(10);
  }
  return !r->stop;
}
static bool start_i2s(Radio *r) {
  module_i2s_config_t c = {0};
  c.size = sizeof(c);
  c.mode = MODULE_I2S_MODE_TX;
  c.sample_rate = RATE;
  c.bits = 16;
  c.channels = 1;
  c.format = MODULE_I2S_FORMAT_I2S;
  c.channel_mode = MODULE_I2S_CHANNEL_MONO_LEFT;
  c.bclk_pin = c.ws_pin = c.din_pin = c.mclk_pin = -1;
  c.dout_pin = 48;
  c.dma_buf_count = 4;
  c.dma_buf_len = 256;
  c.flags = MODULE_I2S_FLAG_AUTO_CLEAR_TX;
  int err=r->host.i2s.begin(&c, &r->i2s);
  if(err!=MODULE_OK) r->error=600-err;
  return err==MODULE_OK;
}
static int32_t read_sample(const uint8_t *p, uint32_t bits) {
  if (bits == 16)
    return (int16_t)((uint32_t)p[0] | ((uint32_t)p[1] << 8));
  if (bits == 24) {
    int32_t v = (int32_t)((uint32_t)p[0] << 8 | ((uint32_t)p[1] << 16) |
                          ((uint32_t)p[2] << 24));
    return v >> 16;
  }
  if (bits == 32) {
    int32_t v = (int32_t)((uint32_t)p[0] | ((uint32_t)p[1] << 8) |
                          ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24));
    return v >> 16;
  }
  return ((int32_t)*p - 128) << 8;
}
static bool process_pcm(Radio *r, uint32_t bytes) {
  uint32_t step = r->source_channels * (r->source_bits / 8), count = 0;
  if (!step)
    return false;
  uint64_t t = r->host.time.micros();
  for (uint32_t pos = 0; pos + step <= bytes && !r->stop; pos += step) {
    float x = 0;
    for (uint32_t c = 0; c < r->source_channels; c++)
      x += (float)read_sample(r->output + pos + c * (r->source_bits / 8),
                              r->source_bits);
    x /= r->source_channels;
    if (r->source_rate > RATE) {
      x = filter(&r->low[0], x);
      x = filter(&r->low[1], x);
    }
    r->phase += RATE;
    while (r->phase >= r->source_rate) {
      r->phase -= r->source_rate;
      float f = 1 - (float)r->phase / RATE;
      float y = r->previous + (x - r->previous) * f;
      y = filter(&r->eq[0], y);
      y = filter(&r->eq[1], y);
      /* Twice the previous PCM amplitude (+6.02 dB), same 0..100 UI scale.
       * Keep saturation below int16 full scale; loud peaks cannot double. */
      y *= 1.12f * (float)r->gain / 100.0f;
      if (y > 31000)
        y = 31000;
      if (y < -31000)
        y = -31000;
      r->pcm[count++] = (int16_t)y;
      if (count == PCM) {
        r->busy_us += r->host.time.micros() - t;
        if (!flush(r, count))
          return false;
        count = 0;
        t = r->host.time.micros();
      }
    }
    r->previous = x;
  }
  r->busy_us += r->host.time.micros() - t;
  return !count || flush(r, count);
}
static void worker(void *p) {
  Radio *r = p;
  r->status = 1;
  uint32_t stall = 0;
  while (!r->stop) {
    if (r->paused) {
      r->host.task.delay(30);
      continue;
    }
    uint32_t got = take(r, r->input + r->queued, INPUT - r->queued);
    r->queued += got;
    if (!r->queued && !r->eos) {
      r->status = 1;
      r->underflows++;
      r->host.task.delay(10);
      continue;
    }
    if (!r->queued && r->eos) {
      r->status = 4;
      break;
    }
    esp_audio_simple_dec_raw_t in = {.buffer = r->input,
                                     .len = r->queued,
                                     .eos = r->eos && !used(r),
                                     .frame_recover =
                                         ESP_AUDIO_SIMPLE_DEC_RECOVERY_NONE};
    esp_audio_simple_dec_out_t out = {.buffer = r->output,
                                      .len = r->output_cap};
    uint64_t t = r->host.time.micros();
    int err = esp_audio_simple_dec_process(r->decoder, &in, &out);
    r->busy_us += r->host.time.micros() - t;
    sample_memory(r);
    if (err == ESP_AUDIO_ERR_BUFF_NOT_ENOUGH) {
      if (out.needed_size > OUTPUT_MAX) {
        r->error = 2;
        break;
      }
      void *n = realloc(r->output, out.needed_size);
      if (!n) {
        r->error = 3;
        break;
      }
      r->output = n;
      r->output_cap = out.needed_size;
      continue;
    }
    if (in.consumed > r->queued) {
      r->error = 4;
      break;
    }
    r->queued -= in.consumed;
    memmove(r->input, r->input + in.consumed, r->queued);
    if (out.decoded_size) {
      esp_audio_simple_dec_info_t info = {0};
      esp_audio_simple_dec_get_info(r->decoder, &info);
      if (!info.sample_rate || !info.channel || info.channel > 2 ||
          (info.bits_per_sample != 8 && info.bits_per_sample != 16 &&
           info.bits_per_sample != 24 && info.bits_per_sample != 32)) {
        r->error = 5;
        break;
      }
      if (info.sample_rate != r->source_rate) {
        r->source_rate = info.sample_rate;
        r->phase = 0;
        r->previous = 0;
        if (info.sample_rate > RATE) {
          lowpass(&r->low[0], info.sample_rate, 0.5411961f);
          lowpass(&r->low[1], info.sample_rate, 1.306563f);
        }
      }
      r->source_channels = info.channel;
      r->source_bits = info.bits_per_sample;
      r->bitrate = info.bitrate;
      if (!r->i2s && !start_i2s(r)) {
        break;
      }
      r->status = 2;
      r->decoded_frames++;
      if (!process_pcm(r, out.decoded_size))
        break;
      stall = 0;
    } else if (!in.consumed && !got) {
      if (r->queued == INPUT || r->eos) {
        if (++stall > 4) {
          r->error = 7;
          break;
        }
      }
      r->host.task.delay(10);
    }
    if (err != ESP_AUDIO_ERR_OK && err != ESP_AUDIO_ERR_DATA_LACK &&
        err != ESP_AUDIO_ERR_CONTINUE) {
      r->error = (uint32_t)(100 - err);
      break;
    }
    r->host.task.yield();
  }
  if (r->i2s) {
    r->host.i2s.mute(r->i2s);
    r->host.i2s.end(r->i2s);
    r->i2s = NULL;
  }
  if (r->decoder) {
    esp_audio_simple_dec_close(r->decoder);
    r->decoder = NULL;
  }
  if (r->error)
    r->status = 5;
  module_task_api_t task = r->host.task;
  __atomic_store_n(&r->running, 0, __ATOMIC_RELEASE);
  for (;;)
    task.delay(1000);
}
static bool stop(Radio *r) {
  r->stop = 1;
  uint32_t at = r->host.time.millis();
  while (__atomic_load_n(&r->running, __ATOMIC_ACQUIRE) &&
         r->host.time.millis() - at < 2000)
    r->host.task.delay(10);
  if (r->running)
    return false;
  if (r->task)
    r->host.task.remove(r->task);
  r->task = NULL;
  return true;
}
static int close_l(lua_State *L) {
  Radio *r = self(L);
  if (!stop(r))
    return fail(L, "worker still stopping");
  r->status = 0;
  r->error = 0;
  H->lua.pushboolean(L, 1);
  return 1;
}
static int open_l(lua_State *L) {
  Radio *r = self(L);
  const char *name = H->lua.checkstring(L, 1);
  esp_audio_simple_dec_type_t type = 0;
  if (!strcmp(name, "mp3"))
    type = ESP_AUDIO_SIMPLE_DEC_TYPE_MP3;
  else if (!strcmp(name, "aac"))
    type = ESP_AUDIO_SIMPLE_DEC_TYPE_AAC;
  else if (!strcmp(name, "flac"))
    type = ESP_AUDIO_SIMPLE_DEC_TYPE_FLAC;
  else if (!strcmp(name, "ts"))
    type = ESP_AUDIO_SIMPLE_DEC_TYPE_TS;
  else
    return fail(L, "unsupported codec");
  if (!stop(r))
    return fail(L, "worker still stopping");
  r->wr = r->rd = r->queued = r->eos = r->stop = r->paused = r->error =
      r->phase = r->decoded_frames = r->written_bytes = r->rejected_bytes =
          r->underflows = r->source_rate = 0;
  r->busy_us = 0;
  r->start_ms = H->time.millis();
  peak(&r->eq[0], 316.2278f, 1.0540926f, 1.3335214f);
  peak(&r->eq[1], 1341.6408f, 1.2196734f, 0.8659643f);
  strcpy(r->format, name);
  esp_aac_dec_cfg_t aac = ESP_AAC_DEC_CONFIG_DEFAULT();
  aac.aac_plus_enable = true;
  esp_ts_dec_cfg_t ts = {.aac_plus_enable = true};
  esp_audio_simple_dec_cfg_t c = {.dec_type = type};
  if (type == ESP_AUDIO_SIMPLE_DEC_TYPE_AAC) {
    c.dec_cfg = &aac;
    c.cfg_size = sizeof(aac);
  }
  if (type == ESP_AUDIO_SIMPLE_DEC_TYPE_TS) {
    c.dec_cfg = &ts;
    c.cfg_size = sizeof(ts);
  }
  int err = esp_audio_simple_dec_open(&c, &r->decoder);
  if (err)
    return fail(L, "codec open failed");
  r->running = 1;
  err = H->task.create("radio_decode", worker, r, 8192, 7, 1, &r->task);
  if (err) {
    r->running = 0;
    esp_audio_simple_dec_close(r->decoder);
    r->decoder = NULL;
    return fail(L, "worker creation failed");
  }
  H->lua.pushboolean(L, 1);
  return 1;
}
static int feed_l(lua_State *L) {
  Radio *r = self(L);
  size_t n;
  const char *p = H->lua.checklstring(L, 1, &n);
  if (!r->running)
    return fail(L, "decoder is not running");
  uint32_t available = RING - used(r);
  if (n > available) {
    return fail(L, "buffer full");
  }
  uint32_t pos = r->wr & (RING - 1), first = RING - pos;
  if (first > n)
    first = n;
  memcpy(r->ring + pos, p, first);
  memcpy(r->ring, p + first, n - first);
  __atomic_store_n(&r->wr, r->wr + n, __ATOMIC_RELEASE);
  H->lua.pushinteger(L, n);
  return 1;
}
static int eos_l(lua_State *L) {
  self(L)->eos = 1;
  return 0;
}
static int volume_l(lua_State *L) {
  int64_t v = H->lua.checkinteger(L, 1);
  if (v < 0)
    v = 0;
  if (v > 100)
    v = 100;
  self(L)->gain = v;
  return 0;
}
static int state_l(lua_State *L) {
  Radio *r = self(L);
  sample_memory(r);
  H->lua.newtable(L);
  num(L, "running", r->running);
  num(L, "status", r->status);
  num(L, "error", r->error);
  num(L, "buffer_bytes", used(r));
  num(L, "buffer_free", RING - used(r));
  num(L, "buffer_capacity", RING);
  num(L, "decoded_frames", r->decoded_frames);
  num(L, "written_bytes", r->written_bytes);
  num(L, "underflows", r->underflows);
  num(L, "source_rate", r->source_rate);
  num(L, "source_bits", r->source_bits);
  num(L, "output_rate", RATE);
  num(L, "bitrate", r->bitrate);
  num(L, "internal_free", H->heap.free_size(INTERNAL));
  num(L, "internal_peak_delta", r->baseline_internal - r->min_internal);
  num(L, "psram_free", H->heap.free_size(PS));
  uint32_t dt = H->time.millis() - r->start_ms;
  num(L, "worker_cpu_permille", dt ? r->busy_us / dt : 0);
  H->lua.pushstring(L, r->format);
  H->lua.setfield(L, -2, "codec");
  return 1;
}
static void bind(lua_State *L, Radio *r, const char *k,
                 module_lua_cfunction_t f) {
  H->lua.pushlightuserdata(L, r);
  H->lua.pushcclosure(L, f, 1);
  H->lua.setfield(L, -2, k);
}
EXPORT const module_manifest_t *module_query_v1(void) { return &manifest; }
EXPORT int32_t module_create_v2(module_host_resolve_v1_fn resolve, void *ctx,
                                const module_open_info_t *info, void **out) {
  (void)info;
  module_host_api_v1 h;
  *out = NULL;
  int e = module_sdk_resolve_host_v1(resolve, ctx, &h);
  if (e)
    return e;
  Radio *r = h.heap.calloc(1, sizeof(*r), PS);
  if (!r)
    return MODULE_ERR_NO_MEMORY;
  r->host = h;
  H = &r->host;
  r->baseline_internal = r->min_internal = h.heap.free_size(INTERNAL);
  r->ring = malloc(RING);
  r->input = malloc(INPUT);
  r->output_cap = 8192;
  r->output = malloc(r->output_cap);
  r->pcm = malloc(PCM * 2);
  r->gain = 25;
  if (!r->ring || !r->input || !r->output || !r->pcm) {
    free(r->ring);
    free(r->input);
    free(r->output);
    free(r->pcm);
    h.heap.free(r);
    H = NULL;
    return MODULE_ERR_NO_MEMORY;
  }
  if (esp_mp3_dec_register() || esp_aac_dec_register() ||
      esp_flac_dec_register() || esp_ts_dec_register()) {
    free(r->ring);
    free(r->input);
    free(r->output);
    free(r->pcm);
    h.heap.free(r);
    H = NULL;
    return MODULE_ERR_NO_MEMORY;
  }
  *out = r;
  return MODULE_OK;
}
EXPORT int32_t module_luaopen_v1(void *p, lua_State *L) {
  Radio *r = p;
  H = &r->host;
  H->lua.newtable(L);
  bind(L, r, "open", open_l);
  bind(L, r, "feed", feed_l);
  bind(L, r, "close", close_l);
  bind(L, r, "eos", eos_l);
  bind(L, r, "volume", volume_l);
  bind(L, r, "state", state_l);
  return MODULE_OK;
}
EXPORT void module_destroy_v1(void *p) {
  Radio *r = p;
  if (!stop(r))
    return;
  esp_ts_dec_unregister();
  esp_audio_dec_unregister(ESP_AUDIO_TYPE_MP3);
  esp_audio_dec_unregister(ESP_AUDIO_TYPE_AAC);
  esp_audio_dec_unregister(ESP_AUDIO_TYPE_FLAC);
  free(r->ring);
  free(r->input);
  free(r->output);
  free(r->pcm);
  module_heap_api_t heap = r->host.heap;
  heap.free(r);
  H = NULL;
}
