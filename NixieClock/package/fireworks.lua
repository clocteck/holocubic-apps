-- Fireworks Clock 烟花时钟
-- Integrated as NixieClock face 9. Original app by community member sk:
-- https://github.com/yizhengzhang1/holocubic-apps/tree/main/fireworks_clock
-- 黑底大字时钟 + 持续绽放的烟花粒子；整点齐射报时，按方向键手动放一发，
-- 摇晃机身来一排齐射，爆炸瞬间机身 RGB LED 随烟花色闪烁。
-- 渲染：单张全屏 canvas 立即模式逐帧重绘（同 MatrixRain/Spectrum 的做法）。

local previous = rawget(_G, "FIREWORKS_CLOCK_APP")
if previous and previous.stop then
  pcall(function() previous.stop("reload") end)
end

local APP = {
  VERSION = "0.13.0",
  APP_DIR = "/sd/apps/NixieClock",
  running = true,
  timers = {},
  font_handles = {},
  state = {},
}
_G.FIREWORKS_CLOCK_APP = APP

-- ---------------------------------------------------------------- locals
local pcall_fn = pcall
local math_floor = math.floor
local math_random = math.random
local math_cos = math.cos
local math_sin = math.sin
local math_abs = math.abs
local math_pi = math.pi
local string_format = string.format

local lv_scr_act_fn = rawget(_G, "lv_scr_act")
local lv_obj_clean_fn = rawget(_G, "lv_obj_clean")
local lv_obj_set_pos_fn = rawget(_G, "lv_obj_set_pos")
local lv_obj_invalidate_fn = rawget(_G, "lv_obj_invalidate")
local lv_canvas_create_fn = rawget(_G, "lv_canvas_create")
local lv_canvas_begin_fn = rawget(_G, "lv_canvas_frame_begin") or rawget(_G, "lv_canvas_begin")
local lv_canvas_end_fn = rawget(_G, "lv_canvas_frame_end") or rawget(_G, "lv_canvas_end")
local lv_canvas_fill_fn = rawget(_G, "lv_canvas_fill_bg") or rawget(_G, "lv_canvas_fill")
local lv_canvas_line_fn = rawget(_G, "lv_canvas_draw_line")
local lv_canvas_rect_fn = rawget(_G, "lv_canvas_draw_rect")
local lv_canvas_text_fn = rawget(_G, "lv_canvas_draw_text")
local lv_font_load_fn = rawget(_G, "lv_font_load")
local lv_font_free_fn = rawget(_G, "lv_font_free")

local CANVAS_FMT = rawget(_G, "LV_IMG_CF_TRUE_COLOR") or rawget(_G, "CANVAS_FMT_TRUE_COLOR")
local ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1

local SCREEN_W, SCREEN_H = 320, 240
local TICK_MS = 33
local MAX_PENDING_LAUNCHES = 12
local HOURLY_BURST_SEQUENCE = {
  "rapidfire", "multibreak", "comet", "spinner", "chrysanthemum",
}
local SHAKE_BURST_SEQUENCE = { "spinner", "rapidfire", "peony" }

-- ---------------------------------------------------------------- colors
local C = {
  bg = 0x000000,
  clock = 0xFFF3DC,
  date = 0x8FA6BC,
  bar_track = 0x14212C,
  bar_fill = 0x59FFE2,
}

-- 每组烟花一个双色调（core 起爆亮色 / body 主体色）
local PALETTES = {
  { core = 0xFFF6C8, body = 0xFFC24D }, -- 金
  { core = 0xD8FFF6, body = 0x4DE8FF }, -- 青
  { core = 0xFFE0F4, body = 0xFF5FD0 }, -- 品红
  { core = 0xE8FFDC, body = 0x8CFF5A }, -- 黄绿
  { core = 0xE0E8FF, body = 0x6E8CFF }, -- 蓝紫
  { core = 0xFFF0DC, body = 0xFF7A48 }, -- 橙红
}
local COMET_PALETTE = { core = 0xFFFFFF, body = 0xFFD06A }
local GOLD_TRAIL_PALETTE = { core = 0xFFFFFF, body = 0xFFC24D }
local COMET_ASCENT_COLORS = {
  0xFFFFFF, 0xFFF0D2, 0xFFC66E, 0xFF8238,
}

local function lerp_channel(a, b, t)
  return math_floor(a + (b - a) * t + 0.5)
end

local function lerp_color(c1, c2, t)
  local r = lerp_channel(math_floor(c1 / 65536) % 256, math_floor(c2 / 65536) % 256, t)
  local g = lerp_channel(math_floor(c1 / 256) % 256, math_floor(c2 / 256) % 256, t)
  local b = lerp_channel(c1 % 256, c2 % 256, t)
  return r * 65536 + g * 256 + b
end

-- 预计算尾段渐暗色，避免满屏粒子时每帧重复做 RGB 插值。
local FADE_COLOR_STEPS = 8
local BODY_FADE_COLORS = {}
for i = 1, #PALETTES do
  local body = PALETTES[i].body
  if not BODY_FADE_COLORS[body] then
    local levels = {}
    for step = 0, FADE_COLOR_STEPS - 1 do
      levels[step + 1] = lerp_color(body, C.bg,
        (step / (FADE_COLOR_STEPS - 1)) * 0.65)
    end
    BODY_FADE_COLORS[body] = levels
  end
end

local function faded_body_color(body, fade)
  if fade < 0 then fade = 0 elseif fade > 1 then fade = 1 end
  local levels = BODY_FADE_COLORS[body]
  if not levels then return lerp_color(body, C.bg, fade * 0.65) end
  local index = math_floor(fade * (FADE_COLOR_STEPS - 1) + 0.5) + 1
  return levels[index]
end

-- ---------------------------------------------------------------- state
local st = APP.state
st.frame = 0
st.rockets = {}
st.sparks = {}
st.spark_pool = {}
st.rocket_pool = {}
st.pending_launches = {}
st.secondary_bursts = {}
st.secondary_pool = {}
st.reserved_sparks = 0
st.secondary_pop_count = 0
st.reservation_errors = 0
st.burst_counts = {}
st.last_burst_kind = nil
st.next_auto_launch = 30
st.led_off_frame = -1
st.led_on = false
st.clock_valid = false
st.clock_hhmm = "--:--"
st.clock_date = ""
st.clock_sec = 0
st.last_time_query_frame = -100
st.last_sec = -1
st.wall_highwater = nil
st.last_seen_hour_key = nil
st.last_hourly_key = nil
st.last_ntp_retry_frame = -10000
st.shake_cooldown_until = 0
st.imu_last_roll = nil
st.imu_last_pitch = nil
st.imu_armed = true
st.imu_calm_samples = 0
st.imu_spike_count = 0
st.imu_last_spike_ms = 0
st.rect_mode = 0
st.language = "zh-CN"

-- ---------------------------------------------------------------- helpers
local function warn(...)
  pcall_fn(print, "[fireworks_clock]", ...)
end

local function seed_random()
  local seed = nil
  local millis_fn = rawget(_G, "millis")
  if millis_fn then
    local ok, value = pcall_fn(millis_fn)
    if ok and type(value) == "number" then seed = value end
  end
  local tmr_mod = rawget(_G, "tmr")
  if not seed and tmr_mod and tmr_mod.now then
    local ok, value = pcall_fn(tmr_mod.now)
    if ok and type(value) == "number" then seed = value end
  end
  if seed then
    pcall_fn(math.randomseed, seed)
    math_random(); math_random(); math_random()
  end
end

local function queue_launch(delay_frames, ttl_frames, burst_kind, rapidfire_member, rapidfire_index)
  if #st.pending_launches >= MAX_PENDING_LAUNCHES then return false end
  local delay = math.max(0, tonumber(delay_frames) or 0)
  local ttl = math.max(30, tonumber(ttl_frames) or 180)
  local due = st.frame + delay
  st.pending_launches[#st.pending_launches + 1] = {
    due = due,
    expires = due + ttl,
    burst_kind = burst_kind,
    rapidfire_member = rapidfire_member == true,
    rapidfire_index = tonumber(rapidfire_index) or 0,
  }
  return true
end

-- ---------------------------------------------------------------- time
local function load_preferences()
  local tz = "CST-8"
  local language = "zh-CN"
  local host = rawget(_G, "HOLO_TIME_APP")
  if host and host.state then
    tz = tostring(host.state.timezone or tz)
    language = tostring(host.state.language or language)
  end
  local codec = rawget(_G, "sjson") or rawget(_G, "json")
  local file_mod = rawget(_G, "file")
  if file_mod and file_mod.getcontents and codec then
    local ok_read, raw = pcall_fn(file_mod.getcontents, "/sd/apps/settings.json")
    if ok_read and type(raw) == "string" and #raw > 0 then
      local ok, cfg = pcall_fn(codec.decode, raw)
      if ok and type(cfg) == "table" and type(cfg.timezone) == "string" and #cfg.timezone > 0 then
        tz = cfg.timezone
      end
      if ok and type(cfg) == "table" then
        language = tostring(cfg.language or cfg.lang or language)
      end
    end
  end
  return tz, language
