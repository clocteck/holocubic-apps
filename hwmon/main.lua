if _G.HWMON_APP and _G.HWMON_APP.stop then
  pcall(function() _G.HWMON_APP.stop("reload") end)
end

HWMON_APP = {
  VERSION = "2026-05-13-hwmon-v10",
  SCREEN_W = 320,
  SCREEN_H = 240,
  TICK_MS = 500,
  FETCH_MS = 1000,
  OFFLINE_MS = 7000,
  ROUTE_BASE = (app and app.route_base and app.route_base()) or "/hwmon",
  DEFAULT_STATE_URL = "http://192.168.0.80:8888/api/state",
  routes = {},
  timers = {},
  running = true,
  config = {},
}

local APP = HWMON_APP
local json = rawget(_G, "sjson") or rawget(_G, "json")
local MAIN_STYLE = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
local ALIGN_LEFT = rawget(_G, "LV_TEXT_ALIGN_LEFT") or 0
local ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1
local ALIGN_RIGHT = rawget(_G, "LV_TEXT_ALIGN_RIGHT") or 2
local CANVAS_FMT = rawget(_G, "LV_IMG_CF_TRUE_COLOR") or rawget(_G, "CANVAS_FMT_TRUE_COLOR")

local C = {
  bg = 0x000000,
  panel = 0x07111B,
  panel2 = 0x0C1824,
  track = 0x151D26,
  track2 = 0x202A35,
  frame = 0xDDEBFF,
  frame2 = 0x6F9FE8,
  dim = 0x66717D,
  sub = 0x9BA8B7,
  text = 0xF4F7FB,
  cpu = 0x46C7FF,
  gpu = 0x62E493,
  mem = 0xF2B84B,
  ok = 0x62E493,
  warn = 0xFF7B4A,
  hot = 0xFF5D5D,
}

local S = {
  seq = 0,
  online = false,
  last_seen_ms = 0,
  last_error = "waiting for host",
  last_http_code = nil,
  request_inflight = false,
  host = "",
  cpu_name = "CPU",
  cpu_usage = nil,
  cpu_temp = nil,
  cpu_power_w = nil,
  cpu_voltage_v = nil,
  gpu_usage = nil,
  gpu_temp = nil,
  gpu_name = "GPU",
  gpu_power_w = nil,
  gpu_power_limit_w = nil,
  gpu_voltage_v = nil,
  mem_usage = nil,
  mem_used_gb = nil,
  mem_total_gb = nil,
  spin = 0,
}

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

local function call_webui(enabled)
  if not app or not app.set_webui then
    return false, "app.set_webui not supported"
  end
  return pcall(function() return app.set_webui(enabled) end)
end

local UI = {
  canvas = nil,
}

APP.config.state_url = APP.DEFAULT_STATE_URL

local math_floor = math.floor
local math_cos = math.cos
local math_sin = math.sin
local math_pi = math.pi
local string_format = string.format

local function call(fn, ...)
  if not fn then return false end
  return pcall(fn, ...)
end

local function now_ms()
  if millis then
    local ok, value = pcall(millis)
    if ok and type(value) == "number" then
      return value
    end
  end
  if tmr and tmr.now then
    local ok, value = pcall(function() return tmr.now() end)
    if ok and type(value) == "number" then
      return math_floor(value / 1000)
    end
  end
  return 0
end

local function clamp(n, lo, hi)
  n = tonumber(n)
  if not n then return nil end
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function clamp_pct(n)
  return clamp(n, 0, 100)
end

local function text_or(value, fallback)
  if value == nil then return fallback or "" end
  local text = tostring(value)
  if text == "" then return fallback or "" end
  return text
end

local function short_text(value, limit)
  local text = text_or(value, "")
  limit = limit or 24
  if #text <= limit then return text end
  return text:sub(1, limit - 1) .. "."
end

local function fmt_pct(value)
  value = tonumber(value)
  if not value then return "--%" end
  return string_format("%d%%", math_floor(value + 0.5))
end

local function fmt_num(value)
  value = tonumber(value)
  if not value then return "--" end
  return string_format("%d", math_floor(value + 0.5))
end

local function fmt_temp(value)
  value = tonumber(value)
  if not value then return "-- C" end
  return string_format("%d C", math_floor(value + 0.5))
end

