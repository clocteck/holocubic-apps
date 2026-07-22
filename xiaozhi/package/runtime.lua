local M = {}

function M.new(cfg, load_module)
  local State = load_module("state")
  local Ui = load_module("ui")
  local Audio = load_module("audio")
  local Protocol = load_module("protocol")
  local Activation = load_module("activation")
  local Mcp = load_module("mcp")
  local Identity = load_module("identity")

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
    listening_mode = State.LISTEN_AUTO,
    pending_wake_word = nil,
    stopped = false,
  }

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
    self.pending_wake_word = wake_word or cfg.WAKE_WORD
    if s == State.IDLE then
      if not self.audio:begin_wake_bridge() then
        self.audio:stop_i2s()
      end
      self.ui:show_notification("你好小智", 1200)
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

  local function on_state_changed(_, new_state)
    self.ui:on_state(new_state)
    if new_state == State.IDLE then
      self.ui:clear_chat_messages()
      self.audio:set_mode("wake")
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
      if self.state.state ~= State.SPEAKING then
        set_state(State.SPEAKING)
      end
      self.audio:play_opus(opus)
    end)
    self.protocol:on("tts_start", function()
      set_state(State.SPEAKING)
    end)
    self.protocol:on("tts_stop", function()
      if self.listening_mode == State.LISTEN_MANUAL then
        set_state(State.IDLE)
      else
        set_state(State.LISTENING)
      end
    end)
    self.protocol:on("chat", function(role, text)
      self.ui:set_chat_message(role, text)
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
      if event == "need_config" then
        self.ui:set_chat_message("system", data or "未配置 ota.url")
      elseif event == "waiting_mac" then
        set_state(State.ACTIVATING)
        self.ui:set_status("等待设备 MAC")
        self.ui:set_chat_message("system", "正在读取设备 MAC")
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
      refresh_metrics()
      if self.ui then
        self.ui:update_status_bar(false)
      end
    end)
  end

  function self:start()
    self.stopped = false
    self.ui:setup()
    self.audio = Audio.new(cfg)
    self.protocol = Protocol.new(cfg)
    self.mcp = Mcp.new(cfg, function(payload)
      return self.protocol:send_mcp_message(payload)
    end, function()
      if self.stop then self.stop("mcp app switch") end
    end)
    bind_audio()
    bind_protocol()
    self.state:on_change(on_state_changed)

    set_state(State.STARTING)
    if not self.audio:load_modules() then
      alert("错误", self.audio.last_error, "circle_xmark")
      set_state(State.FATAL_ERROR)
      return false
    end

    set_state(State.ACTIVATING)
    bind_keys()
    start_timer()
    local activation_started = start_activation()
    if not activation_started then
      self.protocol:start()
      self.ui:show_notification("xiaozhi lua port", 1200)
      set_state(State.IDLE)
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
    if self.controller_exit_timer then
      pcall(function() self.controller_exit_timer:stop() end)
      pcall(function() self.controller_exit_timer:unregister() end)
      self.controller_exit_timer = nil
    end
    if self.wake_open_timer then
      pcall(function() self.wake_open_timer:stop() end)
      pcall(function() self.wake_open_timer:unregister() end)
      self.wake_open_timer = nil
    end
    unbind_keys()
    if self.protocol then
      self.protocol:stop()
    end
    if self.activation then
      self.activation:stop()
      self.activation = nil
    end
    if self.web then
      pcall(function() self.web:stop() end)
      self.web = nil
    end
    if self.audio then
      self.audio:stop()
    end
    if self.ui then
      self.ui:stop()
    end
    print("[xiaozhi] stop", reason or "")
  end

  self.stop = do_stop

  self.toggle_chat = toggle_chat
  self.start_listening = start_listening
  self.stop_listening = stop_listening
  self.wake_word_invoke = wake_word_invoke

  local function encode_json(value)
    local codec = rawget(_G, "json") or rawget(_G, "sjson")
    if not codec or not codec.encode then return nil, "json encode unavailable" end
    local ok, raw = pcall(codec.encode, value)
    if ok and type(raw) == "string" then return raw end
    return nil, "json encode failed"
  end

  local function decode_json(raw)
    local codec = rawget(_G, "json") or rawget(_G, "sjson")
    if not codec or not codec.decode then return nil end
    local ok, doc = pcall(codec.decode, raw or "{}")
    return ok and type(doc) == "table" and doc or nil
  end

  local function update_json_file(path, fallback, mutator, err_prefix)
    if not file or not file.getcontents or not file.putcontents then
      return false, (err_prefix or "配置") .. "存储接口不可用"
    end
    local ok_read, raw = pcall(file.getcontents, path)
    local doc = decode_json(ok_read and raw or "{}") or fallback or {}
    mutator(doc)
    local encoded, encode_err = encode_json(doc)
    if not encoded then return false, encode_err end
    if path:find("/sd/apps/xiaozhi%-service/", 1) and file.mkdir then
      pcall(file.mkdir, "/sd/apps/xiaozhi-service")
    end
    local ok_write, saved = pcall(file.putcontents, path, encoded .. "\n")
    if not ok_write or not saved then return false, (err_prefix or "配置") .. "保存失败" end
    return true
  end

  local function clean_name(value, max_len)
    value = type(value) == "string" and value:match("^%s*(.-)%s*$"):lower() or ""
    if value ~= "" and #value <= (max_len or 48) and value:match("^[%w_.%-]+$") then
      return value
    end
    return nil
  end

  local function clean_app_id(value)
    value = type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
    if value ~= "" and #value <= 64 and value:match("^[%w_.%-]+$") then return value end
    return nil
  end

  local function path_exists(path)
    if file and file.exists then
      local ok, exists = pcall(function() return file.exists(path) end)
      if ok then return exists == true end
    end
    if file and file.stat then
      local ok, stat = pcall(function() return file.stat(path) end)
      if ok and stat ~= nil and stat ~= false then return true end
    end
    if file and file.getcontents then
      local ok, raw = pcall(file.getcontents, path)
      return ok and type(raw) == "string"
    end
    return false
  end

  local function read_dir(path)
    local names = {}
    local methods = { "list", "ls", "listdir", "readdir" }
    for _, method in ipairs(methods) do
      if file and type(file[method]) == "function" then
        local ok, result = pcall(function() return file[method](path) end)
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
    local dir = kind == "float" and "/sd/apps/xiaozhi-service/ui" or ((cfg.APP_DIR or "/sd/apps/xiaozhi") .. "/ui")
    local seen, styles = {}, {}
    local function add(name)
      name = clean_name(name)
      if kind ~= "float" and (name == "driver" or name == "headless") then return end
      if name and not seen[name] and path_exists(dir .. "/" .. name .. ".lua") then
        seen[name] = true
        styles[#styles + 1] = name
      end
    end
    for _, entry in ipairs(read_dir(dir)) do
      add(tostring(entry or ""):gsub("\\", "/"):match("([^/]+)%.lua$"))
    end
    add(kind == "float" and "window" or "subtitle")
    add("wechat")
    if kind == "float" then add("subtitle"); add("assistant") end
    table.sort(styles)
    return styles
  end

  local function list_ui_characters()
    local dir = "/sd/apps/xiaozhi-service/ui/character"
    local seen, out = {}, {}
    local function add(name)
      name = clean_name(name)
      if name and not seen[name] and path_exists(dir .. "/" .. name .. ".rgb565") then
        seen[name] = true
        out[#out + 1] = name
      end
    end
    for _, entry in ipairs(read_dir(dir)) do
      add(tostring(entry or ""):gsub("\\", "/"):match("([^/]+)%.rgb565$"))
    end
    add("xiaozhi_chibi")
    table.sort(out)
    return out
  end

  local function ui_style_exists(kind, name)
    name = clean_name(name)
    if not name then return false end
    local dir = kind == "float" and "/sd/apps/xiaozhi-service/ui" or ((cfg.APP_DIR or "/sd/apps/xiaozhi") .. "/ui")
    return path_exists(dir .. "/" .. name .. ".lua")
  end

  local function normalize_deny_apps(value)
    local out = {}
    if type(value) == "table" then
      for key, enabled in pairs(value) do
        local id = clean_app_id(type(key) == "number" and enabled or key)
        if id and (type(key) == "number" or enabled == true) then out[id] = true end
      end
    end
    return out
  end

  local function read_service_config()
    if not file or not file.getcontents then return {} end
    local ok, raw = pcall(file.getcontents, "/sd/apps/xiaozhi-service/service.json")
    return decode_json(ok and raw or "{}") or { enabled = true, ui_mode = "app", deny_apps = {} }
  end

  local function current_deny_apps()
    local doc = read_service_config()
    return normalize_deny_apps(doc.deny_apps)
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
    local code = self.activation and self.activation.code or self.pairing_code or ""
    return {
      ok = true,
      state = self.state and self.state.state or "unknown",
      connected = p.connected == true,
      pairing_code = code or "",
      activation_status = self.activation_status,
      message = self.activation_message,
      websocket_url = cfg.websocket and cfg.websocket.url or "",
      websocket_version = cfg.websocket and cfg.websocket.version or 1,
      websocket_token_set = cfg.websocket and type(cfg.websocket.token) == "string" and cfg.websocket.token ~= "" or false,
      ota_url = cfg.ota and cfg.ota.url or "",
      app_ui_type = cfg.UI_TYPE or (cfg.UI and cfg.UI.type) or "subtitle",
      ui_options = {
        app = list_ui_styles("app"),
      },
      device_mac = Identity.device_id() or "",
      last_error = p.last_error or "",
      volume = math.max(0, math.min(100, math.floor(tonumber(cfg.AUDIO.volume) or 100))),
    }
  end

  function self:set_app_ui_config(app_ui_type)
    app_ui_type = clean_name(app_ui_type)
    if not app_ui_type then return false, "主应用 UI 类型无效" end
    if not ui_style_exists("app", app_ui_type) then return false, "主应用 UI 文件不存在" end
    local saved, err = update_json_file(cfg.CONFIG_PATH, {}, function(doc)
      doc.ui = type(doc.ui) == "table" and doc.ui or {}
      doc.ui.type = app_ui_type
      doc.ui_type = nil
    end, "配置")
    if not saved then return false, err end
    cfg.UI_TYPE = app_ui_type
    cfg.UI = cfg.UI or {}
    cfg.UI.type = app_ui_type
    if self.ui and self.ui.set_view_mode then self.ui:set_view_mode(app_ui_type) end
    return true, { app_ui_type = app_ui_type }
  end

  function self:set_volume(value)
    value = tonumber(value)
    if not value then return false, "音量值无效" end
    value = math.max(0, math.min(100, math.floor(value)))
    local saved, err = update_json_file(cfg.CONFIG_PATH, {}, function(doc)
      doc.audio = type(doc.audio) == "table" and doc.audio or {}
      doc.audio.volume = value
    end, "配置")
    if not saved then return false, err end
    cfg.AUDIO.volume = value
    if self.audio and self.audio.set_volume then self.audio:set_volume(value) end
    return true, value
  end

  function self:set_server(url, token, version, ota_url)
    url = type(url) == "string" and url:match("^%s*(.-)%s*$") or ""
    ota_url = type(ota_url) == "string" and ota_url:match("^%s*(.-)%s*$") or ""
    token = type(token) == "string" and token:match("^%s*(.-)%s*$") or ""
    version = math.floor(tonumber(version) or 1)
    if not ota_url:match("^https?://") then return false, "OTA 地址必须以 http:// 或 https:// 开头" end
    if url ~= "" and not url:match("^wss?://") then return false, "服务器地址必须以 ws:// 或 wss:// 开头" end
    if url == "" then token = "" end
    if version < 1 or version > 3 then return false, "协议版本仅支持 1 到 3" end
    local saved, err = update_json_file(cfg.CONFIG_PATH, {}, function(doc)
      doc.websocket = type(doc.websocket) == "table" and doc.websocket or {}
      doc.websocket.url = url
      doc.websocket.token = token
      doc.websocket.version = version
      doc.ota = type(doc.ota) == "table" and doc.ota or {}
      doc.ota.url = ota_url
      doc.ota.enabled = true
      doc.ota.force = false
    end, "配置")
    if not saved then return false, err end
    cfg.websocket.url = url
    cfg.websocket.token = token
    cfg.websocket.version = version
    cfg.ota.url = ota_url
    cfg.ota.enabled = true
    cfg.ota.force = false
    if self.activation then self.activation:stop(); self.activation = nil end
    if self.protocol then self.protocol:close_audio_channel(false) end
    set_state(State.IDLE)
    return true, { url = url, ota_url = ota_url, version = version, token_set = token ~= "" }
  end

  function self:set_ui_config(app_ui_type, service_ui_mode, service_ui_type, service_ui_character, deny_apps)
    app_ui_type = clean_name(app_ui_type)
    service_ui_type = clean_name(service_ui_type) or "window"
    service_ui_character = clean_name(service_ui_character) or "xiaozhi_chibi"
    service_ui_mode = tostring(service_ui_mode or ""):lower()
    if not app_ui_type then return false, "主应用 UI 类型无效" end
    if not ui_style_exists("app", app_ui_type) then return false, "主应用 UI 文件不存在" end
    if service_ui_mode ~= "app" and service_ui_mode ~= "floating" then return false, "后台 UI 模式仅支持 app 或 floating" end
    if service_ui_mode == "floating" and not ui_style_exists("float", service_ui_type) then return false, "悬浮 UI 文件不存在" end
    local next_deny_apps = deny_apps ~= nil and normalize_deny_apps(deny_apps) or current_deny_apps()
    local saved, err = update_json_file(cfg.CONFIG_PATH, {}, function(doc)
      doc.ui = type(doc.ui) == "table" and doc.ui or {}
      doc.ui.type = app_ui_type
      doc.ui_type = nil
    end, "配置")
    if not saved then return false, err end
    local service_saved, service_err = update_json_file("/sd/apps/xiaozhi-service/service.json",
      { enabled = true, ui_mode = "app", deny_apps = {} }, function(doc)
        doc.enabled = doc.enabled ~= false
        doc.ui_mode = service_ui_mode
        doc.ui_type = service_ui_type
        doc.ui_character = service_ui_character
        doc.deny_apps = next_deny_apps
      end, "服务配置")
    if not service_saved then return false, service_err end
    cfg.UI_TYPE = app_ui_type
    cfg.UI = cfg.UI or {}
    cfg.UI.type = app_ui_type
    if self.ui and self.ui.set_view_mode then self.ui:set_view_mode(app_ui_type) end
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
    local saved, err = update_json_file("/sd/apps/xiaozhi-service/service.json",
      { enabled = true, ui_mode = "app", deny_apps = {} }, function(doc)
        doc.enabled = enabled
        doc.ui_mode = doc.ui_mode or "app"
        doc.ui_type = doc.ui_type or "window"
        doc.ui_character = doc.ui_character or "xiaozhi_chibi"
        doc.deny_apps = type(doc.deny_apps) == "table" and doc.deny_apps or {}
      end, "服务配置")
    if not saved then return false, err end
    return true, { wake_service_enabled = enabled }
  end

  function self:set_device_mac(value)
    local old_mac = Identity.device_id()
    local mac, mac_err = Identity.set_device_id(value)
    if not mac then return false, mac_err end
    if old_mac == mac then return true, { mac = mac, restarting = false, pairing_required = false, unchanged = true } end
    local saved, err = update_json_file(cfg.CONFIG_PATH, {}, function(doc)
      doc.websocket = type(doc.websocket) == "table" and doc.websocket or {}
      doc.websocket.url = ""
      doc.websocket.token = ""
      doc.websocket.version = 1
      doc.ota = type(doc.ota) == "table" and doc.ota or {}
      doc.ota.enabled = true
      doc.ota.force = false
    end, "配置")
    if not saved then
      if old_mac then Identity.set_device_id(old_mac) end
      return false, err
    end
    cfg.websocket.url = ""
    cfg.websocket.token = ""
    cfg.websocket.version = 1
    cfg.ota.enabled = true
    cfg.ota.force = false
    return true, { mac = mac, restarting = false, pairing_required = true }
  end

  return self
end

return M
