local prev = rawget(_G, "MATRIX_RAIN_APP")
if prev and prev.stop then
  pcall(function()
    prev.stop()
  end)
end

MATRIX_RAIN_APP = {
  VERSION = "2026-04-27-matrix-rain-v1"
}

local APP = MATRIX_RAIN_APP
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

local root = lv_scr_act()
clear_root()

local SCREEN_W = 320
local SCREEN_H = 240
local COLUMN_W = 8
local ROW_H = 13
local FONT_SIZE = 12
local TICK_MS = 30
local MIN_TRAIL = 6
local MAX_TRAIL = 17
local COL_COUNT = math.floor(SCREEN_W / COLUMN_W)
local ROW_COUNT = math.floor(SCREEN_H / ROW_H) + 2
local MAIN_STYLE = rawget(_G, "LV_PART_MAIN") or 0
local ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1
local CANVAS_FMT = rawget(_G, "LV_IMG_CF_TRUE_COLOR") or rawget(_G, "CANVAS_FMT_TRUE_COLOR")
local FONT_HANDLE = rawget(_G, "LV_FONT_MONTSERRAT_10") or rawget(_G, "LV_FONT_MONTSERRAT_12")

local math_floor = math.floor
local math_random = math.random
local pcall_fn = pcall

local lv_canvas_create_fn = rawget(_G, "lv_canvas_create")
local lv_canvas_frame_begin_fn = rawget(_G, "lv_canvas_frame_begin") or rawget(_G, "lv_canvas_begin")
local lv_canvas_frame_end_fn = rawget(_G, "lv_canvas_frame_end") or rawget(_G, "lv_canvas_end")
local lv_canvas_fill_bg_fn = rawget(_G, "lv_canvas_fill_bg") or rawget(_G, "lv_canvas_fill")
local lv_canvas_draw_rect_fn = rawget(_G, "lv_canvas_draw_rect")
local lv_canvas_draw_text_fn = rawget(_G, "lv_canvas_draw_text")
local lv_canvas_draw_text_font_fn = rawget(_G, "lv_canvas_draw_text_font")
local lv_obj_set_pos_fn = rawget(_G, "lv_obj_set_pos")
local lv_obj_set_style_bg_color_fn = rawget(_G, "lv_obj_set_style_bg_color")
local lv_obj_set_style_bg_opa_fn = rawget(_G, "lv_obj_set_style_bg_opa")
local lv_obj_clear_flag_fn = rawget(_G, "lv_obj_clear_flag")
local lv_obj_invalidate_fn = rawget(_G, "lv_obj_invalidate")
local runtime_app = rawget(_G, "app")
local app_exiting_fn = runtime_app and runtime_app.exiting or nil

local C = {
  bg = 0x000000,
  head = 0xEEFFF2,
  hot = 0x8CFFAA,
  body = 0x00E85A,
  mid = 0x009A35,
  tail = 0x062814,
  glow = 0x00FF66,
}

local GLYPHS = {
  "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
  "A", "B", "C", "D", "E", "F", "G", "H", "J", "K",
  "L", "M", "N", "P", "R", "S", "T", "U", "V", "X",
  "Y", "Z", "$", "+", "-", "/", "*", "#"
}
local GLYPH_COUNT = #GLYPHS

local columns = {}
local fade_color = {}
local fade_opa = {}
local canvas = nil
local text_mode = 0
local text_dsc = {
  color = C.body,
  opa = 255,
  align = ALIGN_CENTER,
  font_size = FONT_SIZE,
  font_handle = FONT_HANDLE
}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
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

local function lerp_color(a, b, t)
  local ar, ag, ab = split_rgb(a)
  local br, bg, bb = split_rgb(b)
  return rgb_hex(
    ar + (br - ar) * t,
    ag + (bg - ag) * t,
    ab + (bb - ab) * t
  )
end

local function random_char()
  return GLYPHS[math_random(1, GLYPH_COUNT)]
end