local function fmt_gb(value)
  value = tonumber(value)
  if not value then return "--" end
  if value >= 10 then
    return string_format("%.0f", value)
  end
  return string_format("%.1f", value)
end

local function fmt_mem_short(used, total)
  if used and total then
    return fmt_gb(used) .. "/" .. fmt_gb(total) .. "G"
  end
  if total then
    return fmt_gb(total) .. "G"
  end
  if used then
    return fmt_gb(used) .. "G"
  end
  return ""
end

local function metric_color(temp, base)
  temp = tonumber(temp)
  if not temp then return base end
  if temp >= 85 then return C.hot end
  if temp >= 75 then return C.warn end
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
  if not lv_canvas_draw_rect then return end
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

local function draw_panel(cvs, x, y, w, h, bg, bg_opa, border, border_opa, radius, border_w)
  if not lv_canvas_draw_rect then return end
  local ok = pcall(lv_canvas_draw_rect, cvs, x, y, w, h, {
    bg_color = bg or C.panel,
    bg_opa = bg_opa or 0,
    radius = radius or 0,
    border_width = border_w or 1,
    border_color = border or C.frame,
    border_opa = border_opa or 255,
  })
  if not ok then
    draw_rect(cvs, x, y, w, h, bg or C.panel, bg_opa or 0, radius or 0)
  end
end

local function draw_line(cvs, x1, y1, x2, y2, color, opa, width)
  if not lv_canvas_draw_line then return end
  local ok = pcall(lv_canvas_draw_line, cvs, x1, y1, x2, y2, color, opa or 255, width or 1)
  if not ok then
    pcall(lv_canvas_draw_line, cvs, { x1, y1, x2, y2 }, nil, {
      color = color,
      opa = opa or 255,
      width = width or 1,
    })
  end
end

local function draw_round_dot(cvs, x, y, size, color, opa)
  local r = math_floor(size / 2)
  draw_rect(cvs, math_floor(x - r), math_floor(y - r), size, size, color, opa or 255, r)
end

local function draw_text(cvs, x, y, w, text, color, size, align, opa)
  if not lv_canvas_draw_text then return end
  local ok = pcall(lv_canvas_draw_text, cvs, x, y, w, text_or(text, ""), {
    color = color or C.text,
    opa = opa or 255,
    align = align or ALIGN_LEFT,
    font_size = size or 12,
  })
  if not ok then
    pcall(lv_canvas_draw_text, cvs, x, y, w, text_or(text, ""), color or C.text, opa or 255, align or ALIGN_LEFT, size or 12)
  end
end

local function draw_arc_raw(cvs, cx, cy, r, start_deg, end_deg, color, opa, width)
  if not lv_canvas_draw_arc then return end
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
  if n < 0 then n = n + 360 end
  return n
end

local function draw_arc_span(cvs, cx, cy, r, start_deg, span_deg, color, opa, width)
  span_deg = tonumber(span_deg) or 0
  if span_deg <= 0 then return end
  if span_deg >= 359 then
    draw_arc_raw(cvs, cx, cy, r, 0, 360, color, opa, width)
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

local function polar(cx, cy, r, deg)
  local rad = deg * math_pi / 180
  return cx + math_floor(math_cos(rad) * r + 0.5), cy + math_floor(math_sin(rad) * r + 0.5)
end

local function draw_arc_cap(cvs, cx, cy, r, deg, width, color, opa)
  local cap_r = r - math_floor((width or 1) / 2)
  if cap_r < 0 then cap_r = 0 end
  local x, y = polar(cx, cy, cap_r, math_floor(norm_deg(deg)))
  draw_round_dot(cvs, x, y, width, color, opa or 255)
end

local WHEEL_SEGMENTS = {
  { start = -90, span = 360 },
}
local WHEEL_TOTAL_SPAN = 360
local WHEEL_STEP_COUNT = 8
local WHEEL_STEP_SPANS = { 45, 45, 45, 45, 45, 45, 45, 45 }
local WHEEL_OVERLAP_DEG = 1

local function mix_color(a, b, t)
  if t < 0 then t = 0 end
  if t > 1 then t = 1 end
  local ar = math_floor(a / 65536) % 256
  local ag = math_floor(a / 256) % 256
  local ab = a % 256
  local br = math_floor(b / 65536) % 256
  local bg = math_floor(b / 256) % 256
  local bb = b % 256
  local rr = math_floor(ar + (br - ar) * t + 0.5)
  local rg = math_floor(ag + (bg - ag) * t + 0.5)
  local rb = math_floor(ab + (bb - ab) * t + 0.5)
  return rr * 65536 + rg * 256 + rb
