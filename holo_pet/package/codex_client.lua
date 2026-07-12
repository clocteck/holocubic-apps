local Client = {}
Client.__index = Client

local JSON = rawget(_G, "sjson") or rawget(_G, "json")

local function now_ms()
  if type(millis) == "function" then return millis() end
  if tmr and type(tmr.now) == "function" then return math.floor(tmr.now() / 1000) end
  return 0
end

local function trim(value)
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function callback_string_arg(...)
  for i = 1, select("#", ...) do
    local value = select(i, ...)
    if type(value) == "string" then return value end
  end
  return nil
end

function Client.new(config, handlers)
  return setmetatable({
    config = config or {},
    handlers = handlers or {},
    buffer = "",
    connection = nil,
    reconnect_timer = nil,
    watchdog_timer = nil,
    closed = false,
    online = false,
    last_event_ms = 0,
    connect_started_ms = 0,
  }, Client)
end

function Client:path()
  local path = tostring(self.config.path or "/events")
  return path:sub(1, 1) == "/" and path or ("/" .. path)
end

function Client:url()
  return "http://" .. tostring(self.config.host) .. ":" .. tostring(self.config.port or 17321) .. self:path()
end

function Client:log(...)
  if self.config.serial_log ~= false then print("[clawd-client]", ...) end
end

function Client:emit_status(state, detail)
  if self.handlers.on_status then
    pcall(function() self.handlers.on_status(state, detail or "") end)
  end
end

function Client:emit_event(raw)
  if not JSON or not JSON.decode then return end
  local ok, doc = pcall(function() return JSON.decode(raw) end)
  if not ok or type(doc) ~= "table" then
    self:log("invalid json", tostring(doc))
    return
  end
  self.online = true
  self.last_event_ms = now_ms()
  self.connect_started_ms = 0
  if self.handlers.on_event then pcall(function() self.handlers.on_event(doc) end) end
  self:emit_status("online", self:url())
end

function Client:handle_line(line)
  line = trim(tostring(line or ""):gsub("\r", ""))
  local payload = line:match("^data:%s*(.+)$")
  if payload and payload ~= "" then self:emit_event(payload) end
end

function Client:handle_chunk(chunk)
  self.buffer = self.buffer .. chunk
  while true do
    local nl = self.buffer:find("\n", 1, true)
    if not nl then break end
    local line = self.buffer:sub(1, nl - 1)
    self.buffer = self.buffer:sub(nl + 1)
    self:handle_line(line)
  end
end

function Client:close_connection()
  if self.connection then pcall(function() self.connection:close() end) end
  self.connection = nil
end

function Client:schedule_reconnect()
  if self.closed then return end
  if self.reconnect_timer then self.reconnect_timer:unregister() end
  self.reconnect_timer = tmr.create()
  self.reconnect_timer:alarm(self.config.reconnect_ms or 2000, tmr.ALARM_SINGLE, function()
    self:connect()
  end)
end

function Client:connect()
  if self.closed then return end
  self:close_connection()
  self.buffer = ""
  self.online = false
  self.connect_started_ms = now_ms()
  self:emit_status("connecting", self:url())

  local ok, conn = pcall(function()
    if net and net.TCP then return net.createConnection(net.TCP, false) end
    return net.createConnection()
  end)
  if not ok or not conn then
    self.connect_started_ms = 0
    self:emit_status("error", tostring(conn))
    self:schedule_reconnect()
    return
  end
  self.connection = conn

  local function bind(event, callback)
    local bind_ok, bind_err = pcall(function() conn:on(event, callback) end)
    if not bind_ok then
      self:emit_status("error", "bind " .. event .. ": " .. tostring(bind_err))
      self:schedule_reconnect()
      return false
    end
    return true
  end

  if not bind("connection", function()
    local request = table.concat({
      "GET " .. self:path() .. " HTTP/1.1",
      "Host: " .. tostring(self.config.host),
      "Accept: text/event-stream",
      "Cache-Control: no-cache",
      "Connection: keep-alive",
      "",
      "",
    }, "\r\n")
    local send_ok, send_err = pcall(function() conn:send(request) end)
    if not send_ok then
      self:emit_status("error", "send: " .. tostring(send_err))
      self:close_connection()
      self:schedule_reconnect()
    else
      self:emit_status("connected", self:url())
    end
  end) then return end

  if not bind("receive", function(...)
    local chunk = callback_string_arg(...)
    if chunk and #chunk > 0 then
      local data_ok, data_err = pcall(function() self:handle_chunk(chunk) end)
      if not data_ok then
        self:emit_status("error", tostring(data_err))
        self:close_connection()
        self:schedule_reconnect()
      end
    end
  end) then return end

  if not bind("disconnection", function()
    if self.closed then return end
    self.online = false
    self.connect_started_ms = 0
    self:emit_status("offline", "connection closed")
    self:schedule_reconnect()
  end) then return end

  local connect_ok, connect_err = pcall(function()
    conn:connect(self.config.port or 17321, self.config.host)
  end)
  if not connect_ok then
    self:emit_status("error", tostring(connect_err))
    self:schedule_reconnect()
  end
end

function Client:start_watchdog()
  if self.watchdog_timer then self.watchdog_timer:unregister() end
  self.watchdog_timer = tmr.create()
  self.watchdog_timer:alarm(self.config.watchdog_ms or 1000, tmr.ALARM_AUTO, function()
    if self.closed then return end
    local now = now_ms()
    if self.connect_started_ms > 0 and now - self.connect_started_ms > (self.config.timeout_ms or 7000) then
      self.connect_started_ms = 0
      self.online = false
      self:emit_status("error", "timeout")
      self:close_connection()
      self:schedule_reconnect()
      return
    end
    if self.last_event_ms > 0 and now - self.last_event_ms > (self.config.stale_ms or 120000) then
      self.last_event_ms = now
      self:emit_status("stale", "waiting for Codex activity")
    end
  end)
end

function Client:start()
  self.closed = false
  self:start_watchdog()
  self:connect()
end

function Client:stop()
  self.closed = true
  if self.reconnect_timer then self.reconnect_timer:unregister(); self.reconnect_timer = nil end
  if self.watchdog_timer then self.watchdog_timer:unregister(); self.watchdog_timer = nil end
  self:close_connection()
end

return Client
