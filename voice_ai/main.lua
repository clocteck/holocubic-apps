if _G.VOICE_AI_APP and _G.VOICE_AI_APP.stop then
  pcall(function() _G.VOICE_AI_APP.stop("reload") end)
end

VOICE_AI_APP = {
  VERSION = "2026-05-14-voice-ai-v3",
  SCREEN_W = 320,
  SCREEN_H = 240,
  APP_DIR = "/sd/apps/voice_ai",
  DEFAULT_BRIDGE_URL = "http://192.168.0.80:8790",
  I2S_ID = 0,
  READ_BYTES = 4096,
  RECORD_POLL_MS = 80,
  USE_GIF = true,
}

local APP = VOICE_AI_APP
local MAIN_STYLE = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
local ALIGN_LEFT = rawget(_G, "LV_TEXT_ALIGN_LEFT") or 0
local ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1
local FONT_10 = rawget(_G, "LV_FONT_MONTSERRAT_10") or 10
local FONT_12 = rawget(_G, "LV_FONT_MONTSERRAT_12") or 12
local LABEL_LONG_CLIP = rawget(_G, "LV_LABEL_LONG_CLIP") or rawget(_G, "LABEL_LONG_CLIP")
local LABEL_LONG_WRAP = rawget(_G, "LV_LABEL_LONG_WRAP") or LABEL_LONG_CLIP

local C = {
  bg = 0x000000,
  line = 0x242B33,
  text = 0xF4F7FA,
  sub = 0xAAB4C2,
  dim = 0x66717F,
  cyan = 0x55D6FF,
  green = 0x55E39A,
  yellow = 0xF5C65B,
  red = 0xFF6B5F,
}

APP.running = true
APP.ui = {}
APP.timers = {}
APP.font_handles = {}
APP.ai_ui = nil
APP.main_screen = nil
APP.config = {
  bridge_url = APP.DEFAULT_BRIDGE_URL,
  sample_rate = 16000,
  sample_bits = 32,
  max_record_ms = 10000,
  reply_limit = 100,
  use_gif = APP.USE_GIF,
}
APP.state = {
  mode = "idle",
  shown_gif_state = nil,
  record_started_ms = 0,
  record_bytes = 0,
  rx_events = 0,
  chunks = {},
  last_error = "",
  transcript = "",
  reply = "按下说话",
  pending_reply = "",
  pending_ui_code = "",
  pending_id = "",
  result_polls = 0,
}

local UI = APP.ui
local S = APP.state

local function call(fn, ...)
  if fn then
    return pcall(fn, ...)
  end
  return false
end

local function now_ms()
  if millis then
    local ok, value = pcall(millis)
    if ok and type(value) == "number" then return value end
  end
  if tmr and tmr.now then
    local ok, value = pcall(function() return tmr.now() end)
    if ok and type(value) == "number" then return math.floor(value / 1000) end
  end
  return 0
end

local function text_or(value, fallback)
  if value == nil then return fallback or "" end
  local text = tostring(value)
  if text == "" then return fallback or "" end
  return text
end

local function clamp(n, low, high)
  n = tonumber(n) or 0
  if n < low then return low end
  if n > high then return high end
  return n
end

local function sd_to_lv(path)
  if type(path) == "string" and path:sub(1, 4) == "/sd/" then
    return "/" .. path:sub(5)
  end
  return path
end

local function safe_json_decode(raw)
  if not raw or raw == "" or not json or not json.decode then
    return nil, "json missing"
  end
  local ok, doc, err = pcall(function()
    local value, decode_err = json.decode(raw)
    return value, decode_err
  end)
  if not ok then return nil, tostring(doc) end
  if not doc then return nil, tostring(err or "decode failed") end
  return doc, nil
end

local function load_config()
  if not file or not file.getcontents then return end
  local raw = file.getcontents(APP.APP_DIR .. "/config.json")
  if not raw or raw == "" then return end
  local cfg = safe_json_decode(raw)
  if type(cfg) ~= "table" then return end

  if type(cfg.bridge_url) == "string" and cfg.bridge_url ~= "" then
    APP.config.bridge_url = cfg.bridge_url
  end
  APP.config.sample_rate = clamp(cfg.sample_rate or APP.config.sample_rate, 8000, 48000)
  APP.config.sample_bits = clamp(cfg.sample_bits or APP.config.sample_bits, 16, 32)
  APP.config.max_record_ms = clamp(cfg.max_record_ms or APP.config.max_record_ms, 1000, 30000)
  APP.config.reply_limit = clamp(cfg.reply_limit or APP.config.reply_limit, 20, 100)
  if type(cfg.use_gif) == "boolean" then
    APP.config.use_gif = cfg.use_gif
  end
end

