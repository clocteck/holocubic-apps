"""Run actual Lua function slices with mocked HTTP/settings (requires lupa)."""
from pathlib import Path
import unittest
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

def source(app, name='main.lua'):
    return (ROOT / app / 'package' / name).read_text(encoding='utf-8')

def section(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]

BASE = '''
local APP={running=true, state={}, SETTINGS_PATH='settings', DEFAULT_TIMEZONE='CST-8', DEFAULT_WEATHER_LOCATION='Shanghai', WEATHER_CITY_PATH='/v1/weather/cities', WEATHER_NOW_PATH='/v1/weather/now', WEATHER_3D_PATH='/v1/weather/3d'}
local S, state = {}, {}
local SETTINGS_PATH, DEFAULT_WEATHER_LOCATION='settings','Shanghai'
local function trim(v) return tostring(v or ''):match('^%s*(.-)%s*$') end
local function read_text() return SETTINGS end
local read_text_file=read_text
local function decode_json(v) return v end
local function encode_json(v) return v end
local function write_text(_,v) WRITES=WRITES+1; SETTINGS=type(v)=='table' and v or ENCODED; return true end
local write_text_file=write_text
local function url_encode(v) return tostring(v) end
local function render_clock() end
local function render() end
local function log() end
local function warn() end
local function posix_tz_offset_sec() return 0 end
local function maybe_gunzip(v) return v end
local function maybe_gunzip_body(v) return v end
local function parse_weather() APP.state.weather_valid=true end
local function parse_forecast() APP.state.forecast_valid=true end
local function text_or(v,d) return v or d end
local pcall_fn, floor=pcall, math.floor
json={encode=function(v) ENCODED=v; return 'encoded' end}
file={putcontents=write_text}
WRITES=0; Q={}
http={cubicserver={get=function(url,headers,callback) Q[#Q+1]={url=url,cb=callback} end}}
'''

def harness(app):
    s = source(app)
    if app == 'weather':
        code = section(s, '    local function normalize_language', '    local function startup_boot_city')
        code += section(s, '    local function apply_weather_address', '    local function sd_to_lv')
        code += section(s, '    local function parse_city_lookup_body', '    local function request_weather()')
        exports = 'load=load_runtime_settings,request=resolve_weather_location,display=display_city_name,save=save_location_cache'
    elif app == 'NixieClock':
        code = section(s, 'local function is_english()', 'local LOCALE_TEXT')
        code += section(s, 'local function load_settings()', 'local function load_app_config()')
        code += section(s, 'local function settings_still_current()', 'local WEB_HTML')
        exports = 'load=load_settings,request=request_weather,lang=ui_language'
    else:
        code = section(s, 'local function weather_language', 'redraw = function()')
        code += '\nredraw=function() end\n'
        exports = 'load=load_weather_location,request=request_weather,lang=weather_language'
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().SETTINGS = lua.table_from({'weather_address':'宁波市镇海区','language':'zh-CN'})
    obj = lua.execute(BASE + code + '\nreturn {APP=APP,S=S,' + exports + '}')
    return lua, obj

