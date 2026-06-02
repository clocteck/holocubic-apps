local prev = rawget(_G, "RING_BAR_SPEC_APP")
if prev and prev.stop then
  pcall(function()
    prev.stop()
  end)
end

RING_BAR_SPEC_APP = {}
RING_BAR_SPEC_APP.VERSION = "2026-04-27-spectrum-v18-lua-table-bins"

local APP_STATE = RING_BAR_SPEC_APP

local root = lv_scr_act()
local function clear_root()
  if not lv_obj_clean then
    return
  end
  local ok, root_obj = pcall(function()
    return lv_scr_act()
  end)
  if not ok or not root_obj then
    return
  end
  pcall(function()
    lv_obj_clean(root_obj)
  end)
end

clear_root()

-- =========================
-- localize hot functions
-- =========================
local math_abs   = math.abs
local math_cos   = math.cos
local math_sin   = math.sin
local math_sqrt  = math.sqrt
local math_floor = math.floor
local math_ceil  = math.ceil
local pcall_fn   = pcall
local string_format = string.format
local string_sub = string.sub

local lv_canvas_create_fn     = rawget(_G, "lv_canvas_create")
local lv_canvas_begin_fn      = rawget(_G, "lv_canvas_frame_begin") or rawget(_G, "lv_canvas_begin")
local lv_canvas_end_fn        = rawget(_G, "lv_canvas_frame_end") or rawget(_G, "lv_canvas_end")
local lv_canvas_fill_bg_fn    = rawget(_G, "lv_canvas_fill_bg") or rawget(_G, "lv_canvas_fill")
local lv_canvas_draw_line_fn  = rawget(_G, "lv_canvas_draw_line")
local lv_canvas_draw_polyline_fn = rawget(_G, "lv_canvas_draw_polyline")
local lv_label_create_fn      = rawget(_G, "lv_label_create")
local lv_label_set_text_fn    = rawget(_G, "lv_label_set_text")
local lv_label_set_long_mode_fn = rawget(_G, "lv_label_set_long_mode")
local spectrum_mod            = rawget(_G, "spectrum")
local spectrum_start_fn       = spectrum_mod and spectrum_mod.start or nil
local spectrum_stop_fn        = spectrum_mod and spectrum_mod.stop or nil
local spectrum_on_fn          = spectrum_mod and spectrum_mod.on or nil
local lv_obj_set_pos_fn       = lv_obj_set_pos
local lv_obj_set_width_fn     = rawget(_G, "lv_obj_set_width")
local lv_obj_set_style_text_font_fn = rawget(_G, "lv_obj_set_style_text_font")
local lv_obj_set_style_text_color_fn = rawget(_G, "lv_obj_set_style_text_color")
local lv_obj_set_style_text_opa_fn = rawget(_G, "lv_obj_set_style_text_opa")
local lv_obj_set_style_text_align_fn = rawget(_G, "lv_obj_set_style_text_align")
local lv_obj_remove_style_all_fn = rawget(_G, "lv_obj_remove_style_all")
local lv_obj_move_foreground_fn = rawget(_G, "lv_obj_move_foreground")
local time_mod                 = rawget(_G, "time")
local time_getlocal_fn         = time_mod and time_mod.getlocal or nil
local time_settimezone_fn      = time_mod and time_mod.settimezone or nil
local rtctime_mod              = rawget(_G, "rtctime")
local rtctime_get_fn           = rtctime_mod and rtctime_mod.get or nil
local rtctime_epoch2cal_fn     = rtctime_mod and rtctime_mod.epoch2cal or nil
local os_date_fn               = os and os.date or nil
local millis_fn                = rawget(_G, "millis")
local app_mod                 = rawget(_G, "app")
local app_on_fn               = app_mod and app_mod.on or nil

-- =========================
-- constants
-- =========================
local SCREEN_W = 320
local SCREEN_H = 240

local CX = math_floor(SCREEN_W / 2)
local CY = math_floor(SCREEN_H / 2) + 15

local MAX_V = 100
local TWO_PI = math.pi * 2
local START_ANGLE = -math.pi / 2
local MAIN_STYLE = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
local VIS_MODE_RING = 1
local VIS_MODE_COLUMN = 2

-- =========================
-- tunables
-- =========================
local RING_R = 58
local BAR_START_PAD = 4
local BAR_MIN_LEN = 5
local BAR_MAX_LEN = 35

local INNER_TICK_IN = 7
local INNER_TICK_OUT = 2

local RISE_K = 0.8
local FALL_K = 0.44

local TICK_MS = 23

-- 圆环渐变拆成多个色带；每个色带优先用批量折线画
local RING_SEG_COUNT = 120
local RING_BAND_SEGMENTS = 10
local RING_OPA = 160
local TICK_OPA = 70

