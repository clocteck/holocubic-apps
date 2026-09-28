-- Afterglow 1.0.1 - retro instrument clock for HoloCubic

local APP_KEY = "APP_AFTERGLOW"
local old = rawget(_G, APP_KEY)
if old and old.stop then pcall(function() old.stop("reload") end) end

local APP = {
  running = true,
  mode = 1,
  roll = 0,
  tilt_armed = true,
  audio_started = false,
  audio_pending = "",
  audio_level = 0,
  phase = 0,
  timers = {},
  imu_bound = false,
  gain = 8, -- Quiet-input display gain; compressor reduces this automatically.
  comp_stage = 1,
  comp_release = 0,
  font_3270 = nil,
}
_G[APP_KEY] = APP

local MAIN = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)

-- Relative file paths resolve from /sd, not from the app directory.
-- Resolve fonts from the current app directory or the installation path.
local function font_paths(filename)
  local paths = {}
  if app and app.current then
    local ok, current = pcall(app.current)
    if ok and type(current) == "table" and type(current.entry) == "string" then
      local dir = current.entry:match("^(/sd/.+)/[^/]+$")
      if dir then paths[#paths + 1] = dir .. "/" .. filename end
    end
  end
  local packaged = "/sd/apps/afterglow/" .. filename
  if paths[1] ~= packaged then paths[#paths + 1] = packaged end
  return paths
end

-- The binding returns numeric handles. In Lua, 0 is truthy but NOT a font.
APP.font_attempts, APP.font_handles, APP.font_paths = {}, {}, {}
local function load_font(size, fallback)
  local filename = "ibm3270_" .. size .. ".bin"
  if lv_font_load then
    for _, path in ipairs(font_paths(filename)) do
      local ok, font = pcall(lv_font_load, path)
      if ok and type(font) == "number" and font > 0 then
        APP.font_paths[tostring(size)] = path
        APP.font_handles[#APP.font_handles+1] = font
        print("[Afterglow] IBM 3270 loaded: " .. path)
        return font, true
      end
      APP.font_attempts[#APP.font_attempts + 1] = path .. ": " .. tostring(font)
    end
  end
  print("[Afterglow] " .. filename .. " unavailable; using built-in fallback")
  return rawget(_G, "LV_FONT_MONTSERRAT_" .. fallback) or fallback, false
end

APP.font_3270, APP.font_loaded = load_font(42, 28)
APP.font_path = APP.font_paths["42"]
APP.clock_zoom = APP.font_loaded and 256 or 384
local CLOCK_SPACE = 0

local FONT_BIG = APP.font_3270
local FONT_MED = load_font(16, 16)
local FONT_SMALL = load_font(12, 12)
local FONT_TINY = load_font(10, 10)
local FONT_DB = rawget(_G, "LV_FONT_MONTSERRAT_10") or 10
local LINE = rawget(_G, "lv_line_create")

local COLORS = {
  [1] = { color = 0xFFAC00, grid = 0x553B00, name = "EL" }, -- EL warm amber
  [2] = { color = 0x00F5D4, grid = 0x00554A, name = "VFD" }, -- VFD 青蓝
  [3] = { color = 0x00FF66, grid = 0x005522, name = "CRT" }, -- CRT 经典绿
}

local ui = {}
local apply_theme

local function call(fn, ...)
  if not fn then return false end
  local ok, a, b = pcall(fn, ...)
  return ok, a, b
end

local function set_text(obj, text)
  if obj and lv_label_set_text then pcall(lv_label_set_text, obj, tostring(text or "")) end
end

local function set_pos(obj, x, y)
  if obj and lv_obj_set_pos then pcall(lv_obj_set_pos, obj, x, y) end
end

-- 清理容器的多余边框/外框/阴影，防止出现莫名线框与边距错位
local function clean_style(obj)
  if not obj then return end
  call(lv_obj_set_style_border_width, obj, 0, MAIN)
  call(lv_obj_set_style_outline_width, obj, 0, MAIN)
  call(lv_obj_set_style_shadow_width, obj, 0, MAIN)
  call(lv_obj_set_style_radius, obj, 0, MAIN)
  call(lv_obj_set_style_pad_all, obj, 0, MAIN) -- 清空内边距以保证像素级对齐
end

local function style_text(obj, color, font)
  if not obj then return end
  clean_style(obj)
  call(lv_obj_set_style_text_color, obj, color, MAIN)
  if font then call(lv_obj_set_style_text_font, obj, font, MAIN) end
end

local function style_box(obj, color, is_solid)
  if not obj then return end
  clean_style(obj)
  if is_solid then
    call(lv_obj_set_style_bg_color, obj, color, MAIN)
    call(lv_obj_set_style_bg_opa, obj, 255, MAIN)
  else
    call(lv_obj_set_style_bg_color, obj, 0x000000, MAIN)
    call(lv_obj_set_style_bg_opa, obj, 255, MAIN)
    call(lv_obj_set_style_border_color, obj, color, MAIN)
    call(lv_obj_set_style_border_width, obj, 1, MAIN)
  end
end

local function label(parent, text, x, y, font)
  local o = lv_label_create(parent)
  set_text(o, text)
  set_pos(o, x, y)
  style_text(o, COLORS[APP.mode].color, font or FONT_SMALL)
  return o
end

local function clock_style(o)
  call(lv_obj_set_style_text_letter_space, o, CLOCK_SPACE, MAIN)
  call(lv_obj_set_style_transform_pivot_x, o, 0, MAIN)
  call(lv_obj_set_style_transform_pivot_y, o, 0, MAIN)
  call(lv_obj_set_style_transform_zoom, o, APP.clock_zoom, MAIN)
end

local function set_clock_text(text)
  if ui.clock_text == text then return end
  ui.clock_text = text
  set_text(ui.clock, text)
  if not APP.font_loaded then
    call(lv_obj_update_layout, ui.clock)
    local ok, w = call(lv_obj_get_width, ui.clock)
    if ok and type(w) == "number" then
      set_pos(ui.clock, math.floor((320 - w * APP.clock_zoom / 256) / 2), 26)
    end
  end
end

local function build_ui()
  local root = lv_scr_act()
  lv_obj_clean(root)
  clean_style(root)
  call(lv_obj_set_style_bg_color, root, 0x000000, MAIN)
  call(lv_obj_set_style_bg_opa, root, 255, MAIN)

  ui.root = root

  -- 1. Header 顶部栏 (基线与高度严格对齐)
  ui.brand_box = lv_obj_create(root)
  set_pos(ui.brand_box, 6, 4)
  call(lv_obj_set_size, ui.brand_box, 56, 14)
  ui.brand = label(ui.brand_box, "AFTERGLOW", 5, 2, FONT_TINY)

  ui.mode = label(root, "EL", 68, 3, FONT_SMALL)

  ui.selector = {}
  ui.selector_label = {}
  for i = 1, 3 do
    local b = lv_obj_create(root)
    set_pos(b, 258 + (i - 1) * 18, 4)
    call(lv_obj_set_size, b, 14, 14)
    ui.selector[i] = b
    ui.selector_label[i] = label(b, tostring(i), 4, 1, FONT_TINY)
  end

  ui.header_line = lv_obj_create(root)
  clean_style(ui.header_line)
  set_pos(ui.header_line, 6, 21)
  call(lv_obj_set_size, ui.header_line, 308, 1)

  -- 2. Top Section 时码器与状态栏
  -- 统一为 TC-00:00:00:00 样式，使用 IBM 3270 字体渲染
  ui.clock = label(root, "TC-00:00:00:00", 13, 26, FONT_BIG)
  clock_style(ui.clock)

  -- OK 状态标识（实心填充，黑字，绝对垂直居中于 24x20 框）
  ui.status_box = lv_obj_create(root)
  set_pos(ui.status_box, 6, 64)
  call(lv_obj_set_size, ui.status_box, 24, 20)
  ui.status_txt = label(ui.status_box, "OK", 7, 5, FONT_TINY)

  -- SYS 状态两行文本，高度 20px，与 OK 框平齐
  ui.sys = label(root, "SYS:READY\nTRIG:AUTO", 36, 64, FONT_TINY)
  call(lv_obj_set_style_text_line_space, ui.sys, 0, MAIN)

  -- 右侧 DATE 文本，垂直居中对齐 Y=66
  ui.date = label(root, "2026/09/27", 210, 66, FONT_MED)

  -- 3. Scope Section 示波器区域
  ui.scope = lv_obj_create(root)
  set_pos(ui.scope, 6, 94)
  call(lv_obj_set_size, ui.scope, 308, 140)
  style_box(ui.scope, COLORS[APP.mode].color, false)

  ui.hud_left = label(ui.scope, "CH1 20V/div\nTIME: 5us/div", 6, 4, FONT_TINY)
  ui.hud_right = label(ui.scope, "AUDIO: MIC", 212, 4, FONT_TINY)
  -- Match character-cell origins so colons and both MIC values align.
  ui.hud_input = label(ui.scope, "INPUT: MIC", 212, 16, FONT_TINY)
  call(lv_obj_set_style_text_line_space, ui.hud_left, 2, MAIN)
  call(lv_obj_set_style_text_line_space, ui.hud_right, 2, MAIN)

  -- 右下角常驻 dB 框
  ui.db_box = lv_obj_create(ui.scope)
  set_pos(ui.db_box, 222, 116)
  call(lv_obj_set_size, ui.db_box, 80, 18)
  style_box(ui.db_box, COLORS[APP.mode].color, false)
  ui.db = label(ui.db_box, "0 dB", 14, 2, FONT_DB)
  ui.comp = label(ui.scope, "COMP: OFF", 6, 118, FONT_TINY)
  APP.ui = ui

  -- 示波器 10x6 背景网格
  ui.grid_lines = {}
  if LINE then
    for i = 1, 5 do
      local l = LINE(ui.scope)
      clean_style(l)
      set_pos(l, 2, 28 + i * 15)
      call(lv_obj_set_size, l, 302, 1)
      call(lv_obj_set_style_line_width, l, 1, MAIN)
      call(lv_line_set_points, l, {{x=0, y=0}, {x=302, y=0}}, 2)
      table.insert(ui.grid_lines, l)
    end
    for i = 1, 9 do
      local l = LINE(ui.scope)
      clean_style(l)
      set_pos(l, 2 + i * 30, 28)
      call(lv_obj_set_size, l, 1, 84)
      call(lv_obj_set_style_line_width, l, 1, MAIN)
      call(lv_line_set_points, l, {{x=0, y=0}, {x=0, y=84}}, 2)
      table.insert(ui.grid_lines, l)
    end

    ui.wave = LINE(ui.scope)
    clean_style(ui.wave)
    set_pos(ui.wave, 2, 28)
    call(lv_obj_set_size, ui.wave, 302, 84)
    call(lv_obj_set_style_line_width, ui.wave, 2, MAIN)
  end

  apply_theme()
end

apply_theme = function()
  local c = COLORS[APP.mode]
  if not ui.root then return end

  -- 1. 普通文本颜色
  local normal_texts = {ui.mode, ui.clock, ui.date, ui.sys, ui.hud_left, ui.hud_right, ui.hud_input, ui.db, ui.comp}
  for _, o in ipairs(normal_texts) do style_text(o, c.color) end

  -- 2. Afterglow 徽标反显 (实心背景 + 黑色字)
  style_box(ui.brand_box, c.color, true)
  style_text(ui.brand, 0x000000, FONT_TINY)

  -- 3. OK 标识框反显
  style_box(ui.status_box, c.color, true)
  style_text(ui.status_txt, 0x000000, FONT_TINY)

  -- 4. 1/2/3 选择块 (激活项实心黑字)
  for i = 1, 3 do
    local b = ui.selector[i]
    if b then
      local is_active = (i == APP.mode)
      style_box(b, c.color, is_active)
      if ui.selector_label[i] then 
        style_text(ui.selector_label[i], is_active and 0x000000 or c.color, FONT_TINY)
      end
    end
  end

  style_box(ui.scope, c.color, false)
  style_box(ui.db_box, c.color, false)

  if ui.header_line then call(lv_obj_set_style_bg_color, ui.header_line, c.color, MAIN) end
  if ui.wave then call(lv_obj_set_style_line_color, ui.wave, c.color, MAIN) end

  for _, l in ipairs(ui.grid_lines) do
    call(lv_obj_set_style_line_color, l, c.grid, MAIN)
  end

  call(lv_obj_set_style_bg_color, ui.root, 0x000000, MAIN)
  set_text(ui.mode, c.name)
end

local function set_mode(mode)
  mode = math.max(1, math.min(3, tonumber(mode) or 1))
  if mode == APP.mode then return end
  APP.mode = mode
  apply_theme()
end
APP.set_mode = set_mode

-- 陀螺仪手势
local function bind_imu()
  if not app or not app.on then return end
  app.on("imu", function(_, roll, pitch, gx, gy, gz, ts_ms)
    if not APP.running then return end
    -- On this device orientation, pitch is the left/right tilt axis.
    APP.pitch = tonumber(pitch) or 0
    local r = APP.pitch
    local THRESH = 18
    local RELEASE = 8
    if math.abs(r) < RELEASE then
      APP.tilt_armed = true
      return
    end
    if not APP.tilt_armed then return end
    if r > THRESH then
      set_mode(APP.mode == 3 and 1 or APP.mode + 1)
      APP.tilt_armed = false
    elseif r < -THRESH then
      set_mode(APP.mode == 1 and 3 or APP.mode - 1)
      APP.tilt_armed = false
    end
  end)
  APP.imu_bound = true
end

local function unbind_imu()
  if APP.imu_bound and app and app.on then pcall(app.on, "imu", nil) end
  APP.imu_bound = false
end

-- 高精度时间刷新 - 时码器 TC-HH:MM:SS:FF 格式
local function update_clock()
  if not time or not time.getlocal then return end
  local ok, t = pcall(time.getlocal)
  if not ok or type(t) ~= "table" then return end
  local y = tonumber(t.year or t.y) or 0
  local mo = tonumber(t.month or t.mon) or 0
  local d = tonumber(t.day or t.mday) or 0
  local h = tonumber(t.hour or t.hour24) or 0
  local mi = tonumber(t.min or t.minute) or 0
  local s = tonumber(t.sec or t.second) or 0
  
  local ff = math.floor(((tmr and tmr.now and tmr.now() or 0) % 1000) / 10)

  set_clock_text(string.format("TC-%02d:%02d:%02d:%02d", h, mi, s, ff))
  set_text(ui.date, string.format("%04d/%02d/%02d", y, mo, d))
end

-- Discrete display gain reduction. Attack in the current block; release
-- one stage after 12 safe blocks, with headroom to prevent threshold chatter.
local COMP_DB = {0, 3, 6, 12, 18, 24}
local function compressor(peak)
  local stage = APP.comp_stage
  local required = 1
  while required < #COMP_DB and peak * APP.gain * 10^(-COMP_DB[required]/20) > 0.9 do
    required = required + 1
  end
  if required > stage then
    stage = required
    APP.comp_release = 0
  elseif stage > 1 and peak * APP.gain * 10^(-COMP_DB[stage-1]/20) < 0.72 then
    APP.comp_release = APP.comp_release + 1
    if APP.comp_release >= 12 then
      stage = stage - 1
      APP.comp_release = 0
    end
  else
    APP.comp_release = 0
  end
  APP.comp_stage = stage
  APP.comp_db = COMP_DB[stage]
  return APP.gain * 10^(-APP.comp_db/20)
end

-- Measure every sample before drawing, including peaks between display points.
local function push_wave(raw)
  local pts = {}
  local width = 302
  local height = 84
  local mid = math.floor(height / 2)
  local samples = math.floor(#raw / 4)

  if samples > 4 then
    local values, peak = {}, 0
    for idx = 1, samples do
      local p = (idx - 1) * 4 + 1
      local lo = string.byte(raw, p + 2) or 0
      local hi = string.byte(raw, p + 3) or 0
      local v = lo + hi * 256
      if v >= 32768 then v = v - 65536 end
      
      values[idx] = v / 32768.0
      peak = math.max(peak, math.abs(values[idx]))
    end
    local gain = compressor(peak)
    for x = 0, 60 do
      -- Keep the largest peak in each bin so short transients remain visible.
      local first = math.floor(x * samples / 61) + 1
      local last = math.max(first, math.floor((x + 1) * samples / 61))
      local norm = 0
      for idx = first, math.min(last, samples) do
        if math.abs(values[idx]) > math.abs(norm) then norm = values[idx] end
      end
      local amp = norm * gain
      local px = math.floor(x * width / 60)
      local py = math.floor(mid - amp * 39)
      
      table.insert(pts, { x = px, y = py })
    end
    set_text(ui.hud_right, "AUDIO: MIC")
    set_text(ui.hud_input, "INPUT: MIC")
  else
    compressor(0.08)
    APP.phase = (APP.phase or 0) + 0.16
    for i = 0, 60 do
      local px = math.floor(i * width / 60)
      local angle = (i * 0.08) + APP.phase
      local py = math.floor(mid + math.sin(angle) * 28 * 0.75 + math.sin(angle * 2.5) * 10)
      table.insert(pts, { x = px, y = py })
    end
    set_text(ui.hud_right, "SINE 1.25kHz")
    set_text(ui.hud_input, "INPUT: INT")
  end

  set_text(ui.db, APP.comp_db == 0 and "0 dB" or string.format("-%d dB", APP.comp_db))
  set_text(ui.comp, APP.comp_db == 0 and "COMP: OFF" or "COMP: ON")

  if ui.wave and #pts > 1 then
    pcall(lv_line_set_points, ui.wave, pts, #pts)
  end
end

local function start_audio()
  if not i2s or not i2s.start or not i2s.read then
    set_text(ui.hud_right, "SINE 1.25kHz")
    set_text(ui.hud_input, "INPUT: INT")
    return false
  end
  pcall(i2s.stop, 0)
  local ok, err = pcall(i2s.start, 0, {
    mode = i2s.MODE_MASTER | i2s.MODE_RX,
    rate = 16000,
    bits = 32,
    channel = i2s.CHANNEL_ONLY_LEFT,
    format = i2s.FORMAT_I2S,
    buffer_count = 4,
    buffer_len = 512,
  })
  if not ok then
    set_text(ui.hud_right, "SINE 1.25kHz")
    set_text(ui.hud_input, "INPUT: INT")
    return false
  end
  APP.audio_started = true
  return true
end

local function poll_audio()
  if APP.audio_started and i2s and i2s.read then
    local need = 1024 - #APP.audio_pending
    if need > 0 then
      local ok, chunk = pcall(i2s.read, 0, need, 0)
      if ok and chunk and #chunk > 0 then
        APP.audio_pending = APP.audio_pending .. chunk
      end
    end
    if #APP.audio_pending >= 1024 then
      local raw = string.sub(APP.audio_pending, 1, 1024)
      APP.audio_pending = string.sub(APP.audio_pending, 1025)
      push_wave(raw)
      return
    end
    return -- Keep the last real waveform while waiting for a complete block.
  end
  push_wave("")
end

local function start_timers()
  if not tmr or not tmr.create then return end
  APP.timers.clock = tmr.create()
  APP.timers.clock:alarm(50, tmr.ALARM_AUTO, function()
    if APP.running then update_clock() end
  end)
  APP.timers.audio = tmr.create()
  APP.timers.audio:alarm(40, tmr.ALARM_AUTO, function()
    if APP.running then poll_audio() end
  end)
end

local function stop_timers()
  for _, t in pairs(APP.timers) do
    pcall(function() t:stop() end)
    pcall(function() t:unregister() end)
  end
  APP.timers = {}
end

function APP.stop(reason)
  if not APP.running then return end
  APP.running = false
  stop_timers()
  unbind_imu()
  if APP.audio_started and i2s and i2s.stop then pcall(i2s.stop, 0) end
  APP.audio_started = false
  if rawget(_G, APP_KEY) == APP then _G[APP_KEY] = nil end
  -- Delete labels before freeing the font they reference, including on reload.
  local cleaned = false
  if lv_obj_clean and ui.root then cleaned = pcall(lv_obj_clean, ui.root) end
  if cleaned and lv_font_free then
    for _, font in ipairs(APP.font_handles) do pcall(lv_font_free, font) end
    APP.font_handles = {}
    APP.font_3270 = nil
  end
end
APP.shutdown = APP.stop

build_ui()
bind_imu()
update_clock()
start_audio()
start_timers()
local PadInput = dofile("/sd/apps/afterglow/controller.lua")
PadInput.start(APP, function(delta)
  set_mode(((APP.mode - 1 + delta) % 3) + 1)
end, function()
  APP.stop("controller-exit")
  if app and app.exit then pcall(app.exit) end
end)

if key and key.on then
  key.on(key.HOME, function(evt_type)
    if evt_type == key.SHORT then app.exit() end
  end)
end
