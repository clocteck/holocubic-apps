"""Native float32 DSP regression: VS 2022 + numpy on Windows, cc elsewhere."""
import ctypes as C
import math
import os
from pathlib import Path
import subprocess
import unittest
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/dsp-test'
VCVARS = Path(r'C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat')

class Effects(C.Structure):
    _fields_ = [('gain10', C.c_int*5)] + [(n,C.c_int) for n in
        ('hpf_hz','bass','mix1000','drive1000','low_hz','high_hz','out_low_hz','out_high_hz')]

def settings(bass=True, device=False, flat=False):
    gains = [0]*5 if flat else ([60,42,-20,-10,5] if device else [60,36,-14,-10,5])
    return Effects((C.c_int*5)(*gains),0 if flat else (120 if device else 100),
        int(bass),250,4000 if device else 3500,50,200 if device else 180,120,600)

def compile_native():
    BUILD.mkdir(parents=True,exist_ok=True)
    sources = [ROOT/'tests/dsp_runner.c',ROOT/'main/ncm_dsp.c']
    if os.name=='nt':
        cmd = f'call "{VCVARS}" >nul && cl /nologo /std:c11 /O2 /LD /I"{ROOT / "main"}" '
        cmd += ' '.join(f'"{s}"' for s in sources) + ' /link /OUT:dsp_test.dll'
        subprocess.run(cmd,shell=True,cwd=BUILD,check=True)
        library=BUILD/'dsp_test.dll'
    else:
        library=BUILD/'dsp_test.so'
        subprocess.run(['cc','-std=c11','-O2','-shared','-fPIC',f'-I{ROOT / "main"}',
                        *map(str,sources),'-lm','-o',str(library)],check=True)
    dll=C.CDLL(str(library))
    array=np.ctypeslib.ndpointer(dtype=np.float32,ndim=1,flags='C_CONTIGUOUS')
    dll.process.argtypes=[array,array,array,array,C.c_int,C.c_int,C.POINTER(Effects),
                          C.c_int,C.c_int,C.POINTER(C.c_uint32)]
    dll.protect.argtypes=[array,array,array,C.c_int,C.c_int,C.c_int,C.POINTER(C.c_uint32)]
    dll.process.restype=dll.protect.restype=None
    return dll

def tone(rate,freq,amp,seconds=2):
    return (amp*np.sin(2*np.pi*freq*np.arange(int(rate*seconds))/rate)).astype(np.float32)

def amplitude(x,rate,freq):
    # Last whole second, after filter/mix/limiter settling.
    x=x[-rate:].astype(np.float64)
    return 2*abs(np.sum(x*np.exp(-2j*np.pi*freq*np.arange(len(x))/rate)))/len(x)

def old_second_harmonic(rate,freq,amp,s):
    # Analytic old full-wave rectifier. Cubic contributes odd harmonics only.
    def response(hz,f,high):
        w=2*math.pi*hz/rate;c=math.cos(w);a=math.sin(w)/(2*math.sqrt(.5));den=1+a
        n=1+c if high else 1-c
        b0=n/(2*den);b1=(-n if high else n)/den
        z=np.exp(-2j*np.pi*f/rate)
        return abs((b0+b1*z+b0*z*z)/(1-2*c/den*z+(1-a)/den*z*z))
    h=10**(-sum(max(0,g/10) for g in s.gain10)/20)/1.5
    low=amp*h*(s.drive1000/1000)*response(s.low_hz,freq,True)*response(s.high_hz,freq,False)
    assert low<1  # no saturation in the reference measurement
    return low*4/(3*math.pi)*1.2*(s.mix1000/1000)*response(s.out_low_hz,2*freq,True)*response(s.out_high_hz,2*freq,False)

class DSPTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.dll=compile_native()

    def run_dsp(self,x,s,rate=44100,volume=25,toggle=-1):
        x=np.ascontiguousarray(x,dtype=np.float32)
        dry=np.zeros_like(x);bass=np.zeros_like(x);out=np.zeros_like(x);stats=(C.c_uint32*3)()
        self.dll.process(x,dry,bass,out,len(x),rate,C.byref(s),volume,toggle,stats)
        self.assertTrue(np.isfinite(out).all())
        self.assertEqual(stats[0],0,'hard-clip guard must never be needed')
        self.assertLessEqual(float(np.max(np.abs(out))),.96004)
        return dry,bass,out,list(stats)

    def protect(self,dry,bass,rate=44100,volume=25):
        dry=np.ascontiguousarray(dry,dtype=np.float32);bass=np.ascontiguousarray(bass,dtype=np.float32)
        out=np.zeros_like(dry);stats=(C.c_uint32*3)()
        self.dll.protect(dry,bass,out,len(dry),rate,volume,stats)
        self.assertEqual(stats[0],0)
        self.assertLessEqual(float(np.max(np.abs(out))),.96004)
        return out,list(stats)

    def test_vocal_level_and_dry_path(self):
        for rate in (32000,44100,48000):
            for freq in (400,1000,2500):
                x=tone(rate,freq,.2)+tone(rate,73,.15)
                off=self.run_dsp(x,settings(False,device=True),rate,100)
                on=self.run_dsp(x,settings(True,device=True),rate,100)
                np.testing.assert_array_equal(off[0],on[0])
                delta=20*math.log10(amplitude(on[2],rate,freq)/amplitude(off[2],rate,freq))
                self.assertLess(abs(delta),.1,(rate,freq,delta))
        print('Vocal probes 400/1000/2500 Hz with 73 Hz bass: on/off < 0.1 dB; dry bit-identical')

    def test_user_defaults(self):
        from lupa import LuaRuntime
        doc=LuaRuntime().execute((ROOT.parent/'package/settings.lua').read_text(encoding='utf8'))
        self.assertEqual([doc['eq_db'][i] for i in range(1,6)],[6,4.2,-3.5,-2.5,-.8])
        for key,value in dict(hpf_hz=150,vbass=True,vbass_mix=.2,vbass_drive=3,
                              vbass_low_hpf=75,vbass_low_lpf=200,
                              vbass_out_hpf=150,vbass_out_lpf=495).items():
            self.assertEqual(doc[key],value)
        fx=Effects((C.c_int*5)(60,42,-35,-25,-8),150,1,200,3000,75,200,150,495)
        source=(ROOT/'main/ncm_music.c').read_text(encoding='utf8')
        self.assertIn('{{60,42,-35,-25,-8},150,1,200,3000,75,200,150,495}',source)
        x=tone(44100,80,.2)+tone(44100,1000,.15)
        on=self.run_dsp(x,fx,volume=100)
        fx.bass=0;off=self.run_dsp(x,fx,volume=100)
        np.testing.assert_array_equal(on[0],off[0])
        self.assertLess(abs(20*math.log10(amplitude(on[2],44100,1000)/amplitude(off[2],44100,1000))),.1)
        self.assertGreater(amplitude(on[2]-off[2],44100,160),.005)

    def test_bass_gain_against_old_algorithm(self):
        for freq in (55,80,110):
            for amp in (.05,.2,.5):
                s=settings();dry,bass,out,stats=self.run_dsp(tone(44100,freq,amp),s)
                old=old_second_harmonic(44100,freq,amp,s)
                gain=20*math.log10(amplitude(bass,44100,2*freq)/old)
                self.assertGreater(gain,3,(freq,amp,gain))
                print('Bass %3d Hz amp %.2f: second harmonic %+5.2f dB vs old' % (freq,amp,gain))

    def test_limiter_stress_and_volume(self):
        rng=np.random.default_rng(429)
        for rate in (8000,16000,22050,32000,44100,48000):
            for volume in (0,25,50,100):
                x=rng.uniform(-1,1,rate+731).astype(np.float32)
                s=settings(device=True);s.gain10=(C.c_int*5)(60,60,60,60,60)
                self.run_dsp(x,s,rate,volume)
                self.protect(x*3,np.roll(x,11)*2,rate,volume)
        # First/last samples, each block edge, and partial blocks must be safe.
        for pos in (0,1,127,128,129,255,256,257,512,730):
            x=np.zeros(731,np.float32);x[pos]=20
            out,_=self.protect(x,x)
            self.assertGreater(abs(out[pos]),.9)

    def test_dry_priority_under_overload(self):
        dry=tone(44100,997,.7)
        bass=tone(44100,80,3)
        off,_=self.protect(dry,np.zeros_like(dry))
        on,stats=self.protect(dry,bass)
        delta=20*math.log10(amplitude(on,44100,997)/amplitude(off,44100,997))
        self.assertLess(abs(delta),.1)
        self.assertGreater(stats[2],0)
        print('Overload: vocal delta %.4f dB, bass protection active, no hard clipping' % delta)

    def test_toggle_preserves_filters_and_fades(self):
        x=tone(44100,1000,.2)+tone(44100,80,.2)
        for enabled in (False,True):
            fixed=self.run_dsp(x,settings(enabled))
            switched=self.run_dsp(x,settings(enabled),toggle=44100)
            np.testing.assert_array_equal(fixed[0],switched[0])
            self.assertLess(abs(float(switched[2][44100]-switched[2][44099])),.05)
        print('Toggle: dry filter state preserved; 10 ms bass fade')

    def test_transparency_silence_tail(self):
        rng=np.random.default_rng(7)
        for n in (1,127,128,129,255,256,257,731,10000):
            x=rng.uniform(-.2,.2,n).astype(np.float32)
            out,_=self.protect(x,np.zeros_like(x))
            np.testing.assert_allclose(out,x,atol=1/32767)
        _,bass,out,_=self.run_dsp(np.zeros(88200,np.float32),settings())
        self.assertFalse(np.any(out));self.assertFalse(np.any(bass))
        print('Output state bytes:',self.dll.output_state_bytes(),'; delay: 256 samples')

if __name__=='__main__':unittest.main(verbosity=2)
