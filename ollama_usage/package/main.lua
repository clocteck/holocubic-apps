-- Ollama Cloud usage monitor.
-- Fetches https://ollama.com/api/usage with Authorization: <api_key>
-- and renders only limits.session.usage and limits.weekly.usage.
--
-- API key is read from /sd/apps/ollama_usage/api_key.txt (single line, no trailing newline).
-- If the file is missing, the app shows an error hint instead of fetching.

local APP_KEY = "APP_OLLAMA_USAGE"

local prev = rawget(_G, APP_KEY)
if prev and prev.stop then
  pcall(function() prev.stop("reload") end)
end

local APP_DIR = "/sd/apps/ollama_usage"

local APP = {
  VERSION = "0.1.0",
  DEBUG = false,
  SCREEN_W = 320,
  SCREEN_H = 240,
  API_URL = "https://ollama.com/api/usage",
  API_KEY_PATH = APP_DIR .. "/api_key.txt",
  FETCH_MS = 15 * 1000, -- refresh every 5 minutes
  APP_DIR = APP_DIR,
  route_base = (app and app.route_base and app.route_base()) or "/ollama_usage",
}
_G[APP_KEY] = APP

local MAIN = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
local ALIGN_LEFT = rawget(_G, "LV_TEXT_ALIGN_LEFT") or 0
local ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1

local FONT_12 = rawget(_G, "LV_FONT_MONTSERRAT_12") or 12
local FONT_14 = rawget(_G, "LV_FONT_MONTSERRAT_14") or 14
local FONT_16 = rawget(_G, "LV_FONT_MONTSERRAT_16") or 16
local FONT_20 = rawget(_G, "LV_FONT_MONTSERRAT_20") or 20
local FONT_28 = rawget(_G, "LV_FONT_MONTSERRAT_28") or 28

local C = {
  bg = 0x0B0F14,
  text = 0xF2F4F8,
  text_soft = 0xB8C2CC,
  text_dim = 0x6B7785,
  accent = 0x6CFF99,
  err = 0xFF6B6B,
  panel = 0x121821,
  border = 0x233040,
}

APP.running = true
APP.timer = nil
APP.ui = {}
APP.state = {
  valid = false,
  loading = false,
  last_error = nil,
  last_update_text = "",
  session_usage = "--",
  weekly_usage = "--",
}

local function log(...)
  if APP.DEBUG and print then
    print("[ollama_usage]", ...)
  end
end

local function warn(...)
  if print then
    print("[ollama_usage]", ...)
  end
end

local function call(fn, ...)
  if fn then
    return pcall(fn, ...)
  end
  return false
end

local function trim(s)
  if s == nil then return "" end
  return tostring(s):match("^%s*(.-)%s*$") or ""
end

local function read_text(path)
  if not file then return nil end
  if file.getcontents then
    local ok, raw = pcall(function() return file.getcontents(path) end)
    if ok and type(raw) == "string" then return raw end
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

local function decode_json(raw)
  if type(raw) ~= "string" or raw == "" then return nil end
  local codec = rawget(_G, "json") or rawget(_G, "sjson")
  if not codec or not codec.decode then return nil end
  local ok, doc = pcall(function() return codec.decode(raw) end)
  if ok and type(doc) == "table" then return doc end
  return nil
end

local function two(n)
  n = tonumber(n) or 0
  if n < 10 then return "0" .. tostring(n) end
  return tostring(n)
end

local function get_number(v)
  if v == nil then return nil end
  if type(v) == "number" then return v end
  return tonumber(v)
end

local function format_usage(v)
  local n = get_number(v)
  if n == nil then return "--" end
  -- API returns a fraction (0.073 = 7.3%); display as percentage.
  return string.format("%.1f%%", n * 100)
end

-- Parse the response body. Returns true on success.
local function parse_usage(body)
  local doc = decode_json(body)
  if type(doc) ~= "table" then
    return false, "JSON parse failed"
  end

  local limits = doc.limits or {}
  local session = limits.session or {}
  local weekly = limits.weekly or {}

  APP.state.session_usage = format_usage(session.usage)
  APP.state.weekly_usage = format_usage(weekly.usage)

  return true, nil
end

-- ---- UI helpers ----

