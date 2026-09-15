#pragma once
#include <stdint.h>

/* Previous build used 2x base PCM gain. Double that at unchanged volume. */
static inline float ncm_output_gain(uint32_t volume) {
  return (32767.0f * 4.0f) * volume * 0.01f;
}
static inline int16_t ncm_output_sample(float sample, float gain, uint32_t *clipped) {
  float amplified = sample * gain;
  if (amplified > 32112.0f) { amplified = 32112.0f; ++*clipped; }
  if (amplified < -32112.0f) { amplified = -32112.0f; ++*clipped; }
  return (int16_t)amplified;
}
