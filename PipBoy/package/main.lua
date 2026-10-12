local previous = rawget(_G, "PIP_BOY_APP")
if previous and previous.stop then pcall(previous.stop, "reload") end
local DIR = "/sd/apps/PipBoy"
local Data = dofile(DIR .. "/data.lua")
local APP = { running = true, fonts = {}, timers = {}, labels = {}, values = {} }
_G.PIP_BOY_APP = APP
local PART = rawget(_G, "LV_PART_MAIN") or 0
local ALIGN_LEFT = rawget(_G, "LV_TEXT_ALIGN_LEFT") or 1
local ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 2
local ALIGN_RIGHT = rawget(_G, "LV_TEXT_ALIGN_RIGHT") or 3
local GREEN, BRIGHT, MUTED, DARK = 0x82F65C, 0xACFF84, 0x8EB87B, 0x030B04
local HIDDEN = rawget(_G, "LV_OBJ_FLAG_HIDDEN") or 1
APP.data = Data.new()

local function font(name, fallback)
  if lv_font_load then
    local ok, handle = pcall(lv_font_load, DIR .. "/font/" .. name .. ".bin")
    if ok and type(handle) == "number" and handle > 0 then
      APP.fonts[#APP.fonts + 1] = handle
      return handle
    end
  end
  return fallback
end
local function plain(obj)
  lv_obj_set_style_pad_all(obj, 0, PART)
  lv_obj_set_style_border_width(obj, 0, PART)
  lv_obj_set_style_radius(obj, 0, PART)
  if lv_obj_set_style_shadow_width then lv_obj_set_style_shadow_width(obj, 0, PART) end
  if lv_obj_clear_flag and LV_OBJ_FLAG_SCROLLABLE then lv_obj_clear_flag(obj, LV_OBJ_FLAG_SCROLLABLE) end
end
local function rectangle(x, y, w, h, color)
  local obj = lv_obj_create(APP.root)
  plain(obj)
  lv_obj_set_pos(obj, x, y)
  lv_obj_set_size(obj, w, h)
  lv_obj_set_style_bg_color(obj, color, PART)
  lv_obj_set_style_bg_opa(obj, 255, PART)
  return obj
end
local function label(id, value, x, y, w, h, face, color, align)
  local obj = lv_label_create(APP.root)
  plain(obj)
  lv_obj_set_style_bg_opa(obj, 0, PART)
  lv_obj_set_style_text_font(obj, face, PART)
  lv_obj_set_style_text_color(obj, color or GREEN, PART)
  lv_obj_set_style_text_align(obj, align or ALIGN_LEFT, PART)
  if lv_label_set_long_mode and LV_LABEL_LONG_CLIP then lv_label_set_long_mode(obj, LV_LABEL_LONG_CLIP) end
  lv_obj_set_size(obj, w, h)
  lv_obj_set_pos(obj, x, y)
  lv_label_set_text(obj, value)
  APP.labels[id], APP.values[id] = obj, value
  return obj
end
local function set(id, value)
  if APP.values[id] ~= value then
    lv_label_set_text(APP.labels[id], value)
    APP.values[id] = value
  end
end
local function refresh()
  local t, s = APP.data:local_time(), APP.data.state
  set("hour", t and string.format("%02d", t.hour) or "--")
  set("minute", t and string.format("%02d", t.min) or "--")
  set("second", t and string.format(":%02d", t.sec) or ":--")
  set("date", t and string.format("%02d.%02d / %04d", t.mon, t.day, t.year) or "SYNC TIME")
  set("weekday", Data.weekday(t))
  set("temperature", APP.data:temperature_text())
  local status = s.weather_status
  local condition = s.valid and s.weather_text or (status == "no-location" and "设置地点" or "--")
  set("condition", condition)
  set("humidity", s.humidity and ("RH " .. s.humidity .. "%") or "RH --%")
  set("weather", s.valid and "WX OK" or "WX --")
  local brightness = APP.data:brightness()
  set("brightness", brightness and ("BRI " .. brightness .. "%") or "BRI --%")
  local code = s.valid and s.icon or nil
  if code and code ~= APP.icon_code then
    lv_img_set_src(APP.weather_icon, "S:/apps/PipBoy/assets/weather-line/" .. Data.weather_asset(code) .. ".png")
    APP.icon_code = code
  end
  if code then
    lv_obj_clear_flag(APP.weather_icon, HIDDEN)
    lv_obj_add_flag(APP.labels.weather_unknown, HIDDEN)
  else
    lv_obj_add_flag(APP.weather_icon, HIDDEN)
    lv_obj_clear_flag(APP.labels.weather_unknown, HIDDEN)
  end
end

function APP.stop(reason)
  if not APP.running then return end
  APP.running = false
  APP.data:stop()
  for _, timer in ipairs(APP.timers) do
    pcall(function() timer:stop() end)
    pcall(function() timer:unregister() end)
  end
  APP.timers = {}
  -- Delete only our subtree, before releasing fonts referenced by its labels.
  if APP.root then pcall(lv_obj_del, APP.root); APP.root = nil end
  if lv_font_free then for _, handle in ipairs(APP.fonts) do pcall(lv_font_free, handle) end end
  APP.fonts = {}
  if rawget(_G, "PIP_BOY_APP") == APP then _G.PIP_BOY_APP = nil end
  if print then print("[PipBoy] stop", reason or "") end
end
APP.shutdown = APP.stop

local function start()
  APP.data:init()
  local ui = font("time_en_12", 12)
  local seconds = font("time_en_14", ui)
  local cn = font("time_ui_12", ui)
  local digits = font("time_mono_56", 28)
  -- The numeric-only font omits C/F; the mono font includes digits, degree and both units.
  local temp = font("time_mono_24", 24)
  APP.root = lv_obj_create(lv_scr_act())
  plain(APP.root)
  lv_obj_set_pos(APP.root, 0, 0)
  lv_obj_set_size(APP.root, 320, 240)
  lv_obj_set_style_bg_color(APP.root, DARK, PART)
  lv_obj_set_style_bg_opa(APP.root, 255, PART)
  local bg = lv_img_create(APP.root)
  lv_img_set_src(bg, "S:/apps/PipBoy/assets/background.png")
  lv_obj_set_pos(bg, 0, 0)
  label("brand", "PIP BOY", 13, 11, 140, 18, ui)
  rectangle(13, 34, 294, 1, 0x558F3B)
  APP.weather_icon = lv_img_create(APP.root)
  lv_obj_set_pos(APP.weather_icon, 278, 4)
  lv_obj_add_flag(APP.weather_icon, HIDDEN)
  label("weather_unknown", "--", 278, 11, 28, 18, ui, MUTED, ALIGN_CENTER)
  rectangle(13, 48, 41, 23, GREEN)
  label("weekday", "---", 16, 52, 35, 17, ui, DARK, ALIGN_CENTER)
  label("date", "SYNC TIME", 62, 52, 127, 18, ui, BRIGHT)
  label("hour", "--", 10, 79, 72, 65, digits, BRIGHT)
  label("colon", ":", 77, 79, 25, 65, digits)
  label("minute", "--", 102, 79, 72, 65, digits, BRIGHT)
  label("second", ":--", 153, 143, 39, 20, seconds, MUTED)
  label("temperature", "--°C", 13, 173, 100, 31, temp, BRIGHT)
  label("condition", "--", 113, 181, 80, 17, cn)
  rectangle(13, 207, 174, 1, 0x558F3B)
  label("humidity", "RH --%", 13, 219, 83, 18, ui)
  label("weather", "WX --", 119, 219, 62, 18, ui)
  label("brightness", "BRI --%", 223, 219, 84, 18, ui, GREEN, ALIGN_RIGHT)
  refresh()
  -- Elapsed milliseconds are monotonic across tmr.now() wrap and wall-clock/NTP changes.
  local elapsed, last_raw = 0, nil
  local timer = tmr.create()
  APP.timers[#APP.timers + 1] = timer
  timer:alarm(1000, tmr.ALARM_AUTO, function()
    if not APP.running then return end
    local ok, err = pcall(function()
      if app and app.exiting and app.exiting() then APP.stop("exit"); return end
      local raw = tmr.now and tmr.now() / 1000 or nil
      local delta = raw and last_raw and raw - last_raw or 1000
      elapsed = elapsed + (delta >= 0 and delta or 1000)
      last_raw = raw
      APP.data:tick(elapsed)
      refresh()
    end)
    if not ok then
      if print then print("[PipBoy] tick failed", err) end
      APP.stop("tick-error")
    end
  end)
end
local ok, err = pcall(start)
if not ok then APP.stop("start-error"); error(err) end
