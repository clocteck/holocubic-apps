if _G.CODEX_BUDDY_APP and _G.CODEX_BUDDY_APP.stop then
  pcall(function() _G.CODEX_BUDDY_APP.stop("reload") end)
end

CODEX_BUDDY_APP = {
  VERSION = "2026-05-13-codex-buddy-v1",
  SCREEN_W = 320,
  SCREEN_H = 240,
  APP_DIR = "/sd/apps/codex_buddy",
  DEFAULT_BRIDGE_URL = "http://192.168.0.80:8788",
  POLL_MS = 2500,
  ANIM_MS = 220,
  OFFLINE_MS = 12000,
  STICKY_MS = 4500,
  USE_GIF = true,
  CHARACTER = "bufo",
}

local APP = CODEX_BUDDY_APP
local json = rawget(_G, "sjson") or rawget(_G, "json")
local function clear_root()
  if not lv_scr_act or not lv_obj_clean then
    return
  end
  local ok, root = pcall(function()
    return lv_scr_act()
  end)
  if not ok or not root then
    return
  end
  pcall(function()
    lv_obj_clean(root)
  end)
end
local MAIN_STYLE = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
local ALIGN_LEFT = rawget(_G, "LV_TEXT_ALIGN_LEFT") or 0
local ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1
local FONT_10 = rawget(_G, "LV_FONT_MONTSERRAT_10") or 10
local FONT_12 = rawget(_G, "LV_FONT_MONTSERRAT_12") or 12
local FONT_16 = rawget(_G, "LV_FONT_MONTSERRAT_16") or 16
local CANVAS_FMT = rawget(_G, "LV_IMG_CF_TRUE_COLOR")
local LABEL_LONG_CLIP = rawget(_G, "LV_LABEL_LONG_CLIP") or rawget(_G, "LABEL_LONG_CLIP")

local C = {
  bg = 0x000000,
  panel = 0x0B1117,
  panel2 = 0x101923,
  line = 0x1E252C,
  text = 0xF5F8FB,
  sub = 0xA8B6C7,
  dim = 0x677789,
  cyan = 0x59D6FF,
  green = 0x54E391,
  yellow = 0xF6C85F,
  red = 0xFF6B5F,
  pink = 0xFF86C8,
  violet = 0xAFA4FF,
}

APP.running = true
APP.timers = {}
APP.ui = {}
APP.config = {
  bridge_url = APP.DEFAULT_BRIDGE_URL,
  character = APP.CHARACTER,
  use_gif = APP.USE_GIF,
}
APP.state = {
  snapshot = nil,
  online = false,
  request_inflight = false,
  last_http_code = nil,
  last_error = "starting",
  last_seen_ms = 0,
  last_seq = nil,
  pet_state = "sleep",
  shown_gif_state = nil,
  screen = 1,
  pet_page = 1,
  info_page = 1,
  msg_scroll = 0,
  frame = 0,
  sticky_state = nil,
  sticky_until_ms = 0,
  prompt_arrived_ms = 0,
  last_prompt_id = "",
  last_action = "",
}

local S = APP.state
local UI = APP.ui

local function now_ms()
  if millis then
    local ok, value = pcall(millis)
    if ok and type(value) == "number" then
      return value
    end
  end
  if tmr and tmr.now then
    local ok, value = pcall(function() return tmr.now() end)
    if ok and type(value) == "number" then
      return math.floor(value / 1000)
    end
  end
  return 0
end

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

local function clamp(n, low, high)
  n = tonumber(n) or 0
  if n < low then return low end
  if n > high then return high end
  return n
end

local function sd_to_sdmmc(path)
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
  if not ok then
    return nil, tostring(doc)
  end
  if not doc then
    return nil, tostring(err or "decode failed")
  end
  return doc, nil
end

local function safe_json_encode(value)
  if not json or not json.encode then
    return nil, "json missing"
  end
  local ok, raw, err = pcall(function()
    local text, encode_err = json.encode(value)
    return text, encode_err
  end)
  if not ok then
    return nil, tostring(raw)
  end
  if not raw then
    return nil, tostring(err or "encode failed")
  end
  return raw, nil
end

local function load_config()
  if not file or not file.getcontents then
    return
  end
  local raw = file.getcontents(APP.APP_DIR .. "/config.json")
  if not raw or raw == "" then
    return
  end
  local cfg = safe_json_decode(raw)
  if type(cfg) ~= "table" then
    return
  end
  if type(cfg.bridge_url) == "string" and cfg.bridge_url ~= "" then
    APP.config.bridge_url = cfg.bridge_url
  end
  if type(cfg.character) == "string" and cfg.character ~= "" then
    APP.config.character = cfg.character
  end
  if type(cfg.use_gif) == "boolean" then
    APP.config.use_gif = cfg.use_gif
  end
