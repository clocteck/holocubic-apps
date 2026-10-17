"""Real service UI and activation callback tests; no device pairing is changed."""
from pathlib import Path
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[3]


def make_vm(language="en"):
    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.globals().language = language

    def dofile(path):
        app, name = path.removeprefix("/sd/apps/").split("/", 1)
        return vm.execute((ROOT / app / "package" / name).read_text(encoding="utf-8"))

    vm.globals().dofile = dofile
    vm.execute("""
      XIAOZHI_UI_APP_DIR='/sd/apps/xiaozhi-service'
      XIAOZHI_SERVICE_DIR=XIAOZHI_UI_APP_DIR
      file={exists=function()return true end,getcontents=function()return '{}' end}
      json={decode=function()return {language=language}end}
      timers={};now=0;shows=0;acquires=0;releases=0;drawn={};fonts=0;visible={}
      function millis()return now end
      tmr={ALARM_SINGLE=0,ALARM_AUTO=1,create=function()
        local t={};timers[#timers+1]=t
        function t:unregister()self.active=false end
        t.stop=t.unregister
        function t:alarm(ms,kind,fn)
          self.at=now+ms;self.ms=ms;self.kind=kind;self.fn=fn;self.active=true
        end
        return t
      end}
      function advance(ms)
        now=now+ms
        for _,t in ipairs({table.unpack(timers)})do
          if t.active and now>=t.at then
            t.active=t.kind==1;t.at=now+t.ms;t.fn(t)
          end
        end
      end
      service_ui={
        acquire=function(x,y,w,h)acquires=acquires+1;return acquires end,
        release=function(id)releases=releases+1;visible[id]=nil end,
        show=function(id)shows=shows+1;visible[id]=true end,
        hide=function(id)visible[id]=false end,clear=function()end,
        is_visible=function(id)return visible[id]==true end}
      function lv_canvas_draw_rect()end
      function lv_canvas_draw_text(id,x,y,w,text,style)
        drawn[#drawn+1]={text=text,x=x,y=y,w=w}
      end
      function lv_font_load()fonts=fonts+1;return fonts end
      function lv_font_free()fonts=fonts-1 end
      cfg={APP_DIR=XIAOZHI_UI_APP_DIR,SERVICE_DIR=XIAOZHI_UI_APP_DIR,
        SERVICE_MODE=true,UI_MODE='floating',LANGUAGE=language,UI_TYPE='window',AUDIO={}}
      Driver=dofile(XIAOZHI_UI_APP_DIR..'/ui/driver.lua')
    """)
    return vm


for language, title, hint in (
    ("en", "Pairing code: 057855", "Enter in xiaozhi.me"),
    ("zh-CN", "配对码：057855", "请在 xiaozhi.me 输入"),
    ("zh-TW", "配對碼：057855", "請在 xiaozhi.me 輸入"),
    ("de", "Kopplungscode: 057855", "Auf xiaozhi.me eingeben"),
    ("ja", "ペアリングコード：057855", "xiaozhi.me で入力"),
):
    for style in ("window", "subtitle", "wechat", "assistant"):
        vm = make_vm(language)
        vm.globals().style = style
        vm.globals().expected_title, vm.globals().expected_hint = title, hint
        vm.execute("""
          cfg.UI_TYPE=style
          u=Driver.new(cfg);u:setup();u:on_state('starting');u:on_state('activating')
          u:set_status('checking');u:set_chat_message('system','checking')
          u:show_notification('retrying');advance(200)
          assert(shows==0 and acquires==0, 'startup progress opened chat style')
          assert(not u:show_pairing_code(''));assert(not XIAOZHI_PAIRING_PROMPT_SHOWN)
          assert(u:show_pairing_code('057855'))
          assert(shows==1 and #drawn==2)
          assert(drawn[1].text==expected_title and drawn[2].text==expected_hint)
          assert(drawn[1].y<drawn[2].y and not drawn[1].text:find('...',1,true))
          local deadline=u.pairing.timer.at
          for _=1,10 do
            u:set_status('pending');u:set_chat_message('system','pending')
            u:show_notification('retrying');u:show_pairing_code('057855');advance(400)
          end
          assert(shows==1 and u.pairing.timer.at==deadline)
          assert(u:show_pairing_code('012345'))
          assert(drawn[#drawn-1].text:find('012345',1,true))
          assert(u.pairing.timer.at==deadline, 'code refresh prolonged popup')
          advance(6000);assert(u.pairing.canvas==nil)
          local previous=shows
          assert(not u:show_pairing_code('999999'));advance(1000)
          assert(shows==previous)
          assert(u:show_pairing_code('000007',true))
          u:clear_chat_messages();assert(u.pairing.canvas==nil)
          assert(not u:show_pairing_code('000007'))
          u:stop();assert(fonts==0 and acquires==releases)
          -- Rebuilding styles/config in the same runtime cannot reset the latch.
          u=Driver.new(cfg);u:setup();u:on_state('activating')
          assert(not u:show_pairing_code('057855'))
          -- A new startup lifetime may show one reminder again.
          XIAOZHI_PAIRING_PROMPT_SHOWN=nil
          assert(u:show_pairing_code('057855'))
          u:on_state('idle');assert(u.pairing.canvas==nil)
          u:stop();assert(fonts==0 and acquires==releases)
        """)
