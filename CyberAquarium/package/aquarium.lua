-- SPDX-License-Identifier: GPL-3.0-only
local Aquarium = {}
Aquarium.__index = Aquarium

Aquarium.left, Aquarium.right = 14, 306
Aquarium.top, Aquarium.bottom = 10, 224
Aquarium.waterline = Aquarium.bottom - (Aquarium.bottom - Aquarium.top) * 0.9
Aquarium.glyph_width = 8
Aquarium.fish_row_height = 12

local abs, sin, cos, sqrt = math.abs, math.sin, math.cos, math.sqrt
local tau = 2 * math.pi
local center = (Aquarium.left + Aquarium.right) / 2
local opposite = { ["<"] = ">", [">"] = "<", ["("] = ")", [")"] = "(",
  ["/"] = "\\", ["\\"] = "/" }

local function clamp(value, low, high)
  return math.min(math.max(value, low), high)
end

local function smooth(value, target, rate, dt)
  return value + (target - value) * math.min(rate * dt, 1)
end

local function axis(angle, limit)
  angle = (angle + 180) % 360 - 180
  local magnitude = clamp((abs(angle) - 2) / (limit - 2), 0, 1)
  return angle < 0 and -magnitude or magnitude
end

local function mirror(text)
  return text:reverse():gsub(".", function(c) return opposite[c] or c end)
end

