local prev = rawget(_G, "VIDEOS_APP")
if prev and prev.shutdown then
  pcall(function()
    prev.shutdown("reload")
  end)
end

VIDEOS_APP = {}
local APP = VIDEOS_APP

local root = lv_scr_act()
lv_obj_clean(lv_scr_act())

local screen_w = 320
local screen_h = 240
local MAIN_STYLE = LV_PART_MAIN | LV_STATE_DEFAULT

local function apply_panel_style(id, color)
  lv_obj_set_style_bg_color(id, color, MAIN_STYLE)
  lv_obj_set_style_bg_opa(id, 255, MAIN_STYLE)
  lv_obj_set_style_border_width(id, 0, MAIN_STYLE)
  lv_obj_set_style_radius(id, 0, MAIN_STYLE)
  lv_obj_set_style_pad_all(id, 0, MAIN_STYLE)
end

local bg = lv_obj_create(root)
lv_obj_set_pos(bg, 0, 0)
lv_obj_set_size(bg, screen_w, screen_h)
apply_panel_style(bg, 0x000000)

local gif = lv_gif_create(root)
if gif and gif ~= 0 then
  lv_obj_set_align(gif, LV_ALIGN_CENTER, 0, 0)
end

local info = lv_label_create(root)
lv_label_set_text(info, "")
lv_obj_set_style_text_color(info, 0xFFFFFF, MAIN_STYLE)
lv_obj_set_style_text_opa(info, 0, MAIN_STYLE)
lv_obj_set_style_text_font(info, 14, MAIN_STYLE)
lv_obj_set_align(info, LV_ALIGN_BOTTOM_MID, 0, -8)

local dir = "/sd/gifs"
local play_ms = 10000
local last_switch = millis() or 0

local function is_gif(name)
  local ext = name:match("%.([%a%d]+)$")
  if not ext then return false end
  return ext:lower() == "gif"
end

local function sd_to_sdmmc(path)
  if path:sub(1, 4) == "/sd/" then
    return "/" .. path:sub(5)
  end
  return path
end

local function list_gifs(path)
  local out = {}
  local entries = file.listdir(path) or {}
  for _, e in ipairs(entries) do
    if e and (not e.is_dir) and e.name and is_gif(e.name) then
      table.insert(out, e.name)
    end
  end
  table.sort(out)
  return out
end

-- 读取 GIF 逻辑画布尺寸，用于显示层自动缩放；解码仍由底层按原尺寸完成。
local function read_gif_size(path)
  local fd = file.open(path, "r")
  if not fd then
    return nil, nil
  end

  local header = fd:read(10)
  fd:close()
  if not header or #header < 10 then
    return nil, nil
  end

  local sig = header:sub(1, 6)
  if sig ~= "GIF87a" and sig ~= "GIF89a" then
    return nil, nil
  end

  local b1, b2, b3, b4 = string.byte(header, 7, 10)
  if not b1 or not b2 or not b3 or not b4 then
    return nil, nil
  end

  local width = b1 + b2 * 256
  local height = b3 + b4 * 256
  if width <= 0 or height <= 0 then
    return nil, nil
  end
  return width, height
end

local function calc_fit_zoom(width, height)
  if not width or not height or width <= 0 or height <= 0 then
    return 256
  end

  local scale = math.min(screen_w / width, screen_h / height)
  if scale > 1 then
    scale = 1
  end

  local zoom = math.floor(scale * 256 + 0.5)
  if zoom < 1 then
    zoom = 1
  end
  return zoom
end

local gifs = list_gifs(dir)
local index = 1

local function set_label(text)
  lv_label_set_text(info, text)
  lv_obj_set_style_text_color(info, 0xFFFFFF, MAIN_STYLE)
  lv_obj_set_style_text_opa(info, 0, MAIN_STYLE) -- 透明
end

local function show_gif()
  if #gifs == 0 then
    set_label("NO GIFS")
    lv_obj_set_style_text_color(info, 0xFFFFFF, MAIN_STYLE)
    lv_obj_set_style_text_opa(info, 255, MAIN_STYLE) -- 白色不透明
    if gif and gif ~= 0 then
      lv_gif_set_src(gif, nil)
    end
    return
  end

  if index < 1 then index = #gifs end
  if index > #gifs then index = 1 end

  local name = gifs[index]
  local base = sd_to_sdmmc(dir)
  local src = base .. "/" .. name
  set_label(name)
  if gif and gif ~= 0 then
    local width, height = read_gif_size(src)
    local zoom = calc_fit_zoom(width, height)
    lv_gif_set_src(gif, src)
    lv_img_set_size_mode(gif, LV_IMG_SIZE_MODE_REAL)
    lv_img_set_zoom(gif, zoom)
    lv_obj_set_size(gif, LV_SIZE_CONTENT, LV_SIZE_CONTENT)
    lv_obj_set_align(gif, LV_ALIGN_CENTER, 0, 0)
  end
end

show_gif()

local long_repeat_state = {}
local last_tick_log_ms = -1000000

local function switch_gif(delta, ts_ms)
  index = index + (delta or 1)
  show_gif()
  last_switch = ts_ms or (millis() or 0)
end

local function confirm_left(ts_ms)
  switch_gif(-1, ts_ms)
  print("KEY_LEFT_CONFIRM")
end

local function confirm_right(ts_ms)
  switch_gif(1, ts_ms)
  print("KEY_RIGHT_CONFIRM")
end

local function reset_repeat_state(evt_code)
  long_repeat_state[evt_code] = nil
end

local function should_trigger_press(evt_type, evt_code)
  if evt_type == key.START then
    reset_repeat_state(evt_code)
    return true
  elseif evt_type == key.LONG_START then
    long_repeat_state[evt_code] = {count = 0}
    return false
  elseif evt_type == key.LONG_REPEAT then
    local state = long_repeat_state[evt_code] or {count = 0}
    state.count = state.count + 1
    long_repeat_state[evt_code] = state
    if state.count == 1 or (state.count % 5 == 0) then
      return true
    end
  elseif evt_type == key.LONG_END then
    reset_repeat_state(evt_code)
  end
  return false
end

local function handle_key(evt_code, evt_type, ts_ms)
  if #gifs == 0 then return end

  local dir = nil
  if evt_code == key.LEFT then
    dir = "left"
  elseif evt_code == key.RIGHT then
    dir = "right"
  else
    return
  end

  if not should_trigger_press(evt_type, evt_code) then return end

  if dir == "left" then
    confirm_left(ts_ms)
  else
    confirm_right(ts_ms)
  end
end

key.on(function(evt_code, evt_type, ts_ms)
  handle_key(evt_code, evt_type, ts_ms)
end)

local tick_timer = tmr.create()
tick_timer:alarm(20, tmr.ALARM_AUTO, function()
  local ts_ms = millis() or 0
  if (ts_ms - last_tick_log_ms) >= 1000 then
    last_tick_log_ms = ts_ms
    print("SCRIPT : TICK_1S ")
  end
  if #gifs == 0 then return end
  if play_ms > 0 and (ts_ms - last_switch) >= play_ms then
    switch_gif(1, ts_ms)
  end
  -- ptint ("SCRIPT :  tick_20ms \n")
end)

function APP.shutdown(reason)
  pcall(function() key.off() end)

  if tick_timer then
    pcall(function() tick_timer:stop() end)
    pcall(function() tick_timer:unregister() end)
    tick_timer = nil
  end

  if rawget(_G, "VIDEOS_APP") == APP then
    _G.VIDEOS_APP = nil
  end
end

APP.stop = APP.shutdown
