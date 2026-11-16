#pragma once
#include <stdint.h>
#include <math.h>
#include <string.h>

/* Two-block lookahead, three rotating blocks. Storage belongs to audio_instance
   (PSRAM preferred); no allocations or transcendental functions in the sample loop. */
#define AUDIO_PEAK_LIMIT_BLOCK 128
#define AUDIO_PEAK_OUTPUT_DELAY (2*AUDIO_PEAK_LIMIT_BLOCK)
#define AUDIO_PEAK_OUTPUT_CEILING 0.96f
typedef struct {
  float dry[AUDIO_PEAK_LIMIT_BLOCK],bass[AUDIO_PEAK_LIMIT_BLOCK];
  float dry_target,bass_target,ceiling;
} audio_peak_block;
typedef struct {
  audio_peak_block blocks[3];
  unsigned write_block,position,ready;
  float dry_start,dry_end,bass_start,bass_end;
  float dry_target,bass_target,release;
  uint32_t clipped,limited,bass_limited;
} audio_peak;

static inline float audio_peak_min(float a,float b){return a<b?a:b;}
static inline float audio_peak_abs(float x){return x<0?-x:x;}
static inline void audio_peak_init(audio_peak *o,uint32_t rate){
  memset(o,0,sizeof(*o));
  o->dry_target=o->bass_target=1;
  o->dry_start=o->dry_end=o->bass_start=o->bass_end=1;
  o->release=1-powf(2.0f,-1.442695041f*AUDIO_PEAK_LIMIT_BLOCK/(0.080f*rate));
  for(int i=0;i<3;i++){
    o->blocks[i].dry_target=o->blocks[i].bass_target=1;
    o->blocks[i].ceiling=AUDIO_PEAK_OUTPUT_CEILING;
  }
}
static inline void audio_peak_prepare(audio_peak *o){
  audio_peak_block *b=&o->blocks[o->write_block];
  float peak=0;
  for(int i=0;i<AUDIO_PEAK_LIMIT_BLOCK;i++){
    float a=audio_peak_abs(b->dry[i]);if(a>peak)peak=a;
  }
  /* This target depends ONLY on dry. Enabling bass cannot duck the vocal. */
  float dg=peak>b->ceiling?b->ceiling/peak:1;
  dg=audio_peak_min(dg,o->dry_target+(1-o->dry_target)*o->release);
  float bg=1;
  for(int i=0;i<AUDIO_PEAK_LIMIT_BLOCK;i++){
    float wet=b->bass[i],a=audio_peak_abs(wet);
    if(a>0.0000001f){
      /* Bound for ANY dry gain in [0,dg]. Opposite-polarity bass gets more
         room, but never depends on cancellation to remain safe. */
      float aligned=wet>0?b->dry[i]*dg:-b->dry[i]*dg;
      float room=b->ceiling-(aligned>0?aligned:0);
      bg=audio_peak_min(bg,(room>0?room:0)/a);
    }
  }
  bg=audio_peak_min(bg,o->bass_target+(1-o->bass_target)*o->release);
  b->dry_target=dg;b->bass_target=bg;
  o->dry_target=dg;o->bass_target=bg;

  unsigned current=(o->write_block+2)%3;
  audio_peak_block *c=&o->blocks[current];
  /* Endpoints both <= current block's safe targets; linear interpolation
     therefore stays safe, with continuous gain across block boundaries. */
  o->dry_start=o->dry_end;o->bass_start=o->bass_end;
  o->dry_end=audio_peak_min(c->dry_target,dg);
  o->bass_end=audio_peak_min(c->bass_target,bg);
  o->write_block=(o->write_block+1)%3;
  o->blocks[o->write_block].ceiling=AUDIO_PEAK_OUTPUT_CEILING;
  if(o->ready<2)o->ready++;
}
static inline int16_t audio_peak_sample(audio_peak *o,float dry,float bass,float volume,float ceiling){
  unsigned p=o->position;
  audio_peak_block *w=&o->blocks[o->write_block];
  w->ceiling=audio_peak_min(w->ceiling,ceiling);
  w->dry[p]=dry*volume;w->bass[p]=bass*volume;
  float y=0;
  if(o->ready==2){
    audio_peak_block *b=&o->blocks[(o->write_block+1)%3];
    float t=(p+1)*(1.0f/AUDIO_PEAK_LIMIT_BLOCK);
    float dg=o->dry_start+(o->dry_end-o->dry_start)*t;
    float bg=o->bass_start+(o->bass_end-o->bass_start)*t;
    y=b->dry[p]*dg+b->bass[p]*bg;
    if(dg<0.9999f && audio_peak_abs(b->dry[p])>0.000001f)o->limited++;
    if(bg<0.9999f && audio_peak_abs(b->bass[p])>0.000001f)o->bass_limited++;
  }
  if(++o->position==AUDIO_PEAK_LIMIT_BLOCK){o->position=0;audio_peak_prepare(o);}
  /* Emergency guard, not the normal limiter. Tests require zero guard hits. */
  if(y>0.98f){y=0.98f;o->clipped++;}
  if(y< -0.98f){y=-0.98f;o->clipped++;}
  return (int16_t)(y*32767.0f);
}
