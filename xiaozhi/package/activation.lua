local T = dofile((rawget(_G, "XIAOZHI_UI_APP_DIR") or "/sd/apps/xiaozhi") .. "/i18n.lua").translator()
local M = {}

local identity_cache = nil

local function identity(cfg)
  if not identity_cache then
    identity_cache = dofile((cfg and cfg.APP_DIR or "/sd/apps/xiaozhi") .. "/identity.lua")
  end
  return identity_cache
end

local function decode_json(raw)
  if type(raw) ~= "string" then
    return nil
  end
  if sjson and sjson.decode then
    local ok, obj = pcall(sjson.decode, raw)
    if ok and type(obj) == "table" then
      return obj
    end
  end
  return nil
end

local function pick_block(raw, name)
  if type(raw) ~= "string" then
    return nil
  end
  return raw:match('"' .. name .. '"%s*:%s*{(.-)}')
end

local function pick_string(raw, name)
  if type(raw) ~= "string" then
    return nil
  end
  return raw:match('"' .. name .. '"%s*:%s*"([^"]*)"')
end

local function pick_number(raw, name)
  if type(raw) ~= "string" then
    return nil
  end
  return tonumber(raw:match('"' .. name .. '"%s*:%s*(%d+)') or "")
end

local function normalize_activate_url(url)
  url = tostring(url or "")
  if url == "" then
    return ""
  end
  if url:sub(-1) == "/" then
    return url .. "activate"
  end
  return url .. "/activate"
end

local function encode_body(cfg, id)
  local _ = id
  return identity(cfg).system_info_json(cfg)
end

local function parse_response(raw)
  local obj = decode_json(raw)
  if obj then
    return obj
  end

  local activation = pick_block(raw, "activation") or ""
  local websocket = pick_block(raw, "websocket") or ""
  local out = {}
  if activation ~= "" then
    out.activation = {
      code = pick_string(activation, "code"),
      message = pick_string(activation, "message"),
      challenge = pick_string(activation, "challenge"),
      timeout_ms = pick_number(activation, "timeout_ms"),
    }
  end
  if websocket ~= "" then
    out.websocket = {
      url = pick_string(websocket, "url"),
      token = pick_string(websocket, "token"),
      version = pick_number(websocket, "version"),
    }
  end
  return out
end

local function write_runtime_config(cfg)
  local Store = dofile(cfg.APP_DIR .. "/store.lua")
  return Store.update(function(doc)
    if Store.device_id() ~= cfg.ACTIVATION_ID then return false, "identity_changed" end
    doc.websocket = { url=cfg.websocket.url, token=cfg.websocket.token, version=cfg.websocket.version }
  end)
end

