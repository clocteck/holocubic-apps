-- =========================================
-- Plane War (320x240) - levels + powerups + boss
-- NodeMCU-style global APIs only
-- =========================================

if _G.PLANE_WAR_APP and _G.PLANE_WAR_APP.shutdown then
  pcall(function() _G.PLANE_WAR_APP.shutdown() end)
end

PLANE_WAR_APP = {}
local APP = PLANE_WAR_APP
APP.VERSION = "2026-05-09-plane-war-v11-src-images"
APP.tick_timer = nil
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

if lv_scr_act then
  clear_root()
end

local root = lv_scr_act()
local W, H = 320, 240

local STATE_PLAYING   = 1
local STATE_GAME_OVER = 2

-- 如果你的设备“后仰”方向相反，改成 +18
local TILT_BACK_ANGLE = -18
local TILT_BACK_GYRO = -140
local RETRY_COOLDOWN_MS = 700
local REDRAW_INTERVAL_MS = 19

local COL = {
  BG = 0x061018,
  BG2 = 0x0C1C2A,
  HUD = 0x102436,
  LINE = 0x284E6A,
  TEXT = 0xFFFFFF,
  SUBTEXT = 0x9DB5C7,
  HINT = 0x7EA7C4,
  ACCENT = 0x33D1FF,
  PLAYER_BULLET = 0xFFD166,
  LASER_BULLET = 0x66F5FF,
  SMALL_EBULLET = 0xFFB347,
  MED_EBULLET = 0xFF4D4D,
  BOSS_BLUE = 0x4DA6FF,
  HIT_WHITE = 0xFFFFFF,
  HIT_SPARK = 0xFFE066,
  HIT_PLASMA = 0x66F5FF,
  HIT_BOSS = 0xFF5CFF,
  PANEL = 0x0B1622,
  PANEL_ACCENT = 0x22445E,
  GAMEOVER = 0xFF6B6B,
  STAR = 0xCFE8FF,
  PLAYER_FALLBACK = 0x2ED0FF,
  E1_FALLBACK = 0x7CFF6B,
  E2_FALLBACK = 0xFF5C5C,
  E3_FALLBACK = 0x8B6BFF,
  HP_PACK = 0x59F07A,
  POWER_LASER = 0xFF4DFF,
  POWER_MULTI = 0xFFD166,
  POWER_SHIELD = 0x4DA6FF,
  LIFE_ON = 0xFFFFFF,
  LIFE_OFF = 0x425564,
  LIFE_HIT = 0xFF4D4D,
}

local PATH = {
  PLAYER = "/sd/apps/plane/assets/m.bmp",
  ENEMY1 = "/sd/apps/plane/assets/e1.bmp",
  ENEMY2 = "/sd/apps/plane/assets/e2.bmp",
  ENEMY3 = "/sd/apps/plane/assets/e3.bmp",
  HP = "/sd/apps/plane/assets/hp.bmp",
  POWER_LASER = "/sd/apps/plane/assets/p_laser.bmp",
  POWER_MULTI = "/sd/apps/plane/assets/p_multi.bmp",
  POWER_SHIELD = "/sd/apps/plane/assets/p_shield.bmp",
}

-- -----------------------------------------
-- gameplay tuning
-- -----------------------------------------
local CFG = {
  MAX_LIVES = 5,
  MAX_SMALL_ENEMY = 8,
  MAX_MED_ENEMY = 3,
  MAX_PLAYER_BULLETS = 54,
  MAX_SMALL_EBULLETS = 22,
  MAX_MED_EBULLETS = 26,
  MAX_BOSS_BLUE_BULLETS = 26,
  MAX_BOSS_RED_BULLETS = 26,
  MAX_HP_PACKS = 4,
  MAX_POWERUPS = 5,
  HP_PACK_SIZE = 16,
  POWERUP_SIZE = 18,
  MAX_EFFECTS = 52,
  HP_DROP_CHANCE = 36, -- %
  POWER_DROP_SMALL_CHANCE = 10, -- %
  POWER_DROP_MED_CHANCE = 44, -- %
  POWER_DROP_BOSS_COUNT = 3,
  PLAYER_SPREAD_RAD = math.rad(10),
  DEG15 = math.rad(20),
  SHOT_LEVEL_MAX = 5,
  LASER_LEVEL_MAX = 5,
  BOSS_FIRST_GATE = 1000,
  BOSS_SCORE_STEP = 1500,
  FIRE_BASE_MS = 260,
  FIRE_TIME_STEP_MS = 6000,
  FIRE_TIME_BONUS_MS = 5,
  FIRE_MIN_MS = 88,
}

local POWER = {
  LASER = 1,
  MULTI = 2,
  SHIELD = 3,
}

local STAGES = {
  { score = 0,    spawn_min = 760, spawn_max = 1080, speed_bonus = 0,  med_bias = 1, max_small = 3, max_med = 1, med_hp_bonus = 0, boss_hp_bonus = 0,  boss_speed_bonus = 0 },
  { score = 500,  spawn_min = 600, spawn_max = 860,  speed_bonus = 5,  med_bias = 2, max_small = 4, max_med = 2, med_hp_bonus = 0, boss_hp_bonus = 12, boss_speed_bonus = 2 },
  { score = 1000, spawn_min = 470, spawn_max = 680, speed_bonus = 10, med_bias = 3, med_hp_bonus = 1, boss_hp_bonus = 24, boss_speed_bonus = 4 },
  { score = 1600, spawn_min = 420, spawn_max = 620, speed_bonus = 16, med_bias = 4, med_hp_bonus = 1, boss_hp_bonus = 40, boss_speed_bonus = 6 },
  { score = 2400, spawn_min = 360, spawn_max = 540, speed_bonus = 22, med_bias = 4, med_hp_bonus = 2, boss_hp_bonus = 58, boss_speed_bonus = 8 },
  { score = 3400, spawn_min = 320, spawn_max = 480, speed_bonus = 28, med_bias = 5, med_hp_bonus = 2, boss_hp_bonus = 78, boss_speed_bonus = 10 },
}

math.randomseed((millis() or 1) + (select(1, time.get()) or 0))
math.random()
math.random()
math.random()

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function safe_floor(v)
  return math.floor(v + 0.5)
end

local function set_visible(id, visible)
  if id then
    if visible then
      lv_obj_clear_flag(id, LV_OBJ_FLAG_HIDDEN)
    else
      lv_obj_add_flag(id, LV_OBJ_FLAG_HIDDEN)
    end
  end
end

