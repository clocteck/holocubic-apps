local SCREEN_W = 320
local SCREEN_H = 240
local SETTINGS_PATH = "/sd/apps/settings.json"
local SETUP_SSID = "clocteck-cubic"
local SETUP_PORTAL = "192.168.18.1"
local DEVICE_HOST = "clocteck-cubic.local"
local FONT_DIR = "/sd/apps/wifi_guide/font"

-- 入口脚本会被重复执行（热重载）。以前只有 HOME/手柄路径会调 leave_app()，
-- 热重载、被其它 app 顶掉时 poll/controller 两个 ALARM_AUTO 定时器和字体
-- 都不会释放；异步 RSSI 回调也没有代次检查，会往已删除的 obj_id 上写。
local prev_guide = rawget(_G, "WIFI_GUIDE_APP")
if prev_guide and prev_guide.stop then
  pcall(function() prev_guide.stop("reload") end)
end

local GUIDE = {}
_G.WIFI_GUIDE_APP = GUIDE

local root = lv_scr_act()
lv_obj_clean(root)

local UI = { setup = {}, success = {} }
local STATE = {
  poll_timer = nil,
  controller_timer = nil,
  font_handles = {},
  language = "en",
  connected = false,
  last_ip = "",
  last_rssi = nil,
  rssi_requesting = false,
  rssi_poll_tick = 0,
  screen = "setup",
}

local FONT_TITLE = LV_FONT_MONTSERRAT_20
local FONT_BODY = LV_FONT_MONTSERRAT_14 or LV_FONT_MONTSERRAT_16
local FONT_SMALL = LV_FONT_MONTSERRAT_12 or LV_FONT_MONTSERRAT_14

local TEXT = {
  en = {
    waiting_eyebrow = "WAITING FOR NETWORK",
    waiting_title = "WiFi setup",
    waiting_desc = "Connect to the device hotspot, then open the setup page",
    hotspot = "HOTSPOT",
    portal = "SETUP ADDRESS",
    step1 = "Connect your phone or PC\nto the device hotspot",
    step2 = "Wait for the page, or scan\nthe QR code to open it",
    scan_setup = "SCAN TO SET UP",
    ready_eyebrow = "NETWORK READY",
    ready_title = "Setup complete",
    ready_desc = "Use the IP or domain below to open the control page",
    wifi = "WIFI",
    signal = "SIGNAL",
    ip = "IP",
    domain = "DOMAIN",
    scan_control = "SCAN CONTROL PAGE",
    qr_fallback = "Open the address below",
    unknown_wifi = "Connected WiFi",
    unknown_signal = "-- dBm",
  },
  zh = {
    waiting_eyebrow = "等待网络连接",
    waiting_title = "等待配网",
    waiting_desc = "连接设备热点，然后打开配网页面完成 WiFi 设置",
    hotspot = "设备热点",
    portal = "配网地址",
    step1 = "手机或电脑连接上方\n设备热点",
    step2 = "等待自动弹出页面，或\n扫码打开配网地址",
    scan_setup = "扫码打开配网页",
    ready_eyebrow = "网络已连接",
    ready_title = "配网成功",
    ready_desc = "可以使用以下 IP / 域名进入设备控制网页",
    wifi = "WiFi",
    signal = "信号",
    ip = "IP",
    domain = "域名",
    scan_control = "扫码进入控制网页",
    qr_fallback = "请打开下方地址",
    unknown_wifi = "已连接 WiFi",
    unknown_signal = "-- dBm",
  },
}

local function text_or(value, fallback)
  if value == nil or value == "" then return fallback or "" end
  return tostring(value)
end

local function safe_call(fn)
  local ok, value = pcall(fn)
  if ok then return value end
  return nil
end

local function safe_set_text(obj, value)
  if not obj then return end
  pcall(function() lv_label_set_text(obj, text_or(value, "")) end)
end

