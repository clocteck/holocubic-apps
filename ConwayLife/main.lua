
CONWAY_LIFE_APP = {
  VERSION = "2026-04-28-conway-life-v11-periodic-large-seed"
}

local APP = CONWAY_LIFE_APP
APP.font_handles = {}
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
local CELL = 2
local DOT = 1
local FADE_DOT_OFFSET = math.floor(DOT / 2)
local GRID_W = math.floor(SCREEN_W / CELL)
local GRID_H = math.floor(SCREEN_H / CELL)
local GRID_X = math.floor((SCREEN_W - GRID_W * CELL) / 2)
local GRID_Y = math.floor((SCREEN_H - GRID_H * CELL) / 2)
local CELL_COUNT = GRID_W * GRID_H
local TICK_MS = 160
local FADE_STEPS = 3
local MAX_STAGNANT = 50
local MIN_ALIVE = 10
local ACTIVE_MAX_AGE = 3
local MIN_ACTIVE_ALIVE = math.max(20, math.floor(CELL_COUNT * 0.012))
local ACTIVE_SPARSE_LIMIT = 35
local MAX_ALIVE = math.floor(CELL_COUNT * 0.58)
local BOOST_PATTERN_MIN = 15
local BOOST_PATTERN_MAX = 20
local BOOST_CLUSTER_MIN = 5
local BOOST_CLUSTER_MAX = 10
local PERIODIC_INJECT_MS = 15000
local PERIODIC_PATTERN_COUNT = 2
local PERIODIC_CLUSTER_COUNT = 1
local PERIODIC_POINT_COUNT = 8
local MAIN_STYLE = rawget(_G, "LV_PART_MAIN") or 0
local CANVAS_FMT = rawget(_G, "LV_IMG_CF_TRUE_COLOR") or rawget(_G, "CANVAS_FMT_TRUE_COLOR")
local ALIGN_CENTER = rawget(_G, "LV_ALIGN_CENTER") or 0
local TIME_FONT = rawget(_G, "LV_FONT_MONTSERRAT_28") or rawget(_G, "LV_FONT_MONTSERRAT_24")
local TIME_HOUR_X_OFFSET = -34
local TIME_COLON_X_OFFSET = 0
local TIME_MINUTE_X_OFFSET = 34
local TIME_Y_OFFSET = -28

local math_random = math.random
local pcall_fn = pcall
local string_format = string.format

