if _G.DISPLAY_SERVICE and _G.DISPLAY_SERVICE.stop then
  pcall(function()
    _G.DISPLAY_SERVICE.stop("reload")
  end)
end

DISPLAY_SERVICE = {
  VERSION = "1.0.4",
  ROUTE_BASE = "/display",
  SETTINGS_PATH = "/sd/apps/settings.json",
  SLEEP_BRIGHTNESS = 5,
  routes = {},
  timers = {},
  brightness = 80,
  auto_sleep_enabled = false,
  auto_sleep_seconds = 1800,
  sleeping = false,
  last_activity_ms = 0,
  key_codes = {},
  motion_sample = nil,
  motion_wake_enabled = false,
  imu_registered = false,
  imu_sample = nil,
}

local APP = DISPLAY_SERVICE

local function text_or(value, fallback)
  if value == nil or value == "" then
    return fallback or ""
  end
  return tostring(value)
end

local function clamp(value, min_value, max_value, fallback)
  local num = tonumber(value)
  if num == nil then
    num = fallback
  end
  if num < min_value then
    num = min_value
  elseif num > max_value then
    num = max_value
  end
  return math.floor(num + 0.5)
end

local function bool_value(value, fallback)
  if type(value) == "boolean" then
    return value
  end
  if type(value) == "number" then
    return value ~= 0
  end
  local text = tostring(value or ""):lower()
  if text == "true" or text == "1" or text == "on" or text == "enabled" then
    return true
  end
  if text == "false" or text == "0" or text == "off" or text == "disabled" then
    return false
  end
  return fallback == true
end

local function now_ms()
  local fn = rawget(_G, "millis")
  if type(fn) == "function" then
    local ok, value = pcall(fn)
    if ok and type(value) == "number" then
      return value
    end
  end
  if sys and sys.millis then
    local ok, value = pcall(function()
      return sys.millis()
    end)
    if ok and type(value) == "number" then
      return value
    end
  end
  if tmr and tmr.now then
    local ok, value = pcall(function()
      return tmr.now()
    end)
    if ok and type(value) == "number" then
      return math.floor(value / 1000)
    end
  end
  return 0
end

local function url_decode(text)
  text = text_or(text, "")
  text = text:gsub("+", " ")
  text = text:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
  return text
end

local function parse_query(query)
  local out = {}
  for pair in text_or(query, ""):gmatch("([^&]+)") do
    local key, value = pair:match("^([^=]*)=(.*)$")
    if not key then
      key = pair
      value = ""
    end
    out[url_decode(key)] = url_decode(value)
  end
  return out
end

local function json_response(status, value)
  local ok, raw = pcall(function()
    return json.encode(value)
  end)
  if not ok or not raw then
    raw = "{\"ok\":false,\"error\":\"json encode failed\"}"
    status = "500 Internal Server Error"
  end
  return {
    status = status or "200 OK",
    type = "application/json; charset=utf-8",
    headers = {
      ["cache-control"] = "no-store",
      ["connection"] = "close",
    },
    body = raw,
  }
end

local function read_settings()
  if not file or not file.getcontents then
    return {}
  end
  local ok, raw = pcall(function()
    return file.getcontents(APP.SETTINGS_PATH)
  end)
  if not ok or type(raw) ~= "string" or raw == "" then
    return {}
  end
  local codec = rawget(_G, "json") or rawget(_G, "sjson")
  if not codec or not codec.decode then
    return {}
  end
  local decoded, doc = pcall(function()
    return codec.decode(raw)
  end)
  if decoded and type(doc) == "table" then
    return doc
  end
  return {}
end

local function apply_brightness(value)
  local target = clamp(value, 1, 100, APP.brightness)
  if not sys or not sys.setbrightness then
    return false, "sys.setbrightness unavailable"
  end
  local ok, result = pcall(function()
    return sys.setbrightness(target)
  end)
  if not ok or result == false then
    return false, text_or(result, "setbrightness failed")
  end
  APP.brightness = target
  APP.sleeping = false
  return true
end

local function sleep_display()
  if APP.sleeping or not APP.auto_sleep_enabled then
    return
  end
  if not sys or not sys.setbrightness then
    return
  end
  local ok, result = pcall(function()
    return sys.setbrightness(APP.SLEEP_BRIGHTNESS)
  end)
  if ok and result ~= false then
    APP.sleeping = true
  end
end

local function wake_display()
  APP.last_activity_ms = now_ms()
  if APP.sleeping then
    apply_brightness(APP.brightness)
  end
end

