#pragma once
#include <stddef.h>
#include <stdint.h>
#include <string.h>

/* LVGL 8 little-endian image ABI: cf[0:4], w[10:20], h[21:31].
 * Keep the compressed bytes inside the same full userdata as this descriptor;
 * the host UI owns a registry reference for the complete source lifetime. */
typedef struct {
  uint32_t header, data_size;
  const uint8_t *data;
} ncm_image_dsc;

static inline uint32_t ncm_image_be32(const uint8_t *p) {
  return ((uint32_t)p[0]<<24)|((uint32_t)p[1]<<16)|((uint32_t)p[2]<<8)|p[3];
}
static inline uint32_t ncm_png_header(const uint8_t *p,size_t n) {
  static const uint8_t signature[]={137,80,78,71,13,10,26,10};
  if(!p||n<45||n>96u*1024u||memcmp(p,signature,8)||
     ncm_image_be32(p+8)!=13||memcmp(p+12,"IHDR",4))return 0;
  uint32_t w=ncm_image_be32(p+16),h=ncm_image_be32(p+20);
  if(!w||!h||w>136||h>136)return 0;
  size_t at=8;int data=0;
  while(n-at>=12) {
    uint32_t len=ncm_image_be32(p+at);
    if(len>n-at-12)return 0;
    if(!memcmp(p+at+4,"IHDR",4)&&at!=8)return 0;
    if(!memcmp(p+at+4,"IDAT",4))data=1;
    if(!memcmp(p+at+4,"IEND",4))
      return !len&&at+12==n&&data ? 2u|(w<<10)|(h<<21) : 0;
    at+=(size_t)len+12;
  }
  return 0;
}
static inline void ncm_png_init(ncm_image_dsc *d,const uint8_t *raw,size_t n,uint32_t header) {
  d->header=header;d->data_size=(uint32_t)n;d->data=(uint8_t *)(d+1);
  memcpy((void *)d->data,raw,n);
}
