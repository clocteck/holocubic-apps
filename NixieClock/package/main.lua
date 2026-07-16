local previous = rawget(_G, "HOLO_TIME_APP")
if previous and previous.stop then
  pcall(function() previous.stop("reload") end)
end

HOLO_TIME_APP = {
  VERSION = "2026-07-16-holo-nixie-v6",
  SCREEN_W = 320,
  SCREEN_H = 240,
  APP_DIR = "/sd/apps/NixieClock",
  SETTINGS_PATH = "/sd/apps/settings.json",
  CONFIG_PATH = "/sd/apps/NixieClock/config.json",
  DEFAULT_TIMEZONE = "CST-8",
  NTP_SERVER = "ntp.aliyun.com",
  WEATHER_NOW_PATH = "/v1/weather/now",
  WEATHER_3D_PATH = "/v1/weather/3d",
  WEATHER_CITY_PATH = "/v1/weather/cities",
  WEATHER_FETCH_MS = 30 * 60 * 1000,
  MEMO_FETCH_MS = 30 * 1000,
  MEMO_PATHS = {
    "/sd/apps/time-calendar-weather-memo/memos.json",
  },
  FACE_COUNT = 8,
  TICK_MS = 250,
  KEY_DEBOUNCE_MS = 400,
}

local APP = HOLO_TIME_APP
local floor = math.floor
local abs = math.abs
local sin = math.sin
local cos = math.cos
local sqrt = math.sqrt
local rad = math.rad
local pi = math.pi
local format = string.format
local pcall_fn = pcall

local PART_MAIN = rawget(_G, "LV_PART_MAIN") or 0
local ALIGN_LEFT = rawget(_G, "LV_TEXT_ALIGN_LEFT") or 0
local ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1
local ALIGN_RIGHT = rawget(_G, "LV_TEXT_ALIGN_RIGHT") or 2
local CANVAS_FMT = rawget(_G, "LV_IMG_CF_TRUE_COLOR") or rawget(_G, "CANVAS_FMT_TRUE_COLOR")

local canvas_create = rawget(_G, "lv_canvas_create")
local canvas_begin = rawget(_G, "lv_canvas_frame_begin") or rawget(_G, "lv_canvas_begin")
local canvas_end = rawget(_G, "lv_canvas_frame_end") or rawget(_G, "lv_canvas_end")
local canvas_fill = rawget(_G, "lv_canvas_fill_bg") or rawget(_G, "lv_canvas_fill")
local canvas_rect = rawget(_G, "lv_canvas_draw_rect")
local canvas_line = rawget(_G, "lv_canvas_draw_line")
local canvas_arc = rawget(_G, "lv_canvas_draw_arc")
local canvas_text = rawget(_G, "lv_canvas_draw_text")
local canvas_img = rawget(_G, "lv_canvas_draw_img")
local canvas_transform = rawget(_G, "lv_canvas_transform")
local obj_pos = rawget(_G, "lv_obj_set_pos")
local obj_invalidate = rawget(_G, "lv_obj_invalidate")
local img_create = rawget(_G, "lv_img_create")
local img_set_src = rawget(_G, "lv_img_set_src")
local img_set_angle = rawget(_G, "lv_img_set_angle")
local img_set_pivot = rawget(_G, "lv_img_set_pivot")
local img_set_antialias = rawget(_G, "lv_img_set_antialias")
local obj_add_flag = rawget(_G, "lv_obj_add_flag")
local obj_clear_flag = rawget(_G, "lv_obj_clear_flag")
local FLAG_HIDDEN = rawget(_G, "LV_OBJ_FLAG_HIDDEN") or 1

if not lv_scr_act or not lv_obj_clean or not canvas_create or not canvas_fill then
  if print then print("[HoloTime] required LVGL canvas API missing") end
  return
end

local C = {
  black = 0x000000,
  ink = 0x05070A,
  surface = 0x11151B,
  border = 0x2B3139,
  white = 0xF7F9FC,
  soft = 0xB5BDC7,
  muted = 0x727C88,
  cyan = 0x35E7FF,
  cyan_dim = 0x176E7C,
  lime = 0xB9FF3D,
  orange = 0xFFC247,
  red = 0xFF4164,
  violet = 0xAD94FF,
}

APP.running = true
APP.canvas = nil
APP.timers = {}
APP.font_handles = {}
APP.font = {}
APP.hand_sources = {}
APP.hands_ready = false
APP.input = { imu = false, keys = false }
APP.state = {
  face = 1,
  pending_dir = 0,
  last_key_ms = -1000,
  last_switch_ms = -1000,
  last_auto_switch_ms = 0,
  default_face = 1,
  auto_switch_ms = 0,
  hud_until_ms = 0,
  hud_was_visible = false,
  last_second = -1,
  last_minute = -1,
  last_render_face = 0,
  timezone = APP.DEFAULT_TIMEZONE,
  city = "SHANGHAI",
  weather_address = "",
  location_label = "SHANGHAI",
  weather_location_id = "",
  weather_valid = false,
  temp = nil,
  weather_text = "--",
  humidity = nil,
  wind_speed = nil,
  weather_code = "103",
  weather_inflight = false,
  forecast_valid = false,
  forecast_inflight = false,
  forecast_days = {},
  memos = { "请先安装 Assistant app", "", "" },
  memo_available = false,
  memo_source = "",
  imu_base_roll = nil,
  imu_base_pitch = nil,
  imu_armed = true,
}

local FACE_NAMES = {
  "MERIDIAN", "PULSE WX", "NEON GIRL", "SOLAR WEATHER",
  "TERMINAL", "LUNAR", "FOCUS MEMO", "NIXIE"
}

local WEEKDAYS = { "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" }
local MONTHS = { "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" }

local function warn(...)
  if print then print("[HoloTime]", ...) end
end

local function now_ms()
  if millis then
    local ok, value = pcall_fn(millis)
    if ok and type(value) == "number" then return value end
  end
  if tmr and tmr.now then
    local ok, value = pcall_fn(tmr.now)
    if ok and type(value) == "number" then return floor(value / 1000) end
  end
  return 0
end

local function read_text(path)
  if file and file.getcontents then
    local ok, value = pcall_fn(file.getcontents, path)
    if ok and type(value) == "string" then return value end
  end
  return nil
end

local function decode_json(raw)
  if type(raw) ~= "string" or raw == "" then return nil end
  local codec = rawget(_G, "json") or rawget(_G, "sjson")
  if codec and codec.decode then
    local ok, value = pcall_fn(codec.decode, raw)
    if ok and type(value) == "table" then return value end
  end
  return nil
end

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function utf8_truncate(value, max_chars)
  local source = tostring(value or "")
  local index, count, last = 1, 0, 0
  while index <= #source and count < max_chars do
    local byte = source:byte(index)
    local length = byte < 0x80 and 1 or (byte < 0xE0 and 2 or (byte < 0xF0 and 3 or 4))
    if index + length - 1 > #source then break end
    last = index + length - 1
    index = index + length
    count = count + 1
  end
  return source:sub(1, last)
end

local function sanitize_memo(value)
  local memo = trim(tostring(value or ""):gsub("[%c]+", " "):gsub("%s+", " "))
  if memo == "" then return "暂无内容" end
  return utf8_truncate(memo, 14)
end

local function load_memos()
  for _, path in ipairs(APP.MEMO_PATHS) do
    local doc = decode_json(read_text(path))
    if type(doc) == "table" and type(doc.memos) == "table" then
      local changed = not APP.state.memo_available or APP.state.memo_source ~= path
      for i = 1, 3 do
        local next_value = sanitize_memo(doc.memos[i])
        if APP.state.memos[i] ~= next_value then changed = true end
        APP.state.memos[i] = next_value
      end
      APP.state.memo_available = true
      APP.state.memo_source = path
      return changed
    end
  end
  local changed = APP.state.memo_available or APP.state.memo_source ~= "" or APP.state.memos[1] ~= "请先安装 Assistant app"
  APP.state.memo_available = false
  APP.state.memo_source = ""
  APP.state.memos = { "请先安装 Assistant app", "", "" }
  return changed
end

local function write_text(path, value)
  if file and file.putcontents then
    local ok, result = pcall_fn(file.putcontents, path, value)
    return ok and result ~= false
  end
  return false
end

local function safe_city_label(value)
  value = trim(value)
  if value == "" then return "LOCAL" end
  if value:find("[\128-\255]") then return value end
  return value:upper()
end

