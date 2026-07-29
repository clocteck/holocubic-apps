local prev = rawget(_G, "SETTINGS_APP")
if prev and prev.stop then
  pcall(function()
    prev.stop("reload")
  end)
elseif prev and prev.shutdown then
  pcall(function()
    prev.shutdown("reload")
  end)
end

SETTINGS_APP = {
  VERSION = "2026-07-13-settings-hidpad-v3",
  APP_DIR = "/sd/apps/settings",
  SCREEN_W = 320,
  SCREEN_H = 240,
  timers = {},
  font_handles = {},
  selected_index = 1,
  rendered_page = nil,
  state = {
    page = 1,
    last_wifi_mode = nil,
    wifi_mode = nil,
    ip_text = "--",
    ip_mode = "OFF",
    wifi_ssid = "--",
    message = "",
    slider_syncing = false,
    input_mode = "none",
    repeat_state = {},
    key_debounce = {},
    hidpad_status = nil,
    hidpad_status_ms = 0,
    hidpad_request_ms = 0,
    hidpad_installed = nil,
    hidpad_catalog_ms = 0,
    hidpad_pending_command = nil,
  },
  input = {
    up_code = nil,
    down_code = nil,
    left_code = nil,
    right_code = nil,
    home_code = nil,
    short_type = nil,
    start_type = nil,
    long_start_type = nil,
    long_repeat_type = nil,
    long_end_type = nil,
    exit_type = nil,
    debounce_ms = 120,
  },
  ui = {
    cards = {},
    info_rows = {},
  },
  items = {
    {
      id = "wifi",
      kind = "wifi",
      title = "Wi-Fi",
      value = false,
      available = true,
      accent = 0x58B3FF,
      detail = "--",
      hint = "",
    },
    {
      id = "hidpad",
      kind = "toggle",
      title = "蓝牙手柄",
      value = false,
      available = true,
      accent = 0x4DBD8B,
      detail = "--",
      hint = "",
      name = "",
      address = "",
      profile = "",
      phase = "unsupported",
      buttons = 0,
      raw_buttons = 0,
    },
    {
      id = "brightness",
      kind = "slider",
      title = "亮度",
      value = 80,
      available = true,
      accent = 0xF3B24C,
      step = 5,
      detail = "80%",
      hint = "",
    },
  },
  info_items = {},
}

local APP = SETTINGS_APP
local HIDPAD_SERVICE_ID = "hidpad"
local HIDPAD_ENDPOINT = "ble-controller"
local SETTINGS_HIDPAD_ENDPOINT = "settings-hidpad"
local HIDPAD_MANIFEST_PATH = "/sd/apps/hidpad/app.info"
local HIDPAD_CATALOG_CACHE_MS = 5000
local HIDPAD_STATUS_INTERVAL_MS = 1000
local HIDPAD_STATUS_TTL_MS = 3500

local MAIN_PART = rawget(_G, "LV_PART_MAIN") or 0
local DEFAULT_STATE = rawget(_G, "LV_STATE_DEFAULT") or 0
local MAIN_STYLE = MAIN_PART | DEFAULT_STATE
local PART_INDICATOR = rawget(_G, "LV_PART_INDICATOR") or MAIN_PART
local PART_KNOB = rawget(_G, "LV_PART_KNOB") or MAIN_PART
local LABEL_LONG_CLIP = rawget(_G, "LV_LABEL_LONG_CLIP") or rawget(_G, "LABEL_LONG_CLIP")
local FLAG_SCROLLABLE = rawget(_G, "LV_OBJ_FLAG_SCROLLABLE") or rawget(_G, "OBJ_FLAG_SCROLLABLE")
local ANIM_OFF = rawget(_G, "LV_ANIM_OFF") or 0
local EVENT_VALUE_CHANGED = rawget(_G, "LV_EVENT_VALUE_CHANGED")
local ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1
local KEYMOD = rawget(_G, "key")

local FONT = {
  title = rawget(_G, "LV_FONT_MONTSERRAT_18") or rawget(_G, "LV_FONT_MONTSERRAT_20") or 20,
  label = rawget(_G, "LV_FONT_MONTSERRAT_16") or 16,
  value = rawget(_G, "LV_FONT_MONTSERRAT_16") or 16,
  small = rawget(_G, "LV_FONT_MONTSERRAT_12") or 12,
  tiny = rawget(_G, "LV_FONT_MONTSERRAT_10") or 10,
}

local C = {
  bg = 0x101317,
  panel = 0x20252B,
  panel_active = 0x29313A,
  panel_border = 0x343B44,
  panel_focus = 0x1FA5FF,
  badge = 0x252B34,
  badge_active = 0x26313B,
  title = 0xF7F9FB,
  text = 0xF6F8FA,
  text_dim = 0x9AABC0,
  text_muted = 0x8E9BAA,
  blue = 0x5EB8FF,
  line = 0x2A3139,
  white = 0xFFFFFF,
  slider_bg = 0x3B424B,
  danger = 0xFF6B6B,
}

local function safe_call(tag, fn)
  local ok, a, b, c = pcall(fn)
  if not ok then
    print("[settings]", tag, tostring(a))
    return nil, tostring(a)
  end
  return a, b, c
end

local function try_call(tag, fn)
  local ok, a, b = pcall(fn)
  if not ok then
    print("[settings]", tag, tostring(a))
    return nil, tostring(a)
  end
  if (a == nil or a == false) and b ~= nil then
    return nil, tostring(b)
  end
  return true
end

local function text_or(value, fallback)
  if value == nil or value == "" then
    return fallback or ""
  end
  return tostring(value)
end

local function clip_text(text, max_len)
  local s = text_or(text, "")
  local limit = tonumber(max_len) or 0
  if limit <= 0 or #s <= limit then
    return s
  end
  if limit <= 3 then
    return s:sub(1, limit)
  end
  return s:sub(1, limit - 3) .. "..."
end

