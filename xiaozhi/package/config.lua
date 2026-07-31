local M = {}

M.VERSION = "2026-06-24-xiaozhi-lua-port-v2"
M.FIRMWARE_VERSION = "1.7.5"
M.BOARD_TYPE = "bread-compact-wifi-lcd"
M.BOARD_NAME = "bread-compact-wifi-lcd"
M.APP_DIR = "/sd/apps/xiaozhi"
M.XZ_MODULE = M.APP_DIR .. "/xiaozhi.so"
M.WAKE_MODULE = M.APP_DIR .. "/wake.so"
M.CONFIG_PATH = M.APP_DIR .. "/config.json"
M.MCP_DIR = M.APP_DIR .. "/mcp"
M.WAKE_MODEL_DIR = M.APP_DIR .. "/wake/wn9s_nihaoxiaozhi"
M.WAKE_INDEX = M.WAKE_MODEL_DIR .. "/wn9_index"
M.WAKE_DATA = M.WAKE_MODEL_DIR .. "/wn9_data"
M.WAKE_WORD = "你好小智"
M.TIMEZONE = "CST-8"
M.UI_TYPE = nil
M.ASSET_DIR = M.APP_DIR .. "/assets"
M.EMOJI_GIF_DIR = M.ASSET_DIR .. "/emojis/gif"
M.EMOJI_PNG_DIR = M.ASSET_DIR .. "/emojis/png"
M.TEXT_FONT_PATH = M.ASSET_DIR .. "/fonts/noto_sans_sc_medium_16_2bpp_common4000.bin"

M.AUDIO = {
  rate = 16000,
  wake_rate = 16000,
  channels = 1,
  frame_ms = 60,
  bitrate = 12000,
  complexity = 0,
  mic_bits = 32,
  mic_pack = "b23",
  wake_mic_pack = "b23",
  tx_mic_pack = "b23",
  mic_gain_shift = 0,
  wake_gain_shift = 0,
  tx_gain_shift = 2,
  i2s_id = 0,
  read_wait_ms = 20,
  tx_read_wait_ms = 0,
  capture_task_core = 0,
  capture_task_stack = 12288,
  capture_task_priority = 2,
  capture_queue_depth = 6,
  capture_read_timeout_ms = 100,
  poll_ms = 35,
  wake_poll_ms = 35,
  tx_poll_ms = 60,
  tx_chunk_ms = 60,
  wake_bridge_enabled = false,
  wake_preroll_ms = 120,
  wake_bridge_ms = 240,
  wake_bridge_flush_ms = 120,
  wake_bridge_poll_ms = 35,
  rx_buffer_count = 8,
  max_rx_frames_per_poll = 1,
  max_encode_frames_per_poll = 1,
  tx_pending_frames = 4,
  capture_once = false,
  capture_ms = 1600,
}

M.websocket = {
  url = "",
  token = "",
  version = 3,
  buffer_size = 8192,
  task_stack = 12288,
  timeout_ms = 10000,
  async_send = true,
  send_task_core = 0,
  send_queue_depth = 16,
  send_queue_bytes = 65536,
  send_timeout_ms = 2000,
}

M.ota = {
  url = "https://api.tenclass.net/xiaozhi/ota/",
  enabled = true,
  force = false,
  interval_ms = 3000,
  max_polls = 80,
  timeout_ms = 10000,
}

M.UI = {
  gif_enabled = true,
  emotion_min_ms = 1000,
}

local function read_text(path)
  if not file or not file.getcontents then
    return nil
  end
  local ok, text = pcall(function()
    return file.getcontents(path)
  end)
  if ok and type(text) == "string" then
    return text
  end
  return nil
end

local function pick_string(raw, name)
  local v = raw:match('"' .. name .. '"%s*:%s*"([^"]*)"')
  return v
end

local function pick_number(raw, name)
  local v = tonumber(raw:match('"' .. name .. '"%s*:%s*(%d+)') or "")
  return v
end

local function pick_bool(raw, name)
  local v = raw:match('"' .. name .. '"%s*:%s*(true)')
  if v then
    return true
  end
  v = raw:match('"' .. name .. '"%s*:%s*(false)')
  if v then
    return false
  end
  return nil
end

local function pick_block(raw, name)
  return raw:match('"' .. name .. '"%s*:%s*{(.-)}')
end

local function decode_json(raw)
  local codec = rawget(_G, "json") or rawget(_G, "sjson")
  if codec and codec.decode then
    local ok, obj = pcall(codec.decode, raw)
    if ok and type(obj) == "table" then
      return obj
    end
  end
  return nil
end

local function apply_websocket(ws)
  if type(ws) ~= "table" then
    return
  end
  if type(ws.url) == "string" and ws.url:match("^wss?://") then
    M.websocket.url = ws.url
  end
  if type(ws.token) == "string" then
    M.websocket.token = ws.token
  end
  if tonumber(ws.version) then
    M.websocket.version = math.floor(tonumber(ws.version))
  end