end

local function gradient_color_at(progress)
  if progress <= 0 then return C.cpu end
  if progress >= 1 then return C.hot end
  if progress <= 0.5 then
    return mix_color(C.cpu, C.warn, progress * 2)
  end
  return mix_color(C.warn, C.hot, (progress - 0.5) * 2)
end

local function wheel_step_color(step)
  if step <= 1 then return C.cpu end
  if step >= WHEEL_STEP_COUNT then return C.hot end
  return gradient_color_at((step - 1) / (WHEEL_STEP_COUNT - 1))
end

local function wheel_step_for_offset(offset)
  if offset <= 0 then return 1 end
  local pos = 0
  for i = 1, WHEEL_STEP_COUNT do
    pos = pos + WHEEL_STEP_SPANS[i]
    if offset <= pos or i == WHEEL_STEP_COUNT then
      return i
    end
  end
  return WHEEL_STEP_COUNT
end

local function wheel_color_for_offset(offset)
  return wheel_step_color(wheel_step_for_offset(offset))
end

local function wheel_color_for_pct(pct, fallback)
  local value = clamp_pct(pct)
  if not value then return fallback or C.cpu end
  return wheel_color_for_offset(value * WHEEL_TOTAL_SPAN / 100)
end

local function wheel_angle_at(offset)
  if offset <= 0 then return WHEEL_SEGMENTS[1].start end
  if offset >= WHEEL_TOTAL_SPAN then
    local last = WHEEL_SEGMENTS[#WHEEL_SEGMENTS]
    return last.start + last.span
  end
  local left = offset
  for _, seg in ipairs(WHEEL_SEGMENTS) do
    if left < seg.span then
      return seg.start + left
    end
    left = left - seg.span
  end
  local last = WHEEL_SEGMENTS[#WHEEL_SEGMENTS]
  return last.start + last.span
end

local function wheel_segment_at(offset)
  local left = offset
  for _, seg in ipairs(WHEEL_SEGMENTS) do
    if left < seg.span then
      return seg, left
    end
    left = left - seg.span
  end
  local last = WHEEL_SEGMENTS[#WHEEL_SEGMENTS]
  return last, last.span
end

local function draw_wheel_path_span(cvs, cx, cy, r, offset, span_deg, color, opa, width)
  local pos = offset
  local left = span_deg
  if left <= 0 then return end
  if pos < 0 then
    left = left + pos
    pos = 0
  end
  if pos >= WHEEL_TOTAL_SPAN then return end
  if pos + left > WHEEL_TOTAL_SPAN then
    left = WHEEL_TOTAL_SPAN - pos
  end

  while left > 0 do
    local seg, seg_offset = wheel_segment_at(pos)
    local chunk = seg.span - seg_offset
    if chunk > left then chunk = left end
    if chunk <= 0 then break end
    local draw_span = chunk
    if pos + chunk < WHEEL_TOTAL_SPAN then
      draw_span = draw_span + WHEEL_OVERLAP_DEG
    end
    draw_arc_span(cvs, cx, cy, r, seg.start + seg_offset, draw_span, color, opa, width)
    pos = pos + chunk
    left = left - chunk
  end
end

local function draw_gradient_wheel_span(cvs, cx, cy, r, span_deg, opa, width)
  local left = span_deg
  local offset = 0
  for step = 1, WHEEL_STEP_COUNT do
    if left <= 0 then break end
    local span = WHEEL_STEP_SPANS[step]
    if span > left then span = left end
    draw_wheel_path_span(cvs, cx, cy, r, offset, span, wheel_step_color(step), opa, width)
    left = left - span
    offset = offset + WHEEL_STEP_SPANS[step]
  end
end

local function draw_colored_wheel(cvs, cx, cy, pct, radius, width)
  local value = clamp_pct(pct) or 0
  local active_span = value * WHEEL_TOTAL_SPAN / 100
  radius = radius or 48
  width = width or 9

  draw_arc_span(cvs, cx, cy, radius + 3, 0, 360, C.frame, 105, 3)
  draw_arc_span(cvs, cx, cy, radius, 0, 360, C.track, 180, width)
  draw_arc_span(cvs, cx, cy, radius - width, 0, 360, C.panel2, 135, 2)
  draw_gradient_wheel_span(cvs, cx, cy, radius, WHEEL_TOTAL_SPAN, 78, width)
  draw_gradient_wheel_span(cvs, cx, cy, radius, active_span, 255, width)

  if value > 0 then
    local end_deg = wheel_angle_at(active_span)
    local end_color = wheel_color_for_offset(active_span)
    draw_arc_cap(cvs, cx, cy, radius, wheel_angle_at(0), width, wheel_step_color(1), 245)
    draw_arc_cap(cvs, cx, cy, radius, end_deg, width, end_color, 255)
  end
end

local function draw_temp_strip(cvs, x, y, temp, color)
  local t = tonumber(temp)
  if not t then return end
  local active = metric_color(t, color)
  local bar_w = 52
  local fill_w = math_floor(bar_w * clamp(t, 0, 100) / 100 + 0.5)

  draw_text(cvs, x, y - 1, 38, "TEMP", C.sub, 10, ALIGN_LEFT, 230)
  draw_rect(cvs, x + 41, y + 2, bar_w, 8, C.track2, 230, 1)
  if fill_w > 0 then
    draw_rect(cvs, x + 41, y + 2, fill_w, 8, active, 235, 1)
  end
  draw_text(cvs, x + 98, y - 2, 36, fmt_temp(t), active, 11, ALIGN_RIGHT, 245)
end

local function draw_metric_wheel(cvs, cx, cy, pct, temp, temp_x, color)
  local v = clamp_pct(pct) or 0
  draw_colored_wheel(cvs, cx, cy, v, 52, 12)

  draw_text(cvs, cx - 31, cy - 30, 62, "LOAD", C.sub, 11, ALIGN_CENTER, 245)
  draw_text(cvs, cx - 39, cy - 8, 78, fmt_num(pct), C.text, 30, ALIGN_CENTER, 255)
  draw_text(cvs, cx - 12, cy + 27, 24, "%", C.sub, 12, ALIGN_CENTER, 245)
  draw_temp_strip(cvs, temp_x, 136, temp, color)
end

local function draw_ram(cvs)
  local x = 116
  local y = 174
  local w = 66
  local bar_y = 204
  local bar_h = 12
  local pct = clamp_pct(S.mem_usage) or 0
  local fill_w = math_floor(w * pct / 100 + 0.5)
  local color = wheel_color_for_pct(pct, C.mem)
  local mem_text = fmt_mem_short(S.mem_used_gb, S.mem_total_gb)

  draw_colored_wheel(cvs, 58, 196, pct, 35, 8)
  draw_text(cvs, 38, 183, 40, "LOAD", C.sub, 9, ALIGN_CENTER, 225)
  draw_text(cvs, 33, 198, 50, fmt_num(S.mem_usage), C.text, 20, ALIGN_CENTER, 255)
  draw_text(cvs, 50, 218, 20, "%", C.sub, 10, ALIGN_CENTER, 230)
  draw_text(cvs, 22, 216, 66, "RAM", C.text, 17, ALIGN_CENTER, 245)

  if mem_text ~= "" then
    draw_text(cvs, x, y, w, mem_text, C.text, 14, ALIGN_RIGHT, 255)
  end

  draw_rect(cvs, x, bar_y, w, bar_h, C.track2, 235, 7)
  if fill_w > 0 then
    draw_rect(cvs, x, bar_y, fill_w, bar_h, color, 255, 7)
    if fill_w > 16 then
      draw_rect(cvs, x + 4, bar_y + 3, fill_w - 8, 2, 0xFFFFFF, 42, 2)
    end
  end
end

local function draw_shell(cvs)
  draw_panel(cvs, 8, 18, 304, 140, C.panel, 58, C.frame, 235, 8, 2)
  draw_panel(cvs, 11, 21, 298, 134, C.panel, 30, C.frame2, 105, 7, 1)
  draw_line(cvs, 10, 46, 181, 46, C.frame, 220, 3)
  draw_line(cvs, 188, 46, 310, 46, C.frame, 220, 3)
  draw_line(cvs, 160, 156, 191, 19, C.frame, 230, 3)
  draw_line(cvs, 163, 156, 194, 19, C.frame2, 95, 1)
  draw_line(cvs, 10, 128, 150, 128, C.frame2, 90, 1)
  draw_line(cvs, 196, 128, 310, 128, C.frame2, 90, 1)
  draw_text(cvs, 61, 25, 86, "CPU", C.text, 20, ALIGN_CENTER, 250)
  draw_text(cvs, 215, 25, 86, "GPU", C.text, 20, ALIGN_CENTER, 250)

  draw_panel(cvs, 8, 163, 190, 68, C.panel, 55, C.frame, 225, 8, 2)
  draw_line(cvs, 94, 229, 128, 164, C.frame, 220, 3)
  draw_line(cvs, 97, 229, 131, 164, C.frame2, 90, 1)
end

local function redraw()
  local cvs = UI.canvas
  if not cvs then return end

  local explicit = begin_frame(cvs)
  if lv_canvas_fill_bg then
    pcall(lv_canvas_fill_bg, cvs, C.bg, 255)
  elseif lv_canvas_fill then
    pcall(lv_canvas_fill, cvs, C.bg, 255)
  end

  draw_shell(cvs)
  draw_metric_wheel(cvs, 78, 100, S.cpu_usage, S.cpu_temp, 24, C.cpu)
  draw_metric_wheel(cvs, 242, 100, S.gpu_usage, S.gpu_temp, 184, C.gpu)

  draw_ram(cvs)
  end_frame(cvs, explicit)
end

local function update_online_state()
  if S.last_seen_ms <= 0 then
    S.online = false
    return
  end
  if (now_ms() - S.last_seen_ms) > APP.OFFLINE_MS then
    S.online = false
    S.last_error = "host timeout"
  else
    S.online = true
  end
end

local function safe_json_decode(raw)
  if not json or not json.decode then
    return nil, "json missing"
  end
  local ok, doc, err = pcall(function()
    local value, decode_err = json.decode(raw or "")
    return value, decode_err
  end)
  if not ok then
    return nil, tostring(doc)
  end
  if not doc then
    return nil, tostring(err or "decode failed")
  end
  return doc, nil
end

local function load_config()
  if not file or not file.getcontents then
    return
  end
  local raw = file.getcontents("/sd/apps/hwmon/config.json")
  if not raw or raw == "" then
    return
  end
  local cfg = safe_json_decode(raw)
  if type(cfg) ~= "table" then
    return
  end
  if type(cfg.state_url) == "string" and cfg.state_url ~= "" then
    APP.config.state_url = cfg.state_url
  elseif type(cfg.server_url) == "string" and cfg.server_url ~= "" then
    APP.config.state_url = cfg.server_url
  end
end

local function read_request_body(req, max_bytes)
  if not req or not req.getbody then
    return "", nil
  end
  local parts = {}
  local total = 0
  while true do
    local chunk = req.getbody()
    if not chunk then break end
    total = total + #chunk
    if max_bytes and total > max_bytes then
      return nil, "body too large"
    end
    parts[#parts + 1] = chunk
  end
  return table.concat(parts), nil
end

local function json_response(status, value)
  local raw = nil
  if json and json.encode then
    local ok, body = pcall(function() return json.encode(value) end)
    if ok then raw = body end
  end
  if not raw then
    raw = "{\"ok\":false,\"error\":\"json encode failed\"}"
    status = "500 Internal Server Error"
  end
  return {
    status = status or "200 OK",
    type = "application/json; charset=utf-8",
    headers = {
      ["cache-control"] = "no-store",
      ["access-control-allow-origin"] = "*",
      ["connection"] = "close",
    },
    body = raw,
  }
end

local function text_response(body)
  return {
    status = "200 OK",
    type = "text/plain; charset=utf-8",
    headers = {
      ["cache-control"] = "no-store",
      ["access-control-allow-origin"] = "*",
      ["connection"] = "close",
    },
    body = body or "",
  }
end

local function pick_number(tbl, key1, key2, key3)
  if type(tbl) ~= "table" then return nil end
  local value = tbl[key1]
  if value == nil and key2 then value = tbl[key2] end
  if value == nil and key3 then value = tbl[key3] end
  return tonumber(value)
end

local function apply_payload(doc)
  if type(doc) ~= "table" then
    return false, "json root must be object"
  end

  local cpu = type(doc.cpu) == "table" and doc.cpu or {}
  local gpu = type(doc.gpu) == "table" and doc.gpu or {}
  local mem = type(doc.memory) == "table" and doc.memory or (type(doc.mem) == "table" and doc.mem or {})

  S.seq = S.seq + 1
  S.host = text_or(doc.host or doc.hostname, S.host)
  S.cpu_name = short_text(cpu.name or doc.cpu_name or doc.cpu_model or S.cpu_name, 24)
  S.cpu_usage = clamp_pct(doc.cpu_usage or pick_number(cpu, "usage", "percent", "load"))
  S.cpu_temp = tonumber(doc.cpu_temp or pick_number(cpu, "temp", "temperature"))
  S.cpu_power_w = tonumber(doc.cpu_power_w or pick_number(cpu, "power_w", "power"))
  S.cpu_voltage_v = tonumber(doc.cpu_voltage_v or pick_number(cpu, "voltage_v", "voltage"))
  S.gpu_usage = clamp_pct(doc.gpu_usage or pick_number(gpu, "usage", "percent", "load"))
  S.gpu_temp = tonumber(doc.gpu_temp or pick_number(gpu, "temp", "temperature"))
  S.gpu_name = short_text(gpu.name or doc.gpu_name or doc.gpu_model or S.gpu_name, 24)
  S.gpu_power_w = tonumber(doc.gpu_power_w or pick_number(gpu, "power_w", "power"))
  S.gpu_power_limit_w = tonumber(doc.gpu_power_limit_w or pick_number(gpu, "power_limit_w", "power_limit"))
  S.gpu_voltage_v = tonumber(doc.gpu_voltage_v or pick_number(gpu, "voltage_v", "voltage"))
  S.mem_usage = clamp_pct(doc.mem_usage or pick_number(mem, "usage", "percent"))
  S.mem_used_gb = tonumber(doc.mem_used_gb or pick_number(mem, "used_gb", "used"))
  S.mem_total_gb = tonumber(doc.mem_total_gb or pick_number(mem, "total_gb", "total"))
  S.last_seen_ms = now_ms()
  S.online = true
  S.last_error = nil
  return true, nil
end

local function state_snapshot()
  update_online_state()
  return {
    ok = true,
    version = APP.VERSION,
    route_base = APP.ROUTE_BASE,
    state_url = APP.config.state_url,
    online = S.online,
    seq = S.seq,
    last_error = S.last_error,
    last_http_code = S.last_http_code,
    host = S.host,
    cpu = {
      name = S.cpu_name,
      usage = S.cpu_usage,
      temp = S.cpu_temp,
      power_w = S.cpu_power_w,
      voltage_v = S.cpu_voltage_v,
    },
    gpu = {
      usage = S.gpu_usage,
      temp = S.gpu_temp,
      name = S.gpu_name,
      power_w = S.gpu_power_w,
      power_limit_w = S.gpu_power_limit_w,
      voltage_v = S.gpu_voltage_v,
    },
    memory = {
      usage = S.mem_usage,
      used_gb = S.mem_used_gb,
      total_gb = S.mem_total_gb,
    },
  }
end

local function fetch_state()
  if S.request_inflight then return end
  if not http or not http.get then
    S.last_error = "http missing"
    return
  end
  S.request_inflight = true
  local headers = "Accept: application/json\r\nCache-Control: no-cache\r\n"
  http.get(APP.config.state_url, { headers = headers, timeout = 3000 }, function(code, body)
    S.request_inflight = false
    S.last_http_code = code
    if code ~= 200 then
      S.last_error = "http " .. tostring(code)
      update_online_state()
      redraw()
      return
    end
    local doc, err = safe_json_decode(body)
    if not doc then
      S.last_error = "json " .. tostring(err)
      update_online_state()
      redraw()
      return
    end
    local ok, apply_err = apply_payload(doc)
    if not ok then
      S.last_error = apply_err or "bad state"
    end
    redraw()
  end)
end

local function route_push(req)
  local body, read_err = read_request_body(req, 4096)
  if not body then
    S.last_error = read_err or "body read failed"
    redraw()
    return json_response("400 Bad Request", { ok = false, error = S.last_error })
  end
  local doc, err = safe_json_decode(body)
  if not doc then
    S.last_error = err or "json decode failed"
    redraw()
    return json_response("400 Bad Request", { ok = false, error = S.last_error })
  end
  local ok, apply_err = apply_payload(doc)
  redraw()
  if not ok then
    return json_response("400 Bad Request", { ok = false, error = apply_err })
  end
  return json_response("200 OK", state_snapshot())
end

local function route_index()
  return text_response("HW Monitor\n\nHost metrics:\nGET " .. APP.config.state_url .. "\n\nDevice state:\nGET " .. APP.ROUTE_BASE .. "/api/state\nPOST " .. APP.ROUTE_BASE .. "/api/push\n")
end

local function register_route(method, route, handler)
  if not httpd or not httpd.dynamic then
    return false, "httpd missing"
  end
  local err = httpd.dynamic(method, route, handler)
  if err then
    return false, tostring(err)
  end
  APP.routes[#APP.routes + 1] = { method = method, route = route }
  return true, nil
end

local function unregister_routes()
  if not httpd or not httpd.unregister then
    APP.routes = {}
    return
  end
  for i = #APP.routes, 1, -1 do
    local item = APP.routes[i]
    pcall(function() httpd.unregister(item.method, item.route) end)
  end
  APP.routes = {}
end

local function start_web()
  if not httpd or not httpd.start then
    S.last_error = "httpd missing"
    return
  end
  httpd.start({
    webroot = "/sd",
    auto_index = httpd.INDEX_NONE,
    max_handlers = 16,
  })

  register_route(httpd.GET, APP.ROUTE_BASE, route_index)
  register_route(httpd.GET, APP.ROUTE_BASE .. "/", route_index)
  register_route(httpd.GET, APP.ROUTE_BASE .. "/health", function() return text_response("ok") end)
  register_route(httpd.GET, APP.ROUTE_BASE .. "/api/state", function() return json_response("200 OK", state_snapshot()) end)
  register_route(httpd.POST, APP.ROUTE_BASE .. "/api/push", route_push)

  local ok, err = call_webui(true)
  if not ok then
    S.last_error = "webui " .. tostring(err or "failed")
  end
end

local function build_ui()
  local root = lv_scr_act()
  clear_root()
  call(lv_obj_set_style_bg_color, root, C.bg, MAIN_STYLE)
  call(lv_obj_set_style_bg_opa, root, 255, MAIN_STYLE)
  if lv_obj_clear_flag and rawget(_G, "LV_OBJ_FLAG_SCROLLABLE") then
    call(lv_obj_clear_flag, root, rawget(_G, "LV_OBJ_FLAG_SCROLLABLE"))
  end

  if lv_canvas_create then
    if CANVAS_FMT then
      UI.canvas = lv_canvas_create(root, APP.SCREEN_W, APP.SCREEN_H, CANVAS_FMT)
    else
      UI.canvas = lv_canvas_create(root, APP.SCREEN_W, APP.SCREEN_H)
    end
    call(lv_obj_set_pos, UI.canvas, 0, 0)
  end
end

local function start_timers()
  if not tmr or not tmr.create then
    return
  end
  local tick = tmr.create()
  APP.timers.tick = tick
  tick:alarm(APP.TICK_MS, tmr.ALARM_AUTO, function()
    if not APP.running then return end
    if app and app.exiting and app.exiting() then return end
    S.spin = (S.spin + 24) % 360
    update_online_state()
    redraw()
  end)

  local fetch = tmr.create()
  APP.timers.fetch = fetch
  fetch:alarm(APP.FETCH_MS, tmr.ALARM_AUTO, function()
    if not APP.running then return end
    if app and app.exiting and app.exiting() then return end
    fetch_state()
  end)
end

function APP.stop(reason)
  if not APP.running then return end
  APP.running = false
  for _, timer in pairs(APP.timers or {}) do
    pcall(function()
      timer:stop()
      timer:unregister()
    end)
  end
  APP.timers = {}
  unregister_routes()
  local ok, err = call_webui(false)
  if not ok then
    S.last_error = "webui " .. tostring(err or "ignored")
  end
  print("[hwmon] stop", tostring(reason or ""))
end

load_config()
build_ui()
start_web()
start_timers()
redraw()
fetch_state()
print("[hwmon] ready", APP.VERSION, APP.ROUTE_BASE)
