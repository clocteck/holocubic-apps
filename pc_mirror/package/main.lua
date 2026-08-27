-- PC Mirror 0.0.1
-- Based on clocteck/desktop-mirror commit 7ae2816a7a151e935d226bc1de7deb00e0233da5.
-- Modified 2026-08-27: packaged as pc_mirror with localized metadata, new artwork,
-- documentation, dynamic app paths, and lifecycle/display safeguards.
-- SPDX-License-Identifier: GPL-3.0-only

local prev = rawget(_G, "PC_MIRROR_APP")
if prev and prev.shutdown then
  pcall(function()
    prev.shutdown()
  end)
end

PC_MIRROR_APP = {}
local APP = PC_MIRROR_APP

local MAIN_STYLE = 0
if LV_PART_MAIN and LV_STATE_DEFAULT then
  MAIN_STYLE = LV_PART_MAIN | LV_STATE_DEFAULT
end

local SCREEN_W = 320
local SCREEN_H = 240
local MAGIC_D = 68
local MAGIC_M = 77
local MAGIC_J = 74
local MAGIC_1 = 49

local DEFAULT_APP_DIR = "/sd/apps/pc_mirror"

local function resolve_app_dir()
  if app and app.current then
    local ok, current = pcall(function()
      return app.current()
    end)
    if ok and type(current) == "table" and type(current.entry) == "string" then
      local normalized = current.entry:gsub("\\", "/")
      local dir = normalized:match("^(.*)/[^/]+$")
      if dir and dir ~= "" then
        return dir
      end
    end
  end
  return DEFAULT_APP_DIR
end

local function resolve_route_base()
  if app and app.route_base then
    local ok, route = pcall(function()
      return app.route_base()
    end)
    if ok and type(route) == "string" and route ~= "" and route ~= "/" then
      route = route:gsub("/+$", "")
      if route:sub(1, 1) ~= "/" then
        route = "/" .. route
      end
      return route
    end
  end
  return "/pc_mirror"
end

APP.url = "ws://192.168.0.80:8787"
APP.app_dir = resolve_app_dir()
APP.config_path = APP.app_dir .. "/config.json"
APP.route_base = resolve_route_base()
APP.web_routes = {}
APP.web_started = false
APP.ws_buffer = 8192
APP.serial_debug = true
APP.serial_debug_every = 1
APP.serial_debug_interval_ms = 5000
APP.last_debug_ms = 0
APP.overlay = false
APP.paused = false
APP.connected = false
APP.connecting = false
APP.frame_count = 0
APP.byte_count = 0
APP.rx_count = 0
APP.rx_binary_count = 0
APP.rx_ignored_count = 0
APP.last_frame_id = 0
APP.has_frame_id = false
APP.drop_count = 0
APP.out_of_order_count = 0
APP.last_rx_ms = 0
APP.last_error = ""
APP.last_error_log_ms = 0
APP.ws = nil
APP.ws_generation = 0
APP.reconnect_timer = nil
APP.stat_timer = nil
APP.shutting_down = false
APP.ever_received_frame = false
APP.image_refs = {}
APP.image_ref_index = 0
APP.ui = {}
APP.stat = {
  fps = 0,
  kbps = 0,
  frames = 0,
  bytes = 0,
  last_ms = 0,
}

local function now_ms()
  if millis then
    return millis() or 0
  end
  return 0
end

local function elapsed_ms(start_ms)
  local n = now_ms()
  if n >= start_ms then
    return n - start_ms
  end
  return 0
end

local function u16le(s, i)
  local b1, b2 = string.byte(s, i, i + 1)
  if not b2 then
    return 0
  end
  return b1 + b2 * 256
end

local function u32le(s, i)
  local b1, b2, b3, b4 = string.byte(s, i, i + 3)
  if not b4 then
    return 0
  end
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function device_ip()
  local candidates = {
    function()
      if wifi and wifi.sta and wifi.sta.getip then return wifi.sta.getip() end
    end,
    function()
      if wifi and wifi.sta and wifi.sta.ip then return wifi.sta.ip() end
    end,
    function()
      if net and net.getifaddr then return net.getifaddr() end
    end,
  }
  for _, getter in ipairs(candidates) do
    local ok, value = pcall(getter)
    if ok and type(value) == "string" and value:match("^%d+%.%d+%.%d+%.%d+$") and value ~= "0.0.0.0" then
      return value
    end
  end
  return nil