local function seed_random()
  local seed = 1
  if millis then
    local ok, v = pcall_fn(millis)
    if ok and type(v) == "number" then
      seed = v
    end
  elseif tmr and tmr.now then
    local ok, v = pcall_fn(tmr.now)
    if ok and type(v) == "number" then
      seed = v
    end
  elseif os and os.time then
    seed = os.time()
  end

  math.randomseed(seed)
  math_random()
  math_random()
  math_random()
end

local function build_fade_table()
  for k = 0, MAX_TRAIL do
    if k == 0 then
      fade_color[k] = C.head
      fade_opa[k] = 255
    elseif k == 1 then
      fade_color[k] = C.hot
      fade_opa[k] = 238
    else
      local t = (k - 1) / (MAX_TRAIL - 1)
      fade_color[k] = lerp_color(C.body, C.tail, t)
      fade_opa[k] = clamp(math_floor(218 * (1 - t) + 28), 26, 228)
    end
  end
end

local function seed_chars(col)
  col.chars = col.chars or {}
  for r = 1, ROW_COUNT do
    col.chars[r] = random_char()
  end
end

local function reset_column(col, first_run)
  col.length = math_random(MIN_TRAIL, MAX_TRAIL)

  local speed_roll = math_random(1, 100)
  if speed_roll <= 10 then
    col.speed = 1
  elseif speed_roll <= 60 then
    col.speed = 2
  else
    col.speed = 3
  end

  if col.speed > 1 then
    col.tick = math_random(0, col.speed - 1)
  else
    col.tick = 0
  end
  col.opa_scale = math_random(76, 100)
  col.flicker = math_random(1, 3)

  if first_run then
    col.head = math_random(-ROW_COUNT, ROW_COUNT)
  else
    col.head = -math_random(col.length, ROW_COUNT + col.length)
  end

  seed_chars(col)
end

local function build_columns()
  for i = 1, COL_COUNT do
    local col = {
      x = (i - 1) * COLUMN_W,
      head = 0,
      length = MIN_TRAIL,
      speed = 2,
      tick = 0,
      opa_scale = 100,
      flicker = 1,
      chars = {}
    }

    reset_column(col, true)
    columns[i] = col
  end
end

local function frame_begin()
  if not lv_canvas_frame_begin_fn or not canvas then
    return false
  end

  local ok = pcall_fn(lv_canvas_frame_begin_fn, canvas)
  return ok and true or false
end

local function frame_end(explicit_frame)
  if explicit_frame and lv_canvas_frame_end_fn then
    pcall_fn(lv_canvas_frame_end_fn, canvas)
    return
  end

  if lv_obj_invalidate_fn and canvas then
    pcall_fn(lv_obj_invalidate_fn, canvas)
  end
end

local function clear_canvas()
  if lv_canvas_fill_bg_fn then
    pcall_fn(lv_canvas_fill_bg_fn, canvas, C.bg, 255)
  end
end

local function draw_rect(x, y, w, h, color, opa)
  if not lv_canvas_draw_rect_fn then
    return
  end

  local ok = pcall_fn(lv_canvas_draw_rect_fn, canvas, x, y, w, h, {
    bg_color = color,
    bg_opa = opa,
    radius = 2,
    border_width = 0
  })
  if ok then
    return
  end

  pcall_fn(lv_canvas_draw_rect_fn, canvas, x, y, w, h, color, opa)
end

local function detect_text_mode()
  if lv_canvas_draw_text_fn then
    local ok = pcall_fn(lv_canvas_draw_text_fn, canvas, 0, 0, 1, "", text_dsc)
    if ok then
      text_mode = 1
      return
    end

    ok = pcall_fn(lv_canvas_draw_text_fn, canvas, 0, 0, 1, "", C.body, 1, ALIGN_CENTER, FONT_SIZE)
    if ok then
      text_mode = 2
      return
    end
  end

  if lv_canvas_draw_text_font_fn and FONT_HANDLE then
    text_mode = 3
  end
end

