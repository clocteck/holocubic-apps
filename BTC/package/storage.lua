-- Small JSON documents only. Keep the last valid copy across interrupted writes.
local Storage = {}
local JSON = rawget(_G, "sjson") or rawget(_G, "json")
function Storage.read(path, validate)
  for _, candidate in ipairs({path, path .. ".bak"}) do
    local ok, raw = pcall(file.getcontents, candidate)
    if ok and type(raw) == "string" then
      local decoded, value = pcall(JSON.decode, raw)
      if decoded and type(value) == "table" and (not validate or validate(value)) then
        return value, candidate ~= path
      end
    end
  end
  return nil
end
function Storage.write(path, value)
  local ok, result = pcall(function()
    local raw = JSON.encode(value)
    local temp, backup = path .. ".tmp", path .. ".bak"
    if not file.putcontents(temp, raw) then error("SD write failed") end
    if file.getcontents(temp) ~= raw then error("SD verification failed") end
    -- Only replace the backup when the live file is valid JSON.
    local old = file.getcontents(path)
    local valid = old and pcall(JSON.decode, old)
    if valid then
      if file.exists(backup) then file.remove(backup) end
      if not file.rename(path, backup) then error("SD backup failed") end
    elseif file.exists(path) then
      file.remove(path)
    end
    if not file.rename(temp, path) then error("SD commit failed") end
    return true
  end)
  if not ok then return false, tostring(result) end
  return result
end
return Storage