local function sample_numbers(...)
  local values = {}
  local argc = select("#", ...)
  for i = 1, argc do
    local value = select(i, ...)
    if type(value) == "number" then
      values[#values + 1] = value
    elseif type(value) == "table" then
      local x = tonumber(value.x or value.ax or value.acc_x or value.accel_x or value.gx or value.gyro_x or value[1])
      local y = tonumber(value.y or value.ay or value.acc_y or value.accel_y or value.gy or value.gyro_y or value[2])
      local z = tonumber(value.z or value.az or value.acc_z or value.accel_z or value.gz or value.gyro_z or value[3])
      if x and y and z then
        values[#values + 1] = x
        values[#values + 1] = y
        values[#values + 1] = z
      end
    end
  end
  if #values >= 3 then
    return { values[1], values[2], values[3] }
  end
  return nil
end

local function call_motion_reader(obj, name)
  if type(obj) ~= "table" or type(obj[name]) ~= "function" then
    return nil
  end
  local ok, a, b, c = pcall(function()
    return obj[name]()
  end)
  if ok then
    local sample = sample_numbers(a, b, c)
    if sample then
      return sample
    end
  end
  ok, a, b, c = pcall(function()
    return obj[name](obj)
  end)
  if ok then
    return sample_numbers(a, b, c)
  end
  return nil
end

local function read_motion_sample()
  local globals = { "imu", "motion", "qmi8658", "qmi", "mpu6050", "mpu", "accel", "accelerometer", "sensor", "sensors" }
  local methods = {
    "read_accel", "get_accel", "accel", "readAccel", "getAccel",
    "read_gyro", "get_gyro", "gyro", "readGyro", "getGyro",
    "read", "get", "get_data", "getData", "read_data", "readData"
  }
  for _, global_name in ipairs(globals) do
    local obj = rawget(_G, global_name)
    if type(obj) == "table" then
      for _, method in ipairs(methods) do
        local sample = call_motion_reader(obj, method)
        if sample then
          return sample
        end
      end
    elseif type(obj) == "function" then
      local ok, a, b, c = pcall(obj)
      if ok then
        local sample = sample_numbers(a, b, c)
        if sample then
          return sample
        end
      end
    end
  end
  return nil
end

local function motion_delta(a, b)
  if not a or not b then
    return 0
  end
  local dx = (tonumber(a[1]) or 0) - (tonumber(b[1]) or 0)
  local dy = (tonumber(a[2]) or 0) - (tonumber(b[2]) or 0)
  local dz = (tonumber(a[3]) or 0) - (tonumber(b[3]) or 0)
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function motion_threshold(sample)
  if not sample then
    return 0.12
  end
  local x = tonumber(sample[1]) or 0
  local y = tonumber(sample[2]) or 0
  local z = tonumber(sample[3]) or 0
  local mag = math.sqrt(x * x + y * y + z * z)
  local threshold = mag * 0.035
  if threshold < 0.12 then
    threshold = 0.12
  end
  return threshold
end

local function poll_motion_activity()
  local sample = read_motion_sample()
  if not sample then
    return
  end
  if not APP.motion_sample then
    APP.motion_sample = sample
    APP.motion_wake_enabled = true
    return
  end
  local delta = motion_delta(sample, APP.motion_sample)
  APP.motion_sample = sample
  if delta >= motion_threshold(sample) then
    wake_display()
  end
end

local function abs_num(value)
  local num = tonumber(value) or 0
  if num < 0 then
    return -num
  end
  return num
end

local function handle_imu_activity(roll, pitch, gx, gy, gz, ts_ms)
  local sample = {
    roll = tonumber(roll) or 0,
    pitch = tonumber(pitch) or 0,
    gx = tonumber(gx) or 0,
    gy = tonumber(gy) or 0,
    gz = tonumber(gz) or 0,
    ts_ms = tonumber(ts_ms) or now_ms(),
  }
  if not APP.imu_sample then
    APP.imu_sample = sample
    return
  end

  local last = APP.imu_sample
  APP.imu_sample = sample

  local d_roll = abs_num(sample.roll - (last.roll or 0))
  local d_pitch = abs_num(sample.pitch - (last.pitch or 0))
  local gyro_peak = math.max(abs_num(sample.gx), abs_num(sample.gy), abs_num(sample.gz))

  -- roll/pitch 单位为度。只把明显姿态变化当作“操作”，避免静止 IMU 高频事件让设备永不休眠。
  if d_roll >= 2.5 or d_pitch >= 2.5 or gyro_peak >= 80 then
    wake_display()
  end
end

local function sync_settings()
  local settings = read_settings()
  local value = settings.brightness or settings.display_brightness
  if value ~= nil then
    apply_brightness(value)
  end
  APP.auto_sleep_enabled = bool_value(settings.auto_sleep_enabled, false)
  APP.auto_sleep_seconds = clamp(settings.auto_sleep_seconds, 60, 86400, 1800)
end

function APP.api_info()
  return json_response("200 OK", {
    ok = true,
    version = APP.VERSION,
    brightness = APP.brightness,
    auto_sleep_enabled = APP.auto_sleep_enabled,
    auto_sleep_seconds = APP.auto_sleep_seconds,
    sleeping = APP.sleeping,
    motion_wake_enabled = APP.motion_wake_enabled,
    imu_registered = APP.imu_registered,
  })
end

function APP.api_brightness(req)
  local q = parse_query(req and req.query or "")
  local value = q.value or q.brightness
  local ok, err = apply_brightness(value)
  if not ok then
    return json_response("400 Bad Request", {
      ok = false,
      error = err,
    })
  end
  return json_response("200 OK", {
    ok = true,
    brightness = APP.brightness,
  })
end

function APP.api_sleep(req)
  local q = parse_query(req and req.query or "")
  APP.auto_sleep_enabled = bool_value(q.enabled, APP.auto_sleep_enabled)
  APP.auto_sleep_seconds = clamp(q.seconds, 60, 86400, APP.auto_sleep_seconds)
  wake_display()
  return json_response("200 OK", {
    ok = true,
    auto_sleep_enabled = APP.auto_sleep_enabled,
    auto_sleep_seconds = APP.auto_sleep_seconds,
  })
end

function APP.api_wake()
  wake_display()
  return json_response("200 OK", {
    ok = true,
    brightness = APP.brightness,
    sleeping = APP.sleeping,
  })
end

function APP.register_route(method, route, handler)
  local err = httpd.dynamic(method, route, handler)
  if err then
    print("[display_service] route failed", route, tostring(err))
    return false
  end
  APP.routes[#APP.routes + 1] = { method = method, route = route }
  return true
end

function APP.stop(reason)
  for i = #APP.routes, 1, -1 do
    local item = APP.routes[i]
    pcall(function()
      httpd.unregister(item.method, item.route)
    end)
  end
  APP.routes = {}
  for i = #APP.timers, 1, -1 do
    local timer = APP.timers[i]
    pcall(function() timer:stop() end)
    pcall(function() timer:unregister() end)
  end
  APP.timers = {}
  if key and key.off then
    for _, code in ipairs(APP.key_codes) do
      pcall(function()
        key.off(code)
      end)
    end
  end
  APP.key_codes = {}
  if app and app.on and APP.imu_registered then
    pcall(function()
      app.on("imu", nil)
    end)
  end
  APP.imu_registered = false
  print("[display_service] stop", text_or(reason, ""))
end

sync_settings()
APP.last_activity_ms = now_ms()

if httpd and httpd.dynamic then
  APP.register_route(httpd.GET, APP.ROUTE_BASE .. "/api/info", APP.api_info)
  APP.register_route(httpd.POST, APP.ROUTE_BASE .. "/api/brightness", APP.api_brightness)
  APP.register_route(httpd.POST, APP.ROUTE_BASE .. "/api/sleep", APP.api_sleep)
  APP.register_route(httpd.GET, APP.ROUTE_BASE .. "/api/wake", APP.api_wake)
  APP.register_route(httpd.POST, APP.ROUTE_BASE .. "/api/wake", APP.api_wake)
end

if key and key.on then
  local codes = { key.LEFT, key.RIGHT, key.UP, key.DOWN, key.HOME }
  local seen = {}
  for _, code in ipairs(codes) do
    if code ~= nil and not seen[code] then
      seen[code] = true
      APP.key_codes[#APP.key_codes + 1] = code
      pcall(function()
        key.on(code, function()
          if APP.sleeping then
            wake_display()
            return true
          end
          wake_display()
          return false
        end)
      end)
    end
  end
end

if app and app.on then
  local ok = pcall(function()
    app.on("imu", function(name, roll, pitch, gx, gy, gz, ts_ms)
      handle_imu_activity(roll, pitch, gx, gy, gz, ts_ms)
    end)
  end)
  if ok then
    APP.imu_registered = true
    APP.motion_wake_enabled = true
  end
end

if tmr and tmr.create then
  local timer = tmr.create()
  APP.timers[#APP.timers + 1] = timer
  timer:alarm(1000, tmr.ALARM_AUTO, function()
    poll_motion_activity()
    if APP.auto_sleep_enabled and not APP.sleeping then
      local idle_ms = now_ms() - APP.last_activity_ms
      if idle_ms >= APP.auto_sleep_seconds * 1000 then
        sleep_display()
      end
    end
  end)
end

print("[display_service] ready", APP.VERSION, "brightness", APP.brightness, "auto_sleep", tostring(APP.auto_sleep_enabled))
