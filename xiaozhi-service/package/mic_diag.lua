local APP_DIR = "/sd/apps/xiaozhi-service"
local OUT_DIR = APP_DIR .. "/diag"
local RATE = 16000
local BITS = 32
local CAPTURE_MS = 4000
local DISCARD_MS = 300
local COUNTDOWN_SEC = 3
local READ_BYTES = 4096

local string_byte = string.byte
local string_char = string.char
local table_concat = table.concat

local function le16(v)
  v = math.floor(v) % 65536
  return string_char(v % 256, math.floor(v / 256) % 256)
end

local function le32(v)
  v = math.floor(v) % 4294967296
  return string_char(v % 256, math.floor(v / 256) % 256,
    math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end

local function wav_s16(pcm)
  local data_len = #pcm
  return "RIFF" .. le32(36 + data_len) .. "WAVE" ..
    "fmt " .. le32(16) .. le16(1) .. le16(1) .. le32(RATE) ..
    le32(RATE * 2) .. le16(2) .. le16(16) ..
    "data" .. le32(data_len) .. pcm
end

local function pack_offsets(pack)
  if pack == "b01" then
    return 0, 1
  elseif pack == "b12" then
    return 1, 2
  end
  return 2, 3
end

local function i2s32_to_s16(raw, pack)
  local lo_off, hi_off = pack_offsets(pack)
  local out = {}
  local n = 0
  for i = 1, #raw - 3, 4 do
    n = n + 1
    out[n] = string_char(string_byte(raw, i + lo_off) or 0,
      string_byte(raw, i + hi_off) or 0)
  end
  return table_concat(out)
end

local function pcm_stats(pcm)
  local count, max_abs, sum, sum_sq_norm, clipped = 0, 0, 0, 0, 0
  for i = 1, #pcm - 1, 2 do
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
  local fd = file and file.open and file.open(path, "w+")
  if not fd then
    return false
  end
  local ok = fd:write(data)
  fd:close()
  return ok and true or false
end

local function now_ms()
  if tmr and tmr.now then
    local ok, v = pcall(function() return tmr.now() end)
    if ok and v then
      return math.floor(v / 1000)
    end
  end
  return 0
end

local label = nil
local function show(text)
  print("[mic_diag]", text)
  if label and lv_label_set_text then
    pcall(function() lv_label_set_text(label, text) end)
  end
end

local function setup_ui()
  if not lv_scr_act or not lv_obj_clean or not lv_label_create then
    return
  end
  local root = lv_scr_act()
  lv_obj_clean(root)
  local sel = (LV_PART_MAIN or 0) | (LV_STATE_DEFAULT or 0)
  lv_obj_set_style_bg_color(root, 0x000000, sel)
  lv_obj_set_style_bg_opa(root, 255, sel)
  label = lv_label_create(root)
  lv_label_set_text(label, "mic diag")
  lv_obj_set_style_text_color(label, 0xFFFFFF, sel)
  lv_obj_set_width(label, 280)
  if lv_obj_align then
    lv_obj_align(label, LV_ALIGN_CENTER, 0, 0)
  else
    lv_obj_set_pos(label, 20, 100)
  end
end

local function countdown(name)
  for i = COUNTDOWN_SEC, 1, -1 do
    show(name .. " 声道\n" .. tostring(i) .. " 秒后开始\n请持续说话")
    if sleep then
      sleep(1000)
    end
  end
end

local function read_i2s_bytes(target, keep)
  local chunks = {}
  local got = 0
  while got < target do
    local need = math.min(READ_BYTES, target - got)
    local chunk = i2s.read(0, need, 160)
    if chunk and #chunk > 0 then
      if keep then
        chunks[#chunks + 1] = chunk
      end
      got = got + #chunk
    end
  end
  if keep then
    return table_concat(chunks), got
  end
  return "", got
end

local function capture_slot(name, channel)
  countdown(name)
  show(name .. " 声道\n初始化麦克风")
  pcall(function() i2s.stop(0) end)
  i2s.start(0, {
    mode = i2s.MODE_MASTER | i2s.MODE_RX,
    rate = RATE,
    bits = BITS,
    channel = channel,
    format = i2s.FORMAT_I2S,
    buffer_count = 6,
    buffer_len = 512,
  })

  -- 丢掉 I2S 刚启动时的瞬态，避免把启动尖峰误判成语音。
  local discard_target = math.floor(RATE * DISCARD_MS / 1000) * 4
  local _, discarded = read_i2s_bytes(discard_target, false)

  show(name .. " 声道录音中\n请持续说话 " .. tostring(math.floor(CAPTURE_MS / 1000)) .. " 秒")
  local target = math.floor(RATE * CAPTURE_MS / 1000) * 4
  local t0 = now_ms()
  local raw, got = read_i2s_bytes(target, true)
  local elapsed = now_ms() - t0
  pcall(function() i2s.stop(0) end)

  write_file(OUT_DIR .. "/manual_" .. name .. "_raw_32.i2s", raw)
  local lines = {
    "slot=" .. name,
    "rate=" .. tostring(RATE),
    "bits=" .. tostring(BITS),
    "capture_ms=" .. tostring(CAPTURE_MS),
    "discard_ms=" .. tostring(DISCARD_MS),
    "discarded_bytes=" .. tostring(discarded),
    "raw_bytes=" .. tostring(#raw),
    "got_bytes=" .. tostring(got),
    "elapsed_ms=" .. tostring(elapsed),
    "raw_bytes_per_sec=" .. tostring(elapsed > 0 and math.floor(#raw * 1000 / elapsed) or 0),
  }
  for _, pack in ipairs({ "b01", "b12", "b23" }) do
    local pcm = i2s32_to_s16(raw, pack)
    local st = pcm_stats(pcm)
    lines[#lines + 1] = string.format(
      "%s samples=%d max=%.1f%% rms=%.1f%% dc=%d clipped=%d",
      pack, st.samples, st.max_pct, st.rms_pct, st.dc, st.clipped)
    write_file(OUT_DIR .. "/manual_" .. name .. "_" .. pack .. ".wav", wav_s16(pcm))
  end
  write_file(OUT_DIR .. "/manual_" .. name .. "_stats.txt", table_concat(lines, "\n") .. "\n")
  show(name .. " 保存完成")
  if sleep then
    sleep(600)
  end
end

setup_ui()
if file and file.mkdir then
  pcall(function() file.mkdir(OUT_DIR) end)
end

capture_slot("left", i2s.CHANNEL_ONLY_LEFT)
capture_slot("right", i2s.CHANNEL_ONLY_RIGHT)
show("录音诊断完成")
if sleep then
  sleep(1200)
end
if app and app.launch then
  pcall(function() app.start_service("xiaozhi-service") end)
end