local CENTER_TIME_DIGIT_W = 19
local CENTER_TIME_COLON_W = 12
local CENTER_TIME_TOTAL_W = CENTER_TIME_DIGIT_W * 4 + CENTER_TIME_COLON_W
local CENTER_TIME_X = CX - math_floor(CENTER_TIME_TOTAL_W / 2)
local CENTER_TIME_RING_Y = CY - 16
local CENTER_TIME_COLUMN_Y = 12
local CENTER_TIME_FONT = rawget(_G, "LV_FONT_MONTSERRAT_28") or rawget(_G, "LV_FONT_MONTSERRAT_24")
local CENTER_TIME_D1_COLOR = 0xE8E6FF
local CENTER_TIME_D2_COLOR = 0xE8E6FF
local CENTER_TIME_COLON_COLOR = 0xE8E6FF
local CENTER_TIME_D3_COLOR = 0xE8E6FF
local CENTER_TIME_D4_COLOR = 0xE8E6FF
local CENTER_TIME_ALIGN = rawget(_G, "LV_TEXT_ALIGN_CENTER")
local LABEL_LONG_CLIP = rawget(_G, "LV_LABEL_LONG_CLIP") or rawget(_G, "LABEL_LONG_CLIP")
local LOCAL_TIMEZONE = "CST-8"
local LOCAL_TZ_OFFSET_SEC = 8 * 3600

local RING_BAR_COUNT = 64
local RING_BAR_WIDTH = 5

local COLUMN_BAR_COUNT = 60
local COLUMN_BAR_W = 4
local COLUMN_BAR_GAP = 1
local COLUMN_CHART_W = COLUMN_BAR_COUNT * COLUMN_BAR_W + (COLUMN_BAR_COUNT - 1) * COLUMN_BAR_GAP
local COLUMN_CHART_X = math_floor((SCREEN_W - COLUMN_CHART_W) / 2)
local COLUMN_CHART_TOP_Y = 72
local COLUMN_CHART_BASE_Y = 176
local COLUMN_CHART_H = COLUMN_CHART_BASE_Y - COLUMN_CHART_TOP_Y
local COLUMN_MIN_H = 3
local COLUMN_REFLECT_MAX_H = 42
local COLUMN_BASELINE_COLOR = 0x283346
local COLUMN_BASELINE_OPA = 72

local COL_BG = 0x000000
local COL_TICK = 0xC8B07A
local COL_BAR_FALLBACK = 0xFF8A4A

local BAR_INNER_R = RING_R + BAR_START_PAD

-- =========================
-- canvas
-- =========================
local canvas = lv_canvas_create_fn(root, SCREEN_W, SCREEN_H, CANVAS_FMT_TRUE_COLOR)
if lv_obj_set_pos_fn then
  lv_obj_set_pos_fn(canvas, 0, 0)
end

-- =========================
-- state tables
-- =========================
local raw_bins = {}
local group_bins = {}
local target_bins = {}
local current_bins = {}

local dir_vx = {}
local dir_vy = {}

local bar_base_x = {}
local bar_base_y = {}

local tick_x1 = {}
local tick_y1 = {}
local tick_x2 = {}
local tick_y2 = {}

local bar_col = {}

-- 圆环色带缓存
local ring_band_xs = {}
local ring_band_ys = {}
local ring_band_points = {}
local ring_band_count = {}
local ring_band_col = {}
local ring_band_total = 0

local len_lut = {}
local opa_lut = {}

local raw_count = 0
local active_count = 0
local cached_bar_width = 4
local raw_dirty = false
local force_redraw = true
local center_time_d1_label = nil
local center_time_d2_label = nil
local center_time_colon_label = nil
local center_time_d3_label = nil
local center_time_d4_label = nil
local center_time_text = nil
local center_time_colon_visible = true
local center_time_poll_ms = 1000
local center_time_y = CENTER_TIME_RING_Y
local visual_mode = VIS_MODE_RING
local key_registered_via_module = false
APP_STATE.column_peak = {}
APP_STATE.column_peak_hold = {}
APP_STATE.COLUMN_PEAK_HOLD_FRAMES = 1
APP_STATE.COLUMN_PEAK_FALL_PX = 1.8
APP_STATE.COLUMN_PEAK_OPA = 230
APP_STATE.COLUMN_FALL_K = 0.26

-- =========================
-- utils
-- =========================
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function iround(v)
  if v >= 0 then
    return math_floor(v + 0.5)
  end
  return math_ceil(v - 0.5)
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function split_rgb(c)
  local r = math_floor(c / 0x10000) % 0x100
  local g = math_floor(c / 0x100) % 0x100
  local b = c % 0x100
  return r, g, b
