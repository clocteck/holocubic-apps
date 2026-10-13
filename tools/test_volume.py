"""Host-only Lua regression tests; does not build firmware or native modules."""
import sys
sys.dont_write_bytecode = True
from pathlib import Path
import unittest
from lupa.lua54 import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
PACKAGES=[ROOT/p for p in ['mp3_player/package','radio/package','netease/package',
    'qqmusic/package','mjpeg_player/package','launcher/package/services/display_schedule']]
PACKAGES += [ROOT.parent/'holo-retro-go/package']

class VolumeTests(unittest.TestCase):
    def runtime(self, package, modern=True, value=25):
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.globals().MODERN=modern;lua.globals().INITIAL=value
        lua.execute('''
          reads,writes,sets,applies=0,0,0,{}
          global_volume=INITIAL;save_error='';set_error=false;read_error=false
          file={getcontents=function(path) assert(path=='/sd/apps/settings.json');reads=reads+1;return '{}' end,
                putcontents=function() writes=writes+1;error('must not write')end}
          json={decode=function() return {volume=INITIAL} end}
          if MODERN then sys={
            getvolume=function() if read_error then error('read failure')end;return global_volume end,
            setvolume=function(v) sets=sets+1;if set_error then return nil,'set failure'end;global_volume=v;return true end,
            getvolumestate=function()return {volume=global_volume,pending=save_error~='',error=save_error}end
          } end
          tmr={ALARM_AUTO=1,create=function()return {
            alarm=function(self,ms,mode,fn)assert(ms==200);self.fn=fn;timer=self end,
            unregister=function(self)self.stopped=true end}end}
        ''')
        module=lua.execute((package/'volume.lua').read_text(encoding='utf-8'))
        lua.globals().V=module.new()
        return lua

    def test_identical_adapters_and_syntax(self):
        canonical=(PACKAGES[0]/'volume.lua').read_bytes()
        compiler=LuaRuntime().eval('function(s) local f,e=load(s);return e end')
        for package in PACKAGES:
            self.assertEqual((package/'volume.lua').read_bytes(),canonical)
            for f in package.rglob('*.lua'):
                self.assertIsNone(compiler(f.read_text(encoding='utf-8-sig')),str(f))

    def test_modern_initial_remote_local_mute_stop(self):
        for package in PACKAGES:
            with self.subTest(package=package.name):
                lua=self.runtime(package,value=73)
                lua.execute('''
                  assert(V.supported and V.value==73 and reads==0)
                  V.start(function(n)applies[#applies+1]=n end)
                  assert(#applies==1 and applies[1]==73)
                  for i=1,20 do timer.fn()end;assert(#applies==1 and reads==0)
                  global_volume=32;timer.fn();assert(V.value==32 and applies[2]==32)
                  assert(V.set(0));assert(global_volume==0 and applies[3]==0 and sets==1)
                  assert(V.set(100));assert(global_volume==100)
                  assert(not V.set(101));assert(not V.set(-1));assert(not V.set(0/0));assert(not V.set('25'))
                  assert(writes==0 and reads==0)
                  V.stop();assert(timer.stopped)
                ''')

    def test_legacy_one_read_no_save_no_follow(self):
        for package in PACKAGES:
            lua=self.runtime(package,modern=False,value=0)
            lua.execute('''
              assert(not V.supported and V.value==0 and reads==1)
              V.start(function(n)applies[#applies+1]=n end)
              assert(timer==nil and applies[1]==0)
              assert(V.set(67));assert(V.value==67 and applies[2]==67)
              INITIAL=88;for i=1,50 do V.poll()end
              assert(V.value==67 and reads==1 and writes==0 and sets==0)
            ''')

    def test_modern_errors_never_fall_back_to_sd(self):
        lua=self.runtime(PACKAGES[0],value=31)
        lua.execute('''
          V.start(function(n)applies[#applies+1]=n end)
          set_error=true;assert(not V.set(90));assert(V.value==31 and #applies==1)
          set_error=false;assert(V.set(60));assert(V.value==60)
          save_error='SD failed';timer.fn();assert(V.error=='SD failed' and V.pending)
          save_error='';timer.fn();assert(V.error==nil)
          read_error=true;assert(not V.poll());assert(reads==0 and writes==0)
          read_error=false;global_volume=49;timer.fn();assert(V.value==49)
        ''')

    def test_apply_failure_retries_without_resaving(self):
        lua=self.runtime(PACKAGES[0])
        lua.execute('''
          attempts=0;V.start(function() attempts=attempts+1;if attempts==1 then return nil,'audio not ready'end;return true end)
          assert(V.error=='audio not ready');timer.fn();assert(attempts==2 and V.error==nil)
          timer.fn();assert(attempts==2 and sets==0)
        ''')

    def test_music_settings_do_not_persist_private_volume(self):
        for name in ['netease','qqmusic']:
            lua=LuaRuntime(unpack_returned_tuples=True)
            lua.execute('''
              files={};encoded=nil
              file={exists=function(p)return files[p]~=nil end,mkdir=function(p)files[p]=true end,
                getcontents=function(p)return files[p]end,putcontents=function(p,v)files[p]=v;return true end,
                remove=function(p)files[p]=nil;return true end,
                rename=function(a,b)files[b]=files[a];files[a]=nil;return true end}
              json={encode=function(v)encoded=v;return '{}' end,decode=function()return {}end}
            ''')
            m=lua.execute((ROOT/name/'package/storage.lua').read_text())
            lua.globals().S=m.new(lua.globals().file,lua.globals().json)
            lua.execute("local value={volume=62,play_mode='ordered',custom='keep'};assert(S.save('settings',value));assert(encoded.volume==nil and encoded.custom=='keep' and value.volume==62)")

    def test_firmware_wiring_source_contract(self):
        firmware=ROOT.parents[1]/'cubic_lua/cubic_arduino/cubic-develop/src'
        source=(firmware/'volume_settings.cpp').read_text()
        self.assertIn('"/sd/apps/settings.json"',source)
        self.assertNotIn('"/sd/apps/volume.json"',source)
        self.assertIn('doc["volume"] = value',source)
        self.assertIn('kSaveDelayUs = 500000',source)
        self.assertIn('revision == s_revision',source)
        for f in ['nodemcu/file/lua_file.cpp','http_Interface/httpd_system_fs_routes.cpp']:
            self.assertIn('volume_settings::settings_written()', (firmware/f).read_text())
        routes=(firmware/'http_Interface/httpd_system_routes.cpp').read_text()
        self.assertIn('"/audio/api/settings"',routes)
        self.assertIn('HTTP_GET',routes)
        lua=(firmware/'nodemcu/sys/lua_sys.cpp').read_text()
        for method in ['getvolume','setvolume','getvolumestate']:
            self.assertIn('"'+method+'"',lua)
        self.assertIn('volume_settings::poll()', (firmware/'main.cpp').read_text())

if __name__=='__main__':unittest.main(verbosity=2)