local function safe_set_hidden(obj, hidden)
  if not obj then return end
  pcall(function()
    if hidden then
      lv_obj_add_flag(obj, LV_OBJ_FLAG_HIDDEN)
    else
      lv_obj_clear_flag(obj, LV_OBJ_FLAG_HIDDEN)
    end
  end)
end

local function read_settings()
  if not file or not file.getcontents then return {} end
  local raw = safe_call(function() return file.getcontents(SETTINGS_PATH) end)
  if type(raw) ~= "string" or raw == "" then return {} end
  local codec = rawget(_G, "json") or rawget(_G, "sjson")
  if not codec or not codec.decode then return {} end
  local doc = safe_call(function() return codec.decode(raw) end)
  return type(doc) == "table" and doc or {}
end

-- Only Simplified Chinese is treated as Chinese. Missing, English,
-- Japanese, Traditional Chinese, and unknown values all default to English.
local function selected_language()
  local settings = read_settings()
  local value = tostring(settings.language or settings.locale or settings.lang or "")
  value = value:gsub("_", "-")
  if value == "zh-CN" or value == "zh-Hans" or value:match("^zh%-Hans%-") then
    return "zh"
  end
  return "en"
end

local function style_panel(obj, bg, opa, radius, border_width, border_color, border_opa)
  lv_obj_set_style_bg_color(obj, bg, LV_PART_MAIN)
  lv_obj_set_style_bg_opa(obj, opa or 255, LV_PART_MAIN)
  lv_obj_set_style_radius(obj, radius or 0, LV_PART_MAIN)
  lv_obj_set_style_border_width(obj, border_width or 0, LV_PART_MAIN)
  lv_obj_set_style_border_color(obj, border_color or 0, LV_PART_MAIN)
  lv_obj_set_style_border_opa(obj, border_opa or 0, LV_PART_MAIN)
  lv_obj_set_style_pad_all(obj, 0, LV_PART_MAIN)
end

local function style_text(obj, color, font, align)
  lv_obj_set_style_text_color(obj, color, LV_PART_MAIN)
  lv_obj_set_style_text_opa(obj, 255, LV_PART_MAIN)
  if font then lv_obj_set_style_text_font(obj, font, LV_PART_MAIN) end
  lv_obj_set_style_text_align(obj, align or LV_TEXT_ALIGN_LEFT, LV_PART_MAIN)
end

local function make_panel(parent, x, y, w, h, bg, opa, radius, border_width, border_color, border_opa)
  local obj = lv_obj_create(parent)
  lv_obj_set_pos(obj, x, y)
  lv_obj_set_size(obj, w, h)
  style_panel(obj, bg, opa, radius, border_width, border_color, border_opa)
  return obj
end

local function make_label(parent, x, y, w, h, value, color, font, align)
  local label = lv_label_create(parent)
  lv_obj_set_pos(label, x, y)
  lv_obj_set_size(label, w, h)
  pcall(function() lv_label_set_long_mode(label, LV_LABEL_LONG_CLIP) end)
  style_text(label, color, font, align)
  safe_set_text(label, value)
  return label
end

local function make_divider(parent, y, width)
  return make_panel(parent, 10, y, width or 169, 1, 0x94B5C7, 31, 0, 0, 0, 0)
end

local function stop_timer(name)
  local timer = STATE[name]
  if not timer then return end
  pcall(function() timer:stop() end)
  pcall(function() timer:unregister() end)
  STATE[name] = nil
end