end

local function rgb_hex(r, g, b)
  r = clamp(math_floor(r + 0.5), 0, 255)
  g = clamp(math_floor(g + 0.5), 0, 255)
  b = clamp(math_floor(b + 0.5), 0, 255)
  return r * 0x10000 + g * 0x100 + b
end

local function lerp_color(c1, c2, t)
  local r1, g1, b1 = split_rgb(c1)
  local r2, g2, b2 = split_rgb(c2)
  return rgb_hex(
    lerp(r1, r2, t),
    lerp(g1, g2, t),
    lerp(b1, b2, t)
  )
end

local function wrap01(t)
  return t - math_floor(t)
end

local function two(v)
  v = tonumber(v) or 0
  if v < 0 then v = 0 end
  return string_format("%02d", math_floor(v) % 100)
end

local function init_time_module()
  if time_settimezone_fn then
    pcall_fn(time_settimezone_fn, LOCAL_TIMEZONE)
  end
end

local function tm_from_time_module()
  if not time_getlocal_fn then
    return nil
  end

  local ok, t = pcall_fn(time_getlocal_fn)
  if ok and type(t) == "table" and t.year and t.year >= 2024 then
    return {
      hour = t.hour or 0,
      min = t.min or 0,
    }
  end

  return nil
end

local function tm_from_rtctime()
  if not rtctime_get_fn or not rtctime_epoch2cal_fn then
    return nil
  end

  local ok_get, sec = pcall_fn(rtctime_get_fn)
  if not ok_get or type(sec) ~= "number" or sec <= 0 then
    return nil
  end

  local ok_cal, year, mon, day, hour, min = pcall_fn(rtctime_epoch2cal_fn, sec + LOCAL_TZ_OFFSET_SEC)
  if ok_cal and type(year) == "number" and year >= 2024 and type(hour) == "number" then
    return {
      hour = hour,
      min = min or 0,
    }
  end

  return nil
end

local function tm_from_os()
  if not os_date_fn then
    return nil
  end

  local ok, t = pcall_fn(os_date_fn, "*t")
  if ok and type(t) == "table" and t.year and t.year >= 2024 then
    return {
      hour = t.hour or 0,
      min = t.min or 0,
    }
  end

  return nil
end

local function tm_from_uptime()
  local ms = 0
  if millis_fn then
    local ok, v = pcall_fn(millis_fn)
    if ok and type(v) == "number" then
      ms = v
    end
  end

  local total_sec = math_floor(ms / 1000)
  return {
    hour = math_floor(total_sec / 3600) % 24,
    min = math_floor(total_sec / 60) % 60,
  }
end

local function get_local_tm()
  local t = tm_from_time_module()
  if t then return t end

  t = tm_from_rtctime()
  if t then return t end

  t = tm_from_os()
  if t then return t end

  return tm_from_uptime()
end

local function format_time_text()
  local t = get_local_tm()
  return two(t.hour) .. ":" .. two(t.min)
end

local function palette_cycle_color(palette, t)
  local n = #palette
  if n <= 0 then
    return 0xFFFFFF
  end
  if n == 1 then
    return palette[1]
  end

  local scaled = wrap01(t) * n
  local idx = math_floor(scaled) + 1
  if idx > n then
    idx = 1
  end

  local next_idx = idx + 1
  if next_idx > n then
    next_idx = 1
  end

  return lerp_color(palette[idx], palette[next_idx], scaled - math_floor(scaled))
end

local RING_PALETTE = {
  0xFCE8BE,
  0xC89A54,
  0x91BED4,
  0xEFD6A8
}

local BAR_PALETTE = {
  0xFF6A4A,
  0xFFB85C,
  0x74D4B9,
  0x6FA8FF
}

local COLUMN_PALETTE = {
  0xE83F74,
  0x1D8CFF,
  0xB45CFF
}

local function ring_gradient_color(index, total)
  if total <= 1 then
    return 0xEAD39B
  end

  return palette_cycle_color(RING_PALETTE, (index - 1) / total + 0.08)
end

local function bar_gradient_color(index, total)
  if total <= 1 then
    return COL_BAR_FALLBACK
  end

  return palette_cycle_color(BAR_PALETTE, (index - 1) / total + 0.03)
end

local function column_gradient_color(index, total)
  if total <= 1 then
    return COLUMN_PALETTE[2]
  end

  local t = (index - 1) / (total - 1)
  if t <= 0.58 then
    return lerp_color(COLUMN_PALETTE[1], COLUMN_PALETTE[2], t / 0.58)
  end

  return lerp_color(COLUMN_PALETTE[2], COLUMN_PALETTE[3], (t - 0.58) / 0.42)
