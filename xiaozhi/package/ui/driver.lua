local M = {}

local APP_DIR = rawget(_G, "XIAOZHI_UI_APP_DIR") or "/sd/apps/xiaozhi"
local SERVICE_DIR = rawget(_G, "XIAOZHI_SERVICE_DIR") or "/sd/apps/xiaozhi-service"

-- App UI styles live in /sd/apps/xiaozhi/ui/<name>.lua.
-- Floating UI styles live in /sd/apps/xiaozhi-service/ui/<name>.lua.
-- A style can either implement handle_event(event, payload) or keep the legacy
-- methods below; this driver is the stable event boundary used by runtime.lua.
local METHOD_BY_EVENT = {
  setup = "setup",
  stop = "stop",
  view_mode = "set_view_mode",
  metrics = "set_metrics",
  status_bar_tick = "update_status_bar",
  status = "set_status",
  notification = "show_notification",
  emotion = "set_emotion",
  chat_message = "set_chat_message",
  clear_chat = "clear_chat_messages",
  state = "on_state",
  alert = "alert",
}

local function safe_name(value)
  value = type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
  if value == "" or #value > 48 or not value:match("^[%w_.%-]+$") then
    return nil
  end
  return value
end

local function configured_mode(cfg)
  local ui = type(cfg and cfg.UI) == "table" and cfg.UI or {}
  local mode = safe_name(ui.type or cfg.UI_TYPE)
  if cfg and cfg.SERVICE_MODE then
    local service_mode = tostring(cfg.UI_MODE or "app")
    if service_mode == "floating" or service_mode == "service_ui" then
      return "float", mode or "subtitle"
    end
    return "root", "headless"
  end
  return "app", mode or "subtitle"
end

local function try_load(path)
  local ok, mod = pcall(dofile, path)
  if ok and type(mod) == "table" and type(mod.new) == "function" then
    return mod
  end
  return nil, mod
end

local function load_style(kind, name)
  name = safe_name(name) or "subtitle"
  kind = kind == "float" and "float" or (kind == "root" and "root" or "app")
  local paths = {}
  if kind == "root" then
    paths[#paths + 1] = APP_DIR .. "/ui/" .. name .. ".lua"
  elseif kind == "float" then
    paths[#paths + 1] = SERVICE_DIR .. "/ui/" .. name .. ".lua"
  else
    paths[#paths + 1] = APP_DIR .. "/ui/" .. name .. ".lua"
  end
  -- Compatibility with packages laid out during earlier UI directory migrations.
  if kind == "app" then
    paths[#paths + 1] = APP_DIR .. "/ui/app/" .. name .. ".lua"
  elseif kind == "float" then
    paths[#paths + 1] = APP_DIR .. "/ui/float/" .. name .. ".lua"
    paths[#paths + 1] = APP_DIR .. "/ui/floating_" .. name .. ".lua"
    paths[#paths + 1] = APP_DIR .. "/ui/floating.lua"
  end
  for i = 1, #paths do
    local mod = try_load(paths[i])
    if mod then return mod, name end
  end
  if kind ~= "root" or name ~= "headless" then
    return load_style("root", "headless")
  end
  error("[xiaozhi-ui] unable to load UI style " .. tostring(kind) .. "/" .. tostring(name))
end

local function call_method(target, method, payload)
  if type(target[method]) ~= "function" then return nil end
  if method == "set_chat_message" then
    return target[method](target, payload and payload.role, payload and payload.content)
  elseif method == "show_notification" then
    return target[method](target, payload and payload.text, payload and payload.duration_ms)
  elseif method == "alert" then
    return target[method](target, payload and payload.status, payload and payload.message, payload and payload.emotion)
  elseif method == "on_state" then
    return target[method](target, payload and payload.state, payload and payload.old_state)
  elseif method == "stop" then
    return target[method](target, payload and payload.reason)
  elseif method == "update_status_bar" then
    return target[method](target, payload and payload.force)
  elseif method == "set_status" then
    return target[method](target, payload and payload.status)
  elseif method == "set_emotion" then
    return target[method](target, payload and payload.emotion)
  elseif method == "set_view_mode" then
    return target[method](target, payload and payload.mode)
  elseif method == "set_metrics" then
    return target[method](target, payload and payload.metrics)
  end
  return target[method](target)
end

function M.new(cfg)
  local style_kind, configured_name = configured_mode(cfg)
  local style_mod, style_name = load_style(style_kind, configured_name)
  local impl = style_mod.new(cfg)
  local self = {
    impl = impl,
    kind = style_kind,
    style = style_name,
    suppressed = false,
  }

  function self:emit(event, payload)
    payload = type(payload) == "table" and payload or {}
    if self.suppressed and event ~= "setup" and event ~= "stop" then
      return true, "suppressed"
    end
    if type(impl.handle_event) == "function" then
      local ok, handled, result = pcall(function()
        return impl:handle_event(event, payload)
      end)
      if ok and handled == true then return true, result end
      if not ok then print("[xiaozhi-ui] event failed", tostring(event), tostring(handled)) end
    end
    local method = METHOD_BY_EVENT[event]
    if method then
      local ok, result = pcall(call_method, impl, method, payload)
      if ok then return true, result end
      print("[xiaozhi-ui] method failed", tostring(method), tostring(result))
      return false, result
    end
    return false, "unknown ui event"
  end

  function self:setup() return self:emit("setup") end
  function self:stop(reason) return self:emit("stop", { reason = reason }) end
  function self:set_view_mode(mode) return self:emit("view_mode", { mode = mode }) end
  function self:set_metrics(metrics) return self:emit("metrics", { metrics = metrics or {} }) end
  function self:update_status_bar(force) return self:emit("status_bar_tick", { force = force }) end
  function self:set_status(status) return self:emit("status", { status = status }) end
  function self:show_notification(text, duration_ms)
    return self:emit("notification", { text = text, duration_ms = duration_ms })
  end
  function self:set_emotion(emotion) return self:emit("emotion", { emotion = emotion }) end
  function self:set_chat_message(role, content)
    return self:emit("chat_message", { role = role, content = content })
  end
  function self:clear_chat_messages() return self:emit("clear_chat") end
  function self:on_state(state, old_state)
    return self:emit("state", { state = state, old_state = old_state })
  end
  function self:alert(status, message, emotion)
    return self:emit("alert", { status = status, message = message, emotion = emotion })
  end
  function self:set_suppressed(suppressed)
    suppressed = suppressed == true
    if self.suppressed == suppressed then return true end
    self.suppressed = suppressed
    if suppressed then
      return self:emit("stop", { reason = "suppressed" })
    end
    return self:emit("setup")
  end
  function self:diagnostics()
    local diag = type(impl.diagnostics) == "function" and impl:diagnostics() or {}
    diag = type(diag) == "table" and diag or {}
    diag.kind = self.kind
    diag.style = self.style
    diag.suppressed = self.suppressed
    return diag
  end

  return self
end

return M
