local prev = rawget(_G, "NIXIE_CLOCK_APP")
if prev and prev.stop then
  pcall(function()
    prev.stop("reload")
  end)
end

NIXIE_CLOCK_APP = {
  VERSION = "2026-04-27-nixie-clock-v1",

  SCREEN_W = 320,
  SCREEN_H = 240,
  ASSET_DIR = "/sd/apps/NixieClock/assets",
  TIMEZONE = "CST-8",
  TZ_OFFSET_SEC = 8 * 3600,
  NTP_SERVER = "pool.ntp.org",
  SYNC_RETRY_MS = 30000,

  DIGIT_W = 52,
  DIGIT_H = 116,
  COLON_W = 52,
  TUBE_GAP = 15,
  TUBE_X0 = 0,
  TUBE_Y = 72,
}

local APP = NIXIE_CLOCK_APP
local MAIN_STYLE = rawget(_G, "LV_PART_MAIN") or 0
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
local table_concat = table.concat

APP.running = true
APP.timers = {}
APP.ui = { digits = {} }
APP.state = {
  clock_valid = false,
  last_sync_retry_ms = -30000,
  last_key = "",
}

local function call(fn, ...)
  if fn then
    return pcall_fn(fn, ...)
  end
  return false
end

local function warn(...)
  if print then
    print("[NixieClock]", ...)
  end
end

local function sd_to_lv(path)
  if type(path) == "string" and path:sub(1, 4) == "/sd/" then
    return "S:/" .. path:sub(5)
  end
  return path
end

local function asset(name)
  return sd_to_lv(APP.ASSET_DIR .. "/" .. name .. ".png")
end

local DIGIT_SRC = {
  asset("digit_0"),
  asset("digit_1"),
  asset("digit_2"),
  asset("digit_3"),
  asset("digit_4"),
  asset("digit_5"),
  asset("digit_6"),
  asset("digit_7"),
  asset("digit_8"),
  asset("digit_9"),
}

local SRC_TUBE_OFF = asset("tube_off")
local SRC_SEPARATOR = asset("colon_on")

local function now_ms()
  if millis then
    local ok, v = pcall_fn(millis)
    if ok and type(v) == "number" then
      return v
    end
  end
  return 0
end

local function two(v)
  v = tonumber(v) or 0
  if v < 0 then v = 0 end
  return string_format("%02d", math_floor(v) % 100)
end

local function reset_obj(id)
  if not id then return end
  call(rawget(_G, "lv_obj_remove_style_all"), id)
  if lv_obj_clear_flag and rawget(_G, "LV_OBJ_FLAG_SCROLLABLE") then
    call(lv_obj_clear_flag, id, rawget(_G, "LV_OBJ_FLAG_SCROLLABLE"))
  end
end

local function create_img(parent, src, x, y, w, h)
  local id = lv_img_create(parent)
  reset_obj(id)
  call(lv_obj_set_pos, id, x or 0, y or 0)
  if w and h then
    call(lv_obj_set_size, id, w, h)
  end
  if lv_img_set_antialias then
    call(lv_img_set_antialias, id, true)
  end
  if lv_img_set_src then
    call(lv_img_set_src, id, src)
  end
  return id
end

local function set_img_src(id, src)
  if id and src and lv_img_set_src then
    call(lv_img_set_src, id, src)
  end
end

local function request_time_sync(force)
  local time_mod = rawget(_G, "time")
  if not time_mod then
    return
  end

  local now = now_ms()
  if not force and now - (APP.state.last_sync_retry_ms or 0) < APP.SYNC_RETRY_MS then
    return
  end
  APP.state.last_sync_retry_ms = now

  if time_mod.settimezone then
    call(time_mod.settimezone, APP.TIMEZONE)
  end
  if time_mod.initntp then
    call(time_mod.initntp, APP.NTP_SERVER)
  end
end

