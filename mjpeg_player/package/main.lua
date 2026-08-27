local previous = rawget(_G, "MJPEG_PLAYER_APP")
if previous and previous.shutdown then
  pcall(function() previous.shutdown("reload") end)
end

MJPEG_PLAYER_APP = {}
local APP = MJPEG_PLAYER_APP
APP.VERSION = "1.0.1"

local SCREEN_W = 320
local SCREEN_H = 240
local TARGET_FPS = 20
local FRAME_INTERVAL_MS = 1000 / TARGET_FPS
-- Keep panel ownership with LVGL.  The native worker decodes straight into
-- one of two persistent, 16-byte-aligned LVGL image slots; Lua switches the
-- image source only after a complete frame is ready, so no full-frame copy is
-- needed and Launcher keeps its normal display lifecycle.
local SAFE_LVGL_PRESENT = true
-- Keep decoding and I2S outside the Lua/UI task.  Synchronous JPEG decoding can
-- starve the HTTP callback that performs the pre-exit cleanup.  The native
-- worker now follows a cooperative stop-and-join lifecycle and uses a smaller
-- internal stack so the firmware has enough memory to finish task cleanup.
local USE_NATIVE_WORKER_TASKS = true
local VIDEO_DIR = "/sd/videos"
local MODULE_PATH = "/sd/apps/mjpeg_player/modules/jpg.so"
local AUDIO_MODULE_PATH = "/sd/apps/mjpeg_player/modules/audio.so"
local AUDIO_DATA_OUT_PIN = 48
local MAIN_STYLE = 0
if LV_PART_MAIN and LV_STATE_DEFAULT then
  MAIN_STYLE = LV_PART_MAIN | LV_STATE_DEFAULT
end

APP.files = {}
APP.index = 1
APP.fd = nil
APP.meta = nil
APP.scan_stack = {}
APP.jpg = nil
APP.audio = nil
APP.audio_path = nil
APP.audio_playing = false
APP.audio_error = nil
APP.audio_sample_rate = 0
APP.audio_channels = 0
APP.audio_written_bytes = 0
APP.ui = {}
APP.timers = {}
APP.paused = false
APP.shutting_down = false
APP.overlay = false
APP.started_ms = 0
APP.timeline_frame = 0
APP.submitted = 0
APP.presented = 0
APP.skipped = 0
APP.errors = 0
APP.loop_count = 0
APP.last_presented_id = 0
APP.last_decode_us = 0
APP.last_push_us = 0
APP.last_submit_overwrites = 0
APP.stat_last_ms = 0
APP.stat_last_presented = 0
APP.actual_fps = 0
APP.image_bound = false
APP.image_refs = {}
APP.image_ref_index = 0
APP.direct_present = false
APP.decoder_failed = false
APP.shutdown_complete = false
APP.shutdown_ok = false
APP.controller_buttons = 0
-- App-relative unknown paths are redirected to /main while current_webui is
-- false, so the hidden lifecycle endpoint lives in the global API namespace.
-- It remains app-specific and is removed before every registration.
APP.safe_exit_route = "/api/mjpeg-player/prepare-exit"
APP.status_route = "/api/mjpeg-player/status"

local function now_ms()
  if millis then return millis() or 0 end
  return 0
end

local function now_us()
  if tmr and tmr.now then
    local ok, value = pcall(function() return tmr.now() end)
    if ok and tonumber(value) then return tonumber(value) end
  end
  return now_ms() * 1000
end

local function sleep_ms(ms)
  if sleep then
    pcall(sleep, ms)
  elseif tmr and tmr.delay then
    pcall(tmr.delay, ms * 1000)
  end
end

local function state_is_active(value)
  if value == true then return true end
  if type(value) == "number" then return value ~= 0 end
  if type(value) == "string" then
    local normalized = value:lower()
    return normalized ~= "" and normalized ~= "0" and normalized ~= "false" and normalized ~= "off"
  end
  return false
end

local function u32le(data, index)
  local a, b, c, d = string.byte(data, index, index + 3)
  if not d then return 0 end
  return a + b * 256 + c * 65536 + d * 16777216
end

local function u16le(data, index)
  local a, b = string.byte(data, index, index + 1)
  if not b then return 0 end
  return a + b * 256
end

local function fourcc(value)
  return tostring(value or ""):sub(1, 4)
end

local function align2(value)
  if (value % 2) ~= 0 then return value + 1 end
  return value
end

local function safe_close(fd)
  if fd then pcall(function() fd:close() end) end
end

local function read_at(fd, offset, size)
  if not fd or size <= 0 then return nil end
  local ok_seek, pos = pcall(function() return fd:seek("set", offset) end)
  if not ok_seek or pos == nil then return nil end
  local ok_read, data = pcall(function() return fd:read(size) end)
  if not ok_read or type(data) ~= "string" or #data < size then return nil end
  return data
end

local function file_size(fd)
  local ok, size = pcall(function() return fd:seek("end", 0) end)
  if not ok then return 0 end
  return tonumber(size) or 0
end

local function read_wav_format(path)
  local fd = file.open(path, "r")
  if not fd then return nil end
  local size = file_size(fd)
  local header = read_at(fd, 0, math.min(size, 4096))
  safe_close(fd)
  if not header or #header < 12 or header:sub(1, 4) ~= "RIFF" or header:sub(9, 12) ~= "WAVE" then
    return nil
  end
  local pos = 13
  while pos + 7 <= #header do
    local id = header:sub(pos, pos + 3)
    local chunk_size = u32le(header, pos + 4)
    local data_pos = pos + 8
    if id == "fmt " and chunk_size >= 16 and data_pos + 15 <= #header then
      local format_tag = u16le(header, data_pos)
      local channels = u16le(header, data_pos + 2)
      local sample_rate = u32le(header, data_pos + 4)
      local bits = u16le(header, data_pos + 14)
      if format_tag == 1 and channels > 0 and sample_rate >= 8000 and sample_rate <= 192000 then
        return { sample_rate = sample_rate, channels = channels, bits = bits }
      end
      return nil
    end
    pos = data_pos + align2(chunk_size)
  end
  return nil
