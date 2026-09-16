"""Compile the actual native allocation/cleanup functions with a fault-injection host.
This tests module-owned memory, not ESP32 codec internals/TLS/firmware unloading.
Run on Windows with Visual Studio 2022 Professional installed.
"""
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'main/ncm_music.c'
BUILD = ROOT / 'build/memory-test'
VCVARS = Path(r'C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat')

PREFIX = r'''
#include <assert.h>
#include <setjmp.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "module_abi_types.h"
#include "ncm_dsp.h"
typedef void *esp_audio_simple_dec_handle_t;
#define EXPORT
#define PS (MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT)
#define INTERNAL (MODULE_HEAP_INTERNAL | MODULE_HEAP_8BIT)
#define RING (384u*1024u)
#define INPUT 8192u
#define PCM 2048u
#define ESP_AUDIO_TYPE_MP3 1
#define __ATOMIC_ACQUIRE 0
#define __atomic_load_n(p,order) (*(p))
#define qrcodegen_BUFFER_LEN_FOR_VERSION(v) 512
#define qrcodegen_Ecc_MEDIUM 0
#define qrcodegen_Mask_AUTO 0
static size_t live, blocks, calls, fail_at;
static int registry_fail, qr_fail, copy_fail, task_removed;
static uint32_t clock_ms;
static jmp_buf lua_error;
static void *registry;
static void *allocate(size_t n, uint32_t caps) {
  assert(caps==PS);calls++;
  if(fail_at && calls==fail_at)return NULL;
  size_t *p=malloc(sizeof(size_t)+n);assert(p);*p=n;
  live+=n;blocks++;return p+1;
}
static void release(void *v) {
  if(!v)return;
  size_t *p=(size_t *)v-1;assert(blocks && live>=*p);
  live-=*p;blocks--;free(p);
}
static void *zero_allocate(size_t n,size_t size,uint32_t caps) {
  void *p=allocate(n*size,caps);if(p)memset(p,0,n*size);return p;
}
static size_t free_size(uint32_t caps){return caps==PS?8000000-live:200000;}
static uint32_t millis(void){return clock_ms;}
static void delay(uint32_t ms){clock_ms+=ms;}
static void remove_task(void *p){assert(p);task_removed++;}
static const char *checkstring(lua_State *L,int n){return "test";}
static const char *checklstring(lua_State *L,int n,size_t *size){*size=4;return "test";}
static void pushstring(lua_State *L,const char *s){if(copy_fail)longjmp(lua_error,1);}
static void pushlstring(lua_State *L,const char *s,size_t n){if(copy_fail)longjmp(lua_error,1);}
static void pushinteger(lua_State *L,int64_t n){}
static void pushboolean(lua_State *L,int v){}
static int fail(lua_State *L,const char *message){return 2;}
static int esp_mp3_dec_register(void){
  if(registry_fail)return -1;
  registry=allocate(24,PS);return registry?0:-1;
}
static void esp_audio_dec_unregister(int type){release(registry);registry=NULL;}
static char *ncm_eapi(const char *path,const char *json,size_t n){
  char *p=allocate(128,PS);if(p)strcpy(p,"encoded");return p;
}
static char *ncm_weapi(const char *json,size_t n){return ncm_eapi("",json,n);}
static bool qrcodegen_encodeText(const char *text,void *tmp,void *qr,int a,int b,int c,int d,bool e){return !qr_fail;}
static int qrcodegen_getSize(void *qr){return 21;}
static bool qrcodegen_getModule(void *qr,int x,int y){return (x+y)%2;}
static module_host_api_v2 fake_host;
static int resolve_host(module_host_resolve_v2_fn f,void *ctx,module_host_api_v2 *out){
  *out=fake_host;return 0;
}
#define module_sdk_resolve_host_v2 resolve_host
static void *native_malloc(size_t n){return allocate(n,PS);}
'''
SUFFIX = r'''
int main(void) {
  fake_host.heap.malloc=allocate;fake_host.heap.calloc=zero_allocate;
  fake_host.heap.free=release;fake_host.heap.free_size=free_size;
  fake_host.time.millis=millis;fake_host.task.delay=delay;fake_host.task.remove=remove_task;
  fake_host.lua.checkstring=checkstring;fake_host.lua.checklstring=checklstring;
  fake_host.lua.pushstring=pushstring;fake_host.lua.pushlstring=pushlstring;
  fake_host.lua.pushinteger=pushinteger;fake_host.lua.pushboolean=pushboolean;
  /* Fail each of the five module allocations and registry allocation. */
  for(size_t at=1;at<=6;at++){
    calls=0;fail_at=at;void *out=(void *)1;
    assert(module_create_v2(NULL,NULL,NULL,&out)==MODULE_ERR_NO_MEMORY);
    assert(!out && !live && !blocks && !H);
  }
  fail_at=0;registry_fail=1;
  void *out=NULL;
  assert(module_create_v2(NULL,NULL,NULL,&out)==MODULE_ERR_NO_MEMORY);
  assert(!out && !live && !blocks && !H);
  registry_fail=0;
  int (*wrappers[])(lua_State *)={eapi_l,weapi_l,qr_l};
  for(int cycle=0;cycle<100;cycle++){
    assert(module_create_v2(NULL,NULL,NULL,&out)==MODULE_OK);
    current=out;size_t baseline=live,base_blocks=blocks;
    for(int i=0;i<3;i++){
      copy_fail=0;wrappers[i](NULL);assert(live==baseline && blocks==base_blocks);
      /* Lua OOM longjmps past C frees. Retained ownership must remain reachable. */
      copy_fail=1;
      if(setjmp(lua_error)==0){wrappers[i](NULL);assert(!"expected Lua allocation exception");}
      assert(current->lua_result && live>baseline);
      copy_fail=0;
      /* The next helper call also recovers interrupted output. */
      wrappers[i](NULL);assert(live==baseline && !current->lua_result);
      copy_fail=1;
      if(setjmp(lua_error)==0){wrappers[i](NULL);assert(0);}
      copy_fail=0;
      close_l(NULL);close_l(NULL);
      assert(live==baseline && blocks==base_blocks && !current->lua_result);
    }
    for(size_t at=1;at<=3;at++){
      fail_at=calls+at;qr_l(NULL);fail_at=0;assert(live==baseline);
    }
    qr_fail=1;qr_l(NULL);qr_fail=0;assert(live==baseline);
    /* A timed-out worker must not be deleted or lose its live buffers. */
    current->running=1;current->task=(void *)1;
    int removed=task_removed;
    assert(!stop(current) && task_removed==removed && live==baseline);
    current->running=0;
    copy_fail=1;
    if(setjmp(lua_error)==0){eapi_l(NULL);assert(0);}
    copy_fail=0;
    module_destroy_v1(out);current=NULL;
    assert(task_removed==removed+1 && !live && !blocks && !H && !registry);
  }
  puts("Native memory checks passed: 100 create/destroy cycles, allocation failures, Lua OOM recovery, stop timeout.");
  return 0;
}
'''

