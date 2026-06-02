
LVGL_BENCHMARK_APP = {
  VERSION = "2026-04-04-lvgl-benchmark-lua-v5",
}

local APP = LVGL_BENCHMARK_APP
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

if
  not lv_scr_act or
  not lv_obj_clean or
  not lv_obj_create or
  not lv_obj_del or
  not lv_obj_remove_style_all or
  not lv_obj_set_layout or
  not lv_obj_set_width or
  not lv_obj_set_flex_flow or
  not lv_obj_set_flex_align or
  not lv_obj_get_width or
  not lv_obj_get_height or
  not lv_img_create or
  not lv_img_set_src or
  not lv_img_set_angle or
  not lv_img_set_zoom or
  not lv_img_set_pivot or
  not lv_label_create or
  not lv_line_create or
  not lv_line_set_points or
  not lv_arc_create or
  not lv_table_create or
  not lv_table_set_row_cnt or
  not lv_table_set_col_cnt or
  not lv_table_set_col_width or
  not lv_table_set_cell_value or
  not lv_table_add_cell_ctrl or
  not lv_anim_start or
  not lv_obj_set_style_blend_mode or
  not lv_obj_set_style_img_opa or
  not lv_obj_set_style_img_recolor or
  not lv_obj_set_style_img_recolor_opa or
  not lv_obj_set_style_transform_angle or
  not lv_obj_set_style_transform_zoom or
  not lv_obj_set_style_transform_pivot_x or
  not lv_obj_set_style_transform_pivot_y or
  not lv_pct
then
  print("[lvgldemo] required lua_ui apis are missing")
  return
end

local ROOT = lv_scr_act()
local HAS_REAL_MONITOR = lv_lvgl_monitor_reset and lv_lvgl_monitor_get and true or false

local SCREEN_W = 320
local SCREEN_H = 240
local LV_DPI_DEF = 130

local SCENE_TIME = 1000
local TICK_MS = 10

local OBJ_NUM = 8
local OBJ_SIZE_MIN = math.max(math.floor(LV_DPI_DEF / 20), 5)
local OBJ_SIZE_MAX = math.floor(SCREEN_W / 2)
local RADIUS = math.max(math.floor(LV_DPI_DEF / 15), 2)
local BORDER_WIDTH = math.max(math.floor(LV_DPI_DEF / 40), 1)
local SHADOW_WIDTH_SMALL = math.max(math.floor(LV_DPI_DEF / 15), 5)
local SHADOW_OFS_X_SMALL = math.max(math.floor(LV_DPI_DEF / 20), 2)
local SHADOW_OFS_Y_SMALL = math.max(math.floor(LV_DPI_DEF / 20), 2)
local SHADOW_SPREAD_SMALL = math.max(math.floor(LV_DPI_DEF / 30), 2)
local SHADOW_WIDTH_LARGE = math.max(math.floor(LV_DPI_DEF / 5), 10)
local SHADOW_OFS_X_LARGE = math.max(math.floor(LV_DPI_DEF / 10), 5)
local SHADOW_OFS_Y_LARGE = math.max(math.floor(LV_DPI_DEF / 10), 5)
local SHADOW_SPREAD_LARGE = math.max(math.floor(LV_DPI_DEF / 30), 2)
local IMG_WIDTH = 100
local IMG_HEIGHT = 100
local IMG_PATH = "/sd/cogwheel.png"
local IMG_NUM = math.max(math.floor((SCREEN_W * SCREEN_H) / 5 / IMG_WIDTH / IMG_HEIGHT), 1)
local IMG_ZOOM_MIN = 128
local IMG_ZOOM_MAX = 320
local LINE_WIDTH = math.max(math.floor(LV_DPI_DEF / 50), 2)
local LINE_POINT_NUM = 16
local LINE_POINT_DIFF_MIN = math.floor(LV_DPI_DEF / 10)
local LINE_POINT_DIFF_MAX = math.max(math.floor(SCREEN_W / (LINE_POINT_NUM + 2)), LINE_POINT_DIFF_MIN * 2)
local ARC_WIDTH_THIN = math.max(math.floor(LV_DPI_DEF / 50), 2)
local ARC_WIDTH_THICK = math.max(math.floor(LV_DPI_DEF / 10), 5)
local ANIM_TIME_MIN = math.floor((2 * SCENE_TIME) / 10)
local ANIM_TIME_MAX = SCENE_TIME
local HEADER_PAD = math.floor(LV_DPI_DEF / 30)

local TXT = "hello world\nit is a multi line text to test\nthe performance of text rendering"

local FONT12 = rawget(_G, "LV_FONT_MONTSERRAT_12") or 12
local FONT16 = rawget(_G, "LV_FONT_MONTSERRAT_16") or 16
local FONT28 = rawget(_G, "LV_FONT_MONTSERRAT_28") or 28
local FONT12_COMPR = rawget(_G, "LV_FONT_BENCHMARK_MONTSERRAT_12_COMPR_AZ") or rawget(_G, "lv_font_benchmark_montserrat_12_compr_az") or FONT12
local FONT16_COMPR = rawget(_G, "LV_FONT_BENCHMARK_MONTSERRAT_16_COMPR_AZ") or rawget(_G, "lv_font_benchmark_montserrat_16_compr_az") or FONT16
local FONT28_COMPR = rawget(_G, "LV_FONT_BENCHMARK_MONTSERRAT_28_COMPR_AZ") or rawget(_G, "lv_font_benchmark_montserrat_28_compr_az") or FONT28
local ANIM_REPEAT_INF = rawget(_G, "LV_ANIM_REPEAT_INFINITE") or 0xFFFF
local LINEAR_PATH = rawget(_G, "ANIM_PATH_LINEAR") or 0

