local APP_DIR = "/sd/apps/aida_monitor"

if file and file.exists and not file.exists(APP_DIR .. "/config.lua") then
  for _, dir in ipairs({ "/sd/apps/monitor", "aida_monitor/package", "aida_monitor" }) do
    if file.exists(dir .. "/config.lua") then APP_DIR = dir break end
  end
end

if _G.__aida_monitor and _G.__aida_monitor.stop then pcall(_G.__aida_monitor.stop) end

local config = dofile(APP_DIR .. "/config.lua")
local Layout = dofile(APP_DIR .. "/aida_layout.lua")
local Renderer = dofile(APP_DIR .. "/aida_renderer.lua")
local AidaClient = dofile(APP_DIR .. "/aida_client.lua")
local VectorFont = dofile(APP_DIR .. "/aida_vector_font.lua")
local Pager = dofile(APP_DIR .. "/aida_pager.lua")
local AidaWeb = nil
if file and file.exists and file.exists(APP_DIR .. "/web.lua") then
  local ok, module = pcall(dofile, APP_DIR .. "/web.lua")
  if ok then AidaWeb = module else print("[aida-monitor] web_load_error", module) end
end

local MAIN = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
local ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1
local FLAG_SCROLLABLE = rawget(_G, "LV_OBJ_FLAG_SCROLLABLE")

local state = {
  stopped = false,
  generation = 0,
  client = nil,
  renderer = nil,
  web = nil,
  retry_timer = nil,
  reload_timer = nil,
  status = "STARTING",
  detail = "",
  last_event_ms = 0,
  layout = nil,
  vector_font = VectorFont.new(config),
  pager = Pager.new(config),
}

local function log(...)
  if config.serial_log ~= false then print("[aida-monitor]", ...) end
end

local function now_ms()
  if type(millis) == "function" then
    local ok, value = pcall(millis)
    if ok and type(value) == "number" then return value end
  end
  if tmr and tmr.now then
    local ok, value = pcall(tmr.now)
    if ok and type(value) == "number" then return math.floor(value / 1000) end
  end
  return 0
end

local function stop_timer(name)
  local timer = state[name]
  if timer then pcall(function() timer:unregister() end) end
  state[name] = nil
end

local function clear_root(color)
  local root = lv_scr_act()
  if lv_obj_clean then pcall(lv_obj_clean, root)
  elseif lv_clear then pcall(lv_clear) end
  if lv_obj_set_style_bg_color then pcall(lv_obj_set_style_bg_color, root, color or 0, MAIN) end
  if lv_obj_set_style_bg_opa then pcall(lv_obj_set_style_bg_opa, root, 255, MAIN) end
  if FLAG_SCROLLABLE and lv_obj_clear_flag then pcall(lv_obj_clear_flag, root, FLAG_SCROLLABLE) end
  return root
end

local function show_message(title, detail, color)
  if state.renderer then return end
  local root = clear_root(0x000000)
  if not lv_label_create then return end
  local label = lv_label_create(root)
  pcall(lv_obj_set_pos, label, 12, 78)
  pcall(lv_obj_set_width, label, 296)
  pcall(lv_label_set_text, label, tostring(title or "AIDA MONITOR"))
  pcall(lv_obj_set_style_text_color, label, color or 0xFFFFFF, MAIN)
  pcall(lv_obj_set_style_text_font, label, 20, MAIN)
  pcall(lv_obj_set_style_text_align, label, ALIGN_CENTER, MAIN)
  local sub = lv_label_create(root)
  pcall(lv_obj_set_pos, sub, 12, 112)
  pcall(lv_obj_set_width, sub, 296)
  pcall(lv_label_set_text, sub, tostring(detail or ""))
  pcall(lv_obj_set_style_text_color, sub, 0x8A96A6, MAIN)
  pcall(lv_obj_set_style_text_font, sub, 12, MAIN)
  pcall(lv_obj_set_style_text_align, sub, ALIGN_CENTER, MAIN)
end

local function set_status(status, detail)
  state.status = status
  state.detail = detail or ""
  log("status", status, state.detail)
end

