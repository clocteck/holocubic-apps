"""Bounded ordered transport and automatic/manual listening contracts."""
from pathlib import Path
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[3]
for app in ("xiaozhi","xiaozhi-service"):
    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.globals().protocol = vm.execute((ROOT/app/"package/protocol.lua").read_text(encoding="utf-8"))
    vm.execute("""
      now=0;timers={};wire={};blocked=false
      function millis()return now end
      tmr={ALARM_AUTO=1,create=function()
        local t={}
        function t:stop()self.active=false end
        function t:unregister()self.active=false end
        function t:alarm(ms,kind,fn)self.active=true;self.fn=fn end
        timers[#timers+1]=t;return t
      end}
      function tick(ms)
        now=now+(ms or 20)
        for _,t in ipairs(timers)do if t.active then t.fn()end end
      end
      websocket={TEXT=1,BINARY=2}
      local function connect(p)
        p.connected=true;p.opened=true
        p.ws={close=function()end,send=function(self,data,opcode)
          if blocked then return 'send queue full' end
          wire[#wire+1]={data=data,opcode=opcode};return true
        end}
      end
      local p=protocol.new({websocket={version=1}})
      local errors,closed=0,0
      p:on('error',function()errors=errors+1 end)
      p:on('closed',function()closed=closed+1 end)
      connect(p)
      assert(p:send_start_listening('auto'))
      assert(wire[1].data:find('"mode":"auto"',1,true))
      blocked=true
      assert(p:send_audio('first'));assert(p:send_audio('second'))
      assert(p:send_text('control'));assert(p:info().queued_messages==3 and errors==0)
      tick();assert(#wire==1 and p:info().send_retries>0)
      blocked=false;tick()
      assert(wire[2].data=='first' and wire[3].data=='second' and wire[4].data=='control')
      assert(p:info().uploaded_packets==2 and p:info().queued_messages==0)
      assert(p:send_start_listening('manual'))
      assert(p:send_start_listening('auto'));assert(#wire==6)
      -- Age deadline, not callback count.
      blocked=true;assert(p:send_audio('stale'));tick(1501)
      assert(errors==1 and closed==1 and p:info().queued_messages==0)
      assert(p.last_error:find('1500ms') and not p:is_audio_channel_opened())
      connect(p);assert(p:send_audio('discard-on-close'));p:close_audio_channel(false)
      blocked=false;tick();assert(#wire==6)
      -- Versions retain their framing; reconnect resets automatic start suppression.
      connect(p);p.cfg.websocket.version=3
      assert(p:send_start_listening('auto'));assert(#wire==7)
      assert(p:send_audio('opus'));assert(wire[8].data==string.char(0,0,0,4)..'opus')
      -- Full queue is bounded and fatal, never an unbounded latency/memory increase.
      blocked=true
      for i=1,32 do assert(p:send_audio('x'))end
      assert(not p:send_audio('overflow'));assert(p.last_error:find('limit'))
      assert(p:info().queued_messages==0)
    """)
    print(app + ": automatic protocol / ordered retry / deadlines / queue bounds: PASS")

    # Exercise the real constructors and mode selector without hardware startup.
    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.execute("""
      function dofile()return {translator=function()return function(s)return s end end}end
    """)
    vm.globals().runtime_mod = vm.execute((ROOT/app/"package/runtime.lua").read_text(encoding="utf-8"))
    vm.globals().state_mod = vm.execute((ROOT/app/"package/state.lua").read_text(encoding="utf-8"))
    vm.execute("""
      local function load(name)
        if name=='state' then return state_mod end
        if name=='settings_controller' then return {attach=function()end} end
        return {new=function()return {}end}
      end
      local r=runtime_mod.new({AUDIO={}},load)
      assert(r.listening_mode=='auto')
      r.state.state='listening'
      r.start_listening('manual');assert(r.listening_mode=='manual')
      r.start_listening('auto');assert(r.listening_mode=='auto')
      local h=runtime_mod.new({AUDIO={}},load)
      assert(h.listening_mode=='auto')
    """)
    print(app + ": actual runtime default / manual / explicit half duplex: PASS")