end

local function setup_page_url()
  local ip = device_ip()
  if ip then
    return "http://" .. ip .. APP.route_base
  end
  return "http://<device-ip>" .. APP.route_base
end

local function guide_url_text()
  return "STREAM  " .. APP.url .. "\nSETUP   " .. setup_page_url()
end

local function load_config()
  if not file or not file.getcontents then
    return false
  end

  local ok, raw = pcall(function()
    return file.getcontents(APP.config_path)
  end)
  if not ok or type(raw) ~= "string" then
    return false
  end

  local url = raw:match('"url"%s*:%s*"([^"]+)"')
  if url and url:match("^wss?://") then
    APP.url = url
  end

  local serial_flag = raw:match('"serial_debug"%s*:%s*(%a+)')
  if serial_flag == "false" then
    APP.serial_debug = false
  elseif serial_flag == "true" then
    APP.serial_debug = true
  end

  local overlay_flag = raw:match('"overlay"%s*:%s*(%a+)')
  if overlay_flag == "false" then
    APP.overlay = false
  elseif overlay_flag == "true" then
    APP.overlay = true
  end

  local every = tonumber(raw:match('"serial_debug_every"%s*:%s*(%d+)') or "")
  if every and every >= 1 then
    APP.serial_debug_every = math.min(1000, math.floor(every))
  end

  local interval = tonumber(raw:match('"serial_debug_interval_ms"%s*:%s*(%d+)') or "")
  if interval and interval >= 100 then
    APP.serial_debug_interval_ms = math.min(60000, math.floor(interval))
  end

  local ws_buffer = tonumber(raw:match('"ws_buffer"%s*:%s*(%d+)') or "")
  if ws_buffer and ws_buffer >= 8192 then
    APP.ws_buffer = math.min(65536, math.floor(ws_buffer))
  end

  if APP.ui.url then
    pcall(function()
      lv_label_set_text(APP.ui.url, guide_url_text())
    end)
  end
  return true
end

local function set_status(text)
  if APP.ui.status then
    lv_label_set_text(APP.ui.status, text or "")
  end
end

local function update_status()
  local text = "OFFLINE"
  if APP.paused then
    text = "PAUSED"
  elseif APP.connected then
    text = "CONNECTED"
  elseif APP.connecting then
    text = "CONNECTING"
  end
  set_status(text)
  if APP.ui.guide_status then
    pcall(function()
      lv_label_set_text(APP.ui.guide_status, text)
    end)
  end
end

local function set_obj_hidden(id, hidden)
  if not id or not lv_obj_add_flag or not lv_obj_clear_flag or not LV_OBJ_FLAG_HIDDEN then
    return
  end

  if hidden then
    lv_obj_add_flag(id, LV_OBJ_FLAG_HIDDEN)
  else
    lv_obj_clear_flag(id, LV_OBJ_FLAG_HIDDEN)
  end
end

local function update_overlay_visible()
  set_obj_hidden(APP.ui.panel, not APP.overlay)
  set_obj_hidden(APP.ui.guide, APP.ever_received_frame)
  update_status()
end

local function log_error(text)
  APP.last_error = tostring(text or "")
  if not APP.serial_debug then
    return
  end
  if APP.last_error_log_ms == 0 or elapsed_ms(APP.last_error_log_ms) >= 1000 then
    APP.last_error_log_ms = now_ms()
    print("[pc-mirror] " .. APP.last_error)
  end
end

local function is_binary_opcode(opcode)
  local binary_opcode = websocket and websocket.BINARY or 2
  return opcode == binary_opcode or opcode == 2
end

