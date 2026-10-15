local T = dofile((rawget(_G, "XIAOZHI_UI_APP_DIR") or "/sd/apps/xiaozhi") .. "/i18n.lua").translator()
local M = {}

local function json_escape(text)
  text = tostring(text or "")
  text = text:gsub("\\", "\\\\")
  text = text:gsub('"', '\\"')
  text = text:gsub("\n", "\\n")
  text = text:gsub("\r", "\\r")
  return text
end

local function json_pair(key, value)
  return '"' .. key .. '":"' .. json_escape(value) .. '"'
end

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

local function read_runtime_config(path)
  if not file or not file.getcontents or not sjson or not sjson.decode then
    return nil
  end
  local ok, raw = pcall(function()
    return file.getcontents(path)
  end)
  if not ok or type(raw) ~= "string" or raw == "" then
    return nil
  end
  local decoded, obj = pcall(sjson.decode, raw)
  if decoded and type(obj) == "table" then
    return obj
  end
  return nil
end

local function default_runtime_config(cfg)
  return {
    ota = {
      url = cfg.ota and cfg.ota.url or "",
      enabled = not (cfg.ota and cfg.ota.enabled == false),
      force = cfg.ota and cfg.ota.force == true or false,
      interval_ms = cfg.ota and cfg.ota.interval_ms or 3000,
      max_polls = cfg.ota and cfg.ota.max_polls or 80,
      timeout_ms = cfg.ota and cfg.ota.timeout_ms or 10000,
    },
    websocket = {
      url = cfg.websocket and cfg.websocket.url or "",
      token = cfg.websocket and cfg.websocket.token or "",
      version = cfg.websocket and cfg.websocket.version or 1,
    },
    audio = {
      sample_rate = cfg.AUDIO and cfg.AUDIO.rate or 16000,
      channels = cfg.AUDIO and cfg.AUDIO.channels or 1,
      frame_duration = cfg.AUDIO and cfg.AUDIO.frame_ms or 60,
      bitrate = cfg.AUDIO and cfg.AUDIO.bitrate or 12000,
    },
    wake_word = cfg.WAKE_WORD or "你好小智",
    timezone = cfg.TIMEZONE or "CST-8",
    ui = {
      type = cfg.UI_TYPE or (cfg.UI and cfg.UI.type) or "subtitle",
    },
  }
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
  }

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
    if not tmr or not tmr.create then
      fn()
      return
    end
    stop_timer()
    self.timer = tmr.create()
    self.timer:alarm(delay_ms, tmr.ALARM_SINGLE, fn)
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
    local code, body = http.post(ota_url, {
      headers = headers,
      timeout = self.cfg.ota.timeout_ms or 10000,
      bufsz = 8192,
      max_redirects = 3,
    }, body_text)
    print("[xiaozhi] ota status", tostring(code), "bytes=" .. tostring(body and #body or 0))
    if tonumber(code) ~= 200 then
      local n = tonumber(code) or -1
      return nil, "ota status " .. tostring(code) .. " " .. tostring(body or ""), false,
        n < 0 or n == 408 or n == 429 or n >= 500
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
    local code, body = http.post(normalize_activate_url(self.cfg.ota.url), {
      headers = headers,
      timeout = self.cfg.ota.timeout_ms or 10000,
      bufsz = 2048,
      max_redirects = 3,
    }, "{}")
    code = tonumber(code)
    if code == 200 then
      return "ok"
    end
    if code == 202 then
      return "pending"
    end
    return nil, "activate status " .. tostring(code) .. " " .. tostring(body or ""),
      not code or code < 0 or code == 408 or code == 429 or code >= 500
  end

  local function finish(ok, data)
    self.active = false
    stop_timer()
    emit(ok and "done" or "failed", data)
  end

  local check_again
  local poll_activate
  local start_after_identity_ready

  local function retry_network(err, fn)
    self.network_retries = self.network_retries + 1
    if self.network_retries > 5 then finish(false, err); return end
    emit("pending", {code=self.code, message=err, retry=self.network_retries})
    schedule(math.min(15000, 2000 * self.network_retries), fn)
  end

  start_after_identity_ready = function()
    if not self.active then
      return
    end
    local ident = identity(self.cfg)
    local id = ident.device_id()
    if not id or not ident.client_id(id) then
      emit("waiting_mac", "device mac unavailable")
      schedule(1000, start_after_identity_ready)
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
    local res, err, waiting_mac, transient = request_ota()
    if not self.active then return end
    if not res then
      if waiting_mac then
        emit("waiting_mac", err)
        schedule(1000, check_again)
        return
      end
      if transient then retry_network(err, check_again); return end
      finish(false, err)
      return
    end

    self.network_retries = 0
    local activation = res.activation or {}
    -- A fresh OTA response without activation means binding has completed.
    -- Never let the previous code mask newly returned websocket credentials.
    self.code = activation.code or ""
    self.challenge = activation.challenge or ""
    if self.code ~= "" or self.challenge ~= "" then
      self.pending_websocket = res.websocket or self.pending_websocket
    elseif apply_websocket(res.websocket) then
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
      finish(false, "ota response has no activation or websocket")
      return
    end

    schedule(self.cfg.ota.interval_ms or 3000, poll_activate)
  end

  poll_activate = function()
    if not self.active then
      return
    end
    self.poll_count = self.poll_count + 1
    if self.poll_count > (self.cfg.ota.max_polls or 80) then
      finish(false, "activation timeout")
      return
    end
    emit("pending", {
      code = self.code,
      count = self.poll_count,
      max = self.cfg.ota.max_polls or 80,
    })
    local status, err, transient = request_activate()
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
      if self.poll_count >= (self.cfg.ota.max_polls or 80) then
        finish(false, "activation timeout")
      else
        schedule(self.cfg.ota.interval_ms or 3000, poll_activate)
      end
      return
    end
    if transient then
      -- Recheck OTA after a transport failure: the user may have bound the code
      -- while this request was in flight.
      retry_network(err, check_again)
      return
    end
    finish(false, err)
  end

  function self:start(callback)
    self.callback = callback
    self.poll_count, self.network_retries = 0, 0
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
  end

  return self
end

return M
