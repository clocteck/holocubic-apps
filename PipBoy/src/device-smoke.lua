-- Run through DevTools /api/code/run only; not part of the installed app entry.
-- Reads real data, saves a screenshot, and then launches the installed PipBoy app.
local path = "/sd/apps/PipBoy/smoke-result.json"
local codec = json or sjson
local function save(result) file.putcontents(path, codec.encode(result)) end
local ok, err = pcall(dofile, "/sd/apps/PipBoy/main.lua")
if not ok then save({ok=false,stage="startup",error=tostring(err)}); return end
save({ok=true,stage="waiting-for-weather"})
local probe = tmr.create()
local attempts = 0
probe:alarm(5000, tmr.ALARM_AUTO, function()
  attempts = attempts + 1
  local a = rawget(_G, "PIP_BOY_APP")
  if not a or not a.running then
    save({ok=false,stage="runtime",error="PipBoy stopped"})
    probe:unregister()
    return
  end
  if not a.data.state.valid and attempts < 7 then return end
  probe:unregister()
  local result = {
    ok=true, stage="complete", weather_valid=a.data.state.valid,
    weather_status=a.data.state.weather_status, temperature=a.data:temperature_text(),
    humidity=a.data.state.humidity, brightness=a.data:brightness(),
    clock=a.data:local_time(), labels=a.values,
  }
  local shot_ok, shot_err = pcall(function()
    local snapshot = assert(lv_snapshot_take(a.root))
    local saved, reason = lv_snapshot_save_to_png(snapshot, "/sd/apps/PipBoy/device-preview.png")
    lv_snapshot_free(snapshot)
    assert(saved, reason)
  end)
  result.screenshot_ok, result.screenshot_error = shot_ok, not shot_ok and tostring(shot_err) or nil
  save(result)
  app.rescan()
  app.launch("PipBoy")
end)
