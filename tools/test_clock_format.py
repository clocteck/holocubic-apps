"""Display-only time preference: host Lua regression checks."""
import unittest
from pathlib import Path
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
APPS = ["weather", "NixieClock", "ConwayLife", "FluidPendant", "Spectrum", "afterglow"]

class ClockFormatTests(unittest.TestCase):
    def runtime(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute("""
          stamp=0; reads=0; preference=nil; fail=false
          tmr={now=function() return stamp end}
          file={getcontents=function() reads=reads+1;if fail then error('SD busy')end;return '{}' end}
          json={decode=function() return {time_format=preference} end}
        """)
        module = lua.execute((ROOT/"weather/package/clock_format.lua").read_text())
        return lua, module

    def test_copies_and_all_core_lua_compile(self):
        reference = (ROOT/"weather/package/clock_format.lua").read_bytes()
        compile_lua = LuaRuntime(unpack_returned_tuples=True).eval("function(s) local f,e=load(s);return e end")
        for app in APPS:
            self.assertEqual(reference, (ROOT/app/"package/clock_format.lua").read_bytes())
            for path in (ROOT/app/"package").rglob("*.lua"):
                self.assertIsNone(compile_lua(path.read_text(encoding="utf-8-sig")), str(path))

    def test_boundaries_and_no_calendar_mutation(self):
        lua, m = self.runtime()
        for hour, shown, period in [(0,12,"AM"),(1,1,"AM"),(11,11,"AM"),(12,12,"PM"),(13,1,"PM"),(23,11,"PM")]:
            self.assertEqual(m.hour(hour,"12"),shown)
            self.assertEqual(m.period(hour,"12"),period)
            self.assertEqual(m.text(hour,5,"12"),f"{shown:02}:05")
            self.assertEqual(m.text(hour,5,"24"),f"{hour:02}:05")
            self.assertEqual(m.period(hour,"24"),"")
        self.assertEqual(m.text(None,None),"--:--")
        self.assertEqual(m.period(None,"12"),"")

    def test_cache_errors_default_and_timer_wrap(self):
        lua, m = self.runtime()
        self.assertEqual(m.mode(),"24")
        lua.execute("preference='12';stamp=1000000")
        self.assertEqual(m.mode(),"24")
        self.assertEqual(lua.globals().reads,1)
        lua.execute("stamp=3000000")
        self.assertEqual(m.mode(),"12")
        lua.execute("fail=true;stamp=6000000")
        self.assertEqual(m.mode(),"12")
        lua.execute("fail=false;preference='bad';stamp=9000000")
        self.assertEqual(m.mode(),"24")
        lua.execute("preference=12;stamp=1")
        self.assertEqual(m.mode(),"12")
        lua.execute("preference=nil;stamp=3000001")
        self.assertEqual(m.mode(),"24")

    def test_non_display_logic_unchanged(self):
        import subprocess
        def body(source,start,end):
            return source.split(start,1)[1].split(end,1)[0]
        for relative,start,end in [
            ("weather/package/main.lua","local function is_night_time()","local function format_clock_text()"),
            ("NixieClock/package/main.lua","local function draw_hands(","local function draw_meridian("),
            ("NixieClock/package/fireworks.lua","    local hour = tonumber(t.hour) or 0","\n-- ---------------------------------------------------------------- canvas"),
        ]:
            old=subprocess.check_output(["git","show","bb89ab2:"+relative],cwd=ROOT).decode().replace("\r\n","\n")
            new=(ROOT/relative).read_text(encoding="utf-8")
            self.assertEqual(body(old,start,end),body(new,start,end),relative)

    def test_release_metadata_and_nixie_digits_only(self):
        for app,version in [("launcher","1.33"),("weather","1.16"),("NixieClock","1.2.2")]:
            self.assertIn("version = "+version, (ROOT/app/"package/app.info").read_text(encoding="utf-8"))
            self.assertIn('class="value">'+version+'</span>', (ROOT/app/"package/info.html").read_text(encoding="utf-8"))
        self.assertFalse((ROOT/"PipBoy").exists())
        self.assertIn('if period ~= "" and APP.state.face ~= 8 then',
                      (ROOT/"NixieClock/package/main.lua").read_text(encoding="utf-8"))

if __name__ == "__main__":
    unittest.main()