local function style_obj(id, bg, opa, border)
  if not id then return end
  call(lv_obj_remove_style_all, id)
  call(lv_obj_set_style_bg_color, id, bg or C.bg, MAIN_STYLE)
  call(lv_obj_set_style_bg_opa, id, opa or 255, MAIN_STYLE)
  call(lv_obj_set_style_border_width, id, border and 1 or 0, MAIN_STYLE)
  if border then
    call(lv_obj_set_style_border_color, id, border, MAIN_STYLE)
    call(lv_obj_set_style_border_opa, id, 255, MAIN_STYLE)
  end
  call(lv_obj_set_style_radius, id, 0, MAIN_STYLE)
  call(lv_obj_set_style_pad_all, id, 0, MAIN_STYLE)
  if lv_obj_clear_flag and rawget(_G, "LV_OBJ_FLAG_SCROLLABLE") then
    call(lv_obj_clear_flag, id, rawget(_G, "LV_OBJ_FLAG_SCROLLABLE"))
  end
end

local function set_label_style(id, font, color, align)
  if not id then return end
  call(lv_obj_set_style_text_font, id, font or FONT_12, MAIN_STYLE)
  call(lv_obj_set_style_text_color, id, color or C.text, MAIN_STYLE)
  call(lv_obj_set_style_text_opa, id, 255, MAIN_STYLE)
  call(lv_obj_set_style_text_letter_space, id, 0, MAIN_STYLE)
  call(lv_obj_set_style_text_line_space, id, 2, MAIN_STYLE)
  if align and lv_obj_set_style_text_align then
    call(lv_obj_set_style_text_align, id, align, MAIN_STYLE)
  end
end

local function label(parent, x, y, w, h, text, font, color, align, long_mode)
  local id = lv_label_create(parent)
  call(lv_label_set_text, id, text_or(text, ""))
  call(lv_obj_set_pos, id, x, y)
  call(lv_obj_set_width, id, w)
  if h and lv_obj_set_height then call(lv_obj_set_height, id, h) end
  if lv_label_set_long_mode then
    call(lv_label_set_long_mode, id, long_mode or LABEL_LONG_CLIP)
  end
  set_label_style(id, font, color, align or ALIGN_LEFT)
  return id
end

local function set_text(id, text)
  if id then call(lv_label_set_text, id, text_or(text, "")) end
end

local function set_text_color(id, color)
  if id and lv_obj_set_style_text_color then
    call(lv_obj_set_style_text_color, id, color, MAIN_STYLE)
  end
end

local function set_opa(id, opa)
  if id and lv_obj_set_style_opa then
    call(lv_obj_set_style_opa, id, opa, MAIN_STYLE)
  end
end

local function serial_dump(name, text)
  text = text_or(text, "")
  name = text_or(name, "dump")
  local chunk_size = 384
  local total = #text
  local parts = math.floor((total + chunk_size - 1) / chunk_size)
  if parts < 1 then parts = 1 end

  local function write_text(payload)
    if uart and uart.write then
      pcall(uart.write, 0, payload)
    else
      print(payload)
    end
  end

  write_text("\r\n[voice_ai] " .. name .. "_begin len=" .. tostring(total) .. " parts=" .. tostring(parts) .. "\r\n")
  local part = 1
  local pos = 1
  while pos <= total do
    local chunk = text:sub(pos, pos + chunk_size - 1)
    write_text("[voice_ai] " .. name .. "_part " .. tostring(part) .. "/" .. tostring(parts) .. "=" .. chunk .. "\r\n")
    pos = pos + chunk_size
    part = part + 1
  end
  if total == 0 then
    write_text("[voice_ai] " .. name .. "_part 1/1=\r\n")
  end
  write_text("[voice_ai] " .. name .. "_end\r\n")
end

local function serial_line(name, text)
  text = text_or(text, "")
  name = text_or(name, "line")
  local payload = "[voice_ai] " .. name .. "=" .. text
  if payload:sub(-1) ~= "\n" then
    payload = payload .. "\r\n"
  end
  if uart and uart.write then
    pcall(uart.write, 0, payload)
  else
    print(payload)
  end
end

