local prev = rawget(_G, "SETTINGS_APP")
if prev and prev.stop then
  pcall(function()
    prev.stop()
  end)
elseif prev and prev.shutdown then
  pcall(function()
    prev.shutdown()
  end)
end

SETTINGS_APP = {
  VERSION = "2026-04-27-settings-v1",
  SCREEN_W = 320,
  SCREEN_H = 240,
  timers = {},
  event_handles = {},
  selected_index = 1,
  state = {
    message = "",
    last_wifi_mode = nil,
    wifi_mode = nil,
    ip_text = "Wi-Fi disabled",
    ip_mode = "OFF",
    slider_syncing = false,
  },
  input = {
    mode = "none",
    up_code = nil,
    down_code = nil,
    left_code = nil,
    right_code = nil,
    trigger_type = nil,
  },
  ui = {
    rows = {},
  },
  items = {
    {
      id = "wifi",
      kind = "toggle",
      title = "Wi-Fi",
      value = false,
      available = true,
      accent = 0x2B9AF1,
      detail = "Disabled",
    },
    {
      id = "gamepad",
      kind = "toggle",
      title = "Bluetooth",
      value = false,
      available = true,
      accent = 0x4DBD8B,
      detail = "Disabled",
    },
    {
      id = "brightness",
      kind = "slider",
      title = "Brightness",
      value = 80,
      available = true,
      accent = 0xF3B24C,
      step = 5,
      detail = "80%",
    },
  },
}

local APP = SETTINGS_APP
local MAIN_PART = rawget(_G, "LV_PART_MAIN") or 0
local DEFAULT_STATE = rawget(_G, "LV_STATE_DEFAULT") or 0
local MAIN_STYLE = MAIN_PART | DEFAULT_STATE
local PART_INDICATOR = rawget(_G, "LV_PART_INDICATOR") or MAIN_PART
local function clear_root()
  if not lv_scr_act or not lv_obj_clean then
    return
  end
  local ok, root = pcall(function()
    return lv_scr_act()
  end)
  if not ok or not root then
    return
  end
  pcall(function()
    lv_obj_clean(root)
  end)
end
local PART_KNOB = rawget(_G, "LV_PART_KNOB") or MAIN_PART
local STATE_CHECKED = rawget(_G, "LV_STATE_CHECKED") or 1
local LABEL_LONG_CLIP = rawget(_G, "LV_LABEL_LONG_CLIP") or rawget(_G, "LABEL_LONG_CLIP")
local FLAG_SCROLLABLE = rawget(_G, "LV_OBJ_FLAG_SCROLLABLE") or rawget(_G, "OBJ_FLAG_SCROLLABLE")
local ANIM_OFF = rawget(_G, "LV_ANIM_OFF") or 0
local EVENT_VALUE_CHANGED = rawget(_G, "LV_EVENT_VALUE_CHANGED")
local EVENT_CLICKED = rawget(_G, "LV_EVENT_CLICKED")
local ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1

local FONT = {
  title = rawget(_G, "LV_FONT_MONTSERRAT_20") or 20,
  row = rawget(_G, "LV_FONT_MONTSERRAT_14") or 14,
  value = rawget(_G, "LV_FONT_MONTSERRAT_12") or 12,
  small = rawget(_G, "LV_FONT_MONTSERRAT_10") or 10,
}

local C = {
  bg = 0x111315,
  panel = 0x202326,
  panel_active = 0x272C31,
  panel_border = 0x343A40,
  panel_focus = 0x2B9AF1,
  title = 0xF7F8FA,
  text = 0xD7DEE6,
  text_dim = 0x89939E,
  badge = 0x252A30,
  badge_text = 0xF4F7FA,
  switch_off = 0x5F666E,
  switch_knob = 0xF6F8FA,
  slider_bg = 0x3B4148,
  slider_knob = 0xFFFFFF,
  status = 0xA6AFB8,
}

local function disable_scroll(obj)
  if obj and lv_obj_clear_flag and FLAG_SCROLLABLE then
    pcall(function()
      lv_obj_clear_flag(obj, FLAG_SCROLLABLE)
    end)
  end
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

local function safe_call(tag, fn)
  local ok, a, b = pcall(fn)
  if not ok then
    print("[settings]", tag, tostring(a))
    return nil, tostring(a)
  end
  return a, b
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