local function log_receive(data, opcode)
  APP.rx_count = APP.rx_count + 1
  local is_binary = is_binary_opcode(opcode)
  if is_binary then
    APP.rx_binary_count = APP.rx_binary_count + 1
  else
    APP.rx_ignored_count = APP.rx_ignored_count + 1
  end

  if not APP.serial_debug then
    return
  end
  if APP.rx_count ~= 1 and (APP.rx_count % 120) ~= 0 and is_binary then
    return
  end
  if APP.rx_ignored_count > 8 and not is_binary then
    return
  end

  local len = type(data) == "string" and #data or 0
  local b1, b2, b3, b4 = 0, 0, 0, 0
  if len >= 4 then
    b1, b2, b3, b4 = string.byte(data, 1, 4)
  end
  print(string.format(
    "[pc-mirror] rx=%d bin=%d ignored=%d opcode=%s len=%d magic=%02X %02X %02X %02X",
    APP.rx_count,
    APP.rx_binary_count,
    APP.rx_ignored_count,
    tostring(opcode),
    len,
    b1 or 0,
    b2 or 0,
    b3 or 0,
    b4 or 0
  ))
end

local function style_plain_panel(id, color, opa)
  lv_obj_set_style_bg_color(id, color, MAIN_STYLE)
  lv_obj_set_style_bg_opa(id, opa, MAIN_STYLE)
  lv_obj_set_style_border_width(id, 0, MAIN_STYLE)
  lv_obj_set_style_radius(id, 0, MAIN_STYLE)
  lv_obj_set_style_pad_all(id, 0, MAIN_STYLE)
end

local function build_ui()
  local root = lv_scr_act()
  lv_clear()

  local bg = lv_obj_create(root)
  lv_obj_set_pos(bg, 0, 0)
  lv_obj_set_size(bg, SCREEN_W, SCREEN_H)
  style_plain_panel(bg, 0x000000, 255)

  APP.ui.img = lv_img_create(root)
  lv_obj_set_pos(APP.ui.img, 0, 0)
  if lv_img_set_antialias then
    pcall(function()
      lv_img_set_antialias(APP.ui.img, false)
    end)
  end

  APP.ui.guide = lv_obj_create(root)
  lv_obj_set_pos(APP.ui.guide, 12, 42)
  lv_obj_set_size(APP.ui.guide, 296, 156)
  style_plain_panel(APP.ui.guide, 0x0B1220, 255)
  lv_obj_set_style_radius(APP.ui.guide, 12, MAIN_STYLE)
  lv_obj_set_style_border_width(APP.ui.guide, 1, MAIN_STYLE)
  lv_obj_set_style_border_color(APP.ui.guide, 0x334155, MAIN_STYLE)
  lv_obj_set_style_border_opa(APP.ui.guide, 220, MAIN_STYLE)

  APP.ui.guide_title = lv_label_create(APP.ui.guide)
  lv_obj_set_pos(APP.ui.guide_title, 14, 15)
  lv_obj_set_size(APP.ui.guide_title, 268, 24)
  lv_label_set_text(APP.ui.guide_title, "PC MIRROR")
  lv_obj_set_style_text_color(APP.ui.guide_title, 0xF8FAFC, MAIN_STYLE)
  lv_obj_set_style_text_align(APP.ui.guide_title, LV_TEXT_ALIGN_CENTER, MAIN_STYLE)
  if lv_obj_set_style_text_font then
    pcall(function()
      lv_obj_set_style_text_font(APP.ui.guide_title, LV_FONT_MONTSERRAT_20 or 20, MAIN_STYLE)
    end)
  end

  APP.ui.guide_status = lv_label_create(APP.ui.guide)
  lv_obj_set_pos(APP.ui.guide_status, 14, 45)
  lv_obj_set_size(APP.ui.guide_status, 268, 18)
  lv_label_set_text(APP.ui.guide_status, "OFFLINE")
  lv_obj_set_style_text_color(APP.ui.guide_status, 0x38BDF8, MAIN_STYLE)
  lv_obj_set_style_text_align(APP.ui.guide_status, LV_TEXT_ALIGN_CENTER, MAIN_STYLE)

  APP.ui.url = lv_label_create(APP.ui.guide)
  lv_obj_set_pos(APP.ui.url, 14, 66)
  lv_obj_set_size(APP.ui.url, 268, 36)
  lv_label_set_text(APP.ui.url, guide_url_text())
  lv_obj_set_style_text_color(APP.ui.url, 0xCBD5E1, MAIN_STYLE)
  lv_obj_set_style_text_align(APP.ui.url, LV_TEXT_ALIGN_CENTER, MAIN_STYLE)
  if lv_obj_set_style_text_font then
    pcall(function()
      lv_obj_set_style_text_font(APP.ui.url, LV_FONT_MONTSERRAT_12 or 12, MAIN_STYLE)
    end)
  end

  APP.ui.guide_help = lv_label_create(APP.ui.guide)
  lv_obj_set_pos(APP.ui.guide_help, 14, 112)
  lv_obj_set_size(APP.ui.guide_help, 268, 30)
  lv_label_set_text(APP.ui.guide_help, "LEFT  STATUS    RIGHT  RETRY\nDOWN  PAUSE / RESUME")
  lv_obj_set_style_text_color(APP.ui.guide_help, 0x94A3B8, MAIN_STYLE)
  lv_obj_set_style_text_align(APP.ui.guide_help, LV_TEXT_ALIGN_CENTER, MAIN_STYLE)
  if lv_obj_set_style_text_font then
    pcall(function()
      lv_obj_set_style_text_font(APP.ui.guide_help, LV_FONT_MONTSERRAT_10 or 10, MAIN_STYLE)
    end)
  end

  APP.ui.panel = lv_obj_create(root)
  lv_obj_set_pos(APP.ui.panel, 4, SCREEN_H - 22)
  lv_obj_set_size(APP.ui.panel, 84, 18)
  style_plain_panel(APP.ui.panel, 0x000000, 180)
  lv_obj_set_style_radius(APP.ui.panel, 4, MAIN_STYLE)

  APP.ui.status = lv_label_create(APP.ui.panel)
  lv_obj_set_pos(APP.ui.status, 4, 2)
  lv_obj_set_size(APP.ui.status, 76, 14)
  lv_obj_set_style_text_color(APP.ui.status, 0xFFFFFF, MAIN_STYLE)
  lv_obj_set_style_text_opa(APP.ui.status, 255, MAIN_STYLE)
  if lv_obj_set_style_text_font then
    pcall(function()
      lv_obj_set_style_text_font(APP.ui.status, LV_FONT_MONTSERRAT_10 or 10, MAIN_STYLE)
    end)
  end
  if lv_label_set_long_mode and LV_LABEL_LONG_CLIP then
    pcall(function()
      lv_label_set_long_mode(APP.ui.status, LV_LABEL_LONG_CLIP)
    end)
  end

  update_overlay_visible()