local function tm_from_time_module()
  local time_mod = rawget(_G, "time")
  if not time_mod or not time_mod.getlocal then
    return nil
  end

  local ok, t = pcall_fn(time_mod.getlocal)
  if ok and type(t) == "table" and t.year and t.year >= 2024 then
    return t
  end
  return nil
end

local function tm_from_rtctime()
  local rtctime_mod = rawget(_G, "rtctime")
  if not rtctime_mod or not rtctime_mod.get or not rtctime_mod.epoch2cal then
    return nil
  end

  local ok_get, sec = pcall_fn(rtctime_mod.get)
  if not ok_get or type(sec) ~= "number" or sec <= 0 then
    return nil
  end

  local ok_cal, year, mon, day, hour, min, sec2 = pcall_fn(rtctime_mod.epoch2cal, sec + APP.TZ_OFFSET_SEC)
  if ok_cal and type(year) == "number" and year >= 2024 and type(hour) == "number" then
    return {
      year = year,
      mon = mon,
      day = day,
      hour = hour,
      min = min or 0,
      sec = sec2 or 0,
    }
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
  local t = tm_from_time_module() or tm_from_rtctime() or tm_from_os()
  if t then
    APP.state.clock_valid = true
    return {
      hour = t.hour or 0,
      min = t.min or 0,
      sec = t.sec or 0,
    }
  end

  APP.state.clock_valid = false
  request_time_sync(false)
  return nil
end

local function digits_for_time(t)
  if not t then
    return nil
  end
  local hh = two(t.hour)
  local mm = two(t.min)
  return {
    tonumber(hh:sub(1, 1)) or 0,
    tonumber(hh:sub(2, 2)) or 0,
    tonumber(mm:sub(1, 1)) or 0,
    tonumber(mm:sub(2, 2)) or 0,
  }
end

local function render()
  if not APP.running then
    return
  end

  local t = get_time_parts()
  local digits = digits_for_time(t)

  if digits then
    local key_parts = {}
    for i = 1, 4 do
      key_parts[i] = tostring(digits[i])
    end
    local key = table_concat(key_parts, "")

    if key ~= APP.state.last_key then
      for i = 1, 4 do
        set_img_src(APP.ui.digits[i], DIGIT_SRC[digits[i] + 1])
      end
      APP.state.last_key = key
    end

  else
    if APP.state.last_key ~= "off" then
      for i = 1, 4 do
        set_img_src(APP.ui.digits[i], SRC_TUBE_OFF)
      end
      APP.state.last_key = "off"
    end
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

  local x0 = APP.TUBE_X0
  local y = APP.TUBE_Y
  local d_w = APP.DIGIT_W
  local d_h = APP.DIGIT_H
  local gap = APP.TUBE_GAP

  APP.ui.digits[1] = create_img(root, SRC_TUBE_OFF, x0, y, d_w, d_h)
  APP.ui.digits[2] = create_img(root, SRC_TUBE_OFF, x0 + d_w + gap, y, d_w, d_h)
  APP.ui.colon = create_img(root, SRC_SEPARATOR, x0 + (d_w + gap) * 2, y, APP.COLON_W, d_h)
  APP.ui.digits[3] = create_img(root, SRC_TUBE_OFF, x0 + (d_w + gap) * 2 + APP.COLON_W + gap, y, d_w, d_h)
  APP.ui.digits[4] = create_img(root, SRC_TUBE_OFF, x0 + (d_w + gap) * 3 + APP.COLON_W + gap, y, d_w, d_h)
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

  if rawget(_G, "NIXIE_CLOCK_APP") == APP then
    _G.NIXIE_CLOCK_APP = nil
  end

  if lv_scr_act then
    clear_root()
  end
end

APP.shutdown = APP.stop

if not lv_scr_act or not lv_obj_clean or not lv_img_create then
  warn("ui api missing")
  return
end

init_time()
init_ui()
render()
start_timers()
