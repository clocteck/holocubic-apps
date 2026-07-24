if _G.DISPLAY_SCHEDULE_SERVICE and _G.DISPLAY_SCHEDULE_SERVICE.stop then
  pcall(function()
    _G.DISPLAY_SCHEDULE_SERVICE.stop("reload")
  end)
end

DISPLAY_SCHEDULE_SERVICE = {
  VERSION = "1.0.5",
  SETTINGS_PATH = "/sd/apps/settings.json",
  DIM_BRIGHTNESS = 5,
  timers = {},
  routes = {},
  key_codes = {},
  enabled = false,
  mode = "off",
  sleep_hour = 0,
  sleep_minute = 0,
  wake_hour = 7,
  wake_minute = 0,
  normal_brightness = 80,
  window_active = nil,
  scheduled_sleeping = false,
  settings_signature = "",
  alarms = {},
  alarm_ringing = false,
  alarm_started_ms = 0,
  alarm_last_trigger = {},
  alarm_audio_started = false,
  imu_registered = false,
  imu_sample = nil,
  tick_count = 0,
}

local APP = DISPLAY_SCHEDULE_SERVICE

local function write_status(stage)
  if not file or not file.putcontents then return end
  local line = table.concat({
    "version=" .. APP.VERSION,
    "stage=" .. tostring(stage or "unknown"),
    "routes=" .. tostring(#APP.routes),
    "imu=" .. tostring(APP.imu_registered),
    "enabled=" .. tostring(APP.enabled),
    "alarms=" .. tostring(#APP.alarms),
  }, "\n") .. "\n"
  pcall(function()
    file.putcontents("/sd/apps/display_schedule/status.txt", line)
  end)
end

local function clamp(value, min_value, max_value, fallback)
  local number = tonumber(value)
  if number == nil then number = fallback end
  number = math.floor(number)
  if number < min_value then number = min_value end
  if number > max_value then number = max_value end
  return number
end

local function bool_value(value, fallback)
  if type(value) == "boolean" then return value end
  if type(value) == "number" then return value ~= 0 end
  local text = tostring(value or ""):lower()
  if text == "true" or text == "1" or text == "on" or text == "enabled" then return true end
  if text == "false" or text == "0" or text == "off" or text == "disabled" then return false end
  return fallback
end

local function json_response(value)
  local codec = rawget(_G, "json") or rawget(_G, "sjson")
  local ok, body = false, nil
  if codec and codec.encode then
    ok, body = pcall(function() return codec.encode(value) end)
  end
  if not ok or type(body) ~= "string" then
    body = "{\"ok\":false,\"error\":\"json encode failed\"}"
  end
  return {
    status = ok and "200 OK" or "500 Internal Server Error",
    type = "application/json; charset=utf-8",
    headers = { ["cache-control"] = "no-store", ["connection"] = "close" },
    body = body,
  }
end

local function read_settings()
  if not file or not file.getcontents then return {} end
  local ok, raw = pcall(function() return file.getcontents(APP.SETTINGS_PATH) end)
  if not ok or type(raw) ~= "string" or raw == "" then return {} end
  local codec = rawget(_G, "json") or rawget(_G, "sjson")
  if not codec or not codec.decode then return {} end
  local decoded, doc = pcall(function() return codec.decode(raw) end)
  if not decoded or type(doc) ~= "table" then return {} end
  return doc
end

local function set_brightness(value)
  if not sys or not sys.setbrightness then return false end
  return pcall(function() sys.setbrightness(value) end)
end

local function now_ms()
  if millis then
    local ok, value = pcall(millis)
    if ok and tonumber(value) then return tonumber(value) end
  end
  return 0
end

local function weekday_from_date(year, month, day)
  local y = tonumber(year)
  local m = tonumber(month)
  local d = tonumber(day)
  if not y or not m or not d then return nil end
  if m < 3 then
    m = m + 12
    y = y - 1
  end
  local century = math.floor(y / 100)
  local year_of_century = y % 100
  local zeller = (d + math.floor(13 * (m + 1) / 5) + year_of_century
    + math.floor(year_of_century / 4) + math.floor(century / 4) + 5 * century) % 7
  return ((zeller + 6) % 7) + 1
end

local function local_clock()
  if time and time.getlocal then
    local ok, calendar = pcall(function() return time.getlocal() end)
    if ok and type(calendar) == "table" then
      local year = tonumber(calendar.year or calendar.y)
      local hour = tonumber(calendar.hour)
      local minute = tonumber(calendar.min or calendar.minute)
      local month = tonumber(calendar.mon or calendar.month) or 1
      local day = tonumber(calendar.day or calendar.mday) or 1
      local wday = weekday_from_date(year, month, day)
      local yday = tonumber(calendar.yday or calendar.yearday)
      if year and year >= 2020 and hour and minute then
        return {
          year = year,
          mon = month,
          day = day,
          hour = hour,
          min = minute,
          wday = wday,
          yday = yday,
        }
      end
    end
  end
  if os and os.date then
    local ok, calendar = pcall(os.date, "*t")
    if ok and type(calendar) == "table" and tonumber(calendar.year) and tonumber(calendar.year) >= 2020 then
      return calendar
    end
  end
  return nil
end

local function inside_schedule(clock)
  if not APP.enabled or type(clock) ~= "table" then return false end
  local sleep_at = APP.sleep_hour * 60 + APP.sleep_minute
  local wake_at = APP.wake_hour * 60 + APP.wake_minute
  local now = (tonumber(clock.hour) or 0) * 60 + (tonumber(clock.min) or 0)
  if sleep_at == wake_at then return false end
  if sleep_at < wake_at then
    return now >= sleep_at and now < wake_at
  end
  return now >= sleep_at or now < wake_at
end

local function normalize_repeat(value)
  local text = tostring(value or "daily")
  local allowed = {
    daily = true, weekdays = true, weekend = true,
    mon = true, tue = true, wed = true, thu = true,
    fri = true, sat = true, sun = true,
  }
  return allowed[text] and text or "daily"
end

local function normalize_alarms(value)
  local output = {}
  for index = 1, 3 do
    local item = type(value) == "table" and type(value[index]) == "table" and value[index] or {}
    output[index] = {
      enabled = bool_value(item.enabled, false),
      hour = clamp(item.hour, 0, 23, index == 1 and 7 or (index == 2 and 8 or 9)),
      minute = clamp(item.minute, 0, 59, 0),
      repeat_rule = normalize_repeat(item["repeat"]),
    }
  end
  return output
end

local function alarm_matches_day(repeat_rule, wday)
  local day = tonumber(wday)
  if repeat_rule == "daily" then return true end
  if day == nil then return false end
  if repeat_rule == "weekdays" then return day >= 2 and day <= 6 end
  if repeat_rule == "weekend" then return day == 1 or day == 7 end
  local days = { sun = 1, mon = 2, tue = 3, wed = 4, thu = 5, fri = 6, sat = 7 }
  return days[repeat_rule] == day
end

local function alarm_day_key(clock)
  return table.concat({
    tonumber(clock.year) or 0,
    tonumber(clock.yday) or tonumber(clock.mon) or 0,
    tonumber(clock.day) or 0,
    tonumber(clock.hour) or 0,
    tonumber(clock.min) or 0,
  }, "-")
end

local function make_tone(frequency, duration_ms)
  local rate = 16000
  local samples = math.floor(rate * duration_ms / 1000)
  local chunks = {}
  for sample_index = 0, samples - 1 do
    local envelope = math.min(1, sample_index / 120, (samples - sample_index) / 120)
    local value = math.floor(math.sin(sample_index * 2 * math.pi * frequency / rate) * 9500 * envelope)
    if value < 0 then value = value + 65536 end
    chunks[#chunks + 1] = string.char(value % 256, math.floor(value / 256) % 256)
  end
  return table.concat(chunks)
end

local ALARM_TONE_HIGH = make_tone(880, 150)
local ALARM_TONE_LOW = make_tone(660, 150)
local alarm_tone_phase = false

local function start_alarm_audio()
  if APP.alarm_audio_started then return true end
  if not i2s or not i2s.start or not i2s.write then return false end
  pcall(function() i2s.stop(0) end)
  local channel = i2s.CHANNEL_ONLY_LEFT or i2s.CHANNEL_RIGHT_LEFT
  local ok = pcall(function()
    i2s.start(0, {
      mode = i2s.MODE_MASTER | i2s.MODE_TX,
      rate = 16000,
      bits = 16,
      channel = channel,
      format = i2s.FORMAT_I2S,
      buffer_count = 4,
      buffer_len = 512,
      data_out_pin = 48,
    })
  end)
  APP.alarm_audio_started = ok
  return ok
end

local function stop_alarm()
  if APP.alarm_audio_started and i2s and i2s.stop then
    pcall(function() i2s.stop(0) end)
  end
  APP.alarm_audio_started = false
  APP.alarm_ringing = false
  APP.alarm_started_ms = 0
end

local function start_alarm()
  APP.alarm_ringing = true
  APP.alarm_started_ms = now_ms()
  wake_display()
  start_alarm_audio()
end

local function ring_alarm()
  if not APP.alarm_ringing then return end
  if APP.alarm_started_ms > 0 and now_ms() - APP.alarm_started_ms >= 10 * 60 * 1000 then
    stop_alarm()
    return
  end
  if not start_alarm_audio() then return end
  alarm_tone_phase = not alarm_tone_phase
  pcall(function()
    i2s.write(0, alarm_tone_phase and ALARM_TONE_HIGH or ALARM_TONE_LOW)
  end)
end

local function check_alarms(clock)
  if type(clock) ~= "table" then return end
  local trigger_key = alarm_day_key(clock)
  for index, alarm in ipairs(APP.alarms) do
    if alarm.enabled
        and alarm.hour == tonumber(clock.hour)
        and alarm.minute == tonumber(clock.min)
        and alarm_matches_day(alarm.repeat_rule, clock.wday)
        and APP.alarm_last_trigger[index] ~= trigger_key then
      APP.alarm_last_trigger[index] = trigger_key
      start_alarm()
    end
  end
end

local function api_info()
  local clock = local_clock()
  local current_brightness = nil
  if sys and sys.getbrightness then
    local ok, value = pcall(function() return sys.getbrightness() end)
    if ok then current_brightness = tonumber(value) end
  end
  return json_response({
    ok = true,
    version = APP.VERSION,
    scheduled_sleep_enabled = APP.enabled,
    scheduled_sleep_mode = APP.mode,
    scheduled_sleep_hour = APP.sleep_hour,
    scheduled_sleep_minute = APP.sleep_minute,
    scheduled_wake_hour = APP.wake_hour,
    scheduled_wake_minute = APP.wake_minute,
    scheduled_window_active = inside_schedule(clock),
    scheduled_sleeping = APP.scheduled_sleeping,
    alarm_ringing = APP.alarm_ringing,
    alarm_count = #APP.alarms,
    clock = clock,
    imu_registered = APP.imu_registered,
    current_brightness = current_brightness,
    normal_brightness = APP.normal_brightness,
  })
end

local function sleep_display()
  local brightness = APP.mode == "dim" and APP.DIM_BRIGHTNESS or 0
  if set_brightness(brightness) then
    APP.scheduled_sleeping = true
  end
end

local function wake_display()
  if http and http.post then
    pcall(function()
      http.post("http://127.0.0.1/display/api/wake", {
        timeout = 600,
        bufsz = 256,
        max_redirects = 0,
      }, "")
    end)
  end
  set_brightness(APP.normal_brightness)
  APP.scheduled_sleeping = false
end

APP.sleep_now = sleep_display
APP.wake_now = wake_display

local function api_wake()
  wake_display()
  return api_info()
end

local function sync_settings()
  local settings = read_settings()
  local previous_enabled = APP.enabled
  local previous_mode = APP.mode
  local previous_sleep_hour = APP.sleep_hour
  local previous_sleep_minute = APP.sleep_minute
  local previous_wake_hour = APP.wake_hour
  local previous_wake_minute = APP.wake_minute

  APP.enabled = bool_value(settings.scheduled_sleep_enabled, false)
  APP.mode = tostring(settings.scheduled_sleep_mode or "off") == "dim" and "dim" or "off"
  APP.sleep_hour = clamp(settings.scheduled_sleep_hour, 0, 23, 0)
  APP.sleep_minute = clamp(settings.scheduled_sleep_minute, 0, 59, 0)
  APP.wake_hour = clamp(settings.scheduled_wake_hour, 0, 23, 7)
  APP.wake_minute = clamp(settings.scheduled_wake_minute, 0, 59, 0)
  APP.normal_brightness = clamp(settings.brightness or settings.display_brightness, 1, 100, 80)
  APP.alarms = normalize_alarms(settings.alarms)

  local timezone = tostring(settings.timezone or "")
  if timezone ~= "" and time and time.settimezone then
    pcall(function() time.settimezone(timezone) end)
  end

  local signature = table.concat({
    tostring(APP.enabled), APP.mode,
    APP.sleep_hour, APP.sleep_minute,
    APP.wake_hour, APP.wake_minute,
    APP.normal_brightness, timezone,
  }, ":")
  local changed = signature ~= APP.settings_signature
  APP.settings_signature = signature
  if not changed then return end

  local clock = local_clock()
  local active = inside_schedule(clock)
  local schedule_changed = previous_enabled ~= APP.enabled
    or previous_sleep_hour ~= APP.sleep_hour
    or previous_sleep_minute ~= APP.sleep_minute
    or previous_wake_hour ~= APP.wake_hour
    or previous_wake_minute ~= APP.wake_minute

  if not APP.enabled then
    if APP.scheduled_sleeping then wake_display() end
    APP.window_active = false
    return
  end
  if active and (APP.window_active == nil or schedule_changed) then
    sleep_display()
  elseif not active and APP.scheduled_sleeping then
    wake_display()
  elseif active and APP.scheduled_sleeping and previous_mode ~= APP.mode then
    sleep_display()
  end
  APP.window_active = active
end

local function tick()
  APP.tick_count = (APP.tick_count + 1) % 5
  if APP.tick_count == 0 then sync_settings() end
  local clock = local_clock()
  if clock == nil then return end
  check_alarms(clock)
  local active = inside_schedule(clock)
  if APP.window_active == nil then
    APP.window_active = active
    if active then sleep_display() end
    return
  end
  if active ~= APP.window_active then
    APP.window_active = active
    if active then
      sleep_display()
    else
      wake_display()
    end
  end
end

local function handle_imu(roll, pitch, gx, gy, gz)
  local sample = {
    roll = tonumber(roll) or 0,
    pitch = tonumber(pitch) or 0,
    gx = tonumber(gx) or 0,
    gy = tonumber(gy) or 0,
    gz = tonumber(gz) or 0,
  }
  local previous = APP.imu_sample
  APP.imu_sample = sample
  if not previous then return end
  local gyro_peak = math.max(math.abs(sample.gx), math.abs(sample.gy), math.abs(sample.gz))
  local angle_delta = math.max(
    math.abs(sample.roll - previous.roll),
    math.abs(sample.pitch - previous.pitch)
  )
  if APP.scheduled_sleeping and (gyro_peak >= 80 or angle_delta >= 2.5) then
    wake_display()
    return
  end
  if not APP.alarm_ringing then return end
  if gyro_peak >= 180 or angle_delta >= 12 then
    stop_alarm()
  end
end

function APP.stop(reason)
  for i = #APP.routes, 1, -1 do
    local item = APP.routes[i]
    pcall(function() httpd.unregister(item.method, item.route) end)
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
      pcall(function() key.off(code) end)
    end
  end
  APP.key_codes = {}
  if app and app.on and APP.imu_registered then
    pcall(function() app.on("imu", nil) end)
  end
  APP.imu_registered = false
  stop_alarm()
  print("[display_schedule] stop", tostring(reason or ""))
end

sync_settings()

if httpd and httpd.dynamic then
  local route = "/display-schedule/api/info"
  local ok, err = pcall(function() return httpd.dynamic(httpd.GET, route, api_info) end)
  if ok and not err then
    APP.routes[#APP.routes + 1] = { method = httpd.GET, route = route }
  end
  local wake_route = "/display-schedule/api/wake"
  for _, method in ipairs({ httpd.GET, httpd.POST }) do
    local wake_ok, wake_err = pcall(function() return httpd.dynamic(method, wake_route, api_wake) end)
    if wake_ok and not wake_err then
      APP.routes[#APP.routes + 1] = { method = method, route = wake_route }
    end
  end
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
          if APP.alarm_ringing and code == key.HOME then
            stop_alarm()
            return true
          end
          if APP.scheduled_sleeping then
            wake_display()
            return true
          end
          return false
        end)
      end)
    end
  end
end

if app and app.on then
  local ok = pcall(function()
    app.on("imu", function(name, roll, pitch, gx, gy, gz)
      handle_imu(roll, pitch, gx, gy, gz)
    end)
  end)
  APP.imu_registered = ok
end

if tmr and tmr.create then
  local timer = tmr.create()
  APP.timers[#APP.timers + 1] = timer
  timer:alarm(1000, tmr.ALARM_AUTO, tick)
  local alarm_timer = tmr.create()
  APP.timers[#APP.timers + 1] = alarm_timer
  alarm_timer:alarm(450, tmr.ALARM_AUTO, ring_alarm)
end

print("[display_schedule] ready", APP.VERSION, tostring(APP.enabled))
write_status("ready")
