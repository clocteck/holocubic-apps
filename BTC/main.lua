+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++if _G.BTC_TREND_APP and _G.BTC_TREND_APP.stop then
  pcall(function() _G.BTC_TREND_APP.stop() end)
end

BTC_TREND_APP = {}
BTC_TREND_APP.VERSION = "2026-04-25-btc-trend-v8-compact-candle-panel"

-- =====================================
-- config
-- =====================================
BTC_TREND_APP.SCREEN_W = 320
BTC_TREND_APP.SCREEN_H = 240

BTC_TREND_APP.TOP_GAP = 10

BTC_TREND_APP.BASE_URL = "https://data-api.binance.vision"

BTC_TREND_APP.TICKER_REFRESH_MS = 3000
BTC_TREND_APP.KLINE_REFRESH_MS = 15000
BTC_TREND_APP.TIMER_TICK_MS = 500

BTC_TREND_APP.KLINE_LIMIT = 60
BTC_TREND_APP.CANDLE_VISIBLE_LIMIT = 46

BTC_TREND_APP.INTERVALS = {
  { label = "1m",    api = "1m" },
  { label = "1h",    api = "1h" },
  { label = "1day",  api = "1d" },
  { label = "1week", api = "1w" },
}

BTC_TREND_APP.SYMBOLS = {
  { code = "BTCUSDT", text = "BTC / USDT" },
  { code = "ETHUSDT", text = "ETH / USDT" },
  { code = "SOLUSDT", text = "SOL / USDT" },
}

BTC_TREND_APP.MODES = { "candle", "line" }

BTC_TREND_APP.DEFAULT_SYMBOL = "BTCUSDT"
BTC_TREND_APP.DEFAULT_INTERVAL = "1m"
BTC_TREND_APP.DEFAULT_MODE = "candle"
BTC_TREND_APP.DEFAULT_MA_PERIOD = 10
BTC_TREND_APP.DEFAULT_MA_ENABLED = true

BTC_TREND_APP.KEY_DEBOUNCE_MS = 80
BTC_TREND_APP.KEY_LOCK_MS = 500

BTC_TREND_APP.INFO_X = 10
BTC_TREND_APP.INFO_Y = 10
BTC_TREND_APP.INFO_W = 300
BTC_TREND_APP.INFO_H = 66

BTC_TREND_APP.CHART_PANEL_X = 12
BTC_TREND_APP.CHART_PANEL_Y = 98
BTC_TREND_APP.CHART_PANEL_W = 296
BTC_TREND_APP.CHART_PANEL_H = 112

BTC_TREND_APP.CHART_X = 2
BTC_TREND_APP.CHART_Y = 2
BTC_TREND_APP.CHART_W = 292
BTC_TREND_APP.CHART_H = 108

BTC_TREND_APP.FOOTER_X = 10
BTC_TREND_APP.FOOTER_Y = 210
BTC_TREND_APP.FOOTER_W = 300
BTC_TREND_APP.FOOTER_H = 20

BTC_TREND_APP.CHART_PAD_L = 8
BTC_TREND_APP.CHART_PAD_R = 8
BTC_TREND_APP.CHART_PAD_T = 8
BTC_TREND_APP.CHART_PAD_B = 8

BTC_TREND_APP.COLORS = {
  bg = 0x000000,
  bg_alt = 0x000000,
  panel = 0x080D12,
  panel_hi = 0x0D151F,
  panel_soft = 0x0A1118,
  grid = 0x1B2A36,
  border = 0x243445,
  shadow = 0x02060B,
  glass = 0x0A1118,
  glass_hi = 0x0D151F,
  glass_border = 0x26384A,
  glass_shadow = 0x000000,

  text_main = 0xFFFFFF,
  text_sub = 0xA9BED8,
  text_dim = 0x70849A,

  up = 0x16D39A,
  down = 0xFF7A59,
  ma = 0xF7D154,
  wick = 0xC7D4E5,
  live = 0x7EC8FF,
  warn = 0xFFB347,
}

BTC_TREND_APP.settings = {
  symbol = BTC_TREND_APP.DEFAULT_SYMBOL,
  interval = BTC_TREND_APP.DEFAULT_INTERVAL, -- label
  mode = BTC_TREND_APP.DEFAULT_MODE,
  ma_period = BTC_TREND_APP.DEFAULT_MA_PERIOD,
  ma_enabled = BTC_TREND_APP.DEFAULT_MA_ENABLED,
}

BTC_TREND_APP.state = {
  valid = false,
  chart_dirty = true,

  http_busy = false,
  http_job = nil, -- "ticker" | "kline"
  ticker_loading = false,
  kline_loading = false,

  last_error = nil,
  last_http_code = nil,

  candles = {},
  closes = {},
  ma = {},

  first_price = nil,
  prev_price = nil,
  kline_last_close = nil,
  live_price = nil,
  current_price = nil,

  min_price = nil,
  max_price = nil,
  change = nil,
  change_pct = nil,

  last_update_ms = 0,
  last_update_text = "--:--:--",
  clock_text = "--:--:--",

  next_ticker_at = 0,
  next_kline_at = 0,
}

BTC_TREND_APP.input = {
  last_key_ms = 0,
  lock_until_ms = 0,
}

BTC_TREND_APP.ui = {
  root = nil,
  bg = nil,
  info_card = nil,
  chart_card = nil,
  footer_card = nil,

  title = nil,
  status = nil,

  price = nil,
  subinfo = nil,
  detail = nil,
  updated = nil,

  chart = nil,
  maxv = nil,
  minv = nil,

  footer_left = nil,
  footer_right = nil,
}

BTC_TREND_APP.timers = {
  tick = nil,
}

BTC_TREND_APP.font_handles = {}

BTC_TREND_APP.clock = {
  last_raw_us = nil,
  mono_us = 0,
}

local app = BTC_TREND_APP
local json = rawget(_G, "sjson") or rawget(_G, "json")
local function clear_root()
  if not lv_scr_act or not lv_obj_clean then
    return
  end
  local ok, root = pcall(function()
    return lv_scr_act()
  end)
  if not ok or not root or not lv_obj_clean then
    return
  end
  pcall(function()
    lv_obj_clean(root)
  end)
end
local C = app.COLORS
local CFG = app.settings
local S = app.state
local UI = app.ui
local INP = app.input
local MAIN_STYLE = LV_PART_MAIN | LV_STATE_DEFAULT
local FONT_PRICE = rawget(_G, "LV_FONT_MONTSERRAT_28") or 28

print("[btc_trend]", app.VERSION)

-- =====================================
-- forward decl
-- =====================================
local refresh_ui
local process_http_queue

-- =====================================
-- helpers
-- =====================================
local function now_ms()
  local ok, raw_us
  if tmr and tmr.now then
    ok, raw_us = pcall(function() return tmr.now() end)
    if ok and type(raw_us) == "number" then
      if app.clock.last_raw_us == nil then
        app.clock.last_raw_us = raw_us
      else
        local delta_us
        if raw_us >= app.clock.last_raw_us then
          delta_us = raw_us - app.clock.last_raw_us
        else
          delta_us = (0x100000000 - app.clock.last_raw_us) + raw_us
        end

        app.clock.last_raw_us = raw_us
        if delta_us > 0 then
          app.clock.mono_us = app.clock.mono_us + delta_us
        end
      end

      return math.floor(app.clock.mono_us / 1000)
    end
  end

  if tmr and tmr.time then
    ok, raw_us = pcall(function() return tmr.time() end)
    if ok and type(raw_us) == "number" then
      return raw_us * 1000
    end
  end
  return 0
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function abs(v)
  if v < 0 then return -v end
  return v
end

local function fmt_price(v)
  if type(v) ~= "number" then return "--" end
  if v >= 1000 then
    return string.format("%.1f", v)
  elseif v >= 100 then
    return string.format("%.2f", v)
  else
    return string.format("%.3f", v)
  end
end

local function fmt_signed(v)
  if type(v) ~= "number" then return "--" end
  local av = abs(v)
  if av >= 100 then
    return string.format("%+.1f", v)
  elseif av >= 1 then
    return string.format("%+.2f", v)
  else
    return string.format("%+.3f", v)
  end
end

local function fmt_pct(v)
  if type(v) ~= "number" then return "--%" end
  return string.format("%+.2f%%", v)
end

local function short_text(text, max_len)
  text = tostring(text or "")
  max_len = math.floor(tonumber(max_len) or 0)
  if max_len <= 0 or #text <= max_len then
    return text
  end
  if max_len <= 3 then
    return string.sub(text, 1, max_len)
  end
  return string.sub(text, 1, max_len - 3) .. "..."
end

local function set_label_text(id, text)
  if id then
    pcall(function() lv_label_set_text(id, text or "") end)
  end
end

local function set_label_color(id, color, opa)
  if id then
    pcall(function()
      lv_obj_set_style_text_color(id, color, MAIN_STYLE)
      lv_obj_set_style_text_opa(id, opa or 255, MAIN_STYLE)
    end)
  end
end

local function set_label_font(id, size)
  if id then
    pcall(function() lv_obj_set_style_text_font(id, size, MAIN_STYLE) end)
  end
