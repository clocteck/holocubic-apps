    if _G.WEATHER_APP and _G.WEATHER_APP.stop then
    pcall(function() _G.WEATHER_APP.stop("reload") end)
    end

    WEATHER_APP = {
    VERSION = "2026-07-10-weather-location-cache-v4",
    DEBUG = false,

    SCREEN_W = 320,
    SCREEN_H = 240,

    SETTINGS_PATH = "/sd/apps/settings.json",
    DEFAULT_TIMEZONE = "CST-8",
    DEFAULT_WEATHER_LOCATION = "Shanghai",
    WEATHER_NOW_PATH = "/v1/weather/now",
    WEATHER_3D_PATH = "/v1/weather/3d",
    WEATHER_CITY_PATH = "/v1/weather/cities",
    WEATHER_LOCATION = "",
    LANGUAGE = "zh-CN",
    WEATHER_API_LANG = "zh",
    WEATHER_FETCH_MS = 60000,
    FORECAST_FETCH_MS = 10 * 60000,
    TIME_SYNC_RETRY_MS = 30000,

    TZ_OFFSET_SEC = 0,
    TIMEZONE = "UTC0",
    NTP_SERVER = "ntp.aliyun.com",
    CITY_NAME = "Weather",

    ASSET_DIR = "/sd/apps/weather/assets",
    }

    local APP = WEATHER_APP
    local MAIN_STYLE = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
    local CELSIUS = "\226\132\131"
    local LABEL_LONG_CLIP = rawget(_G, "LV_LABEL_LONG_CLIP") or rawget(_G, "LABEL_LONG_CLIP")

    local ALIGN_LEFT = rawget(_G, "LV_TEXT_ALIGN_LEFT") or 0
    local ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1
    local ALIGN_RIGHT = rawget(_G, "LV_TEXT_ALIGN_RIGHT") or 2

    local FONT_10 = rawget(_G, "LV_FONT_MONTSERRAT_10") or 10
    local FONT_12 = rawget(_G, "LV_FONT_MONTSERRAT_12") or 12
    local FONT_14 = rawget(_G, "LV_FONT_MONTSERRAT_14") or 14
    local FONT_16 = rawget(_G, "LV_FONT_MONTSERRAT_16") or 16
    local FONT_20 = rawget(_G, "LV_FONT_MONTSERRAT_20") or 20
    local FONT_24 = rawget(_G, "LV_FONT_MONTSERRAT_24") or 24
    local FONT_28 = rawget(_G, "LV_FONT_MONTSERRAT_28") or 28
    local FONT_34 = FONT_28
    local FONT_40 = FONT_28
    local CANVAS_FMT = rawget(_G, "LV_IMG_CF_TRUE_COLOR") or rawget(_G, "CANVAS_FMT_TRUE_COLOR")

    local GLASS_X = 10
    local GLASS_Y = 166
    local GLASS_W = 300
    local GLASS_H = 66
    local GLASS_BLUR = 6
    local STARTUP_HOLD_MS = 300
    local FORECAST_GLASS_X = 10
    local FORECAST_GLASS_Y = 45
    local FORECAST_GLASS_W = 300
    local FORECAST_GLASS_H = 170
    local FORECAST_GLASS_BLUR = 8

    local math_floor = math.floor
    local math_abs = math.abs
    local pcall_fn = pcall
    local string_format = string.format

    local I18N = {
    ["zh-CN"] = { weather = "天气", waiting = "等待数据", updating = "更新中", today = "今天", sync_time = "同步时间" },
    en = { weather = "Weather", waiting = "Waiting", updating = "Updating", today = "Today", sync_time = "SYNC TIME" },
    ja = { weather = "天気", waiting = "待機中", updating = "更新中", today = "今日", sync_time = "時刻同期" },
    ["zh-TW"] = { weather = "天氣", waiting = "等待資料", updating = "更新中", today = "今天", sync_time = "同步時間" },
    }

    local function normalize_language(value)
    local text = tostring(value or ""):gsub("_", "-")
    if text == "en" or text:match("^en%-") then return "en", "en" end
    if text == "ja" or text:match("^ja%-") then return "ja", "ja" end
    if text == "zh-TW" or text == "zh-Hant" or text:match("^zh%-Hant") or text:match("^zh%-HK") then return "zh-TW", "zh-hant" end
    return "zh-CN", "zh"
    end

    local function tr(key)
    local dict = I18N[APP.LANGUAGE] or I18N["zh-CN"]
    return dict[key] or I18N.en[key] or tostring(key or "")
    end

    local function display_city_name()
    if APP.CITY_NAME == "" or APP.CITY_NAME == "Weather" then return tr("weather") end
    return APP.CITY_NAME
    end

    local function startup_boot_city()
    local city = tostring(APP.CITY_NAME or "")
    if city ~= "" and not city:find("[\128-\255]") then return city end
    return "Weather"
    end

    APP.running = true
    APP.timers = {}
    APP.ui = {}
    APP.settings_doc = {}
    APP.input = {
    mode = "none",
    left_code = nil,
    right_code = nil,
    }
    APP.font_handles = {}
    APP.state = {
    page = "now",
    valid = false,
    temp = nil,
    humidity = nil,
    wind_speed = nil,
    precip_x10 = nil,
    text = nil,
    code = nil,
    obs_time = nil,
    kind = "partly",
    last_http_code = nil,
    last_error = nil,
    last_update_ms = 0,
    clock_valid = false,
    last_ntp_retry_ms = -30000,
    request_inflight = false,
    location_request_inflight = false,
    location_waiters = {},
    resolved_location_raw = nil,
    resolved_location_id = nil,
    ntp_enabled = false,
    glass_snapshot = nil,
    forecast_glass_snapshot = nil,
    startup_visible = false,
    displayed_icon_code = nil,
    forecast = {
        valid = false,
        days = {},
        last_http_code = nil,
        last_error = nil,
        last_update_ms = 0,
        request_inflight = false,
    },
    }

    APP.colors = {
    black = 0x000000,
    glass = 0x07100D,
    glass_soft = 0x0D1712,
    border = 0xDDFBE4,
    text = 0xF6FFF5,
    text_soft = 0xC7E9CC,
    text_dim = 0x91B49B,
    green = 0x6CFF99,
    warn = 0xFFD66C,
    strip = 0x061119,
    glass_line = 0xE8FFFA,
    }

    local C = APP.colors

    local function log(...)
    if APP.DEBUG and print then
        print("[weather.lua]", ...)
    end
    end

    local function warn(...)
    if print then
        print("[weather.lua]", ...)
    end
    end

    local function call(fn, ...)
    if fn then
        return pcall_fn(fn, ...)
    end
    return false
    end

    local function trim(text)
    if text == nil then
        return ""
    end
    return tostring(text):match("^%s*(.-)%s*$") or ""
    end

    local function read_text(path)
    if not file then
        return nil
    end
    if file.getcontents then
        local ok, raw = pcall_fn(function()
        return file.getcontents(path)
        end)
        if ok and type(raw) == "string" then
        return raw
        end
    end
    if not file.open then
        return nil
    end
    local fd = file.open(path, "r")
    if not fd then
        return nil
    end
    local chunks = {}
    while true do
        local part = fd:read(512)
        if not part or part == "" then
        break
        end
        chunks[#chunks + 1] = part
    end
    fd:close()
    return table.concat(chunks)
    end

    local function decode_json(raw)
    if type(raw) ~= "string" or raw == "" then
        return nil
    end
    if json and json.decode then
        local ok, doc = pcall_fn(function()
        return json.decode(raw)
        end)
        if ok and type(doc) == "table" then
        return doc
        end
    end
    if sjson and sjson.decode then
        local ok, doc = pcall_fn(function()
        return sjson.decode(raw)
        end)
        if ok and type(doc) == "table" then
        return doc
        end
    end
    return nil
    end

    local function encode_json(doc)
    local codec = rawget(_G, "json") or rawget(_G, "sjson")
    if not codec or not codec.encode then return nil end
    local ok, raw = pcall_fn(function() return codec.encode(doc) end)
    if ok and type(raw) == "string" and raw ~= "" then return raw end
    return nil
    end

    local function write_text(path, text)
    if not file or type(text) ~= "string" then return false end
    if file.putcontents then
        local ok, result = pcall_fn(function() return file.putcontents(path, text) end)
        if ok and result then return true end
    end
    if not file.open then return false end
    local fd = file.open(path, "w")
    if not fd then return false end
    local ok = pcall_fn(function() fd:write(text) end)
    pcall_fn(function() fd:close() end)
    return ok and true or false
    end

    local function url_encode(text)
    text = tostring(text or "")
    return (text:gsub("([^%w%-%._~])", function(ch)
        return string_format("%%%02X", string.byte(ch))
    end))
    end

    local function is_digit_char(ch)
    return ch and ch:match("%d") ~= nil
    end

    local function parse_posix_offset(text, index)
    text = tostring(text or "")
    local i = index or 1
    local sign = 1
    local ch = text:sub(i, i)
    if ch == "+" then
        i = i + 1
    elseif ch == "-" then
        sign = -1
        i = i + 1
    end

    local start_i = i
    while is_digit_char(text:sub(i, i)) do
        i = i + 1
    end
    if i == start_i then
        return nil, index
    end

    local hours = tonumber(text:sub(start_i, i - 1)) or 0
    local minutes = 0
    local seconds = 0
    if text:sub(i, i) == ":" then
        i = i + 1
        start_i = i
        while is_digit_char(text:sub(i, i)) do
        i = i + 1
        end
        minutes = tonumber(text:sub(start_i, i - 1)) or 0
        if text:sub(i, i) == ":" then
        i = i + 1
        start_i = i
        while is_digit_char(text:sub(i, i)) do
            i = i + 1
        end
        seconds = tonumber(text:sub(start_i, i - 1)) or 0
        end
    end

    return -(sign * (hours * 3600 + minutes * 60 + seconds)), i
    end

    local function parse_tz_name(text, index)
    text = tostring(text or "")
    local i = index or 1
    local start_i = i
    while text:sub(i, i):match("%a") do
        i = i + 1
    end
    if i == start_i then
        return nil, index
    end
    return text:sub(start_i, i - 1), i
    end

    local function posix_tz_offset_sec(tz)
    local _, index = parse_tz_name(trim(tz), 1)
    local offset = parse_posix_offset(trim(tz), index or 1)
    return offset or 0
    end

    local function is_leap_year(year)
    return (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)
    end

    local function days_in_month(year, mon)
    if mon == 2 then
        return is_leap_year(year) and 29 or 28
    end
    local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    return days[mon] or 30
    end

    local function days_before_year(year)
    local days = 0
    local y = 1970
    while y < year do
        days = days + (is_leap_year(y) and 366 or 365)
        y = y + 1
    end
    return days
    end

    local function days_before_month(year, mon)
    local days = 0
    local m = 1
    while m < mon do
        days = days + days_in_month(year, m)
        m = m + 1
    end
    return days
    end

    local function weekday(year, mon, day)
    local days = days_before_year(year) + days_before_month(year, mon) + day - 1
    return (days + 4) % 7
    end

    local function year_from_epoch(sec)
    local days = math_floor((tonumber(sec) or 0) / 86400)
    local year = 1970
    while true do
        local year_days = is_leap_year(year) and 366 or 365
        if days < year_days then
        return year
        end
        days = days - year_days
        year = year + 1
    end
    end

    local function local_epoch(year, mon, day, hour, min, sec)
    local days = days_before_year(year) + days_before_month(year, mon) + day - 1
    return days * 86400 + (hour or 0) * 3600 + (min or 0) * 60 + (sec or 0)
    end

    local function parse_rule_time(text)
    text = trim(text)
    if text == "" then
        return 2 * 3600
    end

    local sign = 1
    if text:sub(1, 1) == "-" then
        sign = -1
        text = text:sub(2)
    elseif text:sub(1, 1) == "+" then
        text = text:sub(2)
    end

    local h, m, s = text:match("^(%d+):(%d+):(%d+)$")
    if not h then
        h, m = text:match("^(%d+):(%d+)$")
    end
    if not h then
        h = text:match("^(%d+)$")
    end
    if not h then
        return 2 * 3600
    end
    return sign * ((tonumber(h) or 0) * 3600 + (tonumber(m) or 0) * 60 + (tonumber(s) or 0))
    end

    local function parse_dst_rule(text)
    local rule_text, time_text = tostring(text or ""):match("^([^/]+)/*(.*)$")
    local mon, week, dow = tostring(rule_text or ""):match("^M(%d+)%.(%d+)%.(%d+)$")
    if not mon then
        return nil
    end
    return {
        mon = tonumber(mon),
        week = tonumber(week),
        dow = tonumber(dow),
        time_sec = parse_rule_time(time_text),
    }
    end

    local function transition_day(year, rule)
    local first_dow = weekday(year, rule.mon, 1)
    local day = 1 + ((rule.dow - first_dow + 7) % 7) + (rule.week - 1) * 7
    local max_day = days_in_month(year, rule.mon)
    if rule.week == 5 and day > max_day then
        day = day - 7
    end
    return day
    end

    local function transition_utc(year, rule, offset_before)
    local day = transition_day(year, rule)
    return local_epoch(year, rule.mon, day, 0, 0, rule.time_sec) - offset_before
    end

    local function parse_posix_timezone(tz)
    tz = trim(tz)
    local std_name, index = parse_tz_name(tz, 1)
    if not std_name then
        return nil
    end
    local std_offset, next_index = parse_posix_offset(tz, index)
    if not std_offset then
        return nil
    end
    index = next_index

    local dst_name
    dst_name, index = parse_tz_name(tz, index)
    if not dst_name then
        return { std_offset = std_offset }
    end

    local dst_offset = std_offset + 3600
    local ch = tz:sub(index, index)
    if ch ~= "," and ch ~= "" then
        local explicit_offset, explicit_index = parse_posix_offset(tz, index)
        if explicit_offset then
        dst_offset = explicit_offset
        index = explicit_index
        end
    end
    if tz:sub(index, index) ~= "," then
        return { std_offset = std_offset }
    end

    local rules = tz:sub(index + 1)
    local comma = rules:find(",", 1, true)
    if not comma then
        return { std_offset = std_offset }
    end
    local start_rule = parse_dst_rule(rules:sub(1, comma - 1))
    local end_rule = parse_dst_rule(rules:sub(comma + 1))
    if not start_rule or not end_rule then
        return { std_offset = std_offset }
    end

    return {
        std_offset = std_offset,
        dst_offset = dst_offset,
        start_rule = start_rule,
        end_rule = end_rule,
    }
    end

    local function timezone_offset_for_epoch(sec)
    local parsed = parse_posix_timezone(APP.TIMEZONE)
    if not parsed then
        return APP.TZ_OFFSET_SEC or 0
    end
    if not parsed.start_rule or not parsed.end_rule then
        return parsed.std_offset
    end

    local year = year_from_epoch((tonumber(sec) or 0) + parsed.std_offset)
    local start_utc = transition_utc(year, parsed.start_rule, parsed.std_offset)
    local end_utc = transition_utc(year, parsed.end_rule, parsed.dst_offset)
    local in_dst
    if start_utc < end_utc then
        in_dst = sec >= start_utc and sec < end_utc
    else
        in_dst = sec >= start_utc or sec < end_utc
    end
    return in_dst and parsed.dst_offset or parsed.std_offset
    end

    local function apply_weather_address(address)
    address = trim(address)
    APP.WEATHER_LOCATION = address
    if address ~= "" and (APP.CITY_NAME == "" or APP.CITY_NAME == "Weather" or not address:match("^%d+$")) then
        APP.CITY_NAME = address
    end
    end

    local function load_runtime_settings()
    local raw = read_text(APP.SETTINGS_PATH)
    local doc = decode_json(raw) or {}
    APP.settings_doc = doc

    local timezone = trim(doc.timezone)
    if timezone == "" then
        timezone = APP.DEFAULT_TIMEZONE
    end
    APP.TIMEZONE = timezone
    APP.TZ_OFFSET_SEC = posix_tz_offset_sec(timezone)

    APP.LANGUAGE, APP.WEATHER_API_LANG = normalize_language(doc.language or doc.locale or doc.lang)

    local weather_address = trim(doc.weather_address or doc.weatherAddress)
    if weather_address == "" then
        weather_address = APP.DEFAULT_WEATHER_LOCATION
        doc.weather_address = weather_address
        doc.weather_location_address = nil
        doc.weather_location_raw = nil
        doc.weather_location_id = nil
        doc.weather_city = nil
        local encoded = encode_json(doc)
        if not encoded or not write_text(APP.SETTINGS_PATH, encoded) then
        warn("default weather address write failed", APP.SETTINGS_PATH)
        end
        APP.settings_doc = doc
    end
    apply_weather_address(weather_address)

    local city = trim(doc.weather_city or doc.city_name or doc.city)
    local cached_address = trim(doc.weather_location_address or doc.weather_location_raw)
    local cached_id = trim(doc.weather_location_id)
    if cached_address ~= "" and cached_address == APP.WEATHER_LOCATION and cached_id ~= "" then
        APP.state.resolved_location_raw = APP.WEATHER_LOCATION
        APP.state.resolved_location_id = cached_id
    end
    if city ~= "" and (cached_address == "" or cached_address == APP.WEATHER_LOCATION) then
        APP.CITY_NAME = city
    end
    end

    local function save_location_cache(raw_location, location_id, city_name)
    raw_location = trim(raw_location)
    location_id = trim(location_id)
    city_name = trim(city_name)
    if raw_location == "" or location_id == "" then return false end

    local doc = APP.settings_doc
    if type(doc) ~= "table" then doc = {} end
    if trim(doc.weather_location_address) == raw_location
        and trim(doc.weather_location_id) == location_id
        and (city_name == "" or trim(doc.weather_city) == city_name) then
        return true
    end

    doc.weather_location_address = raw_location
    doc.weather_location_id = location_id
    if city_name ~= "" then doc.weather_city = city_name end
    local encoded = encode_json(doc)
    if not encoded then
        warn("location cache encode failed")
        return false
    end
    if not write_text(APP.SETTINGS_PATH, encoded) then
        warn("location cache write failed", APP.SETTINGS_PATH)
        return false
    end
    APP.settings_doc = doc
    log("location cache saved", raw_location, location_id, city_name)
    return true
    end

    local function sd_to_lv(path)
    if type(path) == "string" and path:sub(1, 4) == "/sd/" then
        return "S:/" .. path:sub(5)
    end
    return path
    end

    local function asset_path(group, name)
    return sd_to_lv(APP.ASSET_DIR .. "/" .. group .. "/" .. name .. ".png")
    end

    local function qweather_icon_code(kind)
    local code = tostring(APP.state.code or "")
    if APP.state.valid and code ~= "" and code ~= "--" and code ~= "nil" then
        return code
    end

    if kind == "sunny" then return "100" end
    if kind == "night" then return "150" end
    if kind == "cloudy" then return "104" end
    if kind == "rain" then return "399" end
    if kind == "storm" then return "302" end
    if kind == "snow" then return "499" end
    if kind == "fog" then return "501" end
    return "103"
    end

    local function qweather_icon_code_for(kind, code)
    code = tostring(code or "")
    if code ~= "" and code ~= "--" and code ~= "nil" then
        return code
    end
    return qweather_icon_code(kind)
    end

    local function qweather_icon_path(kind)
    return sd_to_lv(APP.ASSET_DIR .. "/icons/set2/" .. qweather_icon_code(kind) .. ".png")
    end

    local function qweather_icon_path_for(kind, code)
    return sd_to_lv(APP.ASSET_DIR .. "/icons/set2/" .. qweather_icon_code_for(kind, code) .. ".png")
    end

    local function font_load_now_ms()
    if millis then
        local ok, v = pcall_fn(millis)
        if ok and type(v) == "number" then
        return v
        end
    end
    if tmr and tmr.now then
        local ok, v = pcall_fn(function()
        return tmr.now()
        end)
        if ok and type(v) == "number" then
        return math_floor(v / 1000)
        end
    end
    return 0
    end

    local function load_font_ref(path, fallback)
    local start_ms = font_load_now_ms()
    if lv_font_load then
        local ok, handle_or_err = pcall_fn(function()
        return lv_font_load(path)
        end)
        local elapsed_ms = font_load_now_ms() - start_ms
        if ok and type(handle_or_err) == "number" and handle_or_err > 0 then
        local handle = handle_or_err
        APP.font_handles[#APP.font_handles + 1] = handle
        warn("font load ok", path, "handle", handle, "ms", elapsed_ms)
        return handle
        end

        warn("font load failed", path, "ms", elapsed_ms, "err", ok and tostring(handle_or_err) or tostring(handle_or_err))
    else
        warn("font load failed", path, "ms", 0, "err", "lv_font_load missing")
    end
    return fallback
    end

    local function init_fonts()
    FONT_10 = load_font_ref("/sd/apps/weather/font/weather_tiny_10.bin", FONT_10)
    if APP.LANGUAGE == "zh-CN" then
        FONT_12 = load_font_ref("/sd/apps/weather/font/weather_ui_zh_cn_12.bin", FONT_12)
        FONT_16 = load_font_ref("/sd/apps/weather/font/weather_ui_zh_cn_16.bin", FONT_16)
    elseif APP.LANGUAGE == "zh-TW" then
        FONT_12 = load_font_ref("/sd/apps/weather/font/weather_ui_zh_tw_12.bin", FONT_12)
        FONT_16 = load_font_ref("/sd/apps/weather/font/weather_ui_zh_tw_16.bin", FONT_16)
    elseif APP.LANGUAGE == "ja" then
        FONT_12 = load_font_ref("/sd/apps/weather/font/weather_ui_ja_12.bin", FONT_12)
        FONT_16 = load_font_ref("/sd/apps/weather/font/weather_ui_ja_16.bin", FONT_16)
    else
        FONT_12 = load_font_ref("/sd/apps/weather/font/weather_ui_12.bin", FONT_12)
        FONT_16 = load_font_ref("/sd/apps/weather/font/weather_ui_16.bin", FONT_16)
    end
    FONT_28 = load_font_ref("/sd/apps/weather/font/weather_num_28.bin", FONT_28)
    FONT_34 = load_font_ref("/sd/apps/weather/font/weather_temp_34.bin", FONT_28)
    FONT_40 = load_font_ref("/sd/apps/weather/font/weather_time_40.bin", FONT_28)
    end

    local function release_fonts()
    if lv_font_free then
        for _, handle in ipairs(APP.font_handles) do
        pcall_fn(function()
            lv_font_free(handle)
        end)
        end
    end
    APP.font_handles = {}
    end

    local function set_img_src(id, src)
    if id and lv_img_set_src and src and src ~= "" then
        pcall_fn(function()
        lv_img_set_src(id, src)
        end)
    end
    end

    local function set_obj_hidden(id, hidden)
    local flag = rawget(_G, "LV_OBJ_FLAG_HIDDEN")
    if not id or not flag or not lv_obj_add_flag or not lv_obj_clear_flag then
        return false
    end

    if hidden then
        call(lv_obj_add_flag, id, flag)
    else
        call(lv_obj_clear_flag, id, flag)
    end
    return true
    end

    local function set_fullscreen_overlay_hidden(id, hidden)
    if set_obj_hidden(id, hidden) then
        return true
    end

    if id and lv_obj_set_pos then
        call(lv_obj_set_pos, id, hidden and APP.SCREEN_W or 0, 0)
        return true
    end

    return false
    end

    local function get_number(v)
    if v == nil then return nil end
    if type(v) == "number" then return v end
    return tonumber(v)
    end

    local function to_x10(v)
    local n = get_number(v)
    if n == nil then return nil end
    if n >= 0 then
        return math_floor(n * 10 + 0.5)
    end
    return math.ceil(n * 10 - 0.5)
    end

    local function two(n)
    n = tonumber(n) or 0
    if n < 10 then
        return "0" .. tostring(n)
    end
    return tostring(n)
    end

    local function short_text(s, max_len)
    s = tostring(s or "")
    max_len = math_floor(tonumber(max_len) or 0)
    if max_len <= 0 then return s end
    local positions = {}
    local i = 1
    while i <= #s do
        positions[#positions + 1] = i
        local b = string.byte(s, i) or 0
        if b < 0x80 then i = i + 1
        elseif b < 0xE0 then i = i + 2
        elseif b < 0xF0 then i = i + 3
        else i = i + 4 end
    end
    if #positions <= max_len then return s end
    local keep = math.max(1, max_len - 3)
    local end_pos = positions[keep + 1] or (#s + 1)
    return s:sub(1, end_pos - 1) .. "..."
    end

    local function now_ms()
    if millis then
        local ok, v = pcall_fn(millis)
        if ok and type(v) == "number" then
        return v
        end
    end
    return 0
    end

    local function request_time_sync(force)
    if not time then
        return
    end

    local now = now_ms()
    if not force and (now - (APP.state.last_ntp_retry_ms or 0)) < APP.TIME_SYNC_RETRY_MS then
        return
    end

    APP.state.last_ntp_retry_ms = now

    if time.settimezone then
        call(time.settimezone, APP.TIMEZONE)
    end

    if time.initntp then
        local ok = pcall_fn(function()
        time.initntp(APP.NTP_SERVER)
        end)
        APP.state.ntp_enabled = ok and true or APP.state.ntp_enabled
    end
    end

    local function init_time_module()
    if not time or not time.getlocal then
        return
    end

    if time.settimezone then
        call(time.settimezone, APP.TIMEZONE)
    end

    if time.ntpenabled then
        local ok, enabled = pcall_fn(function()
        return time.ntpenabled()
        end)
        if ok then
        APP.state.ntp_enabled = enabled and true or false
        if not enabled then
            request_time_sync(true)
        end
        end
    end
    end

    local function tm_from_time_module()
    if not time or not time.getlocal then
        return nil
    end

    local ok, t = pcall_fn(function()
        return time.getlocal()
    end)
    if ok and type(t) == "table" and t.year and t.mon and t.day and t.year >= 2024 then
        return {
        year = t.year,
        mon = t.mon,
        day = t.day,
        hour = t.hour or 0,
        min = t.min or 0,
        sec = t.sec or 0,
        }
    end

    return nil
    end

    local function tm_from_rtctime()
    if not rtctime or not rtctime.get or not rtctime.epoch2cal then
        return nil
    end

    local ok_get, sec = pcall_fn(rtctime.get)
    if not ok_get or type(sec) ~= "number" or sec <= 0 then
        return nil
    end

    local ok_cal, year, mon, day, hour, min, sec2 = pcall_fn(rtctime.epoch2cal, sec + timezone_offset_for_epoch(sec))
    if ok_cal and type(year) == "number" and type(hour) == "number" and type(min) == "number" then
        return {
        year = year,
        mon = mon,
        day = day,
        hour = hour,
        min = min,
        sec = sec2 or 0,
        }
    end

    return nil
    end

    local function tm_from_os()
    if not os or not os.date or not os.time then
        return nil
    end

    local ok_now, sec = pcall_fn(os.time)
    if not ok_now or type(sec) ~= "number" or sec <= 0 then
        return nil
    end

    local ok, t = pcall_fn(os.date, "!*t", sec + timezone_offset_for_epoch(sec))
    if ok and type(t) == "table" and t.year and t.mon and t.day and t.year >= 2024 then
        return {
        year = t.year,
        mon = t.mon,
        day = t.day,
        hour = t.hour or 0,
        min = t.min or 0,
        sec = t.sec or 0,
        }
    end

    return nil
    end

    local function get_local_tm()
    local t = tm_from_time_module()
    if t then
        APP.state.clock_valid = true
        return t
    end
    t = tm_from_rtctime()
    if t then
        APP.state.clock_valid = true
        return t
    end
    t = tm_from_os()
    if t then
        APP.state.clock_valid = true
        return t
    end

    APP.state.clock_valid = false
    request_time_sync(false)
    return nil
    end

    local function is_night_time()
    local t = get_local_tm()
    if not t then
        return false
    end
    return (t.hour or 12) >= 19 or (t.hour or 12) < 6
    end

    local function format_clock_text()
    local t = get_local_tm()
    if not t then
        return "--:--"
    end
    return two(t.hour) .. ":" .. two(t.min)
    end

    local function format_date_text()
    local t = get_local_tm()
    if not t then
        return tr("sync_time")
    end
    if t.year and t.mon and t.day then
        return string_format("%04d.%s.%s", t.year, two(t.mon), two(t.day))
    end
    if t.mon and t.day then
        return two(t.mon) .. "/" .. two(t.day)
    end
    return "----.--.--"
    end

    local function format_temp_text(temp)
    if temp == nil then
        return "--" .. CELSIUS
    end

    local n = temp
    if n >= 0 then
        n = math_floor(n + 0.5)
    else
        n = -math_floor(math_abs(n) + 0.5)
    end
    return tostring(n) .. CELSIUS
    end

    local function format_condition_text(text)
    text = tostring(text or "")
    if text == "" then
        return tr("waiting")
    end
    return short_text(text, 12)
    end

    local function format_precip_text()
    if APP.state.precip_x10 == nil then
        return "--mm"
    end
    if APP.state.precip_x10 == 0 then
        return "0mm"
    end
    return string_format("%.1fmm", APP.state.precip_x10 / 10.0)
    end

    local function format_mm_x10(x10)
    if x10 == nil then
        return "--mm"
    end
    if x10 == 0 then
        return "0mm"
    end
    return string_format("%.1fmm", x10 / 10.0)
    end

    local function format_humidity_text(v)
    if v == nil then return "--%" end
    return string_format("%d%%", math_floor(v + 0.5))
    end

    local function rounded_int_text(v)
    if v == nil then
        return "--"
    end
    if v >= 0 then
        return tostring(math_floor(v + 0.5))
    end
    return tostring(-math_floor(math_abs(v) + 0.5))
    end

    local function format_forecast_temp_text(max_temp, min_temp)
    if max_temp == nil and min_temp == nil then
        return "--/--" .. CELSIUS
    end

    return rounded_int_text(max_temp) .. "/" .. rounded_int_text(min_temp) .. CELSIUS
    end

    local function format_wind_level(speed)
    if speed == nil then return "--" end

    local n = tonumber(speed) or 0
    local levels = { 1, 6, 12, 20, 29, 39, 50, 62, 75, 89, 103, 118 }
    local idx = 0
    while idx < #levels and n >= levels[idx + 1] do
        idx = idx + 1
    end
    return "L" .. tostring(idx)
    end

    local function weather_kind()
    local code = tonumber(APP.state.code or "")
    local text = tostring(APP.state.text or "")

    if not APP.state.valid then
        return is_night_time() and "night" or "partly"
    end

    if code then
        if code == 302 or code == 303 or code == 304 then return "storm" end
        if code >= 300 and code < 400 then return "rain" end
        if code >= 400 and code < 500 then return "snow" end
        if code >= 500 and code < 600 then return "fog" end
        if code >= 150 and code <= 154 then return "night" end
        if code == 100 then return is_night_time() and "night" or "sunny" end
        if code == 104 then return "cloudy" end
        if code >= 101 and code <= 103 then return is_night_time() and "night" or "partly" end
    end

    if text:find("Thunder") or text:find("storm") or text:find("Storm") then return "storm" end
    if text:find("Rain") or text:find("rain") then return "rain" end
    if text:find("Snow") or text:find("snow") then return "snow" end
    if text:find("Fog") or text:find("fog") or text:find("Haze") then return "fog" end
    if text:find("Cloud") or text:find("cloud") then return "cloudy" end

    return is_night_time() and "night" or "partly"
    end

    local function reset_obj(id)
    if not id then return end
    call(rawget(_G, "lv_obj_remove_style_all"), id)
    if lv_obj_clear_flag and rawget(_G, "LV_OBJ_FLAG_SCROLLABLE") then
        call(lv_obj_clear_flag, id, rawget(_G, "LV_OBJ_FLAG_SCROLLABLE"))
    end
    end

    local function set_label_text(id, text)
    if id and lv_label_set_text then
        pcall_fn(function()
        lv_label_set_text(id, tostring(text or ""))
        end)
    end
    end

    local function style_panel(id, bg, opa, radius, border_opa)
    if not id then return end

    reset_obj(id)
    call(lv_obj_set_style_bg_color, id, bg or C.glass, MAIN_STYLE)
    call(lv_obj_set_style_bg_opa, id, opa or 180, MAIN_STYLE)
    call(lv_obj_set_style_radius, id, radius or 6, MAIN_STYLE)
    call(lv_obj_set_style_border_width, id, 1, MAIN_STYLE)
    call(lv_obj_set_style_border_color, id, C.border, MAIN_STYLE)
    call(lv_obj_set_style_border_opa, id, border_opa or 72, MAIN_STYLE)
    call(rawget(_G, "lv_obj_set_style_pad_all"), id, 0, MAIN_STYLE)
    call(rawget(_G, "lv_obj_set_style_clip_corner"), id, true, MAIN_STYLE)
    end

    local function style_overlay(id)
    reset_obj(id)
    call(lv_obj_set_style_bg_opa, id, 0, MAIN_STYLE)
    call(lv_obj_set_style_border_width, id, 0, MAIN_STYLE)
    call(lv_obj_set_style_radius, id, 0, MAIN_STYLE)
    call(rawget(_G, "lv_obj_set_style_pad_all"), id, 0, MAIN_STYLE)
    end

    local function style_frosted_panel(id)
    style_panel(id, C.strip, 0, 12, 72)
    call(rawget(_G, "lv_obj_set_style_shadow_width"), id, 12, MAIN_STYLE)
    call(rawget(_G, "lv_obj_set_style_shadow_color"), id, C.black, MAIN_STYLE)
    call(rawget(_G, "lv_obj_set_style_shadow_opa"), id, 76, MAIN_STYLE)
    end

    local function create_glass_line(parent, x, y, w, h, opa)
    local id = lv_obj_create(parent)
    reset_obj(id)
    call(lv_obj_set_pos, id, x, y)
    call(lv_obj_set_size, id, w, h)
    call(lv_obj_set_style_bg_color, id, C.glass_line, MAIN_STYLE)
    call(lv_obj_set_style_bg_opa, id, opa or 36, MAIN_STYLE)
    call(lv_obj_set_style_radius, id, h > 1 and math_floor(h / 2) or 0, MAIN_STYLE)
    call(lv_obj_set_style_border_width, id, 0, MAIN_STYLE)
    call(rawget(_G, "lv_obj_set_style_pad_all"), id, 0, MAIN_STYLE)
    return id
    end

    local function style_label(id, font, color, opa, align)
    if not id then return end
    call(lv_obj_set_style_text_font, id, font, MAIN_STYLE)
    call(lv_obj_set_style_text_color, id, color or C.text, MAIN_STYLE)
    call(rawget(_G, "lv_obj_set_style_text_opa"), id, opa or 255, MAIN_STYLE)
    call(rawget(_G, "lv_obj_set_style_text_letter_space"), id, 0, MAIN_STYLE)
    if align then
        call(rawget(_G, "lv_obj_set_style_text_align"), id, align, MAIN_STYLE)
    end
    end

    local function create_label(parent, text, font, color, x, y, w, align)
    local id = lv_label_create(parent)
    reset_obj(id)
    set_label_text(id, text)
    call(lv_obj_set_pos, id, x or 0, y or 0)
    if w and w > 0 then
        call(lv_obj_set_width, id, w)
        if LABEL_LONG_CLIP and lv_label_set_long_mode then
        call(lv_label_set_long_mode, id, LABEL_LONG_CLIP)
        end
    end
    style_label(id, font, color, 255, align)
    return id
    end

    local function create_img(parent, src, x, y, zoom)
    local id = lv_img_create(parent)
    reset_obj(id)
    call(lv_obj_set_pos, id, x or 0, y or 0)
    if zoom and lv_img_set_zoom then
        call(lv_img_set_zoom, id, zoom)
    end
    if lv_img_set_antialias then
        call(lv_img_set_antialias, id, true)
    end
    set_img_src(id, src)
    return id
    end

    local function release_glass_snapshot()
    if not APP.state.glass_snapshot then
        return
    end

    if lv_snapshot_free then
        call(lv_snapshot_free, APP.state.glass_snapshot)
    elseif lv_img_free_handle then
        call(lv_img_free_handle, APP.state.glass_snapshot)
    end

    APP.state.glass_snapshot = nil
    end

    local function release_forecast_glass_snapshot()
    if not APP.state.forecast_glass_snapshot then
        return
    end

    if lv_snapshot_free then
        call(lv_snapshot_free, APP.state.forecast_glass_snapshot)
    elseif lv_img_free_handle then
        call(lv_img_free_handle, APP.state.forecast_glass_snapshot)
    end

    APP.state.forecast_glass_snapshot = nil
    end

    local function canvas_frame_begin(id)
    local fn = rawget(_G, "lv_canvas_frame_begin") or rawget(_G, "lv_canvas_begin")
    if not id or not fn then
        return false
    end
    return call(fn, id)
    end

    local function canvas_frame_end(id)
    local fn = rawget(_G, "lv_canvas_frame_end") or rawget(_G, "lv_canvas_end")
    if id and fn then
        call(fn, id)
        return
    end

    if id and lv_obj_invalidate then
        call(lv_obj_invalidate, id)
    end
    end

    local function canvas_clear(id, color, opa)
    local fn = rawget(_G, "lv_canvas_fill_bg") or rawget(_G, "lv_canvas_fill")
    if fn then
        call(fn, id, color, opa)
    end
    end

    local function canvas_rect(id, x, y, w, h, color, opa)
    if lv_canvas_draw_rect then
        call(lv_canvas_draw_rect, id, x, y, w, h, color, opa)
    end
    end

    local function refresh_glass_panel()
    local cvs = APP.ui.strip_blur
    local root = APP.ui.root
    local strip = APP.ui.strip
    if not cvs or not root or not strip then
        return
    end
    if APP.state.startup_visible then
        return
    end

    release_glass_snapshot()
    if not canvas_frame_begin(cvs) then
        return
    end

    canvas_clear(cvs, C.strip, 255)
    set_obj_hidden(strip, true)

    local ok, snapshot = pcall_fn(function()
        return lv_snapshot_take(root, CANVAS_FMT)
    end)

    set_obj_hidden(strip, false)

    if ok and snapshot then
        APP.state.glass_snapshot = snapshot
        call(lv_canvas_draw_img, cvs, -GLASS_X, -GLASS_Y, { handle = snapshot }, { opa = 255 })
        call(lv_canvas_blur_hor, cvs, nil, GLASS_BLUR)
        call(lv_canvas_blur_ver, cvs, nil, GLASS_BLUR)
    end

    canvas_rect(cvs, 0, 0, GLASS_W, GLASS_H, 0xFFFFFF, 30)
    canvas_rect(cvs, 0, 0, GLASS_W, GLASS_H, C.strip, 82)
    canvas_rect(cvs, 0, GLASS_H - 1, GLASS_W, 1, C.black, 42)
    canvas_frame_end(cvs)
    end

    local function refresh_forecast_glass_panel()
    local cvs = APP.ui.forecast_blur
    local root = APP.ui.root
    local panel = APP.ui.forecast_panel
    if not cvs or not root or not panel then
        return
    end
    if APP.state.startup_visible then
        return
    end

    release_forecast_glass_snapshot()
    if not canvas_frame_begin(cvs) then
        return
    end

    canvas_clear(cvs, C.strip, 255)
    local hidden = set_obj_hidden(panel, true)
    if not hidden then
        call(lv_obj_set_pos, panel, APP.SCREEN_W, FORECAST_GLASS_Y)
    end

    local ok, snapshot = pcall_fn(function()
        return lv_snapshot_take(root, CANVAS_FMT)
    end)

    if hidden then
        set_obj_hidden(panel, false)
    else
        call(lv_obj_set_pos, panel, FORECAST_GLASS_X, FORECAST_GLASS_Y)
    end

    if ok and snapshot then
        APP.state.forecast_glass_snapshot = snapshot
        call(lv_canvas_draw_img, cvs, -FORECAST_GLASS_X, -FORECAST_GLASS_Y, { handle = snapshot }, { opa = 255 })
        call(lv_canvas_blur_hor, cvs, nil, FORECAST_GLASS_BLUR)
        call(lv_canvas_blur_ver, cvs, nil, FORECAST_GLASS_BLUR)
    end

    canvas_rect(cvs, 0, 0, FORECAST_GLASS_W, FORECAST_GLASS_H, 0xFFFFFF, 18)
    canvas_rect(cvs, 0, 0, FORECAST_GLASS_W, FORECAST_GLASS_H, C.strip, 54)
    canvas_rect(cvs, 0, FORECAST_GLASS_H - 1, FORECAST_GLASS_W, 1, C.black, 32)
    canvas_frame_end(cvs)
    end

    local function create_bottom_item(parent, x, icon_name, small_icon, width)
    local item_w = width or 70
    local icon_zoom = small_icon and 256 or 128
    local icon_visual_w = small_icon and 24 or 32
    local icon_x = math_floor((item_w - icon_visual_w) / 2)

    local group = lv_obj_create(parent)
    reset_obj(group)
    call(lv_obj_set_pos, group, x, 0)
    call(lv_obj_set_size, group, item_w, 68)

    local value = create_label(group, "--", FONT_16, C.text, 0, 7, item_w, ALIGN_CENTER)
    local icon_src = small_icon and asset_path("icons", icon_name .. "_sm") or asset_path("icons", icon_name)
    local icon = create_img(group, icon_src, icon_x, small_icon and 35 or 30, icon_zoom)

    return {
        group = group,
        value = value,
        icon = icon,
        small_icon = small_icon,
    }
    end

    local function create_forecast_item(parent, x, label)
    local item_w = 100
    local group = lv_obj_create(parent)
    style_overlay(group)
    call(lv_obj_set_pos, group, x, 0)
    call(lv_obj_set_size, group, item_w, 170)

    local day = create_label(group, label or "--", FONT_12, C.text_soft, 0, 12, item_w, ALIGN_CENTER)
    local icon = create_img(group, qweather_icon_path_for("partly", "103"), 27, 38, 180)
    local text = create_label(group, "--", FONT_12, C.text, 8, 91, item_w - 16, ALIGN_CENTER)
    local temp = create_label(group, "--/--" .. CELSIUS, FONT_16, C.text, 0, 114, item_w, ALIGN_CENTER)
    local rain = create_label(group, "--mm", FONT_12, C.text_soft, 0, 141, item_w, ALIGN_CENTER)

    return {
        group = group,
        day = day,
        icon = icon,
        text = text,
        temp = temp,
        rain = rain,
    }
    end

    local function create_forecast_page(root)
    local page = lv_obj_create(root)
    call(lv_obj_set_pos, page, APP.SCREEN_W, 0)
    set_obj_hidden(page, true)
    style_overlay(page)
    call(lv_obj_set_pos, page, APP.SCREEN_W, 0)
    call(lv_obj_set_size, page, APP.SCREEN_W, APP.SCREEN_H)
    set_fullscreen_overlay_hidden(page, true)

    local panel = lv_obj_create(page)
    APP.ui.forecast_panel = panel
    style_panel(panel, C.strip, 56, 12, 56)
    call(lv_obj_set_pos, panel, FORECAST_GLASS_X, FORECAST_GLASS_Y)
    call(lv_obj_set_size, panel, FORECAST_GLASS_W, FORECAST_GLASS_H)

    if lv_canvas_create then
        if CANVAS_FMT then
        APP.ui.forecast_blur = lv_canvas_create(panel, FORECAST_GLASS_W, FORECAST_GLASS_H, CANVAS_FMT)
        else
        APP.ui.forecast_blur = lv_canvas_create(panel, FORECAST_GLASS_W, FORECAST_GLASS_H)
        end
        call(lv_obj_set_pos, APP.ui.forecast_blur, 0, 0)
        if lv_obj_clear_flag and rawget(_G, "LV_OBJ_FLAG_SCROLLABLE") then
        call(lv_obj_clear_flag, APP.ui.forecast_blur, rawget(_G, "LV_OBJ_FLAG_SCROLLABLE"))
        end
    end

    APP.ui.forecast_sep1 = create_glass_line(panel, 100, 16, 1, 138, 28)
    APP.ui.forecast_sep2 = create_glass_line(panel, 199, 16, 1, 138, 28)
    APP.ui.forecast_top = create_glass_line(panel, 24, 8, 252, 1, 14)
    APP.ui.forecast_bottom = create_glass_line(panel, 24, 160, 252, 1, 14)

    APP.ui.forecast_cols = {
        create_forecast_item(panel, 0, tr("today")),
        create_forecast_item(panel, 100, "+1D"),
        create_forecast_item(panel, 200, "+2D"),
    }

    return page
    end

    local function create_startup_page(root)
    local page = lv_obj_create(root)
    reset_obj(page)
    call(lv_obj_set_pos, page, 0, 0)
    call(lv_obj_set_size, page, APP.SCREEN_W, APP.SCREEN_H)
    call(lv_obj_set_style_bg_color, page, C.black, MAIN_STYLE)
    call(lv_obj_set_style_bg_opa, page, 255, MAIN_STYLE)
    call(lv_obj_set_style_border_width, page, 0, MAIN_STYLE)
    call(rawget(_G, "lv_obj_set_style_pad_all"), page, 0, MAIN_STYLE)

    APP.ui.startup_icon = create_img(page, qweather_icon_path_for("partly", "103"), 136, 58, 192)
    APP.ui.startup_city_label = create_label(page, startup_boot_city(), FONT_16, C.text, 32, 120, 256, ALIGN_CENTER)
    APP.ui.startup_title_label = create_label(page, "Weather", FONT_12, C.text_soft, 32, 145, 256, ALIGN_CENTER)
    create_glass_line(page, 118, 170, 84, 1, 42)

    APP.state.startup_visible = true
    call(rawget(_G, "lv_obj_move_foreground"), page)
    return page
    end

    local function refresh_startup_labels()
    set_label_text(APP.ui.startup_city_label, display_city_name())
    set_label_text(APP.ui.startup_title_label, tr("weather"))
    style_label(APP.ui.startup_city_label, FONT_16, C.text, 255, ALIGN_CENTER)
    style_label(APP.ui.startup_title_label, FONT_12, C.text_soft, 255, ALIGN_CENTER)
    end

    local function get_startup_parent(root)
    local layer_top_fn = rawget(_G, "lv_layer_top")
    if layer_top_fn then
        local ok, top = pcall_fn(layer_top_fn)
        if ok and top then
        return top
        end
    end
    return root
    end

    local function create_screen()
    if not lv_obj_create then
        return nil
    end

    local ok, screen = pcall_fn(function()
        return lv_obj_create(nil)
    end)
    if ok and screen then
        return screen
    end
    return nil
    end

    local function load_screen(screen)
    if screen and lv_scr_load then
        return call(lv_scr_load, screen)
    end
    return false
    end

    local function update_assets(kind)
    APP.state.kind = kind
    set_img_src(APP.ui.bg_img, asset_path("bg", kind))
    APP.state.displayed_icon_code = nil
    set_img_src(APP.ui.weather_icon, qweather_icon_path(kind))
    APP.state.displayed_icon_code = qweather_icon_code(kind)
    refresh_glass_panel()
    if APP.state.page == "forecast" then
        refresh_forecast_glass_panel()
    end
    end

    local function update_weather_icon(kind)
    local code = qweather_icon_code(kind)
    if code ~= APP.state.displayed_icon_code then
        set_img_src(APP.ui.weather_icon, qweather_icon_path(kind))
        APP.state.displayed_icon_code = code
    end
    end

    local function init_ui()
    local root = nil
    local startup_screen = nil
    local main_screen = nil

    if lv_scr_load then
        startup_screen = create_screen()
        main_screen = create_screen()
    end

    if startup_screen and main_screen then
        APP.ui.startup_page = create_startup_page(startup_screen)
        if load_screen(startup_screen) then
        APP.ui.startup_screen = startup_screen
        APP.ui.main_screen = main_screen
        root = main_screen
        else
        APP.ui.startup_page = nil
        APP.state.startup_visible = false
        end
    end

    if not root then
        root = lv_scr_act()
        lv_clear()
        local startup_parent = get_startup_parent(root)
        APP.ui.startup_page = create_startup_page(startup_parent)
    end

    -- 启动页先用内置小字体显示并刷新，再同步加载当前语言的大字库。
    if lv_refr_now then
        pcall_fn(function() lv_refr_now(nil) end)
    elseif lv_timer_handler then
        pcall_fn(lv_timer_handler)
    elseif lv_task_handler then
        pcall_fn(lv_task_handler)
    end
    init_fonts()

    APP.ui.root = root

    call(lv_obj_set_style_bg_color, root, C.black, MAIN_STYLE)
    call(lv_obj_set_style_bg_opa, root, 255, MAIN_STYLE)
    if lv_obj_clear_flag and rawget(_G, "LV_OBJ_FLAG_SCROLLABLE") then
        call(lv_obj_clear_flag, root, rawget(_G, "LV_OBJ_FLAG_SCROLLABLE"))
    end

    refresh_startup_labels()

    APP.ui.bg_img = create_img(root, asset_path("bg", "partly"), 0, 0)

    local now_page = lv_obj_create(root)
    APP.ui.now_page = now_page
    style_overlay(now_page)
    call(lv_obj_set_pos, now_page, 0, 0)
    call(lv_obj_set_size, now_page, APP.SCREEN_W, APP.SCREEN_H)

    APP.ui.time_label = create_label(now_page, "--:--", FONT_34, C.text, 14, 23, 150, ALIGN_LEFT)
    APP.ui.city_label = create_label(now_page, display_city_name(), FONT_16, C.text, 16, 68, 166, ALIGN_LEFT)
    APP.ui.cond_label = create_label(now_page, tr("waiting"), FONT_12, C.text, 16, 90, 132, ALIGN_LEFT)
    APP.ui.date_label = create_label(now_page, "--/--", FONT_12, C.text_soft, 16, 113, 132, ALIGN_LEFT)

    APP.ui.weather_icon = create_img(now_page, qweather_icon_path("partly"), 206, 20, 320)
    APP.state.displayed_icon_code = qweather_icon_code("partly")
    APP.ui.temp_label = create_label(now_page, "--" .. CELSIUS, FONT_34, C.text, 184, 100, 124, ALIGN_CENTER)

    local strip = lv_obj_create(now_page)
    APP.ui.strip = strip
    style_frosted_panel(strip)
    call(lv_obj_set_pos, strip, GLASS_X, GLASS_Y)
    call(lv_obj_set_size, strip, GLASS_W, GLASS_H)

    if lv_canvas_create then
        if CANVAS_FMT then
        APP.ui.strip_blur = lv_canvas_create(strip, GLASS_W, GLASS_H, CANVAS_FMT)
        else
        APP.ui.strip_blur = lv_canvas_create(strip, GLASS_W, GLASS_H)
        end
        call(lv_obj_set_pos, APP.ui.strip_blur, 0, 0)
        if lv_obj_clear_flag and rawget(_G, "LV_OBJ_FLAG_SCROLLABLE") then
        call(lv_obj_clear_flag, APP.ui.strip_blur, rawget(_G, "LV_OBJ_FLAG_SCROLLABLE"))
        end
    end

    APP.ui.strip_bottom = create_glass_line(strip, 24, 63, 252, 1, 16)
    APP.ui.strip_sep1 = create_glass_line(strip, 100, 12, 1, 42, 28)
    APP.ui.strip_sep2 = create_glass_line(strip, 199, 12, 1, 42, 28)

    APP.ui.precip = create_bottom_item(strip, 4, "precip", true, 94)
    APP.ui.humidity = create_bottom_item(strip, 103, "humidity", true, 94)
    APP.ui.wind = create_bottom_item(strip, 202, "wind", true, 94)

    APP.ui.forecast_page = create_forecast_page(root)
    if not set_obj_hidden(APP.ui.forecast_page, true) then
        call(lv_obj_set_pos, APP.ui.forecast_page, APP.SCREEN_W, 0)
    end

    refresh_glass_panel()
    if not APP.ui.startup_screen then
        call(rawget(_G, "lv_obj_move_foreground"), APP.ui.startup_page)
    end
    APP.ui.ready = true
    end

    local function render_clock()
    set_label_text(APP.ui.time_label, format_clock_text())
    set_label_text(APP.ui.city_label, display_city_name())
    set_label_text(APP.ui.startup_city_label, display_city_name())
    set_label_text(APP.ui.date_label, format_date_text())
    end

    local function render_weather()
    if not APP.running then
        return
    end
    if not APP.ui.ready then
        return
    end

    local kind = weather_kind()
    if kind ~= APP.state.kind then
        update_assets(kind)
    else
        update_weather_icon(kind)
    end

    if not APP.state.valid then
        set_label_text(APP.ui.temp_label, "--" .. CELSIUS)
        set_label_text(APP.ui.cond_label, APP.state.request_inflight and tr("updating") or tr("waiting"))
        set_label_text(APP.ui.precip.value, "--mm")
        set_label_text(APP.ui.humidity.value, "--%")
        set_label_text(APP.ui.wind.value, "--")
        return
    end

    set_label_text(APP.ui.temp_label, format_temp_text(APP.state.temp))
    set_label_text(APP.ui.cond_label, format_condition_text(APP.state.text))
    set_label_text(APP.ui.precip.value, format_precip_text())
    set_label_text(APP.ui.humidity.value, format_humidity_text(APP.state.humidity))
    set_label_text(APP.ui.wind.value, format_wind_level(APP.state.wind_speed))
    end

    local function render_forecast()
    local cols = APP.ui.forecast_cols
    if not cols then
        return
    end

    local days = APP.state.forecast.days or {}
    for i = 1, 3 do
        local col = cols[i]
        local day = days[i]
        if col then
        set_label_text(col.day, i == 1 and tr("today") or ("+" .. tostring(i - 1) .. "D"))
        if APP.state.forecast.valid and day then
            set_img_src(col.icon, qweather_icon_path_for("partly", day.icon))
            set_label_text(col.text, format_condition_text(day.text))
            set_label_text(col.temp, format_forecast_temp_text(day.temp_max, day.temp_min))
            set_label_text(col.rain, format_mm_x10(day.precip_x10))
        else
            set_img_src(col.icon, qweather_icon_path_for("partly", "103"))
            set_label_text(col.text, "--")
            set_label_text(col.temp, "--/--" .. CELSIUS)
            set_label_text(col.rain, "--mm")
        end
        end
    end
    end

    local request_forecast

local function set_page_hidden(id, hidden)
    set_obj_hidden(id, hidden)
    call(lv_obj_set_pos, id, hidden and APP.SCREEN_W or 0, 0)
end

    local function set_page(page)
    if page ~= "forecast" then
        page = "now"
    end
    if APP.state.page == page then
        return
    end

    APP.state.page = page
    set_page_hidden(APP.ui.now_page, page ~= "now")
    set_page_hidden(APP.ui.forecast_page, page ~= "forecast")

    if page == "now" then
        refresh_glass_panel()
    else
        refresh_forecast_glass_panel()
        render_forecast()
        if request_forecast and not APP.state.forecast.valid and not APP.state.forecast.request_inflight then
        request_forecast()
        end
    end
    end

    local function toggle_forecast_page()
    if APP.state.page == "forecast" then
        set_page("now")
    else
        set_page("forecast")
    end
    end

    local release_startup_page

    local function hide_startup_page()
    if not APP.state.startup_visible then
        return
    end

    local switched = false
    if APP.ui.main_screen and lv_scr_load then
        switched = load_screen(APP.ui.main_screen) and true or false
        if not switched then
        return
        end
    else
        set_fullscreen_overlay_hidden(APP.ui.startup_page, true)
    end

    APP.state.startup_visible = false
    refresh_glass_panel()
    if APP.state.page == "forecast" then
        refresh_forecast_glass_panel()
    end

    release_startup_page()
    end

    release_startup_page = function()
    if not APP.ui.startup_page and not APP.ui.startup_screen then
        return
    end

    set_fullscreen_overlay_hidden(APP.ui.startup_page, true)
    local del_fn = rawget(_G, "lv_obj_del") or rawget(_G, "lv_obj_delete")
    if del_fn then
        if APP.ui.startup_page then
        pcall_fn(function()
            del_fn(APP.ui.startup_page)
        end)
        end
        if APP.ui.startup_screen then
        pcall_fn(function()
            del_fn(APP.ui.startup_screen)
        end)
        end
    end
    APP.ui.startup_page = nil
    APP.ui.startup_screen = nil
    APP.ui.startup_icon = nil
    APP.ui.startup_city_label = nil
    APP.ui.startup_title_label = nil
    APP.state.startup_visible = false
    end

    local function maybe_gunzip_body(body)
    if not body then
        return nil, "body nil"
    end

    if zlib and zlib.isgzip and zlib.isgzip(body) then
        if not zlib.gunzip then
        return nil, "gzip unsupported"
        end

        local plain, err = zlib.gunzip(body)
        if not plain then
        return nil, "gunzip " .. tostring(err)
        end
        return plain
    end

    return body
    end

    local function parse_weather_body(status_code, body)
    APP.state.last_http_code = status_code

    if status_code ~= 200 or not body then
        APP.state.valid = false
        APP.state.last_error = "HTTP " .. tostring(status_code)
        return false
    end

    if not json or not json.decode then
        APP.state.valid = false
        APP.state.last_error = "JSON missing"
        return false
    end

    local doc, err = json.decode(body)
    if not doc then
        APP.state.valid = false
        APP.state.last_error = "JSON " .. tostring(err)
        return false
    end

    local api_code = tostring(doc.code or "")
    if api_code ~= "200" then
        APP.state.valid = false
        APP.state.last_error = "API " .. api_code
        return false
    end

    local now = doc.now
    if type(now) ~= "table" then
        APP.state.valid = false
        APP.state.last_error = "NO NOW"
        return false
    end

    APP.state.valid = true
    APP.state.last_error = nil
    APP.state.temp = get_number(now.temp)
    APP.state.humidity = get_number(now.humidity)
    APP.state.wind_speed = get_number(now.windSpeed)
    APP.state.precip_x10 = to_x10(now.precip)
    APP.state.text = tostring(now.text or "--")
    APP.state.code = tostring(now.icon or "")
    APP.state.obs_time = tostring(now.obsTime or "")
    APP.state.last_update_ms = millis and (millis() or 0) or 0

    log("parsed", APP.state.temp, APP.state.text, APP.state.humidity, APP.state.wind_speed)
    return true
    end

    local function parse_forecast_body(status_code, body)
    local state = APP.state.forecast
    state.last_http_code = status_code

    if status_code ~= 200 or not body then
        state.valid = false
        state.last_error = "HTTP " .. tostring(status_code)
        return false
    end

    if not json or not json.decode then
        state.valid = false
        state.last_error = "JSON missing"
        return false
    end

    local doc, err = json.decode(body)
    if not doc then
        state.valid = false
        state.last_error = "JSON " .. tostring(err)
        return false
    end

    local api_code = tostring(doc.code or "")
    if api_code ~= "200" then
        state.valid = false
        state.last_error = "API " .. api_code
        return false
    end

    local daily = doc.daily
    if type(daily) ~= "table" then
        state.valid = false
        state.last_error = "NO DAILY"
        return false
    end

    local days = {}
    for i = 1, 3 do
        local d = daily[i]
        if type(d) == "table" then
        days[#days + 1] = {
            date = tostring(d.fxDate or ""),
            icon = tostring(d.iconDay or d.iconNight or ""),
            text = tostring(d.textDay or d.textNight or "--"),
            temp_max = get_number(d.tempMax),
            temp_min = get_number(d.tempMin),
            precip_x10 = to_x10(d.precip),
            humidity = get_number(d.humidity),
            wind_speed = get_number(d.windSpeedDay or d.windSpeedNight),
        }
        end
    end

    if #days == 0 then
        state.valid = false
        state.last_error = "EMPTY DAILY"
        return false
    end

    state.valid = true
    state.days = days
    state.last_error = nil
    state.last_update_ms = millis and (millis() or 0) or 0
    return true
    end

    -- 将用户输入的城市名解析成 QWeather location id，避免 now/3d 直接查询城市名失败。
    local function parse_city_lookup_body(status_code, body, raw_location)
    if status_code ~= 200 or not body then
        return nil, "CITY HTTP " .. tostring(status_code)
    end

    local doc = decode_json(body)
    if type(doc) ~= "table" then
        return nil, "CITY JSON"
    end

    local api_code = tostring(doc.code or "")
    if api_code ~= "200" then
        return nil, "CITY API " .. api_code
    end

    local locations = doc.locations or doc.location
    if type(locations) ~= "table" then
        return nil, "CITY EMPTY"
    end

    local city = locations[1]
    if type(city) ~= "table" then
        return nil, "CITY EMPTY"
    end

    local id = trim(city.id)
    if id == "" then
        return nil, "CITY NO ID"
    end

    APP.state.resolved_location_raw = raw_location
    APP.state.resolved_location_id = id

    local name = trim(city.name)
    if name ~= "" then
        APP.CITY_NAME = name
        render_clock()
    end
    save_location_cache(raw_location, id, name ~= "" and name or APP.CITY_NAME)

    return id, nil
    end

    local function city_name_needs_lookup(raw_location)
    local city = trim(APP.CITY_NAME)
    return city == "" or city == "Weather" or city == trim(raw_location)
    end

    -- 城市名先解析成 location id；数字 id 在缺少显示名时也查一次城市名。
    local function resolve_weather_location(on_done)
    local raw_location = trim(APP.WEATHER_LOCATION)
    if raw_location == "" then
        on_done(nil, "Weather address missing")
        return
    end
    APP.WEATHER_LOCATION = raw_location

    local is_location_id = raw_location:match("^%d+$") ~= nil
    if is_location_id and not city_name_needs_lookup(raw_location) then
        on_done(raw_location, nil)
        return
    end

    if APP.state.resolved_location_raw == raw_location and trim(APP.state.resolved_location_id) ~= "" then
        on_done(APP.state.resolved_location_id, nil)
        return
    end

    if not http or not http.cubicserver or not http.cubicserver.get then
        on_done(nil, "Cubic HTTP missing")
        return
    end

    local waiters = APP.state.location_waiters
    if type(waiters) ~= "table" then
        waiters = {}
        APP.state.location_waiters = waiters
    end
    waiters[#waiters + 1] = on_done

    if APP.state.location_request_inflight then
        return
    end

    APP.state.location_request_inflight = true
    local url = APP.WEATHER_CITY_PATH
        .. "?location="
        .. url_encode(raw_location)
        .. "&number=1&lang="
        .. url_encode(APP.WEATHER_API_LANG)

    log("city request", url)

    http.cubicserver.get(url, "Accept-Encoding: gzip\r\n", function(status_code, body, headers)
        local callbacks = APP.state.location_waiters or {}
        APP.state.location_waiters = {}
        APP.state.location_request_inflight = false

        if not APP.running then
        return
        end

        local location_id, err
        local plain
        plain, err = maybe_gunzip_body(body)
        if plain then
        location_id, err = parse_city_lookup_body(status_code, plain, raw_location)
        end
        if not location_id and raw_location:match("^%d+$") then
        location_id = raw_location
        err = nil
        end
        if not err and not location_id then
        err = "CITY resolve failed"
        end

        for _, callback in ipairs(callbacks) do
        pcall_fn(callback, location_id, err)
        end
    end)
    end

    local function request_weather()
    if not APP.running then
        return
    end

    if APP.state.request_inflight then
        return
    end

    APP.state.request_inflight = true
    render_weather()

    resolve_weather_location(function(location, err)
        if not APP.running then
        return
        end

        if not location then
        APP.state.request_inflight = false
        APP.state.valid = false
        APP.state.last_error = tostring(err)
        render_weather()
        return
        end

        local url = APP.WEATHER_NOW_PATH
        .. "?location="
        .. url_encode(location)
        .. "&unit=m&lang="
        .. url_encode(APP.WEATHER_API_LANG)

        log("request", url)

        http.cubicserver.get(url, "Accept-Encoding: gzip\r\n", function(status_code, body, headers)
        APP.state.request_inflight = false

        if not APP.running then
        return
        end

        local plain, err = maybe_gunzip_body(body)
        if not plain then
        APP.state.valid = false
        APP.state.last_http_code = status_code
        APP.state.last_error = tostring(err)
        warn("body decode failed", tostring(err))
        render_weather()
        return
        end

        parse_weather_body(status_code, plain)
        render_weather()
        end)
    end)
    end

    request_forecast = function()
    if not APP.running then
        return
    end

    if APP.state.forecast.request_inflight then
        return
    end

    local state = APP.state.forecast
    state.request_inflight = true
    render_forecast()

    resolve_weather_location(function(location, err)
        if not APP.running then
        return
        end

        if not location then
        state.request_inflight = false
        state.valid = false
        state.days = {}
        state.last_error = tostring(err)
        render_forecast()
        return
        end

        local url = APP.WEATHER_3D_PATH
        .. "?location="
        .. url_encode(location)
        .. "&unit=m&lang="
        .. url_encode(APP.WEATHER_API_LANG)

        log("forecast request", url)

        http.cubicserver.get(url, "Accept-Encoding: gzip\r\n", function(status_code, body, headers)
        state.request_inflight = false

        if not APP.running then
        return
        end

        local plain, err = maybe_gunzip_body(body)
        if not plain then
        state.valid = false
        state.last_http_code = status_code
        state.last_error = tostring(err)
        warn("forecast body decode failed", tostring(err))
        render_forecast()
        return
        end

        parse_forecast_body(status_code, plain)
        render_forecast()
        end)
    end)
    end

    local function stop_timers()
    for _, timer in pairs(APP.timers) do
        pcall_fn(function() timer:stop() end)
        pcall_fn(function() timer:unregister() end)
    end
    APP.timers = {}
    end

    local runtime_app = rawget(_G, "app")
    local app_exiting_fn = runtime_app and runtime_app.exiting or nil

    local function maybe_stop_for_exit()
    if app_exiting_fn then
        local ok, exiting = pcall_fn(app_exiting_fn)
        if ok and exiting then
        APP.stop("exit")
        return true
        end
    end
    return false
    end

    local function is_long_start(evt_type)
    return evt_type == key.LONG_START
    end

    local function bind_input()
    local left_code = key.LEFT
    local right_code = key.RIGHT

    APP.input.left_code = left_code
    APP.input.right_code = right_code
    APP.input.mode = "key"

    key.on(left_code, function(evt_type, _)
        if APP.running and is_long_start(evt_type) then
            toggle_forecast_page()
        end
    end)
    key.on(right_code, function(evt_type, _)
        if APP.running and is_long_start(evt_type) then
            toggle_forecast_page()
        end
    end)
    end

    local function unbind_input()
    if APP.input.mode == "key" then
        if APP.input.left_code then
        pcall_fn(function() key.off(APP.input.left_code) end)
        end
        if APP.input.right_code then
        pcall_fn(function() key.off(APP.input.right_code) end)
        end
    end

    APP.input.mode = "none"
    end

    local function start_timers()
    if not tmr or not tmr.create then
        hide_startup_page()
        return
    end

    local controller_buttons = 0
    local controller_horizontal = 0
    local controller_hold_ms = 0
    local controller_long_fired = false
    APP.timers.controller = tmr.create()
    APP.timers.controller:alarm(40, tmr.ALARM_AUTO, function()
        if not controller or not controller.state then return end
        local ok, pad = pcall(function() return controller.state("ble-main") end)
        local buttons = ok and type(pad) == "table" and (tonumber(pad.buttons) or 0) or 0
        local pressed = buttons & (~controller_buttons)
        controller_buttons = buttons
        if (pressed & (4096 | 32768)) ~= 0 then
            APP.stop("controller-exit")
            if app and app.exit then pcall(function() app.exit() end) end
            return
        end
        local horizontal = buttons & (4 | 8)
        local stamp = now_ms()
        if horizontal == 0 then
            controller_horizontal = 0
            controller_long_fired = false
        elseif horizontal ~= controller_horizontal then
            controller_horizontal = horizontal
            controller_hold_ms = stamp
            controller_long_fired = false
        elseif not controller_long_fired and stamp - controller_hold_ms >= 600 then
            controller_long_fired = true
            toggle_forecast_page()
        end
    end)

    APP.timers.startup = tmr.create()
    APP.timers.startup:alarm(STARTUP_HOLD_MS, tmr.ALARM_SINGLE or 0, function()
        hide_startup_page()
        APP.timers.startup = nil
    end)

    APP.timers.clock = tmr.create()
    APP.timers.clock:alarm(1000, tmr.ALARM_AUTO, function()
        if not APP.running or maybe_stop_for_exit() then return end
        render_clock()
    end)

    APP.timers.fetch = tmr.create()
    APP.timers.fetch:alarm(APP.WEATHER_FETCH_MS, tmr.ALARM_AUTO, function()
        if not APP.running or maybe_stop_for_exit() then return end
        request_weather()
    end)

    APP.timers.forecast = tmr.create()
    APP.timers.forecast:alarm(APP.FORECAST_FETCH_MS, tmr.ALARM_AUTO, function()
        if not APP.running or maybe_stop_for_exit() then return end
        request_forecast()
    end)
    end

    function APP.stop(reason)
    if not APP.running then
        return
    end
    local stop_reason = tostring(reason or "")

    APP.running = false
    APP.state.request_inflight = false
    APP.state.forecast.request_inflight = false
    unbind_input()
    stop_timers()
    if stop_reason ~= "reload" then
        release_startup_page()
    end
    release_glass_snapshot()
    release_forecast_glass_snapshot()
    log("stop", stop_reason)

    if rawget(_G, "WEATHER_APP") == APP then
        _G.WEATHER_APP = nil
    end

    if lv_clear and stop_reason ~= "reload" then
        pcall_fn(function() lv_clear() end)
    end
    release_fonts()
    end

    if not lv_scr_act or not lv_clear or not lv_obj_create or not lv_label_create or not lv_img_create then
    warn("ui api missing")
    return
    end

    load_runtime_settings()
    init_time_module()
    -- 先启动异步网络请求，让 DNS/HTTP 与启动页和大字体加载并行。
    request_weather()
    request_forecast()
    init_ui()
    render_clock()
    render_weather()
    render_forecast()
    bind_input()
    start_timers()