local function reset_obj(id)
  if not id then return end
  call(rawget(_G, "lv_obj_remove_style_all"), id)
  if lv_obj_clear_flag and rawget(_G, "LV_OBJ_FLAG_SCROLLABLE") then
    call(lv_obj_clear_flag, id, rawget(_G, "LV_OBJ_FLAG_SCROLLABLE"))
  end
end

local function set_label_text(id, text)
  if id and lv_label_set_text then
    pcall(function() lv_label_set_text(id, tostring(text or "")) end)
  end
end

local function style_label(id, font, color, opa, align)
  if not id then return end
  call(lv_obj_set_style_text_font, id, font, MAIN)
  call(lv_obj_set_style_text_color, id, color or C.text, MAIN)
  call(rawget(_G, "lv_obj_set_style_text_opa"), id, opa or 255, MAIN)
  call(rawget(_G, "lv_obj_set_style_text_letter_space"), id, 0, MAIN)
  if align then
    call(rawget(_G, "lv_obj_set_style_text_align"), id, align, MAIN)
  end
end

local function create_label(parent, text, font, color, x, y, w, align)
  local id = lv_label_create(parent)
  reset_obj(id)
  set_label_text(id, text)
  call(lv_obj_set_pos, id, x or 0, y or 0)
  if w and w > 0 then
    call(lv_obj_set_width, id, w)
    local long_clip = rawget(_G, "LV_LABEL_LONG_CLIP") or rawget(_G, "LABEL_LONG_CLIP")
    if long_clip and lv_label_set_long_mode then
      call(lv_label_set_long_mode, id, long_clip)
    end
  end
  style_label(id, font, color, 255, align)
  return id
end

local function style_panel(id, bg, opa, radius, border_opa)
  if not id then return end
  reset_obj(id)
  call(lv_obj_set_style_bg_color, id, bg or C.panel, MAIN)
  call(lv_obj_set_style_bg_opa, id, opa or 255, MAIN)
  call(lv_obj_set_style_radius, id, radius or 6, MAIN)
  call(lv_obj_set_style_border_width, id, 1, MAIN)
  call(lv_obj_set_style_border_color, id, C.border, MAIN)
  call(lv_obj_set_style_border_opa, id, border_opa or 80, MAIN)
  call(rawget(_G, "lv_obj_set_style_pad_all"), id, 0, MAIN)
end

local function sd_to_lv(path)
  if type(path) == "string" and path:sub(1, 4) == "/sd/" then
    return "S:/" .. path:sub(5)
  end
  return path
end

local function set_img_src(id, src)
  if id and lv_img_set_src and src and src ~= "" then
    pcall(function() lv_img_set_src(id, src) end)
  end
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

