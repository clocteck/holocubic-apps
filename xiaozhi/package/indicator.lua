local M = {}

-- The device status LED has red/blue channels swapped at the board mapping.
-- This calibrated value is physically orange on the target hardware.
local ORANGE = { 0, 165, 239 }

function M.new()
  local self = {
    original = nil,
    unavailable_reported = false,
  }

  local function report_unavailable()
    if self.unavailable_reported then return end
    self.unavailable_reported = true
    print("[xiaozhi] ERROR: RGB LED API unavailable; session indicator disabled")
  end

  function self:restore()
    local color = self.original
    if not color then return true end
    if not sys or type(sys.setled) ~= "function" then
      report_unavailable()
      return false
    end
    local ok, result, err = pcall(sys.setled, color[1], color[2], color[3])
    if not ok or result == nil or result == false then
      print("[xiaozhi] ERROR: RGB LED restore failed: " .. tostring(err or result or "unknown error"))
      return false
    end
    self.original = nil
    return true
  end

  function self:set_active(active)
    if not active then return self:restore() end
    if self.original then return true end
    if not sys or type(sys.getled) ~= "function" or type(sys.setled) ~= "function" then
      report_unavailable()
      return false
    end

    local ok_get, red, green, blue = pcall(sys.getled)
    if not ok_get or type(red) ~= "number" or type(green) ~= "number" or type(blue) ~= "number" then
      print("[xiaozhi] ERROR: RGB LED color read failed; session indicator disabled")
      return false
    end

    local ok_set, result, err = pcall(sys.setled, ORANGE[1], ORANGE[2], ORANGE[3])
    if not ok_set or result == nil or result == false then
      print("[xiaozhi] ERROR: RGB LED orange set failed: " .. tostring(err or result or "unknown error"))
      return false
    end
    self.original = { math.floor(red), math.floor(green), math.floor(blue) }
    return true
  end

  function self:on_state(state)
    return self:set_active(state == "connecting" or state == "listening" or state == "speaking")
  end

  return self
end

return M
