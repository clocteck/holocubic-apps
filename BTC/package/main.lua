local previous = rawget(_G, "BTC_MARKETS_APP")
if previous and previous.stop then
  pcall(function() previous.stop("reload") end)
end

local APP_DIR = "/sd/apps/btc"
local function load_module(name) return dofile(APP_DIR .. "/" .. name .. ".lua") end

local Backend = load_module("backend")
local app_obj = {
  VERSION = "2.1.1",
  APP_ID = "btc",
  APP_DIR = APP_DIR,
  route_base = (app and app.route_base and app.route_base()) or "/btc",
  stopping = false,
}

app_obj.backend = Backend.new({
  version = app_obj.VERSION,
  app_id = app_obj.APP_ID,
  config_path = APP_DIR .. "/settings.json",
})
app_obj.backend:queue_refresh()
app_obj.backend:tick()

local I18n = load_module("i18n")
local Ui = load_module("ui")
local Web = load_module("web")
app_obj.i18n = I18n
app_obj.ui = Ui.new(app_obj.backend, I18n)
app_obj.web = Web.new(app_obj.backend, { route_base = app_obj.route_base, language = I18n.language })

local GROUPS = { "fx", "crypto", "nasdaq", "metal", "ashare", "taiwan" }
local DISPLAY_CURRENCIES = { "USD", "CNY", "TWD" }
local MA_VALUES = { 0, 10, 20 }
local MODES = { "line", "candle" }

local PAD_UP, PAD_DOWN, PAD_LEFT, PAD_RIGHT = 1, 2, 4, 8
local PAD_A, PAD_B, PAD_MENU = 16, 32, 8192
local PAD_SELECT, PAD_HOME = 4096, 32768
local CONTROLLER_POLL_MS = 40

app_obj.input = {
  menu_open = false,
  menu_index = 1,
  menu_rows = {},
  controller_buttons = 0,
  repeat_left = 0,
  repeat_right = 0,
}

local function wrap_index(index, count)
  if count < 1 then return 1 end
  while index < 1 do index = index + count end
  while index > count do index = index - count end
  return index
end

local function index_of(list, value)
  for i = 1, #list do
    if list[i] == value then return i end
  end
  return 1
end