function M.new(cfg)
  cfg.ACTIVATION_ID = identity(cfg).device_id()
  local self = {
    cfg = cfg,
    timer = nil,
    active = false,
    poll_count = 0,
    network_retries = 0,
    code = "",
    challenge = "",
    pending_websocket = nil,
    callback = nil,
    started_ms = 0,
    slow_retry = false,
    next_retry_ms = 0,
    last_error = "",
  }

  local function positive_ms(name, fallback)
    return math.max(1000, math.floor(tonumber(cfg.ota and cfg.ota[name]) or fallback))
  end
  -- New keys deliberately ignore legacy interval_ms/max_polls: an old saved
  -- config must not retain the old 3-second polling and terminal poll limit.
  local fast_interval = positive_ms("poll_interval_ms", 6000)
  local slow_interval = positive_ms("slow_poll_interval_ms", 20000)
  local fast_window = positive_ms("pairing_timeout_ms", 300000)

  local function elapsed_ms()
    return (millis() - self.started_ms) % 4294967296
  end

  local function emit(name, data)
    if self.callback then
      pcall(self.callback, name, data)
    end
  end

  local function stop_timer()
    if self.timer then
      pcall(function() self.timer:stop() end)
      pcall(function() self.timer:unregister() end)
      self.timer = nil
    end
  end

  local function schedule(delay_ms, fn)
    if not self.active then
      return
    end
    stop_timer()
    self.next_retry_ms = delay_ms
    local timer = tmr.create()
    self.timer = timer
    timer:alarm(delay_ms, tmr.ALARM_SINGLE, function()
      if not self.active or self.timer ~= timer then return end
      self.next_retry_ms = 0
      fn()
    end)
  end

  local function apply_websocket(ws)
    if type(ws) ~= "table" then
      return false
    end
    local url = ws.url or ws.endpoint
    if type(url) == "string" and url:match("^wss?://") then
      self.cfg.websocket.url = url
    end
    if type(ws.token) == "string" then
      self.cfg.websocket.token = ws.token
    end
    if tonumber(ws.version) then
      self.cfg.websocket.version = math.floor(tonumber(ws.version))
    end
    return type(self.cfg.websocket.url) == "string" and self.cfg.websocket.url ~= ""
  end

  local function request_ota()
    if not http or not http.post then
      return nil, "http api missing"
    end
    local ota_url = self.cfg.ota and self.cfg.ota.url or ""
    if ota_url == "" then
      return nil, "ota url missing"
    end
    local ident = identity(self.cfg)
    local id = ident.device_id()
    if not id then
      return nil, "device mac unavailable", true
    end
    local headers, headers_err = ident.http_headers(self.cfg)
    if not headers then
      return nil, headers_err or "device mac unavailable", true
    end
    local body_text, body_err = encode_body(self.cfg, id)
    if not body_text then
      return nil, body_err or "device identity unavailable", true
    end
    print("[xiaozhi] ota check", ota_url, headers["Device-Id"], headers["Client-Id"])
    local ok, code, body = pcall(http.post, ota_url, {
      headers = headers,
      timeout = self.cfg.ota.timeout_ms or 10000,
      bufsz = 8192,
      max_redirects = 3,
    }, body_text)
    if not ok then return nil, "ota request failed: " .. tostring(code) end
    print("[xiaozhi] ota status", tostring(code), "bytes=" .. tostring(body and #body or 0))
    if tonumber(code) ~= 200 then
      return nil, "ota status " .. tostring(code) .. " " .. tostring(body or "")
    end
    return parse_response(body or ""), nil
  end

  local function request_activate()
    if not http or not http.post then
      return nil, "http api missing"
    end
    local headers, headers_err = identity(self.cfg).http_headers(self.cfg)
    if not headers then
      return nil, headers_err or "device mac unavailable"
    end
    local ok, code, body = pcall(http.post, normalize_activate_url(self.cfg.ota.url), {
      headers = headers,
      timeout = self.cfg.ota.timeout_ms or 10000,
      bufsz = 2048,
      max_redirects = 3,
    }, "{}")
    if not ok then return nil, "activate request failed: " .. tostring(code) end
    code = tonumber(code)
    if code == 200 then
      return "ok"
    end
    if code == 202 then
      return "pending"
    end
    return nil, "activate status " .. tostring(code) .. " " .. tostring(body or "")
  end

  local function finish(ok, data)
    self.active = false
    stop_timer()
    self.next_retry_ms = 0
    if ok then
      self.code, self.challenge, self.pending_websocket, self.last_error = "", "", nil, ""
    else
      self.last_error = tostring(data or "activation failed")
    end
    emit(ok and "done" or "failed", data)
  end

  local check_again
  local poll_activate
  local start_after_identity_ready

  local function pending(message)
    emit("pending", {
      code = self.code, count = self.poll_count, retry = self.network_retries,
      slow_retry = self.slow_retry, elapsed_ms = elapsed_ms(),
      next_retry_ms = self.next_retry_ms,
      message = message or (self.last_error ~= "" and self.last_error)
        or (self.slow_retry and T("配对等待超时，后台继续重试")) or "",
    })
  end

  local function schedule_retry(fn)
    if not self.active then return end
    local elapsed = elapsed_ms()
    if self.slow_retry or elapsed >= fast_window then
      if not self.slow_retry and fn == poll_activate then fn = check_again end
      self.slow_retry = true
      schedule(slow_interval, fn)
    elseif elapsed + fast_interval >= fast_window then
      -- Reach the deadline without issuing another fast request across it.
      -- Network request time is included; retries never reset this deadline.
      schedule(fast_window - elapsed, function()
        schedule_retry(fn)
      end)
    else
      schedule(fast_interval, fn)
    end
    pending()
  end

  local function retry_network(err, fn)
    self.network_retries = self.network_retries + 1
    self.last_error = tostring(err or "activation request failed")
    if err == "http api missing" or err == "ota url missing" then
      finish(false, err)
      return
    end
    schedule_retry(fn)
  end

  start_after_identity_ready = function()
    if not self.active then
      return
    end
    local ident = identity(self.cfg)
    local id = ident.device_id()
    if not id or not ident.client_id(id) then
      emit("waiting_mac", "device mac unavailable")
      schedule_retry(start_after_identity_ready)
      return
    end
    if self.cfg.websocket and self.cfg.websocket.url ~= "" and not self.cfg.ota.force then
      finish(true, "configured")
      return
    end
    schedule(10, check_again)
  end

  check_again = function()
    if not self.active then
      return
    end
    emit("checking", nil)
    local res, err, waiting_mac = request_ota()
    if not self.active then return end
    if not res then
      if waiting_mac then
        emit("waiting_mac", err)
        schedule_retry(check_again)
        return
      end
      retry_network(err, check_again)
      return
    end

    local activation = type(res.activation) == "table" and res.activation or {}
    -- A fresh OTA response without activation means binding has completed.
    -- Never let the previous code mask newly returned websocket credentials.
    self.code = tostring(activation.code or "")
    self.challenge = activation.challenge or ""
    if self.code ~= "" or self.challenge ~= "" then
      self.network_retries, self.last_error = 0, ""
      self.pending_websocket = res.websocket or self.pending_websocket
    elseif apply_websocket(res.websocket) then
      self.network_retries, self.last_error = 0, ""
      local saved, save_err = write_runtime_config(self.cfg)
      if not saved then finish(false, save_err); return end
      finish(true, "configured")
      return
    end

    if self.code ~= "" then
      emit("code", {
        code = self.code,
        message = activation.message or T("在后台添加设备输入验证码"),
      })
    elseif self.challenge ~= "" then
      emit("code", {
        code = "",
        message = T("等待后台设备绑定"),
      })
    else
      retry_network("ota response has no activation or websocket", check_again)
      return
    end

    schedule_retry(poll_activate)
  end

  poll_activate = function()
    if not self.active then
      return
    end
    self.poll_count = self.poll_count + 1
    local status, err = request_activate()
    if not self.active then return end
    if status == "ok" then
      emit("activated", self.code)
      if apply_websocket(self.pending_websocket) then
        local saved, save_err = write_runtime_config(self.cfg)
        if not saved then finish(false, save_err); return end
        finish(true, "configured")
        return
      end
      schedule(400, check_again)
      return
    end
    if status == "pending" then
      self.network_retries = 0
      self.last_error = ""
      -- In the slow phase, also refresh OTA to discover credentials even if
      -- /activate still reports pending, and renew an expired pairing code.
      schedule_retry(self.slow_retry and check_again or poll_activate)
      return
    end
    -- Recheck OTA after an error (including an expired code / HTTP 4xx).
    -- Binding may have completed while the failed request was in flight.
    retry_network(err, check_again)
  end

  function self:start(callback)
    self:stop()
    self.callback = callback
    self.poll_count, self.network_retries = 0, 0
    self.slow_retry, self.last_error = false, ""
    if type(millis) ~= "function" or not tmr or not tmr.create then
      finish(false, "activation timer/clock api missing")
      return true
    end
    self.started_ms = millis()
    local websocket_configured = self.cfg.websocket and self.cfg.websocket.url ~= "" and
        self.cfg.ota and not self.cfg.ota.force
    if (not self.cfg.ota or self.cfg.ota.enabled == false) and not websocket_configured then
      return false, "ota disabled"
    end
    if not websocket_configured and (not self.cfg.ota.url or self.cfg.ota.url == "") then
      emit("need_config", T("未配置 ota.url"))
      return false, "ota url missing"
    end
    self.active = true
    schedule(10, start_after_identity_ready)
    return true
  end

  function self:stop()
    self.active = false
    stop_timer()
    self.next_retry_ms = 0
  end

  return self
end

return M