end

local function desired_bar_count()
  if visual_mode == VIS_MODE_COLUMN then
    return COLUMN_BAR_COUNT
  end

  return RING_BAR_COUNT
end

local function calc_bar_width(n)
  return RING_BAR_WIDTH
end

local function approach(cur, target, rise_k, fall_k)
  local diff = target - cur
  if math_abs(diff) < 0.05 then
    return target, false
  end

  local k = diff > 0 and rise_k or fall_k
  return cur + diff * k, true
end

-- =========================
-- runtime compatibility
-- 新运行时优先用 spectrum 模块；旧固件再回退到 app.on。
-- 频谱开关若当前固件没导出，只做兼容保护避免脚本启动即报错。
-- =========================
local function runtime_event_on(name, fn)
  if spectrum_on_fn then
    if name ~= "spectrum" then
      error("Spectrum circle: unsupported event " .. tostring(name))
    end
    return spectrum_on_fn("data", function(bins, cnt, frame_id, ts_ms)
      return fn(name, bins, cnt, frame_id, ts_ms)
    end)
  end
  if app_on_fn then
    return app_on_fn(name, fn)
  end
  error("Spectrum circle: missing spectrum.on/app.on")
end

local function runtime_event_off(name)
  if spectrum_on_fn then
    if name ~= "spectrum" then
      return
    end
    return spectrum_on_fn("data", nil)
  end
  if app_on_fn then
    return app_on_fn(name, nil)
  end
end

local function set_spectrum_enabled(enable)
  if enable then
    if spectrum_start_fn then
      spectrum_start_fn()
      return true
    end
  else
    if spectrum_stop_fn then
      spectrum_stop_fn()
      return true
    end
  end

  if enable and not APP_STATE.spectrum_enable_warned then
    APP_STATE.spectrum_enable_warned = true
    if print then
      print("[Spectrum circle] spectrum.start unavailable")
    end
  end

  return false
end

-- =========================
-- precompute LUTs
-- =========================
local function build_response_lut()
  for i = 0, MAX_V do
    local v = i / MAX_V
    local shaped = math_sqrt(v)

    len_lut[i] = BAR_MIN_LEN + (BAR_MAX_LEN - BAR_MIN_LEN) * shaped

    local opa = math_floor(200 + shaped * 55 + 0.5)
    opa_lut[i] = clamp(opa, 0, 255)
  end
end

-- =========================
-- batch polyline helper
-- 当前 README_LVGL.md 里的正式接口要求 points 扁平数组：
-- {x1, y1, x2, y2, ...} + point_cnt。
-- =========================
local function draw_polyline_cached(canvas_id, points, xs, ys, count, color, opa, width, closed)
  if count == nil or count < 2 then
    return
  end

  if lv_canvas_draw_polyline_fn then
    local ok = pcall_fn(lv_canvas_draw_polyline_fn, canvas_id, points, count, color, opa, width)
    if ok then
      if closed then
        lv_canvas_draw_line_fn(canvas_id, xs[count], ys[count], xs[1], ys[1], color, opa, width)
      end
      return
    end
  end

  for i = 1, count - 1 do
    lv_canvas_draw_line_fn(
      canvas_id,
      xs[i], ys[i],
      xs[i + 1], ys[i + 1],
      color, opa, width
    )
  end

  if closed then
    lv_canvas_draw_line_fn(
      canvas_id,
      xs[count], ys[count],
      xs[1], ys[1],
      color, opa, width
    )
  end
end

-- =========================
-- precompute ring gradient bands
-- 把 120 段近似成多个色带，每个色带一条 polyline
-- =========================
local function build_ring_cache()
  ring_band_total = 0

  local seg_start = 1
  while seg_start <= RING_SEG_COUNT do
    local seg_end = seg_start + RING_BAND_SEGMENTS - 1
    if seg_end > RING_SEG_COUNT then
      seg_end = RING_SEG_COUNT
    end

    local band_idx = ring_band_total + 1
    local xs = {}
    local ys = {}
    local points = {}
    local n = 0

    -- 一个色带有 k 段线，需要 k+1 个点
    for p = seg_start, seg_end + 1 do
      local point_index = p
      if point_index > RING_SEG_COUNT then
        point_index = 1
      end

      local a = START_ANGLE + (point_index - 1) * TWO_PI / RING_SEG_COUNT
      n = n + 1
      xs[n] = iround(CX + math_cos(a) * RING_R)
      ys[n] = iround(CY + math_sin(a) * RING_R)
      points[n * 2 - 1] = xs[n]
      points[n * 2] = ys[n]
    end

    ring_band_total = band_idx
    ring_band_xs[band_idx] = xs
    ring_band_ys[band_idx] = ys
    ring_band_points[band_idx] = points
    ring_band_count[band_idx] = n
    ring_band_col[band_idx] = ring_gradient_color(
      math_floor((seg_start + seg_end) * 0.5 + 0.5),
      RING_SEG_COUNT
    )

    seg_start = seg_end + 1
  end