end

local function parse_frame(data)
  if type(data) ~= "string" or #data < 36 then
    return nil, "short"
  end

  local b1, b2, b3, b4 = string.byte(data, 1, 4)
  if b1 ~= MAGIC_D or b2 ~= MAGIC_M or b3 ~= MAGIC_J or b4 ~= MAGIC_1 then
    return nil, "magic"
  end

  local version = string.byte(data, 5) or 0
  if version ~= 1 then
    return nil, "version"
  end

  local header_len = u16le(data, 7)
  local jpeg_len = u32le(data, 13)
  if header_len < 36 or jpeg_len <= 0 or #data < header_len + jpeg_len then
    return nil, "length"
  end

  local info = {
    frame_id = u32le(data, 9),
    jpeg_len = jpeg_len,
    width = u16le(data, 17),
    height = u16le(data, 19),
    quality = u16le(data, 21),
    fps100 = u16le(data, 23),
    pc_capture_ms = u16le(data, 25),
    pc_resize_ms = u16le(data, 27),
    pc_encode_ms = u16le(data, 29),
    pc_frame_ms = u16le(data, 31),
    pc_send_ms = u16le(data, 33),
    pc_clients = u16le(data, 35),
  }

  if info.width ~= SCREEN_W or info.height ~= SCREEN_H then
    return nil, "size"
  end

  return info, data:sub(header_len + 1, header_len + jpeg_len)
end