local function schedule_layout_retry(delay, fetch_layout)
  if state.stopped or not tmr or not tmr.create then return end
  stop_timer("retry_timer")
  state.retry_timer = tmr.create()
  state.retry_timer:alarm(delay or config.layout_retry_ms or 3000, tmr.ALARM_SINGLE, function()
    state.retry_timer = nil
    if not state.stopped then fetch_layout("retry") end
  end)
end

local start_stream
local fetch_layout

local function schedule_reload()
  if state.stopped then return end
  if state.client then state.client:stop() state.client = nil end
  stop_timer("reload_timer")
  if tmr and tmr.create then
    state.reload_timer = tmr.create()
    state.reload_timer:alarm(config.reload_delay_ms or 500, tmr.ALARM_SINGLE, function()
      state.reload_timer = nil
      if not state.stopped then fetch_layout("reload") end
    end)
  else
    fetch_layout("reload")
  end
end

start_stream = function()
  if state.stopped then return end
  if state.client then state.client:stop() end
  state.client = AidaClient.new(config, {
    on_status = function(status, detail)
      if status == "connecting" then set_status("CONNECTING", detail)
      elseif status == "connected" or status == "stream" then set_status("WAITING", detail)
      elseif status == "stale" then set_status("STALE", detail)
      elseif status == "error" or status == "complete" then set_status("OFFLINE", detail) end
    end,
    on_sample = function(sample)
      state.last_event_ms = sample.received_at or now_ms()
      if state.renderer then
        sample.page = state.pager:accept_remote(sample.page, #state.renderer.pages)
        state.renderer:apply_sample(sample)
      end
      set_status("LIVE", "page " .. tostring(state.renderer and state.renderer.active_page or 1))
    end,
    on_control = function(control)
      log("control", control)
      if control == "ReLoad" then
        set_status("RELOADING", "AIDA64 layout changed")
        schedule_reload()
      end
    end,
  })
  local ok, err = pcall(function() state.client:start() end)
  if not ok then
    state.client = nil
    set_status("ERROR", tostring(err))
    schedule_layout_retry(config.reconnect_ms or 2000, fetch_layout)
  end
end

fetch_layout = function(reason)
  if state.stopped then return end
  stop_timer("retry_timer")
  state.generation = state.generation + 1
  local generation = state.generation
  set_status("LAYOUT", Layout.url(config))
  if not state.renderer then show_message("AIDA REMOTESENSOR", "Loading layout from " .. tostring(config.host) .. ":" .. tostring(config.port), 0x49B6FF) end
  Layout.fetch(config, function(ok, model, err)
    if state.stopped or generation ~= state.generation then return end
    if not ok then
      set_status("LAYOUT ERROR", tostring(err))
      show_message("REMOTE SENSOR OFFLINE", tostring(err), 0xFF6B5F)
      schedule_layout_retry(config.layout_retry_ms or 3000, fetch_layout)
      return
    end
    if state.client then state.client:stop() state.client = nil end
    if state.renderer then state.renderer:destroy() state.renderer = nil end
    local font_ok, font_err = state.vector_font:select_for_layout(model, config)
    if not font_ok then log("font selection", tostring(font_err)) end
    local renderer = Renderer.new({
      config = config,
      layout = model,
      root = lv_scr_act(),
      resource_url = function(src) return Layout.resource_url(config, src) end,
      log = log,
      vector_font = state.vector_font,
    })
    local built, build_err = pcall(function() renderer:build() end)
    if not built then
      renderer:destroy()
      set_status("RENDER ERROR", tostring(build_err))
      show_message("LAYOUT NOT SUPPORTED", tostring(build_err), 0xFF6B5F)
      schedule_layout_retry(config.layout_retry_ms or 3000, fetch_layout)
      return
    end
    state.renderer = renderer
    state.layout = model
    local restored_page = state.pager:restore(model.page_count)
    if restored_page then renderer:set_page(restored_page) end
    set_status("READY", tostring(model.page_count) .. " page(s), " .. tostring(model.item_count) .. " item(s)")
    start_stream()
  end)
end

function state.snapshot()
  local render = state.renderer and state.renderer:snapshot() or {}
  local pager = state.pager:snapshot()
  return {
    status = state.status,
    detail = state.detail,
    last_event_ms = state.last_event_ms,
    page = render.page or 0,
    pages = render.pages or 0,
    items = render.items or 0,
    counts = render.counts or {},
    images_loaded = render.images_loaded or 0,
    images_skipped = render.images_skipped or 0,
    image_error = render.image_error or "",
    font = render.font or tostring(config.vector_font_family or "Tahoma"),
    font_face = render.font_face or tostring(config.vector_font_fallback_family or "AIDA Noto Sans SC"),
    font_engine = render.font_engine or "firmware fallback",
    font_loaded = render.font_loaded ~= false,
    font_error = render.font_error or "",
    font_bytes = render.font_bytes or 0,
    font_cache_bytes = render.font_cache_bytes or 0,
    font_cache_entries = render.font_cache_entries or 0,
    font_renders = render.font_renders or 0,
    font_missing_glyphs = render.font_missing_glyphs or 0,
    font_source = render.font_source or "default",
    font_match = render.font_match == true,
    font_selection = render.font_selection or "",
    font_requested_families = render.font_requested_families or "",
    font_path = render.font_path or tostring(config.vector_font_default_path or config.vector_font_path or ""),
    internal_free = render.internal_free or 0,
    psram_free = render.psram_free or 0,
    psram_largest = render.psram_largest or 0,
    compositor = render.compositor or "legacy-canvas",
    background_ready = render.background_ready == true,
    layer_model = render.layer_model or "legacy-dom",
    subpixel = render.subpixel or tostring(config.font_subpixel or "off"),
    antialiasing = render.antialiasing or "firmware",
    surface_bytes = render.surface_bytes or 0,
    surface_flushes = render.surface_flushes or 0,
    page_source = pager.source,
    tilt_page_cooldown_ms = pager.cooldown_ms,
  }
end

function state.turn_page(direction)
  if state.stopped or not state.renderer then return false, "renderer unavailable" end
  local page, changed = state.pager:step(state.renderer.active_page,
    #state.renderer.pages, direction, now_ms())
  if not changed then return false, "cooldown or single page" end
  state.renderer:set_page(page)
  set_status("LIVE", "page " .. tostring(page) .. " · tilt")
  return true, page
end

function state.restart_client()
  if state.stopped then return false, "stopped" end
  if state.client then state.client:stop() state.client = nil end
  if state.vector_font then
    state.vector_font.subpixel_order = tostring(config.font_subpixel or "rgb"):lower()
  end
  stop_timer("retry_timer")
  stop_timer("reload_timer")
  fetch_layout("configuration")
  return true
end

function state.stop()
  state.stopped = true
  state.generation = state.generation + 1
  stop_timer("retry_timer")
  stop_timer("reload_timer")
  if state.client then state.client:stop() state.client = nil end
  if state.renderer then state.renderer:destroy() state.renderer = nil end
  if state.web then state.web:stop("app_stop") state.web = nil end
  if key and key.off then key.off() end
end

if key and key.on then
  local function tilt(direction, event)
    -- START is emitted once when the gravity threshold is crossed. SHORT is
    -- the release half of the same gesture; consuming both would double-page.
    if event == key.START then state.turn_page(direction) end
  end
  if key.LEFT then key.on(key.LEFT, function(event) tilt(-1, event) end) end
  if key.RIGHT then key.on(key.RIGHT, function(event) tilt(1, event) end) end
  if key.HOME then
    key.on(key.HOME, function(event)
      if event == key.SHORT then
        state.stop()
        if app and app.exit then app.exit() end
      end
    end)
  end
end

_G.__aida_monitor = state
show_message("AIDA REMOTESENSOR", "Starting...", 0x49B6FF)

if AidaWeb and AidaWeb.new then
  local web_route_base = (app and app.route_base and app.route_base()) or "/aida_monitor"
  state.web = AidaWeb.new({
    config = config,
    config_path = APP_DIR .. "/config.lua",
    route_base = web_route_base,
    restart = function() return state.restart_client() end,
    state = function() return state.snapshot() end,
  })
  state.web:start()
end

fetch_layout("startup")