end

-- =========================
-- rebuild per-bar geometry when display bar count changes
-- =========================
local function rebuild_bar_geometry(n)
  local old_count = active_count
  active_count = n or 0

  cached_bar_width = calc_bar_width(active_count)

  if active_count <= 0 then
    for i = 1, old_count do
      group_bins[i] = 0
      target_bins[i] = 0
      current_bins[i] = 0
    end
    return
  end

  for i = 1, active_count do
    local angle = START_ANGLE + (i - 1) * TWO_PI / active_count
    local vx = math_cos(angle)
    local vy = math_sin(angle)

    dir_vx[i] = vx
    dir_vy[i] = vy

    bar_col[i] = bar_gradient_color(i, active_count)

    bar_base_x[i] = iround(CX + vx * BAR_INNER_R)
    bar_base_y[i] = iround(CY + vy * BAR_INNER_R)

    tick_x1[i] = iround(CX + vx * (RING_R - INNER_TICK_IN))
    tick_y1[i] = iround(CY + vy * (RING_R - INNER_TICK_IN))
    tick_x2[i] = iround(CX + vx * (RING_R - INNER_TICK_OUT))
    tick_y2[i] = iround(CY + vy * (RING_R - INNER_TICK_OUT))

    if current_bins[i] == nil then current_bins[i] = 0 end
    if target_bins[i] == nil then target_bins[i] = 0 end
    if group_bins[i] == nil then group_bins[i] = 0 end
  end

  if old_count > active_count then
    for i = active_count + 1, old_count do
      group_bins[i] = 0
      target_bins[i] = 0
      current_bins[i] = 0
    end
  end
end

-- =========================
-- spectrum data path
-- 事件里只拷贝原始桶值，不做平滑
-- =========================
local function copy_raw_bins(bins, cnt)
  local n = cnt or 0
  if n < 0 then n = 0 end
  if n > RING_BAR_COUNT then n = RING_BAR_COUNT end

  raw_count = n

  local want_count = desired_bar_count()
  if want_count ~= active_count then
    rebuild_bar_geometry(want_count)
    force_redraw = true
  end

  for i = 1, RING_BAR_COUNT do
    if i <= raw_count and bins then
      raw_bins[i] = clamp(bins[i] or 0, 0, MAX_V)
    else
      raw_bins[i] = 0
    end
  end

  raw_dirty = true
end

local function rebuild_targets_from_raw()
  if active_count <= 0 then
    return
  end

  -- 固定桶映射：圆环取前 64 桶，柱状取前 60 桶，少于目标数量时补 0。
  for i = 1, active_count do
    group_bins[i] = raw_bins[i] or 0
  end

  if active_count == 1 then
    target_bins[1] = group_bins[1] or 0
    return
  end

  -- 轻微横向平滑
  for i = 1, active_count do
    local ip = i - 1
    if ip < 1 then ip = active_count end

    local inext = i + 1
    if inext > active_count then inext = 1 end

    target_bins[i] =
      group_bins[ip] * 0.05 +
      group_bins[i] * 0.9 +
      group_bins[inext] * 0.05
  end
end

local function step_animation()
  local changed = false
  local fall_k = (visual_mode == VIS_MODE_COLUMN) and APP_STATE.COLUMN_FALL_K or FALL_K

  for i = 1, active_count do
    local nv, moved = approach(
      current_bins[i] or 0,
      target_bins[i] or 0,
      RISE_K,
      fall_k
    )
    current_bins[i] = nv
    if moved then
      changed = true
    end
  end

  return changed
end

-- =========================
-- drawing
-- =========================
local function frame_begin(id)
  if lv_canvas_begin_fn and lv_canvas_end_fn then
    local ok = pcall_fn(function()
      lv_canvas_begin_fn(id)
    end)
    return ok
  end
  return false
end

local function frame_end(id, explicit_frame)
  if explicit_frame and lv_canvas_end_fn then
    pcall_fn(function()
      lv_canvas_end_fn(id)
    end)
  end
end

local function set_label_text(id, text)
  if id and lv_label_set_text_fn then
    pcall_fn(function()
      lv_label_set_text_fn(id, tostring(text or ""))
    end)
  end
end

