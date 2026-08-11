local REQUIRED_FIRMWARE = "1.102"

local function version_parts(value)
  local parts = {}
  for part in tostring(value or ""):gmatch("%d+") do
    parts[#parts + 1] = tonumber(part) or 0
  end
  return parts
end

local function version_at_least(current, required)
  local have = version_parts(current)
  local need = version_parts(required)
  if #have == 0 then return false end
  local count = math.max(#have, #need)
  for i = 1, count do
    local left = have[i] or 0
    local right = need[i] or 0
    if left ~= right then return left > right end
  end
  return true
end

local firmware_version = ""
if sys and type(sys.version) == "function" then
  local ok, value = pcall(sys.version)
  if ok and type(value) == "string" then firmware_version = value end
end

if not version_at_least(firmware_version, REQUIRED_FIRMWARE) then
  print("[xiaozhi-service] ERROR: firmware " .. REQUIRED_FIRMWARE
    .. " or newer is required; current=" .. (firmware_version ~= "" and firmware_version or "unknown")
    .. "; service startup aborted before loading Lua modules or native modules")
  return
end

local previous = rawget(_G, "XIAOZHI_SERVICE_APP")
if not previous then
  local legacy = rawget(_G, "XIAOZHI_APP")
  if legacy and legacy.cfg and legacy.cfg.SERVICE_MODE == true then
    previous = legacy
    _G.XIAOZHI_APP = nil
  end
end
if previous and previous.stop then
  pcall(function()
    previous.stop("reload")
  end)
end

local APP_DIR = "/sd/apps/xiaozhi-service"
XIAOZHI_UI_APP_DIR = APP_DIR
XIAOZHI_SERVICE_DIR = APP_DIR

local function path_exists(path)
  if file and file.exists then
    local ok, exists = pcall(function() return file.exists(path) end)
    if ok then return exists == true end
  end
  if file and file.stat then
    local ok, stat = pcall(function() return file.stat(path) end)
    if ok then return stat ~= nil and stat ~= false end
  end
  return false
end

local function ensure_native_wake_model()
  local source_dir = APP_DIR .. "/wake/wn9s_nihaoxiaozhi"
  local target_dir = "/sd/apps/xiaozhi/wake/wn9s_nihaoxiaozhi"
  local names = { "_MODEL_INFO_", "wn9_index", "wn9_data" }
  local missing = false
  for _, name in ipairs(names) do
    if not path_exists(target_dir .. "/" .. name) then missing = true; break end
  end
  if not missing then return true end
  if not file or not file.getcontents or not file.putcontents then
    print("[xiaozhi-service] wake model repair unavailable: file read/write API missing")
    return false
  end
  if file.mkdir then
    pcall(function() file.mkdir("/sd/apps/xiaozhi") end)
    pcall(function() file.mkdir("/sd/apps/xiaozhi/wake") end)
    pcall(function() file.mkdir(target_dir) end)
  end
  local repaired = true
  for _, name in ipairs(names) do
    local target = target_dir .. "/" .. name
    if not path_exists(target) then
      local source = source_dir .. "/" .. name
      local ok_read, data = pcall(function() return file.getcontents(source) end)
      if not ok_read or type(data) ~= "string" then
        print("[xiaozhi-service] wake model source missing", source)
        repaired = false
      else
        local ok_write, written = pcall(function() return file.putcontents(target, data) end)
        if not ok_write or written == false or written == nil then
          print("[xiaozhi-service] wake model copy failed", target)
          repaired = false
        else
          print("[xiaozhi-service] wake model copied", target)
        end
      end
    end
  end
  return repaired
end

ensure_native_wake_model()

local function load_app_module(name)
  return dofile(APP_DIR .. "/" .. name .. ".lua")
end

local Config = load_app_module("config")
local Runtime = load_app_module("runtime")
local Web = load_app_module("web")

local cfg = Config.load()
cfg.SERVICE_MODE = true
if cfg.UI_MODE == "app" then
  local app_info = (cfg.UI_APP_DIR or "/sd/apps/xiaozhi") .. "/app.info"
  local installed = false
  if file and file.exists then
    local ok, exists = pcall(function() return file.exists(app_info) end)
    installed = ok and exists == true
  elseif file and file.stat then
    local ok, stat = pcall(function() return file.stat(app_info) end)
    installed = ok and stat ~= nil and stat ~= false
  end
  if not installed then cfg.UI_MODE = "floating" end
end
local app = Runtime.new(cfg, load_app_module)
app.web = Web.new(app, cfg)

XIAOZHI_SERVICE_APP = app
local web_ok, web_err = pcall(function() return app.web:start() end)
if not web_ok then print("[xiaozhi] web start failed", tostring(web_err or "")) end
local run_ok, run_err = pcall(function() return app:start() end)
if not run_ok then print("[xiaozhi] runtime start failed", tostring(run_err or "")) end
