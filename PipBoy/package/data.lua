-- Uses the same settings, NTP and Cubic weather endpoints as Holo Clock.
-- No dependency on another app's installation. The environment is injectable for tests.
local M = {}
local function trim(v) return tostring(v or ""):match("^%s*(.-)%s*$") end
local function finite(v)
  local n = tonumber(v)
  if n and n == n and n ~= math.huge and n ~= -math.huge then return n end
end
local function encode(v)
  return tostring(v):gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", c:byte()) end)
end
local function round(n)
  return n < 0 and -math.floor(-n + 0.5) or math.floor(n + 0.5)
end

function M.new(env)
  local e = env or _G
  local self = { running = true, generation = 0, next_fetch = 2500, next_settings = 0,
    state = { timezone = "CST-8", language = "zh-CN", unit = "C", address = "", location = "",
      valid = false, icon = "999", weather_text = "--", weather_status = "waiting" } }
  local function decode(raw)
    if type(raw) ~= "string" or raw == "" then return nil end
    local ok, value = pcall(function()
      if e.zlib and e.zlib.isgzip and e.zlib.isgzip(raw) then raw = e.zlib.gunzip(raw) end
      local codec = e.json or e.sjson
      return codec and codec.decode(raw)
    end)
    return ok and type(value) == "table" and value or nil
  end
  local function clear_weather(reason)
    local s = self.state
    s.valid, s.temp, s.humidity, s.icon, s.weather_text = false, nil, nil, "999", "--"
    s.weather_status = reason
  end
  function self:load_settings(now)
    local ok, raw = pcall(function() return e.file and e.file.getcontents("/sd/apps/settings.json") end)
    local doc = ok and decode(raw) or nil
    if not doc then return end -- Keep the last settings on transient read/parse failure.
    local s = self.state
    local zone = trim(doc.timezone)
    if zone == "" then zone = "CST-8" end
    local lang = trim(doc.language or doc.lang or "zh-CN")
    local address = trim(doc.weather_address or doc.weatherAddress)
    if address == "" then address = trim(doc.weather_city or doc.city_name or doc.city) end
    local location = trim(doc.weather_location_id)
    local signature = address .. "\n" .. location .. "\n" .. lang
    if self.settings_signature ~= signature then
      self.generation = self.generation + 1 -- Invalidate callbacks for the old city/language.
      self.inflight, self.settings_signature = nil, signature
      s.address, s.location, s.language = address, location, lang
      clear_weather("waiting")
      self.next_fetch = now
    end
    s.unit = doc.temperature_unit == "F" and "F" or "C"
    if s.timezone ~= zone or not self.zone_set then
      s.timezone, self.zone_set = zone, true
      if e.time and e.time.settimezone then pcall(e.time.settimezone, zone) end
    end
  end
  function self:init()
    self:load_settings(0)
    self.next_fetch, self.next_settings = 2500, 30000
    if e.time then
      if not self.zone_set and e.time.settimezone then pcall(e.time.settimezone, self.state.timezone) end
      if e.time.initntp then pcall(e.time.initntp, "ntp.aliyun.com") end
    end
  end
  function self:local_time()
    local function usable(v)
      if type(v) ~= "table" then return false end
      return finite(v.year) and v.year >= 2024 and finite(v.mon) and v.mon >= 1 and v.mon <= 12
        and finite(v.day) and v.day >= 1 and v.day <= 31 and finite(v.hour) and v.hour >= 0 and v.hour < 24
        and finite(v.min) and v.min >= 0 and v.min < 60 and finite(v.sec) and v.sec >= 0 and v.sec < 60
    end
    if e.time and e.time.getlocal then
      local ok, value = pcall(e.time.getlocal)
      if ok and usable(value) then return value end
    end
    if e.os and e.os.date then
      local ok, value = pcall(e.os.date, "*t")
      if ok and usable(value) then return value end
    end
    return nil -- Never substitute a fictitious date before NTP has synchronized.
  end
  function self:brightness()
    local ok, value = pcall(function() return e.sys and e.sys.getbrightness() end)
    local n = ok and finite(value) or nil
    return n and round(math.max(0, math.min(100, n))) or nil
  end
  function self:temperature_text()
    local s = self.state
    if not s.valid then return "--°" .. s.unit end
    local n = s.unit == "F" and s.temp * 9 / 5 + 32 or s.temp
    return tostring(round(n)) .. "°" .. s.unit
  end
  function self:request(now)
    if not self.running or self.inflight then return end
    local s, http = self.state, e.http and e.http.cubicserver
    if not http or not http.get then
      clear_weather("unavailable"); self.next_fetch = now + 60000; return
    end
    if s.location == "" and s.address == "" then
      clear_weather("no-location"); self.next_fetch = now + 60000; return
    end
    self.generation = self.generation + 1
    local token = self.generation
    self.inflight, self.deadline = token, now + 20000
    local function active() return self.running and self.inflight == token and self.generation == token end
    local function fail(reason)
      if not active() then return end
      self.inflight = nil
      clear_weather(reason)
      self.next_fetch = (self.last_now or now) + 60000
    end
    local lang = s.language:lower():match("^en") and "en" or "zh"
    local function get(path, callback)
      local ok, result = pcall(http.get, path, "Accept-Encoding: gzip\r\n", function(status, body)
        if not active() then return end
        local doc = tonumber(status) == 200 and decode(body) or nil
        if not doc or tostring(doc.code) ~= "200" then fail("error"); return end
        callback(doc)
      end)
      if not ok or result == false then fail("error") end
    end
    local function fetch_current(location)
      get("/v1/weather/now?location=" .. encode(location) .. "&unit=m&lang=" .. lang, function(doc)
        local current = type(doc.now) == "table" and doc.now or nil
        local temp = current and finite(current.temp)
        if not temp then fail("error"); return end
        local humidity = finite(current.humidity)
        s.temp, s.humidity = temp, humidity and math.max(0, math.min(100, round(humidity))) or nil
        local icon = tostring(current.icon or "999")
        s.icon = icon:match("^%d%d%d$") and icon or "999"
        s.weather_text = trim(current.text)
        if s.weather_text == "" then s.weather_text = "--" end
        s.valid, s.weather_status = true, "ok"
        self.inflight = nil
        self.next_fetch = (self.last_now or now) + 1800000 -- Same 30-minute refresh as Holo Clock.
      end)
    end
    local location = s.location
    if location == "" and s.address:match("^%d+$") then location = s.address end
    if location ~= "" then fetch_current(location); return end
    get("/v1/weather/cities?location=" .. encode(s.address) .. "&number=1&lang=" .. lang, function(doc)
      local locations = doc.locations or doc.location
      local first = type(locations) == "table" and locations[1] or nil
      local id = type(first) == "table" and trim(first.id) or ""
      if id == "" then fail("no-location"); return end
      s.location = id
      fetch_current(id)
    end)
  end
  function self:tick(now)
    if not self.running then return end
    self.last_now = now
    if now >= self.next_settings then self:load_settings(now); self.next_settings = now + 30000 end
    if self.inflight and now >= self.deadline then
      self.generation, self.inflight = self.generation + 1, nil
      clear_weather("timeout")
      self.next_fetch = now + 60000
    end
    if not self.inflight and now >= self.next_fetch then self:request(now) end
  end
  function self:stop()
    self.running, self.inflight = false, nil
    self.generation = self.generation + 1
  end
  return self
