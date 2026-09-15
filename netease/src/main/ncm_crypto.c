#include "ncm_crypto.h"
#include "mbedtls/aes.h"
#include "mbedtls/md5.h"
#include <stdlib.h>
#include <string.h>
static char *cbc_base64(const char *text,size_t length,const unsigned char *key) {
  static const char b64[]="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  size_t total=(length/16+1)*16;
  unsigned char *buf=malloc(total);
  char *encoded=malloc(4*((total+2)/3)+1);
  if(!buf||!encoded){free(buf);free(encoded);return NULL;}
  memcpy(buf,text,length);memset(buf+length,(int)(total-length),total-length);
  unsigned char previous[16]="0102030405060708";
  mbedtls_aes_context aes;mbedtls_aes_init(&aes);
  int error=mbedtls_aes_setkey_enc(&aes,key,128);
  for(size_t i=0;i<total&&!error;i+=16){
    for(int j=0;j<16;j++)buf[i+j]^=previous[j];
    error=mbedtls_aes_crypt_ecb(&aes,MBEDTLS_AES_ENCRYPT,buf+i,buf+i);
    memcpy(previous,buf+i,16);
  }
  mbedtls_aes_free(&aes);
  if(error){free(buf);free(encoded);return NULL;}
  size_t out=0;
  for(size_t i=0;i<total;i+=3){
    unsigned value=(unsigned)buf[i]<<16;
    if(i+1<total)value|=(unsigned)buf[i+1]<<8;
    if(i+2<total)value|=buf[i+2];
    encoded[out++]=b64[(value>>18)&63];encoded[out++]=b64[(value>>12)&63];
    encoded[out++]=i+1<total?b64[(value>>6)&63]:'=';
    encoded[out++]=i+2<total?b64[value&63]:'=';
  }
  encoded[out]=0;free(buf);return encoded;
}
char *ncm_weapi(const char *json,size_t length) {
  /* WEAPI is protocol obfuscation, not our security boundary. HTTPS protects
   * credentials. Precomputed RSA of this fixed public protocol key avoids
   * linking a bignum/RNG implementation solely for WEAPI. */
  static const char rsa[]="d02957401fb29f9f5882f22abee24302f6efbafc801d1339354b6f41885845d9831cef432bd51f2fcc0d69774cb3e79ba68bb51e9365819a6c23f5b7840bb99a57f82614effb7a7f8819500e705a06343786bf2f0d4843fe57c771796aab3133d297056d84efef0ecb7295f65b350d2e5f00929fb9e0f5753dc8b25d9dab15eb";
  static const char hex[]="0123456789ABCDEF";
  if(!json||length>32768)return NULL;
  char *first=cbc_base64(json,length,(const unsigned char *)"0CoJUm6Qyw8W8jud");
  if(!first)return NULL;
  char *second=cbc_base64(first,strlen(first),(const unsigned char *)"CubicMusic2026S3");
  free(first);if(!second)return NULL;
  size_t n=strlen(second);char *body=malloc(7+n*3+11+sizeof(rsa));
  if(!body){free(second);return NULL;}
  memcpy(body,"params=",7);size_t at=7;
  for(size_t i=0;i<n;i++){
    unsigned char c=(unsigned char)second[i];
    if(c=='+'||c=='/'||c=='='){body[at++]='%';body[at++]=hex[c>>4];body[at++]=hex[c&15];}
    else body[at++]=(char)c;
  }
  memcpy(body+at,"&encSecKey=",11);at+=11;
  memcpy(body+at,rsa,sizeof(rsa));free(second);return body;
}
char *ncm_eapi(const char *path, const char *json, size_t length) {
  static const char sep[]="-36cd479b6b5-";
  static const unsigned char key[]="e82ckenh8dichen8";
  static const char hex[]="0123456789ABCDEF", lower[]="0123456789abcdef";
  if (!path || !json || length>32768) return NULL;
  size_t plen=strlen(path);
  if(plen>256) return NULL;
  mbedtls_md5_context md;
  unsigned char digest[16];
  mbedtls_md5_init(&md);
  int err=mbedtls_md5_starts(&md);
  err|=mbedtls_md5_update(&md,(const unsigned char *)"nobody",6);
  err|=mbedtls_md5_update(&md,(const unsigned char *)path,plen);
  err|=mbedtls_md5_update(&md,(const unsigned char *)"use",3);
  err|=mbedtls_md5_update(&md,(const unsigned char *)json,length);
  err|=mbedtls_md5_update(&md,(const unsigned char *)"md5forencrypt",13);
  err|=mbedtls_md5_finish(&md,digest);
  mbedtls_md5_free(&md);
  if(err) return NULL;
  size_t plain=plen+length+2*(sizeof(sep)-1)+32, total=(plain/16+1)*16;
  unsigned char *buf=malloc(total);
  char *form=malloc(8+total*2);
  if(!buf||!form){free(buf);free(form);return NULL;}
  size_t at=0;
  memcpy(buf+at,path,plen);at+=plen;
  memcpy(buf+at,sep,sizeof(sep)-1);at+=sizeof(sep)-1;
  memcpy(buf+at,json,length);at+=length;
  memcpy(buf+at,sep,sizeof(sep)-1);at+=sizeof(sep)-1;
  for(int i=0;i<16;i++){buf[at++]=lower[digest[i]>>4];buf[at++]=lower[digest[i]&15];}
  memset(buf+at,(int)(total-plain),total-plain);
  mbedtls_aes_context aes;
  mbedtls_aes_init(&aes);
  err=mbedtls_aes_setkey_enc(&aes,key,128);
  for(size_t i=0;i<total&&!err;i+=16) err=mbedtls_aes_crypt_ecb(&aes,MBEDTLS_AES_ENCRYPT,buf+i,buf+i);
  mbedtls_aes_free(&aes);
  if(err){free(buf);free(form);return NULL;}
  memcpy(form,"params=",7);
  for(size_t i=0;i<total;i++){form[7+2*i]=hex[buf[i]>>4];form[8+2*i]=hex[buf[i]&15];}
  form[7+2*total]=0;
  volatile unsigned char *wipe=buf;for(size_t i=0;i<total;i++)wipe[i]=0;
  free(buf);return form;
}