local function print_frame_debug(info, times)
  if not APP.serial_debug then
    return
  end

  local every = APP.serial_debug_every or 1
  if every > 1 and (APP.frame_count % every) ~= 0 then
    return
  end

  local interval = APP.serial_debug_interval_ms or 5000
  local debug_dt = interval
  if APP.last_debug_ms > 0 then
    debug_dt = elapsed_ms(APP.last_debug_ms)
  end
  if APP.last_debug_ms > 0 and debug_dt < interval then
    return
  end
  APP.last_debug_ms = now_ms()

  local mon_cnt, mon_time, mon_px, mon_last_time, mon_last_px = 0, 0, 0, 0, 0
  if lv_lvgl_monitor_get then
    local ok, a, b, c, d, e = pcall(lv_lvgl_monitor_get)
    if ok then
      mon_cnt = tonumber(a) or 0
      mon_time = tonumber(b) or 0
      mon_px = tonumber(c) or 0
      mon_last_time = tonumber(d) or 0
      mon_last_px = tonumber(e) or 0
    end
  end
  local mon_wall_fps = debug_dt > 0 and (mon_cnt * 1000 / debug_dt) or 0
  local mon_render_fps = mon_time > 0 and (mon_cnt * 1000 / mon_time) or 0
  if lv_lvgl_monitor_reset then
    pcall(lv_lvgl_monitor_reset)
  end

  print(string.format(
    "[pc-mirror] frame=%d bytes=%d drop=%d order_err=%d pc_cap=%dms pc_resize=%dms pc_jpeg=%dms pc_send=%dms pc_all=%dms dev_parse=%dms lv_set_src=%dms dev_all=%dms fps=%.1f kbps=%.0f mon_cnt=%d mon_fps=%.1f mon_render=%.1f mon_last=%dms/%dpx",
    info.frame_id or 0,
    info.jpeg_len or 0,
    APP.drop_count or 0,
    APP.out_of_order_count or 0,
    info.pc_capture_ms or 0,
    info.pc_resize_ms or 0,
    info.pc_encode_ms or 0,
    info.pc_send_ms or 0,
    info.pc_frame_ms or 0,
    times.parse_ms or 0,
    times.set_src_ms or 0,
    times.total_ms or 0,
    APP.stat.fps or 0,
    APP.stat.kbps or 0,
    mon_cnt,
    mon_wall_fps,
    mon_render_fps,
    mon_last_time,
    mon_last_px
  ))
end

local function display_frame(data)
  if APP.paused then
    return
  end

  local total_start = now_ms()
  local parse_start = now_ms()
  local info, jpeg_or_err = parse_frame(data)
  local parse_ms = elapsed_ms(parse_start)
  if not info then
    log_error("parse failed: " .. tostring(jpeg_or_err or "parse"))
    return
  end

  if APP.has_frame_id then
    if info.frame_id <= APP.last_frame_id then
      APP.out_of_order_count = APP.out_of_order_count + 1
      print(string.format(
        "[pc-mirror] frame order error: current=%d last=%d count=%d",
        info.frame_id,
        APP.last_frame_id,
        APP.out_of_order_count
      ))
      return
    end

    if info.frame_id > APP.last_frame_id + 1 then
      local lost = info.frame_id - APP.last_frame_id - 1
      APP.drop_count = APP.drop_count + lost
      print(string.format(
        "[pc-mirror] frame drop: last=%d current=%d lost=%d total=%d",
        APP.last_frame_id,
        info.frame_id,
        lost,
        APP.drop_count
      ))
    end
  end

  local jpeg = jpeg_or_err
  APP.image_ref_index = (APP.image_ref_index % 3) + 1
  APP.image_refs[APP.image_ref_index] = jpeg
  local set_src_start = now_ms()
  local set_ok, set_err = pcall(function()
    lv_img_set_src(APP.ui.img, jpeg)
  end)
  local set_src_ms = elapsed_ms(set_src_start)
  if not set_ok then
    log_error("display failed: " .. tostring(set_err or "lv_img_set_src"))
    return
  end

  APP.frame_count = APP.frame_count + 1
  APP.byte_count = APP.byte_count + #jpeg
  APP.last_frame_id = info.frame_id
  APP.has_frame_id = true
  APP.last_rx_ms = now_ms()
  APP.last_error = ""
  APP.last_error_log_ms = 0
  APP.ever_received_frame = true
  update_overlay_visible()

  if APP.ui.panel and APP.overlay and lv_obj_move_foreground then
    pcall(function()
      lv_obj_move_foreground(APP.ui.panel)
    end)
  end

  print_frame_debug(info, {
    parse_ms = parse_ms,
    set_src_ms = set_src_ms,
    total_ms = elapsed_ms(total_start),
  })
end

