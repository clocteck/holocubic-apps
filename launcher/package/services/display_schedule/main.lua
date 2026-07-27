if _G.DISPLAY_SCHEDULE_SERVICE and _G.DISPLAY_SCHEDULE_SERVICE.stop then
  pcall(function()
    _G.DISPLAY_SCHEDULE_SERVICE.stop("reload")
  end)
end

DISPLAY_SCHEDULE_SERVICE = {
  VERSION = "1.2.1",
  APP_DIR = "/sd/apps/display_schedule",
  PAGE_PATH = "/sd/apps/display_schedule/main.html",
  FIXED_ROUTE_BASE = "/display-schedule",
  ROUTE_BASE = "/display-schedule",
  SETTINGS_PATH = "/sd/apps/settings.json",
  SETTINGS_TEMP_PATH = "/sd/apps/settings.json.tmp",
  SETTINGS_BACKUP_PATH = "/sd/apps/settings.json.bak",
  ALARM_STATE_PATH = "/sd/apps/display_schedule/alarm_state.json",
  AUDIO_MODULE_PATH = "/sd/apps/mp3_player/modules/audio.so",
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
  display_settings_signature = "",
  auto_sleep_enabled = false,
  auto_sleep_seconds = 1800,
  alarms = {},
  alarm_ringing = false,
  alarm_started_ms = 0,
  alarm_last_trigger = {},
  alarm_audio_started = false,
  alarm_audio_mode = "builtin",
  alarm_sound = "builtin",
  alarm_pattern_step = 0,
  alarm_audio = nil,
  imu_registered = false,
  imu_sample = nil,
  tick_count = 0,
}

local APP = DISPLAY_SCHEDULE_SERVICE
local wake_display

if app and app.current then
  local current = app.current()
  local entry = current and current.entry
  local dir = type(entry) == "string" and entry:gsub("\\", "/"):match("^(.*)/[^/]+$") or nil
  if dir and dir ~= "" then
    APP.APP_DIR = dir
    APP.PAGE_PATH = dir .. "/main.html"
  end
end
if app and app.route_base then
  APP.ROUTE_BASE = app.route_base() or APP.ROUTE_BASE
end

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

local function html_response(body)
  return {
    status = "200 OK",
    type = "text/html; charset=utf-8",
    headers = { ["cache-control"] = "no-store", ["connection"] = "close" },
    body = body or "",
  }
end

