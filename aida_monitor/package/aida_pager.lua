local Pager = {}
Pager.__index = Pager

local function clamp_page(page, count)
  count = math.max(1, math.floor(tonumber(count) or 1))
  page = math.floor(tonumber(page) or 1)
  if page < 1 then return 1 end
  if page > count then return count end
  return page
end

function Pager.new(config)
  config = config or {}
  return setmetatable({
    config = config,
    last_switch_ms = -(tonumber(config.tilt_page_cooldown_ms) or 1000),
    requested_page = 1,
    local_override = false,
  }, Pager)
end

function Pager:cooldown_ms()
  return math.max(250, math.floor(tonumber(self.config.tilt_page_cooldown_ms) or 1000))
end

function Pager:step(current_page, page_count, direction, now_ms)
  page_count = math.max(1, math.floor(tonumber(page_count) or 1))
  if page_count < 2 then return clamp_page(current_page, page_count), false end
  now_ms = math.floor(tonumber(now_ms) or 0)
  if now_ms - self.last_switch_ms < self:cooldown_ms() then
    return clamp_page(current_page, page_count), false
  end
  direction = tonumber(direction) or 0
  if direction == 0 then return clamp_page(current_page, page_count), false end
  local page = clamp_page(current_page, page_count)
  page = ((page - 1 + (direction < 0 and -1 or 1)) % page_count) + 1
  self.last_switch_ms = now_ms
  self.requested_page = page
  self.local_override = true
  return page, true
end

function Pager:accept_remote(page, page_count)
  if page == nil then return nil end
  if self.local_override then return nil end
  self.requested_page = clamp_page(page, page_count)
  return self.requested_page
end

function Pager:restore(page_count)
  if not self.local_override then return nil end
  self.requested_page = clamp_page(self.requested_page, page_count)
  return self.requested_page
end

function Pager:snapshot()
  return {
    source = self.local_override and "tilt" or "remote",
    requested_page = self.requested_page,
    cooldown_ms = self:cooldown_ms(),
  }
end

return Pager
