"""Lua settings migration, native-call payload and web preset regressions."""
import json
from pathlib import Path
import re
import subprocess
import unittest
from lupa import LuaRuntime

ROOT=Path(__file__).resolve().parents[2]

class PackageTests(unittest.TestCase):
    def setUp(self):
        self.source=(ROOT/'package/main.lua').read_text(encoding='utf8')
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().defaults_source=(ROOT/'package/effects_defaults.lua').read_text(encoding='utf8')
        self.lua.execute('''APP={APP_DIR='/sd/apps/mp3_player'}
          function dofile()return assert(load(defaults_source))()end
          APP.eq_settings=dofile();function web_log()end
        ''')
        # Execute the exact settings helpers and production native-call builder.
        start=self.source.index('local function clamp(')
        end=self.source.index('local function load_eq_settings()',start)
        helpers=self.source[start:end].replace('local function ','function ')
        self.lua.execute(helpers)
        start=self.source.index('apply_audio_effects = function()')
        end=self.source.index('\nlocal function set_error',start)
        self.lua.execute(self.source[start:end])

    def test_fresh_and_native_payload(self):
        self.lua.execute('''
          APP.audio={set_effects=function(s)captured=s;return true end}
          apply_audio_effects();local c=captured
          assert(c.hpf_freq==150 and c.vbass and c.vbass_mix==.2 and c.vbass_drive==3)
          assert(c.vbass_low_hpf==75 and c.vbass_low_lpf==200 and c.vbass_out_hpf==150 and c.vbass_out_lpf==495)
          assert(c.eq1_freq==180 and c.eq1_gain==6 and c.eq1_q==1)
          assert(c.eq2_gain==0 and c.eq5_gain==0)
          assert(c.eq3_freq==420 and c.eq3_gain==4.2)
          assert(c.eq4_freq==1000 and c.eq4_gain==-3.5)
          assert(c.eq6_freq==2500 and c.eq6_gain==-2.5)
          assert(c.eq7_freq==4300 and c.eq7_gain==-.8)
        ''')

    def test_saved_legacy_and_new_presets(self):
        self.lua.execute('''
          assert(merge_eq_settings({volume=.99,vbass=false,hpf_freq=100,eq={1,2,3,4,5,6,-1}}))
          local s=eq_settings_snapshot()
          assert(s.volume==.4 and not s.vbass and s.hpf_freq==100)
          assert(s.eq_freqs[1]==160 and s.eq_freqs[4]==780 and s.eq_freqs[6]==2800)
          assert(s.eq_q[1]==.75 and s.eq_q[7]==.65)
          APP.eq_settings=dofile();assert(merge_eq_settings(s))
          assert(APP.eq_settings.eq[2]==2 and APP.eq_settings.eq_freqs[4]==780)
          local fresh=dofile();assert(merge_eq_settings(fresh))
          assert(APP.eq_settings.eq_freqs[4]==1000 and APP.eq_settings.eq[4]==-3.5)
          assert(APP.eq_settings.eq_q[1]==1 and APP.eq_settings.volume==.4)
        ''')

    def test_versions_syntax_and_web_defaults(self):
        for p in (ROOT/'package').glob('*.lua'):
            self.lua.eval('function(s)assert(load(s))end')(p.read_text(encoding='utf8'))
        self.assertIn('version = 1.14',(ROOT/'package/app.info').read_text())
        self.assertIn('VERSION = "1.14"',self.source)
        self.assertIn('>1.14<',(ROOT/'package/info.html').read_text(encoding='utf8'))
        self.assertIn('#define AUDIO_VERSION "1.14"',(ROOT/'src/main/audio_module.c').read_text(encoding='utf8'))
        script=re.search(r'const BANDS=.*?\nconst EQ_DEFAULT=.*?;',self.source,re.S)[0]
        js=script+'\nconsole.log(JSON.stringify(EQ_DEFAULT));'
        data=json.loads(subprocess.check_output(['node','-e',js],text=True))
        defaults=self.lua.execute('return dofile()')
        for key in ['hpf_freq','vbass','vbass_mix','vbass_drive','vbass_low_hpf','vbass_low_lpf','vbass_out_hpf','vbass_out_lpf','vbass_even','vbass_odd']:
            self.assertEqual(data[key],defaults[key],key)
        for key in ['eq','eq_freqs','eq_q']:
            self.assertEqual(data[key],[defaults[key][i] for i in range(1,8)])
        self.assertIn('p["eq"+(i+1)+"_freq"]=eq.eq_freqs[i]',self.source)
        self.assertRegex(self.source,r'id="vbassOutLpf"[^>]*step="1"')
        for block in re.findall(r'<script>(.*?)</script>',self.source,re.S):
            subprocess.run(['node','-e','new Function('+json.dumps(block)+');'],check=True)

if __name__=='__main__':unittest.main(verbosity=2)
