local M = {}

local SETTINGS_PATH = "/sd/apps/settings.json"
local HIDPAD_SERVICE_ID = "hidpad"
local HIDPAD_ENDPOINT = "ble-controller"
local HIDPAD_REPLY_ENDPOINT = "xiaozhi-device-mcp"
local HIDPAD_MANIFEST_PATH = "/sd/apps/hidpad/app.info"
local HIDPAD_STATUS_TTL_MS = 5000
local NTP_SERVERS = {
  "ntp.aliyun.com",
  "time.cloudflare.com",
  "pool.ntp.org",
}

local HIDPAD = {
  status = nil,
  status_ms = 0,
  listening = false,
}

M.tools = {
  {
    name = "device.get_status",
    description = "读取设备型号、固件、网络和内存状态。",
    inputSchema = { type = "object", additionalProperties = false },
  },
  {
    name = "device.list_apps",
    description = "列出设备上已经安装并可启动的应用。",
    inputSchema = { type = "object", additionalProperties = false },
  },
  {
    name = "device.launch_app",
    description = "按应用 ID 启动设备上已安装的应用。调用前应先使用 device.list_apps 获取 ID。",
    inputSchema = {
      type = "object",
      properties = { app_id = { type = "string", description = "应用 ID" } },
      required = { "app_id" },
      additionalProperties = false,
    },
  },
  {
    name = "device.sync_time",
    description = "立即通过 NTP 同步系统时间。可选传入 server 指定 NTP 服务器。",
    inputSchema = {
      type = "object",
      properties = { server = { type = "string", description = "可选 NTP 服务器域名" } },
      additionalProperties = false,
    },
  },
  {
    name = "device.set_brightness",
    description = "设置屏幕亮度，范围 0 到 100。",
    inputSchema = {
      type = "object",
      properties = {
        brightness = {
          type = "integer",
          minimum = 0,
          maximum = 100,
          description = "屏幕亮度百分比，0 到 100。",
        },
      },
      required = { "brightness" },
      additionalProperties = false,
    },
  },
  {
    name = "device.set_wifi_ap",
    description = "配置 Wi-Fi 热点 AP 模式。开启时保留已有 STA 连接，关闭时保留 STA 客户端模式。",
    inputSchema = {
      type = "object",
      properties = {
        enabled = {
          type = "boolean",
          description = "true 开启 AP 热点，false 关闭 AP 热点。",
        },
      },
      required = { "enabled" },
      additionalProperties = false,
    },
  },
  {
    name = "device.set_bluetooth",
    description = "开启或关闭蓝牙手柄服务，并返回连接设备情况。",
    inputSchema = {
      type = "object",
      properties = {
        enabled = {
          type = "boolean",
          description = "true 开启蓝牙，false 关闭蓝牙。",
        },
      },
      required = { "enabled" },
      additionalProperties = false,
    },
  },
}

local function clamp(value, min_value, max_value)
  local num = tonumber(value)
  if not num then
    return nil
  end
  if num < min_value then
    num = min_value
  elseif num > max_value then
    num = max_value
  end
  return math.floor(num + 0.5)
end

local function clock_ms()
  if sys and sys.millis then
    local ok, value = pcall(function() return sys.millis() end)
    if ok and type(value) == "number" then return value end
  end
  if millis then
    local ok, value = pcall(millis)
    if ok and type(value) == "number" then return value end
  end
  if os and os.clock then
    return math.floor(os.clock() * 1000)
  end
  return 0
end

local function file_exists(path)
  if not file then return false end
  if file.stat then
    local ok, stat = pcall(function() return file.stat(path) end)
    if ok and type(stat) == "table" then return true end
  end
  if file.open then
    local fd = file.open(path, "r")
    if fd then
      fd:close()
      return true
    end
  end
  return false
end

local function service_running(service_id)
  if not app or not app.services then
    return false
  end
  local ok, services = pcall(function() return app.services() end)
  if not ok or type(services) ~= "table" then
    return false
  end
  for _, record in ipairs(services) do
    if type(record) == "table" and record.id == service_id then
      return true
    end
  end
  return false
end