end

local function call(fn, ...)
  if fn then
    return pcall(fn, ...)
  end
  return false
end

local function style_obj(id, bg, opa, border, radius)
  if not id then return end
  call(lv_obj_remove_style_all, id)
  call(lv_obj_set_style_bg_color, id, bg or C.panel, MAIN_STYLE)
  call(lv_obj_set_style_bg_opa, id, opa or 255, MAIN_STYLE)
  call(lv_obj_set_style_border_width, id, border and 1 or 0, MAIN_STYLE)
  if border then
    call(lv_obj_set_style_border_color, id, border, MAIN_STYLE)
    call(lv_obj_set_style_border_opa, id, 255, MAIN_STYLE)
  end
  call(lv_obj_set_style_radius, id, radius or 0, MAIN_STYLE)
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
  if align and lv_obj_set_style_text_align then
    call(lv_obj_set_style_text_align, id, align, MAIN_STYLE)
  end
end

local function label(parent, x, y, w, h, text, font, color, align)
  local id = lv_label_create(parent)
  lv_label_set_text(id, text_or(text, ""))
  call(lv_obj_set_pos, id, x, y)
  call(lv_obj_set_width, id, w)
  if h and lv_obj_set_height then
    call(lv_obj_set_height, id, h)
  end
  if LABEL_LONG_CLIP and lv_label_set_long_mode then
    call(lv_label_set_long_mode, id, LABEL_LONG_CLIP)
  end
  set_label_style(id, font, color, align or ALIGN_LEFT)
  return id
end

local function set_text(id, text)
  if id then
    call(lv_label_set_text, id, text_or(text, ""))
  end
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

local function set_visible(id, visible)
  local hidden = rawget(_G, "LV_OBJ_FLAG_HIDDEN")
  if id and hidden and lv_obj_add_flag and lv_obj_clear_flag then
    if visible then
      call(lv_obj_clear_flag, id, hidden)
    else
      call(lv_obj_add_flag, id, hidden)
    end
  end
  set_opa(id, visible and 255 or 0)
end

local function fmt_tokens(n)
  n = tonumber(n)
  if not n then return "--" end
  if n >= 1000000 then
    return string.format("%.1fM", n / 1000000)
  end
  if n >= 1000 then
    return string.format("%.1fk", n / 1000)
  end
  return tostring(math.floor(n))
end

local function fmt_money(n)
  n = tonumber(n)
  if not n then return "--" end
  return string.format("$%.2f", n)
end

local function first_number(tbl, names, fallback)
  if type(tbl) == "table" then
    for i = 1, #names do
      local v = tonumber(tbl[names[i]])
      if v then return v end
    end
  end
  return fallback
end

local function quota_pct_value(snap, scope)
  if scope == "5h" then
    return clamp(first_number(snap, {
      "quota_5h_pct",
      "quota_pct_5h",
      "remaining_5h_pct",
      "five_hour_pct",
      "quota_5h"
    }, tonumber(snap and snap.quota_pct) or 0), 0, 100)
  end
  return clamp(first_number(snap, {
    "quota_7d_pct",
    "quota_7day_pct",
    "quota_pct_7d",
    "remaining_7day_pct",
    "seven_day_pct",
    "quota_7d",
    "quota_7day"
  }, tonumber(snap and snap.quota_pct) or 0), 0, 100)
end

local function quota_color(pct)
  if pct <= 20 then return C.red end
  if pct <= 50 then return C.yellow end
  return C.green
end

local function bridge_url(path)
  local base = APP.config.bridge_url or APP.DEFAULT_BRIDGE_URL
  while base:sub(-1) == "/" do
    base = base:sub(1, -2)
  end
  return base .. path
end

local function current_prompt()
  local snap = S.snapshot
  if type(snap) ~= "table" or type(snap.prompt) ~= "table" then
    return nil
  end
  if snap.prompt.id or snap.prompt.request_id then
    return snap.prompt
  end
  return nil
end

local function set_sticky(state)
  S.sticky_state = state
  S.sticky_until_ms = now_ms() + APP.STICKY_MS
end

