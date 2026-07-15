
local SCREEN_W = 320
local SCREEN_H = 240
local ICON_SIZE = 84
local ICON_DRAW_SIZE = 75
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
local AUTOSTART_MARK_PATH = "/tmp/launcher_autostart_fired"
local DEFAULT_AUTOSTART_APP_ID = "wifi_guide"
local DISPLAY_SERVICE_ID = "display_service"

local function normalize_language(value)
  local text = tostring(value or ""):gsub("_", "-")
  if text == "en" or text:match("^en%-") then return "en" end
  if text == "ja" or text:match("^ja%-") then return "ja" end
  if text == "zh-TW" or text == "zh-Hant" or text:match("^zh%-Hant") or text:match("^zh%-HK") then return "zh-TW" end
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

local SETTINGS = read_settings()
local LANGUAGE = normalize_language(SETTINGS.language or SETTINGS.locale or SETTINGS.lang)
local AP_PREFERRED_ENABLED = setting_bool(SETTINGS.ap_enabled, true)
local AUTOSTART_ENABLED = setting_bool(SETTINGS.autostart_enabled, true)
local AUTOSTART_APP_ID = tostring(SETTINGS.autostart_app_id or DEFAULT_AUTOSTART_APP_ID)
local UI_TEXT = {
  ["zh-CN"] = { no_apps = "暂无应用", loading = "正在启动" },
  en = { no_apps = "NO APPS", loading = "Starting" },
  ja = { no_apps = "アプリなし", loading = "起動中" },
  ["zh-TW"] = { no_apps = "暫無應用", loading = "正在啟動" },
}

local UI_FONT_PATHS = {
  ["zh-CN"] = "/sd/apps/launcher/font/launcher_ui_zh_cn_16.bin",
  ja = "/sd/apps/launcher/font/launcher_ui_ja_16.bin",
  ["zh-TW"] = "/sd/apps/launcher/font/launcher_ui_zh_tw_16.bin",
}

local root = lv_scr_act()
lv_obj_clean(lv_scr_act())
if rawget(_G, "LAUNCHER_UI_FONT_HANDLE") and lv_font_free then
  pcall(function() lv_font_free(_G.LAUNCHER_UI_FONT_HANDLE) end)
end
_G.LAUNCHER_UI_FONT_HANDLE = nil

-- 先让轻量启动页完成一次刷新，再加载当前语言的大字库。
local splash_bg = lv_obj_create(root)
lv_obj_set_pos(splash_bg, 0, 0)
lv_obj_set_size(splash_bg, SCREEN_W, SCREEN_H)
lv_obj_set_style_bg_color(splash_bg, 0x000000, LV_PART_MAIN)
lv_obj_set_style_bg_opa(splash_bg, 255, LV_PART_MAIN)
lv_obj_set_style_border_width(splash_bg, 0, LV_PART_MAIN)
local splash_label = lv_label_create(root)
lv_label_set_text(splash_label, "Launcher")
lv_obj_set_style_text_color(splash_label, 0xFFFFFF, LV_PART_MAIN)
lv_obj_set_style_text_font(splash_label, LV_FONT_MONTSERRAT_16, LV_PART_MAIN)
lv_obj_center(splash_label)
if lv_refr_now then
  pcall(function() lv_refr_now(nil) end)
elseif lv_timer_handler then
  pcall(lv_timer_handler)
elseif lv_task_handler then
  pcall(lv_task_handler)
end

local UI_FONT = LV_FONT_MONTSERRAT_16
local UI_FONT_HANDLE = nil
local ui_font_path = UI_FONT_PATHS[LANGUAGE]
if ui_font_path and lv_font_load then
  local ok, handle = pcall(function() return lv_font_load(ui_font_path) end)
  if ok and type(handle) == "number" and handle > 0 then
    UI_FONT = handle
    UI_FONT_HANDLE = handle
    _G.LAUNCHER_UI_FONT_HANDLE = handle
  end
end
lv_obj_clean(root)

local STATE = {
  apps = {},
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
}

local UI = {}
local ICON_META_CACHE = {}

local function text_or(value, fallback)
  if value == nil or value == "" then
    return fallback or ""
  end
  return tostring(value)
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

