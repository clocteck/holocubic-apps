#pragma once
#include <stdint.h>
#include <math.h>
#include <string.h>

/* Two-block lookahead, three rotating blocks. Storage belongs to Music
   (PSRAM); no allocations or transcendental functions in the sample loop. */
#define NCM_LIMIT_BLOCK 128
#define NCM_OUTPUT_DELAY (2*NCM_LIMIT_BLOCK)
#define NCM_OUTPUT_CEILING 0.96f
typedef struct {
  float dry[NCM_LIMIT_BLOCK],bass[NCM_LIMIT_BLOCK];
  float dry_target,bass_target;
} ncm_output_block;
typedef struct {
  ncm_output_block blocks[3];
  unsigned write_block,position,ready;
  float dry_start,dry_end,bass_start,bass_end;
  float dry_target,bass_target,release;
  uint32_t clipped,limited,bass_limited;
} ncm_output;

static inline float ncm_output_min(float a,float b){return a<b?a:b;}
static inline float ncm_output_gain(uint32_t volume) {
  /* Preserve the existing volume curve; protection happens AFTER this gain. */
  return 4.0f * (volume>100?100:volume) * 0.01f;
}
static inline void ncm_output_init(ncm_output *o,uint32_t rate){
  memset(o,0,sizeof(*o));
  o->dry_target=o->bass_target=1;
  o->dry_start=o->dry_end=o->bass_start=o->bass_end=1;
  o->release=1-expf(-(float)NCM_LIMIT_BLOCK/(0.080f*rate));
  for(int i=0;i<3;i++)o->blocks[i].dry_target=o->blocks[i].bass_target=1;
}
static inline void ncm_output_prepare(ncm_output *o){
  ncm_output_block *b=&o->blocks[o->write_block];
  float peak=0;
  for(int i=0;i<NCM_LIMIT_BLOCK;i++){
    float a=fabsf(b->dry[i]);if(a>peak)peak=a;
  }
  /* This target depends ONLY on dry. Enabling bass cannot duck the vocal. */
  float dg=peak>NCM_OUTPUT_CEILING?NCM_OUTPUT_CEILING/peak:1;
  dg=ncm_output_min(dg,o->dry_target+(1-o->dry_target)*o->release);
  float bg=1;
  for(int i=0;i<NCM_LIMIT_BLOCK;i++){
    float wet=b->bass[i],a=fabsf(wet);
    if(a>0.0000001f){
      /* Bound for ANY dry gain in [0,dg]. Opposite-polarity bass gets more
         room, but never depends on cancellation to remain safe. */
      float aligned=wet>0?b->dry[i]*dg:-b->dry[i]*dg;
      float room=NCM_OUTPUT_CEILING-(aligned>0?aligned:0);
      bg=ncm_output_min(bg,(room>0?room:0)/a);
    }
  }
  bg=ncm_output_min(bg,o->bass_target+(1-o->bass_target)*o->release);
  b->dry_target=dg;b->bass_target=bg;
  o->dry_target=dg;o->bass_target=bg;

  unsigned current=(o->write_block+2)%3;
  ncm_output_block *c=&o->blocks[current];
  /* Endpoints both <= current block's safe targets; linear interpolation
     therefore stays safe, with continuous gain across block boundaries. */
  o->dry_start=o->dry_end;o->bass_start=o->bass_end;
  o->dry_end=ncm_output_min(c->dry_target,dg);
  o->bass_end=ncm_output_min(c->bass_target,bg);
  o->write_block=(o->write_block+1)%3;
  if(o->ready<2)o->ready++;
}
static inline int16_t ncm_output_sample(ncm_output *o,float dry,float bass,float volume){
  unsigned p=o->position;
  ncm_output_block *w=&o->blocks[o->write_block];
  w->dry[p]=dry*volume;w->bass[p]=bass*volume;
  float y=0;
  if(o->ready==2){
    ncm_output_block *b=&o->blocks[(o->write_block+1)%3];
    float t=(p+1)*(1.0f/NCM_LIMIT_BLOCK);
    float dg=o->dry_start+(o->dry_end-o->dry_start)*t;
    float bg=o->bass_start+(o->bass_end-o->bass_start)*t;
    y=b->dry[p]*dg+b->bass[p]*bg;
    if(dg<0.9999f && fabsf(b->dry[p])>0.000001f)o->limited++;
    if(bg<0.9999f && fabsf(b->bass[p])>0.000001f)o->bass_limited++;
  }
  if(++o->position==NCM_LIMIT_BLOCK){o->position=0;ncm_output_prepare(o);}
  /* Emergency guard, not the normal limiter. Tests require zero guard hits. */
  if(y>0.98f){y=0.98f;o->clipped++;}
  if(y< -0.98f){y=-0.98f;o->clipped++;}
  return (int16_t)(y*32767.0f);
}
