
local SCREEN_W = 320
local SCREEN_H = 240
local ICON_SIZE = 84
local ICON_DRAW_SIZE = 75
local ICON_CANVAS_SIZE = 128
local ICON_MAX_SOURCE_SIZE = 512
local ICON_Y = 85
local LABEL_GAP = 17
local LABEL_H = 16
local LEFT_X = -45
local CENTER_X = math.floor((SCREEN_W - ICON_SIZE) / 2)
local RIGHT_X = SCREEN_W - 45
local NTP_SERVER = "ntp.aliyun.com"
local OFFSCREEN_LEFT_X = -125
local OFFSCREEN_RIGHT_X = SCREEN_W + 45
local ANIM_MS = 360

local SETTINGS_PATH = "/sd/apps/settings.json"
local DEFAULT_LANGUAGE = "zh-CN"
local AP_POLICY_START_DELAY_MS = 750
local AP_IP_WAIT_MS = 5000
local AP_POLICY_POLL_MS = 250
local AUTOSTART_BOOT_WINDOW_MS = 5000
local AUTOSTART_DELAY_MS = 200
local APP_LIST_POLL_MS = 1000
local AUTOSTART_MARK_PATH = "/tmp/launcher_autostart_fired"
local DEFAULT_AUTOSTART_APP_ID = "wifi_guide"
local DISPLAY_SCHEDULE_SERVICE_ID = "display_schedule"
local DISPLAY_SCHEDULE_APP_DIR = "/sd/apps/display_schedule"
local DISPLAY_SCHEDULE_BUNDLE_DIR = "/sd/apps/launcher/services/display_schedule"
local DISPLAY_SCHEDULE_BUNDLE_VERSION = "1.0.2"

local function normalize_language(value)
  local text = tostring(value or ""):gsub("_", "-")
  if text == "en" or text:match("^en%-") then return "en" end
  if text == "ja" or text:match("^ja%-") then return "ja" end
  if text == "zh-TW" or text == "zh-Hant" or text:match("^zh%-Hant") or text:match("^zh%-HK") then
    return "zh-TW"
  end
  return DEFAULT_LANGUAGE
end

local function read_settings()
  if not file or not file.getcontents then return {} end
  local ok, raw = pcall(function() return file.getcontents(SETTINGS_PATH) end)
  if not ok or type(raw) ~= "string" or raw == "" then return {} end
  local codec = rawget(_G, "json") or rawget(_G, "sjson")
  if not codec or not codec.decode then return {} end
  local decoded, doc = pcall(function() return codec.decode(raw) end)
  if not decoded or type(doc) ~= "table" then return {} end
  return doc
end

local function setting_bool(value, fallback)
  if type(value) == "boolean" then return value end
  if type(value) == "number" then return value ~= 0 end
  local text = tostring(value or ""):lower()
  if text == "true" or text == "1" or text == "on" or text == "enabled" then return true end
  if text == "false" or text == "0" or text == "off" or text == "disabled" then return false end
  return fallback
end