end

local function apply_audio(audio)
  if type(audio) ~= "table" then
    return
  end
  local rate = tonumber(audio.sample_rate or audio.rate)
  local channels = tonumber(audio.channels)
  local frame_ms = tonumber(audio.frame_duration or audio.frame_ms)
  local bitrate = tonumber(audio.bitrate)
  local volume = tonumber(audio.volume)
  if rate and rate > 0 then
    M.AUDIO.rate = math.floor(rate)
  end
  if channels and channels > 0 then
    M.AUDIO.channels = math.floor(channels)
  end
  if frame_ms and frame_ms > 0 then
    M.AUDIO.frame_ms = math.floor(frame_ms)
  end
  if bitrate and bitrate > 0 then
    M.AUDIO.bitrate = math.floor(bitrate)
  end
  if volume then
    M.AUDIO.volume = math.max(0, math.min(100, math.floor(volume)))
  end
end

local function apply_ota(ota)
  if type(ota) ~= "table" then
    return
  end
  if type(ota.url) == "string" and ota.url:match("^https?://") then
    M.ota.url = ota.url
  end
  if ota.enabled ~= nil then
    M.ota.enabled = ota.enabled and true or false
  end
  if ota.force ~= nil then
    M.ota.force = ota.force and true or false
  end
  if tonumber(ota.interval_ms) then
    M.ota.interval_ms = math.floor(tonumber(ota.interval_ms))
  end
  if tonumber(ota.max_polls) then
    M.ota.max_polls = math.floor(tonumber(ota.max_polls))
  end
  if tonumber(ota.timeout_ms) then
    M.ota.timeout_ms = math.floor(tonumber(ota.timeout_ms))
  end
end

local function apply_ui_config(ui)
  if type(ui) ~= "table" then return end
  local value = ui.type
  if type(value) == "string" then
    value = value:match("^%s*(.-)%s*$"):lower()
  end
  if type(value) == "string" and value ~= "" and #value <= 48 and value:match("^[%w_.%-]+$") then
    M.UI_TYPE = value
    M.UI.type = value
  end
end

function M.load()
  local raw = read_text(M.CONFIG_PATH)
  if not raw then
    return M
  end

  local obj = decode_json(raw)
  if obj then
    apply_websocket(obj.websocket)
    apply_ota(obj.ota)
    apply_audio(obj.audio or obj.audio_params)
    apply_ui_config(obj.ui)
    apply_ui_config({ type = obj.ui_type })
    if type(obj.wake_word) == "string" and obj.wake_word ~= "" then
      M.WAKE_WORD = obj.wake_word
    end
    if type(obj.timezone) == "string" and obj.timezone ~= "" then
      M.TIMEZONE = obj.timezone
    end
    return M
  end

  local ws_block = pick_block(raw, "websocket") or raw
  local ota_block = pick_block(raw, "ota") or ""
  local audio_block = pick_block(raw, "audio") or pick_block(raw, "audio_params") or ""
  local url = pick_string(ws_block, "url")
  local token = pick_string(ws_block, "token")
  local version = pick_number(ws_block, "version")
  local wake_word = pick_string(raw, "wake_word")
  local timezone = pick_string(raw, "timezone")
  local ui_type = pick_string(raw, "ui_type")

  if url and url:match("^wss?://") then
    M.websocket.url = url
  end
  if token then
    M.websocket.token = token
  end
  if version and version >= 1 then
    M.websocket.version = math.floor(version)
  end
  if wake_word and wake_word ~= "" then
    M.WAKE_WORD = wake_word
  end
  if timezone and timezone ~= "" then
    M.TIMEZONE = timezone
  end
  apply_ui_config({ type = ui_type })
  if ota_block ~= "" then
    local ota_url = pick_string(ota_block, "url")
    local enabled = pick_bool(ota_block, "enabled")
    local force = pick_bool(ota_block, "force")
    local interval_ms = pick_number(ota_block, "interval_ms")
    local max_polls = pick_number(ota_block, "max_polls")
    local timeout_ms = pick_number(ota_block, "timeout_ms")
    apply_ota({
      url = ota_url,
      enabled = enabled,
      force = force,
      interval_ms = interval_ms,
      max_polls = max_polls,
      timeout_ms = timeout_ms,
    })
  end
  if audio_block ~= "" then
    apply_audio({
      sample_rate = pick_number(audio_block, "sample_rate") or pick_number(audio_block, "rate"),
      channels = pick_number(audio_block, "channels"),
      frame_duration = pick_number(audio_block, "frame_duration") or pick_number(audio_block, "frame_ms"),
      bitrate = pick_number(audio_block, "bitrate"),
      volume = pick_number(audio_block, "volume"),
    })
  end

  return M
end

return M
