local APP_DIR = "/sd/apps/aida_monitor"

if file and file.exists and not file.exists(APP_DIR .. "/config.lua") then
  local candidates = {
    "/sd/apps/monitor",
    "aida_monitor/package",
    "aida_monitor",
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
  gpu_usage = nil,
  gpu_temp = nil,
  gpu_clock = nil,
  mem_usage = nil,
}

local UI = {
  canvas = nil,
  w = 320,
  h = 240,
}

local state = {
  client = nil,
  tick_timer = nil,
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

local function draw_text(cvs, x, y, w, text, color, size, align, opa)
  if not lv_canvas_draw_text then
    return
  end

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

local function redraw()
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

  draw_text(cvs, 8, 8, 190, "AIDA MONITOR", C.text, 16, ALIGN_LEFT, 255)

  draw_metric_wheel(cvs, 76, 94, "CPU", S.cpu_usage, S.cpu_temp, C.cpu)
  draw_metric_wheel(cvs, 244, 94, "GPU", S.gpu_usage, S.gpu_temp, C.gpu)
  draw_status_core(cvs, 160, 92)

  draw_clocks(cvs)
  draw_memory(cvs)
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
  S.gpu_usage = metric_value(sample, "gpu_usage")
  S.gpu_temp = metric_value(sample, "gpu_temp")
  S.gpu_clock = metric_value(sample, "gpu_clock")
  S.mem_usage = metric_value(sample, "memory_usage")
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
  S.gpu_usage = nil
  S.gpu_temp = nil
  S.gpu_clock = nil
  S.mem_usage = nil
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

  if key and key.off then
    key.off()
  end
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
redraw()
start_tick()

if AidaWeb and AidaWeb.new then
  state.web = AidaWeb.new({
    config = config,
    config_path = APP_DIR .. "/config.lua",
    route_base = (app and app.route_base and app.route_base()) or "/aida_monitor",
    restart = function()
      return state.restart_client()
    end,
  })
  state.web:start()
end

start_client()
