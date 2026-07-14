local AidaClient = {}
AidaClient.__index = AidaClient

local function now_ms()
  if type(millis) == "function" then
    return millis()
  end

  if tmr and type(tmr.now) == "function" then
    return math.floor(tmr.now() / 1000)
  end

  return 0
end

local function trim(text)
  if text == nil then
    return ""
  end

  return (tostring(text):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function split_remote_items(payload)
  local items = {}
  local pos = 1

  while pos <= #payload do
    local first, last = payload:find("%{%|%}", pos)
    if not first then
      items[#items + 1] = payload:sub(pos)
      break
    end

    items[#items + 1] = payload:sub(pos, first - 1)
    pos = last + 1
  end

  return items
end

local function first_number(text)
  local num = tostring(text or ""):match("([%-+]?%d+%.?%d*)")
  if num then
    return tonumber(num)
  end
  return nil
end

local function number_after_alias(text, alias)
  local lower = text:lower()
  local needle = alias:lower()
  local first, last = lower:find(needle, 1, true)

  if not first then
    return nil
  end

  return first_number(text:sub(last + 1))
end

local function parse_generic_entry(entry)
  local key, text = entry:match("^([^|]+)|(.+)$")
  if not key or not text then
    return nil
  end

  text = trim(text)

  local label, value, unit = text:match("^(.-)%s+([%-+]?%d+%.?%d*)%s*([^%d%-+]*)$")
  if not label or label == "" then
    label = text
  end

  return {
    key = trim(key),
    label = trim(label),
    text = text,
    value = value and tonumber(value) or first_number(text),
    unit = trim(unit or "")
  }
end

local function parse_payload(payload)
  local raw = {}
  local entries = {}

  for _, item in ipairs(split_remote_items(payload)) do
    local entry = parse_generic_entry(item)
    if entry then
      entries[#entries + 1] = entry
      raw[entry.label] = entry
    end
  end

  return raw, entries
end

local function split_fields(entry)
  local fields = {}
  local start = 1
  while true do
    local pos = entry:find("|", start, true)
    if not pos then
      fields[#fields + 1] = entry:sub(start)
      break
    end
    fields[#fields + 1] = entry:sub(start, pos - 1)
    start = pos + 1
  end
  return fields
end

local function color_value(text, fallback)
  local hex = tostring(text or ""):match("#([%x][%x][%x][%x][%x][%x])")
  return hex and tonumber(hex, 16) or fallback
end

local function gradient_value(text, fallback)
  local result = {}
  for hex in tostring(text or ""):gmatch("#([%x][%x][%x][%x][%x][%x])") do
    result[#result + 1] = tonumber(hex, 16)
    if #result == 2 then break end
  end
  if #result == 0 then result[1] = fallback or 0 end
  if #result == 1 then result[2] = result[1] end
  return result
end

local function html_decode(text)
  text = tostring(text or "")
  text = text:gsub("&nbsp;", " "):gsub("&deg;", "°")
  text = text:gsub("&quot;", '"'):gsub("&#39;", "'")
  text = text:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
  return text
end

local function parse_remote_payload(payload)
  local sample = {
    payload = payload,
    page = nil,
    updates = {},
    control = nil,
  }
  for _, entry in ipairs(split_remote_items(payload)) do
    entry = trim(entry)
    if entry ~= "" then
      if entry == "ReLoad" then
        sample.control = "ReLoad"
      else
        local page = entry:match("^Page(%d+)$")
        if page then
          sample.page = tonumber(page) + 1
        else
          local fields = split_fields(entry)
          local id = fields[1] or ""
          if id:match("^SIV%d+$") or id:match("^Simple%d+$") then
            sample.updates[#sample.updates + 1] = {
              id = id, kind = "text", text = html_decode(fields[2] or ""),
              visible = (fields[2] or "") ~= "",
            }
          elseif id:match("^Bar%d+p$") then
            sample.updates[#sample.updates + 1] = {
              id = id,
              kind = "bar",
              percent = tonumber(fields[2]) or 0,
              visible = (fields[2] or "") ~= "",
              background = gradient_value(fields[3], 0x202020),
              foreground = gradient_value(fields[4], 0x00FF00),
            }
          elseif id:match("^Gph%d+p$") then
            if (fields[2] or "") == "" then
              sample.updates[#sample.updates + 1] = { id = id, kind = "graph_clear" }
            else
              sample.updates[#sample.updates + 1] = {
                id = id, kind = "graph", value = tonumber(fields[2]) or first_number(fields[2]) or 0,
              }
            end
          elseif id:match("^Arc%d+p$") then
            sample.updates[#sample.updates + 1] = {
              id = id,
              kind = "arc",
              percent = tonumber(fields[2]) or 0,
              text = html_decode(fields[3] or ""),
              visible = (fields[3] or "") ~= "",
              background_color = color_value(fields[4], 0x202020),
              active_color = color_value(fields[5], 0x00FF00),
            }
          end
        end
      end
    end
  end
  return sample
end

local function map_metrics(entries, metric_defs)
  local metrics = {}

  for _, metric in ipairs(metric_defs or {}) do
    local best

    for _, entry in ipairs(entries) do
      for _, alias in ipairs(metric.aliases or {}) do
        local value = number_after_alias(entry.text, alias)
        if value ~= nil then
          best = {
            value = value,
            unit = metric.unit or entry.unit or "",
            label = alias,
            text = entry.text,
            source = entry.key
          }
          break
        end
      end

      if best then
        break
      end
    end

    if best then
      metrics[metric.id] = best
    end
  end

  return metrics
end

local function callback_string_arg(...)
  for i = 1, select("#", ...) do
    local value = select(i, ...)
    if type(value) == "string" then
      return value
    end
  end

  return nil
end

function AidaClient.new(config, handlers)
  local self = setmetatable({}, AidaClient)

  self.config = config or {}
  self.handlers = handlers or {}
  self.buffer = ""
  self.connection = nil
  self.reconnect_timer = nil
  self.watchdog_timer = nil
  self.closed = false
  self.online = false
  self.last_event_ms = 0
  self.connect_started_ms = 0

  return self
end

function AidaClient:url()
  local path = self.config.path or "/sse"
  if path:sub(1, 1) ~= "/" then
    path = "/" .. path
  end

  return "http://" .. self.config.host .. ":" .. tostring(self.config.port or 80) .. path
end

function AidaClient:path()
  local path = self.config.path or "/sse"
  if path:sub(1, 1) ~= "/" then
    path = "/" .. path
  end

  return path
end

function AidaClient:log(...)
  if self.config.serial_log == false then
    return
  end

  print("[monitor]", ...)
end

function AidaClient:emit_status(state, detail)
  self:log("status", state, detail or "")

  if self.handlers.on_status then
    local ok, err = pcall(function()
      self.handlers.on_status(state, detail or "")
    end)

    if not ok then
      self:log("on_status_error", err)
    end
  end
end

function AidaClient:emit_sample(payload)
  local protocol = parse_remote_payload(payload)
  if protocol.control then
    if self.handlers.on_control then
      local ok, err = pcall(function() self.handlers.on_control(protocol.control) end)
      if not ok then self:log("on_control_error", err) end
    end
    return
  end
  local raw, entries = parse_payload(payload)
  if #entries == 0 and #protocol.updates == 0 and not protocol.page then
    if self.handlers.on_control then
      local ok, err = pcall(function()
        self.handlers.on_control(payload)
      end)

      if not ok then
        self:log("on_control_error", err)
      end
    end
    return
  end

  local sample = {
    received_at = now_ms(),
    payload = payload,
    page = protocol.page,
    updates = protocol.updates,
    raw = raw,
    entries = entries,
    metrics = map_metrics(entries, self.config.metrics)
  }

  self.online = true
  self.last_event_ms = sample.received_at
  self.connect_started_ms = 0

  if self.handlers.on_sample then
    local ok, err = pcall(function()
      self.handlers.on_sample(sample)
    end)

    if not ok then
      self:log("on_sample_error", err)
    end
  end
end

function AidaClient:handle_line(line)
  line = trim(line:gsub("\r", ""))

  if line == "" then
    return
  end

  local payload = line:match("^data:%s*(.+)$")
  if payload and payload ~= "" then
    self:emit_sample(payload)
  end
end

function AidaClient:handle_chunk(chunk)
  self:log("chunk", #chunk)
  self.buffer = self.buffer .. chunk

  while true do
    local nl = self.buffer:find("\n", 1, true)
    if not nl then
      break
    end

    local line = self.buffer:sub(1, nl - 1)
    self.buffer = self.buffer:sub(nl + 1)
    self:handle_line(line)
  end
end

function AidaClient:close_connection()
  if self.connection then
    pcall(function()
      self.connection:close()
    end)
  end

  self.connection = nil
end

function AidaClient:schedule_reconnect()
  if self.closed then
    return
  end

  if self.reconnect_timer then
    self.reconnect_timer:unregister()
  end

  self.reconnect_timer = tmr.create()
  self.reconnect_timer:alarm(self.config.reconnect_ms or 2000, tmr.ALARM_SINGLE, function()
    self:connect()
  end)
end

function AidaClient:connect()
  if self.closed then
    return
  end

  self:close_connection()
  self.buffer = ""
  self.connect_started_ms = now_ms()
  self:log("connect_begin", self:url())
  self:emit_status("connecting", self:url())

  local ok, conn_or_err = pcall(function()
    if net and net.TCP then
      return net.createConnection(net.TCP, false)
    end

    return net.createConnection()
  end)

  if not ok or not conn_or_err then
    self.online = false
    self.connect_started_ms = 0
    self:emit_status("error", tostring(conn_or_err))
    self:schedule_reconnect()
    return
  end

  local conn = conn_or_err
  self.connection = conn
  self:log("socket_created", tostring(conn))

  local function bind(event, callback)
    local bind_ok, bind_err = pcall(function()
      conn:on(event, callback)
    end)

    if not bind_ok then
      self.online = false
      self.connect_started_ms = 0
      self:emit_status("error", "bind " .. event .. ": " .. tostring(bind_err))
      self:schedule_reconnect()
      return false
    end

    self:log("bind_ok", event)
    return true
  end

  local function bind_optional(event, callback)
    local bind_ok, bind_err = pcall(function()
      conn:on(event, callback)
    end)

    if bind_ok then
      self:log("bind_ok", event)
    else
      self:log("bind_skip", event, bind_err)
    end
  end

  if not bind("connection", function()
    self:log("tcp_connected", self.config.host, self.config.port or 80)
    self:emit_status("connected", self:url())

    local request = table.concat({
      "GET " .. self:path() .. " HTTP/1.1",
      "Host: " .. self.config.host,
      "Accept: text/event-stream",
      "Cache-Control: no-cache",
      "Connection: close",
      "",
      ""
    }, "\r\n")

    self:log("send_begin", #request)
    local send_ok, send_err = pcall(function()
      conn:send(request)
    end)
    self:log("send_return", send_ok, send_err or "")

    if not send_ok then
      self.online = false
      self.connect_started_ms = 0
      self:emit_status("error", "send: " .. tostring(send_err))
      self:close_connection()
      self:schedule_reconnect()
      return
    end

    self:emit_status("stream", "request sent")
  end) then
    return
  end

  if not bind("receive", function(...)
    local chunk = callback_string_arg(...)
    if chunk and #chunk > 0 then
      local data_ok, data_err = pcall(function()
        self:handle_chunk(chunk)
      end)

      if not data_ok then
        self.online = false
        self.connect_started_ms = 0
        self:emit_status("error", "data handler: " .. tostring(data_err))
        self:close_connection()
        self:schedule_reconnect()
      end
    end
  end) then
    return
  end

  bind_optional("sent", function()
    self:log("tcp_sent")
  end)

  bind_optional("dns", function(...)
    self:log("tcp_dns", callback_string_arg(...) or "")
  end)

  if not bind("disconnection", function(...)
    if self.closed then
      return
    end

    self.online = false
    self.connect_started_ms = 0
    self:emit_status("complete", callback_string_arg(...) or "closed")
    self:schedule_reconnect()
  end) then
    return
  end

  self:log("tcp_connect_begin", self.config.host, self.config.port or 80)
  local connect_ok, connect_err = pcall(function()
    conn:connect(self.config.port or 80, self.config.host)
  end)
  self:log("tcp_connect_return", connect_ok, connect_err or "")

  if not connect_ok then
    self.online = false
    self.connect_started_ms = 0
    self:emit_status("error", tostring(connect_err))
    self:schedule_reconnect()
  end
end

function AidaClient:start_watchdog()
  if self.watchdog_timer then
    self.watchdog_timer:unregister()
  end

  self.watchdog_timer = tmr.create()
  self.watchdog_timer:alarm(self.config.watchdog_ms or 1000, tmr.ALARM_AUTO, function()
    if self.closed then
      return
    end

    local now = now_ms()

    if self.last_event_ms == 0 and self.connect_started_ms > 0 and now - self.connect_started_ms > (self.config.timeout_ms or 7000) then
      self.connect_started_ms = 0
      self.online = false
      self:emit_status("error", "timeout")
      self:close_connection()
      self:schedule_reconnect()
      return
    end

    if self.last_event_ms > 0 and now - self.last_event_ms > (self.config.stale_ms or 5000) then
      if self.online then
        self.online = false
        self:emit_status("stale", "no data")
      end

      self.last_event_ms = 0
      self.connect_started_ms = 0
      self:close_connection()
      self:schedule_reconnect()
    end
  end)
end

function AidaClient:start()
  self.closed = false
  self:start_watchdog()
  self:connect()
end

function AidaClient:stop()
  self.closed = true

  if self.reconnect_timer then
    self.reconnect_timer:unregister()
    self.reconnect_timer = nil
  end

  if self.watchdog_timer then
    self.watchdog_timer:unregister()
    self.watchdog_timer = nil
  end

  self:close_connection()
end

AidaClient.parse_payload = parse_payload
AidaClient.parse_remote_payload = parse_remote_payload
AidaClient.map_metrics = map_metrics

return AidaClient