local function assets_for_group(snap, group)
  local result = {}
  for i = 1, #(snap.assets or {}) do
    local asset = snap.assets[i]
    if asset.group == group then result[#result + 1] = asset end
  end
  return result
end

local function local_currency_name(code)
  code = tostring(code or "USD")
  if code == "USD" then return I18n:t("usd") end
  if code == "CNY" then return I18n:t("cny") end
  if code == "TWD" then return I18n:t("twd") end
  return code
end

local function refresh_view()
  app_obj.ui:render(true)
end

-- 菜单只描述状态，控制逻辑留在 main，避免 UI 与行情后端相互耦合。
local function build_menu_rows()
  local snap = app_obj.backend:snapshot()
  local active = snap.active or {}
  local settings = snap.settings or {}
  local rows = {
    { kind = "group", label = I18n:t("category"), value = I18n:group_name(active.group) },
  }
  if active.group == "fx" then
    rows[#rows + 1] = { kind = "base", label = I18n:t("base_currency"), value = active.base or "USD" }
    rows[#rows + 1] = { kind = "quote", label = I18n:t("quote_currency"), value = active.quote or "CNY" }
  else
    rows[#rows + 1] = { kind = "asset", label = I18n:t("asset"), value = I18n:asset_name(active) }
  end
  rows[#rows + 1] = { kind = "interval", label = I18n:t("interval"), value = settings.interval_text or settings.interval or "--" }
  if active.group ~= "fx" then
    rows[#rows + 1] = { kind = "mode", label = I18n:t("chart"), value = settings.mode == "candle" and I18n:t("candle") or I18n:t("line") }
    rows[#rows + 1] = { kind = "ma", label = I18n:t("ma"), value = tonumber(settings.ma_period) and tonumber(settings.ma_period) > 0 and ("MA" .. tostring(settings.ma_period)) or I18n:t("off") }
    rows[#rows + 1] = { kind = "currency", label = I18n:t("display_currency"), value = local_currency_name(settings.currency) }
  end
  rows[#rows + 1] = { kind = "tilt", label = I18n:t("tilt"), value = settings.tilt_enabled == false and I18n:t("off") or I18n:t("on") }
  rows[#rows + 1] = { kind = "refresh", label = I18n:t("refresh_now"), value = ">" }
  app_obj.input.menu_rows = rows
  app_obj.input.menu_index = math.max(1, math.min(#rows, app_obj.input.menu_index))
  return rows
end

local function update_menu()
  app_obj.ui:show_menu(build_menu_rows(), app_obj.input.menu_index)
end

local function set_menu(open)
  app_obj.input.menu_open = open and true or false
  if app_obj.input.menu_open then
    app_obj.input.menu_index = 1
    update_menu()
  else
    app_obj.ui:hide_menu()
    refresh_view()
  end
end

local function select_group_delta(delta)
  local snap = app_obj.backend:snapshot()
  local group = snap.active and snap.active.group or "crypto"
  local idx = wrap_index(index_of(GROUPS, group) + delta, #GROUPS)
  local choices = assets_for_group(snap, GROUPS[idx])
  if #choices > 0 then app_obj.backend:apply_settings({ asset = choices[1].id }, true) end
end

local function select_fx_currency(kind, delta)
  local snap = app_obj.backend:snapshot()
  local active = snap.active or {}
  local codes = snap.fx_currencies or { "CNY", "USD", "EUR", "JPY" }
  local base = active.base or "USD"
  local quote = active.quote or "CNY"
  local current = kind == "base" and base or quote
  local next_code = codes[wrap_index(index_of(codes, current) + delta, #codes)]
  local guard = 0
  while ((kind == "base" and next_code == quote) or (kind == "quote" and next_code == base)) and guard < #codes do
    next_code = codes[wrap_index(index_of(codes, next_code) + delta, #codes)]
    guard = guard + 1
  end
  if kind == "base" then base = next_code else quote = next_code end
  app_obj.backend:apply_settings({ source = "fx", group = "fx", base_currency = base, quote_currency = quote }, true)
end

local function change_menu_value(delta)
  local row = app_obj.input.menu_rows[app_obj.input.menu_index]
  if not row then return end
  local snap = app_obj.backend:snapshot()
  local settings = snap.settings or {}
  if row.kind == "group" then
    select_group_delta(delta)
  elseif row.kind == "asset" then
    app_obj.backend:select_group_asset_delta(delta)
  elseif row.kind == "base" or row.kind == "quote" then
    select_fx_currency(row.kind, delta)
  elseif row.kind == "interval" then
    app_obj.backend:select_interval_delta(delta)
  elseif row.kind == "mode" then
    local idx = wrap_index(index_of(MODES, settings.mode) + delta, #MODES)
    app_obj.backend:set_mode(MODES[idx])
  elseif row.kind == "ma" then
    local current = tonumber(settings.ma_period) or 0
    local idx = wrap_index(index_of(MA_VALUES, current) + delta, #MA_VALUES)
    app_obj.backend:apply_settings({ ma = MA_VALUES[idx] }, false)
  elseif row.kind == "currency" then
    local idx = wrap_index(index_of(DISPLAY_CURRENCIES, settings.currency) + delta, #DISPLAY_CURRENCIES)
    app_obj.backend:apply_settings({ currency = DISPLAY_CURRENCIES[idx] }, false)
  elseif row.kind == "tilt" then
    app_obj.backend:apply_settings({ tilt_enabled = settings.tilt_enabled == false and true or false }, false)
  elseif row.kind == "refresh" then
    app_obj.backend:queue_refresh()
  end
  refresh_view()
  update_menu()
end

local function handle_controller_pressed(pressed)
  if pressed == 0 then return end
  -- 与 Weather 完全一致：SELECT/View 或 HOME 随时退出应用并返回 Launcher。
  if (pressed & (PAD_SELECT | PAD_HOME)) ~= 0 then
    app_obj.stop("controller-exit")
    if app and app.exit then pcall(function() app.exit() end) end
    return
  end
  if app_obj.input.menu_open then
    if (pressed & PAD_MENU) ~= 0 or (pressed & PAD_B) ~= 0 then
      set_menu(false)
      return
    end
    if (pressed & PAD_UP) ~= 0 then
      app_obj.input.menu_index = wrap_index(app_obj.input.menu_index - 1, #app_obj.input.menu_rows)
      update_menu()
    elseif (pressed & PAD_DOWN) ~= 0 then
      app_obj.input.menu_index = wrap_index(app_obj.input.menu_index + 1, #app_obj.input.menu_rows)
      update_menu()
    elseif (pressed & PAD_LEFT) ~= 0 then
      change_menu_value(-1)
    elseif (pressed & PAD_RIGHT) ~= 0 or (pressed & PAD_A) ~= 0 then
      change_menu_value(1)
    end
    return
  end

  if (pressed & PAD_MENU) ~= 0 then
    set_menu(true)
  elseif (pressed & PAD_LEFT) ~= 0 then
    app_obj.backend:select_group_asset_delta(-1)
    refresh_view()
  elseif (pressed & PAD_RIGHT) ~= 0 then
    app_obj.backend:select_group_asset_delta(1)
    refresh_view()
  elseif (pressed & PAD_UP) ~= 0 then
    app_obj.backend:select_interval_delta(-1)
    refresh_view()
  elseif (pressed & PAD_DOWN) ~= 0 then
    app_obj.backend:select_interval_delta(1)
    refresh_view()
  elseif (pressed & PAD_A) ~= 0 then
    app_obj.backend:queue_refresh()
  end
end

-- 与 Launcher 相同：40 ms 轮询并只处理 buttons 的上升沿。
local function poll_controller()
  local ctrl = rawget(_G, "controller")
  if not ctrl or not ctrl.state then return end
  local ok, state = pcall(function() return ctrl.state("ble-main") end)
  if not ok or type(state) ~= "table" or state.connected == false then
    app_obj.input.controller_buttons = 0
    return
  end
  local buttons = tonumber(state.buttons) or 0
  local pressed = buttons & (~app_obj.input.controller_buttons)
  app_obj.input.controller_buttons = buttons
  handle_controller_pressed(pressed)
end

local KEYMOD = rawget(_G, "key")
local KEY_START = (KEYMOD and KEYMOD.START) or 1
local KEY_SHORT = (KEYMOD and KEYMOD.SHORT) or 2
local KEY_LONG_START = (KEYMOD and KEYMOD.LONG_START) or 3
local KEY_LONG_REPEAT = (KEYMOD and KEYMOD.LONG_REPEAT) or 4
local KEY_LONG_END = (KEYMOD and KEYMOD.LONG_END) or 5

-- Launcher 原样手感：达到倾斜阈值的 START 当场翻页，长持每三个 repeat 再翻一次。
local function handle_tilt_key(delta, side, evt_type)
  local settings = app_obj.backend:snapshot().settings or {}
  if settings.tilt_enabled == false or app_obj.input.menu_open then
    app_obj.input[side] = 0
    return
  end
  if evt_type == KEY_START then
    app_obj.backend:select_group_asset_delta(delta)
  elseif evt_type == KEY_LONG_START then
    app_obj.input[side] = 0
    app_obj.backend:select_group_asset_delta(delta)
  elseif evt_type == KEY_LONG_REPEAT then
    app_obj.input[side] = app_obj.input[side] + 1
    if (app_obj.input[side] % 3) == 0 then app_obj.backend:select_group_asset_delta(delta) else return end
  elseif evt_type == KEY_LONG_END then
    app_obj.input[side] = 0
    return
  else
    return
  end
  refresh_view()
end

local function bind_keys()
  if not KEYMOD or not KEYMOD.on then return end
  KEYMOD.on(KEYMOD.LEFT, function(evt_type) handle_tilt_key(-1, "repeat_left", evt_type) end)
  KEYMOD.on(KEYMOD.RIGHT, function(evt_type) handle_tilt_key(1, "repeat_right", evt_type) end)
  KEYMOD.on(KEYMOD.UP, function(evt_type)
    if evt_type == KEY_SHORT and not app_obj.input.menu_open then app_obj.backend:select_interval_delta(-1); refresh_view() end
  end)
  KEYMOD.on(KEYMOD.DOWN, function(evt_type)
    if evt_type == KEY_SHORT and not app_obj.input.menu_open then app_obj.backend:select_interval_delta(1); refresh_view() end
  end)
end

function app_obj.stop(reason)
  if app_obj.stopping then return end
  app_obj.stopping = true
  for _, timer in ipairs({ app_obj.tick_timer, app_obj.controller_timer }) do
    if timer then
      pcall(function() timer:stop() end)
      pcall(function() timer:unregister() end)
    end
  end
  app_obj.tick_timer, app_obj.controller_timer = nil, nil
  if KEYMOD and KEYMOD.on then
    for _, code in ipairs({ KEYMOD.LEFT, KEYMOD.RIGHT, KEYMOD.UP, KEYMOD.DOWN }) do
      pcall(function() KEYMOD.on(code, nil) end)
    end
  end
  if app_obj.web then pcall(function() app_obj.web:stop(reason) end) end
  if app_obj.ui then pcall(function() app_obj.ui:stop(reason) end) end
  if app_obj.backend then pcall(function() app_obj.backend:stop(reason) end) end
end

local function start_timers()
  if not tmr or not tmr.create then return end
  app_obj.tick_timer = tmr.create()
  app_obj.tick_timer:alarm(500, tmr.ALARM_AUTO, function()
    if app and app.exiting and app.exiting() then app_obj.stop("exit"); return end
    app_obj.backend:tick()
    app_obj.ui:render()
  end)
  app_obj.controller_timer = tmr.create()
  app_obj.controller_timer:alarm(CONTROLLER_POLL_MS, tmr.ALARM_AUTO, poll_controller)
end

BTC_MARKETS_APP = app_obj
app_obj.ui:build()
app_obj.ui:render(true)
app_obj.web:start()
bind_keys()
start_timers()