local function close_ws()
  APP.ws_generation = APP.ws_generation + 1
  local ws = APP.ws
  APP.ws = nil
  if ws then
    pcall(function()
      ws:close()
    end)
  end
  APP.connected = false
  APP.connecting = false
  update_status()
end

local function connect_ws()
  if APP.shutting_down or APP.connecting then
    return
  end

  close_ws()
  if not websocket or not websocket.createClient then
    log_error("websocket module missing")
    update_status()
    return
  end

  local generation = APP.ws_generation + 1
  APP.ws_generation = generation
  APP.connecting = true
  update_status()

  local ok, err = pcall(function()
    local ws = websocket.createClient()
    if not ws then
      error("websocket.createClient returned nil")
    end
    APP.ws = ws
    ws:config({
      buffer_size = APP.ws_buffer,
      task_stack = 12288,
      network_timeout_ms = 5000,
      auto_reconnect = false,
    })

    ws:on("connection", function(client)
      if APP.shutting_down or generation ~= APP.ws_generation then
        return
      end
      APP.connected = true
      APP.connecting = false
      APP.has_frame_id = false
      APP.last_frame_id = 0
      APP.drop_count = 0
      APP.out_of_order_count = 0
      APP.last_rx_ms = now_ms()
      if lv_lvgl_monitor_reset then
        pcall(lv_lvgl_monitor_reset)
      end
      update_overlay_visible()
      print("[pc-mirror] connected " .. APP.url)
      pcall(function()
        client:send("ready", websocket.TEXT or 1)
      end)
    end)

    ws:on("receive", function(_, data, opcode)
      if APP.shutting_down or generation ~= APP.ws_generation then
        return
      end
      log_receive(data, opcode)
      if is_binary_opcode(opcode) then
        display_frame(data)
      end
    end)

    ws:on("close", function(_, status)
      if APP.shutting_down or generation ~= APP.ws_generation then
        return
      end
      APP.connected = false
      APP.connecting = false
      APP.ws = nil
      update_overlay_visible()
      print("[pc-mirror] disconnected " .. tostring(status or 0))
    end)

    ws:connect(APP.url)
  end)
  if not ok then
    if generation == APP.ws_generation then
      local failed_ws = APP.ws
      APP.ws = nil
      APP.connecting = false
      APP.connected = false
      if failed_ws then
        pcall(function() failed_ws:close() end)
      end
      log_error("connect failed: " .. tostring(err))
      update_overlay_visible()
    end
  end
end

local function start_timers()
  if tmr and tmr.create then
    APP.stat_timer = tmr.create()
    APP.stat_timer:alarm(1000, tmr.ALARM_AUTO, function()
      if APP.shutting_down then
        return
      end
      local ts = now_ms()
      local dt = APP.stat.last_ms > 0 and (ts - APP.stat.last_ms) or 1000
      if dt <= 0 then
        dt = 1000
      end
      APP.stat.fps = (APP.frame_count - APP.stat.frames) * 1000 / dt
      APP.stat.kbps = (APP.byte_count - APP.stat.bytes) * 1000 / dt / 1024
      APP.stat.frames = APP.frame_count
      APP.stat.bytes = APP.byte_count
      APP.stat.last_ms = ts
      if APP.ui.url and not APP.ever_received_frame then
        pcall(function()
          lv_label_set_text(APP.ui.url, guide_url_text())
        end)
      end
    end)

    APP.reconnect_timer = tmr.create()
    APP.reconnect_timer:alarm(2500, tmr.ALARM_AUTO, function()
      if (not APP.shutting_down) and (not APP.connected) and (not APP.connecting) and (not APP.paused) then
        connect_ws()
      end
    end)
  end
end

local function bind_keys()
  if not key or not key.on then
    return
  end

  key.on(key.LEFT, function(evt)
    if evt == key.SHORT then
      APP.overlay = not APP.overlay
      update_overlay_visible()
    end
  end)

  key.on(key.RIGHT, function(evt)
    if evt == key.SHORT then
      load_config()
      update_overlay_visible()
      connect_ws()
    end
  end)

  key.on(key.DOWN, function(evt)
    if evt == key.SHORT then
      APP.paused = not APP.paused
      update_status()
      print("[pc-mirror] paused=" .. tostring(APP.paused))
      if not APP.paused and not APP.connected and not APP.connecting then
        connect_ws()
      end
    end
  end)