end

local function ensure_ntp()
  local time_mod = rawget(_G, "time")
  if not time_mod then return false end
  if time_mod.ntpenabled then
    local ok, enabled = pcall_fn(time_mod.ntpenabled)
    if ok and enabled then return true end
  end
  if time_mod.initntp then
    local ok = pcall_fn(time_mod.initntp, "ntp.aliyun.com")
    if ok then
      st.last_ntp_retry_frame = st.frame
      return true
    end
  end
  return false
end

local function init_time()
  local time_mod = rawget(_G, "time")
  if not time_mod then return end
  if time_mod.settimezone then pcall_fn(time_mod.settimezone, st.timezone) end
  ensure_ntp()
end

local function local_time()
  local time_mod = rawget(_G, "time")
  if time_mod and time_mod.getlocal then
    local ok, value = pcall_fn(time_mod.getlocal)
    if ok and type(value) == "table" and tonumber(value.year) and tonumber(value.year) >= 2024 then
      return value, true
    end
  end
  if os and os.date then
    local ok, value = pcall_fn(os.date, "*t")
    if ok and type(value) == "table" and tonumber(value.year) and tonumber(value.year) >= 2024 then
      return value, true
    end
  end
  return nil, false
end

local WEEKDAYS = {
  en = { "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" },
  zh_cn = { "周日", "周一", "周二", "周三", "周四", "周五", "周六" },
  zh_tw = { "週日", "週一", "週二", "週三", "週四", "週五", "週六" },
  ja = { "日", "月", "火", "水", "木", "金", "土" },
}

local function current_language()
  local host = rawget(_G, "HOLO_TIME_APP")
  local value = host and host.state and host.state.language or st.language
  value = tostring(value or "zh-CN"):lower():gsub("_", "-")
  st.language = value
  return value
end

local function weekday_label(index)
  local language = current_language()
  local labels = language:match("^en") and WEEKDAYS.en
    or language:match("^ja") and WEEKDAYS.ja
    or (language == "zh-tw" or language == "zh-hk" or language == "zh-mo") and WEEKDAYS.zh_tw
    or WEEKDAYS.zh_cn
  return labels[index] or ""
end

-- Zeller：wday 缺失时兜底
local function weekday_of(y, m, d)
  if m < 3 then y = y - 1; m = m + 12 end
  local k = y % 100
  local j = math_floor(y / 100)
  local h = (d + math_floor(13 * (m + 1) / 5) + k + math_floor(k / 4) + math_floor(j / 4) + 5 * j) % 7
  return ((h + 6) % 7) + 1 -- 1 = SUN
end

local function wall_stamp(t)
  local y = tonumber(t.year) or 0
  local mon = tonumber(t.mon) or 0
  local day = tonumber(t.day) or 0
  local hour = tonumber(t.hour) or 0
  local min = tonumber(t.min) or 0
  local sec = tonumber(t.sec) or 0
  return (((((y * 100 + mon) * 100 + day) * 100 + hour) * 100 + min) * 100 + sec)
end

local function refresh_clock()
  local t, valid = local_time()
  st.clock_valid = valid
  if not t then
    st.clock_hhmm = "--:--"
    st.clock_date = "waiting for time sync"
    st.clock_sec = 0
    -- NTP 重试节流 30s
    if st.frame - st.last_ntp_retry_frame > math_floor(30000 / TICK_MS) then
      st.last_ntp_retry_frame = st.frame
      ensure_ntp()
    end
    return
  end
  local sec = tonumber(t.sec) or 0
  if sec ~= st.last_sec then
    st.last_sec = sec
    st.clock_sec = sec
    st.clock_hhmm = string_format("%02d:%02d", tonumber(t.hour) or 0, tonumber(t.min) or 0)
    local wday = tonumber(t.wday)
    if not wday or wday < 1 or wday > 7 then
      wday = weekday_of(tonumber(t.year) or 2026, tonumber(t.mon) or 1, tonumber(t.day) or 1)
    end
    st.clock_date = string_format("%04d-%02d-%02d  %s",
      tonumber(t.year) or 0, tonumber(t.mon) or 0, tonumber(t.day) or 0, weekday_label(wday))
    -- 整点齐射报时：按“日期+小时”去重；时间回拨只更新显示，不重复报时。
    local hour = tonumber(t.hour) or 0
    local hour_key = string_format("%04d-%02d-%02d-%02d",
      tonumber(t.year) or 0, tonumber(t.mon) or 0, tonumber(t.day) or 0, hour)
    local stamp = wall_stamp(t)
    local forward = st.wall_highwater == nil or stamp > st.wall_highwater
    local current_min = tonumber(t.min) or 0
    local crossed_hour = forward and current_min == 0
      and st.last_seen_hour_key ~= nil and hour_key ~= st.last_seen_hour_key
    local first_sample_at_boundary = st.last_seen_hour_key == nil and current_min == 0 and sec <= 5
    if forward and (crossed_hour or first_sample_at_boundary) and st.last_hourly_key ~= hour_key then
      st.last_hourly_key = hour_key
      for i = 0, 4 do
        queue_launch(i * 16, 240, HOURLY_BURST_SEQUENCE[i + 1])
      end
    end
    if forward then
      st.wall_highwater = stamp
      st.last_seen_hour_key = hour_key
    end
  end
end

-- ---------------------------------------------------------------- canvas
local function frame_begin()
  if not (lv_canvas_begin_fn and lv_canvas_end_fn and APP.canvas) then return false end
  return pcall_fn(lv_canvas_begin_fn, APP.canvas) and true or false
end

local function frame_end(explicit)
  if explicit and lv_canvas_end_fn then
    pcall_fn(lv_canvas_end_fn, APP.canvas)
    return
  end
  if lv_obj_invalidate_fn and APP.canvas then
    pcall_fn(lv_obj_invalidate_fn, APP.canvas)
  end
end

local rect_dsc = { bg_color = 0, bg_opa = 255, radius = 0, border_width = 0 }

local function detect_rect_mode()
  if not lv_canvas_rect_fn or not APP.canvas then return end
  rect_dsc.bg_color = C.bg
  rect_dsc.bg_opa = 1
  if pcall_fn(lv_canvas_rect_fn, APP.canvas, 0, 0, 1, 1, rect_dsc) then
    st.rect_mode = 1
  elseif pcall_fn(lv_canvas_rect_fn, APP.canvas, 0, 0, 1, 1, C.bg, 1) then
    st.rect_mode = 2
  end
end

local function draw_rect(x, y, w, h, color, opa, radius)
  if st.rect_mode == 1 then
    rect_dsc.bg_color = color
    rect_dsc.bg_opa = opa
    rect_dsc.radius = radius or 0
    lv_canvas_rect_fn(APP.canvas, x, y, w, h, rect_dsc)
  elseif st.rect_mode == 2 then
    lv_canvas_rect_fn(APP.canvas, x, y, w, h, color, opa)
  end
end

local text_dsc = { color = 0xFFFFFF, opa = 255, align = ALIGN_CENTER, font_size = 14, font_handle = nil }

local function draw_text(x, y, w, value, font, color, opa)
  if not lv_canvas_text_fn then return end
  text_dsc.color = color
  text_dsc.opa = opa or 255
  text_dsc.align = ALIGN_CENTER
  text_dsc.font_handle = font
  pcall_fn(lv_canvas_text_fn, APP.canvas, math_floor(x), math_floor(y), math_floor(w), value, text_dsc)
end

-- ---------------------------------------------------------------- fireworks
local MAX_SPARKS = 150
local MAX_ROCKETS = 5
local MAX_SECONDARY_BURSTS = 8
local GRAVITY = 0.055
local ROCKET_ASCENT_GRAVITY = GRAVITY * 0.8
local SPINNER_ASCENT_GRAVITY = 0.028
local SPINNER_TRAIL_STEPS = 14
local SPINNER_HEAD_RADIUS = 2
local SPINNER_HEAD_WIDTH = 2
local COMET_ASCENT_TRAIL_STEPS = 26
local COMET_HEAD_RADIUS = 3
local COMET_HEAD_WIDTH = 3
local STANDARD_TRAIL_STEPS = 7

local TYPE_PEONY = 1
local TYPE_CHRYSANTHEMUM = 2
local TYPE_WILLOW = 3
local TYPE_STROBE = 4
local TYPE_SPINNER = 5
local TYPE_RAPIDFIRE = 6
local TYPE_MULTIBREAK = 7
local TYPE_COMET = 8
local TYPE_WATERFALL = 9
local TYPE_BROCADE_CROWN = 10

local BURST_NAMES = {
  "peony",
  "chrysanthemum",
  "willow",
  "strobe",
  "spinner",
  "rapidfire",
  "multibreak",
  "comet",
  "waterfall",
  "brocade_crown",
}
local BURST_IDS = {}
for i = 1, #BURST_NAMES do BURST_IDS[BURST_NAMES[i]] = i end