local function clip_utf8_chars(text, max_chars)
  local s = text_or(text, "")
  local limit = tonumber(max_chars) or 0
  if limit <= 0 or s == "" then
    return s
  end

  local out = {}
  local count = 0
  local i = 1
  local len = #s
  while i <= len do
    local byte = s:byte(i)
    local step = 1
    if byte >= 0xF0 then
      step = 4
    elseif byte >= 0xE0 then
      step = 3
    elseif byte >= 0xC0 then
      step = 2
    end

    count = count + 1
    if count > limit then
      return table.concat(out) .. "..."
    end
    out[#out + 1] = s:sub(i, math.min(i + step - 1, len))
    i = i + step
  end

  return s
end

local function clamp(value, min_value, max_value)
  local num = tonumber(value) or min_value
  if num < min_value then
    return min_value
  end
  if num > max_value then
    return max_value
  end
  return math.floor(num + 0.5)
end

local function clock_ms()
  if sys and sys.millis then
    local ok, value = pcall(function()
      return sys.millis()
    end)
    if ok and type(value) == "number" then
      return value
    end
  end
  if type(millis) == "function" then
    local ok, value = pcall(millis)
    if ok and type(value) == "number" then
      return value
    end
  end
  if os and type(os.clock) == "function" then
    return math.floor(os.clock() * 1000)
  end
  return 0
end

local function json_encode(value)
  if not json or not json.encode then
    return nil, "json.encode 不可用"
  end
  local ok, raw = pcall(function()
    return json.encode(value)
  end)
  if not ok then
    return nil, tostring(raw)
  end
  return raw
end

local function json_decode(raw)
  if not json or not json.decode then
    return nil, "json.decode 不可用"
  end
  local ok, value, err = pcall(function()
    return json.decode(raw)
  end)
  if not ok then
    return nil, tostring(value)
  end
  if type(value) ~= "table" then
    return nil, tostring(err or "状态格式错误")
  end
  return value
end

local function disable_scroll(obj)
  if obj and lv_obj_clear_flag and FLAG_SCROLLABLE then
    pcall(function()
      lv_obj_clear_flag(obj, FLAG_SCROLLABLE)
    end)
  end
end

local function add_timer(ms, auto, fn)
  if not tmr or not tmr.create then
    return nil
  end
  local timer = tmr.create()
  APP.timers[#APP.timers + 1] = timer
  timer:alarm(ms, auto and tmr.ALARM_AUTO or tmr.ALARM_SINGLE, fn)
  return timer
end

local function stop_timers()
  for i = 1, #APP.timers do
    local timer = APP.timers[i]
    pcall(function() timer:stop() end)
    pcall(function() timer:unregister() end)
  end
  APP.timers = {}
end

local function load_font_ref(path, fallback)
  if lv_font_load then
    local ok, handle = pcall(function()
      return lv_font_load(path)
    end)
    if ok and type(handle) == "number" and handle > 0 then
      APP.font_handles[#APP.font_handles + 1] = handle
      return handle
    end
  end
  return fallback
end

local function init_fonts()
  FONT.title = load_font_ref(APP.APP_DIR .. "/font/settings_cn_18_used.bin", FONT.title)
  FONT.label = load_font_ref(APP.APP_DIR .. "/font/settings_cn_15_used.bin", FONT.label)
  FONT.value = load_font_ref(APP.APP_DIR .. "/font/settings_cn_15_used.bin", FONT.value)
  FONT.small = load_font_ref(APP.APP_DIR .. "/font/settings_cn_12_common3000.bin", FONT.small)
end

local function release_fonts()
  if lv_font_free then
    for _, handle in ipairs(APP.font_handles or {}) do
      pcall(function()
        lv_font_free(handle)
      end)
    end
  end
  APP.font_handles = {}
end

local function style_panel(obj, bg, border, radius, shadow, border_width)
  if not obj then
    return
  end
  lv_obj_set_style_bg_color(obj, bg, MAIN_STYLE)
  lv_obj_set_style_bg_opa(obj, 255, MAIN_STYLE)
  lv_obj_set_style_border_width(obj, border and (border_width or 1) or 0, MAIN_STYLE)
  if border then
    lv_obj_set_style_border_color(obj, border, MAIN_STYLE)
    lv_obj_set_style_border_opa(obj, 255, MAIN_STYLE)
  end
  lv_obj_set_style_radius(obj, radius or 12, MAIN_STYLE)
  lv_obj_set_style_pad_all(obj, 0, MAIN_STYLE)
  if lv_obj_set_style_shadow_width then
    lv_obj_set_style_shadow_width(obj, shadow or 0, MAIN_STYLE)
    if shadow and shadow > 0 then
      lv_obj_set_style_shadow_color(obj, 0x000000, MAIN_STYLE)
      lv_obj_set_style_shadow_opa(obj, 72, MAIN_STYLE)
    end
  end
end

local function style_text(obj, font_ref, color, align)
  if not obj then
    return
  end
  lv_obj_set_style_text_font(obj, font_ref, MAIN_STYLE)
  lv_obj_set_style_text_color(obj, color, MAIN_STYLE)
  lv_obj_set_style_text_opa(obj, 255, MAIN_STYLE)
  if align and lv_obj_set_style_text_align then
    lv_obj_set_style_text_align(obj, align, MAIN_STYLE)
  end
end

local function create_text(parent, text, font_ref, color, x, y, width, align)
  local id = lv_label_create(parent)
  lv_label_set_text(id, text_or(text, ""))
  if width then
    lv_obj_set_width(id, width)
  end
  if LABEL_LONG_CLIP and lv_label_set_long_mode then
    lv_label_set_long_mode(id, LABEL_LONG_CLIP)
  end
  style_text(id, font_ref, color, align)
  lv_obj_set_pos(id, x, y)
  return id
end

local function style_slider(obj, accent)
  if not obj then
    return
  end
  lv_obj_set_style_bg_color(obj, C.slider_bg, MAIN_STYLE)
  lv_obj_set_style_bg_opa(obj, 255, MAIN_STYLE)
  lv_obj_set_style_border_width(obj, 0, MAIN_STYLE)
  lv_obj_set_style_radius(obj, 6, MAIN_STYLE)
  lv_obj_set_style_bg_color(obj, accent or APP.items[3].accent, PART_INDICATOR)
  lv_obj_set_style_bg_opa(obj, 255, PART_INDICATOR)
  lv_obj_set_style_border_width(obj, 0, PART_INDICATOR)
  lv_obj_set_style_radius(obj, 6, PART_INDICATOR)
  lv_obj_set_style_bg_color(obj, C.white, PART_KNOB)
  lv_obj_set_style_bg_opa(obj, 255, PART_KNOB)
  lv_obj_set_style_border_width(obj, 0, PART_KNOB)
  lv_obj_set_style_radius(obj, 10, PART_KNOB)
end

local function set_message(text)
  APP.state.message = clip_text(text, 54)
end

local function current_item()
  return APP.items[APP.selected_index]
end

local function brightness_text(value)
  return tostring(clamp(value or 0, 0, 100)) .. "%"
end

local function wifi_mode_name(mode)
  if wifi then
    if mode == wifi.NULLMODE then return "OFF" end
    if mode == wifi.STATION then return "STA" end
    if mode == wifi.SOFTAP then return "AP" end
    if mode == wifi.STATIONAP then return "STA+AP" end
  end
  return tostring(mode or "?")
end

local function wifi_value_text(mode)
  if not wifi then
    return "不可用"
  end
  if mode == wifi.NULLMODE then return "关闭" end
  if mode == wifi.STATION then return "客户端" end
  if mode == wifi.SOFTAP then return "热点" end
  if mode == wifi.STATIONAP then return "客户端+热点" end
  return wifi_mode_name(mode)
end

local function toggle_state_text(item)
  if not item then
    return "不可用"
  end
  if item.id == "hidpad" then
    if item.phase == "unsupported" then return "不支持" end
    if not item.available then return "不可用" end
    if not item.value or item.phase == "disabled" then return "已禁用" end
    if item.state_connected then return "已连接" end
    if item.state_connecting or item.phase == "connecting" then return "连接中" end
    if item.phase == "scanning" or item.phase == "select_device" then return "扫描中" end
    return "已开启"
  end
  if not item.available then return "不可用" end
  return item.value and "开启" or "关闭"
end

local function item_summary(item)
  if not item then
    return "设置"
  end
  if item.id == "wifi" then
    return "Wi-Fi " .. text_or(item.value_label, "")
  elseif item.id == "brightness" then
    return "亮度 " .. brightness_text(item.value)
  elseif item.id == "hidpad" then
    return "蓝牙手柄 " .. toggle_state_text(item)
  end
  return item.title
end

local function hidpad_installed(force)
  local stamp = clock_ms()
  local cached_at = tonumber(APP.state.hidpad_catalog_ms) or 0
  if not force
    and APP.state.hidpad_installed ~= nil
    and stamp >= cached_at
    and (stamp - cached_at) < HIDPAD_CATALOG_CACHE_MS
  then
    return APP.state.hidpad_installed
  end

  local installed = false
  if app and app.services then
    local ok, services = pcall(function()
      return app.services()
    end)
    if ok and type(services) == "table" then
      for _, record in ipairs(services) do
        if type(record) == "table" and record.id == HIDPAD_SERVICE_ID then
          installed = true
          break
        end
      end
    end
  end
  if not installed and file and file.stat then
    local ok, stat = pcall(function()
      return file.stat(HIDPAD_MANIFEST_PATH)
    end)
    installed = ok and type(stat) == "table"
  end

  APP.state.hidpad_installed = installed
  APP.state.hidpad_catalog_ms = stamp
  if not installed then
    APP.state.hidpad_status = nil
    APP.state.hidpad_status_ms = 0
  end
  return installed
end

local function hidpad_service_running()
  if not app or not app.services then
    return false
  end
  local ok, services = pcall(function()
    return app.services()
  end)
  if not ok or type(services) ~= "table" then
    return false
  end
  for _, record in ipairs(services) do
    if type(record) == "table" and record.id == HIDPAD_SERVICE_ID then
      return true
    end
  end
  return false
end

local function send_hidpad_command(topic)
  if not hidpad_installed(false) then
    return nil, "不支持"
  end
  if not ipc or not ipc.send then
    return nil, "手柄通信不可用"
  end
  local payload, encode_err = json_encode({ reply = SETTINGS_HIDPAD_ENDPOINT })
  if not payload then
    return nil, encode_err
  end
  local ok_call, sent, send_err = pcall(function()
    return ipc.send(HIDPAD_ENDPOINT, topic, payload)
  end)
  if not ok_call then
    return nil, tostring(sent)
  end
  if not sent then
    return nil, tostring(send_err or "手柄服务未运行")
  end
  return true
end

local function request_hidpad_status(force)
  if not hidpad_installed(false) then
    return false
  end
  local stamp = clock_ms()
  local requested_at = tonumber(APP.state.hidpad_request_ms) or 0
  if not force
    and stamp >= requested_at
    and (stamp - requested_at) < HIDPAD_STATUS_INTERVAL_MS
  then
    return true
  end
  APP.state.hidpad_request_ms = stamp
  local ok = send_hidpad_command("status")
  return ok == true
end

local function bind_hidpad_status()
  if not ipc or not ipc.listen then
    return false
  end
  local ok_call, listened, listen_err = pcall(function()
    return ipc.listen(SETTINGS_HIDPAD_ENDPOINT, function(topic, payload)
      if topic ~= "status" or type(payload) ~= "string" then
        return
      end
      local status, decode_err = json_decode(payload)
      if not status then
        print("[settings] hidpad.status", tostring(decode_err))
        return
      end
      APP.state.hidpad_status = status
      APP.state.hidpad_status_ms = clock_ms()
    end)
  end)
  if not ok_call or not listened then
    print("[settings] hidpad.listen", tostring(listen_err or listened))
    return false
  end
  return true
end

local function hidpad_identity(name, address)
  local device_name = clip_utf8_chars(text_or(name, ""), 9)
  local device_address = text_or(address, "")
  if #device_address > 8 then
    device_address = device_address:sub(-8)
  end
  if device_name ~= "" and device_address ~= "" then
    return device_name .. " · " .. device_address
  end
  return device_name ~= "" and device_name or device_address
end

local function button_bitmap(value)
  local mask = tonumber(value) or 0
  if mask < 0 then mask = 0 end
  return string.format("0x%04X", mask & 0xFFFF)
end

local function refresh_wifi_item()
  local item = APP.items[1]
  APP.state.wifi_mode = nil
  APP.state.wifi_ssid = "--"
  item.available = false
  item.value = false
  item.detail = "不可用"
  item.value_label = "不可用"
  item.hint = ""

  if not wifi or not wifi.getmode then
    return
  end

  local mode, err = safe_call("wifi.getmode", function()
    return wifi.getmode()
  end)
  if mode == nil then
    item.detail = clip_text(err or "读取失败", 18)
    return
  end

  APP.state.wifi_mode = mode
  item.available = true
  item.value = mode ~= wifi.NULLMODE
  item.value_label = wifi_value_text(mode)

  if wifi.sta and wifi.sta.getconfig and (mode == wifi.STATION or mode == wifi.STATIONAP) then
    local cfg = safe_call("wifi.sta.getconfig", function()
      return wifi.sta.getconfig()
    end)
    if type(cfg) == "table" and text_or(cfg.ssid, "") ~= "" then
      APP.state.wifi_ssid = clip_utf8_chars(cfg.ssid, 10)
    end
  end

  if item.value then
    APP.state.last_wifi_mode = mode
    item.detail = wifi_mode_name(mode)
    item.hint = "← 关闭  切换 →"
  else
    item.detail = "未启用"
    item.hint = "← 关闭  开启 →"
  end
end

local function refresh_hidpad_item()
  local item = APP.items[2]
  item.available = false
  item.value = false
  item.state_connected = false
  item.state_connecting = false
  item.phase = "unsupported"
  item.detail = "不支持"
  item.name = ""
  item.address = ""
  item.profile = ""
  item.buttons = 0
  item.raw_buttons = 0
  item.pressed = 0
  item.released = 0
  item.scan_count = 0
  item.last_error = ""
  item.hint = ""

  if not hidpad_installed(false) then
    return
  end

  local running = hidpad_service_running()
  if running and APP.state.hidpad_pending_command then
    local pending = APP.state.hidpad_pending_command
    local sent = send_hidpad_command(pending)
    if sent then
      APP.state.hidpad_pending_command = nil
    end
  end
  if running then
    request_hidpad_status(false)
  end

  item.available = true
  item.phase = running and "starting" or "stopped"
  item.value = running

  local stamp = clock_ms()
  local status_at = tonumber(APP.state.hidpad_status_ms) or 0
  local status = APP.state.hidpad_status
  local status_fresh = type(status) == "table"
    and stamp >= status_at
    and (stamp - status_at) <= HIDPAD_STATUS_TTL_MS
  if status_fresh then
    item.value = status.enabled ~= false
    item.phase = text_or(status.phase, item.value and "idle" or "disabled")
    item.state_connected = status.connected == true
    item.state_connecting = status.connecting == true
    item.name = text_or(status.name, "")
    item.address = text_or(status.address, "")
    item.profile = text_or(status.profile, "")
    item.buttons = tonumber(status.buttons) or 0
    item.raw_buttons = tonumber(status.raw_buttons) or 0
    item.scan_count = tonumber(status.scan_count) or 0
    item.last_error = text_or(status.error, "")
  end

  if controller and controller.state then
    local ok, state = pcall(function()
      return controller.state("ble-main")
    end)
    if ok and type(state) == "table" then
      item.state_connected = item.state_connected or state.connected == true
      item.buttons = tonumber(state.buttons) or item.buttons
      item.pressed = tonumber(state.pressed) or 0
      item.released = tonumber(state.released) or 0
      if item.name == "" then item.name = text_or(state.name, "") end
      if item.address == "" then item.address = text_or(state.device_id, "") end
    end
  end

  local identity = hidpad_identity(item.name, item.address)
  if item.last_error:find("版本不支持", 1, true) then
    item.available = false
    item.value = false
    item.phase = "unsupported"
    item.detail = "不支持"
    item.hint = ""
    return
  elseif status_fresh and (status.command_ok == false or item.phase == "error") and item.last_error ~= "" then
    item.detail = clip_utf8_chars(item.last_error, 14)
    item.hint = "← 关闭  重扫 →"
    return
  end
  if not running and not status_fresh then
    item.value = false
    item.detail = "服务未运行"
    item.hint = "→ 启动服务"
    return
  elseif not item.value or item.phase == "disabled" then
    item.value = false
    item.phase = "disabled"
    item.detail = "BLE 驱动已停止"
    item.hint = "← 关闭  开启 →"
    return
  end

  if item.state_connected then
    item.detail = identity ~= "" and identity or "已连接"
    item.hint = item.buttons ~= 0 and ("按键 " .. button_bitmap(item.buttons)) or "← 关闭  重扫 →"
  elseif item.state_connecting then
    item.detail = identity ~= "" and identity or "正在连接手柄"
    item.hint = "← 关闭  重扫 →"
  elseif item.phase == "scanning" or item.phase == "select_device" then
    item.detail = item.scan_count > 0 and ("发现 " .. tostring(item.scan_count) .. " 个设备") or "正在查找手柄"
    item.hint = "← 关闭  重扫 →"
  else
    item.detail = identity ~= "" and identity or "等待设备"
    item.hint = "← 关闭  重扫 →"
  end
end

local function refresh_brightness_item()
  local item = APP.items[3]
  item.available = false
  item.detail = "不可用"
  item.hint = ""

  if not sys or not sys.getbrightness then
    return
  end

  local level, err = safe_call("sys.getbrightness", function()
    return sys.getbrightness()
  end)
  if level == nil then
    item.detail = clip_text(err or "读取失败", 18)
    return
  end

  item.available = true
  item.value = clamp(level, 0, 100)
  item.detail = brightness_text(item.value)
  item.hint = "← 降低  提高 →"
end

local function refresh_ip_state()
  local mode = APP.state.wifi_mode
  APP.state.ip_text = "--"
  APP.state.ip_mode = "OFF"
  if mode == nil or (wifi and mode == wifi.NULLMODE) then
    return
  end

  local sta_ip = nil
  local ap_ip = nil
  if wifi and wifi.sta and wifi.sta.getip and (mode == wifi.STATION or mode == wifi.STATIONAP) then
    sta_ip = safe_call("wifi.sta.getip", function()
      return wifi.sta.getip()
    end)
  end
  if wifi and wifi.ap and wifi.ap.getip and (mode == wifi.SOFTAP or mode == wifi.STATIONAP) then
    ap_ip = safe_call("wifi.ap.getip", function()
      return wifi.ap.getip()
    end)
  end

  if sta_ip and sta_ip ~= "" then
    APP.state.ip_text = sta_ip
    APP.state.ip_mode = "STA"
  elseif ap_ip and ap_ip ~= "" then
    APP.state.ip_text = ap_ip
    APP.state.ip_mode = "AP"
  else
    APP.state.ip_text = "未分配 IP"
    APP.state.ip_mode = wifi_mode_name(mode)
  end
end

local function refresh_runtime_state()
  refresh_wifi_item()
  refresh_hidpad_item()
  refresh_brightness_item()
  refresh_ip_state()
end

local function ensure_wifi_started(target_mode)
  local ok_mode, err_mode = try_call("wifi.mode", function()
    return wifi.mode(target_mode, false)
  end)
  if ok_mode == nil then
    return nil, err_mode or "Wi-Fi 设置失败"
  end

  if wifi.start then
    local ok_start, err_start = try_call("wifi.start", function()
      return wifi.start()
    end)
    if ok_start == nil then
      return nil, err_start or "Wi-Fi 启动失败"
    end
  end

  if wifi.sta and wifi.sta.connect and (target_mode == wifi.STATION or target_mode == wifi.STATIONAP) then
    pcall(function()
      wifi.sta.connect()
    end)
  end

  APP.state.last_wifi_mode = target_mode
  return true
end

local function set_wifi_enabled(enable)
  if not wifi or not wifi.getmode or not wifi.mode then
    return nil, "Wi-Fi 不可用"
  end

  if enable then
    local target_mode = APP.state.last_wifi_mode or wifi.STATION
    if target_mode == wifi.NULLMODE then
      target_mode = wifi.STATION
    end
    local ok, err = ensure_wifi_started(target_mode)
    if ok == nil then
      return nil, err
    end
    return true, "Wi-Fi " .. wifi_value_text(target_mode)
  end

  local mode = safe_call("wifi.getmode.before_off", function()
    return wifi.getmode()
  end)
  if mode and mode ~= wifi.NULLMODE then
    APP.state.last_wifi_mode = mode
  end
  if wifi.stop then
    pcall(function()
      wifi.stop()
    end)
  end
  local ok_mode, err_mode = try_call("wifi.mode.off", function()
    return wifi.mode(wifi.NULLMODE, false)
  end)
  if ok_mode == nil then
    return nil, err_mode or "Wi-Fi 关闭失败"
  end
  return true, "Wi-Fi 已关闭"
end

local function cycle_wifi_mode()
  if not wifi or not wifi.mode then
    return nil, "Wi-Fi 不可用"
  end
  local mode = APP.state.wifi_mode
  local target = wifi.STATION
  if mode == wifi.STATION then
    target = wifi.SOFTAP
  elseif mode == wifi.SOFTAP then
    target = wifi.STATIONAP
  elseif mode == wifi.STATIONAP then
    target = wifi.STATION
  end
  local ok, err = ensure_wifi_started(target)
  if ok == nil then
    return nil, err
  end
  return true, "Wi-Fi " .. wifi_value_text(target)
end

local function set_hidpad_enabled(enable)
  if not hidpad_installed(false) then
    return nil, "蓝牙手柄不支持"
  end

  local command = enable and "enable" or "disable"
  if not hidpad_service_running() then
    APP.state.hidpad_pending_command = command
    if enable and app and app.start_service then
      local ok_call, started, start_err = pcall(function()
        return app.start_service(HIDPAD_SERVICE_ID)
      end)
      if not ok_call or not started then
        return nil, tostring(start_err or started or "手柄服务启动失败")
      end
      return true, "手柄服务启动中"
    end
    return true, "等待手柄服务"
  end

  local sent, send_err = send_hidpad_command(command)
  if not sent then
    return nil, send_err
  end
  return true, enable and "蓝牙手柄正在开启" or "蓝牙手柄正在关闭"
end

local function rescan_hidpad()
  if not hidpad_installed(false) then
    return nil, "蓝牙手柄不支持"
  end
  local sent, send_err = send_hidpad_command("rescan")
  if not sent then
    return nil, send_err
  end
  return true, "蓝牙手柄重新扫描"
end

local function set_brightness_level(level)
  local item = APP.items[3]
  local target = clamp(level, 0, 100)
  if not sys or not sys.setbrightness then
    item.available = false
    return nil, "亮度不可用"
  end
  local ok_call, ok_set, err = pcall(function()
    return sys.setbrightness(target)
  end)
  if not ok_call or not ok_set then
    return nil, tostring(err or ok_set or "亮度设置失败")
  end
  item.available = true
  item.value = target
  item.detail = brightness_text(target)
  return true, "亮度 " .. item.detail
end

local function apply_selected_value(direction)
  if APP.selected_index == 4 then
    APP.state.page = APP.state.page == 1 and 2 or 1
    APP.selected_index = 4
    set_message(APP.state.page == 1 and "设置" or "设备信息")
    return
  end

  local item = current_item()
  if not item then
    return
  end

  local ok, message
  if item.id == "wifi" then
    if direction < 0 then
      ok, message = set_wifi_enabled(false)
    else
      ok, message = cycle_wifi_mode()
    end
  elseif item.id == "hidpad" then
    if direction < 0 then
      ok, message = set_hidpad_enabled(false)
    else
      if item.value then
        ok, message = rescan_hidpad()
      else
        ok, message = set_hidpad_enabled(true)
      end
    end
  elseif item.id == "brightness" then
    ok, message = set_brightness_level(item.value + (direction > 0 and item.step or -item.step))
  else
    ok, message = nil, "不支持"
  end

  refresh_runtime_state()
  set_message(ok and message or (message or "操作失败"))
end

local function move_selection(delta)
  if APP.state.page == 2 then
    APP.state.page = 1
    APP.selected_index = delta < 0 and 3 or 1
    set_message(item_summary(current_item()))
    return
  end

  local next_index = APP.selected_index + (delta or 0)
  if next_index < 1 then
    next_index = 4
  elseif next_index > 4 then
    next_index = 1
  end
  APP.selected_index = next_index
  if next_index == 4 then
    set_message("左右切换页面")
  else
    set_message(item_summary(current_item()))
  end
end

local function format_bytes(value)
  local n = tonumber(value)
  if not n or n <= 0 then
    return "--"
  end
  if n >= 1024 * 1024 * 1024 then
    return string.format("%.1fGB", n / (1024 * 1024 * 1024))
  end
  if n >= 1024 * 1024 then
    return string.format("%.1fMB", n / (1024 * 1024))
  end
  if n >= 1024 then
    return string.format("%.1fKB", n / 1024)
  end
  return tostring(n) .. "B"
end

local function refresh_info_items()
  local remain, used, total = nil, nil, nil
  if file and file.fsinfo then
    remain, used, total = safe_call("file.fsinfo", function()
      return file.fsinfo()
    end)
  end

  local version = "--"
  if sys and sys.version then
    local v = safe_call("sys.version", function()
      return sys.version()
    end)
    version = text_or(v, "--")
  end

  local bluetooth = "不支持"
  local gp = APP.items[2]
  if gp.available then
    bluetooth = toggle_state_text(gp)
    local identity = hidpad_identity(gp.name, gp.address)
    if identity ~= "" then
      bluetooth = bluetooth .. " · " .. identity
    end
  end

  local sd_text = "--"
  if total then
    sd_text = format_bytes(used) .. " / 余 " .. format_bytes(remain)
  end

  APP.info_items = {
    { name = "处理器", value = "ESP32-S3 · 240M" },
    { name = "运存", value = "8 MB PSRAM" },
    { name = "SD卡", value = sd_text },
    { name = "系统版本", value = version },
    { name = "Wi-Fi", value = APP.state.wifi_ssid },
    { name = "IP 地址", value = APP.state.ip_text },
    { name = "蓝牙手柄", value = bluetooth },
  }
end

-- 前置声明：refresh_ui / build_ui 以前是全局函数，即使 stop() 清掉了
-- SETTINGS_APP，这两个闭包仍持有局部 APP，整份状态无法回收；别的 app
-- 若碰巧调到同名全局，还会用已释放的字体和失效 obj_id 重建 Settings UI。
local refresh_ui, build_ui

local function create_header(title)
  APP.ui.title = create_text(APP.ui.root, title, FONT.title, C.title, 14, 8, 160)
  APP.ui.badge_box = lv_obj_create(APP.ui.root)
  lv_obj_set_size(APP.ui.badge_box, 58, 22)
  lv_obj_set_pos(APP.ui.badge_box, 248, 9)
  disable_scroll(APP.ui.badge_box)
  APP.ui.badge_label = create_text(APP.ui.badge_box, APP.state.page .. " / 2", FONT.small, C.text, 2, 3, 54, ALIGN_CENTER)
end

local function build_settings_page()
  create_header("设置")

  local row_y = { 38, 92, 146 }
  local row_h = { 48, 48, 58 }
  for i = 1, 3 do
    local item = APP.items[i]
    local card = {}
    card.panel = lv_obj_create(APP.ui.root)
    lv_obj_set_size(card.panel, 300, row_h[i])
    lv_obj_set_pos(card.panel, 10, row_y[i])
    disable_scroll(card.panel)
    local card_font = item.id == "hidpad" and FONT.small or FONT.label
    local value_font = item.id == "hidpad" and FONT.small or FONT.value
    card.label = create_text(card.panel, item.title, card_font, C.text, 18, 7, 92)
    card.value = create_text(card.panel, "", value_font, item.accent, 178, 7, 104, ALIGN_CENTER)
    if item.kind == "slider" then
      card.slider = lv_slider_create(card.panel)
      lv_obj_set_pos(card.slider, 18, 36)
      lv_obj_set_size(card.slider, 264, 10)
      lv_slider_set_range(card.slider, 0, 100)
      style_slider(card.slider, item.accent)
      disable_scroll(card.slider)
      if EVENT_VALUE_CHANGED and lv_obj_add_event_cb and lv_slider_get_value then
        lv_obj_add_event_cb(card.slider, function(_)
          if APP.state.slider_syncing then
            return
          end
          APP.selected_index = 3
          local ok, message = set_brightness_level(lv_slider_get_value(card.slider))
          refresh_runtime_state()
          set_message(ok and message or (message or "亮度设置失败"))
          refresh_ui()
        end, EVENT_VALUE_CHANGED, "settings-brightness")
      end
    else
      card.sub = create_text(card.panel, "", FONT.small, C.text_dim, 18, 31, 134)
      card.hint = create_text(card.panel, "", FONT.small, C.text_dim, 168, 31, 114, ALIGN_CENTER)
    end
    APP.ui.cards[i] = card
  end

  APP.ui.footer = create_text(APP.ui.root, "上下选择  左右调整  Home 返回", FONT.small, C.text_muted, 10, 215, 300, ALIGN_CENTER)
end

local function build_info_page()
  create_header("设备信息")

  for i = 1, #APP.info_items do
    local y = 40 + (i - 1) * 23
    local row = {}
    row.line = lv_obj_create(APP.ui.root)
    lv_obj_set_size(row.line, 288, 1)
    lv_obj_set_pos(row.line, 16, y + 20)
    style_panel(row.line, C.line, nil, 0, 0)
    disable_scroll(row.line)
    row.name = create_text(APP.ui.root, "", FONT.small, C.text_dim, 16, y + 1, 86)
    row.value = create_text(APP.ui.root, "", FONT.small, C.text, 102, y + 1, 202, ALIGN_CENTER)
    APP.ui.info_rows[i] = row
  end

  APP.ui.footer = create_text(APP.ui.root, "左右切换页面  Home 返回", FONT.small, C.text_muted, 10, 215, 300, ALIGN_CENTER)
end

refresh_ui = function()
  if not APP.ui.root then
    return
  end

  if APP.rendered_page ~= APP.state.page then
    build_ui()
    return
  end

  local badge_selected = APP.selected_index == 4 or APP.state.page == 2
  if APP.ui.badge_box then
    style_panel(
      APP.ui.badge_box,
      badge_selected and C.badge_active or C.badge,
      badge_selected and C.panel_focus or nil,
      13,
      badge_selected and 9 or 0,
      badge_selected and 2 or 0
    )
  end
  if APP.ui.badge_label then
    lv_label_set_text(APP.ui.badge_label, APP.state.page .. " / 2")
    lv_obj_set_style_text_color(APP.ui.badge_label, badge_selected and C.blue or C.text, MAIN_STYLE)
  end

  if APP.state.page == 1 then
    for i = 1, 3 do
      local item = APP.items[i]
      local card = APP.ui.cards[i]
      local selected = APP.selected_index == i
      if card and item then
        style_panel(
          card.panel,
          selected and C.panel_active or C.panel,
          selected and C.panel_focus or C.panel_border,
          13,
          selected and 10 or 0,
          selected and 2 or 1
        )
        lv_label_set_text(card.label, item.title)
        lv_obj_set_style_text_color(card.label, item.available and C.text or C.text_dim, MAIN_STYLE)

        if item.id == "brightness" then
          lv_label_set_text(card.value, item.available and brightness_text(item.value) or "不可用")
          lv_obj_set_style_text_color(card.value, item.available and item.accent or C.text_dim, MAIN_STYLE)
          if card.slider then
            style_slider(card.slider, item.available and item.accent or C.text_dim)
            APP.state.slider_syncing = true
            lv_slider_set_value(card.slider, clamp(item.value, 0, 100), ANIM_OFF)
            APP.state.slider_syncing = false
          end
        else
          local value_text = item.id == "wifi" and text_or(item.value_label, "关闭") or toggle_state_text(item)
          local detail_text = item.id == "wifi" and text_or(APP.state.ip_text, "--") or text_or(item.detail, "--")
          lv_label_set_text(card.value, value_text)
          lv_label_set_text(card.sub, clip_text(detail_text, 22))
          lv_label_set_text(card.hint, item.hint)
          lv_obj_set_style_text_color(card.value, item.available and (item.value and item.accent or C.text_dim) or C.text_dim, MAIN_STYLE)
          lv_obj_set_style_text_color(card.sub, item.available and C.text_dim or C.text_muted, MAIN_STYLE)
          lv_obj_set_style_text_color(card.hint, selected and C.text_dim or C.text_muted, MAIN_STYLE)
        end
      end
    end
  else
    for i = 1, #APP.info_items do
      local row = APP.ui.info_rows[i]
      local info = APP.info_items[i] or { name = "", value = "" }
      if row then
        lv_label_set_text(row.name, info.name)
        lv_label_set_text(row.value, clip_text(info.value, 26))
      end
    end
  end
end

build_ui = function()
  lv_obj_clean(lv_scr_act())
  APP.ui = {
    root = lv_scr_act(),
    cards = {},
    info_rows = {},
  }
  APP.rendered_page = APP.state.page
  disable_scroll(APP.ui.root)

  local bg = lv_obj_create(APP.ui.root)
  lv_obj_set_size(bg, APP.SCREEN_W, APP.SCREEN_H)
  lv_obj_set_pos(bg, 0, 0)
  style_panel(bg, C.bg, nil, 0, 0)
  disable_scroll(bg)

  if APP.state.page == 1 then
    build_settings_page()
  else
    build_info_page()
  end

  refresh_ui()
end

local function now_ms()
  return clock_ms()
end

local function allow_key_event(evt_code, evt_type, ts_ms)
  if evt_type == APP.input.long_repeat_type then
    return true
  end

  local stamp = tonumber(ts_ms) or now_ms()
  local id = tostring(evt_code) .. ":" .. tostring(evt_type)
  local last_stamp = APP.state.key_debounce[id]
  if last_stamp and stamp >= last_stamp and (stamp - last_stamp) < APP.input.debounce_ms then
    return false
  end

  APP.state.key_debounce[id] = stamp
  return true
end

local function is_action_press_event(evt_type)
  if APP.input.start_type ~= nil then
    return evt_type == APP.input.start_type
  end
  return evt_type == APP.input.short_type
end

local function is_home_short_event(evt_type)
  if APP.input.short_type ~= nil then
    return evt_type == APP.input.short_type
  end
  return evt_type == APP.input.start_type
end

local function is_home_long_event(evt_type)
  return evt_type == APP.input.long_start_type or evt_type == APP.input.exit_type
end

local function should_repeat(evt_type, evt_code)
  if is_action_press_event(evt_type) then
    APP.state.repeat_state[evt_code] = { count = 0 }
    return true
  elseif evt_type == APP.input.long_start_type then
    APP.state.repeat_state[evt_code] = { count = 0 }
    return false
  elseif evt_type == APP.input.long_repeat_type then
    local state = APP.state.repeat_state[evt_code] or { count = 0 }
    state.count = state.count + 1
    APP.state.repeat_state[evt_code] = state
    return state.count == 1 or (state.count % 4) == 0
  elseif evt_type == APP.input.long_end_type then
    APP.state.repeat_state[evt_code] = nil
  end
  return false
end

local function request_exit(kind)
  set_message(kind == "long" and "强制退出" or "返回上级")
  refresh_ui()
  if app and app.exit then
    pcall(function()
      app.exit()
    end)
  end
end

local function handle_key(evt_code, evt_type, ts_ms)
  if not allow_key_event(evt_code, evt_type, ts_ms) then
    return
  end

  if evt_code == APP.input.home_code then
    if is_home_short_event(evt_type) then
      request_exit("short")
    elseif is_home_long_event(evt_type) then
      request_exit("long")
    end
    return
  end

  if not should_repeat(evt_type, evt_code) then
    return
  end

  if evt_code == APP.input.up_code then
    move_selection(-1)
  elseif evt_code == APP.input.down_code then
    move_selection(1)
  elseif evt_code == APP.input.left_code then
    apply_selected_value(-1)
  elseif evt_code == APP.input.right_code then
    apply_selected_value(1)
  else
    return
  end

  refresh_info_items()
  refresh_ui()
end

local function bind_input()
  local up_code = (KEYMOD and KEYMOD.UP) or rawget(_G, "KEY_UP")
  local down_code = (KEYMOD and KEYMOD.DOWN) or rawget(_G, "KEY_DOWN")
  local left_code = (KEYMOD and KEYMOD.LEFT) or rawget(_G, "KEY_LEFT")
  local right_code = (KEYMOD and KEYMOD.RIGHT) or rawget(_G, "KEY_RIGHT")
  local home_code = (KEYMOD and KEYMOD.HOME) or rawget(_G, "KEY_HOME")

  APP.input.up_code = up_code
  APP.input.down_code = down_code
  APP.input.left_code = left_code
  APP.input.right_code = right_code
  APP.input.home_code = home_code
  APP.input.short_type = (KEYMOD and KEYMOD.SHORT) or rawget(_G, "KEY_EVENT_SHORT")
  APP.input.start_type = (KEYMOD and KEYMOD.START) or rawget(_G, "KEY_EVENT_START")
  APP.input.long_start_type = (KEYMOD and KEYMOD.LONG_START) or rawget(_G, "KEY_EVENT_LONG_START")
  APP.input.long_repeat_type = (KEYMOD and KEYMOD.LONG_REPEAT) or rawget(_G, "KEY_EVENT_LONG_REPEAT")
  APP.input.long_end_type = (KEYMOD and KEYMOD.LONG_END) or rawget(_G, "KEY_EVENT_LONG_END")
  APP.input.exit_type = (KEYMOD and KEYMOD.EXIT) or rawget(_G, "KEY_EVENT_EXIT")

  if not up_code or not down_code or not left_code or not right_code then
    set_message("按键映射不可用")
    return
  end

  if KEYMOD and KEYMOD.on and KEYMOD.off then
    KEYMOD.on(up_code, function(evt_type, ts_ms)
      handle_key(up_code, evt_type, ts_ms)
    end)
    KEYMOD.on(down_code, function(evt_type, ts_ms)
      handle_key(down_code, evt_type, ts_ms)
    end)
    KEYMOD.on(left_code, function(evt_type, ts_ms)
      handle_key(left_code, evt_type, ts_ms)
    end)
    KEYMOD.on(right_code, function(evt_type, ts_ms)
      handle_key(right_code, evt_type, ts_ms)
    end)
    if home_code then
      KEYMOD.on(home_code, function(evt_type, ts_ms)
        handle_key(home_code, evt_type, ts_ms)
      end)
    end
    APP.state.input_mode = "key"
    return
  end

  if app and app.on then
    app.on("key", function(_, evt_type, evt_code, ts_ms)
      handle_key(evt_code, evt_type, ts_ms)
    end)
    APP.state.input_mode = "app"
  end
end

local function unbind_input()
  if APP.state.input_mode == "key" and KEYMOD and KEYMOD.off then
    pcall(function() KEYMOD.off(APP.input.up_code) end)
    pcall(function() KEYMOD.off(APP.input.down_code) end)
    pcall(function() KEYMOD.off(APP.input.left_code) end)
    pcall(function() KEYMOD.off(APP.input.right_code) end)
    if APP.input.home_code then
      pcall(function() KEYMOD.off(APP.input.home_code) end)
    end
  elseif APP.state.input_mode == "app" and app and app.on then
    pcall(function()
      app.on("key", nil)
    end)
  end
  APP.state.input_mode = "none"
end

local function start_polling()
  local controller_buttons = 0
  add_timer(40, true, function()
    if not controller or not controller.state then return end
    local ok, pad = pcall(function() return controller.state("ble-main") end)
    local buttons = ok and type(pad) == "table" and (tonumber(pad.buttons) or 0) or 0
    local pressed = buttons & (~controller_buttons)
    controller_buttons = buttons
    if (pressed & (4096 | 32768)) ~= 0 then
      request_exit("short")
    elseif (pressed & 4) ~= 0 then
      handle_key(APP.input.left_code, APP.input.start_type, clock_ms())
    elseif (pressed & 8) ~= 0 then
      handle_key(APP.input.right_code, APP.input.start_type, clock_ms())
    end
  end)
  add_timer(1000, true, function()
    if app and app.exiting and app.exiting() then
      return
    end
    refresh_runtime_state()
    refresh_info_items()
    refresh_ui()
  end)
end

function APP.stop(_reason)
  stop_timers()
  unbind_input()
  if ipc and ipc.listen then
    pcall(function()
      ipc.listen(SETTINGS_HIDPAD_ENDPOINT, nil)
    end)
  end
  -- 必须先删掉引用字体的 LVGL 对象，再 lv_font_free。反过来做的话
  -- 样式里还留着已释放的字体指针，渲染任务碰到就是 use-after-free。
  if lv_obj_clean and lv_scr_act then
    pcall(function()
      lv_obj_clean(lv_scr_act())
    end)
  end
  release_fonts()

  if rawget(_G, "SETTINGS_APP") == APP then
    _G.SETTINGS_APP = nil
  end
end

APP.shutdown = APP.stop

local function boot()
  if not lv_scr_act
    or not lv_obj_clean
    or not lv_obj_create
    or not lv_label_create
    or not lv_slider_create
  then
    print("[settings] ui api unavailable")
    return
  end

  init_fonts()
  bind_hidpad_status()
  refresh_runtime_state()
  refresh_info_items()
  set_message(item_summary(current_item()))
  build_ui()
  bind_input()
  start_polling()
end

boot()
