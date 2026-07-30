local APP_DIR = "/sd/apps/holo_pc_monitor"

if file and file.exists and not file.exists(APP_DIR .. "/config.lua") then
  local candidates = {
    "/sd/apps/monitor",
    "holo_pc_monitor/package",
    "holo_pc_monitor",
  }

  for _, dir in ipairs(candidates) do
    if file.exists(dir .. "/config.lua") then
      APP_DIR = dir
      break
    end
  end
end

if _G.__aida_monitor and _G.__aida_monitor.stop then
  pcall(_G.__aida_monitor.stop)
end

local config = dofile(APP_DIR .. "/config.lua")
config.metrics = config.metrics or {}
local function ensure_metric(def)
  for _, item in ipairs(config.metrics) do
    if item.id == def.id then
      for key, value in pairs(def) do
        item[key] = value
      end
      return
    end
  end
  config.metrics[#config.metrics + 1] = def
end
ensure_metric({
  id = "cpu_voltage", title = "CPU Voltage", unit = "V", kind = "voltage",
  aliases = { "CPU Voltage", "CPU Core Voltage", "Vcore", "CPU Vcore", "CPU VID" }, min_valid = 0.01
})
ensure_metric({
  id = "cpu_power", title = "CPU Power", unit = "W", kind = "power",
  aliases = { "CPU Package Power", "CPU Power", "CPU PPT" }, min_valid = 0.01
})
ensure_metric({ id = "cpu_name", title = "CPU Name", kind = "text", aliases = { "CPU Name" } })
ensure_metric({ id = "gpu_name", title = "GPU Name", kind = "text", aliases = { "GPU Name" } })
ensure_metric({ id = "memory_used", title = "Used Memory", unit = "MB", kind = "memory", aliases = { "Used Memory" }, min_valid = 0 })
ensure_metric({ id = "memory_free", title = "Free Memory", unit = "MB", kind = "memory", aliases = { "Free Memory" }, min_valid = 0 })
ensure_metric({ id = "network_upload", title = "Network Upload", unit = "KB/s", kind = "network", aliases = { "Network Upload 1", "Network Upload 2", "Network Upload 3", "Network Upload 4", "Network Upload 5", "Network Upload 6", "Network Upload 7", "Network Upload 8" }, min_valid = 0.01 })
ensure_metric({ id = "network_download", title = "Network Download", unit = "KB/s", kind = "network", aliases = { "Network Download 1", "Network Download 2", "Network Download 3", "Network Download 4", "Network Download 5", "Network Download 6", "Network Download 7", "Network Download 8" }, min_valid = 0.01 })
local AidaClient = dofile(APP_DIR .. "/aida_client.lua")
local AidaWeb = nil

if file and file.exists and file.exists(APP_DIR .. "/web.lua") then
  local ok, mod = pcall(dofile, APP_DIR .. "/web.lua")
  if ok then
    AidaWeb = mod
  else
    print("[monitor-ui] web_load_error", mod)
  end
end

local MAIN_STYLE = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
local ALIGN_LEFT = rawget(_G, "LV_TEXT_ALIGN_LEFT") or 0
local ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1
local ALIGN_RIGHT = rawget(_G, "LV_TEXT_ALIGN_RIGHT") or 2
local CANVAS_FMT = rawget(_G, "LV_IMG_CF_TRUE_COLOR") or rawget(_G, "CANVAS_FMT_TRUE_COLOR")

local C = {
  bg = 0x000000,
  line = 0x1A2028,
  dim = 0x66717D,
  sub = 0x9BA8B7,
  text = 0xF4F7FB,
  cpu = 0x46C7FF,
  gpu = 0x62E493,
  mem = 0xF2B84B,
  warn = 0xFF7B4A,
  hot = 0xFF5D5D,
  accent = tonumber(config.accent_color) or 0xE7C21D,
}

local S = {
  status = "CONNECTING",
  status_color = C.warn,
  last_sample = nil,
  last_seen_ms = 0,
  spin = 0,
  cpu_usage = nil,
  cpu_temp = nil,
  cpu_clock = nil,
  cpu_voltage = nil,
  cpu_power = nil,
  cpu_name = nil,
  gpu_usage = nil,
  gpu_temp = nil,
  gpu_clock = nil,
  gpu_name = nil,
  mem_usage = nil,
  mem_used = nil,
  mem_free = nil,
  net_upload = nil,
  net_download = nil,
  fan = nil,
  cpu_history = {},
  gpu_history = {},
  cpu_temp_history = {},
  gpu_temp_history = {},
  weather_city = "--",
  weather_temp = nil,
  weather_text = "--",
  weather_code = "999",
  weather_inflight = false,
}

local UI = {
  canvas = nil,
  w = 320,
  h = 240,
}

local WEATHER_FONT = nil

local state = {
  client = nil,
  tick_timer = nil,
  weather_timer = nil,
  stopped = false,
}

local math_floor = math.floor
local string_format = string.format

local function log(...)
  if config.serial_log == false then
    return
  end

  print("[monitor-ui]", ...)
end

local function call(fn, ...)
  if not fn then
    return false
  end
  return pcall(fn, ...)
end

local function now_ms()
  if type(millis) == "function" then
    local ok, value = pcall(millis)
    if ok and type(value) == "number" then
      return value
    end
  end

  if tmr and type(tmr.now) == "function" then
    local ok, value = pcall(function()
      return tmr.now()
    end)
    if ok and type(value) == "number" then
      return math_floor(value / 1000)
    end
  end

  return 0
end

local function clamp(value, min_value, max_value)
  value = tonumber(value)
  if not value then
    return nil
  end
  if value < min_value then
    return min_value
  end
  if value > max_value then
    return max_value
  end
  return value
end

local function clamp_pct(value)
  return clamp(value, 0, 100)
end

local function metric(sample, id)
  if sample and sample.metrics then
    return sample.metrics[id]
  end
  return nil
end

local function metric_value(sample, id)
  local item = metric(sample, id)
  return item and item.value or nil
end

local function text_or(value, fallback)
  if value == nil then
    return fallback or ""
  end
  local text = tostring(value)
  if text == "" then
    return fallback or ""
  end
  return text
end

local function fmt_pct(value)
  value = tonumber(value)
  if not value then
    return "--%"
  end
  return string_format("%d%%", math_floor(value + 0.5))
end

local function fmt_temp(value)
  value = tonumber(value)
  if not value then
    return "-- C"
  end
  return string_format("%d C", math_floor(value + 0.5))
end

local function fmt_clock(value)
  value = tonumber(value)
  if not value then
    return "-- MHz"
  end
  return string_format("%d MHz", math_floor(value + 0.5))
end

local function metric_color(temp, base)
  temp = tonumber(temp)
  if not temp then
    return base
  end
  if temp >= (config.thresholds.hot_temp or 85) then
    return C.hot
  end
  if temp >= (config.thresholds.warm_temp or 70) then
    return C.warn
  end
  return base
end

local function begin_frame(cvs)
  if lv_canvas_frame_begin then
    local ok = pcall(lv_canvas_frame_begin, cvs)
    return ok
  end
  if lv_canvas_begin then
    local ok = pcall(lv_canvas_begin, cvs)
    return ok
  end
  return false
end

local function end_frame(cvs, explicit)
  if explicit and lv_canvas_frame_end then
    pcall(lv_canvas_frame_end, cvs)
  elseif explicit and lv_canvas_end then
    pcall(lv_canvas_end, cvs)
  end
end

local function draw_rect(cvs, x, y, w, h, color, opa, radius)
  if not lv_canvas_draw_rect then
    return
  end

  local ok = pcall(lv_canvas_draw_rect, cvs, x, y, w, h, {
    bg_color = color,
    bg_opa = opa or 255,
    radius = radius or 0,
    border_width = 0,
  })
  if not ok then
    pcall(lv_canvas_draw_rect, cvs, x, y, w, h, color, opa or 255)
  end
end

local function draw_text(cvs, x, y, w, text, color, size, align, opa, font_handle)
  if not lv_canvas_draw_text then
    return
  end

  local ok = pcall(lv_canvas_draw_text, cvs, x, y, w, text_or(text, ""), {
    color = color or C.text,
    opa = opa or 255,
    align = align or ALIGN_LEFT,
    font_size = size or 12,
    font_handle = font_handle,
  })
  if not ok then
    pcall(lv_canvas_draw_text, cvs, x, y, w, text_or(text, ""), color or C.text, opa or 255, align or ALIGN_LEFT, size or 12)
  end
end

local function draw_arc_raw(cvs, cx, cy, r, start_deg, end_deg, color, opa, width)
  if not lv_canvas_draw_arc then
    return
  end

  local ok = pcall(lv_canvas_draw_arc, cvs, cx, cy, r, start_deg, end_deg, {
    color = color,
    opa = opa or 255,
    width = width or 4,
  })
  if not ok then
    pcall(lv_canvas_draw_arc, cvs, cx, cy, r, start_deg, end_deg, color, opa or 255, width or 4)
  end
end

local function norm_deg(deg)
  local n = deg % 360
  if n < 0 then
    n = n + 360
  end
  return n
end

local function draw_arc_span(cvs, cx, cy, r, start_deg, span_deg, color, opa, width)
  span_deg = tonumber(span_deg) or 0
  if span_deg <= 0 then
    return
  end
  if span_deg >= 359 then
    draw_arc_raw(cvs, cx, cy, r, 0, 359, color, opa, width)
    return
  end

  local a1 = norm_deg(start_deg)
  local a2 = a1 + span_deg
  if a2 <= 360 then
    draw_arc_raw(cvs, cx, cy, r, math_floor(a1), math_floor(a2), color, opa, width)
  else
    draw_arc_raw(cvs, cx, cy, r, math_floor(a1), 359, color, opa, width)
    draw_arc_raw(cvs, cx, cy, r, 0, math_floor(a2 - 360), color, opa, width)
  end
end

local function draw_metric_wheel(cvs, cx, cy, name, pct, temp, color)
  local value = clamp_pct(pct) or 0
  local active = metric_color(temp, color)
  local span = value * 3.58

  draw_arc_span(cvs, cx, cy, 48, 0, 359, C.line, 210, 8)
  draw_arc_span(cvs, cx, cy, 48, -90, span, active, 255, 8)

  draw_text(cvs, cx - 32, cy - 35, 64, name, C.sub, 11, ALIGN_CENTER, 255)
  draw_text(cvs, cx - 39, cy - 14, 78, fmt_pct(pct), C.text, 24, ALIGN_CENTER, 255)
  draw_text(cvs, cx - 30, cy + 18, 60, fmt_temp(temp), active, 12, ALIGN_CENTER, 255)
end

local function draw_status_core(cvs, cx, cy)
  local live = S.status == "LIVE"
  local color = live and C.gpu or S.status_color

  draw_arc_span(cvs, cx, cy, 13, 0, 359, C.line, 150, 2)
  if live then
    draw_arc_span(cvs, cx, cy, 13, S.spin - 90, 74, color, 245, 2)
  else
    draw_arc_span(cvs, cx, cy, 13, -90, 52, color, 210, 2)
  end
end

local function draw_bar(cvs, x, y, w, h, pct, color)
  local value = clamp_pct(pct) or 0
  local fill_w = math_floor(w * value / 100 + 0.5)
  draw_rect(cvs, x, y, w, h, C.line, 230, 2)
  if fill_w > 0 then
    draw_rect(cvs, x, y, fill_w, h, color, 255, 2)
  end
end

local function draw_memory(cvs)
  local x = 18
  local y = 177
  local w = 284

  draw_text(cvs, x, y, 55, "RAM", C.sub, 12, ALIGN_LEFT, 255)
  draw_text(cvs, x + 48, y - 2, 72, fmt_pct(S.mem_usage), C.text, 18, ALIGN_LEFT, 255)
  draw_text(cvs, x + 150, y, 134, "MEMORY", C.dim, 10, ALIGN_RIGHT, 255)
  draw_bar(cvs, x, y + 23, w, 9, S.mem_usage, C.mem)
end

local function draw_clocks(cvs)
  draw_text(cvs, 24, 145, 104, fmt_clock(S.cpu_clock), S.cpu_clock and C.cpu or C.dim, 12, ALIGN_CENTER, 255)
  draw_text(cvs, 192, 145, 104, fmt_clock(S.gpu_clock), S.gpu_clock and C.gpu or C.dim, 12, ALIGN_CENTER, 255)
end

local function read_text_file(path)
  if not file then return nil end
  if file.getcontents then
    local ok, raw = pcall(file.getcontents, path)
    if ok and type(raw) == "string" then return raw end
  end
  if not file.open then return nil end
  local fd = file.open(path, "r")
  if not fd then return nil end
  local chunks = {}
  while true do
    local part = fd:read(512)
    if not part or part == "" then break end
    chunks[#chunks + 1] = part
  end
  fd:close()
  return table.concat(chunks)
end

local function decode_json(raw)
  local codec = rawget(_G, "sjson") or rawget(_G, "json")
  if not codec or not codec.decode or type(raw) ~= "string" then return nil end
  local ok, value = pcall(codec.decode, raw)
  return ok and value or nil
end

local function push_history(history, value)
  history[#history + 1] = clamp_pct(value) or 0
  local limit = tonumber(config.history_points) or 48
  while #history > limit do table.remove(history, 1) end
end

local function draw_line(cvs, x1, y1, x2, y2, color, opa, width)
  if not lv_canvas_draw_line then return end
  x1, y1, x2, y2 = math_floor(x1 + 0.5), math_floor(y1 + 0.5), math_floor(x2 + 0.5), math_floor(y2 + 0.5)
  local ok = pcall(lv_canvas_draw_line, cvs, x1, y1, x2, y2, color, opa or 255, width or 1)
  if not ok then
    pcall(lv_canvas_draw_line, cvs, { { x = x1, y = y1 }, { x = x2, y = y2 } }, {
      color = color, opa = opa or 255, width = width or 1,
    })
  end
end

local function draw_panel(cvs, x, y, w, h, radius)
  draw_rect(cvs, x, y, w, h, 0x343A3E, 255, radius or 6)
  draw_rect(cvs, x + 1, y + 1, w - 2, h - 2, 0x000000, 255, math.max(0, (radius or 6) - 1))
end

local function draw_chip_icon(cvs, x, y, color)
  draw_rect(cvs, x + 3, y + 3, 8, 8, color, 255, 1)
  draw_rect(cvs, x + 5, y + 5, 4, 4, 0x000000, 255, 0)
  for _, p in ipairs({5, 9}) do
    draw_line(cvs, x, y + p, x + 3, y + p, color, 255, 1)
    draw_line(cvs, x + 11, y + p, x + 14, y + p, color, 255, 1)
    draw_line(cvs, x + p, y, x + p, y + 3, color, 255, 1)
    draw_line(cvs, x + p, y + 11, x + p, y + 14, color, 255, 1)
  end
end

local function draw_gpu_icon(cvs, x, y, color)
  draw_line(cvs, x + 1, y + 4, x + 13, y + 4, color, 255, 1)
  draw_line(cvs, x + 13, y + 4, x + 13, y + 14, color, 255, 1)
  draw_line(cvs, x + 13, y + 14, x + 1, y + 14, color, 255, 1)
  draw_line(cvs, x + 1, y + 14, x + 1, y + 4, color, 255, 1)
  draw_arc_span(cvs, x + 7, y + 9, 3, 0, 359, color, 255, 1)
  draw_line(cvs, x + 7, y + 6, x + 7, y + 12, color, 255, 1)
  draw_line(cvs, x + 4, y + 9, x + 10, y + 9, color, 255, 1)
  for _, py in ipairs({6, 9, 12}) do
    draw_line(cvs, x - 2, y + py, x + 1, y + py, color, 255, 1)
    draw_line(cvs, x + 13, y + py, x + 16, y + py, color, 255, 1)
  end
end

local function draw_fan_icon(cvs, x, y, color)
  draw_arc_span(cvs, x + 8, y + 8, 7, 0, 359, color, 255, 2)
  draw_arc_span(cvs, x + 8, y + 8, 2, 0, 359, color, 255, 2)
  for _, blade in ipairs({
    {8, 6, 6, 2, 10, 2},
    {10, 8, 14, 6, 14, 10},
    {8, 10, 10, 14, 6, 14},
    {6, 8, 2, 10, 2, 6},
  }) do
    draw_line(cvs, x + blade[1], y + blade[2], x + blade[3], y + blade[4], color, 255, 1)
    draw_line(cvs, x + blade[3], y + blade[4], x + blade[5], y + blade[6], color, 255, 1)
    draw_line(cvs, x + blade[5], y + blade[6], x + blade[1], y + blade[2], color, 255, 1)
  end
end

local function draw_legend_item(cvs, x, color, label)
  draw_rect(cvs, x, 218, 6, 6, color, 255, 1)
  draw_text(cvs, x + 9, 216, 27, label, C.sub, 10, ALIGN_LEFT, 255)
end

local function draw_dashboard_card(cvs, x, title, value, color, caption, suffix)
  draw_panel(cvs, x, 31, 75, 93, 6)
  draw_text(cvs, x, 35, 75, title, C.text, 11, ALIGN_CENTER, 255)
  draw_arc_span(cvs, x + 37, 87, 32, 0, 359, C.line, 255, 2)
  draw_arc_span(cvs, x + 37, 87, 32, -90, (clamp_pct(value) or 0) * 3.58, color, 255, 3)
  local display = value and tostring(math_floor(value + 0.5)) .. (suffix or "") or "--"
  draw_text(cvs, x + 8, 78, 58, display, C.text, 18, ALIGN_CENTER, 255)
end

local function draw_history(cvs, history, x, y, w, h, color)
  if #history < 2 then return end
  local step = w / math.max(#history - 1, 1)
  for i = 2, #history do
    draw_line(cvs,
      math_floor(x + (i - 2) * step), math_floor(y + h - h * history[i - 1] / 100),
      math_floor(x + (i - 1) * step), math_floor(y + h - h * history[i] / 100), color, 255, 1)
  end
end

local function dashboard_clock()
  if time and time.getlocal then
    local ok, cal = pcall(time.getlocal)
    if ok and type(cal) == "table" then
      local year = tonumber(cal.year or cal.tm_year) or 2026
      local mon = tonumber(cal.mon or cal.month) or 1
      local day = tonumber(cal.day or cal.mday) or 1
      local hour = tonumber(cal.hour or cal.tm_hour) or 0
      local min = tonumber(cal.min or cal.minute) or 0
      local wday = tonumber(cal.wday)
      local months = { "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" }
      local weekdays = { "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" }
      if not wday or wday < 1 or wday > 7 then
        local offsets = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
        local y = mon < 3 and year - 1 or year
        wday = (y + math_floor(y / 4) - math_floor(y / 100) + math_floor(y / 400) + offsets[mon] + day) % 7 + 1
      end
      return string_format("%02d:%02d", hour, min), string_format("%s %02d %s", months[mon] or "---", day, weekdays[wday] or "---")
    end
  end
  if rtctime and rtctime.get and rtctime.epoch2cal then
    local ok_sec, sec = pcall(rtctime.get)
    if ok_sec and type(sec) == "number" and sec > 0 then
      local ok, year, mon, day, hour, min = pcall(rtctime.epoch2cal, sec + 8 * 3600)
      if ok and year and hour and min then
        return string_format("%02d:%02d", hour, min), string_format("%s %02d", ({ "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" })[mon] or "---", day)
      end
    end
  end
  if os and os.date then
    local ok_time, clock = pcall(os.date, "%H:%M")
    local ok_date, date = pcall(os.date, "%Y-%m-%d")
    if ok_time and ok_date then return clock, date end
  end
  return "--:--", "---- -- --"
end

local function weather_text_width(text)
  local width, i = 0, 1
  text = tostring(text or "")
  while i <= #text do
    local byte = text:byte(i)
    if byte >= 0xE0 then width, i = width + 12, i + 3
    elseif byte >= 0xC0 then width, i = width + 10, i + 2
    else
      local ch = text:sub(i, i)
      width = width + ((ch == " ") and 3 or ((ch == "/") and 5 or 6))
      i = i + 1
    end
  end
  return width
end

local function redraw_dashboard(cvs)
  local clock, date = dashboard_clock()
  local weather = S.weather_city .. "//" .. S.weather_text .. "//" .. (S.weather_temp and tostring(math_floor(S.weather_temp + 0.5)) .. "°C" or "--°C")
  local function weather_icon(x, y, code)
    code = tostring(code or "999")
    local is_rain = code:match("^3") ~= nil
    local is_snow = code:match("^4") ~= nil
    local is_storm = code == "302" or code == "303" or code == "304"
    local is_sunny = code == "100" or code == "150"
    local is_partly = code == "101" or code == "102" or code == "103" or code == "151" or code == "152" or code == "153"
    local is_fog = code:match("^5") ~= nil
    if is_sunny then
      draw_arc_span(cvs, x + 7, y + 7, 4, 0, 359, 0xFFB22E, 255, 1)
      for a = 0, 315, 45 do
        local r = a * math.pi / 180
        draw_line(cvs, x + 7 + math.cos(r) * 6, y + 7 + math.sin(r) * 6,
          x + 7 + math.cos(r) * 8, y + 7 + math.sin(r) * 8, 0xFFB22E, 255, 1)
      end
      return
    end
    if is_fog then
      draw_arc_span(cvs, x + 7, y + 5, 4, 190, 160, 0xD7E7F5, 255, 1)
      draw_line(cvs, x + 2, y + 9, x + 14, y + 9, 0xD7E7F5, 255, 1)
      draw_line(cvs, x, y + 12, x + 11, y + 12, 0x91A9BC, 255, 1)
      draw_line(cvs, x + 4, y + 15, x + 16, y + 15, 0x91A9BC, 255, 1)
      return
    end
    if is_partly then
      draw_arc_span(cvs, x + 5, y + 5, 3, 0, 359, 0xFFB22E, 255, 1)
      draw_line(cvs, x + 5, y, x + 5, y + 2, 0xFFB22E, 255, 1)
      draw_line(cvs, x, y + 5, x + 2, y + 5, 0xFFB22E, 255, 1)
    end
    draw_arc_span(cvs, x + 5, y + 7, 4, 190, 170, 0xD7E7F5, 255, 1)
    draw_arc_span(cvs, x + 10, y + 7, 5, 180, 180, 0xD7E7F5, 255, 1)
    draw_line(cvs, x + 2, y + 10, x + 15, y + 10, 0xD7E7F5, 255, 1)
    if is_storm then
      draw_line(cvs, x + 9, y + 11, x + 6, y + 15, 0xFFD43B, 255, 1)
      draw_line(cvs, x + 6, y + 15, x + 10, y + 14, 0xFFD43B, 255, 1)
    elseif is_rain then
      draw_line(cvs, x + 5, y + 12, x + 4, y + 15, 0x46C7FF, 255, 1)
      draw_line(cvs, x + 10, y + 12, x + 9, y + 15, 0x46C7FF, 255, 1)
    elseif is_snow then
      draw_line(cvs, x + 5, y + 12, x + 5, y + 16, C.text, 255, 1)
      draw_line(cvs, x + 3, y + 14, x + 7, y + 14, C.text, 255, 1)
      draw_line(cvs, x + 11, y + 12, x + 11, y + 16, C.text, 255, 1)
      draw_line(cvs, x + 9, y + 14, x + 13, y + 14, C.text, 255, 1)
    end
  end
  draw_text(cvs, 9, 6, 52, clock, C.text, 13, ALIGN_LEFT, 255)
  local label_width = weather_text_width(weather)
  local group_width = 16 + 4 + label_width
  local group_x = math_floor(160 - group_width / 2)
  weather_icon(group_x, 7, S.weather_code)
  draw_text(cvs, group_x + 20, 5, 220, weather, 0xFF9A26, 12, ALIGN_LEFT, 255, WEATHER_FONT)
  draw_text(cvs, 231, 7, 85, date, C.sub, 10, ALIGN_RIGHT, 255)
  draw_text(cvs, 230, 7, 85, date, C.sub, 10, ALIGN_RIGHT, 255)
  draw_dashboard_card(cvs, 4, "CPU", S.cpu_usage, 0x25CEF4, "Usage", "%")
  draw_dashboard_card(cvs, 83, "GPU", S.gpu_usage, 0xA857F4, "Usage", "%")
  draw_dashboard_card(cvs, 162, "RAM", S.mem_usage, 0x8DF018, "Usage", "%")
  draw_dashboard_card(cvs, 241, "TEMP", S.cpu_temp, 0xFF8707, "Temperature", " C")

  draw_panel(cvs, 4, 132, 184, 100, 6)
  draw_text(cvs, 11, 138, 156, "PERFORMANCE", C.text, 10, ALIGN_LEFT, 255)
  for _, gy in ipairs({157, 184, 211}) do draw_line(cvs, 25, gy, 181, gy, 0x2B3135, 210, 1) end
  draw_text(cvs, 6, 151, 16, "100", C.dim, 8, ALIGN_RIGHT, 255)
  draw_text(cvs, 6, 178, 16, "50", C.dim, 8, ALIGN_RIGHT, 255)
  draw_text(cvs, 6, 205, 16, "0", C.dim, 8, ALIGN_RIGHT, 255)
  draw_history(cvs, S.cpu_history, 25, 157, 156, 54, 0x21C9ED)
  draw_history(cvs, S.gpu_history, 25, 157, 156, 54, 0xA752EE)
  draw_history(cvs, S.cpu_temp_history, 25, 157, 156, 54, 0xFFD166)
  draw_history(cvs, S.gpu_temp_history, 25, 157, 156, 54, 0xFF4D6D)
  draw_legend_item(cvs, 35, 0x21C9ED, "CPU")
  draw_legend_item(cvs, 73, 0xA752EE, "GPU")
  draw_legend_item(cvs, 118, 0xFFD166, "CT")
  draw_legend_item(cvs, 149, 0xFF4D6D, "GT")

  local function ghz(value)
    return value and string_format("%.1f GHz", value / 1000) or "-- GHz"
  end
  draw_panel(cvs, 193, 132, 123, 100, 6)
  draw_chip_icon(cvs, 200, 141, C.cpu)
  draw_text(cvs, 219, 140, 32, "CPU", C.cpu, 14, ALIGN_LEFT, 255)
  draw_text(cvs, 247, 140, 61, ghz(S.cpu_clock), C.text, 14, ALIGN_RIGHT, 255)
  draw_line(cvs, 199, 164, 310, 164, C.line, 220, 1)
  draw_gpu_icon(cvs, 201, 171, 0xA857F4)
  draw_text(cvs, 219, 172, 32, "GPU", 0xA857F4, 14, ALIGN_LEFT, 255)
  draw_text(cvs, 247, 172, 61, ghz(S.gpu_clock), C.text, 14, ALIGN_RIGHT, 255)
  draw_line(cvs, 199, 196, 310, 196, C.line, 220, 1)
  draw_fan_icon(cvs, 200, 204, C.warn)
  draw_text(cvs, 219, 204, 32, "FAN", C.warn, 14, ALIGN_LEFT, 255)
  draw_text(cvs, 247, 204, 61, S.fan and string_format("%d RPM", math_floor(S.fan + 0.5)) or "-- RPM", C.text, 14, ALIGN_RIGHT, 255)
end

local function draw_hexagon(cvs, x, y, active)
  local color = C.accent
  local points = {
    { x + 18, y }, { x + 54, y }, { x + 72, y + 30 },
    { x + 54, y + 60 }, { x + 18, y + 60 }, { x, y + 30 },
  }
  for i = 1, 6 do
    local a = points[i]
    local b = points[(i % 6) + 1]
    if not (active and (i == 1 or i == 6)) then
      draw_line(cvs, a[1], a[2], b[1], b[2], color, 255, 2)
    end
  end
end

local function draw_bold_text(cvs, x, y, w, text, color, size, align)
  draw_text(cvs, x, y, w, text, color, size, align, 255)
  draw_text(cvs, x + 1, y, w, text, color, size, align, 255)
end

local function draw_hex_node(cvs, x, y, label, value, suffix, active)
  draw_hexagon(cvs, x, y, active)
  local label_color = C.accent
  local value_color = C.text
  draw_bold_text(cvs, x + 10, y + 7, 52, label, label_color, 10, ALIGN_CENTER)
  draw_bold_text(cvs, x + 7, y + 28, 58,
    tostring(value or "--") .. tostring(suffix or ""), value_color, 18, ALIGN_CENTER)
end

local function network_rate(value)
  value = tonumber(value)
  if not value then return "--" end
  if value >= 1024 then return string_format("%.1fM", value / 1024) end
  return string_format("%.0fK", value)
end

local function draw_hex_network_node(cvs, x, y, upload, download)
  draw_hexagon(cvs, x, y, false)
  local color = C.accent
  draw_line(cvs, x + 19, y + 25, x + 19, y + 15, color, 255, 2)
  draw_line(cvs, x + 19, y + 15, x + 15, y + 19, color, 255, 2)
  draw_line(cvs, x + 19, y + 15, x + 23, y + 19, color, 255, 2)
  draw_line(cvs, x + 19, y + 47, x + 19, y + 37, color, 255, 2)
  draw_line(cvs, x + 19, y + 47, x + 15, y + 43, color, 255, 2)
  draw_line(cvs, x + 19, y + 47, x + 23, y + 43, color, 255, 2)
  draw_bold_text(cvs, x + 24, y + 13, 40, network_rate(upload), C.text, 17, ALIGN_CENTER)
  draw_bold_text(cvs, x + 24, y + 35, 40, network_rate(download), C.text, 17, ALIGN_CENTER)
end

local function draw_hex_clock_node(cvs, x, y, value, is_gpu)
  draw_hexagon(cvs, x, y, false)
  local icon_color = is_gpu and 0xA857F4 or C.cpu
  if is_gpu then
    draw_gpu_icon(cvs, x + 31, y + 7, icon_color)
  else
    draw_chip_icon(cvs, x + 32, y + 9, icon_color)
  end
  draw_text(cvs, x + 8, y + 35, 62, tostring(value or "--") .. "G", C.text, 11, ALIGN_CENTER, 255)
end

local function hex_clock(value)
  value = tonumber(value)
  return value and string_format("%.1f", value / 1000) or "--"
end

local function hex_number(value)
  value = tonumber(value)
  return value and tostring(math_floor(value + 0.5)) or "--"
end

local function draw_clock_temp(cvs, x, y, clock_value, temp_value, color)
  draw_bold_text(cvs, x, y, 53, hex_clock(clock_value) .. " GHz", color, 12, ALIGN_LEFT)
  draw_arc_span(cvs, x + 58, y + 8, 1, 0, 359, color, 255, 2)
  draw_bold_text(cvs, x + 65, y, 48, hex_number(temp_value) .. "°C", color, 12, ALIGN_LEFT)
end

local function hex_voltage(value)
  value = tonumber(value)
  return value and string_format("%.2f", value) or "--"
end

local function hex_power(value)
  value = tonumber(value)
  return value and tostring(math_floor(value + 0.5)) or "--"
end

local function memory_gb(value)
  value = tonumber(value)
  return value and string_format("%.0fG", value / 1024) or "--"
end

local function memory_pair(used, total)
  used, total = tonumber(used), tonumber(total)
  if not used or not total then return "--/--" end
  return string_format("%.0f/%.0fG", used / 1024, total / 1024)
end

local function utf8_prefix(text, max_chars)
  text = tostring(text or "")
  local out, pos, count = {}, 1, 0
  while pos <= #text and count < max_chars do
    local byte = text:byte(pos)
    local size = byte >= 0xF0 and 4 or (byte >= 0xE0 and 3 or (byte >= 0xC0 and 2 or 1))
    out[#out + 1] = text:sub(pos, pos + size - 1)
    pos = pos + size
    count = count + 1
  end
  return table.concat(out)
end

local function utf8_length(text)
  text = tostring(text or "")
  local pos, count = 1, 0
  while pos <= #text do
    local byte = text:byte(pos)
    pos = pos + (byte >= 0xF0 and 4 or (byte >= 0xE0 and 3 or (byte >= 0xC0 and 2 or 1)))
    count = count + 1
  end
  return count
end

local function name_style(text, large)
  local count = utf8_length(text)
  if large then
    if count <= 8 then return 22, 8 end
    if count <= 12 then return 17, 12 end
    if count <= 17 then return 13, 17 end
    return 10, 22
  end
  if count <= 7 then return 15, 7 end
  if count <= 10 then return 11, 10 end
  if count <= 14 then return 8, 14 end
  return 7, 17
end

local function compact_cpu_name(text)
  text = tostring(text or "CPU")
  text = text:gsub("^AMD%s+", "")
  text = text:gsub("^Intel%(R%)%s+", "")
  text = text:gsub("^Intel%s+", "")
  text = text:gsub("Core%(TM%)%s*", "Core ")
  text = text:gsub("Processor%s*$", "")
  text = text:gsub("CPU%s*@.*$", "")
  text = text:gsub("^Ryzen%s+(%d+)%s+", "R%1 ")
  text = text:gsub("^Core%s+", "")
  text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return text ~= "" and text or "CPU"
end

local function redraw_hex(cvs)
  local clock, date = dashboard_clock()
  local weather = utf8_prefix(S.weather_city, 4) .. "/" .. utf8_prefix(S.weather_text, 3) .. "/" ..
    (S.weather_temp and tostring(math_floor(S.weather_temp + 0.5)) .. "°C" or "--°C")

  draw_text(cvs, 12, 5, 60, clock, C.text, 14, ALIGN_LEFT, 255)
  draw_arc_span(cvs, 101, 12, 3, 0, 359, C.accent, 255, 1)
  draw_line(cvs, 105, 14, 109, 14, 0xD7E7F5, 255, 1)
  draw_line(cvs, 109, 14, 112, 17, 0xD7E7F5, 255, 1)
  draw_line(cvs, 112, 17, 105, 17, 0xD7E7F5, 255, 1)
  draw_text(cvs, 111, 5, 116, weather, C.text, 8, ALIGN_CENTER, 255, WEATHER_FONT)
  draw_bold_text(cvs, 235, 6, 76, date, C.sub, 10, ALIGN_RIGHT)
  draw_line(cvs, 0, 27, 319, 27, 0x161A1C, 255, 1)

  draw_hex_node(cvs, 65, 45, "CPU V", hex_voltage(S.cpu_voltage), "V", false)
  draw_hex_node(cvs, 11, 75, "CPU", hex_number(S.cpu_usage), "%", false)
  draw_hex_node(cvs, 65, 105, "GPU", hex_number(S.gpu_usage), "%", true)
  draw_hex_node(cvs, 119, 75, "RAM", hex_number(S.mem_usage), "%", false)
  draw_hex_network_node(cvs, 11, 135, S.net_upload, S.net_download)
  draw_hex_node(cvs, 65, 165, "PWR", hex_power(S.cpu_power), "W", false)
  draw_hex_node(cvs, 119, 135, "FAN", hex_number(S.fan), "", false)

  local gpu_name = config.gpu_name ~= nil and config.gpu_name ~= "GPU" and config.gpu_name or S.gpu_name or "GPU"
  local cpu_name = config.cpu_name ~= nil and config.cpu_name ~= "CPU" and config.cpu_name or S.cpu_name or "CPU"
  cpu_name = compact_cpu_name(cpu_name)
  draw_bold_text(cvs, 200, 56, 113, utf8_prefix(gpu_name, 13), C.text, 30, ALIGN_LEFT)
  draw_clock_temp(cvs, 200, 84, S.gpu_clock, S.gpu_temp, C.accent)
  draw_line(cvs, 200, 110, 313, 110, C.accent, 255, 2)
  draw_bold_text(cvs, 200, 123, 28, "CPU", C.accent, 12, ALIGN_LEFT)
  draw_bold_text(cvs, 234, 123, 79,
    utf8_prefix(cpu_name, 12),
    C.text, 12, ALIGN_LEFT)
  draw_clock_temp(cvs, 200, 149, S.cpu_clock, S.cpu_temp, C.accent)
  draw_line(cvs, 200, 174, 313, 174, C.accent, 255, 2)
  local mem_total = S.mem_used and S.mem_free and (S.mem_used + S.mem_free) or nil
  draw_bold_text(cvs, 200, 187, 40, "MEM", C.accent, 12, ALIGN_LEFT)
  draw_bold_text(cvs, 240, 187, 73,
    memory_pair(S.mem_used, mem_total), C.text, 12, ALIGN_LEFT)

end

local function load_weather_location()
  local doc = decode_json(read_text_file("/sd/apps/settings.json")) or {}
  local raw = text_or(doc.weather_address or doc.weatherAddress, "")
  local location = text_or(doc.weather_location_id, raw)
  local city = text_or(doc.weather_city or doc.city_name or doc.city, raw)
  S.weather_city = city ~= "" and city or "Weather"
  if type(doc.timezone) == "string" and doc.timezone ~= "" and time and time.settimezone then
    pcall(time.settimezone, doc.timezone)
  end
  return location
end

local redraw

local function request_weather()
  if S.weather_inflight or not http or not http.cubicserver or not http.cubicserver.get then return end
  local location = load_weather_location()
  if location == "" then return end
  S.weather_inflight = true
  local url = "/v1/weather/now?location=" .. tostring(location) .. "&unit=m&lang=zh"
  http.cubicserver.get(url, "Accept-Encoding: gzip\r\n", function(status_code, body)
    S.weather_inflight = false
    if state.stopped or status_code ~= 200 then return end
    if zlib and zlib.isgzip and zlib.isgzip(body) and zlib.gunzip then
      local ok, plain = pcall(zlib.gunzip, body)
      if ok and type(plain) == "string" then body = plain end
    end
    local doc = decode_json(body)
    local now = doc and doc.now
    if tostring(doc and doc.code or "") == "200" and type(now) == "table" then
      S.weather_temp = tonumber(now.temp)
      S.weather_text = text_or(now.text, "--")
      S.weather_code = text_or(now.icon, "999")
      redraw()
    end
  end)
end

redraw = function()
  local cvs = UI.canvas
  if not cvs then
    return
  end

  local explicit = begin_frame(cvs)
  if lv_canvas_fill_bg then
    pcall(lv_canvas_fill_bg, cvs, C.bg, 255)
  elseif lv_canvas_fill then
    pcall(lv_canvas_fill, cvs, C.bg, 255)
  end

  if config.layout == "dashboard" then
    redraw_dashboard(cvs)
  elseif config.layout == "hex" then
    redraw_hex(cvs)
  else
    draw_text(cvs, 8, 8, 220, "HOLO PC MONITOR", C.text, 16, ALIGN_LEFT, 255)
    draw_metric_wheel(cvs, 76, 94, "CPU", S.cpu_usage, S.cpu_temp, C.cpu)
    draw_metric_wheel(cvs, 244, 94, "GPU", S.gpu_usage, S.gpu_temp, C.gpu)
    draw_status_core(cvs, 160, 92)
    draw_clocks(cvs)
    draw_memory(cvs)
  end
  end_frame(cvs, explicit)
end

local function set_status(text, color)
  S.status = text
  S.status_color = color
  redraw()
end

local function update_from_sample(sample)
  S.last_sample = sample
  S.last_seen_ms = sample and sample.received_at or now_ms()
  S.cpu_usage = metric_value(sample, "cpu_usage")
  S.cpu_temp = metric_value(sample, "cpu_temp")
  S.cpu_clock = metric_value(sample, "cpu_clock")
  S.cpu_voltage = metric_value(sample, "cpu_voltage")
  S.cpu_power = metric_value(sample, "cpu_power")
  S.cpu_name = metric_value(sample, "cpu_name")
  S.gpu_usage = metric_value(sample, "gpu_usage")
  S.gpu_temp = metric_value(sample, "gpu_temp")
  S.gpu_clock = metric_value(sample, "gpu_clock")
  S.gpu_name = metric_value(sample, "gpu_name")
  S.mem_usage = metric_value(sample, "memory_usage")
  S.mem_used = metric_value(sample, "memory_used")
  S.mem_free = metric_value(sample, "memory_free")
  S.net_upload = metric_value(sample, "network_upload")
  S.net_download = metric_value(sample, "network_download")
  S.fan = metric_value(sample, "fan")
  push_history(S.cpu_history, S.cpu_usage)
  push_history(S.gpu_history, S.gpu_usage)
  push_history(S.cpu_temp_history, S.cpu_temp)
  push_history(S.gpu_temp_history, S.gpu_temp)
end

local function update_stale_status()
  if S.last_seen_ms <= 0 then
    return
  end

  if now_ms() - S.last_seen_ms > (config.stale_ms or 5000) and S.status == "LIVE" then
    S.status = "STALE"
    S.status_color = C.hot
  end
end

local function reset_sample_state()
  S.last_sample = nil
  S.last_seen_ms = 0
  S.spin = 0
  S.cpu_usage = nil
  S.cpu_temp = nil
  S.cpu_clock = nil
  S.cpu_voltage = nil
  S.cpu_power = nil
  S.cpu_name = nil
  S.gpu_usage = nil
  S.gpu_temp = nil
  S.gpu_clock = nil
  S.gpu_name = nil
  S.mem_usage = nil
  S.mem_used = nil
  S.mem_free = nil
  S.net_upload = nil
  S.net_download = nil
  S.fan = nil
  S.cpu_history = {}
  S.gpu_history = {}
  S.cpu_temp_history = {}
  S.gpu_temp_history = {}
end

local function build_ui()
  local root = lv_scr_act()
  if lv_obj_clean then
    lv_obj_clean(root)
  elseif lv_clear then
    lv_clear()
  end

  call(lv_obj_set_style_bg_color, root, C.bg, MAIN_STYLE)
  call(lv_obj_set_style_bg_opa, root, 255, MAIN_STYLE)
  if lv_obj_clear_flag and rawget(_G, "LV_OBJ_FLAG_SCROLLABLE") then
    call(lv_obj_clear_flag, root, rawget(_G, "LV_OBJ_FLAG_SCROLLABLE"))
  end

  if lv_canvas_create then
    if CANVAS_FMT then
      UI.canvas = lv_canvas_create(root, UI.w, UI.h, CANVAS_FMT)
    else
      UI.canvas = lv_canvas_create(root, UI.w, UI.h)
    end
    call(lv_obj_set_pos, UI.canvas, 0, 0)
  end
end

local function create_client()
  return AidaClient.new(config, {
    on_status = function(status)
      log("status", status)

      if status == "connecting" then
        set_status("CONNECTING", C.warn)
      elseif status == "connected" or status == "stream" then
        set_status("WAITING", C.warn)
      elseif status == "stale" then
        set_status("STALE", C.hot)
      elseif status == "error" or status == "complete" then
        set_status("OFFLINE", C.hot)
      end
    end,
    on_sample = function(sample)
      log("sample", sample and sample.received_at or 0)
      update_from_sample(sample)
      set_status("LIVE", C.gpu)
    end,
    on_control = function(payload)
      log("control", payload)
      if payload == "ReLoad" then
        set_status("NO ITEMS", C.warn)
      end
    end
  })
end

local function start_client()
  if state.client then
    state.client:stop()
  end

  reset_sample_state()
  set_status("CONNECTING", C.warn)

  state.client = create_client()
  local start_ok, start_err = pcall(function()
    state.client:start()
  end)

  if not start_ok then
    log("client_start_error", start_err)
    set_status("ERROR", C.hot)
    return false, start_err
  end

  return true
end

local function start_tick()
  if not tmr or not tmr.create then
    return
  end

  state.tick_timer = tmr.create()
  state.tick_timer:alarm(120, tmr.ALARM_AUTO, function()
    if state.stopped then
      return
    end
    S.spin = (S.spin + 10) % 360
    update_stale_status()
    redraw()
  end)
end

local function load_weather_font()
  if lv_font_load then
    local ok, handle = pcall(lv_font_load, "/sd/apps/weather/font/weather_ui_zh_cn_12.bin")
    if ok and type(handle) == "number" and handle > 0 then WEATHER_FONT = handle end
  end
end

local function start_weather()
  request_weather()
  if not tmr or not tmr.create then return end
  state.weather_timer = tmr.create()
  state.weather_timer:alarm(60000, tmr.ALARM_AUTO, function()
    if not state.stopped then request_weather() end
  end)
end

function state.stop()
  state.stopped = true

  if state.client then
    state.client:stop()
  end

  if state.web then
    state.web:stop("app_stop")
  end

  if state.tick_timer then
    state.tick_timer:unregister()
    state.tick_timer = nil
  end
  if state.weather_timer then
    state.weather_timer:unregister()
    state.weather_timer = nil
  end
  if state.controller_timer then
    state.controller_timer:unregister()
    state.controller_timer = nil
  end

  if key and key.off then
    key.off()
  end
  -- 先清 LVGL 对象再释放字体，否则残留对象仍指向已释放的字体指针。
  if lv_obj_clean and lv_scr_act then
    pcall(function() lv_obj_clean(lv_scr_act()) end)
  end
  if WEATHER_FONT and lv_font_free then
    pcall(lv_font_free, WEATHER_FONT)
    WEATHER_FONT = nil
  end
  -- stop 后必须清全局单例 key：否则退出后整份状态（采样历史/闭包/canvas id）
  -- 仍被 _G.__aida_monitor 持有无法回收，下次进入还会再调一遍旧实例的 stop。
  if rawget(_G, "__aida_monitor") == state then
    _G.__aida_monitor = nil
  end
end

if controller and controller.state and tmr and tmr.create then
  local last_buttons = 0
  state.controller_timer = tmr.create()
  state.controller_timer:alarm(40, tmr.ALARM_AUTO, function()
    local ok, pad = pcall(function() return controller.state("ble-main") end)
    local buttons = ok and type(pad) == "table" and (tonumber(pad.buttons) or 0) or 0
    local pressed = buttons & (~last_buttons)
    last_buttons = buttons
    if (pressed & (4096 | 32768)) ~= 0 then
      state.stop()
      if app and app.exit then pcall(function() app.exit() end) end
    end
  end)
end

function state.restart_client()
  if state.stopped then
    return false, "stopped"
  end
  return start_client()
end

if key and key.on and key.HOME then
  key.on(key.HOME, function(evt_type)
    if evt_type == key.SHORT then
      state.stop()
      if app and app.exit then
        app.exit()
      end
    end
  end)
end

_G.__aida_monitor = state
build_ui()
load_weather_font()
redraw()
start_tick()
start_weather()

if AidaWeb and AidaWeb.new then
  state.web = AidaWeb.new({
    config = config,
    config_path = APP_DIR .. "/config.lua",
    route_base = (app and app.route_base and app.route_base()) or "/holo_pc_monitor",
    restart = function()
      C.accent = tonumber(config.accent_color) or 0xE7C21D
      redraw()
      return state.restart_client()
    end,
  })
  state.web:start()
end

start_client()
