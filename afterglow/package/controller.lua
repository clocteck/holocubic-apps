-- Launcher-compatible BLE pad input: edge-triggered, 40ms polling.
local M = {}
function M.start(app_state, switch, exit)
  if not controller or not controller.state or not tmr or not tmr.create then return end
  local previous, primed, cooldown = 0, false, 0
  local timer = tmr.create()
  app_state.timers.controller = timer
  timer:alarm(40, tmr.ALARM_AUTO, function()
    if not app_state.running then return end
    cooldown = math.max(0, cooldown - 40)
    local ok, pad = pcall(controller.state, "ble-main")
    if not ok or type(pad) ~= "table" or pad.connected == false then
      previous, primed = 0, false
      return
    end
    local buttons = math.floor(tonumber(pad.buttons) or 0)
    -- Ignore buttons held while launching/reconnecting until a new press.
    if not primed then previous, primed = buttons, true; return end
    local pressed = buttons & (~previous)
    previous = buttons
    if (pressed & (4096 | 32768)) ~= 0 then exit(); return end
    if cooldown > 0 then return end
    local delta
    if (pressed & (4 | 1)) ~= 0 then delta = -1
    elseif (pressed & (8 | 2 | 16 | 8192)) ~= 0 then delta = 1 end
    if delta then switch(delta); cooldown = 390 end
  end)
end
return M