local function create_time_part_label(x, width, color, align)
  local id = lv_label_create_fn(root)

  if lv_obj_remove_style_all_fn then
    pcall_fn(function() lv_obj_remove_style_all_fn(id) end)
  end

  if lv_obj_set_pos_fn then
    lv_obj_set_pos_fn(id, x, center_time_y)
  end
  if lv_obj_set_width_fn then
    lv_obj_set_width_fn(id, width)
  end
  if CENTER_TIME_FONT and lv_obj_set_style_text_font_fn then
    lv_obj_set_style_text_font_fn(id, CENTER_TIME_FONT, MAIN_STYLE)
  end
  if lv_obj_set_style_text_color_fn then
    lv_obj_set_style_text_color_fn(id, color, MAIN_STYLE)
  end
  if lv_obj_set_style_text_opa_fn then
    lv_obj_set_style_text_opa_fn(id, 250, MAIN_STYLE)
  end
  if align and lv_obj_set_style_text_align_fn then
    lv_obj_set_style_text_align_fn(id, align, MAIN_STYLE)
  end
  if LABEL_LONG_CLIP and lv_label_set_long_mode_fn then
    pcall_fn(function() lv_label_set_long_mode_fn(id, LABEL_LONG_CLIP) end)
  end
  if lv_obj_move_foreground_fn then
    pcall_fn(function() lv_obj_move_foreground_fn(id) end)
  end

  return id
end

local function position_center_time_labels()
  if not lv_obj_set_pos_fn then
    return
  end

  if center_time_d1_label then
    lv_obj_set_pos_fn(center_time_d1_label, CENTER_TIME_X, center_time_y)
  end
  if center_time_d2_label then
    lv_obj_set_pos_fn(center_time_d2_label, CENTER_TIME_X + CENTER_TIME_DIGIT_W, center_time_y)
  end
  if center_time_colon_label then
    lv_obj_set_pos_fn(center_time_colon_label, CENTER_TIME_X + CENTER_TIME_DIGIT_W * 2, center_time_y)
  end
  if center_time_d3_label then
    lv_obj_set_pos_fn(center_time_d3_label, CENTER_TIME_X + CENTER_TIME_DIGIT_W * 2 + CENTER_TIME_COLON_W, center_time_y)
  end
  if center_time_d4_label then
    lv_obj_set_pos_fn(center_time_d4_label, CENTER_TIME_X + CENTER_TIME_DIGIT_W * 3 + CENTER_TIME_COLON_W, center_time_y)
  end
end

local function set_center_time_text(text, colon_visible)
  text = tostring(text or "--:--")
  set_label_text(center_time_d1_label, string_sub(text, 1, 1))
  set_label_text(center_time_d2_label, string_sub(text, 2, 2))
  set_label_text(center_time_colon_label, colon_visible and ":" or " ")
  set_label_text(center_time_d3_label, string_sub(text, 4, 4))
  set_label_text(center_time_d4_label, string_sub(text, 5, 5))
end

local function create_center_time_label()
  if not lv_label_create_fn then
    return
  end

  center_time_d1_label = create_time_part_label(
    CENTER_TIME_X,
    CENTER_TIME_DIGIT_W,
    CENTER_TIME_D1_COLOR,
    CENTER_TIME_ALIGN
  )
  center_time_d2_label = create_time_part_label(
    CENTER_TIME_X + CENTER_TIME_DIGIT_W,
    CENTER_TIME_DIGIT_W,
    CENTER_TIME_D2_COLOR,
    CENTER_TIME_ALIGN
  )
  center_time_colon_label = create_time_part_label(
    CENTER_TIME_X + CENTER_TIME_DIGIT_W * 2,
    CENTER_TIME_COLON_W,
    CENTER_TIME_COLON_COLOR,
    CENTER_TIME_ALIGN
  )
  center_time_d3_label = create_time_part_label(
    CENTER_TIME_X + CENTER_TIME_DIGIT_W * 2 + CENTER_TIME_COLON_W,
    CENTER_TIME_DIGIT_W,
    CENTER_TIME_D3_COLOR,
    CENTER_TIME_ALIGN
  )
  center_time_d4_label = create_time_part_label(
    CENTER_TIME_X + CENTER_TIME_DIGIT_W * 3 + CENTER_TIME_COLON_W,
    CENTER_TIME_DIGIT_W,
    CENTER_TIME_D4_COLOR,
    CENTER_TIME_ALIGN
  )

  set_center_time_text("--:--", true)
end

local function update_center_time(force)
  if not center_time_d1_label then
    return
  end
  if visual_mode == VIS_MODE_COLUMN then
    return
  end

  if not force then
    center_time_poll_ms = center_time_poll_ms + TICK_MS
    if center_time_poll_ms < 1000 then
      return
    end
    center_time_colon_visible = not center_time_colon_visible
  else
    center_time_colon_visible = true
  end
  center_time_poll_ms = 0

  local text = format_time_text()
  if force or text ~= center_time_text then
    center_time_text = text
  end
  set_center_time_text(center_time_text or text, center_time_colon_visible)