-- 每种类型的固定粒子成本；火箭升空时先预留，保证复杂图案不会只画出半边。
local BURST_BUDGETS = { 34, 38, 20, 26, 24, 16, 52, 10, 30, 32 }
local BURST_WEIGHTS = { 15, 13, 10, 9, 10, 10, 9, 8, 8, 8 }
local TOTAL_BURST_WEIGHT = 0
for i = 1, #BURST_WEIGHTS do
  TOTAL_BURST_WEIGHT = TOTAL_BURST_WEIGHT + BURST_WEIGHTS[i]
end

APP.BURST_TYPES = BURST_NAMES
APP.BURST_TYPE_IDS = BURST_IDS

local DRAW_TRAIL = 0
local DRAW_STROBE = 1
local DRAW_BROCADE_CROWN = 2
local SPARK_TRAIL_SEGMENTS = 4

-- 固定样式表只在爆炸生成时读取；每粒子保存数值字段，更新和绘制热路径不查表。
local STYLE_PEONY = {
  drag = 0.972, gravity = GRAVITY, trail = 4.6, width = 2,
  fade_start = 0.72, twinkle_period = 7, draw_mode = DRAW_TRAIL,
}
local STYLE_CHRYSANTHEMUM = {
  drag = 0.978, gravity = 0.050, trail = 4.2, width = 2,
  fade_start = 0.74, twinkle_period = 7, draw_mode = DRAW_TRAIL,
}
local STYLE_WILLOW = {
  drag = 0.987, gravity = 0.078, trail = 5.5, width = 2,
  fade_start = 0.68, twinkle_period = 5, draw_mode = DRAW_TRAIL,
}
local STYLE_STROBE = {
  drag = 0.976, gravity = 0.045, trail = 3.4, width = 2,
  fade_start = 0.82, twinkle_period = 6, draw_mode = DRAW_STROBE,
}
local STYLE_SPINNER = {
  drag = 0.978, gravity = 0.050, trail = 3.8, width = 2,
  fade_start = 0.74, twinkle_period = 6, draw_mode = DRAW_TRAIL,
}
local STYLE_RAPIDFIRE = {
  drag = 0.970, gravity = 0.054, trail = 3.5, width = 2,
  fade_start = 0.76, twinkle_period = 5, draw_mode = DRAW_TRAIL,
}
local STYLE_MULTIBREAK = {
  drag = 0.976, gravity = 0.050, trail = 4.0, width = 2,
  fade_start = 0.68, twinkle_period = 5, draw_mode = DRAW_TRAIL,
}
local STYLE_SECONDARY = {
  drag = 0.970, gravity = 0.058, trail = 3.5, width = 2,
  fade_start = 0.72, twinkle_period = 4, draw_mode = DRAW_TRAIL,
}
local STYLE_COMET = {
  drag = 0.900, gravity = 0.015, trail = 3.4, width = 1,
  fade_start = 0.30, twinkle_period = 0, draw_mode = DRAW_STROBE,
}
local STYLE_WATERFALL = {
  drag = 0.982, gravity = 0.060, trail = 15.0, width = 2,
  fade_start = 0.78, twinkle_period = 5, draw_mode = DRAW_TRAIL,
}
local STYLE_BROCADE_CROWN = {
  drag = 0.986, gravity = 0.034, trail = 11.0, width = 2,
  fade_start = 0.66, twinkle_period = 0,
  draw_mode = DRAW_BROCADE_CROWN,
}

local function pool_get(pool)
  local n = #pool
  if n > 0 then
    local obj = pool[n]
    pool[n] = nil
    return obj
  end
  return {}
end

local function reservation_fault(message)
  st.reservation_errors = st.reservation_errors + 1
  warn("reservation", message)
end

local function reserve_for(owner, amount)
  amount = math_floor(tonumber(amount) or 0)
  if amount <= 0 then return true end
  if (tonumber(owner.reserved) or 0) ~= 0 then
    reservation_fault("owner already reserved")
    return false
  end
  if #st.sparks + st.reserved_sparks + amount > MAX_SPARKS then return false end
  owner.reserved = amount
  st.reserved_sparks = st.reserved_sparks + amount
  return true
end

local function transfer_reservation(from, to, amount)
  amount = math_floor(tonumber(amount) or 0)
  local owned = tonumber(from.reserved) or 0
  if amount <= 0 or owned < amount or (tonumber(to.reserved) or 0) ~= 0 then
    reservation_fault("invalid transfer")
    return false
  end
  from.reserved = owned - amount
  to.reserved = amount
  return true
end

local function consume_reservation(owner, amount)
  amount = math_floor(tonumber(amount) or 0)
  local owned = tonumber(owner.reserved) or 0
  if amount <= 0 or owned < amount or st.reserved_sparks < amount then
    reservation_fault("invalid consume")
    return false
  end
  owner.reserved = owned - amount
  st.reserved_sparks = st.reserved_sparks - amount
  return true
end

local function release_reservation(owner)
  local owned = math_floor(tonumber(owner.reserved) or 0)
  owner.reserved = 0
  if owned <= 0 then return end
  if st.reserved_sparks < owned then
    reservation_fault("release underflow")
    st.reserved_sparks = 0
    return
  end
  st.reserved_sparks = st.reserved_sparks - owned
end

local function set_led(color)
  local sys_mod = rawget(_G, "sys")
  if not sys_mod or not sys_mod.setled then return end
  if color then
    local r = math_floor((math_floor(color / 65536) % 256) * 0.3)
    local g = math_floor((math_floor(color / 256) % 256) * 0.3)
    local b = math_floor((color % 256) * 0.3)
    local ok = pcall_fn(sys_mod.setled, r, g, b)
    if ok then
      st.led_on = true
      st.led_off_frame = st.frame + 10
    end
  elseif st.led_on then
    local ok = pcall_fn(sys_mod.setled)
    if ok then st.led_on = false end
  end
end

local function select_burst_kind(forced_kind)
  local forced_id = nil
  if type(forced_kind) == "string" then
    forced_id = BURST_IDS[forced_kind]
  elseif type(forced_kind) == "number" then
    forced_id = math_floor(forced_kind)
  end
  if forced_id and forced_id >= 1 and forced_id <= #BURST_NAMES then
    return forced_id
  end

  local roll = math_random(TOTAL_BURST_WEIGHT)
  local total = 0
  local kind = TYPE_PEONY
  for i = 1, #BURST_WEIGHTS do
    total = total + BURST_WEIGHTS[i]
    if roll <= total then
      kind = i
      break
    end
  end
  -- 随机烟花不连续重复；齐射中显式指定的类型不受影响。
  if kind == st.last_burst_kind then
    kind = kind % #BURST_NAMES + 1
  end
  return kind
end