end

function M.weather_asset(code)
  local n = tonumber(code)
  if n == 100 or n == 900 then return "sun" end
  if n == 150 then return "moon" end
  if n == 101 or n == 102 or n == 103 then return "partly-day" end
  if n == 151 or n == 152 or n == 153 then return "partly-night" end
  if n == 104 or n == 154 then return "cloud" end
  if n == 302 or n == 303 or n == 304 then return "storm" end
  if n == 404 or n == 405 or n == 406 or n == 456 or n == 457 then return "sleet" end
  if n and n >= 300 and n < 400 then return "rain" end
  if n == 901 or (n and n >= 400 and n < 500) then return "snow" end
  if n == 503 or n == 504 or n == 507 or n == 508 or (n and n >= 200 and n < 300) then return "wind" end
  if n and n >= 500 and n < 600 then return "fog" end
  return "unknown"
end

function M.weekday(t)
  if not t then return "---" end
  local y, m = t.year, t.mon
  if m < 3 then y, m = y - 1, m + 12 end
  local k, j = y % 100, math.floor(y / 100)
  local h = (t.day + math.floor(13 * (m + 1) / 5) + k + math.floor(k / 4) + math.floor(j / 4) + 5 * j) % 7
  return ({ "SAT", "SUN", "MON", "TUE", "WED", "THU", "FRI" })[h + 1]
end
return M