end

APP_STATE.set_center_time_visible = function(visible)
  local add_flag = rawget(_G, "lv_obj_add_flag")
  local clear_flag = rawget(_G, "lv_obj_clear_flag")
  local hidden_flag = rawget(_G, "LV_OBJ_FLAG_HIDDEN")

  local function apply(id)
    if not id then
      return
    end

    if add_flag and clear_flag and hidden_flag then
      if visible then
        pcall_fn(function() clear_flag(id, hidden_flag) end)
      else
        pcall_fn(function() add_flag(id, hidden_flag) end)
      end
    elseif not visible then
      set_label_text(id, "")
    end
  end

  apply(center_time_d1_label)
  apply(center_time_d2_label)
  apply(center_time_colon_label)
  apply(center_time_d3_label)
  apply(center_time_d4_label)

  if visible then
    update_center_time(true)
  end
end

local function draw_base_ring()
  -- 渐变圆环：优先走批量折线
  for i = 1, ring_band_total do
    draw_polyline_cached(
      canvas,
      ring_band_points[i],
      ring_band_xs[i],
      ring_band_ys[i],
      ring_band_count[i],
      ring_band_col[i],
      RING_OPA,
      2,
      false
    )
  end

  -- 内圈刻度
  for i = 1, active_count do
    lv_canvas_draw_line_fn(
      canvas,
      tick_x1[i], tick_y1[i],
      tick_x2[i], tick_y2[i],
      COL_TICK,
      TICK_OPA,
      1
    )
  end
end

-- 宽线 bar：这是这版最大优化点
local function draw_radial_bar(i, len, opa)
  if len <= 0 then
    return
  end

  local x1 = bar_base_x[i]
  local y1 = bar_base_y[i]
  local x2 = iround(x1 + dir_vx[i] * len)
  local y2 = iround(y1 + dir_vy[i] * len)

  lv_canvas_draw_line_fn(
    canvas,
    x1, y1,
    x2, y2,
    bar_col[i] or COL_BAR_FALLBACK,
    opa,
    cached_bar_width
  )
end

local function draw_column_spectrum()
  lv_canvas_draw_line_fn(
    canvas,
    COLUMN_CHART_X,
    COLUMN_CHART_BASE_Y + 1,
    COLUMN_CHART_X + COLUMN_CHART_W,
    COLUMN_CHART_BASE_Y + 1,
    COLUMN_BASELINE_COLOR,
    COLUMN_BASELINE_OPA,
    1
  )

  if active_count <= 0 then
    return
  end

  for i = 1, active_count do
    local v = current_bins[i] or 0
    local idx = clamp(math_floor(v + 0.5), 0, MAX_V)
    local shaped = math_sqrt(idx / MAX_V)
    local h = math_floor(COLUMN_MIN_H + (COLUMN_CHART_H - COLUMN_MIN_H) * shaped + 0.5)
    local x = COLUMN_CHART_X + math_floor(COLUMN_BAR_W * 0.5) + (i - 1) * (COLUMN_BAR_W + COLUMN_BAR_GAP)
    local color = column_gradient_color(i, active_count)
    local opa = opa_lut[idx] or 220
    local peak = APP_STATE.column_peak[i] or 0
    local hold = APP_STATE.column_peak_hold[i] or 0

    if h >= peak then
      peak = h
      hold = APP_STATE.COLUMN_PEAK_HOLD_FRAMES
    elseif hold > 0 then
      hold = hold - 1
    else
      peak = peak - APP_STATE.COLUMN_PEAK_FALL_PX
      if peak < h then
        peak = h
      end
    end

    APP_STATE.column_peak[i] = peak
    APP_STATE.column_peak_hold[i] = hold

    lv_canvas_draw_line_fn(
      canvas,
      x,
      COLUMN_CHART_BASE_Y,
      x,
      COLUMN_CHART_BASE_Y - h,
      color,
      opa,
      COLUMN_BAR_W
    )

    local reflect_h = math_floor(h * 0.34 + 0.5)
    if reflect_h > COLUMN_REFLECT_MAX_H then
      reflect_h = COLUMN_REFLECT_MAX_H
    end
    if reflect_h > 1 then
      lv_canvas_draw_line_fn(
        canvas,
        x,
        COLUMN_CHART_BASE_Y + 3,
        x,
        COLUMN_CHART_BASE_Y + 3 + reflect_h,
        color,
        math_floor(opa * 0.22 + 0.5),
        COLUMN_BAR_W
      )
    end

    local peak_y = COLUMN_CHART_BASE_Y - iround(peak)
    local cap_half = math_floor(COLUMN_BAR_W * 0.5)
    lv_canvas_draw_line_fn(
      canvas,
      x - 1,
      peak_y,
      x + 2,
      peak_y,
      color,
      APP_STATE.COLUMN_PEAK_OPA,
      2
    )
  end