def main():
    source=SOURCE.read_text(encoding='utf-8')
    # Compile these exact production functions; mocks only replace platform/codec APIs.
    def function(name):
        pattern=r'^(?:static|EXPORT) [A-Za-z0-9_* ]+\b'+name+r'\([^{};]*\)\s*\{'
        match=re.search(pattern,source,re.M)
        if not match: raise AssertionError(name)
        end=source.index('\n}',match.end())+2
        return source[match.start():end]
    structure=source[source.index('typedef struct {'):source.index('} Music;')+8]
    functions='\n'.join(function(name) for name in (
        'stop','clear_lua_result','close_l','eapi_l','weapi_l','qr_l',
        'module_create_v2','module_destroy_v1'))
    functions=re.sub(r'(?<![.\w])malloc\(', 'native_malloc(', functions)
    functions=re.sub(r'(?<![.\w])free\(', 'release(', functions)
    generated=PREFIX+structure+r'''
static const module_host_api_v2 *H;
static Music *current;
static Music *self(lua_State *L){return current;}
'''+functions+SUFFIX
    BUILD.mkdir(parents=True,exist_ok=True)
    # Use real host types, excluding the GCC-only inline resolver (mocked above).
    abi=(ROOT/'main/module_abi.h').read_text(encoding='utf-8')
    abi=abi[:abi.index('static inline int32_t module_sdk_resolve_required_v2')]
    (BUILD/'module_abi_types.h').write_text(abi,encoding='utf-8')
    test_file=BUILD/'native_memory.c'
    test_file.write_text(generated,encoding='utf-8')
    command=f'call "{VCVARS}" >nul && cl /nologo /std:c11 /Od /I"{ROOT / "main"}" "{test_file}" /Fe:native_memory.exe'
    subprocess.run(command,shell=True,cwd=BUILD,check=True)
    subprocess.run([str(BUILD/'native_memory.exe')],cwd=BUILD,check=True)

if __name__=='__main__': main()