local function start_display_service()
  if not app or not app.start_service then
    return
  end
  pcall(function()
    app.start_service(DISPLAY_SERVICE_ID)
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

local function app_icon(item)
  if not item or not item.icon or item.icon == "" then
    return nil
  end
  return item.icon
end

local function path_ext(path)
  local ext = text_or(path, ""):match("(%.[^./\\]+)$")
  if not ext then
    return ""
  end
  return string.lower(ext)
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

local function fallback_sd_icon_path(item, preferred_ext)
  if text_or(item and item.source, "") ~= "sd" then
    return nil
  end

  local app_id = text_or(item and item.id, "")
  if app_id == "" then
    return nil
  end

  local png_path = "/sd/apps/" .. app_id .. "/main.png"
  local bmp_path = "/sd/apps/" .. app_id .. "/main.bmp"
  local ext = path_ext(preferred_ext)

  if ext == ".bmp" then
    if path_exists(bmp_path) then
      return bmp_path
    end
    if path_exists(png_path) then
      return png_path
    end
    return nil
  end

  if path_exists(png_path) then
    return png_path
  end
  if path_exists(bmp_path) then
    return bmp_path
  end
  return nil
end

local function normalize_icon_fs_path(path)
  local src = text_or(path, "")
  if src == "" then
    return nil
  end
  if src:sub(1, 3) == "S:/" then
    return src:sub(3)
  end
  if src:sub(1, 1) == "/" then
    return src
  end
  return nil
end

local function read_le_u16(data, index)
  local b1, b2 = string.byte(data, index, index + 1)
  if not b1 or not b2 then
    return nil
  end
  return b1 + b2 * 256
end

local function read_le_u32(data, index)
  local b1, b2, b3, b4 = string.byte(data, index, index + 3)
  if not b1 or not b2 or not b3 or not b4 then
    return nil
  end
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function read_be_u32(data, index)
  local b1, b2, b3, b4 = string.byte(data, index, index + 3)
  if not b1 or not b2 or not b3 or not b4 then
    return nil
  end
  return ((b1 * 256 + b2) * 256 + b3) * 256 + b4
end

local function read_bmp_size(path)
  local fd = file and file.open and file.open(path, "r")
  if not fd then
    return nil
  end

  local header = fd:read(30)
  fd:close()
  if not header or #header < 26 then
    return nil
  end
  if header:sub(1, 2) ~= "BM" then
    return nil
  end

  local dib_size = read_le_u32(header, 15)
  if dib_size == 12 then
    local w = read_le_u16(header, 19)
    local h = read_le_u16(header, 21)
    if w and h and w > 0 and h > 0 then
      return { w = w, h = h }
    end
    return nil
  end

  local w = read_le_u32(header, 19)
  local h = read_le_u32(header, 23)
  if not w or not h or w == 0 or h == 0 then
    return nil
  end
  if h > 2147483647 then
    h = 4294967296 - h
  end
  if h < 0 then
    h = -h
  end
  return { w = w, h = h }
end

local function read_png_size(path)
  local fd = file and file.open and file.open(path, "r")
  if not fd then
    return nil
  end

  local header = fd:read(24)
  fd:close()
  if not header or #header < 24 then
    return nil
  end

  local sig = string.char(137, 80, 78, 71, 13, 10, 26, 10)
  if header:sub(1, 8) ~= sig then
    return nil
  end
  if header:sub(13, 16) ~= "IHDR" then
    return nil
  end

  local w = read_be_u32(header, 17)
  local h = read_be_u32(header, 21)
  if not w or not h or w <= 0 or h <= 0 then
    return nil
  end
  return { w = w, h = h }
end

local function read_image_size(path)
  local ext = path_ext(path)
  if ext == ".png" then
    return read_png_size(path) or read_bmp_size(path)
  end
  if ext == ".bmp" then
    return read_bmp_size(path) or read_png_size(path)
  end
  return read_png_size(path) or read_bmp_size(path)
end

local function resolve_icon_probe_path(item, path)
  local fs_path = normalize_icon_fs_path(path)
  if fs_path then
    return fs_path
  end
  return fallback_sd_icon_path(item, path_ext(path))
end

local function icon_meta(item, path)
  local cache_key = text_or(path, "")
  if cache_key == "" then
    return nil
  end

  local cached = ICON_META_CACHE[cache_key]
  if cached ~= nil then
    return cached or nil
  end

  local meta = read_image_size(resolve_icon_probe_path(item, path))
  ICON_META_CACHE[cache_key] = meta or false
  return meta
end

local function display_icon_path(item)
  return app_icon(item) or fallback_sd_icon_path(item, ".png")
end

local function has_display_icon(item)
  local path = display_icon_path(item)
  if not path or path == "" then
    return false
  end
  return icon_meta(item, path) ~= nil
end

local function fit_zoom(meta, target_size, dim)
  if not meta or not meta.w or not meta.h or meta.w <= 0 or meta.h <= 0 then
    return 256
  end

  local zoom_w = math.floor((target_size * 256) / meta.w)
  local zoom_h = math.floor((target_size * 256) / meta.h)
  local zoom = math.min(zoom_w, zoom_h)
  local max_zoom = dim and 288 or 320
  if zoom < 32 then
    zoom = 32
  elseif zoom > max_zoom then
    zoom = max_zoom
  end
  return zoom
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

local function schedule_anim_done()
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
    STATE.animating = false
  end)