end

local JSON = rawget(_G, "sjson") or rawget(_G, "json")

local function json_escape(value)
  local text = tostring(value or "")
  text = text:gsub("\\", "\\\\")
  text = text:gsub('"', '\\"')
  text = text:gsub("\r", "\\r")
  text = text:gsub("\n", "\\n")
  return text
end

local function url_decode(value)
  local text = tostring(value or ""):gsub("+", " ")
  return text:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
end

local function parse_query(query)
  local values = {}
  for pair in tostring(query or ""):gmatch("([^&]+)") do
    local key, value = pair:match("^([^=]*)=(.*)$")
    if not key then
      key, value = pair, ""
    end
    values[url_decode(key)] = url_decode(value)
  end
  return values
end

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function valid_ipv4(host)
  local a, b, c, d = tostring(host or ""):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  if not a then return false end
  for _, part in ipairs({ tonumber(a), tonumber(b), tonumber(c), tonumber(d) }) do
    if not part or part < 0 or part > 255 then return false end
  end
  return true
end

local function current_host_port()
  local host, port = tostring(APP.url or ""):match("^wss?://(%d+%.%d+%.%d+%.%d+):(%d+)")
  return host or "192.168.0.80", tonumber(port) or 8787
end

local function write_config_url(url)
  local raw = string.format(
    '{\n  "url": "%s",\n  "ws_buffer": %d,\n  "overlay": %s,\n  "serial_debug": %s,\n  "serial_debug_every": %d,\n  "serial_debug_interval_ms": %d\n}\n',
    json_escape(url),
    tonumber(APP.ws_buffer) or 8192,
    APP.overlay and "true" or "false",
    APP.serial_debug and "true" or "false",
    tonumber(APP.serial_debug_every) or 1,
    tonumber(APP.serial_debug_interval_ms) or 5000
  )

  if file and file.putcontents then
    local ok, result = pcall(function()
      return file.putcontents(APP.config_path, raw)
    end)
    if ok and result ~= false then
      return true
    end
    return false, tostring(result or "write failed")
  end

  if file and file.open and file.write and file.close then
    local ok, err = pcall(function()
      file.open(APP.config_path, "w+")
      file.write(raw)
      file.close()
    end)
    return ok, ok and nil or tostring(err)
  end
  return false, "file API missing"
end

local function web_snapshot(ok, message)
  local host, port = current_host_port()
  return {
    ok = ok ~= false,
    host = host,
    port = port,
    url = APP.url,
    setup_url = setup_page_url(),
    connected = APP.connected,
    connecting = APP.connecting,
    paused = APP.paused,
    fps = APP.stat.fps or 0,
    kbps = APP.stat.kbps or 0,
    frames = APP.frame_count or 0,
    drops = APP.drop_count or 0,
    message = message or APP.last_error or "",
  }
end

local function encode_web_json(value)
  if JSON and JSON.encode then
    local ok, raw = pcall(function() return JSON.encode(value) end)
    if ok and type(raw) == "string" then return raw end
  end
  return string.format(
    '{"ok":%s,"host":"%s","port":%d,"url":"%s","setup_url":"%s","connected":%s,"connecting":%s,"paused":%s,"fps":%.2f,"kbps":%.2f,"frames":%d,"drops":%d,"message":"%s"}',
    value.ok and "true" or "false",
    json_escape(value.host),
    tonumber(value.port) or 0,
    json_escape(value.url),
    json_escape(value.setup_url),
    value.connected and "true" or "false",
    value.connecting and "true" or "false",
    value.paused and "true" or "false",
    tonumber(value.fps) or 0,
    tonumber(value.kbps) or 0,
    tonumber(value.frames) or 0,
    tonumber(value.drops) or 0,
    json_escape(value.message)
  )
end

local function web_response(status, content_type, body)
  return {
    status = status or "200 OK",
    type = content_type or "text/plain; charset=utf-8",
    headers = {
      ["cache-control"] = "no-store",
      ["connection"] = "close",
    },
    body = body or "",
  }
end

local function web_json_response(status, value)
  return web_response(status, "application/json; charset=utf-8", encode_web_json(value))