class WeatherTests(unittest.TestCase):
    def test_compile_complete_files(self):
        lua=LuaRuntime(unpack_returned_tuples=True)
        compile_lua=lua.eval('function(s) local f,e=load(s); assert(f,e); return true end')
        for app,name in [('weather','main.lua'),('NixieClock','main.lua'),('NixieClock','fireworks.lua'),('holo_pc_monitor','main.lua')]:
            self.assertTrue(compile_lua(source(app,name)),app)

    def run_case(self,app,language='ja',cached=True):
        lua,obj=harness(app)
        doc=lua.globals().SETTINGS
        doc.language=language
        if cached:
            doc.weather_location_address=doc.weather_address
            doc.weather_location_id='101210412'
            doc.weather_city='镇海'
            doc.weather_city_lang='zh-CN'
        obj.load()
        if app=='weather': obj.request(lua.eval('function(id,err) RESULT=id; ERR=err end'))
        else: obj.request()
        return lua,obj

    def test_language_refresh_uses_id(self):
        for app in ['weather','NixieClock','holo_pc_monitor']:
            for lang,api in [('en','en'),('ja','ja'),('de','de'),('zh-TW','zh-hant')]:
                lua,obj=self.run_case(app,lang)
                self.assertIn('location=101210412',lua.globals().Q[1].url)
                self.assertIn('lang='+api,lua.globals().Q[1].url)

    def test_stale_id_and_unowned_legacy_id(self):
        for app in ['weather','NixieClock','holo_pc_monitor']:
            for cached_raw in ['Ningbo','']:
                lua,obj=harness(app); d=lua.globals().SETTINGS
                d.weather_location_id='old-id';d.weather_location_address=cached_raw
                obj.load()
                if app=='weather':obj.request(lua.eval('function() end'))
                else:obj.request()
                self.assertIn('location=宁波市镇海区',lua.globals().Q[1].url)

    def test_localized_name_persists_and_restart_reuses_it(self):
        for app in ['weather','NixieClock']:
            lua,obj=self.run_case(app)
            lua.execute("Q[1].cb(200,{code='200',location={{id='101210412',name='新宿'}}})")
            self.assertEqual(lua.globals().SETTINGS.weather_city,'新宿')
            self.assertEqual(lua.globals().SETTINGS.weather_city_lang,'ja')
            lua2,obj2=harness(app)
            lua2.globals().SETTINGS=lua2.table_from(dict(lua.globals().SETTINGS.items()))
            obj2.load()
            if app=='weather':
                self.assertEqual(obj2.display(),'新宿')
                obj2.request(lua2.eval('function(id) RESULT=id end'))
                self.assertEqual(len(lua2.globals().Q),0)
            else:
                obj2.request()
                self.assertIn('/now?',lua2.globals().Q[1].url)
                self.assertEqual(obj2.APP.state.city,'新宿')

    def test_translation_failure_keeps_location(self):
        for app in ['weather','NixieClock','holo_pc_monitor']:
            lua,obj=self.run_case(app)
            lua.execute('Q[1].cb(500,nil)')
            if app=='weather':
                self.assertEqual(lua.globals().RESULT,'101210412')
                self.assertEqual(obj.display(),'镇海')
            else:self.assertIn('/now?location=101210412',lua.globals().Q[2].url)
            self.assertEqual(lua.globals().WRITES,0)

    def test_do_not_overwrite_changed_settings(self):
        for app in ['weather','NixieClock','holo_pc_monitor']:
            lua,obj=self.run_case(app)
            lua.execute("SETTINGS.weather_address='Tokyo'; Q[1].cb(200,{code='200',location={{id='wrong',name='旧城市'}}})")
            self.assertEqual(lua.globals().WRITES,0)
            self.assertEqual(len(lua.globals().Q),1)

    def test_do_not_overwrite_changed_language(self):
        for app in ['weather','NixieClock','holo_pc_monitor']:
            lua,obj=self.run_case(app)
            lua.execute("SETTINGS.language='de'; Q[1].cb(200,{code='200',location={{id='101210412',name='新宿'}}})")
            self.assertEqual(lua.globals().WRITES,0)
            self.assertEqual(len(lua.globals().Q),1)

    def test_legacy_cache_name_is_kept_until_translation(self):
        lua,obj=harness('weather');d=lua.globals().SETTINGS
        d.language='en';d.weather_location_address=d.weather_address
        d.weather_location_id='101210412';d.weather_city='镇海'
        obj.load();self.assertEqual(obj.display(),'镇海')
        obj.request(lua.eval('function() end'))
        self.assertIn('location=101210412',lua.globals().Q[1].url)

    def test_monitor_blank_address_does_not_write_default(self):
        lua,obj=harness('holo_pc_monitor');lua.globals().SETTINGS.weather_address=''
        obj.load();obj.request()
        self.assertIn('location=Shanghai',lua.globals().Q[1].url)
        self.assertEqual(lua.globals().WRITES,0)

    def test_merge_latest_unrelated_setting(self):
        for app in ['weather','NixieClock']:
            lua,obj=self.run_case(app)
            lua.execute("SETTINGS.brightness=37; Q[1].cb(200,{code='200',location={{id='101210412',name='新宿'}}})")
            self.assertEqual(lua.globals().SETTINGS.brightness,37)
            self.assertEqual(lua.globals().WRITES,1)

    def test_monitor_never_writes_and_reuses_private_cache(self):
        lua,obj=self.run_case('holo_pc_monitor',cached=False)
        lua.execute("Q[1].cb(200,{code='200',location={{id='101210412',name='新宿'}}}); Q[2].cb(200,{code='200',now={temp='24',text='晴れ',icon='100'}})")
        obj.request()
        self.assertIn('/now?location=101210412',lua.globals().Q[3].url)
        self.assertEqual(lua.globals().WRITES,0)
        self.assertIsNone(lua.globals().SETTINGS.weather_location_id)
        lua.execute("Q[3].cb(200,{code='200',now={temp='24',text='晴れ',icon='100'}}); SETTINGS.language='de'")
        obj.request()
        self.assertIn('/cities?location=101210412&number=1&lang=de',lua.globals().Q[4].url)

    def test_holo_temperature_font(self):
        s=source('NixieClock');lua=LuaRuntime(unpack_returned_tuples=True)
        code=section(s,'local FACE_LABELS','local function circle(')
        lua.execute('''APP={font={localized={[12]=112,[11]=111,[14]=114,[16]=116},n34=34,en11=11,ui12=12},canvas=1}; C={white=1};ALIGN_LEFT=0; text_dsc={};floor=math.floor;pcall_fn=pcall;canvas_text=function(_,x,y,w,v,d) RESULT_FONT=d.font_handle;RESULT_TEXT=v end;function ui_language() return 'ja' end\n'''+code+"\ntext(0,0,80,'24°',APP.font.n34); assert(RESULT_FONT==34); text(0,0,80,'新宿',APP.font.en11); assert(RESULT_FONT==111)")

if __name__ == '__main__':
    unittest.main(verbosity=2)