local function hidpad_installed()
  if service_running(HIDPAD_SERVICE_ID) then
    return true
  end
  return file_exists(HIDPAD_MANIFEST_PATH)
end

local function codec()
  return rawget(_G, "json") or rawget(_G, "sjson")
end

local function encode_json(value)
  local c = codec()
  if not c or not c.encode then return nil end
  local ok, raw = pcall(c.encode, value)
  if ok and type(raw) == "string" then return raw end
  return nil
end

local function decode_json(raw)
  if type(raw) ~= "string" or raw == "" then
    return nil
  end
  local c = codec()
  if not c or not c.decode then
    return nil
  end
  local ok, value = pcall(c.decode, raw)
  if ok and type(value) == "table" then
    return value
  end
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

local function read_settings()
  return decode_json(read_text(SETTINGS_PATH)) or {}
end

local function write_settings_patch(values)
  local doc = read_settings()
  for key, value in pairs(values or {}) do
    doc[key] = value
  end
  doc.saved_at_ms = clock_ms()
  local raw = encode_json(doc)
  return raw and write_text(SETTINGS_PATH, raw)
end

local function get_brightness()
  if not sys or not sys.getbrightness then
    return nil, "sys.getbrightness unavailable"
  end
  local ok, level = pcall(sys.getbrightness)
  if not ok then
    return nil, tostring(level or "brightness read failed")
  end
  return clamp(level, 0, 100) or 0
end

local function set_brightness(level)
  local target = clamp(level, 0, 100)
  if not target then
    return nil, "invalid brightness"
  end
  if not sys or not sys.setbrightness then
    return nil, "sys.setbrightness unavailable"
  end
  local ok_call, ok_set, err = pcall(sys.setbrightness, target)
  if not ok_call or ok_set == false then
    return nil, tostring(err or ok_set or "brightness set failed")
  end
  return { accepted = true, brightness = target }
end

local function listen_hidpad()
  if HIDPAD.listening then
    return true
  end
  if not ipc or not ipc.listen then
    return false
  end
  local ok_call, listened = pcall(function()
    return ipc.listen(HIDPAD_REPLY_ENDPOINT, function(topic, payload)
      if topic ~= "status" or type(payload) ~= "string" then
        return
      end
      local status = decode_json(payload)
      if type(status) == "table" then
        HIDPAD.status = status
        HIDPAD.status_ms = clock_ms()
      end
    end)
  end)
  HIDPAD.listening = ok_call and listened == true
  return HIDPAD.listening
end

local function send_hidpad_command(topic)
  if not hidpad_installed() then
    return nil, "hidpad service unavailable"
  end
  if not ipc or not ipc.send then
    return nil, "ipc.send unavailable"
  end
  listen_hidpad()
  local payload = encode_json({ reply = HIDPAD_REPLY_ENDPOINT })
  if not payload then
    return nil, "json encode unavailable"
  end
  local ok_call, sent, send_err = pcall(function()
    return ipc.send(HIDPAD_ENDPOINT, topic, payload)
  end)
  if not ok_call or not sent then
    return nil, tostring(send_err or sent or "hidpad command failed")
  end
  return true
end

local function request_hidpad_status()
  local running = service_running(HIDPAD_SERVICE_ID)
  if running then
    send_hidpad_command("status")
  end
  local stamp = clock_ms()
  local fresh = type(HIDPAD.status) == "table"
    and stamp >= HIDPAD.status_ms
    and (stamp - HIDPAD.status_ms) <= HIDPAD_STATUS_TTL_MS
  return running, fresh and HIDPAD.status or nil
end

