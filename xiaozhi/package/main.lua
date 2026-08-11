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
local Runtime = load_app_module("runtime")

local cfg = Config.load()
local startup_wake_word = nil
local service = rawget(_G, "XIAOZHI_SERVICE")
if type(service) == "table" and not service.stopped then
  if service.take_pending_wake then
    local ok, wake_word = pcall(function() return service:take_pending_wake() end)
    if ok and type(wake_word) == "string" and wake_word ~= "" then startup_wake_word = wake_word end
  end
  if service.suspend then pcall(function() service:suspend("foreground xiaozhi opened") end) end
end
if not startup_wake_word and file and file.getcontents then
  local handoff_path = "/sd/apps/xiaozhi-service/pending-wake.json"
  local ok, raw = pcall(function() return file.getcontents(handoff_path) end)
  local codec = rawget(_G, "json") or rawget(_G, "sjson")
  if ok and type(raw) == "string" and codec and codec.decode then
    local decoded, doc = pcall(codec.decode, raw)
    if decoded and type(doc) == "table" and type(doc.wake_word) == "string" then
      startup_wake_word = doc.wake_word
    end
  end
  if file.remove then pcall(function() file.remove(handoff_path) end) end
end
if ipc and ipc.send then
  local codec = rawget(_G, "json") or rawget(_G, "sjson")
  local payload = '{"app_id":"xiaozhi","source":"foreground-main"}'
  if codec and codec.encode then
    local ok, raw = pcall(codec.encode, { app_id = "xiaozhi", source = "foreground-main" })
    if ok and type(raw) == "string" then payload = raw end
  end
  pcall(function() ipc.send("xiaozhi-service", "on_app_change", payload) end)
end

local app = Runtime.new(cfg, load_app_module)
app.startup_wake_word = startup_wake_word
local app_api = rawget(_G, "app")

XIAOZHI_UI_APP = app
local ok_web, Web = pcall(load_app_module, "web")
if ok_web and Web and Web.new then
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
