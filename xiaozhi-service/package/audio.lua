local M = {}

local string_byte = string.byte
local string_char = string.char
local string_sub = string.sub
local table_concat = table.concat
local table_remove = table.remove
local WAKE_INIT_RETRY_MAX = 5
local WAKE_INIT_RETRY_DELAY_MS = 500

local function pcall_fn(fn, ...)
  if not fn then
    return false, "missing function"
  end
  return pcall(fn, ...)
end

local function file_exists(path)
  if file and file.exists then
    local ok, ret = pcall(function() return file.exists(path) end)
    if ok and ret then
      return true
    end
  end
  if file and file.stat then
    local ok, st = pcall(function() return file.stat(path) end)
    return ok and st ~= nil
  end
  return false
end

local function clip_s16(v)
  if v > 32767 then
    return 32767
  end
  if v < -32768 then
    return -32768
  end
  return v
end

local function pack_offsets(pack)
  if pack == "b01" then
    return 0, 1
  elseif pack == "b12" then
    return 1, 2
  end
  return 2, 3
end

-- 将常见 I2S 32-bit 麦克风样本转换成 WakeNet/Opus 需要的 s16 little-endian PCM。
local function i2s32_to_s16(raw, pack, gain_shift)
  pack = pack or "b23"
  gain_shift = tonumber(gain_shift) or 0
  local lo_off, hi_off = pack_offsets(pack)
  if pack == "b23" and gain_shift == 0 then
    local out = {}
    local n = 0
    local len = #raw - 3
    for i = 1, len, 4 do
      n = n + 1
      out[n] = string_char(string_byte(raw, i + 2), string_byte(raw, i + 3))
    end
    return table_concat(out)
  end

  local out = {}
  local n = 0
  local len = #raw - 3
  local gain = 1
  if gain_shift > 0 then
    gain = 2 ^ math.min(gain_shift, 8)
  end
  for i = 1, len, 4 do
    local lo = string_byte(raw, i + lo_off) or 0
    local hi = string_byte(raw, i + hi_off) or 0
    local v = lo + hi * 256
    if v >= 32768 then
      v = v - 65536
    end
    if gain ~= 1 then
      v = clip_s16(v * gain)
    end
    if v < 0 then
      v = v + 65536
    end
    n = n + 1
    out[n] = string_char(v % 256, math.floor(v / 256) % 256)
  end
  return table_concat(out)
end

local function le16(v)
  v = math.floor(v) % 65536
  return string_char(v % 256, math.floor(v / 256) % 256)
end

local function le32(v)
  v = math.floor(v) % 4294967296
  local b0 = v % 256
  local b1 = math.floor(v / 256) % 256
  local b2 = math.floor(v / 65536) % 256
  local b3 = math.floor(v / 16777216) % 256
  return string_char(b0, b1, b2, b3)
end

local function wav_s16(pcm, rate, channels)
  channels = tonumber(channels) or 1
  rate = tonumber(rate) or 16000
  local data_len = #pcm
  local byte_rate = rate * channels * 2
  local block_align = channels * 2
  return "RIFF" .. le32(36 + data_len) .. "WAVE" ..
    "fmt " .. le32(16) .. le16(1) .. le16(channels) .. le32(rate) ..
    le32(byte_rate) .. le16(block_align) .. le16(16) ..
    "data" .. le32(data_len) .. pcm
end

local function pcm_level_s16(pcm)
  local max_abs = 0
  local len = #pcm - 1
  for i = 1, len, 64 do
    local lo, hi = string_byte(pcm, i, i + 1)
    if lo and hi then
      local v = lo + hi * 256
      if v >= 32768 then
        v = v - 65536
      end
      if v < 0 then
        v = -v
      end
      if v > max_abs then
        max_abs = v
      end
    end
  end
  return math.floor(max_abs * 100 / 32768)
end

local function i2s32_level(raw, pack, gain_shift)
  local lo_off, hi_off = pack_offsets(pack or "b23")
  local max_abs = 0
  local gain = 1
  if gain_shift and gain_shift > 0 then
    gain = 2 ^ math.min(gain_shift, 8)
  end
  local len = #raw - 3
  for i = 1, len, 128 do
    local lo = string_byte(raw, i + lo_off) or 0
    local hi = string_byte(raw, i + hi_off) or 0
    local v = lo + hi * 256
    if v >= 32768 then
      v = v - 65536
    end
    if gain ~= 1 then
      v = clip_s16(v * gain)
    end
    if v < 0 then
      v = -v
    end
    if v > max_abs then
      max_abs = v
    end
  end
  return math.floor(max_abs * 100 / 32768)
end

local function pcm_stats_s16(pcm)
  local count = 0
  local max_abs = 0
  local sum = 0
  local sum_sq_norm = 0
  local clipped = 0
  local len = #pcm - 1
  for i = 1, len, 2 do
    local lo, hi = string_byte(pcm, i, i + 1)
    if lo and hi then
      local v = lo + hi * 256
      if v >= 32768 then
        v = v - 65536
      end
      local a = v < 0 and -v or v
      if a > max_abs then
        max_abs = a
      end
      if a >= 32760 then
        clipped = clipped + 1
      end
      count = count + 1
      sum = sum + v
      local norm = v / 32768
      sum_sq_norm = sum_sq_norm + norm * norm
    end
  end
  if count == 0 then
    return { samples = 0, max_pct = 0, rms_pct = 0, dc = 0, clipped = 0 }
  end
  return {
    samples = count,
    max_pct = math.floor(max_abs * 1000 / 32768) / 10,
    rms_pct = math.floor(math.sqrt(sum_sq_norm / count) * 1000) / 10,
    dc = math.floor(sum / count),
    clipped = clipped,
  }