local function palette_index_for(kind)
  if kind == TYPE_WILLOW then return 1 end -- 金色垂柳
  if kind == TYPE_COMET then return 1 end -- 银金彗星
  if kind == TYPE_WATERFALL then return 1 end -- 金色瀑布
  if kind == TYPE_BROCADE_CROWN then return 1 end -- 白金锦冠
  return math_random(#PALETTES)
end

local function emit_spark(x, y, vx, vy, life, palette, kind, style, phase)
  if #st.sparks >= MAX_SPARKS then return false end
  local s = pool_get(st.spark_pool)
  -- 对象池复用时显式覆盖所有类型字段，杜绝上一种烟花的样式残留。
  s.x = x
  s.y = y
  s.vx = vx
  s.vy = vy
  s.life = life
  s.age = 0
  s.core = palette.core
  s.body = palette.body
  s.kind = kind
  s.drag = style.drag
  s.gravity = style.gravity
  s.trail = style.trail
  s.width = style.width
  s.fade_start = style.fade_start
  s.twinkle_period = style.twinkle_period
  s.twinkle_phase = phase or 0
  s.draw_mode = style.draw_mode
  st.sparks[#st.sparks + 1] = s
  return true
end

local function schedule_secondary_burst(owner, x, y, vx, vy, delay_frames, palette_index)
  if #st.secondary_bursts >= MAX_SECONDARY_BURSTS then return false end
  local budget = 10
  local item = pool_get(st.secondary_pool)
  item.reserved = 0
  if not transfer_reservation(owner, item, budget) then
    st.secondary_pool[#st.secondary_pool + 1] = item
    return false
  end
  item.x = x
  item.y = y
  item.vx = vx
  item.vy = vy
  item.due = st.frame + delay_frames
  item.budget = budget
  item.palette_index = palette_index
  item.palette = PALETTES[palette_index]
  item.phase = math_random(0, 5)
  item.burst_phase = math_random() * 2 * math_pi
  st.secondary_bursts[#st.secondary_bursts + 1] = item
  return true
end

local function emit_secondary_burst(item)
  local count = item.budget
  local palette = item.palette
  local ring_speed = 1.35 + math_random() * 0.45
  for i = 1, count do
    local ang = item.burst_phase + ((i - 1) / count) * 2 * math_pi
    local speed = ring_speed * (0.90 + math_random() * 0.18)
    emit_spark(item.x, item.y, math_cos(ang) * speed, math_sin(ang) * speed * 0.86,
      math_random(34, 48), palette, TYPE_MULTIBREAK, STYLE_SECONDARY, math_random(0, 3))
  end
end

-- 在普通粒子遍历结束后处理，避免新增子粒子在同一帧被继续迭代或级联生成。
local function update_secondary_bursts()
  local bursts = st.secondary_bursts
  local i = 1
  while i <= #bursts do
    local item = bursts[i]
    item.vx = item.vx * 0.985
    item.vy = item.vy * 0.985 + 0.025
    item.x = item.x + item.vx
    item.y = item.y + item.vy
    if st.frame >= item.due then
      local owned = tonumber(item.reserved) or 0
      local other_reserved = st.reserved_sparks - owned
      local available = MAX_SPARKS - #st.sparks - other_reserved
      if owned == item.budget and other_reserved >= 0 and available >= item.budget
          and consume_reservation(item, item.budget) then
        if item.x < 18 then item.x = 18 elseif item.x > SCREEN_W - 18 then item.x = SCREEN_W - 18 end
        if item.y < 18 then item.y = 18 elseif item.y > SCREEN_H - 18 then item.y = SCREEN_H - 18 end
        emit_secondary_burst(item)
        st.secondary_pop_count = st.secondary_pop_count + 1
        st.flash_x = item.x
        st.flash_y = item.y
        st.flash_until = st.frame + 2
        set_led(item.palette.body)
      else
        reservation_fault("secondary capacity mismatch")
        release_reservation(item)
      end
      bursts[i] = bursts[#bursts]
      bursts[#bursts] = nil
      item.palette = nil
      item.reserved = 0
      st.secondary_pool[#st.secondary_pool + 1] = item
    else
      i = i + 1
    end
  end
end

local function emit_peony(x, y, palette)
  local count = BURST_BUDGETS[TYPE_PEONY]
  local phase = math_random() * 2 * math_pi
  local ring_speed = 2.0 + math_random() * 1.35
  for i = 1, count do
    local ang = phase + ((i - 1) / count) * 2 * math_pi + (math_random() - 0.5) * 0.16
    local speed
    if i % 2 == 0 then
      speed = ring_speed * (0.92 + math_random() * 0.16)
    else
      speed = 0.6 + math_random() * ring_speed
    end
    emit_spark(x, y, math_cos(ang) * speed, math_sin(ang) * speed * 0.86,
      math_random(44, 64), palette, TYPE_PEONY, STYLE_PEONY, math_random(0, 6))
  end
end

local function emit_chrysanthemum(x, y, palette, palette_index)
  local outer_count = 24
  local inner_count = BURST_BUDGETS[TYPE_CHRYSANTHEMUM] - outer_count
  local phase = math_random() * 2 * math_pi
  local inner_palette = PALETTES[(palette_index % #PALETTES) + 1]
  for i = 1, outer_count do
    local ang = phase + ((i - 1) / outer_count) * 2 * math_pi
      + (math_random() - 0.5) * 0.08
    local speed = 2.75 + math_random() * 0.65
    emit_spark(x, y, math_cos(ang) * speed, math_sin(ang) * speed * 0.90,
      math_random(62, 78), palette, TYPE_CHRYSANTHEMUM,
      STYLE_CHRYSANTHEMUM, math_random(0, 6))
  end
  for i = 1, inner_count do
    local ang = phase + math_pi / inner_count
      + ((i - 1) / inner_count) * 2 * math_pi
    local speed = 1.45 + math_random() * 0.45
    emit_spark(x, y, math_cos(ang) * speed, math_sin(ang) * speed * 0.90,
      math_random(54, 68), inner_palette, TYPE_CHRYSANTHEMUM,
      STYLE_CHRYSANTHEMUM, math_random(0, 6))
  end
end

local function emit_willow(x, y, palette)
  local count = BURST_BUDGETS[TYPE_WILLOW]
  local phase = math_random() * 2 * math_pi
  for i = 1, count do
    local ang = phase + ((i - 1) / count) * 2 * math_pi + (math_random() - 0.5) * 0.10
    local speed = 1.7 + math_random() * 1.1
    emit_spark(x, y, math_cos(ang) * speed, math_sin(ang) * speed * 0.70 - 0.55,
      math_random(80, 96), palette, TYPE_WILLOW, STYLE_WILLOW, math_random(0, 4))
  end
end

local function emit_strobe(x, y, palette)
  local count = BURST_BUDGETS[TYPE_STROBE]
  local phase = math_random() * 2 * math_pi
  for i = 1, count do
    local ang = phase + ((i - 1) / count) * 2 * math_pi + (math_random() - 0.5) * 0.24
    local speed = 0.75 + math_random() * 2.25
    emit_spark(x, y, math_cos(ang) * speed, math_sin(ang) * speed * 0.84,
      math_random(48, 68), palette, TYPE_STROBE, STYLE_STROBE, math_random(0, 5))
  end
end

local function emit_spinner(x, y, palette, palette_index)
  local spokes = 12
  local phase = math_random() * 2 * math_pi
  local inner_palette = PALETTES[(palette_index % #PALETTES) + 1]
  for i = 1, spokes do
    local ang = phase + ((i - 1) / spokes) * 2 * math_pi
    local outer_speed = 2.55 + math_random() * 0.45
    emit_spark(x, y, math_cos(ang) * outer_speed, math_sin(ang) * outer_speed * 0.88,
      math_random(48, 64), palette, TYPE_SPINNER, STYLE_SPINNER, math_random(0, 5))
    local inner_speed = 1.25 + math_random() * 0.35
    emit_spark(x, y, math_cos(ang + 0.11) * inner_speed,
      math_sin(ang + 0.11) * inner_speed * 0.88,
      math_random(42, 56), inner_palette, TYPE_SPINNER, STYLE_SPINNER, math_random(0, 5))
  end
end

local function emit_rapidfire(x, y, palette)
  local count = BURST_BUDGETS[TYPE_RAPIDFIRE]
  local phase = math_random() * 2 * math_pi
  for i = 1, count do
    local ang = phase + ((i - 1) / count) * 2 * math_pi
      + (math_random() - 0.5) * 0.12
    local speed = 1.35 + math_random() * 1.05
    emit_spark(x, y, math_cos(ang) * speed, math_sin(ang) * speed * 0.88,
      math_random(44, 58), palette, TYPE_RAPIDFIRE, STYLE_RAPIDFIRE, math_random(0, 4))
  end
end

local function emit_multibreak(x, y, palette, palette_index, owner)
  local primary_count = 12
  local phase = math_random() * 2 * math_pi
  -- 第一下是较紧凑的主爆，同时把四个“子弹”送向不同方向。
  for i = 1, primary_count do
    local ang = phase + ((i - 1) / primary_count) * 2 * math_pi
    local speed = 1.15 + math_random() * 0.85
    emit_spark(x, y, math_cos(ang) * speed, math_sin(ang) * speed * 0.82,
      math_random(34, 46), palette, TYPE_MULTIBREAK, STYLE_MULTIBREAK, math_random(0, 4))
  end
  -- 四个子爆错峰触发，视觉上形成“砰—砰砰砰砰”的连爆节奏。
  for i = 1, 4 do
    local ang = phase + (i - 1) * math_pi * 0.5 + (math_random() - 0.5) * 0.16
    local speed = 1.35 + math_random() * 0.35
    local child_palette_index = (palette_index + i - 1) % #PALETTES + 1
    schedule_secondary_burst(owner, x, y,
      math_cos(ang) * speed,
      math_sin(ang) * speed * 0.78 - 0.12,
      12 + (i - 1) * 6,
      child_palette_index)
  end
end

local WATERFALL_CLUSTERS = {
  { dx = -42, dy = 10, life_min = 100, life_max = 112 },
  { dx = -22, dy = -4, life_min = 106, life_max = 118 },
  { dx = 0, dy = -16, life_min = 112, life_max = 124 },
  { dx = 23, dy = 5, life_min = 104, life_max = 116 },
  { dx = 42, dy = -8, life_min = 108, life_max = 120 },
}

local function emit_waterfall(x, y, palette)
  local strands_per_cluster = 6
  local count = BURST_BUDGETS[TYPE_WATERFALL]
  for i = 1, count do
    local cluster = math_floor((i - 1) / strands_per_cluster) + 1
    local strand = (i - 1) % strands_per_cluster
    local fan = (strand / (strands_per_cluster - 1)) * 2 - 1
    local spec = WATERFALL_CLUSTERS[cluster]
    local origin_x = x + spec.dx + (math_random() - 0.5) * 0.8
    local origin_y = y + spec.dy + (math_random() - 0.5) * 0.6
    local inward_vx = -spec.dx * 0.004
    local vx = inward_vx + fan * (0.14 + math_random() * 0.08)
      + (math_random() - 0.5) * 0.03
    local vy = -0.72 - (1 - math_abs(fan)) * 0.32
      + (math_random() - 0.5) * 0.12
    emit_spark(origin_x, origin_y, vx, vy,
      math_random(spec.life_min, spec.life_max), palette, TYPE_WATERFALL,
      STYLE_WATERFALL, math_random(0, 4))
  end
end

local function emit_brocade_crown(x, y, palette)
  local count = BURST_BUDGETS[TYPE_BROCADE_CROWN]
  local phase = math_random() * 2 * math_pi
  for i = 1, count do
    local ang = phase + ((i - 1) / count) * 2 * math_pi
      + (math_random() - 0.5) * 0.04
    local speed = 2.15 + math_random() * 0.40
    emit_spark(x, y, math_cos(ang) * speed,
      math_sin(ang) * speed - 0.08,
      math_random(82, 96), palette, TYPE_BROCADE_CROWN,
      STYLE_BROCADE_CROWN, 0)
  end
end

local function emit_comet(x, y, palette)
  local count = BURST_BUDGETS[TYPE_COMET]
  local phase = math_random() * 2 * math_pi
  -- 彗星的主体是升空中的单颗亮头；到顶后只留下半径很小的余辉，
  -- 不再向左右扇射成多条彼此分离的弧线。
  for i = 1, count do
    local ang = phase + ((i - 1) / count) * 2 * math_pi
    local speed = 0.18 + math_random() * 0.12
    emit_spark(
      x + (math_random() - 0.5) * 0.8,
      y + (math_random() - 0.5) * 0.8,
      math_cos(ang) * speed,
      math_sin(ang) * speed * 0.72 - 0.04,
      math_random(22, 28), palette, TYPE_COMET,
      STYLE_COMET, 0)
  end
end

local EXPLODERS = {
  emit_peony,
  emit_chrysanthemum,
  emit_willow,
  emit_strobe,
  emit_spinner,
  emit_rapidfire,
  emit_multibreak,
  emit_comet,
  emit_waterfall,
  emit_brocade_crown,
}

local RAPIDFIRE_X = { 64, 112, 160, 208, 256 }

local function spawn_rocket(forced_kind, launch_item)
  if #st.rockets >= MAX_ROCKETS then return false end
  local kind = select_burst_kind(forced_kind)
  local budget = BURST_BUDGETS[kind]
  local rapidfire_member = launch_item and launch_item.rapidfire_member == true
  local starts_rapidfire = kind == TYPE_RAPIDFIRE and not rapidfire_member
  local rapidfire_index = 0
  if kind == TYPE_RAPIDFIRE then
    if rapidfire_member then
      rapidfire_index = math_floor(tonumber(launch_item.rapidfire_index) or 2)
      if rapidfire_index < 2 then rapidfire_index = 2 end
      if rapidfire_index > 5 then rapidfire_index = 5 end
    else
      rapidfire_index = 1
    end
  end
  -- 初发仍占着一个待发槽位，因此先为四发跟射预留完整队列空间。
  if starts_rapidfire and #st.pending_launches > MAX_PENDING_LAUNCHES - 4 then
    return false
  end
  if kind == TYPE_MULTIBREAK then
    local planned = #st.secondary_bursts
    for i = 1, #st.rockets do
      if st.rockets[i].kind == TYPE_MULTIBREAK then planned = planned + 4 end
    end
    if planned + 4 > MAX_SECONDARY_BURSTS then return false end
  end

  local r = pool_get(st.rocket_pool)
  r.reserved = 0
  if not reserve_for(r, budget) then
    st.rocket_pool[#st.rocket_pool + 1] = r
    return false
  end
  r.rapidfire_index = rapidfire_index
  r.spin_phase = 0
  r.spin_speed = 0
  r.spin_amplitude = 0
  r.spin_center_x = 0

  -- 连珠按舞台横向铺开；旋升火箭留出摆动边距；
  -- 子母连爆与彗星留出各自完整轮廓。
  if kind == TYPE_RAPIDFIRE then
    r.x = RAPIDFIRE_X[rapidfire_index] + math_random(-5, 5)
  elseif kind == TYPE_SPINNER then
    r.x = math_random(88, 232)
  elseif kind == TYPE_MULTIBREAK then
    if math_random(2) == 1 then
      r.x = math_random(62, 92)
    else
      r.x = math_random(228, 258)
    end
  elseif kind == TYPE_WATERFALL then
    r.x = math_random(92, 228)
  elseif kind == TYPE_BROCADE_CROWN then
    r.x = math_random(124, 196)
  elseif kind == TYPE_COMET then
    r.x = math_random(142, 178)
  elseif math_random(2) == 1 then
    r.x = math_random(42, 112)
  else
    r.x = math_random(208, SCREEN_W - 42)
  end
  r.y = SCREEN_H + 4
  r.vx = (math_random() - 0.5) * 0.75
  if kind == TYPE_COMET then
    r.vx = (math_random() - 0.5) * 0.22
  elseif kind == TYPE_WATERFALL then
    r.vx = (math_random() - 0.5) * 0.14
  elseif kind == TYPE_BROCADE_CROWN then
    r.vx = (math_random() - 0.5) * 0.30
  end

  -- 旋升火箭头围绕固定中心线窄幅周期摆动，严格限制整体横向漂移。
  if kind == TYPE_SPINNER then
    r.spin_phase = math_random() * 2 * math_pi
    r.spin_speed = (math_random(2) == 1 and -1 or 1) * (0.36 + math_random() * 0.06)
    r.spin_amplitude = 0.5 + math_random() * 0.5
    r.spin_center_x = r.x
    r.vx = 0
    r.x = r.spin_center_x + math_sin(r.spin_phase) * r.spin_amplitude
  else
    r.spin_center_x = r.x
  end
  r.prev_x = r.x
  r.prev_y = r.y

  -- 需要下垂或完整轮廓的类型优先在较高处展开；其余覆盖上、中和中下部。
  if kind == TYPE_WILLOW then
    r.vy = -(4.1 + math_random() * 1.0)
    r.apex_y = math_random(36, 96)
  elseif kind == TYPE_WATERFALL then
    r.vy = -(4.55 + math_random() * 0.45)
    r.apex_y = math_random(28, 56)
  elseif kind == TYPE_BROCADE_CROWN then
    r.vy = -(4.2 + math_random() * 0.8)
    r.apex_y = math_random(68, 92)
  elseif kind == TYPE_COMET then
    r.vy = -(4.0 + math_random() * 0.7)
    r.apex_y = math_random(58, 112)
  elseif kind == TYPE_SPINNER then
    r.vy = -(3.45 + math_random() * 0.30)
    r.apex_y = math_random(44, 74)
  elseif kind == TYPE_RAPIDFIRE then
    r.vy = -(4.15 + math_random() * 0.30)
    r.apex_y = math_random(132, 152)
  elseif kind == TYPE_MULTIBREAK then
    r.vy = -(3.9 + math_random() * 1.0)
    r.apex_y = math_random(52, 122)
  else
    local height_roll = math_random(100)
    if height_roll <= 50 then
      r.vy = -(4.0 + math_random() * 1.4)
      r.apex_y = math_random(34, 112)
    elseif height_roll <= 80 then
      r.vy = -(3.15 + math_random() * 0.9)
      r.apex_y = math_random(112, 158)
    else
      r.vy = -(2.55 + math_random() * 0.75)
      r.apex_y = math_random(150, 182)
    end
  end

  local palette_index = palette_index_for(kind)
  if kind == TYPE_RAPIDFIRE then
    palette_index = (rapidfire_index % #PALETTES) + 1
  end
  r.palette_index = palette_index
  r.palette = kind == TYPE_COMET and COMET_PALETTE
    or (kind == TYPE_WATERFALL or kind == TYPE_BROCADE_CROWN)
      and GOLD_TRAIL_PALETTE
    or PALETTES[palette_index]
  r.tail_color = kind == TYPE_COMET and COMET_ASCENT_COLORS[3]
    or lerp_color(r.palette.body, C.bg, 0.45)
  r.kind = kind
  r.budget = budget
  st.last_burst_kind = kind
  st.rockets[#st.rockets + 1] = r
  if starts_rapidfire then
    for index = 2, 5 do
      queue_launch((index - 1) * 6, 300, "rapidfire", true, index)
    end
  end
  return true
end

local function explode(r)
  local kind = tonumber(r.kind) or TYPE_PEONY
  if kind < 1 or kind > #BURST_NAMES then kind = TYPE_PEONY end
  local budget = BURST_BUDGETS[kind]
  -- 兼容测试或外部注入的火箭；正式路径已在发射时持有完整 reservation。
  if (tonumber(r.reserved) or 0) == 0 and not reserve_for(r, budget) then
    reservation_fault("unreserved rocket had no capacity")
    return
  end

  local primary_budget = kind == TYPE_MULTIBREAK and 12 or budget
  if not consume_reservation(r, primary_budget) then
    release_reservation(r)
    return
  end

  local palette_index = tonumber(r.palette_index) or palette_index_for(kind)
  local palette = kind == TYPE_WILLOW and PALETTES[1]
    or kind == TYPE_COMET and COMET_PALETTE
    or (kind == TYPE_WATERFALL or kind == TYPE_BROCADE_CROWN)
      and GOLD_TRAIL_PALETTE
    or (r.palette or PALETTES[palette_index])
  EXPLODERS[kind](r.x, r.y, palette, palette_index, r)
  -- 队列容量异常等降级路径会在这里释放尚未成功转移的余额。
  release_reservation(r)
  local name = BURST_NAMES[kind]
  st.burst_counts[name] = (st.burst_counts[name] or 0) + 1
  st.last_explosion_kind = name
  st.flash_x = r.x
  st.flash_y = r.y
  st.flash_until = st.frame + 3
  set_led(palette.body)
end

local function update_fireworks()
  -- 待发队列（齐射）：容量不足时短暂延后，避免整点或摇晃齐射丢发。
  local pending = st.pending_launches
  local i = 1
  while i <= #pending do
    local item = pending[i]
    if st.frame >= item.due then
      if spawn_rocket(item.burst_kind, item) or st.frame >= item.expires then
        pending[i] = pending[#pending]
        pending[#pending] = nil
      else
        item.due = st.frame + 5
        i = i + 1
      end
    else
      i = i + 1
    end
  end
  -- 自动定期发射
  if st.frame >= st.next_auto_launch then
    st.next_auto_launch = st.frame + math_random(36, 78)
    if #pending == 0 then spawn_rocket() end
  end
  -- 火箭
  local rockets = st.rockets
  i = 1
  while i <= #rockets do
    local r = rockets[i]
    r.prev_x = r.x
    r.prev_y = r.y
    local ascent_gravity = r.kind == TYPE_SPINNER
      and SPINNER_ASCENT_GRAVITY or ROCKET_ASCENT_GRAVITY
    r.vy = r.vy + ascent_gravity
    if r.kind == TYPE_SPINNER then
      r.spin_center_x = r.spin_center_x + r.vx
      r.spin_phase = r.spin_phase + r.spin_speed
      r.x = r.spin_center_x + math_sin(r.spin_phase) * r.spin_amplitude
    else
      r.x = r.x + r.vx
    end
    r.y = r.y + r.vy
    if r.vy >= -0.7 or r.y <= r.apex_y then
      explode(r)
      rockets[i] = rockets[#rockets]
      rockets[#rockets] = nil
      r.palette = nil
      r.reserved = 0
      st.rocket_pool[#st.rocket_pool + 1] = r
    else
      i = i + 1
    end
  end
  -- 粒子
  local sparks = st.sparks
  i = 1
  while i <= #sparks do
    local s = sparks[i]
    s.vx = s.vx * s.drag
    s.vy = s.vy * s.drag + s.gravity
    s.x = s.x + s.vx
    s.y = s.y + s.vy
    s.age = s.age + 1
    if s.age >= s.life or s.y > SCREEN_H + 4 or s.x < -4 or s.x > SCREEN_W + 4 then
      sparks[i] = sparks[#sparks]
      sparks[#sparks] = nil
      st.spark_pool[#st.spark_pool + 1] = s
    else
      i = i + 1
    end
  end
  update_secondary_bursts()
  -- LED 熄灭
  if st.led_on and st.frame >= st.led_off_frame then
    set_led(nil)
  end
end

local function draw_fireworks()
  if not lv_canvas_line_fn then return end
  local canvas = APP.canvas
  -- 火箭：亮头 + 暗尾
  for i = 1, #st.rockets do
    local r = st.rockets[i]
    local x = r.kind == TYPE_SPINNER
      and math_floor(r.x + 0.5) or math_floor(r.x)
    local y = math_floor(r.y)
    if r.kind == TYPE_SPINNER then
      local path_x = x
      local path_y = y
      for step = 1, SPINNER_TRAIL_STEPS do
        local phase = r.spin_phase - r.spin_speed * step
        local trail_x = math_floor(r.spin_center_x - r.vx * step
          + math_sin(phase) * r.spin_amplitude + 0.5)
        local trail_y = math_floor(r.y - r.vy * step
          + SPINNER_ASCENT_GRAVITY * step * (step - 1) * 0.5)
        local opa = 235 - step * 12
        lv_canvas_line_fn(canvas, path_x, path_y, trail_x, trail_y,
          r.tail_color or r.palette.body, opa, 2)
        path_x = trail_x
        path_y = trail_y
      end
      -- 旋升尾迹较粗且很长，使用更大的银白十字亮核把头部明确压在尾迹前端。
      draw_rect(x - 4, y - 4, 9, 9, r.palette.body, 56, 4)
      draw_rect(x - 2, y - 2, 5, 5, r.palette.core, 144, 2)
      draw_rect(x - 1, y - 1, 3, 3, r.palette.core, 240, 1)
      lv_canvas_line_fn(canvas,
        x - SPINNER_HEAD_RADIUS, y, x + SPINNER_HEAD_RADIUS, y,
        r.palette.core, 255, SPINNER_HEAD_WIDTH)
      lv_canvas_line_fn(canvas,
        x, y - SPINNER_HEAD_RADIUS, x, y + SPINNER_HEAD_RADIUS,
        r.palette.core, 255, SPINNER_HEAD_WIDTH)
    elseif r.kind == TYPE_COMET then
      -- 参考真实彗星：单颗高亮头部持续升空，尾部由白到橙逐渐变细变暗。
      local path_x = x
      local path_y = y
      for step = 1, COMET_ASCENT_TRAIL_STEPS do
        local trail_x = math_floor(r.x - r.vx * step)
        local trail_y = math_floor(r.y - r.vy * step
          + ROCKET_ASCENT_GRAVITY * step * (step - 1) * 0.5)
        local color_index = step <= 7 and 1
          or step <= 15 and 2
          or step <= 22 and 3 or 4
        local width = step <= 4 and 3 or step <= 14 and 2 or 1
        local opa = 255 - step * 7
        lv_canvas_line_fn(canvas, path_x, path_y, trail_x, trail_y,
          COMET_ASCENT_COLORS[color_index], opa, width)
        path_x = trail_x
        path_y = trail_y
      end
      -- 交错的小火星让长尾更密集；偏移随距离增加，但仍围绕同一条轨迹。
      for step = 4, COMET_ASCENT_TRAIL_STEPS, 2 do
        local trail_x = math_floor(r.x - r.vx * step)
        local trail_y = math_floor(r.y - r.vy * step
          + ROCKET_ASCENT_GRAVITY * step * (step - 1) * 0.5)
        local spread = 1 + math_floor(step / 7)
        local offset = math_floor(
          math_sin((st.frame + step) * 1.91) * spread + 0.5)
        local speck_x = trail_x + offset
        local speck_y = trail_y + ((st.frame + step) % 3) - 1
        local speck_color = step <= 14
          and COMET_ASCENT_COLORS[1] or COMET_ASCENT_COLORS[2]
        lv_canvas_line_fn(canvas, speck_x, speck_y, speck_x, speck_y + 1,
          speck_color, 230 - step * 5, 1)
      end
      -- 三层圆形暖光加银白十字亮核，保持照片中“头亮、尾密”的比例。
      draw_rect(x - 5, y - 5, 11, 11, COMET_ASCENT_COLORS[4], 72, 5)
      draw_rect(x - 3, y - 3, 7, 7, COMET_ASCENT_COLORS[2], 168, 3)
      draw_rect(x - 2, y - 2, 5, 5, COMET_ASCENT_COLORS[1], 255, 2)
      lv_canvas_line_fn(canvas,
        x - COMET_HEAD_RADIUS, y, x + COMET_HEAD_RADIUS, y,
        COMET_ASCENT_COLORS[1], 255, COMET_HEAD_WIDTH)
      lv_canvas_line_fn(canvas,
        x, y - COMET_HEAD_RADIUS, x, y + COMET_HEAD_RADIUS,
        COMET_ASCENT_COLORS[1], 255, COMET_HEAD_WIDTH)
    else
      local path_x = x
      local path_y = y
      for step = 1, STANDARD_TRAIL_STEPS do
        local trail_x = math_floor(r.x - r.vx * step)
        local trail_y = math_floor(r.y - r.vy * step
          + ROCKET_ASCENT_GRAVITY * step * (step - 1) * 0.5)
        local opa = 235 - step * 24
        lv_canvas_line_fn(canvas, path_x, path_y, trail_x, trail_y,
          r.tail_color or r.palette.body, opa, 2)
        path_x = trail_x
        path_y = trail_y
      end
      local head_x = math_floor(r.x - r.vx)
      local head_y = math_floor(r.y - r.vy)
      lv_canvas_line_fn(canvas, x, y, head_x, head_y, r.palette.core, 255, 2)
    end
  end
  -- 子母烟花的四个亮点继续向外飞行，抵达各自延迟后再次爆炸。
  for i = 1, #st.secondary_bursts do
    local item = st.secondary_bursts[i]
    if (st.frame + item.phase) % 4 < 3 then
      local x2 = math_floor(item.x)
      local y2 = math_floor(item.y)
      local x1 = math_floor(item.x - item.vx * 2.2)
      local y1 = math_floor(item.y - item.vy * 2.2)
      lv_canvas_line_fn(canvas, x1, y1, x2, y2, item.palette.core, 255, 2)
    end
  end
  -- 爆炸白闪
  if st.flash_until and st.frame < st.flash_until then
    draw_rect(math_floor(st.flash_x) - 3, math_floor(st.flash_y) - 3, 6, 6, 0xFFFFFF, 230, 3)
  end
  -- 粒子：沿速度方向的短线，自带运动拖尾
  for i = 1, #st.sparks do
    local s = st.sparks[i]
    local frac = s.age / s.life
    local phase = s.twinkle_period > 0
      and (s.age + s.twinkle_phase) % s.twinkle_period or -1
    local visible = s.draw_mode ~= DRAW_STROBE or phase < 3
    local color, opa
    if frac < 0.25 then
      color = s.core
      opa = 255
    elseif frac < s.fade_start then
      color = s.body
      opa = 255
    else
      local fade = (frac - s.fade_start) / (1 - s.fade_start)
      color = faded_body_color(s.body, fade)
      opa = math_floor(255 * (1 - fade))
      -- 闪烁相位在生成时固定，绘制不再消耗随机数。
      if s.draw_mode ~= DRAW_STROBE and s.twinkle_period > 0 and phase == 0 then
        opa = math_floor(opa * 0.4)
      end
      if s.kind ~= TYPE_COMET and opa < 24 then opa = 24 end
    end
    if visible then
      local x2 = math_floor(s.x)
      local y2 = math_floor(s.y)
      -- 所有爆炸火丝都从细暗尾端向粗亮头部画空间渐变；
      -- 彗星终闪沿用四段短尾与小十字，避免重新分裂成多条长彗尾。
      local trail_dx = s.vx * s.trail
      local trail_dy = s.vy * s.trail
      local trail_segments = SPARK_TRAIL_SEGMENTS
      local opacity_step = 0.22
      local trail_color = color
      if s.draw_mode == DRAW_BROCADE_CROWN and frac < s.fade_start then
        trail_color = s.body
      end
      for segment = trail_segments, 1, -1 do
        local far = segment / trail_segments
        local near = (segment - 1) / trail_segments
        local x1 = math_floor(s.x - trail_dx * far)
        local y1 = math_floor(s.y - trail_dy * far)
        local sx2 = math_floor(s.x - trail_dx * near)
        local sy2 = math_floor(s.y - trail_dy * near)
        local segment_opa = math_floor(
          opa * (1 - (segment - 1) * opacity_step) + 0.5)
        local segment_width = segment <= 2 and s.width or 1
        lv_canvas_line_fn(canvas, x1, y1, sx2, sy2,
          trail_color, segment_opa, segment_width)
      end
      if s.draw_mode == DRAW_STROBE then
        local size = frac < 0.6 and 2 or 1
        lv_canvas_line_fn(canvas, x2 - size, y2, x2 + size, y2, color, opa, 1)
        lv_canvas_line_fn(canvas, x2, y2 - size, x2, y2 + size, color, opa, 1)
      elseif s.draw_mode == DRAW_BROCADE_CROWN then
        draw_rect(x2 - 1, y2 - 1, 3, 3, s.core, opa, 1)
      end
    end
  end
end

-- ---------------------------------------------------------------- clock draw
local function weather_values()
  local host = rawget(_G, "HOLO_TIME_APP")
  local state = host and host.state
  if not state then return "--", "--°", "103" end
  local temp = tonumber(state.temp)
  local temp_text = temp and string_format("%d°", math_floor(temp + 0.5)) or "--°"
  return tostring(state.weather_text or "--"), temp_text, tostring(state.weather_code or "103")
end

local function draw_temperature_icon(x, y, color, opa)
  -- Linear thermometer based on the reference set: 1 px outline, hollow tube,
  -- round hollow bulb and a short centered mercury column.
  draw_rect(x + 4, y, 5, 11, color, opa, 2)
  draw_rect(x + 5, y + 1, 3, 9, C.bg, 255, 1)
  draw_rect(x + 2, y + 8, 9, 8, color, opa, 4)
  draw_rect(x + 3, y + 9, 7, 6, C.bg, 255, 3)
  draw_rect(x + 6, y + 4, 1, 8, color, opa, 1)
  draw_rect(x + 5, y + 11, 3, 3, color, opa, 1)
end

local function weather_kind(code, label)
  label = tostring(label or "")
  if code:match("^4") or label:find("雪") then return "snow" end
  if code:match("^3") or label:find("雨") then return "rain" end
  if code:match("^2") or label:find("雷") then return "storm" end
  if code == "100" or code == "150" or label == "晴" then return "sun" end
  return "cloud"
end

local function draw_weather_status_icon(x, y, code, label, color, opa)
  local kind = weather_kind(code, label)
  if kind == "sun" then
    draw_rect(x + 3, y + 3, 7, 7, color, opa, 3)
    if lv_canvas_line_fn then
      lv_canvas_line_fn(APP.canvas, x + 6, y, x + 6, y + 2, color, opa, 1)
      lv_canvas_line_fn(APP.canvas, x + 6, y + 11, x + 6, y + 13, color, opa, 1)
      lv_canvas_line_fn(APP.canvas, x, y + 6, x + 2, y + 6, color, opa, 1)
      lv_canvas_line_fn(APP.canvas, x + 11, y + 6, x + 13, y + 6, color, opa, 1)
    end
    return
  end
  draw_rect(x + 1, y + 5, 12, 6, color, opa, 3)
  draw_rect(x + 4, y + 2, 6, 6, color, opa, 3)
  if kind == "rain" or kind == "storm" then
    if lv_canvas_line_fn then
      lv_canvas_line_fn(APP.canvas, x + 4, y + 12, x + 3, y + 14, color, opa, 1)
      lv_canvas_line_fn(APP.canvas, x + 9, y + 12, x + 8, y + 14, color, opa, 1)
    end
  elseif kind == "snow" then
    draw_rect(x + 3, y + 13, 2, 2, color, opa, 1)
    draw_rect(x + 9, y + 13, 2, 2, color, opa, 1)
  end
end

local function draw_clock()
  -- 用细黑描边保护读数，同时保留烟花在数字间穿行的亮度。
  local clock_y = 62
  draw_text(-2, clock_y, SCREEN_W, st.clock_hhmm, APP.font_time, C.bg, 255)
  draw_text(2, clock_y, SCREEN_W, st.clock_hhmm, APP.font_time, C.bg, 255)
  draw_text(0, clock_y - 2, SCREEN_W, st.clock_hhmm, APP.font_time, C.bg, 255)
  draw_text(0, clock_y + 2, SCREEN_W, st.clock_hhmm, APP.font_time, C.bg, 255)
  draw_text(0, clock_y, SCREEN_W, st.clock_hhmm, APP.font_time, C.clock, st.clock_valid and 255 or 140)
  -- 秒进度条
  local bar_x, bar_y, bar_w = 70, 154, 180
  draw_rect(bar_x, bar_y, bar_w, 3, C.bar_track, 255, 1)
  if st.clock_valid then
    local w = math_floor(bar_w * st.clock_sec / 59 + 0.5)
    if w > 0 then
      draw_rect(bar_x, bar_y, w, 3, C.bar_fill, 220, 1)
    end
  end
  local date_font = current_language():match("^en") and APP.font_date_en or APP.font_date_cjk
  draw_text(0, 169, SCREEN_W, st.clock_date, date_font, C.bg, 255)
  draw_text(0, 168, SCREEN_W, st.clock_date, date_font, C.date, 220)
  local weather_text, temp_text, weather_code = weather_values()
  -- Two compact groups share the screen center; narrow text boxes keep each
  -- glyph run visually attached to its icon instead of drifting inside a wide box.
  draw_weather_status_icon(84, 194, weather_code, weather_text, C.date, 220)
  draw_text(99, 196, 40, weather_text, date_font, C.bg, 255)
  draw_text(99, 195, 40, weather_text, date_font, C.date, 220)
  draw_temperature_icon(177, 195, C.date, 220)
  draw_text(188, 196, 28, temp_text, date_font, C.bg, 255)
  draw_text(188, 195, 28, temp_text, date_font, C.date, 220)
end

-- ---------------------------------------------------------------- render / tick
local function render()
  local explicit = frame_begin()
  if lv_canvas_fill_fn then
    pcall_fn(lv_canvas_fill_fn, APP.canvas, C.bg, 255)
  end
  draw_fireworks()
  draw_clock()
  frame_end(explicit)
end

local function maybe_stop_for_exit()
  local app_mod = rawget(_G, "app")
  if app_mod and app_mod.exiting then
    local ok, exiting = pcall_fn(app_mod.exiting)
    if ok and exiting then
      APP.stop("exit")
      return true
    end
  end
  return false
end

local function tick()
  if not APP.running or rawget(_G, "FIREWORKS_CLOCK_APP") ~= APP then return end
  if maybe_stop_for_exit() then return end
  st.frame = st.frame + 1
  -- 时间查询降频：每 8 帧（~264ms）一次
  if st.frame - st.last_time_query_frame >= 8 then
    st.last_time_query_frame = st.frame
    refresh_clock()
  end
  update_fireworks()
  render()
  if st.frame % 64 == 0 then
    pcall_fn(collectgarbage, "step")
  end
end

-- ---------------------------------------------------------------- input
local function angle_delta(value, previous_value)
  local delta = (tonumber(value) or 0) - (tonumber(previous_value) or 0)
  while delta > 180 do delta = delta - 360 end
  while delta < -180 do delta = delta + 360 end
  return delta
end

local function bind_input()
  local key_mod = rawget(_G, "key")
  if key_mod and key_mod.on then
    local launch_keys = { key_mod.LEFT, key_mod.RIGHT, key_mod.UP, key_mod.DOWN }
    APP.bound_keys = {}
    for i = 1, #launch_keys do
      local code = launch_keys[i]
      if code then
        APP.bound_keys[#APP.bound_keys + 1] = code
        key_mod.on(code, function(evt)
          if rawget(_G, "FIREWORKS_CLOCK_APP") ~= APP then return end
          if evt == key_mod.SHORT then
            queue_launch(0, 180)
          end
        end)
      end
    end
  end
  local app_mod = rawget(_G, "app")
  if app_mod and app_mod.on then
    app_mod.on("imu", function(_, roll, pitch, _, _, _, ts_ms)
      if rawget(_G, "FIREWORKS_CLOCK_APP") ~= APP then return end
      roll = tonumber(roll)
      pitch = tonumber(pitch)
      if not roll or not pitch then return end
      if st.imu_last_roll then
        local motion = math_abs(angle_delta(roll, st.imu_last_roll))
          + math_abs(angle_delta(pitch, st.imu_last_pitch))
        local now = tonumber(ts_ms) or st.frame * TICK_MS
        if st.imu_armed then
          if motion >= 18 then
            if now - st.imu_last_spike_ms > 220 then st.imu_spike_count = 0 end
            st.imu_spike_count = st.imu_spike_count + 1
            st.imu_last_spike_ms = now
            if st.imu_spike_count >= 2 and st.frame >= st.shake_cooldown_until then
              st.shake_cooldown_until = st.frame + 45
              st.imu_armed = false
              st.imu_calm_samples = 0
              st.imu_spike_count = 0
              for i = 0, 2 do
                queue_launch(i * 9, 210, SHAKE_BURST_SEQUENCE[i + 1])
              end
            end
          elseif motion < 8 then
            st.imu_spike_count = 0
          end
        elseif motion < 5 then
          st.imu_calm_samples = st.imu_calm_samples + 1
          if st.imu_calm_samples >= 8 and st.frame >= st.shake_cooldown_until then
            st.imu_armed = true
            st.imu_calm_samples = 0
          end
        else
          st.imu_calm_samples = 0
        end
      end
      st.imu_last_roll = roll
      st.imu_last_pitch = pitch
    end)
    APP.imu_bound = true
  end
end

-- ---------------------------------------------------------------- fonts / ui
local function font_load(path, fallback)
  if lv_font_load_fn then
    local ok, handle = pcall_fn(lv_font_load_fn, path)
    if ok and type(handle) == "number" and handle > 0 then
      APP.font_handles[#APP.font_handles + 1] = handle
      return handle
    end
  end
  return fallback
end

local function init_fonts()
  local host = rawget(_G, "HOLO_TIME_APP")
  APP.font_time = host and host.font and host.font.n72
    or font_load(APP.APP_DIR .. "/font/time_num_72.bin",
      rawget(_G, "LV_FONT_MONTSERRAT_28") or 28)
  APP.font_date_en = rawget(_G, "LV_FONT_MONTSERRAT_14") or rawget(_G, "LV_FONT_MONTSERRAT_12") or 14
  APP.font_date_cjk = host and host.font and host.font.cn14 or APP.font_date_en
  APP.font_date = APP.font_date_en
end

local function init_ui()
  if not (lv_scr_act_fn and lv_canvas_create_fn) then
    warn("lvgl canvas unavailable")
    return false
  end
  local root = lv_scr_act_fn()
  if lv_obj_clean_fn then pcall_fn(lv_obj_clean_fn, root) end
  APP.root = root
  if CANVAS_FMT then
    APP.canvas = lv_canvas_create_fn(root, SCREEN_W, SCREEN_H, CANVAS_FMT)
  else
    APP.canvas = lv_canvas_create_fn(root, SCREEN_W, SCREEN_H)
  end
  if not APP.canvas then
    warn("canvas create failed")
    return false
  end
  if lv_obj_set_pos_fn then pcall_fn(lv_obj_set_pos_fn, APP.canvas, 0, 0) end
  detect_rect_mode()
  return true
end

-- ---------------------------------------------------------------- lifecycle
function APP.stop(reason)
  if not APP.running then return end
  APP.running = false
  for _, timer in pairs(APP.timers) do
    pcall_fn(function() timer:stop() end)
    pcall_fn(function() timer:unregister() end)
  end
  APP.timers = {}
  local app_mod = rawget(_G, "app")
  if APP.imu_bound and app_mod and app_mod.on then
    pcall_fn(app_mod.on, "imu", nil)
  end
  local key_mod = rawget(_G, "key")
  if key_mod and key_mod.off and APP.bound_keys then
    for i = 1, #APP.bound_keys do
      pcall_fn(key_mod.off, APP.bound_keys[i])
    end
  end
  for i = 1, #st.rockets do release_reservation(st.rockets[i]) end
  for i = 1, #st.secondary_bursts do release_reservation(st.secondary_bursts[i]) end
  if st.reserved_sparks ~= 0 then
    reservation_fault("orphaned reservation on stop")
    st.reserved_sparks = 0
  end
  local sys_mod = rawget(_G, "sys")
  if sys_mod and sys_mod.setled then
    local ok = pcall_fn(sys_mod.setled)
    if ok then st.led_on = false end
  end
  if lv_font_free_fn then
    for _, handle in ipairs(APP.font_handles) do
      pcall_fn(lv_font_free_fn, handle)
    end
  end
  APP.font_handles = {}
  st.secondary_bursts = {}
  st.secondary_pool = {}
  if rawget(_G, "FIREWORKS_CLOCK_APP") == APP then
    _G.FIREWORKS_CLOCK_APP = nil
  end
  if lv_scr_act_fn and lv_obj_clean_fn then
    pcall_fn(lv_obj_clean_fn, lv_scr_act_fn())
  end
  warn("stop", tostring(reason or ""))
end

APP.shutdown = APP.stop

-- ---------------------------------------------------------------- start
local function start_tick_timer()
  local tmr_mod = rawget(_G, "tmr")
  if not (tmr_mod and tmr_mod.create and tmr_mod.ALARM_AUTO) then
    warn("timer unavailable")
    return false
  end
  local ok_create, timer = pcall_fn(tmr_mod.create)
  if not ok_create or not timer then
    warn("timer create failed", tostring(timer or ""))
    return false
  end
  APP.timers.tick = timer
  local ok_alarm, started_or_err = pcall_fn(function()
    return timer:alarm(TICK_MS, tmr_mod.ALARM_AUTO, function()
      if rawget(_G, "FIREWORKS_CLOCK_APP") ~= APP then return end
      local ok, tick_err = pcall_fn(tick)
      if not ok then
        warn("tick failed", tostring(tick_err))
        APP.stop("tick-error")
      end
    end)
  end)
  if not ok_alarm or started_or_err ~= true then
    warn("timer alarm failed", tostring(started_or_err or ""))
    pcall_fn(function() timer:stop() end)
    pcall_fn(function() timer:unregister() end)
    APP.timers.tick = nil
    return false
  end
  return true
end

local function start_app()
  local ok, err = pcall_fn(function()
    seed_random()
    st.timezone, st.language = load_preferences()
    init_time()
    init_fonts()
    if not init_ui() then error("ui-init-failed") end
    -- NixieClock owns input so LEFT/RIGHT and Web control can leave this face.
    refresh_clock()
    render()
    if not start_tick_timer() then error("timer-init-failed") end
  end)
  if not ok then
    warn("start failed", tostring(err))
    APP.stop("start-error")
  end
end

start_app()
