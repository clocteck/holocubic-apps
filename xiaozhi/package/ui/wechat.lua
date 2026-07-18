local M = {}
local FIXED_VIEW_MODE = "wechat"

local SEL_MAIN = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
local LV_LABEL_LONG_CLIP = rawget(_G, "LV_LABEL_LONG_CLIP") or 1
local LV_LABEL_LONG_WRAP = rawget(_G, "LV_LABEL_LONG_WRAP") or LV_LABEL_LONG_CLIP
local LV_LABEL_LONG_SCROLL_CIRCULAR = rawget(_G, "LV_LABEL_LONG_SCROLL_CIRCULAR") or LV_LABEL_LONG_CLIP
local LV_TEXT_ALIGN_LEFT = rawget(_G, "LV_TEXT_ALIGN_LEFT") or 0
local LV_TEXT_ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1
local LV_IMG_SIZE_MODE_REAL = rawget(_G, "LV_IMG_SIZE_MODE_REAL") or 0
local LV_OBJ_FLAG_SCROLLABLE = rawget(_G, "LV_OBJ_FLAG_SCROLLABLE") or 0
local LV_OBJ_FLAG_HIDDEN = rawget(_G, "LV_OBJ_FLAG_HIDDEN") or 0
local LV_DIR_VER = rawget(_G, "LV_DIR_VER") or 0
local LV_ANIM_ON = rawget(_G, "LV_ANIM_ON") or 1
local LV_ANIM_OFF = rawget(_G, "LV_ANIM_OFF") or 0
local lv_obj_has_flag_fn = rawget(_G, "lv_obj_has_flag")

-- 官方默认 LCD 深色主题：纯黑背景、白色文字。
local C = {
  bg = 0x000000,
  text = 0xFFFFFF,
  user_text = 0x111111,
  muted = 0xB8B8B8,
  user = 0x00FF00,
  assistant = 0x222222,
  system = 0x000000,
}

local active_text_font = nil

local function text_or(value, fallback)
  if value == nil then
    return fallback or ""
  end
  local text = tostring(value)
  if text == "" then
    return fallback or ""
  end
  return text
end

local function utf8_char(cp)
  if cp < 0 or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF) then
    return nil
  end
  if cp <= 0x7F then
    return string.char(cp)
  elseif cp <= 0x7FF then
    return string.char(
      0xC0 + math.floor(cp / 0x40),
      0x80 + (cp % 0x40)
    )
  elseif cp <= 0xFFFF then
    return string.char(
      0xE0 + math.floor(cp / 0x1000),
      0x80 + (math.floor(cp / 0x40) % 0x40),
      0x80 + (cp % 0x40)
    )
  end
  return string.char(
    0xF0 + math.floor(cp / 0x40000),
    0x80 + (math.floor(cp / 0x1000) % 0x40),
    0x80 + (math.floor(cp / 0x40) % 0x40),
    0x80 + (cp % 0x40)
  )
end