local function version_parts(value)
  local parts = {}
  for part in tostring(value or ""):gmatch("(%d+)") do
    parts[#parts + 1] = tonumber(part) or 0
    if #parts >= 4 then break end
  end
  return parts
end

local function version_lt(a, b)
  local av, bv = version_parts(a), version_parts(b)
  for i = 1, 4 do
    local ai, bi = av[i] or 0, bv[i] or 0
    if ai < bi then return true end
    if ai > bi then return false end
  end
  return false
end

local function read_info_value(path, key)
  if not file or not file.getcontents then return "" end
  local ok, raw = pcall(function() return file.getcontents(path) end)
  if not ok or type(raw) ~= "string" then return "" end
  local pattern = "\n%s*" .. key .. "%s*=%s*([^\r\n]+)"
  return tostring(("\n" .. raw):match(pattern) or ""):match("^%s*(.-)%s*$") or ""
end

local function copy_file(src, dst)
  if not file or not file.getcontents or not file.putcontents then return false end
  local ok, data = pcall(function() return file.getcontents(src) end)
  if not ok or type(data) ~= "string" then return false end
  local wrote, result = pcall(function() return file.putcontents(dst, data) end)
  return wrote and result ~= false
end

local function ensure_display_schedule_service()
  if not file or not file.exists then return false end
  if not file.exists(DISPLAY_SCHEDULE_BUNDLE_DIR .. "/main.lua") then return false end

  local current_version = read_info_value(DISPLAY_SCHEDULE_APP_DIR .. "/app.info", "version")
  if file.exists(DISPLAY_SCHEDULE_APP_DIR .. "/main.lua")
      and current_version ~= ""
      and not version_lt(current_version, DISPLAY_SCHEDULE_BUNDLE_VERSION) then
    return false
  end

  if file.mkdir then pcall(function() file.mkdir(DISPLAY_SCHEDULE_APP_DIR) end) end
  local ok_info = copy_file(DISPLAY_SCHEDULE_BUNDLE_DIR .. "/app.info", DISPLAY_SCHEDULE_APP_DIR .. "/app.info")
  local ok_main = copy_file(DISPLAY_SCHEDULE_BUNDLE_DIR .. "/main.lua", DISPLAY_SCHEDULE_APP_DIR .. "/main.lua")
  if ok_info and ok_main and app and app.rescan then
    pcall(function() app.rescan() end)
  end
  return ok_info and ok_main
end

local function start_display_schedule_service()
  if not app or not app.start_service then return end
  ensure_display_schedule_service()
  pcall(function() app.start_service(DISPLAY_SCHEDULE_SERVICE_ID) end)
end

local SETTINGS = read_settings()
local LANGUAGE = normalize_language(SETTINGS.language or SETTINGS.locale or SETTINGS.lang)
local TIMEZONE = tostring(SETTINGS.timezone or "CST-8")
if TIMEZONE == "" then TIMEZONE = "CST-8" end
local AP_PREFERRED_ENABLED = setting_bool(SETTINGS.ap_enabled, true)
local AUTOSTART_ENABLED = setting_bool(SETTINGS.autostart_enabled, true)
local AUTOSTART_APP_ID = tostring(SETTINGS.autostart_app_id or DEFAULT_AUTOSTART_APP_ID)

local UI_TEXT = {
  ["zh-CN"] = { no_apps = "暂无应用" },
  en = { no_apps = "NO APPS" },
  ja = { no_apps = "アプリなし" },
  ["zh-TW"] = { no_apps = "暫無應用" },
}

local UI_FONT_PATHS = {
  ["zh-CN"] = "/sd/apps/launcher/font/launcher_ui_zh_cn_16.bin",
  ja = "/sd/apps/launcher/font/launcher_ui_ja_16.bin",
  ["zh-TW"] = "/sd/apps/launcher/font/launcher_ui_zh_tw_16.bin",
}

local root = lv_scr_act()
lv_obj_clean(root)
if rawget(_G, "LAUNCHER_UI_FONT_HANDLE") and lv_font_free then
  pcall(function() lv_font_free(_G.LAUNCHER_UI_FONT_HANDLE) end)
end
_G.LAUNCHER_UI_FONT_HANDLE = nil

local UI_FONT = LV_FONT_MONTSERRAT_16
local ui_font_path = UI_FONT_PATHS[LANGUAGE]
if ui_font_path and lv_font_load then
  local ok, handle = pcall(function() return lv_font_load(ui_font_path) end)
  if ok and type(handle) == "number" and handle > 0 then
    UI_FONT = handle
    _G.LAUNCHER_UI_FONT_HANDLE = handle
  end
end

local STATE = {
  apps = {},
  icon_sizes = {},
  index = 1,
  reload_timer = nil,
  anim_timer = nil,
  ap_policy_timer = nil,
  animating = false,
  repeat_left = 0,
  repeat_right = 0,
  repeat_up = 0,
  up_launch_fired = false,
  autostart_fired = false,
  app_list_signature = "",
  app_list_timer = nil,
  controller_timer = nil,
  controller_buttons = 0,
}

local UI = {}

local function text_or(value, fallback)
  if value == nil or value == "" then
    return fallback or ""
  end
  return tostring(value)
end

local APP_NAMES = {
  launcher = { ["zh-CN"]="启动器", en="Launcher", ja="ランチャー", ["zh-TW"]="啟動器" },
  ["2048"] = { ["zh-CN"]="2048", en="2048", ja="2048", ["zh-TW"]="2048" },
  BTC = { ["zh-CN"]="股票", en="Ticker", ja="相場", ["zh-TW"]="股票" },
  ConwayLife = { ["zh-CN"]="生命游戏", en="Conway's Life", ja="ライフゲーム", ["zh-TW"]="生命遊戲" },
  devtools = { ["zh-CN"]="开发工具", en="DevTools", ja="開発ツール", ["zh-TW"]="開發工具" },
  Spectrum = { ["zh-CN"]="频谱时钟", en="Spectrum", ja="スペクトラム", ["zh-TW"]="頻譜時鐘" },
  ["time-calendar-weather-memo"] = { ["zh-CN"]="记事本", en="Assistant", ja="アシスタント", ["zh-TW"]="記事本" },
  photos = { ["zh-CN"]="相册", en="Photos", ja="写真", ["zh-TW"]="相簿" },
  wifi_guide = { ["zh-CN"]="配网指南", en="WiFi Setup", ja="WiFi 設定", ["zh-TW"]="配網指南" },
  videos = { ["zh-CN"]="动图播放器", en="GIF Player", ja="GIF プレーヤー", ["zh-TW"]="動圖播放器" },
  NixieClock = { ["zh-CN"]="全息时钟", en="Holo Clock", ja="ホロ時計", ["zh-TW"]="全息時鐘" },
  settings = { ["zh-CN"]="设置", en="Settings", ja="設定", ["zh-TW"]="設定" },
  mp3_player = { ["zh-CN"]="音乐", en="Music", ja="音楽", ["zh-TW"]="音樂" },
  MatrixRain = { ["zh-CN"]="代码雨", en="Matrix Rain", ja="マトリックスレイン", ["zh-TW"]="程式碼雨" },
  holopet = { ["zh-CN"]="Clawd 监控", en="Clawd Monitor", ja="Clawd モニター", ["zh-TW"]="Clawd 監控" },
  devrun = { ["zh-CN"]="文件管理器", en="DevRun", ja="開発実行", ["zh-TW"]="檔案管理器" },
  weather = { ["zh-CN"]="天气", en="Weather", ja="天気", ["zh-TW"]="天氣" },
  holo_pc_monitor = { ["zh-CN"]="全息PC监控", en="PC Monitor", ja="PC モニター", ["zh-TW"]="全息PC監控" },
  ["holo-retro-go"] = { ["zh-CN"]="复古游戏", en="Retro-Go", ja="レトロゲーム", ["zh-TW"]="復古遊戲" },
  FluidPendant = { ["zh-CN"]="流体时钟", en="Fluid Pendant", ja="流体ペンダント", ["zh-TW"]="流體時鐘" },
  aida_monitor = { ["zh-CN"]="AIDA64 监控", en="AIDA64 Monitor", ja="AIDA64 モニター", ["zh-TW"]="AIDA64 監控" },
  xiaozhi = { ["zh-CN"]="小智", en="Xiaozhi", ja="Xiaozhi", ["zh-TW"]="小智" },
  ["xiaozhi-service"] = { ["zh-CN"]="小智服务", en="Xiaozhi Service", ja="Xiaozhi サービス", ["zh-TW"]="小智服務" },
  plane = { ["zh-CN"]="飞机大战", en="Plane", ja="飛行機", ["zh-TW"]="飛機大戰" },
}

local APP_INFO_CACHE = {}

local function app_info_names(id)
  id = tostring(id or "")
  if APP_INFO_CACHE[id] then return APP_INFO_CACHE[id] end
  local values = {}
  if id:match("^[%w_.%-]+$") and file and file.getcontents then
    local ok, raw = pcall(function() return file.getcontents("/sd/apps/" .. id .. "/app.info") end)
    if ok and type(raw) == "string" then
      for line in raw:gmatch("[^\r\n]+") do
        local key, value = line:match("^%s*([%w_%-]+)%s*=%s*(.-)%s*$")
        if key and value and value ~= "" then values[key:lower():gsub("-", "_")] = value end
      end
    end
  end
  APP_INFO_CACHE[id] = values
  return values
end

local function localized_app_name(item)
  if not item then return "" end
  local id = text_or(item.id, "")
  local info = app_info_names(id)
  local keys = LANGUAGE == "zh-CN" and { "name_zh_cn", "name_zh", "name_cn" }
    or LANGUAGE == "zh-TW" and { "name_zh_tw", "name_zh_hant", "name_tw" }
    or LANGUAGE == "ja" and { "name_ja", "name_jp" }
    or { "name_en", "name_en_us" }
  for _, key in ipairs(keys) do
    if info[key] and info[key] ~= "" then return info[key] end
  end
  local known = APP_NAMES[id]
  if known and known[LANGUAGE] then return known[LANGUAGE] end
  local raw = text_or(item.name, id)
  -- 英文模式绝不把未本地化的 CJK 名称直接显示到桌面。
  if LANGUAGE == "en" and raw:find("[\128-\255]") then return id ~= "" and id or "App" end
  return raw
end

local function safe_set_text(id, text)
  if not id then
    return
  end
  pcall(function()
    lv_label_set_text(id, text_or(text, ""))
  end)
end

local function safe_set_hidden(id, hidden)
  if not id then
    return
  end
  pcall(function()
    if hidden then
      lv_obj_add_flag(id, LV_OBJ_FLAG_HIDDEN)
    else
      lv_obj_clear_flag(id, LV_OBJ_FLAG_HIDDEN)
    end
  end)
end

local function sync_ntp_once()
  local time_mod = rawget(_G, "time")
  if not time_mod or not time_mod.initntp then
    return
  end
  pcall(function()
    time_mod.initntp(NTP_SERVER)
  end)
end

local function apply_timezone()
  local time_mod = rawget(_G, "time")
  if not time_mod or not time_mod.settimezone then
    return
  end
  pcall(function()
    time_mod.settimezone(TIMEZONE)
  end)
end

local function style_panel(id, bg, opa, radius, border_w, border_color, border_opa)
  lv_obj_set_style_bg_color(id, bg, LV_PART_MAIN)
  lv_obj_set_style_bg_opa(id, opa, LV_PART_MAIN)
  lv_obj_set_style_radius(id, radius, LV_PART_MAIN)
  lv_obj_set_style_border_width(id, border_w, LV_PART_MAIN)
  lv_obj_set_style_border_color(id, border_color, LV_PART_MAIN)
  lv_obj_set_style_border_opa(id, border_opa, LV_PART_MAIN)
  lv_obj_set_style_pad_all(id, 0, LV_PART_MAIN)
end

local function style_text(id, color, font, align)
  lv_obj_set_style_text_color(id, color, LV_PART_MAIN)
  lv_obj_set_style_text_opa(id, 255, LV_PART_MAIN)
  lv_obj_set_style_text_font(id, font, LV_PART_MAIN)
  lv_obj_set_style_text_align(id, align, LV_PART_MAIN)
end

local function style_icon_box(id, dim)
  lv_obj_set_style_bg_opa(id, 0, LV_PART_MAIN)
  lv_obj_set_style_border_width(id, dim and 0 or 2, LV_PART_MAIN)
  lv_obj_set_style_border_color(id, 0xFFFFFF, LV_PART_MAIN)
  lv_obj_set_style_border_opa(id, dim and 0 or 255, LV_PART_MAIN)
  lv_obj_set_style_radius(id, math.floor(ICON_SIZE / 6), LV_PART_MAIN)
  lv_obj_set_style_clip_corner(id, true, LV_PART_MAIN)
  lv_obj_set_style_border_post(id, true, LV_PART_MAIN)
  lv_obj_set_style_pad_all(id, 2, LV_PART_MAIN)
  lv_obj_clear_flag(id, LV_OBJ_FLAG_OVERFLOW_VISIBLE)
end

local function clamp_index()
  local count = #STATE.apps
  if count <= 0 then
    STATE.index = 1
    return
  end
  if STATE.index < 1 then
    STATE.index = count
  elseif STATE.index > count then
    STATE.index = 1
  end
end

local function current_item()
  clamp_index()
  return STATE.apps[STATE.index]
end

local function path_exists(path)
  if not path or path == "" or not file or not file.open then
    return false
  end

  local fd = file.open(path, "r")
  if not fd then
    return false
  end
  fd:close()
  return true
end

local function read_be_u32(data, index)
  local b1, b2, b3, b4 = string.byte(data, index, index + 3)
  if not b1 or not b2 or not b3 or not b4 then return nil end
  return ((b1 * 256 + b2) * 256 + b3) * 256 + b4
end

local function read_png_size(path)
  local fd = file and file.open and file.open(path, "r")
  if not fd then return nil end
  local header = fd:read(24)
  fd:close()
  if not header or #header < 24 then return nil end
  if header:sub(1, 8) ~= string.char(137, 80, 78, 71, 13, 10, 26, 10) then return nil end
  if header:sub(13, 16) ~= "IHDR" then return nil end
  local w, h = read_be_u32(header, 17), read_be_u32(header, 21)
  if not w or not h or w < 1 or h < 1 or w > ICON_MAX_SOURCE_SIZE or h > ICON_MAX_SOURCE_SIZE then
    return nil
  end
  return { w = w, h = h }
end

local function display_icon_path(item)
  local app_id = text_or(item and item.id, "")
  if app_id == "" then
    return nil
  end
  return "S:/apps/" .. app_id .. "/main.png"
end

local function has_display_icon(item)
  local app_id = text_or(item and item.id, "")
  if app_id == "" then return false end
  local size = read_png_size("/sd/apps/" .. app_id .. "/main.png")
  if not size then return false end
  STATE.icon_sizes[app_id] = size
  return true
end

local function stop_timer(timer_ref_name)
  local timer = STATE[timer_ref_name]
  if not timer then
    return
  end
  pcall(function()
    timer:stop()
    timer:unregister()
  end)
  STATE[timer_ref_name] = nil
end

local function set_wifi_mode(mode)
  if not wifi or not wifi.mode or mode == nil then
    return false
  end
  local ok, err = pcall(function()
    wifi.mode(mode, false)
  end)
  if not ok then
    print("[launcher] set wifi mode failed:", tostring(err))
  end
  return ok
end

local function station_ip()
  if not wifi or not wifi.sta or not wifi.sta.getip then
    return nil
  end
  local ok, ip = pcall(function()
    return wifi.sta.getip()
  end)
  if ok and type(ip) == "string" and ip ~= "" then
    return ip
  end
  return nil
end

-- 固件会先短暂启动 AP+STA；launcher 稍后按用户偏好关闭 AP，
-- 若纯 STA 在约 5 秒内仍未获得 IP，则恢复 AP 作为救援入口。
local function start_ap_policy()
  if not tmr or not tmr.create or not wifi then
    return
  end

  stop_timer("ap_policy_timer")
  local startup_wait_ms = 0
  local ip_wait_ms = 0
  local policy_started = false
  local t = tmr.create()
  STATE.ap_policy_timer = t
  t:alarm(AP_POLICY_POLL_MS, tmr.ALARM_AUTO, function(self)
    if not policy_started then
      startup_wait_ms = startup_wait_ms + AP_POLICY_POLL_MS
      if startup_wait_ms < AP_POLICY_START_DELAY_MS then
        return
      end
      policy_started = true

      if AP_PREFERRED_ENABLED then
        set_wifi_mode(wifi.STATIONAP)
        stop_timer("ap_policy_timer")
        return
      end

      if station_ip() then
        set_wifi_mode(wifi.STATION)
        stop_timer("ap_policy_timer")
        return
      end

      set_wifi_mode(wifi.STATION)
      return
    end

    if station_ip() then
      set_wifi_mode(wifi.STATION)
      stop_timer("ap_policy_timer")
      return
    end

    ip_wait_ms = ip_wait_ms + AP_POLICY_POLL_MS
    if ip_wait_ms >= AP_IP_WAIT_MS then
      set_wifi_mode(wifi.STATIONAP)
      stop_timer("ap_policy_timer")
    else
      -- 网络初始化任务若稍晚写回 AP+STA，本轮会再次收敛到纯 STA。
      set_wifi_mode(wifi.STATION)
    end
  end)
end

local function schedule_anim_done(on_done)
  stop_timer("anim_timer")
  STATE.animating = true

  local t = tmr.create()
  STATE.anim_timer = t
  t:alarm(ANIM_MS + 30, tmr.ALARM_SINGLE, function(self)
    pcall(function()
      self:unregister()
    end)
    if STATE.anim_timer == self then
      STATE.anim_timer = nil
    end
    if on_done then
      on_done()
    end
    STATE.animating = false
  end)
end

local function create_icon_canvas(parent, w, h)
  local canvas_id = lv_canvas_create(parent, w, h, LV_IMG_CF_TRUE_COLOR)
  if not canvas_id or canvas_id <= 0 then return nil end
  lv_obj_clear_flag(canvas_id, LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_SCROLLABLE)
  safe_set_hidden(canvas_id, true)
  return canvas_id
end

local function ensure_slot_canvas(slot, w, h)
  if slot.canvas and slot.canvas > 0 and slot.canvas_w == w and slot.canvas_h == h then
    return true
  end
  if slot.canvas and slot.canvas > 0 then
    lv_obj_del(slot.canvas)
  end
  slot.canvas = create_icon_canvas(slot.box, w, h)
  slot.canvas_w, slot.canvas_h = w, h
  return slot.canvas ~= nil
end

local function icon_zoom(w, h)
  local zoom = math.floor(math.min(ICON_DRAW_SIZE * 256 / w, ICON_DRAW_SIZE * 256 / h))
  if zoom < 32 then return 32 end
  if zoom > 1024 then return 1024 end
  return zoom
end

local function set_icon(slot, item, dim)
  local path = display_icon_path(item)
  local app_id = text_or(item and item.id, "")
  local size = STATE.icon_sizes[app_id]
  local loaded = false
  style_icon_box(slot.box, dim)
  if path and path ~= "" and size and ensure_slot_canvas(slot, size.w, size.h) then
    local ok = pcall(function()
      lv_canvas_frame_begin(slot.canvas)
      lv_canvas_fill_bg(slot.canvas, 0x000000, 255)
      lv_canvas_draw_img(slot.canvas, 0, 0, path, 255)
      lv_canvas_frame_end(slot.canvas)
      lv_img_set_pivot(slot.canvas, math.floor(size.w / 2), math.floor(size.h / 2))
      lv_img_set_zoom(slot.canvas, icon_zoom(size.w, size.h))
    end)
    safe_set_hidden(slot.canvas, not ok)
    loaded = ok
  elseif slot.canvas then
    safe_set_hidden(slot.canvas, true)
  end
  if slot.canvas then
    lv_obj_set_style_img_opa(slot.canvas, dim and 128 or 255, LV_PART_MAIN)
    lv_obj_center(slot.canvas)
  end
  return loaded
end

local function item_at(index)
  local count = #STATE.apps
  if count <= 0 then return nil end
  while index < 1 do index = index + count end
  while index > count do index = index - count end
  return STATE.apps[index]
end

local function set_slot_content(slot, item, dim)
  local next_id = text_or(item and item.id, "")
  local reuse_pixels = next_id ~= "" and slot.item_id == next_id
  safe_set_text(slot.label, item and localized_app_name(item) or "")
  style_text(slot.label, dim and 0x808080 or 0xFFFFFF, UI_FONT, LV_TEXT_ALIGN_CENTER)
  if reuse_pixels then
    style_icon_box(slot.box, dim)
    if slot.canvas then
      lv_obj_set_style_img_opa(slot.canvas, dim and 128 or 255, LV_PART_MAIN)
    end
  else
    slot.item_id = set_icon(slot, item, dim) and next_id or ""
  end
end

local function set_slot_pos(slot, x)
  lv_obj_set_pos(slot.box, x, ICON_Y)
  lv_obj_set_pos(slot.label, x, ICON_Y + ICON_SIZE + LABEL_GAP)
end

local function style_slot(slot, dim)
  style_icon_box(slot.box, dim)
  style_text(slot.label, dim and 0x808080 or 0xFFFFFF, UI_FONT, LV_TEXT_ALIGN_CENTER)
  if slot.canvas then
    lv_obj_set_style_img_opa(slot.canvas, dim and 128 or 255, LV_PART_MAIN)
  end
end

local function anim_slot(slot, from_x, to_x)
  set_slot_pos(slot, from_x)
  local function anim_x(obj)
    local a = lv_anim_t()
    lv_anim_init(a)
    lv_anim_set_var(a, obj)
    lv_anim_set_exec_cb(a, lv_obj_set_x)
    lv_anim_set_values(a, from_x, to_x)
    lv_anim_set_time(a, ANIM_MS)
    lv_anim_set_path_cb(a, lv_anim_path_ease_out)
    lv_anim_start(a)
  end
  anim_x(slot.box)
  anim_x(slot.label)
end

local function render_initial()
  local count = #STATE.apps
  local center_item = current_item()

  if count <= 0 or not center_item then
    set_slot_content(UI.slots[1], nil, true)
    set_slot_content(UI.slots[2], { name = (UI_TEXT[LANGUAGE] or UI_TEXT.en).no_apps }, false)
    set_slot_content(UI.slots[3], nil, true)
    UI.left, UI.center, UI.right, UI.hidden = UI.slots[1], UI.slots[2], UI.slots[3], UI.slots[4]
    set_slot_pos(UI.left, LEFT_X)
    set_slot_pos(UI.center, CENTER_X)
    set_slot_pos(UI.right, RIGHT_X)
    set_slot_pos(UI.hidden, OFFSCREEN_RIGHT_X)
    STATE.animating = false
    return
  end

  UI.left, UI.center, UI.right, UI.hidden = UI.slots[1], UI.slots[2], UI.slots[3], UI.slots[4]
  set_slot_content(UI.left, count > 1 and item_at(STATE.index - 1) or nil, true)
  set_slot_content(UI.center, center_item, false)
  set_slot_content(UI.right, count > 1 and item_at(STATE.index + 1) or nil, true)
  set_slot_pos(UI.left, LEFT_X)
  set_slot_pos(UI.center, CENTER_X)
  set_slot_pos(UI.right, RIGHT_X)
  set_slot_pos(UI.hidden, OFFSCREEN_RIGHT_X)
  STATE.animating = false
end

local function show_initial_labels()
  if not UI.initial_labels_hidden then
    return
  end
  for _, slot in ipairs(UI.slots or {}) do
    safe_set_hidden(slot.label, false)
  end
  UI.initial_labels_hidden = false
end

local function start_slide(dir)
  local incoming = item_at(STATE.index + dir)
  local hidden = UI.hidden
  set_slot_content(hidden, incoming, true)

  if dir > 0 then
    style_slot(UI.left, true)
    style_slot(UI.center, true)
    style_slot(UI.right, false)
    style_slot(hidden, true)
    anim_slot(UI.left, LEFT_X, OFFSCREEN_LEFT_X)
    anim_slot(UI.center, CENTER_X, LEFT_X)
    anim_slot(UI.right, RIGHT_X, CENTER_X)
    anim_slot(hidden, OFFSCREEN_RIGHT_X, RIGHT_X)
    schedule_anim_done(function()
      UI.left, UI.center, UI.right, UI.hidden = UI.center, UI.right, hidden, UI.left
    end)
  else
    style_slot(hidden, true)
    style_slot(UI.left, false)
    style_slot(UI.center, true)
    style_slot(UI.right, true)
    anim_slot(hidden, OFFSCREEN_LEFT_X, LEFT_X)
    anim_slot(UI.left, LEFT_X, CENTER_X)
    anim_slot(UI.center, CENTER_X, RIGHT_X)
    anim_slot(UI.right, RIGHT_X, OFFSCREEN_RIGHT_X)
    schedule_anim_done(function()
      UI.left, UI.center, UI.right, UI.hidden = hidden, UI.left, UI.center, UI.right
    end)
  end
end

local function app_list_signature(list)
  local ids = {}
  for _, item in ipairs(list or {}) do
    ids[#ids + 1] = text_or(item and item.id, "")
  end
  table.sort(ids)
  return table.concat(ids, "\n")
end

local function load_apps(list)
  STATE.icon_sizes = {}
  list = type(list) == "table" and list or (app.list() or {})
  STATE.app_list_signature = app_list_signature(list)
  local visible = {}
  for _, item in ipairs(list) do
    if has_display_icon(item) then
      visible[#visible + 1] = item
    end
  end
  STATE.apps = visible
  clamp_index()
  render_initial()
  show_initial_labels()
end

local function start_app_list_watch()
  if not tmr or not tmr.create then
    return
  end
  local t = tmr.create()
  STATE.app_list_timer = t
  t:alarm(APP_LIST_POLL_MS, tmr.ALARM_AUTO, function()
    if STATE.animating then
      return
    end
    local ok, list = pcall(function() return app.list() end)
    if ok and type(list) == "table"
      and app_list_signature(list) ~= STATE.app_list_signature then
      load_apps(list)
    end
  end)
end

local function schedule_reload(delay_ms)
  stop_timer("reload_timer")

  local t = tmr.create()
  STATE.reload_timer = t
  t:alarm(delay_ms or 240, tmr.ALARM_SINGLE, function(self)
    pcall(function()
      self:unregister()
    end)
    if STATE.reload_timer == self then
      STATE.reload_timer = nil
    end
    load_apps()
  end)
end

local function move(delta)
  if #STATE.apps <= 0 or STATE.animating then
    return
  end
  STATE.index = STATE.index + delta
  clamp_index()
  if #STATE.apps < 2 then
    render_initial()
  else
    start_slide(delta)
  end
end

local launch_item

local function launch_current()
  local item = current_item()
  launch_item(item)
end

launch_item = function(item)
  if not item then
    return
  end

  -- 用户在启动判定完成前进入应用时，优先保留可恢复的网络入口。
  if STATE.ap_policy_timer then
    if AP_PREFERRED_ENABLED or not station_ip() then
      set_wifi_mode(wifi.STATIONAP)
    else
      set_wifi_mode(wifi.STATION)
    end
    stop_timer("ap_policy_timer")
  end

  local ok, err = app.launch(item.id)
  if not ok then
    print("launch failed:", text_or(err, "unknown"))
  end
end

local function boot_millis()
  local fn = rawget(_G, "millis")
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn)
  if not ok then
    return nil
  end
  return tonumber(value)
end

local function autostart_marker_exists()
  return path_exists(AUTOSTART_MARK_PATH)
end

local function mark_autostart_fired()
  if not file or not file.open then
    return
  end
  local fd = file.open(AUTOSTART_MARK_PATH, "w")
  if not fd then
    return
  end
  fd:write("app_id=" .. AUTOSTART_APP_ID .. "\n")
  fd:write("ms=" .. tostring(boot_millis() or "") .. "\n")
  fd:close()
end

local function should_autostart()
  local ms = boot_millis()
  return AUTOSTART_ENABLED
    and AUTOSTART_APP_ID ~= ""
    and not autostart_marker_exists()
    and ms ~= nil
    and ms >= 0
    and ms <= AUTOSTART_BOOT_WINDOW_MS
end

local function autostart_candidate(item)
  local id = text_or(item and item.id, "")
  if id == "" or id ~= AUTOSTART_APP_ID or id == "launcher" then
    return false
  end
  local kind = tostring(item.kind or ""):lower()
  return kind ~= "service"
end

local function find_autostart_app()
  local list = {}
  if app and app.list then
    list = app.list() or {}
  else
    list = STATE.apps
  end
  for _, item in ipairs(list) do
    if autostart_candidate(item) then
      return item
    end
  end
  return nil
end

local function run_autostart(skip_boot_window_check)
  if STATE.autostart_fired then
    return
  end
  if not skip_boot_window_check and not should_autostart() then
    return
  end
  STATE.autostart_fired = true
  local item = find_autostart_app()
  if not item then
    print("[launcher] autostart app not found:", AUTOSTART_APP_ID)
    return
  end
  mark_autostart_fired()
  launch_item(item)
end

local function schedule_autostart()
  if not should_autostart() then
    return
  end
  if not tmr or not tmr.create then
    run_autostart(true)
    return
  end
  local t = tmr.create()
  t:alarm(AUTOSTART_DELAY_MS, tmr.ALARM_SINGLE, function(self)
    pcall(function()
      self:unregister()
    end)
    run_autostart(true)
  end)
end

local function rescan_apps()
  local ok, err = app.rescan()
  if not ok then
    print("rescan failed:", text_or(err, "unknown"))
    return
  end
  -- 等待 AppManager 重扫完成，再按固定 SD 路径重新解码可见图标。
  schedule_reload(320)
end

local function build_ui()
  UI.bg = lv_obj_create(root)
  lv_obj_set_pos(UI.bg, 0, 0)
  lv_obj_set_size(UI.bg, SCREEN_W, SCREEN_H)
  style_panel(UI.bg, 0x000000, 255, 0, 0, 0x000000, 0)

  UI.slots = {}
  UI.initial_labels_hidden = true
  for i = 1, 4 do
    local slot = {}
    slot.box = lv_obj_create(root)
    lv_obj_set_size(slot.box, ICON_SIZE, ICON_SIZE)
    lv_obj_clear_flag(slot.box, LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_SCROLLABLE)
    slot.canvas = create_icon_canvas(slot.box, ICON_CANVAS_SIZE, ICON_CANVAS_SIZE)
    if not slot.canvas then error("launcher: icon canvas create failed") end
    slot.canvas_w, slot.canvas_h = ICON_CANVAS_SIZE, ICON_CANVAS_SIZE
    slot.label = lv_label_create(root)
    safe_set_hidden(slot.label, true)
    lv_obj_set_size(slot.label, ICON_SIZE, LABEL_H)
    lv_label_set_long_mode(slot.label, LV_LABEL_LONG_CLIP)
    style_text(slot.label, 0x808080, UI_FONT, LV_TEXT_ALIGN_CENTER)
    UI.slots[i] = slot
  end
end

build_ui()
load_apps()
start_app_list_watch()
apply_timezone()
sync_ntp_once()
start_display_schedule_service()
start_ap_policy()
schedule_autostart()

key.on(key.LEFT, function(evt_type, ts_ms)
  if evt_type == key.START then
    move(-1)
  elseif evt_type == key.LONG_START then
    STATE.repeat_left = 0
    move(-1)
  elseif evt_type == key.LONG_REPEAT then
    STATE.repeat_left = STATE.repeat_left + 1
    if (STATE.repeat_left % 3) == 0 then
      move(-1)
    end
  elseif evt_type == key.LONG_END then
    STATE.repeat_left = 0
  end
end)

key.on(key.RIGHT, function(evt_type, ts_ms)
  if evt_type == key.START then
    move(1)
  elseif evt_type == key.LONG_START then
    STATE.repeat_right = 0
    move(1)
  elseif evt_type == key.LONG_REPEAT then
    STATE.repeat_right = STATE.repeat_right + 1
    if (STATE.repeat_right % 3) == 0 then
      move(1)
    end
  elseif evt_type == key.LONG_END then
    STATE.repeat_right = 0
  end
end)

key.on(key.UP, function(evt_type, ts_ms)
  if evt_type == key.LONG_START then
    STATE.repeat_up = 0
    STATE.up_launch_fired = false
  elseif evt_type == key.LONG_REPEAT then
    STATE.repeat_up = STATE.repeat_up + 1
    if STATE.repeat_up >= 1 and not STATE.up_launch_fired then
      STATE.up_launch_fired = true
      launch_current()
    end
  elseif evt_type == key.LONG_END then
    STATE.repeat_up = 0
    STATE.up_launch_fired = false
  end
end)

key.on(key.DOWN, function(evt_type, ts_ms)
  if evt_type == key.SHORT then
    load_apps()
  elseif evt_type == key.LONG_START then
    rescan_apps()
  end
end)

-- BLE 手柄：方向键选择，A/Menu 启动；Select/Home 在桌面不处理。
local PAD_UP, PAD_DOWN, PAD_LEFT, PAD_RIGHT = 1, 2, 4, 8
local PAD_A, PAD_MENU = 16, 8192
if controller and controller.state and tmr and tmr.create then
  STATE.controller_timer = tmr.create()
  STATE.controller_timer:alarm(40, tmr.ALARM_AUTO, function()
    local ok, pad = pcall(function() return controller.state("ble-main") end)
    local buttons = ok and type(pad) == "table" and tonumber(pad.buttons) or 0
    buttons = buttons or 0
    local pressed = buttons & (~STATE.controller_buttons)
    STATE.controller_buttons = buttons
    if (pressed & (PAD_LEFT | PAD_UP)) ~= 0 then
      move(-1)
    elseif (pressed & (PAD_RIGHT | PAD_DOWN)) ~= 0 then
      move(1)
    elseif (pressed & (PAD_A | PAD_MENU)) ~= 0 then
      launch_current()
    end
    -- PAD_SELECT / PAD_HOME intentionally do nothing in Launcher.
  end)
end
