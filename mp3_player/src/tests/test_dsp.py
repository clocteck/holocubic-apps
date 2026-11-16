"""Build actual Music DSP/filter/PCM/EOF functions with a host decoder stub.
Uses the shipped scalar esp-dsp biquad reference and the module's math approximations.
Does not claim to run the ESP32-S3 vector assembly or MP3/WAV codec on the host.
"""
import ctypes as C
import math
from pathlib import Path
import re
import subprocess
import unittest
import numpy as np
from lupa import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build/dsp-test'
VCVARS=r'C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat'

def function(source,name):
    m=re.search(r'^(?:static )?[\w *]+\b'+name+r'\([^;{}]*\)\s*\{',source,re.M)
    if not m:raise AssertionError(name)
    end=source.index('\n}',m.end())+2
    return source[m.start():end]

def compile_native():
    source=(ROOT/'main/audio_module.c').read_text(encoding='utf8')
    constants='\n'.join(l for l in source.splitlines() if l.startswith('#define AUDIO_') and 'EXPORT' not in l and 'DSPS' not in l)
    structs=source[source.index('typedef struct audio_dsp_filter_t'):source.index('} audio_instance_t;')+len('} audio_instance_t;')]
    vendor=(ROOT/'managed_components/espressif__esp-dsp/modules/iir/biquad/dsps_biquad_f32_ansi.c').read_text()
    biquad=function(vendor,'dsps_biquad_f32_ansi').replace('esp_err_t','int').replace('ESP_OK','0')
    prefix=r'''
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <string.h>
#include <math.h>
#include <intrin.h>
#define API __declspec(dllexport)
#define __ATOMIC_ACQUIRE 0
#define __ATOMIC_RELEASE 0
#define __atomic_exchange_n(p,v,o) _InterlockedExchange((volatile long *)(p),(v))
#define __atomic_store_n(p,v,o) _InterlockedExchange((volatile long *)(p),(v))
typedef void *esp_audio_simple_dec_handle_t;
typedef void *module_task_create_ex_v1_fn;
typedef struct {struct {void (*delay)(uint32_t);void (*remove)(void *);} task;
                struct {void (*delay)(uint32_t);} time;} module_host_api_v1;
float audio_native_powf(float,float);
float audio_native_sinf(float);
float audio_native_cosf(float);
#define powf audio_native_powf
#define sinf audio_native_sinf
#define cosf audio_native_cosf
#include "audio_peak.h"
#define AUDIO_DSPS_BIQUAD_F32 dsps_biquad_f32_ansi
'''
    names=['audio_wrap_pi','sinf','cosf','powf','audio_clampf','audio_clipf',
        'audio_default_effects','audio_combined_gain_q15','audio_note_limiter','audio_copy_bytes',
        'audio_filter_reset','audio_filter_set','audio_reset_filter_state','audio_config_hpf',
        'audio_config_lpf','audio_config_peak','audio_rebuild_filters','audio_dsp_lock','audio_dsp_unlock',
        'audio_vbass_active','audio_dsp_active','audio_apply_dsp_mono','audio_postprocess_pcm',
        'audio_play_task_stop_internal']
    generated=prefix+constants+'\n'+structs+'\n'+biquad+'\n'+'\n'.join(function(source,n) for n in names)
    generated+='\nstatic int audio_decode_next(audio_instance_t *,size_t *,int);\n'
    generated+=function(source,'audio_read_pcm')+'\n'+(ROOT/'tests/dsp_runner.c').read_text()
    BUILD.mkdir(parents=True,exist_ok=True)
    (BUILD/'native_dsp.c').write_text(generated,encoding='utf8')
    cmd=f'call "{VCVARS}" >nul && cl /nologo /std:c11 /O2 /LD /I"{ROOT / "main"}" native_dsp.c /link /OUT:music_dsp.dll'
    subprocess.run(cmd,shell=True,cwd=BUILD,check=True)
    dll=C.CDLL(str(BUILD/'music_dsp.dll'))
    f=np.ctypeslib.ndpointer(dtype=np.float32,ndim=1,flags='C_CONTIGUOUS')
    s=np.ctypeslib.ndpointer(dtype=np.int16,ndim=1,flags='C_CONTIGUOUS')
    dll.process.argtypes=[s,f]+[C.c_int]*10+[C.POINTER(C.c_uint32)]
    dll.process.restype=C.c_int
    dll.defaults.argtypes=[f]
    dll.protect.argtypes=[f,f,f,C.c_int,C.c_int,C.c_float,C.c_float,C.POINTER(C.c_uint32)]
    return dll

def tone(rate,freq,amp,n=None):
    return amp*np.sin(2*np.pi*freq*np.arange(n or rate*2)/rate)

def amplitude(x,rate,freq):
    x=x[-rate:].astype(np.float64)
    return 2*abs(np.sum(x*np.exp(-2j*np.pi*freq*np.arange(len(x))/rate)))/len(x)

class MusicDSPTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.dll=compile_native()

    def run_dsp(self,x,rate=44100,bass=True,volume=1,loudness=1,channels=1,toggle=-1,chunk=257,flat=False,threshold=31000):
        pcm=np.ascontiguousarray(np.clip(x*32767,-32768,32767),dtype=np.int16)
        n=len(pcm)//channels;out=np.zeros(n+256,np.float32);st=(C.c_uint32*3)()
        count=self.dll.process(pcm,out,n,rate,channels,int(volume*32768),int(loudness*32768),bass,toggle,chunk,flat,threshold,st)
        self.assertEqual(count,n+256 if n else 0)
        self.assertEqual(st[0],0,'emergency hard clip must not run')
        self.assertTrue(np.isfinite(out).all())
        self.assertLessEqual(float(np.max(np.abs(out))),min(.96,threshold/32768)+.00004)
        return out[256:],list(st)

    def test_defaults_match_user_preset(self):
        v=np.zeros(28,np.float32);self.dll.defaults(v)
        lua=LuaRuntime();d=lua.execute((ROOT.parent/'package/effects_defaults.lua').read_text(encoding='utf8'))
        for start,key in [(0,'eq_freqs'),(7,'eq'),(14,'eq_q')]:
            np.testing.assert_allclose(v[start:start+7],[d[key][i] for i in range(1,8)],atol=1e-6)
        np.testing.assert_allclose(v[21:],[150,.2,3,75,200,150,495],atol=1e-6)
        self.assertTrue(d['vbass'])

    def test_vocal_and_harmonics(self):
        for rate in (32000,44100,48000):
            for freq in (400,1000,2500):
                x=tone(rate,freq,.15)+tone(rate,73,.15)
                off,_=self.run_dsp(x,rate,False)
                on,_=self.run_dsp(x,rate,True)
                delta=20*math.log10(amplitude(on,rate,freq)/amplitude(off,rate,freq))
                self.assertLess(abs(delta),.15,(rate,freq,delta))
        off,_=self.run_dsp(tone(44100,80,.2),bass=False)
        on,_=self.run_dsp(tone(44100,80,.2))
        self.assertGreater(amplitude(on-off,44100,160),.005)
        print('Music: vocal probes <0.15 dB; added 160 Hz harmonic',amplitude(on-off,44100,160))

    def test_peak_stress(self):
        rng=np.random.default_rng(17)
        for rate in (8000,16000,22050,32000,44100,48000):
            for volume in (0,.4,1,2):
                x=rng.uniform(-1,1,rate+37)
                self.run_dsp(x,rate,volume=volume,loudness=4,chunk=31)
        for threshold in (1024,20000,31000,32767):
            for pos in (0,127,128,255,256,730):
                d=np.zeros(731,np.float32);d[pos]=20;b=d.copy();out=np.zeros_like(d);st=(C.c_uint32*3)()
                self.dll.protect(d,b,out,len(d),44100,6,threshold/32768,st)
                self.assertEqual(st[0],0)
                self.assertLessEqual(float(np.max(np.abs(out))),min(.96,threshold/32768)+.00004)

    def test_fragmentation_stereo_downmix_tail(self):
        rng=np.random.default_rng(8)
        for n in (0,1,127,128,129,255,256,257,731,48001):
            x=rng.uniform(-.1,.1,n)
            y,_=self.run_dsp(x,bass=False,flat=True,chunk=31)
            np.testing.assert_allclose(y,np.asarray(x*32767,dtype=np.int16)/32767,atol=2/32767)
        x=tone(44100,80,.2)+tone(44100,1000,.1)
        reference,_=self.run_dsp(x,chunk=1024)
        for chunk in (1,31,127,128,257):
            out,_=self.run_dsp(x,chunk=chunk)
            np.testing.assert_allclose(out,reference,atol=2/32767)
        stereo=np.column_stack((x,x)).ravel()
        out,_=self.run_dsp(stereo,channels=2)
        np.testing.assert_allclose(out,reference,atol=2/32767)

    def test_toggle_and_silence(self):
        x=tone(44100,1000,.1)
        off,_=self.run_dsp(x,bass=False)
        switched,_=self.run_dsp(x,bass=False,toggle=44100)
        # The newly warmed low-band filters can contribute a very small faded
        # transient; dry filter history itself must remain sample-identical.
        self.assertLess(float(np.max(np.abs(switched-off))),.001)
        np.testing.assert_allclose(switched[49000:],off[49000:],atol=2/32767)
        dry_only,_=self.run_dsp(x,bass=2,toggle=44100)
        np.testing.assert_array_equal(dry_only,off)
        silence,_=self.run_dsp(np.zeros(88200))
        self.assertFalse(np.any(silence))

    def test_forced_stop_releases_orphaned_lock(self):
        self.assertEqual(self.dll.stop_check(),1)

if __name__=='__main__':unittest.main(verbosity=2)