end

local function scan_avi_range(fd, start_pos, end_pos, meta, depth)
  if depth > 8 then return end
  local pos = start_pos
  while pos + 8 <= end_pos do
    local header = read_at(fd, pos, 8)
    if not header then return end
    local id = fourcc(header)
    local size = u32le(header, 5)
    local data_pos = pos + 8
    local data_end = data_pos + size
    local next_pos = data_pos + align2(size)
    if size < 0 or data_end > end_pos or next_pos <= pos then return end

    if id == "LIST" or id == "RIFF" then
      local list_type = read_at(fd, data_pos, 4)
      if not list_type then return end
      if list_type == "movi" and not meta.movi_start then
        meta.movi_start = data_pos + 4
        meta.movi_end = data_end
      elseif list_type == "hdrl" or list_type == "strl" or list_type == "AVI " or list_type == "AVIX" then
        scan_avi_range(fd, data_pos + 4, data_end, meta, depth + 1)
      end
    elseif id == "avih" and size >= 40 then
      local data = read_at(fd, data_pos, math.min(size, 56))
      if data then
        meta.microseconds_per_frame = u32le(data, 1)
        meta.total_frames = u32le(data, 17)
        meta.width = u32le(data, 33)
        meta.height = u32le(data, 37)
      end
    elseif id == "strh" and size >= 40 then
      local data = read_at(fd, data_pos, math.min(size, 64))
      if data and fourcc(data) == "vids" then
        meta.codec = fourcc(data:sub(5, 8))
        meta.scale = u32le(data, 21)
        meta.rate = u32le(data, 25)
        meta.stream_frames = u32le(data, 33)
        if meta.scale > 0 and meta.rate > 0 then
          meta.source_fps = meta.rate / meta.scale
        end
      end
    end
    pos = next_pos
  end
end

local function parse_avi(fd, path)
  local size = file_size(fd)
  if size < 12 then return nil, "AVI file is too short" end
  local header = read_at(fd, 0, 12)
  if not header or header:sub(1, 4) ~= "RIFF" or header:sub(9, 12) ~= "AVI " then
    return nil, "Not an AVI file"
  end
  local riff_end = math.min(size, 8 + u32le(header, 5))
  local meta = {
    path = path,
    file_size = size,
    codec = "",
    source_fps = 0,
    total_frames = 0,
    width = 0,
    height = 0,
  }
  scan_avi_range(fd, 12, riff_end, meta, 0)
  if not meta.movi_start or not meta.movi_end then
    return nil, "AVI movi list was not found"
  end
  local supported_size = (meta.width == SCREEN_W and meta.height == SCREEN_H) or
                         (meta.width == 160 and meta.height == 120)
  if not supported_size then
    return nil, "Video must be 160x120 or 320x240"
  end
  if meta.codec ~= "" and meta.codec ~= "MJPG" and meta.codec ~= "JPEG" and meta.codec ~= "dmb1" then
    return nil, "AVI codec is not MJPEG: " .. meta.codec
  end
  if meta.source_fps > 0 and math.abs(meta.source_fps - TARGET_FPS) > 0.5 then
    return nil, "Video must be 20 FPS"
  end
  return meta
end

local function reset_frame_scan()
  APP.scan_stack = {}
  if APP.meta then
    APP.scan_stack[1] = { pos = APP.meta.movi_start, limit = APP.meta.movi_end }
  end
end

local function is_video_chunk(id)
  return type(id) == "string" and id:match("^%d%dd[bc]$") ~= nil
end

