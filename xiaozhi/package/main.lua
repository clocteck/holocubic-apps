local previous = rawget(_G, "XIAOZHI_APP")
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
local Runtime = load_app_module("runtime")
local UiIpc = load_app_module("ui_ipc")

local cfg = Config.load()
local use_ipc = UiIpc.available()
if not use_ipc and UiIpc.service_installed() then
  if app and app.start_service then
    pcall(function() app.start_service("xiaozhi-service") end)
  end
  use_ipc = true
end

local app = use_ipc and UiIpc.new(cfg) or Runtime.new(cfg, load_app_module)
local app_api = rawget(_G, "app")

XIAOZHI_APP = app
if not use_ipc then
  local ok_web, Web = pcall(load_app_module, "web")
  if ok_web and Web and Web.new then
    app.web = Web.new(app, cfg)
    local web_ok, web_err = pcall(function() return app.web:start() end)
    if not web_ok then print("[xiaozhi] web start failed", tostring(web_err or "")) end
  end
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