local function load_font_ref(path, fallback)
  if lv_font_load then
    local ok, handle = pcall_fn(function()
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
  TIME_FONT = load_font_ref("/sd/apps/ConwayLife/font/time_46.bin", TIME_FONT)
end

local function release_fonts()
  if lv_font_free then
    for _, handle in ipairs(APP.font_handles) do
      pcall_fn(function()
        lv_font_free(handle)
      end)
    end
  end
  APP.font_handles = {}
end

local lv_canvas_create_fn = rawget(_G, "lv_canvas_create")
local lv_canvas_frame_begin_fn = rawget(_G, "lv_canvas_frame_begin") or rawget(_G, "lv_canvas_begin")
local lv_canvas_frame_end_fn = rawget(_G, "lv_canvas_frame_end") or rawget(_G, "lv_canvas_end")
local lv_canvas_fill_bg_fn = rawget(_G, "lv_canvas_fill_bg") or rawget(_G, "lv_canvas_fill")
local lv_canvas_draw_rect_fn = rawget(_G, "lv_canvas_draw_rect")
local lv_label_create_fn = rawget(_G, "lv_label_create")
local lv_label_set_text_fn = rawget(_G, "lv_label_set_text")
local lv_obj_set_pos_fn = rawget(_G, "lv_obj_set_pos")
local lv_obj_align_fn = rawget(_G, "lv_obj_align")
local lv_obj_set_style_bg_color_fn = rawget(_G, "lv_obj_set_style_bg_color")
local lv_obj_set_style_bg_opa_fn = rawget(_G, "lv_obj_set_style_bg_opa")
local lv_obj_set_style_text_color_fn = rawget(_G, "lv_obj_set_style_text_color")
local lv_obj_set_style_text_opa_fn = rawget(_G, "lv_obj_set_style_text_opa")
local lv_obj_set_style_text_font_fn = rawget(_G, "lv_obj_set_style_text_font")
local lv_obj_clear_flag_fn = rawget(_G, "lv_obj_clear_flag")
local lv_obj_invalidate_fn = rawget(_G, "lv_obj_invalidate")
local runtime_app = rawget(_G, "app")
local app_exiting_fn = runtime_app and runtime_app.exiting or nil
local runtime_tmr = rawget(_G, "tmr")
local runtime_time = rawget(_G, "time")
local time_getlocal_fn = runtime_time and runtime_time.getlocal or nil

local C = {
  bg = 0x000000,
  dim = 0x052512,
  ember = 0x0A5A27,
  green = 0x00E85A,
  hot = 0x3CFF88,
  time = 0xFFFFFF,
  white = 0xE9FFF0,
}

local age = {}
local fade = {}
local alive_cells = {}
local next_alive_cells = {}
local fade_cells = {}
local next_fade_cells = {}
local neighbor_count = {}
local candidate_cells = {}
local left_col = {}
local right_col = {}
local row_offset = {}
local row_up = {}
local row_down = {}
local cell_px = {}
local cell_py = {}
local neighbor_1 = {}
local neighbor_2 = {}
local neighbor_3 = {}
local neighbor_4 = {}
local neighbor_5 = {}
local neighbor_6 = {}
local neighbor_7 = {}
local neighbor_8 = {}
local canvas = nil
local time_hour_label = nil
local time_colon_label = nil
local time_minute_label = nil
local time_colon_visible = true
local rect_mode = 0
local rect_dsc = {
  bg_color = C.green,
  bg_opa = 255,
  radius = 0,
  border_width = 0
}

local generation = 0
local stagnant = 0
local sparse_ticks = 0
local active_sparse_ticks = 0
local alive_count = 0
local fade_count = 0

local PATTERNS = {
  -- glider
  { {1, 0}, {2, 1}, {0, 2}, {1, 2}, {2, 2} },

  -- blinker
  { {0, 0}, {1, 0}, {2, 0} },

  -- block
  { {0, 0}, {1, 0}, {0, 1}, {1, 1} },

  -- beehive
  { {1, 0}, {2, 0}, {0, 1}, {3, 1}, {1, 2}, {2, 2} },

  -- loaf
  { {1, 0}, {2, 0}, {0, 1}, {3, 1}, {1, 2}, {3, 2}, {2, 3} },

  -- boat
  { {0, 0}, {1, 0}, {0, 1}, {2, 1}, {1, 2} },

  -- tub
  { {1, 0}, {0, 1}, {2, 1}, {1, 2} },

  -- toad
  { {1, 0}, {2, 0}, {3, 0}, {0, 1}, {1, 1}, {2, 1} },

  -- beacon
  { {0, 0}, {1, 0}, {0, 1}, {1, 1}, {2, 2}, {3, 2}, {2, 3}, {3, 3} },

  -- r-pentomino
  { {1, 0}, {2, 0}, {0, 1}, {1, 1}, {1, 2} },

  -- acorn
  { {1, 0}, {3, 1}, {0, 2}, {1, 2}, {4, 2}, {5, 2}, {6, 2} },

  -- diehard
  { {6, 0}, {0, 1}, {1, 1}, {1, 2}, {5, 2}, {6, 2}, {7, 2} },

  -- small exploder
  { {1, 0}, {0, 1}, {1, 1}, {2, 1}, {0, 2}, {2, 2}, {1, 3} },

  -- pentadecathlon
  { {1, 0}, {1, 1}, {0, 2}, {2, 2}, {1, 3}, {1, 4}, {1, 5}, {0, 6}, {2, 6}, {1, 7} },

  -- split blocks
  { {0, 0}, {1, 0}, {0, 1}, {3, 2}, {2, 3}, {3, 3} },

  -- plus
  { {1, 0}, {0, 1}, {1, 1}, {2, 1}, {1, 2} },

  -- lightweight spaceship
  { {1, 0}, {4, 0}, {0, 1}, {0, 2}, {4, 2}, {0, 3}, {1, 3}, {2, 3}, {3, 3} },

  -- spark
  { {1, 0}, {2, 0}, {3, 0}, {0, 1}, {3, 1}, {3, 2}, {0, 3}, {2, 3} },

  -- big exploder
  { {0, 0}, {2, 0}, {4, 0}, {0, 1}, {4, 1}, {0, 2}, {4, 2}, {0, 3}, {4, 3}, {0, 4}, {2, 4}, {4, 4} },

  -- pulsar
  {
    {2, 0}, {3, 0}, {4, 0}, {8, 0}, {9, 0}, {10, 0},
    {0, 2}, {5, 2}, {7, 2}, {12, 2},
    {0, 3}, {5, 3}, {7, 3}, {12, 3},
    {0, 4}, {5, 4}, {7, 4}, {12, 4},
    {2, 5}, {3, 5}, {4, 5}, {8, 5}, {9, 5}, {10, 5},
    {2, 7}, {3, 7}, {4, 7}, {8, 7}, {9, 7}, {10, 7},
    {0, 8}, {5, 8}, {7, 8}, {12, 8},
    {0, 9}, {5, 9}, {7, 9}, {12, 9},
    {0, 10}, {5, 10}, {7, 10}, {12, 10},
    {2, 12}, {3, 12}, {4, 12}, {8, 12}, {9, 12}, {10, 12},
  },

  -- gosper glider gun
  {
    {24, 0},
    {22, 1}, {24, 1},
    {12, 2}, {13, 2}, {20, 2}, {21, 2}, {34, 2}, {35, 2},
    {11, 3}, {15, 3}, {20, 3}, {21, 3}, {34, 3}, {35, 3},
    {0, 4}, {1, 4}, {10, 4}, {16, 4}, {20, 4}, {21, 4},
    {0, 5}, {1, 5}, {10, 5}, {14, 5}, {16, 5}, {17, 5}, {22, 5}, {24, 5},
    {10, 6}, {16, 6}, {24, 6},
    {11, 7}, {15, 7},
    {12, 8}, {13, 8},
  },
}

local LARGE_PATTERN_COUNT = 3
local LARGE_PATTERN_START = #PATTERNS - LARGE_PATTERN_COUNT + 1

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

local function idx(x, y)
  return (y - 1) * GRID_W + x
end

local function wrap(v, max_v)
  if v < 1 then
    return max_v
  end
  if v > max_v then
    return 1
  end
  return v
end

local function clear_world()
  local ages = age
  local fades = fade
  local nc = neighbor_count

  for i = 1, CELL_COUNT do
    ages[i] = 0
    fades[i] = 0
    nc[i] = 0
  end

  alive_count = 0
  fade_count = 0
end

local function build_lookup()
  for x = 1, GRID_W do
    left_col[x] = x == 1 and GRID_W or x - 1
    right_col[x] = x == GRID_W and 1 or x + 1
  end

  for y = 1, GRID_H do
    row_offset[y] = (y - 1) * GRID_W
    row_up[y] = (wrap(y - 1, GRID_H) - 1) * GRID_W
    row_down[y] = (wrap(y + 1, GRID_H) - 1) * GRID_W
  end

  for y = 1, GRID_H do
    local row = row_offset[y]
    local up = row_up[y]
    local down = row_down[y]
    local py = GRID_Y + (y - 1) * CELL

    for x = 1, GRID_W do
      local i = row + x
      local xm = left_col[x]
      local xp = right_col[x]

      cell_px[i] = GRID_X + (x - 1) * CELL
      cell_py[i] = py
      neighbor_1[i] = up + xm
      neighbor_2[i] = up + x
      neighbor_3[i] = up + xp
      neighbor_4[i] = row + xm
      neighbor_5[i] = row + xp
      neighbor_6[i] = down + xm
      neighbor_7[i] = down + x
      neighbor_8[i] = down + xp
    end
  end
end

local function set_alive(x, y)
  x = wrap(x, GRID_W)
  y = wrap(y, GRID_H)
  local i = idx(x, y)
  if age[i] == 0 then
    alive_count = alive_count + 1
    alive_cells[alive_count] = i
  end
  age[i] = math_random(1, 3)
  fade[i] = 0
end

local function place_pattern(pattern, ox, oy)
  for i = 1, #pattern do
    local p = pattern[i]
    set_alive(ox + p[1], oy + p[2])
  end
end

local function pattern_size(pattern)
  local max_x = 0
  local max_y = 0
  for i = 1, #pattern do
    local p = pattern[i]
    if p[1] > max_x then
      max_x = p[1]
    end
    if p[2] > max_y then
      max_y = p[2]
    end
  end
  return max_x, max_y
end

local function place_random_pattern(pattern)
  local max_x, max_y = pattern_size(pattern)
  local max_ox = GRID_W - max_x - 1
  local max_oy = GRID_H - max_y - 1
  if max_ox < 2 then
    max_ox = GRID_W
  end
  if max_oy < 2 then
    max_oy = GRID_H
  end

  place_pattern(pattern, math_random(2, max_ox), math_random(2, max_oy))
end

local function seed_cluster(cx, cy, radius)
  for dy = -radius, radius do
    for dx = -radius, radius do
      local distance = dx * dx + dy * dy
      local limit = radius * radius
      if distance <= limit and math_random(1, 100) <= 34 then
        set_alive(cx + dx, cy + dy)
      end
    end
  end
end

local function seed_patterns(min_count, max_count)
  local pattern_count = math_random(min_count, max_count)
  for _ = 1, pattern_count do
    local pattern = PATTERNS[math_random(1, LARGE_PATTERN_START - 1)]
    place_random_pattern(pattern)
  end
end

local function seed_large_patterns(min_count, max_count)
  local pattern_count = math_random(min_count, max_count)
  for _ = 1, pattern_count do
    local pattern = PATTERNS[math_random(LARGE_PATTERN_START, #PATTERNS)]
    place_random_pattern(pattern)
  end
end

local function seed_clusters(min_count, max_count)
  local cluster_count = math_random(min_count, max_count)
  for _ = 1, cluster_count do
    seed_cluster(math_random(4, GRID_W - 3), math_random(4, GRID_H - 3), math_random(2, 3))
  end
end

local function seed_points(count)
  for _ = 1, count do
    set_alive(math_random(1, GRID_W), math_random(1, GRID_H))
  end
end

local function add_life_patch()
  seed_patterns(BOOST_PATTERN_MIN, BOOST_PATTERN_MAX)
  seed_clusters(BOOST_CLUSTER_MIN, BOOST_CLUSTER_MAX)

  generation = 0
  stagnant = 0
  sparse_ticks = 0
  active_sparse_ticks = 0
end

local function add_periodic_life_patch()
  seed_patterns(PERIODIC_PATTERN_COUNT, PERIODIC_PATTERN_COUNT)
  seed_large_patterns(2, 2)
  seed_clusters(PERIODIC_CLUSTER_COUNT, PERIODIC_CLUSTER_COUNT)
  seed_points(PERIODIC_POINT_COUNT)

  stagnant = 0
  sparse_ticks = 0
  active_sparse_ticks = 0
end

local function seed_world()
  clear_world()
  generation = 0
  stagnant = 0
  sparse_ticks = 0
  active_sparse_ticks = 0
  alive_count = 0

  seed_patterns(50, 60)
  seed_large_patterns(10, 15)
  seed_clusters(10, 16)
  seed_points(50)
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

local function detect_rect_mode()
  if not lv_canvas_draw_rect_fn then
    return
  end

  rect_dsc.bg_color = C.dim
  rect_dsc.bg_opa = 1

  local ok = pcall_fn(lv_canvas_draw_rect_fn, canvas, 0, 0, 1, 1, rect_dsc)
  if ok then
    rect_mode = 1
    return
  end

  ok = pcall_fn(lv_canvas_draw_rect_fn, canvas, 0, 0, 1, 1, C.dim, 1)
  if ok then
    rect_mode = 2
  end
end

local function draw_rect(x, y, w, h, color, opa)
  if rect_mode == 1 then
    rect_dsc.bg_color = color
    rect_dsc.bg_opa = opa
    lv_canvas_draw_rect_fn(canvas, x, y, w, h, rect_dsc)
  elseif rect_mode == 2 then
    lv_canvas_draw_rect_fn(canvas, x, y, w, h, color, opa)
  end
end

local function cell_color(cell_age)
  if cell_age <= 1 then
    return C.hot, 255
  end
  if cell_age <= 3 then
    return C.green, 242
  end
  if cell_age <= 8 then
    return C.white, 232
  end
  return C.white, 205
end

local function finish_generation(changed, next_active_alive)
  generation = generation + 1

  if changed <= 2 then
    stagnant = stagnant + 1
  else
    stagnant = 0
  end

  if alive_count < MIN_ALIVE then
    sparse_ticks = sparse_ticks + 1
  else
    sparse_ticks = 0
  end

  if next_active_alive < MIN_ACTIVE_ALIVE then
    active_sparse_ticks = active_sparse_ticks + 1
  else
    active_sparse_ticks = 0
  end

  if alive_count > MAX_ALIVE then
    seed_world()
  elseif alive_count == 0 or stagnant > MAX_STAGNANT or sparse_ticks > 24 or active_sparse_ticks > ACTIVE_SPARSE_LIMIT or generation > 1400 then
    add_life_patch()
  end
end

local function redraw()
  if not canvas or rect_mode == 0 then
    return
  end

  local explicit_frame = frame_begin()
  clear_canvas()

  for n = 1, fade_count do
    local i = fade_cells[n]
    local f = fade[i]
    if f and f > 0 then
      local px = cell_px[i]
      local py = cell_py[i]
      local size = f >= 2 and DOT or 1
      local offset = f >= 2 and 0 or FADE_DOT_OFFSET
      draw_rect(px + offset, py + offset, size, size, C.ember, 26 + f * 22)
    end
  end

  for n = 1, alive_count do
    local i = alive_cells[n]
    local color, opa = cell_color(age[i])
    draw_rect(cell_px[i], cell_py[i], DOT, DOT, color, opa)
  end

  frame_end(explicit_frame)
end

local function update_world()
  local changed = 0
  local next_alive = 0
  local next_active_alive = 0
  local candidate_count = 0
  local next_fade_count = 0
  local current_alive = alive_cells
  local next_alive_list = next_alive_cells
  local current_fade = fade_cells
  local next_fade_list = next_fade_cells
  local ages = age
  local fades = fade
  local nc = neighbor_count
  local candidates = candidate_cells
  local n1 = neighbor_1
  local n2 = neighbor_2
  local n3 = neighbor_3
  local n4 = neighbor_4
  local n5 = neighbor_5
  local n6 = neighbor_6
  local n7 = neighbor_7
  local n8 = neighbor_8
  local fade_steps = FADE_STEPS
  local active_max_age = ACTIVE_MAX_AGE

  -- neighbor_count 使用 count+1 编码：0 表示未访问，1 表示已入候选且邻居数为 0。
  for n = 1, alive_count do
    local i = current_alive[n]
    if nc[i] == 0 then
      nc[i] = 1
      candidate_count = candidate_count + 1
      candidates[candidate_count] = i
    end

    local j = n1[i]
    local count = nc[j]
    if count ~= 0 then
      nc[j] = count + 1
    else
      nc[j] = 2
      candidate_count = candidate_count + 1
      candidates[candidate_count] = j
    end

    j = n2[i]
    count = nc[j]
    if count ~= 0 then
      nc[j] = count + 1
    else
      nc[j] = 2
      candidate_count = candidate_count + 1
      candidates[candidate_count] = j
    end

    j = n3[i]
    count = nc[j]
    if count ~= 0 then
      nc[j] = count + 1
    else
      nc[j] = 2
      candidate_count = candidate_count + 1
      candidates[candidate_count] = j
    end

    j = n4[i]
    count = nc[j]
    if count ~= 0 then
      nc[j] = count + 1
    else
      nc[j] = 2
      candidate_count = candidate_count + 1
      candidates[candidate_count] = j
    end

    j = n5[i]
    count = nc[j]
    if count ~= 0 then
      nc[j] = count + 1
    else
      nc[j] = 2
      candidate_count = candidate_count + 1
      candidates[candidate_count] = j
    end

    j = n6[i]
    count = nc[j]
    if count ~= 0 then
      nc[j] = count + 1
    else
      nc[j] = 2
      candidate_count = candidate_count + 1
      candidates[candidate_count] = j
    end

    j = n7[i]
    count = nc[j]
    if count ~= 0 then
      nc[j] = count + 1
    else
      nc[j] = 2
      candidate_count = candidate_count + 1
      candidates[candidate_count] = j
    end

    j = n8[i]
    count = nc[j]
    if count ~= 0 then
      nc[j] = count + 1
    else
      nc[j] = 2
      candidate_count = candidate_count + 1
      candidates[candidate_count] = j
    end
  end

  for n = 1, candidate_count do
    local i = candidates[n]
    local neighbor_score = nc[i]
    local cell_age = ages[i]

    if cell_age > 0 then
      if neighbor_score == 3 or neighbor_score == 4 then
        local next_age = cell_age + 1
        next_alive = next_alive + 1
        next_alive_list[next_alive] = i
        ages[i] = next_age
        if next_age <= active_max_age then
          next_active_alive = next_active_alive + 1
        end
      else
        changed = changed + 1
        ages[i] = 0
        fades[i] = fade_steps
        next_fade_count = next_fade_count + 1
        next_fade_list[next_fade_count] = i
      end
    elseif neighbor_score == 4 then
      changed = changed + 1
      next_alive = next_alive + 1
      next_alive_list[next_alive] = i
      ages[i] = 1
      fades[i] = 0
      if active_max_age >= 1 then
        next_active_alive = next_active_alive + 1
      end
    end

    nc[i] = 0
  end

  for n = 1, fade_count do
    local i = current_fade[n]
    if ages[i] == 0 then
      local f = fades[i]
      if f > 0 then
        f = f - 1
        fades[i] = f
        if f > 0 then
          next_fade_count = next_fade_count + 1
          next_fade_list[next_fade_count] = i
        end
      end
    end
  end

  alive_count = next_alive
  fade_count = next_fade_count
  alive_cells, next_alive_cells = next_alive_list, current_alive
  fade_cells, next_fade_cells = next_fade_list, current_fade
  finish_generation(changed, next_active_alive)
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

  if APP.time_timer then
    pcall_fn(function()
      APP.time_timer:stop()
    end)
    pcall_fn(function()
      APP.time_timer:unregister()
    end)
    APP.time_timer = nil
  end

  if APP.inject_timer then
    pcall_fn(function()
      APP.inject_timer:stop()
    end)
    pcall_fn(function()
      APP.inject_timer:unregister()
    end)
    APP.inject_timer = nil
  end

  if rawget(_G, "CONWAY_LIFE_APP") == APP then
    _G.CONWAY_LIFE_APP = nil
  end

  if lv_scr_act then
    clear_root()
  end
  release_fonts()
end

APP.shutdown = APP.stop

local function tick()
  if rawget(_G, "CONWAY_LIFE_APP") ~= APP then
    return
  end

  if app_exiting_fn then
    local ok, exiting = pcall_fn(app_exiting_fn)
    if ok and exiting then
      APP.stop()
      return
    end
  end

  update_world()
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

local function get_time_parts()
  local hour = 8
  local minute = 0

  if time_getlocal_fn then
    local ok, tm = pcall_fn(time_getlocal_fn)
    if ok and tm then
      hour = tonumber(tm.hour) or hour
      minute = tonumber(tm.min) or minute
    end
  end

  return hour, minute
end

local function update_time_label()
  if not time_hour_label or not time_colon_label or not time_minute_label or not lv_label_set_text_fn then
    return
  end

  local hour, minute = get_time_parts()
  pcall_fn(lv_label_set_text_fn, time_hour_label, string_format("%02d", hour))
  pcall_fn(lv_label_set_text_fn, time_minute_label, string_format("%02d", minute))

  if lv_obj_set_style_text_opa_fn then
    pcall_fn(lv_label_set_text_fn, time_colon_label, ":")
    pcall_fn(lv_obj_set_style_text_opa_fn, time_colon_label, time_colon_visible and 255 or 0, MAIN_STYLE)
  else
    pcall_fn(lv_label_set_text_fn, time_colon_label, time_colon_visible and ":" or "")
  end

  if lv_obj_align_fn then
    pcall_fn(lv_obj_align_fn, time_hour_label, ALIGN_CENTER, TIME_HOUR_X_OFFSET, TIME_Y_OFFSET)
    pcall_fn(lv_obj_align_fn, time_colon_label, ALIGN_CENTER, TIME_COLON_X_OFFSET, TIME_Y_OFFSET)
    pcall_fn(lv_obj_align_fn, time_minute_label, ALIGN_CENTER, TIME_MINUTE_X_OFFSET, TIME_Y_OFFSET)
  end
end

local function init_time_label()
  if not lv_label_create_fn or not lv_label_set_text_fn then
    return
  end

  time_hour_label = lv_label_create_fn(root)
  time_colon_label = lv_label_create_fn(root)
  time_minute_label = lv_label_create_fn(root)
  if not time_hour_label or not time_colon_label or not time_minute_label then
    return
  end

  local labels = { time_hour_label, time_colon_label, time_minute_label }
  for i = 1, 3 do
    local label = labels[i]
    if lv_obj_set_style_text_color_fn then
      pcall_fn(lv_obj_set_style_text_color_fn, label, C.time, MAIN_STYLE)
    end
    if lv_obj_set_style_text_font_fn and TIME_FONT then
      pcall_fn(lv_obj_set_style_text_font_fn, label, TIME_FONT, MAIN_STYLE)
    end
  end

  time_colon_visible = true
  update_time_label()
end

local function init_time_timer()
  if not runtime_tmr or not runtime_tmr.create or not time_hour_label then
    return
  end

  APP.time_timer = runtime_tmr.create()
  APP.time_timer:alarm(1000, runtime_tmr.ALARM_AUTO, function()
    if rawget(_G, "CONWAY_LIFE_APP") ~= APP then
      return
    end
    time_colon_visible = not time_colon_visible
    update_time_label()
  end)
end

local function init_inject_timer()
  if not runtime_tmr or not runtime_tmr.create then
    return
  end

  APP.inject_timer = runtime_tmr.create()
  APP.inject_timer:alarm(PERIODIC_INJECT_MS, runtime_tmr.ALARM_AUTO, function()
    if rawget(_G, "CONWAY_LIFE_APP") ~= APP then
      return
    end
    add_periodic_life_patch()
  end)
end

seed_random()
build_lookup()
seed_world()
init_fonts()
init_root()

if init_canvas() then
  detect_rect_mode()
  redraw()
  init_time_label()
  init_time_timer()
  init_inject_timer()

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
