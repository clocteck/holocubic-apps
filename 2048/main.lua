local prev = rawget(_G, "APP_2048")
if prev and prev.stop then
  pcall(function()
    prev.stop("reload")
  end)
end

APP_2048 = {
  font_handles = {}
}

local APP = APP_2048
local json = rawget(_G, "sjson") or rawget(_G, "json")
local function clear_root()
  if not lv_scr_act or not lv_obj_clean then
    return
  end
  local ok, root = pcall(function()
    return lv_scr_act()
  end)
  if not ok or not root or not lv_obj_clean then
    return
  end
  pcall(function()
    pcall(lv_obj_clean, root)
  end)
end
local lv_begin = lv_begin or lv_canvas_frame_begin or lv_canvas_begin
local lv_end = lv_end or lv_canvas_frame_end or lv_canvas_end
local lv_anim_delete = lv_anim_delete or lv_anim_del
local lv_img_free_handle = lv_img_free_handle or (lv_snapshot_free and function(handle)
  if handle then
    pcall(function() lv_snapshot_free(handle) end)
  end
end) or function() end
local root = lv_scr_act()
local MAIN_STYLE = LV_PART_MAIN | LV_STATE_DEFAULT
local FONT_18 = rawget(_G, "LV_FONT_MONTSERRAT_16") or 16

