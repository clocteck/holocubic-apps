local M = {}

local APP_DIR = "/sd/apps/xiaozhi"
local SERVICE_ENDPOINT = "xiaozhi-service"
local UI_ENDPOINT = "xiaozhi-ui"

local function load_ui()
  return dofile(APP_DIR .. "/ui.lua")
end

local function bridge()
  local b = rawget(_G, "XIAOZHI_SERVICE")
  if type(b) == "table" and not b.stopped then return b end
  return nil
end

local function codec()
  return rawget(_G, "json") or rawget(_G, "sjson")
end

local function encode(value)
  local lib = codec()
  if not lib or not lib.encode then return "{}" end
  local ok, raw = pcall(lib.encode, value)
  return ok and type(raw) == "string" and raw or "{}"
end

local function decode(raw)
  local lib = codec()
  if type(raw) ~= "string" or raw == "" or not lib or not lib.decode then return nil end
  local ok, value = pcall(lib.decode, raw)
  return ok and type(value) == "table" and value or nil
end

local function ipc_endpoint_available()
  if not ipc or not ipc.endpoints then return false end
  local ok, endpoints = pcall(ipc.endpoints)
  if not ok or type(endpoints) ~= "table" then return false end
  for _, endpoint in ipairs(endpoints) do
    if endpoint == SERVICE_ENDPOINT then return true end
    if type(endpoint) == "table" and endpoint.id == SERVICE_ENDPOINT then return true end
    if type(endpoint) == "table" and endpoint.name == SERVICE_ENDPOINT then return true end
  end
  for key, endpoint in pairs(endpoints) do
    if key == SERVICE_ENDPOINT or endpoint == SERVICE_ENDPOINT then return true end
    if type(endpoint) == "table" and endpoint.id == SERVICE_ENDPOINT then return true end
    if type(endpoint) == "table" and endpoint.name == SERVICE_ENDPOINT then return true end
  end
  return false
end

function M.available()
  return bridge() ~= nil or ipc_endpoint_available()
end

function M.service_installed()
  if not app or not app.list then return false end
  local ok, apps = pcall(app.list)
  if not ok or type(apps) ~= "table" then return false end
  for _, record in ipairs(apps) do
    if type(record) == "table" and record.id == SERVICE_ENDPOINT then return true end
    if record == SERVICE_ENDPOINT then return true end
  end
  for key, record in pairs(apps) do
    if key == SERVICE_ENDPOINT or record == SERVICE_ENDPOINT then return true end
    if type(record) == "table" and record.id == SERVICE_ENDPOINT then return true end
  end
  return false
end