local function decode_unicode_escapes(value)
  local text = text_or(value, "")
  if not string.find(text, "\\u", 1, true) then
    return text
  end

  local out = {}
  local i = 1
  while i <= #text do
    if string.sub(text, i, i + 1) == "\\u" then
      local hex = string.sub(text, i + 2, i + 5)
      local cp = tonumber(hex, 16)
      if cp then
        local used = 6
        if cp >= 0xD800 and cp <= 0xDBFF and string.sub(text, i + 6, i + 7) == "\\u" then
          local low = tonumber(string.sub(text, i + 8, i + 11), 16)
          if low and low >= 0xDC00 and low <= 0xDFFF then
            cp = 0x10000 + (cp - 0xD800) * 0x400 + (low - 0xDC00)
            used = 12
          end
        end
        local ch = utf8_char(cp)
        if ch then
          out[#out + 1] = ch
          i = i + used
        else
          out[#out + 1] = string.sub(text, i, i + used - 1)
          i = i + used
        end
      else
        out[#out + 1] = string.sub(text, i, i)
        i = i + 1
      end
    else
      out[#out + 1] = string.sub(text, i, i)
      i = i + 1
    end
  end
  return table.concat(out)
end

local function path_exists(path)
  if not path or path == "" then
    return false
  end
  if file and file.exists then
    local ok, ret = pcall(function()
      return file.exists(path)
    end)
    if ok then
      return ret and true or false
    end
  end
  if file and file.stat then
    local ok, st = pcall(function()
      return file.stat(path)
    end)
    return ok and st ~= nil
  end
  return false
end

local function load_text_font(cfg)
  if not lv_font_load then
    return nil
  end
  local path = cfg and cfg.TEXT_FONT_PATH or nil
  if not path_exists(path) then
    return nil
  end
  local ok, handle = pcall(function()
    return lv_font_load(path)
  end)
  if ok and type(handle) == "number" and handle > 0 then
    print("[xiaozhi] font loaded", path)
    return handle
  end
  print("[xiaozhi] font load failed", tostring(path), tostring(handle))
  return nil
end

local function set_label(id, text)
  if id and lv_label_set_text then
    pcall(function()
      lv_label_set_text(id, text_or(text, ""))
    end)
  end
end

local function disable_scroll(id)
  if id and lv_obj_clear_flag and LV_OBJ_FLAG_SCROLLABLE ~= 0 then
    pcall(function()
      lv_obj_clear_flag(id, LV_OBJ_FLAG_SCROLLABLE)
    end)
  end
end

local function enable_scroll_y(id)
  if not id then
    return
  end
  if lv_obj_add_flag and LV_OBJ_FLAG_SCROLLABLE ~= 0 then
    pcall(function()
      lv_obj_add_flag(id, LV_OBJ_FLAG_SCROLLABLE)
    end)
  end
  if lv_obj_set_scroll_dir and LV_DIR_VER ~= 0 then
    pcall(function()
      lv_obj_set_scroll_dir(id, LV_DIR_VER)
    end)
  end
end

local function style_rect(id, bg, opa, scrollable)
  if not id then
    return
  end
  lv_obj_set_style_bg_color(id, bg or C.bg, SEL_MAIN)
  lv_obj_set_style_bg_opa(id, opa == nil and 255 or opa, SEL_MAIN)
  lv_obj_set_style_border_width(id, 0, SEL_MAIN)
  lv_obj_set_style_radius(id, 0, SEL_MAIN)
  if lv_obj_set_style_pad_all then
    lv_obj_set_style_pad_all(id, 0, SEL_MAIN)
  end
  if scrollable then
    enable_scroll_y(id)
  else
    disable_scroll(id)
  end
end

local function style_transparent(id)
  style_rect(id, C.bg, 0, false)
end

local function style_round(id, bg, radius)
  style_rect(id, bg, 255, false)
  lv_obj_set_style_radius(id, radius or 8, SEL_MAIN)
end

local function style_label(id, color, align)
  if not id then
    return
  end
  lv_obj_set_style_text_color(id, color or C.text, SEL_MAIN)
  if active_text_font and lv_obj_set_style_text_font then
    pcall(function()
      lv_obj_set_style_text_font(id, active_text_font, SEL_MAIN)
    end)
  end
  if lv_obj_set_style_text_align then
    lv_obj_set_style_text_align(id, align or LV_TEXT_ALIGN_CENTER, SEL_MAIN)
  end
end

local function label(parent, x, y, w, h, text, color, align, long_mode)
  local id = lv_label_create(parent)
  lv_obj_set_pos(id, x, y)
  lv_obj_set_size(id, w, h)
  if lv_label_set_long_mode then
    lv_label_set_long_mode(id, long_mode or LV_LABEL_LONG_CLIP)
  end
  style_label(id, color, align)
  set_label(id, text)
  return id
end

local function set_hidden(id, hidden)
  if not id or LV_OBJ_FLAG_HIDDEN == 0 then
    return
  end
  if lv_obj_has_flag_fn then
    local ok, has = pcall(lv_obj_has_flag_fn, id, LV_OBJ_FLAG_HIDDEN)
    if ok and has == hidden then
      return
    end
  end
  if hidden and lv_obj_add_flag then
    pcall(function() lv_obj_add_flag(id, LV_OBJ_FLAG_HIDDEN) end)
  elseif (not hidden) and lv_obj_clear_flag then
    pcall(function() lv_obj_clear_flag(id, LV_OBJ_FLAG_HIDDEN) end)
  end
end

local function text_units(text)
  local units = {}
  local i = 1
  while i <= #text do
    local b = string.byte(text, i)
    local size = 1
    if b >= 0xF0 then
      size = 4
    elseif b >= 0xE0 then
      size = 3
    elseif b >= 0xC0 then
      size = 2
    end
    local ch = string.sub(text, i, i + size - 1)
    local width = 16
    if b < 0x80 then
      if ch == "\t" then
        width = 16
      elseif string.find("ilI1.,:;!'|`", ch, 1, true) then
        width = 5
      elseif string.find("MWmw@#%&", ch, 1, true) then
        width = 13
      else
        width = 9
      end
    end
    units[#units + 1] = { text = ch, width = width }
    i = i + size
  end
  return units
end

-- LVGL 的 Lua 绑定没有可靠的文本测量接口。这里用当前 16px 字体的保守宽度
-- 预先换行，让气泡尺寸、实际标签行数和滚动内容高度始终保持一致。
local function bubble_layout(text, max_w, min_w)
  text = text_or(text, ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  local natural_w = 0
  local line_w = 0
  for _, unit in ipairs(text_units(text)) do
    if unit.text == "\n" then
      natural_w = math.max(natural_w, line_w)
      line_w = 0
    else
      line_w = line_w + unit.width
    end
  end
  natural_w = math.max(natural_w, line_w)

  local width = math.max(min_w or 44, math.min(max_w, natural_w + 18))
  local content_w = math.max(8, width - 18)
  local out = {}
  local lines = 1
  line_w = 0
  for _, unit in ipairs(text_units(text)) do
    if unit.text == "\n" then
      out[#out + 1] = "\n"
      lines = lines + 1
      line_w = 0
    else
      if line_w > 0 and line_w + unit.width > content_w then
        out[#out + 1] = "\n"
        lines = lines + 1
        line_w = 0
      end
      out[#out + 1] = unit.text
      line_w = line_w + unit.width
    end
  end
  return width, 14 + lines * 20, table.concat(out)
end

local emotion_alias = {
  microchip_ai = "neutral",
  listening = "thinking",
  speaking = "happy",
  download = "thinking",
  link = "happy",
  triangle_exclamation = "confused",
  circle_xmark = "sad",
  cloud_slash = "sad",
}

local emotion_text = {
  neutral = "AI",
  listening = "听",
  speaking = "说",
  sleepy = "休",
  happy = "笑",
  laughing = "笑",
  funny = "乐",
  sad = "忧",
  angry = "怒",
  crying = "哭",
  loving = "爱",
  embarrassed = "羞",
  surprised = "惊",
  shocked = "惊",
  thinking = "想",
  winking = "眨",
  cool = "酷",
  relaxed = "松",
  delicious = "馋",
  kissy = "亲",
  confident = "稳",
  silly = "玩",
  confused = "?",
  microchip_ai = "AI",
  triangle_exclamation = "!",
  circle_xmark = "!",
  cloud_slash = "云",
  download = "↓",
  link = "链",
}

local function emotion_name(emotion)
  local name = text_or(emotion, "neutral")
  return emotion_alias[name] or name
end

local function find_asset(candidates)
  for i = 1, #candidates do
    if path_exists(candidates[i]) then
      return candidates[i]
    end
  end
  return nil
end

local function trim(text)
  return tostring(text or ""):match("^%s*(.-)%s*$") or ""
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
  local days = math.floor((tonumber(sec) or 0) / 86400)
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
    return { std_name = std_name, std_offset = std_offset }
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

  local parsed = {
    std_name = std_name,
    std_offset = std_offset,
    dst_name = dst_name,
    dst_offset = dst_offset,
  }
  if tz:sub(index, index) ~= "," then
    return parsed
  end

  local rules = tz:sub(index + 1)
  local comma = rules:find(",", 1, true)
  if not comma then
    return parsed
  end
  parsed.start_rule = parse_dst_rule(rules:sub(1, comma - 1))
  parsed.end_rule = parse_dst_rule(rules:sub(comma + 1))
  return parsed
end

local function timezone_offset_for_epoch(tz, sec)
  local parsed = parse_posix_timezone(tz)
  if not parsed then
    return 0
  end
  if not parsed.start_rule or not parsed.end_rule then
    return parsed.std_offset or 0
  end

  local year = year_from_epoch((tonumber(sec) or 0) + (parsed.std_offset or 0))
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

local function timezone_label(tz, sec, tm)
  local parsed = parse_posix_timezone(tz)
  if not parsed then
    return trim(tz) ~= "" and trim(tz) or "UTC", false
  end

  local in_dst = false
  if type(tm) == "table" then
    in_dst = tm.isdst == true or tm.dst == true
  end
  if parsed.start_rule and parsed.end_rule and type(sec) == "number" then
    local year = year_from_epoch(sec + (parsed.std_offset or 0))
    local start_utc = transition_utc(year, parsed.start_rule, parsed.std_offset)
    local end_utc = transition_utc(year, parsed.end_rule, parsed.dst_offset)
    if start_utc < end_utc then
      in_dst = sec >= start_utc and sec < end_utc
    else
      in_dst = sec >= start_utc or sec < end_utc
    end
  end

  if in_dst and parsed.dst_name then
    return parsed.dst_name, true
  end
  return parsed.std_name or trim(tz), false
end

local applied_timezone = nil

local function apply_timezone(tz)
  tz = trim(tz)
  if tz == "" then
    tz = "CST-8"
  end
  if applied_timezone ~= tz and time and time.settimezone then
    pcall(time.settimezone, tz)
    applied_timezone = tz
  end
  return tz
end

local function current_epoch()
  if time and time.get then
    local ok, sec = pcall(time.get)
    if ok and type(sec) == "number" and sec > 0 then
      return sec
    end
  end
  if rtctime and rtctime.get then
    local ok, sec = pcall(rtctime.get)
    if ok and type(sec) == "number" and sec > 0 then
      return sec
    end
  end
  if os and os.time then
    local ok, sec = pcall(os.time)
    if ok and type(sec) == "number" and sec > 0 then
      return sec
    end
  end
  return nil
end

local function now_clock(cfg)
  local tz = apply_timezone(cfg and cfg.TIMEZONE or "CST-8")
  local epoch = current_epoch()
  if time and time.getlocal then
    local ok, t = pcall(time.getlocal)
    if ok and type(t) == "table" and t.hour then
      local name, in_dst = timezone_label(tz, epoch, t)
      return string.format("%02d:%02d %s%s", tonumber(t.hour) or 0, tonumber(t.min) or 0, name, in_dst and " DST" or "")
    end
  end
  if epoch and time and time.epoch2cal then
    local offset = timezone_offset_for_epoch(tz, epoch)
    local ok_cal, cal = pcall(time.epoch2cal, epoch + offset)
    if ok_cal and type(cal) == "table" and cal.hour then
      local name, in_dst = timezone_label(tz, epoch, cal)
      return string.format("%02d:%02d %s%s", tonumber(cal.hour) or 0, tonumber(cal.min) or 0, name, in_dst and " DST" or "")
    end
  end
  if epoch and rtctime and rtctime.epoch2cal then
    local offset = timezone_offset_for_epoch(tz, epoch)
    local ok_cal, year, mon, day, hour, min = pcall(rtctime.epoch2cal, epoch + offset)
    if ok_cal and type(year) == "number" and year >= 2024 and type(hour) == "number" then
      local name, in_dst = timezone_label(tz, epoch, { year = year, mon = mon, day = day, hour = hour, min = min })
      return string.format("%02d:%02d %s%s", tonumber(hour) or 0, tonumber(min) or 0, name, in_dst and " DST" or "")
    end
  end
  if epoch and os and os.date then
    local offset = timezone_offset_for_epoch(tz, epoch)
    local ok, t = pcall(os.date, "!*t", epoch + offset)
    if ok and type(t) == "table" and t.hour then
      local name, in_dst = timezone_label(tz, epoch, t)
      return string.format("%02d:%02d %s%s", tonumber(t.hour) or 0, tonumber(t.min) or 0, name, in_dst and " DST" or "")
      end
  end
  return ""
end

local function now_ms()
  if millis then
    local ok, value = pcall(millis)
    if ok and tonumber(value) then
      return tonumber(value)
    end
  end
  if tmr and tmr.now then
    local ok, value = pcall(tmr.now)
    if ok and tonumber(value) then
      return math.floor(tonumber(value) / 1000)
    end
  end
  return 0
end

function M.new(cfg)
  local self = {
    cfg = cfg,
    root = nil,
    notification_timer = nil,
    text_font = nil,
    ui = {},
    messages = {},
    -- nil forces setup() to apply the configured layout instead of treating
    -- the default value as if the layout had already been initialized.
    view_mode = nil,
    last_state = "",
    last_status = "正在初始化",
    last_status_ms = 0,
    last_emotion = "microchip_ai",
    last_role = "system",
    last_message = "",
    current_emotion_name = "",
    current_media_kind = "",
    current_media_src = "",
    gif_loaded_src = "",
    last_emotion_ms = 0,
    metrics = {},
  }
  apply_timezone(cfg and cfg.TIMEZONE or "CST-8")

  local function append_message(role, content)
    content = text_or(content, "")
    if content == "" then
      return
    end
    role = text_or(role, "system")
    local last = self.messages[#self.messages]
    if role == "system" and last and last.role == "system" then
      last.content = content
    else
      self.messages[#self.messages + 1] = { role = role, content = content }
    end
    while #self.messages > 20 do
      table.remove(self.messages, 1)
    end
  end

  local function draw_bubble(role, content, y)
    local max_w = role == "system" and 236 or 230
    local min_w = role == "system" and 52 or 48
    local w, content_h, wrapped = bubble_layout(content, max_w, min_w)
    -- 上下各留 10px，保证任何单个气泡都不会高于 212px 的聊天视口。
    -- 超出的文字保留完整高度，由气泡自身提供纵向滚动。
    local h = math.min(content_h, 192)
    local x = 12
    local bg = C.assistant
    if role == "user" then
      x = 320 - 12 - w
      bg = C.user
    elseif role == "system" then
      x = math.floor((320 - w) / 2)
      bg = C.system
    end

    local bubble = lv_obj_create(self.ui.chat_area)
    lv_obj_set_pos(bubble, x, y)
    lv_obj_set_size(bubble, w, h)
    style_round(bubble, bg, 8)

    local txt = label(bubble, 9, 7, w - 18, content_h - 12, wrapped,
      role == "user" and C.user_text or C.text,
      LV_TEXT_ALIGN_LEFT, LV_LABEL_LONG_WRAP)
    if lv_obj_set_style_text_align then
      lv_obj_set_style_text_align(txt, LV_TEXT_ALIGN_LEFT, SEL_MAIN)
    end
    if content_h > h then
      enable_scroll_y(bubble)
      if lv_obj_scroll_to_y then
        pcall(function() lv_obj_scroll_to_y(bubble, 0, LV_ANIM_OFF) end)
      end
    end
    return bubble, h
  end

  -- 重绘微信气泡列表；列表对象较少，重建比维护局部状态更稳定。
  local function refresh_chat_area()
    if not self.ui.chat_area or not lv_obj_clean then
      return
    end
    -- 列表使用绝对坐标重建；重建完成并定位到底部前先隐藏视口，避免
    -- 尚未应用新滚动量的气泡短暂绘制在物理屏幕范围之外。
    set_hidden(self.ui.chat_area, true)
    -- 重建前清掉旧的视口偏移，避免新气泡沿用旧坐标原点而出现在屏幕外。
    if lv_obj_scroll_to_y then
      pcall(function() lv_obj_scroll_to_y(self.ui.chat_area, 0, LV_ANIM_OFF) end)
    end
    pcall(function()
      lv_obj_clean(self.ui.chat_area)
    end)
    local y = 10
    local first = nil
    for i = #self.messages, 1, -1 do
      local item = self.messages[i]
      local bubble, h = draw_bubble(item.role, item.content, y)
      first = first or bubble
      y = y + h + 8
    end
    if first then
      -- 倒序显示时最新消息固定在顶部；重建后归零滚动位置即可。
      if lv_obj_update_layout then
        pcall(function() lv_obj_update_layout(self.ui.chat_area) end)
      end
      if lv_obj_scroll_to_y then
        pcall(function() lv_obj_scroll_to_y(self.ui.chat_area, 0, LV_ANIM_OFF) end)
      elseif lv_obj_scroll_to_view_recursive then
        pcall(function() lv_obj_scroll_to_view_recursive(first, LV_ANIM_ON) end)
      end
    end
    if self.view_mode == "wechat" then
      set_hidden(self.ui.chat_area, false)
    end
  end

  -- 微信 UI 固定使用气泡布局；保留 set_view_mode 仅兼容旧按键事件。
  function self:set_view_mode(mode, quiet)
    mode = FIXED_VIEW_MODE
    if self.view_mode == mode and self.ui.chat_area then
      return
    end
    self.view_mode = mode
    set_hidden(self.ui.chat_area, mode ~= "wechat")
    set_hidden(self.ui.emoji_box, mode == "wechat")
    if mode == "wechat" then
      set_hidden(self.ui.bottom_bar, true)
      refresh_chat_area()
      if not quiet then
        self:show_notification("微信气泡模式", 1200)
      end
    else
      set_hidden(self.ui.bottom_bar, self.last_message == "")
      if not quiet then
        self:show_notification("官方字幕模式", 1200)
      end
    end
  end

  -- 更新顶部左侧状态文字；通知显示时会临时覆盖它。
  function self:set_status(status)
    self.last_status = text_or(status, "")
    self.last_status_ms = now_ms()
    set_label(self.ui.status, self.last_status)
    set_hidden(self.ui.notify, true)
    set_hidden(self.ui.status, false)
  end

  -- 显示官方同款顶部通知，超时后恢复状态文字。
  function self:show_notification(text, duration_ms)
    duration_ms = tonumber(duration_ms) or 3000
    set_label(self.ui.notify, text_or(text, ""))
    set_hidden(self.ui.status, true)
    set_hidden(self.ui.notify, false)
    if self.notification_timer then
      pcall(function() self.notification_timer:stop() end)
      pcall(function() self.notification_timer:unregister() end)
      self.notification_timer = nil
    end
    if tmr and tmr.create then
      self.notification_timer = tmr.create()
      self.notification_timer:alarm(duration_ms, tmr.ALARM_SINGLE, function()
        self.notification_timer = nil
        set_hidden(self.ui.notify, true)
        set_hidden(self.ui.status, false)
      end)
    end
  end

  -- 先使用官方表情 GIF，再退回 PNG，最后退回白色文字占位。
  function self:set_emotion(emotion)
    self.last_emotion = text_or(emotion, "neutral")
    local name = emotion_name(self.last_emotion)
    local ts = now_ms()
    if self.current_emotion_name == name and self.current_media_kind ~= "" then
      return
    end
    local min_ms = self.cfg.UI and tonumber(self.cfg.UI.emotion_min_ms) or 0
    local important = (name == "sad" or name == "confused" or name == "shocked" or name == "circle_xmark")
    if not important and self.current_emotion_name ~= "" and min_ms > 0 and
        ts > 0 and (ts - self.last_emotion_ms) < min_ms then
      return
    end

    local gif_path = find_asset({
      (self.cfg.EMOJI_GIF_DIR or "") .. "/" .. name .. ".gif",
      (self.cfg.ASSET_DIR or "") .. "/emojis/" .. name .. ".gif",
    })
    local gif_enabled = not (self.cfg.UI and self.cfg.UI.gif_enabled == false)
    if gif_enabled and gif_path and self.ui.emotion_gif and lv_gif_set_src then
      -- GIF 解码器设置 src 会从第一帧重启；同一路径已加载时只切可见性。
      local ok = true
      if self.gif_loaded_src ~= gif_path then
        ok = pcall(function()
          lv_gif_set_src(self.ui.emotion_gif, gif_path)
        end)
      end
      if ok then
        self.current_emotion_name = name
        self.current_media_kind = "gif"
        self.current_media_src = gif_path
        self.gif_loaded_src = gif_path
        self.last_emotion_ms = ts
        set_hidden(self.ui.emotion_gif, false)
        set_hidden(self.ui.emotion_img, true)
        set_hidden(self.ui.emotion, true)
        return
      end
    end

    local img_path = find_asset({
      (self.cfg.EMOJI_PNG_DIR or "") .. "/" .. name .. ".png",
      (self.cfg.ASSET_DIR or "") .. "/emojis/" .. name .. ".png",
      (self.cfg.ASSET_DIR or "") .. "/emojis/" .. name .. ".jpg",
      (self.cfg.ASSET_DIR or "") .. "/emojis/" .. name .. ".bmp",
    })
    if img_path and self.ui.emotion_img and lv_img_set_src then
      local ok = true
      if self.current_media_kind ~= "img" or self.current_media_src ~= img_path then
        ok = pcall(function()
          lv_img_set_src(self.ui.emotion_img, img_path)
          if lv_img_set_size_mode then
            lv_img_set_size_mode(self.ui.emotion_img, LV_IMG_SIZE_MODE_REAL)
          end
          if lv_img_set_zoom then
            lv_img_set_zoom(self.ui.emotion_img, 256)
          end
          if lv_img_set_antialias then
            lv_img_set_antialias(self.ui.emotion_img, true)
          end
        end)
      end
      if ok then
        if self.ui.emotion_gif and lv_gif_set_src and self.current_media_kind == "gif" then
          pcall(function() lv_gif_set_src(self.ui.emotion_gif, nil) end)
        end
        self.gif_loaded_src = ""
        self.current_emotion_name = name
        self.current_media_kind = "img"
        self.current_media_src = img_path
        self.last_emotion_ms = ts
        set_hidden(self.ui.emotion_gif, true)
        set_hidden(self.ui.emotion_img, false)
        set_hidden(self.ui.emotion, true)
        return
      end
    end

    if self.ui.emotion_gif and lv_gif_set_src and self.current_media_kind == "gif" then
      pcall(function() lv_gif_set_src(self.ui.emotion_gif, nil) end)
    end
    self.gif_loaded_src = ""
    self.current_emotion_name = name
    self.current_media_kind = "text"
    self.current_media_src = emotion_text[self.last_emotion] or emotion_text[name] or self.last_emotion
    self.last_emotion_ms = ts
    set_hidden(self.ui.emotion_gif, true)
    set_hidden(self.ui.emotion_img, true)
    set_hidden(self.ui.emotion, false)
    set_label(self.ui.emotion, self.current_media_src)
  end

  -- 默认模式显示底部字幕；微信模式保存最近 20 条并重绘气泡。
  function self:set_chat_message(role, content)
    self.last_role = text_or(role, "system")
    self.last_message = decode_unicode_escapes(content)
    append_message(self.last_role, self.last_message)
    set_label(self.ui.chat, self.last_message)
    set_hidden(self.ui.bottom_bar, self.view_mode ~= "default" or self.last_message == "")
    if self.view_mode == "wechat" then
      refresh_chat_area()
    end
  end

  function self:clear_chat_messages()
    self.last_role = "system"
    self.last_message = ""
    self.messages = {}
    set_label(self.ui.chat, "")
    set_hidden(self.ui.bottom_bar, true)
    if self.ui.chat_area and lv_obj_clean then
      pcall(function()
        lv_obj_clean(self.ui.chat_area)
      end)
    end
  end

  function self:update_status_bar(force)
    local metrics = self.metrics or {}
    set_label(self.ui.net, metrics.network or "")
    set_label(self.ui.audio, "")
    set_label(self.ui.wake, "")
    if self.last_state == "idle" then
      local ts = now_ms()
      if ts > 0 and self.last_status_ms > 0 and (ts - self.last_status_ms) > 10000 then
        local clock = now_clock(self.cfg)
        if clock ~= "" then
          set_label(self.ui.status, clock)
        end
      end
    end
    if force then
      self:set_status(self.last_status)
    end
  end

  function self:set_metrics(metrics)
    self.metrics = metrics or {}
    self:update_status_bar(false)
  end

  function self:on_state(state)
    self.last_state = text_or(state, "")
    local status = {
      starting = "启动中",
      wifi_configuring = "配网中",
      activating = "激活中",
      idle = "待命",
      connecting = "连接中",
      listening = "聆听中",
      speaking = "回答中",
      upgrading = "升级中",
      audio_testing = "音频测试",
      fatal_error = "错误",
    }
    local emotion = {
      starting = "microchip_ai",
      wifi_configuring = "thinking",
      activating = "thinking",
      idle = "neutral",
      connecting = "thinking",
      listening = "thinking",
      speaking = "happy",
      upgrading = "download",
      audio_testing = "microchip_ai",
      fatal_error = "circle_xmark",
    }
    self:set_status(status[state] or tostring(state or ""))
    self:set_emotion(emotion[state] or "neutral")
  end

  function self:alert(status, message, emotion)
    self:set_status(status or "错误")
    self:set_emotion(emotion or "circle_xmark")
    self:set_chat_message("system", message or "")
  end

  -- 搭建官方默认 LCD 布局，并预创建微信气泡层供长按切换。
  function self:setup()
    self.root = lv_scr_act and lv_scr_act() or nil
    if not self.root or not lv_obj_create or not lv_label_create then
      print("[xiaozhi] lvgl api missing")
      return false
    end
    if lv_obj_clean then
      pcall(function() lv_obj_clean(self.root) end)
    end

    active_text_font = load_text_font(self.cfg)
    self.text_font = active_text_font
    style_rect(self.root, C.bg, 255, false)

    self.ui.container = lv_obj_create(self.root)
    lv_obj_set_pos(self.ui.container, 0, 0)
    lv_obj_set_size(self.ui.container, 320, 240)
    style_rect(self.ui.container, C.bg, 255, false)

    self.ui.chat_area = lv_obj_create(self.root)
    lv_obj_set_pos(self.ui.chat_area, 0, 28)
    lv_obj_set_size(self.ui.chat_area, 320, 212)
    style_rect(self.ui.chat_area, C.bg, 255, true)
    set_hidden(self.ui.chat_area, true)

    self.ui.emoji_box = lv_obj_create(self.root)
    lv_obj_set_pos(self.ui.emoji_box, 110, 70)
    lv_obj_set_size(self.ui.emoji_box, 100, 100)
    style_transparent(self.ui.emoji_box)

    if lv_gif_create then
      self.ui.emotion_gif = lv_gif_create(self.ui.emoji_box)
      lv_obj_set_pos(self.ui.emotion_gif, 18, 18)
      lv_obj_set_size(self.ui.emotion_gif, 64, 64)
      set_hidden(self.ui.emotion_gif, true)
    end

    if lv_img_create then
      self.ui.emotion_img = lv_img_create(self.ui.emoji_box)
      lv_obj_set_pos(self.ui.emotion_img, 18, 18)
      lv_obj_set_size(self.ui.emotion_img, 64, 64)
      set_hidden(self.ui.emotion_img, true)
    end

    self.ui.emotion = label(self.ui.emoji_box, 0, 34, 100, 32, "AI", C.text)

    self.ui.bottom_bar = lv_obj_create(self.root)
    lv_obj_set_pos(self.ui.bottom_bar, 0, 204)
    lv_obj_set_size(self.ui.bottom_bar, 320, 36)
    style_rect(self.ui.bottom_bar, C.bg, 128, false)
    self.ui.chat = label(self.ui.bottom_bar, 16, 8, 288, 20, "", C.text,
      LV_TEXT_ALIGN_CENTER, LV_LABEL_LONG_SCROLL_CIRCULAR)
    set_hidden(self.ui.bottom_bar, true)

    self.ui.top_bar = lv_obj_create(self.root)
    lv_obj_set_pos(self.ui.top_bar, 0, 0)
    lv_obj_set_size(self.ui.top_bar, 320, 28)
    style_rect(self.ui.top_bar, C.bg, 128, false)

    self.ui.net = label(self.ui.top_bar, 270, 6, 38, 16, "", C.text)
    self.ui.audio = label(self.ui.top_bar, 232, 6, 34, 16, "", C.text)
    self.ui.wake = label(self.ui.top_bar, 270, 6, 38, 16, "", C.text)

    self.ui.status_bar = lv_obj_create(self.root)
    lv_obj_set_pos(self.ui.status_bar, 0, 0)
    lv_obj_set_size(self.ui.status_bar, 320, 28)
    style_transparent(self.ui.status_bar)
    self.ui.notify = label(self.ui.status_bar, 12, 5, 248, 18, "", C.text,
      LV_TEXT_ALIGN_LEFT, LV_LABEL_LONG_CLIP)
    self.ui.status = label(self.ui.status_bar, 12, 5, 248, 18, self.last_status,
      C.text, LV_TEXT_ALIGN_LEFT, LV_LABEL_LONG_CLIP)
    set_hidden(self.ui.notify, true)

    self:set_emotion("neutral")
    self:set_view_mode(FIXED_VIEW_MODE, true)
    self:update_status_bar(true)
    return true
  end

  function self:stop()
    if self.notification_timer then
      pcall(function() self.notification_timer:stop() end)
      pcall(function() self.notification_timer:unregister() end)
      self.notification_timer = nil
    end
    if self.ui.emotion_gif and lv_gif_set_src then
      pcall(function() lv_gif_set_src(self.ui.emotion_gif, nil) end)
    end
    self.gif_loaded_src = ""
    if self.root and lv_obj_clean then
      pcall(function() lv_obj_clean(self.root) end)
    end
    if self.text_font and lv_font_free then
      pcall(function() lv_font_free(self.text_font) end)
      if active_text_font == self.text_font then
        active_text_font = nil
      end
      self.text_font = nil
    end
  end

  return self
end

return M
