if _G.MINI_CLAW_APP and _G.MINI_CLAW_APP.stop then
  pcall(function() _G.MINI_CLAW_APP.stop("reload") end)
end

MINI_CLAW_APP = {
  VERSION = "2026-05-16-mini-claw-v1",
  APP_DIR = "/sd/apps/mini_claw",
  ROUTE_BASE = (app and app.route_base and app.route_base()) or "/mini_claw",
  SCREEN_W = 320,
  SCREEN_H = 240,
  MAX_BODY_BYTES = 24 * 1024,
  MAX_REPLY_CHARS = 2800,
  DEFAULT_LLM_BASE_URL = "http://47.251.91.47/v1",
  DEFAULT_WECHAT_BASE_URL = "https://ilinkai.weixin.qq.com",
  routes = {},
  timers = {},
  running = true,
  shutting_down = false,
}

local APP = MINI_CLAW_APP
APP.API_PREFIX = APP.ROUTE_BASE .. "/api"
local json = rawget(_G, "sjson") or rawget(_G, "json")
local ui_clear_fn = rawget(_G, "ui_clear")
local ui_scr_act_fn = rawget(_G, "ui_scr_act") or lv_scr_act
local function clear_root()
  if ui_clear_fn then
    return pcall(ui_clear_fn)
  end
  if not lv_scr_act or not lv_obj_clean then
    return
  end
  local ok, root = pcall(function()
    return (ui_scr_act_fn and ui_scr_act_fn()) or lv_scr_act()
  end)
  if not ok or not root then
    return
  end
  pcall(function()
    lv_obj_clean(root)
  end)
end
local function call_webui(enabled)
  if not app or not app.set_webui then
    return false, "app.set_webui not supported"
  end
  return pcall(function() return app.set_webui(enabled) end)
end

local MAIN_STYLE = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
local ALIGN_LEFT = rawget(_G, "LV_TEXT_ALIGN_LEFT") or 0
local ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1
local LABEL_LONG_CLIP = rawget(_G, "LV_LABEL_LONG_CLIP") or rawget(_G, "LABEL_LONG_CLIP")
local LABEL_LONG_WRAP = rawget(_G, "LV_LABEL_LONG_WRAP") or LABEL_LONG_CLIP
local FONT_10 = rawget(_G, "LV_FONT_MONTSERRAT_10") or 10
local FONT_12 = rawget(_G, "LV_FONT_MONTSERRAT_12") or 12
local FONT_16 = rawget(_G, "LV_FONT_MONTSERRAT_16") or 16
local FONT_20 = rawget(_G, "LV_FONT_MONTSERRAT_20") or 20

local C = {
  bg = 0x05070A,
  panel = 0x101820,
  panel2 = 0x17212B,
  line = 0x2A3542,
  text = 0xF4F7FA,
  sub = 0xAAB4C2,
  dim = 0x6E7B8A,
  blue = 0x4DA3FF,
  green = 0x4DD88A,
  amber = 0xF4B860,
  red = 0xFF6B5F,
}

APP.config = {
  llm_base_url = APP.DEFAULT_LLM_BASE_URL,
  llm_api_key = "",
  llm_model = "gpt-4o-mini",
  llm_timeout_ms = 45000,
  max_tool_rounds = 4,
  history_limit = 10,
  wechat_enabled = false,
  wechat_token = "",
  wechat_base_url = APP.DEFAULT_WECHAT_BASE_URL,
  wechat_poll_ms = 3500,
}

APP.state = {
  online = false,
  busy = false,
  request_count = 0,
  tool_count = 0,
  wechat_inflight = false,
  wechat_sync_buf = "",
  last_error = "",
  last_user = "",
  last_reply = "Open WebUI",
  screen_note = "",
  brightness = 80,
  last_channel = "web",
  last_chat_id = "",
  started_ms = 0,
  last_wechat_poll_ms = 0,
  logs = {},
  seen = {},
  wechat_context = {},
  wechat_poll_started_ms = 0,
  wechat_qr = {
    active = false,
    completed = false,
    status = "idle",
    message = "QR idle",
    qrcode = "",
    qr_data_url = "",
    token = "",
    user_id = "",
    base_url = "",
    current_api_base_url = "",
    started_ms = 0,
  },
}

APP.history = {}
APP.ui = {}

local S = APP.state
local UI = APP.ui

local function call(fn, ...)
  if fn then return pcall(fn, ...) end
  return false
end

local function text_or(value, fallback)
  if value == nil then return fallback or "" end
  local text = tostring(value)
  if text == "" then return fallback or "" end
  return text
end

local function trim(text)
  text = text_or(text, "")
  return text:match("^%s*(.-)%s*$") or ""
end

local function clamp(n, low, high)
  n = tonumber(n) or low
  if n < low then return low end
  if n > high then return high end
  return n
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

local function app_is_exiting()
  if app and app.exiting then
    local ok, exiting = pcall(app.exiting)
    return ok and exiting
  end
  return false
end

local function sleep_ms(ms)
  if sleep then
    sleep(ms)
  elseif tmr and tmr.delay then
    tmr.delay(ms * 1000)
  end
end

local function url_encode(text)
  text = text_or(text, "")
  return (text:gsub("([^%w%-%._~])", function(ch)
    return string.format("%%%02X", string.byte(ch))
  end))
end

local function short_text(value, limit)
  local text = text_or(value, "")
  limit = limit or 48
  text = text:gsub("[\r\n]+", " ")
  if #text <= limit then return text end
  if limit <= 3 then return text:sub(1, limit) end
  return text:sub(1, limit - 3) .. "..."
end

local function normalize_space(text)
  text = text_or(text, "")
  text = text:gsub("[\r\n]+", "\n")
  text = text:gsub("[ \t]+", " ")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  return text
end

local function compare_text(text)
  text = normalize_space(text)
  text = text:gsub("%s+", "")
  return text
end