function M.new(cfg)
  local Ui = load_ui()
  local self = {
    cfg = cfg,
    ui = Ui.new(cfg),
    timer = nil,
    unsubscribe = nil,
    stopped = false,
    last_state = nil,
    last_role = nil,
    last_text = nil,
    last_emotion = nil,
    last_status = nil,
    ipc_listening = false,
  }

  local function control(action, value)
    local b = bridge()
    if b and b.control then
      return pcall(function() return b:control(action, value) end)
    end
    if ipc and ipc.send then
      return pcall(function()
        return ipc.send(SERVICE_ENDPOINT, "control", encode({
          endpoint = UI_ENDPOINT,
          action = action,
          value = value,
        }))
      end)
    end
    return false
  end

  local function apply_snapshot(snapshot)
    if type(snapshot) ~= "table" or self.stopped then return end
    local state = tostring(snapshot.state or "idle")
    if state ~= self.last_state then
      self.last_state = state
      self.ui:on_state(state)
    end
    local emotion = tostring(snapshot.emotion or "neutral")
    if emotion ~= self.last_emotion then
      self.last_emotion = emotion
      self.ui:set_emotion(emotion)
    end
    local role = tostring(snapshot.role or "system")
    local text = tostring(snapshot.text or snapshot.notice or snapshot.message or "")
    if role ~= self.last_role or text ~= self.last_text then
      self.last_role = role
      self.last_text = text
      self.ui:set_chat_message(role, text)
    end
    if type(snapshot.status) == "string" and snapshot.status ~= "" and snapshot.status ~= self.last_status then
      self.last_status = snapshot.status
      self.ui:set_status(snapshot.status)
    end
  end

  local function refresh()
    local b = bridge()
    if b and b.snapshot then
      local ok, snapshot = pcall(function() return b:snapshot() end)
      if ok then apply_snapshot(snapshot) end
      return
    end
    if ipc and ipc.send then
      local ok, sent = pcall(function()
        return ipc.send(SERVICE_ENDPOINT, "snapshot", encode({ reply_to = UI_ENDPOINT }))
      end)
      if not ok or not sent then self.ui:set_status("等待小智服务") end
    else
      self.ui:set_status("等待小智服务")
    end
  end

  local function subscribe()
    local b = bridge()
    if not b or not b.subscribe then return false end
    local ok, unsubscribe = pcall(function()
      return b:subscribe(function(snapshot)
        apply_snapshot(snapshot)
      end)
    end)
    if ok and type(unsubscribe) == "function" then
      self.unsubscribe = unsubscribe
      return true
    end
    return false
  end

  local function listen_ipc()
    if self.ipc_listening or not ipc or not ipc.listen then return false end
    local ok, result = pcall(function()
      return ipc.listen(UI_ENDPOINT, function(topic, payload)
        if topic == "snapshot" then
          apply_snapshot(decode(payload))
        end
      end)
    end)
    self.ipc_listening = ok and result ~= nil and result ~= false
    return self.ipc_listening
  end

  local function subscribe_ipc()
    if not listen_ipc() or not ipc or not ipc.send then return false end
    pcall(function()
      ipc.send(SERVICE_ENDPOINT, "subscribe", encode({ endpoint = UI_ENDPOINT }))
    end)
    return true
  end

  function self:start()
    self.stopped = false
    self.ui:setup()
    self.ui:set_metrics({ network = "IPC", audio = "", wake = "", counter = "" })
    if not subscribe() then subscribe_ipc() end
    refresh()
    if tmr and tmr.create then
      self.timer = tmr.create()
      self.timer:alarm(500, tmr.ALARM_AUTO, function()
        if not self.unsubscribe then
          if not subscribe() then subscribe_ipc() end
        end
        refresh()
      end)
    end
    if key and key.on then
      local down = key.DOWN or rawget(_G, "KEY_DOWN")
      local left = key.LEFT or rawget(_G, "KEY_LEFT")
      local right = key.RIGHT or rawget(_G, "KEY_RIGHT")
      local short = key.SHORT or rawget(_G, "KEY_EVENT_SHORT")
      local start = key.START or rawget(_G, "KEY_EVENT_START")
      local function fire(evt) return evt == short or evt == start end
      if down then pcall(function() key.on(down, function(evt) if fire(evt) then control("toggle") end end) end) end
      if left then pcall(function() key.on(left, function(evt) if fire(evt) then control("start", "manual") end end) end) end
      if right then pcall(function() key.on(right, function(evt) if fire(evt) then control("stop") end end) end) end
    end
    return true
  end

  function self:stop(reason)
    self.stopped = true
    if self.unsubscribe then pcall(self.unsubscribe); self.unsubscribe = nil end
    if ipc and ipc.send then
      pcall(function() ipc.send(SERVICE_ENDPOINT, "unsubscribe", encode({ endpoint = UI_ENDPOINT })) end)
    end
    if self.ipc_listening and ipc and ipc.listen then
      pcall(function() ipc.listen(UI_ENDPOINT, nil) end)
      self.ipc_listening = false
    end
    if self.timer then
      pcall(function() self.timer:stop() end)
      pcall(function() self.timer:unregister() end)
      self.timer = nil
    end
    if key and key.off then
      pcall(function() key.off(key.DOWN or rawget(_G, "KEY_DOWN")) end)
      pcall(function() key.off(key.LEFT or rawget(_G, "KEY_LEFT")) end)
      pcall(function() key.off(key.RIGHT or rawget(_G, "KEY_RIGHT")) end)
    end
    self.ui:stop()
    print("[xiaozhi-ui] stop", reason or "")
  end

  self.toggle_chat = function() return control("toggle") end
  self.start_listening = function(mode) return control("start", mode) end
  self.stop_listening = function() return control("stop") end

  return self
end

return M
