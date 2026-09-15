#pragma once
#include <stdint.h>
#include <string.h>
#define NCM_RING_CAPACITY (384u * 1024u)
/* Separate physical positions from wrapping uint32 byte counters. */
static inline uint32_t ncm_ring_write(uint8_t *ring,uint32_t pos,const uint8_t *src,uint32_t n) {
  uint32_t first=NCM_RING_CAPACITY-pos;
  if(first>n)first=n;
  memcpy(ring+pos,src,first);memcpy(ring,src+first,n-first);
  pos+=n;return pos>=NCM_RING_CAPACITY?pos-NCM_RING_CAPACITY:pos;
}
static inline uint32_t ncm_ring_read(const uint8_t *ring,uint32_t pos,uint8_t *dst,uint32_t n) {
  uint32_t first=NCM_RING_CAPACITY-pos;
  if(first>n)first=n;
  memcpy(dst,ring+pos,first);memcpy(dst+first,ring,n-first);
  pos+=n;return pos>=NCM_RING_CAPACITY?pos-NCM_RING_CAPACITY:pos;
}