end

local function write_file(path, data)
  if file and file.putcontents then
    local ok, ret = pcall(function() return file.putcontents(path, data) end)
    if ok and ret then
      return true
    end
  end
  if not file or not file.open then
    return false
  end
  local fd = file.open(path, "w+")
  if not fd then
    return false
  end
  local ok = fd:write(data)
  fd:close()
  return ok and true or false
end

function M.new(cfg)
  local self = {
    cfg = cfg,
    xiaozhi = nil,
    voice = nil,
    wake = nil,
    mode = "off",
    timer = nil,
    wake_retry_timer = nil,
    wake_retry_count = 0,
    rx_pending = "",
    wake_pending = "",
    send_pending = "",
    raw_send_pending = "",
    pre_raw = {},
    pre_raw_bytes = 0,
    bridge_raw = {},
    bridge_raw_bytes = 0,
    bridge_started = false,
    wake_ready = false,
    wake_missing = false,
    voice_ready = false,
    frame_pcm_bytes = math.floor(((cfg.AUDIO.rate or 16000) * (cfg.AUDIO.frame_ms or 60) / 1000)) * 2,
    wake_chunk_bytes = 1024,
    read_raw_bytes = 2048,
    pcm_bytes = 0,
    send_frames = 0,
    wake_frames = 0,
    detect_count = 0,
    play_count = 0,
    level = 0,
    last_error = "",
    on_wake = nil,
    on_send = nil,
    on_error = nil,
    capture = nil,
    capture_done = false,
    capture_active = false,
    wake_capture_active = false,
    polling = false,
  }
  local cancel_wake_retry

  local function set_error(msg)
    self.last_error = tostring(msg or "")
    if self.on_error and self.last_error ~= "" then
      pcall(self.on_error, self.last_error)
    end
  end

  local function module_owned_elsewhere(message)
    return type(message) == "string"
        and message:find("module already loaded by another runtime", 1, true) ~= nil
  end

  local function pack_for_mode(mode)
    if mode == "wake" then
      return cfg.AUDIO.wake_mic_pack or cfg.AUDIO.mic_pack or "b23"
    elseif mode == "listen" or mode == "bridge" then
      return cfg.AUDIO.tx_mic_pack or cfg.AUDIO.mic_pack or "b23"
    end
    return cfg.AUDIO.mic_pack or "b23"
  end

  local function raw_bytes_for_ms(ms, rate)
    rate = tonumber(rate) or tonumber(cfg.AUDIO.rate) or 16000
    return math.floor(rate * (tonumber(ms) or 0) / 1000) * 4
  end

  local function push_limited(chunks, total, limit, raw)
    limit = math.floor(tonumber(limit) or 0)
    if not raw or #raw == 0 or limit <= 0 then
      return total
    end
    chunks[#chunks + 1] = raw
    total = total + #raw
    while total > limit and #chunks > 1 do
      total = total - #chunks[1]
      table_remove(chunks, 1)
    end
    if total > limit and #chunks == 1 then
      chunks[1] = string_sub(chunks[1], #chunks[1] - limit + 1)
      total = #chunks[1]
    end
    return total
  end

  local function clear_prebuffer()
    self.pre_raw = {}
    self.pre_raw_bytes = 0
  end

  local function clear_bridge()
    self.bridge_raw = {}
    self.bridge_raw_bytes = 0
    self.bridge_started = false
  end

  local function push_pre_raw(raw)
    self.pre_raw_bytes = push_limited(
      self.pre_raw,
      self.pre_raw_bytes,
      raw_bytes_for_ms(cfg.AUDIO.wake_preroll_ms or 480, cfg.AUDIO.wake_rate or 16000),
      raw)
  end

  local function push_bridge_raw(raw)
    local ms = (tonumber(cfg.AUDIO.wake_preroll_ms) or 480) +
      (tonumber(cfg.AUDIO.wake_bridge_ms) or 900)
    self.bridge_raw_bytes = push_limited(
      self.bridge_raw,
      self.bridge_raw_bytes,
      raw_bytes_for_ms(ms, cfg.AUDIO.wake_rate or 16000),
      raw)
  end

  local function copy_pre_to_bridge()
    self.bridge_raw = {}
    for i = 1, #self.pre_raw do
      self.bridge_raw[i] = self.pre_raw[i]
    end
    self.bridge_raw_bytes = self.pre_raw_bytes
  end

  function self:info()
    return {
      mode = self.mode,
      wake_ready = self.wake_ready,
      wake_missing = self.wake_missing,
      voice_ready = self.voice_ready,
      pcm_bytes = self.pcm_bytes,
      send_frames = self.send_frames,
      wake_frames = self.wake_frames,
      detect_count = self.detect_count,
      play_count = self.play_count,
      level = self.level,
      bridge_bytes = self.bridge_raw_bytes,
      last_error = self.last_error,
    }
  end

  function self:begin_wake_bridge()
    if cfg.AUDIO.wake_bridge_enabled == false then
      return false
    end
    if self.mode == "bridge" then
      return true
    end
    if self.mode ~= "wake" then
      return false
    end
    copy_pre_to_bridge()
    self.bridge_started = true
    self.mode = "bridge"
    self.wake_pending = ""
    print("[xiaozhi] wake bridge start raw=" .. tostring(self.bridge_raw_bytes))
    return true
  end

  function self:is_wake_bridge()
    return self.mode == "bridge" or self.bridge_started
  end

  function self:load_wake_module()
    if self.wake then return true end
    local wake_ok, wake_mod = pcall(require, cfg.WAKE_MODULE)
    if wake_ok and type(wake_mod) == "table" then
      self.wake = wake_mod
      return true
    end
    print("[xiaozhi] wake require failed", wake_mod)
    set_error(tostring(wake_mod or "wake module load failed"))
    return false
  end

  function self:load_modules()
    local ok, mod = pcall(require, cfg.XZ_MODULE)
    if not ok or type(mod) ~= "table" then
      set_error("xiaozhi.so load failed")
      print("[xiaozhi] require failed", mod)
      return false
    end
    self.xiaozhi = mod.xz or rawget(_G, "xz")
    self.voice = mod.voice or rawget(_G, "voice")
    if not self.voice or not self.voice.start then
      set_error("voice api missing")
      return false
    end

    return true
  end

  function self:start_codecs()
    if self.voice_ready then
      return true
    end
    -- WakeNet and Opus do not need to be resident at the same time. Stop the
    -- native wake capture/backend before creating the xiaozhi codecs, while
    -- keeping wake.so loaded so returning to wake mode does not relocate ELF.
    cancel_wake_retry()
    if self.wake_capture_active and self.wake and self.wake.capture_stop then
      pcall(function() self.wake.capture_stop() end)
      self.wake_capture_active = false
    end
    if self.wake_ready and self.wake and self.wake.stop then
      pcall(self.wake.stop)
      self.wake_ready = false
    end
    if not self.voice and not self:load_modules() then
      return false
    end
    local ok, ret, err = pcall(self.voice.start, {
      rate = cfg.AUDIO.rate,
      channels = cfg.AUDIO.channels,
      frame_ms = cfg.AUDIO.frame_ms,
      tx = true,
      rx = true,
      hold_audio = false,
      bitrate = cfg.AUDIO.bitrate,
      complexity = cfg.AUDIO.complexity,
    })
    if not ok or not ret then
      set_error(tostring(err or ret or "voice.start failed"))
      return false
    end
    self.voice_ready = true
    if self.voice.info then
      local info_ok, info = pcall(self.voice.info)
      if info_ok and type(info) == "table" then
        self.frame_pcm_bytes = tonumber(info.frame_pcm_bytes) or self.frame_pcm_bytes
      end
    end
    return true
  end

  function self:start_wake_model()
    if self.wake_ready then
      return true
    end
    if not file_exists(cfg.WAKE_INDEX) or not file_exists(cfg.WAKE_DATA) then
      self.wake_missing = true
      set_error("wake model missing")
      print("[xiaozhi] missing wake model", cfg.WAKE_INDEX, cfg.WAKE_DATA)
      return false
    end
    if not self.wake and not self:load_wake_module() then
      return false
    end
    if not self.wake or not self.wake.start then
      set_error("wake api missing")
      return false
    end
    local ok, ret, err = pcall(self.wake.start)
    if not ok or not ret then
      set_error(tostring(err or ret or "wake.start failed"))
      return false
    end
    self.wake_ready = true
    self.wake_missing = false
    if self.wake.info then
      local info_ok, info = pcall(self.wake.info)
      if info_ok and type(info) == "table" then
        local samples = tonumber(info.chunk_samples)
        if samples and samples > 0 then
          self.wake_chunk_bytes = samples * 2
        end
      end
    end
    return true
  end

  local function stop_timer()
    if self.timer then
      pcall(function() self.timer:stop() end)
      pcall(function() self.timer:unregister() end)
      self.timer = nil
    end
  end

  cancel_wake_retry = function()
    local timer = self.wake_retry_timer
    self.wake_retry_timer = nil
    self.wake_retry_count = 0
    if timer then
      pcall(function() timer:stop() end)
      pcall(function() timer:unregister() end)
    end
  end

  local function schedule_wake_retry()
    if not module_owned_elsewhere(self.last_error) then
      return false
    end
    if self.wake_retry_count >= WAKE_INIT_RETRY_MAX then
      return false
    end
    if not tmr or not tmr.create then
      return false
    end
    if self.wake_retry_timer then
      return true
    end
    self.wake_retry_count = self.wake_retry_count + 1
    local attempt = self.wake_retry_count
    local timer = tmr.create()
    self.wake_retry_timer = timer
    print("[xiaozhi] wake init retry", tostring(attempt), "/" .. tostring(WAKE_INIT_RETRY_MAX))
    timer:alarm(WAKE_INIT_RETRY_DELAY_MS, tmr.ALARM_SINGLE, function(instance)
      pcall(function() instance:unregister() end)
      if self.wake_retry_timer ~= timer then return end
      self.wake_retry_timer = nil
      if self.mode == "off" then
        self:set_mode("wake")
      end
    end)
    return true
  end

  local function start_capture(mode)
    if self.capture_done or not cfg.AUDIO.capture_once or mode ~= "listen" then
      return
    end
    local ms = tonumber(cfg.AUDIO.capture_ms) or 1600
    local pcm_limit = math.floor((cfg.AUDIO.rate or 16000) * ms / 1000) * 2
    if pcm_limit < 3200 then
      pcm_limit = 3200
    end
    self.capture = {
      dir = (cfg.APP_DIR or "/sd/apps/xiaozhi-service") .. "/diag",
      raw = {},
      pcm = {},
      raw_bytes = 0,
      pcm_bytes = 0,
      pcm_limit = pcm_limit,
      mode = mode,
    }
    if file and file.mkdir then
      pcall(function() file.mkdir(self.capture.dir) end)
    end
    print("[xiaozhi] mic capture start", tostring(ms) .. "ms")
  end

  local function finish_capture(reason)
    local cap = self.capture
    if not cap then
      return
    end
    self.capture = nil
    self.capture_done = true
    local raw = table_concat(cap.raw)
    local pcm_current = table_concat(cap.pcm)
    local dir = cap.dir
    local variants = { "b01", "b12", "b23" }
    local lines = {
      "reason=" .. tostring(reason or "done"),
      "rate=" .. tostring(cfg.AUDIO.rate or 16000),
      "channels=1",
      "mic_bits=" .. tostring(cfg.AUDIO.mic_bits or 32),
      "mic_pack=" .. tostring(cfg.AUDIO.mic_pack or "b23"),
      "mic_gain_shift=" .. tostring(cfg.AUDIO.mic_gain_shift or 0),
      "raw_bytes=" .. tostring(#raw),
      "pcm_bytes=" .. tostring(#pcm_current),
    }

    write_file(dir .. "/mic_raw_32.i2s", raw)
    write_file(dir .. "/mic_current.wav", wav_s16(pcm_current, cfg.AUDIO.rate or 16000, 1))

    for _, pack in ipairs(variants) do
      local pcm = i2s32_to_s16(raw, pack, 0)
      local st = pcm_stats_s16(pcm)
      lines[#lines + 1] = string.format(
        "%s samples=%d max=%.1f%% rms=%.1f%% dc=%d clipped=%d",
        pack, st.samples, st.max_pct, st.rms_pct, st.dc, st.clipped)
      write_file(dir .. "/mic_" .. pack .. ".wav", wav_s16(pcm, cfg.AUDIO.rate or 16000, 1))
    end

    local current_stats = pcm_stats_s16(pcm_current)
    lines[#lines + 1] = string.format(
      "current samples=%d max=%.1f%% rms=%.1f%% dc=%d clipped=%d",
      current_stats.samples, current_stats.max_pct, current_stats.rms_pct,
      current_stats.dc, current_stats.clipped)
    write_file(dir .. "/mic_stats.txt", table_concat(lines, "\n") .. "\n")
    print("[xiaozhi] mic capture saved", dir)
  end

  local function feed_capture(raw, pcm)
    local cap = self.capture
    if not cap then
      return
    end
    cap.raw[#cap.raw + 1] = raw
    cap.pcm[#cap.pcm + 1] = pcm
    cap.raw_bytes = cap.raw_bytes + #raw
    cap.pcm_bytes = cap.pcm_bytes + #pcm
    if cap.pcm_bytes >= cap.pcm_limit then
      finish_capture("limit")
    end
  end

  local function stop_i2s()
    if self.capture then
      finish_capture("stop")
    end
    if self.capture_active and self.voice and self.voice.capture_stop then
      pcall(function() self.voice.capture_stop() end)
      self.capture_active = false
    end
    if self.wake_capture_active and self.wake and self.wake.capture_stop then
      pcall(function() self.wake.capture_stop() end)
      self.wake_capture_active = false
    end
    if i2s and i2s.mute then
      pcall(function() i2s.mute(cfg.AUDIO.i2s_id) end)
    end
    if i2s and i2s.stop then
      pcall(function() i2s.stop(cfg.AUDIO.i2s_id) end)
    end
  end

  function self:stop_i2s()
    stop_timer()
    stop_i2s()
    self.rx_pending = ""
    self.wake_pending = ""
    self.send_pending = ""
    self.raw_send_pending = ""
    clear_prebuffer()
    clear_bridge()
    self.mode = "off"
  end

  function self:release_wake_module()
    cancel_wake_retry()
    if self.wake and self.wake.stop then
      pcall(self.wake.stop)
    end
    self.wake_ready = false
    self.wake_missing = false
    -- Keep the dynmod resident for this Lua runtime. Clearing package.loaded
    -- here made every wake/listen transition relocate the full WakeNet ELF on
    -- lua_update's stack. The runtime unloads dynmods when the Service exits.
  end

  function self:release_codecs(unload_module)
    if self.capture_active and self.voice and self.voice.capture_stop then
      pcall(function() self.voice.capture_stop() end)
    end
    self.capture_active = false
    if self.voice and self.voice.stop then
      pcall(self.voice.stop)
    end
    self.voice_ready = false
    -- Keep xiaozhi.so resident too. Requiring it again after every idle/listen
    -- transition adds another expensive ELF relocation on the Lua task stack.
  end

  local function start_rx(samples, sample_rate)
    if not i2s or not i2s.start or not i2s.read then
      set_error("i2s missing")
      return false
    end
    stop_i2s()
    if collectgarbage then pcall(collectgarbage, "collect") end
    local requested = math.max(2, math.floor(tonumber(cfg.AUDIO.rx_buffer_count) or 4))
    local counts, seen = {}, {}
    for _, count in ipairs({ requested, 4, 3, 2 }) do
      if count <= requested and not seen[count] then
        seen[count] = true
        counts[#counts + 1] = count
      end
    end
    local last_error = nil
    for _, count in ipairs(counts) do
      local ok, ret = pcall(i2s.start, cfg.AUDIO.i2s_id, {
        mode = i2s.MODE_MASTER | i2s.MODE_RX,
        rate = sample_rate or cfg.AUDIO.rate,
        bits = cfg.AUDIO.mic_bits,
        channel = i2s.CHANNEL_ONLY_LEFT,
        format = i2s.FORMAT_I2S,
        buffer_count = count,
        buffer_len = samples,
      })
      if ok and ret ~= false then
        if count ~= requested then
          print("[xiaozhi] i2s rx DMA fallback buffers=" .. tostring(count))
        end
        return true
      end
      last_error = ret
      pcall(function() i2s.stop(cfg.AUDIO.i2s_id) end)
    end
    set_error(tostring(last_error or "i2s.start rx failed"))
    return false
  end

  local function start_tx()
    if not i2s or not i2s.start or not i2s.write then
      set_error("i2s missing")
      return false
    end
    stop_i2s()
    if collectgarbage then pcall(collectgarbage, "collect") end
    local requested = math.max(2, math.floor(tonumber(cfg.AUDIO.tx_buffer_count) or 4))
    local counts, seen = {}, {}
    for _, count in ipairs({ requested, 4, 3, 2 }) do
      if count <= requested and not seen[count] then
        seen[count] = true
        counts[#counts + 1] = count
      end
    end
    local last_error = nil
    for _, count in ipairs(counts) do
      local ok, ret = pcall(i2s.start, cfg.AUDIO.i2s_id, {
        mode = i2s.MODE_MASTER | i2s.MODE_TX,
        rate = cfg.AUDIO.rate,
        bits = 16,
        channel = i2s.CHANNEL_ONLY_LEFT,
        format = i2s.FORMAT_I2S,
        buffer_count = count,
        buffer_len = 512,
        data_out_pin = 48,
      })
      if ok and ret ~= false then
        if count ~= requested then
          print("[xiaozhi] i2s tx DMA fallback buffers=" .. tostring(count))
        end
        return true
      end
      last_error = ret
      pcall(function() i2s.stop(cfg.AUDIO.i2s_id) end)
    end
    set_error(tostring(last_error or "i2s.start tx failed"))
    return false
  end

  local function handle_wake_result(ok, ret, err)
    if not ok or type(ret) ~= "table" then
      set_error(tostring(err or ret or "wake.feed failed"))
      return false
    end
    self.wake_frames = self.wake_frames + (tonumber(ret.frames) or 0)
    local detections = tonumber(ret.detections) or 0
    if ret.detected or detections > 0 or (tonumber(ret.state) or 0) > 0 then
      self.detect_count = self.detect_count + (detections > 0 and detections or 1)
      if self.on_wake then
        pcall(self.on_wake, cfg.WAKE_WORD)
      end
      return true
    end
    return false
  end

  local function feed_wake_pcm(pcm)
    if not self.wake_ready or not self.wake or not self.wake.feed then
      return
    end
    self.wake_pending = self.wake_pending .. pcm
    while #self.wake_pending >= self.wake_chunk_bytes do
      local frame = string_sub(self.wake_pending, 1, self.wake_chunk_bytes)
      self.wake_pending = string_sub(self.wake_pending, self.wake_chunk_bytes + 1)
      local ok, ret, err = pcall(self.wake.feed, frame)
      if handle_wake_result(ok, ret, err) then
        return
      end
    end
  end

  local function feed_wake_i2s(raw, gain_shift)
    if not self.wake_ready or not self.wake then
      return
    end
    local pack = pack_for_mode("wake")
    if self.wake.feed_i2s_fast then
      local ok, detected, frames, detections, state = pcall(
        self.wake.feed_i2s_fast, raw, pack, gain_shift)
      if not ok or type(detected) ~= "boolean" then
        set_error(tostring(frames or detected or "wake.feed_i2s_fast failed"))
        return
      end
      self.wake_frames = self.wake_frames + (tonumber(frames) or 0)
      detections = tonumber(detections) or 0
      if detected or detections > 0 or (tonumber(state) or 0) > 0 then
        self.detect_count = self.detect_count + (detections > 0 and detections or 1)
        if self.on_wake then pcall(self.on_wake, cfg.WAKE_WORD) end
      end
      return
    end
    if not self.wake.feed_i2s then
      feed_wake_pcm(i2s32_to_s16(raw, pack, gain_shift))
      return
    end
    local ok, ret, err = pcall(self.wake.feed_i2s, raw, pack, gain_shift)
    handle_wake_result(ok, ret, err)
  end

  local function send_pcm(pcm)
    if not self.voice_ready or not self.voice or not self.voice.encode then
      return
    end
    self.send_pending = self.send_pending .. pcm
    local max_pending = self.frame_pcm_bytes * (tonumber(cfg.AUDIO.tx_pending_frames) or 3)
    if #self.send_pending > max_pending then
      self.send_pending = string_sub(self.send_pending, #self.send_pending - max_pending + 1)
    end
    local encoded = 0
    local max_frames = tonumber(cfg.AUDIO.max_encode_frames_per_poll) or 1
    while #self.send_pending >= self.frame_pcm_bytes do
      if encoded >= max_frames then
        return
      end
      local frame = string_sub(self.send_pending, 1, self.frame_pcm_bytes)
      self.send_pending = string_sub(self.send_pending, self.frame_pcm_bytes + 1)
      local ok, opus_or_err = pcall(self.voice.encode, frame)
      if ok and type(opus_or_err) == "string" then
        self.send_frames = self.send_frames + 1
        encoded = encoded + 1
        if self.on_send then
          pcall(self.on_send, opus_or_err)
        end
      else
        set_error(tostring(opus_or_err or "voice.encode failed"))
        return
      end
    end
  end

  local function send_raw_i2s(raw, gain_shift)
    if not self.voice_ready or not self.voice then
      return
    end
    local pack = pack_for_mode("listen")
    if not self.voice.encode_i2s then
      send_pcm(i2s32_to_s16(raw, pack, gain_shift))
      return
    end

    local frame_raw_bytes = self.frame_pcm_bytes * 2
    self.raw_send_pending = self.raw_send_pending .. raw
    local max_pending = frame_raw_bytes * (tonumber(cfg.AUDIO.tx_pending_frames) or 3)
    if #self.raw_send_pending > max_pending then
      self.raw_send_pending = string_sub(self.raw_send_pending, #self.raw_send_pending - max_pending + 1)
    end

    local encoded = 0
    local max_frames = tonumber(cfg.AUDIO.max_encode_frames_per_poll) or 1
    while #self.raw_send_pending >= frame_raw_bytes do
      if encoded >= max_frames then
        return
      end
      local frame = string_sub(self.raw_send_pending, 1, frame_raw_bytes)
      self.raw_send_pending = string_sub(self.raw_send_pending, frame_raw_bytes + 1)
      local ok, opus_or_err = pcall(self.voice.encode_i2s, frame, pack, gain_shift)
      if ok and type(opus_or_err) == "string" then
        self.send_frames = self.send_frames + 1
        encoded = encoded + 1
        if self.on_send then
          pcall(self.on_send, opus_or_err)
        end
      else
        set_error(tostring(opus_or_err or "voice.encode_i2s failed"))
        return
      end
    end
  end

  local poll_rx

  local function flush_bridge_raw()
    if self.bridge_raw_bytes <= 0 then
      self.bridge_started = false
      clear_prebuffer()
      return
    end
    local chunks = self.bridge_raw
    local bytes = self.bridge_raw_bytes
    clear_bridge()
    clear_prebuffer()
    local keep = raw_bytes_for_ms(cfg.AUDIO.wake_bridge_flush_ms or 240)
    keep = math.floor(keep / 4) * 4
    local raw = ""
    if keep > 0 then
      local tail = {}
      local need = keep
      for i = #chunks, 1, -1 do
        local chunk = chunks[i]
        if #chunk >= need then
          table.insert(tail, 1, string_sub(chunk, #chunk - need + 1))
          break
        end
        table.insert(tail, 1, chunk)
        need = need - #chunk
      end
      raw = table_concat(tail)
    end
    print("[xiaozhi] wake bridge flush raw=" .. tostring(bytes) .. " keep=" .. tostring(#raw))
    local gain_shift = cfg.AUDIO.tx_gain_shift
    if gain_shift == nil then
      gain_shift = cfg.AUDIO.mic_gain_shift
    end
    send_raw_i2s(raw, gain_shift)
  end

  local function start_poll_timer(mode, interval_override)
    if tmr and tmr.create then
      self.timer = tmr.create()
      local interval = interval_override or cfg.AUDIO.poll_ms
      if mode == "wake" then
        interval = cfg.AUDIO.wake_poll_ms or interval
      elseif mode == "listen" then
        interval = cfg.AUDIO.tx_poll_ms or interval
      elseif mode == "bridge" then
        interval = cfg.AUDIO.wake_bridge_poll_ms or cfg.AUDIO.wake_poll_ms or interval
      end
      self.timer:alarm(interval, tmr.ALARM_AUTO, poll_rx)
      return true
    end
    set_error("tmr missing")
    self:stop_i2s()
    return false
  end

  local function poll_rx_body()
    if self.mode ~= "wake" and self.mode ~= "listen" and self.mode ~= "bridge" then
      return
    end

    if self.mode == "wake" and self.wake_capture_active and self.wake.capture_read then
      local ok, ret = pcall(self.wake.capture_read)
      if not ok or type(ret) ~= "table" then
        set_error(tostring(ret or "wake.capture_read failed"))
        self:stop_i2s()
        return
      end
      self.wake_frames = tonumber(ret.frames) or self.wake_frames
      local detections = tonumber(ret.detections) or 0
      if ret.detected or detections > 0 or (tonumber(ret.state) or 0) > 0 then
        self.detect_count = self.detect_count + (detections > 0 and detections or 1)
        if self.on_wake then pcall(self.on_wake, cfg.WAKE_WORD) end
      elseif ret.running == false and ret.error and ret.error ~= "" then
        set_error(ret.error)
        self:stop_i2s()
      end
      return
    end

    if self.mode == "listen" and self.capture_active and self.voice and self.voice.capture_read then
      local max_frames = tonumber(cfg.AUDIO.max_rx_frames_per_poll) or 1
      for _ = 1, max_frames do
        local ok, opus_or_err = pcall(self.voice.capture_read)
        if not ok then
          set_error(tostring(opus_or_err or "voice.capture_read failed"))
          self:stop_i2s()
          return
        end
        if type(opus_or_err) ~= "string" or #opus_or_err == 0 then
          return
        end
        self.send_frames = self.send_frames + 1
        if self.on_send then
          pcall(self.on_send, opus_or_err)
        end
      end
      return
    end

    local function poll_one(wait_ms)
      local need = self.read_raw_bytes - #self.rx_pending
      if need > 0 then
        local ok, chunk = pcall_fn(i2s.read, cfg.AUDIO.i2s_id, need, wait_ms)
        if not ok then
          set_error("i2s.read failed")
          self:stop_i2s()
          return false
        end
        if chunk and #chunk > 0 then
          self.rx_pending = self.rx_pending .. chunk
        end
      end
      if #self.rx_pending < self.read_raw_bytes then
        return false
      end

      local raw = string_sub(self.rx_pending, 1, self.read_raw_bytes)
      self.rx_pending = string_sub(self.rx_pending, self.read_raw_bytes + 1)
      local gain_shift = cfg.AUDIO.mic_gain_shift
      if self.mode == "wake" and cfg.AUDIO.wake_gain_shift ~= nil then
        gain_shift = cfg.AUDIO.wake_gain_shift
      elseif self.mode == "bridge" and cfg.AUDIO.tx_gain_shift ~= nil then
        gain_shift = cfg.AUDIO.tx_gain_shift
      elseif self.mode == "listen" and cfg.AUDIO.tx_gain_shift ~= nil then
        gain_shift = cfg.AUDIO.tx_gain_shift
      end
      if self.mode == "wake" then
        local pack = pack_for_mode("wake")
        if cfg.AUDIO.wake_bridge_enabled ~= false then
          push_pre_raw(raw)
        end
        if self.capture then
          feed_capture(raw, i2s32_to_s16(raw, pack, gain_shift))
        end
        if cfg.AUDIO.level_enabled ~= false then
          self.level = i2s32_level(raw, pack, gain_shift)
        end
        self.pcm_bytes = self.pcm_bytes + math.floor(#raw / 2)
        feed_wake_i2s(raw, gain_shift)
      elseif self.mode == "bridge" then
        local pack = pack_for_mode("bridge")
        if cfg.AUDIO.level_enabled ~= false then
          self.level = i2s32_level(raw, pack, gain_shift)
        end
        self.pcm_bytes = self.pcm_bytes + math.floor(#raw / 2)
        push_bridge_raw(raw)
      elseif self.mode == "listen" then
        local pack = pack_for_mode("listen")
        if self.capture then
          feed_capture(raw, i2s32_to_s16(raw, pack, gain_shift))
        end
        if cfg.AUDIO.level_enabled ~= false then
          self.level = i2s32_level(raw, pack, gain_shift)
        end
        self.pcm_bytes = self.pcm_bytes + math.floor(#raw / 2)
        send_raw_i2s(raw, gain_shift)
      end
      return true
    end

    local max_frames = 1
    if self.mode == "listen" then
      max_frames = tonumber(cfg.AUDIO.max_rx_frames_per_poll) or 1
    end
    for i = 1, max_frames do
      local wait_ms = cfg.AUDIO.read_wait_ms
      if self.mode == "listen" or self.mode == "bridge" then
        wait_ms = cfg.AUDIO.tx_read_wait_ms
      end
      if not poll_one(i == 1 and wait_ms or 0) then
        return
      end
    end
  end

  poll_rx = function()
    if self.polling then
      return
    end
    self.polling = true
    local ok, err = pcall(poll_rx_body)
    self.polling = false
    if not ok then
      set_error(tostring(err or "audio poll failed"))
      self:stop_i2s()
    end
  end

  function self:set_mode(mode)
    if mode == self.mode then
      if mode ~= "wake" then
        cancel_wake_retry()
      end
      return true
    end
    if mode ~= "wake" then
      cancel_wake_retry()
    end
    if self.mode == "bridge" and mode == "listen" then
      stop_timer()
      self.send_pending = ""
      self.raw_send_pending = ""
      self.last_error = ""
      if not self:start_codecs() then
        self:stop_i2s()
        return false
      end
      start_capture(mode)
      self.mode = "listen"
      local chunk_ms = tonumber(cfg.AUDIO.tx_chunk_ms) or 20
      local samples = math.max(160, math.floor((cfg.AUDIO.rate or 16000) * chunk_ms / 1000))
      self.read_raw_bytes = samples * 4
      flush_bridge_raw()
      return start_poll_timer("listen")
    end
    stop_timer()
    stop_i2s()
    self.rx_pending = ""
    self.wake_pending = ""
    self.send_pending = ""
    self.raw_send_pending = ""
    self.mode = "off"
    self.last_error = ""
    if mode ~= "listen" then
      clear_bridge()
    end
    if mode == "wake" or mode == "off" then
      clear_prebuffer()
    end

    if mode == "off" then
      return true
    end
    if mode == "wake" then
      self:release_codecs(true)
      if not self:start_wake_model() then
        schedule_wake_retry()
        return false
      end
      local samples = math.max(256, math.floor(self.wake_chunk_bytes / 2))
      self.read_raw_bytes = samples * 4
      if self.wake.capture_start and not cfg.AUDIO.wake_capture_lua_fallback then
        local ok, ret, err = pcall(self.wake.capture_start, {
          bits = cfg.AUDIO.mic_bits,
          i2s_id = cfg.AUDIO.i2s_id,
          bclk_pin = 41,
          ws_pin = 45,
          din_pin = 42,
          buffer_count = cfg.AUDIO.rx_buffer_count or 4,
          buffer_len = samples,
          pack = cfg.AUDIO.wake_mic_pack or cfg.AUDIO.mic_pack or "b23",
          gain_shift = cfg.AUDIO.wake_gain_shift or cfg.AUDIO.mic_gain_shift or 0,
          task_stack = cfg.AUDIO.wake_capture_task_stack or 32768,
          priority = cfg.AUDIO.wake_capture_task_priority or 2,
          core = cfg.AUDIO.wake_capture_task_core,
          read_timeout_ms = cfg.AUDIO.wake_capture_read_timeout_ms or 100,
        })
        if ok and ret then
          self.wake_capture_active = true
          self.mode = mode
          cancel_wake_retry()
          return start_poll_timer(mode)
        end
        print("[xiaozhi] wake capture_start fallback", tostring(err or ret))
      end
      if not start_rx(samples, cfg.AUDIO.wake_rate or 16000) then
        return false
      end
    elseif mode == "listen" then
      if not self:start_codecs() then
        return false
      end
      start_capture(mode)
      if self.voice.capture_start and not cfg.AUDIO.capture_lua_fallback then
        local ok, ret, err = pcall(self.voice.capture_start, {
          rate = cfg.AUDIO.rate,
          bits = cfg.AUDIO.mic_bits,
          i2s_id = cfg.AUDIO.i2s_id,
          bclk_pin = 41,
          ws_pin = 45,
          din_pin = 42,
          buffer_count = cfg.AUDIO.rx_buffer_count or 8,
          buffer_len = self.frame_pcm_bytes / 2,
          pack = cfg.AUDIO.tx_mic_pack or cfg.AUDIO.mic_pack or "b23",
          gain_shift = cfg.AUDIO.tx_gain_shift or cfg.AUDIO.mic_gain_shift or 0,
          queue_depth = cfg.AUDIO.capture_queue_depth or 6,
          task_stack = cfg.AUDIO.capture_task_stack or 8192,
          priority = cfg.AUDIO.capture_task_priority or 3,
          core = cfg.AUDIO.capture_task_core,
          read_timeout_ms = cfg.AUDIO.capture_read_timeout_ms or 100,
        })
        if ok and ret then
          self.capture_active = true
          self.mode = mode
          return start_poll_timer(mode)
        end
        print("[xiaozhi] capture_start fallback", tostring(err or ret))
      end
      local chunk_ms = tonumber(cfg.AUDIO.tx_chunk_ms) or 20
      local samples = math.max(160, math.floor((cfg.AUDIO.rate or 16000) * chunk_ms / 1000))
      self.read_raw_bytes = samples * 4
      if not start_rx(samples, cfg.AUDIO.rate or 16000) then
        return false
      end
    elseif mode == "speak" then
      if not self:start_codecs() then
        return false
      end
      if not start_tx() then
        return false
      end
      self.mode = "speak"
      return true
    else
      set_error("bad audio mode")
      return false
    end

    self.mode = mode
    if mode == "wake" then
      cancel_wake_retry()
    end
    return start_poll_timer(mode)
  end

  function self:play_opus(opus)
    if not self.voice_ready and not self:start_codecs() then
      return false
    end
    if self.mode ~= "speak" and not self:set_mode("speak") then
      return false
    end
    local ok, pcm_or_err = pcall(self.voice.decode, opus)
    if not ok or type(pcm_or_err) ~= "string" then
      set_error(tostring(pcm_or_err or "voice.decode failed"))
      return false
    end
    local write_ok, write_err = pcall(i2s.write, cfg.AUDIO.i2s_id, pcm_or_err)
    if not write_ok then
      set_error(tostring(write_err or "i2s.write failed"))
      return false
    end
    self.play_count = self.play_count + 1
    return true
  end

  function self:stop()
    self:stop_i2s()
    self:release_wake_module()
    self:release_codecs(true)
  end

  return self
end

return M
