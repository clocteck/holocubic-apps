/* Independent Music module. Codec allocations are PSRAM-only. */
#include "esp_audio_dec_default.h"
#include "esp_audio_simple_dec.h"
#include "esp_chip_info.h"
#include "qrcodegen.h"
#include "ncm_crypto.h"
#include "ncm_dsp.h"
#include "ncm_output.h"
#include "ncm_ring.h"
#include "ncm_image.h"
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
#define RING NCM_RING_CAPACITY
#define INPUT 8192u
#define OUTPUT_MAX 16384u
#define PCM 2048u
#define DMA_COUNT 6u
#define DMA_FRAMES 512u
typedef struct {
  module_host_api_v2 host;
  esp_audio_simple_dec_handle_t decoder;
  void *task, *i2s;
  uint8_t *ring, *input, *output;
  void *lua_result; /* Owned until Lua string copy succeeds; survives Lua OOM. */
  uint32_t read_pos,write_pos;
  int16_t *pcm;
  volatile uint32_t wr, rd;
  volatile uint32_t stop, running, eos, paused, gain;
  uint32_t queued, output_cap, source_rate, source_channels, source_bits,
      bitrate;
  uint32_t status, error, underflows, decoded_frames, written_bytes,
      rejected_bytes;
  uint32_t baseline_internal, min_internal, start_ms;
  uint64_t busy_us;

  char format[8];
  ncm_dsp dsp;
  ncm_effects effects;
  ncm_effects pending_effects;
  volatile uint32_t effects_pending; /* 0 idle, 1 Lua writing, 2 ready */
} Music;
static const module_host_api_v2 *H;
static int local_errno;
int *__errno(void) { return &local_errno; }
int abs(int x) { return x<0?-x:x; }
long labs(long x) { return x<0?-x:x; }
char *strchr(const char *s,int c) {
  do { if(*s==(char)c)return (char *)s; }while(*s++);
  return NULL;
}
static const module_manifest_t manifest = {MODULE_MANIFEST_MAGIC,
                                           MODULE_SDK_VERSION,
                                           sizeof(module_manifest_t),
                                           "qq_music",
                                           "1.0.0",
                                           "QQ Music PSRAM MP3 decoder",
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
static struct _reent ncm_music_reent;
struct _reent *__getreent(void) { return &ncm_music_reent; }
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

static uint32_t used(Music *r) {
  return __atomic_load_n(&r->wr, __ATOMIC_ACQUIRE) -
         __atomic_load_n(&r->rd, __ATOMIC_ACQUIRE);
}
static uint32_t take(Music *r, uint8_t *p, uint32_t n) {
  uint32_t a = used(r);
  if (n > a)
    n = a;
  r->read_pos=ncm_ring_read(r->ring,r->read_pos,p,n);
  __atomic_store_n(&r->rd, r->rd + n, __ATOMIC_RELEASE);
  return n;
}
static Music *self(lua_State *L) {
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
static void sample_memory(Music *r) {
  uint32_t n = r->host.heap.free_size(INTERNAL);
  uint32_t previous=__atomic_load_n(&r->min_internal,__ATOMIC_RELAXED);
  while(n<previous && !__atomic_compare_exchange_n(&r->min_internal,&previous,n,0,__ATOMIC_RELAXED,__ATOMIC_RELAXED)) {}
}
static bool flush(Music *r, uint32_t n) {
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
static bool start_i2s(Music *r) {
  module_i2s_config_t c = {0};
  c.size = sizeof(c);
  c.mode = MODULE_I2S_MODE_TX;
  c.sample_rate = r->source_rate;
  c.bits = 16;
  c.channels = 1;
  c.format = MODULE_I2S_FORMAT_I2S;
  c.channel_mode = MODULE_I2S_CHANNEL_MONO_LEFT;
  c.bclk_pin = c.ws_pin = c.din_pin = c.mclk_pin = -1;
  c.dout_pin = 48;
  c.dma_buf_count = DMA_COUNT;
  c.dma_buf_len = DMA_FRAMES;
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
static bool process_pcm(Music *r, uint32_t bytes) {
  uint32_t step = r->source_channels * (r->source_bits / 8), count = 0;
  if (!step) return false;
  const float normalization=1.0f/(32768.0f*r->source_channels);
  const float volume=ncm_output_gain(r->gain);
  uint64_t started=r->host.time.micros();
  for (uint32_t pos = 0; pos + step <= bytes && !r->stop; pos += step) {
    int32_t x = 0;
    for (uint32_t c=0; c<r->source_channels; ++c)
      x += read_sample(r->output + pos + c * (r->source_bits / 8), r->source_bits);
    float sample=(float)x * normalization;
    sample=ncm_dsp_sample(&r->dsp,sample);
    r->pcm[count++] = ncm_output_sample(sample,volume,&r->dsp.clipped);
    if (count == PCM) {
      r->busy_us+=r->host.time.micros()-started;
      if (!flush(r,count)) return false;
      count=0;started=r->host.time.micros();
    }
  }
  r->busy_us+=r->host.time.micros()-started;
  return !count || flush(r,count);
}
static void worker(void *p) {
  Music *r = p;
  r->status = 1;
  uint32_t stall = 0;
  while (!r->stop) {
    if(__atomic_load_n(&r->effects_pending,__ATOMIC_ACQUIRE)==2) {
      r->effects=r->pending_effects;
      __atomic_store_n(&r->effects_pending,0,__ATOMIC_RELEASE);
      if(r->source_rate)ncm_dsp_configure(&r->dsp,&r->effects,r->source_rate);
    }
    sample_memory(r);
    if (r->paused) {
      r->host.task.delay(30);
      continue;
    }
    if(!r->decoded_frames && !r->eos && used(r)<16384) {
      r->host.task.delay(10);continue;
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
      if (r->source_rate && info.sample_rate != r->source_rate) { r->error = 9; break; }
      if(!r->source_rate) ncm_dsp_configure(&r->dsp,&r->effects,info.sample_rate);
      r->source_rate = info.sample_rate;
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
static bool stop(Music *r) {
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
static void clear_lua_result(Music *r) {
  if (r->lua_result) {
    r->host.heap.free(r->lua_result);
    r->lua_result = NULL;
  }
}
static int close_l(lua_State *L) {
  Music *r = self(L);
  clear_lua_result(r);
  if (!stop(r))
    return fail(L, "worker still stopping");
  r->status = 0;
  r->error = 0;
  H->lua.pushboolean(L, 1);
  return 1;
}
static int open_l(lua_State *L) {
  Music *r = self(L);
  const char *name = H->lua.checkstring(L, 1);
  esp_audio_simple_dec_type_t type = 0;
  if (!strcmp(name, "mp3"))
    type = ESP_AUDIO_SIMPLE_DEC_TYPE_MP3;
  else
    return fail(L, "unsupported codec");
  if (!stop(r))
    return fail(L, "worker still stopping");
  if(__atomic_load_n(&r->effects_pending,__ATOMIC_ACQUIRE)==2) {
    r->effects=r->pending_effects;
    __atomic_store_n(&r->effects_pending,0,__ATOMIC_RELEASE);
  }
  r->read_pos=r->write_pos=0;
  r->wr = r->rd = r->queued = r->eos = r->stop = r->paused = r->error =
      r->decoded_frames = r->written_bytes = r->rejected_bytes =
          r->underflows = r->source_rate = 0;
  r->busy_us = 0;
  r->start_ms = H->time.millis();
  strcpy(r->format, name);
  esp_audio_simple_dec_cfg_t c = {.dec_type = type};
  int err = esp_audio_simple_dec_open(&c, &r->decoder);
  if (err)
    return fail(L, "codec open failed");
  r->running = 1;
  err = H->task.create("ncm_music_decode", worker, r, 8192, 7, 1, &r->task);
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
  Music *r = self(L);
  size_t n;
  const char *p = H->lua.checklstring(L, 1, &n);
  if (!r->running)
    return fail(L, "decoder is not running");
  uint32_t available = RING - used(r);
  if (n > available) {
    return fail(L, "buffer full");
  }
  r->write_pos=ncm_ring_write(r->ring,r->write_pos,(const uint8_t *)p,(uint32_t)n);
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
  Music *r = self(L);
  sample_memory(r);
  H->lua.newtable(L);
  num(L, "running", r->running);
  num(L, "status", r->status);
  num(L, "error", r->error);
  num(L, "buffer_bytes", used(r));
  num(L, "buffer_free", RING - used(r));
  num(L, "buffer_capacity", RING);
  num(L, "pcm_buffer_bytes", PCM*2);
  num(L, "dma_buf_count", DMA_COUNT);
  num(L, "dma_buf_frames", DMA_FRAMES);
  num(L, "decoded_frames", r->decoded_frames);
  num(L, "written_bytes", r->written_bytes);
  num(L, "underflows", r->underflows);
  num(L, "source_rate", r->source_rate);
  num(L, "source_bits", r->source_bits);
  num(L, "output_rate", r->source_rate);
  num(L, "paused", r->paused);
  num(L, "clipped_samples", r->dsp.clipped);
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

static int pause_l(lua_State *L) {
  self(L)->paused = H->lua.toboolean(L,1) ? 1 : 0; return 0;
}
static int baseline_l(lua_State *L) {
  Music *r=self(L);
  if(r->running)return fail(L,"baseline must be set before playback");
  int64_t value=H->lua.checkinteger(L,1);
  if(value<=0||value>1024*1024)return fail(L,"invalid internal heap baseline");
  r->baseline_internal=(uint32_t)value;
  r->min_internal=H->heap.free_size(INTERNAL);
  if(r->min_internal>r->baseline_internal)r->min_internal=r->baseline_internal;
  return 0;
}
/* Single-producer/single-consumer mailbox; worker applies at frame boundaries. */
static int effects_l(lua_State *L) {
  Music *r=self(L);
  ncm_effects s={0};
  for(int i=0;i<5;i++) {
    s.gain10[i]=(int)H->lua.checkinteger(L,i+1);
    if(s.gain10[i]<-60||s.gain10[i]>60)return fail(L,"EQ range is -6..6 dB");
  }
  s.hpf_hz=(int)H->lua.checkinteger(L,6);
  s.bass=H->lua.toboolean(L,7);
  s.mix1000=(int)H->lua.checkinteger(L,8);
  s.drive1000=(int)H->lua.checkinteger(L,9);
  s.low_hz=(int)H->lua.checkinteger(L,10);s.high_hz=(int)H->lua.checkinteger(L,11);
  s.out_low_hz=(int)H->lua.checkinteger(L,12);s.out_high_hz=(int)H->lua.checkinteger(L,13);
  if(s.hpf_hz<0||s.hpf_hz>300||s.mix1000<0||s.mix1000>250||
     s.drive1000<1000||s.drive1000>4000||s.low_hz<20||s.high_hz>300||
     s.low_hz>=s.high_hz||s.out_low_hz<50||s.out_high_hz>1200||s.out_low_hz>=s.out_high_hz)
    return fail(L,"invalid effect parameters");
  if(r->running) {
    uint32_t expected=0;
    if(!__atomic_compare_exchange_n(&r->effects_pending,&expected,1,0,__ATOMIC_ACQUIRE,__ATOMIC_RELAXED))
      return fail(L,"effect update pending; retry");
    r->pending_effects=s;
    __atomic_store_n(&r->effects_pending,2,__ATOMIC_RELEASE);
  } else {
    r->effects=s;
    __atomic_store_n(&r->effects_pending,0,__ATOMIC_RELEASE);
  }
  H->lua.pushboolean(L,1);return 1;
}
static int eapi_l(lua_State *L) {
  Music *r=self(L);clear_lua_result(r);
  size_t n; const char *path=H->lua.checkstring(L,1);
  const char *json=H->lua.checklstring(L,2,&n);
  if (strlen(path)>256 || n>32768) return fail(L,"request too large");
  char *body=ncm_eapi(path,json,n);
  if (!body) return fail(L,"EAPI allocation/encryption failed");
  r->lua_result=body;
  H->lua.pushstring(L,body);clear_lua_result(r);return 1;
}
static int weapi_l(lua_State *L) {
  Music *r=self(L);clear_lua_result(r);
  size_t n;const char *json=H->lua.checklstring(L,1,&n);
  char *body=ncm_weapi(json,n);
  if(!body)return fail(L,"WEAPI encoding failed");
  r->lua_result=body;
  H->lua.pushstring(L,body);clear_lua_result(r);return 1;
}
static int qr_l(lua_State *L) {
  Music *r=self(L);clear_lua_result(r);
  const char *text=H->lua.checkstring(L,1);
  if(strlen(text)>512) return fail(L,"QR payload too long");
  size_t cap=qrcodegen_BUFFER_LEN_FOR_VERSION(10);
  uint8_t *tmp=malloc(cap), *qr=malloc(cap);
  if(!tmp||!qr) {free(tmp);free(qr);return fail(L,"PSRAM required");}
  bool ok=qrcodegen_encodeText(text,tmp,qr,qrcodegen_Ecc_MEDIUM,1,10,qrcodegen_Mask_AUTO,true);
  if(!ok) {free(tmp);free(qr);return fail(L,"QR encode failed");}
  int size=qrcodegen_getSize(qr); char *pixels=malloc((size_t)size*size);
  if(!pixels){free(tmp);free(qr);return fail(L,"PSRAM required");}
  for(int y=0;y<size;y++) for(int x=0;x<size;x++) pixels[y*size+x]=qrcodegen_getModule(qr,x,y)?1:0;
  free(tmp);free(qr);
  r->lua_result=pixels;
  H->lua.pushinteger(L,size);H->lua.pushlstring(L,pixels,(size_t)size*size);
  clear_lua_result(r);return 2;
}
static int png_image_limit_l(lua_State *L,uint32_t limit) {
  _Static_assert(sizeof(ncm_image_dsc)==12,"LVGL 8 image ABI requires 32-bit pointers");
  size_t n;const uint8_t *raw=(const uint8_t *)H->lua.checklstring(L,1,&n);
  uint32_t header=ncm_png_header_limit(raw,n,limit);
  if(!header)return fail(L,"invalid PNG thumbnail or exceeds 96KiB");
  if(!H->lua.newuserdata)return fail(L,"host image userdata API unavailable");
  ncm_image_dsc *d=H->lua.newuserdata(L,sizeof(*d)+n);
  if(!d)return fail(L,"PNG userdata allocation failed");
  ncm_png_init(d,raw,n,header);
  return 1;
}
static int png_image_l(lua_State *L) { return png_image_limit_l(L,136); }
static int qr_image_l(lua_State *L) { return png_image_limit_l(L,512); }
static void bind(lua_State *L, Music *r, const char *k,
                 module_lua_cfunction_t f) {
  H->lua.pushlightuserdata(L, r);
  H->lua.pushcclosure(L, f, 1);
  H->lua.setfield(L, -2, k);
}
EXPORT const module_manifest_t *module_query_v1(void) { return &manifest; }
EXPORT int32_t module_create_v2(module_host_resolve_v2_fn resolve, void *ctx,
                                const module_open_info_t *info, void **out) {
  (void)info;
  module_host_api_v2 h;
  *out = NULL;
  int e = module_sdk_resolve_host_v2(resolve, ctx, &h);
  if (e)
    return e;
  Music *r = h.heap.calloc(1, sizeof(*r), PS);
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
  r->effects=(ncm_effects){{60,36,-14,-10,5},100,1,250,3500,50,180,120,600};
  if (!r->ring || !r->input || !r->output || !r->pcm) {
    free(r->ring);
    free(r->input);
    free(r->output);
    free(r->pcm);
    h.heap.free(r);
    H = NULL;
    return MODULE_ERR_NO_MEMORY;
  }
  if (esp_mp3_dec_register()) {
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
  Music *r = p;
  H = &r->host;
  H->lua.newtable(L);
  bind(L, r, "open", open_l);
  bind(L, r, "pause", pause_l);
  bind(L, r, "effects", effects_l);
  bind(L, r, "baseline", baseline_l);
  bind(L, r, "eapi", eapi_l);
  bind(L, r, "weapi", weapi_l);
  bind(L, r, "qr", qr_l);
  bind(L, r, "png_image", png_image_l);
  bind(L, r, "qr_image", qr_image_l);
  bind(L, r, "feed", feed_l);
  bind(L, r, "close", close_l);
  bind(L, r, "eos", eos_l);
  bind(L, r, "volume", volume_l);
  bind(L, r, "state", state_l);
  return MODULE_OK;
}
EXPORT void module_destroy_v1(void *p) {
  Music *r = p;
  while (!stop(r)) r->host.task.delay(10);
  clear_lua_result(r);
  esp_audio_dec_unregister(ESP_AUDIO_TYPE_MP3);
  free(r->ring);
  free(r->input);
  free(r->output);
  free(r->pcm);
  module_heap_api_t heap = r->host.heap;
  heap.free(r);
  H = NULL;
}