local function draw_text(x, y, text, color, opa)
  if text_mode == 2 then
    lv_canvas_draw_text_fn(canvas, x, y, COLUMN_W, text, color, opa, ALIGN_CENTER, FONT_SIZE)
  elseif text_mode == 1 then
    text_dsc.color = color
    text_dsc.opa = opa
    lv_canvas_draw_text_fn(canvas, x, y, COLUMN_W, text, text_dsc)
  elseif text_mode == 3 then
    lv_canvas_draw_text_font_fn(canvas, x, y, COLUMN_W, text, color, opa, ALIGN_CENTER, FONT_HANDLE)
  end
end

local function update_column(col)
  col.tick = col.tick + 1
  if col.tick >= col.speed then
    col.tick = 0
    col.head = col.head + 1
    if col.head >= 0 and col.head < ROW_COUNT then
      col.chars[col.head + 1] = random_char()
    end
  end

  for _ = 1, col.flicker do
    if math_random(1, 100) <= 22 then
      col.chars[math_random(1, ROW_COUNT)] = random_char()
    end
  end

  if col.head - col.length > ROW_COUNT then
    reset_column(col, false)
  end
end

local function update_state()
  for i = 1, COL_COUNT do
    update_column(columns[i])
  end
end

local function draw_column(col)
  for k = col.length - 1, 0, -1 do
    local row = col.head - k
    if row >= 0 and row < ROW_COUNT then
      local y = row * ROW_H - 1
      if y < SCREEN_H then
        local color = fade_color[k] or C.tail
        local opa = fade_opa[k] or 40
        opa = clamp(math_floor((opa * col.opa_scale) / 100), 18, 255)

        if k == 0 then
          draw_rect(col.x + 1, y + 1, COLUMN_W - 2, ROW_H - 1, C.glow, 26)
        end

        draw_text(col.x, y, col.chars[row + 1] or random_char(), color, opa)
      end
    end
  end
end

local function redraw()
  if not canvas or text_mode == 0 then
    return
  end

  local explicit_frame = frame_begin()
  clear_canvas()

  for i = 1, COL_COUNT do
    draw_column(columns[i])
  end

  frame_end(explicit_frame)
end

function APP.stop()
  if APP.stopped then
    return
  end

  APP.stopped = true

  if APP.timer then
    pcall_fn(function()
      APP.timer:stop()
    end)
    pcall_fn(function()
      APP.timer:unregister()
    end)
    APP.timer = nil
  end

  if rawget(_G, "MATRIX_RAIN_APP") == APP then
    _G.MATRIX_RAIN_APP = nil
  end
end

local function tick()
  if rawget(_G, "MATRIX_RAIN_APP") ~= APP then
    return
  end

  if app_exiting_fn then
    local ok, exiting = pcall_fn(app_exiting_fn)
    if ok and exiting then
      APP.stop()
      return
    end
  end

  update_state()
  redraw()
end

local function init_root()
  if lv_obj_set_style_bg_color_fn then
    pcall_fn(lv_obj_set_style_bg_color_fn, root, C.bg, MAIN_STYLE)
  end
  if lv_obj_set_style_bg_opa_fn then
    pcall_fn(lv_obj_set_style_bg_opa_fn, root, 255, MAIN_STYLE)
  end
  if lv_obj_clear_flag_fn and rawget(_G, "LV_OBJ_FLAG_SCROLLABLE") then
    pcall_fn(lv_obj_clear_flag_fn, root, rawget(_G, "LV_OBJ_FLAG_SCROLLABLE"))
  end
end

local function init_canvas()
  if not lv_canvas_create_fn then
    return false
  end

  if CANVAS_FMT then
    canvas = lv_canvas_create_fn(root, SCREEN_W, SCREEN_H, CANVAS_FMT)
  else
    canvas = lv_canvas_create_fn(root, SCREEN_W, SCREEN_H)
  end
  if lv_obj_set_pos_fn and canvas then
    lv_obj_set_pos_fn(canvas, 0, 0)
  end

  return canvas and true or false
end

seed_random()
build_fade_table()
build_columns()
init_root()

if init_canvas() then
  detect_text_mode()
  redraw()

  if tmr and tmr.create then
    APP.timer = tmr.create()
    APP.timer:alarm(TICK_MS, tmr.ALARM_AUTO, function()
      local ok = pcall_fn(tick)
      if not ok then
        APP.stop()
      end
    end)
  end
end
