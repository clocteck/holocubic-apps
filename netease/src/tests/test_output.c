#include "ncm_output.h"
#include "ncm_ring.h"
#include "ncm_image.h"
uint32_t ncm_test_png_header(const uint8_t *raw,size_t size) { return ncm_png_header(raw,size); }
void ncm_test_png_init(ncm_image_dsc *d,const uint8_t *raw,size_t size,uint32_t header) {
  ncm_png_init(d,raw,size,header);
}
uint32_t ncm_test_ring_write(uint8_t *ring,uint32_t pos,const uint8_t *src,uint32_t n) {
  return ncm_ring_write(ring,pos,src,n);
}
uint32_t ncm_test_ring_read(const uint8_t *ring,uint32_t pos,uint8_t *dst,uint32_t n) {
  return ncm_ring_read(ring,pos,dst,n);
}
float ncm_test_output_gain(uint32_t volume) { return ncm_output_gain(volume); }
int16_t ncm_test_output_sample(float sample, uint32_t volume, uint32_t *clipped) {
  return ncm_output_sample(sample,ncm_output_gain(volume),clipped);
}