local function aabb_hit(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

local function world_hitbox(o)
  return o.x + o.hx, o.y + o.hy, o.hw, o.hh
end

local function file_exists(path)
  if file and file.exists then
    local ok, ret = pcall(function() return file.exists(path) end)
    if ok then
      return ret and true or false
    end
  end
  return false
end

local function sd_to_lv(path)
  if type(path) == "string" and path:sub(1, 4) == "/sd/" then
    return "S:/" .. path:sub(5)
  end
  return path
end

local function image_src(path)
  if file and file.exists and not file_exists(path) then
    return nil
  end
  return sd_to_lv(path)
end

local MAIN_STYLE = LV_PART_MAIN | LV_STATE_DEFAULT

local FONT_12 = rawget(_G, "LV_FONT_MONTSERRAT_12") or 12
local FONT_18 = rawget(_G, "LV_FONT_MONTSERRAT_16") or 16
local FONT_22 = rawget(_G, "LV_FONT_MONTSERRAT_24") or 24
local FONT_30 = rawget(_G, "LV_FONT_MONTSERRAT_28") or 28

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
  FONT_18 = load_font_ref("/sd/apps/plane/font/plane_ui_18.bin", FONT_18)
  FONT_22 = load_font_ref("/sd/apps/plane/font/plane_title_22.bin", FONT_22)
  FONT_30 = load_font_ref("/sd/apps/plane/font/plane_score_30.bin", FONT_30)
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

local function set_label_text(id, text)
  if id then
    lv_label_set_text(id, text or "")
  end
end

local function set_label_color(id, color, opa)
  if id then
    lv_obj_set_style_text_color(id, color, MAIN_STYLE)
    lv_obj_set_style_text_opa(id, opa or 255, MAIN_STYLE)
  end
end

local function set_label_font(id, size)
  if id then
    lv_obj_set_style_text_font(id, size, MAIN_STYLE)
  end
end

local function create_text_label(parent, text, color, font, align, x, y)
  local id = lv_label_create(parent)
  set_label_text(id, text)
  set_label_color(id, color, 255)
  set_label_font(id, font)
  lv_obj_align(id, align, x or 0, y or 0)
  return id
end

local function canvas_frame_begin(id)
  if lv_canvas_begin and lv_canvas_end then
    local ok = pcall(function() lv_canvas_begin(id) end)
    return ok
  end
  return false
end

local function canvas_frame_end(id, explicit_frame)
  if explicit_frame and lv_canvas_end then
    pcall(function() lv_canvas_end(id) end)
  elseif lv_obj_invalidate then
    pcall(function() lv_obj_invalidate(id) end)
  end
end

print("[plane_war]", APP.VERSION)
print("player file exists:", file_exists(PATH.PLAYER))
print("enemy1 file exists:", file_exists(PATH.ENEMY1))
print("enemy2 file exists:", file_exists(PATH.ENEMY2))
print("enemy3 file exists:", file_exists(PATH.ENEMY3))
print("hp file exists:", file_exists(PATH.HP))
print("laser file exists:", file_exists(PATH.POWER_LASER))
print("multi file exists:", file_exists(PATH.POWER_MULTI))
print("shield file exists:", file_exists(PATH.POWER_SHIELD))

init_fonts()

local PLAYER_IMG_SRC = image_src(PATH.PLAYER)
local ENEMY1_IMG_SRC = image_src(PATH.ENEMY1)
local ENEMY2_IMG_SRC = image_src(PATH.ENEMY2)
local ENEMY3_IMG_SRC = image_src(PATH.ENEMY3)
local HP_IMG_SRC = image_src(PATH.HP)
local POWER_LASER_IMG_SRC = image_src(PATH.POWER_LASER)
local POWER_MULTI_IMG_SRC = image_src(PATH.POWER_MULTI)
local POWER_SHIELD_IMG_SRC = image_src(PATH.POWER_SHIELD)

print("player img src ok:", PLAYER_IMG_SRC ~= nil)
print("enemy1 img src ok:", ENEMY1_IMG_SRC ~= nil)
print("enemy2 img src ok:", ENEMY2_IMG_SRC ~= nil)
print("enemy3 img src ok:", ENEMY3_IMG_SRC ~= nil)
print("hp img src ok:", HP_IMG_SRC ~= nil)
print("laser img src ok:", POWER_LASER_IMG_SRC ~= nil)
print("multi img src ok:", POWER_MULTI_IMG_SRC ~= nil)
print("shield img src ok:", POWER_SHIELD_IMG_SRC ~= nil)

local score = 0
local level = 1
local lives = CFG.MAX_LIVES
local last_redraw_ms = -100000
local scene_canvas = lv_canvas_create(root, W, H)
lv_obj_set_pos(scene_canvas, 0, 0)
local current_stage = STAGES[1]
local boss_count = 0

local function stage_for_score(v)
  local s = STAGES[1]
  for i = 1, #STAGES do
    if v >= STAGES[i].score then
      s = STAGES[i]
    else
      break
    end
  end
  return s
end

-- -----------------------------------------
-- background
-- -----------------------------------------
local STAR_COUNT = 22
local stars = {}

for i = 1, STAR_COUNT do
  local size = (i % 4 == 0) and 2 or 1
  local opa = (i % 5 == 0) and 220 or ((i % 2 == 0) and 170 or 130)
  local sx = math.random(2, W - 4)
  local sy = math.random(36, H - 6)

  stars[i] = {
    x = sx,
    y = sy,
    size = size,
    opa = opa,
    speed = 14 + math.random(16, 56),
  }
end

-- -----------------------------------------
-- HUD
-- -----------------------------------------
local score_title = create_text_label(root, "", COL.SUBTEXT, FONT_12, LV_ALIGN_TOP_LEFT, 10, 4)
local score_label = create_text_label(root, "0", COL.TEXT, FONT_22, LV_ALIGN_TOP_LEFT, 10, 5)
local level_title = create_text_label(root, "", COL.SUBTEXT, FONT_12, LV_ALIGN_TOP_MID, 18, 4)
local level_label = create_text_label(root, "L1", COL.ACCENT, FONT_18, LV_ALIGN_TOP_MID, 18, 8)
local status_label = create_text_label(root, "TILT TO MOVE", COL.HINT, FONT_12, LV_ALIGN_BOTTOM_LEFT, 10, -8)
local footer_label = create_text_label(root, "HOME EXIT", COL.HINT, FONT_12, LV_ALIGN_BOTTOM_RIGHT, -10, -8)
set_visible(score_title, false)
set_visible(level_title, false)

-- -----------------------------------------
-- life dots (top-right)
-- -----------------------------------------
local life_title = create_text_label(root, "", COL.SUBTEXT, FONT_12, LV_ALIGN_TOP_RIGHT, -78, 4)
set_visible(life_title, false)

local life_dots = {}
for i = 1, CFG.MAX_LIVES do
  life_dots[i] = {
    x = W - 60 + (i - 1) * 12,
    y = 12,
    size = 8,
  }
end

local life_flash_toggles = 0
local life_flash_next_ms = 0
local life_flash_red = false

local function refresh_lives_ui()
  return
end

-- -----------------------------------------
-- sprite helper
-- -----------------------------------------
local IMG_DSC = { opa = 255 }
local CAPSULE_DSC = {
  bg_color = 0xFFFFFF,
  bg_opa = 255,
  radius = 3,
  border_width = 0,
  border_opa = 0,
}

local function draw_sprite(src, x, y, w, h, fallback_color, opa)
  if src and lv_canvas_draw_img then
    IMG_DSC.opa = opa or 255
    lv_canvas_draw_img(scene_canvas, safe_floor(x), safe_floor(y), src, IMG_DSC)
  else
    lv_canvas_draw_rect(scene_canvas, safe_floor(x), safe_floor(y), w, h, fallback_color, opa or 255)
  end
end

local function draw_capsule(x, y, w, h, color, opa, radius)
  CAPSULE_DSC.bg_color = color
  CAPSULE_DSC.bg_opa = opa or 255
  CAPSULE_DSC.radius = radius or math.floor(math.min(w, h) / 2)
  lv_canvas_draw_rect(scene_canvas, safe_floor(x), safe_floor(y), w, h, CAPSULE_DSC)
end

local function draw_powerup_fallback(p, color, kind, strong)
  local x = safe_floor(p.x)
  local y = safe_floor(p.y)
  local w = p.w
  local h = p.h
  local opa = strong and 240 or 185
  draw_capsule(x - 2, y - 2, w + 4, h + 4, color, strong and 95 or 58, 6)

  if kind == POWER.LASER then
    draw_capsule(x + 7, y + 3, 4, h - 6, COL.LASER_BULLET, opa, 2)
    lv_canvas_draw_rect(scene_canvas, x + 8, y + 2, 2, h - 4, COL.HIT_WHITE, 125)
  elseif kind == POWER.MULTI then
    draw_capsule(x + 4, y + 7, 3, 7, COL.PLAYER_BULLET, opa, 2)
    draw_capsule(x + 8, y + 4, 3, 9, COL.PLAYER_BULLET, opa, 2)
    draw_capsule(x + 12, y + 7, 3, 7, COL.PLAYER_BULLET, opa, 2)
    lv_canvas_draw_rect(scene_canvas, x + 8, y + 4, 3, 1, COL.HIT_WHITE, 130)
  elseif kind == POWER.SHIELD then
    draw_capsule(x + 3, y + 2, w - 6, h - 4, COL.POWER_SHIELD, opa, 6)
    draw_capsule(x + 6, y + 5, w - 12, h - 10, COL.BG, 190, 4)
    lv_canvas_draw_rect(scene_canvas, x + math.floor(w / 2), y + 4, 1, h - 8, COL.HIT_WHITE, 145)
  else
    draw_capsule(x + 2, y + 2, w - 4, h - 4, color, opa, 4)
    lv_canvas_draw_rect(scene_canvas, x + math.floor(w / 2), y + 4, 1, h - 8, COL.HIT_WHITE, 165)
    lv_canvas_draw_rect(scene_canvas, x + 4, y + math.floor(h / 2), w - 8, 1, COL.HIT_WHITE, 145)
  end
end

local function draw_hp_fallback(p, strong)
  local x = safe_floor(p.x)
  local y = safe_floor(p.y)
  local s = p.w
  local opa = strong and 255 or 205
  draw_capsule(x - 2, y - 2, s + 4, s + 4, COL.HP_PACK, strong and 92 or 55, 6)
  lv_canvas_draw_rect(scene_canvas, x + 3, y + math.floor(s / 2) - 2, s - 6, 4, COL.HP_PACK, opa)
  lv_canvas_draw_rect(scene_canvas, x + math.floor(s / 2) - 2, y + 3, 4, s - 6, COL.HP_PACK, opa)
  lv_canvas_draw_rect(scene_canvas, x + math.floor(s / 2), y + 4, 1, s - 8, COL.HIT_WHITE, strong and 150 or 95)
end

-- -----------------------------------------
-- impact / damage effects
-- -----------------------------------------
local effects = {}
for i = 1, CFG.MAX_EFFECTS do
  effects[i] = {
    active = false,
    x = 0, y = 0,
    vx = 0, vy = 0,
    size = 1,
    color = COL.HIT_SPARK,
    age = 0,
    life = 180,
  }
end

local function spawn_effect_particle(x, y, vx, vy, size, color, life)
  for i = 1, #effects do
    local e = effects[i]
    if not e.active then
      e.active = true
      e.x = x
      e.y = y
      e.vx = vx
      e.vy = vy
      e.size = size
      e.color = color
      e.age = 0
      e.life = life
      return true
    end
  end
  return false
end

local function spawn_sparks(x, y, color, count, speed_min, speed_max, size)
  for _ = 1, count do
    local a = math.random(0, 628) / 100
    local spd = math.random(speed_min, speed_max)
    spawn_effect_particle(
      x,
      y,
      math.cos(a) * spd,
      math.sin(a) * spd,
      size or math.random(1, 2),
      color,
      math.random(140, 260)
    )
  end
end

local function spawn_hit_effect(x, y, color)
  spawn_sparks(x, y, color or COL.HIT_SPARK, 7, 32, 105, 1)
  spawn_sparks(x, y, COL.HIT_WHITE, 2, 12, 42, 1)
end

local function spawn_explosion_effect(x, y, color, strong)
  spawn_sparks(x, y, color or COL.HIT_SPARK, strong and 16 or 9, 45, strong and 150 or 105, strong and 2 or 1)
  spawn_sparks(x, y, COL.HIT_WHITE, strong and 5 or 3, 18, 55, 1)
end

local function update_effects(dt)
  local dt_ms = dt * 1000
  for i = 1, #effects do
    local e = effects[i]
    if e.active then
      e.age = e.age + dt_ms
      if e.age >= e.life then
        e.active = false
      else
        e.x = e.x + e.vx * dt
        e.y = e.y + e.vy * dt
        e.vy = e.vy + 80 * dt
      end
    end
  end
end

local function draw_effects()
  for i = 1, #effects do
    local e = effects[i]
    if e.active then
      local opa = clamp(math.floor(255 * (1 - e.age / e.life)), 35, 255)
      lv_canvas_draw_rect(scene_canvas, safe_floor(e.x), safe_floor(e.y), e.size, e.size, e.color, opa)
    end
  end
end

-- -----------------------------------------
-- player
-- -----------------------------------------
local player = {
  w = 35, h = 35,
  hx = 7, hy = 7, hw = 20, hh = 22,
  x = math.floor((W - 35) / 2),
  y = H - 35 - 12,
  img_src = PLAYER_IMG_SRC,
  fallback_color = COL.PLAYER_FALLBACK,
  invincible_until = 0,
  flash_toggles = 0,
  flash_next_ms = 0,
  flash_visible = true,
}

print("player uses image:", player.img_src ~= nil)

local power_state = {
  shot_level = 1,
  laser_level = 0,
  shield = 0,
}

local CENTER_BULLET_COLORS = {
  [0] = COL.PLAYER_BULLET,
  0xF8D878,
  0xCDECA6,
  0x9AF1DC,
  0x7BEFFF,
  COL.LASER_BULLET,
}

local function shot_count_from_level(v)
  if v <= 1 then
    return 1
  elseif v <= 2 then
    return 3
  end
  return 5
end

-- -----------------------------------------
-- player bullets
-- -----------------------------------------
local player_bullets = {}

for i = 1, CFG.MAX_PLAYER_BULLETS do
  player_bullets[i] = {
    active = false,
    x = 0, y = 0,
    w = 4, h = 9,
    hx = 0, hy = 0, hw = 4, hh = 9,
    vx = 0, vy = -430,
    color = COL.PLAYER_BULLET,
    damage = 1,
    pierce_left = 0,
  }
end

local function deactivate_player_bullet(b)
  b.active = false
end

local function spawn_player_bullet(px, py, vx, vy, w, h, color, damage, pierce_left)
  for i = 1, #player_bullets do
    local b = player_bullets[i]
    if not b.active then
      b.active = true
      b.x = px
      b.y = py
      b.w = w or 4
      b.h = h or 9
      b.hw = b.w
      b.hh = b.h
      b.vx = vx or 0
      b.vy = vy or -430
      b.color = color or COL.PLAYER_BULLET
      b.damage = damage or 1
      b.pierce_left = pierce_left or 0
      return true
    end
  end
  return false
end

local function fire_player(now_ms)
  local center_x = player.x + math.floor(player.w / 2)
  local nose_y = player.y + 2
  local speed = 460
  local shot_level = clamp(power_state.shot_level, 1, CFG.SHOT_LEVEL_MAX)
  local count = shot_count_from_level(shot_level)
  local center_power = clamp(power_state.laser_level or 0, 0, CFG.LASER_LEVEL_MAX)

  local function shoot(offset_x, angle, center_shot)
    local power = center_shot and center_power or 0
    local bw = 4
    local bh = 9 + power * 2
    local color = CENTER_BULLET_COLORS[power] or COL.LASER_BULLET
    local damage = center_shot and math.max(1, power) or 1
    local shot_speed = speed
    local vx = shot_speed * math.sin(angle or 0)
    local vy = -shot_speed * math.cos(angle or 0)
    spawn_player_bullet(center_x + offset_x - math.floor(bw / 2), nose_y, vx, vy, bw, bh, color, damage, 0)
  end

  if count == 1 then
    shoot(0, 0, true)
  elseif count == 3 then
    shoot(-9, -CFG.PLAYER_SPREAD_RAD, false)
    shoot(0, 0, true)
    shoot(9, CFG.PLAYER_SPREAD_RAD, false)
  else
    shoot(-14, -CFG.PLAYER_SPREAD_RAD, false)
    shoot(-7, -CFG.PLAYER_SPREAD_RAD * 0.45, false)
    shoot(0, 0, true)
    shoot(7, CFG.PLAYER_SPREAD_RAD * 0.45, false)
    shoot(14, CFG.PLAYER_SPREAD_RAD, false)
  end
end

-- -----------------------------------------
-- generic enemy bullet pool (circular style)
-- -----------------------------------------
local function create_enemy_bullet_pool(count, size, color)
  local pool = {}
  for i = 1, count do
    pool[i] = {
      active = false,
      x = 0, y = 0,
      w = size, h = size + 2,
      hx = 0, hy = 0, hw = size, hh = size + 2,
      vx = 0, vy = 0,
      color = color,
      core_color = 0xFFFFFF,
      style = 1,
    }
  end
  return pool
end

local small_enemy_bullets = create_enemy_bullet_pool(CFG.MAX_SMALL_EBULLETS, 6, COL.SMALL_EBULLET)
local med_enemy_bullets   = create_enemy_bullet_pool(CFG.MAX_MED_EBULLETS, 8, COL.MED_EBULLET)
local boss_blue_bullets   = create_enemy_bullet_pool(CFG.MAX_BOSS_BLUE_BULLETS, 6, COL.BOSS_BLUE)
local boss_red_bullets    = create_enemy_bullet_pool(CFG.MAX_BOSS_RED_BULLETS, 8, COL.MED_EBULLET)

local function deactivate_enemy_bullet(b)
  b.active = false
end

local function spawn_enemy_bullet(pool, x, y, vx, vy, style)
  for i = 1, #pool do
    local b = pool[i]
    if not b.active then
      b.active = true
      b.x = x
      b.y = y
      b.vx = vx
      b.vy = vy
      b.style = style or 1
      return true
    end
  end
  return false
end

local function spawn_small_enemy_bullet(e)
  local cx = e.x + math.floor(e.w / 2) - 3
  local by = e.y + e.h - 2
  local speed = e.vy + 35
  spawn_enemy_bullet(small_enemy_bullets, cx, by, 0, speed, 1)
end

local function spawn_med_enemy_triplet(e)
  local cx = e.x + math.floor(e.w / 2) - 4
  local by = e.y + e.h - 2
  local speed = e.vy + 50
  local side_vx = speed * math.sin(CFG.DEG15)
  local side_vy = speed * math.cos(CFG.DEG15)

  spawn_enemy_bullet(med_enemy_bullets, cx,     by, 0,       speed, 2)
  spawn_enemy_bullet(med_enemy_bullets, cx - 8, by, -side_vx, side_vy, 2)
  spawn_enemy_bullet(med_enemy_bullets, cx + 8, by,  side_vx, side_vy, 2)
end

local function spawn_boss_blue_pair(boss)
  local speed = 55 + boss.phase * 6
  local y = boss.y + boss.h - 2
  spawn_enemy_bullet(boss_blue_bullets, boss.x + 18,         y, -18, speed, 3)
  spawn_enemy_bullet(boss_blue_bullets, boss.x + boss.w - 24, y, 18, speed, 3)
end

local function spawn_boss_red_triplet(boss)
  local speed = 80 + boss.phase * 7
  local side_vx = speed * math.sin(CFG.DEG15)
  local side_vy = speed * math.cos(CFG.DEG15)
  local cx = boss.x + math.floor(boss.w / 2) - 4
  local y = boss.y + boss.h - 4

  spawn_enemy_bullet(boss_red_bullets, cx,      y, 0,        speed, 4)
  spawn_enemy_bullet(boss_red_bullets, cx - 10, y, -side_vx, side_vy, 4)
  spawn_enemy_bullet(boss_red_bullets, cx + 10, y,  side_vx, side_vy, 4)
end

-- -----------------------------------------
-- hp packs
-- -----------------------------------------
local hp_packs = {}
for i = 1, CFG.MAX_HP_PACKS do
  hp_packs[i] = {
    active = false,
    x = 0, y = 0,
    w = CFG.HP_PACK_SIZE, h = CFG.HP_PACK_SIZE,
    hx = 1, hy = 1, hw = CFG.HP_PACK_SIZE - 2, hh = CFG.HP_PACK_SIZE - 2,
    vy = 70,
  }
end

local function deactivate_hp_pack(p)
  p.active = false
end

local function spawn_hp_pack(x, y)
  for i = 1, #hp_packs do
    local p = hp_packs[i]
    if not p.active then
      p.active = true
      p.x = x
      p.y = y
      return true
    end
  end
  return false
end

-- -----------------------------------------
-- weapon powerups
-- -----------------------------------------
local powerup_defs = {
  [POWER.LASER] = {
    name = "LASER",
    img_src = POWER_LASER_IMG_SRC,
    fallback_color = COL.POWER_LASER,
  },
  [POWER.MULTI] = {
    name = "SHOT +1",
    img_src = POWER_MULTI_IMG_SRC,
    fallback_color = COL.POWER_MULTI,
  },
  [POWER.SHIELD] = {
    name = "SHIELD",
    img_src = POWER_SHIELD_IMG_SRC,
    fallback_color = COL.POWER_SHIELD,
  },
}

local powerups = {}
for i = 1, CFG.MAX_POWERUPS do
  powerups[i] = {
    active = false,
    kind = POWER.LASER,
    x = 0, y = 0,
    w = CFG.POWERUP_SIZE, h = CFG.POWERUP_SIZE,
    hx = 1, hy = 1, hw = CFG.POWERUP_SIZE - 2, hh = CFG.POWERUP_SIZE - 2,
    vy = 72,
  }
end

local function deactivate_powerup(p)
  p.active = false
end

local function spawn_powerup(kind, x, y)
  for i = 1, #powerups do
    local p = powerups[i]
    if not p.active then
      p.active = true
      p.kind = kind
      p.x = clamp(x or 0, 4, W - p.w - 4)
      p.y = y or 34
      return true
    end
  end
  return false
end

local function spawn_random_powerup(x, y)
  local roll = math.random(1, 100)
  if roll <= 36 then
    return spawn_powerup(POWER.LASER, x, y)
  elseif roll <= 72 then
    return spawn_powerup(POWER.MULTI, x, y)
  end
  return spawn_powerup(POWER.SHIELD, x, y)
end

-- -----------------------------------------
-- enemies
-- -----------------------------------------
local function create_enemy_pool(count, w, h, img_src, fallback_color, hx, hy, hw, hh, points, base_min, base_rand, kind, base_hp)
  local pool = {}
  for i = 1, count do
    pool[i] = {
      active = false,
      x = 0, y = 0,
      w = w, h = h,
      hx = hx, hy = hy, hw = hw, hh = hh,
      vy = base_min,
      points = points,
      base_min = base_min,
      base_rand = base_rand,
      kind = kind, -- "small" / "med"
      hp = base_hp,
      max_hp = base_hp,
      img_src = img_src,
      fallback_color = fallback_color,
      fired = false,
      fire_y = 90,
    }
  end
  return pool
end

local small_enemies = create_enemy_pool(
  CFG.MAX_SMALL_ENEMY, 22, 22, ENEMY1_IMG_SRC, COL.E1_FALLBACK,
  4, 4, 14, 14,
  20, 50, 24, "small", 1
)

local med_enemies = create_enemy_pool(
  CFG.MAX_MED_ENEMY, 35, 35, ENEMY2_IMG_SRC, COL.E2_FALLBACK,
  5, 5, 24, 24,
  100, 36, 18, "med", 3
)

print("enemy1 uses image:", small_enemies[1] and (small_enemies[1].img_src ~= nil))
print("enemy2 uses image:", med_enemies[1] and (med_enemies[1].img_src ~= nil))

local function deactivate_enemy(e)
  e.active = false
end

local function count_active(pool)
  local n = 0
  for i = 1, #pool do
    if pool[i].active then
      n = n + 1
    end
  end
  return n
end

local last_spawn_x = math.floor(W / 2)

local function next_spawn_x(enemy_w)
  local min_x = 8
  local max_x = W - enemy_w - 8
  local x = min_x
  for _ = 1, 6 do
    local cand = math.random(min_x, max_x)
    if math.abs(cand - last_spawn_x) >= 22 then
      x = cand
      last_spawn_x = cand
      return x
    end
    x = cand
  end
  last_spawn_x = x
  return x
end

local function setup_enemy_fire(e)
  e.fired = false
  if e.kind == "small" then
    e.fire_y = math.random(8, 50)   -- 更早射出
  else
    e.fire_y = math.random(5, 20)   -- 更早射出
  end
end

local function spawn_from_pool(pool)
  for i = 1, #pool do
    local e = pool[i]
    if not e.active then
      e.active = true
      e.x = next_spawn_x(e.w)
      e.y = -e.h

      local st = current_stage or STAGES[1]
      local speed_bonus = st.speed_bonus or 0
      e.vy = e.base_min + math.random(0, e.base_rand) + speed_bonus
      e.hp = e.max_hp
      if e.kind == "med" then
        e.hp = e.hp + (st.med_hp_bonus or 0)
      end
      setup_enemy_fire(e)
      return true
    end
  end
  return false
end

-- -----------------------------------------
-- boss
-- -----------------------------------------
local boss = {
  active = false,
  w = 84, h = 48,
  hx = 8, hy = 8, hw = 68, hh = 30,
  x = math.floor((W - 84) / 2),
  y = 36,
  dir = 1,
  speed = 42,
  img_src = ENEMY3_IMG_SRC,
  fallback_color = COL.E3_FALLBACK,
  hp = 0,
  max_hp = 0,
  points = 0,
  phase = 0,
  next_blue_ms = 0,
  next_red_ms = 0,
}

print("enemy3 uses image:", boss.img_src ~= nil)

local next_boss_gate = CFG.BOSS_FIRST_GATE

local boss_title = lv_label_create(root)
set_label_text(boss_title, "BOSS")
set_label_color(boss_title, COL.GAMEOVER, 255)
set_label_font(boss_title, FONT_12)
lv_obj_set_pos(boss_title, 126, 34)
set_visible(boss_title, false)

local function refresh_boss_hp_ui()
  return
end

local function deactivate_boss()
  boss.active = false
  set_visible(boss_title, false)
end

local function spawn_boss(now_ms)
  local st = current_stage or STAGES[1]
  boss.active = true
  boss_count = boss_count + 1
  boss.phase = boss_count
  boss.x = math.floor((W - boss.w) / 2)
  boss.y = 36
  boss.dir = (math.random(0, 1) == 0) and -1 or 1
  boss.speed = 40 + boss.phase * 3 + (st.boss_speed_bonus or 0)
  boss.max_hp = 95 + (boss.phase - 1) * 25 + (st.boss_hp_bonus or 0)
  boss.hp = boss.max_hp
  boss.points = 400 + (boss.phase - 1) * 120
  boss.next_blue_ms = now_ms + math.random(700, 980)
  boss.next_red_ms = now_ms + math.random(1200, 1650)

  set_visible(boss_title, true)
  refresh_boss_hp_ui()

  next_boss_gate = next_boss_gate + CFG.BOSS_SCORE_STEP
end

-- -----------------------------------------
-- panel
-- -----------------------------------------
local panel_visible = false
local PANEL_X = 56
local PANEL_Y = 56
local PANEL_W = 208
local PANEL_H = 132
local OVER_IMG_SRC = { handle = nil }
local OVER_IMG_DSC = { opa = 255 }
local game_over_snapshot_handle = nil
local game_over_blur = lv_canvas_create(root, PANEL_W, PANEL_H, LV_IMG_CF_TRUE_COLOR)
lv_obj_set_pos(game_over_blur, PANEL_X, PANEL_Y)

local over_title = create_text_label(root, "GAME OVER", COL.GAMEOVER, FONT_22, LV_ALIGN_TOP_LEFT, PANEL_X + 44, PANEL_Y + 24)
local over_score = create_text_label(root, "0", COL.TEXT, FONT_30, LV_ALIGN_TOP_LEFT, PANEL_X, PANEL_Y + 52)
if lv_obj_set_width then
  lv_obj_set_width(over_score, PANEL_W)
end
if lv_obj_set_style_text_align then
  pcall(function() lv_obj_set_style_text_align(over_score, LV_TEXT_ALIGN_CENTER, MAIN_STYLE) end)
end
local over_hint1 = create_text_label(root, "TILT RETRY", COL.ACCENT, FONT_12, LV_ALIGN_TOP_LEFT, PANEL_X, PANEL_Y + 92)
local over_hint2 = create_text_label(root, "HOME EXIT", COL.HINT, FONT_12, LV_ALIGN_TOP_LEFT, PANEL_X, PANEL_Y + 108)
if lv_obj_set_width then
  lv_obj_set_width(over_hint1, PANEL_W)
  lv_obj_set_width(over_hint2, PANEL_W)
end
if lv_obj_set_style_text_align then
  pcall(function() lv_obj_set_style_text_align(over_hint1, LV_TEXT_ALIGN_CENTER, MAIN_STYLE) end)
  pcall(function() lv_obj_set_style_text_align(over_hint2, LV_TEXT_ALIGN_CENTER, MAIN_STYLE) end)
end

set_visible(over_title, false)
set_visible(over_score, false)
set_visible(over_hint1, false)
set_visible(over_hint2, false)
set_visible(game_over_blur, false)

-- -----------------------------------------
-- canvas redraw
-- -----------------------------------------
local function draw_hud_background()
  lv_canvas_fill_bg(scene_canvas, COL.BG, 255)
  lv_canvas_draw_rect(scene_canvas, 0, 0, W, 34, COL.BG2, 255)
  lv_canvas_draw_rect(scene_canvas, 0, 0, W, 30, COL.HUD, 235)
  lv_canvas_draw_rect(scene_canvas, 0, 30, W, 1, COL.LINE, 255)
end

local function draw_stars()
  for i = 1, #stars do
    local s = stars[i]
    lv_canvas_draw_rect(scene_canvas, safe_floor(s.x), safe_floor(s.y), s.size, s.size, COL.STAR, s.opa)
  end
end

local function draw_lives()
  for i = 1, CFG.MAX_LIVES do
    local dot = life_dots[i]
    local color = COL.LIFE_OFF
    if i <= lives then
      color = life_flash_red and COL.LIFE_HIT or COL.LIFE_ON
    end
    lv_canvas_draw_rect(scene_canvas, dot.x, dot.y, dot.size, dot.size, color, 255)
  end

  if (power_state.shield or 0) > 0 then
    for i = 1, power_state.shield do
      lv_canvas_draw_rect(scene_canvas, W - 60 + (i - 1) * 12, 24, 8, 2, COL.POWER_SHIELD, 255)
    end
  end
end

local function draw_bullet_pool(pool)
  for i = 1, #pool do
    local b = pool[i]
    if b.active then
      draw_capsule(b.x, b.y, b.w, b.h, b.color, 235, math.floor(b.w / 2))
      if b.style == 2 then
        draw_capsule(b.x + 2, b.y + 1, math.max(2, b.w - 4), math.max(3, b.h - 2), 0xFFE8AA, 210, 2)
      elseif b.style == 3 then
        draw_capsule(b.x + 1, b.y + 1, math.max(2, b.w - 2), math.max(3, b.h - 3), 0xBDEFFF, 190, 2)
      elseif b.style == 4 then
        lv_canvas_draw_rect(scene_canvas, safe_floor(b.x + math.floor(b.w / 2)), safe_floor(b.y), 1, b.h, COL.HIT_WHITE, 175)
      end
    end
  end
end

local function draw_enemy_pool(pool, now_ms)
  for i = 1, #pool do
    local e = pool[i]
    if e.active then
      draw_sprite(e.img_src, e.x, e.y, e.w, e.h, e.fallback_color, 255)
    end
  end
end

local function draw_hp_packs()
  for i = 1, #hp_packs do
    local p = hp_packs[i]
    if p.active then
      draw_capsule(p.x - 1, p.y - 1, p.w + 2, p.h + 2, COL.HP_PACK, 55, 5)
      if HP_IMG_SRC then
        draw_sprite(HP_IMG_SRC, p.x, p.y, p.w, p.h, COL.HP_PACK, 255)
      end
      draw_hp_fallback(p, HP_IMG_SRC == nil)
    end
  end
end

local function draw_powerups()
  for i = 1, #powerups do
    local p = powerups[i]
    if p.active then
      local def = powerup_defs[p.kind] or powerup_defs[POWER.LASER]
      draw_capsule(p.x - 1, p.y - 1, p.w + 2, p.h + 2, def.fallback_color, 55, 5)
      if def.img_src then
        draw_sprite(def.img_src, p.x, p.y, p.w, p.h, def.fallback_color, 255)
      end
      draw_powerup_fallback(p, def.fallback_color, p.kind, def.img_src == nil)
    end
  end
end

local function draw_boss_hp()
  if not boss.active or boss.max_hp <= 0 then
    return
  end

  local bar_w = math.floor(124 * boss.hp / boss.max_hp + 0.5)
  bar_w = clamp(bar_w, 0, 124)
  lv_canvas_draw_rect(scene_canvas, 98, 48, 124, 6, 0x2B3540, 255)
  if bar_w > 0 then
    lv_canvas_draw_rect(scene_canvas, 98, 48, bar_w, 6, COL.GAMEOVER, 255)
  end
end

local function draw_game_over_panel()
  if not panel_visible then
    return
  end
  lv_canvas_draw_rect(scene_canvas, 0, 0, W, H, 0x000000, 86)
end

local function redraw_scene()
  local now_ms = millis() or 0
  if now_ms - last_redraw_ms < REDRAW_INTERVAL_MS then
    return false
  end
  last_redraw_ms = now_ms

  local explicit_frame = canvas_frame_begin(scene_canvas)

  draw_hud_background()
  draw_stars()
  draw_lives()

  if player.flash_visible then
    draw_sprite(player.img_src, player.x, player.y, player.w, player.h, player.fallback_color, 255)
  end

  for i = 1, #player_bullets do
    local b = player_bullets[i]
    if b.active then
      draw_capsule(b.x, b.y, b.w, b.h, b.color or COL.PLAYER_BULLET, 255, 2)
    end
  end

  draw_bullet_pool(small_enemy_bullets)
  draw_bullet_pool(med_enemy_bullets)
  draw_bullet_pool(boss_blue_bullets)
  draw_bullet_pool(boss_red_bullets)
  draw_enemy_pool(small_enemies, now_ms)
  draw_enemy_pool(med_enemies, now_ms)

  if boss.active then
    draw_sprite(boss.img_src, boss.x, boss.y, boss.w, boss.h, boss.fallback_color, 255)
  end

  draw_boss_hp()
  draw_hp_packs()
  draw_powerups()
  draw_effects()
  draw_game_over_panel()

  canvas_frame_end(scene_canvas, explicit_frame)
  return true
end

-- -----------------------------------------
-- score / state
-- -----------------------------------------
local set_status_text = nil

local function refresh_score_ui()
  set_label_text(score_label, tostring(score))
end

local function refresh_level_ui()
  set_label_text(level_label, "L" .. tostring(level))
end

local function update_level_from_score(now_ms, announce)
  current_stage = stage_for_score(score)
  local new_level = 1
  for i = 1, #STAGES do
    if STAGES[i] == current_stage then
      new_level = i
      break
    end
  end

  if new_level > level then
    level = new_level
    refresh_level_ui()
    if announce and set_status_text then
      set_status_text("LEVEL " .. tostring(level), (now_ms or 0) + 1000)
    end
    spawn_random_powerup(math.random(54, W - 70), 36)
  elseif new_level < level then
    level = new_level
    refresh_level_ui()
  end
end

local function set_score(v)
  score = math.max(0, math.floor(v))
  refresh_score_ui()
  update_level_from_score(millis() or 0, true)
end

refresh_score_ui()
refresh_level_ui()
refresh_lives_ui()

local state = STATE_PLAYING
local last_ts = nil
local start_ms = millis() or 0
local next_fire_ms = 0
local next_spawn_ms = 0
local status_hint_until_ms = 0
local status_hint_text = ""

local filtered_pitch = 0
local last_roll = 0
local last_pitch = 0
local last_gx = 0
local last_gy = 0
local last_retry_ms = -100000

set_status_text = function(s, until_ms)
  status_hint_text = s or ""
  status_hint_until_ms = until_ms or 0
  set_label_text(status_label, status_hint_text)
end

local function release_game_over_snapshot()
  if game_over_snapshot_handle and lv_img_free_handle then
    pcall(function() lv_img_free_handle(game_over_snapshot_handle) end)
  end
  game_over_snapshot_handle = nil
end

local function refresh_game_over_blur()
  if not game_over_blur then
    return
  end

  release_game_over_snapshot()

  local explicit_frame = canvas_frame_begin(game_over_blur)
  if not explicit_frame then
    return
  end

  local handle = nil
  if lv_snapshot_take and lv_canvas_draw_img and lv_canvas_blur_hor and lv_canvas_blur_ver then
    local ok, snapshot = pcall(function()
      return lv_snapshot_take(root, LV_IMG_CF_TRUE_COLOR)
    end)
    if ok and snapshot then
      handle = snapshot
      game_over_snapshot_handle = snapshot
    end
  end

  if handle then
    OVER_IMG_SRC.handle = handle
    OVER_IMG_DSC.opa = 255
    lv_canvas_draw_img(game_over_blur, -PANEL_X, -PANEL_Y, OVER_IMG_SRC, OVER_IMG_DSC)
    lv_canvas_blur_hor(game_over_blur, nil, 7)
    lv_canvas_blur_ver(game_over_blur, nil, 7)
  else
    lv_canvas_fill_bg(game_over_blur, 0x102436, 235)
  end

  lv_canvas_draw_rect(game_over_blur, 0, 0, PANEL_W, PANEL_H, {
    bg_color = 0xD8F3FF,
    bg_opa = 54,
    radius = 14,
    border_width = 1,
    border_color = 0xBDEFFF,
    border_opa = 120,
  })
  lv_canvas_draw_rect(game_over_blur, 10, 8, PANEL_W - 20, 22, {
    bg_color = 0xFFFFFF,
    bg_opa = 18,
    radius = 8,
    border_width = 0,
    border_opa = 0,
  })
  lv_canvas_draw_rect(game_over_blur, 24, PANEL_H - 18, PANEL_W - 48, 1, 0xE6FAFF, 52)

  canvas_frame_end(game_over_blur, explicit_frame)
end

local function show_panel(show)
  panel_visible = show and true or false
  if panel_visible then
    refresh_game_over_blur()
  else
    release_game_over_snapshot()
  end
  set_visible(game_over_blur, panel_visible)
  set_visible(over_title, panel_visible)
  set_visible(over_score, panel_visible)
  set_visible(over_hint1, panel_visible)
  set_visible(over_hint2, panel_visible)
  if panel_visible and lv_obj_move_foreground then
    pcall(function() lv_obj_move_foreground(game_over_blur) end)
    pcall(function() lv_obj_move_foreground(over_title) end)
    pcall(function() lv_obj_move_foreground(over_score) end)
    pcall(function() lv_obj_move_foreground(over_hint1) end)
    pcall(function() lv_obj_move_foreground(over_hint2) end)
  end
end

local function start_player_hit_flash(now_ms)
  player.flash_toggles = 6     -- 闪烁3次
  player.flash_next_ms = now_ms + 100
  player.flash_visible = false

  life_flash_toggles = 6
  life_flash_next_ms = now_ms + 100
  life_flash_red = true
  refresh_lives_ui()
end

local function heal_player(now_ms)
  if lives < CFG.MAX_LIVES then
    lives = lives + 1
    refresh_lives_ui()
    set_status_text("HP +1", now_ms + 700)
  end
end

local function show_game_over(ts_ms)
  state = STATE_GAME_OVER
  set_label_text(over_score, tostring(score))
  set_status_text("", ts_ms + 999999)
  show_panel(true)
  last_retry_ms = ts_ms or (millis() or 0)
  redraw_scene()
end

local function damage_player(now_ms)
  if state ~= STATE_PLAYING then
    return
  end
  if now_ms < player.invincible_until then
    return
  end
  if (power_state.shield or 0) > 0 then
    power_state.shield = power_state.shield - 1
    player.invincible_until = now_ms + 450
    spawn_explosion_effect(player.x + math.floor(player.w / 2), player.y + math.floor(player.h / 2), COL.POWER_SHIELD, false)
    set_status_text("BLOCK", now_ms + 600)
    return
  end

  lives = lives - 1
  if lives < 0 then lives = 0 end
  refresh_lives_ui()
  spawn_explosion_effect(player.x + math.floor(player.w / 2), player.y + math.floor(player.h / 2), COL.LIFE_HIT, false)

  if lives <= 0 then
    spawn_explosion_effect(player.x + math.floor(player.w / 2), player.y + math.floor(player.h / 2), COL.LIFE_HIT, true)
    show_game_over(now_ms)
    return
  end

  player.invincible_until = now_ms + 900
  start_player_hit_flash(now_ms)
  set_status_text("HIT!", now_ms + 600)
end

local function reset_game(ts_ms)
  state = STATE_PLAYING
  show_panel(false)

  player.x = math.floor((W - player.w) / 2)
  player.y = H - player.h - 12
  player.invincible_until = 0
  player.flash_toggles = 0
  player.flash_visible = true

  for i = 1, #player_bullets do deactivate_player_bullet(player_bullets[i]) end
  for i = 1, #small_enemy_bullets do deactivate_enemy_bullet(small_enemy_bullets[i]) end
  for i = 1, #med_enemy_bullets do deactivate_enemy_bullet(med_enemy_bullets[i]) end
  for i = 1, #boss_blue_bullets do deactivate_enemy_bullet(boss_blue_bullets[i]) end
  for i = 1, #boss_red_bullets do deactivate_enemy_bullet(boss_red_bullets[i]) end
  for i = 1, #small_enemies do deactivate_enemy(small_enemies[i]) end
  for i = 1, #med_enemies do deactivate_enemy(med_enemies[i]) end
  for i = 1, #hp_packs do deactivate_hp_pack(hp_packs[i]) end
  for i = 1, #powerups do deactivate_powerup(powerups[i]) end
  for i = 1, #effects do effects[i].active = false end
  deactivate_boss()

  filtered_pitch = 0
  last_roll = 0
  last_pitch = 0
  last_gx = 0
  last_gy = 0

  life_flash_toggles = 0
  life_flash_red = false

  lives = CFG.MAX_LIVES
  power_state.shot_level = 1
  power_state.laser_level = 0
  power_state.shield = 0
  refresh_lives_ui()
  set_score(0)
  start_ms = ts_ms or (millis() or 0)
  next_boss_gate = CFG.BOSS_FIRST_GATE
  boss_count = 0
  current_stage = STAGES[1]
  set_status_text("TILT TO MOVE", (ts_ms or 0) + 1600)

  last_ts = ts_ms
  next_fire_ms = (ts_ms or 0) + 130
  next_spawn_ms = (ts_ms or 0) + 1050
  last_redraw_ms = -100000
  redraw_scene()
end

reset_game(millis() or 0)

-- -----------------------------------------
-- movement / collision
-- -----------------------------------------
local function player_speed_from_pitch(p)
  local ap = math.abs(p)
  if ap < 1 then
    return 0
  elseif ap < 10 then
    return 120
  elseif ap < 20 then
    return 180
  else
    return 220
  end
end

local function player_dir_from_pitch(p)
  if p <= -2 then
    return 1
  elseif p >= 2 then
    return -1
  end
  return 0
end

local function player_hit_object(o)
  local px, py, pw, ph = world_hitbox(player)
  local ox, oy, ow, oh = world_hitbox(o)
  return aabb_hit(px, py, pw, ph, ox, oy, ow, oh)
end

local function player_bullet_hit_enemy(b, e)
  if (b.y + b.h) < e.y then
    return false
  end
  if b.y > (e.y + e.h) then
    return false
  end

  local bx, by, bw, bh = world_hitbox(b)
  local ex, ey, ew, eh = world_hitbox(e)
  return aabb_hit(bx, by, bw, bh, ex, ey, ew, eh)
end

local function update_stars(dt)
  local mul = (state == STATE_PLAYING) and 1.0 or 0.35
  for i = 1, #stars do
    local s = stars[i]
    s.y = s.y + s.speed * dt * mul
    if s.y > H + 2 then
      s.y = 34 + math.random(0, 6)
      s.x = math.random(2, W - 4)
    end
  end
end

local function update_player_flash(now_ms)
  while player.flash_toggles > 0 and now_ms >= player.flash_next_ms do
    player.flash_visible = not player.flash_visible
    player.flash_next_ms = player.flash_next_ms + 100
    player.flash_toggles = player.flash_toggles - 1
  end

  if player.flash_toggles <= 0 and now_ms >= player.invincible_until then
    player.flash_visible = true
  end
end

local function update_life_flash(now_ms)
  while life_flash_toggles > 0 and now_ms >= life_flash_next_ms do
    life_flash_red = not life_flash_red
    refresh_lives_ui()
    life_flash_next_ms = life_flash_next_ms + 100
    life_flash_toggles = life_flash_toggles - 1
  end

  if life_flash_toggles <= 0 and life_flash_red then
    life_flash_red = false
    refresh_lives_ui()
  end
end

local function update_player_bullets(dt)
  for i = 1, #player_bullets do
    local b = player_bullets[i]
    if b.active then
      b.x = b.x + b.vx * dt
      b.y = b.y + b.vy * dt
      if b.y < -b.h - 2 then
        deactivate_player_bullet(b)
      end
    end
  end
end

local function update_enemy_bullet_pool(pool, dt, now_ms)
  for i = 1, #pool do
    local b = pool[i]
    if b.active then
      b.x = b.x + b.vx * dt
      b.y = b.y + b.vy * dt
      if b.y > H + 12 or b.x < -16 or b.x > W + 16 then
        deactivate_enemy_bullet(b)
      else
        if player_hit_object(b) then
          deactivate_enemy_bullet(b)
          damage_player(now_ms)
          if state == STATE_GAME_OVER then
            return true
          end
        end
      end
    end
  end
  return false
end

local function maybe_enemy_fire(e)
  if e.fired then
    return
  end
  if e.y < e.fire_y then
    return
  end

  e.fired = true
  if e.kind == "small" then
    spawn_small_enemy_bullet(e)
  else
    spawn_med_enemy_triplet(e)
  end
end

local function update_enemy_pool(pool, dt, now_ms)
  for i = 1, #pool do
    local e = pool[i]
    if e.active then
      e.y = e.y + e.vy * dt
      if e.y > H + 12 then
        deactivate_enemy(e)
      else
        maybe_enemy_fire(e)

        if player_hit_object(e) then
          spawn_explosion_effect(e.x + math.floor(e.w / 2), e.y + math.floor(e.h / 2), e.fallback_color, e.kind == "med")
          deactivate_enemy(e)
          damage_player(now_ms)
          if state == STATE_GAME_OVER then
            return true
          end
        end
      end
    end
  end
  return false
end

local function update_boss(dt, now_ms)
  if not boss.active then
    return
  end

  boss.x = boss.x + boss.dir * boss.speed * dt
  if boss.x <= 8 then
    boss.x = 8
    boss.dir = 1
  elseif boss.x >= W - boss.w - 8 then
    boss.x = W - boss.w - 8
    boss.dir = -1
  end

  if now_ms >= boss.next_blue_ms then
    spawn_boss_blue_pair(boss)
    boss.next_blue_ms = now_ms + math.random(1200, 2020)
  end

  if now_ms >= boss.next_red_ms then
    spawn_boss_red_triplet(boss)
    boss.next_red_ms = now_ms + math.random(1980, 3520)
  end
end

local function maybe_drop_from_enemy(e)
  local drop_x = e.x + math.floor((e.w - CFG.POWERUP_SIZE) / 2)
  local drop_y = e.y + math.floor((e.h - CFG.POWERUP_SIZE) / 2)

  if e.kind == "med" then
    if lives < CFG.MAX_LIVES and math.random(1, 100) <= CFG.HP_DROP_CHANCE then
      spawn_hp_pack(e.x + math.floor((e.w - CFG.HP_PACK_SIZE) / 2), e.y + math.floor((e.h - CFG.HP_PACK_SIZE) / 2))
      return
    end
    if math.random(1, 100) <= CFG.POWER_DROP_MED_CHANCE then
      spawn_random_powerup(drop_x, drop_y)
    end
  elseif math.random(1, 100) <= CFG.POWER_DROP_SMALL_CHANCE then
    spawn_random_powerup(drop_x, drop_y)
  end
end

local function hit_enemy_with_player_bullets(pool)
  for bi = 1, #player_bullets do
    local b = player_bullets[bi]
    if b.active then
      for ei = 1, #pool do
        local e = pool[ei]
        if e.active and player_bullet_hit_enemy(b, e) then
          spawn_hit_effect(b.x + math.floor(b.w / 2), b.y, (b.color == COL.LASER_BULLET) and COL.HIT_PLASMA or COL.HIT_SPARK)
          e.hp = e.hp - (b.damage or 1)
          if (b.pierce_left or 0) > 0 then
            b.pierce_left = b.pierce_left - 1
          else
            deactivate_player_bullet(b)
          end
          if e.hp <= 0 then
            spawn_explosion_effect(e.x + math.floor(e.w / 2), e.y + math.floor(e.h / 2), e.fallback_color, e.kind == "med")
            deactivate_enemy(e)
            set_score(score + e.points)
            maybe_drop_from_enemy(e)
          end
          break
        end
      end
    end
  end
end

local function hit_boss_with_player_bullets()
  if not boss.active then
    return
  end

  local bx, by, bw, bh = world_hitbox(boss)

  for i = 1, #player_bullets do
    local b = player_bullets[i]
    if b.active then
      local px, py, pw, ph = world_hitbox(b)
      if aabb_hit(px, py, pw, ph, bx, by, bw, bh) then
        spawn_hit_effect(b.x + math.floor(b.w / 2), b.y, (b.color == COL.LASER_BULLET) and COL.HIT_PLASMA or COL.HIT_BOSS)
        boss.hp = boss.hp - (b.damage or 1)
        if (b.pierce_left or 0) > 0 then
          b.pierce_left = b.pierce_left - 1
        else
          deactivate_player_bullet(b)
        end
        if boss.hp < 0 then boss.hp = 0 end
        refresh_boss_hp_ui()

        if boss.hp <= 0 then
          local reward_x = boss.x + 12
          local reward_y = boss.y + math.floor(boss.h / 2)
          local reward_step = CFG.POWERUP_SIZE + 6
          spawn_explosion_effect(boss.x + math.floor(boss.w / 2), boss.y + math.floor(boss.h / 2), COL.HIT_BOSS, true)
          deactivate_boss()
          set_score(score + boss.points)
          for n = 1, CFG.POWER_DROP_BOSS_COUNT do
            spawn_random_powerup(reward_x + (n - 1) * reward_step, reward_y)
          end
          if lives < CFG.MAX_LIVES then
            spawn_hp_pack(reward_x + reward_step * CFG.POWER_DROP_BOSS_COUNT, reward_y)
          end
          set_status_text("BOSS DOWN!", (millis() or 0) + 1000)
          break
        end
      end
    end
  end
end

local function update_hp_packs(dt, now_ms)
  for i = 1, #hp_packs do
    local p = hp_packs[i]
    if p.active then
      p.y = p.y + p.vy * dt
      if p.y > H + 12 then
        deactivate_hp_pack(p)
      else
        if player_hit_object(p) then
          deactivate_hp_pack(p)
          heal_player(now_ms)
        end
      end
    end
  end
end

local function apply_powerup(kind, now_ms)
  if kind == POWER.LASER then
    power_state.laser_level = clamp((power_state.laser_level or 0) + 1, 0, CFG.LASER_LEVEL_MAX)
    set_status_text("LASER " .. tostring(power_state.laser_level), now_ms + 900)
  elseif kind == POWER.MULTI then
    power_state.shot_level = clamp(power_state.shot_level + 1, 1, CFG.SHOT_LEVEL_MAX)
    set_status_text("SHOT x" .. tostring(shot_count_from_level(power_state.shot_level)), now_ms + 900)
  elseif kind == POWER.SHIELD then
    power_state.shield = clamp((power_state.shield or 0) + 1, 0, 2)
    set_status_text("SHIELD", now_ms + 900)
  end
end

local function update_powerups(dt, now_ms)
  for i = 1, #powerups do
    local p = powerups[i]
    if p.active then
      p.y = p.y + p.vy * dt
      if p.y > H + 16 then
        deactivate_powerup(p)
      elseif player_hit_object(p) then
        local kind = p.kind
        deactivate_powerup(p)
        apply_powerup(kind, now_ms)
      end
    end
  end
end

local function next_spawn_delay_ms()
  local st = current_stage or STAGES[1]
  if boss.active then
    return math.random(900, 1350)
  end

  local min_d = st.spawn_min or 560
  local max_d = st.spawn_max or 800
  if max_d < min_d then
    max_d = min_d
  end
  return math.random(min_d, max_d)
end

local function spawn_enemy()
  local small_alive = count_active(small_enemies)
  local med_alive = count_active(med_enemies)
  local st = current_stage or STAGES[1]
  local max_small = st.max_small or 4
  local max_med = st.max_med or 2

  if boss.active then
    max_small = 2
    max_med = 1
    if small_alive >= 2 and med_alive >= 1 then
      return false
    end
  else
    if small_alive >= max_small and med_alive >= max_med then
      return false
    end
  end

  local med_bias = st.med_bias or 2

  if boss.active then
    if med_alive >= 1 then
      med_bias = 1
    end
  end

  local roll = math.random(1, 10)
  if roll <= med_bias then
    if med_alive < max_med then
      if spawn_from_pool(med_enemies) then return true end
    end
    if small_alive < max_small then
      return spawn_from_pool(small_enemies)
    end
  else
    if small_alive < max_small then
      if spawn_from_pool(small_enemies) then return true end
    end
    if med_alive < max_med then
      return spawn_from_pool(med_enemies)
    end
  end

  return false
end

local function player_fire_interval_ms(now_ms)
  local survive_ms = now_ms - start_ms
  local time_step = math.floor(survive_ms / CFG.FIRE_TIME_STEP_MS)
  local score_step = math.floor(score / 700)
  local iv = CFG.FIRE_BASE_MS - time_step * CFG.FIRE_TIME_BONUS_MS - score_step * 7
  return clamp(iv, CFG.FIRE_MIN_MS, CFG.FIRE_BASE_MS)
end

-- -----------------------------------------
-- events
-- -----------------------------------------
key.on(key.HOME, function(type, ts_ms)
  if type == key.SHORT then
    if APP.shutdown then
      APP.shutdown()
    end
    pcall(function()
      app.exit()
    end)
  end
end)

app.on("imu", function(name, roll, pitch, gx, gy, gz, ts_ms)
  last_roll = roll or 0
  last_pitch = pitch or 0
  last_gx = gx or 0
  last_gy = gy or 0

  filtered_pitch = filtered_pitch * 0.75 + (last_pitch * 0.25)

  if state == STATE_GAME_OVER then
    local now_ms = ts_ms or (millis() or 0)
    if now_ms - last_retry_ms >= RETRY_COOLDOWN_MS then
      local retry_by_angle = (last_roll <= TILT_BACK_ANGLE)
      local retry_by_gyro = (last_gx <= TILT_BACK_GYRO) or (last_gy <= TILT_BACK_GYRO)
      if retry_by_angle or retry_by_gyro then
        reset_game(now_ms)
      end
    end
  end
end)

APP.tick_timer = tmr.create()
APP.tick_timer:alarm(20, tmr.ALARM_AUTO, function()
  if app.exiting() then
    return
  end

  local ts_ms = millis() or 0

  if not last_ts then
    last_ts = ts_ms
  end

  local dt_ms = ts_ms - last_ts
  if dt_ms < 10 then
    return
  end
  if dt_ms > 60 then
    dt_ms = 60
  end
  last_ts = ts_ms

  local dt = dt_ms / 1000.0

  update_stars(dt)
  update_player_flash(ts_ms)
  update_life_flash(ts_ms)
  update_effects(dt)

  if state == STATE_GAME_OVER then
    redraw_scene()
    return
  end

  if ts_ms > status_hint_until_ms then
    if status_hint_text ~= "" then
      status_hint_text = ""
      set_label_text(status_label, "")
    end
  end

  if (not boss.active) and score >= next_boss_gate then
    spawn_boss(ts_ms)
    set_status_text("BOSS INCOMING!", ts_ms + 1200)
  end

  -- player move
  local dir = player_dir_from_pitch(filtered_pitch)
  local speed = player_speed_from_pitch(filtered_pitch)
  if dir ~= 0 and speed > 0 then
    player.x = clamp(player.x + dir * speed * dt, 0, W - player.w)
  end

  -- player auto fire: 随时间加快
  if ts_ms >= next_fire_ms then
    fire_player(ts_ms)
    next_fire_ms = ts_ms + player_fire_interval_ms(ts_ms)
  end

  -- enemy spawn
  if ts_ms >= next_spawn_ms then
    spawn_enemy()
    next_spawn_ms = ts_ms + next_spawn_delay_ms()
  end

  update_player_bullets(dt)

  if update_enemy_bullet_pool(small_enemy_bullets, dt, ts_ms) then return end
  if update_enemy_bullet_pool(med_enemy_bullets, dt, ts_ms) then return end
  if update_enemy_bullet_pool(boss_blue_bullets, dt, ts_ms) then return end
  if update_enemy_bullet_pool(boss_red_bullets, dt, ts_ms) then return end

  if update_enemy_pool(small_enemies, dt, ts_ms) then return end
  if update_enemy_pool(med_enemies, dt, ts_ms) then return end

  update_boss(dt, ts_ms)

  hit_enemy_with_player_bullets(med_enemies)
  hit_enemy_with_player_bullets(small_enemies)
  hit_boss_with_player_bullets()

  update_hp_packs(dt, ts_ms)
  update_powerups(dt, ts_ms)
  redraw_scene()
end)

-- -----------------------------------------
-- cleanup
-- -----------------------------------------
function APP.shutdown()
  pcall(function() app.on("imu", nil) end)
  pcall(function() key.off(key.HOME) end)
  if APP.tick_timer then
    pcall(function() APP.tick_timer:stop() end)
    pcall(function() APP.tick_timer:unregister() end)
    APP.tick_timer = nil
  end

  if lv_scr_act then
    clear_root()
  end
  release_fonts()
  release_game_over_snapshot()
end