local function read_next_jpeg()
  local fd = APP.fd
  if not fd then return nil, "video is closed" end
  local inspected = 0
  while #APP.scan_stack > 0 and inspected < 10000 do
    inspected = inspected + 1
    local top = APP.scan_stack[#APP.scan_stack]
    if top.pos + 8 > top.limit then
      table.remove(APP.scan_stack)
    else
      local chunk_pos = top.pos
      local header = read_at(fd, chunk_pos, 8)
      if not header then return nil, "AVI read failed" end
      local id = fourcc(header)
      local size = u32le(header, 5)
      local data_pos = chunk_pos + 8
      local data_end = data_pos + size
      local next_pos = data_pos + align2(size)
      if data_end > top.limit or next_pos <= chunk_pos then
        return nil, "AVI chunk is damaged"
      end
      top.pos = next_pos

      if id == "LIST" then
        local list_type = read_at(fd, data_pos, 4)
        if list_type == "rec " or list_type == "movi" then
          APP.scan_stack[#APP.scan_stack + 1] = { pos = data_pos + 4, limit = data_end }
        end
      elseif is_video_chunk(id) and size > 4 then
        local jpeg = read_at(fd, data_pos, size)
        if not jpeg then return nil, "JPEG frame read failed" end
        local soi = jpeg:find(string.char(0xFF, 0xD8), 1, true)
        if soi then
          if soi > 1 then jpeg = jpeg:sub(soi) end
          return jpeg
        end
      end
    end
  end
  return nil, "eof"
end

local function style_panel(object, color, opacity)
  lv_obj_set_style_bg_color(object, color, MAIN_STYLE)
  lv_obj_set_style_bg_opa(object, opacity, MAIN_STYLE)
  lv_obj_set_style_border_width(object, 0, MAIN_STYLE)
  lv_obj_set_style_radius(object, 0, MAIN_STYLE)
  lv_obj_set_style_pad_all(object, 0, MAIN_STYLE)
end

local function set_label_text(label, text)
  if label then pcall(function() lv_label_set_text(label, tostring(text or "")) end) end
end

local function show_message(title, detail)
  if APP.ui.message then
    set_label_text(APP.ui.message, tostring(title or "") .. "\n" .. tostring(detail or ""))
    lv_obj_set_style_text_opa(APP.ui.message, 255, MAIN_STYLE)
  end
end

local function hide_message()
  if APP.ui.message then lv_obj_set_style_text_opa(APP.ui.message, 0, MAIN_STYLE) end
end

local function update_overlay()
  if not APP.ui.overlay then return end
  lv_obj_set_style_bg_opa(APP.ui.overlay, APP.overlay and 185 or 0, MAIN_STYLE)
  if APP.ui.stats then
    lv_obj_set_style_text_opa(APP.ui.stats, APP.overlay and 255 or 0, MAIN_STYLE)
    local decode_ms = (APP.last_decode_us or 0) / 1000
    set_label_text(APP.ui.stats, string.format("%.1f/20 fps  dec %.1fms  drop %d", APP.actual_fps or 0, decode_ms, APP.skipped or 0))
  end
  if APP.ui.name then
    lv_obj_set_style_text_opa(APP.ui.name, APP.overlay and 255 or 0, MAIN_STYLE)
  end
end

local function build_ui()
  local root = lv_scr_act()
  lv_obj_clean(root)

  local bg = lv_obj_create(root)
  lv_obj_set_pos(bg, 0, 0)
  lv_obj_set_size(bg, SCREEN_W, SCREEN_H)
  style_panel(bg, 0x000000, 255)

  APP.ui.image = lv_img_create(root)
  lv_obj_set_pos(APP.ui.image, 0, 0)
  if lv_img_set_antialias then pcall(function() lv_img_set_antialias(APP.ui.image, false) end) end

  APP.ui.message = lv_label_create(root)
  lv_obj_set_pos(APP.ui.message, 12, 82)
  lv_obj_set_size(APP.ui.message, 296, 76)
  lv_obj_set_style_text_color(APP.ui.message, 0xFFFFFF, MAIN_STYLE)
  lv_obj_set_style_text_opa(APP.ui.message, 255, MAIN_STYLE)
  lv_obj_set_style_text_font(APP.ui.message, 14, MAIN_STYLE)
  lv_obj_set_style_text_align(APP.ui.message, LV_TEXT_ALIGN_CENTER, MAIN_STYLE)

  APP.ui.overlay = lv_obj_create(root)
  lv_obj_set_pos(APP.ui.overlay, 0, 0)
  lv_obj_set_size(APP.ui.overlay, SCREEN_W, 38)
  style_panel(APP.ui.overlay, 0x000000, 185)

  APP.ui.name = lv_label_create(APP.ui.overlay)
  lv_obj_set_pos(APP.ui.name, 6, 3)
  lv_obj_set_size(APP.ui.name, 308, 14)
  lv_obj_set_style_text_color(APP.ui.name, 0xFFFFFF, MAIN_STYLE)
  lv_obj_set_style_text_font(APP.ui.name, 12, MAIN_STYLE)

  APP.ui.stats = lv_label_create(APP.ui.overlay)
  lv_obj_set_pos(APP.ui.stats, 6, 20)
  lv_obj_set_size(APP.ui.stats, 308, 14)
  lv_obj_set_style_text_color(APP.ui.stats, 0x71F59B, MAIN_STYLE)
  lv_obj_set_style_text_font(APP.ui.stats, 11, MAIN_STYLE)
  update_overlay()
end

local function load_jpg_module()
  if not require then return nil, "require is unavailable" end
  local candidates = {
    MODULE_PATH,
    "/sd/apps/mjpeg_player/jpg.so",
    "/sd/apps/desktop_mirror_sd/modules/jpg.so",
  }
  local last_error = "module not found"
  for _, path in ipairs(candidates) do
    if not file or not file.exists or file.exists(path) then
      local ok, module_or_error = pcall(require, path)
      if ok
        and type(module_or_error) == "table"
        and type(module_or_error.submit) == "function"
        and type(module_or_error.read_ready_image) == "function"
        and type(module_or_error.commit_image) == "function"
        and type(module_or_error.cancel_image) == "function" then
        print("[mjpeg] jpg module loaded: " .. path)
        return module_or_error
      end
      last_error = tostring(module_or_error or "invalid jpg module")
    end
  end
  return nil, last_error
end

local function load_audio_module()
  if not require then return nil, "require is unavailable" end
  local candidates = {
    AUDIO_MODULE_PATH,
    "/sd/apps/mjpeg_player/audio.so",
    "/sd/apps/mp3_player/modules/audio.so",
  }
  local last_error = "audio module not found"
  for _, path in ipairs(candidates) do
    if not file or not file.exists or file.exists(path) then
      local ok, module_or_error = pcall(require, path)
      if ok and type(module_or_error) == "table" and type(module_or_error.open) == "function" then
        print("[mjpeg] audio module loaded: " .. path)
        return module_or_error
      end
      last_error = tostring(module_or_error or "invalid audio module")
    end
  end
  return nil, last_error
end

local function stop_audio()
  APP.audio_playing = false
  APP.audio_path = nil
  APP.audio_sample_rate = 0
  APP.audio_channels = 0
  APP.audio_written_bytes = 0
  if not APP.audio then return true end
  local audio = APP.audio
  if audio.i2s_play_pause then pcall(function() audio.i2s_play_pause(true) end) end
  if audio.i2s_play_stop then
    local ok, stopped, stop_error = pcall(function() return audio.i2s_play_stop() end)
    if not ok or stopped == false then
      print("[mjpeg] audio play stop warning: " .. tostring(stop_error or stopped))
    end
  end

  -- i2s_play_stop asks both native tasks to stop.  Do not tear down I2S or
  -- unload audio.so until they have actually returned; doing that raced the
  -- producer task and caused a panic on the next app launch.
  local deadline = now_ms() + 1200
  local tasks_stopped = false
  while now_ms() < deadline do
    local ok, state = pcall(function()
      if audio.i2s_play_state then return audio.i2s_play_state() end
      return nil
    end)
    if not ok or type(state) ~= "table" then
      tasks_stopped = true
      break
    end
    local consumer_running = state_is_active(state.running) or state_is_active(state.i2s_task_running)
    local producer_running = state_is_active(state.producer_running) or state_is_active(state.i2s_producer_running)
    if not consumer_running and not producer_running then
      tasks_stopped = true
      break
    end
    if tmr and tmr.wdclr then pcall(tmr.wdclr) end
    sleep_ms(20)
  end
  print("[mjpeg] audio tasks stopped: " .. tostring(tasks_stopped))
  if not tasks_stopped then
    -- Do not close/free objects that may still be used by a native task.  The
    -- caller will reject the Web exit instead of destroying a live module.
    print("[mjpeg] audio cleanup aborted: native tasks are still active")
    return false
  end
  if audio.i2s_stop then pcall(function() audio.i2s_stop() end) end
  sleep_ms(20)
  if audio.close then pcall(function() audio.close() end) end
  return true
end

local function audio_path_for_video(name)
  local base = tostring(name or ""):gsub("%.[Aa][Vv][Ii]$", "")
  return VIDEO_DIR .. "/" .. base .. ".wav"
end

local function start_audio(name)
  stop_audio()
  APP.audio_error = nil
  if not APP.audio then return false end
  local path = audio_path_for_video(name)
  if file and file.exists and not file.exists(path) then
    print("[mjpeg] no matching audio: " .. path)
    return false
  end
  local ok, error_message = pcall(function()
    local opened, open_error = APP.audio.open(path, { output_channels = 1 })
    if not opened then error("audio.open failed: " .. tostring(open_error)) end
    local info, info_error = APP.audio.info()
    if type(info) ~= "table" then error("audio.info failed: " .. tostring(info_error)) end
    local wav_format = read_wav_format(path)
    local sample_rate = tonumber(wav_format and wav_format.sample_rate) or tonumber(info.sample_rate) or 16000
    local channels = tonumber(wav_format and wav_format.channels) or tonumber(info.channels) or 1
    local sample_bits = tonumber(wav_format and wav_format.bits) or tonumber(info.bits_per_sample or info.bits) or 16
    APP.audio_sample_rate = sample_rate
    APP.audio_channels = channels
    print("[mjpeg] audio info rate=" .. tostring(sample_rate) ..
      " channels=" .. tostring(channels) ..
      " bits=" .. tostring(sample_bits) ..
      " module_rate=" .. tostring(info.sample_rate or "nil"))
    if APP.audio.set_effects then
      pcall(function() APP.audio.set_effects({ volume = 0.20 }) end)
    end
    local started = false
    local start_error = nil
    -- PCM already has a large PSRAM ring.  A 6x512 DMA queue still provides
    -- roughly 192 ms at 16 kHz mono while avoiding the old 12x1024 queue's
    -- ~24 KB internal-DMA footprint.
    local profiles = { { 6, 512 }, { 4, 512 }, { 4, 256 } }
    for _, profile in ipairs(profiles) do
      local call_ok, result, call_error = pcall(APP.audio.i2s_start, {
        port = 0,
        sample_rate = sample_rate,
        channels = channels,
        bits = sample_bits,
        buffer_count = profile[1],
        buffer_len = profile[2],
        data_out_pin = AUDIO_DATA_OUT_PIN,
      })
      if call_ok and result then
        started = true
        break
      end
      start_error = call_ok and call_error or result
    end
    if not started then error("audio.i2s_start failed: " .. tostring(start_error)) end
    if APP.audio.prefetch then pcall(function() APP.audio.prefetch(65536, 262144) end) end
    if USE_NATIVE_WORKER_TASKS then
      local playing, play_error = APP.audio.i2s_play_start({
        chunk_bytes = 4096,
        timeout_ms = 80,
        stack_bytes = 5120,
        priority = 9,
        core = 1,
        producer_core = 1,
      })
      if not playing then error("audio.i2s_play_start failed: " .. tostring(play_error)) end
    end
  end)
  if not ok then
    APP.audio_error = tostring(error_message)
    print("[mjpeg] audio start failed: " .. APP.audio_error)
    stop_audio()
    return false
  end
  APP.audio_path = path
  APP.audio_playing = true
  APP.audio_written_bytes = 0
  print("[mjpeg] audio started: " .. path)
  return true
end

local function pump_audio()
  if USE_NATIVE_WORKER_TASKS or APP.paused or not APP.audio_playing or not APP.audio then return end
  if type(APP.audio.play_i2s) ~= "function" then return end
  -- timeout=0 only fills currently available DMA space; it never stalls the
  -- Lua/UI thread behind an audio write while a JPEG frame is being decoded.
  for _ = 1, 2 do
    local ok, written, produced, eof = pcall(function()
      return APP.audio.play_i2s(4096, 0)
    end)
    if not ok then
      APP.audio_error = tostring(written)
      print("[mjpeg] audio pump failed: " .. APP.audio_error)
      APP.audio_playing = false
      return
    end
    local count = tonumber(written) or 0
    APP.audio_written_bytes = (APP.audio_written_bytes or 0) + count
    if eof or count <= 0 or (tonumber(produced) or 0) <= 0 then break end
  end
end

local function pause_audio(paused)
  if not APP.audio or not APP.audio_playing or not APP.audio.i2s_play_pause then return end
  local ok, result, error_message = pcall(APP.audio.i2s_play_pause, paused and true or false)
  if not ok or result == false then
    print("[mjpeg] audio pause failed: " .. tostring(error_message or result))
  end
end

local function list_videos()
  local result = {}
  local entries = file and file.listdir and (file.listdir(VIDEO_DIR) or {}) or {}
  for _, entry in ipairs(entries) do
    if entry and not entry.is_dir and type(entry.name) == "string" and entry.name:lower():match("%.avi$") then
      result[#result + 1] = entry.name
    end
  end
  table.sort(result, function(a, b) return a:lower() < b:lower() end)
  return result
end

local function close_video()
  local audio_stopped = stop_audio()
  safe_close(APP.fd)
  APP.fd = nil
  APP.meta = nil
  APP.scan_stack = {}
  return audio_stopped ~= false
end

local function release_display()
  if not APP.jpg or type(APP.jpg.release) ~= "function" then return true end
  -- Drop LVGL's pointer to the native image descriptor before the module frees
  -- its two persistent pixel slots.  Deleting only this child is immediate and
  -- leaves the rest of the shutdown UI intact if native cleanup must be retried.
  if APP.ui.image and lv_obj_del then
    pcall(function() lv_obj_del(APP.ui.image) end)
    APP.ui.image = nil
  elseif APP.ui.image and lv_img_set_src then
    pcall(function() lv_img_set_src(APP.ui.image, nil) end)
  end
  APP.image_bound = false
  APP.image_refs = {}
  local last_error = nil
  for attempt = 1, 3 do
    local ok, released, release_error = pcall(function() return APP.jpg.release() end)
    if ok and released == true then
      print("[mjpeg] display release: true attempt=" .. tostring(attempt))
      return true
    end
    last_error = ok and release_error or released
    if tmr and tmr.wdclr then pcall(tmr.wdclr) end
  end
  print("[mjpeg] display release: false " .. tostring(last_error or "unknown"))
  return false
end

local function start_timeline()
  APP.started_ms = now_ms()
  APP.timeline_frame = 0
  APP.submitted = 0
  APP.presented = 0
  APP.skipped = 0
  APP.errors = 0
  APP.last_presented_id = 0
  APP.stat_last_ms = APP.started_ms
  APP.stat_last_presented = 0
  APP.actual_fps = 0
  APP.image_bound = false
  APP.image_refs = {}
  APP.decoder_failed = false
  reset_frame_scan()
end

local function open_video(index)
  close_video()
  if #APP.files == 0 then
    show_message("NO MJPEG AVI", VIDEO_DIR)
    return false
  end
  if index < 1 then index = #APP.files end
  if index > #APP.files then index = 1 end
  APP.index = index
  local name = APP.files[index]
  local path = VIDEO_DIR .. "/" .. name
  local fd = file.open(path, "r")
  if not fd then
    show_message("OPEN FAILED", name)
    return false
  end
  local meta, error_message = parse_avi(fd, path)
  if not meta then
    safe_close(fd)
    show_message("UNSUPPORTED VIDEO", error_message)
    return false
  end
  APP.fd = fd
  APP.meta = meta
  APP.direct_present = (not SAFE_LVGL_PRESENT)
    and meta.width == SCREEN_W
    and meta.height == SCREEN_H
    and type(APP.jpg.present_ready) == "function"
  APP.paused = false
  hide_message()
  start_timeline()
  local has_audio = start_audio(name)
  set_label_text(APP.ui.name, name .. string.format("  %.1f->20 fps  %s", meta.source_fps or 0, has_audio and "AUDIO" or "SILENT"))
  APP.started_ms = now_ms()
  update_overlay()
  print(string.format("[mjpeg] open %s codec=%s size=%dx%d source_fps=%.3f frames=%d", path, meta.codec or "", meta.width or 0, meta.height or 0, meta.source_fps or 0, meta.total_frames or 0))
  return true
end

local function loop_video()
  APP.loop_count = APP.loop_count + 1
  reset_frame_scan()
  start_audio(APP.files[APP.index])
  APP.started_ms = now_ms()
  APP.timeline_frame = 0
  APP.last_presented_id = 0
end

local function submit_jpeg(jpeg, frame_id)
  if not USE_NATIVE_WORKER_TASKS then
    local ok, decoded, width, height, stats = pcall(function()
      return APP.jpg.decode(jpeg, {
        swap_color_bytes = false,
        chunked = true,
      })
    end)
    if not ok or decoded ~= true then
      APP.errors = APP.errors + 1
      print("[mjpeg] decode failed: " .. tostring(decoded or width))
      APP.decoder_failed = true
      APP.paused = true
      stop_audio()
      show_message("DECODER FAILED", tostring(decoded or width))
      return false
    end
    if tonumber(width) ~= SCREEN_W or tonumber(height) ~= SCREEN_H then
      APP.errors = APP.errors + 1
      APP.paused = true
      show_message("DECODE SIZE ERROR", tostring(width) .. "x" .. tostring(height))
      return false
    end
    local present_ok, presented, present_stats = pcall(function() return APP.jpg.present() end)
    if not present_ok or presented ~= true then
      APP.errors = APP.errors + 1
      print("[mjpeg] present failed: " .. tostring(presented or present_stats))
      return false
    end
    APP.submitted = APP.submitted + 1
    APP.presented = APP.presented + 1
    APP.last_presented_id = frame_id
    if type(stats) == "table" then
      APP.last_decode_us = tonumber(stats.decode_us) or APP.last_decode_us
    end
    if type(present_stats) == "table" then
      APP.last_push_us = tonumber(present_stats.push_us) or APP.last_push_us
    end
    return true
  end
  local ok, submitted, stats = pcall(function()
    return APP.jpg.submit(jpeg, {
      frame_id = frame_id,
      swap_color_bytes = false,
      direct_present = APP.direct_present,
    })
  end)
  if not ok or submitted ~= true then
    APP.errors = APP.errors + 1
    print("[mjpeg] submit failed: " .. tostring(submitted or stats))
    APP.decoder_failed = true
    APP.paused = true
    stop_audio()
    show_message("DECODER START FAILED", tostring(submitted or stats))
    return false
  end
  APP.submitted = APP.submitted + 1
  if type(stats) == "table" then
    APP.last_submit_overwrites = tonumber(stats.async_pending_overwrites) or APP.last_submit_overwrites
  end
  return true
end

local function retain_image(image, slot)
  APP.image_refs[slot] = image
end

local function present_ready()
  if not USE_NATIVE_WORKER_TASKS then return end
  if not APP.jpg or not APP.ui.image then return end
  if APP.direct_present then
    local ok, presented, stats = pcall(function() return APP.jpg.present_ready() end)
    if not ok then
      APP.errors = APP.errors + 1
      print("[mjpeg] direct present failed: " .. tostring(presented))
      return
    end
    if presented ~= true then return end
    APP.presented = APP.presented + 1
    if type(stats) == "table" then
      APP.last_presented_id = tonumber(stats.frame_id) or APP.last_presented_id
      APP.last_decode_us = tonumber(stats.decode_us) or APP.last_decode_us
      APP.last_push_us = tonumber(stats.push_us) or APP.last_push_us
    end
    return
  end
  local ok, image, width, height, stats = pcall(function() return APP.jpg.read_ready_image() end)
  if not ok then
    APP.errors = APP.errors + 1
    print("[mjpeg] read_ready_image failed: " .. tostring(image))
    return
  end
  if type(image) ~= "userdata" then return end
  local slot = type(stats) == "table" and tonumber(stats.image_pool_pending_slot) or nil
  if not slot or slot < 1 or slot > 2 then
    APP.errors = APP.errors + 1
    APP.paused = true
    show_message("DISPLAY ERROR", "Decoder returned no pending image slot")
    return
  end
  if width ~= SCREEN_W or height ~= SCREEN_H then
    pcall(function() APP.jpg.cancel_image(slot) end)
    APP.errors = APP.errors + 1
    show_message("DECODE SIZE ERROR", tostring(width) .. "x" .. tostring(height))
    APP.paused = true
    return
  end
  local set_started_us = now_us()
  local set_ok, set_error = pcall(function() lv_img_set_src(APP.ui.image, image) end)
  local set_finished_us = now_us()
  local set_src_us = set_finished_us >= set_started_us and (set_finished_us - set_started_us) or 0
  if not set_ok then
    pcall(function() APP.jpg.cancel_image(slot) end)
    APP.errors = APP.errors + 1
    show_message("DISPLAY ERROR", tostring(set_error))
    APP.paused = true
    return
  end

  -- Only now may the old front slot become writable.  If commit unexpectedly
  -- fails, leave the new slot pending (and therefore protected) and pause.
  local commit_ok, committed, commit_stats = pcall(function()
    return APP.jpg.commit_image(slot, set_src_us)
  end)
  if not commit_ok or committed ~= true then
    APP.errors = APP.errors + 1
    APP.paused = true
    show_message("DISPLAY ERROR", tostring(commit_stats or committed))
    return
  end

  APP.image_bound = true
  retain_image(image, slot)
  if lv_obj_invalidate then pcall(function() lv_obj_invalidate(APP.ui.image) end) end
  APP.presented = APP.presented + 1
  if type(commit_stats) == "table" then
    APP.last_presented_id = tonumber(commit_stats.frame_id) or APP.last_presented_id
    APP.last_decode_us = tonumber(commit_stats.decode_us) or APP.last_decode_us
    APP.last_push_us = tonumber(commit_stats.push_us) or APP.last_push_us
  end
  if APP.ui.overlay and lv_obj_move_foreground then pcall(function() lv_obj_move_foreground(APP.ui.overlay) end) end
end

local function skip_one_frame()
  local jpeg, reason = read_next_jpeg()
  if jpeg then
    APP.timeline_frame = APP.timeline_frame + 1
    APP.skipped = APP.skipped + 1
    return true
  end
  if reason == "eof" then
    loop_video()
    return false
  end
  APP.errors = APP.errors + 1
  return false
end

local function schedule_frame()
  if APP.paused or not APP.fd or not APP.jpg then return end
  local elapsed = now_ms() - APP.started_ms
  if elapsed < 0 then
    APP.started_ms = now_ms()
    elapsed = 0
  end
  local desired_frame = math.floor(elapsed / FRAME_INTERVAL_MS) + 1
  if desired_frame <= APP.timeline_frame then return end

  local behind = desired_frame - APP.timeline_frame - 1
  local skip_limit = math.min(behind, 6)
  for _ = 1, skip_limit do
    if not skip_one_frame() then return end
  end

  local jpeg, reason = read_next_jpeg()
  if not jpeg then
    if reason == "eof" then loop_video() else APP.errors = APP.errors + 1 end
    return
  end
  APP.timeline_frame = APP.timeline_frame + 1
  submit_jpeg(jpeg, APP.timeline_frame)
  jpeg = nil
  if (APP.timeline_frame % 20) == 0 then collectgarbage("step", 20) end
end

local function update_stats()
  local current = now_ms()
  local delta = current - APP.stat_last_ms
  if delta > 0 then
    APP.actual_fps = (APP.presented - APP.stat_last_presented) * 1000 / delta
  end
  APP.stat_last_ms = current
  APP.stat_last_presented = APP.presented
  update_overlay()
  local audio_ms = -1
  if not USE_NATIVE_WORKER_TASKS then
    local bytes_per_second = (APP.audio_sample_rate or 0) * (APP.audio_channels or 0) * 2
    if APP.audio_playing and bytes_per_second > 0 then
      audio_ms = math.floor((APP.audio_written_bytes or 0) * 1000 / bytes_per_second)
    end
  elseif APP.audio and APP.audio_playing and APP.audio.i2s_play_state then
    local ok, state = pcall(APP.audio.i2s_play_state)
    local bytes_per_second = (APP.audio_sample_rate or 0) * (APP.audio_channels or 0) * 2
    if ok and type(state) == "table" and bytes_per_second > 0 then
      audio_ms = math.floor((tonumber(state.written_bytes) or 0) * 1000 / bytes_per_second)
    end
  end
  local video_ms = math.floor((APP.timeline_frame or 0) * FRAME_INTERVAL_MS)
  print(string.format("[mjpeg] fps=%.1f/20 submitted=%d presented=%d skipped=%d errors=%d decode=%.2fms push=%.2fms overwrite=%d loop=%d video_ms=%d audio_ms=%d drift_ms=%d", APP.actual_fps or 0, APP.submitted or 0, APP.presented or 0, APP.skipped or 0, APP.errors or 0, (APP.last_decode_us or 0) / 1000, (APP.last_push_us or 0) / 1000, APP.last_submit_overwrites or 0, APP.loop_count or 0, video_ms, audio_ms, audio_ms >= 0 and (audio_ms - video_ms) or 0))
end

local function switch_video(delta)
  if #APP.files == 0 then return end
  open_video(APP.index + delta)
end

local function toggle_pause()
  APP.paused = not APP.paused
  if APP.paused then
    pause_audio(true)
    show_message("PAUSED", APP.files[APP.index] or "")
  else
    pause_audio(false)
    hide_message()
    APP.started_ms = now_ms() - math.floor(APP.timeline_frame * FRAME_INTERVAL_MS)
  end
end

local function register_keys()
  if app and app.set_home_exit then
    pcall(function() app.set_home_exit(false) end)
  end
  if key.LEFT then key.on(key.LEFT, function(event_type)
    if event_type == key.START then switch_video(-1) end
  end) end
  if key.RIGHT then key.on(key.RIGHT, function(event_type)
    if event_type == key.START then switch_video(1) end
  end) end
  if key.UP then key.on(key.UP, function(event_type)
    if event_type == key.START then toggle_pause() end
  end) end
  if key.DOWN then key.on(key.DOWN, function(event_type)
    if event_type == key.START then
      APP.overlay = not APP.overlay
      update_overlay()
    end
  end) end
  if key.HOME then key.on(key.HOME, function(event_type)
    if event_type == key.SHORT or event_type == key.EXIT or event_type == key.LONG_START then
      local stopped = APP.shutdown("home")
      if stopped then
        -- Give the native task scheduler one turn after all workers have
        -- reported stopped before the firmware destroys the Lua state.
        sleep_ms(80)
        if app and app.exit then pcall(function() app.exit() end) end
      else
        show_message("EXIT BLOCKED", "Native cleanup incomplete")
      end
    end
  end) end
end

local function runtime_is_exiting()
  if not app or not app.exiting then return false end
  local ok, exiting = pcall(app.exiting)
  return ok and exiting and true or false
end

local function start_timers()
  APP.timers.process = tmr.create()
  APP.timers.process:alarm(4, tmr.ALARM_AUTO, function()
    if APP.shutting_down then return end
    if runtime_is_exiting() then
      APP.shutdown("runtime_exit")
      return
    end
    pump_audio()
    present_ready()
    schedule_frame()
    pump_audio()
  end)

  APP.timers.stats = tmr.create()
  APP.timers.stats:alarm(1000, tmr.ALARM_AUTO, function()
    if not APP.shutting_down then update_stats() end
  end)

  local PAD_SELECT, PAD_HOME = 4096, 32768
  if controller and controller.state then
    APP.timers.controller = tmr.create()
    APP.timers.controller:alarm(40, tmr.ALARM_AUTO, function()
      if APP.shutting_down then return end
      local ok, pad = pcall(function() return controller.state("ble-main") end)
      local buttons = ok and type(pad) == "table" and tonumber(pad.buttons) or 0
      buttons = buttons or 0
      local pressed = buttons & (~APP.controller_buttons)
      APP.controller_buttons = buttons
      if (pressed & (PAD_SELECT | PAD_HOME)) ~= 0 then
        local stopped = APP.shutdown("controller")
        if stopped then
          sleep_ms(80)
          if app and app.exit then pcall(function() app.exit() end) end
        else
          show_message("EXIT BLOCKED", "Native cleanup incomplete")
        end
      end
    end)
  end

end

function APP.shutdown(reason)
  if APP.shutdown_complete then return APP.shutdown_ok end
  if APP.shutting_down then return false end
  APP.shutting_down = true
  pcall(function() key.off() end)
  for _, timer in pairs(APP.timers) do
    if timer then
      pcall(function() timer:stop() end)
      pcall(function() timer:unregister() end)
    end
  end
  APP.timers = {}
  -- Stop both native pipelines before dropping the Lua references.  This is
  -- the same lifecycle used by the repository's emulator/audio apps: stop
  -- callback sources, synchronously stop native tasks, release hardware, then
  -- let app.exit destroy the Lua state.
  -- Stop audio first: its task stacks, DMA buffers and decoder state occupy
  -- enough internal RAM to prevent the display service from allocating the
  -- LVGL draw buffers required when direct-display ownership is returned.
  local audio_stopped = close_video()
  local display_released = release_display()
  local cleanup_ok = display_released ~= false and audio_stopped ~= false
  APP.shutdown_ok = cleanup_ok
  APP.shutdown_complete = cleanup_ok
  if not cleanup_ok then
    APP.shutting_down = false
    print("[mjpeg] cleanup incomplete; refusing forced exit")
    return false
  end
  APP.jpg = nil
  APP.audio = nil
  APP.image_refs = {}
  if rawget(_G, "MJPEG_PLAYER_APP") == APP then _G.MJPEG_PLAYER_APP = nil end
  print("[mjpeg] stopped: " .. tostring(reason or "shutdown"))
  return true
end

APP.stop = APP.shutdown

local function register_safe_exit_api()
  if not (httpd and httpd.dynamic and httpd.GET and httpd.POST) then
    print("[mjpeg] lifecycle APIs unavailable")
    return false
  end
  local route = APP.safe_exit_route
  -- A hot reload can leave the previous handler registered even though its
  -- Lua closure is no longer useful.  Remove only our private route first.
  if httpd.unregister then
    pcall(function() httpd.unregister(httpd.POST, route) end)
    pcall(function() httpd.unregister(httpd.GET, APP.status_route) end)
  end
  local ok, route_error = pcall(function()
    return httpd.dynamic(httpd.POST, route, function()
      local prepared = APP.shutdown("web_prepare_exit")
      if not prepared then
        return {
          status = "503 Service Unavailable",
          type = "application/json; charset=utf-8",
          headers = {
            ["cache-control"] = "no-store",
            ["connection"] = "close",
          },
          body = '{"ok":false,"prepared":false,"error":"native cleanup incomplete"}'
        }
      end
      return {
        status = "200 OK",
        type = "application/json; charset=utf-8",
        headers = {
          ["cache-control"] = "no-store",
          ["connection"] = "close",
        },
        body = '{"ok":true,"prepared":true}'
      }
    end)
  end)
  if not ok or route_error then
    print("[mjpeg] safe exit API register failed: " .. tostring(route_error))
    return false
  end

  local status_ok, status_error = pcall(function()
    return httpd.dynamic(httpd.GET, APP.status_route, function()
      pcall(function() collectgarbage("collect") end)
      local usage = {}
      local decoder = {}
      local audio_state = {}
      local audio_memory = {}
      if sys and type(sys.usage) == "function" then
        local usage_ok, value = pcall(sys.usage)
        if usage_ok and type(value) == "table" then usage = value end
      end
      if APP.jpg and type(APP.jpg.stats) == "function" then
        local stats_ok, value = pcall(APP.jpg.stats)
        if stats_ok and type(value) == "table" then decoder = value end
      end
      if APP.audio and type(APP.audio.i2s_play_state) == "function" then
        local audio_ok, value = pcall(APP.audio.i2s_play_state)
        if audio_ok and type(value) == "table" then audio_state = value end
      end
      if APP.audio and type(APP.audio.stats) == "function" then
        local audio_ok, value = pcall(APP.audio.stats)
        if audio_ok and type(value) == "table" then audio_memory = value end
      end
      local payload = {
        ok = true,
        app_version = APP.VERSION,
        module_version = APP.jpg and APP.jpg.VERSION or nil,
        presented = APP.presented,
        submitted = APP.submitted,
        usage = usage,
        decoder = decoder,
        audio = audio_state,
        audio_memory = audio_memory,
      }
      local body = '{"ok":true}'
      if json and type(json.encode) == "function" then
        local encoded_ok, encoded = pcall(json.encode, payload)
        if encoded_ok and type(encoded) == "string" then body = encoded end
      end
      return {
        status = "200 OK",
        type = "application/json; charset=utf-8",
        headers = {
          ["cache-control"] = "no-store",
          ["connection"] = "close",
        },
        body = body,
      }
    end)
  end)
  if not status_ok or status_error then
    print("[mjpeg] status API register failed: " .. tostring(status_error))
    return false
  end
  print("[mjpeg] safe exit API ready: " .. route)
  print("[mjpeg] status API ready: " .. APP.status_route)
  return true
end

build_ui()
register_safe_exit_api()
show_message("LOADING MJPEG", "Native JPEG module")
APP.jpg, APP.module_error = load_jpg_module()
APP.audio, APP.audio_error = load_audio_module()
if not APP.audio then
  print("[mjpeg] audio unavailable: " .. tostring(APP.audio_error))
end
if not APP.jpg then
  show_message("JPEG MODULE ERROR", APP.module_error)
  print("[mjpeg] module load failed: " .. tostring(APP.module_error))
else
  APP.files = list_videos()
  if #APP.files == 0 then
    show_message("NO MJPEG AVI", "Copy a 320x240 AVI to " .. VIDEO_DIR)
  else
    open_video(1)
  end
  register_keys()
  start_timers()
end