local RND_MAP = {
  0xbd13204f, 0x67d8167f, 0x20211c99, 0xb0a7cc05,
  0x06d5c703, 0xeafb01a7, 0xd0473b5c, 0xc999aaa2,
  0x86f9d5d9, 0x294bdb29, 0x12a3c207, 0x78914d14,
  0x10a30006, 0x6134c7db, 0x194443af, 0x142d1099,
  0x376292d5, 0x20f433c5, 0x074d2a59, 0x4e74c293,
  0x072a0810, 0xdd0f136d, 0x5cca6dbc, 0x623bfdd8,
  0xb645eb2f, 0xbe50894a, 0xc9b56717, 0xe0f912c8,
  0x4f6b5e24, 0xfe44b128, 0xe12d57a8, 0x9b15c9cc,
  0xab2ae1d3, 0xb4dc5074, 0x67d457c8, 0x8e46b00c,
  0xa29a1871, 0xcee40332, 0x80f93aa1, 0x85286096,
  0x09bd6b49, 0x95072088, 0x2093924b, 0x6a27328f,
  0xa796079b, 0xc3b488bc, 0xe29bcce0, 0x07048a4c,
  0x7d81bd99, 0x27aacb30, 0x44fc7a0e, 0xa2382241,
  0x8357a17d, 0x97e9c9cc, 0xad10ff52, 0x9923fc5c,
  0x8f2c840a, 0x20356ba2, 0x7997a677, 0x9a7f1800,
  0x35c7562b, 0xd901fe51, 0x8f4e053d, 0xa5b94923,
}

APP.running = true
APP.timer = nil
APP.title = nil
APP.subtitle = nil
APP.scene_bg = nil
APP.scene = nil
APP.scene_act = 0
APP.opa_mode = false
APP.scene_started_ms = 0
APP.frame_count = 0
APP.rnd_act = 1
APP.summary_visible = false
APP.scene_y = 0
APP.scene_h = 0

APP.scenes = {
  { name = "Rectangle", weight = 30, create = "rectangle" },
  { name = "Rectangle rounded", weight = 20, create = "rectangle_rounded" },
  { name = "Circle", weight = 10, create = "rectangle_circle" },
  { name = "Border", weight = 20, create = "border" },
  { name = "Border rounded", weight = 30, create = "border_rounded" },
  { name = "Circle border", weight = 10, create = "border_circle" },
  { name = "Border top", weight = 3, create = "border_top" },
  { name = "Border left", weight = 3, create = "border_left" },
  { name = "Border top + left", weight = 3, create = "border_top_left" },
  { name = "Border left + right", weight = 3, create = "border_left_right" },
  { name = "Border top + bottom", weight = 3, create = "border_top_bottom" },
  { name = "Shadow small", weight = 3, create = "shadow_small" },
  { name = "Shadow small offset", weight = 5, create = "shadow_small_ofs" },
  { name = "Shadow large", weight = 5, create = "shadow_large" },
  { name = "Shadow large offset", weight = 3, create = "shadow_large_ofs" },
  { name = "Image RGB", weight = 20, create = "img_rgb" },
  { name = "Image ARGB", weight = 20, create = "img_argb" },
  { name = "Image chorma keyed", weight = 5, create = "img_ckey" },
  { name = "Image indexed", weight = 5, create = "img_index" },
  { name = "Image alpha only", weight = 5, create = "img_alpha" },
  { name = "Image RGB recolor", weight = 5, create = "img_rgb_recolor" },
  { name = "Image ARGB recolor", weight = 20, create = "img_argb_recolor" },
  { name = "Image chorma keyed recolor", weight = 3, create = "img_ckey_recolor" },
  { name = "Image indexed recolor", weight = 3, create = "img_index_recolor" },
  { name = "Image RGB rotate", weight = 3, create = "img_rgb_rot" },
  { name = "Image RGB rotate anti aliased", weight = 3, create = "img_rgb_rot_aa" },
  { name = "Image ARGB rotate", weight = 5, create = "img_argb_rot" },
  { name = "Image ARGB rotate anti aliased", weight = 5, create = "img_argb_rot_aa" },
  { name = "Image RGB zoom", weight = 3, create = "img_rgb_zoom" },
  { name = "Image RGB zoom anti aliased", weight = 3, create = "img_rgb_zoom_aa" },
  { name = "Image ARGB zoom", weight = 5, create = "img_argb_zoom" },
  { name = "Image ARGB zoom anti aliased", weight = 5, create = "img_argb_zoom_aa" },
  { name = "Text small", weight = 20, create = "txt_small" },
  { name = "Text medium", weight = 30, create = "txt_medium" },
  { name = "Text large", weight = 20, create = "txt_large" },
  { name = "Text small compressed", weight = 3, create = "txt_small_compr" },
  { name = "Text medium compressed", weight = 5, create = "txt_medium_compr" },
  { name = "Text large compressed", weight = 10, create = "txt_large_compr" },
  { name = "Line", weight = 10, create = "line" },
  { name = "Arc think", weight = 10, create = "arc_thin" },
  { name = "Arc thick", weight = 10, create = "arc_thick" },
  { name = "Substr. rectangle", weight = 10, create = "sub_rectangle" },
  { name = "Substr. border", weight = 10, create = "sub_border" },
  { name = "Substr. shadow", weight = 10, create = "sub_shadow" },
  { name = "Substr. image", weight = 10, create = "sub_img" },
  { name = "Substr. line", weight = 10, create = "sub_line" },
  { name = "Substr. arc", weight = 10, create = "sub_arc" },
  { name = "Substr. text", weight = 10, create = "sub_text" },
}

for i = 1, #APP.scenes do
  APP.scenes[i].fps_normal = 0
  APP.scenes[i].fps_opa = 0
end

-- 输出更完整的 Lua traceback，方便串口直接定位脚本错误。
local function traceback_handler(err)
  if debug and debug.traceback then
    local ok, trace = pcall(function()
      return debug.traceback(err, 2)
    end)
    if ok and trace then
      return trace
    end
  end
  return tostring(err)
end

-- 四舍五入到整数，避免位置和角度的小数抖动。
local function iround(v)
  return math.floor(v + 0.5)
end

-- 生成官方 fall_anim 对应的上下往返曲线。
local function ping_pong(elapsed_ms, period_ms, lo, hi, phase_ms)
  if hi <= lo then
    return lo
  end

  local phase = phase_ms or 0
  local pos = ((elapsed_ms + phase) % period_ms) / period_ms
  local t = pos * 2.0
  if t > 1.0 then
    t = 2.0 - t
  end

  return iround(lo + (hi - lo) * t)
end

-- 生成线性往返角度，用来代替官方 arc 动画。
local function saw(elapsed_ms, period_ms, lo, hi, phase_ms)
  if hi <= lo then
    return lo
  end

  local phase = phase_ms or 0
  local pos = ((elapsed_ms + phase) % period_ms) / period_ms
  return iround(lo + (hi - lo) * pos)
end

