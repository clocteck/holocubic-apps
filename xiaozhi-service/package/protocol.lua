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

local function decode_json(raw)
  if type(raw) ~= "string" or not sjson or not sjson.decode then
    return nil
  end
  local ok, obj = pcall(sjson.decode, raw)
  if ok and type(obj) == "table" then
    return obj
  end
  return nil
end

local function json_string(obj, raw, name)
  if type(obj) == "table" and type(obj[name]) == "string" then
    return obj[name]
  end
  return pick_string(raw, name)
end

local function json_number(obj, raw, name)
  if type(obj) == "table" and tonumber(obj[name]) then
    return tonumber(obj[name])
  end
  return pick_number(raw, name)
end

local function u16be(value)
  value = tonumber(value) or 0
  local hi = math.floor(value / 256) % 256
  local lo = value % 256
  return string.char(hi, lo)
end

local function device_id(cfg)
  local ok, ident = pcall(dofile, ((cfg and cfg.APP_DIR) or "/sd/apps/xiaozhi") .. "/identity.lua")
  if ok and ident and ident.device_id then
    return ident.device_id(), ident.client_id()
  end
  return nil, nil
end

function M.new(cfg)
  local self = {
    cfg = cfg,
    ws = nil,
    connected = false,
    opened = false,
    connecting = false,
    session_id = "",
    server_sample_rate = 24000,
    server_frame_duration = 60,
    last_error = "",
    callbacks = {},
    listening_mode = nil,
    uploaded_packets = 0,
    send_retries = 0,
  }
  local send_queue, send_bytes, send_timer = {}, 0, nil
  local function clear_send_queue()
    if send_timer then send_timer:stop();send_timer:unregister();send_timer=nil end
    send_queue,send_bytes={},0
  end

  function self:on(name, fn)
    self.callbacks[name] = fn
  end

  local function emit(name, ...)
    local fn = self.callbacks[name]
    if fn then
      pcall(fn, ...)
    end
  end

  local function set_error(msg)
    self.last_error = tostring(msg or "")
    if self.last_error ~= "" then
      emit("error", self.last_error)
    end
  end

  function self:info()
    return {
      connected = self.connected,
      opened = self.opened,
      connecting = self.connecting,
      session_id = self.session_id,
      server_sample_rate = self.server_sample_rate,
      server_frame_duration = self.server_frame_duration,
      last_error = self.last_error,
      listening_mode = self.listening_mode,
      uploaded_packets = self.uploaded_packets,
      queued_messages = #send_queue,
      queued_bytes = send_bytes,
      send_retries = self.send_retries,
    }
  end

  local function transport_failure(message)
    self:close_audio_channel(false)
    emit("closed", -1)
    set_error(message)
    return false,message
  end
  local function write_packet(data,opcode)
    local ok,result,err=pcall(function()return self.ws:send(data,opcode)end)
    if not ok then return false,tostring(result) end
    if type(result)=="string" then return false,result end
    if result==false or (result==nil and err~=nil) then
      return false,tostring(err or "websocket send failed")
    end
    if opcode==websocket.BINARY then self.uploaded_packets=self.uploaded_packets+1 end
    return true
  end
  local function drain_send_queue()
    for _=1,4 do
      local item=send_queue[1]
      if not item then
        if send_timer then send_timer:stop();send_timer:unregister();send_timer=nil end
        return true
      end
      local age=millis and (millis()-item.started) or item.ticks*20
      if age>=1500 then return transport_failure("websocket send backlog exceeded 1500ms") end
      local ok,err=write_packet(item.data,item.opcode)
      if not ok then
        if err~="send queue full" then return transport_failure(err) end
        self.send_retries=self.send_retries+1
        return true
      end
      send_bytes=send_bytes-#item.data
      table.remove(send_queue,1)
    end
    return true
  end
  local function send_packet(data,opcode)
    if not self.ws or not self.connected then
      return false, "not connected"
    end
    if #send_queue==0 then
      local ok,err=write_packet(data,opcode)
      if ok then return true end
      if err~="send queue full" then return transport_failure(err) end
      self.send_retries=self.send_retries+1
    end
    -- One ordered queue for control and audio: listen/start cannot overtake
    -- earlier messages, and transient firmware backpressure doesn't lose speech.
    if #send_queue>=32 or send_bytes+#data>65536 then
      return transport_failure("websocket send backlog limit exceeded")
    end
    send_queue[#send_queue+1]={data=data,opcode=opcode,started=millis and millis() or 0,ticks=0}
    send_bytes=send_bytes+#data
    if not send_timer then
      send_timer=tmr.create()
      local timer=send_timer
      timer:alarm(20,tmr.ALARM_AUTO,function()
        if send_timer~=timer then return end
        for _,item in ipairs(send_queue)do item.ticks=item.ticks+1 end
        drain_send_queue()
      end)
    end
    return true
  end
  local function send_text(text) return send_packet(text,websocket.TEXT) end

  function self:send_text(text)
    return send_text(text)
  end

  local function hello_json()
    return "{" ..
      json_pair("type", "hello") ..
      ',"version":' .. tostring(cfg.websocket.version or 1) ..
      ',"features":{"mcp":true}' ..
      ',"transport":"websocket"' ..
      ',"audio_params":{"format":"opus","sample_rate":' .. tostring(cfg.AUDIO.rate or 16000) ..
      ',"channels":' .. tostring(cfg.AUDIO.channels or 1) .. ',"frame_duration":' ..
      tostring(cfg.AUDIO.frame_ms or 60) .. "}" ..
      "}"
  end

  local function handle_hello(raw, obj)
    local transport = json_string(obj, raw, "transport")
    if transport and transport ~= "websocket" then
      set_error("unsupported transport")
      return
    end
    self.session_id = json_string(obj, raw, "session_id") or self.session_id
    local audio_params = type(obj) == "table" and obj.audio_params or nil
    self.server_sample_rate = json_number(audio_params, raw, "sample_rate") or self.server_sample_rate
    self.server_frame_duration = json_number(audio_params, raw, "frame_duration") or self.server_frame_duration
    self.opened = true
    self.connecting = false
    emit("opened")
  end

  local function handle_json(raw)
    local obj = decode_json(raw)
    local typ = json_string(obj, raw, "type")
    if typ == "hello" then
      handle_hello(raw, obj)
      return
    end
    if typ == "tts" then
      local state = json_string(obj, raw, "state")
      if state == "start" then
        emit("tts_start")
      elseif state == "stop" then
        emit("tts_stop")
      elseif state == "sentence_start" then
        emit("chat", "assistant", json_string(obj, raw, "text") or "")
      end
    elseif typ == "stt" then
      emit("chat", "user", json_string(obj, raw, "text") or "")
    elseif typ == "llm" then
      local emotion = json_string(obj, raw, "emotion")
      if emotion then
        emit("emotion", emotion)
      end
    elseif typ == "alert" then
      emit("alert", json_string(obj, raw, "status") or "alert",
        json_string(obj, raw, "message") or "", json_string(obj, raw, "emotion") or "neutral")
    elseif typ == "mcp" then
      emit("mcp", type(obj) == "table" and obj.payload or nil, raw)
    else
      emit("json", raw)
    end
  end

  local function parse_binary(data)
    if (cfg.websocket.version or 1) == 3 and type(data) == "string" and #data >= 4 then
      local typ, _, hi, lo = string.byte(data, 1, 4)
      local size = (hi or 0) * 256 + (lo or 0)
      if typ == 0 and size > 0 and #data >= size + 4 then
        return data:sub(5, size + 4)
      end
    end
    return data
  end

  function self:start()
    return true
  end

  function self:is_audio_channel_opened()
    return self.connected and self.opened
  end

  function self:open_audio_channel()
    if self:is_audio_channel_opened() then
      return true
    end
    if not websocket or not websocket.createClient then
      set_error("websocket api missing")
      return false
    end
    if not cfg.websocket.url or cfg.websocket.url == "" then
      set_error("websocket config missing")
      return false
    end
    local id, client_id = device_id(cfg)
    if not id or not client_id then
      set_error("device mac unavailable")
      return false
    end

    self:close_audio_channel(false)
    self.last_error = ""
    self.uploaded_packets,self.send_retries=0,0
    self.connecting = true
    self.opened = false
    self.connected = false

    local ws = websocket.createClient()
    self.ws = ws
    local token = cfg.websocket.token or ""
    if token ~= "" and not token:find(" ", 1, true) then
      token = "Bearer " .. token
    end
    local headers = {
      ["Protocol-Version"] = tostring(cfg.websocket.version or 1),
      ["Device-Id"] = id,
      ["Client-Id"] = client_id or id,
    }
    if token ~= "" then
      headers["Authorization"] = token
    end

    ws:config({
      headers = headers,
      buffer_size = cfg.websocket.buffer_size,
      task_stack = cfg.websocket.task_stack,
      network_timeout_ms = cfg.websocket.timeout_ms,
      async_send = cfg.websocket.async_send,
      send_task_core = cfg.websocket.send_task_core,
      send_queue_depth = cfg.websocket.send_queue_depth,
      send_queue_bytes = cfg.websocket.send_queue_bytes,
      send_timeout_ms = cfg.websocket.send_timeout_ms,
      auto_reconnect = false,
      use_crt_bundle = true,
    })

    ws:on("connection", function(client)
      if self.ws ~= ws then return end
      self.connected = true
      self.connecting = false
      emit("connected")
      local ok, err = send_text(hello_json())
      if not ok then
        set_error(err)
      end
    end)

    ws:on("receive", function(_, data, opcode)
      if self.ws ~= ws then return end
      if opcode == websocket.BINARY then
        emit("audio", parse_binary(data))
      else
        handle_json(data)
      end
    end)

    ws:on("close", function(_, status)
      if self.ws ~= ws then return end
      clear_send_queue()
      self.listening_mode=nil
      self.connected = false
      self.opened = false
      self.connecting = false
      self.ws = nil
      emit("closed", status)
    end)

    local ok, err = pcall(function()
      ws:connect(cfg.websocket.url)
    end)
    if not ok then
      self.connecting = false
      set_error(tostring(err or "websocket connect failed"))
      return false
    end
    return true
  end

  function self:close_audio_channel(send_goodbye)
    clear_send_queue()
    local ws=self.ws
    self.ws = nil
    self.listening_mode=nil
    self.connected = false
    self.opened = false
    self.connecting = false
    if ws then pcall(function() ws:close() end) end
    if send_goodbye then
      emit("closed", 0)
    end
  end

  function self:send_audio(opus)
    if not self:is_audio_channel_opened() then
      return false
    end
    local packet = opus
    if (cfg.websocket.version or 1) == 3 then
      packet = string.char(0, 0) .. u16be(#opus) .. opus
    end
    return send_packet(packet,websocket.BINARY)
  end

  function self:send_wake_word_detected(wake_word)
    return send_text("{" .. json_pair("session_id", self.session_id) ..
      ',"type":"listen","state":"detect",' .. json_pair("text", wake_word) .. "}")
  end

  function self:send_start_listening(mode)
    mode=mode=="manual" and "manual" or "auto"
    local ok,err=send_text("{" .. json_pair("session_id", self.session_id) ..
      ',"type":"listen","state":"start","mode":"' .. json_escape(mode) .. '"}')
    if ok then self.listening_mode=mode end
    return ok,err
  end

  function self:send_stop_listening()
    self.listening_mode=nil
    return send_text("{" .. json_pair("session_id", self.session_id) ..
      ',"type":"listen","state":"stop"}')
  end

  function self:send_abort_speaking(reason)
    local msg = "{" .. json_pair("session_id", self.session_id) .. ',"type":"abort"'
    if reason == "wake_word_detected" then
      msg = msg .. ',"reason":"wake_word_detected"'
    end
    return send_text(msg .. "}")
  end

  function self:send_mcp_message(payload)
    return send_text("{" .. json_pair("session_id", self.session_id) ..
      ',"type":"mcp","payload":' .. tostring(payload or "{}") .. "}")
  end

  function self:stop()
    self:close_audio_channel(false)
  end

  return self
end

return M