end

local function redraw()
  local explicit_frame = frame_begin(canvas)

  if lv_canvas_fill_bg_fn then
    lv_canvas_fill_bg_fn(canvas, COL_BG, 255)
  end

  if visual_mode == VIS_MODE_COLUMN then
    draw_column_spectrum()
  else
    draw_base_ring()

    for i = 1, active_count do
      local v = current_bins[i] or 0
      local idx = clamp(math_floor(v + 0.5), 0, MAX_V)
      draw_radial_bar(i, len_lut[idx], opa_lut[idx])
    end
  end

  frame_end(canvas, explicit_frame)
end

-- =========================
-- frame processing
-- =========================
local function process_frame(force_draw)
  update_center_time(false)

  if raw_dirty then
    rebuild_targets_from_raw()
    raw_dirty = false
    force_draw = true
  end

  local changed = step_animation()

  if force_draw or changed then
    redraw()
    return true
  end

  return false
end

APP_STATE.set_visual_mode = function(mode)
  if mode ~= VIS_MODE_RING and mode ~= VIS_MODE_COLUMN then
    return
  end
  if visual_mode == mode then
    return
  end

  visual_mode = mode
  rebuild_bar_geometry(desired_bar_count())
  rebuild_targets_from_raw()
  center_time_y = (visual_mode == VIS_MODE_COLUMN) and CENTER_TIME_COLUMN_Y or CENTER_TIME_RING_Y
  position_center_time_labels()
  APP_STATE.set_center_time_visible(visual_mode ~= VIS_MODE_COLUMN)
  force_redraw = false
  redraw()
end

APP_STATE.toggle_visual_mode = function()
  if visual_mode == VIS_MODE_COLUMN then
    APP_STATE.set_visual_mode(VIS_MODE_RING)
  else
    APP_STATE.set_visual_mode(VIS_MODE_COLUMN)
  end
end

APP_STATE.is_long_start = function(evt_type)
  return evt_type == key.LONG_START
end

APP_STATE.is_left_or_right = function(evt_code)
  return evt_code == key.LEFT or evt_code == key.RIGHT
end

APP_STATE.register_mode_key_handlers = function()
  key.on(key.LEFT, function(evt_type, ts_ms)
    if APP_STATE.is_long_start(evt_type) then
      APP_STATE.toggle_visual_mode()
    end
  end)
  key.on(key.RIGHT, function(evt_type, ts_ms)
    if APP_STATE.is_long_start(evt_type) then
      APP_STATE.toggle_visual_mode()
    end
  end)
  key_registered_via_module = true
end

APP_STATE.unregister_mode_key_handlers = function()
  if key_registered_via_module then
    pcall_fn(function() key.off(key.LEFT) end)
    pcall_fn(function() key.off(key.RIGHT) end)
    key_registered_via_module = false
  end
end

-- =========================
-- init
-- =========================
build_response_lut()
build_ring_cache()
rebuild_bar_geometry(desired_bar_count())
init_time_module()
create_center_time_label()
update_center_time(true)
redraw()
APP_STATE.register_mode_key_handlers()

set_spectrum_enabled(true)

runtime_event_on("spectrum", function(name, bins, cnt, frame_id, ts_ms)
  if _G.RING_BAR_SPEC_APP ~= APP_STATE then
    return
  end

  copy_raw_bins(bins, cnt)

  if not APP_STATE.timer then
    local force = force_redraw
    force_redraw = false
    process_frame(force)
  end
end)

if tmr and tmr.create then
  APP_STATE.timer = tmr.create()
  APP_STATE.timer:alarm(TICK_MS, tmr.ALARM_AUTO, function()
    if _G.RING_BAR_SPEC_APP ~= APP_STATE then
      return
    end

    local force = force_redraw
    force_redraw = false
    process_frame(force)
  end)
end

APP_STATE.stop = function()
  if APP_STATE.timer then
    pcall_fn(function() APP_STATE.timer:stop() end)
    pcall_fn(function() APP_STATE.timer:unregister() end)
    APP_STATE.timer = nil
  end

  pcall_fn(function()
    APP_STATE.unregister_mode_key_handlers()
  end)

  pcall_fn(function()
    runtime_event_off("spectrum")
  end)

  pcall_fn(function()
    set_spectrum_enabled(false)
  end)
end