print("Pairing card: five languages / four styles / timeout / HOME / reload: PASS")

vm = make_vm()
vm.execute("""
  u=Driver.new(cfg);u:setup();u:on_state('activating');u:set_suppressed(true)
  assert(not u:show_pairing_code('057855'));assert(shows==0)
  u:set_suppressed(false);assert(not u:show_pairing_code('057855'))
  assert(u:show_pairing_code('057855',true));u:set_suppressed(true)
  assert(u.pairing.canvas==nil);u:stop();assert(fonts==0)
  cfg.UI_MODE='app';XIAOZHI_PAIRING_PROMPT_SHOWN=nil
  u=Driver.new(cfg);u:setup();u:on_state('activating')
  assert(not u:show_pairing_code('057855'));u:stop()
""")
print("Pairing card respects foreground suppression / headless mode: PASS")

vm = make_vm()
vm.execute("""
  local State=dofile(XIAOZHI_UI_APP_DIR..'/state.lua')
  local Runtime=dofile(XIAOZHI_UI_APP_DIR..'/runtime.lua')
  local function noop()end
  local function load_module(name)
    if name=='state' then return State end
    if name=='ui' then return Driver end
    if name=='settings_controller' then return {attach=noop} end
    if name=='playback_session' then return {bind=noop} end
    if name=='activation' then return {new=function()
      local a={active=true,code=''}
      function a:start(fn)
        function emit_activation(event,data)
          if type(data)=='table' and data.code then self.code=data.code end
          if event=='done' then self.code='';self.active=false end
          fn(event,data)
        end
        return true
      end
      a.stop=function(self)self.active=false end
      return a
    end} end
    return {new=function()return {
      on=noop,on_state=noop,info=function()return {}end,set_mode=noop,
      start=noop,stop=noop,close_audio_channel=noop,is_audio_channel_opened=function()return false end,
    }end}
  end
  key={HOME=1,SHORT=1,on=function()return true end,off=noop}
  ipc={listen=function()return true end}
  json.decode=function()return {enabled=true,language=language}end
  cfg.websocket={url=''};cfg.ota={enabled=true};cfg.WAKE_WORD='Hi ESP'
  runtime=Runtime.new(cfg,load_module);assert(runtime:start())
  emit_activation('checking');assert(shows==0)
  emit_activation('code',{code='057855',message='old long server instruction'})
  assert(shows==1)
  local snapshot=runtime:ui_snapshot()
  assert(snapshot.text=='Pairing code: 057855\\nEnter in xiaozhi.me')
  assert(snapshot.pairing_code=='057855')
  for _=1,20 do
    emit_activation('pending',{code='057855'})
    emit_activation('retrying','network timeout')
    emit_activation('checking')
    emit_activation('code',{code='057855'})
  end
  assert(shows==1)
  assert(runtime:ui_control('dismiss'));assert(runtime.ui.pairing.canvas==nil)
  emit_activation('code',{code='012345'});emit_activation('pending',{code='012345'})
  assert(shows==1)
  assert(runtime:ui_snapshot().text=='Pairing code: 012345\\nEnter in xiaozhi.me')
  emit_activation('failed','activation timeout');advance(1000)
  assert(shows==1 and runtime.activation_message=='activation timeout')
  -- Explicit user requests remain usable even after the automatic reminder.
  assert(runtime:ui_control('wake'))
  assert(shows==2 and drawn[#drawn-1].text=='Pairing code: 012345')
  emit_activation('activated','012345');emit_activation('done','configured')
  assert(runtime.state.state=='idle' and runtime.ui.pairing.canvas==nil)
  assert(runtime:ui_snapshot().pairing_code=='')
""")
print("Real activation runtime: dynamic code / polling / retry / dismissal / completion: PASS")