local function read_body(req, limit)
  if not req or not req.getbody then return "", nil end
  local parts, total = {}, 0
  while true do
    local chunk = req.getbody()
    if not chunk then break end
    total = total + #chunk
    if total > limit then return nil, "request too large" end
    parts[#parts + 1] = chunk
  end
  return table.concat(parts), nil
end

local function write_settings(settings)
  if not file or not file.putcontents then return false, "file.putcontents missing" end
  local codec = rawget(_G, "json") or rawget(_G, "sjson")
  if not codec or not codec.encode then return false, "json.encode missing" end
  local ok, raw = pcall(function() return codec.encode(settings) end)
  if not ok or type(raw) ~= "string" then return false, tostring(raw or "json encode failed") end

  if file.rename and file.remove then
    local temp_ok, temp_result = pcall(function() return file.putcontents(APP.SETTINGS_TEMP_PATH, raw) end)
    if not temp_ok or temp_result == false then return false, tostring(temp_result or "temp write failed") end
    local verify_ok, verify_raw = pcall(function() return file.getcontents(APP.SETTINGS_TEMP_PATH) end)
    if not verify_ok or verify_raw ~= raw then
      pcall(function() file.remove(APP.SETTINGS_TEMP_PATH) end)
      return false, "temp verify failed"
    end

    pcall(function() file.remove(APP.SETTINGS_BACKUP_PATH) end)
    local current_exists = file.exists and file.exists(APP.SETTINGS_PATH)
    if current_exists then
      local backup_ok, backup_result = pcall(function()
        return file.rename(APP.SETTINGS_PATH, APP.SETTINGS_BACKUP_PATH)
      end)
      if not backup_ok or backup_result == false then
        pcall(function() file.remove(APP.SETTINGS_TEMP_PATH) end)
        return false, "settings backup failed"
      end
    end

    local replace_ok, replace_result = pcall(function()
      return file.rename(APP.SETTINGS_TEMP_PATH, APP.SETTINGS_PATH)
    end)
    if not replace_ok or replace_result == false then
      if current_exists then
        pcall(function() file.rename(APP.SETTINGS_BACKUP_PATH, APP.SETTINGS_PATH) end)
      end
      pcall(function() file.remove(APP.SETTINGS_TEMP_PATH) end)
      return false, "settings replace failed"
    end
    return true
  end

  local wrote, result = pcall(function() return file.putcontents(APP.SETTINGS_PATH, raw) end)
  if not wrote or result == false then return false, tostring(result or "write failed") end
  return true
end

local function read_json_file(path)
  if not file or not file.getcontents then return nil end
  local ok, raw = pcall(function() return file.getcontents(path) end)
  if not ok or type(raw) ~= "string" or raw == "" then return nil end
  local codec = rawget(_G, "json") or rawget(_G, "sjson")
  if not codec or not codec.decode then return nil end
  local decoded, doc = pcall(function() return codec.decode(raw) end)
  if not decoded or type(doc) ~= "table" then return nil end
  return doc
end

local function read_settings()
  local settings = read_json_file(APP.SETTINGS_PATH)
  if type(settings) == "table" then return settings end
  local backup = read_json_file(APP.SETTINGS_BACKUP_PATH)
  if type(backup) == "table" then return backup end
  return {}
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

local function apply_firmware_display_settings(force)
  local signature = table.concat({
    tostring(APP.auto_sleep_enabled),
    tostring(APP.auto_sleep_seconds),
  }, ":")
  if not force and signature == APP.display_settings_signature then return true end
  if not http or not http.post then return false end
  local url = "http://127.0.0.1/display/api/settings"
    .. "?auto_sleep_enabled=" .. (APP.auto_sleep_enabled and "true" or "false")
    .. "&auto_sleep_seconds=" .. tostring(APP.auto_sleep_seconds)
  local ok, result = pcall(function()
    return http.post(url, {
      timeout = 1000,
      bufsz = 512,
      max_redirects = 0,
    }, "")
  end)
  if ok and result ~= false then
    APP.display_settings_signature = signature
    return true
  end
  return false
end

local function load_alarm_state()
  local state = read_json_file(APP.ALARM_STATE_PATH)
  if type(state) ~= "table" or type(state.triggers) ~= "table" then return end
  for index = 1, 3 do
    local value = state.triggers[index] or state.triggers[tostring(index)]
    if type(value) == "string" and #value <= 64 then
      APP.alarm_last_trigger[index] = value
    end
  end
end

local function save_alarm_state()
  if not file or not file.putcontents then return end
  local codec = rawget(_G, "json") or rawget(_G, "sjson")
  if not codec or not codec.encode then return end
  local ok, raw = pcall(function()
    return codec.encode({ triggers = APP.alarm_last_trigger })
  end)
  if ok and type(raw) == "string" then
    pcall(function() file.putcontents(APP.ALARM_STATE_PATH, raw) end)
  end
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

local ALARM_TONE = make_tone(1000, 105)
local ALARM_PATTERN = {
  true, true, true, false, false,
  true, true, true, false, false, false,
}

local function normalize_alarm_sound(value)
  local path = tostring(value or "builtin")
  if path == "" or path == "builtin" then return "builtin" end
  if path:find("..", 1, true) then return "builtin" end
  if not (path:match("^/sd/mp3/") or path:match("^/sd/MP3/")) then return "builtin" end
  if not path:lower():match("%.mp3$") then return "builtin" end
  return path
end

local function alarm_file_exists(path)
  if not file or not file.stat then return false end
  local ok, stat = pcall(function() return file.stat(path) end)
  return ok and type(stat) == "table" and not stat.is_dir
end

local function stop_alarm_audio()
  local audio = APP.alarm_audio
  if audio then
    if audio.i2s_play_stop then pcall(function() audio.i2s_play_stop() end) end
    if audio.i2s_stop then pcall(function() audio.i2s_stop() end) end
    if audio.close then pcall(function() audio.close() end) end
  elseif APP.alarm_audio_started and i2s and i2s.stop then
    pcall(function() i2s.stop(0) end)
  end
  APP.alarm_audio = nil
  APP.alarm_audio_started = false
  APP.alarm_audio_mode = "builtin"
end

local function start_mp3_alarm_audio()
  local path = normalize_alarm_sound(APP.alarm_sound)
  if path == "builtin" or not alarm_file_exists(path) then return false end
  local ok, audio_or_err = pcall(require, APP.AUDIO_MODULE_PATH)
  if not ok or type(audio_or_err) ~= "table" then return false end
  local audio = audio_or_err
  local started = pcall(function()
    if audio.i2s_play_stop then pcall(function() audio.i2s_play_stop() end) end
    if audio.i2s_stop then pcall(function() audio.i2s_stop() end) end
    if audio.close then pcall(function() audio.close() end) end
    if i2s and i2s.stop then pcall(function() i2s.stop(0) end) end
    local opened, open_err = audio.open(path, { output_channels = 1 })
    if not opened then error(open_err or "audio.open failed") end
    local info, info_err = audio.info()
    if type(info) ~= "table" then error(info_err or "audio.info failed") end
    local i2s_ok, i2s_err = audio.i2s_start({
      port = 0,
      sample_rate = tonumber(info.sample_rate) or 44100,
      channels = 1,
      bits = 16,
      buffer_count = 6,
      buffer_len = 512,
      data_out_pin = 48,
    })
    if not i2s_ok then error(i2s_err or "audio.i2s_start failed") end
    if audio.prefetch then pcall(function() audio.prefetch(32768, 8192) end) end
    local play_ok, play_err = audio.i2s_play_start({
      chunk_bytes = 4096,
      timeout_ms = 80,
      stack_bytes = 5120,
      priority = 9,
      core = 1,
      producer_stack_bytes = 7168,
      producer_priority = 8,
      producer_core = 1,
    })
    if not play_ok then error(play_err or "audio.i2s_play_start failed") end
  end)
  if not started then
    if audio.i2s_play_stop then pcall(function() audio.i2s_play_stop() end) end
    if audio.i2s_stop then pcall(function() audio.i2s_stop() end) end
    if audio.close then pcall(function() audio.close() end) end
    return false
  end
  APP.alarm_audio = audio
  APP.alarm_audio_started = true
  APP.alarm_audio_mode = "mp3"
  return true
end

local function start_builtin_alarm_audio()
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
  if ok then APP.alarm_audio_mode = "builtin" end
  return ok
end

local function stop_alarm()
  stop_alarm_audio()
  APP.alarm_ringing = false
  APP.alarm_started_ms = 0
  APP.alarm_pattern_step = 0
end

local function start_alarm()
  stop_alarm_audio()
  APP.alarm_ringing = true
  APP.alarm_started_ms = now_ms()
  APP.alarm_pattern_step = 0
  wake_display()
  if not start_mp3_alarm_audio() then
    start_builtin_alarm_audio()
  end
end

local function ring_alarm()
  if not APP.alarm_ringing then return end
  if APP.alarm_started_ms > 0 and now_ms() - APP.alarm_started_ms >= 10 * 60 * 1000 then
    stop_alarm()
    return
  end
  if APP.alarm_audio_mode == "mp3" and APP.alarm_audio then
    local ok, state = pcall(function() return APP.alarm_audio.i2s_play_state() end)
    if ok and type(state) == "table"
        and tonumber(state.eof) == 1 and tonumber(state.running) ~= 1 then
      stop_alarm_audio()
      if not start_mp3_alarm_audio() then start_builtin_alarm_audio() end
    elseif not ok or (type(state) == "table" and tonumber(state.error) == 1) then
      stop_alarm_audio()
      start_builtin_alarm_audio()
    end
    return
  end
  if not start_builtin_alarm_audio() then return end
  APP.alarm_pattern_step = (APP.alarm_pattern_step % #ALARM_PATTERN) + 1
  if ALARM_PATTERN[APP.alarm_pattern_step] then
    pcall(function() i2s.write(0, ALARM_TONE) end)
  end
end

APP.start_alarm = start_alarm
APP.stop_alarm = stop_alarm

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
      save_alarm_state()
      start_alarm()
    end
  end
end

local function list_mp3_files()
  local output, seen = {}, {}
  if not file or not file.listdir then return output end
  for _, dir in ipairs({ "/sd/mp3", "/sd/MP3" }) do
    local ok, entries = pcall(function() return file.listdir(dir) end)
    if ok and type(entries) == "table" then
      for _, entry in ipairs(entries) do
        local name = tostring(type(entry) == "table" and entry.name or entry or "")
        local is_dir = type(entry) == "table" and entry.is_dir == true
        if not is_dir and name:lower():match("%.mp3$") then
          local dedupe_key = name:lower()
          local path = type(entry) == "table" and tostring(entry.path or "") or ""
          if path == "" then path = dir .. "/" .. name end
          path = normalize_alarm_sound(path)
          if path ~= "builtin" and not seen[dedupe_key] then
            seen[dedupe_key] = true
            output[#output + 1] = { name = name, path = path }
          end
        end
      end
    end
  end
  table.sort(output, function(a, b) return a.name:lower() < b.name:lower() end)
  return output
end

local function api_info()
  local clock = local_clock()
  local settings = read_settings()
  local current_brightness = nil
  if sys and sys.getbrightness then
    local ok, value = pcall(function() return sys.getbrightness() end)
    if ok then current_brightness = tonumber(value) end
  end
  local alarms = {}
  for index, alarm in ipairs(APP.alarms) do
    alarms[index] = {
      enabled = alarm.enabled,
      hour = alarm.hour,
      minute = alarm.minute,
      ["repeat"] = alarm.repeat_rule,
    }
  end
  return json_response({
    ok = true,
    version = APP.VERSION,
    language = tostring(settings.language or settings.locale or settings.lang or "zh-CN"),
    route_base = APP.ROUTE_BASE,
    fixed_route_base = APP.FIXED_ROUTE_BASE,
    auto_sleep_enabled = APP.auto_sleep_enabled,
    auto_sleep_seconds = APP.auto_sleep_seconds,
    display_settings_applied = APP.display_settings_signature ~= "",
    scheduled_sleep_enabled = APP.enabled,
    scheduled_sleep_mode = APP.mode,
    scheduled_sleep_hour = APP.sleep_hour,
    scheduled_sleep_minute = APP.sleep_minute,
    scheduled_wake_hour = APP.wake_hour,
    scheduled_wake_minute = APP.wake_minute,
    scheduled_window_active = inside_schedule(clock),
    scheduled_sleeping = APP.scheduled_sleeping,
    alarm_ringing = APP.alarm_ringing,
    alarm_sound = APP.alarm_sound,
    alarm_audio_mode = APP.alarm_audio_mode,
    alarm_count = #APP.alarms,
    alarms = alarms,
    mp3_files = list_mp3_files(),
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

wake_display = function()
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
  APP.auto_sleep_enabled = bool_value(settings.auto_sleep_enabled, false)
  APP.auto_sleep_seconds = clamp(settings.auto_sleep_seconds, 60, 86400, 1800)
  APP.alarms = normalize_alarms(settings.alarms)
  APP.alarm_sound = normalize_alarm_sound(settings.alarm_sound)
  apply_firmware_display_settings(false)

  local timezone = tostring(settings.timezone or "")
  if timezone ~= "" and time and time.settimezone then
    pcall(function() time.settimezone(timezone) end)
  end

  local signature = table.concat({
    tostring(APP.enabled), APP.mode,
    APP.sleep_hour, APP.sleep_minute,
    APP.wake_hour, APP.wake_minute,
    APP.normal_brightness, timezone, APP.alarm_sound,
    tostring(APP.auto_sleep_enabled), APP.auto_sleep_seconds,
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

local function api_settings(req)
  local raw, body_err = read_body(req, 32768)
  if not raw then return json_response({ ok = false, error = body_err }) end
  local codec = rawget(_G, "json") or rawget(_G, "sjson")
  if not codec or not codec.decode then
    return json_response({ ok = false, error = "json.decode missing" })
  end
  local decoded, input = pcall(function() return codec.decode(raw) end)
  if not decoded or type(input) ~= "table" then
    return json_response({ ok = false, error = "invalid json" })
  end

  local settings = read_settings()
  settings.auto_sleep_enabled = bool_value(input.auto_sleep_enabled, false)
  settings.auto_sleep_seconds = clamp(input.auto_sleep_seconds, 1, 86400, 1800)
  settings.scheduled_sleep_enabled = bool_value(input.scheduled_sleep_enabled, false)
  settings.scheduled_sleep_mode = tostring(input.scheduled_sleep_mode or "off") == "dim" and "dim" or "off"
  settings.scheduled_sleep_hour = clamp(input.scheduled_sleep_hour, 0, 23, 0)
  settings.scheduled_sleep_minute = clamp(input.scheduled_sleep_minute, 0, 59, 0)
  settings.scheduled_wake_hour = clamp(input.scheduled_wake_hour, 0, 23, 7)
  settings.scheduled_wake_minute = clamp(input.scheduled_wake_minute, 0, 59, 0)
  settings.alarm_sound = normalize_alarm_sound(input.alarm_sound)
  settings.alarms = {}
  for index, alarm in ipairs(normalize_alarms(input.alarms)) do
    settings.alarms[index] = {
      enabled = alarm.enabled,
      hour = alarm.hour,
      minute = alarm.minute,
      ["repeat"] = alarm.repeat_rule,
    }
  end

  if settings.scheduled_sleep_enabled
      and settings.scheduled_sleep_hour == settings.scheduled_wake_hour
      and settings.scheduled_sleep_minute == settings.scheduled_wake_minute then
    return json_response({ ok = false, error = "screen-off and screen-on times must differ" })
  end

  local was_ringing = APP.alarm_ringing
  if was_ringing then stop_alarm() end
  local saved, save_err = write_settings(settings)
  if not saved then return json_response({ ok = false, error = save_err }) end
  sync_settings()
  if was_ringing then start_alarm() end
  return api_info()
end

local function api_alarm_test()
  stop_alarm()
  sync_settings()
  start_alarm()
  return api_info()
end

local function api_alarm_stop()
  stop_alarm()
  return api_info()
end

local function web_page()
  local body = ""
  if file and file.getcontents then
    local ok, raw = pcall(function() return file.getcontents(APP.PAGE_PATH) end)
    if ok and type(raw) == "string" then body = raw end
  end
  if body == "" then
    body = "<!doctype html><meta charset=\"utf-8\"><title>Screen & Alarms</title><p>Control page unavailable.</p>"
  end
  return html_response(body)
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
load_alarm_state()

local function register_route(method, route, handler)
  if not httpd or not httpd.dynamic then return false end
  local ok, err = pcall(function() return httpd.dynamic(method, route, handler) end)
  if ok and not err then
    APP.routes[#APP.routes + 1] = { method = method, route = route }
    return true
  end
  return false
end

local function register_route_set(base)
  if type(base) ~= "string" or base == "" then return end
  base = base:gsub("/+$", "")
  local get, post = httpd.GET or "GET", httpd.POST or "POST"
  register_route(get, base, web_page)
  register_route(get, base .. "/", web_page)
  register_route(get, base .. "/api/info", api_info)
  register_route(post, base .. "/api/settings", api_settings)
  register_route(post, base .. "/api/alarm/test", api_alarm_test)
  register_route(post, base .. "/api/alarm/stop", api_alarm_stop)
  register_route(get, base .. "/api/wake", api_wake)
  register_route(post, base .. "/api/wake", api_wake)
end

if httpd then
  register_route_set(APP.ROUTE_BASE)
  if APP.ROUTE_BASE ~= APP.FIXED_ROUTE_BASE then register_route_set(APP.FIXED_ROUTE_BASE) end
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
  alarm_timer:alarm(220, tmr.ALARM_AUTO, ring_alarm)
  local display_retry_timer = tmr.create()
  APP.timers[#APP.timers + 1] = display_retry_timer
  display_retry_timer:alarm(2000, tmr.ALARM_SINGLE or 0, function()
    apply_firmware_display_settings(true)
  end)
end

print("[display_schedule] ready", APP.VERSION, tostring(APP.enabled))
write_status("ready")
