"""Real Lua audio/session contracts, with deterministic native workers."""
from pathlib import Path
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[3]
for app in ("xiaozhi","xiaozhi-service"):
    vm=LuaRuntime(unpack_returned_tuples=True)
    for name in ("audio","playback_queue","playback_session"):
        vm.globals()[name]=vm.execute((ROOT/app/"package"/(name+".lua")).read_text(encoding="utf-8"))
    vm.execute("""
      timers={};now=0
      function millis()return now end
      tmr={ALARM_AUTO=1,ALARM_SINGLE=0,create=function()
        local t={active=false}
        function t:stop()self.active=false end
        function t:unregister()self.active=false end
        function t:alarm(ms,kind,fn)self.active=true;self.ms=ms;self.kind=kind;self.fn=fn;self.next=now+ms end
        timers[#timers+1]=t;return t
      end}
      function tick(n)
        for _=1,(n or 1) do
          now=now+40
          local list={table.unpack(timers)}
          for _,t in ipairs(list)do
            if t.active and now>=t.next then
              t.next=now+t.ms;if t.kind==0 then t.active=false end;t.fn(t)
            end
          end
        end
      end
      file={exists=function()return true end}
      function dofile(path) assert(path:match('/playback_queue.lua$'));return playback_queue end
      local rx,tx,drained,finished=false,false,false,false
      local sent,received,stops,aborts=0,0,0,0
      local native_error=""
      local a=audio.new({APP_DIR='/app',AUDIO={rate=16000,channels=1,frame_ms=60,volume=37}})
      a.voice_ready=true
      a.voice={
        set_volume=function(v)assert(v==37)end,
        capture_start=function()assert(not tx);rx=true;return true end,
        capture_stop=function()rx=false;return true end,
        capture_read=function() if rx then return 'mic' end end,
        info=function()return {capture_running=rx,last_error=native_error}end,
        playback_start=function()assert(not rx);tx=true;drained=false;finished=false;return true end,
        playback_stop=function()tx=false;return true end,
        playback_status=function()return {running=tx and not drained,drained=drained,error=native_error}end,
        playback_write=function()assert(tx and not rx);received=received+1;return true end,
        playback_finish=function()finished=true;return true end}
      a.wake_ready=true
      a.wake={capture_start=function()assert(not rx and not tx);return true end,
        capture_stop=function()return true end,capture_read=function()return {running=true,frames=1}end}
      local p={callbacks={}}
      function p:on(e,fn)self.callbacks[e]=fn end
      function p:close_audio_channel()end
      function p:send_abort_speaking()aborts=aborts+1;return true end
      local r={audio=a,protocol=p,state={state='listening'},stop=function()a:stop_i2s()end}
      a.on_send=function()sent=sent+1;return true end
      a.on_error=function()r.state.state='fatal_error' end
      p.callbacks.audio=function(packet)a:play_opus(packet)end
      p.callbacks.tts_start=function()r.state.state='speaking';a:set_mode('speak')end
      p.callbacks.tts_stop=function()stops=stops+1;r.state.state='listening';a:set_mode('listen')end
      p.callbacks.closed=function()r.state.state='idle';a:stop_i2s()end
      playback_session.bind(r)
      assert(a:set_mode('listen'));tick();assert(sent>0 and rx and not tx)
      p.callbacks.tts_start();local before=sent
      tick(3);assert(sent==before and not rx and tx)
      assert(not a.on_send('should-not-upload') and sent==before)
      p.callbacks.audio('one');p.callbacks.audio('two');assert(received==2)
      p.callbacks.tts_stop();tick(3)
      assert(finished and r.state.state=='speaking' and not rx)
      p.callbacks.audio('late');assert(received==2)
      drained=true;tick(2);assert(not rx)
      tick();assert(rx and not tx and stops==1)
      -- A new answer replaces a draining answer, and cancels its timer.
      p.callbacks.tts_start();p.callbacks.audio('old');p.callbacks.tts_stop();tick()
      p.callbacks.tts_start();p.callbacks.audio('new');tick(4)
      assert(r.state.state=='speaking' and stops==1 and not rx)
      -- Explicit interruption stops output immediately, waits for server ack + tail.
      assert(p:send_abort_speaking('none'));assert(not tx and not rx and aborts==1)
      p.callbacks.audio('stale');local count=received
      tick(2);assert(r.state.state=='speaking')
      p.callbacks.tts_stop();tick(3);assert(rx and received==count and stops==2)
      p.callbacks.tts_start();assert(p:send_abort_speaking('none'))
      p:close_audio_channel(false);r.state.state='idle';a:stop_i2s();tick(50)
      r.state.state='listening';a:set_mode('listen');p.callbacks.tts_start()
      p.callbacks.audio('after-reconnect');assert(received==count+1);count=received
      -- Causal native errors survive stop and later callbacks.
      p.callbacks.tts_start();native_error='audio: decoder corrupt packet';tick()
      assert(r.state.state=='fatal_error' and a.last_error==native_error and not tx)
      a:fail('secondary failure');assert(a.last_error==native_error)
      p.callbacks.tts_start();p.callbacks.audio('late');assert(received==count)
      p.callbacks.closed();r.stopped=true;r.stop();tick(100);assert(not rx and not tx)
    """)
    print(app+": RX/TX exclusion, local drain, room tail, abort, first failure PASS")
