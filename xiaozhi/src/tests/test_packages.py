"""Host-side syntax and migration/identity contract tests (requires lupa)."""
import json
from pathlib import Path
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[3]
lua = LuaRuntime(unpack_returned_tuples=True)
load = lua.eval('function(s, name) local f,e=load(s,name); return f~=nil,e end')
for app in ('xiaozhi', 'xiaozhi-service'):
    for path in (ROOT/app/'package').rglob('*.lua'):
        ok, err = load(path.read_text(encoding='utf-8-sig'), str(path))
        assert ok, err
print('Lua syntax: PASS')

fs = {}
def contents(path): return fs.get(path)
def put(path, data): fs[path] = data; return True
def rename(src, dst):
    if src not in fs: return False
    fs[dst] = fs.pop(src); return True
def remove(path): fs.pop(path, None); return True
def table(value):
    if isinstance(value, dict): return lua.table_from({k:table(v) for k,v in value.items()})
    if isinstance(value, list): return lua.table_from([table(v) for v in value])
    return value
def plain(value):
    if hasattr(value, 'items'): return {str(k):plain(v) for k,v in value.items()}
    return value
lua.globals().file = lua.table_from(dict(getcontents=contents, putcontents=put, exists=lambda p:p in fs, mkdir=lambda p:True, rename=rename, remove=remove))
lua.globals().json = lua.table_from(dict(decode=lambda s:table(json.loads(s)), encode=lambda v:json.dumps(plain(v),ensure_ascii=False)))
lua.execute('wifi={sta={getmac=function() return "a0:b1:c2:d3:e4:f5" end}}; millis=function() return 1234 end')
store = lua.execute((ROOT/'xiaozhi/package/store.lua').read_text(encoding='utf-8'))
fs['/sd/apps/xiaozhi/config.json'] = json.dumps({'websocket':{'url':'wss://example.test','token':'legacy'}, 'ui':{'type':'wechat'}})
store.ensure()
assert store.device_id() == 'a0:b1:c2:d3:e4:f5'
assert store.identity_action('create') is True
new_id = store.device_id()
assert new_id.startswith('02:') and new_id != 'a0:b1:c2:d3:e4:f5'
reloaded = lua.execute((ROOT/'xiaozhi/package/store.lua').read_text(encoding='utf-8'))
assert reloaded.device_id() == new_id, 'virtual MAC reverted after restart'
assert reloaded.identity_action('select','a0:b1:c2:d3:e4:f5') is True
assert reloaded.ensure()['websocket']['token'] == 'legacy'
assert reloaded.identity_action('delete','a0:b1:c2:d3:e4:f5')[0] is False
assert '/sd/apps/xiaozhi/config.json' in fs, 'migration deleted old state'
assert '/sd/data/xiaozhi/config.json' in fs
assert store.identity_action('create') is True
assert store.device_id() != new_id
print('Shared configuration / virtual identity migration: PASS')

# Both independently deployed config loaders use the same state, with local assets.
def dofile(path):
    prefix = '/sd/apps/'
    assert path.startswith(prefix), path
    app_name, relative = path[len(prefix):].split('/',1)
    return lua.execute((ROOT/app_name/'package'/relative).read_text(encoding='utf-8'))
