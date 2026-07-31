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

local previous = rawget(_G, "XIAOZHI_APP")
if previous and previous.stop then
  pcall(function()
    previous.stop("reload")
  end)
end

local APP_DIR = "/sd/apps/xiaozhi-service"
local UI_APP_DIR = "/sd/apps/xiaozhi"
XIAOZHI_UI_APP_DIR = UI_APP_DIR
XIAOZHI_SERVICE_DIR = APP_DIR
local SHARED_MODULES = {
  activation = true,
  audio = true,
  identity = true,
  mcp = true,
  mic_diag = true,
  protocol = true,
  state = true,
}

local function load_app_module(name)
  if SHARED_MODULES[name] then
    local ok, mod = pcall(dofile, UI_APP_DIR .. "/" .. name .. ".lua")
    if ok then return mod end
    error("[xiaozhi-service] missing shared module " .. name
      .. " from " .. UI_APP_DIR .. ": " .. tostring(mod or ""))
  end
  return dofile(APP_DIR .. "/" .. name .. ".lua")
end

local Config = load_app_module("config")
local Runtime = load_app_module("runtime")
local Web = load_app_module("web")

local cfg = Config.load()
cfg.SERVICE_MODE = true
local app = Runtime.new(cfg, load_app_module)
app.web = Web.new(app, cfg)

XIAOZHI_APP = app
local web_ok, web_err = pcall(function() return app.web:start() end)
if not web_ok then print("[xiaozhi] web start failed", tostring(web_err or "")) end
local run_ok, run_err = pcall(function() return app:start() end)
if not run_ok then print("[xiaozhi] runtime start failed", tostring(run_err or "")) end
