/* Host-only bridge: compile the production DSP/output code, not a simulation. */
#include "ncm_dsp.h"
#include "ncm_output.h"
#include <stdlib.h>
#ifdef _WIN32
#define API __declspec(dllexport)
#else
#define API
#endif
API void process(const float *input,float *dry,float *bass,float *output,
                 int length,int rate,const ncm_effects *settings,int volume,
                 int toggle_at,uint32_t *stats){
  ncm_dsp d={0};ncm_output o;
  ncm_effects s=*settings;
  ncm_dsp_configure(&d,&s,rate);ncm_output_init(&o,rate);
  for(int i=0;i<length+NCM_OUTPUT_DELAY;i++){
    if(i==toggle_at){s.bass=!s.bass;ncm_dsp_configure(&d,&s,rate);}
    float b=0,y=0;
    if(i<length){y=ncm_dsp_sample(&d,input[i],&b);dry[i]=y;bass[i]=b;}
    int16_t pcm=ncm_output_sample(&o,y,b,ncm_output_gain(volume));
    if(i>=NCM_OUTPUT_DELAY)output[i-NCM_OUTPUT_DELAY]=pcm/32767.0f;
  }
  stats[0]=o.clipped;stats[1]=o.limited;stats[2]=o.bass_limited;
}
API void protect(const float *dry,const float *bass,float *output,int length,
                 int rate,int volume,uint32_t *stats){
  ncm_output o;ncm_output_init(&o,rate);
  for(int i=0;i<length+NCM_OUTPUT_DELAY;i++){
    int16_t pcm=ncm_output_sample(&o,i<length?dry[i]:0,i<length?bass[i]:0,ncm_output_gain(volume));
    if(i>=NCM_OUTPUT_DELAY)output[i-NCM_OUTPUT_DELAY]=pcm/32767.0f;
  }
  stats[0]=o.clipped;stats[1]=o.limited;stats[2]=o.bass_limited;
}
API int output_state_bytes(void){return sizeof(ncm_output);}