local function bluetooth_status_from_hidpad()
  local available = hidpad_installed()
  local running, status = request_hidpad_status()
  if not available then
    return {
      available = false,
      enabled = false,
      connected = false,
      connecting = false,
      status = "unavailable",
    }
  end
  local result = {
    available = true,
    enabled = running,
    connected = false,
    connecting = false,
    status = running and "on" or "off",
  }
  if type(status) == "table" then
    result.enabled = status.enabled ~= false
    result.connected = status.connected == true
    result.connecting = status.connecting == true
    result.phase = status.phase
    result.name = status.name
    result.address = status.address
    result.profile = status.profile
    result.buttons = tonumber(status.buttons) or 0
    result.raw_buttons = tonumber(status.raw_buttons) or 0
    result.scan_count = tonumber(status.scan_count) or 0
    result.error = status.error
    if result.connected then
      result.status = "connected"
    elseif result.connecting or status.phase == "connecting" then
      result.status = "connecting"
    elseif status.phase == "scanning" or status.phase == "select_device" then
      result.status = "scanning"
    elseif not result.enabled or status.phase == "disabled" then
      result.status = "off"
    else
      result.status = "on"
    end
  elseif gamepad and gamepad.state then
    local ok, state = pcall(gamepad.state)
    if ok and type(state) == "table" then
      result.enabled = state.started and true or running
      result.connected = state.connected and true or false
      result.connecting = state.connecting and true or false
      result.name = state.name
      result.address = state.address or state.last_address
      result.profile = state.profile
      if result.connected then
        result.status = "connected"
      elseif result.connecting then
        result.status = "connecting"
      elseif result.enabled then
        result.status = "on"
      end
    end
  end
  return result
end

local function get_bluetooth_status()
  local status = bluetooth_status_from_hidpad()
  if status.available or not gamepad or not gamepad.state then
    return status
  end
  local ok, state = pcall(gamepad.state)
  if not ok or type(state) ~= "table" then
    return {
      available = true,
      enabled = false,
      connected = false,
      connecting = false,
      status = "error",
      error = tostring(state or "gamepad.state failed"),
    }
  end
  local connected = state.connected and true or false
  local connecting = state.connecting and true or false
  local enabled = state.started and true or false
  local status = "off"
  if connected then
    status = "connected"
  elseif connecting then
    status = "connecting"
  elseif enabled then
    status = "on"
  end
  return {
    available = true,
    enabled = enabled,
    connected = connected,
    connecting = connecting,
    status = status,
    name = state.name,
    address = state.address or state.last_address,
    profile = state.profile,
  }
end

local function set_bluetooth_enabled(enabled)
  enabled = enabled and true or false
  if hidpad_installed() then
    if enabled and not service_running(HIDPAD_SERVICE_ID) then
      if not app or not app.start_service then
        return nil, "app.start_service unavailable"
      end
      local ok_call, started, start_err = pcall(function()
        return app.start_service(HIDPAD_SERVICE_ID)
      end)
      if not ok_call or not started then
        return nil, tostring(start_err or started or "hidpad service start failed")
      end
    end
    if service_running(HIDPAD_SERVICE_ID) then
      local sent, send_err = send_hidpad_command(enabled and "enable" or "disable")
      if not sent then
        return nil, send_err
      end
    elseif not enabled then
      return {
        accepted = true,
        available = true,
        enabled = false,
        connected = false,
        connecting = false,
        status = "off",
      }
    end
    local status = get_bluetooth_status()
    status.accepted = true
    status.enabled = enabled
    return status
  end

  if gamepad then
    if enabled then
      if gamepad.off then pcall(gamepad.off) end
      if not gamepad.start then return nil, "gamepad.start unavailable" end
      local ok_call, ok_start, err = pcall(function()
        return gamepad.start({ clear_bonds = false, debug = false })
      end)
      if not ok_call or ok_start == false then
        return nil, tostring(err or ok_start or "bluetooth start failed")
      end
    else
      if gamepad.off then pcall(gamepad.off) end
      if not gamepad.stop then return nil, "gamepad.stop unavailable" end
      local ok_call, err = pcall(gamepad.stop)
      if not ok_call then
        return nil, tostring(err or "bluetooth stop failed")
      end
    end
    local status = get_bluetooth_status()
    status.accepted = true
    status.enabled = enabled
    return status
  end

  return nil, "bluetooth api unavailable"
end

local function wifi_mode_text(mode)
  if not wifi then return tostring(mode or "unknown") end
  if mode == wifi.NULLMODE then return "off" end
  if mode == wifi.STATION then return "sta" end
  if mode == wifi.SOFTAP then return "ap" end
  if mode == wifi.STATIONAP then return "sta+ap" end
  return tostring(mode or "unknown")
end

