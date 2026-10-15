-- Keep microphone off through network stop, local DMA drain and room tail.
local M={}
function M.bind(runtime)
  local audio,protocol=runtime.audio,runtime.protocol
  local c=protocol.callbacks
  local on_audio,on_start,on_stop,on_closed=c.audio,c.tts_start,c.tts_stop,c.closed
  local timer,accept,aborted=nil,false,false
  audio.session_events={}
  local function cancel()
    if timer then timer:stop();timer:unregister();timer=nil end
  end
  local function alive()
    return not runtime.stopped and runtime.state.state~="fatal_error" and not runtime.audio_suspended_by_app
  end
  local function record(event)
    local list=audio.session_events
    list[#list+1]={event=event,ms=millis and millis() or 0}
    if #list>20 then table.remove(list,1) end
    print("[xiaozhi-audio]",event)
  end
  local function drain()
    cancel()
    local empty,ticks=0,0
    local current=tmr.create();timer=current
    current:alarm(40,tmr.ALARM_AUTO,function()
      if timer~=current then return end
      if not alive() or runtime.state.state~="speaking" then cancel();return end
      ticks=ticks+1;empty=audio:playback_pending() and 0 or empty+1
      if empty>=3 then
        cancel();aborted=false;record("playback_drained");on_stop()
      elseif ticks>=750 then cancel();audio:fail("playback drain timeout") end
    end)
  end
  local send=audio.on_send
  audio.on_send=function(packet)
    if not alive() or runtime.state.state~="listening" then return false,"upload outside listening phase" end
    return send(packet)
  end
  -- Intentional close(false) suppresses the transport's closed callback.
  -- Clear cancellation state here too, so the next conversation is not muted.
  local close=protocol.close_audio_channel
  function protocol:close_audio_channel(...)
    cancel();accept=false;aborted=false
    return close(self,...)
  end
  local abort=protocol.send_abort_speaking
  function protocol:send_abort_speaking(reason)
    if runtime.state.state~="speaking" then return abort(self,reason) end
    cancel();accept=false;aborted=true;audio:stop_i2s();record("explicit_abort")
    local ok,err=abort(self,reason)
    if not ok then audio:fail(err or "abort send failed");return false,err end
    local current=tmr.create();timer=current
    current:alarm(1500,tmr.ALARM_SINGLE,function()
      if timer~=current then return end
      cancel()
      if alive() and aborted and runtime.state.state=="speaking" then audio:fail("server abort acknowledgement timeout") end
    end)
    return true
  end
  protocol:on("audio",function(packet)
    if alive() and accept and not aborted and runtime.state.state=="speaking" then return on_audio(packet) end
  end)
  protocol:on("tts_start",function(...)
    if not alive() or aborted then return end
    if runtime.state.state~="listening" and runtime.state.state~="speaking" then return end
    cancel();accept=true;record("tts_start")
    if audio.mode=="speak" then audio:stop_i2s() end
    on_start(...)
    if alive() and runtime.state.state=="speaking" then audio:set_mode("speak") end
  end)
  protocol:on("tts_stop",function()
    if not alive() or runtime.state.state~="speaking" then return end
    accept=false;record(aborted and "abort_ack" or "tts_stop")
    audio:finish_playback();drain()
  end)
  protocol:on("closed",function(...)
    cancel();accept=false;aborted=false;return on_closed(...)
  end)
  local stop=runtime.stop
  runtime.stop=function(...)
    cancel();accept=false;aborted=false;return stop(...)
  end
end
return M
