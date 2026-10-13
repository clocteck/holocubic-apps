"""Offline regression tests: Lua locale routing, translations and binary glyphs.

Run: python -X utf8 tools/test_i18n.py (requires Lupa; no device or network access).
"""
import re
import subprocess
import sys
sys.dont_write_bytecode = True
from pathlib import Path
from lupa.lua54 import LuaRuntime
from check_font_coverage import codepoints
from generate_i18n_charsets import gb2312_hanzi, PLACE_NAMES

ROOT = Path(__file__).resolve().parents[1]
PACKAGES = ['launcher', 'BTC', 'weather', 'ebook', 'settings', 'NixieClock',
            '../hidpad', '../holopet', '../youxia173-holocubic-apps/gold-miner']


def runtime(language):
    lua = LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.os = g.io = g.require = g.dofile = None
    g.TEST_LANGUAGE = language
    g.pcall_fn = g.pcall
    g.APP = lua.table_from({'state': lua.table_from({'language': language})})
    g.file = lua.table_from({'getcontents': lambda _: '{}'})
    g.json = lua.table_from({'decode': lambda _: lua.table_from({'language': language})})
    g.sjson = g.JSON = g.json
    return lua


def function_source(path, name):
    s = path.read_text(encoding='utf-8')
    m = re.search(r'(?ms)^(?P<i> *)local function '+name+r'\([^\n]*\).*?^(?P=i)end\b', s)
    assert m, (path, name)
    return m[0]


compiled = 0
for package in PACKAGES:
    for p in (ROOT/package/'package').rglob('*.lua'):
        compiler = LuaRuntime().eval('function(s,n) local f,e=load(s,n); return e end')
        error = compiler(p.read_text(encoding='utf-8-sig'), '@'+str(p))
        assert error is None, (p, error)
        compiled += 1
print(f'PASS: {compiled} Lua files compile with Lua 5.4')

cases = [
 ('launcher/package/main.lua', 'normalize_language'),
 ('weather/package/main.lua', 'normalize_language'),
 ('ebook/package/reader.lua', 'normalize_language'),
 ('../hidpad/package/main.lua', 'normalize_language'),
 ('../youxia173-holocubic-apps/gold-miner/package/main.lua', 'device_language'),
 ('NixieClock/package/main.lua', 'ui_language'),
 ('../holopet/package/web.lua', 'read_ui_language'),
]
tested = 0
for relative, name in cases:
    code = function_source(ROOT/relative, name)
    for lang, want in [('en','en'),('EN_us','en'),('de','de'),('de-DE','de'),('de_DE','de'),('ja','ja'),('ja-JP','ja'),('fr','en')]:
        expression = name+'()' if name in ('device_language','ui_language','read_ui_language') else name+'(TEST_LANGUAGE)'
        got = runtime(lang).execute('local DEFAULT_LANGUAGE="zh-CN"; '+code+';return '+expression)
        if isinstance(got, tuple): got = got[0]
        assert got == want, (relative, lang, got, want)
        tested += 1
for relative in ['BTC/package/i18n.lua','settings/package/i18n.lua']:
    code=(ROOT/relative).read_text(encoding='utf-8')
    for lang, want in [('en','en'),('de-DE','de'),('de_DE','de'),('ja-JP','ja'),('fr','en')]:
        lua=runtime(lang); module=lua.execute(code)
        assert module.language == want, (relative,lang,module.language)
        if relative.startswith('settings'):
            for key in ['设置','蓝牙手柄','不可用','连接中','设备信息','操作失败']:
                value=module.t(key)
                assert value != key, (relative,lang,key,value)
                if want in ('en','de'): assert not re.search('[\u3400-\u9fff]',value)
        tested += 1
print(f'PASS: {tested} Lua language and translation cases')

# Keep a usable cached name while fetching its localized replacement by ID.
city_source=(ROOT/'weather/package/main.lua').read_text(encoding='utf-8')
city_code='local function display_city_name()'+city_source.split('local function display_city_name()',1)[1].split('local function startup_boot_city()',1)[0]
for lang, city, address, source_language, expected in [
    ('en','宁波','Ningbo','', '宁波'),
    ('de','宁波','Ningbo','', '宁波'),
    ('ja','宁波','Ningbo','', '宁波'),
    ('de','München','München','', 'München'),
    ('ja','東京','Tokyo','ja', '東京'),
    ('zh-CN','湛江','Zhanjiang','', '湛江'),
    ('en','湛江','湛江','', '湛江'),
]:
    lua=LuaRuntime()
    lua.globals().APP=lua.table_from({'LANGUAGE':lang,'CITY_NAME':city,'WEATHER_LOCATION':address,'CITY_NAME_LANGUAGE':source_language})
    assert lua.execute('local function tr() return "Weather" end; '+city_code+';return display_city_name()') == expected