end

local function set_icon(box_id, img_id, item, dim)
  local path = display_icon_path(item)
  style_icon_box(box_id, dim and true or false)
  if path and path ~= "" then
    local ok = pcall(function()
      local meta = icon_meta(item, path)
      local zoom = fit_zoom(meta, ICON_DRAW_SIZE, dim)
      lv_img_set_src(img_id, path)
      lv_img_set_size_mode(img_id, LV_IMG_SIZE_MODE_REAL)
      lv_obj_set_size(img_id, LV_SIZE_CONTENT, LV_SIZE_CONTENT)
      lv_img_set_zoom(img_id, zoom)
    end)
    safe_set_hidden(img_id, not ok)
  else
    safe_set_hidden(img_id, true)
  end
  lv_obj_set_style_img_opa(img_id, dim and 128 or 255, LV_PART_MAIN)
  lv_obj_center(img_id)
end

local function set_triplet_content(left_item, center_item, right_item)
  safe_set_text(UI.left_label, left_item and text_or(left_item.name, left_item.id) or "")
  safe_set_text(UI.center_label, center_item and text_or(center_item.name, center_item.id) or "")
  safe_set_text(UI.right_label, right_item and text_or(right_item.name, right_item.id) or "")

  set_icon(UI.left_icon, UI.left_img, left_item, true)
  set_icon(UI.center_icon, UI.center_img, center_item, false)
  set_icon(UI.right_icon, UI.right_img, right_item, true)
end

local function set_static_positions()
  lv_obj_set_pos(UI.left_icon, LEFT_X, ICON_Y)
  lv_obj_set_pos(UI.left_label, LEFT_X, ICON_Y + ICON_SIZE + LABEL_GAP)
  lv_obj_set_pos(UI.center_icon, CENTER_X, ICON_Y)
  lv_obj_set_pos(UI.center_label, CENTER_X, ICON_Y + ICON_SIZE + LABEL_GAP)
  lv_obj_set_pos(UI.right_icon, RIGHT_X, ICON_Y)
  lv_obj_set_pos(UI.right_label, RIGHT_X, ICON_Y + ICON_SIZE + LABEL_GAP)
end

local function start_slide(dir)
  local left_start_x = 0
  local center_start_x = 0
  local right_start_x = 0

  if dir < 0 then
    left_start_x = OFFSCREEN_LEFT_X
    center_start_x = LEFT_X
    right_start_x = CENTER_X
  else
    left_start_x = CENTER_X
    center_start_x = RIGHT_X
    right_start_x = OFFSCREEN_RIGHT_X
  end

  lv_obj_set_pos(UI.left_icon, left_start_x, ICON_Y)
  lv_obj_set_pos(UI.left_label, left_start_x, ICON_Y + ICON_SIZE + LABEL_GAP)
  lv_obj_set_pos(UI.center_icon, center_start_x, ICON_Y)
  lv_obj_set_pos(UI.center_label, center_start_x, ICON_Y + ICON_SIZE + LABEL_GAP)
  lv_obj_set_pos(UI.right_icon, right_start_x, ICON_Y)
  lv_obj_set_pos(UI.right_label, right_start_x, ICON_Y + ICON_SIZE + LABEL_GAP)

  local function anim_x(obj, from_x, to_x)
    local a = lv_anim_t()
    lv_anim_init(a)
    lv_anim_set_var(a, obj)
    lv_anim_set_exec_cb(a, lv_obj_set_x)
    lv_anim_set_values(a, from_x, to_x)
    lv_anim_set_time(a, ANIM_MS)
    lv_anim_set_path_cb(a, lv_anim_path_ease_out)
    lv_anim_start(a)
  end

  anim_x(UI.left_icon, left_start_x, LEFT_X)
  anim_x(UI.left_label, left_start_x, LEFT_X)
  anim_x(UI.center_icon, center_start_x, CENTER_X)
  anim_x(UI.center_label, center_start_x, CENTER_X)
  anim_x(UI.right_icon, right_start_x, RIGHT_X)
  anim_x(UI.right_label, right_start_x, RIGHT_X)
  schedule_anim_done()