lua.globals().dofile = dofile
saved = json.loads(fs['/sd/data/xiaozhi/config.json'])
saved.update(language='en',wake={'id':'hi_esp'})
saved['ota'] = {'interval_ms': 3000, 'max_polls': 80}
saved['audio']['duplex'] = True
saved['audio']['aec_delay_ms'] = 16
saved['audio']['aec_nlp_level'] = 1
saved['websocket'] = {'url':'wss://shared.test','token':'shared-token','version':1}
fs['/sd/data/xiaozhi/config.json'] = json.dumps(saved)
for app_name in ('xiaozhi','xiaozhi-service'):
    cfg = lua.execute((ROOT/app_name/'package/config.lua').read_text(encoding='utf-8')).load()
    assert cfg['CONFIG_PATH'] == '/sd/data/xiaozhi/config.json'
    assert cfg['websocket']['token'] == 'shared-token'
    assert cfg['WAKE_MODEL'] == 'wn9s_hiesp'
    assert cfg['WAKE_ROOT'] == '/sd/apps/'+app_name+'/wake'
    assert cfg['LANGUAGE'] == 'en'
    assert cfg['ota']['poll_interval_ms'] == 6000
    assert cfg['ota']['slow_poll_interval_ms'] == 20000
    assert cfg['ota']['pairing_timeout_ms'] == 300000
    assert cfg['ota']['max_polls'] is None
    assert cfg['AUDIO']['duplex'] is None
    assert cfg['AUDIO']['aec_delay_ms'] is None
    assert cfg['AUDIO']['aec_nlp_level'] is None
    migrated = json.loads(fs['/sd/data/xiaozhi/config.json'])
    assert 'duplex' not in migrated['audio']
    assert migrated['websocket']['token'] == 'shared-token'
print('Standalone App / Service shared configuration: PASS')

# Startup ownership matrix: an installed or running service must prevent a second core.
for installed, ready in ((False,False),(True,False),(True,True),(False,True)):
    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.execute('count={core=0,ui=0,service=0}; app={start_service=function() count.service=count.service+1 end}')
    vm.globals().installed, vm.globals().ready = installed, ready
    vm.execute('''
      function dofile(path)
        if path:match('/config.lua$') then return {load=function() return {} end} end
        if path:match('/runtime.lua$') then return {new=function() count.core=count.core+1; return {start=function()end} end} end
        if path:match('/ui_ipc.lua$') then return {
          available=function() return ready end, service_installed=function() return installed end,
          new=function() count.ui=count.ui+1; return {start=function()end} end} end
        if path:match('/web.lua$') then return {} end
        error(path)
      end
    ''')
    vm.execute((ROOT/'xiaozhi/package/main.lua').read_text(encoding='utf-8'))
    assert vm.globals().count.core == (0 if installed or ready else 1)
    assert vm.globals().count.ui == (1 if installed or ready else 0)
    assert vm.globals().count.service == (1 if installed and not ready else 0)
print('Frontend ownership startup matrix: PASS')

import runpy
runpy.run_path(str(Path(__file__).with_name('test_half_duplex.py')))
runpy.run_path(str(Path(__file__).with_name('test_transport.py')))
runpy.run_path(str(Path(__file__).with_name('test_pairing_popup.py')))
runpy.run_path(str(Path(__file__).with_name('test_activation_retry.py')))

# A failed atomic commit must retain the previous identity and token.
snapshot = fs['/sd/data/xiaozhi/config.json']
original_rename = lua.globals().file.rename
lua.globals().file.rename = lambda src,dst: False if src.endswith('.tmp') else rename(src,dst)
ok, err = store.identity_action('create')
assert ok is False and err == 'config_commit_failed'
assert fs['/sd/data/xiaozhi/config.json'] == snapshot
lua.globals().file.rename = original_rename
print('Atomic-save rollback on rename failure: PASS')

# Binding survives a transient activation HTTP error and a stale displayed code.
for app_name in ('xiaozhi', 'xiaozhi-service'):
    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.execute("""
      callbacks={};events={};posted=0;saved=0
      function millis()return 0 end
      tmr={ALARM_SINGLE=0,create=function() return {
        stop=function()end,unregister=function()end,
        alarm=function(self,ms,kind,fn) callbacks[#callbacks+1]=fn end} end}
      sjson={decode=function(raw)
        if raw=='unbound' then return {activation={code='123456'}} end
        return {websocket={url='wss://bound.test',token='bound-token',version=1}}
      end}
      http={post=function(url)
        posted=posted+1
        if posted==1 then return 200,'unbound' end
        if posted==2 then return -1,'perform ESP_ERR_HTTP_EAGAIN' end
        return 200,'bound'
      end}
      function dofile(path)
        if path:match('/i18n.lua$') then return {translator=function() return function(s)return s end end} end
        if path:match('/identity.lua$') then return {
          device_id=function()return '02:01:02:03:04:05'end, client_id=function()return 'client'end,
          http_headers=function() return {} end,system_info_json=function()return '{}'end} end
        if path:match('/store.lua$') then return {
          device_id=function()return '02:01:02:03:04:05'end,
          update=function(fn) local doc={};fn(doc);saved=saved+1;assert(doc.websocket.token=='bound-token');return true end} end
        error(path)
      end
    """)
    vm.globals().activation_mod = vm.execute((ROOT/app_name/'package/activation.lua').read_text(encoding='utf-8'))
    vm.execute("""
      local a=activation_mod.new({APP_DIR='/app',ota={url='https://ota.test/',enabled=true},websocket={url=''}})
      a:start(function(e,data)events[#events+1]=e end)
      for i=1,10 do local fn=table.remove(callbacks,1);if not fn then break end;fn()end
      assert(saved==1 and posted==3 and events[#events]=='done')
    """)
