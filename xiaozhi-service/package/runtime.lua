local M = {}

function M.new(cfg, load_module)
  local State = load_module("state")
  local Ui = load_module(cfg.SERVICE_MODE and "service_ui" or "ui")
  local Audio = load_module("audio")
  local Protocol = load_module("protocol")
  local Activation = load_module("activation")
  local Mcp = load_module("mcp")
  local XIAOZHI_WAKE_CONFIG_PATH = "/sd/apps/xiaozhi-service/service.json"
  local XIAOZHI_WAKE_CONFIG_EXAMPLE_PATH = "/sd/apps/xiaozhi-service/service.example.json"
  local XIAOZHI_WAKE_TARGET_PATH = "/sd/apps/xiaozhi_wake/target_app_id.txt"
  local XIAOZHI_GUARD_DIR = "/sd/apps/xiaozhi-service-guard"
  local XIAOZHI_GUARD_INFO_PATH = XIAOZHI_GUARD_DIR .. "/app.info"
  local XIAOZHI_GUARD_MAIN_PATH = XIAOZHI_GUARD_DIR .. "/main.lua"

  local XIAOZHI_GUARD_INFO = [=[name = XiaoZhi Guard
kind = service
entry = main.lua
allow_webui = false
autostart_service = true
description = Temporary foreground guard created by XiaoZhi
version = 1.0.0
]=]

  local XIAOZHI_GUARD_MAIN = [=[local previous = rawget(_G, "XIAOZHI_GUARD")
if previous and previous.stop then pcall(previous.stop, "reload") end

local SERVICE_ID = "xiaozhi-service"
local GUARD_ID = "xiaozhi-service-guard"
local GUARD_DIR = "/sd/apps/xiaozhi-service-guard"
local INFO_PATH = GUARD_DIR .. "/app.info"
local MAIN_PATH = "/sd/apps/xiaozhi-service-guard/main.lua"
local CONFIG_PATH = "/sd/apps/xiaozhi-service/service.json"
local CONFIG_EXAMPLE_PATH = "/sd/apps/xiaozhi-service/service.example.json"
local POLL_MS = 5000

local guard = {
  timer = nil,
  confirm_timer = nil,
  stopped = false,
  finishing = false,
  awaiting_start = false,
  confirm_attempts = 0,
}

local function decode(raw)
  local codec = rawget(_G, "json") or rawget(_G, "sjson")
  if type(raw) ~= "string" or raw == "" or not codec or not codec.decode then return nil end
  local ok, value = pcall(codec.decode, raw)
  return ok and type(value) == "table" and value or nil
end

local function read_text(path)
  if not file or not file.getcontents then return nil end
  local ok, value = pcall(file.getcontents, path)
  return ok and type(value) == "string" and value or nil
end

local config = decode(read_text(CONFIG_PATH))
  or decode(read_text(CONFIG_EXAMPLE_PATH))
  or { enabled = true, deny_apps = {} }
local deny_apps = type(config.deny_apps) == "table" and config.deny_apps or {}

local function foreground_app_id()
  if not app or not app.list then return nil end
  local ok, apps = pcall(app.list)
  if not ok or type(apps) ~= "table" then return nil end
  for _, record in ipairs(apps) do
    if type(record) == "table" and record.running == true then return record.id end
  end
  return "launcher"
end

local function service_running(id)
  if not app or not app.services then return nil end
  local ok, services = pcall(app.services)
  if not ok or type(services) ~= "table" then return nil end
  for _, record in ipairs(services) do
    if type(record) == "table" and record.id == id then return true end
  end
  return false
end

local function stop_confirm_timer()
  if not guard.confirm_timer then return end
  pcall(function() guard.confirm_timer:stop() end)
  pcall(function() guard.confirm_timer:unregister() end)
  guard.confirm_timer = nil
end

local function finish_guard()
  if guard.stopped or guard.finishing then return end
  guard.finishing = true

  local function remove_if_present(path)
    if not file or not file.stat or not file.remove then return false end
    local ok_stat, stat = pcall(file.stat, path)
    if ok_stat and type(stat) ~= "table" then return true end
    local ok_remove, removed = pcall(file.remove, path)
    return ok_remove and removed ~= false
  end

  if not remove_if_present(MAIN_PATH) or not remove_if_present(INFO_PATH) then
    print("[xiaozhi_guard] temporary files removal failed; will retry")
    guard.finishing = false
    return
  end
  if file and file.rmdir then pcall(file.rmdir, GUARD_DIR) end

  local ok_rescan, rescanned, rescan_err = pcall(app.rescan)
  if not ok_rescan or not rescanned then
    print("[xiaozhi_guard] catalog rescan failed; will retry", tostring(rescan_err or rescanned or ""))
    guard.finishing = false
    return
  end

  local ok_stop, stopped, stop_err = pcall(app.stop_service, GUARD_ID)
  if not ok_stop or not stopped then
    print("[xiaozhi_guard] self-stop failed; will retry", tostring(stop_err or stopped or ""))
    guard.finishing = false
    return
  end
  guard.stopped = true
  stop_confirm_timer()
  if guard.timer then
    pcall(function() guard.timer:stop() end)
    pcall(function() guard.timer:unregister() end)
    guard.timer = nil
  end
  print("[xiaozhi_guard] temporary package removed")
end

local function confirm_xiaozhi()
  if service_running(SERVICE_ID) == true then
    print("[xiaozhi_guard] xiaozhi running; removing temporary guard")
    finish_guard()
    return
  end
  guard.confirm_attempts = guard.confirm_attempts + 1
  if guard.confirm_attempts >= 20 then
    print("[xiaozhi_guard] xiaozhi start confirmation timed out; will retry")
    stop_confirm_timer()
    guard.awaiting_start = false
  end
end

local function schedule_confirmation()
  if guard.confirm_timer or not tmr or not tmr.create then return end
  guard.confirm_timer = tmr.create()
  guard.confirm_timer:alarm(500, tmr.ALARM_AUTO, confirm_xiaozhi)
end

function guard.poll()
  if guard.stopped then return end
  local foreground = foreground_app_id()
  if not foreground then return end
  local denied = config.enabled == false or deny_apps[foreground] == true
  if denied then return end

  if service_running(SERVICE_ID) == true then
    finish_guard()
    return
  end
  if guard.awaiting_start then return end
  local ok, started, err = pcall(app.start_service, SERVICE_ID)
  if ok and started then
    guard.awaiting_start = true
    guard.confirm_attempts = 0
    print("[xiaozhi_guard] xiaozhi start requested")
    schedule_confirmation()
  else
    print("[xiaozhi_guard] xiaozhi start failed", tostring(err or started or ""))
  end
end

function guard.stop(reason)
  if guard.stopped then return end
  guard.stopped = true
  stop_confirm_timer()
  if guard.timer then
    pcall(function() guard.timer:stop() end)
    pcall(function() guard.timer:unregister() end)
    guard.timer = nil
  end
  print("[xiaozhi_guard] stop", tostring(reason or ""))
end

XIAOZHI_GUARD = guard
-- The creator may have only queued an app launch. Waiting for the first normal
-- 5-second poll prevents an allowed launcher frame from destroying the guard
-- before the denied foreground app is actually active.
if tmr and tmr.create then
  guard.timer = tmr.create()
  guard.timer:alarm(POLL_MS, tmr.ALARM_AUTO, guard.poll)
end
]=]

  local self = {
    cfg = cfg,
    state = State.new(),
    ui = Ui.new(cfg),
    audio = nil,
    protocol = nil,
    activation = nil,
    mcp = nil,
    timer = nil,
    wake_open_timer = nil,
    external_return_timer = nil,
    listening_mode = State.LISTEN_AUTO,
    pending_wake_word = nil,
    startup_wake_word = nil,
    startup_wake_from_service = false,
    return_app_id = nil,
    external_wake_active = false,
    foreground_check_ticks = 0,
    activation_status = "启动中",
    activation_message = "",
    pairing_code = "",
    pending_goodbye = false,
    tts_text_ready = false,
    tts_audio_queue = {},
    tts_audio_timer = nil,
    web = nil,
    stopped = false,
  }

  local function wake_service()
    return rawget(_G, "XIAOZHI_WAKE_SERVICE")
  end

  local function codec()
    return rawget(_G, "json") or rawget(_G, "sjson")
  end

  local function decode(raw)
    local lib = codec()
    if type(raw) ~= "string" or raw == "" or not lib or not lib.decode then return nil end
    local ok, value = pcall(lib.decode, raw)
    if ok and type(value) == "table" then return value end
    return nil
  end

  local function read_text(path)
    if file and file.getcontents then
      local ok, raw = pcall(function() return file.getcontents(path) end)
      if ok and type(raw) == "string" then return raw end
    end
    local fd = file and file.open and file.open(path, "r")
    if not fd then return nil end
    local raw = fd:read(8192)
    fd:close()
    return raw
  end

  local function write_text(path, raw)
    if file and file.putcontents then
      local ok, ret = pcall(function() return file.putcontents(path, raw) end)
      if ok and ret ~= false and ret ~= nil then return true end
    end
    local fd = file and file.open and file.open(path, "w+")
    if not fd then return false end
    local written = fd:write(raw)
    if fd.flush then pcall(function() fd:flush() end) end
    fd:close()
    return written and true or false
  end

  local function read_wake_service_config()
    return decode(read_text(XIAOZHI_WAKE_CONFIG_PATH))
      or decode(read_text(XIAOZHI_WAKE_CONFIG_EXAMPLE_PATH))
      or cfg.wake_service
      or {}
  end

  local function wake_service_enabled()
    local wake_cfg = read_wake_service_config()
    return type(wake_cfg) == "table" and wake_cfg.enabled == true
  end

  local function foreground_denies_service()
    if not cfg.SERVICE_MODE or not http or not http.get then return false end
    local ok, code, body = pcall(function()
      return http.get("http://127.0.0.1/api/system/state", { timeout = 500, bufsz = 1024 })
    end)
    if not ok or tonumber(code) ~= 200 then return false end
    local state = decode(body)
    local current = state and state.current_app or nil
    local app_id = type(current) == "table" and current.id or nil
    local wake_cfg = read_wake_service_config()
    return type(app_id) == "string"
      and type(wake_cfg.deny_apps) == "table"
      and wake_cfg.deny_apps[app_id] == true, app_id
  end

  local function service_running(id)
    if not app or not app.services then return false end
    local ok, services = pcall(app.services)
    if not ok or type(services) ~= "table" then return false end
    for _, record in ipairs(services) do
      if type(record) == "table" and record.id == id then return true end
    end
    return false
  end

  local function ensure_temporary_guard()
    if service_running("xiaozhi-service-guard") then return true end
    if not file or not file.mkdir or not app or not app.rescan then
      return false, "guard APIs unavailable"
    end

    local stat = file.stat and file.stat(XIAOZHI_GUARD_DIR) or nil
    if type(stat) ~= "table" then
      local ok_mkdir, made = pcall(file.mkdir, XIAOZHI_GUARD_DIR)
      if not ok_mkdir or made == false then return false, "guard mkdir failed" end
    end

    -- Write the entry first and the manifest last, so a rescan can never see a
    -- half-created service package.
    if not write_text(XIAOZHI_GUARD_MAIN_PATH, XIAOZHI_GUARD_MAIN) then
      return false, "guard main write failed"
    end
    if not write_text(XIAOZHI_GUARD_INFO_PATH, XIAOZHI_GUARD_INFO) then
      return false, "guard manifest write failed"
    end

    local ok_rescan, rescanned, rescan_err = pcall(app.rescan)
    if not ok_rescan or not rescanned then
      return false, rescan_err or rescanned or "guard rescan failed"
    end
    if service_running("xiaozhi-service-guard") then return true end

    if app.start_service then
      local ok_start, started, start_err = pcall(app.start_service, "xiaozhi-service-guard")
      if not ok_start or not started then
        return false, start_err or started or "guard start failed"
      end
    end
    return false, "guard start pending"
  end

  local function stop_xiaozhi_with_guard(owner_app_id)
    local guard_ready, guard_err = ensure_temporary_guard()
    if not guard_ready then
      print("[xiaozhi] keep running; temporary guard unavailable", tostring(guard_err or ""))
      return false
    end
    if not app or not app.stop_service then
      print("[xiaozhi] keep running; stop_service unavailable")
      return false
    end
    print("[xiaozhi] temporary guard ready; stopping service", tostring(owner_app_id or ""))
    local ok, stopped, stop_err = pcall(app.stop_service, "xiaozhi-service")
    if not ok or not stopped then
      print("[xiaozhi] stop request failed", tostring(stop_err or stopped or ""))
      return false
    end
    return true
  end

  local function start_wake_service_for_app(app_id)
    if not wake_service_enabled() or not app or not app.start_service then
      return nil
    end
    app_id = type(app_id) == "string" and app_id ~= "" and app_id or "launcher"
    _G.XIAOZHI_WAKE_TARGET_APP_ID = app_id
    write_text(XIAOZHI_WAKE_TARGET_PATH, app_id)
    local ok, started = pcall(function() return app.start_service("xiaozhi_wake") end)
    if ok and type(started) == "table" then return started end
    return wake_service()
  end

  local function encode(value)
    if not sjson or not sjson.encode then return nil end
    local ok, raw = pcall(sjson.encode, value)
    if ok and type(raw) == "string" then return raw end
    return nil
  end

  local function post_wake_control(path, payload)
    if not http or not http.post then return false end
    payload = payload or { source = "xiaozhi-ui" }
    payload.source = "xiaozhi-ui"
    local raw = encode(payload) or '{"source":"xiaozhi-ui"}'
    local ok, code = pcall(function()
      return http.post("http://127.0.0.1" .. path, {
        headers = { ["Content-Type"] = "application/json" },
        timeout = 1200,
        bufsz = 512,
        max_redirects = 0,
      }, raw)
    end)
    return ok and tonumber(code) == 200
  end

  local function notify_wake_service_for_app(app_id, allow_wake_service, delay_ms)
    if cfg.SERVICE_MODE then return false end
    local service = wake_service()
    if (not service or service.stopped) and allow_wake_service ~= false then
      service = start_wake_service_for_app(app_id)
    end
    if service and service.resume_for_app then
      pcall(function() service:resume_for_app(app_id, allow_wake_service, delay_ms or 1200) end)
      return true
    end
    return post_wake_control("/xiaozhi_wake/api/audio/resume", {
      target_app_id = app_id,
      allow_wake_service = allow_wake_service,
      delay_ms = delay_ms or 1200,
    })
  end

  local function stop_wake_service_now(reason)
    local service = wake_service()
    if service and service.stop then
      pcall(function() service:stop(reason or "foreground xiaozhi") end)
    end
    if app and app.stop_service then
      pcall(function() app.stop_service("xiaozhi_wake") end)
    end
  end

  local function take_service_wake_remote()
    if not http or not http.post then return nil, nil end
    local ok, code, body = pcall(function()
      return http.post("http://127.0.0.1/xiaozhi_wake/api/wake/take", {
        headers = { ["Content-Type"] = "application/json" },
        timeout = 1200,
        bufsz = 512,
        max_redirects = 0,
      }, '{"source":"xiaozhi-ui"}')
    end)
    if not ok or tonumber(code) ~= 200 or type(body) ~= "string" then return nil, nil end
    if sjson and sjson.decode then
      local decoded, value = pcall(sjson.decode, body)
      if decoded and type(value) == "table" and type(value.wake_word) == "string" then
        return value.wake_word, type(value.return_app_id) == "string" and value.return_app_id or nil
      end
    end
    return body:match('"wake_word"%s*:%s*"([^"]+)"'),
      body:match('"return_app_id"%s*:%s*"([^"]+)"')
  end

  local function returnable_app_id(app_id)
    if type(app_id) ~= "string" or app_id == "" then return nil end
    if app_id == "launcher" or app_id == "xiaozhi-service" or app_id == "xiaozhi_wake" then return nil end
    return app_id
  end

  local function consume_service_wake()
    local service = wake_service()
    if service and service.take_pending_wake then
      local ok, wake_word, return_app_id = pcall(function() return service:take_pending_wake() end)
      if ok and wake_word then
        self.startup_wake_word = wake_word
        if service.active_app_id == "launcher" then
          self.return_app_id = nil
        else
          self.return_app_id = returnable_app_id(return_app_id)
            or returnable_app_id(service.active_app_id)
            or returnable_app_id(service.last_returnable_app_id)
        end
        self.startup_wake_from_service = true
        print("[xiaozhi] service wake return", tostring(self.return_app_id or ""))
      end
    end
    if service and service.suspend then
      pcall(function()
        service.foreground_owner = true
        service.active_app_id = "xiaozhi-service"
        service:suspend("foreground xiaozhi")
      end)
    else
      post_wake_control("/xiaozhi_wake/api/audio/release")
    end
    if not self.startup_wake_word then
      self.startup_wake_word, self.return_app_id = take_service_wake_remote()
      self.return_app_id = returnable_app_id(self.return_app_id)
      if self.startup_wake_word then
        self.startup_wake_from_service = true
        print("[xiaozhi] service wake return", tostring(self.return_app_id or ""))
      end
    end
    stop_wake_service_now("foreground xiaozhi")
  end

  local function set_state(to)
    return self.state:set(to)
  end

  local function refresh_metrics()
    if not self.ui then
      return
    end
    local ai = self.audio and self.audio:info() or {}
    local pi = self.protocol and self.protocol:info() or {}
    local wake = "OFF"
    if ai.wake_ready then
      wake = "READY"
    elseif ai.wake_missing then
      wake = "MISS"
    end
    local network = pi.opened and "WS" or (pi.connected and "NET" or "NET")
    local counter = "lv " .. tostring(ai.level or 0) ..
      "  det " .. tostring(ai.detect_count or 0) ..
      "  tx " .. tostring(ai.send_frames or 0) ..
      "  rx " .. tostring(ai.play_count or 0)
    self.ui:set_metrics({
      network = network,
      audio = (ai.mode or "off"),
      wake = wake,
      counter = counter,
    })
  end

  local function alert(status, message, emotion)
    self.ui:alert(status or "错误", message or "", emotion or "circle_xmark")
  end

  local function open_audio_channel_now()
    local ok = self.protocol:open_audio_channel()
    if not ok then
      local msg = self.protocol.last_error or "server not connected"
      if msg == "websocket config missing" then
        msg = "未配置 websocket"
      end
      alert("连接失败", msg, "cloud_slash")
      set_state(State.IDLE)
      return false
    end
    return true
  end

  local function open_audio_channel()
    if not self.protocol then
      alert("错误", "protocol missing", "circle_xmark")
      set_state(State.IDLE)
      return false
    end
    if self.protocol:is_audio_channel_opened() then
      set_state(State.LISTENING)
      return true
    end
    set_state(State.CONNECTING)
    self.ui:set_chat_message("system", "")
    return open_audio_channel_now()
  end

  local function open_audio_channel_deferred()
    if not self.protocol then
      alert("错误", "protocol missing", "circle_xmark")
      set_state(State.IDLE)
      return false
    end
    if self.protocol:is_audio_channel_opened() then
      set_state(State.LISTENING)
      return true
    end
    set_state(State.CONNECTING)
    self.ui:set_chat_message("system", "")
    if self.wake_open_timer then
      pcall(function() self.wake_open_timer:stop() end)
      pcall(function() self.wake_open_timer:unregister() end)
      self.wake_open_timer = nil
    end
    if tmr and tmr.create then
      self.wake_open_timer = tmr.create()
      self.wake_open_timer:alarm(1, tmr.ALARM_SINGLE, function()
        self.wake_open_timer = nil
        if not self.stopped and self.state.state == State.CONNECTING then
          open_audio_channel_now()
        end
      end)
      return true
    end
    return open_audio_channel_now()
  end

  local function start_listening(mode)
    self.listening_mode = mode or State.LISTEN_AUTO
    local s = self.state.state
    if s == State.IDLE then
      return open_audio_channel()
    elseif s == State.SPEAKING then
      self.protocol:send_abort_speaking("none")
      set_state(State.LISTENING)
      return true
    elseif s == State.LISTENING then
      return true
    end
    return false
  end

  local function stop_listening()
    local s = self.state.state
    if s == State.LISTENING and self.protocol then
      self.protocol:send_stop_listening()
      set_state(State.IDLE)
    elseif s == State.SPEAKING and self.protocol then
      self.protocol:send_abort_speaking("none")
      set_state(State.IDLE)
    elseif s == State.CONNECTING and self.protocol then
      self.protocol:close_audio_channel(false)
      set_state(State.IDLE)
    end
  end

  local function wake_word_invoke(wake_word)
    local s = self.state.state
    print("[xiaozhi] wake detected", tostring(wake_word), "state=" .. tostring(s))
    if self.startup_wake_from_service or self.return_app_id then
      self.external_wake_active = true
      self.startup_wake_from_service = false
    end
    self.pending_wake_word = wake_word or cfg.WAKE_WORD
    if s == State.IDLE then
      self.ui:show_notification("你好小智", 1200)
      -- Make the service overlay visible before touching I2S/network state.
      -- A capture handoff failure must not swallow the wake UI notification.
      local bridge_ok, bridging = pcall(function()
        return self.audio:begin_wake_bridge()
      end)
      if not bridge_ok or not bridging then
        pcall(function() self.audio:stop_i2s() end)
      end
      return open_audio_channel_deferred()
    elseif s == State.SPEAKING or s == State.LISTENING then
      if self.protocol then
        self.protocol:send_abort_speaking("wake_word_detected")
      end
      set_state(State.LISTENING)
    elseif s == State.ACTIVATING then
      set_state(State.IDLE)
    end
    return true
  end

  local function toggle_chat()
    local s = self.state.state
    if s == State.IDLE then
      start_listening(State.LISTEN_AUTO)
    elseif s == State.SPEAKING then
      if self.protocol then
        self.protocol:send_abort_speaking("none")
      end
      set_state(State.IDLE)
    elseif s == State.LISTENING or s == State.CONNECTING then
      stop_listening()
    elseif s == State.ACTIVATING then
      set_state(State.IDLE)
    end
  end

  local function cancel_external_return()
    local timer = self.external_return_timer
    self.external_return_timer = nil
    if timer then
      pcall(function() timer:stop() end)
      pcall(function() timer:unregister() end)
    end
  end

  local function launch_app_from_ui(app_id, allow_wake_service, reason)
    print("[xiaozhi] app launch request", tostring(reason or ""), tostring(app_id or ""))
    if type(app_id) ~= "string" or app_id == "" or app_id == "launcher" then
      if cfg.SERVICE_MODE then
        if self.ui and self.ui.on_state then self.ui:on_state(State.IDLE) end
        if self.audio then self.audio:set_mode("wake") end
      else
        notify_wake_service_for_app("launcher", nil, 800)
      end
      if not cfg.SERVICE_MODE and app and app.exit then
        local ok, err = pcall(app.exit)
        if not ok then print("[xiaozhi] launcher return exit failed", tostring(err)) end
      end
      return false
    end
    if app_id == "xiaozhi-service" or app_id == "xiaozhi_wake" then
      notify_wake_service_for_app("launcher", nil, 800)
      return false
    end
    cancel_external_return()
    if self.audio then self.audio:set_mode("off") end
    if not cfg.SERVICE_MODE then
      notify_wake_service_for_app(app_id, allow_wake_service, 1200)
    end
    local function do_launch()
      if self.stopped then
        print("[xiaozhi] app launch skipped stopped", tostring(reason or ""), tostring(app_id))
        return
      end
      local ok, err = app and app.launch and app.launch(app_id)
      print("[xiaozhi] app launch", tostring(reason or ""), tostring(app_id), tostring(ok), tostring(err or ""))
      if cfg.SERVICE_MODE and ok then
        if allow_wake_service == false then
          -- High-load/audio-owner apps must get the codec and native modules exclusively.
          -- Stop only after app.launch returns so the MCP result survives, and
          -- never stop unless a temporary recovery guard is already running.
          stop_xiaozhi_with_guard(app_id)
        elseif self.audio then
          self.audio:set_mode("wake")
        end
      end
    end
    if tmr and tmr.create then
      local timer = tmr.create()
      timer:alarm(500, tmr.ALARM_SINGLE, function(instance)
        pcall(function() instance:unregister() end)
        do_launch()
      end)
    else
      do_launch()
    end
    return true
  end

  local function return_to_origin()
    local app_id = self.return_app_id
    self.return_app_id = nil
    self.external_wake_active = false
    launch_app_from_ui(app_id, nil, "external wake return")
  end

  local function schedule_external_return()
    cancel_external_return()
    if not self.external_wake_active then return end
    if not tmr or not tmr.create then return end
    local timer = tmr.create()
    self.external_return_timer = timer
    timer:alarm(8000, tmr.ALARM_SINGLE, function(instance)
      pcall(function() instance:unregister() end)
      if self.external_return_timer ~= timer then return end
      self.external_return_timer = nil
      if self.external_wake_active
          and (self.state.state == State.LISTENING or self.state.state == State.SPEAKING) then
        stop_listening()
      end
    end)
  end

  local function on_state_changed(old_state, new_state)
    self.ui:on_state(new_state)
    if new_state == State.IDLE then
      self.ui:clear_chat_messages()
      -- Release the WebSocket task/queues before asking I2S for contiguous DMA RAM.
      if self.protocol and self.protocol:is_audio_channel_opened() then
        self.protocol:close_audio_channel(false)
      end
      if self.external_wake_active then
        self.audio:set_mode("off")
      else
        self.audio:set_mode("wake")
      end
    elseif new_state == State.CONNECTING then
      if not self.audio:is_wake_bridge() then
        self.audio:set_mode("off")
      end
    elseif new_state == State.LISTENING then
      if self.pending_wake_word and self.protocol then
        self.protocol:send_wake_word_detected(self.pending_wake_word)
        self.pending_wake_word = nil
      end
      if self.protocol then
        self.protocol:send_start_listening(self.listening_mode)
      end
      self.audio:set_mode("listen")
    elseif new_state == State.SPEAKING then
      self.audio:set_mode("speak")
    elseif new_state == State.FATAL_ERROR then
      self.audio:set_mode("off")
    end
    refresh_metrics()
    if new_state == State.IDLE and self.external_wake_active
        and (old_state == State.CONNECTING or old_state == State.LISTENING or old_state == State.SPEAKING) then
      return_to_origin()
    end
  end

  local function cancel_tts_audio_timer()
    if self.tts_audio_timer then
      pcall(function() self.tts_audio_timer:unregister() end)
      self.tts_audio_timer = nil
    end
  end

  local function flush_tts_audio()
    cancel_tts_audio_timer()
    local queue = self.tts_audio_queue
    self.tts_audio_queue = {}
    if not self.audio then return end
    for i = 1, #queue do
      self.audio:play_opus(queue[i])
    end
  end

  local function schedule_tts_audio_flush()
    if self.tts_audio_timer or not tmr or not tmr.create then return end
    local timer = tmr.create()
    self.tts_audio_timer = timer
    timer:alarm(tonumber(cfg.AUDIO.tts_text_lead_ms) or 180, tmr.ALARM_SINGLE, function(instance)
      pcall(function() instance:unregister() end)
      if self.tts_audio_timer == timer then self.tts_audio_timer = nil end
      self.tts_text_ready = true
      flush_tts_audio()
    end)
  end

  local function bind_protocol()
    self.protocol:on("opened", function()
      if self.state.state == State.CONNECTING then
        set_state(State.LISTENING)
      end
    end)
    self.protocol:on("closed", function()
      if self.state.state == State.CONNECTING or self.state.state == State.LISTENING or self.state.state == State.SPEAKING then
        set_state(State.IDLE)
      end
    end)
    self.protocol:on("error", function(message)
      alert("错误", message, "cloud_slash")
      if self.state.state == State.CONNECTING then
        set_state(State.IDLE)
      end
    end)
    self.protocol:on("audio", function(opus)
      if self.external_return_timer then schedule_external_return() end
      if self.state.state ~= State.SPEAKING then
        set_state(State.SPEAKING)
      end
      if not self.tts_text_ready then
        local max_frames = tonumber(cfg.AUDIO.tts_audio_lead_frames) or 3
        if #self.tts_audio_queue < max_frames then
          self.tts_audio_queue[#self.tts_audio_queue + 1] = opus
          schedule_tts_audio_flush()
          return
        end
        self.tts_text_ready = true
        flush_tts_audio()
      end
      self.audio:play_opus(opus)
    end)
    self.protocol:on("tts_start", function()
      cancel_external_return()
      cancel_tts_audio_timer()
      self.tts_text_ready = false
      self.tts_audio_queue = {}
      set_state(State.SPEAKING)
    end)
    self.protocol:on("tts_stop", function()
      flush_tts_audio()
      if self.pending_goodbye then
        self.pending_goodbye = false
        set_state(State.IDLE)
      elseif self.external_wake_active then
        set_state(State.LISTENING)
        schedule_external_return()
      elseif self.listening_mode == State.LISTEN_MANUAL then
        set_state(State.IDLE)
      else
        set_state(State.LISTENING)
      end
    end)
    self.protocol:on("chat", function(role, text)
      if role == "user" then cancel_external_return() end
      self.ui:set_chat_message(role, text)
      if role == "assistant" and type(text) == "string" then
        self.tts_text_ready = true
        flush_tts_audio()
        local lower = text:lower()
        if text:find("拜拜", 1, true) or text:find("再见", 1, true)
            or text:find("下次见", 1, true) or lower:find("goodbye", 1, true)
            or lower:find("bye bye", 1, true) then
          self.pending_goodbye = true
        end
      end
    end)
    self.protocol:on("emotion", function(emotion)
      self.ui:set_emotion(emotion)
    end)
    self.protocol:on("alert", function(status, message, emotion)
      alert(status, message, emotion)
    end)
    self.protocol:on("mcp", function(payload)
      if self.mcp then
        self.mcp:handle(payload)
      end
    end)
  end

  local function bind_audio()
    self.audio.on_wake = wake_word_invoke
    self.audio.on_send = function(opus)
      if self.protocol and self.protocol:is_audio_channel_opened() then
        pcall(function()
          self.protocol:send_audio(opus)
        end)
      end
    end
    self.audio.on_error = function(message)
      if message == "wake model missing" then
        self.ui:show_notification("缺少唤醒模型", 2500)
      else
        self.ui:show_notification(message, 2500)
      end
    end
  end

  local function start_activation()
    if self.activation then
      self.activation:stop()
      self.activation = nil
    end
    self.activation = Activation.new(cfg)
    local started = self.activation:start(function(event, data)
      self.activation_status = tostring(event or "")
      if type(data) == "table" then
        self.pairing_code = tostring(data.code or self.pairing_code or "")
        self.activation_message = tostring(data.message or "")
      elseif type(data) == "string" then
        self.activation_message = data
      end
      if event == "need_config" then
        self.ui:set_chat_message("system", data or "未配置 ota.url")
      elseif event == "checking" then
        set_state(State.ACTIVATING)
        self.ui:set_status("检查 OTA")
        self.ui:set_chat_message("system", "正在向小智服务端申请验证码")
      elseif event == "code" then
        set_state(State.ACTIVATING)
        local code = data and data.code or ""
        self.ui:set_emotion("thinking")
        if code ~= "" then
          self.ui:set_status("验证码 " .. code)
          self.ui:set_chat_message("system", "后台添加设备输入验证码 " .. code)
          self.ui:show_notification("验证码 " .. code, 2500)
        else
          self.ui:set_status("等待绑定")
          self.ui:set_chat_message("system", data and data.message or "等待后台设备绑定")
        end
      elseif event == "pending" then
        local code = data and data.code or ""
        if code ~= "" then
          self.ui:set_status("验证码 " .. code)
        else
          self.ui:set_status("等待绑定")
        end
      elseif event == "activated" then
        self.ui:show_notification("绑定成功", 1600)
        self.ui:set_chat_message("system", "绑定成功，正在读取服务配置")
      elseif event == "done" then
        self.protocol:start()
        self.ui:show_notification("小智已就绪", 1600)
        set_state(State.IDLE)
        if self.startup_wake_word then
          local wake_word = self.startup_wake_word
          self.startup_wake_word = nil
          wake_word_invoke(wake_word)
        end
        refresh_metrics()
      elseif event == "failed" then
        alert("激活失败", data or "activation failed", "cloud_slash")
        set_state(State.IDLE)
        refresh_metrics()
      end
    end)
    return started
  end

  local function bind_keys()
    if cfg.SERVICE_MODE then return end
    if not key or not key.on then
      return
    end
    local down = key.DOWN or rawget(_G, "KEY_DOWN")
    local left = key.LEFT or rawget(_G, "KEY_LEFT")
    local right = key.RIGHT or rawget(_G, "KEY_RIGHT")
    local short = key.SHORT or rawget(_G, "KEY_EVENT_SHORT")
    local start = key.START or rawget(_G, "KEY_EVENT_START")
    local long_start = key.LONG_START or rawget(_G, "KEY_EVENT_LONG_START")
    local long_repeat = key.LONG_REPEAT or rawget(_G, "KEY_EVENT_LONG_REPEAT")
    local function fire(evt)
      return evt == short or evt == start
    end
    local function long_fire(evt)
      return evt == long_start or evt == long_repeat
    end
    if down then
      pcall(function()
        key.on(down, function(evt)
          if fire(evt) then toggle_chat() end
        end)
      end)
    end
    if left then
      pcall(function()
        key.on(left, function(evt)
          if long_fire(evt) then
            self.ui:set_view_mode("default")
          elseif evt == short then
            start_listening(State.LISTEN_MANUAL)
          end
        end)
      end)
    end
    if right then
      pcall(function()
        key.on(right, function(evt)
          if long_fire(evt) then
            self.ui:set_view_mode("wechat")
          elseif evt == short then
            stop_listening()
          end
        end)
      end)
    end
  end

  local function unbind_keys()
    if cfg.SERVICE_MODE then return end
    if not key or not key.off then
      return
    end
    pcall(function() key.off(key.DOWN or rawget(_G, "KEY_DOWN")) end)
    pcall(function() key.off(key.LEFT or rawget(_G, "KEY_LEFT")) end)
    pcall(function() key.off(key.RIGHT or rawget(_G, "KEY_RIGHT")) end)
  end

  local function start_timer()
    if not tmr or not tmr.create then
      return
    end
    self.timer = tmr.create()
    self.timer:alarm(cfg.SERVICE_MODE and 3000 or 700, tmr.ALARM_AUTO, function()
      if app and app.exiting and app.exiting() then
        self.stop("app.exiting")
        return
      end
      if not cfg.SERVICE_MODE then refresh_metrics() end
      if cfg.SERVICE_MODE then
        self.foreground_check_ticks = self.foreground_check_ticks + 1
        if self.foreground_check_ticks >= 1 then
          self.foreground_check_ticks = 0
          local denied, owner_app_id = foreground_denies_service()
          if denied then
            stop_xiaozhi_with_guard(owner_app_id)
            return
          end
        end
      end
      if self.ui and not cfg.SERVICE_MODE then
        self.ui:update_status_bar(false)
      end
    end)
  end

  function self:start()
    self.stopped = false
    consume_service_wake()
    self.ui:setup()
    self.audio = Audio.new(cfg)
    self.protocol = Protocol.new(cfg)
    self.mcp = Mcp.new(cfg, function(payload)
      return self.protocol:send_mcp_message(payload)
    end, function(target_app_id, allow_wake_service)
      return launch_app_from_ui(target_app_id, allow_wake_service, "mcp app switch")
    end)
    bind_audio()
    bind_protocol()
    self.state:on_change(on_state_changed)

    set_state(State.STARTING)
    set_state(State.ACTIVATING)
    bind_keys()
    start_timer()
    local activation_started = start_activation()
    if not activation_started then
      self.protocol:start()
      self.ui:show_notification("xiaozhi lua port", 1200)
      set_state(State.IDLE)
      if self.startup_wake_word then
        local wake_word = self.startup_wake_word
        self.startup_wake_word = nil
        wake_word_invoke(wake_word)
      end
    end
    refresh_metrics()
    return true
  end

  local function do_stop(reason)
    if self.stopped then
      return
    end
    self.stopped = true
    if self.timer then
      pcall(function() self.timer:stop() end)
      pcall(function() self.timer:unregister() end)
      self.timer = nil
    end
    if self.wake_open_timer then
      pcall(function() self.wake_open_timer:stop() end)
      pcall(function() self.wake_open_timer:unregister() end)
      self.wake_open_timer = nil
    end
    cancel_external_return()
    cancel_tts_audio_timer()
    self.tts_audio_queue = {}
    unbind_keys()
    if self.protocol then
      self.protocol:stop()
    end
    if self.activation then
      self.activation:stop()
      self.activation = nil
    end
    if self.audio then
      self.audio:stop()
    end
    if self.ui then
      self.ui:stop()
    end
    if self.web then self.web:stop() end
    notify_wake_service_for_app(self.return_app_id or "launcher", nil, 800)
    print("[xiaozhi] stop", reason or "")
  end

  self.stop = do_stop

  self.toggle_chat = toggle_chat
  self.start_listening = start_listening
  self.stop_listening = stop_listening
  self.wake_word_invoke = wake_word_invoke

  function self:snapshot()
    local p = self.protocol and self.protocol:info() or {}
    local code = self.pairing_code
    if self.activation and type(self.activation.code) == "string" and self.activation.code ~= "" then
      code = self.activation.code
    end
    return {
      ok = true,
      state = self.state and self.state.state or "unknown",
      connected = p.connected == true,
      pairing_code = code or "",
      activation_status = self.activation_status,
      message = self.activation_message,
      websocket_url = cfg.websocket and cfg.websocket.url or "",
      last_error = p.last_error or "",
      transparent_color = rawget(_G, "SERVICE_UI_TRANSPARENT_COLOR")
        or (service_ui and service_ui.TRANSPARENT_COLOR) or nil,
      ui_diagnostics = self.ui and self.ui.diagnostics and self.ui:diagnostics() or nil,
    }
  end

  return self
end

return M