local function split_sentences(text)
  text = text_or(text, "")
  text = text:gsub("。", "。\n")
  text = text:gsub("！", "！\n")
  text = text:gsub("？", "？\n")
  text = text:gsub("%.", ".\n")
  text = text:gsub("!", "!\n")
  text = text:gsub("%?", "?\n")
  local sentences = {}
  for item in text:gmatch("[^\n]+") do
    local sentence = normalize_space(item)
    if sentence ~= "" then sentences[#sentences + 1] = sentence end
  end
  return sentences
end

local function repeated_sequence_prefix(items)
  local total = #items
  if total < 2 then return nil end
  for repeat_count = 4, 2, -1 do
    if total % repeat_count == 0 then
      local unit = total / repeat_count
      local same = true
      for i = unit + 1, total do
        if compare_text(items[i]) ~= compare_text(items[((i - 1) % unit) + 1]) then
          same = false
          break
        end
      end
      if same then
        local out = {}
        for i = 1, unit do out[#out + 1] = items[i] end
        return out
      end
    end
  end
  return nil
end

local function squash_repeated_reply(text)
  text = normalize_space(text)
  if text == "" then return "" end

  local flat = compare_text(text)
  for n = 2, 4 do
    if #flat % n == 0 then
      local part = flat:sub(1, #flat / n)
      local repeated = ""
      for _ = 1, n do repeated = repeated .. part end
      if repeated == flat then
        return part
      end
    end
  end

  local sentences = split_sentences(text)
  local sentence_prefix = repeated_sequence_prefix(sentences)
  if sentence_prefix then
    return table.concat(sentence_prefix, "\n")
  end

  local lines = {}
  for line in text:gmatch("[^\n]+") do
    local normalized_line = normalize_space(line)
    if normalized_line ~= "" then lines[#lines + 1] = normalized_line end
  end
  local line_prefix = repeated_sequence_prefix(lines)
  if line_prefix then
    return table.concat(line_prefix, "\n")
  end
  return text
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

local function safe_json_encode(value)
  if not json or not json.encode then
    return nil, "json missing"
  end
  local ok, raw, err = pcall(function()
    local text, encode_err = json.encode(value)
    return text, encode_err
  end)
  if not ok then return nil, tostring(raw) end
  if not raw then return nil, tostring(err or "encode failed") end
  return raw, nil
end

local function append_log(kind, text)
  local line = {
    at = now_ms(),
    kind = text_or(kind, "info"),
    text = short_text(text, 180),
  }
  table.insert(S.logs, 1, line)
  while #S.logs > 32 do table.remove(S.logs) end
end

local function read_request_body(req, max_bytes)
  if not req or not req.getbody then
    return "", nil
  end
  local parts = {}
  local total = 0
  while true do
    local chunk = req.getbody()
    if not chunk then break end
    total = total + #chunk
    if max_bytes and total > max_bytes then
      return nil, "body too large"
    end
    parts[#parts + 1] = chunk
  end
  return table.concat(parts), nil
end

local function json_response(status, value)
  local raw, err = safe_json_encode(value)
  if not raw then
    raw = string.format("{\"ok\":false,\"error\":%q}", text_or(err, "json encode failed"))
    status = "500 Internal Server Error"
  end
  return {
    status = status or "200 OK",
    type = "application/json; charset=utf-8",
    headers = {
      ["cache-control"] = "no-store",
      ["connection"] = "close",
    },
    body = raw,
  }
end

local function text_response(status, content_type, body, headers)
  headers = type(headers) == "table" and headers or {}
  headers["cache-control"] = headers["cache-control"] or "no-store"
  headers["connection"] = headers["connection"] or "close"
  return {
    status = status or "200 OK",
    type = content_type or "text/plain; charset=utf-8",
    headers = headers,
    body = text_or(body, ""),
  }
end

local function error_response(status, message)
  return json_response(status or "400 Bad Request", {
    ok = false,
    error = text_or(message, "request failed"),
  })
end

local function apply_config(cfg)
  if type(cfg) ~= "table" then return end
  if type(cfg.llm_base_url) == "string" then
    APP.config.llm_base_url = trim(cfg.llm_base_url)
  end
  if type(cfg.llm_api_key) == "string" then
    APP.config.llm_api_key = trim(cfg.llm_api_key)
  end
  if type(cfg.llm_model) == "string" then
    APP.config.llm_model = trim(cfg.llm_model)
  end
  APP.config.llm_timeout_ms = clamp(cfg.llm_timeout_ms or APP.config.llm_timeout_ms, 5000, 120000)
  APP.config.max_tool_rounds = clamp(cfg.max_tool_rounds or APP.config.max_tool_rounds, 1, 8)
  APP.config.history_limit = clamp(cfg.history_limit or APP.config.history_limit, 0, 30)

  if type(cfg.wechat_enabled) == "boolean" then
    APP.config.wechat_enabled = cfg.wechat_enabled
  end
  if type(cfg.wechat_token) == "string" then
    APP.config.wechat_token = trim(cfg.wechat_token)
  end
  if type(cfg.wechat_base_url) == "string" then
    APP.config.wechat_base_url = trim(cfg.wechat_base_url)
  end
  APP.config.wechat_poll_ms = clamp(cfg.wechat_poll_ms or APP.config.wechat_poll_ms, 1500, 60000)
end

local function public_config()
  return {
    llm_base_url = APP.config.llm_base_url,
    llm_api_key_set = APP.config.llm_api_key ~= "",
    llm_model = APP.config.llm_model,
    llm_timeout_ms = APP.config.llm_timeout_ms,
    max_tool_rounds = APP.config.max_tool_rounds,
    history_limit = APP.config.history_limit,
    wechat_enabled = APP.config.wechat_enabled,
    wechat_token_set = APP.config.wechat_token ~= "",
    wechat_base_url = APP.config.wechat_base_url,
    wechat_poll_ms = APP.config.wechat_poll_ms,
  }
end

local function config_path()
  return APP.APP_DIR .. "/config.json"
end

local function ensure_dir(path)
  if not file then return false, "file api missing" end
  if file.stat then
    local st = file.stat(path)
    if st and st.is_dir then return true, nil end
    if st then return false, path .. " is not a directory" end
  end
  if not file.mkdir then return true, nil end
  local ok = file.mkdir(path)
  if ok then return true, nil end
  if file.stat then
    local st = file.stat(path)
    if st and st.is_dir then return true, nil end
  end
  return false, "create dir failed: " .. path
end

local function ensure_app_dir()
  local ok_parent, parent_err = ensure_dir("/sd/apps")
  if not ok_parent then return false, parent_err end
  return ensure_dir(APP.APP_DIR)
end

local function write_text_file(path, raw)
  if not file then return false, "file api missing" end
  if file.putcontents then
    local ok_call, ok_put = pcall(function()
      return file.putcontents(path, raw)
    end)
    if ok_call and ok_put then return true, nil end
  end
  if not file.open then return false, "file write api missing" end
  local fd = file.open(path, "w+")
  if not fd then return false, "open config failed: " .. path end
  local ok_write = fd:write(raw)
  if not ok_write then
    fd:close()
    return false, "write config failed: " .. path
  end
  if fd.flush then fd:flush() end
  fd:close()
  return true, nil
end

local function load_config()
  if not file or not file.getcontents then return end
  local path = config_path()
  if file.exists and not file.exists(path) then
    return
  end
  local raw = file.getcontents(path)
  if not raw or raw == "" then return end
  local cfg = safe_json_decode(raw)
  if type(cfg) == "table" then
    apply_config(cfg)
  end
end

local function save_config(partial)
  local merged = {}
  for k, v in pairs(APP.config) do merged[k] = v end
  for k, v in pairs(partial or {}) do
    if k == "llm_api_key" and v == "__keep__" then
      merged[k] = APP.config.llm_api_key
    elseif k == "wechat_token" and v == "__keep__" then
      merged[k] = APP.config.wechat_token
    else
      merged[k] = v
    end
  end
  apply_config(merged)
  local raw, err = safe_json_encode(APP.config)
  if not raw then return false, err end
  local ok_dir, dir_err = ensure_app_dir()
  if not ok_dir then return false, dir_err end
  local ok, write_err = write_text_file(config_path(), raw)
  if not ok then return false, write_err end
  return true, nil
end

local function endpoint_url(base_url)
  local base = trim(base_url)
  if base == "" then return nil, "llm_base_url is empty" end
  base = base:gsub("/+$", "")
  if base:match("/responses$") then return base end
  if base:match("/chat/completions$") then
    return base:gsub("/chat/completions$", "/responses")
  end
  return base .. "/responses"
end

local function llm_configured()
  return APP.config.llm_base_url ~= "" and APP.config.llm_api_key ~= "" and APP.config.llm_model ~= ""
end

local function status_snapshot()
  local remain, used, total = nil, nil, nil
  if file and file.fsinfo then
    local ok, a, b, c = pcall(file.fsinfo)
    if ok then
      remain, used, total = a, b, c
    end
  end
  local version = ""
  if sys and sys.version then
    local ok, v = pcall(sys.version)
    if ok then version = text_or(v, "") end
  end
  return {
    ok = true,
    version = APP.VERSION,
    route_base = APP.ROUTE_BASE,
    llm_ready = llm_configured(),
    busy = S.busy,
    request_count = S.request_count,
    tool_count = S.tool_count,
    last_error = S.last_error,
    last_user = S.last_user,
    last_reply = S.last_reply,
    last_channel = S.last_channel,
    screen_note = S.screen_note,
    brightness = S.brightness,
    uptime_ms = now_ms() - (S.started_ms or now_ms()),
    fs = { remain = remain, used = used, total = total },
    sys_version = version,
    wechat = {
      enabled = APP.config.wechat_enabled,
      configured = APP.config.wechat_token ~= "",
      inflight = S.wechat_inflight,
      sync = S.wechat_sync_buf ~= "",
      qr = {
        active = S.wechat_qr.active,
        completed = S.wechat_qr.completed,
        status = S.wechat_qr.status,
        message = S.wechat_qr.message,
      },
    },
    logs = S.logs,
    config = public_config(),
  }
end

local function set_screen_text(text)
  S.screen_note = short_text(text, 120)
  if UI.note then
    call(lv_label_set_text, UI.note, S.screen_note)
  end
end

local function redraw()
  if UI.status then
    local state = S.busy and "BUSY" or (S.last_error ~= "" and "WARN" or "READY")
    call(lv_label_set_text, UI.status, state)
    local color = S.busy and C.amber or (S.last_error ~= "" and C.red or C.green)
    call(lv_obj_set_style_text_color, UI.status, color, MAIN_STYLE)
  end
  if UI.route then
    call(lv_label_set_text, UI.route, APP.ROUTE_BASE)
  end
  if UI.last_user then
    call(lv_label_set_text, UI.last_user, short_text(S.last_user ~= "" and S.last_user or "No messages", 44))
  end
  if UI.last_reply then
    call(lv_label_set_text, UI.last_reply, short_text(S.last_reply, 92))
  end
  if UI.wechat then
    local text = "WeChat " .. (APP.config.wechat_enabled and "on" or "off")
    if APP.config.wechat_enabled and APP.config.wechat_token == "" then text = "WeChat no token" end
    call(lv_label_set_text, UI.wechat, text)
  end
  if UI.note then
    call(lv_label_set_text, UI.note, short_text(S.screen_note, 56))
  end
end

local function tool_get_device_status()
  local snap = status_snapshot()
  snap.logs = nil
  snap.config = nil
  local raw = safe_json_encode(snap)
  return raw or "{\"ok\":true}"
end

local function tool_set_screen_message(args)
  local message = short_text(type(args) == "table" and args.message or "", 120)
  if message == "" then
    return "{\"ok\":false,\"error\":\"message is required\"}"
  end
  set_screen_text(message)
  redraw()
  return "{\"ok\":true,\"message\":\"screen updated\"}"
end

local function tool_set_brightness(args)
  local level = clamp(type(args) == "table" and args.level or 80, 1, 100)
  S.brightness = level
  if sys and sys.setbrightness then
    local ok, err = pcall(sys.setbrightness, level)
    if not ok then
      return string.format("{\"ok\":false,\"error\":%q}", tostring(err))
    end
  end
  redraw()
  return string.format("{\"ok\":true,\"level\":%d}", level)
end

local TOOL_DEFS = {
  {
    type = "function",
    ["function"] = {
      name = "get_device_status",
      description = "Read basic app, device, storage, and WeChat status.",
      parameters = {
        type = "object",
        properties = {
          include_details = {
            type = "boolean",
            description = "Optional. Return normal status details when true.",
          },
        },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "set_screen_message",
      description = "Set a short text note on the device screen.",
      parameters = {
        type = "object",
        properties = {
          message = { type = "string", description = "Short note to show on screen." },
        },
        required = { "message" },
      },
    },
  },
  {
    type = "function",
    ["function"] = {
      name = "set_brightness",
      description = "Set device screen brightness from 1 to 100.",
      parameters = {
        type = "object",
        properties = {
          level = { type = "integer", minimum = 1, maximum = 100 },
        },
        required = { "level" },
      },
    },
  },
}

local function response_tool_defs()
  local out = {}
  for i = 1, #TOOL_DEFS do
    local fn = TOOL_DEFS[i]["function"]
    if type(fn) == "table" then
      out[#out + 1] = {
        type = "function",
        name = fn.name,
        description = fn.description,
        parameters = fn.parameters,
      }
    end
  end
  return out
end

local function execute_tool(name, args_json)
  local args = {}
  if type(args_json) == "string" and args_json ~= "" then
    local parsed = safe_json_decode(args_json)
    if type(parsed) == "table" then args = parsed end
  elseif type(args_json) == "table" then
    args = args_json
  end

  S.tool_count = S.tool_count + 1
  append_log("tool", name)

  if name == "get_device_status" then return tool_get_device_status(args) end
  if name == "set_screen_message" then return tool_set_screen_message(args) end
  if name == "set_brightness" then return tool_set_brightness(args) end
  return string.format("{\"ok\":false,\"error\":\"unknown tool %s\"}", text_or(name, ""))
end

local function copy_history_into(messages)
  for i = 1, #APP.history do
    messages[#messages + 1] = APP.history[i]
  end
end

local function trim_history()
  local limit = tonumber(APP.config.history_limit) or 0
  if limit <= 0 then
    APP.history = {}
    return
  end
  local max_messages = limit * 2
  while #APP.history > max_messages do
    table.remove(APP.history, 1)
  end
end

local function response_instructions(source)
  source = type(source) == "table" and source or {}
  return table.concat({
    "You are Mini Claw, a small device agent running on an embedded Lua app.",
    "Answer directly and keep replies concise.",
    "Use tools when the user asks about device status, screen notes, or brightness.",
    "Do not claim file, image, or complex hardware control support.",
    "Current channel: " .. text_or(source.channel, "web"),
    "Current chat id: " .. text_or(source.chat_id, ""),
  }, "\n")
end

local function response_user_input(user_text)
  local parts = {}
  if #APP.history > 0 then
    parts[#parts + 1] = "Recent conversation:"
    for i = 1, #APP.history do
      local item = APP.history[i]
      local role = text_or(type(item) == "table" and item.role or "", "message")
      local content = text_or(type(item) == "table" and item.content or "", "")
      if content ~= "" then
        parts[#parts + 1] = role .. ": " .. content
      end
    end
    parts[#parts + 1] = ""
  end
  parts[#parts + 1] = "User: " .. user_text
  return table.concat(parts, "\n")
end

local function response_text(resp)
  if type(resp) ~= "table" then return "" end
  if type(resp.output_text) == "string" and resp.output_text ~= "" then
    return resp.output_text
  end
  local parts = {}
  local output = type(resp.output) == "table" and resp.output or {}
  for i = 1, #output do
    local item = output[i]
    if type(item) == "table" then
      if item.type == "message" and type(item.content) == "table" then
        for j = 1, #item.content do
          local content = item.content[j]
          if type(content) == "table" then
            local text = content.text or content.output_text
            if type(text) == "string" and text ~= "" then
              parts[#parts + 1] = text
            end
          elseif type(content) == "string" and content ~= "" then
            parts[#parts + 1] = content
          end
        end
      elseif item.type == "output_text" and type(item.text) == "string" then
        parts[#parts + 1] = item.text
      end
    end
  end
  return table.concat(parts, "\n")
end

local function response_function_calls(resp)
  local calls = {}
  local output = type(resp) == "table" and type(resp.output) == "table" and resp.output or {}
  for i = 1, #output do
    local item = output[i]
    if type(item) == "table" and item.type == "function_call" then
      calls[#calls + 1] = {
        id = item.id,
        call_id = item.call_id,
        name = item.name,
        arguments = item.arguments or "{}",
      }
    end
  end
  return calls
end

local function tool_success_reply(name, args_json, output)
  local args = {}
  if type(args_json) == "string" and args_json ~= "" then
    local parsed = safe_json_decode(args_json)
    if type(parsed) == "table" then args = parsed end
  end
  if name == "set_brightness" then
    local level = tonumber(args.level) or S.brightness
    return "已将屏幕亮度调到 " .. tostring(level) .. "。"
  end
  if name == "set_screen_message" then
    return "已更新屏幕显示文字。"
  end
  if name == "get_device_status" then
    local snap = safe_json_decode(output)
    if type(snap) == "table" then
      local wx = type(snap.wechat) == "table" and snap.wechat or {}
      return "设备在线，亮度 " .. tostring(snap.brightness or S.brightness) ..
        "，微信 " .. (wx.enabled and "已启用" or "未启用") .. "。"
    end
    return "已读取设备状态。"
  end
  return "操作已执行。"
end

local function decode_response_body(body)
  local resp, dec_err = safe_json_decode(body)
  if type(resp) == "table" then
    return resp, nil
  end

  local completed = nil
  local latest = nil
  local text_parts = {}
  local calls = {}
  local function handle_event(doc)
    if type(doc) ~= "table" then return end
    if type(doc.response) == "table" then
      latest = doc.response
      if doc.type == "response.completed" or doc.response.status == "completed" then
        completed = doc.response
      end
    end
    if doc.type == "response.output_text.delta" and type(doc.delta) == "string" then
      text_parts[#text_parts + 1] = doc.delta
    end
    local item = type(doc.item) == "table" and doc.item or nil
    if item and item.type == "function_call" then
      calls[#calls + 1] = item
    end
  end

  for line in text_or(body, ""):gmatch("[^\r\n]+") do
    local data = line:match("^data:%s*(.+)$")
    if data and data ~= "[DONE]" then
      local doc = safe_json_decode(data)
      handle_event(doc)
    end
  end

  local out = completed or latest
  if type(out) == "table" then
    if (not out.output or #out.output == 0) and #calls > 0 then
      out.output = calls
    end
    if (not out.output_text or out.output_text == "") and #text_parts > 0 then
      out.output_text = table.concat(text_parts)
    end
    return out, nil
  end
  if #text_parts > 0 then
    return { output_text = table.concat(text_parts), output = {} }, nil
  end
  return nil, dec_err or "decode failed"
end

local function call_llm(input, previous_response_id, instructions)
  local url, url_err = endpoint_url(APP.config.llm_base_url)
  if not url then return nil, url_err end

  local body = {
    model = APP.config.llm_model,
    input = input,
    tools = response_tool_defs(),
    stream = false,
  }
  if instructions and instructions ~= "" then
    body.instructions = instructions
  end
  if previous_response_id and previous_response_id ~= "" then
    body.previous_response_id = previous_response_id
  end
  local raw, enc_err = safe_json_encode(body)
  if not raw then return nil, enc_err end

  local headers = {
    ["Content-Type"] = "application/json",
    ["Accept"] = "application/json",
    ["Authorization"] = "Bearer " .. APP.config.llm_api_key,
  }
  local code, resp_body = http.post(url, {
    headers = headers,
    timeout = APP.config.llm_timeout_ms,
    bufsz = 4096,
  }, raw)

  if code ~= 200 then
    return nil, "llm http " .. tostring(code) .. ": " .. short_text(resp_body, 220)
  end

  local resp, dec_err = decode_response_body(resp_body)
  if type(resp) ~= "table" then
    return nil, "llm json " .. text_or(dec_err, "decode failed") .. ": " .. short_text(resp_body, 220)
  end
  if resp.error then
    local msg = type(resp.error) == "table" and resp.error.message or resp.error
    return nil, "llm error " .. text_or(msg, "unknown")
  end
  if type(resp.output) ~= "table" and type(resp.output_text) ~= "string" then
    return nil, "llm response missing output"
  end
  return resp, nil
end

local function run_agent(user_text, source)
  if not llm_configured() then
    return nil, "LLM is not configured. Set base URL, API key, and model in WebUI."
  end
  if not http or not http.post then
    return nil, "http client missing"
  end

  local rounds = tonumber(APP.config.max_tool_rounds) or 4
  local final_text = nil
  local fallback_text = nil
  local instructions = response_instructions(source)
  local input = response_user_input(user_text)
  local previous_response_id = ""
  for _ = 1, rounds do
    local resp, err = call_llm(input, previous_response_id, instructions)
    if not resp then
      if fallback_text then
        append_log("warn", short_text(err, 120))
        final_text = fallback_text
        break
      end
      return nil, err
    end
    previous_response_id = text_or(resp.id, previous_response_id)

    local tool_calls = response_function_calls(resp)
    if type(tool_calls) ~= "table" or #tool_calls == 0 then
      final_text = response_text(resp)
      break
    end

    for i = 1, #tool_calls do
      local tc = tool_calls[i]
      local name = text_or(tc.name, "")
      local args = tc.arguments or "{}"
      local output = execute_tool(name, args)
      fallback_text = tool_success_reply(name, args, output)
    end
    final_text = fallback_text or "操作已执行。"
    break
  end

  if not final_text or final_text == "" then
    final_text = "Done."
  end
  final_text = squash_repeated_reply(final_text)
  if #final_text > APP.MAX_REPLY_CHARS then
    final_text = final_text:sub(1, APP.MAX_REPLY_CHARS) .. "..."
  end

  APP.history[#APP.history + 1] = { role = "user", content = user_text }
  APP.history[#APP.history + 1] = { role = "assistant", content = final_text }
  trim_history()
  return final_text, nil
end

local function handle_user_message(user_text, source)
  user_text = trim(user_text)
  if user_text == "" then return nil, "message is empty" end
  source = type(source) == "table" and source or {}

  S.busy = true
  S.request_count = S.request_count + 1
  S.last_error = ""
  S.last_user = user_text
  S.last_channel = text_or(source.channel, "web")
  S.last_chat_id = text_or(source.chat_id, "")
  append_log("in", S.last_channel .. ": " .. short_text(user_text, 120))
  redraw()

  local reply, err = run_agent(user_text, source)
  S.busy = false
  if not reply then
    S.last_error = text_or(err, "agent failed")
    S.last_reply = S.last_error
    append_log("error", S.last_error)
    redraw()
    return nil, S.last_error
  end

  S.last_reply = reply
  append_log("out", short_text(reply, 140))
  redraw()
  return reply, nil
end

local function wechat_headers(auth)
  local headers = {
    ["Content-Type"] = "application/json",
    ["iLink-App-Id"] = "bot",
    ["iLink-App-ClientVersion"] = "131329",
  }
  if auth then
    headers["AuthorizationType"] = "ilink_bot_token"
    headers["Authorization"] = "Bearer " .. APP.config.wechat_token
  end
  return headers
end

local function wechat_base_url(value)
  local base = trim(value)
  if base == "" then base = APP.DEFAULT_WECHAT_BASE_URL end
  return base:gsub("/+$", "")
end

local function wechat_post(endpoint, root, callback)
  local base = wechat_base_url(APP.config.wechat_base_url)
  local raw = safe_json_encode(root)
  if not raw then
    if callback then callback(nil, "encode failed") end
    return
  end
  return http.post(base .. "/" .. endpoint, {
    headers = wechat_headers(true),
    timeout = 40000,
    bufsz = 4096,
  }, raw, callback)
end

local function wechat_qr_snapshot(include_token)
  local q = S.wechat_qr
  local out = {
    ok = true,
    active = q.active,
    completed = q.completed,
    configured = APP.config.wechat_token ~= "",
    status = q.status,
    message = q.message,
    qr_data_url = q.qr_data_url,
    user_id = q.user_id,
    base_url = q.base_url,
  }
  if include_token and q.completed and q.token ~= "" then
    out.token = q.token
  end
  return out
end

local function wechat_qr_reset(status, message)
  local q = S.wechat_qr
  q.active = false
  q.completed = false
  q.status = status or "idle"
  q.message = message or "QR idle"
  q.qrcode = ""
  q.qr_data_url = ""
  q.token = ""
  q.user_id = ""
  q.base_url = ""
  q.current_api_base_url = ""
  q.started_ms = 0
end

local function wechat_get_json_wait(base_url, endpoint, timeout_ms, label)
  if not http or not http.get then
    return nil, "http.get missing"
  end
  label = text_or(label, "wechat qr")
  local base = wechat_base_url(base_url)
  local ok_call, code, body = pcall(function()
    return http.get(base .. "/" .. endpoint, {
      headers = wechat_headers(false),
      timeout = timeout_ms or 15000,
      bufsz = 4096,
      max_redirects = 2,
    })
  end)
  if not ok_call then
    return nil, label .. " request failed: " .. short_text(code, 160)
  end
  if not code then
    return nil, label .. " timeout"
  end
  if code < 200 or code >= 300 then
    return nil, label .. " http " .. tostring(code) .. ": " .. short_text(body, 160)
  end
  local doc, err = safe_json_decode(body)
  if type(doc) ~= "table" then
    return nil, label .. " json " .. text_or(err, "bad")
  end
  return doc, nil
end

local function wechat_qr_start(force, base_url)
  local q = S.wechat_qr
  if q.active and not force then
    return true, wechat_qr_snapshot(false)
  end
  wechat_qr_reset("starting", "Fetching QR code")
  q.active = true
  q.started_ms = now_ms()
  q.current_api_base_url = wechat_base_url(base_url or APP.config.wechat_base_url)

  local doc, err = wechat_get_json_wait(q.current_api_base_url, "ilink/bot/get_bot_qrcode?bot_type=3", 15000, "wechat qr")
  if type(doc) ~= "table" then
    wechat_qr_reset("error", err or "failed to fetch QR code")
    append_log("error", S.wechat_qr.message)
    redraw()
    return false, S.wechat_qr.message
  end

  local qrcode = text_or(doc.qrcode, "")
  local qr_data_url = text_or(doc.qrcode_img_content, "")
  if qrcode == "" or qr_data_url == "" then
    wechat_qr_reset("error", "QR response missing fields")
    append_log("error", S.wechat_qr.message)
    redraw()
    return false, S.wechat_qr.message
  end

  q.qrcode = qrcode
  q.qr_data_url = qr_data_url
  q.status = "waiting_scan"
  q.message = "Scan the QR code with WeChat."
  append_log("wechat", "qr waiting")
  redraw()
  return true, wechat_qr_snapshot(false)
end

local function wechat_qr_poll_once()
  local q = S.wechat_qr
  if not q.active or q.qrcode == "" then
    return true, wechat_qr_snapshot(true)
  end
  local base = q.current_api_base_url ~= "" and q.current_api_base_url or APP.DEFAULT_WECHAT_BASE_URL
  local endpoint = "ilink/bot/get_qrcode_status?qrcode=" .. url_encode(q.qrcode)
  local doc, err = wechat_get_json_wait(base, endpoint, 12000, "wechat qr status")
  if type(doc) ~= "table" then
    local err_text = text_or(err, "")
    if err_text:find("timeout", 1, true)
      or err_text:find("ESP_ERR_HTTP_EAGAIN", 1, true)
      or err_text:find("http -1", 1, true) then
      if q.status == "scanned" then
        q.message = "Scanned. Confirm in WeChat."
      elseif q.status == "redirected" then
        q.message = "Login node redirected. Continue waiting."
      else
        q.status = "waiting_scan"
        q.message = "Waiting for scan."
      end
      redraw()
      return true, wechat_qr_snapshot(true)
    end
    q.status = "error"
    q.message = err or "QR status failed"
    append_log("warn", q.message)
    redraw()
    return false, q.message
  end

  local status = text_or(doc.status, "")
  if status == "wait" then
    q.status = "waiting_scan"
    q.message = "Waiting for scan."
  elseif status == "scanned" then
    q.status = "scanned"
    q.message = "Scanned. Confirm in WeChat."
  elseif status == "scaned_but_redirect" then
    local redirect_host = text_or(doc.redirect_host, "")
    if redirect_host ~= "" then
      q.current_api_base_url = "https://" .. redirect_host
    end
    q.status = "redirected"
    q.message = "Login node redirected. Continue waiting."
  elseif status == "expired" then
    q.active = false
    q.status = "expired"
    q.message = "QR code expired."
  elseif status == "confirmed" then
    q.active = false
    q.completed = true
    q.status = "confirmed"
    q.message = "WeChat login confirmed. Review and Save."
    q.token = text_or(doc.bot_token, q.token)
    q.user_id = text_or(doc.ilink_user_id, q.user_id)
    q.base_url = text_or(doc.baseurl, q.current_api_base_url ~= "" and q.current_api_base_url or APP.DEFAULT_WECHAT_BASE_URL)
    append_log("wechat", "qr confirmed")
  else
    q.status = "error"
    q.message = "Unknown QR status."
  end
  redraw()
  return true, wechat_qr_snapshot(true)
end

local function wechat_qr_cancel()
  wechat_qr_reset("cancelled", "WeChat login cancelled.")
  append_log("wechat", "qr cancelled")
  redraw()
  return true, wechat_qr_snapshot(false)
end

local function wechat_send_text(chat_id, message)
  if not APP.config.wechat_enabled or APP.config.wechat_token == "" then
    return false, "wechat not configured"
  end
  local client_id = "mini-" .. tostring(now_ms()) .. "-" .. tostring(math.random(1000, 9999))
  local root = {
    msg = {
      from_user_id = "",
      to_user_id = chat_id,
      client_id = client_id,
      message_type = 2,
      message_state = 2,
      item_list = {
        {
          type = 1,
          text_item = { text = message },
        },
      },
    },
    base_info = {
      channel_version = "esp-claw-wechat",
    },
  }
  local context_token = text_or(S.wechat_context[chat_id], "")
  if context_token ~= "" then
    root.msg.context_token = context_token
  end
  local ok_call, code, body = pcall(function()
    return wechat_post("ilink/bot/sendmessage", root)
  end)
  if not ok_call then
    return false, "wechat send failed: " .. short_text(code, 160)
  end
  if not code or code < 200 or code >= 300 then
    return false, "wechat send http " .. tostring(code) .. ": " .. short_text(body, 160)
  end
  return true, nil
end

local function wechat_text_from_msg(msg)
  if type(msg) ~= "table" or type(msg.item_list) ~= "table" then return "" end
  local parts = {}
  for i = 1, #msg.item_list do
    local item = msg.item_list[i]
    if type(item) == "table" and tonumber(item.type) == 1 and type(item.text_item) == "table" then
      local text = text_or(item.text_item.text, "")
      if text ~= "" then parts[#parts + 1] = text end
    end
  end
  return table.concat(parts, "\n")
end

local function wechat_next_sync(doc)
  if type(doc) ~= "table" then return nil end
  local keys = {
    "get_updates_buf",
    "getupdates_buf",
    "next_get_updates_buf",
    "sync_buf",
  }
  for i = 1, #keys do
    local value = doc[keys[i]]
    if type(value) == "string" then return value, keys[i] end
  end
  return nil, nil
end

local function wechat_msg_label(msg)
  if type(msg) ~= "table" then return "bad" end
  local id = text_or(msg.message_id, "")
  if type(msg.message_id) == "number" then
    id = "num:" .. id
  end
  local from = text_or(msg.from_user_id, "")
  local group = text_or(msg.group_id, "")
  return "id=" .. short_text(id, 20) .. " from=" .. short_text(from ~= "" and from or group, 18)
end

local function wechat_seen_key(chat_id, from_user_id, msg, text)
  local message_id = text_or(type(msg) == "table" and msg.message_id or "", "")
  local t = text_or(type(msg) == "table" and (msg.create_time or msg.timestamp or msg.time) or "", "")
  local client_id = text_or(type(msg) == "table" and msg.client_id or "", "")
  return table.concat({
    "wxmsg",
    text_or(chat_id, ""),
    text_or(from_user_id, ""),
    message_id,
    t,
    client_id,
    short_text(normalize_space(text), 180),
  }, "|")
end

local function seen_message(id)
  id = text_or(id, "")
  if id == "" then return false end
  if S.seen[id] then return true end
  S.seen[id] = true
  local count = 0
  for _ in pairs(S.seen) do count = count + 1 end
  if count > 80 then S.seen = { [id] = true } end
  return false
end

local function handle_wechat_msg(msg)
  local from_user_id = text_or(msg.from_user_id, "")
  local group_id = text_or(msg.group_id, "")
  local chat_id = group_id ~= "" and group_id or from_user_id
  if chat_id == "" then return end
  local context_token = text_or(msg.context_token, "")
  if context_token ~= "" then
    S.wechat_context[chat_id] = context_token
  end

  local text = trim(wechat_text_from_msg(msg))
  if text == "" then return end

  local seen_key = wechat_seen_key(chat_id, from_user_id, msg, text)
  if seen_message(seen_key) then
    return
  end

  local reply, err = handle_user_message(text, {
    channel = "wechat",
    chat_id = chat_id,
    sender_id = from_user_id,
    message_id = text_or(msg.message_id, ""),
  })
  if not reply then
    reply = "Mini Claw error: " .. short_text(err, 180)
  end
  local ok, send_err = wechat_send_text(chat_id, reply)
  if not ok then append_log("error", send_err or "wechat send failed") end
end

local function wechat_poll_once()
  if not APP.config.wechat_enabled or APP.config.wechat_token == "" or not http or not http.post then
    return
  end
  local now = now_ms()
  if S.wechat_inflight then
    if now > 0 and S.wechat_poll_started_ms > 0 and now - S.wechat_poll_started_ms > 55000 then
      append_log("warn", "wechat poll watchdog reset")
      S.wechat_inflight = false
    else
      return
    end
  end
  if S.busy then return end
  S.wechat_inflight = true
  S.wechat_poll_started_ms = now
  local root = {
    get_updates_buf = S.wechat_sync_buf or "",
    base_info = {
      channel_version = "esp-claw-wechat",
    },
  }

  local function finish_poll()
    S.wechat_inflight = false
    S.wechat_poll_started_ms = 0
    S.last_wechat_poll_ms = now_ms()
  end

  local function handle_poll_response(code, body)
    if code ~= 200 then
      append_log("warn", "wechat poll http " .. tostring(code))
      finish_poll()
      redraw()
      return
    end
    local doc, err = safe_json_decode(body)
    if type(doc) ~= "table" then
      append_log("warn", "wechat json " .. text_or(err, "bad"))
      finish_poll()
      redraw()
      return
    end
    local ret = tonumber(doc.ret or 0) or 0
    local errcode = tonumber(doc.errcode or 0) or 0
    if ret ~= 0 or errcode ~= 0 then
      append_log("warn", "wechat api ret=" .. tostring(ret) .. " err=" .. tostring(errcode))
      finish_poll()
      redraw()
      return
    end
    local next_sync, sync_key = wechat_next_sync(doc)
    if next_sync ~= nil then
      local old_len = #(S.wechat_sync_buf or "")
      S.wechat_sync_buf = next_sync
      if #next_sync ~= old_len then
        append_log("wechat", "sync " .. tostring(old_len) .. "->" .. tostring(#next_sync) .. " " .. text_or(sync_key, ""))
      end
    else
      append_log("warn", "wechat no sync key")
    end
    local msgs = type(doc.msgs) == "table" and doc.msgs or {}
    if #msgs > 0 then append_log("wechat", "msgs " .. tostring(#msgs) .. " " .. wechat_msg_label(msgs[1])) end
    for i = 1, #msgs do
      local ok, msg_err = pcall(handle_wechat_msg, msgs[i])
      if not ok then
        append_log("error", "wechat msg " .. short_text(msg_err, 140))
      end
    end
    finish_poll()
    redraw()
  end

  local ok_call, code, body = pcall(function()
    return wechat_post("ilink/bot/getupdates", root, handle_poll_response)
  end)
  if not ok_call then
    append_log("error", "wechat poll start " .. short_text(code, 140))
    finish_poll()
    redraw()
  elseif type(code) == "number" then
    handle_poll_response(code, body)
  end
end

local function route_chat(req)
  local body, body_err = read_request_body(req, APP.MAX_BODY_BYTES)
  if not body then return error_response("413 Payload Too Large", body_err) end
  local doc, err = safe_json_decode(body)
  if type(doc) ~= "table" then return error_response("400 Bad Request", err or "invalid json") end
  local message = trim(doc.message)
  if message == "" then return error_response("400 Bad Request", "message is required") end
  if doc.reset then APP.history = {} end
  local reply, agent_err = handle_user_message(message, {
    channel = "web",
    chat_id = "web",
  })
  if not reply then return error_response("500 Internal Server Error", agent_err) end
  return json_response("200 OK", {
    ok = true,
    reply = reply,
    state = status_snapshot(),
  })
end

local function route_config_get()
  return json_response("200 OK", {
    ok = true,
    config = public_config(),
  })
end

local function route_config_post(req)
  local body, body_err = read_request_body(req, APP.MAX_BODY_BYTES)
  if not body then return error_response("413 Payload Too Large", body_err) end
  local doc, err = safe_json_decode(body)
  if type(doc) ~= "table" then return error_response("400 Bad Request", err or "invalid json") end
  local ok, save_err = save_config(doc)
  if not ok then return error_response("500 Internal Server Error", save_err) end
  append_log("config", "saved")
  redraw()
  return json_response("200 OK", {
    ok = true,
    config = public_config(),
  })
end

local route_reset

local function route_api(req)
  local body, body_err = read_request_body(req, APP.MAX_BODY_BYTES)
  if not body then return error_response("413 Payload Too Large", body_err) end
  local doc, err = safe_json_decode(body)
  if type(doc) ~= "table" then return error_response("400 Bad Request", err or "invalid json") end

  local action = trim(doc.action)
  if action == "state" then
    return json_response("200 OK", status_snapshot())
  end
  if action == "config" then
    return route_config_get()
  end
  if action == "wechat_qr_start" then
    local ok, result = wechat_qr_start(doc.force ~= false, doc.wechat_base_url)
    if not ok then return error_response("500 Internal Server Error", result) end
    return json_response("200 OK", result)
  end
  if action == "wechat_qr_status" then
    local ok, result = wechat_qr_poll_once()
    if not ok then return error_response("500 Internal Server Error", result) end
    return json_response("200 OK", result)
  end
  if action == "wechat_qr_cancel" then
    local ok, result = wechat_qr_cancel()
    if not ok then return error_response("500 Internal Server Error", result) end
    return json_response("200 OK", result)
  end
  if action == "save_config" then
    local ok, save_err = save_config(doc)
    if not ok then return error_response("500 Internal Server Error", save_err) end
    append_log("config", "saved")
    redraw()
    return json_response("200 OK", {
      ok = true,
      config = public_config(),
    })
  end
  if action == "chat" then
    local message = trim(doc.message)
    if message == "" then return error_response("400 Bad Request", "message is required") end
    if doc.reset then APP.history = {} end
    local reply, agent_err = handle_user_message(message, {
      channel = "web",
      chat_id = "web",
    })
    if not reply then return error_response("500 Internal Server Error", agent_err) end
    return json_response("200 OK", {
      ok = true,
      reply = reply,
      state = status_snapshot(),
    })
  end
  if action == "reset" then
    return route_reset()
  end
  return error_response("404 Not Found", "unknown action")
end

route_reset = function()
  APP.history = {}
  S.last_error = ""
  S.last_user = ""
  S.last_reply = "Session cleared"
  append_log("session", "cleared")
  redraw()
  return json_response("200 OK", { ok = true, state = status_snapshot() })
end

APP.HTML = [==[
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Mini Claw</title>
<style>
:root{
  color-scheme:light;
  --bg:#f5f7fb;
  --surface:#ffffff;
  --surface-2:#eef4ff;
  --text:#17202a;
  --muted:#667085;
  --line:#d8e0ea;
  --blue:#1769e0;
  --blue-soft:#e8f1ff;
  --orange:#c56a10;
  --red:#c0362c;
  --green:#168257;
  --shadow:0 12px 34px rgba(27,43,70,.08);
  --radius:8px;
  font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Roboto,Arial,sans-serif;
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font-size:16px;line-height:1.5}
button,input,textarea{font:inherit}
button{min-height:44px;border:1px solid var(--line);border-radius:8px;background:#fff;color:var(--text);padding:0 14px;cursor:pointer}
button.primary{background:var(--blue);border-color:var(--blue);color:#fff}
button.danger{color:var(--red)}
button:disabled{opacity:.55;cursor:not-allowed}
button:focus-visible,input:focus-visible,textarea:focus-visible{outline:3px solid rgba(23,105,224,.25);outline-offset:2px}
.shell{min-height:100dvh;display:grid;grid-template-columns:minmax(0,1fr) 340px;gap:18px;padding:18px;max-width:1180px;margin:0 auto}
.main,.side{display:flex;flex-direction:column;gap:14px}
.panel{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);box-shadow:var(--shadow)}
.top{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:14px 16px}
h1{font-size:1.15rem;line-height:1.2;margin:0}
.status{display:flex;gap:8px;align-items:center;color:var(--muted);font-size:.9rem}
.dot{width:9px;height:9px;border-radius:99px;background:var(--green)}
.dot.busy{background:var(--orange)}
.dot.warn{background:var(--red)}
.chat{display:flex;flex-direction:column;height:min(720px,calc(100dvh - 150px));min-height:480px}
.messages{flex:1;overflow:auto;padding:16px;display:flex;flex-direction:column;gap:12px}
.msg{max-width:78%;padding:10px 12px;border-radius:8px;border:1px solid var(--line);white-space:pre-wrap;word-break:break-word}
.msg.user{align-self:flex-end;background:var(--blue-soft);border-color:#cfe1ff}
.msg.assistant{align-self:flex-start;background:#fff}
.composer{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:10px;border-top:1px solid var(--line);padding:12px}
textarea{width:100%;min-height:54px;max-height:160px;resize:vertical;border:1px solid var(--line);border-radius:8px;padding:10px 12px;color:var(--text)}
.section{padding:14px 16px;display:flex;flex-direction:column;gap:10px}
.section h2{font-size:.95rem;margin:0}
.grid{display:grid;grid-template-columns:1fr;gap:10px}
label{display:flex;flex-direction:column;gap:5px;color:var(--muted);font-size:.82rem}
input{width:100%;height:42px;border:1px solid var(--line);border-radius:8px;padding:0 10px;color:var(--text)}
.row{display:flex;gap:10px;align-items:center;justify-content:space-between;flex-wrap:wrap}
.pill{display:inline-flex;align-items:center;min-height:30px;padding:3px 9px;border-radius:999px;background:var(--surface-2);color:var(--muted);font-size:.82rem}
.qrbox{border:1px solid var(--line);border-radius:8px;background:#fbfdff;padding:10px;display:flex;flex-direction:column;gap:9px}
.qr-actions{display:flex;gap:8px;flex-wrap:wrap}
.qr-actions button{min-height:38px;padding:0 11px}
.qrstage{min-height:238px;display:flex;align-items:center;justify-content:center;background:#fff;border:1px solid var(--line);border-radius:8px}
.qrstage canvas{width:220px;height:220px;image-rendering:pixelated}
.link{color:var(--blue);font-size:.82rem;text-decoration:none}
.link:hover{text-decoration:underline}
.logs{display:flex;flex-direction:column;gap:6px;max-height:210px;overflow:auto}
.log{font-size:.82rem;color:var(--muted);border-top:1px solid var(--line);padding-top:6px}
.error{color:var(--red);font-size:.9rem;min-height:1.4em}
.small{color:var(--muted);font-size:.82rem}
@media (max-width:840px){
  .shell{grid-template-columns:1fr;padding:10px;gap:10px}
  .chat{height:calc(100dvh - 118px);min-height:390px}
  .msg{max-width:92%}
}
</style>
</head>
<body>
<main class="shell">
  <section class="main">
    <div class="panel top">
      <div>
        <h1>Mini Claw</h1>
        <div class="small" id="route">connecting</div>
      </div>
      <div class="status"><span id="dot" class="dot"></span><span id="statusText">ready</span></div>
    </div>
    <div class="panel chat">
      <div id="messages" class="messages"></div>
      <form id="composer" class="composer">
        <textarea id="input" placeholder="Message"></textarea>
        <button id="send" class="primary" type="submit">Send</button>
      </form>
    </div>
    <div class="error" id="error"></div>
  </section>
  <aside class="side">
    <div class="panel section">
      <div class="row">
        <h2>Runtime</h2>
        <button id="reset" class="danger" type="button">Reset</button>
      </div>
      <div class="row">
        <span class="pill" id="llmReady">LLM</span>
        <span class="pill" id="wechatReady">WeChat</span>
        <span class="pill" id="toolCount">Tools 0</span>
      </div>
    </div>
    <form id="configForm" class="panel section">
      <h2>LLM</h2>
      <div class="grid">
        <label>Base URL<input id="llm_base_url" autocomplete="off"></label>
        <label>Model<input id="llm_model" autocomplete="off"></label>
        <label>API Key<input id="llm_api_key" type="password" autocomplete="off" placeholder="keep existing"></label>
      </div>
      <h2>WeChat</h2>
      <div class="qrbox">
        <div class="row">
          <span class="small" id="wechatQrStatus">Status: idle</span>
          <div class="qr-actions">
            <button id="wechatQrStart" type="button">Scan</button>
            <button id="wechatQrCancel" type="button">Cancel</button>
          </div>
        </div>
        <div class="qrstage">
          <canvas id="wechatQr" width="220" height="220" aria-label="WeChat login QR code"></canvas>
        </div>
        <a id="wechatQrLink" class="link" href="#" target="_blank" rel="noopener noreferrer" hidden>Open login link</a>
        <div class="small">Scan with WeChat. After confirmation, review the fields below and Save.</div>
      </div>
      <div class="grid">
        <label>Enabled<input id="wechat_enabled" type="checkbox"></label>
        <label>Base URL<input id="wechat_base_url" autocomplete="off"></label>
        <label>Token<input id="wechat_token" type="password" autocomplete="off" placeholder="keep existing"></label>
      </div>
      <button class="primary" type="submit">Save</button>
    </form>
    <div class="panel section">
      <h2>Logs</h2>
      <div id="logs" class="logs"></div>
    </div>
  </aside>
</main>
<script>
const BASE="__BASE__";
const $=id=>document.getElementById(id);
const messages=[];
function showError(text){$("error").textContent=text||""}
function addMsg(role,text){
  messages.push({role,text});
  const wrap=$("messages");
  const el=document.createElement("div");
  el.className="msg "+(role==="user"?"user":"assistant");
  el.textContent=text;
  wrap.appendChild(el);
  wrap.scrollTop=wrap.scrollHeight;
}
async function api(action,payload){
  const res=await fetch(BASE+"/api",{
    method:"POST",
    headers:{"Content-Type":"application/json"},
    body:JSON.stringify(Object.assign({action},payload||{}))
  });
  const text=await res.text();
  let data={};
  try{data=text?JSON.parse(text):{};}catch{data={ok:false,error:text||"bad response"}}
  if(!res.ok||data.ok===false) throw new Error(data.error||res.statusText);
  return data;
}
const QR_SPEC=[
  {v:1,ecc:7,blocks:[19]},{v:2,ecc:10,blocks:[34]},{v:3,ecc:15,blocks:[55]},
  {v:4,ecc:20,blocks:[80]},{v:5,ecc:26,blocks:[108]},{v:6,ecc:18,blocks:[68,68]},
  {v:7,ecc:20,blocks:[78,78]},{v:8,ecc:24,blocks:[97,97]},{v:9,ecc:30,blocks:[116,116]},
  {v:10,ecc:18,blocks:[68,68,69,69]}
];
const QR_ALIGN={1:[],2:[6,18],3:[6,22],4:[6,26],5:[6,30],6:[6,34],7:[6,22,38],8:[6,24,42],9:[6,26,46],10:[6,28,50]};
const GF_EXP=new Array(512),GF_LOG=new Array(256);
(function(){let x=1;for(let i=0;i<255;i++){GF_EXP[i]=x;GF_LOG[x]=i;x<<=1;if(x&256)x^=0x11d}for(let i=255;i<512;i++)GF_EXP[i]=GF_EXP[i-255]})();
function gfMul(a,b){return a&&b?GF_EXP[GF_LOG[a]+GF_LOG[b]]:0}
function rsGen(deg){
  let poly=[1];
  for(let i=0;i<deg;i++){
    const next=new Array(poly.length+1).fill(0);
    for(let j=0;j<poly.length;j++){next[j]^=poly[j];next[j+1]^=gfMul(poly[j],GF_EXP[i])}
    poly=next;
  }
  return poly.slice(1);
}
function rsEncode(data,deg){
  const gen=rsGen(deg),rem=new Array(deg).fill(0);
  data.forEach(b=>{
    const factor=b^rem.shift();
    rem.push(0);
    for(let i=0;i<deg;i++)rem[i]^=gfMul(gen[i],factor);
  });
  return rem;
}
function makeQr(data){
  const bytes=Array.from(new TextEncoder().encode(data));
  let spec=null;
  for(const s of QR_SPEC){
    const cc=s.v<10?8:16,cap=s.blocks.reduce((a,b)=>a+b,0)*8;
    if(4+cc+bytes.length*8<=cap){spec=s;break}
  }
  if(!spec)throw new Error("QR data too long");
  const capBytes=spec.blocks.reduce((a,b)=>a+b,0),bits=[];
  const push=(val,len)=>{for(let i=len-1;i>=0;i--)bits.push((val>>>i)&1)};
  push(4,4);push(bytes.length,spec.v<10?8:16);bytes.forEach(b=>push(b,8));
  for(let i=0;i<4&&bits.length<capBytes*8;i++)bits.push(0);
  while(bits.length%8)bits.push(0);
  const dataCw=[];
  for(let i=0;i<bits.length;i+=8)dataCw.push(bits.slice(i,i+8).reduce((a,b)=>(a<<1)|b,0));
  for(let pad=0xec;dataCw.length<capBytes;pad=pad===0xec?0x11:0xec)dataCw.push(pad);
  const blocks=[];let off=0;
  spec.blocks.forEach(len=>{const d=dataCw.slice(off,off+len);off+=len;blocks.push({d,e:rsEncode(d,spec.ecc)})});
  const code=[];
  for(let i=0;i<Math.max(...blocks.map(b=>b.d.length));i++)blocks.forEach(b=>{if(i<b.d.length)code.push(b.d[i])});
  for(let i=0;i<spec.ecc;i++)blocks.forEach(b=>code.push(b.e[i]));
  const n=17+4*spec.v,m=Array.from({length:n},()=>Array(n).fill(false)),fn=Array.from({length:n},()=>Array(n).fill(false));
  const set=(r,c,v,f)=>{if(r>=0&&r<n&&c>=0&&c<n){m[r][c]=!!v;if(f)fn[r][c]=true}};
  const getB=(x,i)=>((x>>>i)&1)!==0;
  const finder=(r,c)=>{for(let y=-1;y<=7;y++)for(let x=-1;x<=7;x++){const rr=r+y,cc=c+x;if(rr<0||rr>=n||cc<0||cc>=n)continue;const on=y>=0&&y<=6&&x>=0&&x<=6&&(y===0||y===6||x===0||x===6||(y>=2&&y<=4&&x>=2&&x<=4));set(rr,cc,on,true)}};
  finder(0,0);finder(0,n-7);finder(n-7,0);
  for(let i=8;i<n-8;i++){set(6,i,i%2===0,true);set(i,6,i%2===0,true)}
  (QR_ALIGN[spec.v]||[]).forEach(r=>(QR_ALIGN[spec.v]||[]).forEach(c=>{
    if((r<9&&c<9)||(r<9&&c>n-10)||(r>n-10&&c<9))return;
    for(let y=-2;y<=2;y++)for(let x=-2;x<=2;x++)set(r+y,c+x,Math.max(Math.abs(x),Math.abs(y))!==1,true);
  }));
  set(n-8,8,true,true);
  function format(mask){
    const data=(1<<3)|mask;let rem=data;
    for(let i=0;i<10;i++)rem=(rem<<1)^(((rem>>>9)&1)?0x537:0);
    const b=((data<<10)|rem)^0x5412;
    for(let i=0;i<=5;i++)set(i,8,getB(b,i),true);
    set(7,8,getB(b,6),true);set(8,8,getB(b,7),true);set(8,7,getB(b,8),true);
    for(let i=9;i<15;i++)set(8,14-i,getB(b,i),true);
    for(let i=0;i<8;i++)set(8,n-1-i,getB(b,i),true);
    for(let i=8;i<15;i++)set(n-15+i,8,getB(b,i),true);
  }
  function versionInfo(){
    if(spec.v<7)return;
    let rem=spec.v;
    for(let i=0;i<12;i++)rem=(rem<<1)^(((rem>>>11)&1)?0x1f25:0);
    const b=(spec.v<<12)|rem;
    for(let i=0;i<18;i++){const bit=getB(b,i),a=n-11+i%3,bb=Math.floor(i/3);set(a,bb,bit,true);set(bb,a,bit,true)}
  }
  format(0);versionInfo();
  let bit=0,up=true;
  for(let c=n-1;c>0;c-=2){
    const right=c<=6?c-1:c;
    for(let j=0;j<n;j++){
      const r=up?n-1-j:j;
      for(let dc=0;dc<2;dc++){
        const cc=right-dc;
        if(fn[r][cc])continue;
        const val=bit<code.length*8?getB(code[Math.floor(bit/8)],7-bit%8):false;
        set(r,cc,val,false);bit++;
      }
    }
    up=!up;
  }
  for(let r=0;r<n;r++)for(let c=0;c<n;c++)if(!fn[r][c]&&((r+c)%2===0))m[r][c]=!m[r][c];
  format(0);versionInfo();
  return m;
}
function renderQr(data){
  const canvas=$("wechatQr"),ctx=canvas.getContext("2d");
  canvas.width=220;canvas.height=220;
  ctx.fillStyle="#fff";ctx.fillRect(0,0,220,220);
  if(!data)return;
  const matrix=makeQr(data),quiet=4,modules=matrix.length+quiet*2,px=Math.max(2,Math.floor(220/modules)),size=px*modules,off=Math.floor((220-size)/2);
  ctx.fillStyle="#fff";ctx.fillRect(0,0,220,220);
  ctx.fillStyle="#111";
  matrix.forEach((row,r)=>row.forEach((on,c)=>{if(on)ctx.fillRect(off+(c+quiet)*px,off+(r+quiet)*px,px,px)}));
}
function applyState(st){
  $("route").textContent=st.route_base||BASE;
  $("statusText").textContent=st.busy?"busy":(st.last_error?"warn":"ready");
  $("dot").className="dot "+(st.busy?"busy":(st.last_error?"warn":""));
  $("llmReady").textContent=st.llm_ready?"LLM ready":"LLM missing";
  $("wechatReady").textContent=st.wechat&&st.wechat.enabled?(st.wechat.configured?"WeChat on":"WeChat token"):"WeChat off";
  $("toolCount").textContent="Tools "+(st.tool_count||0);
  if(st.wechat&&st.wechat.qr) setWechatQrText(st.wechat.qr);
  const logs=$("logs");
  logs.innerHTML="";
  (st.logs||[]).slice(0,18).forEach(item=>{
    const el=document.createElement("div");
    el.className="log";
    el.textContent=(item.kind||"info")+": "+(item.text||"");
    logs.appendChild(el);
  });
}
let wechatQrTimer=null;
function stopWechatQrPoll(){
  if(wechatQrTimer){clearTimeout(wechatQrTimer);wechatQrTimer=null}
}
function setWechatQrText(qr){
  const text=qr&&qr.status?("Status: "+qr.status):"Status: idle";
  $("wechatQrStatus").textContent=qr&&qr.message?text+" - "+qr.message:text;
}
function setWechatQrBusy(busy){
  $("wechatQrStart").disabled=!!busy;
  $("wechatQrCancel").disabled=!!busy;
}
function applyWechatQr(qr){
  setWechatQrText(qr);
  try{renderQr(qr&&qr.qr_data_url?qr.qr_data_url:"")}catch(err){showError("QR render: "+(err.message||String(err)))}
  const link=$("wechatQrLink");
  if(qr&&qr.qr_data_url){link.href=qr.qr_data_url;link.hidden=false}else{link.hidden=true}
  if(qr&&qr.completed&&qr.token){
    $("wechat_token").value=qr.token;
    $("wechat_enabled").checked=true;
    if(qr.base_url)$("wechat_base_url").value=qr.base_url;
    stopWechatQrPoll();
  }
}
async function pollWechatQr(){
  const data=await api("wechat_qr_status");
  applyWechatQr(data);
  if(data.active&&!data.completed){
    wechatQrTimer=setTimeout(()=>pollWechatQr().catch(err=>showError(err.message||String(err))),1500);
  }
}
async function refresh(){
  const data=await api("state");
  applyState(data);
}
async function loadConfig(){
  const data=await api("config");
  const c=data.config||{};
  $("llm_base_url").value=c.llm_base_url||"";
  $("llm_model").value=c.llm_model||"";
  $("wechat_enabled").checked=!!c.wechat_enabled;
  $("wechat_base_url").value=c.wechat_base_url||"";
}
$("composer").addEventListener("submit",async ev=>{
  ev.preventDefault();
  const input=$("input");
  const text=input.value.trim();
  if(!text) return;
  input.value="";
  addMsg("user",text);
  $("send").disabled=true;
  showError("");
  try{
    const data=await api("chat",{message:text});
    addMsg("assistant",data.reply||"");
    applyState(data.state||{});
  }catch(err){
    showError(err.message||String(err));
    addMsg("assistant","Error: "+(err.message||String(err)));
    refresh().catch(()=>{});
  }finally{
    $("send").disabled=false;
    input.focus();
  }
});
$("configForm").addEventListener("submit",async ev=>{
  ev.preventDefault();
  showError("");
  const body={
    llm_base_url:$("llm_base_url").value.trim(),
    llm_model:$("llm_model").value.trim(),
    llm_api_key:$("llm_api_key").value.trim()||"__keep__",
    wechat_enabled:$("wechat_enabled").checked,
    wechat_base_url:$("wechat_base_url").value.trim(),
    wechat_token:$("wechat_token").value.trim()||"__keep__"
  };
  try{
    await api("save_config",body);
    $("llm_api_key").value="";
    $("wechat_token").value="";
    await refresh();
  }catch(err){showError(err.message||String(err))}
});
$("reset").addEventListener("click",async()=>{
  showError("");
  try{
    messages.length=0;
    $("messages").innerHTML="";
    const data=await api("reset");
    applyState(data.state||{});
  }catch(err){showError(err.message||String(err))}
});
$("wechatQrStart").addEventListener("click",async()=>{
  showError("");
  stopWechatQrPoll();
  setWechatQrBusy(true);
  try{
    const data=await api("wechat_qr_start",{
      force:true,
      wechat_base_url:$("wechat_base_url").value.trim()
    });
    applyWechatQr(data);
    if(data.active&&!data.completed){
      wechatQrTimer=setTimeout(()=>pollWechatQr().catch(err=>showError(err.message||String(err))),1000);
    }
  }catch(err){showError(err.message||String(err))}
  finally{setWechatQrBusy(false)}
});
$("wechatQrCancel").addEventListener("click",async()=>{
  showError("");
  stopWechatQrPoll();
  setWechatQrBusy(true);
  try{
    const data=await api("wechat_qr_cancel");
    applyWechatQr(data);
  }catch(err){showError(err.message||String(err))}
  finally{setWechatQrBusy(false)}
});
(async function boot(){
  try{
    await loadConfig();
    await refresh();
    pollWechatQr().catch(()=>{});
    addMsg("assistant","Ready.");
    setInterval(()=>refresh().catch(()=>{}),3500);
  }catch(err){showError(err.message||String(err))}
})();
</script>
</body>
</html>
]==]

local function route_index()
  local html = APP.HTML:gsub("__BASE__", function()
    return APP.ROUTE_BASE
  end)
  return text_response("200 OK", "text/html; charset=utf-8", html)
end

local function route_redirect()
  return text_response("302 Found", "text/plain; charset=utf-8", "", {
    ["location"] = APP.ROUTE_BASE .. "/",
  })
end

local function register_route(method, route, handler)
  local err = httpd.dynamic(method, route, handler)
  if err then
    local msg = "httpd.dynamic failed: " .. route .. " (" .. tostring(err) .. ")"
    S.last_error = msg
    append_log("error", msg)
    print("[mini_claw] " .. msg)
    return false
  end
  APP.routes[#APP.routes + 1] = { method = method, route = route }
  return true
end

local function unregister_routes()
  if not httpd or not httpd.unregister then
    APP.routes = {}
    return
  end
  for i = #APP.routes, 1, -1 do
    local item = APP.routes[i]
    pcall(function() httpd.unregister(item.method, item.route) end)
  end
  APP.routes = {}
end

function APP.stop(reason)
  if APP.shutting_down then return end
  APP.shutting_down = true
  APP.running = false
  for _, timer in ipairs(APP.timers) do
    pcall(function() timer:stop() end)
  end
  APP.timers = {}
  unregister_routes()
  local ok, err = call_webui(false)
  if not ok then
    APP.startup_error = "webui " .. tostring(err or "failed")
  end
  print("[mini_claw] stop", text_or(reason, ""))
end

local function build_ui()
  clear_root()
  local root = (ui_scr_act_fn and ui_scr_act_fn()) or (lv_scr_act and lv_scr_act())
  if not root then return end
  call(lv_obj_set_style_bg_color, root, C.bg, MAIN_STYLE)
  call(lv_obj_set_style_bg_opa, root, 255, MAIN_STYLE)
  if lv_obj_clear_flag and rawget(_G, "LV_OBJ_FLAG_SCROLLABLE") then
    call(lv_obj_clear_flag, root, rawget(_G, "LV_OBJ_FLAG_SCROLLABLE"))
  end

  local function label(x, y, w, h, text, font, color, align, long_mode)
    local id = lv_label_create(root)
    call(lv_obj_set_pos, id, x, y)
    call(lv_obj_set_width, id, w)
    if h and lv_obj_set_height then call(lv_obj_set_height, id, h) end
    call(lv_label_set_text, id, text)
    call(lv_obj_set_style_text_font, id, font or FONT_12, MAIN_STYLE)
    call(lv_obj_set_style_text_color, id, color or C.text, MAIN_STYLE)
    call(lv_obj_set_style_text_letter_space, id, 0, MAIN_STYLE)
    call(lv_obj_set_style_text_line_space, id, 2, MAIN_STYLE)
    if align and lv_obj_set_style_text_align then
      call(lv_obj_set_style_text_align, id, align, MAIN_STYLE)
    end
    if lv_label_set_long_mode then
      call(lv_label_set_long_mode, id, long_mode or LABEL_LONG_CLIP)
    end
    return id
  end

  UI.title = label(12, 10, 150, 24, "Mini Claw", FONT_20, C.text, ALIGN_LEFT)
  UI.status = label(220, 13, 88, 22, "READY", FONT_16, C.green, ALIGN_CENTER)
  UI.route = label(12, 38, 296, 18, APP.ROUTE_BASE, FONT_12, C.sub, ALIGN_LEFT)
  UI.wechat = label(12, 62, 296, 18, "WeChat off", FONT_12, C.dim, ALIGN_LEFT)
  UI.last_user = label(12, 96, 296, 34, "No messages", FONT_12, C.blue, ALIGN_LEFT, LABEL_LONG_WRAP)
  UI.last_reply = label(12, 136, 296, 58, "Open WebUI", FONT_12, C.text, ALIGN_LEFT, LABEL_LONG_WRAP)
  UI.note = label(12, 210, 296, 18, "", FONT_10, C.amber, ALIGN_LEFT)
  redraw()
end

local function start_web()
  if not httpd or not httpd.start then
    S.last_error = "httpd missing"
    return
  end
  httpd.start({
    webroot = "/sd",
    auto_index = httpd.INDEX_NONE,
    max_handlers = 18,
  })
  register_route(httpd.POST, APP.API_PREFIX, route_api)
  register_route(httpd.GET, APP.ROUTE_BASE, route_index)
  register_route(httpd.GET, APP.ROUTE_BASE .. "/", route_index)
  local ok, err = call_webui(true)
  if not ok then
    S.last_error = "webui " .. tostring(err or "failed")
  end
end

local function start_wechat_timer()
  if not tmr or not tmr.create then return end
  local timer = tmr.create()
  APP.timers[#APP.timers + 1] = timer
  timer:alarm(1000, tmr.ALARM_AUTO, function()
    local ok, err = pcall(function()
      local now = now_ms()
      if APP.running
        and APP.config.wechat_enabled
        and now - (S.last_wechat_poll_ms or 0) >= APP.config.wechat_poll_ms then
        wechat_poll_once()
      end
    end)
    if not ok then
      S.wechat_inflight = false
      append_log("error", "wechat timer " .. short_text(err, 140))
      redraw()
    end
  end)
end

math.randomseed(now_ms() + 17)
S.started_ms = now_ms()
load_config()
build_ui()
start_web()
start_wechat_timer()
append_log("ready", APP.ROUTE_BASE)
redraw()
print("[mini_claw] ready", APP.VERSION, APP.ROUTE_BASE)