local function choose_pet_state()
  local now = now_ms()
  if S.sticky_state and now < S.sticky_until_ms then
    return S.sticky_state
  end
  S.sticky_state = nil

  if not S.online or (S.last_seen_ms > 0 and (now - S.last_seen_ms) > APP.OFFLINE_MS) then
    return "sleep"
  end

  local snap = S.snapshot or {}
  local waiting = tonumber(snap.waiting) or 0
  if current_prompt() or waiting > 0 then
    return "attention"
  end
  if type(snap.pet) == "table" and type(snap.pet.state) == "string" then
    local state = snap.pet.state
    if state == "sleep" or state == "idle" or state == "busy" or state == "attention" or state == "celebrate" or state == "dizzy" or state == "heart" then
      return state
    end
  end
  if tonumber(snap.running) and tonumber(snap.running) > 0 then
    return "busy"
  end
  return "idle"
end

local function state_color(state)
  if state == "sleep" then return C.dim end
  if state == "idle" then return C.green end
  if state == "busy" then return C.cyan end
  if state == "attention" then return C.yellow end
  if state == "celebrate" then return C.violet end
  if state == "dizzy" then return C.red end
  if state == "heart" then return C.pink end
  return C.sub
end

local function state_text(state)
  if state == "sleep" then return "SLEEP" end
  if state == "idle" then return "IDLE" end
  if state == "busy" then return "BUSY" end
  if state == "attention" then return "WAIT" end
  if state == "celebrate" then return "DONE" end
  if state == "dizzy" then return "ERR" end
  if state == "heart" then return "OK" end
  return "STATE"
end

local function draw_text(cvs, x, y, w, text, color, font, align, opa)
  if not lv_canvas_draw_text then return end
  local dsc = {
    color = color or C.text,
    opa = opa or 255,
    align = align or ALIGN_LEFT,
    font_size = font or 12
  }
  local ok = pcall(lv_canvas_draw_text, cvs, x, y, w, text_or(text, ""), dsc)
  if not ok then
    pcall(lv_canvas_draw_text, cvs, x, y, w, text_or(text, ""), color or C.text, opa or 255, align or ALIGN_LEFT, font or 12)
  end
end

local function draw_rect(cvs, x, y, w, h, color, radius, border, opa)
  if lv_canvas_draw_rect then
    pcall(lv_canvas_draw_rect, cvs, x, y, w, h, {
      bg_color = color,
      bg_opa = opa or 255,
      radius = radius or 0,
      border_width = border and 1 or 0,
      border_color = border or color,
      border_opa = border and 255 or 0
    })
  end
end

local function draw_line(cvs, x1, y1, x2, y2, color, width, opa)
  if lv_canvas_draw_line then
    pcall(lv_canvas_draw_line, cvs, x1, y1, x2, y2, color or C.text, opa or 255, width or 1)
  end
end

