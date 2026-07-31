local M = {}

function M.new(cfg, load_module)
  local State = load_module("state")
  local Ui = load_module("ui")
  local Audio = load_module("audio")
  local Protocol = load_module("protocol")
  local Activation = load_module("activation")
  local Identity = load_module("identity")
  local Mcp = load_module("mcp")
  local XIAOZHI_WAKE_CONFIG_PATH = "/sd/apps/xiaozhi-service/service.json"
  local XIAOZHI_WAKE_TARGET_PATH = "/sd/apps/xiaozhi_wake/target_app_id.txt"

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
    current_app_id = "launcher",
    audio_suspended_by_app = false,
    audio_suspended_app_id = nil,
    temporary_wake_backoff = false,
    temporary_wake_backoff_timer = nil,
    temporary_wake_backoff_source = nil,
    activation_status = "启动中",
    activation_message = "",
    pairing_code = "",
    ui_status = "启动中",
    ui_role = "system",
    ui_text = "",
    ui_emotion = "neutral",
    ui_notice = "",
    ipc = nil,
    ipc_next_id = 0,
    ipc_subscribers = {},
    ipc_endpoint_subscribers = {},
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
      or cfg.wake_service
      or {}
  end

  local function wake_service_enabled()
    local wake_cfg = read_wake_service_config()
    return type(wake_cfg) == "table" and wake_cfg.enabled == true
  end

  local function service_wake_enabled()
    return wake_service_enabled()
  end

  local function app_denies_service(app_id)
    if not cfg.SERVICE_MODE then return false end
    local wake_cfg = read_wake_service_config()
    return type(app_id) == "string"
      and type(wake_cfg.deny_apps) == "table"
      and wake_cfg.deny_apps[app_id] == true
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
    if app_id == "launcher" or app_id == "xiaozhi" or app_id == "xiaozhi-service" or app_id == "xiaozhi_wake" then return nil end
    return app_id
  end

  local function foreground_app_id()
    if app and app.list then
      local ok, apps = pcall(app.list)
      if ok and type(apps) == "table" then
        for _, record in ipairs(apps) do
          if type(record) == "table" and record.running == true then
            return record.id
          end
        end
      end
    end
    if app and app.current then
      local ok, current = pcall(app.current)
      if ok and type(current) == "table" then
        return current.id
      end
    end
    return "launcher"
  end

  local refresh_metrics

  local function xiaozhi_is_foreground()
    if self.current_app_id == "xiaozhi" then return true end
    return foreground_app_id() == "xiaozhi"
  end

  local function apply_service_ui_suppression()
    if cfg.SERVICE_MODE and self.ui and self.ui.set_suppressed then
      self.ui:set_suppressed(xiaozhi_is_foreground())
    end
  end

  local function rebuild_service_ui(reason, quiet)
    if not self.ui then return false end
    pcall(function() self.ui:stop(reason or "reconfigure") end)
    self.ui = Ui.new(cfg)
    self.ui:setup()
    apply_service_ui_suppression()
    if quiet then
      refresh_metrics()
      return true
    end
    if self.state and self.state.state then
      self.ui:on_state(self.state.state)
    end
    self.ui:set_emotion(self.ui_emotion or "neutral")
    if type(self.ui_status) == "string" and self.ui_status ~= "" then
      self.ui:set_status(self.ui_status)
    end
    if type(self.ui_text) == "string" and self.ui_text ~= "" then
      self.ui:set_chat_message(self.ui_role or "system", self.ui_text)
    elseif type(self.ui_notice) == "string" and self.ui_notice ~= "" then
      self.ui:show_notification(self.ui_notice, 1800)
    end
    if refresh_metrics then refresh_metrics() end
    return true
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

  refresh_metrics = function()
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

  local notify_ipc

  local function alert(status, message, emotion)
    self.ui_status = tostring(status or "错误")
    self.ui_text = tostring(message or "")
    self.ui_role = "system"
    self.ui_emotion = emotion or "circle_xmark"
    self.ui:alert(status or "错误", message or "", emotion or "circle_xmark")
    notify_ipc()
  end

  notify_ipc = function()
    if not self.ipc_subscribers then return end
    local snapshot = self.ui_snapshot and self:ui_snapshot() or nil
    if not snapshot then return end
    for id, callback in pairs(self.ipc_subscribers) do
      local ok = pcall(callback, snapshot)
      if not ok then self.ipc_subscribers[id] = nil end
    end
    local lib = codec()
    if ipc and ipc.send and lib and lib.encode then
      local ok_encode, raw = pcall(lib.encode, snapshot)
      if ok_encode and type(raw) == "string" then
        for endpoint in pairs(self.ipc_endpoint_subscribers or {}) do
          local ok_send = pcall(function()
            return ipc.send(endpoint, "snapshot", raw)
          end)
          if not ok_send then self.ipc_endpoint_subscribers[endpoint] = nil end
        end
      end
    end
  end

  local start_activation

  local function show_pairing_code()
    local code = self.pairing_code or ""
    if self.activation and type(self.activation.code) == "string" and self.activation.code ~= "" then
      code = self.activation.code
    end
    if not self.activation or not self.activation.active then
      start_activation()
    end
    set_state(State.ACTIVATING)
    self.ui:set_emotion("thinking")
    self.ui_emotion = "thinking"
    if code ~= "" then
      self.ui_status = "验证码 " .. code
      self.ui_role = "system"
      self.ui_text = "后台添加设备输入验证码 " .. code
      self.ui_notice = "验证码 " .. code
      self.ui:set_status("验证码 " .. code)
      self.ui:set_chat_message("system", "后台添加设备输入验证码 " .. code)
      self.ui:show_notification("验证码 " .. code, 3000)
    else
      self.ui_status = "获取验证码"
      self.ui_role = "system"
      self.ui_text = "正在向小智服务端申请验证码"
      self.ui_notice = "正在获取配对码"
      self.ui:set_status("获取验证码")
      self.ui:set_chat_message("system", "正在向小智服务端申请验证码")
      self.ui:show_notification("正在获取配对码", 1800)
    end
    notify_ipc()
    return true
  end

  local function open_audio_channel_now()
    if not cfg.websocket or not cfg.websocket.url or cfg.websocket.url == "" then
      return show_pairing_code()
    end
    local ok = self.protocol:open_audio_channel()
    if not ok then
      local msg = self.protocol.last_error or "server not connected"
      alert("连接失败", msg, "cloud_slash")
      set_state(State.IDLE)
      return false
    end
    return true
  end

  local function open_audio_channel()
    if self.audio_suspended_by_app then
      return false
    end
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
    if self.audio_suspended_by_app then
      return false
    end
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

  local function launch_xiaozhi_ui(reason)
    if cfg.UI_MODE ~= "app" or not app or not app.launch then return false end
    local foreground = foreground_app_id()
    if foreground == "xiaozhi" then
      self.current_app_id = "xiaozhi"
      apply_service_ui_suppression()
      return false
    end
    local origin_app_id = returnable_app_id(foreground)
    local ok, launched, err = pcall(function() return app.launch("xiaozhi") end)
    if not ok or not launched then
      print("[xiaozhi] xiaozhi UI launch failed", tostring(reason or ""), tostring(err or launched or ""))
      return false
    end
    if origin_app_id then
      self.return_app_id = origin_app_id
      self.external_wake_active = true
      print("[xiaozhi] xiaozhi UI return target", origin_app_id)
    end
    print("[xiaozhi] xiaozhi UI launch", tostring(reason or ""))
    return true
  end

  local function wake_word_invoke(wake_word)
    if cfg.SERVICE_MODE and not service_wake_enabled() then
      print("[xiaozhi] wake ignored; background wake disabled")
      return false
    end
    if self.audio_suspended_by_app then
      print("[xiaozhi] wake ignored; audio suspended by app", tostring(self.audio_suspended_app_id or ""))
      return false
    end
    local s = self.state.state
    print("[xiaozhi] wake detected", tostring(wake_word), "state=" .. tostring(s))
    if self.startup_wake_from_service or self.return_app_id then
      self.external_wake_active = true
      self.startup_wake_from_service = false
    end
    self.pending_wake_word = wake_word or cfg.WAKE_WORD
    local foreground_xiaozhi = xiaozhi_is_foreground()
    apply_service_ui_suppression()
    if s == State.IDLE and not foreground_xiaozhi then
      launch_xiaozhi_ui("wake")
    end
    if not cfg.websocket or not cfg.websocket.url or cfg.websocket.url == "" then
      return show_pairing_code()
    end
    if s == State.IDLE then
      if not foreground_xiaozhi then
        self.ui:show_notification("你好小智", 1200)
      end
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

  local on_app_change
  local temporary_wake_backoff_active
  local clear_temporary_wake_backoff_timer

  local function launch_app_from_ui(app_id, allow_wake_service, reason)
    print("[xiaozhi] app launch request", tostring(reason or ""), tostring(app_id or ""))
    if type(app_id) ~= "string" or app_id == "" or app_id == "launcher" then
      if cfg.SERVICE_MODE then
        if self.ui and self.ui.on_state then self.ui:on_state(State.IDLE) end
        if self.audio and not temporary_wake_backoff_active() then self.audio:set_mode("wake") end
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
      -- Temporary firmware stand-in: callers report foreground transitions over
      -- IPC until the firmware owns app-change notifications.
      on_app_change(app_id, reason or "service-launch")
      local ok, err = app and app.launch and app.launch(app_id)
      print("[xiaozhi] app launch", tostring(reason or ""), tostring(app_id), tostring(ok), tostring(err or ""))
      if cfg.SERVICE_MODE and ok then
        if allow_wake_service ~= false and self.audio and not self.audio_suspended_by_app
            and not temporary_wake_backoff_active() then
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
    local labels = {
      starting = "正在启动",
      activating = "正在连接服务",
      connecting = "正在连接",
      listening = "我在听",
      speaking = "小智正在回答",
      fatal_error = "启动失败",
      idle = "小智待命中",
    }
    self.ui_status = labels[new_state] or tostring(new_state or self.ui_status)
    if new_state == State.IDLE then
      self.ui_role = "system"
      self.ui_text = ""
      self.ui_notice = ""
    end
    self.ui:on_state(new_state)
    if self.audio_suspended_by_app then
      refresh_metrics()
      notify_ipc()
      return
    end
    if temporary_wake_backoff_active() and new_state == State.IDLE then
      if self.audio then pcall(function() self.audio:set_mode("off") end) end
      refresh_metrics()
      notify_ipc()
      if self.external_wake_active
          and (old_state == State.CONNECTING or old_state == State.LISTENING or old_state == State.SPEAKING) then
        return_to_origin()
      end
      return
    end
    if new_state == State.IDLE then
      self.ui:clear_chat_messages()
      -- Release the WebSocket task/queues before asking I2S for contiguous DMA RAM.
      if self.protocol and self.protocol:is_audio_channel_opened() then
        self.protocol:close_audio_channel(false)
      end
      if cfg.SERVICE_MODE and not service_wake_enabled() then
        self.audio:set_mode("off")
      elseif self.external_wake_active then
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
    notify_ipc()
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

  temporary_wake_backoff_active = function()
    return self.temporary_wake_backoff == true
  end

  clear_temporary_wake_backoff_timer = function()
    if self.temporary_wake_backoff_timer then
      pcall(function() self.temporary_wake_backoff_timer:stop() end)
      pcall(function() self.temporary_wake_backoff_timer:unregister() end)
      self.temporary_wake_backoff_timer = nil
    end
  end

  local resume_audio_for_app

  local function restore_after_temporary_wake_backoff(source)
    clear_temporary_wake_backoff_timer()
    if not temporary_wake_backoff_active() then return true end
    self.temporary_wake_backoff = false
    self.temporary_wake_backoff_source = nil
    if self.stopped then return true end
    if self.audio_suspended_by_app then
      refresh_metrics()
      notify_ipc()
      return true
    end
    if self.audio and self.state.state == State.IDLE and service_wake_enabled() then
      pcall(function() self.audio:set_mode("wake") end)
    end
    refresh_metrics()
    notify_ipc()
    print("[xiaozhi] temporary wake backoff restored", tostring(source or ""))
    return true
  end

  local function temporary_wake_backoff(duration_ms, source)
    if not cfg.SERVICE_MODE then return false, "service mode required" end
    duration_ms = math.floor(tonumber(duration_ms) or 0)
    if duration_ms <= 0 then
      return false, "duration required"
    end
    duration_ms = math.max(1000, math.min(60000, duration_ms))
    source = type(source) == "string" and source ~= "" and source or "ipc"
    if not service_wake_enabled() then
      return true, { active = false, duration_ms = duration_ms, reason = "wake disabled" }
    end
    self.temporary_wake_backoff = true
    self.temporary_wake_backoff_source = source
    clear_temporary_wake_backoff_timer()
    if self.wake_open_timer then
      pcall(function() self.wake_open_timer:stop() end)
      pcall(function() self.wake_open_timer:unregister() end)
      self.wake_open_timer = nil
    end
    if self.audio and not self.audio_suspended_by_app and self.state.state == State.IDLE then
      pcall(function() self.audio:set_mode("off") end)
    end
    if tmr and tmr.create then
      local timer = tmr.create()
      self.temporary_wake_backoff_timer = timer
      timer:alarm(duration_ms, tmr.ALARM_SINGLE, function(instance)
        pcall(function() instance:unregister() end)
        if self.temporary_wake_backoff_timer ~= timer then return end
        self.temporary_wake_backoff_timer = nil
        restore_after_temporary_wake_backoff(source)
      end)
    else
      self.temporary_wake_backoff = false
      self.temporary_wake_backoff_source = nil
      return false, "timer unavailable"
    end
    refresh_metrics()
    notify_ipc()
    print("[xiaozhi] temporary wake backoff", tostring(source), tostring(duration_ms) .. "ms")
    return true, { active = true, duration_ms = duration_ms }
  end

  local function suspend_audio_for_app(app_id)
    if not cfg.SERVICE_MODE then return false end
    self.current_app_id = app_id
    if self.audio_suspended_by_app and self.audio_suspended_app_id == app_id then
      return true
    end
    self.audio_suspended_by_app = true
    self.audio_suspended_app_id = app_id
    if self.wake_open_timer then
      pcall(function() self.wake_open_timer:stop() end)
      pcall(function() self.wake_open_timer:unregister() end)
      self.wake_open_timer = nil
    end
    clear_temporary_wake_backoff_timer()
    self.temporary_wake_backoff = false
    self.temporary_wake_backoff_source = nil
    cancel_external_return()
    cancel_tts_audio_timer()
    self.pending_wake_word = nil
    self.pending_goodbye = false
    self.tts_text_ready = false
    self.tts_audio_queue = {}
    if self.protocol then
      pcall(function() self.protocol:send_abort_speaking("none") end)
      pcall(function() self.protocol:close_audio_channel(false) end)
    end
    if self.audio then
      pcall(function() self.audio:stop() end)
    end
    set_state(State.IDLE)
    refresh_metrics()
    notify_ipc()
    print("[xiaozhi] audio suspended for app", tostring(app_id or ""))
    return true
  end

  resume_audio_for_app = function(app_id)
    if not cfg.SERVICE_MODE then return false end
    self.current_app_id = app_id
    apply_service_ui_suppression()
    if not self.audio_suspended_by_app then return true end
    self.audio_suspended_by_app = false
    self.audio_suspended_app_id = nil
    if temporary_wake_backoff_active() then
      refresh_metrics()
      notify_ipc()
      print("[xiaozhi] audio resume deferred by temporary wake backoff", tostring(app_id or ""))
      return true
    end
    if self.audio and self.state.state == State.IDLE then
      if service_wake_enabled() then
        pcall(function() self.audio:set_mode("wake") end)
      end
    end
    refresh_metrics()
    notify_ipc()
    print("[xiaozhi] audio resumed for app", tostring(app_id or ""))
    return true
  end

  on_app_change = function(app_id, source)
    app_id = type(app_id) == "string" and app_id ~= "" and app_id or "launcher"
    if not cfg.SERVICE_MODE then return true end
    if app_id == "xiaozhi" or app_id == "xiaozhi-service" or app_id == "xiaozhi_wake" then
      return resume_audio_for_app(app_id)
    end
    if app_denies_service(app_id) then
      return suspend_audio_for_app(app_id)
    end
    return resume_audio_for_app(app_id)
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
      if self.audio_suspended_by_app then
        if self.protocol then self.protocol:close_audio_channel(false) end
        return
      end
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
      if self.audio_suspended_by_app then return end
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
      if self.audio_suspended_by_app then return end
      cancel_external_return()
      cancel_tts_audio_timer()
      self.tts_text_ready = false
      self.tts_audio_queue = {}
      set_state(State.SPEAKING)
    end)
    self.protocol:on("tts_stop", function()
      if self.audio_suspended_by_app then return end
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
      self.ui_role = tostring(role or "system")
      self.ui_text = tostring(text or "")
      self.ui:set_chat_message(role, text)
      notify_ipc()
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
      self.ui_emotion = tostring(emotion or "neutral")
      self.ui:set_emotion(emotion)
      notify_ipc()
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

  start_activation = function()
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
        self.ui_status = "未配置 OTA"
        self.ui_role = "system"
        self.ui_text = tostring(data or "未配置 ota.url")
        self.ui_notice = self.ui_text
        self.ui:set_chat_message("system", data or "未配置 ota.url")
      elseif event == "waiting_mac" then
        self.activation_message = "正在读取设备 MAC"
        self.ui_status = "等待设备 MAC"
        self.ui_role = "system"
        self.ui_text = self.activation_message
        self.ui_notice = self.activation_message
        set_state(State.ACTIVATING)
        self.ui:set_status("等待设备 MAC")
        self.ui:set_chat_message("system", self.activation_message)
      elseif event == "checking" then
        self.ui_status = "检查 OTA"
        self.ui_role = "system"
        self.ui_text = "正在向小智服务端申请验证码"
        self.ui_notice = "正在获取配对码"
        set_state(State.ACTIVATING)
        self.ui:set_status("检查 OTA")
        self.ui:set_chat_message("system", "正在向小智服务端申请验证码")
      elseif event == "code" then
        set_state(State.ACTIVATING)
        local code = data and data.code or ""
        self.ui:set_emotion("thinking")
        self.ui_emotion = "thinking"
        if code ~= "" then
          self.ui_status = "验证码 " .. code
          self.ui_role = "system"
          self.ui_text = "后台添加设备输入验证码 " .. code
          self.ui_notice = "验证码 " .. code
          self.ui:set_status("验证码 " .. code)
          self.ui:set_chat_message("system", "后台添加设备输入验证码 " .. code)
          self.ui:show_notification("验证码 " .. code, 2500)
        else
          self.ui_status = "等待绑定"
          self.ui_role = "system"
          self.ui_text = data and data.message or "等待后台设备绑定"
          self.ui_notice = self.ui_text
          self.ui:set_status("等待绑定")
          self.ui:set_chat_message("system", data and data.message or "等待后台设备绑定")
        end
      elseif event == "pending" then
        local code = data and data.code or ""
        if code ~= "" then
          self.ui_status = "验证码 " .. code
          self.ui_role = "system"
          self.ui_text = "后台添加设备输入验证码 " .. code
          self.ui_notice = "验证码 " .. code
          self.ui:set_status("验证码 " .. code)
        else
          self.ui_status = "等待绑定"
          self.ui_role = "system"
          self.ui_text = "等待后台设备绑定"
          self.ui_notice = self.ui_text
          self.ui:set_status("等待绑定")
        end
      elseif event == "retrying" then
        set_state(State.ACTIVATING)
        local code = self.activation and self.activation.code or self.pairing_code or ""
        if code ~= "" then
          self.activation_message = "网络暂时繁忙，仍在等待后台绑定"
          self.ui_status = "验证码 " .. code
          self.ui_role = "system"
          self.ui_text = "后台添加设备输入验证码 " .. code
          self.ui_notice = self.activation_message
          self.ui:set_status("验证码 " .. code)
          self.ui:set_chat_message("system", "后台添加设备输入验证码 " .. code)
        else
          self.activation_message = "网络暂时繁忙，正在重新获取配对信息"
          self.ui_status = "正在重试"
          self.ui_role = "system"
          self.ui_text = self.activation_message
          self.ui_notice = self.activation_message
          self.ui:set_status("正在重试")
          self.ui:set_chat_message("system", self.activation_message)
        end
      elseif event == "activated" then
        self.ui_status = "绑定成功"
        self.ui_role = "system"
        self.ui_text = "绑定成功，正在读取服务配置"
        self.ui_notice = "绑定成功"
        self.ui:show_notification("绑定成功", 1600)
        self.ui:set_chat_message("system", "绑定成功，正在读取服务配置")
      elseif event == "done" then
        self.pairing_code = ""
        self.ui_status = "小智已就绪"
        self.ui_role = "system"
        self.ui_text = ""
        self.ui_notice = "小智已就绪"
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
        self.ui_status = "激活失败"
        self.ui_role = "system"
        self.ui_text = tostring(data or "activation failed")
        self.ui_notice = self.ui_text
        alert("激活失败", data or "activation failed", "cloud_slash")
        set_state(State.IDLE)
        refresh_metrics()
      end
      notify_ipc()
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
    self.timer:alarm(700, tmr.ALARM_AUTO, function()
      if app and app.exiting and app.exiting() then
        self.stop("app.exiting")
        return
      end
      if not cfg.SERVICE_MODE then refresh_metrics() end
      if self.ui and not cfg.SERVICE_MODE then
        self.ui:update_status_bar(false)
      end
    end)
  end

  local function install_ipc()
    local bridge = {
      id = "xiaozhi-service",
      runtime = self,
      stopped = false,
    }
    function bridge:snapshot()
      return self.runtime:ui_snapshot()
    end
    function bridge:control(action, value)
      return self.runtime:ui_control(action, value)
    end
    function bridge:on_app_change(app_id, source)
      return on_app_change(app_id, source or "bridge")
    end
    function bridge:temporary_wake_backoff(duration_ms, source)
      return temporary_wake_backoff(duration_ms, source or "bridge")
    end
    function bridge:subscribe(callback)
      if type(callback) ~= "function" then return nil, "callback required" end
      self.runtime.ipc_next_id = self.runtime.ipc_next_id + 1
      local id = self.runtime.ipc_next_id
      self.runtime.ipc_subscribers[id] = callback
      pcall(callback, self.runtime:ui_snapshot())
      return function()
        self.runtime.ipc_subscribers[id] = nil
      end
    end
    function bridge:unsubscribe(id)
      self.runtime.ipc_subscribers[id] = nil
    end
    self.ipc = bridge
    _G.XIAOZHI_SERVICE = bridge
    if ipc and ipc.listen then
      pcall(function()
        ipc.listen("xiaozhi-service", function(topic, payload)
          local doc = {}
          local lib = codec()
          if type(payload) == "string" and payload ~= "" and lib and lib.decode then
            local ok_decode, value = pcall(lib.decode, payload)
            if ok_decode and type(value) == "table" then doc = value end
          end
          local reply_to = type(doc.reply_to) == "string" and doc.reply_to
            or type(doc.endpoint) == "string" and doc.endpoint
            or nil
          if topic == "subscribe" then
            if reply_to then
              self.ipc_endpoint_subscribers[reply_to] = true
              notify_ipc()
            end
          elseif topic == "unsubscribe" then
            if reply_to then self.ipc_endpoint_subscribers[reply_to] = nil end
          elseif topic == "snapshot" then
            if reply_to and ipc.send and lib and lib.encode then
              local ok_encode, raw = pcall(lib.encode, self:ui_snapshot())
              if ok_encode and type(raw) == "string" then
                pcall(function() ipc.send(reply_to, "snapshot", raw) end)
              end
            end
          elseif topic == "control" then
            self:ui_control(doc.action, doc.value)
          elseif topic == "on_app_change" then
            on_app_change(doc.app_id or doc.id or doc.app, doc.source or reply_to or "ipc")
          elseif topic == "temporary_wake_backoff" or topic == "wake_backoff" then
            local ms = tonumber(doc.duration_ms or doc.ms)
            if not ms and tonumber(doc.seconds or doc.sec or doc.duration) then
              ms = tonumber(doc.seconds or doc.sec or doc.duration) * 1000
            end
            local ok_backoff, result = temporary_wake_backoff(ms, doc.source or reply_to or "ipc")
            if reply_to and ipc.send and lib and lib.encode then
              local body = ok_backoff and { ok = true, result = result }
                or { ok = false, error = tostring(result or "temporary wake backoff failed") }
              local ok_encode, raw = pcall(lib.encode, body)
              if ok_encode and type(raw) == "string" then
                pcall(function() ipc.send(reply_to, "temporary_wake_backoff_result", raw) end)
              end
            end
          end
        end)
      end)
    end
    notify_ipc()
  end

  function self:start()
    self.stopped = false
    install_ipc()
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
    clear_temporary_wake_backoff_timer()
    self.temporary_wake_backoff = false
    self.temporary_wake_backoff_source = nil
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
    if rawget(_G, "XIAOZHI_SERVICE") == self.ipc then
      _G.XIAOZHI_SERVICE = nil
    end
    if ipc and ipc.listen then pcall(function() ipc.listen("xiaozhi-service", nil) end) end
    if self.ipc then self.ipc.stopped = true end
    self.ipc_subscribers = {}
    self.ipc_endpoint_subscribers = {}
    notify_wake_service_for_app(self.return_app_id or "launcher", nil, 800)
    print("[xiaozhi] stop", reason or "")
  end

  self.stop = do_stop

  self.toggle_chat = toggle_chat
  self.start_listening = start_listening
  self.stop_listening = stop_listening
  self.wake_word_invoke = wake_word_invoke

  local function update_saved_config(mutator)
    local codec = rawget(_G, "json") or rawget(_G, "sjson")
    if not codec or not codec.decode or not codec.encode or not file
        or not file.getcontents or not file.putcontents then
      return false, "配置存储接口不可用"
    end
    local ok_read, raw = pcall(file.getcontents, cfg.CONFIG_PATH)
    local ok_decode, doc = pcall(codec.decode, ok_read and raw or "{}")
    if not ok_decode or type(doc) ~= "table" then
      return false, "配置读取失败"
    end
    mutator(doc)
    local ok_encode, encoded = pcall(codec.encode, doc)
    if not ok_encode or type(encoded) ~= "string" then
      return false, "配置编码失败"
    end
    local ok_write, saved = pcall(file.putcontents, cfg.CONFIG_PATH, encoded .. "\n")
    if not ok_write or not saved then
      return false, "配置保存失败"
    end
    return true
  end

  local function update_saved_service_config(mutator)
    local codec = rawget(_G, "json") or rawget(_G, "sjson")
    if not codec or not codec.decode or not codec.encode or not file
        or not file.getcontents or not file.putcontents then
      return false, "服务配置存储接口不可用"
    end
    local ok_read, raw = pcall(file.getcontents, XIAOZHI_WAKE_CONFIG_PATH)
    local ok_decode, doc = pcall(codec.decode, ok_read and raw or "{}")
    if not ok_decode or type(doc) ~= "table" then
      doc = { enabled = true, ui_mode = "app", deny_apps = {} }
    end
    mutator(doc)
    local ok_encode, encoded = pcall(codec.encode, doc)
    if not ok_encode or type(encoded) ~= "string" then
      return false, "服务配置编码失败"
    end
    local ok_write, saved = pcall(file.putcontents, XIAOZHI_WAKE_CONFIG_PATH, encoded .. "\n")
    if not ok_write or not saved then
      return false, "服务配置保存失败"
    end
    return true
  end

  local function clean_ui_type(value)
    value = type(value) == "string" and value:match("^%s*(.-)%s*$"):lower() or ""
    if value ~= "" and #value <= 48 and value:match("^[%w_.%-]+$") then
      return value
    end
    return nil
  end

  local function path_exists(path)
    if type(path) ~= "string" or path == "" then return false end
    if file and file.exists then
      local ok, exists = pcall(function() return file.exists(path) end)
      if ok then return exists == true end
    end
    if file and file.stat then
      local ok, stat = pcall(function() return file.stat(path) end)
      if ok and stat ~= nil and stat ~= false then return true end
    end
    return read_text(path) ~= nil
  end

  local function read_dir(path)
    local names = {}
    local candidates = {
      { owner = file, method = "list" },
      { owner = file, method = "ls" },
      { owner = file, method = "listdir" },
      { owner = file, method = "readdir" },
    }
    for i = 1, #candidates do
      local owner, method = candidates[i].owner, candidates[i].method
      if owner and type(owner[method]) == "function" then
        local ok, result = pcall(function() return owner[method](path) end)
        if ok and type(result) == "table" then
          for key, value in pairs(result) do
            if type(value) == "string" then names[#names + 1] = value
            elseif type(value) == "table" and type(value.name) == "string" then names[#names + 1] = value.name
            elseif type(key) == "string" then names[#names + 1] = key end
          end
          if #names > 0 then return names end
        end
      end
    end
    return names
  end

  local function list_ui_styles(kind)
    kind = kind == "float" and "float" or "app"
    local dir = kind == "float"
      and ((cfg.SERVICE_DIR or "/sd/apps/xiaozhi-service") .. "/ui")
      or ((cfg.UI_APP_DIR or cfg.APP_DIR or "/sd/apps/xiaozhi") .. "/ui")
    local seen, styles = {}, {}
    local function add(name)
      name = clean_ui_type(name)
      if kind == "app" and (name == "driver" or name == "headless") then return end
      if name and not seen[name] and path_exists(dir .. "/" .. name .. ".lua") then
        seen[name] = true
        styles[#styles + 1] = name
      end
    end
    local names = read_dir(dir)
    for i = 1, #names do
      local name = tostring(names[i] or ""):gsub("\\", "/"):match("([^/]+)%.lua$")
      add(name)
    end
    add("subtitle")
    add("window")
    add("wechat")
    table.sort(styles)
    return styles
  end

  local function ui_style_exists(kind, name)
    name = clean_ui_type(name)
    if not name then return false end
    local dir = kind == "float"
      and ((cfg.SERVICE_DIR or "/sd/apps/xiaozhi-service") .. "/ui")
      or ((cfg.UI_APP_DIR or cfg.APP_DIR or "/sd/apps/xiaozhi") .. "/ui")
    return path_exists(dir .. "/" .. name .. ".lua")
  end

  local function list_ui_characters()
    local dir = (cfg.SERVICE_DIR or "/sd/apps/xiaozhi-service") .. "/ui/character"
    local seen, characters = {}, {}
    local function add(name)
      name = clean_ui_type(name)
      if name and not seen[name] and path_exists(dir .. "/" .. name .. ".rgb565") then
        seen[name] = true
        characters[#characters + 1] = name
      end
    end
    local names = read_dir(dir)
    for i = 1, #names do
      local name = tostring(names[i] or ""):gsub("\\", "/"):match("([^/]+)%.rgb565$")
      add(name)
    end
    add("xiaozhi_chibi")
    table.sort(characters)
    return characters
  end

  local function ui_character_exists(name)
    name = clean_ui_type(name)
    if not name then return false end
    local dir = (cfg.SERVICE_DIR or "/sd/apps/xiaozhi-service") .. "/ui/character"
    return path_exists(dir .. "/" .. name .. ".rgb565")
  end

  local function clean_app_id(value)
    value = type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
    if value ~= "" and #value <= 64 and value:match("^[%w_.%-]+$") then
      return value
    end
    return nil
  end

  local function normalize_deny_apps(value)
    local out = {}
    if type(value) == "table" then
      for key, enabled in pairs(value) do
        local id = clean_app_id(type(key) == "number" and enabled or key)
        if id and (type(key) == "number" or enabled == true) then
          out[id] = true
        end
      end
    end
    return out
  end

  local function service_deny_apps()
    local doc = read_wake_service_config()
    return normalize_deny_apps(type(doc) == "table" and doc.deny_apps or nil)
  end

  local function deny_app_options(deny_apps)
    local seen, options = {}, {}
    local function add(id, name)
      id = clean_app_id(id)
      if id and not seen[id] and id ~= "xiaozhi" and id ~= "xiaozhi-service" and id ~= "xiaozhi_wake" then
        seen[id] = true
        options[#options + 1] = { id = id, name = type(name) == "string" and name ~= "" and name or id }
      end
    end
    if app and app.list then
      local ok, list = pcall(app.list)
      if ok and type(list) == "table" then
        for _, item in ipairs(list) do
          if type(item) == "table" then add(item.id or item.app_id, item.name or item.title)
          elseif type(item) == "string" then add(item, item) end
        end
      end
    end
    add("videos", "视频")
    add("holo-retro-go", "Holo Retro Go")
    add("mp3_player", "MP3 Player")
    add("Spectrum", "Spectrum")
    add("2048", "2048")
    for id in pairs(deny_apps or {}) do add(id, id) end
    table.sort(options, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return options
  end

  function self:snapshot()
    local p = self.protocol and self.protocol:info() or {}
    local code = self.pairing_code
    if self.activation and type(self.activation.code) == "string" and self.activation.code ~= "" then
      code = self.activation.code
    end
    local deny_apps = service_deny_apps()
    return {
      ok = true,
      state = self.state and self.state.state or "unknown",
      connected = p.connected == true,
      pairing_code = code or "",
      activation_status = self.activation_status,
      message = self.activation_message,
      websocket_url = cfg.websocket and cfg.websocket.url or "",
      websocket_version = cfg.websocket and cfg.websocket.version or 1,
      websocket_token_set = cfg.websocket and type(cfg.websocket.token) == "string"
        and cfg.websocket.token ~= "" or false,
      ota_url = cfg.ota and cfg.ota.url or "",
      app_ui_type = cfg.APP_UI_TYPE or (cfg.app_ui and cfg.app_ui.type) or "subtitle",
      service_ui_mode = cfg.UI_MODE or "app",
      service_ui_type = cfg.UI_TYPE or (cfg.UI and cfg.UI.type) or "window",
      service_ui_character = cfg.UI_CHARACTER or (cfg.UI and cfg.UI.character) or "xiaozhi_chibi",
      deny_apps = deny_apps,
      deny_app_options = deny_app_options(deny_apps),
      ui_options = {
        app = list_ui_styles("app"),
        float = list_ui_styles("float"),
        characters = list_ui_characters(),
      },
      wake_service_enabled = service_wake_enabled(),
      device_mac = Identity.device_id() or "",
      last_error = p.last_error or "",
      volume = math.max(0, math.min(100, math.floor(tonumber(cfg.AUDIO.volume) or 100))),
      ui = self:ui_snapshot(),
      transparent_color = rawget(_G, "SERVICE_UI_TRANSPARENT_COLOR")
        or (service_ui and service_ui.TRANSPARENT_COLOR) or nil,
      ui_diagnostics = self.ui and self.ui.diagnostics and self.ui:diagnostics() or nil,
    }
  end

  function self:ui_snapshot()
    local code = self.pairing_code
    if self.activation and type(self.activation.code) == "string" and self.activation.code ~= "" then
      code = self.activation.code
    end
    local status = self.ui_status or ""
    local role = self.ui_role or "system"
    local text = self.ui_text or ""
    local notice = self.ui_notice or self.activation_message or ""
    if type(code) == "string" and code ~= "" and (text == "" or self.activation_status == "code" or self.activation_status == "pending") then
      status = "验证码 " .. code
      role = "system"
      text = "后台添加设备输入验证码 " .. code
      notice = "验证码 " .. code
    end
    return {
      ok = true,
      service = "xiaozhi-service",
      state = self.state and self.state.state or "unknown",
      status = status,
      role = role,
      text = text,
      emotion = self.ui_emotion or "neutral",
      notice = notice,
      connected = self.protocol and self.protocol:info().connected == true or false,
      pairing_code = code or "",
      activation_status = self.activation_status or "",
      message = self.activation_message or "",
      current_app_id = self.current_app_id or "",
      audio_suspended = self.audio_suspended_by_app == true,
      audio_suspended_app_id = self.audio_suspended_app_id or "",
      temporary_wake_backoff = self.temporary_wake_backoff == true,
      temporary_wake_backoff_source = self.temporary_wake_backoff_source or "",
    }
  end

  function self:ui_control(action, value)
    action = tostring(action or "")
    if action == "toggle" then
      toggle_chat()
      return true
    elseif action == "start" then
      return start_listening(value == "manual" and State.LISTEN_MANUAL or State.LISTEN_AUTO)
    elseif action == "stop" then
      stop_listening()
      return true
    elseif action == "wake" then
      return wake_word_invoke(type(value) == "string" and value ~= "" and value or cfg.WAKE_WORD)
    end
    return false, "unknown ui action"
  end

  function self:set_volume(value)
    value = tonumber(value)
    if not value then
      return false, "音量值无效"
    end
    value = math.max(0, math.min(100, math.floor(value)))
    local saved, save_err = update_saved_config(function(doc)
      doc.audio = type(doc.audio) == "table" and doc.audio or {}
      doc.audio.volume = value
    end)
    if not saved then return false, save_err end
    if self.audio and self.audio.set_volume then
      self.audio:set_volume(value)
    else
      cfg.AUDIO.volume = value
    end
    return true, value
  end

  function self:set_server(url, token, version, ota_url)
    url = type(url) == "string" and url:match("^%s*(.-)%s*$") or ""
    ota_url = type(ota_url) == "string" and ota_url:match("^%s*(.-)%s*$") or ""
    token = type(token) == "string" and token:match("^%s*(.-)%s*$") or ""
    version = math.floor(tonumber(version) or 1)
    if not ota_url:match("^https?://") then
      return false, "OTA 地址必须以 http:// 或 https:// 开头"
    end
    if url ~= "" and not url:match("^wss?://") then
      return false, "服务器地址必须以 ws:// 或 wss:// 开头"
    end
    if url == "" then token = "" end
    if version < 1 or version > 3 then
      return false, "协议版本仅支持 1 到 3"
    end
    local saved, save_err = update_saved_config(function(doc)
      doc.websocket = type(doc.websocket) == "table" and doc.websocket or {}
      doc.websocket.url = url
      doc.websocket.token = token
      doc.websocket.version = version
      doc.ota = type(doc.ota) == "table" and doc.ota or {}
      doc.ota.url = ota_url
      doc.ota.enabled = true
      doc.ota.force = false
    end)
    if not saved then return false, save_err end
    if self.activation then self.activation:stop() end
    if self.protocol then self.protocol:close_audio_channel(false) end
    cfg.websocket.url = url
    cfg.websocket.token = token
    cfg.websocket.version = version
    cfg.ota = cfg.ota or {}
    cfg.ota.url = ota_url
    cfg.ota.enabled = true
    cfg.ota.force = false
    self.pairing_code = ""
    self.activation_status = "custom"
    self.activation_message = "已切换自定义服务"
    set_state(State.IDLE)
    self.ui:set_status("自定义服务")
    self.ui:set_chat_message("system", "自定义服务已保存，唤醒后连接")
    self.ui:show_notification("自定义服务已保存", 1800)
    return true, { url = url, ota_url = ota_url, version = version, token_set = token ~= "" }
  end

  function self:set_ui_config(app_ui_type, service_ui_mode, service_ui_type, service_ui_character, deny_apps)
    app_ui_type = clean_ui_type(app_ui_type)
    service_ui_type = clean_ui_type(service_ui_type)
    service_ui_character = clean_ui_type(service_ui_character) or "xiaozhi_chibi"
    service_ui_mode = tostring(service_ui_mode or ""):lower()
    if not app_ui_type then
      return false, "主应用 UI 类型无效"
    end
    if not ui_style_exists("app", app_ui_type) then
      return false, "主应用 UI 文件不存在"
    end
    if service_ui_mode ~= "app" and service_ui_mode ~= "floating" then
      return false, "后台 UI 模式仅支持 app 或 floating"
    end
    if not service_ui_type then
      return false, "后台 UI 类型无效"
    end
    if service_ui_mode == "floating" and not ui_style_exists("float", service_ui_type) then
      return false, "悬浮 UI 文件不存在"
    end
    if service_ui_type == "assistant" and not ui_character_exists(service_ui_character) then
      return false, "悬浮角色文件不存在"
    end

    local saved, save_err = update_saved_config(function(doc)
      doc.ui = type(doc.ui) == "table" and doc.ui or {}
      doc.ui.type = app_ui_type
      doc.ui_type = nil
    end)
    if not saved then return false, save_err end

    local next_deny_apps = deny_apps ~= nil and normalize_deny_apps(deny_apps) or service_deny_apps()
    local service_saved, service_err = update_saved_service_config(function(doc)
      doc.enabled = doc.enabled ~= false
      doc.ui_mode = service_ui_mode
      doc.ui_type = service_ui_type
      doc.ui_character = service_ui_character
      doc.deny_apps = next_deny_apps
    end)
    if not service_saved then return false, service_err end

    cfg.APP_UI_TYPE = app_ui_type
    cfg.app_ui = cfg.app_ui or {}
    cfg.app_ui.type = app_ui_type
    cfg.UI_MODE = service_ui_mode
    cfg.UI_TYPE = service_ui_type
    cfg.UI_CHARACTER = service_ui_character
    cfg.UI = cfg.UI or {}
    cfg.UI.type = service_ui_type
    cfg.UI.character = service_ui_character
    self.activation_message = "UI 配置已保存，已立即生效"
    rebuild_service_ui("ui config changed", true)
    notify_ipc()
    return true, {
      app_ui_type = app_ui_type,
      service_ui_mode = service_ui_mode,
      service_ui_type = service_ui_type,
      service_ui_character = service_ui_character,
      deny_apps = next_deny_apps,
      deny_app_options = deny_app_options(next_deny_apps),
    }
  end

  function self:set_wake_enabled(enabled)
    enabled = enabled == true
    local saved, save_err = update_saved_service_config(function(doc)
      doc.enabled = enabled
      doc.ui_mode = doc.ui_mode or (cfg.UI_MODE or "app")
      doc.ui_type = doc.ui_type or (cfg.UI_TYPE or "window")
      doc.ui_character = doc.ui_character or (cfg.UI_CHARACTER or "xiaozhi_chibi")
      doc.deny_apps = type(doc.deny_apps) == "table" and doc.deny_apps or {}
    end)
    if not saved then return false, save_err end

    cfg.wake_service = cfg.wake_service or {}
    cfg.wake_service.enabled = enabled
    if not enabled then
      if self.wake_open_timer then
        pcall(function() self.wake_open_timer:stop() end)
        pcall(function() self.wake_open_timer:unregister() end)
        self.wake_open_timer = nil
      end
      cancel_external_return()
      cancel_tts_audio_timer()
      self.pending_wake_word = nil
      self.pending_goodbye = false
      self.tts_text_ready = false
      self.tts_audio_queue = {}
      if self.protocol then
        pcall(function() self.protocol:send_abort_speaking("none") end)
        pcall(function() self.protocol:close_audio_channel(false) end)
      end
      if self.audio then pcall(function() self.audio:set_mode("off") end) end
      set_state(State.IDLE)
    else
      if self.audio_suspended_by_app then
        -- Keep the app-specific suspension in force until the foreground app changes.
      elseif temporary_wake_backoff_active() then
        -- Keep temporary I2S backoff ahead of launcher/app-driven wake recovery.
      elseif self.audio and self.state.state == State.IDLE then
        pcall(function() self.audio:set_mode("wake") end)
      end
    end
    refresh_metrics()
    notify_ipc()
    return true, { wake_service_enabled = enabled }
  end

  function self:set_device_mac(value)
    local old_mac = Identity.device_id()
    local mac, mac_err = Identity.set_device_id(value)
    if not mac then return false, mac_err end
    if old_mac == mac then
      return true, { mac = mac, restarting = false, pairing_required = false, unchanged = true }
    end
    local official = type(cfg.websocket.url) ~= "string" or cfg.websocket.url == ""
      or cfg.websocket.url:find("api.tenclass.net", 1, true) ~= nil
    if official then
      local saved, save_err = update_saved_config(function(doc)
        doc.websocket = type(doc.websocket) == "table" and doc.websocket or {}
        doc.websocket.url = ""
        doc.websocket.token = ""
        doc.websocket.version = 1
        doc.ota = type(doc.ota) == "table" and doc.ota or {}
        doc.ota.enabled = true
        doc.ota.force = false
      end)
      if not saved then
        if old_mac then Identity.set_device_id(old_mac) end
        return false, save_err
      end
    end
    self.pairing_code = ""
    self.activation_status = "restarting"
    self.activation_message = official and "设备身份已修改，正在重新获取配对码"
      or "设备身份已修改，正在重启服务"
    local timer = tmr and tmr.create and tmr.create() or nil
    if timer then
      timer:alarm(400, tmr.ALARM_SINGLE, function(t)
        pcall(function() t:unregister() end)
        app.start_service("xiaozhi-service")
      end)
    end
    return true, { mac = mac, restarting = timer ~= nil, pairing_required = official }
  end

  return self
end

return M
