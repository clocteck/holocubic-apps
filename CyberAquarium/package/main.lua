-- SPDX-License-Identifier: GPL-3.0-only
local current = assert(app.current(), "Cyber Aquarium requires the Cubic app launcher")
local directory = assert(current.entry:match("^(.*)/[^/]+$"), "Cannot find app directory")
local Aquarium = dofile(directory .. "/aquarium.lua")
local tank = Aquarium.new()
local FRAME_MS = 33

local root = lv_scr_act()
lv_obj_clean(root)
lv_obj_set_style_bg_color(root, 0x000000, 0)
lv_obj_set_style_bg_opa(root, 255, 0)
lv_obj_clear_flag(root, LV_OBJ_FLAG_SCROLLABLE)

local canvas = assert(lv_canvas_create(root, 320, 240, LV_IMG_CF_TRUE_COLOR))
lv_obj_set_pos(canvas, 0, 0)
local font = assert(lv_font_load(directory .. "/aquarium-ascii.bin"))
local descriptors = {}
local function draw(x, y, text, color)
  local dsc = descriptors[color]
  if not dsc then
    dsc = { font_handle = font, color = color }
    descriptors[color] = dsc
  end
  x = math.floor(x + 0.5)
  lv_canvas_draw_text(canvas, x, math.floor(y + 0.5), 320 - x, text, dsc)
end

local function circle(x, y, radius, color)
  lv_canvas_draw_arc(canvas, math.floor(x + 0.5), math.floor(y + 0.5), radius, 0, 360, color, 255, 1)
end

local water = {"---", "---", "--~", "~~~", "~--", "---"}
local surface_group_width = Aquarium.glyph_width * 3
local surface_groups = math.floor((tank.right - tank.left) / surface_group_width)
local surface_start = (tank.left + tank.right - surface_groups * surface_group_width) / 2
local bubble_x = {65, 178, 274}
local bubble_radii = {3, 5, 4}
local kelp_roots = {{57, 35}, {159, 28}, {257, 32}}
local stem_style = {color = 0x56996A, width = 2}

local function kelp_blade(x, height, phase, direction)
  local y = tank.bottom - 2
  local bend = math.sin(tank.time * 1.8 + phase) * 4 + tank.flow_x * 3 + direction * 2
  local lower_x = math.floor(x + bend * 0.2 + 0.5)
  local upper_x = math.floor(x + bend * 0.55 + 0.5)
  local lower_y = y - math.floor(height * 0.36)
  local upper_y = y - math.floor(height * 0.67)
  local tip_x = math.floor(x + bend + 0.5)
  lv_canvas_draw_line(canvas, {x, y, lower_x, lower_y, upper_x, upper_y, tip_x, y - height}, 4, stem_style)
  lv_canvas_draw_line(canvas, lower_x, lower_y, lower_x - direction * 6, lower_y - 6, 0x427C56, 255, 2)
  lv_canvas_draw_line(canvas, upper_x, upper_y, upper_x + direction * 5, upper_y - 5, 0x75AC7D, 255, 2)
end

local function render()
  local now = tank.time
  lv_canvas_frame_begin(canvas)
  lv_canvas_fill_bg(canvas, 0x000000, 255)

  for i = 0, surface_groups - 1 do
    local x = surface_start + i * surface_group_width
    local sample_x = tank.left + (tank.right - tank.left) * i / (surface_groups - 1)
    local y = tank:surface(sample_x)
    local glyph = water[1 + (i + math.floor(now * 3)) % #water]
    draw(x, y - 8, glyph, 0x2ABFDE)
  end
  for i, origin in ipairs(bubble_x) do
    local radius = bubble_radii[i]
    local y = 213 - (now * (23 + i * 3) + i * 45) % 182
    local x = origin + math.sin(now * 1.8 + i + y * 0.06) * 5
    x = x - tank.flow_x * (213 - y) * 0.18
    if x >= 15 and x <= 299 and y > tank:surface(x) + radius + 2 then
      circle(x, y, radius, 0x469CFF)
    end
  end

  for i, root in ipairs(kelp_roots) do
    local x, height = root[1], root[2]
    kelp_blade(x - 4, height, i * 1.3, -1)
    kelp_blade(x + 4, height - 9, i * 1.3 + 0.9, 1)
  end

  for _, fish in ipairs(tank.fish) do
    local kind = fish.species
    local frames = fish.facing > 0 and kind.right or kind.left
    local frame = frames[1 + math.floor(now * 5 + fish.phase) % #frames]
    for row, text in ipairs(frame) do
      local y = fish.y - kind.half_height + (row - 1) * Aquarium.fish_row_height
      draw(fish.x - kind.half_width, y, text, fish.color)
    end
    if fish.spark > now then
      local x = fish.x + fish.facing * kind.half_width - 3
      draw(x, fish.y - 15, "*", 0xFFECA2)
    end
  end
  for _, pellet in ipairs(tank.food) do
    circle(pellet.x, pellet.y, pellet.radius, 0xFFDC40)
  end

  lv_canvas_frame_end(canvas)
end

local timer
local function stop()
  if timer then
    timer:unregister()
    timer = nil
  end
  app.on("imu", nil)
  lv_obj_del(canvas)
  lv_font_free(font)
end

local last_ms = millis()
local function tick()
  if app.exiting() then
    stop()
    return
  end
  local now_ms = millis()
  local dt = math.min(math.max((now_ms - last_ms) / 1000, 0), 0.16)
  last_ms = now_ms
  local now = tank.time + dt
  if imu and imu.raw then
    local ax, ay, az, _, _, _, _, seq = imu.raw()
    tank:sample(ax, ay, az, seq, now)
  end
  tank:step(now, dt)
  render()
end

render()
app.on("imu", function(_, roll, pitch)
  tank:orient(roll, pitch)
end)
timer = tmr.create()
timer:alarm(FRAME_MS, tmr.ALARM_AUTO, function()
  local ok, err = pcall(tick)
  if not ok then
    print("Cyber Aquarium: " .. tostring(err))
    pcall(stop)
    app.exit()
  end
end)
