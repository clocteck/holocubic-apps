-- Shared display preference. Sensor/weather values stay Celsius internally.
local M = {}
local unit, checked = "C", nil
function M.unit()
  local now = tmr and tmr.now and tmr.now() / 1000000 or (os and os.time and os.time() or 0)
  if checked and now >= checked and now - checked < 3 then return unit end
  checked = now
  local ok, doc = pcall(function()
    local raw
    if file and file.getcontents then raw = file.getcontents("/sd/apps/settings.json") end
    if not raw and file and file.open then
      local f = file.open("/sd/apps/settings.json", "r")
      if f then local parts = {}; while true do local part = f:read(512); if not part or part == "" then break end; parts[#parts+1] = part end; f:close(); raw = table.concat(parts) end
    end
    local codec = rawget(_G, "sjson") or rawget(_G, "json")
    if raw and codec and codec.decode then return codec.decode(raw) end
  end)
  if ok and type(doc) == "table" then unit = doc.temperature_unit == "F" and "F" or "C" end
  return unit
end
function M.value(celsius)
  local n = tonumber(celsius)
  if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
  return M.unit() == "F" and n * 9 / 5 + 32 or n
end
function M.round(n)
  if n == nil then return "--" end
  return tostring(n < 0 and -math.floor(-n + 0.5) or math.floor(n + 0.5))
end
function M.symbol() return "°" .. M.unit() end
function M.text(celsius) return M.round(M.value(celsius)) .. M.symbol() end
function M.to_celsius(value, source_unit)
  local n = tonumber(value); if not n then return nil end
  return (source_unit == "F" or source_unit == "°F" or source_unit == "℉") and (n - 32) * 5 / 9 or n
end
return M
