-- Shared persistent state. No package directory owns a device identity.
local M = { PATH = "/sd/data/xiaozhi/config.json", VERSION = 2 }
local function codec() return rawget(_G, "json") or rawget(_G, "sjson") end
function M.read(path)
  local ok, raw = pcall(file.getcontents, path or M.PATH)
  if not ok or type(raw) ~= "string" or raw == "" then return nil end
  local good, doc = pcall(codec().decode, raw)
  if good and type(doc) == "table" then return doc end
  return nil
end
local function exists(path)
  if file.exists then return file.exists(path) end
  return M.read(path) ~= nil
end
function M.save(doc)
  for _, p in ipairs({ "/sd/data", "/sd/data/xiaozhi" }) do
    if file.mkdir then pcall(file.mkdir, p) end
  end
  local ok, raw = pcall(codec().encode, doc)
  if not ok then return false, "config_encode_failed" end
  local tmp, backup = M.PATH .. ".tmp", M.PATH .. ".bak"
  local wrote, result = pcall(file.putcontents, tmp, raw)
  if not wrote or not result or not M.read(tmp) then return false, "config_write_failed" end
  if not file.rename then return false, "atomic_rename_unavailable" end
  if exists(M.PATH) then
    if exists(backup) then file.remove(backup) end
    local moved, ret = pcall(file.rename, M.PATH, backup)
    if not moved or ret == false or ret == nil then return false, "config_backup_failed" end
  end
  local moved, ret = pcall(file.rename, tmp, M.PATH)
  if not moved or ret == false or ret == nil then
    if exists(backup) then pcall(file.rename, backup, M.PATH) end
    return false, "config_commit_failed"
  end
  return true
end
function M.update(fn)
  local doc = M.read()
  if not doc then return false, "config_unavailable" end
  local ok, err = fn(doc)
  if ok == false then return false, err end
  doc.revision = (tonumber(doc.revision) or 0) + 1
  return M.save(doc)
end
function M.normalize_mac(value)
  local hex = tostring(value or ""):lower():gsub("[:-]", "")
  if #hex ~= 12 or not hex:match("^[0-9a-f]+$") or hex == "000000000000" or hex == "ffffffffffff" then return nil end
  if tonumber(hex:sub(1, 2), 16) % 2 ~= 0 then return nil end
  return hex:gsub("(..)", "%1:"):sub(1, -2)
end
local function hardware_mac()
  for _, fn in ipairs({ wifi and wifi.sta and wifi.sta.getmac or false, sys and sys.mac or false }) do
    if fn then local ok, mac = pcall(fn); if ok and M.normalize_mac(mac) then return M.normalize_mac(mac) end end
  end
end
function M.ensure()
  local doc = M.read()
  if doc then return doc end
  doc = M.read(M.PATH .. ".bak")
  if doc then assert(M.save(doc)); return doc end
  -- Never replace a corrupt shared configuration with a fresh identity.
  if exists(M.PATH) then error("shared_config_corrupt") end
  local service = M.read("/sd/apps/xiaozhi-service/config.json")
  local front = M.read("/sd/apps/xiaozhi/config.json")
  local function connected(v) return v and v.websocket and type(v.websocket.url) == "string" and v.websocket.url ~= "" end
  doc = connected(service) and service or (connected(front) and front or service or front or {})
  doc.schema_version = M.VERSION
  doc.ui = doc.ui or { type = "subtitle" }
  doc.language = doc.language or "auto"
  doc.wake = doc.wake or { id = "nihaoxiaozhi" }
  doc.audio = doc.audio or { sample_rate = 16000, channels = 1, frame_duration = 60, bitrate = 12000 }
  local legacy = M.read("/sd/xiaozhi-service/device_mac.json")
  -- Old releases preferred the hardware MAC; preserve the identity actually used.
  local mac = hardware_mac() or (legacy and M.normalize_mac(legacy.mac))
  doc.identity = doc.identity or { mac = mac, name = "Migrated device", virtual = false }
  doc.identities = doc.identities or {}
  if front and service and front ~= doc and connected(front) then
    doc.legacy_foreground = front -- preserved, never silently merges different tokens
  end
  local ok, err = M.save(doc)
  if not ok then error(err) end
  return doc
end
function M.device_id()
  local doc = M.ensure()
  local mac = M.normalize_mac(doc.identity and doc.identity.mac)
  if mac then return mac end
  -- A first boot may run before the hardware identity API becomes ready.
  mac = hardware_mac()
  if mac then
    local ok = M.update(function(saved)
      saved.identity = saved.identity or { name = "Migrated device", virtual = false }
      saved.identity.mac = mac
    end)
    if ok then return mac end
  end
  return nil
end
function M.client_id(mac)
  mac = M.normalize_mac(mac or M.device_id())
  return mac and ("00000000-0000-4000-8000-" .. mac:gsub(":", "")) or nil
end
local function archive(doc)
  doc.identities = doc.identities or {}
  if doc.identity and doc.identity.mac then
    doc.identities[doc.identity.mac] = { identity = doc.identity, websocket = doc.websocket, ota = doc.ota }
  end
end
function M.identity_action(action, value)
  return M.update(function(doc)
    local mac = M.normalize_mac(value)
    if action == "create" then
      doc.identity_sequence = (tonumber(doc.identity_sequence) or 0) + 1
      local base = (hardware_mac() or "02:00:00:00:00:01"):gsub(":", "")
      local seed = (tonumber(base:sub(-8), 16) + doc.identity_sequence * 104729 + (millis and millis() or 0)) % 4294967296
      repeat
        seed = (seed * 1664525 + 1013904223) % 4294967296
        mac = "02:" .. base:sub(3, 4) .. ":" .. string.format("%08x", seed):gsub("(..)", "%1:"):sub(1, -2)
      until mac ~= (doc.identity and doc.identity.mac) and not (doc.identities or {})[mac]
    elseif action == "rename" then
      if not doc.identity then return false, "identity_missing" end
      local name = tostring(value or ""):sub(1, 64)
      if name == "" then return false, "name_required" end
      doc.identity.name = name
      return true
    elseif action == "delete" then
      if not mac or mac == (doc.identity and doc.identity.mac) then return false, "cannot_delete_active_identity" end
      if doc.identities then doc.identities[mac] = nil end
      return true
    elseif action ~= "select" and action ~= "set" then return false, "bad_identity_action" end
    if not mac then return false, "invalid_mac" end
    if mac == (doc.identity and doc.identity.mac) then return true end
    local saved = (doc.identities or {})[mac]
    if action == "select" and not saved then return false, "identity_missing" end
    archive(doc)
    if saved then
      doc.identity, doc.websocket, doc.ota = saved.identity, saved.websocket, saved.ota
    else
      doc.identity = { mac = mac, name = "Device " .. tostring(doc.identity_sequence or mac), virtual = true }
      doc.websocket = { url = "", token = "", version = 1 }
      doc.ota = doc.ota or { url = "https://api.tenclass.net/xiaozhi/ota/" }
      doc.ota.enabled, doc.ota.force = true, false
    end
  end)
end
function M.public_identities()
  local doc = M.ensure()
  local out, seen = {}, {}
  local function add(v, active)
    if v and v.mac and not seen[v.mac] then
      out[#out + 1] = { mac = v.mac, name = v.name or v.mac, active = active, virtual = v.virtual == true }
      seen[v.mac] = true
    end
  end
  add(doc.identity, true)
  for _, profile in pairs(doc.identities or {}) do add(profile.identity, false) end
  return out
end
return M