local function species(color, frames)
  local left_frames = {}
  local width = #frames[1][1]
  for i, frame in ipairs(frames) do
    left_frames[i] = {}
    for row, text in ipairs(frame) do
      assert(#text == width)
      left_frames[i][row] = mirror(text)
    end
  end
  return {
    color = color, right = frames, left = left_frames,
    half_width = width * Aquarium.glyph_width / 2,
    half_height = 6.5 + (#frames[1] - 1) * Aquarium.fish_row_height / 2
  }
end

local jade = species(0x82F2D9, {
  { [[   /^^\   ]], [[><(::o )> ]], [[   \__/   ]] },
  { [[   /^^\   ]], [[>:(::o )> ]], [[   \__/   ]] }
})
local silver = species(0xBAD8E4, { {"><-o>"}, {">:-o>"} })
local ice = species(0x86C7E8, { {"><:o>"}, {">.:o>"} })
local fish_layout = {
  {jade, 77, 96, 1, 17}, {jade, 234, 154, -1, 13},
  {silver, 229, 62, -1, 23}, {ice, 149, 116, 1, 20},
  {silver, 97, 188, 1, 18}
}

function Aquarium.new()
  local fish = {}
  for i, entry in ipairs(fish_layout) do
    local kind, x, y, direction, speed = table.unpack(entry)
    fish[i] = {
      species = kind, x = x, y = y, direction = direction, facing = direction,
      vx = speed * direction, vy = 0, speed = speed, depth = y,
      phase = i * 1.63, spark = 0
    }
  end
  return setmetatable({
    fish = fish, food = {}, time = 0, target_x = 0, target_y = 0,
    flow_x = 0, flow_y = 0, wave = 0, slosh = 0,
    impulse_time = -1, fed_at = -10, next_feed = math.random(30, 60)
  }, Aquarium)
end

function Aquarium:orient(roll, pitch)
  if type(roll) ~= "number" or type(pitch) ~= "number" or
     roll ~= roll or pitch ~= pitch then
    return
  end
  self.target_x = -axis(pitch, 36)
  self.target_y = -axis(roll, 32)
end

function Aquarium:surface(x)
  local fraction = (x - self.left) / (self.right - self.left)
  local tilt = self.flow_x * 27.5
  local wave_room = self.waterline - abs(tilt) - 2.5
  local motion = clamp(self.wave + self.slosh, -wave_room, wave_room)
  local ripple = sin(fraction * tau * 2 - self.time * 2.8) * 1.5
  local swell = sin(fraction * tau + self.time * 4.2) * motion
  -- The surface is perpendicular to gravity. Fish drift with gravity.
  return self.waterline - (fraction * 2 - 1) * tilt + ripple + swell
end

function Aquarium:feed(now)
  self.fed_at = now
  self.next_feed = now + math.random(30, 60)
  local offset = math.random(-28, 28)
  local count = math.random(2, 5)
  self.food = {}
  for i = 1, count do
    local x = center + offset + (i - (count + 1) / 2) * 16 + math.random(-6, 6)
    self.food[i] = {
      x = x, y = self:surface(x) + 6 + i % 3, age = 0,
      speed = 15 + math.random(0, 9), phase = i * 1.78
    }
  end
end

function Aquarium:sample(ax, ay, az, seq, now)
  if type(ax) ~= "number" or type(ay) ~= "number" or type(az) ~= "number" or
     seq == nil or seq == self.last_seq then
    return
  end
  ax, ay, az = ax / 4096, ay / 4096, az / 4096
  local last = self.last_accel
  self.last_seq = seq
  self.last_accel = {ax, ay, az}
  if not last or now - self.fed_at < 2.5 then return end

  -- A slow turn preserves |a|. Look for two short acceleration impulses.
  local dx, dy, dz = ax - last[1], ay - last[2], az - last[3]
  local delta = sqrt(dx * dx + dy * dy + dz * dz)
  local force = sqrt(ax * ax + ay * ay + az * az)
  if delta < 0.52 or abs(force - 1) < 0.23 then return end
  if self.impulse_time >= 0 and now - self.impulse_time <= 0.36 then
    self.impulse_time = -1
    self.slosh = 11
    self:feed(now)
  else
    self.impulse_time = now
  end
end

local function nearest_food(food, fish)
  local closest, best = nil, math.huge
  for _, pellet in ipairs(food) do
    local dx, dy = pellet.x - fish.x, pellet.y - fish.y
    local distance = dx * dx + dy * dy
    if distance < best then
      closest, best = pellet, distance
    end
  end
  return closest
end

function Aquarium:step(now, dt)
  self.time = now
  local change_x = self.target_x - self.flow_x
  self.flow_x = smooth(self.flow_x, self.target_x, 5, dt)
  self.flow_y = smooth(self.flow_y, self.target_y, 4, dt)
  self.wave = smooth(self.wave, 5 * self.flow_y + 7 * change_x, 4, dt)
  self.slosh = smooth(self.slosh, 0, 1.5, dt)
  if now >= self.next_feed then self:feed(now) end

  for i = #self.food, 1, -1 do
    local pellet = self.food[i]
    pellet.age = pellet.age + dt
    pellet.x = clamp(pellet.x + dt * (self.flow_x * 22 + sin(now * 4 + pellet.phase) * 6),
      self.left + 5, self.right - 5)
    pellet.y = clamp(pellet.y + dt * (pellet.speed + self.flow_y * 9),
      self:surface(pellet.x) + 5, self.bottom - 5)
    if pellet.age >= 11 then table.remove(self.food, i) end
  end

  for _, fish in ipairs(self.fish) do
    local kind = fish.species
    local left, right = self.left + kind.half_width, self.right - kind.half_width
    local pellet = nearest_food(self.food, fish)
    local vx = fish.direction * fish.speed + self.flow_x * 22
    local depth = fish.depth + sin(now * 0.85 + fish.phase) * 10
    local vy = (depth - fish.y) * 1.15 + self.flow_y * 40
    if pellet then
      vx = clamp((pellet.x - fish.x) * 2.7, -56, 56) + self.flow_x * 9
      vy = clamp((pellet.y - fish.y) * 2.5, -48, 48) + self.flow_y * 8
    elseif fish.x <= left + 1 or fish.x >= right - 1 then
      fish.direction = fish.x <= left + 1 and 1 or -1
      -- Ensure an inward turn even for small fish in a strong current.
      vx = fish.direction * (fish.speed + 5)
    end
    fish.vx = smooth(fish.vx, vx, 5.5, dt)
    fish.vy = smooth(fish.vy, vy, 4, dt)
    if abs(fish.vx) > 4 then fish.facing = fish.vx > 0 and 1 or -1 end
    fish.x = clamp(fish.x + fish.vx * dt, left, right)
    local top = math.max(self:surface(fish.x - kind.half_width), self:surface(fish.x),
      self:surface(fish.x + kind.half_width))
    fish.y = clamp(fish.y + fish.vy * dt, top + kind.half_height + 4,
      self.bottom - kind.half_height - 2)

    if pellet and abs(pellet.x - fish.x) < kind.half_width * 0.65 + 3 and
       abs(pellet.y - fish.y) < kind.half_height * 0.45 + 4 then
      for index, candidate in ipairs(self.food) do
        if candidate == pellet then
          table.remove(self.food, index)
          break
        end
      end
      fish.spark = now + 0.32
    end
  end
end

return Aquarium