local function get_wifi_status()
  local result = {
    available = wifi ~= nil,
    enabled = false,
    mode = "unavailable",
    sta_connected = false,
    ap_enabled = false,
  }
  if not wifi or not wifi.getmode then
    return result
  end

  local ok_mode, mode = pcall(wifi.getmode)
  if ok_mode then
    result.raw_mode = mode
    result.mode = wifi_mode_text(mode)
    result.enabled = mode ~= wifi.NULLMODE
    result.ap_enabled = mode == wifi.SOFTAP or mode == wifi.STATIONAP
  end

  if wifi.sta then
    if wifi.sta.getip then
      local ok_ip, ip = pcall(wifi.sta.getip)
      if ok_ip and type(ip) == "string" and ip ~= "" then
        result.sta_ip = ip
        result.ip_address = ip
        result.sta_connected = true
      end
    end
    if wifi.sta.getconfig then
      local ok_cfg, cfg = pcall(wifi.sta.getconfig)
      if ok_cfg and type(cfg) == "table" then
        result.ssid = cfg.ssid
      end
    end
  end
  if wifi.ap and wifi.ap.getip then
    local ok_ap, ap_ip = pcall(wifi.ap.getip)
    if ok_ap and type(ap_ip) == "string" and ap_ip ~= "" then
      result.ap_ip = ap_ip
      if not result.ip_address then result.ip_address = ap_ip end
    end
  end
  return result
end

local function set_wifi_ap_enabled(enabled)
  enabled = enabled and true or false
  if not wifi or not wifi.getmode or not wifi.mode then
    return nil, "wifi api unavailable"
  end
  local ok_mode, current = pcall(wifi.getmode)
  if not ok_mode then
    return nil, tostring(current or "wifi.getmode failed")
  end

  local target = current
  if enabled then
    if current == wifi.NULLMODE then
      target = wifi.SOFTAP
    elseif current == wifi.STATION then
      target = wifi.STATIONAP
    elseif current == wifi.SOFTAP or current == wifi.STATIONAP then
      target = current
    else
      target = wifi.STATIONAP
    end
  else
    if current == wifi.SOFTAP then
      target = wifi.NULLMODE
    elseif current == wifi.STATIONAP then
      target = wifi.STATION
    else
      target = current
    end
  end

  local ok_set, ok_result, err = pcall(function()
    return wifi.mode(target, false)
  end)
  if not ok_set or ok_result == false then
    return nil, tostring(err or ok_result or "wifi.mode failed")
  end
  if wifi.start and target ~= wifi.NULLMODE then
    pcall(function() wifi.start() end)
  elseif wifi.stop and target == wifi.NULLMODE then
    pcall(function() wifi.stop() end)
  end
  if wifi.sta and wifi.sta.connect and (target == wifi.STATION or target == wifi.STATIONAP) then
    pcall(function() wifi.sta.connect() end)
  end
  write_settings_patch({ ap_enabled = enabled })

  local status = get_wifi_status()
  status.accepted = true
  status.ap_enabled = enabled
  return status
end

local function installed_apps()
  if not app or not app.list then
    return nil, "app api unavailable"
  end
  local ok, list = pcall(app.list)
  if not ok or type(list) ~= "table" then
    return nil, tostring(list or "failed to list apps")
  end
  local result = {}
  for _, item in ipairs(list) do
    if type(item) == "table" and item.id then
      result[#result + 1] = {
        id = tostring(item.id),
        name = tostring(item.name or item.id),
        description = tostring(item.description or ""),
      }
    end
  end
  return result
end

local function read_wake_service_config()
  return decode_json(read_text("/sd/apps/xiaozhi-service/service.json"))
    or decode_json(read_text("/sd/apps/xiaozhi-service/service.example.json"))
    or {}
end

local function app_allows_wake_service(app_id)
  local cfg = read_wake_service_config()
  app_id = type(app_id) == "string" and app_id or ""
  if type(cfg.deny_apps) == "table" and cfg.deny_apps[app_id] == true then
    return false
  end
  return true
end