end

local function set_label_text_align(id, align)
  if id then
    pcall(function() lv_obj_set_style_text_align(id, align, MAIN_STYLE) end)
  end
end

local function set_label_width(id, width)
  if id then
    pcall(function() lv_obj_set_width(id, width) end)
  end
end

local function set_label_long_mode(id, mode)
  if id and lv_label_set_long_mode then
    pcall(function() lv_label_set_long_mode(id, mode) end)
  end
end

local function apply_price_font()
  if not UI.price then
    return
  end

  set_label_width(UI.price, app.SCREEN_W - 24)
  set_label_long_mode(UI.price, LV_LABEL_LONG_CLIP)
  set_label_text_align(UI.price, LV_TEXT_ALIGN_LEFT)
  set_label_font(UI.price, FONT_PRICE)
end

local function load_font_ref(path, fallback)
  if lv_font_load then
    local ok, handle_or_err = pcall(function()
      return lv_font_load(path)
    end)
    if ok and type(handle_or_err) == "number" and handle_or_err > 0 then
      app.font_handles[#app.font_handles + 1] = handle_or_err
      print("[btc_trend] font load ok", path, "handle", handle_or_err)
      return handle_or_err
    end

    print("[btc_trend] font load failed", path, ok and tostring(handle_or_err) or tostring(handle_or_err))
  else
    print("[btc_trend] font load failed", path, "lv_font_load missing")
  end
  return fallback
end

local function init_fonts()
  FONT_PRICE = rawget(_G, "LV_FONT_MONTSERRAT_28") or 28
  print("[btc_trend] price font builtin", tostring(FONT_PRICE))
end

local function release_fonts()
  if lv_font_free then
    for _, handle in ipairs(app.font_handles) do
      pcall(function()
        lv_font_free(handle)
      end)
    end
  end
  app.font_handles = {}
end

-- 图表卡片改成深色轻面板，避免小屏上出现过重的毛玻璃噪点。
local function style_card(id, bg0, bg1, radius, shadow_width)
  if not id then
    return
  end

  local card_bg = bg0 or C.panel_soft
  local card_bg_hi = bg1 or C.panel_hi
  local sw = shadow_width or 0

  lv_obj_set_style_bg_color(id, card_bg, MAIN_STYLE)
  lv_obj_set_style_bg_opa(id, 255, MAIN_STYLE)

  if lv_obj_set_style_bg_grad_color and lv_obj_set_style_bg_grad_dir then
    lv_obj_set_style_bg_grad_color(id, card_bg_hi, MAIN_STYLE)
    lv_obj_set_style_bg_grad_dir(id, LV_GRAD_DIR_VER, MAIN_STYLE)
  end

  lv_obj_set_style_border_width(id, 1, MAIN_STYLE)
  lv_obj_set_style_border_color(id, C.border, MAIN_STYLE)
  lv_obj_set_style_border_opa(id, 132, MAIN_STYLE)
  lv_obj_set_style_radius(id, radius or 6, MAIN_STYLE)

  if lv_obj_set_style_pad_all then
    lv_obj_set_style_pad_all(id, 0, MAIN_STYLE)
  end

  if lv_obj_set_style_clip_corner then
    pcall(function() lv_obj_set_style_clip_corner(id, true, MAIN_STYLE) end)
  end

  if lv_obj_set_style_shadow_width and lv_obj_set_style_shadow_color and lv_obj_set_style_shadow_opa then
    lv_obj_set_style_shadow_width(id, sw, MAIN_STYLE)
    lv_obj_set_style_shadow_color(id, C.shadow, MAIN_STYLE)
    lv_obj_set_style_shadow_opa(id, sw > 0 and 36 or 0, MAIN_STYLE)
  end

  if lv_obj_clear_flag then
    pcall(function() lv_obj_clear_flag(id, LV_OBJ_FLAG_SCROLLABLE) end)
  end
end

local function draw_line(canvas, x1, y1, x2, y2, color, opa, width)
  lv_canvas_draw_line(canvas, x1, y1, x2, y2, color, opa or 255, width or 1)
end

local function canvas_frame_begin(id)
  if not id then
    return false
  end

  if lv_canvas_begin and lv_canvas_end then
    local ok = pcall(function() lv_canvas_begin(id) end)
    return ok
  end

  return false
end

local function canvas_frame_end(id, use_explicit_frame)
  if not id then
    return
  end

  if use_explicit_frame and lv_canvas_end then
    pcall(function() lv_canvas_end(id) end)
    return
  end

  if lv_obj_invalidate then
    pcall(function() lv_obj_invalidate(id) end)
  end
end

local function mark_chart_dirty()
  S.chart_dirty = true
end

local function chart_error_handler(err)
  err = tostring(err)
  if debug and debug.traceback then
    local ok, trace = pcall(function()
      return debug.traceback(err, 2)
    end)
    if ok and type(trace) == "string" then
      return trace
    end
  end
  return err
end

local function clear_chart_bounds()
  return
end

local function draw_chart_text(x, y, w, text, color, opa, align, font_size)
  lv_canvas_draw_text(UI.chart, x, y, w, text, {
    color = color,
    opa = opa or 255,
    align = align,
    font_size = font_size
  })
end

local function set_chart_bounds(maxp, minp)
  if type(maxp) == "number" and type(minp) == "number" then
    local text_w = 72
    local x = app.CHART_W - text_w - 8
    local y_top = 10
    local y_bottom = app.CHART_H - 24

    draw_chart_text(x, y_top, text_w, fmt_price(maxp), C.text_sub, 255, LV_TEXT_ALIGN_RIGHT, 10)
    draw_chart_text(x, y_bottom, text_w, fmt_price(minp), C.text_sub, 255, LV_TEXT_ALIGN_RIGHT, 10)
  else
    clear_chart_bounds()
  end
end

local function chart_inner_rect()
  local x = app.CHART_PAD_L
  local y = app.CHART_PAD_T
  local w = app.CHART_W - app.CHART_PAD_L - app.CHART_PAD_R
  local h = app.CHART_H - app.CHART_PAD_T - app.CHART_PAD_B
  return x, y, w, h
end

local function fmt_clock_utc()
  local raw_time
  if time and time.getutc then
    local ok, t = pcall(function() return time.getutc() end)
    if ok and type(t) == "table" and t.hour ~= nil and t.min ~= nil and t.sec ~= nil then
      return string.format("%02d:%02d:%02d", t.hour, t.min, t.sec)
    end
    raw_time = t
  end

  if time and time.get then
    local ok, sec = pcall(function() return time.get() end)
    if ok then
      if type(sec) == "table" and sec.hour then
        return string.format("%02d:%02d:%02d", sec.hour, sec.min, sec.sec)
      end
      if type(sec) == "number" then
        local h = math.floor((sec / 3600) % 24)
        local m = math.floor((sec / 60) % 60)
        local s = sec % 60
        return string.format("%02d:%02d:%02d", h, m, s)
      end
    end
    raw_time = sec
  end

  if type(raw_time) == "table" and raw_time.hour and raw_time.min and raw_time.sec then
    return string.format("%02d:%02d:%02d", raw_time.hour, raw_time.min, raw_time.sec)
  end

  local s = math.floor(now_ms() / 1000)
  local h = math.floor((s / 3600) % 24)
  local m = math.floor((s / 60) % 60)
  local sec = s % 60
  return string.format("%02d:%02d:%02d", h, m, sec)
end

local function symbol_text(code)
  for i = 1, #app.SYMBOLS do
    if app.SYMBOLS[i].code == code then
      return app.SYMBOLS[i].text
    end
  end
  return code
end

local function allowed_symbol(code)
  for i = 1, #app.SYMBOLS do
    if app.SYMBOLS[i].code == code then
      return true
    end
  end
  return false
end

local function normalize_interval(v)
  if type(v) ~= "string" then
    return nil, nil
  end

  for i = 1, #app.INTERVALS do
    local it = app.INTERVALS[i]
    if v == it.label or v == it.api then
      return it.label, it.api
    end
  end

  return nil, nil
end

local function interval_api(label)
  local _, api = normalize_interval(label)
  return api or "1m"
end

local function find_interval_index(label)
  for i = 1, #app.INTERVALS do
    if app.INTERVALS[i].label == label then
      return i
    end
  end
  return 1
end

local function next_interval_label(delta)
  local idx = find_interval_index(CFG.interval)
  idx = idx + delta
  if idx < 1 then idx = #app.INTERVALS end
  if idx > #app.INTERVALS then idx = 1 end
  return app.INTERVALS[idx].label
end

local function is_allowed_mode(v)
  for i = 1, #app.MODES do
    if app.MODES[i] == v then return true end
  end
  return false
end

local function current_color()
  if type(S.change) == "number" and S.change < 0 then
    return C.down
  end
  return C.up
end

local function ms_to_sec_ceil(target_ms)
  local delta = target_ms - now_ms()
  if delta <= 0 then return 0 end
  return math.floor((delta + 999) / 1000)
end

local function fmt_countdown_short(sec)
  sec = tonumber(sec) or 0
  if sec <= 0 then
    return "0s"
  end
  if sec < 100 then
    return tostring(sec) .. "s"
  end
  if sec < 3600 then
    return tostring(math.floor((sec + 59) / 60)) .. "m"
  end
  if sec < 86400 then
    return tostring(math.floor((sec + 3599) / 3600)) .. "h"
  end
  return tostring(math.floor((sec + 86399) / 86400)) .. "d"
end

local function mode_text(mode)
  if mode == "line" then
    return "Line"
  end
  return "Candle"
end

local function ma_status_text()
  if CFG.ma_enabled then
    return "MA" .. tostring(CFG.ma_period)
  end
  return "MA off"
end

-- 屏幕端和 Web 面板都复用同一套状态判断，避免两边文案不一致。
local function status_info()
  local st = "idle"
  local st_color = C.text_dim
  local tone = "idle"

  if S.http_busy then
    if S.http_job == "ticker" then
      st = "live"
    elseif S.http_job == "kline" then
      st = "sync"
    else
      st = "busy"
    end
    st_color = C.warn
    tone = "warn"
  elseif S.kline_loading then
    st = "sync"
    st_color = C.warn
    tone = "warn"
  elseif S.ticker_loading then
    st = "live"
    st_color = C.warn
    tone = "warn"
  elseif S.valid then
    st = CFG.mode == "candle" and "kline" or "line"
    st_color = current_color()
    tone = (type(S.change) == "number" and S.change < 0) and "down" or "up"
  elseif S.last_error then
    st = "err"
    st_color = C.down
    tone = "error"
  end

  return st, st_color, tone
end

local function build_detail_text()
  return CFG.interval .. "  " .. mode_text(CFG.mode) .. "  " .. ma_status_text()
end

local function build_subinfo_text()
  if S.valid then
    return fmt_signed(S.change) .. "  " .. fmt_pct(S.change_pct)
  end
  return short_text(S.last_error or "Waiting data", 26)
end

local function build_updated_text()
  if S.valid and S.last_update_text and S.last_update_text ~= "" then
    return "UPD " .. S.last_update_text
  end
  return "UTC " .. (S.clock_text or "--:--:--")
end

local function build_refresh_text()
  local rt = ms_to_sec_ceil(S.next_ticker_at or 0)
  local rk = ms_to_sec_ceil(S.next_kline_at or 0)
  return fmt_countdown_short(rt) .. "/" .. fmt_countdown_short(rk), rt, rk
end

local function build_footer_left_text()
  return "L/R " .. tostring(CFG.interval or "--")
end

local function mark_ticker_due(ms)
  S.next_ticker_at = now_ms() + (ms or 0)
end

local function mark_kline_due(ms)
  S.next_kline_at = now_ms() + (ms or 0)
end

local function url_decode(s)
  s = s or ""
  s = s:gsub("+", " ")
  s = s:gsub("%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end)
  return s
end

local function parse_query(q)
  local out = {}
  q = q or ""
  for seg in string.gmatch(q, "([^&]+)") do
    local k, v = seg:match("^([^=]*)=(.*)$")
    if not k then
      k = seg
      v = ""
    end
    out[url_decode(k)] = url_decode(v)
  end
  return out
end

local function json_response(tbl)
  local body, err = json.encode(tbl)
  if not body then
    body = "{\"ok\":false,\"err\":\"" .. tostring(err) .. "\"}"
  end

  return {
    status = "200 OK",
    type = "application/json",
    headers = {
      ["cache-control"] = "no-store",
      ["access-control-allow-origin"] = "*",
    },
    body = body,
  }
end

local function text_response(body)
  return {
    status = "200 OK",
    type = "text/plain; charset=utf-8",
    headers = { ["cache-control"] = "no-store" },
    body = body or "",
  }
end

local function html_response(body)
  return {
    status = "200 OK",
    type = "text/html; charset=utf-8",
    headers = { ["cache-control"] = "no-store" },
    body = body or "",
  }
end

local function maybe_decompress(body, headers)
  if type(body) ~= "string" then return body, nil end
  if type(headers) ~= "table" then return body, nil end

  local enc = headers["content-encoding"]
  if type(enc) ~= "string" then return body, nil end
  if not enc:find("gzip", 1, true) then return body, nil end

  if not zlib or not zlib.isgzip or not zlib.gunzip then
    return nil, "gzip no zlib"
  end

  if not zlib.isgzip(body) then
    return nil, "gzip bad body"
  end

  local plain, err = zlib.gunzip(body)
  if not plain then
    return nil, err or "gunzip failed"
  end
  return plain, nil
end

local function build_http_error_detail(code, body)
  local detail = "http " .. tostring(code)
  if type(body) ~= "string" or #body == 0 then
    return detail
  end

  local text = body
  text = text:gsub("[%c]+", " ")
  text = text:gsub("%s+", " ")
  text = text:gsub("^%s+", "")
  text = text:gsub("%s+$", "")

  if #text == 0 then
    return detail
  end

  if #text > 160 then
    text = text:sub(1, 160) .. "..."
  end

  return text
end

local function request_json(job_name, url, callback)
  if S.http_busy then
    return false
  end

  S.http_busy = true
  S.http_job = job_name

  -- K 线接口未压缩时响应体大约 10KB，设备上的 HTTPS 读取在大 body 场景下更容易失败；
  -- 这里在具备 zlib 解压能力时优先请求 gzip，把 body 压到约 3KB，保持 ticker/kline 共用同一套解析流程。
  local accept_encoding = "identity"
  if zlib and zlib.isgzip and zlib.gunzip then
    accept_encoding = "gzip, identity"
  end

  local req_headers =
    "Accept: application/json\r\n" ..
    "Accept-Encoding: " .. accept_encoding .. "\r\n" ..
    "Cache-Control: no-cache\r\n" ..
    "Pragma: no-cache\r\n" ..
    "User-Agent: btc-lua-app/4.0\r\n"

  http.get(url, req_headers, function(code, body, headers)
    S.http_busy = false
    S.http_job = nil

    if code ~= 200 then
      callback(false, nil, build_http_error_detail(code, body), code, headers)
      return
    end

    if type(body) ~= "string" or #body == 0 then
      callback(false, nil, "empty body", code, headers)
      return
    end

    local plain, derr = maybe_decompress(body, headers)
    if not plain then
      callback(false, nil, derr or "decode body", code, headers)
      return
    end

    local doc, jerr = json.decode(plain)
    if not doc then
      callback(false, nil, "json " .. tostring(jerr), code, headers)
      return
    end

    callback(true, doc, nil, code, headers)
  end)

  return true
end

-- =====================================
-- data model
-- =====================================
local function build_effective_closes()
  local out = {}
  local n = #S.closes
  for i = 1, n do
    out[i] = S.closes[i]
  end

  if n >= 1 and type(S.live_price) == "number" then
    out[n] = S.live_price
  end

  return out
end

local function build_ma_series(period)
  period = tonumber(period) or 10
  if period < 2 then period = 2 end

  local eff = build_effective_closes()
  local out = {}
  local sum = 0

  for i = 1, #eff do
    sum = sum + eff[i]
    if i > period then
      sum = sum - eff[i - period]
    end

    if i >= period then
      out[i] = sum / period
    else
      out[i] = nil
    end
  end

  return out
end

local function parse_klines(doc)
  if type(doc) ~= "table" then
    return nil, "json type"
  end

  local candles = {}
  local closes = {}

  for i, row in ipairs(doc) do
    if type(row) == "table" then
      local open_t  = tonumber(row[1])
      local open_p  = tonumber(row[2])
      local high_p  = tonumber(row[3])
      local low_p   = tonumber(row[4])
      local close_p = tonumber(row[5])
      local close_t = tonumber(row[7])

      if open_p and high_p and low_p and close_p then
        candles[#candles + 1] = {
          open_time = open_t or 0,
          close_time = close_t or 0,
          open = open_p,
          high = high_p,
          low = low_p,
          close = close_p,
        }
        closes[#closes + 1] = close_p
      end
    end
  end

  if #candles < 2 then
    return nil, "points<2"
  end

  local first = closes[1]
  local last = closes[#closes]
  local prev = closes[#closes - 1] or first

  local minp = candles[1].low
  local maxp = candles[1].high
  for i = 2, #candles do
    if candles[i].low < minp then minp = candles[i].low end
    if candles[i].high > maxp then maxp = candles[i].high end
  end

  return {
    candles = candles,
    closes = closes,
    first_price = first,
    prev_price = prev,
    kline_last_close = last,
    min_price = minp,
    max_price = maxp,
  }
end

local function recompute_derived_fields()
  local curr = S.live_price or S.kline_last_close
  S.current_price = curr

  if type(S.first_price) == "number" and type(curr) == "number" then
    S.change = curr - S.first_price
    if S.first_price ~= 0 then
      S.change_pct = (S.change / S.first_price) * 100
    else
      S.change_pct = 0
    end
  else
    S.change = nil
    S.change_pct = nil
  end

  S.ma = build_ma_series(CFG.ma_period)
end

local function apply_kline_data(parsed)
  S.candles = parsed.candles
  S.closes = parsed.closes
  S.first_price = parsed.first_price
  S.prev_price = parsed.prev_price
  S.kline_last_close = parsed.kline_last_close
  S.min_price = parsed.min_price
  S.max_price = parsed.max_price
  S.valid = true

  recompute_derived_fields()
  mark_chart_dirty()
end

local function apply_live_price(price)
  if type(price) == "number" then
    S.live_price = price
    if S.valid then
      recompute_derived_fields()
      mark_chart_dirty()
    else
      S.current_price = price
    end
  end
end

local function reset_chart_state(reset_live_price)
  S.valid = false
  S.candles = {}
  S.closes = {}
  S.ma = {}
  S.first_price = nil
  S.prev_price = nil
  S.kline_last_close = nil
  S.min_price = nil
  S.max_price = nil
  S.change = nil
  S.change_pct = nil
  S.last_error = nil
  S.last_http_code = nil

  if reset_live_price then
    S.live_price = nil
  end

  if type(S.live_price) == "number" then
    S.current_price = S.live_price
  else
    S.current_price = nil
  end

  mark_chart_dirty()
end

-- =====================================
-- chart
-- =====================================
local function chart_visible_range()
  local n = #S.candles
  if n <= 0 then
    return 1, 0, 0
  end

  if CFG.mode == "candle" then
    local limit = app.CANDLE_VISIBLE_LIMIT or 46
    if n > limit then
      return n - limit + 1, n, limit
    end
  end

  return 1, n, n
end

local function compute_price_bounds()
  if not S.valid or #S.candles == 0 then
    return nil, nil
  end

  local first_idx, last_idx = chart_visible_range()
  local first = S.candles[first_idx]
  if not first then
    return nil, nil
  end

  local minp = first.low
  local maxp = first.high

  for i = first_idx, last_idx do
    local c = S.candles[i]
    if c then
      if c.low < minp then minp = c.low end
      if c.high > maxp then maxp = c.high end
    end
  end

  if CFG.ma_enabled and S.ma then
    for i = first_idx, last_idx do
      local v = S.ma[i]
      if type(v) == "number" then
        if v < minp then minp = v end
        if v > maxp then maxp = v end
      end
    end
  end

  if type(S.live_price) == "number" then
    if S.live_price < minp then minp = S.live_price end
    if S.live_price > maxp then maxp = S.live_price end
  end

  return minp, maxp
end

local function price_to_y(price, lo, hi, iy, ih)
  local ratio = (hi - price) / (hi - lo)
  ratio = clamp(ratio, 0, 1)
  return iy + math.floor(ratio * (ih - 1) + 0.5)
end

local function draw_chart_background()
  lv_canvas_fill_bg(UI.chart, C.panel, 255)

  draw_line(UI.chart, 0, 0, app.CHART_W - 1, 0, C.border, 140, 1)
  draw_line(UI.chart, 0, app.CHART_H - 1, app.CHART_W - 1, app.CHART_H - 1, C.border, 140, 1)
  draw_line(UI.chart, 0, 0, 0, app.CHART_H - 1, C.border, 140, 1)
  draw_line(UI.chart, app.CHART_W - 1, 0, app.CHART_W - 1, app.CHART_H - 1, C.border, 140, 1)

  local ix, iy, iw, ih = chart_inner_rect()

  for i = 0, 3 do
    local gy = iy + math.floor(i * (ih - 1) / 3 + 0.5)
    draw_line(UI.chart, ix, gy, ix + iw - 1, gy, C.grid, 120, 1)
  end

  for i = 0, 4 do
    local gx = ix + math.floor(i * (iw - 1) / 4 + 0.5)
    draw_line(UI.chart, gx, iy, gx, iy + ih - 1, C.grid, 80, 1)
  end
end

local function draw_chart_message(msg)
  clear_chart_bounds()
  draw_chart_text(0, 50, app.CHART_W, short_text(msg or "No data", 28), C.text_sub, 255, LV_TEXT_ALIGN_CENTER, 16)
end

local function draw_chart_empty(msg)
  draw_chart_background()
  draw_chart_message(msg)
end

local function draw_ma_line(lo, hi, ix, iy, iw, ih, first_idx, last_idx)
  if not CFG.ma_enabled then return end
  if not S.ma or #S.ma < 2 then return end

  first_idx = first_idx or 1
  last_idx = last_idx or #S.ma
  if first_idx < 1 then first_idx = 1 end
  if last_idx > #S.ma then last_idx = #S.ma end

  local span = last_idx - first_idx
  if span < 1 then return end

  local last_x = nil
  local last_y = nil

  for i = first_idx, last_idx do
    local v = S.ma[i]
    if type(v) == "number" then
      local x = ix + math.floor((i - first_idx) * (iw - 1) / span + 0.5)
      local y = price_to_y(v, lo, hi, iy, ih)

      if last_x ~= nil then
        draw_line(UI.chart, last_x, last_y, x, y, C.ma, 255, 1)
      end

      last_x = x
      last_y = y
    else
      last_x = nil
      last_y = nil
    end
  end
end

local function draw_live_price_line(lo, hi, ix, iy, iw, ih)
  if type(S.live_price) ~= "number" then return end
  local y = price_to_y(S.live_price, lo, hi, iy, ih)
  draw_line(UI.chart, ix, y, ix + iw - 1, y, C.live, 180, 1)
  lv_canvas_draw_rect(UI.chart, ix + iw - 4, y - 2, 4, 5, C.live, 255)
end

local function draw_line_chart(lo, hi, ix, iy, iw, ih)
  local eff = build_effective_closes()
  local n = #eff
  if n < 2 then
    draw_chart_message("No data")
    return
  end

  local color = current_color()
  local last_x = nil
  local last_y = nil

  for i = 1, n do
    local p = eff[i]
    local x = ix + math.floor((i - 1) * (iw - 1) / (n - 1) + 0.5)
    local y = price_to_y(p, lo, hi, iy, ih)

    if last_x ~= nil then
      draw_line(UI.chart, last_x, last_y, x, y, color, 255, 2)
    end

    last_x = x
    last_y = y
  end

  if last_x and last_y then
    lv_canvas_draw_rect(UI.chart, last_x - 2, last_y - 2, 5, 5, color, 255)
  end
end

local function draw_candles(lo, hi, ix, iy, iw, ih)
  local n = #S.candles
  if n < 1 then
    draw_chart_message("No data")
    return
  end

  local first_idx, last_idx, visible_n = chart_visible_range()
  if visible_n < 1 then
    draw_chart_message("No data")
    return
  end

  local step = iw / visible_n
  local body_w = math.floor(step * 0.62)
  if body_w < 2 then body_w = 2 end
  if body_w > 7 then body_w = 7 end

  for pos = 1, visible_n do
    local i = first_idx + pos - 1
    local c = S.candles[i]
    local cx = ix + math.floor((pos - 0.5) * step + 0.5)

    local y_open = price_to_y(c.open, lo, hi, iy, ih)
    local y_close = price_to_y(c.close, lo, hi, iy, ih)
    local y_high = price_to_y(c.high, lo, hi, iy, ih)
    local y_low = price_to_y(c.low, lo, hi, iy, ih)

    draw_line(UI.chart, cx, y_high, cx, y_low, C.wick, 255, 1)

    local top = y_open
    local bottom = y_close
    if y_close < y_open then
      top = y_close
      bottom = y_open
    end

    local body_h = bottom - top + 1
    if body_h < 1 then body_h = 1 end

    local color = C.up
    if c.close < c.open then
      color = C.down
    end

    local x = cx - math.floor(body_w / 2)
    lv_canvas_draw_rect(UI.chart, x, top, body_w, body_h, color, 255)
  end
end

local function redraw_chart_body()
  if (S.kline_loading or S.http_job == "kline") and not S.valid then
    draw_chart_empty("Loading...")
  elseif not S.valid or #S.candles == 0 then
    draw_chart_empty(S.last_error or "No data")
  else
    draw_chart_background()

    local minp, maxp = compute_price_bounds()
    if type(minp) ~= "number" or type(maxp) ~= "number" then
      draw_chart_message("No data")
    else
      local spread = maxp - minp
      local pad = spread * 0.08
      if pad < 0.5 then pad = 0.5 end

      local lo = minp - pad
      local hi = maxp + pad
      if hi <= lo then hi = lo + 1 end

      local ix, iy, iw, ih = chart_inner_rect()
      local first_idx, last_idx = chart_visible_range()

      if CFG.mode == "line" then
        draw_line_chart(lo, hi, ix, iy, iw, ih)
      else
        draw_candles(lo, hi, ix, iy, iw, ih)
      end

      draw_ma_line(lo, hi, ix, iy, iw, ih, first_idx, last_idx)
      draw_live_price_line(lo, hi, ix, iy, iw, ih)

      set_chart_bounds(maxp, minp)
    end
  end
end

local function redraw_chart(force)
  if not UI.chart then
    return false
  end

  if (not force) and (not S.chart_dirty) then
    return false
  end

  local use_explicit_frame = canvas_frame_begin(UI.chart)
  local ok, err = xpcall(redraw_chart_body, chart_error_handler)
  canvas_frame_end(UI.chart, use_explicit_frame)

  if not ok then
    print("[btc_trend] chart redraw error", err)
    mark_chart_dirty()
    return false
  end

  S.chart_dirty = false
  return true
end

-- =====================================
-- UI
-- =====================================
local function build_ui()
  UI.root = lv_scr_act()
  clear_root()
  init_fonts()
  UI.info_card = nil
  UI.footer_card = nil

  UI.bg = lv_obj_create(UI.root)
  lv_obj_set_pos(UI.bg, 0, 0)
  lv_obj_set_size(UI.bg, app.SCREEN_W, app.SCREEN_H)
  lv_obj_set_style_bg_color(UI.bg, C.bg, MAIN_STYLE)
  lv_obj_set_style_bg_opa(UI.bg, 255, MAIN_STYLE)
  lv_obj_set_style_border_width(UI.bg, 0, MAIN_STYLE)
  lv_obj_set_style_radius(UI.bg, 0, MAIN_STYLE)

  -- 黑底只保留一张走势图卡片，其它信息全部直接铺在背景上，避免出现多个视觉中心。
  UI.chart_card = lv_obj_create(UI.root)
  lv_obj_set_pos(UI.chart_card, app.CHART_PANEL_X, app.CHART_PANEL_Y)
  lv_obj_set_size(UI.chart_card, app.CHART_PANEL_W, app.CHART_PANEL_H)
  style_card(UI.chart_card, C.panel_soft, C.panel_hi, 6, 0)

  UI.title = lv_label_create(UI.root)
  lv_label_set_text(UI.title, symbol_text(CFG.symbol))
  lv_obj_set_pos(UI.title, 12, 10)
  set_label_width(UI.title, 164)
  set_label_long_mode(UI.title, LV_LABEL_LONG_CLIP)
  set_label_font(UI.title, 12)
  set_label_color(UI.title, C.text_sub, 255)

  UI.status = lv_label_create(UI.root)
  lv_label_set_text(UI.status, "idle")
  lv_obj_set_pos(UI.status, 234, 10)
  set_label_width(UI.status, 74)
  set_label_long_mode(UI.status, LV_LABEL_LONG_CLIP)
  set_label_text_align(UI.status, LV_TEXT_ALIGN_RIGHT)
  set_label_font(UI.status, 12)
  set_label_color(UI.status, C.text_dim, 255)

  UI.price = lv_label_create(UI.root)
  lv_label_set_text(UI.price, "--")
  lv_obj_set_pos(UI.price, 12, 25)
  apply_price_font()
  set_label_color(UI.price, C.text_main, 255)

  UI.subinfo = lv_label_create(UI.root)
  lv_label_set_text(UI.subinfo, "--")
  lv_obj_set_pos(UI.subinfo, 12, 62)
  set_label_width(UI.subinfo, 160)
  set_label_long_mode(UI.subinfo, LV_LABEL_LONG_CLIP)
  set_label_font(UI.subinfo, 12)
  set_label_color(UI.subinfo, C.text_sub, 255)

  UI.detail = lv_label_create(UI.root)
  lv_label_set_text(UI.detail, "--")
  lv_obj_set_pos(UI.detail, 180, 64)
  set_label_width(UI.detail, 128)
  set_label_long_mode(UI.detail, LV_LABEL_LONG_CLIP)
  set_label_text_align(UI.detail, LV_TEXT_ALIGN_RIGHT)
  set_label_font(UI.detail, 12)
  set_label_color(UI.detail, C.live, 255)

  UI.updated = lv_label_create(UI.root)
  lv_label_set_text(UI.updated, "--:--:--")
  lv_obj_set_pos(UI.updated, 12, 82)
  set_label_width(UI.updated, 162)
  set_label_long_mode(UI.updated, LV_LABEL_LONG_CLIP)
  set_label_font(UI.updated, 12)
  set_label_color(UI.updated, C.text_dim, 255)

  UI.chart = lv_canvas_create(UI.chart_card, app.CHART_W, app.CHART_H, CANVAS_FMT_TRUE_COLOR)
  lv_obj_set_pos(UI.chart, app.CHART_X, app.CHART_Y)
  lv_obj_set_style_radius(UI.chart, 2, MAIN_STYLE)
  lv_obj_set_style_border_width(UI.chart, 0, MAIN_STYLE)
  lv_obj_set_style_bg_opa(UI.chart, 0, MAIN_STYLE)
  if lv_obj_set_style_clip_corner then
    pcall(function() lv_obj_set_style_clip_corner(UI.chart, true, MAIN_STYLE) end)
  end

  UI.maxv = nil
  UI.minv = nil

  UI.footer_left = lv_label_create(UI.root)
  lv_label_set_text(UI.footer_left, "")
  lv_obj_set_pos(UI.footer_left, 12, 220)
  set_label_width(UI.footer_left, 142)
  set_label_long_mode(UI.footer_left, LV_LABEL_LONG_CLIP)
  set_label_font(UI.footer_left, 12)
  set_label_color(UI.footer_left, C.text_sub, 255)

  UI.footer_right = lv_label_create(UI.root)
  lv_label_set_text(UI.footer_right, "")
  lv_obj_set_pos(UI.footer_right, 178, 220)
  set_label_width(UI.footer_right, 130)
  set_label_long_mode(UI.footer_right, LV_LABEL_LONG_CLIP)
  set_label_text_align(UI.footer_right, LV_TEXT_ALIGN_RIGHT)
  set_label_font(UI.footer_right, 12)
  set_label_color(UI.footer_right, C.text_dim, 255)

  redraw_chart()
end

refresh_ui = function()
  local st, st_color = status_info()

  set_label_text(UI.title, symbol_text(CFG.symbol))
  set_label_text(UI.status, string.upper(st))
  set_label_color(UI.status, st_color, 255)
  apply_price_font()

  if type(S.current_price) == "number" then
    set_label_text(UI.price, fmt_price(S.current_price))
    set_label_color(UI.price, current_color(), 255)
  else
    set_label_text(UI.price, "--")
    set_label_color(UI.price, C.text_main, 255)
  end

  set_label_text(UI.detail, build_detail_text())

  if S.valid then
    set_label_text(UI.subinfo, build_subinfo_text())
    set_label_color(UI.subinfo, current_color(), 255)
  else
    set_label_text(UI.subinfo, build_subinfo_text())
    set_label_color(UI.subinfo, C.text_sub, 255)
  end

  local clock_text = fmt_clock_utc()
  if clock_text ~= S.clock_text then
    S.clock_text = clock_text
  end

  set_label_text(UI.updated, build_updated_text())

  local refresh_text = build_refresh_text()
  set_label_text(UI.footer_left, build_footer_left_text())
  set_label_text(UI.footer_right, refresh_text)

  if S.chart_dirty then
    redraw_chart()
  end
end

-- =====================================
-- fetchers
-- =====================================
local function on_request_fail(kind, err, code)
  S.last_error = kind .. " " .. tostring(err or code or -1)
  S.last_http_code = code or -1
  if not S.valid then
    mark_chart_dirty()
  end
  print("[btc_trend]", kind, "fail", S.last_http_code, S.last_error)
  refresh_ui()
end

local function fetch_ticker_only()
  if S.http_busy then return false end

  local req_symbol = CFG.symbol
  local url = app.BASE_URL .. "/api/v3/ticker/price?symbol=" .. req_symbol

  S.ticker_loading = true

  local ok = request_json("ticker", url, function(success, doc, err, code)
    S.ticker_loading = false
    mark_ticker_due(app.TICKER_REFRESH_MS)

    if req_symbol ~= CFG.symbol then
      refresh_ui()
      return
    end

    if not success then
      on_request_fail("ticker", err, code)
      return
    end

    local p = nil
    if type(doc) == "table" then
      p = tonumber(doc.price)
    end

    if not p then
      on_request_fail("ticker", "bad price", code)
      return
    end

    apply_live_price(p)
    S.last_error = nil
    S.last_http_code = 200
    S.last_update_ms = now_ms()
    S.last_update_text = fmt_clock_utc()

    refresh_ui()
  end)

  if not ok then
    S.ticker_loading = false
    refresh_ui()
    return false
  end

  refresh_ui()
  return true
end

local function fetch_kline_only()
  if S.http_busy then return false end

  local req_symbol = CFG.symbol
  local req_interval_label = CFG.interval
  local req_interval_api = interval_api(req_interval_label)

  local url = app.BASE_URL
    .. "/api/v3/klines?symbol=" .. req_symbol
    .. "&interval=" .. req_interval_api
    .. "&limit=" .. tostring(app.KLINE_LIMIT)

  S.kline_loading = true
  if not S.valid then
    mark_chart_dirty()
  end

  local ok = request_json("kline", url, function(success, doc, err, code)
    S.kline_loading = false
    mark_kline_due(app.KLINE_REFRESH_MS)

    if req_symbol ~= CFG.symbol or req_interval_label ~= CFG.interval then
      refresh_ui()
      return
    end

    if not success then
      on_request_fail("kline", err, code)
      return
    end

    local parsed, perr = parse_klines(doc)
    if not parsed then
      on_request_fail("kline", "parse " .. tostring(perr), code)
      return
    end

    apply_kline_data(parsed)
    S.last_error = nil
    S.last_http_code = 200
    S.last_update_ms = now_ms()
    S.last_update_text = fmt_clock_utc()

    refresh_ui()
  end)

  if not ok then
    S.kline_loading = false
    if not S.valid then
      mark_chart_dirty()
    end
    refresh_ui()
    return false
  end

  refresh_ui()
  return true
end

process_http_queue = function()
  if S.http_busy then
    return
  end

  local t = now_ms()

  if (not S.valid) and t >= (S.next_kline_at or 0) then
    fetch_kline_only()
    return
  end

  if t >= (S.next_ticker_at or 0) then
    fetch_ticker_only()
    return
  end

  if t >= (S.next_kline_at or 0) then
    fetch_kline_only()
    return
  end
end

-- =====================================
-- settings
-- =====================================
local function queue_full_refresh()
  mark_ticker_due(0)
  mark_kline_due(0)
end

local function queue_ticker_refresh()
  mark_ticker_due(0)
end

local function apply_settings(new_cfg, fetch_now)
  local need_kline = false
  local need_ticker = false
  local chart_style_changed = false
  local symbol_changed = false

  if new_cfg.symbol and allowed_symbol(new_cfg.symbol) and new_cfg.symbol ~= CFG.symbol then
    CFG.symbol = new_cfg.symbol
    need_kline = true
    need_ticker = true
    symbol_changed = true
  end

  if new_cfg.interval then
    local label = normalize_interval(new_cfg.interval)
    if label and label ~= CFG.interval then
      CFG.interval = label
      need_kline = true
      chart_style_changed = true
    end
  end

  if new_cfg.mode and is_allowed_mode(new_cfg.mode) and new_cfg.mode ~= CFG.mode then
    CFG.mode = new_cfg.mode
    chart_style_changed = true
  end

  if new_cfg.ma_enabled ~= nil then
    if new_cfg.ma_enabled == true or new_cfg.ma_enabled == "1" or new_cfg.ma_enabled == "true" then
      if not CFG.ma_enabled then
        CFG.ma_enabled = true
        chart_style_changed = true
      end
    elseif new_cfg.ma_enabled == false or new_cfg.ma_enabled == "0" or new_cfg.ma_enabled == "false" then
      if CFG.ma_enabled then
        CFG.ma_enabled = false
        chart_style_changed = true
      end
    end
  end

  if new_cfg.ma_period ~= nil then
    local p = tonumber(new_cfg.ma_period)
    if p and p >= 2 and p <= 30 then
      p = math.floor(p)
      if p ~= CFG.ma_period then
        CFG.ma_period = p
        chart_style_changed = true
      end
      if S.valid then
        recompute_derived_fields()
      end
    end
  end

  if need_kline then
    reset_chart_state(symbol_changed)
    S.kline_loading = true
    mark_kline_due(0)
  end
  if need_ticker then
    mark_ticker_due(0)
  end
  if chart_style_changed then
    mark_chart_dirty()
  end

  refresh_ui()

  if fetch_now then
    process_http_queue()
  end
end

-- =====================================
-- web
-- =====================================
local function build_web_html()
  return [=[
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>BTC Trend Console</title>
<style>
:root{
  color-scheme:light;
  --bg:#eef3fb;
  --panel:rgba(255,255,255,.84);
  --panel-strong:#ffffff;
  --line:rgba(15,23,42,.11);
  --text:#111827;
  --muted:#64748b;
  --accent:#0a84ff;
  --good:#16a34a;
  --good-soft:#dcfce7;
  --bad:#e2553f;
  --bad-soft:#ffe4dd;
  --warn:#d97706;
  --warn-soft:#fff1d6;
  --idle:#7b8794;
  --idle-soft:#eef2f7;
  --shadow:0 20px 48px rgba(15,23,42,.08);
  --radius:24px;
}
*{box-sizing:border-box}
html,body{margin:0;min-height:100%}
body{
  font-family:"SF Pro Display","PingFang SC","Segoe UI",sans-serif;
  color:var(--text);
  background:
    radial-gradient(circle at 0% 0%, rgba(10,132,255,.16), transparent 26%),
    radial-gradient(circle at 100% 10%, rgba(22,163,74,.12), transparent 24%),
    linear-gradient(180deg, #f7faff 0%, var(--bg) 100%);
}
.page{max-width:1080px;margin:0 auto;padding:24px 16px 36px}
.hero{display:grid;grid-template-columns:minmax(0,1.3fr) minmax(320px,.9fr);gap:16px;align-items:stretch}
.card,.stat-card{
  background:var(--panel);
  border:1px solid var(--line);
  box-shadow:var(--shadow);
  backdrop-filter:blur(18px);
  border-radius:var(--radius);
}
.card{padding:20px}
.hero-main{
  display:flex;
  flex-direction:column;
  gap:16px;
  min-height:272px;
  background:linear-gradient(135deg, rgba(255,255,255,.95), rgba(244,248,255,.78));
}
.eyebrow{
  font-size:12px;
  letter-spacing:.16em;
  text-transform:uppercase;
  color:var(--muted);
}
.hero-top{display:flex;justify-content:space-between;gap:16px;align-items:flex-start}
h1{margin:0;font-size:clamp(1.9rem,4vw,3rem);line-height:1.04}
.hero-meta{margin:6px 0 0;color:var(--muted);font-size:15px}
.pill{
  display:inline-flex;
  align-items:center;
  justify-content:center;
  min-width:78px;
  padding:9px 14px;
  border-radius:999px;
  border:1px solid transparent;
  font-size:12px;
  font-weight:700;
  letter-spacing:.08em;
  text-transform:uppercase;
}
.pill-idle{background:var(--idle-soft);color:var(--idle);border-color:rgba(100,116,139,.16)}
.pill-up{background:var(--good-soft);color:var(--good);border-color:rgba(22,163,74,.22)}
.pill-down{background:var(--bad-soft);color:var(--bad);border-color:rgba(226,85,63,.22)}
.pill-warn{background:var(--warn-soft);color:var(--warn);border-color:rgba(217,119,6,.22)}
.pill-error{background:var(--bad-soft);color:var(--bad);border-color:rgba(226,85,63,.24)}
.price-wrap{display:flex;gap:14px;align-items:flex-end;flex-wrap:wrap}
.price{
  font-size:clamp(2.6rem,6vw,4.4rem);
  font-weight:700;
  line-height:1;
  letter-spacing:-.05em;
}
.change{
  display:inline-flex;
  align-items:center;
  padding:10px 14px;
  border-radius:18px;
  background:var(--idle-soft);
  color:var(--idle);
  font-size:15px;
  font-weight:600;
}
.change.up{background:var(--good-soft);color:var(--good)}
.change.down{background:var(--bad-soft);color:var(--bad)}
.hero-note{max-width:56ch;color:var(--muted);line-height:1.6;font-size:14px}
.hero-foot{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}
.inline-metric{
  padding:14px 16px;
  border-radius:18px;
  background:rgba(255,255,255,.76);
  border:1px solid rgba(15,23,42,.06);
}
.inline-metric span{display:block;font-size:12px;color:var(--muted);margin-bottom:6px}
.inline-metric strong{display:block;font-size:18px}
.controls-card{display:flex;flex-direction:column;gap:16px}
.section-head{display:flex;justify-content:space-between;align-items:flex-start;gap:12px}
.section-head h2{margin:0;font-size:18px}
.muted{color:var(--muted);font-size:13px;line-height:1.5}
.control-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}
.field{display:flex;flex-direction:column;gap:8px}
.field span{font-size:12px;color:var(--muted);font-weight:600}
select,input,button{font:inherit}
select,input{
  width:100%;
  padding:12px 14px;
  border-radius:16px;
  border:1px solid rgba(15,23,42,.12);
  background:rgba(255,255,255,.88);
  color:var(--text);
  outline:none;
  transition:border-color .18s ease, box-shadow .18s ease;
}
select:focus,input:focus{
  border-color:rgba(10,132,255,.48);
  box-shadow:0 0 0 4px rgba(10,132,255,.12);
}
.actions{display:flex;gap:12px;margin-top:4px}
.btn{
  flex:1;
  padding:13px 16px;
  border:none;
  border-radius:16px;
  font-weight:700;
  cursor:pointer;
  transition:transform .18s ease, opacity .18s ease, box-shadow .18s ease;
}
.btn:hover{transform:translateY(-1px)}
.btn:active{transform:translateY(0)}
.btn:disabled{opacity:.58;cursor:wait;transform:none}
.btn-primary{
  background:linear-gradient(135deg, #0a84ff, #45b2ff);
  color:#fff;
  box-shadow:0 10px 24px rgba(10,132,255,.22);
}
.btn-secondary{
  background:#eff4fb;
  color:#16324f;
  border:1px solid rgba(15,23,42,.08);
}
.stats-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px;margin-top:16px}
.stat-card{padding:16px;border-radius:20px}
.stat-card span{display:block;font-size:12px;color:var(--muted);margin-bottom:10px}
.stat-card strong{display:block;font-size:24px;line-height:1.1}
.stat-card small{display:block;margin-top:8px;color:var(--muted);font-size:13px}
.content-grid{display:grid;grid-template-columns:minmax(0,.92fr) minmax(0,1.08fr);gap:16px;margin-top:16px}
.list{display:grid;gap:10px}
.list-row{
  display:flex;
  justify-content:space-between;
  gap:16px;
  padding:12px 0;
  border-bottom:1px solid rgba(15,23,42,.08);
}
.list-row:last-child{border-bottom:none;padding-bottom:0}
.list-row span{color:var(--muted)}
.list-row strong{text-align:right}
.note{
  margin-top:14px;
  padding:14px 16px;
  border-radius:18px;
  background:#eff5ff;
  color:#34506b;
  line-height:1.5;
}
.note.error{background:var(--bad-soft);color:var(--bad)}
.note.warn{background:var(--warn-soft);color:var(--warn)}
.debug-panel{
  border:1px solid rgba(15,23,42,.08);
  border-radius:18px;
  background:rgba(247,250,255,.9);
  overflow:hidden;
}
.debug-panel summary{
  cursor:pointer;
  padding:14px 16px;
  font-weight:600;
  list-style:none;
}
.debug-panel summary::-webkit-details-marker{display:none}
pre{
  margin:0;
  padding:0 16px 16px;
  white-space:pre-wrap;
  word-break:break-word;
  font-size:12px;
  line-height:1.55;
  color:#1f2937;
}
@media (max-width:920px){
  .hero{grid-template-columns:1fr}
  .content-grid{grid-template-columns:1fr}
}
@media (max-width:680px){
  .control-grid,
  .stats-grid,
  .hero-foot{grid-template-columns:repeat(2,minmax(0,1fr))}
}
@media (max-width:560px){
  .page{padding:16px 12px 28px}
  .card,.stat-card{padding:16px}
  .control-grid,
  .stats-grid,
  .hero-foot{grid-template-columns:1fr}
  .actions{flex-direction:column}
  .hero-top{flex-direction:column}
  .price{font-size:2.8rem}
}
</style>
</head>
<body>
<div class="page">
  <section class="hero">
    <div class="card hero-main">
      <div class="eyebrow">BTC.lua / Web Console</div>
      <div class="hero-top">
        <div>
          <h1 id="heroSymbol">BTC / USDT</h1>
          <div class="hero-meta" id="heroMeta">1m · Candle · MA10</div>
        </div>
        <div id="statusPill" class="pill pill-idle">idle</div>
      </div>

      <div class="price-wrap">
        <div class="price" id="heroPrice">--</div>
        <div class="change" id="heroChange">--</div>
      </div>

      <div class="hero-note" id="heroNote">
        左右按键继续负责切换周期；网页端只负责改币种、模式和均线，不改变原有接口与刷新流程。
      </div>

      <div class="hero-foot">
        <div class="inline-metric">
          <span>上次更新</span>
          <strong id="lastUpdate">--:--:--</strong>
        </div>
        <div class="inline-metric">
          <span>刷新倒计时</span>
          <strong id="refreshEta">P 0s / K 0s</strong>
        </div>
      </div>
    </div>

    <div class="card controls-card">
      <div class="section-head">
        <h2>快速控制</h2>
        <div class="muted">修改后会沿用现有 `/api/set` 与 `/api/refresh` 路由。</div>
      </div>

      <div class="control-grid">
        <label class="field">
          <span>交易对</span>
          <select id="symbol">
            <option value="BTCUSDT">BTC / USDT</option>
            <option value="ETHUSDT">ETH / USDT</option>
            <option value="SOLUSDT">SOL / USDT</option>
          </select>
        </label>

        <label class="field">
          <span>周期</span>
          <select id="interval">
            <option value="1m">1m</option>
            <option value="1h">1h</option>
            <option value="1day">1day</option>
            <option value="1week">1week</option>
          </select>
        </label>

        <label class="field">
          <span>图表模式</span>
          <select id="mode">
            <option value="candle">Candle</option>
            <option value="line">Line</option>
          </select>
        </label>

        <label class="field">
          <span>均线周期</span>
          <input id="ma_period" type="number" min="2" max="30" value="10">
        </label>

        <label class="field">
          <span>均线开关</span>
          <select id="ma_enabled">
            <option value="1">On</option>
            <option value="0">Off</option>
          </select>
        </label>

        <div class="field">
          <span>按键说明</span>
          <div class="muted">屏幕端左/右键切周期，触发后保持 500ms 锁，网页侧可并行查看与控制。</div>
        </div>
      </div>

      <div class="actions">
        <button id="applyBtn" class="btn btn-primary" onclick="applyCfg()">Apply Settings</button>
        <button id="refreshBtn" class="btn btn-secondary" onclick="refreshNow()">Refresh Now</button>
      </div>
    </div>
  </section>

  <section class="stats-grid">
    <article class="stat-card">
      <span>Interval</span>
      <strong id="statInterval">1m</strong>
      <small id="statMode">Candle</small>
    </article>
    <article class="stat-card">
      <span>Moving Average</span>
      <strong id="statMa">MA10</strong>
      <small id="statBars">60 bars</small>
    </article>
    <article class="stat-card">
      <span>Ticker Queue</span>
      <strong id="statTicker">0s</strong>
      <small id="statTickerHint">next live price poll</small>
    </article>
    <article class="stat-card">
      <span>Kline Queue</span>
      <strong id="statKline">0s</strong>
      <small id="statKlineHint">next chart sync</small>
    </article>
  </section>

  <section class="content-grid">
    <article class="card">
      <div class="section-head">
        <h2>运行状态</h2>
        <div class="muted" id="syncState">idle</div>
      </div>

      <div class="list">
        <div class="list-row">
          <span>HTTP Queue</span>
          <strong id="httpState">idle</strong>
        </div>
        <div class="list-row">
          <span>Data State</span>
          <strong id="dataState">cold</strong>
        </div>
        <div class="list-row">
          <span>Current Price</span>
          <strong id="currentPriceText">--</strong>
        </div>
        <div class="list-row">
          <span>UTC Clock</span>
          <strong id="utcClock">--:--:--</strong>
        </div>
        <div class="list-row">
          <span>Last HTTP Code</span>
          <strong id="lastHttpCode">--</strong>
        </div>
      </div>

      <div class="note" id="errorBanner">设备状态正常，面板会每 2 秒自动刷新一次。</div>
    </article>

    <article class="card">
      <div class="section-head">
        <h2>调试明细</h2>
        <div class="muted">实时 JSON 快照</div>
      </div>

      <details class="debug-panel" open>
        <summary>state snapshot</summary>
        <pre id="state">loading...</pre>
      </details>
    </article>
  </section>
</div>

<script>
const els = {
  heroSymbol: document.getElementById('heroSymbol'),
  heroMeta: document.getElementById('heroMeta'),
  statusPill: document.getElementById('statusPill'),
  heroPrice: document.getElementById('heroPrice'),
  heroChange: document.getElementById('heroChange'),
  heroNote: document.getElementById('heroNote'),
  lastUpdate: document.getElementById('lastUpdate'),
  refreshEta: document.getElementById('refreshEta'),
  statInterval: document.getElementById('statInterval'),
  statMode: document.getElementById('statMode'),
  statMa: document.getElementById('statMa'),
  statBars: document.getElementById('statBars'),
  statTicker: document.getElementById('statTicker'),
  statKline: document.getElementById('statKline'),
  syncState: document.getElementById('syncState'),
  httpState: document.getElementById('httpState'),
  dataState: document.getElementById('dataState'),
  currentPriceText: document.getElementById('currentPriceText'),
  utcClock: document.getElementById('utcClock'),
  lastHttpCode: document.getElementById('lastHttpCode'),
  errorBanner: document.getElementById('errorBanner'),
  state: document.getElementById('state'),
  applyBtn: document.getElementById('applyBtn'),
  refreshBtn: document.getElementById('refreshBtn'),
  symbol: document.getElementById('symbol'),
  interval: document.getElementById('interval'),
  mode: document.getElementById('mode'),
  ma_period: document.getElementById('ma_period'),
  ma_enabled: document.getElementById('ma_enabled')
};

let renderBusy = false;

function safeText(value, fallback){
  return value === undefined || value === null || value === '' ? fallback : String(value);
}

function pillClass(tone){
  switch(tone){
    case 'up': return 'pill-up';
    case 'down': return 'pill-down';
    case 'warn': return 'pill-warn';
    case 'error': return 'pill-error';
    default: return 'pill-idle';
  }
}

function setPill(tone, text){
  els.statusPill.className = 'pill ' + pillClass(tone);
  els.statusPill.textContent = safeText(text, 'idle');
}

function setChange(changeText, changeValue){
  els.heroChange.className = 'change';
  if(typeof changeValue === 'number'){
    els.heroChange.classList.add(changeValue < 0 ? 'down' : 'up');
  }
  els.heroChange.textContent = safeText(changeText, '--');
}

function syncForm(s){
  els.symbol.value = s.symbol || 'BTCUSDT';
  els.interval.value = s.interval || '1m';
  els.mode.value = s.mode || 'candle';
  els.ma_period.value = s.ma_period || 10;
  els.ma_enabled.value = s.ma_enabled ? '1' : '0';
}

function setActionBusy(busy){
  els.applyBtn.disabled = !!busy;
  els.refreshBtn.disabled = !!busy;
}

function renderBanner(s){
  if(s.last_error){
    els.errorBanner.className = 'note error';
    els.errorBanner.textContent = '最近一次错误：' + s.last_error;
    return;
  }
  if(s.http_busy || s.ticker_loading || s.kline_loading){
    els.errorBanner.className = 'note warn';
    els.errorBanner.textContent = '请求进行中，设备会按现有刷新队列继续拉取 ticker 与 kline。';
    return;
  }
  els.errorBanner.className = 'note';
  els.errorBanner.textContent = '设备状态正常，面板会每 2 秒自动刷新一次。';
}

function renderState(s){
  syncForm(s);

  setPill(s.status_tone, safeText(s.status_text, 'idle'));
  els.heroSymbol.textContent = safeText(s.symbol_text, 'BTC / USDT');
  els.heroMeta.textContent = [
    safeText(s.interval, '1m'),
    safeText(s.mode_text, 'Candle'),
    safeText(s.ma_text, 'MA10')
  ].join(' · ');
  els.heroPrice.textContent = safeText(s.current_price_text, '--');
  setChange(s.change_text, s.change);
  els.lastUpdate.textContent = safeText(s.updated_text, '--:--:--');
  els.refreshEta.textContent = safeText(s.refresh_text, 'P 0s  K 0s');

  els.statInterval.textContent = safeText(s.interval, '1m');
  els.statMode.textContent = safeText(s.mode_text, 'Candle');
  els.statMa.textContent = safeText(s.ma_text, 'MA10');
  els.statBars.textContent = safeText(s.count, 0) + ' bars';
  els.statTicker.textContent = safeText(s.next_ticker_in_s, 0) + 's';
  els.statKline.textContent = safeText(s.next_kline_in_s, 0) + 's';

  els.syncState.textContent = safeText(s.detail_text, '--');
  els.httpState.textContent = s.http_busy ? ('busy / ' + safeText(s.http_job, '-')) : 'idle';
  els.dataState.textContent = s.valid ? 'ready' : 'cold';
  els.currentPriceText.textContent = safeText(s.current_price_text, '--');
  els.utcClock.textContent = safeText(s.utc_clock, '--:--:--');
  els.lastHttpCode.textContent = safeText(s.last_http_code, '--');
  els.state.textContent = JSON.stringify(s, null, 2);

  if(s.last_error){
    els.heroNote.textContent = '最近一次请求失败后仍会保留已有数据，方便继续观察走势与刷新队列。';
  }else if(s.valid){
    els.heroNote.textContent = '屏幕端保持主行情 + 图表 + 底部状态三层信息，网页端补充控制与调试细节。';
  }else{
    els.heroNote.textContent = '等待首轮 kline 完成后会出现完整状态；当前页面仍可提前设置交易对、模式和均线。';
  }

  renderBanner(s);
}

async function getJson(url){
  const r = await fetch(url, { cache: 'no-store' });
  if(!r.ok){
    throw new Error('HTTP ' + r.status);
  }
  return await r.json();
}

async function render(){
  if(renderBusy){
    return;
  }
  renderBusy = true;
  try{
    const s = await getJson('/api/state?_=' + Date.now());
    renderState(s);
  }catch(e){
    setPill('error', 'err');
    els.errorBanner.className = 'note error';
    els.errorBanner.textContent = '状态读取失败：' + e;
    els.state.textContent = 'state fetch failed: ' + e;
  }finally{
    renderBusy = false;
  }
}

async function applyCfg(){
  setActionBusy(true);
  try{
    const q = new URLSearchParams({
      symbol: els.symbol.value,
      interval: els.interval.value,
      mode: els.mode.value,
      ma_period: els.ma_period.value,
      ma_enabled: els.ma_enabled.value
    });
    const s = await getJson('/api/set?' + q.toString());
    renderState(s);
  }catch(e){
    els.errorBanner.className = 'note error';
    els.errorBanner.textContent = '应用配置失败：' + e;
  }finally{
    setActionBusy(false);
    window.setTimeout(render, 260);
  }
}

async function refreshNow(){
  setActionBusy(true);
  try{
    const s = await getJson('/api/refresh');
    renderState(s);
  }catch(e){
    els.errorBanner.className = 'note error';
    els.errorBanner.textContent = '手动刷新失败：' + e;
  }finally{
    setActionBusy(false);
    window.setTimeout(render, 260);
  }
}

render();
setInterval(render, 2000);
</script>
</body>
</html>
]=]
end

local function state_snapshot()
  local st, _, tone = status_info()
  local refresh_text = build_refresh_text()
  return {
    ok = true,
    symbol = CFG.symbol,
    symbol_text = symbol_text(CFG.symbol),
    interval = CFG.interval,
    interval_api = interval_api(CFG.interval),
    mode = CFG.mode,
    mode_text = mode_text(CFG.mode),
    ma_enabled = CFG.ma_enabled,
    ma_period = CFG.ma_period,
    ma_text = ma_status_text(),
    detail_text = build_detail_text(),

    status_text = st,
    status_tone = tone,

    http_busy = S.http_busy,
    http_job = S.http_job,
    ticker_loading = S.ticker_loading,
    kline_loading = S.kline_loading,

    valid = S.valid,
    last_error = S.last_error,
    last_http_code = S.last_http_code,

    live_price = S.live_price,
    kline_last_close = S.kline_last_close,
    current_price = S.current_price,
    current_price_text = fmt_price(S.current_price),

    change = S.change,
    change_text = fmt_signed(S.change),
    change_pct = S.change_pct,
    change_pct_text = fmt_pct(S.change_pct),

    min_price = S.min_price,
    max_price = S.max_price,

    last_update = S.last_update_text,
    updated_text = build_updated_text(),
    utc_clock = S.clock_text,
    next_ticker_at = S.next_ticker_at,
    next_kline_at = S.next_kline_at,
    next_ticker_in_s = ms_to_sec_ceil(S.next_ticker_at or 0),
    next_kline_in_s = ms_to_sec_ceil(S.next_kline_at or 0),
    refresh_text = refresh_text,

    count = #S.candles,
  }
end

local function start_web()
  pcall(function() httpd.stop() end)

  httpd.start({
    webroot = "/sd",
    auto_index = httpd.INDEX_NONE,
    max_handlers = 16
  })

  httpd.dynamic(httpd.GET, "/", function(req)
    return html_response(build_web_html())
  end)

  httpd.dynamic(httpd.GET, "/api/state", function(req)
    return json_response(state_snapshot())
  end)

  httpd.dynamic(httpd.GET, "/api/refresh", function(req)
    queue_full_refresh()
    process_http_queue()
    return json_response(state_snapshot())
  end)

  httpd.dynamic(httpd.GET, "/api/set", function(req)
    local q = parse_query(req.query or "")
    apply_settings({
      symbol = q.symbol,
      interval = q.interval,
      mode = q.mode,
      ma_period = q.ma_period,
      ma_enabled = q.ma_enabled,
    }, true)
    return json_response(state_snapshot())
  end)

  httpd.dynamic(httpd.GET, "/health", function(req)
    return text_response("ok")
  end)
end

-- =====================================
-- key handling
-- =====================================
local function handle_key(key_code)
  if type(key_code) ~= "number" then return end

  local t = now_ms()

  if t < INP.lock_until_ms then
    return
  end

  if (t - INP.last_key_ms) < app.KEY_DEBOUNCE_MS then
    return
  end

  INP.last_key_ms = t

  if key_code == key.LEFT then
    INP.lock_until_ms = t + app.KEY_LOCK_MS
    apply_settings({ interval = next_interval_label(-1) }, true)
  elseif key_code == key.RIGHT then
    INP.lock_until_ms = t + app.KEY_LOCK_MS
    apply_settings({ interval = next_interval_label(1) }, true)
  end
end

-- =====================================
-- lifecycle
-- =====================================
function app.stop()
  if app.timers.tick then
    pcall(function() app.timers.tick:unregister() end)
    app.timers.tick = nil
  end

  pcall(function()
    key.off()
  end)

  pcall(function() httpd.stop() end)

  if lv_scr_act then
    clear_root()
  end
  release_fonts()
end

local function start_timers()
  app.timers.tick = tmr.create()
  app.timers.tick:alarm(app.TIMER_TICK_MS, tmr.ALARM_AUTO, function()
    if _G.app and _G.app.exiting and _G.app.exiting() then
      app.stop()
      return
    end

    process_http_queue()
    refresh_ui()
  end)
end

local function init_events()
  pcall(function() key.off() end)

  key.on(function(key_code, evt_type, ts_ms)
    handle_key(key_code)
  end)
end

-- =====================================
-- boot
-- =====================================
build_ui()
refresh_ui()
init_events()
start_web()

mark_kline_due(0)
mark_ticker_due(0)

start_timers()
process_http_queue()