local function init_ui()
  local root = lv_scr_act()
  if not root then
    warn("no active screen")
    return false
  end
  lv_obj_clean(root)
  APP.ui.root = root

  call(lv_obj_set_style_bg_color, root, C.bg, MAIN)
  call(lv_obj_set_style_bg_opa, root, 255, MAIN)
  if lv_obj_clear_flag and rawget(_G, "LV_OBJ_FLAG_SCROLLABLE") then
    call(lv_obj_clear_flag, root, rawget(_G, "LV_OBJ_FLAG_SCROLLABLE"))
  end

  -- Logo + Title bar (use inverted logo for the device's dark screen)
  -- Logo is 32x32 at y=6 (center at y=22); title is FONT_20 (~20px) centered at y=12
  local logo_src = sd_to_lv(APP.APP_DIR .. "/ollama_inverted.png")
  APP.ui.logo = create_img(root, logo_src, 10, 6, 256)
  APP.ui.title = create_label(root, "Ollama Usage", FONT_20, C.text, 46, 12, 200, ALIGN_LEFT)
  APP.ui.status = create_label(root, "Loading...", FONT_12, C.text_dim, 210, 14, 100, ALIGN_LEFT)

  -- Session panel (left half)
  local session_panel = lv_obj_create(root)
  APP.ui.session_panel = session_panel
  style_panel(session_panel, C.panel, 255, 6, 80)
  call(lv_obj_set_pos, session_panel, 10, 44)
  call(lv_obj_set_size, session_panel, 145, 132)

  APP.ui.session_title = create_label(session_panel, "Session", FONT_14, C.text_soft, 8, 10, 130, ALIGN_CENTER)
  APP.ui.session_usage = create_label(session_panel, "--", FONT_28, C.accent, 8, 50, 130, ALIGN_CENTER)

  -- Weekly panel (right half)
  local weekly_panel = lv_obj_create(root)
  APP.ui.weekly_panel = weekly_panel
  style_panel(weekly_panel, C.panel, 255, 6, 80)
  call(lv_obj_set_pos, weekly_panel, 165, 44)
  call(lv_obj_set_size, weekly_panel, 145, 132)

  APP.ui.weekly_title = create_label(weekly_panel, "Weekly", FONT_14, C.text_soft, 8, 10, 130, ALIGN_CENTER)
  APP.ui.weekly_usage = create_label(weekly_panel, "--", FONT_28, C.accent, 8, 50, 130, ALIGN_CENTER)

  -- Footer: last updated
  APP.ui.footer = create_label(root, "", FONT_12, C.text_dim, 10, 184, 300, ALIGN_LEFT)

  APP.ui.ready = true

  -- Force a screen refresh so the logo and panels render immediately,
  -- before the HTTP callback or timer fires.
  if lv_refr_now then
    pcall(function() lv_refr_now(nil) end)
  elseif lv_timer_handler then
    pcall(lv_timer_handler)
  elseif lv_task_handler then
    pcall(lv_task_handler)
  end

  return true
end

local function render()
  if not APP.running or not APP.ui.ready then return end

  if APP.state.last_error then
    set_label_text(APP.ui.status, "Error")
    style_label(APP.ui.status, FONT_12, C.err, 255, ALIGN_LEFT)
    set_label_text(APP.ui.session_usage, "--")
    set_label_text(APP.ui.weekly_usage, "--")
    set_label_text(APP.ui.footer, APP.state.last_error .. "  " .. APP.state.last_update_text)
    return
  end

  if APP.state.loading then
    set_label_text(APP.ui.status, "Loading...")
    style_label(APP.ui.status, FONT_12, C.text_dim, 255, ALIGN_LEFT)
  elseif APP.state.valid then
    set_label_text(APP.ui.status, "OK")
    style_label(APP.ui.status, FONT_12, C.accent, 255, ALIGN_LEFT)
  else
    set_label_text(APP.ui.status, "Waiting")
    style_label(APP.ui.status, FONT_12, C.text_dim, 255, ALIGN_LEFT)
  end

  set_label_text(APP.ui.session_usage, APP.state.session_usage)
  set_label_text(APP.ui.weekly_usage, APP.state.weekly_usage)
  set_label_text(APP.ui.footer, "Updated: " .. APP.state.last_update_text)
end

local function update_clock_text()
  -- Best-effort local time for "Updated" stamp.
  local t
  if time and time.getlocal then
    local ok, lt = pcall(function() return time.getlocal() end)
    if ok and type(lt) == "table" and lt.year and lt.year >= 2024 then
      t = lt
    end
  end
  if not t and os and os.date and os.time then
    local ok_now, sec = pcall(os.time)
    if ok_now and type(sec) == "number" then
      local ok, ot = pcall(os.date, "!*t", sec)
      if ok and type(ot) == "table" and ot.year then
        t = ot
      end
    end
  end
  if t then
    APP.state.last_update_text = string.format("%04d-%s-%s %s:%s:%s",
      t.year, two(t.mon), two(t.day), two(t.hour), two(t.min), two(t.sec))
  else
    APP.state.last_update_text = "(clock not synced)"
  end
end

-- ---- HTTP fetch ----

local function fetch_usage()
  if not APP.running then return end
  if APP.state.loading then return end

  local api_key = trim(read_text(APP.API_KEY_PATH))
  if api_key == "" then
    APP.state.valid = false
    APP.state.last_error = "API key missing: " .. APP.API_KEY_PATH
    APP.state.last_update_text = "(no key)"
    render()
    return
  end

  if not http or not http.get then
    APP.state.valid = false
    APP.state.last_error = "http module missing"
    render()
    return
  end

  APP.state.loading = true
  APP.state.last_error = nil
  render()

  local headers = "Authorization: " .. api_key .. "\r\n"
    .. "Accept: application/json\r\n"
    .. "Accept-Encoding: identity\r\n"

  log("GET", APP.API_URL)

  http.get(APP.API_URL, headers, function(code, body, resp_headers)
    APP.state.loading = false
    if not APP.running then return end

    if code ~= 200 or not body then
      APP.state.valid = false
      APP.state.last_error = "HTTP " .. tostring(code)
      update_clock_text()
      render()
      return
    end

    if type(body) ~= "string" or body == "" then
      APP.state.valid = false
      APP.state.last_error = "empty body"
      update_clock_text()
      render()
      return
    end

    local ok, err = parse_usage(body)
    if not ok then
      APP.state.valid = false
      APP.state.last_error = tostring(err)
      update_clock_text()
      render()
      return
    end

    APP.state.valid = true
    APP.state.last_error = nil
    update_clock_text()
    log("usage parsed", APP.state.session_usage, APP.state.weekly_usage)
    render()
  end)
end

-- Expose fetch_usage on APP so the web module can trigger a refresh.
APP.fetch_usage = fetch_usage

-- ---- API key helpers (shared with web module) ----

function APP.has_api_key()
  local key = trim(read_text(APP.API_KEY_PATH) or "")
  return key ~= ""
end

function APP.get_api_key_preview()
  local key = trim(read_text(APP.API_KEY_PATH) or "")
  if key == "" then
    return false, ""
  end
  -- Show first 4 + last 4 to confirm a key is set without leaking it.
  local len = #key
  if len <= 8 then
    return true, string.rep("*", len)
  end
  return true, key:sub(1, 4) .. "..." .. key:sub(-4)
end

function APP.save_api_key(key)
  key = trim(key or "")
  if key == "" then
    return false, "key must not be empty"
  end
  if not file then
    return false, "file module missing"
  end
  -- Ensure app directory exists (deployed path should already exist, but be safe).
  pcall(function() file.mkdir(APP.APP_DIR) end)

  if file.putcontents then
    local ok = pcall(function() file.putcontents(APP.API_KEY_PATH, key) end)
    if ok then
      -- Trigger a refresh so the device screen picks up the new key.
      pcall(function() APP.fetch_usage() end)
      return true
    end
  end
  if not file.open then
    return false, "file.open missing"
  end
  local fd = file.open(APP.API_KEY_PATH, "w")
  if not fd then
    return false, "open failed"
  end
  pcall(function() fd:write(key) end)
  pcall(function() fd:close() end)
  pcall(function() APP.fetch_usage() end)
  return true
end

-- ---- Key handling ----

local function setup_keys()
  key.on(key.HOME, function(evt_type)
    if evt_type == key.SHORT then
      app.exit()
    end
  end)

  key.on(key.UP, function(evt_type)
    if evt_type == key.SHORT and APP.running then
      fetch_usage()
    end
  end)
end

-- ---- Lifecycle ----

local function load_module(name)
  return dofile(APP.APP_DIR .. "/" .. name .. ".lua")
end

local function start()
  if not init_ui() then
    warn("init_ui failed")
    return
  end
  setup_keys()

  -- Load and start the web config module (mimics BTC main.lua wiring).
  local ok_web, Web = pcall(load_module, "web")
  if ok_web and Web and Web.new then
    APP.web = Web.new(APP, { route_base = APP.route_base })
    pcall(function() APP.web:start() end)
  else
    warn("web module load failed")
  end

  -- First fetch right away.
  fetch_usage()

  -- Periodic refresh.
  APP.timer = tmr.create()
  APP.timer:alarm(APP.FETCH_MS, tmr.ALARM_AUTO, function()
    if APP.running then
      fetch_usage()
    end
  end)
end

function APP.stop(reason)
  APP.running = false

  if APP.timer then
    pcall(function() APP.timer:stop() end)
    pcall(function() APP.timer:unregister() end)
    APP.timer = nil
  end

  if APP.web then
    pcall(function() APP.web:stop(reason) end)
    APP.web = nil
  end

  pcall(function() key.off() end)

  if APP.ui and APP.ui.root and lv_obj_clean then
    pcall(function() lv_obj_clean(APP.ui.root) end)
  end

  if rawget(_G, APP_KEY) == APP then
    _G[APP_KEY] = nil
  end
end

APP.shutdown = APP.stop

start()