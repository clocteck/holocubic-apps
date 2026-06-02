local prev = rawget(_G, "CLOCK_APP")
if prev and prev.stop then
  pcall(function()
    prev.stop("reload")
  end)
end

CLOCK_APP = {
  VERSION = "2026-04-27-watch-clock-v1",

  SCREEN_W = 320,
  SCREEN_H = 240,
  DIAL_SIZE = 192,
  DIAL_X = 64,
  DIAL_Y = 12,
  DIAL_CENTER_X = 160,
  DIAL_CENTER_Y = 108,
  ASSET_DIR = "/sd/apps/clock/assets",
  TIMEZONE = "CST-8",
  NTP_SERVER = "pool.ntp.org",
  SYNC_RETRY_MS = 30000,
}

local APP = CLOCK_APP
local MAIN_STYLE = rawget(_G, "LV_PART_MAIN") or 0
local FONT_10 = rawget(_G, "LV_FONT_MONTSERRAT_10") or 10
local FONT_20 = rawget(_G, "LV_FONT_MONTSERRAT_20") or 20
local ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1
local LABEL_LONG_CLIP = rawget(_G, "LV_LABEL_LONG_CLIP") or rawget(_G, "LABEL_LONG_CLIP")
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

local math_floor = math.floor
local pcall_fn = pcall
local string_format = string.format

APP.running = true
APP.timers = {}
APP.ui = {}
APP.state = {
  clock_valid = false,
  last_sync_retry_ms = -30000,
}

local function call(fn, ...)
  if fn then
    return pcall_fn(fn, ...)
  end
  return false
end

local function warn(...)
  if print then
    print("[clock.lua]", ...)
  end
end

local function sd_to_lv(path)
  if type(path) == "string" and path:sub(1, 4) == "/sd/" then
    return "S:/" .. path:sub(5)
  end
  return path
end

local function asset_path(name)
  return sd_to_lv(APP.ASSET_DIR .. "/" .. name .. ".png")
end

local function now_ms()
  if millis then
    local ok, v = pcall_fn(millis)
    if ok and type(v) == "number" then
      return v
    end
  end
  return 0
end

local function two(n)
  n = tonumber(n) or 0
  if n < 10 then
    return "0" .. tostring(n)
  end
  return tostring(n)
end

local function reset_obj(id)
  if not id then return end
  call(rawget(_G, "lv_obj_remove_style_all"), id)
  if lv_obj_clear_flag and rawget(_G, "LV_OBJ_FLAG_SCROLLABLE") then
    call(lv_obj_clear_flag, id, rawget(_G, "LV_OBJ_FLAG_SCROLLABLE"))
  end
end

local function set_label_text(id, text)
  if id and lv_label_set_text then
    pcall_fn(function()
      lv_label_set_text(id, tostring(text or ""))
    end)
  end
end

local function style_label(id, font, color, opa)
  if not id then return end
  call(lv_obj_set_style_text_font, id, font, MAIN_STYLE)
  call(lv_obj_set_style_text_color, id, color, MAIN_STYLE)
  call(rawget(_G, "lv_obj_set_style_text_opa"), id, opa or 255, MAIN_STYLE)
  call(rawget(_G, "lv_obj_set_style_text_align"), id, ALIGN_CENTER, MAIN_STYLE)
  call(rawget(_G, "lv_obj_set_style_text_letter_space"), id, 0, MAIN_STYLE)
end

local function create_label(parent, text, font, color, x, y, w)
  local id = lv_label_create(parent)
  reset_obj(id)
  set_label_text(id, text)
  call(lv_obj_set_pos, id, x or 0, y or 0)
  call(lv_obj_set_width, id, w or APP.SCREEN_W)
  if LABEL_LONG_CLIP and lv_label_set_long_mode then
    call(lv_label_set_long_mode, id, LABEL_LONG_CLIP)
  end
  style_label(id, font, color, 255)
  return id
end

local function create_img(parent, src, x, y)
  local id = lv_img_create(parent)
  reset_obj(id)
  call(lv_obj_set_pos, id, x or 0, y or 0)
  call(lv_obj_set_size, id, APP.DIAL_SIZE, APP.DIAL_SIZE)
  if lv_img_set_antialias then
    call(lv_img_set_antialias, id, true)
  end
  if lv_img_set_src then
    pcall_fn(function()
      lv_img_set_src(id, src)
    end)
  end
  return id
end

local function create_hand(parent, src, pivot_x, pivot_y, zoom)
  pivot_x = math_floor(tonumber(pivot_x) or APP.DIAL_SIZE / 2)
  pivot_y = math_floor(tonumber(pivot_y) or APP.DIAL_SIZE / 2)

  local id = create_img(parent, src, APP.DIAL_CENTER_X - pivot_x, APP.DIAL_CENTER_Y - pivot_y)
  if lv_img_set_pivot then
    call(lv_img_set_pivot, id, pivot_x, pivot_y)
  end
  if zoom and lv_img_set_zoom then
    call(lv_img_set_zoom, id, zoom)
  end
  return id
end

local function request_time_sync(force)
  if not time then
    return
  end

  local now = now_ms()
  if not force and now - (APP.state.last_sync_retry_ms or 0) < APP.SYNC_RETRY_MS then
    return
  end
  APP.state.last_sync_retry_ms = now

  if time.settimezone then
    call(time.settimezone, APP.TIMEZONE)
  end
  if time.initntp then
    call(time.initntp, APP.NTP_SERVER)
  end