end

local function register_web_route(method, route, handler)
  if not httpd or not httpd.dynamic or not method then
    return false
  end
  local ok, err = pcall(function()
    return httpd.dynamic(method, route, handler)
  end)
  if not ok or err then
    print("[pc-mirror] web route failed " .. route .. ": " .. tostring(err))
    return false
  end
  APP.web_routes[#APP.web_routes + 1] = { method = method, route = route }
  return true
end

local function start_web()
  if APP.web_started or not httpd or not httpd.dynamic then
    return
  end

  if httpd.start then
    pcall(function()
      httpd.start({
        webroot = "/sd",
        auto_index = httpd.INDEX_NONE or 0,
        max_handlers = 64,
      })
    end)
  end

  local get = httpd.GET
  local function serve_page()
    local body = nil
    if file and file.getcontents then
      local ok, raw = pcall(function()
        return file.getcontents(APP.app_dir .. "/main.html")
      end)
      if ok and type(raw) == "string" then body = raw end
    end
    if not body then
      return web_response("500 Internal Server Error", "text/plain; charset=utf-8", "PC Mirror Web page is unavailable")
    end
    return web_response("200 OK", "text/html; charset=utf-8", body)
  end

  register_web_route(get, APP.route_base, serve_page)
  register_web_route(get, APP.route_base .. "/", serve_page)
  register_web_route(get, APP.route_base .. "/main.html", serve_page)
  register_web_route(get, APP.route_base .. "/api/state", function()
    return web_json_response("200 OK", web_snapshot(true, "loaded"))
  end)
  register_web_route(get, APP.route_base .. "/api/save", function(req)
    local query = parse_query(req and req.query or "")
    local host = trim(query.host)
    local port = tonumber(query.port)
    if not valid_ipv4(host) then
      local state = web_snapshot(false, "请输入有效的电脑 IPv4 地址")
      return web_json_response("400 Bad Request", state)
    end
    if not port or port < 1 or port > 65535 or port ~= math.floor(port) then
      local state = web_snapshot(false, "端口需为 1 到 65535 的整数")
      return web_json_response("400 Bad Request", state)
    end

    local url = "ws://" .. host .. ":" .. tostring(math.floor(port))
    local saved, save_error = write_config_url(url)
    if not saved then
      local state = web_snapshot(false, "配置保存失败: " .. tostring(save_error or "unknown"))
      return web_json_response("500 Internal Server Error", state)
    end

    APP.url = url
    APP.last_error = ""
    if APP.ui.url then
      pcall(function() lv_label_set_text(APP.ui.url, guide_url_text()) end)
    end
    connect_ws()
    return web_json_response("200 OK", web_snapshot(true, "saved"))
  end)
  register_web_route(get, APP.route_base .. "/api/health", function()
    return web_response("200 OK", "text/plain; charset=utf-8", "ok")
  end)

  APP.web_started = #APP.web_routes > 0
  if APP.web_started then
    print("[pc-mirror] web setup: " .. setup_page_url())
  end
end

local function stop_web()
  if httpd and httpd.unregister then
    for i = #APP.web_routes, 1, -1 do
      local item = APP.web_routes[i]
      pcall(function()
        httpd.unregister(item.method, item.route)
      end)
    end
  end
  APP.web_routes = {}
  APP.web_started = false
end

function APP.shutdown()
  if APP.shutting_down then
    return
  end
  APP.shutting_down = true

  if APP.reconnect_timer then
    pcall(function()
      APP.reconnect_timer:stop()
    end)
    pcall(function()
      APP.reconnect_timer:unregister()
    end)
    APP.reconnect_timer = nil
  end
  if APP.stat_timer then
    pcall(function()
      APP.stat_timer:stop()
    end)
    pcall(function()
      APP.stat_timer:unregister()
    end)
    APP.stat_timer = nil
  end

  stop_web()
  close_ws()

  if key and key.off then
    pcall(function()
      key.off(key.LEFT)
      key.off(key.RIGHT)
      key.off(key.DOWN)
    end)
  end

  APP.image_refs = {}
  APP.ui = {}
  pcall(function()
    lv_clear()
  end)
end

load_config()
build_ui()
bind_keys()
start_timers()
start_web()
connect_ws()