local function load_font_ref(path, fallback)
  if not lv_font_load then return fallback end
  local ok, handle = pcall(function() return lv_font_load(path) end)
  if ok and type(handle) == "number" and handle > 0 then
    APP.font_handles[#APP.font_handles + 1] = handle
    return handle
  end
  return fallback
end

local function release_fonts()
  if lv_font_free then
    for _, handle in ipairs(APP.font_handles or {}) do
      pcall(function() lv_font_free(handle) end)
    end
  end
  APP.font_handles = {}
end

local function next_utf8_char(text, index)
  local b = text:byte(index)
  if not b then return nil, index end
  local len = 1
  if b >= 240 then len = 4
  elseif b >= 224 then len = 3
  elseif b >= 192 then len = 2 end
  return text:sub(index, index + len - 1), index + len
end

local function wrap_for_screen(text, max_units, max_lines)
  text = text_or(text, "")
  local lines = {}
  local line = ""
  local units = 0
  local i = 1
  while i <= #text and #lines < max_lines do
    local ch, ni = next_utf8_char(text, i)
    i = ni
    if not ch then break end
    if ch == "\r" then
      -- skip
    elseif ch == "\n" then
      lines[#lines + 1] = line
      line = ""
      units = 0
    else
      local b = ch:byte(1) or 0
      local add = (b < 128) and 0.55 or 1
      if units + add > max_units and line ~= "" then
        lines[#lines + 1] = line
        line = ch
        units = add
      else
        line = line .. ch
        units = units + add
      end
    end
  end
  if #lines < max_lines and line ~= "" then
    lines[#lines + 1] = line
  end
  return table.concat(lines, "\n")
end

local function bridge_url(path)
  local base = text_or(APP.config.bridge_url, APP.DEFAULT_BRIDGE_URL)
  if base:sub(-1) == "/" then base = base:sub(1, -2) end
  return base .. path
end

local function status_text()
  if S.mode == "recording" then return "录音中" end
  if S.mode == "sending" then return "思考中" end
  if S.mode == "error" then return "失败" end
  if S.mode == "reply" then return "回复" end
  return "按下说话"
end

local function status_color()
  if S.mode == "recording" then return C.red end
  if S.mode == "sending" then return C.yellow end
  if S.mode == "error" then return C.red end
  if S.mode == "reply" then return C.green end
  return C.cyan
end

local function gif_state()
  if S.mode == "recording" then return "attention" end
  if S.mode == "sending" then return "busy" end
  if S.mode == "error" then return "dizzy" end
  if S.mode == "reply" then return "celebrate" end
  return "idle"
end

local function gif_path_for_state(state)
  local map = {
    idle = "idle_0.gif",
    attention = "attention.gif",
    busy = "busy.gif",
    celebrate = "celebrate.gif",
    dizzy = "dizzy.gif",
    sleep = "sleep.gif",
  }
  local path = APP.APP_DIR .. "/assets/buddy/" .. (map[state] or map.idle)
  if file and file.exists and file.exists(path) then
    return sd_to_lv(path)
  end
  return nil
end

local function update_gif()
  if not UI.gif or not lv_gif_set_src then return end
  if not APP.config.use_gif then
    if S.shown_gif_state ~= nil then
      call(lv_gif_set_src, UI.gif, nil)
      S.shown_gif_state = nil
    end
    set_opa(UI.gif, 0)
    return
  end

  local state = gif_state()
  local src = gif_path_for_state(state)
  if not src then
    set_opa(UI.gif, 0)
    return
  end
  set_opa(UI.gif, 255)
  if S.shown_gif_state ~= state then
    S.shown_gif_state = state
    call(lv_gif_set_src, UI.gif, src)
  end
end

local function dialog_text(transcript, reply, transcript_lines, reply_lines)
  transcript = text_or(transcript, "")
  reply = text_or(reply, "")
  if transcript ~= "" and reply ~= "" then
    local user_text = wrap_for_screen("我：" .. transcript, 13, transcript_lines or 2)
    local reply_text = wrap_for_screen("AI：" .. reply, 13, reply_lines or 4)
    if reply_text ~= "" then return user_text .. "\n\n" .. reply_text end
    return user_text
  end
  if transcript ~= "" then
    return wrap_for_screen("我：" .. transcript, 13, (transcript_lines or 6) + (reply_lines or 0))
  end
  return wrap_for_screen(reply, 13, reply_lines or 6)
end

local function update_ui()
  set_text(UI.status, status_text())
  set_text_color(UI.status, status_color())

  local body = S.reply
  local body_wrapped = false
  if S.mode == "recording" then
    local elapsed = now_ms() - (S.record_started_ms or now_ms())
    local sec = math.floor(math.max(elapsed, 0) / 1000)
    body = "正在听\n" .. tostring(sec) .. "s\n" .. tostring(S.record_bytes or 0) .. " B"
  elseif S.mode == "sending" then
    if S.transcript ~= "" then
      body = dialog_text(S.transcript, "思考中", 2, 3)
      body_wrapped = true
    else
      body = "请稍等"
    end
  elseif S.mode == "error" then
    body = dialog_text(S.transcript, S.last_error ~= "" and S.last_error or "服务不可用", 2, 4)
    body_wrapped = true
  elseif S.mode == "reply" then
    body = dialog_text(S.transcript, S.reply, 2, 4)
    body_wrapped = true
  end

  if body_wrapped then
    set_text(UI.reply, body)
  else
    set_text(UI.reply, wrap_for_screen(body, 13, 6))
  end
  update_gif()
end

local function set_mode(mode, message)
  S.mode = mode
  if message then S.reply = message end
  update_ui()
end

local function clear_recording()
  S.chunks = {}
  S.record_bytes = 0
  S.rx_events = 0
  S.record_started_ms = 0
end

local function stop_i2s()
  if i2s and i2s.stop then
    pcall(function() i2s.stop(APP.I2S_ID) end)
  end
end

local function stop_timer(timer)
  if not timer then return end
  pcall(function()
    timer:stop()
    timer:unregister()
  end)
end

local function cleanup_ai_ui(load_main)
  local current = APP.ai_ui
  APP.ai_ui = nil

  if current then
    current.active = false
    for _, timer in ipairs(current.timers or {}) do
      stop_timer(timer)
    end
  end

  if load_main and APP.main_screen and lv_scr_load then
    pcall(function() lv_scr_load(APP.main_screen) end)
  end

  if current then
    if type(current.cleanup) == "function" then
      pcall(current.cleanup)
    end
    if current.screen and current.screen ~= 0 and current.screen ~= APP.main_screen and lv_obj_del then
      if lv_obj_del_async then
        pcall(function() lv_obj_del_async(current.screen) end)
      else
        pcall(function() lv_obj_del(current.screen) end)
      end
    end
  end
  if load_main then update_ui() end
end

local function compile_ai_code(code, env)
  if type(code) ~= "string" or code == "" then
    return nil, "empty code"
  end

  if type(load) == "function" then
    local ok, fn_or_err, load_err = pcall(load, code, "voice_ai_ui", "t", env)
    if ok and type(fn_or_err) == "function" then
      return fn_or_err, nil
    end
    if ok then
      return nil, tostring(load_err or fn_or_err or "compile failed")
    end
  end

  if type(loadstring) == "function" then
    local fn, err = loadstring(code, "voice_ai_ui")
    if not fn then return nil, tostring(err or "compile failed") end
    if type(setfenv) == "function" then
      pcall(setfenv, fn, env)
    end
    return fn, nil
  end
  return nil, "load unavailable"
end

local function ai_style_obj(id, bg)
  if not id then return end
  call(lv_obj_remove_style_all, id)
  call(lv_obj_set_style_bg_color, id, bg or C.bg, MAIN_STYLE)
  call(lv_obj_set_style_bg_opa, id, 255, MAIN_STYLE)
  call(lv_obj_set_style_border_width, id, 0, MAIN_STYLE)
  call(lv_obj_set_style_radius, id, 0, MAIN_STYLE)
  call(lv_obj_set_style_pad_all, id, 0, MAIN_STYLE)
  if lv_obj_clear_flag and rawget(_G, "LV_OBJ_FLAG_SCROLLABLE") then
    call(lv_obj_clear_flag, id, rawget(_G, "LV_OBJ_FLAG_SCROLLABLE"))
  end
end

local function ai_label(parent, x, y, w, h, text, color, align)
  local id = lv_label_create(parent)
  call(lv_obj_set_pos, id, x, y)
  call(lv_obj_set_width, id, w)
  if h and lv_obj_set_height then call(lv_obj_set_height, id, h) end
  if lv_label_set_long_mode then
    call(lv_label_set_long_mode, id, LABEL_LONG_WRAP)
  end
  call(lv_label_set_text, id, text_or(text, ""))
  set_label_style(id, APP.font_cn, color or C.text, align or ALIGN_LEFT)
  return id
end

local AI_BLOCKED_LV = {
  lv_scr_act = true,
  lv_scr_load = true,
  lv_scr_load_anim = true,
  lv_begin = true,
  lv_end = true,
  lv_get_root = true,

  lv_obj_del = true,
  lv_obj_del_async = true,
  lv_obj_clean = true,
  lv_obj_set_parent = true,
  lv_obj_get_parent = true,
  lv_obj_get_child = true,
  lv_obj_get_child_cnt = true,

  lv_font_load = true,
  lv_font_free = true,
  lv_img_load_bmp565 = true,
  lv_img_free_handle = true,
  lv_snapshot_take = true,
  lv_snapshot_free = true,
  lv_snapshot_buf_size_needed = true,

  lv_anim_del_all = true,
  lv_anim_delete_all = true,
  lv_avi_canvas_start = true,
  lv_avi_canvas_stop = true,
  lv_avi_canvas_poll = true,
}

local function expose_ai_lv_globals(env)
  for name, value in pairs(_G) do
    if type(name) == "string" and not AI_BLOCKED_LV[name] then
      local is_lv_api = name:sub(1, 3) == "lv_"
      local is_lv_const = name:sub(1, 3) == "LV_"
      local is_label_const = name:sub(1, 11) == "LABEL_LONG_"
      if is_lv_api or is_lv_const or is_label_const then
        env[name] = value
      end
    end
  end
end

local function build_ai_env(ctx)
  local env = {
    ctx = ctx,
    math = math,
    string = string,
    table = table,
    ipairs = ipairs,
    pairs = pairs,
    next = next,
    tonumber = tonumber,
    tostring = tostring,
    type = type,
    pcall = pcall,
    select = select,

    lv_obj_create = lv_obj_create,
    lv_obj_set_pos = lv_obj_set_pos,
    lv_obj_set_size = lv_obj_set_size,
    lv_obj_set_x = lv_obj_set_x,
    lv_obj_set_y = lv_obj_set_y,
    lv_obj_set_width = lv_obj_set_width,
    lv_obj_set_height = lv_obj_set_height,
    lv_obj_center = lv_obj_center,
    lv_obj_align = lv_obj_align,
    lv_obj_remove_style_all = lv_obj_remove_style_all,
    lv_obj_clear_flag = lv_obj_clear_flag,
    lv_obj_set_style_bg_color = lv_obj_set_style_bg_color,
    lv_obj_set_style_bg_opa = lv_obj_set_style_bg_opa,
    lv_obj_set_style_border_width = lv_obj_set_style_border_width,
    lv_obj_set_style_border_color = lv_obj_set_style_border_color,
    lv_obj_set_style_border_opa = lv_obj_set_style_border_opa,
    lv_obj_set_style_radius = lv_obj_set_style_radius,
    lv_obj_set_style_pad_all = lv_obj_set_style_pad_all,
    lv_obj_set_style_opa = lv_obj_set_style_opa,
    lv_obj_set_style_text_font = lv_obj_set_style_text_font,
    lv_obj_set_style_text_color = lv_obj_set_style_text_color,
    lv_obj_set_style_text_opa = lv_obj_set_style_text_opa,
    lv_obj_set_style_text_align = lv_obj_set_style_text_align,
    lv_obj_set_style_text_line_space = lv_obj_set_style_text_line_space,
    lv_obj_set_style_text_letter_space = lv_obj_set_style_text_letter_space,
    lv_obj_set_style_line_width = lv_obj_set_style_line_width,
    lv_obj_set_style_line_color = lv_obj_set_style_line_color,
    lv_obj_set_style_line_opa = lv_obj_set_style_line_opa,

    lv_label_create = lv_label_create,
    lv_label_set_text = lv_label_set_text,
    lv_label_set_long_mode = lv_label_set_long_mode,
    lv_line_create = lv_line_create,
    lv_line_set_points = lv_line_set_points,
    lv_canvas_create = lv_canvas_create,
    lv_canvas_fill_bg = lv_canvas_fill_bg,
    lv_canvas_frame_begin = lv_canvas_frame_begin,
    lv_canvas_frame_end = lv_canvas_frame_end,
    lv_canvas_draw_rect = lv_canvas_draw_rect,
    lv_canvas_draw_line = lv_canvas_draw_line,
    lv_canvas_draw_arc = lv_canvas_draw_arc,
    lv_canvas_draw_text = lv_canvas_draw_text,
    lv_canvas_set_px_color = lv_canvas_set_px_color,
    lv_canvas_set_px_opa = lv_canvas_set_px_opa,

    LV_PART_MAIN = rawget(_G, "LV_PART_MAIN") or 0,
    LV_STATE_DEFAULT = rawget(_G, "LV_STATE_DEFAULT") or 0,
    LV_TEXT_ALIGN_LEFT = ALIGN_LEFT,
    LV_TEXT_ALIGN_CENTER = ALIGN_CENTER,
    LV_LABEL_LONG_CLIP = LABEL_LONG_CLIP,
    LV_LABEL_LONG_WRAP = LABEL_LONG_WRAP,
    LV_OBJ_FLAG_SCROLLABLE = rawget(_G, "LV_OBJ_FLAG_SCROLLABLE"),
    LV_IMG_CF_TRUE_COLOR = rawget(_G, "LV_IMG_CF_TRUE_COLOR"),
    LV_IMG_CF_TRUE_COLOR_CHROMA_KEYED = rawget(_G, "LV_IMG_CF_TRUE_COLOR_CHROMA_KEYED"),
  }
  expose_ai_lv_globals(env)
  env._ENV = env
  return env
end

local function show_ai_ui(code)
  cleanup_ai_ui(true)
  local timers = {}
  local state = { active = true, timers = timers }

  local function fail(message)
    state.active = false
    for _, timer in ipairs(timers) do
      stop_timer(timer)
    end
    if state.created_screen and state.created_screen ~= 0 and state.created_screen ~= APP.main_screen and lv_obj_del then
      pcall(function() lv_obj_del(state.created_screen) end)
    end
    S.last_error = message
    set_mode("error")
    return false
  end

  local ctx = {
    SCREEN_W = APP.SCREEN_W,
    SCREEN_H = APP.SCREEN_H,
    ALIGN_LEFT = ALIGN_LEFT,
    ALIGN_CENTER = ALIGN_CENTER,
    MAIN_STYLE = MAIN_STYLE,
    FONT = APP.font_cn or FONT_12,
    C = {
      bg = C.bg,
      line = C.line,
      text = C.text,
      sub = C.sub,
      dim = C.dim,
      cyan = C.cyan,
      green = C.green,
      yellow = C.yellow,
      red = C.red,
    },
    new_screen = function()
      local screen = lv_obj_create(nil)
      state.created_screen = screen
      ai_style_obj(screen, C.bg)
      return screen
    end,
    style_obj = ai_style_obj,
    label = ai_label,
    every = function(ms, fn)
      if not tmr or not tmr.create or type(fn) ~= "function" then return nil end
      local timer = tmr.create()
      timers[#timers + 1] = timer
      timer:alarm(clamp(ms, 50, 5000), tmr.ALARM_AUTO, function()
        if APP.running and state.active then
          pcall(fn)
        end
      end)
      return timer
    end,
  }

  local fn, err = compile_ai_code(code, build_ai_env(ctx))
  if not fn then
    return fail("代码错误 " .. tostring(err or ""))
  end

  local ok, factory_or_result = pcall(fn)
  if not ok then
    return fail("运行错误 " .. tostring(factory_or_result))
  end

  local ok2, result
  if type(factory_or_result) == "function" then
    ok2, result = pcall(factory_or_result, ctx)
  else
    ok2, result = true, factory_or_result
  end
  if not ok2 then
    return fail("界面错误 " .. tostring(result))
  end

  if type(result) == "number" then
    result = { screen = result }
  end
  if type(result) ~= "table" or type(result.screen) ~= "number" then
    return fail("没有返回 screen")
  end
  if result.screen == 0 or result.screen == APP.main_screen then
    return fail("不能占用主屏幕")
  end

  state.screen = result.screen
  state.cleanup = result.cleanup
  APP.ai_ui = state
  if lv_scr_load then
    pcall(function() lv_scr_load(result.screen) end)
  end
  return true
end

local schedule_reply
local start_result_poll

local function handle_bridge_response(code, body)
  serial_dump("bridge_json", body or "")
  if code ~= 200 then
    local doc = nil
    if body and body ~= "" then
      doc = safe_json_decode(body)
    end
    if type(doc) == "table" and doc.transcript then
      S.transcript = text_or(doc.transcript, "")
    end
    if type(doc) == "table" and doc.error then
      S.last_error = text_or(doc.error, "HTTP " .. tostring(code))
    else
      S.last_error = "HTTP " .. tostring(code)
    end
    set_mode("error")
    return
  end

  local doc, err = safe_json_decode(body)
  if type(doc) ~= "table" then
    S.last_error = tostring(err or "响应错误")
    set_mode("error")
    return
  end

  if doc.ok == false then
    S.transcript = text_or(doc.transcript, "")
    S.last_error = text_or(doc.error, "请求失败")
    set_mode("error")
    return
  end

  S.transcript = text_or(doc.transcript, "")
  if doc.pending == true and doc.id then
    S.pending_id = text_or(doc.id, "")
    S.pending_reply = ""
    S.pending_ui_code = ""
    S.result_polls = 0
    set_mode("sending")
    start_result_poll()
    return
  end

  S.pending_reply = text_or(doc.reply, "没有回复")
  S.pending_ui_code = type(doc.ui_code) == "string" and doc.ui_code or ""
  set_mode("sending")
  schedule_reply()
end

local function submit_audio(raw)
  if not raw or #raw == 0 then
    S.last_error = "没有录到声音"
    set_mode("error")
    return
  end
  if not http or not http.post then
    S.last_error = "HTTP 不可用"
    set_mode("error")
    return
  end

  S.pending_reply = ""
  S.pending_ui_code = ""
  S.pending_id = ""
  S.result_polls = 0
  set_mode("sending")
  local headers = {
    ["Content-Type"] = "application/octet-stream",
    ["X-Audio-Format"] = "pcm_s32le",
    ["X-Sample-Rate"] = tostring(APP.config.sample_rate),
    ["X-Bits"] = tostring(APP.config.sample_bits),
    ["X-Channels"] = "1",
    ["X-Reply-Limit"] = tostring(APP.config.reply_limit),
  }
  http.post(bridge_url("/api/chat"), { headers = headers, timeout = 35000 }, raw, function(code, body)
    handle_bridge_response(code, body)
  end)
end

local stop_record_poll

local function stop_recording_and_send()
  if S.mode ~= "recording" then return end
  stop_record_poll()
  stop_i2s()
  local chunks = S.chunks or {}
  local raw = table.concat(chunks)
  clear_recording()
  if not raw or #raw == 0 then
    S.last_error = "未录到声音"
    set_mode("error")
    return
  end
  submit_audio(raw)
end

local function read_recording_chunk(wait_ms)
  if not APP.running or S.mode ~= "recording" then return end
  if not i2s or not i2s.read then return end
  local pcm = i2s.read(APP.I2S_ID, APP.READ_BYTES, wait_ms or 0)
  if pcm and #pcm > 0 then
    S.chunks[#S.chunks + 1] = pcm
    S.record_bytes = S.record_bytes + #pcm
  end
  local elapsed = now_ms() - S.record_started_ms
  local max_bytes = math.floor(APP.config.sample_rate * (APP.config.sample_bits / 8) * APP.config.max_record_ms / 1000)
  if elapsed >= APP.config.max_record_ms or S.record_bytes >= max_bytes then
    stop_recording_and_send()
  end
end

local function on_i2s_rx(id, dir)
  if not APP.running or S.mode ~= "recording" or dir ~= "rx" then return end
  S.rx_events = (S.rx_events or 0) + 1
  read_recording_chunk(0)
end

stop_record_poll = function()
  local poll = APP.timers.record_poll
  if poll then
    pcall(function()
      poll:stop()
      poll:unregister()
    end)
    APP.timers.record_poll = nil
  end
end

local function stop_result_poll()
  local timer = APP.timers.result_poll
  if timer then
    pcall(function()
      timer:stop()
      timer:unregister()
    end)
    APP.timers.result_poll = nil
  end
end

local function stop_reply_delay()
  local timer = APP.timers.reply_delay
  if timer then
    pcall(function()
      timer:stop()
      timer:unregister()
    end)
    APP.timers.reply_delay = nil
  end
end

local function show_pending_reply()
  stop_reply_delay()
  stop_result_poll()
  S.reply = text_or(S.pending_reply, "没有回复")
  serial_line("ai_reply", S.reply)
  local ui_code = text_or(S.pending_ui_code, "")
  if ui_code ~= "" then
    serial_dump("ai_ui_code", ui_code)
  end
  S.pending_reply = ""
  S.pending_ui_code = ""
  S.pending_id = ""
  S.result_polls = 0
  set_mode("reply")
  if ui_code ~= "" then
    show_ai_ui(ui_code)
  end
end

local function handle_result_response(code, body)
  if S.pending_id == "" then
    stop_result_poll()
    return
  end
  if code ~= 200 then
    S.result_polls = (S.result_polls or 0) + 1
    if S.result_polls > 160 then
      stop_result_poll()
      S.last_error = "AI 回复超时"
      set_mode("error")
    end
    return
  end

  local doc, err = safe_json_decode(body)
  if type(doc) ~= "table" then
    stop_result_poll()
    S.last_error = tostring(err or "响应错误")
    set_mode("error")
    return
  end

  if doc.pending == true then
    return
  end

  stop_result_poll()
  if doc.ok == false then
    S.last_error = text_or(doc.error, "AI 回复失败")
    set_mode("error")
    return
  end

  S.pending_reply = text_or(doc.reply, "没有回复")
  S.pending_ui_code = type(doc.ui_code) == "string" and doc.ui_code or ""
  show_pending_reply()
end

start_result_poll = function()
  stop_result_poll()
  if S.pending_id == "" then return end
  if not http or not http.get then
    S.last_error = "HTTP 不可用"
    set_mode("error")
    return
  end
  if not tmr or not tmr.create then
    http.get(bridge_url("/api/result?id=" .. S.pending_id), { timeout = 5000 }, function(code, body)
      handle_result_response(code, body)
    end)
    return
  end

  local timer = tmr.create()
  APP.timers.result_poll = timer
  local in_flight = false
  timer:alarm(500, tmr.ALARM_AUTO, function()
    if not APP.running or S.mode ~= "sending" or S.pending_id == "" then
      stop_result_poll()
      return
    end
    if in_flight then return end
    in_flight = true
    http.get(bridge_url("/api/result?id=" .. S.pending_id), { timeout = 5000 }, function(code, body)
      in_flight = false
      handle_result_response(code, body)
    end)
  end)
end

schedule_reply = function()
  stop_reply_delay()
  if not tmr or not tmr.create then
    show_pending_reply()
    return
  end
  local timer = tmr.create()
  APP.timers.reply_delay = timer
  timer:alarm(350, tmr.ALARM_SINGLE or 0, function()
    show_pending_reply()
  end)
end

local function start_record_poll()
  stop_record_poll()
  if not tmr or not tmr.create then return end
  local poll = tmr.create()
  APP.timers.record_poll = poll
  poll:alarm(APP.RECORD_POLL_MS, tmr.ALARM_AUTO, function()
    if APP.running and S.mode == "recording" then
      read_recording_chunk(0)
    else
      stop_record_poll()
    end
  end)
end

local function start_recording()
  if S.mode == "recording" or S.mode == "sending" then return end
  cleanup_ai_ui(true)
  stop_reply_delay()
  stop_result_poll()
  if not i2s or not i2s.start or not i2s.read then
    S.last_error = "I2S 不可用"
    set_mode("error")
    return
  end

  clear_recording()
  S.record_started_ms = now_ms()
  S.last_error = ""
  S.transcript = ""
  S.reply = ""
  S.pending_reply = ""
  S.pending_ui_code = ""
  S.pending_id = ""
  S.result_polls = 0
  set_mode("recording")

  local ok, err = pcall(function()
    i2s.start(APP.I2S_ID, {
      mode = i2s.MODE_MASTER | i2s.MODE_RX,
      rate = APP.config.sample_rate,
      bits = APP.config.sample_bits,
      channel = i2s.CHANNEL_ONLY_LEFT,
      format = i2s.FORMAT_I2S,
      buffer_count = 4,
      buffer_len = 256,
    }, on_i2s_rx)
  end)
  if not ok then
    clear_recording()
    S.last_error = tostring(err or "录音失败")
    set_mode("error")
    stop_record_poll()
  else
    start_record_poll()
  end
end

local function on_short_press()
  if S.mode == "recording" then
    stop_recording_and_send()
  elseif S.mode ~= "sending" then
    start_recording()
  end
end

local function exit_app()
  APP.stop("exit")
  if app and app.exit then
    pcall(function() app.exit() end)
  end
end

local function bind_keys()
  if app and app.set_home_exit then
    pcall(function() app.set_home_exit(false) end)
  end
  if not key or not key.on then return end
  key.on(key.HOME, function(evt_type)
    if evt_type == key.SHORT then
      on_short_press()
    elseif evt_type == key.LONG_START or evt_type == key.EXIT then
      exit_app()
    end
  end)
end

local function build_ui()
  for key_name in pairs(UI) do
    UI[key_name] = nil
  end

  local root = nil
  if lv_obj_create then
    root = lv_obj_create(nil)
  end
  if not root or root == 0 then
    root = lv_scr_act()
    if lv_obj_clean and lv_scr_act then
      pcall(function()
        lv_obj_clean(root)
      end)
    end
  end
  APP.main_screen = root

  call(lv_obj_set_style_bg_color, root, C.bg, MAIN_STYLE)
  call(lv_obj_set_style_bg_opa, root, 255, MAIN_STYLE)

  if lv_gif_create then
    UI.gif = lv_gif_create(root)
    call(lv_obj_set_pos, UI.gif, 0, 58)
    call(lv_obj_set_size, UI.gif, 120, 120)
  end

  UI.line = lv_obj_create(root)
  call(lv_obj_set_pos, UI.line, 122, 20)
  call(lv_obj_set_size, UI.line, 1, 198)
  style_obj(UI.line, C.line, 255, nil)

  UI.status = label(root, 134, 32, 174, 20, "按下说话", APP.font_cn, C.cyan, ALIGN_LEFT)
  UI.reply = label(root, 134, 68, 174, 118, "短按开始", APP.font_cn, C.text, ALIGN_LEFT, LABEL_LONG_WRAP)
  UI.hint = label(root, 134, 207, 174, 16, "短按录音  长按退出", APP.font_cn, C.dim, ALIGN_LEFT)

  if root ~= 0 and lv_scr_load then
    pcall(function() lv_scr_load(root) end)
  end
end

local function start_timers()
  local tick = tmr and tmr.create and tmr.create() or nil
  if tick then
    APP.timers.tick = tick
    tick:alarm(250, tmr.ALARM_AUTO, function()
      if APP.running then update_ui() end
    end)
  end
end

function APP.stop()
  APP.running = false
  cleanup_ai_ui(true)
  stop_record_poll()
  stop_i2s()
  for _, timer in pairs(APP.timers or {}) do
    stop_timer(timer)
  end
  APP.timers = {}
  if key and key.off then
    pcall(key.off, key.HOME)
  end
  if app and app.set_home_exit then
    pcall(function() app.set_home_exit(true) end)
  end
  if UI.gif and lv_gif_set_src then
    pcall(lv_gif_set_src, UI.gif, nil)
  end
  release_fonts()
end

load_config()
APP.font_cn = load_font_ref(APP.APP_DIR .. "/font/msyh_cn_13.bin", FONT_12)
build_ui()
bind_keys()
start_timers()
update_ui()