print('Pairing transient retry / stale code: PASS')

# Host control-page discovery requires the route ending in slash.
vm = LuaRuntime(unpack_returned_tuples=True)
vm.execute("""
  routes={}
  httpd={GET=0,dynamic=function(method,path,fn)routes[path]=fn end}
  app={route_base=function()return '/xiaozhi'end}
  function dofile(path) return {new=function()return {
    setup=function()end,set_metrics=function()end,set_status=function()end}end}end
""")
ipc_ui = vm.execute((ROOT/'xiaozhi/package/ui_ipc.lua').read_text(encoding='utf-8'))
controller = ipc_ui.new(vm.table())
controller.start(controller)
assert vm.globals().routes['/xiaozhi/']()['headers']['location'] == '/xiaozhi-service/'
print('Foreground control-page discovery: PASS')

# Server bursts larger than the native ring are backpressured, not fatal.
vm=LuaRuntime(unpack_returned_tuples=True)
vm.globals().queues=vm.execute((ROOT/'xiaozhi/package/playback_queue.lua').read_text(encoding='utf-8'))
vm.execute("""
  local capacity, delivered=0,{}
  local q=queues.new(function(packet)
    if capacity==0 then return nil,'would_block' end
    capacity=capacity-1;delivered[#delivered+1]=packet;return true
  end,256,256*1024)
  for i=1,120 do assert(q:push(tostring(i))) end
  assert(q:count()==120)
  for i=1,10 do capacity=12;assert(q:drain())end
  assert(q:count()==0 and #delivered==120)
  for i=1,120 do assert(delivered[i]==tostring(i))end
  capacity=0;assert(q:push('stale'));q:clear()
  capacity=1;assert(q:push('fresh'));assert(delivered[121]=='fresh')
  capacity=0
  for i=1,256 do assert(q:push('x'))end
  assert(q:push('overflow')==false)
""")
print('Playback burst / FIFO / flush / bounded memory: PASS')

volume_source=(ROOT/'xiaozhi/package/volume.lua').read_text(encoding='utf-8')
vm=LuaRuntime(unpack_returned_tuples=True)
vm.execute("""
  writes,reads,current=0,0,25
  sys={getvolume=function()return current end,
    setvolume=function(v)current=v;writes=writes+1;return true end}
  file={getcontents=function()error('must not read SD on new firmware')end}
""")
vm.globals().volume=vm.execute(volume_source).new()
vm.execute("assert(volume.supported and volume.value==25);assert(volume.set(42));assert(current==42 and writes==1);current=18;volume.poll();assert(volume.value==18)")
vm=LuaRuntime(unpack_returned_tuples=True)
vm.execute("""
  reads=0;file={getcontents=function(path)assert(path=='/sd/apps/settings.json');reads=reads+1;return '{}'end}
  json={decode=function()return {volume=37}end}
""")
vm.globals().volume=vm.execute(volume_source).new()
vm.execute("assert(not volume.supported and volume.value==37);volume.poll();volume.set(18);assert(reads==1 and volume.value==18)")
print('Unified volume: firmware API / legacy settings read-once: PASS')