local function sync_time(server)
  if not time or type(time.initntp) ~= "function" then
    return nil, "time.initntp unavailable"
  end
  server = type(server) == "string" and server:match("^%s*(.-)%s*$") or ""
  if server == "" then
    server = NTP_SERVERS[1]
  end
  if not server:match("^[%w_.%-]+$") then
    return nil, "invalid ntp server"
  end
  local ok, result = pcall(time.initntp, server)
  if not ok then
    return nil, tostring(result or "ntp request failed")
  end
  if result == false then
    return nil, "ntp request rejected"
  end
  return { accepted = true, server = server }
end

local function launch_app(arguments, ctx)
  arguments = type(arguments) == "table" and arguments or {}
  local app_id = arguments.app_id
  if type(app_id) ~= "string" or app_id == "" or #app_id > 64 or not app_id:match("^[%w_.%-]+$") then
    return nil, "invalid app_id"
  end
  local list, err = installed_apps()
  if not list then return nil, err end
  local found = false
  for _, item in ipairs(list) do
    if item.id == app_id then found = true break end
  end
  if not found then return nil, "app not installed: " .. app_id end

  if not tmr or not tmr.create then
    return nil, "timer api unavailable"
  end
  local allow_wake_service = app_allows_wake_service(app_id)
  local timer = tmr.create()
  timer:alarm(250, tmr.ALARM_SINGLE, function(instance)
    pcall(function() instance:unregister() end)
    local handled = false
    if ctx.before_app_exit then
      local prepare_ok, prepare_ret = pcall(ctx.before_app_exit, app_id, allow_wake_service)
      if not prepare_ok then
        print("[xiaozhi] mcp app switch prepare failed", tostring(prepare_ret))
      elseif prepare_ret == true then
        handled = true
      end
    end
    if handled then
      print("[xiaozhi] mcp launch handled", app_id)
      return
    end
    local ok_launch, launch_err = app.launch(app_id)
    print("[xiaozhi] mcp launch", app_id, tostring(ok_launch), tostring(launch_err or ""))
  end)
  return { accepted = true, app_id = app_id, allow_wake_service = allow_wake_service }
end

M.handlers = {
  ["device.get_status"] = function(arguments, ctx)
    local cfg = ctx.cfg or {}
    local ok, identity = pcall(dofile, (cfg.APP_DIR or "/sd/apps/xiaozhi-service") .. "/identity.lua")
    if not ok or type(identity) ~= "table" or not identity.system_info then
      return ctx.error_result("identity module unavailable")
    end
    local status_ok, status = pcall(identity.system_info, cfg)
    if not status_ok or type(status) ~= "table" then
      return ctx.error_result(status or "failed to read device status")
    end
    if wifi and wifi.sta and wifi.sta.getip then
      local ok_ip, ip = pcall(wifi.sta.getip)
      if ok_ip then status.ip_address = ip end
    end
    status.network = get_wifi_status()
    local brightness = get_brightness()
    if type(status.display) ~= "table" then
      status.display = {}
    end
    status.display.brightness = brightness
    status.bluetooth = get_bluetooth_status()
    return ctx.text_result(status)
  end,

  ["device.list_apps"] = function(arguments, ctx)
    local list, err = installed_apps()
    return list and ctx.text_result({ apps = list }) or ctx.error_result(err)
  end,

  ["device.sync_time"] = function(arguments, ctx)
    local result, err = sync_time(arguments.server)
    return result and ctx.text_result(result) or ctx.error_result(err)
  end,

  ["device.launch_app"] = function(arguments, ctx)
    local result, err = launch_app(arguments, ctx)
    return result and ctx.text_result(result) or ctx.error_result(err)
  end,

  ["device.set_brightness"] = function(arguments, ctx)
    local result, err = set_brightness(arguments.brightness)
    return result and ctx.text_result(result) or ctx.error_result(err)
  end,

  ["device.set_wifi_ap"] = function(arguments, ctx)
    local result, err = set_wifi_ap_enabled(arguments.enabled)
    return result and ctx.text_result(result) or ctx.error_result(err)
  end,

  ["device.set_bluetooth"] = function(arguments, ctx)
    local result, err = set_bluetooth_enabled(arguments.enabled)
    return result and ctx.text_result(result) or ctx.error_result(err)
  end,
}

return M