end

local function render(dir)
  local count = #STATE.apps
  local center_item = current_item()

  if count <= 0 or not center_item then
    set_triplet_content(nil, { name = (UI_TEXT[LANGUAGE] or UI_TEXT.en).no_apps }, nil)
    set_static_positions()
    STATE.animating = false
    return
  end

  local left_index = STATE.index - 1
  if left_index < 1 then
    left_index = count
  end

  local right_index = STATE.index + 1
  if right_index > count then
    right_index = 1
  end

  local left_item = count > 1 and STATE.apps[left_index] or nil
  local right_item = count > 1 and STATE.apps[right_index] or nil
  set_triplet_content(left_item, center_item, right_item)

  if dir == nil or dir == 0 or count < 2 then
    set_static_positions()
    STATE.animating = false
  else
    start_slide(dir)
  end
end

local function load_apps(dir)
  local list = app.list() or {}
  local visible = {}
  for _, item in ipairs(list) do
    if has_display_icon(item) then
      visible[#visible + 1] = item
    end
  end
  STATE.apps = visible
  clamp_index()
  render(dir)
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
    load_apps(0)
  end)
end

local function move(delta)
  if #STATE.apps <= 0 or STATE.animating then
    return
  end
  STATE.index = STATE.index + delta
  clamp_index()
  render(delta)
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
  -- 重扫会重建图标源，延后一拍再重绑，避免内置/SD 图标在同帧刷新时短暂失效。
  schedule_reload(320)
end

local function build_ui()
  UI.bg = lv_obj_create(root)
  lv_obj_set_pos(UI.bg, 0, 0)
  lv_obj_set_size(UI.bg, SCREEN_W, SCREEN_H)
  style_panel(UI.bg, 0x000000, 255, 0, 0, 0x000000, 0)

  UI.center_icon = lv_obj_create(root)
  lv_obj_set_size(UI.center_icon, ICON_SIZE, ICON_SIZE)
  lv_obj_set_pos(UI.center_icon, CENTER_X, ICON_Y)
  UI.center_img = lv_img_create(UI.center_icon)
  safe_set_hidden(UI.center_img, true)

  UI.center_label = lv_label_create(root)
  lv_obj_set_size(UI.center_label, ICON_SIZE, LABEL_H)
  lv_obj_set_pos(UI.center_label, CENTER_X, ICON_Y + ICON_SIZE + LABEL_GAP)
  lv_label_set_long_mode(UI.center_label, LV_LABEL_LONG_CLIP)
  style_text(UI.center_label, 0xFFFFFF, UI_FONT, LV_TEXT_ALIGN_CENTER)

  UI.left_icon = lv_obj_create(root)
  lv_obj_set_size(UI.left_icon, ICON_SIZE, ICON_SIZE)
  lv_obj_set_pos(UI.left_icon, LEFT_X, ICON_Y)
  UI.left_img = lv_img_create(UI.left_icon)
  safe_set_hidden(UI.left_img, true)

  UI.left_label = lv_label_create(root)
  lv_obj_set_size(UI.left_label, ICON_SIZE, LABEL_H)
  lv_obj_set_pos(UI.left_label, LEFT_X, ICON_Y + ICON_SIZE + LABEL_GAP)
  lv_label_set_long_mode(UI.left_label, LV_LABEL_LONG_CLIP)
  style_text(UI.left_label, 0x808080, UI_FONT, LV_TEXT_ALIGN_CENTER)

  UI.right_icon = lv_obj_create(root)
  lv_obj_set_size(UI.right_icon, ICON_SIZE, ICON_SIZE)
  lv_obj_set_pos(UI.right_icon, RIGHT_X, ICON_Y)
  UI.right_img = lv_img_create(UI.right_icon)
  safe_set_hidden(UI.right_img, true)

  UI.right_label = lv_label_create(root)
  lv_obj_set_size(UI.right_label, ICON_SIZE, LABEL_H)
  lv_obj_set_pos(UI.right_label, RIGHT_X, ICON_Y + ICON_SIZE + LABEL_GAP)
  lv_label_set_long_mode(UI.right_label, LV_LABEL_LONG_CLIP)
  style_text(UI.right_label, 0x808080, UI_FONT, LV_TEXT_ALIGN_CENTER)
end

build_ui()
load_apps(0)
sync_ntp_once()
start_display_service()
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
    rescan_apps()
  end
end)