local function add_timer(ms, auto, fn)
  if not tmr or not tmr.create then
    return nil
  end

  local timer = tmr.create()
  APP.timers[#APP.timers + 1] = timer
  timer:alarm(ms, auto and tmr.ALARM_AUTO or tmr.ALARM_SINGLE, fn)
  return timer
end

local function track_event(handle)
  if handle then
    APP.event_handles[#APP.event_handles + 1] = handle
  end
end

local function stop_timers()
  for i = 1, #APP.timers do
    local timer = APP.timers[i]
    pcall(function()
      timer:stop()
    end)
    pcall(function()
      timer:unregister()
    end)
  end
  APP.timers = {}
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
      lv_obj_set_style_shadow_opa(obj, 34, MAIN_STYLE)
      if lv_obj_set_style_shadow_ofs_y then
        lv_obj_set_style_shadow_ofs_y(obj, 1, MAIN_STYLE)
      end
    end
  end
end

local function create_text(parent, text, font_ref, color, x, y, width, align)
  local id = lv_label_create(parent)
  lv_label_set_text(id, text_or(text, ""))
  lv_obj_set_style_text_font(id, font_ref, MAIN_STYLE)
  lv_obj_set_style_text_color(id, color, MAIN_STYLE)
  lv_obj_set_style_text_opa(id, 255, MAIN_STYLE)
  if width then
    lv_obj_set_width(id, width)
  end
  if LABEL_LONG_CLIP and lv_label_set_long_mode then
    lv_label_set_long_mode(id, LABEL_LONG_CLIP)
  end
  if align and lv_obj_set_style_text_align then
    lv_obj_set_style_text_align(id, align, MAIN_STYLE)
  end
  lv_obj_set_pos(id, x, y)
  return id
end

local function style_switch(obj, accent)
  if not obj then
    return
  end

  lv_obj_set_size(obj, 46, 24)
  lv_obj_set_style_bg_color(obj, C.switch_off, MAIN_STYLE)
  lv_obj_set_style_bg_opa(obj, 255, MAIN_STYLE)
  lv_obj_set_style_border_width(obj, 0, MAIN_STYLE)
  lv_obj_set_style_radius(obj, 14, MAIN_STYLE)
  lv_obj_set_style_bg_color(obj, accent or C.panel_focus, PART_INDICATOR)
  lv_obj_set_style_bg_opa(obj, 255, PART_INDICATOR)
  lv_obj_set_style_border_width(obj, 0, PART_INDICATOR)
  lv_obj_set_style_radius(obj, 14, PART_INDICATOR)
  lv_obj_set_style_bg_color(obj, C.switch_knob, PART_KNOB)
  lv_obj_set_style_bg_opa(obj, 255, PART_KNOB)
  lv_obj_set_style_border_width(obj, 0, PART_KNOB)
  lv_obj_set_style_radius(obj, 14, PART_KNOB)
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
  lv_obj_set_style_bg_color(obj, C.slider_knob, PART_KNOB)
  lv_obj_set_style_bg_opa(obj, 255, PART_KNOB)
  lv_obj_set_style_border_width(obj, 0, PART_KNOB)
  lv_obj_set_style_radius(obj, 10, PART_KNOB)
end

local function set_switch_checked(obj, enabled)
  if not obj then
    return
  end
  if enabled then
    lv_obj_add_state(obj, STATE_CHECKED)
  else
    lv_obj_clear_state(obj, STATE_CHECKED)
  end
end

local function set_message(text)
  APP.state.message = clip_text(text, 54)
end

local function current_item()
  return APP.items[APP.selected_index]
end

local function wifi_mode_name(mode)
  if wifi then
    if mode == wifi.NULLMODE then
      return "OFF"
    end
    if mode == wifi.STATION then
      return "STA"
    end
    if mode == wifi.SOFTAP then
      return "AP"
    end
    if mode == wifi.STATIONAP then
      return "STA+AP"
    end
  end
  return tostring(mode or "?")
end

local function toggle_state_text(item)
  if not item or not item.available then
    return "ERR"
  end
  return item.value and "ON" or "OFF"
end

local function brightness_text(value)
  return tostring(clamp(value or 0, 0, 100)) .. "%"
end

local function item_summary(item)
  if not item then
    return "Settings"
  end
  if item.kind == "slider" then
    return item.title .. " " .. brightness_text(item.value)
  end
  return item.title .. " " .. toggle_state_text(item)
end

local function refresh_wifi_item()
  local item = APP.items[1]
  APP.state.wifi_mode = nil

  if not wifi or not wifi.getmode then
    item.available = false
    item.value = false
    item.detail = "Unavailable"
    return
  end

  local mode, err = safe_call("wifi.getmode", function()
    return wifi.getmode()
  end)
  if mode == nil then
    item.available = false
    item.value = false
    item.detail = clip_text(err or "Read failed", 18)
    return
  end

  APP.state.wifi_mode = mode
  item.available = true
  item.value = mode ~= wifi.NULLMODE
  if item.value then
    APP.state.last_wifi_mode = mode
    item.detail = wifi_mode_name(mode)
  else
    item.detail = "Disabled"
  end
end

local function refresh_gamepad_item()
  local item = APP.items[2]
  if not gamepad or not gamepad.state then
    item.available = false
    item.value = false
    item.detail = "Unavailable"
    return
  end

  local state, err = safe_call("gamepad.state", function()
    return gamepad.state()
  end)
  if type(state) ~= "table" then
    item.available = false
    item.value = false
    item.detail = clip_text(err or "Read failed", 18)
    return
  end

  item.available = true
  item.value = state.started and true or false
  if not item.value then
    item.detail = "Disabled"
  elseif state.connected then
    item.detail = "Linked"
  elseif state.connecting then
    item.detail = "Pairing"
  else
    item.detail = "Ready"
  end
end

local function refresh_brightness_item()
  local item = APP.items[3]

  if not sys or not sys.getbrightness then
    item.available = false
    item.detail = "Unavailable"
    return
  end

  local level, err = safe_call("sys.getbrightness", function()
    return sys.getbrightness()
  end)
  if level == nil then
    item.available = false
    item.detail = clip_text(err or "Read failed", 18)
    return
  end

  item.available = true
  item.value = clamp(level, 0, 100)
  item.detail = brightness_text(item.value)
end

local function refresh_ip_state()
  local mode = APP.state.wifi_mode
  APP.state.ip_text = "Wi-Fi disabled"
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
    return
  end

  if ap_ip and ap_ip ~= "" then
    APP.state.ip_text = ap_ip
    APP.state.ip_mode = "AP"
    return
  end

  APP.state.ip_text = "No IP assigned"
  APP.state.ip_mode = wifi_mode_name(mode)
end

local function refresh_runtime_state()
  refresh_wifi_item()
  refresh_gamepad_item()
  refresh_brightness_item()
  refresh_ip_state()
end

local function set_wifi_enabled(enable)
  if not wifi or not wifi.getmode or not wifi.mode then
    return nil, "Wi-Fi unavailable"
  end

  if enable then
    local target_mode = APP.state.last_wifi_mode or wifi.STATION
    if target_mode == wifi.NULLMODE then
      target_mode = wifi.STATION
    end

    local ok_mode, err_mode = try_call("wifi.mode.on", function()
      return wifi.mode(target_mode, false)
    end)
    if ok_mode == nil then
      return nil, err_mode or "Enable failed"
    end

    if wifi.start then
      local ok_start, err_start = try_call("wifi.start", function()
        return wifi.start()
      end)
      if ok_start == nil then
        return nil, err_start or "Start failed"
      end
    end

    if wifi.sta and wifi.sta.connect and (target_mode == wifi.STATION or target_mode == wifi.STATIONAP) then
      pcall(function()
        wifi.sta.connect()
      end)
    end

    return true, "Wi-Fi " .. wifi_mode_name(target_mode)
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
    return nil, err_mode or "Disable failed"
  end

  return true, "Wi-Fi off"
end

local function set_gamepad_enabled(enable)
  if not gamepad or not gamepad.start or not gamepad.stop then
    return nil, "Bluetooth unavailable"
  end

  if enable then
    if gamepad.off then
      pcall(function()
        gamepad.off()
      end)
    end

    local ok_call, ok_start, err = pcall(function()
      return gamepad.start({
        clear_bonds = false,
        debug = false,
      })
    end)
    if not ok_call or not ok_start then
      return nil, tostring(err or ok_start or "Start failed")
    end

    return true, "Bluetooth on"
  end

  if gamepad.off then
    pcall(function()
      gamepad.off()
    end)
  end

  local ok_call, err = pcall(function()
    return gamepad.stop()
  end)
  if not ok_call then
    return nil, tostring(err or "Stop failed")
  end

  return true, "Bluetooth off"
end

local function set_brightness_level(level)
  local item = APP.items[3]
  local target = clamp(level, 0, 100)

  if not sys or not sys.setbrightness then
    item.available = false
    return nil, "Brightness unavailable"
  end

  local ok_call, ok_set, err = pcall(function()
    return sys.setbrightness(target)
  end)
  if not ok_call or not ok_set then
    return nil, tostring(err or ok_set or "Set brightness failed")
  end

  item.available = true
  item.value = target
  item.detail = brightness_text(target)
  return true, "Brightness " .. item.detail
end

local function apply_selected_value(enable)
  local item = current_item()
  if not item then
    return
  end

  if not item.available and item.kind ~= "toggle" then
    set_message(item.title .. " unavailable")
    return
  end

  local ok, message
  if item.id == "wifi" then
    ok, message = set_wifi_enabled(enable)
  elseif item.id == "gamepad" then
    ok, message = set_gamepad_enabled(enable)
  elseif item.id == "brightness" then
    local delta = enable and item.step or -item.step
    ok, message = set_brightness_level(item.value + delta)
  else
    ok, message = nil, "Unsupported"
  end

  refresh_runtime_state()
  if ok then
    set_message(message)
  else
    set_message(message or "Operation failed")
  end
end

local function move_selection(delta)
  local next_index = APP.selected_index + (delta or 0)
  if next_index < 1 then
    next_index = 1
  elseif next_index > #APP.items then
    next_index = #APP.items
  end
  APP.selected_index = next_index

  local item = current_item()
  if item then
    set_message(item_summary(item))
  end
end

local function selected_badge_text()
  local item = current_item()
  if not item then
    return "SET"
  end
  if item.kind == "slider" then
    return brightness_text(item.value)
  end
  return toggle_state_text(item)
end

local function refresh_ui()
  if not APP.ui.root then
    return
  end

  if APP.ui.badge_label then
    lv_label_set_text(APP.ui.badge_label, selected_badge_text())
  end
  if APP.ui.status then
    lv_label_set_text(APP.ui.status, APP.state.message or "")
  end

  for i = 1, 2 do
    local item = APP.items[i]
    local row = APP.ui.rows[i]
    local selected = i == APP.selected_index

    if row and item then
      style_panel(
        row.panel,
        selected and C.panel_active or C.panel,
        selected and C.panel_focus or C.panel_border,
        12,
        selected and 9 or 0,
        selected and 2 or 1
      )

      lv_label_set_text(row.title, item.title)
      lv_label_set_text(row.detail_label, clip_text(item.detail, i == 1 and 10 or 14))
      lv_label_set_text(row.state_label, toggle_state_text(item))
      lv_obj_set_style_text_color(row.title, item.available and C.title or C.text_dim, MAIN_STYLE)
      lv_obj_set_style_text_color(
        row.detail_label,
        item.available and (item.value and item.accent or C.text_dim) or C.text_dim,
        MAIN_STYLE
      )
      lv_obj_set_style_text_color(
        row.state_label,
        item.available and (item.value and item.accent or C.text_dim) or C.text_dim,
        MAIN_STYLE
      )
      set_switch_checked(row.switch, item.value)
    end
  end

  if APP.ui.ip_value then
    lv_label_set_text(APP.ui.ip_value, clip_text(APP.state.ip_text, 16))
    lv_obj_set_style_text_color(APP.ui.ip_value, APP.items[1].value and C.title or C.text_dim, MAIN_STYLE)
  end

  if APP.ui.brightness_panel then
    local selected = APP.selected_index == 3
    style_panel(
      APP.ui.brightness_panel,
      selected and C.panel_active or C.panel,
      selected and C.panel_focus or C.panel_border,
      12,
      selected and 9 or 0,
      selected and 2 or 1
    )
  end
  if APP.ui.brightness_title then
    lv_obj_set_style_text_color(APP.ui.brightness_title, APP.items[3].available and C.text or C.text_dim, MAIN_STYLE)
  end
  if APP.ui.brightness_value then
    lv_label_set_text(APP.ui.brightness_value, APP.items[3].available and brightness_text(APP.items[3].value) or "ERR")
    lv_obj_set_style_text_color(
      APP.ui.brightness_value,
      APP.items[3].available and APP.items[3].accent or C.text_dim,
      MAIN_STYLE
    )
  end
  if APP.ui.brightness_slider then
    style_slider(APP.ui.brightness_slider, APP.items[3].available and APP.items[3].accent or C.text_dim)
    APP.state.slider_syncing = true
    lv_slider_set_value(APP.ui.brightness_slider, clamp(APP.items[3].value, 0, 100), ANIM_OFF)
    APP.state.slider_syncing = false
  end
end

local function build_ui()
  clear_root()
  APP.ui = {
    rows = {},
  }
  APP.ui.root = lv_scr_act()
  disable_scroll(APP.ui.root)

  local bg = lv_obj_create(APP.ui.root)
  lv_obj_set_size(bg, APP.SCREEN_W, APP.SCREEN_H)
  lv_obj_set_pos(bg, 0, 0)
  style_panel(bg, C.bg, nil, 0, 0)
  disable_scroll(bg)

  APP.ui.title = create_text(APP.ui.root, "Settings", FONT.title, C.title, 14, 9, 132)

  APP.ui.badge_box = lv_obj_create(APP.ui.root)
  lv_obj_set_size(APP.ui.badge_box, 62, 22)
  lv_obj_set_pos(APP.ui.badge_box, 244, 9)
  style_panel(APP.ui.badge_box, C.badge, nil, 11, 0)
  disable_scroll(APP.ui.badge_box)
  APP.ui.badge_label = create_text(APP.ui.badge_box, "SET", FONT.small, C.badge_text, 8, 5, 46, ALIGN_CENTER)

  local row_y = { 38, 98 }
  local row_h = { 54, 36 }
  for i = 1, 2 do
    local item = APP.items[i]
    local y = row_y[i]
    local row = {}

    row.panel = lv_obj_create(APP.ui.root)
    lv_obj_set_size(row.panel, 300, row_h[i])
    lv_obj_set_pos(row.panel, 10, y)
    style_panel(row.panel, C.panel, C.panel_border, 12, 0)
    disable_scroll(row.panel)

    row.title = create_text(row.panel, item.title, FONT.row, C.title, 14, 5, 86)
    if i == 1 then
      row.detail_label = create_text(row.panel, item.detail, FONT.small, C.text_dim, 92, 8, 88)
    else
      row.detail_label = create_text(row.panel, item.detail, FONT.small, C.text_dim, 14, 20, 114)
    end
    row.state_label = create_text(row.panel, "OFF", FONT.small, C.text_dim, 195, 11, 34, ALIGN_CENTER)
    row.switch = lv_switch_create(row.panel)
    lv_obj_set_pos(row.switch, 242, 5)
    style_switch(row.switch, item.accent)
    disable_scroll(row.switch)

    APP.ui.rows[i] = row
  end

  APP.ui.ip_title = create_text(APP.ui.rows[1].panel, "IP", FONT.small, C.text_dim, 14, 31, 16)
  APP.ui.ip_value = create_text(APP.ui.rows[1].panel, "No IP assigned", FONT.small, C.title, 34, 31, 248)

  APP.ui.brightness_panel = lv_obj_create(APP.ui.root)
  lv_obj_set_size(APP.ui.brightness_panel, 300, 44)
  lv_obj_set_pos(APP.ui.brightness_panel, 10, 144)
  style_panel(APP.ui.brightness_panel, C.panel, C.panel_border, 12, 0)
  disable_scroll(APP.ui.brightness_panel)
  APP.ui.brightness_title = create_text(APP.ui.brightness_panel, "Brightness", FONT.small, C.text_dim, 14, 5, 90)
  APP.ui.brightness_value = create_text(APP.ui.brightness_panel, "0%", FONT.value, APP.items[3].accent, 246, 4, 36, ALIGN_CENTER)
  APP.ui.brightness_slider = lv_slider_create(APP.ui.brightness_panel)
  lv_obj_set_pos(APP.ui.brightness_slider, 14, 23)
  lv_obj_set_size(APP.ui.brightness_slider, 272, 8)
  lv_slider_set_range(APP.ui.brightness_slider, 0, 100)
  style_slider(APP.ui.brightness_slider, APP.items[3].accent)
  disable_scroll(APP.ui.brightness_slider)

  APP.ui.status = create_text(APP.ui.root, "", FONT.small, C.status, 14, 198, 292)
end

local function bind_touch()
  if not lv_obj_add_event_cb then
    return
  end

  if EVENT_CLICKED then
    for i = 1, 2 do
      local row = APP.ui.rows[i]
      if row and row.switch then
        local index = i
        track_event(lv_obj_add_event_cb(row.switch, function(_)
          APP.selected_index = index
          refresh_runtime_state()
          apply_selected_value(not APP.items[index].value)
          refresh_ui()
        end, EVENT_CLICKED, "settings-toggle"))
      end
    end
  end

  if EVENT_VALUE_CHANGED and APP.ui.brightness_slider and lv_slider_get_value then
    track_event(lv_obj_add_event_cb(APP.ui.brightness_slider, function(_)
      if APP.state.slider_syncing then
        return
      end
      APP.selected_index = 3
      local ok, message = set_brightness_level(lv_slider_get_value(APP.ui.brightness_slider))
      refresh_runtime_state()
      set_message(ok and message or (message or "Brightness failed"))
      refresh_ui()
    end, EVENT_VALUE_CHANGED, "settings-brightness"))
  end
end

local function bind_input()
  local up_code = key.UP
  local down_code = key.DOWN
  local left_code = key.LEFT
  local right_code = key.RIGHT
  local trigger_type = key.START

  APP.input.up_code = up_code
  APP.input.down_code = down_code
  APP.input.left_code = left_code
  APP.input.right_code = right_code
  APP.input.trigger_type = trigger_type
  APP.input.mode = "none"

  if not up_code or not down_code or not left_code or not right_code or not trigger_type then
    set_message("Key mapping unavailable")
    return
  end

  local function handle_key(evt_code)
    if evt_code == up_code then
      move_selection(-1)
    elseif evt_code == down_code then
      move_selection(1)
    elseif evt_code == left_code then
      apply_selected_value(false)
    elseif evt_code == right_code then
      apply_selected_value(true)
    else
      return
    end
    refresh_ui()
  end

  key.on(up_code, function(evt_type, _)
    if evt_type == trigger_type then
      handle_key(up_code)
    end
  end)
  key.on(down_code, function(evt_type, _)
    if evt_type == trigger_type then
      handle_key(down_code)
    end
  end)
  key.on(left_code, function(evt_type, _)
    if evt_type == trigger_type then
      handle_key(left_code)
    end
  end)
  key.on(right_code, function(evt_type, _)
    if evt_type == trigger_type then
      handle_key(right_code)
    end
  end)
  APP.input.mode = "key"
end

local function unbind_input()
  if APP.input.mode == "key" then
    pcall(function()
      key.off(APP.input.up_code)
    end)
    pcall(function()
      key.off(APP.input.down_code)
    end)
    pcall(function()
      key.off(APP.input.left_code)
    end)
    pcall(function()
      key.off(APP.input.right_code)
    end)
  end
  APP.input.mode = "none"
end

local function unbind_touch()
  if lv_obj_remove_event_dsc then
    for _, handle in ipairs(APP.event_handles or {}) do
      pcall(function()
        lv_obj_remove_event_dsc(handle)
      end)
    end
  end
  APP.event_handles = {}
end

local function start_polling()
  add_timer(1000, true, function()
    if app and app.exiting and app.exiting() then
      return
    end
    refresh_runtime_state()
    refresh_ui()
  end)
end

function APP.stop()
  stop_timers()
  unbind_input()
  unbind_touch()

  if lv_scr_act then
    clear_root()
  end
end

APP.shutdown = APP.stop

local function boot()
if not lv_scr_act
    or not lv_obj_clean
    or not lv_obj_create
    or not lv_label_create
    or not lv_switch_create
    or not lv_slider_create
  then
    print("[settings] ui api unavailable")
    return
  end

  build_ui()
  refresh_runtime_state()
  set_message(item_summary(current_item()))
  refresh_ui()
  bind_touch()
  bind_input()
  start_polling()
end

boot()