-- 重置固定伪随机序列表，保证每轮 normal/opa 的元素一致。
local function rnd_reset()
  APP.rnd_act = 1
end

-- 复刻官方 rnd_next：上界开区间，并按固定表循环取值。
local function rnd_next(min_v, max_v)
  if min_v == max_v then
    return min_v
  end

  if min_v > max_v then
    local t = min_v
    min_v = max_v
    max_v = t
  end

  local d = max_v - min_v
  if d <= 0 then
    return min_v
  end

  local r = (RND_MAP[APP.rnd_act] % d) + min_v
  APP.rnd_act = APP.rnd_act + 1
  if APP.rnd_act > #RND_MAP then
    APP.rnd_act = 1
  end

  return r
end

-- 创建基础标签，供标题和副标题复用。
local function create_label(parent, text, x, y, width, font)
  local id = lv_label_create(parent)
  lv_label_set_text(id, text or "")
  lv_obj_set_pos(id, x or 0, y or 0)
  if width then
    lv_obj_set_size(id, width, LV_SIZE_CONTENT)
  end
  if font then
    lv_obj_set_style_text_font(id, font, LV_PART_MAIN)
  end
  return id
end

-- 先更新标题区文本，再按最新高度重排副标题，避免左上角文字和场景区互相压住。
local function update_header_texts(title_text, subtitle_text)
  lv_label_set_text(APP.title, title_text or "")

  local title_h = lv_obj_get_height(APP.title)
  lv_obj_set_pos(APP.subtitle, HEADER_PAD, HEADER_PAD + title_h)
  lv_label_set_text(APP.subtitle, subtitle_text or "")
end

-- 重新创建场景容器，布局公式直接照官方 benchmark_init。
local function recreate_scene_bg()
  if APP.scene_bg then
    pcall(function()
      lv_obj_del(APP.scene_bg)
    end)
    APP.scene_bg = nil
  end

  local subtitle_h = lv_obj_get_height(APP.subtitle)
  local scene_y = HEADER_PAD + lv_obj_get_height(APP.title) + subtitle_h + HEADER_PAD
  if scene_y > SCREEN_H then
    scene_y = SCREEN_H
  end

  APP.scene_y = scene_y
  APP.scene_h = SCREEN_H - scene_y
  if APP.scene_h < 0 then
    APP.scene_h = 0
  end

  APP.scene_bg = lv_obj_create(ROOT)
  lv_obj_remove_style_all(APP.scene_bg)
  lv_obj_set_pos(APP.scene_bg, 0, APP.scene_y)
  lv_obj_set_size(APP.scene_bg, SCREEN_W, APP.scene_h)
  lv_obj_set_style_bg_opa(APP.scene_bg, 0, LV_PART_MAIN)
  lv_obj_set_style_border_width(APP.scene_bg, 0, LV_PART_MAIN)
  lv_obj_set_style_pad_all(APP.scene_bg, 0, LV_PART_MAIN)
end

-- 初始化 benchmark 外壳，采用官方的白底黑字简洁布局。
local function benchmark_init()
  clear_root()
  lv_obj_set_layout(ROOT, LV_LAYOUT_NONE)
  lv_obj_set_style_bg_color(ROOT, 0xFFFFFF, LV_PART_MAIN)
  lv_obj_set_style_bg_opa(ROOT, 255, LV_PART_MAIN)

  APP.title = create_label(ROOT, " ", HEADER_PAD, HEADER_PAD, nil, FONT16)
  APP.subtitle = create_label(ROOT, " ", HEADER_PAD, HEADER_PAD, nil, FONT12)
  lv_obj_set_style_text_color(APP.title, 0x000000, LV_PART_MAIN)
  lv_obj_set_style_text_color(APP.subtitle, 0x000000, LV_PART_MAIN)
  lv_obj_set_style_text_opa(APP.subtitle, 255, LV_PART_MAIN)

  update_header_texts(" ", " ")
  recreate_scene_bg()
end

-- 只在位置变化时下发命令，减少无意义的 UI 队列压力。
local function set_pos_if_changed(item, x, y)
  x = iround(x)
  y = iround(y)
  if item._x == x and item._y == y then
    return
  end
  item._x = x
  item._y = y
  lv_obj_set_pos(item.id, x, y)
end

-- 只在 transform angle 变化时下发命令。
local function set_obj_angle_if_changed(item, angle)
  angle = iround(angle)
  if item._angle == angle then
    return
  end
  item._angle = angle
  if item.use_img_transform then
    lv_img_set_angle(item.id, angle)
  else
    lv_obj_set_style_transform_angle(item.id, angle, LV_PART_MAIN)
  end
end

-- 只在 transform zoom 变化时下发命令。
local function set_obj_zoom_if_changed(item, zoom)
  zoom = iround(zoom)
  if item._zoom == zoom then
    return
  end
  item._zoom = zoom
  if item.use_img_transform then
    lv_img_set_zoom(item.id, zoom)
  else
    lv_obj_set_style_transform_zoom(item.id, zoom, LV_PART_MAIN)
  end
end

-- 只在 arc 终点角变化时下发命令。
local function set_arc_end_if_changed(item, end_angle)
  end_angle = iround(end_angle)
  if item._end_angle == end_angle then
    return
  end
  item._end_angle = end_angle
  lv_arc_set_angles(item.id, 0, end_angle)
end

-- 复刻官方 fall_anim 的随机 x / time / 初始半程进度。
local function build_fall_motion(motion_w, motion_h)
  local max_x = SCREEN_W - motion_w
  if max_x < 0 then
    max_x = 0
  end

  local max_y = APP.scene_h - motion_h
  if max_y < 0 then
    max_y = 0
  end

  local x = rnd_next(0, max_x + 1)
  local t = rnd_next(ANIM_TIME_MIN, ANIM_TIME_MAX)
  return {
    x = x,
    y_lo = 0,
    y_hi = max_y,
    anim_time = t,
    period = t * 2,
    phase = math.floor(t / 2),
  }
end

-- 把官方 fall_anim 的上下往返交给 LVGL 原生动画，避免 Lua 每 tick 逐帧推 Y。
-- 目前 Lua 动画接口还没有 act_time，起始相位会从顶部开始，无法做到官方“半程起步”。
local function start_native_fall_anim(item)
  set_pos_if_changed(item, item.x, item.y_lo)

  if item.y_hi <= item.y_lo then
    return
  end

  lv_anim_start(item.id, ANIM_Y, item.y_lo, item.y_hi, {
    time = item.anim_time,
    path = LINEAR_PATH,
    playback_time = item.anim_time,
    repeat_count = ANIM_REPEAT_INF,
    early_apply = true,
  })
