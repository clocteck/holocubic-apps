local M = {}

M.UNKNOWN = "unknown"
M.STARTING = "starting"
M.WIFI_CONFIGURING = "wifi_configuring"
M.IDLE = "idle"
M.CONNECTING = "connecting"
M.LISTENING = "listening"
M.SPEAKING = "speaking"
M.UPGRADING = "upgrading"
M.ACTIVATING = "activating"
M.AUDIO_TESTING = "audio_testing"
M.FATAL_ERROR = "fatal_error"

M.LISTEN_AUTO = "auto"
M.LISTEN_MANUAL = "manual"
M.LISTEN_REALTIME = "realtime"

local allowed = {
  [M.UNKNOWN] = { [M.STARTING] = true },
  [M.STARTING] = { [M.WIFI_CONFIGURING] = true, [M.ACTIVATING] = true },
  [M.WIFI_CONFIGURING] = { [M.ACTIVATING] = true, [M.AUDIO_TESTING] = true },
  [M.AUDIO_TESTING] = { [M.WIFI_CONFIGURING] = true },
  [M.ACTIVATING] = { [M.UPGRADING] = true, [M.IDLE] = true, [M.WIFI_CONFIGURING] = true },
  [M.UPGRADING] = { [M.IDLE] = true, [M.ACTIVATING] = true },
  [M.IDLE] = {
    [M.CONNECTING] = true,
    [M.LISTENING] = true,
    [M.SPEAKING] = true,
    [M.ACTIVATING] = true,
    [M.UPGRADING] = true,
    [M.WIFI_CONFIGURING] = true,
  },
  [M.CONNECTING] = { [M.IDLE] = true, [M.LISTENING] = true },
  [M.LISTENING] = { [M.SPEAKING] = true, [M.IDLE] = true },
  [M.SPEAKING] = { [M.LISTENING] = true, [M.IDLE] = true },
  [M.FATAL_ERROR] = {},
}

function M.new()
  local self = {
    state = M.UNKNOWN,
    listeners = {},
  }

  function self:can(to)
    if to == M.FATAL_ERROR then
      return self.state ~= M.FATAL_ERROR
    end
    if self.state == to then
      return true
    end
    local list = allowed[self.state]
    return list and list[to] == true
  end

  function self:on_change(fn)
    self.listeners[#self.listeners + 1] = fn
  end

  function self:set(to)
    local from = self.state
    if from == to then
      return true
    end
    if not self:can(to) then
      print("[xiaozhi] invalid state", tostring(from), "->", tostring(to))
      return false
    end
    self.state = to
    for _, fn in ipairs(self.listeners) do
      pcall(fn, from, to)
    end
    return true
  end

  return self
end

return M