local function draw_canvas_pet(state)
  if not UI.canvas then return end
  local cvs = UI.canvas
  if lv_canvas_frame_begin then pcall(lv_canvas_frame_begin, cvs) end
  if lv_canvas_fill_bg then pcall(lv_canvas_fill_bg, cvs, C.bg, 255) end

  local f = S.frame
  local bob = 0
  if state == "busy" then
    bob = (f % 4) - 1
  elseif state == "idle" or state == "heart" then
    bob = (f % 6 == 0) and -1 or 0
  elseif state == "dizzy" then
    bob = (f % 2 == 0) and -2 or 2
  elseif state == "celebrate" then
    bob = (f % 2 == 0) and -3 or 1
  end

  local body = state_color(state)
  local x, y = 14, 18 + bob
  draw_rect(cvs, x, y + 12, 88, 72, 0x101820, 22, body, 255)
  draw_rect(cvs, x + 10, y + 2, 68, 26, 0x142331, 14, body, 255)
  draw_rect(cvs, x + 18, y + 34, 12, 12, body, 6, nil, 255)
  draw_rect(cvs, x + 58, y + 34, 12, 12, body, 6, nil, 255)

  if state == "sleep" then
    draw_line(cvs, x + 26, y + 38, x + 36, y + 38, C.sub, 2, 255)
    draw_line(cvs, x + 52, y + 38, x + 62, y + 38, C.sub, 2, 255)
    draw_text(cvs, 80, 10, 30, "z", C.dim, 16, ALIGN_CENTER, 180)
    draw_text(cvs, 94, 0, 30, "z", C.dim, 12, ALIGN_CENTER, 150)
  elseif state == "attention" then
    draw_rect(cvs, x + 26, y + 34, 9, 18, C.yellow, 4, nil, 255)
    draw_rect(cvs, x + 54, y + 34, 9, 18, C.yellow, 4, nil, 255)
    draw_text(cvs, 42, 82, 42, "!", C.yellow, 16, ALIGN_CENTER, 255)
  elseif state == "dizzy" then
    draw_text(cvs, x + 20, y + 32, 18, "x", C.red, 14, ALIGN_CENTER, 255)
    draw_text(cvs, x + 50, y + 32, 18, "x", C.red, 14, ALIGN_CENTER, 255)
    draw_line(cvs, x + 32, y + 61, x + 57, y + 57, C.red, 2, 255)
  elseif state == "heart" then
    draw_rect(cvs, x + 24, y + 34, 10, 10, C.pink, 5, nil, 255)
    draw_rect(cvs, x + 55, y + 34, 10, 10, C.pink, 5, nil, 255)
    draw_text(cvs, 37, 81, 50, "<3", C.pink, 14, ALIGN_CENTER, 255)
  else
    local eye_h = state == "celebrate" and 13 or 10
    draw_rect(cvs, x + 24, y + 34, 10, eye_h, C.text, 5, nil, 255)
    draw_rect(cvs, x + 56, y + 34, 10, eye_h, C.text, 5, nil, 255)
    if state == "busy" then
      draw_line(cvs, x + 31, y + 60, x + 57, y + 60, C.cyan, 2, 255)
      draw_line(cvs, 6, 8 + (f % 8), 24, 8 + (f % 8), C.cyan, 2, 180)
      draw_line(cvs, 84, 13 + (f % 7), 110, 13 + (f % 7), C.cyan, 2, 160)
    elseif state == "celebrate" then
      draw_line(cvs, x + 32, y + 61, x + 44, y + 66, C.violet, 2, 255)
      draw_line(cvs, x + 44, y + 66, x + 58, y + 61, C.violet, 2, 255)
      draw_text(cvs, 4, 4, 30, "+", C.yellow, 16, ALIGN_CENTER, 255)
      draw_text(cvs, 88, 8, 24, "+", C.pink, 14, ALIGN_CENTER, 255)
    else
      draw_line(cvs, x + 34, y + 61, x + 56, y + 61, C.green, 2, 220)
    end
  end

  draw_text(cvs, 0, 118, 118, state_text(state), state_color(state), 12, ALIGN_CENTER, 255)
  if lv_canvas_frame_end then pcall(lv_canvas_frame_end, cvs) end
end

local function gif_path_for_state(state)
  local dir = APP.APP_DIR .. "/assets/" .. text_or(APP.config.character, "bufo")
  local map = {
    sleep = "sleep.gif",
    idle = "idle_0.gif",
    busy = "busy.gif",
    attention = "attention.gif",
    celebrate = "celebrate.gif",
    dizzy = "dizzy.gif",
    heart = "heart.gif",
  }
  local name = map[state] or map.idle
  local path = dir .. "/" .. name
  if file and file.exists and file.exists(path) then
    return sd_to_sdmmc(path)
  end
  return nil
end

local function update_pet_view()
  local state = choose_pet_state()
  S.pet_state = state

  local src = nil
  if APP.config.use_gif and UI.gif and lv_gif_set_src then
    src = gif_path_for_state(state)
  end

  if src then
    set_opa(UI.gif, 255)
    set_opa(UI.canvas, 0)
    if S.shown_gif_state ~= state then
      S.shown_gif_state = state
      pcall(lv_gif_set_src, UI.gif, src)
    end
  else
    if UI.gif and lv_gif_set_src then
      if S.shown_gif_state ~= nil then
        pcall(lv_gif_set_src, UI.gif, nil)
      end
      S.shown_gif_state = nil
      set_opa(UI.gif, 0)
    end
    set_opa(UI.canvas, 255)
    draw_canvas_pet(state)
  end
end

local function screen_name()
  if S.screen == 2 then return "Pet" end
  if S.screen == 3 then return "Info" end
  return "Codex"
end

local function mode_count()
  if S.screen == 2 then return S.pet_page, 2 end
  if S.screen == 3 then return S.info_page, 3 end
  return 1, 3
end

local function line_clip(text, max_len)
  text = text_or(text, "")
  max_len = max_len or 34
  if #text <= max_len then return text end
  return text:sub(1, max_len - 2) .. ".."
end