end

-- 创建清空默认样式后的基础 box，便于模拟官方 remove_style_all + add_style。
local function create_bare_box(parent, w, h)
  local id = lv_obj_create(parent)
  lv_obj_remove_style_all(id)
  lv_obj_set_size(id, w, h)
  lv_obj_clear_flag(id, LV_OBJ_FLAG_SCROLLABLE)
  lv_obj_set_style_pad_all(id, 0, LV_PART_MAIN)
  lv_obj_set_style_border_width(id, 0, LV_PART_MAIN)
  lv_obj_set_style_shadow_width(id, 0, LV_PART_MAIN)
  lv_obj_set_style_radius(id, 0, LV_PART_MAIN)
  lv_obj_set_style_bg_opa(id, 255, LV_PART_MAIN)
  return id
end

-- 只有在场景需要时才设置 blend_mode，保持普通场景和官方默认一致。
local function apply_blend_mode_if_needed(obj, blend_mode, selector)
  if not blend_mode then
    return
  end
  lv_obj_set_style_blend_mode(obj, blend_mode, selector or LV_PART_MAIN)
end

-- 复刻官方 rect_create：颜色、尺寸、位置的随机顺序保持一致。
local function create_rect_scene(style)
  local scene = { items = {} }

  for _ = 1, OBJ_NUM do
    local bg_color = rnd_next(0, 0xFFFFF0)
    local border_color = rnd_next(0, 0xFFFFF0)
    local shadow_color = rnd_next(0, 0xFFFFF0)
    local w = rnd_next(OBJ_SIZE_MIN, OBJ_SIZE_MAX)
    local h = rnd_next(OBJ_SIZE_MIN, OBJ_SIZE_MAX)

    local obj = create_bare_box(APP.scene_bg, w, h)
    lv_obj_set_style_bg_color(obj, bg_color, LV_PART_MAIN)
    lv_obj_set_style_border_color(obj, border_color, LV_PART_MAIN)
    lv_obj_set_style_shadow_color(obj, shadow_color, LV_PART_MAIN)

    if style.bg_opa then
      lv_obj_set_style_bg_opa(obj, style.bg_opa, LV_PART_MAIN)
    else
      lv_obj_set_style_bg_opa(obj, 0, LV_PART_MAIN)
    end

    if style.radius then
      lv_obj_set_style_radius(obj, style.radius, LV_PART_MAIN)
    end

    if style.border_width then
      lv_obj_set_style_border_width(obj, style.border_width, LV_PART_MAIN)
      lv_obj_set_style_border_opa(obj, style.border_opa or 255, LV_PART_MAIN)
      lv_obj_set_style_border_side(obj, style.border_side or LV_BORDER_SIDE_FULL, LV_PART_MAIN)
    end

    if style.shadow_width then
      lv_obj_set_style_shadow_width(obj, style.shadow_width, LV_PART_MAIN)
      lv_obj_set_style_shadow_opa(obj, style.shadow_opa or 255, LV_PART_MAIN)
      lv_obj_set_style_shadow_ofs_x(obj, style.shadow_ofs_x or 0, LV_PART_MAIN)
      lv_obj_set_style_shadow_ofs_y(obj, style.shadow_ofs_y or 0, LV_PART_MAIN)
      lv_obj_set_style_shadow_spread(obj, style.shadow_spread or 0, LV_PART_MAIN)
    end
    apply_blend_mode_if_needed(obj, style.blend_mode, LV_PART_MAIN)

    local motion = build_fall_motion(w, h)
    local item = {
      id = obj,
      x = motion.x,
      y_lo = motion.y_lo,
      y_hi = motion.y_hi,
      anim_time = motion.anim_time,
      period = motion.period,
      phase = motion.phase,
    }

    start_native_fall_anim(item)
    scene.items[#scene.items + 1] = item
  end

  return scene
end

-- 图片场景统一从 SD 根目录读取 cogwheel.png，并按官方 img_create 的随机顺序设置 recolor/rotate/zoom。
local function create_image_scene(style)
  local scene = { items = {} }

  for _ = 1, IMG_NUM do
    local recolor = rnd_next(0, 0xFFFFF0)
    local angle = nil
    local zoom = nil
    if style.rotate then
      angle = rnd_next(0, 3599)
    end
    if style.zoom then
      zoom = rnd_next(IMG_ZOOM_MIN, IMG_ZOOM_MAX)
    end

    local obj = lv_img_create(APP.scene_bg)
    lv_obj_remove_style_all(obj)
    lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT)
    lv_obj_clear_flag(obj, LV_OBJ_FLAG_SCROLLABLE)
    lv_img_set_src(obj, IMG_PATH)
    lv_img_set_pivot(obj, math.floor(IMG_WIDTH / 2), math.floor(IMG_HEIGHT / 2))
    lv_obj_set_style_img_opa(obj, style.img_opa or 255, LV_PART_MAIN)
    lv_obj_set_style_img_recolor(obj, recolor, LV_PART_MAIN)
    lv_obj_set_style_img_recolor_opa(obj, style.recolor_opa or 0, LV_PART_MAIN)
    if lv_img_set_antialias then
      lv_img_set_antialias(obj, style.antialias and true or false)
    end
    apply_blend_mode_if_needed(obj, style.blend_mode, LV_PART_MAIN)

    local motion = build_fall_motion(IMG_WIDTH, IMG_HEIGHT)
    local item = {
      id = obj,
      x = motion.x,
      y_lo = motion.y_lo,
      y_hi = motion.y_hi,
      anim_time = motion.anim_time,
      period = motion.period,
      phase = motion.phase,
      use_img_transform = true,
    }

    start_native_fall_anim(item)
    if angle then
      set_obj_angle_if_changed(item, angle)
    end
    if zoom then
      set_obj_zoom_if_changed(item, zoom)
    end

    scene.items[#scene.items + 1] = item
  end

  return scene
end

-- 文本场景照官方 txt_create：颜色、字体、位置的随机顺序不变。
local function create_text_scene(font_ref, text_opa, blend_mode)
  local scene = { items = {} }

  for _ = 1, OBJ_NUM do
    local color = rnd_next(0, 0xFFFFF0)
    local obj = lv_label_create(APP.scene_bg)
    lv_obj_remove_style_all(obj)
    lv_obj_clear_flag(obj, LV_OBJ_FLAG_SCROLLABLE)
    lv_obj_set_style_text_font(obj, font_ref, LV_PART_MAIN)
    lv_obj_set_style_text_color(obj, color, LV_PART_MAIN)
    lv_obj_set_style_text_opa(obj, text_opa or 255, LV_PART_MAIN)
    apply_blend_mode_if_needed(obj, blend_mode, LV_PART_MAIN)
    lv_label_set_text(obj, TXT)

    local w = lv_obj_get_width(obj)
    local h = lv_obj_get_height(obj)
    local motion = build_fall_motion(w, h)
    local item = {
      id = obj,
      x = motion.x,
      y_lo = motion.y_lo,
      y_hi = motion.y_hi,
      anim_time = motion.anim_time,
      period = motion.period,
      phase = motion.phase,
    }

    start_native_fall_anim(item)
    scene.items[#scene.items + 1] = item
  end

  return scene
end

-- 线场景改为直接使用 lv_line，随机点序列与官方 line_create 保持一致。
local function create_line_scene(line_opa, blend_mode)
  local scene = { items = {} }

  for _ = 1, OBJ_NUM do
    local points = { 0, 0 }
    local last_x = 0
    local max_y = 0

    for _ = 2, LINE_POINT_NUM do
      last_x = last_x + rnd_next(LINE_POINT_DIFF_MIN, LINE_POINT_DIFF_MAX)
      local py = rnd_next(LINE_POINT_DIFF_MIN, LINE_POINT_DIFF_MAX)
      if py > max_y then
        max_y = py
      end
      points[#points + 1] = last_x
      points[#points + 1] = py
    end

    local color = rnd_next(0, 0xFFFFF0)
    local obj = lv_line_create(APP.scene_bg)
    lv_obj_remove_style_all(obj)
    lv_obj_set_style_line_width(obj, LINE_WIDTH, LV_PART_MAIN)
    lv_obj_set_style_line_opa(obj, line_opa or 255, LV_PART_MAIN)
    lv_obj_set_style_line_color(obj, color, LV_PART_MAIN)
    apply_blend_mode_if_needed(obj, blend_mode, LV_PART_MAIN)
    lv_line_set_points(obj, points)

    local motion_w = lv_obj_get_width(obj)
    local motion_h = lv_obj_get_height(obj)
    if motion_w < 1 then
      motion_w = last_x
    end
    if motion_h < 1 then
      motion_h = max_y
    end
    if motion_w < 1 then
      motion_w = LINE_WIDTH
    end
    if motion_h < 1 then
      motion_h = LINE_WIDTH
    end

    local motion = build_fall_motion(motion_w, motion_h)
    local item = {
      id = obj,
      x = motion.x,
      y_lo = motion.y_lo,
      y_hi = motion.y_hi,
      anim_time = motion.anim_time,
      period = motion.period,
      phase = motion.phase,
    }

    start_native_fall_anim(item)
    scene.items[#scene.items + 1] = item
  end

  return scene
end

-- 弧线场景复制官方 arc_create 的随机尺寸、颜色、角度周期和掉落动画。
local function create_arc_scene(arc_width, arc_opa, blend_mode)
  local scene = { items = {} }

  for _ = 1, OBJ_NUM do
    local w = rnd_next(OBJ_SIZE_MIN, OBJ_SIZE_MAX)
    local h = rnd_next(OBJ_SIZE_MIN, OBJ_SIZE_MAX)
    local color = rnd_next(0, 0xFFFFF0)
    local t = rnd_next(math.max(math.floor(ANIM_TIME_MIN / 4), 1), math.max(math.floor(ANIM_TIME_MAX / 4), 2))

    local obj = lv_arc_create(APP.scene_bg)
    lv_obj_remove_style_all(obj)
    lv_obj_set_size(obj, w, h)
    lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE)
    lv_obj_clear_flag(obj, LV_OBJ_FLAG_SCROLLABLE)
    lv_obj_set_style_bg_opa(obj, 0, LV_PART_MAIN)
    lv_obj_set_style_border_width(obj, 0, LV_PART_MAIN)
    lv_obj_set_style_arc_width(obj, 0, LV_PART_MAIN)
    lv_obj_set_style_arc_width(obj, arc_width, LV_PART_INDICATOR)
    lv_obj_set_style_arc_color(obj, color, LV_PART_INDICATOR)
    lv_obj_set_style_arc_opa(obj, arc_opa or 255, LV_PART_INDICATOR)
    apply_blend_mode_if_needed(obj, blend_mode, LV_PART_INDICATOR)
    lv_obj_set_style_opa(obj, 0, LV_PART_KNOB)
    lv_arc_set_bg_angles(obj, 0, 360)
    lv_arc_set_angles(obj, 0, 0)

    local motion = build_fall_motion(w, h)
    local item = {
      id = obj,
      x = motion.x,
      y_lo = motion.y_lo,
      y_hi = motion.y_hi,
      anim_time = motion.anim_time,
      period = motion.period,
      phase = motion.phase,
      arc_period = t * 2,
      arc_phase = math.floor(t / 2),
    }

    start_native_fall_anim(item)
    set_arc_end_if_changed(item, ping_pong(0, item.arc_period, 0, 359, item.arc_phase))
    scene.items[#scene.items + 1] = item
  end

  -- 弧线场景只保留 end angle 的 Lua 更新；上下移动已经交给原生 ANIM_Y。
  function scene.update(self, elapsed_ms)
    for i = 1, #self.items do
      local item = self.items[i]
      local end_angle = ping_pong(elapsed_ms, item.arc_period, 0, 359, item.arc_phase)
      set_arc_end_if_changed(item, end_angle)
    end
  end

  return scene
end

-- 依官方 scene 列表派发构造函数；图片场景统一使用 SD 卡上的 cogwheel.png。
local function build_scene(kind, opa_mode)
  local bg_opa = opa_mode and 128 or 255
  local shadow_opa = opa_mode and 204 or 255
  local text_opa = opa_mode and 128 or 255

  if kind == "rectangle" then
    return create_rect_scene({ bg_opa = bg_opa })
  elseif kind == "rectangle_rounded" then
    return create_rect_scene({ radius = RADIUS, bg_opa = bg_opa })
  elseif kind == "rectangle_circle" then
    return create_rect_scene({ radius = 1000, bg_opa = bg_opa })
  elseif kind == "border" then
    return create_rect_scene({ border_width = BORDER_WIDTH, border_opa = bg_opa })
  elseif kind == "border_rounded" then
    return create_rect_scene({ radius = RADIUS, border_width = BORDER_WIDTH, border_opa = bg_opa })
  elseif kind == "border_circle" then
    return create_rect_scene({ radius = 1000, border_width = BORDER_WIDTH, border_opa = bg_opa })
  elseif kind == "border_top" then
    return create_rect_scene({ radius = RADIUS, border_width = BORDER_WIDTH, border_opa = bg_opa, border_side = LV_BORDER_SIDE_TOP })
  elseif kind == "border_left" then
    return create_rect_scene({ radius = RADIUS, border_width = BORDER_WIDTH, border_opa = bg_opa, border_side = LV_BORDER_SIDE_LEFT })
  elseif kind == "border_top_left" then
    return create_rect_scene({ radius = RADIUS, border_width = BORDER_WIDTH, border_opa = bg_opa, border_side = LV_BORDER_SIDE_LEFT | LV_BORDER_SIDE_TOP })
  elseif kind == "border_left_right" then
    return create_rect_scene({ radius = RADIUS, border_width = BORDER_WIDTH, border_opa = bg_opa, border_side = LV_BORDER_SIDE_LEFT | LV_BORDER_SIDE_RIGHT })
  elseif kind == "border_top_bottom" then
    return create_rect_scene({ radius = RADIUS, border_width = BORDER_WIDTH, border_opa = bg_opa, border_side = LV_BORDER_SIDE_TOP | LV_BORDER_SIDE_BOTTOM })
  elseif kind == "shadow_small" then
    return create_rect_scene({ radius = RADIUS, bg_opa = 255, shadow_width = SHADOW_WIDTH_SMALL, shadow_opa = shadow_opa })
  elseif kind == "shadow_small_ofs" then
    return create_rect_scene({
      radius = RADIUS,
      bg_opa = 255,
      shadow_width = SHADOW_WIDTH_SMALL,
      shadow_opa = shadow_opa,
      shadow_ofs_x = SHADOW_OFS_X_SMALL,
      shadow_ofs_y = SHADOW_OFS_Y_SMALL,
      shadow_spread = SHADOW_SPREAD_SMALL,
    })
  elseif kind == "shadow_large" then
    return create_rect_scene({ radius = RADIUS, bg_opa = 255, shadow_width = SHADOW_WIDTH_LARGE, shadow_opa = shadow_opa })
  elseif kind == "shadow_large_ofs" then
    return create_rect_scene({
      radius = RADIUS,
      bg_opa = 255,
      shadow_width = SHADOW_WIDTH_LARGE,
      shadow_opa = shadow_opa,
      shadow_ofs_x = SHADOW_OFS_X_LARGE,
      shadow_ofs_y = SHADOW_OFS_Y_LARGE,
      shadow_spread = SHADOW_SPREAD_LARGE,
    })
  elseif kind == "img_rgb" or kind == "img_argb" or kind == "img_ckey" or kind == "img_index" or kind == "img_alpha" then
    return create_image_scene({ img_opa = bg_opa, antialias = false })
  elseif kind == "img_rgb_recolor" or kind == "img_argb_recolor" or kind == "img_ckey_recolor" or kind == "img_index_recolor" then
    return create_image_scene({ img_opa = bg_opa, recolor_opa = 128, antialias = false })
  elseif kind == "img_rgb_rot" or kind == "img_rgb_rot_aa" or kind == "img_argb_rot" or kind == "img_argb_rot_aa" then
    return create_image_scene({
      img_opa = bg_opa,
      rotate = true,
      antialias = kind == "img_rgb_rot_aa" or kind == "img_argb_rot_aa",
    })
  elseif kind == "img_rgb_zoom" or kind == "img_rgb_zoom_aa" or kind == "img_argb_zoom" or kind == "img_argb_zoom_aa" then
    return create_image_scene({
      img_opa = bg_opa,
      zoom = true,
      antialias = kind == "img_rgb_zoom_aa" or kind == "img_argb_zoom_aa",
    })
  elseif kind == "txt_small" then
    return create_text_scene(FONT12, text_opa)
  elseif kind == "txt_medium" then
    return create_text_scene(FONT16, text_opa)
  elseif kind == "txt_large" then
    return create_text_scene(FONT28, text_opa)
  elseif kind == "txt_small_compr" then
    return create_text_scene(FONT12_COMPR, text_opa)
  elseif kind == "txt_medium_compr" then
    return create_text_scene(FONT16_COMPR, text_opa)
  elseif kind == "txt_large_compr" then
    return create_text_scene(FONT28_COMPR, text_opa)
  elseif kind == "line" then
    return create_line_scene(bg_opa)
  elseif kind == "arc_thin" then
    return create_arc_scene(ARC_WIDTH_THIN, bg_opa)
  elseif kind == "arc_thick" then
    return create_arc_scene(ARC_WIDTH_THICK, bg_opa)
  elseif kind == "sub_rectangle" then
    return create_rect_scene({ radius = RADIUS, bg_opa = bg_opa, blend_mode = LV_BLEND_MODE_SUBTRACTIVE })
  elseif kind == "sub_border" then
    return create_rect_scene({ radius = RADIUS, border_width = BORDER_WIDTH, border_opa = bg_opa, blend_mode = LV_BLEND_MODE_SUBTRACTIVE })
  elseif kind == "sub_shadow" then
    return create_rect_scene({
      radius = RADIUS,
      bg_opa = 255,
      shadow_width = SHADOW_WIDTH_SMALL,
      shadow_spread = SHADOW_WIDTH_SMALL,
      shadow_opa = shadow_opa,
      blend_mode = LV_BLEND_MODE_SUBTRACTIVE,
    })
  elseif kind == "sub_img" then
    return create_image_scene({ img_opa = bg_opa, blend_mode = LV_BLEND_MODE_SUBTRACTIVE, antialias = false })
  elseif kind == "sub_line" then
    return create_line_scene(bg_opa, LV_BLEND_MODE_SUBTRACTIVE)
  elseif kind == "sub_arc" then
    return create_arc_scene(ARC_WIDTH_THICK, bg_opa, LV_BLEND_MODE_SUBTRACTIVE)
  elseif kind == "sub_text" then
    return create_text_scene(FONT16, text_opa, LV_BLEND_MODE_SUBTRACTIVE)
  end

  return nil
end

-- 生成与官方一致的标题格式，run index 使用 0-based 编号。
local function make_scene_title(scene_index, opa_mode)
  local total = #APP.scenes * 2
  local spec = APP.scenes[scene_index]
  local run_no = (scene_index - 1) * 2 + (opa_mode and 1 or 0)
  return string.format("%d/%d: %s%s", run_no, total, spec.name, opa_mode and " + opa" or "")
end

-- 副标题逻辑直接照官方：显示上一轮结果，便于 normal / opa 对照。
local function make_scene_subtitle(scene_index, opa_mode)
  if opa_mode then
    local spec = APP.scenes[scene_index]
    return string.format("Result of \"%s\": %d FPS", spec.name, spec.fps_normal or 0)
  end

  if scene_index > 1 then
    local prev_spec = APP.scenes[scene_index - 1]
    return string.format("Result of \"%s + opa\": %d FPS", prev_spec.name, prev_spec.fps_opa or 0)
  end

  return ""
end

-- 开始一轮前重置测量状态；有 monitor API 时优先清空真实 LVGL 统计。
local function reset_scene_measurement()
  APP.frame_count = 0

  if HAS_REAL_MONITOR then
    pcall(function()
      lv_lvgl_monitor_reset()
    end)
  end
end

-- 读取当前轮次的测量快照；优先返回真实 monitor 数据，缺失时再回退到 tick 估算。
local function get_scene_measurement(now_ms)
  if HAS_REAL_MONITOR then
    local ok, render_cnt, time_sum_ms, px_sum, last_time_ms, last_px = pcall(lv_lvgl_monitor_get)
    if ok then
      return true,
        tonumber(render_cnt) or 0,
        tonumber(time_sum_ms) or 0,
        tonumber(px_sum) or 0,
        tonumber(last_time_ms) or 0,
        tonumber(last_px) or 0
    end
  end

  local measured_ms = now_ms - APP.scene_started_ms
  if measured_ms < 1 then
    measured_ms = 1
  end

  return false, APP.frame_count, measured_ms, 0, 0, 0
end

-- 启动一轮 benchmark，重建 scene_bg 并按官方顺序创建元素。
local function start_scene(scene_index, opa_mode, now_ms)
  pcall(function()
    APP.timer:interval(TICK_MS)
  end)

  APP.scene_act = scene_index
  APP.opa_mode = opa_mode and true or false
  APP.summary_visible = false
  APP.scene_started_ms = now_ms
  APP.scene = nil

  reset_scene_measurement()
  update_header_texts(make_scene_title(scene_index, APP.opa_mode), make_scene_subtitle(scene_index, APP.opa_mode))
  recreate_scene_bg()

  rnd_reset()
  APP.scene = build_scene(APP.scenes[scene_index].create, APP.opa_mode)
end

-- 优先使用真实 LVGL monitor 统计计算 FPS；旧固件再回退到 tick 估算。
local function record_scene_result(now_ms)
  if APP.scene_act < 1 or APP.scene_act > #APP.scenes then
    return
  end

  local using_monitor, render_cnt, time_sum_ms, px_sum = get_scene_measurement(now_ms)
  local denom_ms = time_sum_ms
  if denom_ms < 1 then
    denom_ms = 1
  end

  local fps = math.floor(((1000 * render_cnt) / denom_ms) + 0.5)
  local spec = APP.scenes[APP.scene_act]
  local source_tag = using_monitor and "monitor" or "tick"

  if APP.opa_mode then
    spec.fps_opa = fps
    print(string.format("Result of \"%s + opa\": %d FPS [%s cnt=%d time=%dms px=%d]", spec.name, fps, source_tag, render_cnt, time_sum_ms, px_sum))
  else
    spec.fps_normal = fps
    print(string.format("Result of \"%s\": %d FPS [%s cnt=%d time=%dms px=%d]", spec.name, fps, source_tag, render_cnt, time_sum_ms, px_sum))
  end
end

-- 依照官方顺序切换到下一轮：先 normal，再同场景 opa，再进入下一个场景。
local function next_scene(now_ms)
  if APP.scene_act > 0 then
    record_scene_result(now_ms)
  end

  if APP.opa_mode then
    local next_index = APP.scene_act + 1
    if next_index > #APP.scenes then
      return nil
    end
    start_scene(next_index, false, now_ms)
    return true
  end

  start_scene(APP.scene_act, true, now_ms)
  return true
end

-- 计算官方 weighted FPS 与 opacity speed，公式保持一致。
local function compute_summary()
  local weight_sum = 0
  local weight_normal_sum = 0
  local weight_opa_sum = 0
  local fps_sum = 0
  local fps_normal_sum = 0
  local fps_opa_sum = 0

  for i = 1, #APP.scenes do
    local spec = APP.scenes[i]
    fps_normal_sum = fps_normal_sum + (spec.fps_normal or 0) * spec.weight
    weight_normal_sum = weight_normal_sum + spec.weight

    local w = math.max(math.floor(spec.weight / 2), 1)
    fps_opa_sum = fps_opa_sum + (spec.fps_opa or 0) * w
    weight_opa_sum = weight_opa_sum + w
  end

  fps_sum = fps_normal_sum + fps_opa_sum
  weight_sum = weight_normal_sum + weight_opa_sum

  local fps_weighted = 0
  local fps_normal_weighted = 0
  local fps_opa_weighted = 0
  if weight_sum > 0 then
    fps_weighted = math.floor(fps_sum / weight_sum)
  end
  if weight_normal_sum > 0 then
    fps_normal_weighted = math.floor(fps_normal_sum / weight_normal_sum)
  end
  if weight_opa_sum > 0 then
    fps_opa_weighted = math.floor(fps_opa_sum / weight_opa_sum)
  end

  local opa_speed_pct = 0
  if fps_normal_weighted > 0 then
    opa_speed_pct = math.floor((fps_opa_weighted * 100) / fps_normal_weighted)
  end

  return fps_weighted, opa_speed_pct
end

-- 官方 summary 里“Slow but common cases”的筛选规则。
local function is_slow_common(spec, with_opa)
  if with_opa then
    return (spec.fps_opa or 0) < 20 and math.max(math.floor(spec.weight / 2), 1) >= 10
  end

  return (spec.fps_normal or 0) < 20 and spec.weight >= 10
end

-- 在 root 上按官方 generate_report 结构重建 summary：title/subtitle/table 直挂 root。
local function show_summary()
  local fps_weighted, opa_speed_pct = compute_summary()
  local slow_rows = 0

  for i = 1, #APP.scenes do
    local spec = APP.scenes[i]
    if is_slow_common(spec, false) then
      slow_rows = slow_rows + 1
    end
    if is_slow_common(spec, true) then
      slow_rows = slow_rows + 1
    end
  end

  local row_cnt = 1 + math.max(slow_rows, 1) + 1 + (#APP.scenes * 2)

  APP.summary_visible = true
  APP.scene = nil
  APP.scene_bg = nil

  pcall(function()
    APP.timer:interval(120)
  end)

  clear_root()
  lv_obj_set_layout(ROOT, LV_LAYOUT_FLEX)
  lv_obj_set_flex_flow(ROOT, LV_FLEX_FLOW_COLUMN)
  lv_obj_set_flex_align(ROOT, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_START)
  lv_obj_set_style_bg_color(ROOT, 0xFFFFFF, LV_PART_MAIN)
  lv_obj_set_style_bg_opa(ROOT, 255, LV_PART_MAIN)

  APP.title = create_label(ROOT, string.format("Weighted FPS: %d", fps_weighted), 0, 0, nil, FONT16)
  APP.subtitle = create_label(ROOT, string.format("Opa. speed: %d%%", opa_speed_pct), 0, 0, nil, FONT12)
  lv_obj_set_style_text_color(APP.title, 0x000000, LV_PART_MAIN)
  lv_obj_set_style_text_color(APP.subtitle, 0x000000, LV_PART_MAIN)
  lv_obj_set_style_text_opa(APP.subtitle, 255, LV_PART_MAIN)

  local table_id = lv_table_create(ROOT)
  lv_table_set_col_cnt(table_id, 2)
  lv_table_set_row_cnt(table_id, row_cnt)
  lv_table_set_col_width(table_id, 0, math.floor((SCREEN_W * 3) / 4) - 3)
  lv_table_set_col_width(table_id, 1, math.floor(SCREEN_W / 4) - 3)
  lv_obj_set_width(table_id, lv_pct(100))

  local row = 0
  lv_table_add_cell_ctrl(table_id, row, 0, LV_TABLE_CELL_CTRL_MERGE_RIGHT)
  lv_table_set_cell_value(table_id, row, 0, "Slow but common cases")
  row = row + 1

  print("")
  print("LVGL Lua Benchmark (official scene list emulation)")
  print(string.format("Weighted FPS: %d", fps_weighted))
  print(string.format("Opa. speed: %d%%", opa_speed_pct))

  for i = 1, #APP.scenes do
    local spec = APP.scenes[i]

    if is_slow_common(spec, false) then
      lv_table_set_cell_value(table_id, row, 0, spec.name)
      lv_table_set_cell_value(table_id, row, 1, tostring(spec.fps_normal or 0))
      row = row + 1
    end

    if is_slow_common(spec, true) then
      lv_table_set_cell_value(table_id, row, 0, spec.name .. " + opa")
      lv_table_set_cell_value(table_id, row, 1, tostring(spec.fps_opa or 0))
      row = row + 1
    end
  end

  if slow_rows == 0 then
    lv_table_add_cell_ctrl(table_id, row, 0, LV_TABLE_CELL_CTRL_MERGE_RIGHT)
    lv_table_set_cell_value(table_id, row, 0, "All good")
    row = row + 1
  end

  lv_table_add_cell_ctrl(table_id, row, 0, LV_TABLE_CELL_CTRL_MERGE_RIGHT)
  lv_table_set_cell_value(table_id, row, 0, "All cases")
  row = row + 1

  for i = 1, #APP.scenes do
    local spec = APP.scenes[i]

    lv_table_set_cell_value(table_id, row, 0, spec.name)
    lv_table_set_cell_value(table_id, row, 1, tostring(spec.fps_normal or 0))
    print(string.format("%s,%d", spec.name, spec.fps_normal or 0))
    row = row + 1

    lv_table_set_cell_value(table_id, row, 0, spec.name .. " + opa")
    lv_table_set_cell_value(table_id, row, 1, tostring(spec.fps_opa or 0))
    print(string.format("%s + opa,%d", spec.name, spec.fps_opa or 0))
    row = row + 1
  end
end

-- 主循环负责推进 scene，并在每个 1000ms 场景结束后切换下一轮。
local function app_tick()
  if not APP.running then
    return
  end

  if app.exiting() then
    APP.shutdown()
    return
  end

  local now_ms = millis() or 0

  if APP.summary_visible then
    return
  end

  if not APP.title or not APP.subtitle or not APP.scene_bg then
    benchmark_init()
    start_scene(1, false, now_ms)
    return
  end

  if APP.scene and APP.scene.update then
    APP.scene:update(now_ms - APP.scene_started_ms)
  end

  APP.frame_count = APP.frame_count + 1

  if (now_ms - APP.scene_started_ms) >= SCENE_TIME then
    local ok = next_scene(now_ms)
    if not ok then
      show_summary()
    end
  end
end

-- 停止 timer 并清空页面，保证重复打开 benchmark 不残留旧实例。
function APP.shutdown()
  if not APP.running then
    return
  end

  APP.running = false

  if APP.timer then
    pcall(function()
      APP.timer:stop()
    end)
    pcall(function()
      APP.timer:unregister()
    end)
    APP.timer = nil
  end

  if APP.scene_bg then
    pcall(function()
      lv_obj_del(APP.scene_bg)
    end)
    APP.scene_bg = nil
  end

  clear_root()

  _G.LVGL_BENCHMARK_APP = nil
end

APP.timer = tmr.create()
APP.timer:alarm(TICK_MS, tmr.ALARM_AUTO, function()
  local ok, err = xpcall(app_tick, traceback_handler)
  if not ok then
    print("[lvgldemo] fatal:", err)
    APP.shutdown()
  end
end)

print("[lvgldemo] started", APP.VERSION, HAS_REAL_MONITOR and "monitor" or "tick")