print('PASS: 7 cached-city display cases; names remain visible during localization')

# Keep the Settings control flow exactly as it was: only display wrappers and the
# font-selection branch may differ from the checked-in version.
before=subprocess.check_output(['git','show','HEAD:settings/package/main.lua'],cwd=ROOT).decode('utf-8')
after=(ROOT/'settings/package/main.lua').read_text(encoding='utf-8')
def settings_control_flow(source):
    source=source.replace('\r\n','\n').removeprefix('local I18n = dofile("/sd/apps/settings/i18n.lua")\nlocal T = I18n.t\n\n')
    source=re.sub(r'  if I18n.language == "de".*?\n  end\n', '', source, count=1, flags=re.S)
    return re.sub(r'T\(("(?:\\.|[^"\\])*")\)',r'\1',source).strip()
assert settings_control_flow(before) == settings_control_flow(after), 'Settings business logic changed'
print('PASS: Settings control flow unchanged after removing translation/font additions')

required=set(map(ord,gb2312_hanzi()+PLACE_NAMES))
for size in [12,16]:
    p=ROOT/f'weather/package/font/weather_ui_zh_cn_{size}.bin'
    present=codepoints(p)
    assert not required-present, (p, ''.join(chr(x) for x in sorted(required-present)))
    print(f'PASS: Weather {size}px contains all 6,763 GB2312 Hanzi and place-name extensions ({p.stat().st_size} bytes)')
for package in PACKAGES:
    for p in (ROOT/package/'package/font').glob('*de*.bin'):
        assert set(map(ord,'ÄÖÜäöüß')) <= codepoints(p), p
print('PASS: German fonts retain umlauts and sharp S')

settings_source=(ROOT/'settings/package/i18n.lua').read_text(encoding='utf-8')
settings_keys=set(re.findall(r'\["([^"\n]+)"\]\s*=',settings_source))
for language in ['en','de','ja']:
    module=runtime(language).execute(settings_source)
    texts=[module.t(key) for key in settings_keys]
    family='ja' if language=='ja' else 'de'
    for size in [12,15,18]:
        present=codepoints(ROOT/f'settings/package/font/settings_{family}_{size}.bin')
        missing={c for text in texts for c in text if not c.isspace() and ord(c) not in present}
        assert not missing,(language,size,sorted(missing))
print('PASS: every translated Settings string is covered by each selected font')

for relative in ['BTC/package/i18n.lua','ebook/package/reader.lua','../youxia173-holocubic-apps/gold-miner/package/main.lua']:
    source=(ROOT/relative).read_text(encoding='utf-8')
    table=re.search(r'(?ms)^local TEXT = \{.*?^\}',source)
    assert table,relative
    translations=LuaRuntime().execute(table[0]+';return TEXT')
    for key,value in translations.en.items():
        for language in ['de','ja']:
            translated=translations[language][key]
            assert translated,(relative,language,key)
            spec=lambda text:re.findall(r'%(?:\d+)?[sdf]',text)
            assert spec(value)==spec(translated),(relative,language,key,value,translated)
            if language=='de':assert not re.search('[\u3400-\u9fff]',translated),(relative,key)
    if relative.startswith('BTC'):
        font_paths=lambda language:[ROOT/f'BTC/package/font/btc_ui_{language}_12.bin']
    elif relative.startswith('ebook'):
        font_paths=lambda language:[ROOT/('ebook/package/font/launcher_ui_ja_16.bin' if language=='ja' else 'ebook/package/font/launcher_ui_zh_cn_16.bin')]
    else:
        font_paths=lambda language:[ROOT/f'../youxia173-holocubic-apps/gold-miner/package/font/ui_{language}_{size}.bin' for size in [12,16,20,24]]
    for language in ['de','ja']:
        wanted={ord(c) for _,text in translations[language].items() for c in text if not c.isspace()}
        for font in font_paths(language):
            missing=wanted-codepoints(font)
            assert not missing,(font,''.join(chr(x) for x in sorted(missing)))
print('PASS: BTC, E-Book and Gold Miner locale keys and formatting placeholders match')
print('PASS: BTC, E-Book and Gold Miner packaged fonts cover their German/Japanese UI text')