local function load_font_ref(path, fallback)
  if lv_font_load then
    local ok, handle = pcall(function()
      return lv_font_load(path)
    end)
    if ok and type(handle) == "number" and handle > 0 then
      APP.font_handles[#APP.font_handles + 1] = handle
      return handle
    end
  end
  return fallback
end

local function init_fonts()
  FONT_18 = load_font_ref("/sd/apps/2048/font/tile_18.bin", FONT_18)
end

local function release_fonts()
  if lv_font_free then
    for _, handle in ipairs(APP.font_handles) do
      pcall(function()
        lv_font_free(handle)
      end)
    end
  end
  APP.font_handles = {}
end

init_fonts()

local screen_w = 320
local screen_h = 240

local board_size = 240
local board_x = 0
local board_y = 0

local side_x = 246
local side_y = 44
local side_w = 68
local side_h = 152
local over_w = 220
local over_h = 160
local over_x = math.floor((screen_w - over_w) / 2)
local over_y = math.floor((screen_h - over_h) / 2)

local gap = 5
local cell_size = math.floor((board_size - gap * 5) / 4)
local grid_pad = math.floor((board_size - (cell_size * 4 + gap * 5)) / 2)
local cell_radius = 6

local C = {
  bg_top = 0x120E0C,
  bg_bottom = 0x221913,
  board = 0x6B5A50,
  board_grad = 0x7A665A,
  board_border = 0xC9B09A,
  panel_bg = 0x2B2018,
  panel_inner = 0x463226,
  panel_border = 0x8E6B4C,
  over_dim = 0x050303,
  over_glass = 0xE7D9CA,
  over_glass_hi = 0xBF946B,
  over_border = 0xFFF1E1,
  shadow = 0x060404,
  text_main = 0xFFF7EF,
  text_soft = 0xD7C4B1,
  title_accent = 0xF0B247,
  tile_dark = 0x5F5148,
  tile_light = 0xFFF8F0,
}

-- 用 begin/end 包住对象切换边界，避免删建和动画初始态被半途刷出来。
local function with_lv_batch(fn)
  if not fn then
    return
  end

  if not lv_begin or not lv_end then
    return fn()
  end

  lv_begin()
  local ok, result = xpcall(fn, function(err)
    return tostring(err)
  end)

  local end_ok, end_err = pcall(function() lv_end() end)
  if not end_ok then
    error("[2048] lv_end failed: " .. tostring(end_err), 0)
  end

  if not ok then
    error(result, 0)
  end

  return result
end

local function clear_scroll_flag(obj)
  if not obj or not lv_obj_clear_flag then
    return
  end
  pcall(function() lv_obj_clear_flag(obj, LV_OBJ_FLAG_SCROLLABLE) end)
end

local function set_visible(obj, visible)
  if not obj or not lv_obj_add_flag or not lv_obj_clear_flag then
    return
  end
  if visible then
    pcall(function() lv_obj_clear_flag(obj, LV_OBJ_FLAG_HIDDEN) end)
  else
    pcall(function() lv_obj_add_flag(obj, LV_OBJ_FLAG_HIDDEN) end)
  end
end

local function set_shadow(obj, width, color, opa, ofs_y)
  if not obj then
    return
  end
  if not (lv_obj_set_style_shadow_width and lv_obj_set_style_shadow_color and lv_obj_set_style_shadow_opa) then
    return
  end

  local real_width = width or 0
  lv_obj_set_style_shadow_width(obj, real_width, MAIN_STYLE)
  lv_obj_set_style_shadow_color(obj, color or C.shadow, MAIN_STYLE)
  lv_obj_set_style_shadow_opa(obj, real_width > 0 and (opa or 96) or 0, MAIN_STYLE)

  if lv_obj_set_style_shadow_ofs_x then
    lv_obj_set_style_shadow_ofs_x(obj, 0, MAIN_STYLE)
  end
  if lv_obj_set_style_shadow_ofs_y then
    lv_obj_set_style_shadow_ofs_y(obj, ofs_y or 0, MAIN_STYLE)
  end
  if lv_obj_set_style_shadow_spread then
    lv_obj_set_style_shadow_spread(obj, 0, MAIN_STYLE)
  end
end

local function style_panel(obj, bg_color, bg_opa, radius, border_color, border_opa, grad_color, shadow_width, shadow_color, shadow_opa, shadow_ofs_y)
  if not obj then
    return
  end

  lv_obj_set_style_bg_color(obj, bg_color, MAIN_STYLE)
  lv_obj_set_style_bg_opa(obj, bg_opa or 255, MAIN_STYLE)

  if grad_color and lv_obj_set_style_bg_grad_color and lv_obj_set_style_bg_grad_dir then
    lv_obj_set_style_bg_grad_color(obj, grad_color, MAIN_STYLE)
    lv_obj_set_style_bg_grad_dir(obj, LV_GRAD_DIR_VER, MAIN_STYLE)
    if lv_obj_set_style_bg_main_stop and lv_obj_set_style_bg_grad_stop then
      lv_obj_set_style_bg_main_stop(obj, 18, MAIN_STYLE)
      lv_obj_set_style_bg_grad_stop(obj, 255, MAIN_STYLE)
    end
  end

  if border_color then
    lv_obj_set_style_border_width(obj, 1, MAIN_STYLE)
    lv_obj_set_style_border_color(obj, border_color, MAIN_STYLE)
    lv_obj_set_style_border_opa(obj, border_opa or 255, MAIN_STYLE)
  else
    lv_obj_set_style_border_width(obj, 0, MAIN_STYLE)
  end

  lv_obj_set_style_radius(obj, radius or 0, MAIN_STYLE)
  if lv_obj_set_style_pad_all then
    lv_obj_set_style_pad_all(obj, 0, MAIN_STYLE)
  end
  if lv_obj_set_style_clip_corner then
    pcall(function() lv_obj_set_style_clip_corner(obj, true, MAIN_STYLE) end)
  end

  set_shadow(obj, shadow_width, shadow_color, shadow_opa, shadow_ofs_y)
  clear_scroll_flag(obj)
end

local function style_label(id, color, font_size, align, letter_space)
  if not id then
    return
  end

  lv_obj_set_style_text_color(id, color, MAIN_STYLE)
  lv_obj_set_style_text_font(id, font_size, MAIN_STYLE)
  if lv_obj_set_style_text_opa then
    lv_obj_set_style_text_opa(id, 255, MAIN_STYLE)
  end
  if align and lv_obj_set_style_text_align then
    pcall(function() lv_obj_set_style_text_align(id, align, MAIN_STYLE) end)
  end
  if letter_space ~= nil and lv_obj_set_style_text_letter_space then
    pcall(function() lv_obj_set_style_text_letter_space(id, letter_space, MAIN_STYLE) end)
  end
end

local colors

local function tile_text_color(value)
  if value ~= 0 and value <= 4 then
    return C.tile_dark
  end
  return value == 0 and C.tile_dark or C.tile_light
end

local function tile_font_size(value)
  if value >= 1024 then
    return 16
  elseif value >= 128 then
    return FONT_18
  end
  return 20
end

local function set_tile_style(obj, value)
  style_panel(obj, colors[value] or 0x4F423A, 255, cell_radius, nil, 0, nil, 0)
end

local function set_tile_label_style(label, value)
  style_label(label, tile_text_color(value), tile_font_size(value), LV_TEXT_ALIGN_CENTER)
end

local function score_font_size(value)
  local digits = string.len(tostring(math.max(0, value)))
  if digits >= 6 then
    return 14
  elseif digits >= 5 then
    return 16
  elseif digits >= 4 then
    return FONT_18
  end
  return 20
end

local bg = nil
local board = nil
local info_panel = nil
local score_value_label = nil
local game_over_dim = nil
local game_over_card = nil
local game_over_blur = nil
local game_over_score_label = nil
local game_over_snapshot_handle = nil

colors = {
  [0] = 0x7F6D62,
  [2] = 0xF3E8DA,
  [4] = 0xEFDCC7,
  [8] = 0xF2B378,
  [16] = 0xED9865,
  [32] = 0xEA795D,
  [64] = 0xE15E47,
  [128] = 0xD8C567,
  [256] = 0xD2BD59,
  [512] = 0xCCB24C,
  [1024] = 0xC6A842,
  [2048] = 0xC1A038,
}

math.randomseed(millis() or 1)

local slide_ms = 280
local anim_active = false
local anim_end_ms = 0
local anim_tiles = {}
local pending_spawn = nil
local game_over = false
local pending_game_over = false

local grid = {
  {0, 0, 0, 0},
  {0, 0, 0, 0},
  {0, 0, 0, 0},
  {0, 0, 0, 0},
}

local score = 0

local cells = {}

-- 静态棋盘对象只创建一次，后续移动阶段只切换状态和临时动画层。
local function build_board_ui()
clear_root()

  bg = lv_obj_create(root)
  lv_obj_set_pos(bg, 0, 0)
  lv_obj_set_size(bg, screen_w, screen_h)
  style_panel(bg, C.bg_top, 255, 0, nil, 0, nil, 0)

  board = lv_obj_create(root)
  lv_obj_set_pos(board, board_x, board_y)
  lv_obj_set_size(board, board_size, board_size)
  style_panel(board, C.board, 255, 12, C.board_border, 38, nil, 0, nil, 0, 0)

  info_panel = lv_obj_create(root)
  lv_obj_set_pos(info_panel, side_x, side_y)
  lv_obj_set_size(info_panel, side_w, side_h)
  style_panel(info_panel, C.panel_bg, 232, 12, C.panel_border, 64, nil, 0, nil, 0, 0)

  local title_label = lv_label_create(info_panel)
  lv_label_set_text(title_label, "2048")
  lv_obj_set_pos(title_label, 0, 16)
  lv_obj_set_width(title_label, side_w)
  style_label(title_label, C.title_accent, 20, LV_TEXT_ALIGN_CENTER)

  local score_card = lv_obj_create(info_panel)
  lv_obj_set_pos(score_card, 9, 62)
  lv_obj_set_size(score_card, side_w - 18, 56)
  style_panel(score_card, C.panel_inner, 255, 8, nil, 0, nil, 0)

  local score_title = lv_label_create(score_card)
  lv_label_set_text(score_title, "SCORE")
  lv_obj_set_pos(score_title, 0, 8)
  lv_obj_set_width(score_title, side_w - 18)
  style_label(score_title, C.text_soft, 10, LV_TEXT_ALIGN_CENTER, 1)

  score_value_label = lv_label_create(score_card)
  lv_label_set_text(score_value_label, "0")
  lv_obj_set_pos(score_value_label, 0, 24)
  lv_obj_set_width(score_value_label, side_w - 18)
  style_label(score_value_label, C.text_main, 20, LV_TEXT_ALIGN_CENTER)

  game_over_dim = lv_obj_create(root)
  lv_obj_set_pos(game_over_dim, 0, 0)
  lv_obj_set_size(game_over_dim, screen_w, screen_h)
  style_panel(game_over_dim, C.over_dim, 30, 0, nil, 0, nil, 0)

  game_over_card = lv_obj_create(root)
  lv_obj_set_pos(game_over_card, over_x, over_y)
  lv_obj_set_size(game_over_card, over_w, over_h)
  style_panel(game_over_card, 0xFFFFFF, 0, 18, C.over_border, 96, nil, 14, C.shadow, 88, 6)

  game_over_blur = lv_canvas_create(game_over_card, over_w, over_h, LV_IMG_CF_TRUE_COLOR)
  lv_obj_set_pos(game_over_blur, 0, 0)
  clear_scroll_flag(game_over_blur)

  local game_over_title = lv_label_create(game_over_card)
  lv_label_set_text(game_over_title, "2048")
  lv_obj_set_pos(game_over_title, 0, 26)
  lv_obj_set_width(game_over_title, over_w)
  style_label(game_over_title, C.title_accent, 32, LV_TEXT_ALIGN_CENTER)

  game_over_score_label = lv_label_create(game_over_card)
  lv_label_set_text(game_over_score_label, "SCORE: 0")
  lv_obj_set_pos(game_over_score_label, 0, 80)
  lv_obj_set_width(game_over_score_label, over_w)
  style_label(game_over_score_label, C.text_main, 20, LV_TEXT_ALIGN_CENTER)

  local game_over_hint = lv_label_create(game_over_card)
  lv_label_set_text(game_over_hint, "PRESS HOME TO EXIT")
  lv_obj_set_pos(game_over_hint, 0, 124)
  lv_obj_set_width(game_over_hint, over_w)
  style_label(game_over_hint, C.text_soft, 10, LV_TEXT_ALIGN_CENTER, 1)

  set_visible(game_over_dim, false)
  set_visible(game_over_card, false)

  cells = {}
  for r = 1, 4 do
    cells[r] = {}
    for c = 1, 4 do
      local x = grid_pad + gap + (c - 1) * (cell_size + gap)
      local y = grid_pad + gap + (r - 1) * (cell_size + gap)

      local cell = lv_obj_create(board)
      lv_obj_set_pos(cell, x, y)
      lv_obj_set_size(cell, cell_size, cell_size)
      set_tile_style(cell, 0)

      local label = lv_label_create(cell)
      lv_label_set_text(label, "")
      set_tile_label_style(label, 0)
      lv_obj_align(label, LV_ALIGN_CENTER, 0, 0)

      cells[r][c] = {rect = cell, label = label, base_x = x, base_y = y}
    end
  end
end

with_lv_batch(build_board_ui)

local function render_grid()
  for r = 1, 4 do
    for c = 1, 4 do
      local v = grid[r][c]
      local cell = cells[r][c]
      if lv_anim_delete then
        pcall(function() lv_anim_delete(cell.rect, ANIM_X) end)
        pcall(function() lv_anim_delete(cell.rect, ANIM_Y) end)
        pcall(function() lv_anim_delete(cell.rect, ANIM_W) end)
        pcall(function() lv_anim_delete(cell.rect, ANIM_H) end)
        pcall(function() lv_anim_delete(cell.label, ANIM_OPA) end)
      end
      lv_obj_set_pos(cell.rect, cell.base_x, cell.base_y)
      lv_obj_set_size(cell.rect, cell_size, cell_size)
      if lv_obj_set_style_opa then
        lv_obj_set_style_opa(cell.label, 255, MAIN_STYLE)
      end

      set_tile_style(cell.rect, v)
      set_tile_label_style(cell.label, v)
      if v == 0 then
        lv_label_set_text(cell.label, "")
      else
        lv_label_set_text(cell.label, tostring(v))
      end
    end
  end
end

local function clear_cell(r, c)
  local cell = cells[r][c]
  if not cell then return end
  if lv_anim_delete then
    pcall(function() lv_anim_delete(cell.rect, ANIM_X) end)
    pcall(function() lv_anim_delete(cell.rect, ANIM_Y) end)
    pcall(function() lv_anim_delete(cell.rect, ANIM_W) end)
    pcall(function() lv_anim_delete(cell.rect, ANIM_H) end)
    pcall(function() lv_anim_delete(cell.label, ANIM_OPA) end)
  end
  lv_obj_set_pos(cell.rect, cell.base_x, cell.base_y)
  lv_obj_set_size(cell.rect, cell_size, cell_size)
  if lv_obj_set_style_opa then
    lv_obj_set_style_opa(cell.label, 255, MAIN_STYLE)
  end
  set_tile_style(cell.rect, 0)
  set_tile_label_style(cell.label, 0)
  lv_label_set_text(cell.label, "")
end

local function update_score()
  if score_value_label then
    lv_obj_set_style_text_font(score_value_label, score_font_size(score), MAIN_STYLE)
    lv_label_set_text(score_value_label, tostring(score))
  end
end

local function free_image_handle(handle)
  if not handle then
    return
  end

  if lv_snapshot_free then
    pcall(function() lv_snapshot_free(handle) end)
    return
  end

  if lv_img_free_handle then
    pcall(function() lv_img_free_handle(handle) end)
  end
end

local function release_game_over_snapshot()
  if not game_over_snapshot_handle then
    return
  end

  free_image_handle(game_over_snapshot_handle)
  game_over_snapshot_handle = nil
end

local function canvas_frame_begin(id)
  if not id or not lv_canvas_begin then
    return false
  end
  local ok = pcall(function() lv_canvas_begin(id) end)
  return ok
end

local function canvas_frame_end(id)
  if not id then
    return
  end

  if lv_canvas_end then
    pcall(function() lv_canvas_end(id) end)
    return
  end

  if lv_obj_invalidate then
    pcall(function() lv_obj_invalidate(id) end)
  end
end

-- 结束弹层优先使用 snapshot + canvas blur；若接口缺失或 PSRAM 不足，再回退到静态玻璃底。
local function refresh_game_over_blur()
  if not game_over_blur then
    return
  end

  release_game_over_snapshot()

  if not canvas_frame_begin(game_over_blur) then
    return
  end

  local handle = nil
  if lv_snapshot_take and lv_canvas_draw_img and lv_canvas_blur_hor and lv_canvas_blur_ver then
    local ok, snapshot_handle = pcall(function()
      return lv_snapshot_take(root, LV_IMG_CF_TRUE_COLOR)
    end)
    if ok and type(snapshot_handle) == "number" and snapshot_handle > 0 then
      handle = snapshot_handle
      game_over_snapshot_handle = snapshot_handle
    end
  end

  if handle then
    lv_canvas_fill_bg(game_over_blur, C.panel_bg, 255)
    lv_canvas_draw_img(game_over_blur, -over_x, -over_y, { handle = handle }, { opa = 255 })
    lv_canvas_blur_hor(game_over_blur, nil, 7)
    lv_canvas_blur_ver(game_over_blur, nil, 7)
    lv_canvas_draw_rect(game_over_blur, 0, 0, over_w, over_h, 0xF1E0D0, 44)
    lv_canvas_draw_rect(game_over_blur, 0, 0, over_w, 34, 0xFFF8EF, 14)
    lv_canvas_draw_rect(game_over_blur, 14, 12, over_w - 28, 18, 0xFFFFFF, 18)
    lv_canvas_draw_rect(game_over_blur, 18, over_h - 18, over_w - 36, 1, 0x130E0B, 18)
  else
    lv_canvas_fill_bg(game_over_blur, 0xD9C5B1, 255)
    lv_canvas_draw_rect(game_over_blur, 0, 0, over_w, over_h, 0xF3E5D7, 66)
    lv_canvas_draw_rect(game_over_blur, 0, 0, over_w, 36, 0xFFF8F0, 20)
    lv_canvas_draw_rect(game_over_blur, 14, 12, over_w - 28, 18, 0xFFFFFF, 16)
  end

  canvas_frame_end(game_over_blur)
end

-- 棋盘没有空格且不存在可合并相邻块时，判定为游戏结束。
local function has_available_moves()
  for r = 1, 4 do
    for c = 1, 4 do
      local v = grid[r][c]
      if v == 0 then
        return true
      end
      if c < 4 and grid[r][c + 1] == v then
        return true
      end
      if r < 4 and grid[r + 1][c] == v then
        return true
      end
    end
  end
  return false
end

local function hide_game_over()
  game_over = false
  pending_game_over = false
  set_visible(game_over_dim, false)
  set_visible(game_over_card, false)
  release_game_over_snapshot()
end

-- 结束弹层只负责提示当前分数和 HOME 退出，不额外增加按钮状态。
local function show_game_over()
  game_over = true
  pending_game_over = false
  if game_over_score_label then
    lv_label_set_text(game_over_score_label, "SCORE: " .. tostring(score))
  end
  refresh_game_over_blur()
  set_visible(game_over_dim, true)
  set_visible(game_over_card, true)
  if lv_obj_move_foreground then
    pcall(function() lv_obj_move_foreground(game_over_dim) end)
    pcall(function() lv_obj_move_foreground(game_over_card) end)
  end
end

local function get_empty_cells()
  local empty = {}
  for r = 1, 4 do
    for c = 1, 4 do
      if grid[r][c] == 0 then
        empty[#empty + 1] = {r = r, c = c}
      end
    end
  end
  return empty
end

local function spawn_random()
  local empty = get_empty_cells()
  if #empty == 0 then
    return nil
  end
  local pick = empty[math.random(1, #empty)]
  local value = (math.random(1, 10) == 1) and 4 or 2
  grid[pick.r][pick.c] = value
  return pick.r, pick.c
end

local function anim_spawn(r, c)
  local cell = cells[r][c]
  if not cell then return end
  local cx = cell.base_x + math.floor(cell_size / 2)
  local cy = cell.base_y + math.floor(cell_size / 2)
  if lv_anim_delete then
    pcall(function() lv_anim_delete(cell.rect, ANIM_X) end)
    pcall(function() lv_anim_delete(cell.rect, ANIM_Y) end)
    pcall(function() lv_anim_delete(cell.rect, ANIM_W) end)
    pcall(function() lv_anim_delete(cell.rect, ANIM_H) end)
    pcall(function() lv_anim_delete(cell.label, ANIM_OPA) end)
  end
  lv_obj_set_pos(cell.rect, cx, cy)
  lv_obj_set_size(cell.rect, 0, 0)
  if lv_obj_set_style_opa then
    lv_obj_set_style_opa(cell.label, 0, MAIN_STYLE)
  end

  lv_anim_start(cell.rect, ANIM_W, 0, cell_size, 280, 0, ANIM_PATH_EASE_OUT)
  lv_anim_start(cell.rect, ANIM_H, 0, cell_size, 280, 0, ANIM_PATH_EASE_OUT)
  lv_anim_start(cell.rect, ANIM_X, cx, cell.base_x, 280, 0, ANIM_PATH_EASE_OUT)
  lv_anim_start(cell.rect, ANIM_Y, cy, cell.base_y, 280, 0, ANIM_PATH_EASE_OUT)
  lv_anim_start(cell.label, ANIM_OPA, 0, 255, 280, 0, ANIM_PATH_EASE_OUT)
end

-- 同一目标被多个 move 指向时，表示这是一次 merge，需要把原地那块也交给动画层接管。
local function move_to_key(pos)
  return tostring(pos.r) .. ":" .. tostring(pos.c)
end

local function collect_target_counts(moves)
  local counts = {}
  for i = 1, #moves do
    local key = move_to_key(moves[i].to)
    counts[key] = (counts[key] or 0) + 1
  end
  return counts
end

local function move_needs_temp(m, target_counts)
  if m.from.r ~= m.to.r or m.from.c ~= m.to.c then
    return true
  end
  return (target_counts[move_to_key(m.to)] or 0) > 1
end

local function slide_line(line, positions)
  local tiles = {}
  for i = 1, 4 do
    if line[i] ~= 0 then
      tiles[#tiles + 1] = {v = line[i], pos = i}
    end
  end
  local merged = {0, 0, 0, 0}
  local moves = {}
  local dst = 1
  local i = 1
  while i <= #tiles do
    local v = tiles[i].v
    if i < #tiles and tiles[i + 1].v == v then
      merged[dst] = v * 2
      score = score + merged[dst]
      moves[#moves + 1] = {from = positions[tiles[i].pos], to = positions[dst], value = v}
      moves[#moves + 1] = {from = positions[tiles[i + 1].pos], to = positions[dst], value = v}
      i = i + 2
    else
      merged[dst] = v
      moves[#moves + 1] = {from = positions[tiles[i].pos], to = positions[dst], value = v}
      i = i + 1
    end
    dst = dst + 1
  end
  local moved = false
  for k = 1, 4 do
    if merged[k] ~= line[k] then
      moved = true
      break
    end
  end
  return merged, moved, moves
end

local function move(dir)
  local moved = false
  local moves = {}
  if dir == "left" then
    for r = 1, 4 do
      local positions = {
        {r = r, c = 1},
        {r = r, c = 2},
        {r = r, c = 3},
        {r = r, c = 4},
      }
      local line = {
        grid[r][1], grid[r][2], grid[r][3], grid[r][4],
      }
      local new_line, changed, line_moves = slide_line(line, positions)
      for i = 1, 4 do
        local p = positions[i]
        grid[p.r][p.c] = new_line[i]
      end
      for i = 1, #line_moves do
        moves[#moves + 1] = line_moves[i]
      end
      if changed then moved = true end
    end
  elseif dir == "right" then
    for r = 1, 4 do
      local positions = {
        {r = r, c = 4},
        {r = r, c = 3},
        {r = r, c = 2},
        {r = r, c = 1},
      }
      local line = {
        grid[r][4], grid[r][3], grid[r][2], grid[r][1],
      }
      local new_line, changed, line_moves = slide_line(line, positions)
      for i = 1, 4 do
        local p = positions[i]
        grid[p.r][p.c] = new_line[i]
      end
      for i = 1, #line_moves do
        moves[#moves + 1] = line_moves[i]
      end
      if changed then moved = true end
    end
  elseif dir == "up" then
    for c = 1, 4 do
      local positions = {
        {r = 1, c = c},
        {r = 2, c = c},
        {r = 3, c = c},
        {r = 4, c = c},
      }
      local line = {
        grid[1][c], grid[2][c], grid[3][c], grid[4][c],
      }
      local new_line, changed, line_moves = slide_line(line, positions)
      for i = 1, 4 do
        local p = positions[i]
        grid[p.r][p.c] = new_line[i]
      end
      for i = 1, #line_moves do
        moves[#moves + 1] = line_moves[i]
      end
      if changed then moved = true end
    end
  elseif dir == "down" then
    for c = 1, 4 do
      local positions = {
        {r = 4, c = c},
        {r = 3, c = c},
        {r = 2, c = c},
        {r = 1, c = c},
      }
      local line = {
        grid[4][c], grid[3][c], grid[2][c], grid[1][c],
      }
      local new_line, changed, line_moves = slide_line(line, positions)
      for i = 1, 4 do
        local p = positions[i]
        grid[p.r][p.c] = new_line[i]
      end
      for i = 1, #line_moves do
        moves[#moves + 1] = line_moves[i]
      end
      if changed then moved = true end
    end
  end
  return moved, moves
end

local function clear_anim_tiles()
  for i = 1, #anim_tiles do
    pcall(function() lv_obj_del(anim_tiles[i]) end)
  end
  anim_tiles = {}
end

local function start_slide_anims(moves, ts_ms)
  local any = false
  local target_counts = collect_target_counts(moves)

  with_lv_batch(function()
    clear_anim_tiles()
    for i = 1, #moves do
      local m = moves[i]
      if move_needs_temp(m, target_counts) then
        any = true

        local from = m.from
        local to = m.to
        local from_cell = cells[from.r][from.c]
        local to_cell = cells[to.r][to.c]

        clear_cell(from.r, from.c)

        local temp = lv_obj_create(board)
        lv_obj_set_pos(temp, from_cell.base_x, from_cell.base_y)
        lv_obj_set_size(temp, cell_size, cell_size)
        set_tile_style(temp, m.value)

        local label = lv_label_create(temp)
        lv_label_set_text(label, tostring(m.value))
        set_tile_label_style(label, m.value)
        lv_obj_align(label, LV_ALIGN_CENTER, 0, 0)

        if from.r ~= to.r or from.c ~= to.c then
          lv_anim_start(temp, ANIM_X, from_cell.base_x, to_cell.base_x, slide_ms, 0, ANIM_PATH_EASE_OUT)
          lv_anim_start(temp, ANIM_Y, from_cell.base_y, to_cell.base_y, slide_ms, 0, ANIM_PATH_EASE_OUT)
        end

        anim_tiles[#anim_tiles + 1] = temp
      end
    end
  end)

  if any then
    anim_active = true
    anim_end_ms = ts_ms + slide_ms
  end
  return any
end

local function reset_game()
  anim_active = false
  anim_end_ms = 0
  pending_spawn = nil
  hide_game_over()
  for r = 1, 4 do
    for c = 1, 4 do
      grid[r][c] = 0
    end
  end
  score = 0
  local r1, c1 = spawn_random()
  local r2, c2 = spawn_random()
  update_score()
  with_lv_batch(function()
    clear_anim_tiles()
    render_grid()
    if r1 then anim_spawn(r1, c1) end
    if r2 then anim_spawn(r2, c2) end
  end)
end

reset_game()

local long_repeat_state = {}

local function reset_repeat_state(evt_code)
  long_repeat_state[evt_code] = nil
end

local function should_trigger_press(evt_type, evt_code)
  if evt_type == key.START then
    reset_repeat_state(evt_code)
    return true
  elseif evt_type == key.LONG_START then
    long_repeat_state[evt_code] = {count = 0}
    return false
  elseif evt_type == key.LONG_REPEAT then
    local state = long_repeat_state[evt_code] or {count = 0}
    state.count = state.count + 1
    long_repeat_state[evt_code] = state
    if state.count == 1 or (state.count % 5 == 0) then
      return true
    end
  elseif evt_type == key.LONG_END then
    reset_repeat_state(evt_code)
  end
  return false
end

key.on(function(evt_code, evt_type, ts_ms)
  if anim_active then return end

  local dir = nil
  if evt_code == key.LEFT then
    dir = "left"
  elseif evt_code == key.RIGHT then
    dir = "right"
  elseif evt_code == key.UP then
    dir = "up"
  elseif evt_code == key.DOWN then
    dir = "down"
  else
    return
  end

  if not should_trigger_press(evt_type, evt_code) then return end
  if game_over then return end

  local moved, moves = move(dir)
  if moved then
    local r, c = spawn_random()
    pending_spawn = (r and c) and {r = r, c = c} or nil
    pending_game_over = not has_available_moves()
    update_score()
    if not start_slide_anims(moves, ts_ms) then
      with_lv_batch(function()
        render_grid()
        if pending_spawn then
          anim_spawn(pending_spawn.r, pending_spawn.c)
          pending_spawn = nil
        end
        if pending_game_over then
          show_game_over()
        end
      end)
    end
  elseif not has_available_moves() then
    with_lv_batch(show_game_over)
  end
end)

local tick_timer = tmr.create()
tick_timer:alarm(20, tmr.ALARM_AUTO, function()
  local ts_ms = millis() or 0
  if anim_active and ts_ms >= anim_end_ms then
    anim_active = false
    with_lv_batch(function()
      clear_anim_tiles()
      render_grid()
      if pending_spawn then
        anim_spawn(pending_spawn.r, pending_spawn.c)
        pending_spawn = nil
      end
      if pending_game_over then
        show_game_over()
      end
    end)
  end
end)

function APP.stop(reason)
  if tick_timer then
    pcall(function() tick_timer:stop() end)
    pcall(function() tick_timer:unregister() end)
    tick_timer = nil
  end

  pcall(function() key.off() end)

  if rawget(_G, "APP_2048") == APP then
    _G.APP_2048 = nil
  end

  if lv_scr_act then
    clear_root()
  end
  release_fonts()
end

APP.shutdown = APP.stop
