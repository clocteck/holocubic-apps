local previous = rawget(_G, "BTC_MARKETS_APP")
if previous and previous.stop then
  pcall(function()
    previous.stop("reload")
  end)
end

local APP_DIR = "/sd/apps/btc"

-- 加载目录内模块，保持目录式 app 的入口只负责装配。
local function load_module(name)
  return dofile(APP_DIR .. "/" .. name .. ".lua")
end

local Backend = load_module("backend")

local app_obj = {
  VERSION = "2.0.1",
  APP_ID = "btc",
  APP_DIR = APP_DIR,
  route_base = (app and app.route_base and app.route_base()) or "/btc",
  timers = {},
  stopping = false,
}

app_obj.backend = Backend.new({
  version = app_obj.VERSION,
  app_id = app_obj.APP_ID,
  config_path = APP_DIR .. "/settings.json",
})

-- 配置已在 Backend.new 中快速读取；这里先发出异步行情请求，后续 UI 字体加载可与网络等待重叠。
app_obj.backend:queue_refresh()
app_obj.backend:tick()

-- HTTP 已经启动，再解析 Web/UI 模块并加载大字体。
local I18n = load_module("i18n")
local Ui = load_module("ui")
local Web = load_module("web")

app_obj.i18n = I18n
app_obj.ui = Ui.new(app_obj.backend, I18n)
app_obj.web = Web.new(app_obj.backend, {
  route_base = app_obj.route_base,
  language = I18n.language,
})
app_obj.input = {
  last_key_ms = 0,
}

local KEYMOD = rawget(_G, "key")
local KEY_LEFT_CODE = (KEYMOD and KEYMOD.LEFT) or rawget(_G, "KEY_LEFT") or 1
local KEY_RIGHT_CODE = (KEYMOD and KEYMOD.RIGHT) or rawget(_G, "KEY_RIGHT") or 2
local KEY_UP_CODE = (KEYMOD and KEYMOD.UP) or rawget(_G, "KEY_UP") or 3
local KEY_DOWN_CODE = (KEYMOD and KEYMOD.DOWN) or rawget(_G, "KEY_DOWN") or 4
local KEY_EVENT_START_CODE = (KEYMOD and KEYMOD.START) or rawget(_G, "KEY_EVENT_START") or 1
local KEY_EVENT_SHORT_CODE = (KEYMOD and KEYMOD.SHORT) or rawget(_G, "KEY_EVENT_SHORT") or 2
local KEY_EVENT_LONG_START_CODE = (KEYMOD and KEYMOD.LONG_START) or rawget(_G, "KEY_EVENT_LONG_START") or 3
local KEY_DEBOUNCE_MS = 120

-- 返回当前毫秒，用于按键去抖。
local function now_ms()
  if millis then
    local ok, value = pcall(millis)
    if ok and type(value) == "number" then
      return value
    end
  end
  if tmr and tmr.now then
    local ok, value = pcall(function() return tmr.now() end)
    if ok and type(value) == "number" then
      return math.floor(value / 1000)
    end
  end
  return 0
end

-- 停止 timer、按键、HTTP 路由和页面，确保热重载不会留下旧状态。
function app_obj.stop(reason)
  if app_obj.stopping then
    return
  end
  app_obj.stopping = true

  if app_obj.tick_timer then
    pcall(function() app_obj.tick_timer:stop() end)
    pcall(function() app_obj.tick_timer:unregister() end)
    app_obj.tick_timer = nil
  end

  if app and app.on then
    pcall(function() app.on("key", nil) end)
  end

  if app_obj.web then
    pcall(function() app_obj.web:stop(reason) end)
  end
  if app_obj.ui then
    pcall(function() app_obj.ui:stop(reason) end)
  end
  if app_obj.backend then
    pcall(function() app_obj.backend:stop(reason) end)
  end
end

-- 判断按键码，避免把事件类型误识别为键码。
local function is_key_code(value)
  return value == KEY_LEFT_CODE
    or value == KEY_RIGHT_CODE
    or value == KEY_UP_CODE
    or value == KEY_DOWN_CODE
end

-- 判断事件类型，app.on("key") 会同时传事件类型和键码。
local function is_event_type(value)
  return value == KEY_EVENT_START_CODE
    or value == KEY_EVENT_SHORT_CODE
    or value == KEY_EVENT_LONG_START_CODE
end

-- 从 app.on/key.on 的不同回调参数中提取事件类型和键码。
local function extract_key_event(...)
  local args = { ... }
  for i = 1, #args - 1 do
    local evt_type = args[i]
    local evt_code = args[i + 1]
    if type(evt_type) == "number" and type(evt_code) == "number"
      and is_event_type(evt_type) and is_key_code(evt_code) then
      return evt_type, evt_code, args[i + 2]
    end
  end

  for i = 1, #args do
    if is_key_code(args[i]) then
      return KEY_EVENT_SHORT_CODE, args[i], 0
    end
  end
  return nil, nil, nil
end

-- 处理实体按键：短按上下切资产，短按左右切周期，长按左右切折线/K 线。
local function handle_key(...)
  local evt_type, evt_code, ts_ms = extract_key_event(...)
  if not evt_code then
    return
  end

  local t = tonumber(ts_ms) or now_ms()
  if t > 0 and app_obj.input.last_key_ms > 0 and (t - app_obj.input.last_key_ms) < KEY_DEBOUNCE_MS then
    return
  end

  if evt_type == KEY_EVENT_LONG_START_CODE then
    if evt_code == KEY_LEFT_CODE or evt_code == KEY_RIGHT_CODE then
      app_obj.input.last_key_ms = t
      app_obj.backend:toggle_mode()
      app_obj.ui:render(true)
    end
    return
  end

  if evt_type ~= KEY_EVENT_SHORT_CODE then
    return
  end

  app_obj.input.last_key_ms = t
  if evt_code == KEY_UP_CODE then
    app_obj.backend:select_asset_delta(-1)
  elseif evt_code == KEY_DOWN_CODE then
    app_obj.backend:select_asset_delta(1)
  elseif evt_code == KEY_LEFT_CODE then
    app_obj.backend:select_interval_delta(-1)
  elseif evt_code == KEY_RIGHT_CODE then
    app_obj.backend:select_interval_delta(1)
  end
  app_obj.ui:render(true)
end

-- 启动周期任务，网络请求由 backend 内部串行调度。
local function start_tick()
  if not tmr or not tmr.create then
    return
  end
  app_obj.tick_timer = tmr.create()
  app_obj.tick_timer:alarm(500, tmr.ALARM_AUTO, function()
    if app and app.exiting and app.exiting() then
      app_obj.stop("exit")
      return
    end

    app_obj.backend:tick()
    app_obj.ui:render()
  end)
end

BTC_MARKETS_APP = app_obj

app_obj.ui:build()
app_obj.ui:render(true)
app_obj.web:start()

if app and app.on then
  pcall(function() app.on("key", nil) end)
  app.on("key", handle_key)
end

start_tick()
