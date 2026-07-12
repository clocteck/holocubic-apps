local WeatherClient = {}
WeatherClient.__index = WeatherClient

local JSON = rawget(_G, "json") or rawget(_G, "sjson")
local SETTINGS_PATH = "/sd/apps/settings.json"

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function read_text(path)
  if not file then return nil end
  if file.getcontents then
    local ok, value = pcall(file.getcontents, path)
    if ok and type(value) == "string" then return value end
  end
  if not file.open then return nil end
  local fd = file.open(path, "r")
  if not fd then return nil end
  local chunks = {}
  while true do
    local part = fd:read(512)
    if not part or part == "" then break end
    chunks[#chunks + 1] = part
  end
  fd:close()
  return table.concat(chunks)
end

local function decode(raw)
  if type(raw) ~= "string" or raw == "" or not JSON or not JSON.decode then return nil end
  local ok, value = pcall(JSON.decode, raw)
  return ok and type(value) == "table" and value or nil
end

local function url_encode(value)
  return (tostring(value or ""):gsub("([^%w%-%._~])", function(ch)
    return string.format("%%%02X", string.byte(ch))
  end))
end

local function number(value, fallback)
  local result = tonumber(value)
  return result ~= nil and result or fallback
end

local function rounded(value)
  value = number(value, 0)
  return math.floor(value + (value >= 0 and 0.5 or -0.5))
end

local function hour_text(value)
  local hour = tostring(value or ""):match("T(%d%d):")
  return hour and (hour .. ":00") or "--:--"
end

local function weather_kind(code)
  code = tonumber(code) or -1
  if code == 0 then return "clear" end
  if code == 1 or code == 2 then return "partly" end
  if code == 3 then return "overcast" end
  if code == 45 or code == 48 then return "fog" end
  if code == 51 or code == 53 or code == 55 or code == 56 or code == 57 then return "drizzle" end
  if (code >= 61 and code <= 67) or code == 80 or code == 81 or code == 82 then return "rain" end
  if (code >= 71 and code <= 77) or code == 85 or code == 86 then return "snow" end
  if code >= 95 then return "storm" end
  return "cloudy"
end

local function weather_label(kind)
  local labels = {
    clear = "CLEAR", partly = "PARTLY", cloudy = "CLOUDY", overcast = "OVERCAST",
    drizzle = "DRIZZLE", rain = "RAIN", storm = "STORM", snow = "SNOW",
    fog = "FOG", wind = "WIND",
  }
  return labels[kind] or "WEATHER"
end

local function climate_mood(temp, humidity)
  local temp_band = "mild"
  if number(temp, 20) < 10 then temp_band = "cold"
  elseif number(temp, 20) >= 28 then temp_band = "hot" end
  local humidity_band = number(humidity, 50) >= 70 and "humid" or "dry"
  return temp_band .. "_" .. humidity_band
end

function WeatherClient.new(opts)
  opts = opts or {}
  local self = setmetatable({
    running = false,
    inflight = false,
    generation = 0,
    resolved_for = "",
    latitude = nil,
    longitude = nil,
    timezone = "Asia/Shanghai",
    on_update = opts.on_update,
    on_status = opts.on_status,
    state = {
      valid = false,
      loading = false,
      stale = false,
      city = "WEATHER",
      address = "",
      error = "",
      updated_at_ms = 0,
      current = {},
      hourly = {},
      tomorrow = {},
      rain_probability = 0,
      rain_time = "--:--",
      max_gust = 0,
    },
  }, WeatherClient)
  return self
end

function WeatherClient:emit_status(value, detail)
  if self.on_status then pcall(self.on_status, value, detail or "") end
end

function WeatherClient:emit_update()
  if self.on_update then pcall(self.on_update, self.state) end
end

function WeatherClient:load_location()
  local doc = decode(read_text(SETTINGS_PATH)) or {}
  local address = trim(doc.weather_address or doc.weatherAddress or doc.weather_city or doc.city)
  if address == "" then address = "Beijing" end
  self.state.address = address
  if self.resolved_for ~= address then
    self.resolved_for = ""
    self.latitude = nil
    self.longitude = nil
  end
  return address
end

function WeatherClient:fail(message)
  self.inflight = false
  self.state.loading = false
  self.state.stale = self.state.valid
  self.state.error = tostring(message or "weather unavailable")
  self:emit_status("error", self.state.error)
  self:emit_update()
end

function WeatherClient:resolve_location(address, done)
  if self.resolved_for == address and self.latitude and self.longitude then
    done(true)
    return
  end
  if not http or not http.get then done(false, "HTTP missing"); return end
  local url = "https://geocoding-api.open-meteo.com/v1/search?name=" .. url_encode(address)
    .. "&count=1&language=en&format=json"
  http.get(url, { timeout = 12000, headers = { ["Accept-Encoding"] = "identity" } }, function(code, body)
    if not self.running then return end
    local doc = code == 200 and decode(body) or nil
    local result = doc and type(doc.results) == "table" and doc.results[1] or nil
    if type(result) ~= "table" or not tonumber(result.latitude) or not tonumber(result.longitude) then
      done(false, "location " .. tostring(code or "?"))
      return
    end
    self.resolved_for = address
    self.latitude = tonumber(result.latitude)
    self.longitude = tonumber(result.longitude)
    self.timezone = trim(result.timezone) ~= "" and trim(result.timezone) or "Asia/Shanghai"
    self.state.city = trim(result.name) ~= "" and trim(result.name) or address
    done(true)
  end)
end

function WeatherClient:parse_forecast(doc)
  local current = type(doc.current) == "table" and doc.current or nil
  local hourly = type(doc.hourly) == "table" and doc.hourly or nil
  local daily = type(doc.daily) == "table" and doc.daily or nil
  if not current or not hourly or type(hourly.time) ~= "table" then return false, "forecast shape" end

  local kind = weather_kind(current.weather_code)
  local gust = number(current.wind_gusts_10m, 0)
  if gust >= 35 and kind ~= "storm" and kind ~= "rain" then kind = "wind" end
  self.state.current = {
    time = tostring(current.time or ""),
    temp = number(current.temperature_2m, 0),
    temp_text = tostring(rounded(current.temperature_2m)) .. "C",
    feels = number(current.apparent_temperature, current.temperature_2m),
    humidity = rounded(current.relative_humidity_2m),
    precipitation = number(current.precipitation, 0),
    wind_speed = number(current.wind_speed_10m, 0),
    wind_direction = rounded(current.wind_direction_10m),
    wind_gust = gust,
    code = tonumber(current.weather_code) or -1,
    kind = kind,
    label = weather_label(kind),
    mood = climate_mood(current.temperature_2m, current.relative_humidity_2m),
  }

  local rows = {}
  local max_pop, max_gust, first_rain = 0, gust, nil
  for i = 1, math.min(8, #hourly.time) do
    local pop = number(hourly.precipitation_probability and hourly.precipitation_probability[i], 0)
    local precip = number(hourly.precipitation and hourly.precipitation[i], 0)
    local item_gust = number(hourly.wind_gusts_10m and hourly.wind_gusts_10m[i], 0)
    local item_kind = weather_kind(hourly.weather_code and hourly.weather_code[i])
    if item_gust >= 35 and item_kind ~= "storm" and item_kind ~= "rain" then item_kind = "wind" end
    rows[#rows + 1] = {
      time = tostring(hourly.time[i] or ""),
      hour = hour_text(hourly.time[i]),
      temp = rounded(hourly.temperature_2m and hourly.temperature_2m[i]),
      humidity = rounded(hourly.relative_humidity_2m and hourly.relative_humidity_2m[i]),
      pop = rounded(pop),
      precipitation = precip,
      wind_speed = number(hourly.wind_speed_10m and hourly.wind_speed_10m[i], 0),
      wind_direction = rounded(hourly.wind_direction_10m and hourly.wind_direction_10m[i]),
      gust = item_gust,
      kind = item_kind,
    }
    if i <= 3 then
      max_pop = math.max(max_pop, pop)
      max_gust = math.max(max_gust, item_gust)
      if not first_rain and (pop >= 30 or precip >= 0.1) then first_rain = hour_text(hourly.time[i]) end
    end
  end

  self.state.hourly = rows
  if daily and type(daily.time) == "table" and daily.time[2] then
    local tomorrow_kind = weather_kind(daily.weather_code and daily.weather_code[2])
    local tomorrow_gust = number(daily.wind_gusts_10m_max and daily.wind_gusts_10m_max[2], 0)
    if tomorrow_gust >= 35 and tomorrow_kind ~= "storm" and tomorrow_kind ~= "rain" then tomorrow_kind = "wind" end
    self.state.tomorrow = {
      date = tostring(daily.time[2] or ""),
      code = tonumber(daily.weather_code and daily.weather_code[2]) or -1,
      kind = tomorrow_kind,
      label = weather_label(tomorrow_kind),
      temp_min = rounded(daily.temperature_2m_min and daily.temperature_2m_min[2]),
      temp_max = rounded(daily.temperature_2m_max and daily.temperature_2m_max[2]),
      pop = rounded(daily.precipitation_probability_max and daily.precipitation_probability_max[2]),
      precipitation = number(daily.precipitation_sum and daily.precipitation_sum[2], 0),
      gust = tomorrow_gust,
    }
  elseif type(self.state.tomorrow) ~= "table" then
    self.state.tomorrow = {}
  end
  self.state.rain_probability = rounded(max_pop)
  self.state.rain_time = first_rain or "DRY"
  self.state.max_gust = max_gust
  self.state.valid = true
  self.state.loading = false
  self.state.stale = false
  self.state.error = ""
  self.state.updated_at_ms = millis and (millis() or 0) or 0
  return true
end

function WeatherClient:fetch()
  if not self.running or self.inflight then return end
  self.inflight = true
  self.state.loading = true
  self:emit_status("loading", "resolving location")
  self:emit_update()
  local address = self:load_location()
  self:resolve_location(address, function(ok, err)
    if not self.running then return end
    if not ok then self:fail(err); return end
    local base_url = "https://api.open-meteo.com/v1/forecast?latitude=" .. tostring(self.latitude)
      .. "&longitude=" .. tostring(self.longitude)
      .. "&timezone=" .. url_encode(self.timezone)
    local forecast_url = base_url
      .. "&forecast_hours=8"
      .. "&current=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,rain,showers,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m"
      .. "&hourly=temperature_2m,relative_humidity_2m,precipitation_probability,precipitation,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m"
    local daily_url = base_url
      .. "&forecast_days=3"
      .. "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,wind_gusts_10m_max"
    self:emit_status("loading", "forecast")
    http.get(forecast_url, { timeout = 12000, headers = { ["Accept-Encoding"] = "identity" } }, function(code, body)
      if not self.running then return end
      local doc = code == 200 and decode(body) or nil
      if not doc then self:fail("forecast " .. tostring(code or "?")); return end
      self:emit_status("loading", "daily")
      http.get(daily_url, { timeout = 12000, headers = { ["Accept-Encoding"] = "identity" } }, function(daily_code, daily_body)
        if not self.running then return end
        self.inflight = false
        local daily_doc = daily_code == 200 and decode(daily_body) or nil
        if daily_doc and type(daily_doc.daily) == "table" then
          doc.daily = daily_doc.daily
        end
        local parsed, parse_err = self:parse_forecast(doc)
        if not parsed then self:fail(parse_err); return end
        if not daily_doc then
          self.state.error = "daily " .. tostring(daily_code or "?")
          self:emit_status("partial", self.state.error)
        else
          self:emit_status("online", "updated")
        end
        self:emit_update()
      end)
    end)
  end)
end

function WeatherClient:start()
  if self.running then return end
  self.running = true
  self.generation = self.generation + 1
  self:fetch()
end

function WeatherClient:stop()
  self.running = false
  self.inflight = false
  self.generation = self.generation + 1
end

WeatherClient.weather_kind = weather_kind
WeatherClient.weather_label = weather_label
WeatherClient.climate_mood = climate_mood

return WeatherClient