end

local function tm_from_time()
  if not time or not time.getlocal then
    return nil
  end

  local ok, t = pcall_fn(function()
    return time.getlocal()
  end)
  if ok and type(t) == "table" and t.year and t.year >= 2024 then
    return t
  end
  return nil
end

local function tm_from_os()
  if not os or not os.date then
    return nil
  end

  local ok, t = pcall_fn(os.date, "*t")
  if ok and type(t) == "table" and t.year and t.year >= 2024 then
    return t
  end
  return nil
end

local function get_time_parts()
  local t = tm_from_time() or tm_from_os()
  if t then
    APP.state.clock_valid = true
    return {
      hour = t.hour or 0,
      min = t.min or 0,
      sec = t.sec or 0,
      mon = t.mon,
      day = t.day,
      wday = t.wday,
    }
  end

  APP.state.clock_valid = false
  request_time_sync(false)
  return { hour = 10, min = 10, sec = 30 }
end

local function angle_parts(t)
  local sec = t.sec or 0
  local min = (t.min or 0) + sec / 60
  local hour = ((t.hour or 0) % 12) + min / 60

  return {
    second = math_floor(sec * 60 + 0.5),
    minute = math_floor(min * 60 + 0.5),
    hour = math_floor(hour * 300 + 0.5),
  }
end

local function weekday_name(wday)
  local names = { "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" }
  return names[tonumber(wday or 0)] or "--"
end

local function render()
  if not APP.running then
    return
  end

  local t = get_time_parts()
  local a = angle_parts(t)

  if lv_img_set_angle then
    call(lv_img_set_angle, APP.ui.hour_hand, a.hour)
    call(lv_img_set_angle, APP.ui.minute_hand, a.minute)
    call(lv_img_set_angle, APP.ui.second_hand, a.second)
  end

  if APP.state.clock_valid then
    set_label_text(APP.ui.time_label, two(t.hour) .. ":" .. two(t.min))
    if t.mon and t.day then
      set_label_text(APP.ui.date_label, weekday_name(t.wday) .. " " .. two(t.mon) .. "/" .. two(t.day))
    else
      set_label_text(APP.ui.date_label, "LIVE")
    end
  else
    set_label_text(APP.ui.time_label, "--:--")
    set_label_text(APP.ui.date_label, "SYNC")
  end
end

local function init_time()
  request_time_sync(true)
end

local function init_ui()
  local root = lv_scr_act()
  clear_root()
  APP.ui.root = root

  call(lv_obj_set_style_bg_color, root, 0x000000, MAIN_STYLE)
  call(lv_obj_set_style_bg_opa, root, 255, MAIN_STYLE)
  if lv_obj_clear_flag and rawget(_G, "LV_OBJ_FLAG_SCROLLABLE") then
    call(lv_obj_clear_flag, root, rawget(_G, "LV_OBJ_FLAG_SCROLLABLE"))
  end

  APP.ui.bg = lv_img_create(root)
  reset_obj(APP.ui.bg)
  call(lv_obj_set_pos, APP.ui.bg, 0, 0)
  call(lv_obj_set_size, APP.ui.bg, APP.SCREEN_W, APP.SCREEN_H)
  if lv_img_set_src then
    call(lv_img_set_src, APP.ui.bg, asset_path("bg"))
  end

  APP.ui.dial = create_img(root, asset_path("dial"), APP.DIAL_X, APP.DIAL_Y)
  -- 指针素材的可见轴心不一定等于图片中心；旋转轴必须对齐到表盘圆心。
  APP.ui.hour_hand = create_hand(root, asset_path("hour"), 96, 129, 160)
  APP.ui.minute_hand = create_hand(root, asset_path("minute"), 96, 131, 168)
  APP.ui.second_hand = create_hand(root, asset_path("second"), 96, 96, 236)

  APP.ui.time_label = create_label(root, "--:--", FONT_20, 0xF7F7F5, 0, 205, APP.SCREEN_W)
  APP.ui.date_label = create_label(root, "SYNC", FONT_10, 0xA8A8A8, 0, 228, APP.SCREEN_W)
end

local runtime_app = rawget(_G, "app")
local app_exiting_fn = runtime_app and runtime_app.exiting or nil

local function maybe_stop_for_exit()
  if app_exiting_fn then
    local ok, exiting = pcall_fn(app_exiting_fn)
    if ok and exiting then
      APP.stop("exit")
      return true
    end
  end
  return false
end

local function start_timers()
  if not tmr or not tmr.create then
    return
  end

  APP.timers.clock = tmr.create()
  APP.timers.clock:alarm(1000, tmr.ALARM_AUTO, function()
    if not APP.running or maybe_stop_for_exit() then return end
    render()
  end)
end

local function stop_timers()
  for _, timer in pairs(APP.timers) do
    pcall_fn(function() timer:stop() end)
    pcall_fn(function() timer:unregister() end)
  end
  APP.timers = {}
end

function APP.stop(reason)
  if not APP.running then
    return
  end

  APP.running = false
  stop_timers()
  warn("stop", tostring(reason or ""))

  if rawget(_G, "CLOCK_APP") == APP then
    _G.CLOCK_APP = nil
  end

  if lv_scr_act then
    clear_root()
  end
end

APP.shutdown = APP.stop

if not lv_scr_act or not lv_obj_clean or not lv_img_create or not lv_label_create then
  warn("ui api missing")
  return
end

init_time()
init_ui()
render()
start_timers()
