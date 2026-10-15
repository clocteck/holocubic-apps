-- Half-duplex smoke test. No microphone audio is saved or uploaded.
local codec=rawget(_G,"json") or rawget(_G,"sjson")
local result={stage="starting",ok=false,modules={}}
local function save()file.putcontents("/sd/data/xiaozhi/hardware-test.json",codec.encode(result))end
local modules={"/sd/apps/xiaozhi/xiaozhi.so","/sd/apps/xiaozhi-service/xzvoice.so"}
local index,voice,timer=0,nil,nil
local function fail(err)
  if timer then timer:stop();timer:unregister();timer=nil end
  if voice then pcall(voice.stop)end
  result.stage="failed";result.error=tostring(err);save()
end
local function next_module()
  index=index+1
  if index>#modules then result.stage="complete";result.ok=true;save();return end
  local mod=require(modules[index]);voice=mod.voice
  assert(mod.VERSION=="0.5.0","wrong native version")
  assert(voice.start({rate=16000,channels=1,frame_ms=60,bitrate=12000,complexity=0,tx=true,rx=true,hold_audio=false}))
  voice.set_volume(0)
  local packets={}
  -- Known silence, not recorded microphone data. 60 ms packets cross 128-sample blocks.
  for i=1,21 do packets[i]=assert(voice.encode(string.rep(string.char(0),1920)))end
  assert(voice.playback_start())
  for _,packet in ipairs(packets)do assert(voice.playback_write(packet))end
  assert(voice.playback_finish())
  local started=millis()
  local row={version=mod.VERSION,packets=0}
  result.modules[index]=row;result.stage="playback";save()
  timer=tmr.create()
  timer:alarm(40,tmr.ALARM_AUTO,function(t)
    local ok,err=pcall(function()
      if result.stage=="playback" then
        local status=voice.playback_status()
        assert(status.error=="",status.error)
        assert(millis()-started<5000,"playback timeout")
        if status.drained then
          row.playback=status
          assert(status.samples_written==20160 and status.packets_decoded==21,"PCM count mismatch")
          assert(status.underruns==0,"unexpected underrun")
          voice.playback_stop()
          assert(voice.capture_start({rate=16000,bits=32,buffer_count=4,buffer_len=128,
            gain_shift=0,queue_depth=6,task_stack=32768,core=0,priority=2,read_timeout_ms=100}))
          result.stage="capture";started=millis()
        end
      else
        for _=1,6 do if not voice.capture_read()then break end;row.packets=row.packets+1 end
        local info=voice.info();assert(info.capture_running,info.last_error)
        if millis()-started>=2400 then
          row.capture=info;assert(row.packets>=30,"capture stalled")
          assert(info.capture_dropped==0,"capture queue overflow")
          voice.capture_stop();voice.stop()
          t:stop();t:unregister();timer=nil;save();next_module()
        end
      end
    end)
    if not ok then fail(err)end
  end)
end
save()
local ok,err=pcall(next_module);if not ok then fail(err)end
