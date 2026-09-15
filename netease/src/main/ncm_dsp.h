#pragma once
#include <stdint.h>
typedef struct {float b0,b1,b2,a1,a2,z1,z2; int active;} ncm_biquad;
typedef struct {
  int gain10[5], hpf_hz, bass, mix1000, drive1000;
  int low_hz, high_hz, out_low_hz, out_high_hz;
} ncm_effects;
typedef struct {
  ncm_biquad eq[5], hpf, extract_hp, extract_lp, output_hp, output_lp;
  ncm_effects settings;
  float headroom, mix, drive;
  uint32_t rate, clipped;
} ncm_dsp;
void ncm_dsp_configure(ncm_dsp *d, const ncm_effects *s, uint32_t rate);
float ncm_dsp_sample(ncm_dsp *d,float x);
