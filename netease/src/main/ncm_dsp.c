#include "ncm_dsp.h"
#include <math.h>
#include <string.h>
static float clip(float x,float a,float b){return x<a?a:x>b?b:x;}
static void setup(ncm_biquad *b,float rate,float hz,float db,int kind) {
  memset(b,0,sizeof(*b));
  if(hz<=0 || (kind==0 && db==0)) return;
  float w=6.283185307179586f*clip(hz,10,rate*0.45f)/rate;
  float c=cosf(w), a=sinf(w)/(2*0.70710678f), A=powf(10,db/40), den;
  if(kind==0) {
    a=sinf(w)/2; den=1+a/A;
    b->b0=(1+a*A)/den;b->b1=-2*c/den;b->b2=(1-a*A)/den;
    b->a1=b->b1;b->a2=(1-a/A)/den;
  } else {
    den=1+a;float n=kind==1?(1+c):(1-c);
    b->b0=n/(2*den);b->b1=(kind==1?-n:n)/den;b->b2=b->b0;
    b->a1=-2*c/den;b->a2=(1-a)/den;
  }
  b->active=1;
}
static inline float run(ncm_biquad *b,float x){
  if(!b->active)return x;
  float y=b->b0*x+b->z1;
  b->z1=b->b1*x-b->a1*y+b->z2;b->z2=b->b2*x-b->a2*y;
  return y;
}
void ncm_dsp_configure(ncm_dsp *d,const ncm_effects *s,uint32_t rate) {
  static const float hz[5]={180,420,1000,2500,4300};
  memset(d,0,sizeof(*d));d->settings=*s;d->rate=rate;
  float boost=0;
  for(int i=0;i<5;i++){
    float db=clip(s->gain10[i]*0.1f,-6,6);
    if(db>0)boost+=db;
    setup(&d->eq[i],rate,hz[i],db,0);
  }
  setup(&d->hpf,rate,s->hpf_hz,0,1);
  d->mix=s->bass?clip(s->mix1000*0.001f,0,0.25f):0;
  d->drive=clip(s->drive1000*0.001f,1,4);
  /* Conservative pre-gain prevents summed positive EQ gains from clipping. */
  d->headroom=powf(10,-boost/20)/(1+2*d->mix);
  if(d->mix>0){
    setup(&d->extract_hp,rate,s->low_hz,0,1);
    setup(&d->extract_lp,rate,s->high_hz,0,2);
    setup(&d->output_hp,rate,s->out_low_hz,0,1);
    setup(&d->output_lp,rate,s->out_high_hz,0,2);
  }
}
float ncm_dsp_sample(ncm_dsp *d,float x){
  x*=d->headroom;float bass=0;
  if(d->mix>0){
    float low=clip(run(&d->extract_lp,run(&d->extract_hp,x))*d->drive,-1,1);
    /* Rectification + cubic harmonics; no per-sample transcendentals. */
    bass=run(&d->output_lp,run(&d->output_hp,fabsf(low)*1.2f+low*low*low*3.2f))*d->mix;
  }
  float y=run(&d->hpf,x);
  for(int i=0;i<5;i++)y=run(&d->eq[i],y);
  y+=bass;
  if(y>0.98f||y< -0.98f)d->clipped++;
  return clip(y,-0.98f,0.98f);
}
