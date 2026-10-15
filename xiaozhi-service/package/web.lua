local M = {}

local PAGE = nil


local function encode(value)
  local c = rawget(_G, "json") or rawget(_G, "sjson")
  if not c or not c.encode then return "{}" end
  local ok, raw = pcall(c.encode, value)
  return ok and raw or "{}"
end

local function decode(raw)
  local c = rawget(_G, "json") or rawget(_G, "sjson")
  if not c or not c.decode then return {} end
  local ok, value = pcall(c.decode, raw or "{}")
  return ok and type(value) == "table" and value or {}
end

local function request_json(req)
  local raw = req and (req.body or req.payload) or nil
  if not raw and req and req.getbody then
    local ok, value = pcall(req.getbody)
    if ok then raw = value end
  end
  return decode(raw)
end

local function response(status, typ, body)
  return { status = status, type = typ, headers = { ["cache-control"] = "no-store" }, body = body or "" }
end

local function json_response(status, body)
  return response(status, "application/json; charset=utf-8", encode(body))
end

function M.new(runtime, cfg)
  PAGE = file.getcontents(cfg.APP_DIR .. "/settings.html")
  local default_base = cfg and cfg.SERVICE_MODE and "/xiaozhi-service" or "/xiaozhi"
  local instance_base = (app and app.route_base and app.route_base()) or default_base
  local self = { routes = {}, base = default_base, instance_base = instance_base }

  local function register(method, path, fn)
    local err = httpd.dynamic(method, path, fn)
    if not err then self.routes[#self.routes + 1] = { method = method, path = path } end
  end

  function self:start()
    if not httpd or not httpd.dynamic then return false end
    pcall(function() httpd.start({ webroot = "/sd", auto_index = httpd.INDEX_NONE, max_handlers = 48 }) end)

    local function index()
      return response("200 OK", "text/html; charset=utf-8", PAGE)
    end

    local function state()
      return json_response("200 OK", runtime:snapshot())
    end

    local function volume(req)
      local doc = request_json(req)
      local saved, result = runtime:set_volume(tonumber(doc.volume))
      if not saved then return json_response("400 Bad Request", { ok = false, error = result }) end
      return json_response("200 OK", {ok=true})
    end

    local function server(req)
      local doc = request_json(req)
      if doc.keep_token == true then doc.token = cfg.websocket.token end
      local saved, result = runtime:set_server(doc.url, doc.token, doc.version, doc.ota_url or doc.otaUrl)
      if not saved then return json_response("400 Bad Request", { ok = false, error = result }) end
      result.ok = true
      return json_response("200 OK", result)
    end

    local function ui(req)
      local doc = request_json(req)
      local saved, result = runtime:set_ui_config(doc.app_ui_type, doc.service_ui_mode, doc.service_ui_type,
        doc.service_ui_character, doc.deny_apps, doc.session_idle_timeout_sec)
      if not saved then return json_response("400 Bad Request", { ok = false, error = result }) end
      result.ok = true
      return json_response("200 OK", result)
    end

    local function wake(req)
      local doc = request_json(req)
      local saved, result = runtime:set_wake_enabled(doc.enabled == true)
      if not saved then return json_response("400 Bad Request", { ok = false, error = result }) end
      result.ok = true
      return json_response("200 OK", result)
    end

    local function mac(req)
      local doc = request_json(req)
      local saved, result = runtime:set_device_mac(doc.mac)
      if not saved then return json_response("400 Bad Request", { ok = false, error = result }) end
      result.ok = true
      return json_response("202 Accepted", result)
    end

    local function repair(req)
      local ok, result = runtime:repair_pairing(request_json(req).new_identity == true)
      return json_response(ok and "202 Accepted" or "400 Bad Request", ok and {ok=true} or {error=result})
    end
    local function preferences(req)
      local ok, result = runtime:set_preferences(request_json(req))
      return json_response(ok and "202 Accepted" or "400 Bad Request", ok and {ok=true} or {error=result})
    end
    local function control(req)
      local ok, err = runtime:control_session(request_json(req).action)
      return json_response(ok and "202 Accepted" or "400 Bad Request", {ok=ok == true,error=err})
    end
    local function identity(req)
      local doc = request_json(req)
      local ok, result = runtime:manage_identity(doc.action, doc.value)
      return json_response(ok and "202 Accepted" or "400 Bad Request", ok and {ok=true} or {error=result})
    end

    local bases = { self.base }
    if self.instance_base ~= self.base then bases[#bases + 1] = self.instance_base end
    for _, base in ipairs(bases) do
      register(httpd.GET, base, index)
      register(httpd.GET, base .. "/", index)
      register(httpd.GET, base .. "/api/state", state)
      register(httpd.POST, base .. "/api/volume", volume)
      register(httpd.POST, base .. "/api/server", server)
      register(httpd.POST, base .. "/api/ui", ui)
      register(httpd.POST, base .. "/api/wake", wake)
      register(httpd.POST, base .. "/api/mac", mac)
      register(httpd.POST, base .. "/api/repair", repair)
      register(httpd.POST, base .. "/api/preferences", preferences)
      register(httpd.POST, base .. "/api/control", control)
      register(httpd.POST, base .. "/api/identity", identity)
    end
    if app and app.set_webui then pcall(function() app.set_webui(true) end) end
    return true
  end

  function self:stop()
    if httpd and httpd.unregister then
      for i = #self.routes, 1, -1 do
        local r = self.routes[i]
        pcall(httpd.unregister, r.method, r.path)
      end
    end
    self.routes = {}
  end

  return self
end

return M
