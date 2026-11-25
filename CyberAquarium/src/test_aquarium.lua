-- SPDX-License-Identifier: GPL-3.0-only
-- Run from the repository root: lua CyberAquarium/src/test_aquarium.lua
local aquarium = dofile("CyberAquarium/package/aquarium.lua")
math.randomseed(42)

assert(math.abs((aquarium.bottom - aquarium.waterline) / (aquarium.bottom - aquarium.top) - 0.9) < 0.001)
local flat = aquarium.new()
for i = 1, 24 do
  flat:orient(0, 0)
  flat:step(i * 0.06, 0.06)
end
assert(math.abs(flat:surface(flat.right) - flat:surface(flat.left)) < 0.1,
  "zero reported tilt did not produce a level waterline")
for i = 25, 44 do
  flat:orient(0, 6)
  flat:step(i * 0.06, 0.06)
end
assert(flat:surface(flat.right) - flat:surface(flat.left) > 3,
  "gentle reported tilt was suppressed")
for i = 45, 77 do
  flat:orient(0, 0)
  flat:step(i * 0.06, 0.06)
end
assert(math.abs(flat:surface(flat.right) - flat:surface(flat.left)) < 0.1,
  "water did not settle level after returning to rest")

local idle = aquarium.new()
assert(#idle.fish == 5, "the tank should have two large fish and three small fish")
local large = 0
for _, fish in ipairs(idle.fish) do
  local rows = #fish.species.right[1]
  assert(rows == 1 or rows == 3)
  if rows == 3 then large = large + 1 end
end
assert(large == 2)
assert(idle.fish[1].species == idle.fish[2].species, "large fish should use one design")
local extreme = aquarium.new()
for i = 1, 24 do
  extreme:orient(0, -55)
  extreme:step(i * 0.06, 0.06)
end
local extreme_delta = extreme:surface(extreme.left) - extreme:surface(extreme.right)
assert(math.abs(extreme_delta - 55) < 0.02, "the full waterline tilt should span 55 px")
extreme.slosh = 11
for x = extreme.left, extreme.right do
  assert(extreme:surface(x) >= 1, "strong shake should keep waterline on screen")
end
local right = aquarium.new()
local left = aquarium.new()
for i=1, 12 do
  local t=i*0.06
  idle:step(t, 0.06)
  right:orient(0, -25)
  left:orient(0, 25)
  right:step(t, 0.06)
  left:step(t, 0.06)
end
assert(right:surface(306) - right:surface(14) < -25, "water should rise on screen toward the lowered right edge")
assert(left:surface(306) - left:surface(14) > 25, "water should rise on screen toward the lowered left edge")
assert(math.abs((right:surface(306)+right:surface(14))*0.5 - aquarium.waterline) < 2)
assert(math.abs((left:surface(306)+left:surface(14))*0.5 - aquarium.waterline) < 2)
assert(right.fish[1].x > idle.fish[1].x and idle.fish[1].x > left.fish[1].x)
local vertical = aquarium.new()
for i=1, 12 do
  vertical:orient(20, 0)
  vertical:step(i*0.06, 0.06)
end
assert(vertical.fish[1].y < idle.fish[1].y)
assert(math.abs((vertical:surface(306)+vertical:surface(14))*0.5 - aquarium.waterline) < 3)
assert(#right.food == 0 and #left.food == 0)
local automatic = aquarium.new()
local scheduled = automatic.next_feed
assert(scheduled >= 30 and scheduled <= 60)
automatic:step(scheduled - 0.06, 0.06)
assert(#automatic.food == 0)
automatic:step(scheduled, 0.06)
assert(#automatic.food >= 2 and #automatic.food <= 5, "timed feeding did not drop a random portion")
assert(automatic.next_feed - scheduled >= 30 and automatic.next_feed - scheduled <= 60)
local amounts = {}
for i = 1, 20 do
  automatic:feed(i * 60)
  amounts[#automatic.food] = true
end
assert(next(amounts, next(amounts)) ~= nil, "every feed had the same portion")

local tank = aquarium.new()
local seq = 0
local function raw(x, y, z, time)
  seq = seq + 1
  tank:sample(x, y, z, seq, time)
end
for i=1, 12 do
  raw(i*120, 0, math.floor(math.sqrt(4096^2 - (i*120)^2)), i*0.06)
  tank:step(i*0.06, 0.06)
end
assert(#tank.food == 0, "slow tilt spawned food")
raw(5200, 0, 4200, 0.82)
tank:sample(-5200, 0, 4200, seq, 0.88)
assert(#tank.food == 0, "duplicate sample counted twice")
raw(-5200, 0, 4200, 0.94)
local portion = #tank.food
assert(portion >= 2 and portion <= 5, "shake did not drop one portion")
assert(tank.slosh >= 10, "shake should make a prominent wave")
raw(5200, 0, 4200, 1)
raw(-5200, 0, 4200, 1.06)
assert(#tank.food == portion and tank.fed_at == 0.94, "cooldown dropped another portion")
local fish = tank.fish[1]
local pellet = tank.food[1]
pellet.x, pellet.y = fish.x, fish.y
tank:step(1.12, 0.06)
assert(#tank.food < portion and fish.spark > 1.12, "fish did not eat overlapping food")
for i=20, 230 do
  local time = i*0.06
  tank:orient(math.sin(time)*25, math.cos(time)*35)
  tank:step(time, 0.06)
  for _, fish in ipairs(tank.fish) do
    assert(fish.x >= 14+fish.species.half_width and fish.x <= 306-fish.species.half_width)
    assert(fish.y-fish.species.half_height > tank:surface(fish.x))
  end
end
assert(#tank.food == 0, "food did not expire")
raw(5200, 0, 4200, 14.12)
raw(-5200, 0, 4200, 14.18)
raw(5200, 0, 4200, 14.24)
assert(#tank.food >= 2 and #tank.food <= 5, "new shake after cooldown did not drop food")
print("PASS: 90% waterline, level and tilt direction, fish sizes, random timed feeding, shake, cooldown, eating and bounds")
