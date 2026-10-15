-- Exclusive native RX/Opus or TX/Opus; no simultaneous capture and playback.
local M={}
function M.new(cfg)
  local self={cfg=cfg,mode="off",voice_ready=false,wake_ready=false,wake_missing=false,
    wake_capture_active=false,capture_active=false,play_count=0,send_frames=0,
    wake_frames=0,detect_count=0,pcm_bytes=0,level=0,last_error=""}
  local timer,generation,ticks=nil,0,0
  local function call(fn,...)
    if not fn then return false,"native API missing" end
    local ok,value,err=pcall(fn,...)
    if not ok then return false,tostring(value) end
    return value,err
  end
  function self:fail(message)
    if self.last_error~="" then return false end
    message=tostring(message or "unknown audio error")
    if not message:find("^audio:") then message="audio: "..message end
    self.last_error,self.last_failure=message,message
    self:stop_i2s()
    if self.on_error then self.on_error(message) end
    return false
  end
  function self:info()
    return {mode=self.mode,wake_ready=self.wake_ready,wake_missing=self.wake_missing,
      wake_capture_active=self.wake_capture_active,voice_ready=self.voice_ready,
      pcm_bytes=self.pcm_bytes,send_frames=self.send_frames,wake_frames=self.wake_frames,
      detect_count=self.detect_count,play_count=self.play_count,level=self.level,last_error=self.last_error}
  end
  function self:begin_wake_bridge() return false end
  function self:is_wake_bridge() return false end
  function self:start_codecs()
    if self.voice_ready then return true end
    if not self.voice then
      local ok,mod=pcall(require,cfg.XZ_MODULE)
      if not ok or type(mod)~="table" then return self:fail("voice module load: "..tostring(mod)) end
      self.voice=mod.voice
    end
    local ok,err=call(self.voice and self.voice.start,{
      rate=cfg.AUDIO.rate,channels=cfg.AUDIO.channels,frame_ms=cfg.AUDIO.frame_ms,
      tx=true,rx=true,hold_audio=false,bitrate=cfg.AUDIO.bitrate,complexity=cfg.AUDIO.complexity})
    if not ok then return self:fail(err or "codec start failed") end
    self.voice_ready=true;call(self.voice.set_volume,cfg.AUDIO.volume or 0);return true
  end
  function self:start_wake_model()
    if self.wake_ready then return true end
    if not file.exists(cfg.WAKE_INDEX) or not file.exists(cfg.WAKE_DATA) then
      self.wake_missing=true;return self:fail("wake model missing")
    end
    if not self.wake then
      local ok,mod=pcall(require,cfg.WAKE_MODULE)
      if not ok or type(mod)~="table" then return self:fail("wake module load: "..tostring(mod)) end
      self.wake=mod
    end
    local ok,err=call(self.wake.start,{model=cfg.WAKE_MODEL,model_root=cfg.WAKE_ROOT})
    if not ok then return self:fail(err or "wake model start failed") end
    self.wake_ready,self.wake_missing=true,false;return true
  end
  function self:stop_i2s()
    generation=generation+1
    if timer then timer:stop();timer:unregister();timer=nil end
    if self.playback_queue then self.playback_queue:clear() end
    if self.wake_capture_active then call(self.wake.capture_stop) end
    if self.capture_active then call(self.voice.capture_stop) end
    if self.playback_active then
      local status=call(self.voice.playback_status)
      if type(status)=="table" then self.last_native_status=status end
      call(self.voice.playback_stop)
    end
    self.wake_capture_active,self.capture_active,self.playback_active=false,false,false
    self.playback_finishing,self.finish_sent=false,false
    self.mode="off"
  end
  local function poll()
    local serial=generation;ticks=ticks+1
    if self.mode=="wake" then
      local status,err=call(self.wake.capture_read)
      if type(status)~="table" then return self:fail(err or "wake read failed") end
      self.wake_frames=status.frames or self.wake_frames
      if status.ok==false or status.running==false then return self:fail(status.error or "wake worker stopped") end
      if status.detected or (status.detections or 0)>0 then
        self.detect_count=self.detect_count+math.max(1,status.detections or 0)
        if self.on_wake then self.on_wake(cfg.WAKE_WORD) end
      end
    elseif self.mode=="listen" then
      if ticks%5==0 then
        local status,err=call(self.voice.info)
        if type(status)~="table" or not status.capture_running then
          return self:fail(type(status)=="table" and status.last_error~="" and status.last_error or err or "capture worker stopped")
        end
        self.last_native_status=status
      end
      for _=1,6 do
        local packet,err=call(self.voice.capture_read)
        if err then return self:fail(err) end
        if type(packet)~="string" or #packet==0 then break end
        if self.on_send then
          local ok,why=self.on_send(packet)
          if not ok then return self:fail(why or "microphone upload failed") end
        end
        self.send_frames=self.send_frames+1
        if generation~=serial then return end
      end
    elseif self.mode=="speak" then
      local status,err=call(self.voice.playback_status)
      if type(status)~="table" then return self:fail(err or "playback status failed") end
      self.last_native_status=status
      if status.error and status.error~="" then return self:fail(status.error) end
      if not status.running and not status.drained then return self:fail("playback worker stopped") end
      local ok,why=self.playback_queue:drain()
      if not ok then return self:fail(why) end
      if self.playback_finishing and not self.finish_sent and self.playback_queue:count()==0 then
        local finished,why=call(self.voice.playback_finish)
        if not finished then return self:fail(why) end
        self.finish_sent=true
      end
    end
  end
  function self:set_mode(mode)
    if mode==self.mode then return true end
    self:stop_i2s()
    if mode=="off" then return true end
    if self.last_error~="" then return false end
    local ok,err
    if mode=="wake" then
      if not self:start_wake_model() then return false end
      ok,err=call(self.wake.capture_start,{
        bits=32,i2s_id=cfg.AUDIO.i2s_id,bclk_pin=41,ws_pin=45,din_pin=42,
        buffer_count=4,pack="b23",gain_shift=cfg.AUDIO.wake_gain_shift or 0,
        task_stack=8192,priority=2,core=0,read_timeout_ms=100})
      self.wake_capture_active=ok==true
    elseif mode=="listen" then
      if not self:start_codecs() then return false end
      ok,err=call(self.voice.capture_start,{
        rate=cfg.AUDIO.rate,bits=32,i2s_id=cfg.AUDIO.i2s_id,bclk_pin=41,ws_pin=45,din_pin=42,
        buffer_count=4,buffer_len=128,pack="b23",gain_shift=cfg.AUDIO.tx_gain_shift or 0,
        queue_depth=6,task_stack=32768,priority=2,core=0,read_timeout_ms=100})
      self.capture_active=ok==true
    elseif mode=="speak" then
      if not self:start_codecs() then return false end
      call(self.voice.set_volume,cfg.AUDIO.volume or 0)
      ok,err=call(self.voice.playback_start)
      self.playback_active=ok==true
      self.playback_queue=dofile(cfg.APP_DIR.."/playback_queue.lua").new(
        function(packet)return self.voice.playback_write(packet)end,256,256*1024)
    else return self:fail("invalid audio mode") end
    if not ok then return self:fail(err or ("cannot start "..mode)) end
    self.mode=mode;ticks=0;timer=tmr.create()
    timer:alarm(mode=="wake" and 60 or 40,tmr.ALARM_AUTO,function()
      local ok,err=pcall(poll);if not ok then self:fail(err) end
    end)
    return true
  end
  function self:set_volume(value)
    cfg.AUDIO.volume=math.max(0,math.min(100,tonumber(value) or 0))
    if self.voice then call(self.voice.set_volume,cfg.AUDIO.volume) end
  end
  function self:finish_playback() self.playback_finishing=true end
  function self:playback_pending()
    if not self.playback_active then return false end
    if self.playback_queue:count()>0 or not self.finish_sent then return true end
    local status,err=call(self.voice.playback_status)
    if type(status)~="table" then self:fail(err);return true end
    self.last_native_status=status
    if status.error and status.error~="" then self:fail(status.error);return true end
    return not status.drained
  end
  function self:play_opus(packet)
    if self.mode~="speak" then return self:fail("packet outside playback phase") end
    local ok,err=self.playback_queue:push(packet)
    if not ok then return self:fail(err) end
    self.play_count=self.play_count+1;return true
  end
  function self:stop()
    self:stop_i2s()
    if self.wake then call(self.wake.stop) end
    if self.voice then call(self.voice.stop) end
    self.wake_ready,self.voice_ready=false,false
  end
  return self
end
return M
