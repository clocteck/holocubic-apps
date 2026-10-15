local previous = rawget(_G, "XIAOZHI_UI_APP")
if not previous then
  local legacy = rawget(_G, "XIAOZHI_APP")
  if legacy and (not legacy.cfg or legacy.cfg.SERVICE_MODE ~= true) then
    previous = legacy
    _G.XIAOZHI_APP = nil
  end
end
if previous and previous.stop then
  pcall(function()
    previous.stop("reload")
  end)
end

local APP_DIR = "/sd/apps/xiaozhi"
XIAOZHI_UI_APP_DIR = APP_DIR

local function load_app_module(name)
  return dofile(APP_DIR .. "/" .. name .. ".lua")
end

local Config = load_app_module("config")
local cfg = Config.load()
local Runtime = load_app_module("runtime")
local IpcUi = load_app_module("ui_ipc")
local service_mode = IpcUi.available() or IpcUi.service_installed()
local app
if service_mode then
  if not IpcUi.available() and _G.app and _G.app.start_service then
    pcall(_G.app.start_service, "xiaozhi-service")
  end
  app = IpcUi.new(cfg)
else
  app = Runtime.new(cfg, load_app_module)
end
local app_api = rawget(_G, "app")

XIAOZHI_UI_APP = app
local ok_web, Web = pcall(load_app_module, "web")
if not service_mode and ok_web and Web and Web.new then
  app.web = Web.new(app, cfg)
  local web_ok, web_err = pcall(function() return app.web:start() end)
  if not web_ok then print("[xiaozhi] web start failed", tostring(web_err or "")) end
end
app:start()

if controller and controller.state and tmr and tmr.create then
  local controller_buttons = 0
  app.controller_exit_timer = tmr.create()
  app.controller_exit_timer:alarm(40, tmr.ALARM_AUTO, function()
    local ok, pad = pcall(function() return controller.state("ble-main") end)
    local buttons = ok and type(pad) == "table" and (tonumber(pad.buttons) or 0) or 0
    local pressed = buttons & (~controller_buttons)
    controller_buttons = buttons
    if (pressed & (4096 | 32768)) ~= 0 then
      pcall(function() app.stop("controller-exit") end)
      if app_api and app_api.exit then pcall(function() app_api.exit() end) end
    end
  end)
end
