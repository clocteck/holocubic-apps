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

local root = lv_scr_act()
clear_root()

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

local dir = "/sd/videos"
local play_ms = 10000
local last_switch = 0

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
    lv_gif_set_src(gif, src)
  end
end

show_gif()

local long_repeat_state = {}
local last_tick_log_ms = -1000000

local function confirm_left(ts_ms)
  index = index - 1
  show_gif()
  last_switch = ts_ms
  print("KEY_LEFT_CONFIRM")
end

local function confirm_right(ts_ms)
  index = index + 1
  show_gif()
  last_switch = ts_ms
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

key.on(function(evt_code, evt_type, ts_ms)
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
    index = index + 1
    --show_gif()
    last_switch = ts_ms
  end
  -- ptint ("SCRIPT :  tick_20ms \n")
end)