local function transcript_lines()
  local lines = {}
  if S.last_error and not S.online then
    lines[1] = "No Codex connected"
    lines[2] = tostring(S.last_error)
    lines[3] = APP.config.bridge_url
    return lines
  end

  local snap = S.snapshot or {}
  if type(snap.entries) == "table" then
    for i = 1, #snap.entries do
      if snap.entries[i] ~= nil then
        lines[#lines + 1] = tostring(snap.entries[i])
      end
      if #lines >= 8 then break end
    end
  end
  if #lines == 0 and snap.msg then
    lines[1] = tostring(snap.msg)
  end
  if #lines == 0 then
    lines[1] = "waiting for bridge"
  end
  return lines
end

local function update_hud()
  local lines = transcript_lines()
  local max_scroll = #lines > 3 and (#lines - 3) or 0
  if S.msg_scroll > max_scroll then S.msg_scroll = max_scroll end
  local start = #lines - 2 - S.msg_scroll
  if start < 1 then start = 1 end

  for i = 1, 3 do
    local line = lines[start + i - 1] or ""
    local id = UI.hud_lines and UI.hud_lines[i]
    set_text(id, line_clip(line, 44))
    set_text_color(id, i == 3 and C.text or C.sub)
  end

  if UI.scroll_mark then
    set_text(UI.scroll_mark, S.msg_scroll > 0 and ("-" .. tostring(S.msg_scroll)) or "")
  end
end

local function update_approval(prompt)
  if not prompt then return end
  local waited = 0
  if S.prompt_arrived_ms > 0 then
    waited = math.floor((now_ms() - S.prompt_arrived_ms) / 1000)
  end
  local hot = waited >= 10
  set_text(UI.approve_title, "approve? " .. tostring(waited) .. "s")
  set_text_color(UI.approve_title, hot and C.red or C.dim)
  set_text(UI.approve_tool, line_clip(prompt.tool or prompt.name or "permission", 18))
  set_text(UI.approve_hint1, line_clip(prompt.hint or prompt.text or prompt.message or "approval requested", 32))
  set_text(UI.approve_hint2, "")
end

local function update_pet_page()
  local snap = S.snapshot or {}
  local pct5h = quota_pct_value(snap, "5h")
  local pct7d = quota_pct_value(snap, "7d")
  if S.pet_page == 1 then
    set_text(UI.page_title, "Pet")
    set_text(UI.page_count, "1/2")
    set_text(UI.page_lines[1], "mood       " .. state_text(S.pet_state))
    set_text(UI.page_lines[2], "fed        " .. fmt_tokens(snap.tokens_today) .. " today")
    set_text(UI.page_lines[3], "quota 5h   " .. tostring(math.floor(pct5h)) .. "% left")
    set_text(UI.page_lines[4], "quota 7d   " .. tostring(math.floor(pct7d)) .. "% left")
    set_text(UI.page_lines[5], "approved   " .. text_or((snap.last_permission and snap.last_permission.decision), "--"))
    set_text(UI.page_lines[6], "tokens     " .. fmt_tokens(snap.tokens or snap.tokens_today))
  else
    set_text(UI.page_title, "Pet")
    set_text(UI.page_count, "2/2")
    set_text(UI.page_lines[1], "MOOD")
    set_text(UI.page_lines[2], " approve fast = heart")
    set_text(UI.page_lines[3], " deny/error = dizzy")
    set_text(UI.page_lines[4], "FED")
    set_text(UI.page_lines[5], " tokens feed the buddy")
    set_text(UI.page_lines[6], "L: screens  R: page")
  end
end

local function update_info_page()
  local snap = S.snapshot or {}
  set_text(UI.page_title, "Info")
  set_text(UI.page_count, tostring(S.info_page) .. "/3")
  if S.info_page == 1 then
    set_text(UI.page_lines[1], "ABOUT")
    set_text(UI.page_lines[2], "I watch Codex sessions.")
    set_text(UI.page_lines[3], "Sleep when bridge is down.")
    set_text(UI.page_lines[4], "Busy when work is running.")
    set_text(UI.page_lines[5], "Attention asks permission.")
    set_text(UI.page_lines[6], "L approve, R deny.")
  elseif S.info_page == 2 then
    set_text(UI.page_lines[1], "CODEX")
    set_text(UI.page_lines[2], "sessions  " .. text_or(snap.total, "0"))
    set_text(UI.page_lines[3], "running   " .. text_or(snap.running, "0"))
    set_text(UI.page_lines[4], "waiting   " .. text_or(snap.waiting, "0"))
    set_text(UI.page_lines[5], "state     " .. S.pet_state)
    set_text(UI.page_lines[6], "tokens    " .. fmt_tokens(snap.tokens_today))
  else
    local age = "--"
    if S.last_seen_ms > 0 then
      age = tostring(math.floor((now_ms() - S.last_seen_ms) / 1000)) .. "s"
    end
    set_text(UI.page_lines[1], "BRIDGE")
    set_text(UI.page_lines[2], APP.config.bridge_url)
    set_text(UI.page_lines[3], "last msg  " .. age)
    set_text(UI.page_lines[4], "today     " .. fmt_money(snap.cost_today))
    set_text(UI.page_lines[5], "month     " .. fmt_money(snap.cost_month))
    set_text(UI.page_lines[6], "5h/7d     " .. tostring(math.floor(quota_pct_value(snap, "5h"))) .. "% / " .. tostring(math.floor(quota_pct_value(snap, "7d"))) .. "%")
  end
end

local function update_ui()
  local snap = S.snapshot or {}
  local state = choose_pet_state()
  S.pet_state = state
  local online = S.online and state ~= "sleep"
  local pct5h = quota_pct_value(snap, "5h")
  local pct7d = quota_pct_value(snap, "7d")
  local prompt = current_prompt()

  set_text(UI.title, screen_name())
  set_text(UI.state_badge, state_text(state))
  set_text_color(UI.state_badge, state_color(state))
  set_text(UI.link, online and "linked" or "offline")
  set_text_color(UI.link, online and C.green or C.red)
  set_text(UI.quota_5h, "5h " .. tostring(math.floor(pct5h)) .. "%")
  set_text_color(UI.quota_5h, quota_color(pct5h))
  set_text(UI.quota_7d, "7d " .. tostring(math.floor(pct7d)) .. "%")
  set_text_color(UI.quota_7d, quota_color(pct7d))

  local page, count = mode_count()
  set_text(UI.mode_count, tostring(page) .. "/" .. tostring(count))

  local show_page = not prompt and S.screen ~= 1
  local show_hud = not prompt and S.screen == 1
  local show_approval = prompt ~= nil
  set_visible(UI.hud, show_hud)
  set_visible(UI.approval, show_approval)
  set_visible(UI.page, show_page)
  set_visible(UI.hud_line, show_hud or show_approval)
  set_visible(UI.footer_left, not show_approval)
  set_visible(UI.footer_right, not show_approval)

  if prompt then
    update_approval(prompt)
  elseif S.screen == 2 then
    update_pet_page()
  elseif S.screen == 3 then
    update_info_page()
  else
    update_hud()
  end

  set_text(UI.footer_left, "L screen")
  set_text(UI.footer_right, S.screen == 1 and "R scroll" or "R page")
  set_text(UI.approve_left, "L: approve")
  set_text(UI.approve_right, "R: deny")
  update_pet_view()
end

local function handle_snapshot(doc)
  if type(doc) ~= "table" then
    S.online = false
    S.last_error = "bad state"
    set_sticky("dizzy")
    update_ui()
    return
  end

  S.snapshot = doc
  S.online = true
  S.last_error = nil
  S.last_seen_ms = now_ms()

  local prompt = current_prompt()
  local prompt_id = prompt and text_or(prompt.id or prompt.request_id, "") or ""
  if prompt_id ~= S.last_prompt_id then
    S.last_prompt_id = prompt_id
    S.prompt_arrived_ms = prompt_id ~= "" and now_ms() or 0
    if prompt_id ~= "" then
      S.screen = 1
      S.msg_scroll = 0
    end
  end

  local seq = doc.seq or doc.updated_at
  if S.last_seq ~= nil and seq ~= nil and seq ~= S.last_seq then
    S.msg_scroll = 0
  end
  if S.last_seq ~= nil and seq ~= nil and seq ~= S.last_seq then
    if doc.event == "completed" or doc.completed == true then
      set_sticky("celebrate")
    elseif doc.event == "quota" then
      set_sticky("heart")
    end
  end
  if seq ~= nil then
    S.last_seq = seq
  end

  update_ui()
end

local function fetch_state()
  if S.request_inflight or not http or not http.get then
    return
  end
  S.request_inflight = true
  local headers = "Accept: application/json\r\nCache-Control: no-cache\r\n"
  http.get(bridge_url("/state"), { headers = headers, timeout = 3500 }, function(code, body)
    S.request_inflight = false
    S.last_http_code = code
    if code ~= 200 or not body then
      S.online = false
      S.last_error = "http " .. tostring(code)
      update_ui()
      return
    end
    local doc, err = safe_json_decode(body)
    if not doc then
      S.online = false
      S.last_error = "json " .. tostring(err)
      set_sticky("dizzy")
      update_ui()
      return
    end
    handle_snapshot(doc)
  end)
end

local function post_permission(decision)
  local prompt = current_prompt()
  if not prompt or not http or not http.post then
    return
  end
  local body, err = safe_json_encode({
    id = prompt.id or prompt.request_id,
    decision = decision,
  })
  if not body then
    S.last_error = err
    set_sticky("dizzy")
    update_ui()
    return
  end

  S.last_action = decision
  set_sticky(decision == "deny" and "dizzy" or "heart")
  if S.snapshot then
    S.snapshot.prompt = nil
    S.snapshot.waiting = 0
  end
  S.last_prompt_id = ""
  S.prompt_arrived_ms = 0
  update_ui()

  http.post(bridge_url("/permission"), { headers = { ["Content-Type"] = "application/json" }, timeout = 3500 }, body, function(code)
    if code ~= 200 and code ~= 202 then
      S.last_error = "permission " .. tostring(code)
      set_sticky("dizzy")
    end
    fetch_state()
  end)
end

local function next_screen()
  S.screen = S.screen + 1
  if S.screen > 3 then S.screen = 1 end
  S.msg_scroll = 0
  update_ui()
end

local function next_subpage()
  if S.screen == 2 then
    S.pet_page = S.pet_page + 1
    if S.pet_page > 2 then S.pet_page = 1 end
  elseif S.screen == 3 then
    S.info_page = S.info_page + 1
    if S.info_page > 3 then S.info_page = 1 end
  else
    local max_scroll = #transcript_lines() > 3 and (#transcript_lines() - 3) or 0
    if max_scroll == 0 then
      S.msg_scroll = 0
    else
      S.msg_scroll = S.msg_scroll + 1
      if S.msg_scroll > max_scroll then S.msg_scroll = 0 end
    end
  end
  update_ui()
end

local function on_left(evt_type)
  if key and evt_type ~= key.SHORT and evt_type ~= key.START then
    return
  end
  if current_prompt() then
    post_permission("once")
  else
    next_screen()
  end
end

local function on_right(evt_type)
  if key and evt_type ~= key.SHORT and evt_type ~= key.START then
    return
  end
  if current_prompt() then
    post_permission("deny")
  else
    next_subpage()
  end
end

local function build_ui()
  local root = lv_scr_act()
  clear_root()

  local bg = lv_obj_create(root)
  call(lv_obj_set_pos, bg, 0, 0)
  call(lv_obj_set_size, bg, APP.SCREEN_W, APP.SCREEN_H)
  style_obj(bg, C.bg, 255, nil, 0)

  UI.title = label(root, 8, 17, 58, 18, "Codex", FONT_16, C.text, ALIGN_LEFT)
  UI.state_badge = label(root, 70, 19, 44, 14, "SLEEP", FONT_10, C.dim, ALIGN_LEFT)
  UI.link = label(root, 116, 19, 48, 14, "offline", FONT_10, C.red, ALIGN_LEFT)
  UI.quota_5h = label(root, 168, 17, 58, 18, "5h --", FONT_12, C.green, ALIGN_LEFT)
  UI.quota_7d = label(root, 230, 17, 58, 18, "7d --", FONT_12, C.green, ALIGN_LEFT)
  UI.mode_count = label(root, 294, 19, 22, 14, "1/3", FONT_10, C.dim, ALIGN_LEFT)

  local top_line = lv_obj_create(root)
  call(lv_obj_set_pos, top_line, 0, 40)
  call(lv_obj_set_size, top_line, 320, 1)
  style_obj(top_line, C.line, 190, nil, 0)
  UI.top_line = top_line

  if lv_canvas_create then
    if CANVAS_FMT then
      UI.canvas = lv_canvas_create(root, 150, 132, CANVAS_FMT)
    else
      UI.canvas = lv_canvas_create(root, 150, 132)
    end
    call(lv_obj_set_pos, UI.canvas, 85, 44)
  end
  if APP.config.use_gif and lv_gif_create then
    UI.gif = lv_gif_create(root)
    call(lv_obj_set_pos, UI.gif, 100, 44)
    set_opa(UI.gif, 0)
  end

  local hud_line = lv_obj_create(root)
  call(lv_obj_set_pos, hud_line, 0, 168)
  call(lv_obj_set_size, hud_line, 320, 1)
  style_obj(hud_line, C.line, 210, nil, 0)
  UI.hud_line = hud_line

  UI.hud = lv_obj_create(root)
  call(lv_obj_set_pos, UI.hud, 0, 170)
  call(lv_obj_set_size, UI.hud, 320, 46)
  style_obj(UI.hud, C.bg, 0, nil, 0)
  UI.hud_lines = {
    label(UI.hud, 8, 1, 286, 14, "", FONT_10, C.sub, ALIGN_LEFT),
    label(UI.hud, 8, 15, 286, 14, "", FONT_10, C.sub, ALIGN_LEFT),
    label(UI.hud, 8, 29, 286, 14, "", FONT_10, C.text, ALIGN_LEFT),
  }
  UI.scroll_mark = label(UI.hud, 296, 29, 20, 14, "", FONT_10, C.cyan, ALIGN_LEFT)

  UI.approval = lv_obj_create(root)
  call(lv_obj_set_pos, UI.approval, 0, 170)
  call(lv_obj_set_size, UI.approval, 320, 58)
  style_obj(UI.approval, C.bg, 0, nil, 0)
  UI.approve_title = label(UI.approval, 8, 1, 110, 14, "approve?", FONT_10, C.yellow, ALIGN_LEFT)
  UI.approve_tool = label(UI.approval, 8, 15, 170, 18, "permission", FONT_16, C.text, ALIGN_LEFT)
  UI.approve_hint1 = label(UI.approval, 8, 36, 210, 14, "", FONT_10, C.sub, ALIGN_LEFT)
  UI.approve_hint2 = label(UI.approval, 8, 48, 210, 10, "", FONT_10, C.sub, ALIGN_LEFT)
  UI.approve_left = label(UI.approval, 222, 35, 56, 14, "L: approve", FONT_10, C.green, ALIGN_LEFT)
  UI.approve_right = label(UI.approval, 278, 35, 42, 14, "R: deny", FONT_10, C.red, ALIGN_LEFT)

  UI.page = lv_obj_create(root)
  call(lv_obj_set_pos, UI.page, 0, 104)
  call(lv_obj_set_size, UI.page, 320, 116)
  style_obj(UI.page, C.bg, 0, nil, 0)
  UI.page_title = label(UI.page, 8, 0, 88, 14, "Info", FONT_12, C.text, ALIGN_LEFT)
  UI.page_count = label(UI.page, 288, 0, 26, 14, "1/3", FONT_10, C.dim, ALIGN_LEFT)
  UI.page_lines = {}
  for i = 1, 6 do
    UI.page_lines[i] = label(UI.page, 8, 16 + (i - 1) * 15, 304, 14, "", FONT_10, i == 1 and C.cyan or C.sub, ALIGN_LEFT)
  end

  local foot_line = lv_obj_create(root)
  call(lv_obj_set_pos, foot_line, 0, 222)
  call(lv_obj_set_size, foot_line, 320, 1)
  style_obj(foot_line, C.line, 180, nil, 0)
  UI.foot_line = foot_line
  UI.footer_left = label(root, 8, 225, 78, 12, "L screen", FONT_10, C.dim, ALIGN_LEFT)
  UI.footer_right = label(root, 242, 225, 70, 12, "R scroll", FONT_10, C.dim, ALIGN_LEFT)
end

local function start_timers()
  local poll = tmr.create()
  APP.timers.poll = poll
  poll:alarm(APP.POLL_MS, tmr.ALARM_AUTO, function()
    if APP.running and not (app and app.exiting and app.exiting()) then
      fetch_state()
    end
  end)

  local anim = tmr.create()
  APP.timers.anim = anim
  anim:alarm(APP.ANIM_MS, tmr.ALARM_AUTO, function()
    if not APP.running then return end
    S.frame = S.frame + 1
    if S.online and S.last_seen_ms > 0 and (now_ms() - S.last_seen_ms) > APP.OFFLINE_MS then
      S.online = false
      S.last_error = "stale bridge"
      update_ui()
      return
    end
    update_pet_view()
  end)
end

local function bind_keys()
  if not key or not key.on then
    return
  end
  key.on(key.LEFT, function(evt_type)
    on_left(evt_type)
  end)
  key.on(key.RIGHT, function(evt_type)
    on_right(evt_type)
  end)
end

function APP.stop()
  APP.running = false
  for _, timer in pairs(APP.timers or {}) do
    pcall(function()
      timer:stop()
      timer:unregister()
    end)
  end
  APP.timers = {}
  if key and key.off then
    pcall(key.off, key.LEFT)
    pcall(key.off, key.RIGHT)
  end
  if lv_scr_act then
    clear_root()
  end
  if UI.gif and lv_gif_set_src then
    pcall(lv_gif_set_src, UI.gif, nil)
  end
end

load_config()
build_ui()
bind_keys()
start_timers()
update_ui()
fetch_state()