local function ascii_city_label(value)
  value = trim(value)
  if value == "" then return "LOCAL" end
  if not value:find("[\128-\255]") then return value:upper():gsub("[^A-Z0-9 ._-]", "") end
  local pinyin = {
    ["北"]="BEI",["京"]="JING",["上"]="SHANG",["海"]="HAI",["天"]="TIAN",["津"]="JIN",["重"]="CHONG",["庆"]="QING",
    ["河"]="HE",["南"]="NAN",["湖"]="HU",["广"]="GUANG",["东"]="DONG",["西"]="XI",["山"]="SHAN",["陕"]="SHAAN",
    ["辽"]="LIAO",["宁"]="NING",["吉"]="JI",["林"]="LIN",["黑"]="HEI",["龙"]="LONG",["江"]="JIANG",["苏"]="SU",
    ["浙"]="ZHE",["安"]="AN",["徽"]="HUI",["福"]="FU",["建"]="JIAN",["青"]="QING",["甘"]="GAN",["肃"]="SU",
    ["云"]="YUN",["贵"]="GUI",["州"]="ZHOU",["四"]="SI",["川"]="CHUAN",["台"]="TAI",["湾"]="WAN",["内"]="NEI",
    ["蒙"]="MENG",["古"]="GU",["新"]="XIN",["疆"]="JIANG",["藏"]="ZANG",["桂"]="GUI",["琼"]="QIONG",["香"]="XIANG",
    ["港"]="GANG",["澳"]="AO",["门"]="MEN",["浦"]="PU",["徐"]="XU",["黄"]="HUANG",["静"]="JING",["长"]="CHANG",
    ["普"]="PU",["虹"]="HONG",["杨"]="YANG",["闵"]="MIN",["宝"]="BAO",["嘉"]="JIA",["金"]="JIN",["松"]="SONG",
    ["奉"]="FENG",["崇"]="CHONG",["明"]="MING",["深"]="SHEN",["圳"]="ZHEN",["杭"]="HANG",["武"]="WU",["汉"]="HAN",
    ["成"]="CHENG",["都"]="DU",["昆"]="KUN",["厦"]="XIA",["佛"]="FO",["莞"]="GUAN",["珠"]="ZHU",["郑"]="ZHENG",
    ["济"]="JI",["岛"]="DAO",["大"]="DA",["连"]="LIAN",["沈"]="SHEN",["阳"]="YANG",["哈"]="HA",["尔"]="ER",
    ["滨"]="BIN",["波"]="BO",["石"]="SHI",["家"]="JIA",["庄"]="ZHUANG",["太"]="TAI",["原"]="YUAN",["呼"]="HU",["和"]="HE",
    ["浩"]="HAO",["特"]="TE",["乌"]="WU",["鲁"]="LU",["木"]="MU",["齐"]="QI",["拉"]="LA",["萨"]="SA",
    ["银"]="YIN",["兰"]="LAN",["昌"]="CHANG",["沙"]="SHA",["合"]="HE",["肥"]="FEI",["口"]="KOU",["三"]="SAN",
    ["亚"]="YA",["路"]="LU",["街"]="JIE",["道"]="DAO",["号"]="HAO",["园"]="YUAN",["城"]="CHENG",["中"]="ZHONG",
    ["华"]="HUA",["朝"]="CHAO",["白"]="BAI",["丰"]="FENG",["通"]="TONG",["顺"]="SHUN",["义"]="YI",["房"]="FANG",
    ["兴"]="XING",["平"]="PING",["谷"]="GU",["密"]="MI",["延"]="YAN",["省"]="",["市"]="",["区"]="",["县"]="",
    ["无"]="WU",["锡"]="XI",["常"]="CHANG",["温"]="WEN",["绍"]="SHAO",["衢"]="QU",["丽"]="LI",["舟"]="ZHOU",
    ["扬"]="YANG",["盐"]="YAN",["泰"]="TAI",["宿"]="SU",["迁"]="QIAN",["淮"]="HUAI",["德"]="DE",["莆"]="PU",
    ["泉"]="QUAN",["漳"]="ZHANG",["岩"]="YAN",["九"]="JIU",["赣"]="GAN",["饶"]="RAO",["景"]="JING",["萍"]="PING",
    ["宜"]="YI",["春"]="CHUN",["鹰"]="YING",["潭"]="TAN",["烟"]="YAN",["潍"]="WEI",["坊"]="FANG",["淄"]="ZI",
    ["博"]="BO",["枣"]="ZAO",["营"]="YING",["威"]="WEI",["日"]="RI",["照"]="ZHAO",["临"]="LIN",["沂"]="YI",
    ["聊"]="LIAO",["菏"]="HE",["泽"]="ZE",["洛"]="LUO",["开"]="KAI",["封"]="FENG",["许"]="XU",["焦"]="JIAO",
    ["作"]="ZUO",["鹤"]="HE",["壁"]="BI",["濮"]="PU",["漯"]="LUO",["峡"]="XIA",["商"]="SHANG",["丘"]="QIU",
    ["周"]="ZHOU",["驻"]="ZHU",["马"]="MA",["店"]="DIAN",["信"]="XIN",["襄"]="XIANG",["荆"]="JING",["孝"]="XIAO",
    ["感"]="GAN",["冈"]="GANG",["咸"]="XIAN",["随"]="SUI",["恩"]="EN",["施"]="SHI",["株"]="ZHU",["洲"]="ZHOU",
    ["湘"]="XIANG",["衡"]="HENG",["邵"]="SHAO",["岳"]="YUE",["张"]="ZHANG",["界"]="JIE",["益"]="YI",["郴"]="CHEN",
    ["永"]="YONG",["怀"]="HUAI",["化"]="HUA",["娄"]="LOU",["底"]="DI",["韶"]="SHAO",["关"]="GUAN",["湛"]="ZHAN",
    ["茂"]="MAO",["名"]="MING",["肇"]="ZHAO",["惠"]="HUI",["梅"]="MEI",["汕"]="SHAN",["尾"]="WEI",["源"]="YUAN",
    ["清"]="QING",["远"]="YUAN",["潮"]="CHAO",["揭"]="JIE",["浮"]="FU",["村"]="CUN",["弄"]="NONG",["巷"]="XIANG",
    ["苑"]="YUAN",["公"]="GONG",["馆"]="GUAN",["站"]="ZHAN",["桥"]="QIAO",["鄞"]="YIN",["慈"]="CI",["溪"]="XI",
    ["余"]="YU",["姚"]="YAO",["曙"]="SHU",["仑"]="LUN",["镇"]="",["乡"]=""
  }
  local parts = {}
  for ch in value:gmatch("[\0-\127\194-\244][\128-\191]*") do
    local converted = pinyin[ch]
    if converted ~= nil then parts[#parts + 1] = converted
    elseif ch:match("[%w]") then parts[#parts + 1] = ch:upper() end
  end
  local result = table.concat(parts)
  return result ~= "" and result or "LOCAL"
end

local function load_settings()
  local doc = decode_json(read_text(APP.SETTINGS_PATH)) or {}
  local state = APP.state
  state.timezone = trim(doc.timezone)
  if state.timezone == "" then state.timezone = APP.DEFAULT_TIMEZONE end
  state.weather_address = trim(doc.weather_address or doc.weatherAddress)
  state.weather_location_id = trim(doc.weather_location_id)
  local city = state.weather_address ~= "" and state.weather_address or trim(doc.weather_city or doc.city_name or doc.city)
  if city ~= "" then
    state.city = safe_city_label(city)
    state.location_label = ascii_city_label(city)
  end
end

local function load_app_config()
  local doc = decode_json(read_text(APP.CONFIG_PATH)) or {}
  local face = floor(tonumber(doc.default_face) or 1)
  if face < 1 or face > APP.FACE_COUNT then face = 1 end
  local interval = tonumber(doc.auto_switch_ms) or 0
  if interval ~= 600000 and interval ~= 3600000 then interval = 0 end
  APP.state.default_face = face
  APP.state.auto_switch_ms = interval
  APP.state.face = face
end

local function save_app_config()
  local codec = rawget(_G, "json") or rawget(_G, "sjson")
  if not (codec and codec.encode) then return false end
  local ok, raw = pcall_fn(codec.encode, { default_face = APP.state.default_face, auto_switch_ms = APP.state.auto_switch_ms })
  return ok and type(raw) == "string" and write_text(APP.CONFIG_PATH, raw)
end

local function init_time()
  local time_mod = rawget(_G, "time")
  if not time_mod then return end
  if time_mod.settimezone then pcall_fn(time_mod.settimezone, APP.state.timezone) end
  if time_mod.initntp then pcall_fn(time_mod.initntp, APP.NTP_SERVER) end
end

local function local_time()
  local time_mod = rawget(_G, "time")
  if time_mod and time_mod.getlocal then
    local ok, value = pcall_fn(time_mod.getlocal)
    if ok and type(value) == "table" and tonumber(value.year) and tonumber(value.year) >= 2024 then
      return {
        year = tonumber(value.year) or 2026,
        mon = tonumber(value.mon) or 1,
        day = tonumber(value.day) or 1,
        hour = tonumber(value.hour) or 0,
        min = tonumber(value.min) or 0,
        sec = tonumber(value.sec) or 0,
        wday = tonumber(value.wday),
      }
    end
  end
  if os and os.date then
    local ok, value = pcall_fn(os.date, "*t")
    if ok and type(value) == "table" then return value end
  end
  return { year = 2026, mon = 7, day = 14, hour = 9, min = 41, sec = 0, wday = 3 }
end

local function weekday_of(t)
  local wday = tonumber(t.wday)
  if wday and WEEKDAYS[wday] then return WEEKDAYS[wday] end
  local y, m, d = t.year, t.mon, t.day
  if m < 3 then y = y - 1; m = m + 12 end
  local k = y % 100
  local j = floor(y / 100)
  local h = (d + floor(13 * (m + 1) / 5) + k + floor(k / 4) + floor(j / 4) + 5 * j) % 7
  local map = { 7, 1, 2, 3, 4, 5, 6 }
  return WEEKDAYS[map[h + 1]] or "TUE"
end

local function font_load(path, fallback)
  if lv_font_load then
    local ok, handle = pcall_fn(lv_font_load, path)
    if ok and type(handle) == "number" and handle > 0 then
      APP.font_handles[#APP.font_handles + 1] = handle
      return handle
    end
  end
  return fallback
end

local function init_fonts()
  APP.font.cn8 = font_load(APP.APP_DIR .. "/font/time_ui_8.bin", rawget(_G, "LV_FONT_MONTSERRAT_8") or 8)
  APP.font.cn10 = font_load(APP.APP_DIR .. "/font/time_ui_10.bin", APP.font.cn8)
  APP.font.cn11 = font_load(APP.APP_DIR .. "/font/time_ui_11.bin", APP.font.cn10)
  APP.font.cn12 = font_load(APP.APP_DIR .. "/font/time_ui_12.bin", rawget(_G, "LV_FONT_MONTSERRAT_12") or 12)
  APP.font.memo13 = font_load(APP.APP_DIR .. "/font/time_memo_13.bin", APP.font.cn12)
  APP.font.cn14 = font_load(APP.APP_DIR .. "/font/time_ui_14.bin", APP.font.cn12)
  APP.font.en8 = font_load(APP.APP_DIR .. "/font/time_en_8.bin", APP.font.cn8)
  APP.font.en9 = font_load(APP.APP_DIR .. "/font/time_en_9.bin", APP.font.en8)
  APP.font.en10 = font_load(APP.APP_DIR .. "/font/time_en_10.bin", APP.font.cn12)
  APP.font.en11 = font_load(APP.APP_DIR .. "/font/time_en_11.bin", APP.font.en10)
  APP.font.en12 = font_load(APP.APP_DIR .. "/font/time_en_12.bin", APP.font.en10)
  APP.font.en13 = font_load(APP.APP_DIR .. "/font/time_en_13.bin", APP.font.en12)
  APP.font.en14 = font_load(APP.APP_DIR .. "/font/time_en_14.bin", APP.font.en12)
  APP.font.en15 = font_load(APP.APP_DIR .. "/font/time_en_15.bin", APP.font.en14)
  APP.font.en16 = font_load(APP.APP_DIR .. "/font/time_en_16.bin", rawget(_G, "LV_FONT_MONTSERRAT_16") or 16)
  APP.font.en20 = font_load(APP.APP_DIR .. "/font/time_en_20.bin", APP.font.en16)
  APP.font.mono11 = font_load(APP.APP_DIR .. "/font/time_mono_11.bin", APP.font.en10)
  APP.font.mono12 = font_load(APP.APP_DIR .. "/font/time_mono_12.bin", APP.font.en12)
  APP.font.mono24 = font_load(APP.APP_DIR .. "/font/time_mono_24.bin", APP.font.mono12)
  APP.font.mono56 = font_load(APP.APP_DIR .. "/font/time_mono_56.bin", rawget(_G, "LV_FONT_MONTSERRAT_28") or 28)
  APP.font.ui12 = APP.font.en10
  APP.font.ui14 = APP.font.en14
  APP.font.ui16 = APP.font.en16
  APP.font.n28 = font_load(APP.APP_DIR .. "/font/time_num_28.bin", rawget(_G, "LV_FONT_MONTSERRAT_28") or 28)
  APP.font.n34 = font_load(APP.APP_DIR .. "/font/time_num_34.bin", APP.font.n28)
  APP.font.n40 = font_load(APP.APP_DIR .. "/font/time_num_40.bin", APP.font.n28)
  APP.font.n42 = font_load(APP.APP_DIR .. "/font/time_num_42.bin", APP.font.n40)
  APP.font.n52 = font_load(APP.APP_DIR .. "/font/time_num_52.bin", APP.font.n42)
  APP.font.n69 = font_load(APP.APP_DIR .. "/font/time_num_69.bin", APP.font.n40)
  APP.font.n72 = font_load(APP.APP_DIR .. "/font/time_num_72.bin", APP.font.n40)
end

local rect_dsc = { bg_color = C.black, bg_opa = 255, radius = 0, border_width = 0, border_color = C.black, border_opa = 255 }
local line_dsc = { color = C.white, opa = 255, width = 1 }
local text_dsc = { color = C.white, opa = 255, align = ALIGN_LEFT, font_size = 12, font_handle = nil }

local function has_cjk(value)
  local s = tostring(value or "")
  for i = 1, #s do
    local b = s:byte(i)
    if b and b >= 0xE4 and b <= 0xE9 then return true end
  end
  return false
end

local function frame_begin()
  if canvas_begin and APP.canvas then pcall_fn(canvas_begin, APP.canvas) end
end

local function frame_end()
  if canvas_end and APP.canvas then
    pcall_fn(canvas_end, APP.canvas)
  elseif obj_invalidate and APP.canvas then
    pcall_fn(obj_invalidate, APP.canvas)
  end
end

local function fill(color)
  pcall_fn(canvas_fill, APP.canvas, color, 255)
end

local function rect(x, y, w, h, color, opa, radius, border_color, border_width)
  if not canvas_rect or w <= 0 or h <= 0 then return end
  rect_dsc.bg_color = color or C.black
  rect_dsc.bg_opa = opa or 255
  rect_dsc.radius = radius or 0
  rect_dsc.border_width = border_width or 0
  rect_dsc.border_color = border_color or color or C.black
  rect_dsc.border_opa = 255
  pcall_fn(canvas_rect, APP.canvas, floor(x), floor(y), floor(w), floor(h), rect_dsc)
end

local function line(x1, y1, x2, y2, color, opa, width)
  if not canvas_line then return end
  line_dsc.color = color or C.white
  line_dsc.opa = opa or 255
  line_dsc.width = width or 1
  pcall_fn(canvas_line, APP.canvas, floor(x1), floor(y1), floor(x2), floor(y2), line_dsc.color, line_dsc.opa, line_dsc.width)
end

local function arc(cx, cy, radius, start_deg, end_deg, color, opa, width)
  if not canvas_arc then return end
  line_dsc.color = color or C.white
  line_dsc.opa = opa or 255
  line_dsc.width = width or 1
  pcall_fn(canvas_arc, APP.canvas, floor(cx), floor(cy), floor(radius), start_deg, end_deg, line_dsc)
end

local function text(x, y, w, value, font, color, align, opa, letter_space)
  if not canvas_text then return end
  local chosen_font = font or APP.font.ui12
  if has_cjk(value) then
    if chosen_font == APP.font.ui12 then chosen_font = APP.font.cn12 end
    if chosen_font == APP.font.ui14 then chosen_font = APP.font.cn14 end
    if chosen_font == APP.font.ui16 then chosen_font = APP.font.cn16 end
  end
  text_dsc.color = color or C.white
  text_dsc.opa = opa or 255
  text_dsc.align = align or ALIGN_LEFT
  text_dsc.font_handle = chosen_font
  text_dsc.letter_space = letter_space or 0
  pcall_fn(canvas_text, APP.canvas, floor(x), floor(y), floor(w), tostring(value or ""), text_dsc)
end

local function circle(cx, cy, radius, color, opa, width)
  arc(cx, cy, radius, 0, 360, color, opa, width)
end

local function disc(cx, cy, radius, color, opa)
  rect(cx - radius, cy - radius, radius * 2, radius * 2, color, opa, radius)
end

local function polar(cx, cy, radius, degrees)
  local a = rad(degrees - 90)
  return cx + cos(a) * radius, cy + sin(a) * radius
end

local function draw_sun(cx, cy, radius, color)
  circle(cx, cy, radius, color, 255, 2)
  for i = 0, 7 do
    local a = i * 45
    local x1, y1 = polar(cx, cy, radius + 3, a)
    local x2, y2 = polar(cx, cy, radius + 7, a)
    line(x1, y1, x2, y2, color, 220, 1)
  end
end

local function weather_kind(code, label)
  code = tostring(code or "")
  label = tostring(label or "")
  if code:match("^4") or label:find("雪") then return "snow" end
  if code:match("^3") or label:find("雨") then return "rain" end
  if code:match("^2") or label:find("雷") then return "storm" end
  if code == "100" or code == "150" or label == "晴" then return "sun" end
  return "cloud"
end

local function draw_ui_asset(x, y, name)
  if not canvas_img then return false end
  return pcall_fn(canvas_img, APP.canvas, floor(x), floor(y), "S:/apps/NixieClock/assets/ui/" .. name .. ".png", { opa = 255 })
end

local function draw_cloud(cx, cy, scale, color)
  disc(cx - scale * 0.34, cy, scale * 0.28, color, 255)
  disc(cx, cy - scale * 0.18, scale * 0.38, color, 255)
  disc(cx + scale * 0.36, cy, scale * 0.27, color, 255)
  rect(cx - scale * 0.62, cy, scale * 1.25, scale * 0.42, color, 255, scale * 0.20)
end

local function draw_weather_icon(cx, cy, scale, code, label)
  local kind = weather_kind(code, label)
  if kind == "sun" then
    draw_sun(cx, cy, scale * 0.38, C.orange)
    disc(cx, cy, scale * 0.27, C.orange, 255)
    return
  end
  if kind == "storm" then
    draw_cloud(cx, cy - 3, scale, C.soft)
    line(cx + 2, cy + scale * 0.30, cx - 4, cy + scale * 0.72, C.orange, 255, 3)
    line(cx - 4, cy + scale * 0.72, cx + 5, cy + scale * 0.62, C.orange, 255, 3)
    return
  end
  if kind == "cloud" then
    draw_sun(cx - scale * 0.35, cy - scale * 0.32, scale * 0.28, C.orange)
    draw_cloud(cx + scale * 0.08, cy, scale, C.soft)
    return
  end
  draw_cloud(cx, cy - 4, scale, C.soft)
  for i = -1, 1 do
    local x = cx + i * scale * 0.34
    if kind == "snow" then
      line(x - 3, cy + scale * 0.42, x + 3, cy + scale * 0.60, C.cyan, 255, 1)
      line(x + 3, cy + scale * 0.42, x - 3, cy + scale * 0.60, C.cyan, 255, 1)
    else
      line(x + 3, cy + scale * 0.35, x - 2, cy + scale * 0.65, C.cyan, 255, 2)
    end
  end
end

local function draw_droplet(cx, cy, scale, color)
  local top_y = cy - scale * 0.60
  line(cx, top_y, cx - scale * 0.42, cy + scale * 0.08, color, 255, 2)
  arc(cx, cy + scale * 0.08, scale * 0.42, 0, 180, color, 255, 2)
  line(cx + scale * 0.42, cy + scale * 0.08, cx, top_y, color, 255, 2)
end

local function draw_wind(cx, cy, scale, color)
  line(cx - scale, cy - 5, cx + scale * 0.62, cy - 5, color, 255, 2)
  arc(cx + scale * 0.62, cy - 1, 4, 260, 80, color, 255, 2)
  line(cx - scale * 0.70, cy + 5, cx + scale, cy + 5, color, 215, 2)
  line(cx - scale, cy + 13, cx + scale * 0.35, cy + 13, color, 165, 1)
end

local function moon_phase(t)
  local y, m = t.year, t.mon
  if m < 3 then y = y - 1; m = m + 12 end
  local a = floor(y / 100)
  local b = 2 - a + floor(a / 4)
  local jd = floor(365.25 * (y + 4716)) + floor(30.6001 * (m + 1)) + t.day + b - 1524.5
  jd = jd + ((t.hour or 0) + (t.min or 0) / 60) / 24
  return ((jd - 2451550.1) / 29.530588853) % 1
end

local function draw_moon_phase(cx, cy, radius, phase)
  disc(cx, cy, radius, 0x11131D, 255)
  for dy = -radius + 2, radius - 2, 2 do
    local half = sqrt(radius * radius - dy * dy)
    local left, right
    if phase <= 0.5 then
      left, right = half * cos(phase * 2 * pi), half
    else
      left, right = -half, -half * cos(phase * 2 * pi)
    end
    if right > left then line(cx + left, cy + dy, cx + right, cy + dy, 0xF0F1F6, 255, 2) end
  end
  circle(cx, cy, radius, 0x73758A, 230, 1)
end

local function temp_text()
  if APP.state.weather_valid and APP.state.temp ~= nil then
    return tostring(floor(tonumber(APP.state.temp) + 0.5)) .. "°"
  end
  return "--°"
end

local function date_parts(t)
  return weekday_of(t), MONTHS[t.mon] or "---", format("%02d", t.day)
end

local function draw_ticks(cx, cy, radius, count, color, major_every)
  for i = 0, count - 1 do
    local major = (i % major_every) == 0
    local r1 = radius - (major and 10 or 5)
    local x1, y1 = polar(cx, cy, r1, i * 360 / count)
    local x2, y2 = polar(cx, cy, radius, i * 360 / count)
    line(x1, y1, x2, y2, color, major and 235 or 155, major and 2 or 1)
  end
end

local function draw_hands(cx, cy, radius, t, hour_color, minute_color, second_color)
  local hour_angle = (t.hour % 12) * 30 + t.min * 0.5
  local minute_angle = t.min * 6 + t.sec * 0.1
  local second_angle = t.sec * 6
  local hx, hy = polar(cx, cy, radius * 0.48, hour_angle)
  local mx, my = polar(cx, cy, radius * 0.70, minute_angle)
  local sx, sy = polar(cx, cy, radius * 0.82, second_angle)
  local tx, ty = polar(cx, cy, radius * 0.15, second_angle + 180)
  line(cx, cy, hx, hy, hour_color or C.white, 255, 7)
  line(cx, cy, mx, my, minute_color or C.white, 255, 4)
  line(tx, ty, sx, sy, second_color or C.red, 255, 2)
  disc(cx, cy, 5, C.ink, 255)
  circle(cx, cy, 5, second_color or C.red, 255, 2)
end

local function draw_meridian(t)
  fill(C.black)
  local day, month, date = date_parts(t)
  -- Device fonts sit above browser glyphs; use matched visual baselines.
  text(17, 34, 90, day .. " · " .. month .. " " .. date, APP.font.en12, 0xBFC7D0)
  text(17, 67, 82, temp_text(), APP.font.n28, C.white)
  text(17, 107, 88, APP.state.city, APP.font.ui14, 0x8D99A6)
  if not draw_ui_asset(18, 175, "mini-" .. weather_kind(APP.state.weather_code, APP.state.weather_text)) then
    draw_sun(28, 185, 8, C.orange)
  end
  text(43, 178, 52, APP.state.weather_valid and APP.state.weather_text or "天气", APP.font.ui12, C.orange)
  -- Match the 210 px HTML dial and allow its right bezel to clip at x=320.
  local cx, cy, r = 212, 120, 105
  -- Browser-rendered transparent ring preserves the HTML gradients and edge
  -- antialiasing. Keep vector arcs as a safe fallback.
  local ring_ok = false
  if canvas_img then
    ring_ok = pcall_fn(canvas_img, APP.canvas, 102, 10, "S:/apps/NixieClock/assets/meridian-ring.png", { opa = 255 })
  end
  if not ring_ok then
    arc(cx, cy, r + 2, 68, 104, C.orange, 240, 3)
    arc(cx, cy, r + 2, 109, 180, C.cyan, 240, 3)
    arc(cx, cy, r + 2, 210, 262, C.lime, 225, 3)
    arc(cx, cy, r + 2, 276, 360, C.violet, 230, 3)
  end
  draw_ticks(cx, cy, 98, 60, C.white, 5)
  -- Warm quarter markers add hierarchy without coloring every tick.
  for i = 0, 3 do
    local x1, y1 = polar(cx, cy, 88, i * 90)
    local x2, y2 = polar(cx, cy, 98, i * 90)
    line(x1, y1, x2, y2, C.orange, 255, 2)
  end
  text(cx - 18, cy - 84, 36, "XII", APP.font.en12, C.orange, ALIGN_CENTER)
  text(cx + 61, cy - 7, 28, "III", APP.font.en12, C.soft, ALIGN_CENTER)
  text(cx - 14, cy + 72, 28, "VI", APP.font.en12, C.orange, ALIGN_CENTER)
  text(cx - 86, cy - 7, 30, "IX", APP.font.en12, C.soft, ALIGN_CENTER)
  draw_hands(cx, cy, r, t)
end

local function draw_orbit(t)
  fill(C.black)
  arc(38, 40, 20, 300, 585, C.red, 255, 5)
  arc(38, 40, 14, 300, 535, C.orange, 255, 5)
  arc(38, 40, 8, 300, 500, 0x67DE7A, 255, 4)
  text(9, 75, 58, weekday_of(t) .. " " .. format("%02d", t.day), APP.font.ui12, C.muted, ALIGN_CENTER)
  local cx, cy, r = 160, 120, 90
  circle(cx, cy, r + 7, 0x171C22, 255, 1)
  circle(cx, cy, r, C.border, 255, 1)
  draw_ticks(cx, cy, 81, 12, C.soft, 1)
  text(cx - 12, cy - 76, 24, "12", APP.font.ui12, C.white, ALIGN_CENTER)
  text(cx + 69, cy - 6, 18, "3", APP.font.ui12, C.white, ALIGN_CENTER)
  text(cx - 9, cy + 66, 18, "6", APP.font.ui12, C.white, ALIGN_CENTER)
  text(cx - 86, cy - 6, 18, "9", APP.font.ui12, C.white, ALIGN_CENTER)
  draw_hands(cx, cy, r, t)
  text(263, 30, 48, "MOVE", APP.font.ui12, C.muted, ALIGN_CENTER)
  text(263, 47, 48, "74%", APP.font.ui16, C.orange, ALIGN_CENTER)
  line(262, 117, 312, 117, C.border, 255, 1)
  text(260, 124, 54, "BATTERY 82", APP.font.ui12, C.soft, ALIGN_CENTER)
  line(268, 144, 298, 144, C.lime, 255, 3)
  line(298, 144, 306, 144, 0x1E2920, 255, 3)
end

local function draw_bauhaus(t)
  fill(C.black)
  rect(38, 8, 232, 224, C.ink, 255, 3, C.border, 1)
  local cx, cy, r = 154, 120, 98
  circle(cx, cy, r, C.border, 255, 1)
  draw_ticks(cx, cy, 91, 60, C.soft, 5)
  text(cx - 14, 26, 28, "12", APP.font.ui16, C.white, ALIGN_CENTER)
  text(230, 112, 30, "03", APP.font.ui16, C.white, ALIGN_CENTER)
  text(cx - 14, 198, 28, "06", APP.font.ui16, C.white, ALIGN_CENTER)
  text(48, 112, 30, "09", APP.font.ui16, C.white, ALIGN_CENTER)
  draw_hands(cx, cy, r, t)
  local day, month, date = date_parts(t)
  rect(276, 87, 40, 57, 0xF1F0EB, 255)
  text(278, 91, 36, month, APP.font.ui12, C.muted, ALIGN_CENTER)
  text(278, 105, 36, date, APP.font.ui16, C.black, ALIGN_CENTER)
  text(278, 126, 36, day, APP.font.ui12, C.muted, ALIGN_CENTER)
end

local function draw_weather_card(x, y)
  rect(x, y, 106, 127, 0x071014, 255, 13, 0x1B2A31, 1)
  disc(x + 27, y + 22, 9, C.cyan, 255)
  disc(x + 37, y + 30, 12, 0x16343D, 255)
  rect(x + 18, y + 30, 42, 14, 0x16343D, 255, 7, C.cyan, 1)
  text(x + 10, y + 49, 86, temp_text(), APP.font.n28, C.white)
  text(x + 10, y + 91, 86, APP.state.weather_valid and APP.state.weather_text or "晴间多云", APP.font.ui12, C.cyan)
end

local function draw_modular(t)
  fill(C.black)
  text(8, 5, 184, format("%02d", t.hour), APP.font.n72, C.white)
  text(8, 92, 184, format("%02d", t.min), APP.font.n72, C.lime)
  local day, month, date = date_parts(t)
  rect(202, 14, 106, 80, 0x14131C, 255, 13, 0x2A273C, 1)
  text(213, 23, 45, day, APP.font.ui12, C.violet)
  text(254, 19, 45, date, APP.font.n40, C.white, ALIGN_RIGHT)
  text(213, 70, 65, month, APP.font.ui12, C.muted)
  draw_weather_card(202, 101)
end

local DOT_GLYPHS = {
  ["0"] = { "11111", "10001", "10011", "10101", "11001", "10001", "11111" },
  ["1"] = { "00100", "01100", "00100", "00100", "00100", "00100", "01110" },
  ["2"] = { "11110", "00001", "00001", "11110", "10000", "10000", "11111" },
  ["3"] = { "11110", "00001", "00001", "01110", "00001", "00001", "11110" },
  ["4"] = { "10010", "10010", "10010", "11111", "00010", "00010", "00010" },
  ["5"] = { "11111", "10000", "10000", "11110", "00001", "00001", "11110" },
  ["6"] = { "01111", "10000", "10000", "11110", "10001", "10001", "01110" },
  ["7"] = { "11111", "00001", "00010", "00100", "01000", "01000", "01000" },
  ["8"] = { "01110", "10001", "10001", "01110", "10001", "10001", "01110" },
  ["9"] = { "01110", "10001", "10001", "01111", "00001", "00001", "11110" },
}

local function draw_dot_digit(x, y, digit, color, dim_color)
  local glyph = DOT_GLYPHS[tostring(digit)] or DOT_GLYPHS["0"]
  for row = 1, 7 do
    for col = 1, 5 do
      local lit = glyph[row]:sub(col, col) == "1"
      disc(x + (col - 1) * 11, y + (row - 1) * 11, 4, lit and color or dim_color, 255)
    end
  end
end

local function draw_mono(t)
  fill(C.black)
  local day, month, date = date_parts(t)
  text(14, 13, 136, day .. " " .. string.char(194, 183) .. " " .. month .. " " .. date, APP.font.en12, C.muted)
  text(160, 13, 146, ascii_city_label(APP.state.city) .. "  " .. temp_text(), APP.font.en12, C.soft, ALIGN_RIGHT)
  local hh = format("%02d", t.hour)
  local mm = format("%02d", t.min)
  draw_dot_digit(37, 56, hh:sub(1, 1), 0xFF607A, 0x0A0103)
  draw_dot_digit(98, 56, hh:sub(2, 2), 0xFFB13D, 0x0B0501)
  local colon_color = floor((t.sec or 0) / 2) % 2 == 0 and C.white or 0x181C20
  disc(160, 82, 4, colon_color, 255)
  disc(160, 110, 4, colon_color, 255)
  draw_dot_digit(178, 56, mm:sub(1, 1), C.cyan, 0x020B0E)
  draw_dot_digit(239, 56, mm:sub(2, 2), C.lime, 0x060B02)
  line(14, 154, 305, 154, 0x222A32, 255, 1)
  line(108, 166, 108, 230, 0x1C232B, 255, 1)
  line(211, 166, 211, 230, 0x1C232B, 255, 1)
  if not draw_ui_asset(27, 183, "pulse-weather") then
    draw_weather_icon(43, 199, 13, APP.state.weather_code, APP.state.weather_text)
  end
  text(66, 183, 38, temp_text(), APP.font.en13, C.white)
  text(66, 202, 40, weather_kind(APP.state.weather_code, APP.state.weather_text):upper(), APP.font.en10, 0x596571, nil, nil, 1)
  if not draw_ui_asset(119, 180, "pulse-humidity") then draw_droplet(135, 196, 15, C.cyan) end
  text(154, 183, 52, APP.state.humidity and (tostring(floor(APP.state.humidity)) .. "%") or "--%", APP.font.en13, C.white)
  text(154, 202, 54, "HUMIDITY", APP.font.en10, 0x596571, nil, nil, 1)
  if not draw_ui_asset(227, 183, "pulse-wind") then draw_wind(243, 199, 13, C.lime) end
  text(266, 183, 38, APP.state.wind_speed and tostring(floor(APP.state.wind_speed + 0.5)) or "--", APP.font.en13, C.white)
  text(266, 202, 38, "WIND", APP.font.en10, 0x596571, nil, nil, 1)
end

local FULL_DAY_NAMES = { SUN = "SUNDAY", MON = "MONDAY", TUE = "TUESDAY", WED = "WEDNESDAY", THU = "THURSDAY", FRI = "FRIDAY", SAT = "SATURDAY" }
local FULL_MONTH_NAMES = { JAN = "JANUARY", FEB = "FEBRUARY", MAR = "MARCH", APR = "APRIL", MAY = "MAY", JUN = "JUNE", JUL = "JULY", AUG = "AUGUST", SEP = "SEPTEMBER", OCT = "OCTOBER", NOV = "NOVEMBER", DEC = "DECEMBER" }

local function draw_neon_girl(t)
  fill(C.black)
  local src = "S:/apps/NixieClock/assets/neon-girl-bg.png"
  if canvas_img then pcall_fn(canvas_img, APP.canvas, 0, 0, src, { opa = 255 }) end
  local day, month, date = date_parts(t)
  local date_label = (FULL_DAY_NAMES[day] or day) .. ", " .. (FULL_MONTH_NAMES[month] or month) .. " " .. date
  text(20, 31, 190, date_label, APP.font.en9, 0xA8D8EE, nil, nil, 4)
  text(18, 68, 84, format("%02d", t.hour), APP.font.n69, C.white, nil, nil, -7)
  local colon_color = floor((t.sec or 0) / 2) % 2 == 0 and C.white or 0x181C20
  text(93, 60, 24, ":", APP.font.n69, colon_color)
  text(117, 68, 90, format("%02d", t.min), APP.font.n69, C.white, nil, nil, -7)
  text(19, 142, 40, temp_text(), APP.font.en20, C.white, nil, nil, -1)
  line(60, 144, 60, 163, 0x56CBE2, 255, 1)
  text(71, 148, 76, ascii_city_label(APP.state.city) .. " " .. string.char(194, 183), APP.font.en12, 0x8EB9CA, nil, nil, 1)
  text(148, 148, 40, APP.state.weather_valid and APP.state.weather_text or "晴", APP.font.cn12, 0x8EB9CA)
  for i = 0, 11 do
    local x1 = 18 + i * 24
    local x2 = 37 + i * 24
    if i < 6 then
      line(x1, 219, x2, 219, 0x285E59, 120, 5)
      line(x1, 219, x2, 219, 0x66F1DA, 255, 3)
    else
      line(x1, 219, x2, 219, 0x4A6A84, 133, 3)
    end
  end
end

local function draw_solar_weather(t)
  fill(C.black)
  local day, month, date = date_parts(t)
  text(14, 11, 120, "SOLAR WEATHER", APP.font.en11, C.white, nil, nil, 1)
  text(150, 11, 156, ascii_city_label(APP.state.city) .. " · " .. day .. " " .. date, APP.font.en11, 0x8995A1, ALIGN_RIGHT, nil, 1)

  local previous_x, previous_y
  for i = 0, 48 do
    local p = i / 48
    local x = 22 + 276 * p
    local y = 108 - sin(p * pi) * 44
    if previous_x and i % 2 == 0 then line(previous_x, previous_y, x, y, 0x735D32, 210, 1) end
    previous_x, previous_y = x, y
  end
  disc(197, 59, 13, 0xFFC24D, 18)
  disc(197, 59, 10, 0xFFC24D, 48)
  disc(197, 59, 8, 0xFFC24D, 255)

  text(14, 59, 150, format("%02d:%02d", t.hour, t.min), APP.font.n52, C.white, nil, nil, -5)
  text(141, 97, 28, format("%02d", t.sec), APP.font.en15, 0xFFC24D)
  text(224, 67, 82, temp_text(), APP.font.n34, C.white, ALIGN_RIGHT)

  local current = APP.state.temp and floor(APP.state.temp + 0.5) or nil
  local today = APP.state.forecast_days[1]
  local high = today and today.temp_max and floor(today.temp_max + 0.5) or (current and current + 4)
  local low = today and today.temp_min and floor(today.temp_min + 0.5) or (current and current - 4)
  local weather = APP.state.weather_valid and APP.state.weather_text or "等待天气"
  local feels = current and tostring(current + 2) or "--"
  text(15, 133, 190, weather .. " · 体感 " .. feels .. "°", APP.font.cn11, 0xAAA397)
  local range = high and low and format("H %d° · L %d°", high, low) or "H --° · L --°"
  text(224, 112, 82, range, APP.font.en11, 0xC39A56, ALIGN_RIGHT)

  line(13, 158, 307, 158, 0x443720, 255, 1)
  local labels = { "NOW", "11:00", "13:00", "15:00" }
  local values = {
    current,
    current and current + 2,
    high or (current and current + 4),
    high and high - 1 or (current and current + 3),
  }
  local column_x = { 13, 86, 160, 233 }
  local centers = { 49, 123, 196, 270 }
  for i = 1, 4 do
    if i > 1 then line(column_x[i], 170, column_x[i], 227, 0x30291D, 255, 1) end
    text(column_x[i], 170, 73, labels[i], APP.font.en11, 0xAA9875, ALIGN_CENTER)
    text(column_x[i], 189, 73, values[i] and (tostring(values[i]) .. "°") or "--°", APP.font.en15, C.white, ALIGN_CENTER)
    disc(centers[i], 216, 4, 0xFFC24D, 255)
  end
end

local function draw_terminal(t)
  fill(C.black)
  local green = 0x39FF62
  local green_dim = 0x184F20
  for y = 0, 240, 4 do line(0, y, 320, y, 0x0B2A0F, 24, 1) end
  rect(10, 9, 300, 24, 0x041207, 255, 1, green_dim, 1)
  text(17, 14, 150, "HOLO_TIME / LOCAL", APP.font.mono11, green)
  text(170, 14, 132, "[ NTP SYNC ]", APP.font.mono11, 0x6EF27A, ALIGN_RIGHT)
  text(14, 42, 160, "> CLOCK.RUN", APP.font.mono11, 0x36773C)
  text(12, 61, 216, format("%02d:%02d", t.hour, t.min), APP.font.mono56, green)
  text(237, 72, 68, ":" .. format("%02d", t.sec), APP.font.mono24, 0xB8FFAC, ALIGN_RIGHT)

  local day, month, date = date_parts(t)
  text(15, 119, 190, day .. "  " .. tostring(t.year) .. "-" .. format("%02d-%02d", t.mon, t.day), APP.font.mono11, 0x65C970)
  rect(14, 145, 141, 49, 0x031006, 255, 1, green_dim, 1)
  if not draw_ui_asset(18, 154, "terminal-weather") then draw_cloud(33, 169, 14, 0x61F05D) end
  text(53, 153, 94, temp_text() .. " " .. weather_kind(APP.state.weather_code, APP.state.weather_text):upper(), APP.font.mono12, green)
  text(53, 172, 94, ascii_city_label(APP.state.city), APP.font.mono11, 0x36773C)
  rect(165, 145, 141, 49, 0x031006, 255, 1, green_dim, 1)
  if not draw_ui_asset(169, 153, "terminal-humidity") then draw_droplet(181, 169, 13, 0x75FF82) end
  text(204, 153, 94, APP.state.humidity and (tostring(floor(APP.state.humidity)) .. "% RH") or "--% RH", APP.font.mono12, green)
  text(204, 172, 94, "WEATHER DATA", APP.font.mono11, 0x36773C)

  line(14, 220, 306, 220, green_dim, 230, 1)
  local base = 220
  for i = 0, 23 do
    local wave = 3 + ((i * 7 + t.sec) % 10)
    local x = 22 + i * 12
    line(x, base, x, base - wave, i == (t.sec % 24) and 0xC7FFCA or green, i == (t.sec % 24) and 255 or 120, 2)
  end
end

local function draw_lunar(t)
  fill(C.black)
  local day, month, date = date_parts(t)
  local accent = 0xD2B25C
  text(14, 11, 118, "LUNAR PHASE", APP.font.en11, C.white, nil, nil, 1)
  text(165, 11, 141, day .. " · " .. month .. " " .. date, APP.font.en11, 0x8995A1, ALIGN_RIGHT, nil, 1)
  line(150, 43, 150, 180, 0x302D25, 255, 1)

  local orb_drawn = false
  if canvas_img then
    local phase_index = floor(moon_phase(t) * 16 + 0.5) % 16
    local source = "S:/apps/NixieClock/assets/moon-small-" .. tostring(phase_index) .. ".png"
    orb_drawn = pcall_fn(canvas_img, APP.canvas, 27, 58, source, { opa = 255 })
  end
  if not orb_drawn then
    circle(79, 110, 52, accent, 36, 1)
    draw_moon_phase(79, 110, 40, moon_phase(t))
  end

  text(164, 63, 142, format("%02d:%02d", t.hour, t.min), APP.font.n40, C.white, ALIGN_RIGHT)
  text(164, 121, 142, temp_text() .. " · " .. weather_kind(APP.state.weather_code, APP.state.weather_text):upper(), APP.font.en11, 0xC5BAA0, ALIGN_RIGHT)
  line(14, 198, 306, 198, 0x302D25, 255, 1)

  local orb_value = tostring(floor(moon_phase(t) * 100 + 0.5)) .. "%"
  text(14, 208, 132, "MOON " .. orb_value, APP.font.en11, accent)
  local humidity = APP.state.humidity and ("HUMIDITY " .. tostring(floor(APP.state.humidity)) .. "%") or "HUMIDITY --%"
  text(165, 208, 141, humidity, APP.font.en11, 0x817B6D, ALIGN_RIGHT)
end

local function draw_focus_memo(t)
  fill(C.black)
  line(108, 14, 108, 226, 0x20252B, 255, 1)

  local hh = format("%02d", t.hour)
  local mm = format("%02d", t.min)
  local function focus_digit(x, y, digit)
    text(x + (digit == "1" and 2 or 0), y, 40, digit, APP.font.n42, C.white)
  end
  focus_digit(14, 43, hh:sub(1, 1))
  focus_digit(42, 43, hh:sub(2, 2))
  focus_digit(14, 85, mm:sub(1, 1))
  focus_digit(42, 85, mm:sub(2, 2))

  rect(14, 153, 85, 61, 0x20262D, 255, 4)
  rect(15, 154, 83, 59, C.black, 255, 3)
  if not draw_ui_asset(26, 163, "focus-weather") then
    disc(32, 168, 4, 0xFFB946, 255)
    disc(35, 177, 6, C.soft, 255)
    disc(40, 171, 6, C.soft, 255)
    disc(47, 177, 5, C.soft, 255)
    rect(30, 176, 22, 7, C.soft, 255, 4)
  end
  text(61, 164, 38, temp_text(), APP.font.en16, C.white)
  text(12, 193, 88, ascii_city_label(APP.state.city), APP.font.en9, 0x77828D, ALIGN_CENTER, nil, 1)

  if not APP.state.memo_available then
    rect(120, 63, 187, 112, 0x0C0D11, 255)
    rect(120, 63, 3, 112, C.orange, 255)
    text(133, 83, 162, "MEMO SYNC", APP.font.en10, C.orange, nil, nil, 1)
    text(133, 111, 162, "请先安装 Assistant app", APP.font.cn12, C.white)
    text(133, 139, 162, "time-calendar-weather-memo", APP.font.en8, 0x737B85)
    return
  end

  local row_colors = { C.violet, C.cyan, 0xFF8A3D }
  local row_y = { 32, 95, 158 }
  local row_time = { "10:00", "11:30", "14:00" }
  local row_duration = { "19 MIN", "50 MIN", "2 HOURS" }
  for i = 1, 3 do
    local y = row_y[i]
    rect(120, y, 187, 56, 0x0C0D11, 255)
    rect(120, y, 3, 56, row_colors[i], 255)
    text(133, y + 8, 72, row_time[i], APP.font.en9, row_colors[i])
    text(244, y + 8, 55, row_duration[i], APP.font.en9, 0x737B85, ALIGN_RIGHT)
    text(133, y + 23, 166, utf8_truncate(APP.state.memos[i] or "", 10), APP.font.memo13, C.white)
    rect(133, y + 49, 146, 2, 0x182028, 255)
    rect(133, y + 49, 91, 2, row_colors[i], 255)
  end

end

local function draw_nixie(t)
  fill(C.black)
  local hh = format("%02d", t.hour)
  local mm = format("%02d", t.min)
  local digits = { hh:sub(1, 1), hh:sub(2, 2), mm:sub(1, 1), mm:sub(2, 2) }
  local positions = { 0, 67, 201, 268 }
  if canvas_img then
    for i = 1, 4 do
      local src = "S:/apps/NixieClock/assets/digit_" .. digits[i] .. ".png"
      pcall_fn(canvas_img, APP.canvas, positions[i], 72, src, { opa = 255 })
    end
    pcall_fn(canvas_img, APP.canvas, 134, 72, "S:/apps/NixieClock/assets/colon_on.png", { opa = 255 })
  else
    text(12, 76, 296, hh .. ":" .. mm, APP.font.n72, 0xFF6A22, ALIGN_CENTER)
  end
end

local function draw_calendar(t)
  fill(C.black)
  rect(0, 0, 138, 240, 0x07090C, 255)
  line(126, 18, 126, 223, C.border, 255, 1)
  local day, month, date = date_parts(t)
  text(16, 20, 100, day, APP.font.ui12, C.orange)
  text(9, 54, 108, date, APP.font.n72, C.white)
  text(16, 166, 100, month .. " · " .. tostring(t.year), APP.font.ui12, C.muted)
  for i = 0, 5 do
    disc(20 + i * 14, 195, 3, i < 3 and C.orange or 0x3B2A20, 255)
  end
  text(16, 207, 80, "WEEK 29", APP.font.ui12, C.muted)
  line(143, 18, 143, 36, C.orange, 255, 3)
  line(143, 36, 143, 56, C.violet, 255, 3)
  text(145, 22, 160, format("%02d:%02d", t.hour, t.min), APP.font.n40, C.white)
  draw_sun(158, 98, 7, C.orange)
  text(177, 86, 72, temp_text(), APP.font.n28, C.white)
  text(177, 119, 125, (APP.state.weather_valid and APP.state.weather_text or "晴") .. " · 体感", APP.font.ui12, C.muted)
  line(145, 154, 304, 154, C.border, 255, 1)
  text(145, 164, 60, "NEXT", APP.font.ui12, C.violet)
  text(145, 183, 80, "10:30", APP.font.n28, C.white)
  text(232, 196, 70, "专注时间", APP.font.ui12, C.muted, ALIGN_RIGHT)
end

local function draw_flip_card(x, digit, accent)
  rect(x, 69, 61, 101, 0x181B20, 255, 7)
  rect(x + 1, 69, 59, 2, accent or C.cyan, 255, 1)
  rect(x, 120, 61, 50, 0x101216, 255, 0)
  text(x, 84, 61, tostring(digit), APP.font.n56, 0xECEEF0, ALIGN_CENTER)
  line(x, 120, x + 61, 120, C.black, 255, 2)
  rect(x, 116, 3, 8, C.black, 255)
  rect(x + 58, 116, 3, 8, C.black, 255)
end

local function draw_flip(t)
  fill(C.black)
  local day, month, date = date_parts(t)
  text(26, 20, 55, day, APP.font.ui12, C.muted)
  text(105, 20, 110, month .. " " .. date, APP.font.ui12, C.white, ALIGN_CENTER)
  text(245, 20, 50, temp_text() .. "C", APP.font.ui12, C.muted, ALIGN_RIGHT)
  text(35, 48, 75, "HOUR", APP.font.ui12, C.muted, ALIGN_CENTER)
  text(210, 48, 75, "MINUTE", APP.font.ui12, C.muted, ALIGN_CENTER)
  local hh = format("%02d", t.hour)
  local mm = format("%02d", t.min)
  draw_flip_card(15, hh:sub(1, 1), C.orange)
  draw_flip_card(81, hh:sub(2, 2), C.orange)
  text(145, 93, 25, ":", APP.font.n40, C.muted, ALIGN_CENTER)
  draw_flip_card(174, mm:sub(1, 1), C.cyan)
  draw_flip_card(240, mm:sub(2, 2), C.cyan)
  rect(42, 204, 236, 7, 0x111820, 100, 4)
end

local function draw_glow(t)
  fill(C.black)
  if canvas_img then
    pcall_fn(canvas_img, APP.canvas, 0, 0, "S:/apps/NixieClock/assets/glow-base.png", { opa = 255 })
  else
    for x = 0, 320, 16 do line(x, 0, x, 240, C.cyan_dim, 35, 1) end
    for y = 0, 240, 16 do line(0, y, 320, y, C.cyan_dim, 35, 1) end
  end
  local day, month, date = date_parts(t)
  text(20, 22, 150, day .. "  " .. month .. " " .. date, APP.font.ui12, 0x79D5DF)
  local value = format("%02d:%02d", t.hour, t.min)
  text(23, 76, 275, value, APP.font.n56, 0x164D55, ALIGN_CENTER, 200)
  text(21, 74, 275, value, APP.font.n56, 0x2DA9B4, ALIGN_CENTER, 220)
  text(20, 73, 275, value, APP.font.n56, 0xA9FBFF, ALIGN_CENTER, 255)
  text(276, 80, 34, format("%02d", t.sec), APP.font.ui16, C.cyan)
  draw_sun(25, 215, 6, C.cyan)
  text(36, 208, 55, temp_text() .. "C", APP.font.ui12, C.cyan)
  text(115, 208, 90, "HOLO TIME", APP.font.ui12, C.cyan, ALIGN_CENTER)
  text(252, 208, 52, "82%", APP.font.ui12, C.cyan, ALIGN_RIGHT)
end

local DRAW_FACE = {
  draw_meridian, draw_mono, draw_neon_girl, draw_solar_weather,
  draw_terminal, draw_lunar, draw_focus_memo, draw_nixie
}

local function draw_hud()
  local now = now_ms()
  if now >= APP.state.hud_until_ms then return false end
  rect(93, 205, 134, 27, 0x090C10, 225, 14, C.border, 1)
  text(101, 211, 83, FACE_NAMES[APP.state.face], APP.font.ui12, C.white, ALIGN_CENTER)
  text(185, 211, 34, tostring(APP.state.face) .. "/" .. tostring(APP.FACE_COUNT), APP.font.ui12, C.muted, ALIGN_CENTER)
  return true
end

local function render()
  if not APP.running or not APP.canvas then return end
  local t = local_time()
  frame_begin()
  local fn = DRAW_FACE[APP.state.face] or draw_meridian
  fn(t)
  APP.state.hud_was_visible = draw_hud()
  frame_end()
  APP.state.last_second = t.sec
  APP.state.last_minute = t.min
  APP.state.last_render_face = APP.state.face
end

local function switch_face(direction)
  local next_face = APP.state.face + direction
  if next_face < 1 then next_face = APP.FACE_COUNT end
  if next_face > APP.FACE_COUNT then next_face = 1 end
  APP.state.face = next_face
  APP.state.last_switch_ms = now_ms()
  APP.state.last_auto_switch_ms = APP.state.last_switch_ms
  APP.state.hud_until_ms = APP.state.last_switch_ms + 900
  render()
end

local function angle_delta(value, base)
  local delta = (tonumber(value) or 0) - (tonumber(base) or 0)
  while delta > 180 do delta = delta - 360 end
  while delta < -180 do delta = delta + 360 end
  return delta
end

local function on_imu(_, roll, pitch)
  if not APP.running then return end
  local state = APP.state
  roll = tonumber(roll) or 0
  pitch = tonumber(pitch) or 0
  if state.imu_base_roll == nil then
    state.imu_base_roll = roll
    state.imu_base_pitch = pitch
    return
  end
  local dr = angle_delta(roll, state.imu_base_roll)
  local dp = angle_delta(pitch, state.imu_base_pitch)
  local motion = abs(dp) >= abs(dr) and dp or dr
  if state.imu_armed then
    if abs(motion) >= 27 and now_ms() - state.last_switch_ms >= 650 then
      state.pending_dir = motion > 0 and 1 or -1
      state.imu_armed = false
    elseif abs(dr) < 7 and abs(dp) < 7 then
      state.imu_base_roll = state.imu_base_roll * 0.97 + roll * 0.03
      state.imu_base_pitch = state.imu_base_pitch * 0.97 + pitch * 0.03
    end
  elseif abs(dr) < 10 and abs(dp) < 10 then
    state.imu_armed = true
    state.imu_base_roll = roll
    state.imu_base_pitch = pitch
  end
end

local function bind_input()
  local app_mod = rawget(_G, "app")
  if app_mod and app_mod.on then
    app_mod.on("imu", on_imu)
    APP.input.imu = true
  end
  local key_mod = rawget(_G, "key")
  if key_mod and key_mod.on then
    local function request_key_switch(direction, evt)
      if evt ~= key_mod.SHORT and evt ~= key_mod.START then return end
      local now = now_ms()
      if APP.state.pending_dir ~= 0 or now - APP.state.last_key_ms < APP.KEY_DEBOUNCE_MS then return end
      APP.state.last_key_ms = now
      APP.state.pending_dir = direction
    end
    key_mod.on(key_mod.LEFT, function(evt)
      request_key_switch(-1, evt)
    end)
    key_mod.on(key_mod.RIGHT, function(evt)
      request_key_switch(1, evt)
    end)
    APP.input.keys = true
  end
end

local function url_encode(value)
  return tostring(value or ""):gsub("([^%w%-_%.~])", function(ch)
    return format("%%%02X", string.byte(ch))
  end)
end

local function maybe_gunzip(body)
  if body and zlib and zlib.isgzip and zlib.isgzip(body) and zlib.gunzip then
    local plain = zlib.gunzip(body)
    if plain then return plain end
  end
  return body
end

local function parse_weather(status, body)
  if status ~= 200 or not body then return false end
  local doc = decode_json(maybe_gunzip(body))
  if not doc or tostring(doc.code or "") ~= "200" or type(doc.now) ~= "table" then return false end
  local current = doc.now
  APP.state.temp = tonumber(current.temp)
  APP.state.humidity = tonumber(current.humidity)
  APP.state.wind_speed = tonumber(current.windSpeed)
  APP.state.weather_code = tostring(current.icon or "103")
  APP.state.weather_text = tostring(current.text or "--")
  APP.state.weather_valid = APP.state.temp ~= nil
  render()
  return APP.state.weather_valid
end

local function parse_forecast(status, body)
  if status ~= 200 or not body then APP.state.forecast_valid = false; return false end
  local doc = decode_json(maybe_gunzip(body))
  if not doc or tostring(doc.code or "") ~= "200" or type(doc.daily) ~= "table" then
    APP.state.forecast_valid = false
    return false
  end
  local days = {}
  for i = 1, 3 do
    local item = doc.daily[i]
    if type(item) == "table" then
      days[#days + 1] = {
        date = tostring(item.fxDate or ""),
        icon = tostring(item.iconDay or item.iconNight or "103"),
        text = tostring(item.textDay or item.textNight or "--"),
        temp_max = tonumber(item.tempMax),
        temp_min = tonumber(item.tempMin),
      }
    end
  end
  APP.state.forecast_days = days
  APP.state.forecast_valid = #days > 0
  render()
  return APP.state.forecast_valid
end

local function request_forecast_for(location)
  local http_mod = rawget(_G, "http")
  if not http_mod or not http_mod.cubicserver or not http_mod.cubicserver.get then
    APP.state.forecast_inflight = false
    return
  end
  APP.state.forecast_inflight = true
  local url = APP.WEATHER_3D_PATH .. "?location=" .. url_encode(location) .. "&unit=m&lang=zh"
  http_mod.cubicserver.get(url, "Accept-Encoding: gzip\r\n", function(status, body)
    APP.state.forecast_inflight = false
    if APP.running then parse_forecast(status, body) end
  end)
end

local function request_weather_for(location)
  local http_mod = rawget(_G, "http")
  if not http_mod or not http_mod.cubicserver or not http_mod.cubicserver.get then
    APP.state.weather_inflight = false
    return
  end
  local url = APP.WEATHER_NOW_PATH .. "?location=" .. url_encode(location) .. "&unit=m&lang=zh"
  http_mod.cubicserver.get(url, "Accept-Encoding: gzip\r\n", function(status, body)
    APP.state.weather_inflight = false
    if APP.running then parse_weather(status, body) end
  end)
end

local function request_weather()
  if not APP.running or APP.state.weather_inflight then return end
  local http_mod = rawget(_G, "http")
  if not http_mod or not http_mod.cubicserver or not http_mod.cubicserver.get then return end
  local raw_location = APP.state.weather_address
  local location = APP.state.weather_location_id
  if location == "" and raw_location:match("^%d+$") then location = raw_location end
  if location ~= "" then
    APP.state.weather_inflight = true
    request_weather_for(location)
    return
  end
  if raw_location == "" then return end
  APP.state.weather_inflight = true
  local url = APP.WEATHER_CITY_PATH .. "?location=" .. url_encode(raw_location) .. "&number=1&lang=zh"
  http_mod.cubicserver.get(url, "Accept-Encoding: gzip\r\n", function(status, body)
    if not APP.running then return end
    local doc = status == 200 and decode_json(maybe_gunzip(body)) or nil
    local locations = doc and (doc.locations or doc.location)
    local first = type(locations) == "table" and locations[1] or nil
    local id = type(first) == "table" and trim(first.id) or ""
    if APP.state.weather_address == "" and type(first) == "table" and trim(first.name) ~= "" then APP.state.city = safe_city_label(first.name) end
    if id == "" then APP.state.weather_inflight = false; return end
    APP.state.weather_location_id = id
    request_weather_for(id)
    if not APP.state.forecast_inflight then request_forecast_for(id) end
  end)
end

local function request_forecast()
  if not APP.running or APP.state.forecast_inflight then return end
  local location = APP.state.weather_location_id
  if location == "" and APP.state.weather_address:match("^%d+$") then location = APP.state.weather_address end
  if location ~= "" then request_forecast_for(location) end
end

local WEB_HTML = [=[<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Holo Clock 表盘</title><style>
:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:#020406;color:#f7f9fc;font-family:Inter,"Microsoft YaHei",system-ui,sans-serif}.page{max-width:1100px;margin:auto;padding:24px 16px 48px}header{display:flex;align-items:end;justify-content:space-between;gap:16px;margin-bottom:16px}h1{margin:0;font-size:28px;letter-spacing:-.03em}header p{margin:6px 0 0;color:#8995a1}.state{color:#53e6ff;font:600 13px ui-monospace,monospace}.settings{display:grid;grid-template-columns:1fr 1fr auto;gap:12px;align-items:end;margin-bottom:20px;padding:14px;border:1px solid #26303a;border-radius:14px;background:#080b0f}.field{display:grid;gap:6px}.field label{color:#aeb7c2;font-size:13px}.field select{width:100%;min-height:44px;padding:0 12px;border:1px solid #36424e;border-radius:9px;background:#10151b;color:#f7f9fc;font-size:14px}.save{min-height:44px;padding:0 20px;border:0;border-radius:9px;background:#53e6ff;color:#001014;font-weight:800;cursor:pointer}.save:disabled{opacity:.5;cursor:default}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:14px}.face{appearance:none;width:100%;padding:8px;border:1px solid #26303a;border-radius:14px;background:#080b0f;color:inherit;text-align:left;cursor:pointer;transition:border-color .16s,transform .16s,background .16s}.face:hover{transform:translateY(-2px);border-color:#53606d}.face:focus-visible,.save:focus-visible,.field select:focus-visible{outline:2px solid #53e6ff;outline-offset:2px}.face.selected{border-color:#53e6ff;background:#0a151a;box-shadow:0 0 0 1px #53e6ff,0 0 24px #53e6ff20}.face img{display:block;width:100%;aspect-ratio:4/3;object-fit:cover;border-radius:8px;background:#000}.meta{display:flex;align-items:center;justify-content:space-between;padding:10px 4px 4px}.meta b{font-size:14px}.meta span{color:#75818d;font:600 11px ui-monospace,monospace}.face.selected .meta span{color:#53e6ff}@media(max-width:560px){header{align-items:start;flex-direction:column}.page{padding-top:18px}.settings{grid-template-columns:1fr}.save{width:100%}.grid{grid-template-columns:1fr 1fr;gap:8px}.face{padding:5px;border-radius:10px}.meta b{font-size:12px}.meta span{font-size:9px}}
</style></head><body><main class="page"><header><div><h1>Holo Clock</h1><p>选择表盘会立即切换设备显示。</p></div><div id="state" class="state" aria-live="polite">正在连接设备</div></header><section class="settings" aria-label="表盘设置"><div class="field"><label for="defaultFace">开机默认表盘</label><select id="defaultFace"></select></div><div class="field"><label for="autoSwitch">自动切换表盘</label><select id="autoSwitch"><option value="0">不切换</option><option value="600000">每 10 分钟</option><option value="3600000">每 1 小时</option></select></div><button id="save" class="save" type="button">保存设置</button></section><section id="grid" class="grid"></section></main><script>
const faces=['Meridian','Pulse WX','Neon Girl','Solar Weather','Terminal','Lunar','Focus Memo','Nixie'];const count=faces.length,grid=document.getElementById('grid'),state=document.getElementById('state'),defaultFace=document.getElementById('defaultFace'),autoSwitch=document.getElementById('autoSwitch'),save=document.getElementById('save');const base=location.pathname.replace(/\/?$/,'/'),faceApi=base+'api/face',settingsApi=base+'api/settings';faces.forEach((name,i)=>{const option=document.createElement('option');option.value=i+1;option.textContent=`${String(i+1).padStart(2,'0')} · ${name}`;defaultFace.appendChild(option);const b=document.createElement('button');b.className='face';b.dataset.face=i+1;b.innerHTML=`<img src="/apps/NixieClock/previews/${String(i+1).padStart(2,'0')}.png" alt="${name} 表盘预览"><span class="meta"><b>${name}</b><span>${String(i+1).padStart(2,'0')} / ${String(count).padStart(2,'0')}</span></span>`;b.onclick=()=>select(i+1);grid.appendChild(b)});function paint(face){document.querySelectorAll('.face').forEach(e=>e.classList.toggle('selected',Number(e.dataset.face)===face));state.textContent=`当前表盘 ${String(face).padStart(2,'0')} / ${String(count).padStart(2,'0')}`}async function load(){const [fr,sr]=await Promise.all([fetch(faceApi,{cache:'no-store'}),fetch(settingsApi,{cache:'no-store'})]),f=await fr.json(),s=await sr.json();if(!f.ok||!s.ok)throw Error(f.error||s.error||'读取失败');paint(f.face);defaultFace.value=s.default_face;autoSwitch.value=s.auto_switch_ms}async function select(face){state.textContent='正在切换';try{const r=await fetch(faceApi,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({face})}),d=await r.json();if(!d.ok)throw Error(d.error||'切换失败');paint(d.face)}catch(e){state.textContent=e.message}}save.onclick=async()=>{save.disabled=true;state.textContent='正在保存设置';try{const r=await fetch(settingsApi,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({default_face:Number(defaultFace.value),auto_switch_ms:Number(autoSwitch.value)})}),d=await r.json();if(!d.ok)throw Error(d.error||'保存失败');state.textContent='设置已保存'}catch(e){state.textContent=e.message}finally{save.disabled=false}};load().catch(e=>state.textContent=e.message);
</script></body></html>]=]

local function encode_json(value)
  local codec = rawget(_G, "json") or rawget(_G, "sjson")
  if codec and codec.encode then
    local ok, body = pcall_fn(codec.encode, value)
    if ok and type(body) == "string" then return body end
  end
  return "{\"ok\":false,\"error\":\"JSON unavailable\"}"
end

local function web_response(body, content_type, status)
  return {
    status = status or "200 OK",
    type = content_type or "text/plain; charset=utf-8",
    headers = { ["cache-control"] = "no-store" },
    body = body or "",
  }
end

local function normalize_route_base(base)
  if type(base) ~= "string" then return nil end
  base = base:gsub("\\", "/"):gsub("^/*", ""):gsub("/*$", "")
  if base == "" then return nil end
  return "/" .. base
end

local function start_web()
  local server = rawget(_G, "httpd")
  if not (server and server.start and server.dynamic) then return end
  pcall_fn(server.stop)
  pcall_fn(server.start, { webroot = "/sd", auto_index = server.INDEX_NONE, max_handlers = 16 })
  local function route(method, path, handler) pcall_fn(server.dynamic, method, path, handler) end
  local function index() return web_response(WEB_HTML, "text/html; charset=utf-8") end
  local function face_api(req)
    if req and req.method == server.POST then
      local raw = req.body or req.payload
      if not raw and req.getbody then
        local ok, value = pcall_fn(req.getbody)
        if ok then raw = value end
      end
      local doc = decode_json(raw or "")
      local face = type(doc) == "table" and tonumber(doc.face) or nil
      if not face or face < 1 or face > APP.FACE_COUNT then
        return web_response(encode_json({ ok = false, error = "表盘编号无效" }), "application/json; charset=utf-8", "400 Bad Request")
      end
      APP.state.face = floor(face)
      APP.state.last_render_face = 0
      APP.state.hud_until_ms = 0
      APP.state.last_auto_switch_ms = now_ms()
      render()
    end
    return web_response(encode_json({ ok = true, face = APP.state.face, count = APP.FACE_COUNT, names = FACE_NAMES }), "application/json; charset=utf-8")
  end
  local function settings_api(req)
    if req and req.method == server.POST then
      local raw = req.body or req.payload
      if not raw and req.getbody then
        local ok, value = pcall_fn(req.getbody)
        if ok then raw = value end
      end
      local doc = decode_json(raw or "")
      local face = type(doc) == "table" and floor(tonumber(doc.default_face) or 0) or 0
      local interval = type(doc) == "table" and tonumber(doc.auto_switch_ms) or -1
      if face < 1 or face > APP.FACE_COUNT or (interval ~= 0 and interval ~= 600000 and interval ~= 3600000) then
        return web_response(encode_json({ ok = false, error = "设置值无效" }), "application/json; charset=utf-8", "400 Bad Request")
      end
      APP.state.default_face = face
      APP.state.auto_switch_ms = interval
      APP.state.last_auto_switch_ms = now_ms()
      if not save_app_config() then
        return web_response(encode_json({ ok = false, error = "设置保存失败" }), "application/json; charset=utf-8", "500 Internal Server Error")
      end
    end
    return web_response(encode_json({ ok = true, default_face = APP.state.default_face, auto_switch_ms = APP.state.auto_switch_ms }), "application/json; charset=utf-8")
  end
  local function snapshot_api(req)
    local raw = req and (req.body or req.payload) or nil
    if not raw and req and req.getbody then
      local ok, value = pcall_fn(req.getbody)
      if ok then raw = value end
    end
    local doc = decode_json(raw or "")
    local face = type(doc) == "table" and tonumber(doc.face) or APP.state.face
    if not face or face < 1 or face > APP.FACE_COUNT then
      return web_response(encode_json({ ok = false, error = "表盘编号无效" }), "application/json; charset=utf-8", "400 Bad Request")
    end
    local snapshot_take = rawget(_G, "lv_snapshot_take")
    local snapshot_save = rawget(_G, "lv_snapshot_save_to_png")
    local snapshot_free = rawget(_G, "lv_snapshot_free")
    if not (snapshot_take and snapshot_save and snapshot_free) then
      return web_response(encode_json({ ok = false, error = "snapshot API unavailable" }), "application/json; charset=utf-8", "501 Not Implemented")
    end
    local requested_face = floor(face)
    if APP.state.face ~= requested_face then
      APP.state.face = requested_face
      APP.state.last_render_face = 0
      APP.state.hud_until_ms = 0
      render()
    end
    local ok_take, snapshot, take_err = pcall_fn(snapshot_take, APP.canvas)
    if not ok_take or not snapshot then
      return web_response(encode_json({ ok = false, error = tostring(take_err or snapshot or "snapshot failed") }), "application/json; charset=utf-8", "500 Internal Server Error")
    end
    local path = APP.APP_DIR .. "/captures/face-" .. format("%02d", face) .. ".png"
    local ok_save, saved, save_err = pcall_fn(snapshot_save, snapshot, path)
    pcall_fn(snapshot_free, snapshot)
    if not ok_save or not saved then
      return web_response(encode_json({ ok = false, error = tostring(save_err or saved or "PNG save failed") }), "application/json; charset=utf-8", "500 Internal Server Error")
    end
    return web_response(encode_json({ ok = true, face = face, path = path }), "application/json; charset=utf-8")
  end
  local bases, seen = {}, {}
  local function add_base(base)
    base = normalize_route_base(base)
    if base and not seen[base] then seen[base] = true; bases[#bases + 1] = base end
  end
  add_base("NixieClock")
  local app_mod = rawget(_G, "app")
  if app_mod and app_mod.route_base then
    local ok, base = pcall_fn(app_mod.route_base)
    if ok then add_base(base) end
  end
  for _, base in ipairs(bases) do
    route(server.GET, base, index)
    route(server.GET, base .. "/", index)
    route(server.GET, base .. "/api/face", face_api)
    route(server.POST, base .. "/api/face", face_api)
    route(server.GET, base .. "/api/settings", settings_api)
    route(server.POST, base .. "/api/settings", settings_api)
    route(server.POST, base .. "/api/snapshot", snapshot_api)
  end
  APP.web_started = true
end

local function maybe_stop_for_exit()
  local app_mod = rawget(_G, "app")
  if app_mod and app_mod.exiting then
    local ok, exiting = pcall_fn(app_mod.exiting)
    if ok and exiting then APP.stop("exit"); return true end
  end
  return false
end

local function tick()
  if not APP.running or maybe_stop_for_exit() then return end
  local now = now_ms()
  if APP.state.auto_switch_ms > 0 and now - APP.state.last_auto_switch_ms >= APP.state.auto_switch_ms then
    switch_face(1)
    return
  end
  if APP.state.pending_dir ~= 0 then
    local direction = APP.state.pending_dir
    APP.state.pending_dir = 0
    switch_face(direction)
    return
  end
  local t = local_time()
  local hud_visible = now < APP.state.hud_until_ms
  local second_face = APP.state.face == 1 or APP.state.face == 5
  local blink_face = APP.state.face == 2 or APP.state.face == 3
  local blink_phase_changed = blink_face and floor(t.sec / 2) ~= floor((APP.state.last_second < 0 and -2 or APP.state.last_second) / 2)
  local time_changed = second_face and t.sec ~= APP.state.last_second or blink_phase_changed or t.min ~= APP.state.last_minute
  if APP.state.face ~= APP.state.last_render_face or time_changed or hud_visible ~= APP.state.hud_was_visible then render() end
end

local function init_ui()
  local root = lv_scr_act()
  lv_obj_clean(root)
  APP.root = root
  if lv_obj_set_style_bg_color then pcall_fn(lv_obj_set_style_bg_color, root, C.black, PART_MAIN) end
  if lv_obj_set_style_bg_opa then pcall_fn(lv_obj_set_style_bg_opa, root, 255, PART_MAIN) end
  if CANVAS_FMT then APP.canvas = canvas_create(root, APP.SCREEN_W, APP.SCREEN_H, CANVAS_FMT)
  else APP.canvas = canvas_create(root, APP.SCREEN_W, APP.SCREEN_H) end
  if obj_pos and APP.canvas then pcall_fn(obj_pos, APP.canvas, 0, 0) end
end

local function start_timers()
  if not tmr or not tmr.create then return end
  APP.timers.tick = tmr.create()
  APP.timers.tick:alarm(APP.TICK_MS, tmr.ALARM_AUTO, function()
    local ok, err = pcall_fn(tick)
    if not ok then warn("tick failed", tostring(err)); APP.stop("tick-error") end
  end)
  APP.timers.weather = tmr.create()
  APP.timers.weather:alarm(APP.WEATHER_FETCH_MS, tmr.ALARM_AUTO, function()
    if APP.running then request_weather() end
  end)
  APP.timers.forecast = tmr.create()
  APP.timers.forecast:alarm(APP.WEATHER_FETCH_MS, tmr.ALARM_AUTO, function()
    if APP.running then request_forecast() end
  end)
  APP.timers.memo = tmr.create()
  APP.timers.memo:alarm(APP.MEMO_FETCH_MS, tmr.ALARM_AUTO, function()
    if APP.running and load_memos() and APP.state.face == 7 then render() end
  end)
  APP.timers.weather_start = tmr.create()
  APP.timers.weather_start:alarm(2500, tmr.ALARM_SINGLE, function()
    if APP.running then request_weather() end
  end)
  APP.timers.forecast_start = tmr.create()
  APP.timers.forecast_start:alarm(4500, tmr.ALARM_SINGLE, function()
    if APP.running then request_forecast() end
  end)
end

function APP.stop(reason)
  if not APP.running then return end
  APP.running = false
  for _, timer in pairs(APP.timers) do
    pcall_fn(function() timer:stop() end)
    pcall_fn(function() timer:unregister() end)
  end
  APP.timers = {}
  local app_mod = rawget(_G, "app")
  if APP.input.imu and app_mod and app_mod.on then pcall_fn(app_mod.on, "imu", nil) end
  local key_mod = rawget(_G, "key")
  if APP.input.keys and key_mod and key_mod.off then
    pcall_fn(key_mod.off, key_mod.LEFT)
    pcall_fn(key_mod.off, key_mod.RIGHT)
  end
  local server = rawget(_G, "httpd")
  if APP.web_started and server and server.stop then pcall_fn(server.stop) end
  APP.web_started = false
  if lv_font_free then
    for _, handle in ipairs(APP.font_handles) do pcall_fn(lv_font_free, handle) end
  end
  APP.font_handles = {}
  if rawget(_G, "HOLO_TIME_APP") == APP then _G.HOLO_TIME_APP = nil end
  if lv_scr_act and lv_obj_clean then pcall_fn(lv_obj_clean, lv_scr_act()) end
  warn("stop", tostring(reason or ""))
end

APP.shutdown = APP.stop

load_settings()
load_app_config()
init_time()
init_fonts()
load_memos()
init_ui()
if APP.canvas then
  APP.state.last_auto_switch_ms = now_ms()
  bind_input()
  render()
  start_web()
  start_timers()
end