local function load_font(path, fallback)
  if not lv_font_load then return fallback end
  local handle = safe_call(function() return lv_font_load(path) end)
  if type(handle) == "number" and handle > 0 then
    STATE.font_handles[#STATE.font_handles + 1] = handle
    return handle
  end
  return fallback
end

local function release_fonts()
  if lv_font_free then
    for _, handle in ipairs(STATE.font_handles) do
      pcall(function() lv_font_free(handle) end)
    end
  end
  STATE.font_handles = {}
end

local function init_fonts()
  FONT_TITLE = LV_FONT_MONTSERRAT_20
  FONT_BODY = LV_FONT_MONTSERRAT_14 or LV_FONT_MONTSERRAT_16
  FONT_SMALL = LV_FONT_MONTSERRAT_12 or LV_FONT_MONTSERRAT_14
  if STATE.language == "zh" then
    FONT_TITLE = load_font(FONT_DIR .. "/18chinese.bin", FONT_TITLE)
    FONT_BODY = load_font(FONT_DIR .. "/msyh_cn_13.bin", FONT_BODY)
    FONT_SMALL = FONT_BODY
  end
end

local function looks_like_ip(ip)
  ip = text_or(ip, "")
  return ip ~= "" and ip ~= "0.0.0.0" and ip:match("^%d+%.%d+%.%d+%.%d+$") ~= nil
end

local function wifi_ip()
  local ip = nil
  if wifi and wifi.sta and wifi.sta.getip then
    ip = safe_call(function() return wifi.sta.getip() end)
  end
  if not looks_like_ip(ip) and wifi and wifi.sta and wifi.sta.ip then
    ip = safe_call(function() return wifi.sta.ip() end)
  end
  if not looks_like_ip(ip) and net and net.getifaddr then
    ip = safe_call(function() return net.getifaddr() end)
  end
  return looks_like_ip(ip) and tostring(ip) or ""
end

local function wifi_name()
  if wifi and wifi.sta and wifi.sta.getconfig then
    local cfg = safe_call(function() return wifi.sta.getconfig() end)
    if type(cfg) == "table" and text_or(cfg.ssid, "") ~= "" then
      return tostring(cfg.ssid)
    end
  end
  return TEXT[STATE.language].unknown_wifi
end

local function wifi_rssi()
  if type(STATE.last_rssi) == "number" then
    return STATE.last_rssi
  end
  local value = nil
  if wifi and wifi.sta and wifi.sta.getrssi then
    value = safe_call(function() return wifi.sta.getrssi() end)
  elseif wifi and wifi.sta and wifi.sta.rssi then
    value = safe_call(function() return wifi.sta.rssi() end)
  end
  value = tonumber(value)
  return value and math.floor(value) or nil
end

local function wifi_connected()
  local ip = wifi_ip()
  if ip ~= "" then return true, ip end
  if wifi and wifi.sta and wifi.sta.status then
    local status = safe_call(function() return wifi.sta.status() end)
    if status == "got_ip" or status == "connected" or status == 5 then return true, "" end
  end
  return false, ""
end

local function set_group_visible(group, visible)
  for _, obj in pairs(group) do safe_set_hidden(obj, not visible) end
end

local function xor8(a, b)
  local result = 0
  local place = 1
  a = math.floor(a or 0)
  b = math.floor(b or 0)
  for _ = 1, 8 do
    if (a % 2) ~= (b % 2) then result = result + place end
    a = math.floor(a / 2)
    b = math.floor(b / 2)
    place = place * 2
  end
  return result
end

local function gf_multiply(a, b)
  local result = 0
  while b > 0 do
    if b % 2 == 1 then result = xor8(result, a) end
    b = math.floor(b / 2)
    a = a * 2
    if a >= 256 then a = xor8(a, 0x11D) end
  end
  return result
end

local function reed_solomon_remainder(data, degree)
  local coefficients = {}
  for i = 1, degree do coefficients[i] = 0 end
  coefficients[degree] = 1
  local root_value = 1
  for _ = 1, degree do
    for j = 1, degree do
      coefficients[j] = gf_multiply(coefficients[j], root_value)
      if j < degree then coefficients[j] = xor8(coefficients[j], coefficients[j + 1]) end
    end
    root_value = gf_multiply(root_value, 2)
  end

  local result = {}
  for i = 1, degree do result[i] = 0 end
  for _, value in ipairs(data) do
    local factor = xor8(value, result[1])
    for i = 1, degree - 1 do result[i] = result[i + 1] end
    result[degree] = 0
    for i = 1, degree do
      result[i] = xor8(result[i], gf_multiply(coefficients[i], factor))
    end
  end
  return result
end

local function append_bits(bits, value, count)
  for shift = count - 1, 0, -1 do
    bits[#bits + 1] = math.floor(value / (2 ^ shift)) % 2 == 1
  end
end

-- Offline QR encoder for Version 2-L, byte mode. This version stores up to
-- 32 bytes, enough for an IPv4 control URL such as http://192.168.0.188/.
local function encode_qr_v2_l(text)
  if type(text) ~= "string" or #text > 32 then return nil end
  local bits = {}
  append_bits(bits, 0x4, 4)
  append_bits(bits, #text, 8)
  for i = 1, #text do append_bits(bits, text:byte(i), 8) end

  local data_capacity_bits = 34 * 8
  local terminator = math.min(4, data_capacity_bits - #bits)
  for _ = 1, terminator do bits[#bits + 1] = false end
  while #bits % 8 ~= 0 do bits[#bits + 1] = false end

  local pad = 0
  while #bits < data_capacity_bits do
    append_bits(bits, pad % 2 == 0 and 0xEC or 0x11, 8)
    pad = pad + 1
  end

  local codewords = {}
  for offset = 1, #bits, 8 do
    local value = 0
    for i = 0, 7 do value = value * 2 + (bits[offset + i] and 1 or 0) end
    codewords[#codewords + 1] = value
  end
  local ecc = reed_solomon_remainder(codewords, 10)
  for _, value in ipairs(ecc) do codewords[#codewords + 1] = value end

  local size = 25
  local modules = {}
  local reserved = {}
  for y = 1, size do
    modules[y] = {}
    reserved[y] = {}
  end

  local function set_function(x, y, dark)
    if x < 0 or y < 0 or x >= size or y >= size then return end
    modules[y + 1][x + 1] = dark and true or false
    reserved[y + 1][x + 1] = true
  end

  local function place_finder(left, top)
    for dy = -1, 7 do
      for dx = -1, 7 do
        local in_symbol = dx >= 0 and dx <= 6 and dy >= 0 and dy <= 6
        local outer = in_symbol and (dx == 0 or dx == 6 or dy == 0 or dy == 6)
        local center = dx >= 2 and dx <= 4 and dy >= 2 and dy <= 4
        set_function(left + dx, top + dy, outer or center)
      end
    end
  end

  place_finder(0, 0)
  place_finder(size - 7, 0)
  place_finder(0, size - 7)

  for i = 8, size - 9 do
    set_function(i, 6, i % 2 == 0)
    set_function(6, i, i % 2 == 0)
  end

  for dy = -2, 2 do
    for dx = -2, 2 do
      set_function(18 + dx, 18 + dy, math.max(math.abs(dx), math.abs(dy)) ~= 1)
    end
  end

  -- Error correction level L with mask pattern 0: format bits 0x77C4.
  local format_bits = 0x77C4
  local function format_bit(index)
    return math.floor(format_bits / (2 ^ index)) % 2 == 1
  end
  for i = 0, 5 do set_function(8, i, format_bit(i)) end
  set_function(8, 7, format_bit(6))
  set_function(8, 8, format_bit(7))
  set_function(7, 8, format_bit(8))
  for i = 9, 14 do set_function(14 - i, 8, format_bit(i)) end
  for i = 0, 7 do set_function(size - 1 - i, 8, format_bit(i)) end
  for i = 8, 14 do set_function(8, size - 15 + i, format_bit(i)) end
  set_function(8, size - 8, true)

  local data_bits = {}
  for _, value in ipairs(codewords) do append_bits(data_bits, value, 8) end
  local bit_index = 1
  local right = size - 1
  while right >= 1 do
    if right == 6 then right = 5 end
    -- QR data columns alternate bottom-to-top and top-to-bottom.
    -- For a 25-module symbol the first pair (24, 23) travels upward.
    local upward = (right + 1) % 4 < 2
    for vertical = 0, size - 1 do
      local y = upward and (size - 1 - vertical) or vertical
      for column = 0, 1 do
        local x = right - column
        if not reserved[y + 1][x + 1] then
          local dark = data_bits[bit_index] or false
          bit_index = bit_index + 1
          if (x + y) % 2 == 0 then dark = not dark end
          modules[y + 1][x + 1] = dark
        end
      end
    end
    right = right - 2
  end
  return modules
end

local function draw_qr_canvas(frame, size, modules)
  if not modules or not lv_canvas_create or not lv_canvas_fill_bg or not lv_canvas_draw_rect then return nil end
  local canvas = safe_call(function()
    return lv_canvas_create(frame, size, size, LV_IMG_CF_TRUE_COLOR)
  end)
  if not canvas then return nil end
  lv_obj_set_pos(canvas, 0, 0)
  local began = false
  if lv_canvas_frame_begin then
    began = pcall(function() lv_canvas_frame_begin(canvas) end)
  elseif lv_canvas_begin then
    began = pcall(function() lv_canvas_begin(canvas) end)
  end
  lv_canvas_fill_bg(canvas, 0xFFFFFF, 255)
  local module_size = size >= 88 and 3 or 2
  local symbol_pixels = #modules * module_size
  local origin = math.floor((size - symbol_pixels) / 2)
  for y = 1, #modules do
    for x = 1, #modules do
      if modules[y][x] then
        lv_canvas_draw_rect(canvas, origin + (x - 1) * module_size, origin + (y - 1) * module_size,
          module_size, module_size, 0x000000, 255)
      end
    end
  end
  if began then
    if lv_canvas_frame_end then
      pcall(function() lv_canvas_frame_end(canvas) end)
    elseif lv_canvas_end then
      pcall(function() lv_canvas_end(canvas) end)
    end
  end
  return canvas
end

local function make_qr(parent, x, y, size, target, fallback)
  local frame = make_panel(parent, x, y, size, size, 0xFFFFFF, 255, 5, 0, 0, 0)
  local modules = encode_qr_v2_l(target)
  local canvas = draw_qr_canvas(frame, size, modules)
  if canvas then return frame, canvas end
  local label = make_label(frame, 4, 19, size - 8, 36, fallback, 0x071018, FONT_SMALL, LV_TEXT_ALIGN_CENTER)
  return frame, label
end

local function update_signal_bars(db)
  local level = 0
  if db then
    level = db >= -55 and 4 or db >= -67 and 3 or db >= -75 and 2 or 1
  end
  for index, bar in ipairs(UI.success.signal_bars or {}) do
    lv_obj_set_style_bg_color(bar, index <= level and 0x22D3EE or 0x48606E, LV_PART_MAIN)
  end
end

local function update_success_signal(db)
  if not UI.success or not UI.success.signal then return end
  safe_set_text(UI.success.signal, db and (tostring(db) .. " dBm") or TEXT[STATE.language].unknown_signal)
  update_signal_bars(db)
end

local function request_system_rssi(force)
  if not STATE.connected or STATE.rssi_requesting or not http or not http.get then return end
  STATE.rssi_poll_tick = (STATE.rssi_poll_tick or 0) + 1
  if not force and STATE.rssi_poll_tick < 3 then return end
  STATE.rssi_poll_tick = 0

  local ip = wifi_ip()
  if not looks_like_ip(ip) then return end
  STATE.rssi_requesting = true
  local url = "http://" .. ip .. "/api/system/state"
  local started = pcall(function()
    http.get(url, {}, function(code, body)
      STATE.rssi_requesting = false
      -- 请求发出后按 HOME 或热重载时，这个回调仍会到达。此时 launcher
      -- 可能已经接管屏幕，继续 update_success_signal() 就是往已删除或
      -- 已被复用的 obj_id 上写。
      if GUIDE.stopped or rawget(_G, "WIFI_GUIDE_APP") ~= GUIDE then return end
      if tonumber(code) ~= 200 or type(body) ~= "string" then return end
      local codec = rawget(_G, "json") or rawget(_G, "sjson")
      if not codec or not codec.decode then return end
      local doc = safe_call(function() return codec.decode(body) end)
      local wifi_state = doc and doc.wifi or nil
      local db = wifi_state and tonumber(wifi_state.sta_rssi) or nil

      -- Match the Web control page: prefer the first scan record with the
      -- connected SSID, then fall back to the actual station-link RSSI.
      local connected_ssid = wifi_state and tostring(wifi_state.sta_ssid or "") or ""
      local scans = wifi_state and wifi_state.scans or nil
      if connected_ssid ~= "" and type(scans) == "table" then
        for _, record in ipairs(scans) do
          if type(record) == "table" and tostring(record.ssid or "") == connected_ssid then
            db = tonumber(record.rssi) or db
            break
          end
        end
      end
      if not db then return end
      STATE.last_rssi = math.floor(db)
      if STATE.screen == "success" then update_success_signal(STATE.last_rssi) end
    end)
  end)
  if not started then STATE.rssi_requesting = false end
end

local function make_caption(parent, x, y, w, h, value)
  local label = make_label(parent, x, y, w, h, value, 0xFFFFFF, FONT_SMALL, LV_TEXT_ALIGN_CENTER)
  pcall(function() lv_obj_set_style_text_letter_space(label, -1, LV_PART_MAIN) end)
  return label
end

local function build_setup_ui()
  local t = TEXT[STATE.language]
  UI.setup.dot = make_panel(root, 14, 13, 8, 8, 0x22D3EE, 255, 4, 0, 0, 0)
  UI.setup.eyebrow = make_label(root, 28, 10, 180, 14, t.waiting_eyebrow, 0x8CECF2, FONT_SMALL)
  UI.setup.title = make_label(root, 14, 29, 190, 28, t.waiting_title, 0xF7FBFF, FONT_TITLE)
  UI.setup.description = make_label(root, 14, 61, 292, 30, t.waiting_desc, 0x9FB0BE, FONT_SMALL)

  UI.setup.card = make_panel(root, 14, 96, 190, 126, 0xFFFFFF, 12, 10, 1, 0x94B5C7, 46)
  UI.setup.hotspot_label = make_label(UI.setup.card, 10, 8, 62, 16, t.hotspot, 0x718695, FONT_SMALL)
  UI.setup.hotspot = make_label(UI.setup.card, 69, 8, 110, 16, SETUP_SSID, 0x8CECF2, FONT_SMALL, LV_TEXT_ALIGN_RIGHT)
  UI.setup.divider1 = make_divider(UI.setup.card, 30)
  UI.setup.portal_label = make_label(UI.setup.card, 10, 33, 62, 16, t.portal, 0x718695, FONT_SMALL)
  UI.setup.portal = make_label(UI.setup.card, 69, 33, 110, 16, SETUP_PORTAL, 0x67E8F9, FONT_SMALL, LV_TEXT_ALIGN_RIGHT)
  UI.setup.divider2 = make_divider(UI.setup.card, 55)

  UI.setup.step1_badge = make_panel(UI.setup.card, 10, 64, 18, 18, 0x22D3EE, 25, 9, 1, 0x22D3EE, 86)
  UI.setup.step1_number = make_label(UI.setup.step1_badge, 0, 1, 18, 16, "1", 0x67E8F9, FONT_SMALL, LV_TEXT_ALIGN_CENTER)
  UI.setup.step1 = make_label(UI.setup.card, 35, 63, 144, 24, t.step1, 0xA9BAC6, FONT_SMALL)
  UI.setup.step2_badge = make_panel(UI.setup.card, 10, 92, 18, 18, 0x22D3EE, 25, 9, 1, 0x22D3EE, 86)
  UI.setup.step2_number = make_label(UI.setup.step2_badge, 0, 1, 18, 16, "2", 0x67E8F9, FONT_SMALL, LV_TEXT_ALIGN_CENTER)
  UI.setup.step2 = make_label(UI.setup.card, 35, 91, 144, 24, t.step2, 0xA9BAC6, FONT_SMALL)

  UI.setup.qr_card = make_panel(root, 206, 96, 104, 126, 0x0A1922, 224, 10, 1, 0x67E8F9, 61)
  UI.setup.qr_frame, UI.setup.qr = make_qr(UI.setup.qr_card, 2, 2, 100, "http://" .. SETUP_PORTAL .. "/", t.qr_fallback)
  UI.setup.qr_title = make_label(UI.setup.qr_card, 4, 102, 96, 12, t.scan_setup, 0xDFFBFF, FONT_SMALL, LV_TEXT_ALIGN_CENTER)
  UI.setup.qr_target = make_label(UI.setup.qr_card, 4, 114, 96, 11, SETUP_PORTAL, 0x66808F, FONT_SMALL, LV_TEXT_ALIGN_CENTER)
end

local function build_success_ui()
  local t = TEXT[STATE.language]
  UI.success.dot = make_panel(root, 14, 13, 8, 8, 0x34D399, 255, 4, 0, 0, 0)
  UI.success.eyebrow = make_label(root, 28, 10, 180, 14, t.ready_eyebrow, 0x8CF2C5, FONT_SMALL)
  UI.success.title = make_label(root, 14, 29, 210, 28, t.ready_title, 0xF7FBFF, FONT_TITLE)
  UI.success.description = make_label(root, 14, 61, 292, 30, t.ready_desc, 0x9FB0BE, FONT_SMALL)

  UI.success.card = make_panel(root, 14, 96, 190, 126, 0xFFFFFF, 12, 10, 1, 0x94B5C7, 46)
  UI.success.wifi_label = make_label(UI.success.card, 10, 17, 48, 16, t.wifi, 0x718695, FONT_SMALL)
  UI.success.wifi = make_label(UI.success.card, 58, 17, 121, 16, t.unknown_wifi, 0xEDF8FF, FONT_SMALL, LV_TEXT_ALIGN_RIGHT)
  UI.success.divider1 = make_divider(UI.success.card, 39)
  UI.success.signal_label = make_label(UI.success.card, 10, 42, 48, 16, t.signal, 0x718695, FONT_SMALL)
  UI.success.signal = make_label(UI.success.card, 107, 42, 72, 16, t.unknown_signal, 0xEDF8FF, FONT_SMALL, LV_TEXT_ALIGN_RIGHT)
  UI.success.signal_bars = {}
  local heights = { 4, 7, 10, 12 }
  for i = 1, 4 do
    UI.success.signal_bars[i] = make_panel(UI.success.card, 58 + ((i - 1) * 8), 57 - heights[i], 5, heights[i], 0x48606E, 255, 2, 0, 0, 0)
  end
  UI.success.divider2 = make_divider(UI.success.card, 64)
  UI.success.ip_label = make_label(UI.success.card, 10, 67, 48, 16, t.ip, 0x718695, FONT_SMALL)
  UI.success.ip = make_label(UI.success.card, 58, 67, 121, 16, "--", 0x67E8F9, FONT_SMALL, LV_TEXT_ALIGN_RIGHT)
  UI.success.divider3 = make_divider(UI.success.card, 89)
  UI.success.domain_label = make_label(UI.success.card, 10, 92, 48, 16, t.domain, 0x718695, FONT_SMALL)
  UI.success.domain = make_label(UI.success.card, 58, 92, 121, 16, DEVICE_HOST, 0x8CF2C5, FONT_SMALL, LV_TEXT_ALIGN_RIGHT)

  UI.success.qr_card = make_panel(root, 206, 96, 104, 126, 0x0A1922, 224, 10, 1, 0x67E8F9, 61)
  UI.success.qr_title = make_caption(UI.success.qr_card, 0, 104, 104, 18, t.scan_control)
end

local function build_ui()
  UI = { setup = {}, success = {} }
  UI.bg = make_panel(root, 0, 0, SCREEN_W, SCREEN_H, 0x000000, 255, 0, 0, 0, 0)
  build_setup_ui()
  build_success_ui()
end

local function show_setup()
  STATE.connected = false
  STATE.screen = "setup"
  set_group_visible(UI.success, false)
  set_group_visible(UI.setup, true)
end

local function rebuild_success_qr(ip)
  if UI.success.qr_frame then
    pcall(function() lv_obj_del(UI.success.qr_frame) end)
    UI.success.qr_frame = nil
    UI.success.qr = nil
  end
  local target = "http://" .. ip .. "/"
  UI.success.qr_frame, UI.success.qr = make_qr(UI.success.qr_card, 2, 2, 100, target, TEXT[STATE.language].qr_fallback)
end

local function show_success(ip)
  STATE.connected = true
  STATE.screen = "success"
  if looks_like_ip(ip) then STATE.last_ip = ip end
  local display_ip = looks_like_ip(STATE.last_ip) and STATE.last_ip or "--"
  safe_set_text(UI.success.ip, display_ip)
  safe_set_text(UI.success.wifi, wifi_name())
  local db = wifi_rssi()
  update_success_signal(db)
  if looks_like_ip(display_ip) then rebuild_success_qr(display_ip) end
  set_group_visible(UI.setup, false)
  set_group_visible(UI.success, true)
  request_system_rssi(true)
end

local function rebuild_for_language(language)
  STATE.language = language
  release_fonts()
  lv_obj_clean(root)
  init_fonts()
  build_ui()
  if STATE.connected then show_success(STATE.last_ip) else show_setup() end
end

local function check_state()
  local language = selected_language()
  if language ~= STATE.language then rebuild_for_language(language) end

  local connected, ip = wifi_connected()
  if connected then
    if not STATE.connected or STATE.screen ~= "success" or (looks_like_ip(ip) and ip ~= STATE.last_ip) then
      show_success(ip)
    else
      safe_set_text(UI.success.wifi, wifi_name())
      local db = wifi_rssi()
      update_success_signal(db)
      request_system_rssi(false)
    end
  elseif STATE.connected or STATE.screen ~= "setup" then
    show_setup()
  end
end

function GUIDE.stop(reason)
  if GUIDE.stopped then
    return
  end
  GUIDE.stopped = true

  stop_timer("poll_timer")
  stop_timer("controller_timer")
  pcall(function() key.off() end)
  -- 先删引用字体的 LVGL 对象，再 lv_font_free；反过来会留下指向已释放
  -- 字体的样式，渲染任务碰到就是 use-after-free。
  if lv_obj_clean then
    pcall(function() lv_obj_clean(root) end)
  end
  release_fonts()
  if rawget(_G, "WIFI_GUIDE_APP") == GUIDE then
    _G.WIFI_GUIDE_APP = nil
  end
end

GUIDE.shutdown = GUIDE.stop

local function leave_app()
  GUIDE.stop("exit")
  if app and app.exit then pcall(function() app.exit() end) end
end

if controller and controller.state and tmr and tmr.create then
  local controller_buttons = 0
  STATE.controller_timer = tmr.create()
  STATE.controller_timer:alarm(40, tmr.ALARM_AUTO, function()
    local ok, pad = pcall(function() return controller.state("ble-main") end)
    local buttons = ok and type(pad) == "table" and (tonumber(pad.buttons) or 0) or 0
    local pressed = buttons & (~controller_buttons)
    controller_buttons = buttons
    if (pressed & (4096 | 32768)) ~= 0 then leave_app() end
  end)
end

STATE.language = selected_language()
init_fonts()
build_ui()
show_setup()
check_state()

STATE.poll_timer = tmr.create()
STATE.poll_timer:alarm(1200, tmr.ALARM_AUTO, check_state)

key.on(key.HOME, function(event_type)
  if event_type == key.SHORT or event_type == key.START then leave_app() end
end)
