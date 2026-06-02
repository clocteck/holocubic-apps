local prev = rawget(_G, "PHOTO_CANVAS_APP")
if prev and prev.shutdown then
  pcall(function()
    prev.shutdown()
  end)
end

PHOTO_CANVAS_APP = {}
local APP = PHOTO_CANVAS_APP
local function clear_root()
  if not lv_scr_act or not lv_obj_clean then
    return
  end
  local ok, root = pcall(lv_scr_act)
  if ok and root then
    pcall(lv_obj_clean, root)
  end
end
local lv_anim_delete = lv_anim_delete or lv_anim_del
local lv_img_free_handle = lv_img_free_handle or (lv_snapshot_free and function(handle)
  if handle then
    pcall(function() lv_snapshot_free(handle) end)
  end
end) or function() end

local root = lv_scr_act()
clear_root()

local screen_w = 320
local screen_h = 240
local MAIN_STYLE = LV_PART_MAIN | LV_STATE_DEFAULT

local dir = "/sd/images"
local play_ms = 10000
local slide_ms = 280

local function apply_panel_style(id, color)
  lv_obj_set_style_bg_color(id, color, MAIN_STYLE)
  lv_obj_set_style_bg_opa(id, 255, MAIN_STYLE)
  lv_obj_set_style_border_width(id, 0, MAIN_STYLE)
  lv_obj_set_style_radius(id, 0, MAIN_STYLE)
  lv_obj_set_style_pad_all(id, 0, MAIN_STYLE)
end

local function canvas_frame_begin(id)
  if lv_canvas_begin and lv_canvas_end then
    local ok = pcall(function()
      lv_canvas_begin(id)
    end)
    return ok
  end
  return false
end

local function canvas_frame_end(id, explicit_frame)
  if explicit_frame and lv_canvas_end then
    pcall(function()
      lv_canvas_end(id)
    end)
    return
  end

  if lv_obj_invalidate then
    pcall(function()
      lv_obj_invalidate(id)
    end)
  end
end

local bg = lv_obj_create(root)
lv_obj_set_pos(bg, 0, 0)
lv_obj_set_size(bg, screen_w, screen_h)
apply_panel_style(bg, 0x000000)

local info = lv_label_create(root)
lv_label_set_text(info, "")
lv_obj_set_style_text_font(info, 14, MAIN_STYLE)
lv_obj_set_style_text_color(info, 0xFFFFFF, MAIN_STYLE)
lv_obj_set_style_text_opa(info, 255, MAIN_STYLE)
lv_obj_set_align(info, LV_ALIGN_BOTTOM_MID, 0, -8)

local function is_image(name)
  local ext = name:match("%.([%a%d]+)$")
  if not ext then
    return false
  end
  ext = ext:lower()
  return ext == "jpg" or ext == "jpeg" or ext == "png" or ext == "bmp" or ext == "webp"
end

local function sd_to_lv(path)
  if path:sub(1, 4) == "/sd/" then
    return "S:/" .. path:sub(5)
  end
  return path
end

local function list_images(path)
  local out = {}
  local entries = file.listdir(path) or {}
  for _, e in ipairs(entries) do
    if e and (not e.is_dir) and e.name and is_image(e.name) then
      out[#out + 1] = e.name
    end
  end
  table.sort(out)
  return out
end

local images = list_images(dir)
local index = 1
local animating = false
local anim_end_ms = 0
local slide_dir = 0
local last_switch = millis() or 0

local function create_canvas_slot(x)
  local id = lv_canvas_create(root, screen_w, screen_h, CANVAS_FMT_TRUE_COLOR)
  lv_obj_set_pos(id, x, 0)
  return {
    id = id,
    name = nil,
  }
end

local left_slot = create_canvas_slot(-screen_w)
local center_slot = create_canvas_slot(0)
local right_slot = create_canvas_slot(screen_w)

local function set_label(text)
  lv_label_set_text(info, text or "")
  lv_obj_set_style_text_opa(info, 255, MAIN_STYLE)
end

local function clear_slot(slot)
  if not slot or not slot.id then
    return
  end

  local explicit_frame = canvas_frame_begin(slot.id)
  lv_canvas_fill_bg(slot.id, 0x000000, 255)
  canvas_frame_end(slot.id, explicit_frame)
  slot.name = nil
end

-- 这里假设 `/sd/images` 下主要是与屏幕尺寸匹配的静态图片；
-- canvas 当前只负责“整张图画进去再平移”，不做额外缩放排版。
local function draw_image_to_slot(slot, name)
  if not slot or not slot.id then
    return
  end

  if not name or name == "" then
    clear_slot(slot)
    return
  end

  if slot.name == name then
    return
  end

  local src = sd_to_lv(dir) .. "/" .. name
  local explicit_frame = canvas_frame_begin(slot.id)
  lv_canvas_fill_bg(slot.id, 0x000000, 255)
  lv_canvas_draw_img(slot.id, 0, 0, src, { opa = 255 })
  canvas_frame_end(slot.id, explicit_frame)
  slot.name = name
end

local function wrap_index(i)
  local n = #images
  if n <= 0 then
    return 0
  end
  while i < 1 do
    i = i + n
  end
  while i > n do
    i = i - n
  end
  return i
end

local function image_name_at(i)
  if #images == 0 then
    return nil
  end
  return images[wrap_index(i)]
end

local function position_slots()
  lv_obj_set_pos(left_slot.id, -screen_w, 0)
  lv_obj_set_pos(center_slot.id, 0, 0)
  lv_obj_set_pos(right_slot.id, screen_w, 0)
end

local function sync_slots()
  if #images == 0 then
    clear_slot(left_slot)
    clear_slot(center_slot)
    clear_slot(right_slot)
    set_label("NO IMAGES")
    return
  end

  draw_image_to_slot(center_slot, image_name_at(index))
  draw_image_to_slot(left_slot, image_name_at(index - 1))
  draw_image_to_slot(right_slot, image_name_at(index + 1))
  set_label(image_name_at(index))
end

local function finish_slide(ts_ms)
  if not animating then
    return
  end

  animating = false
  anim_end_ms = 0

  if slide_dir > 0 then
    local old_left = left_slot
    left_slot = center_slot
    center_slot = right_slot
    right_slot = old_left
    index = wrap_index(index + 1)
  elseif slide_dir < 0 then
    local old_right = right_slot
    right_slot = center_slot
    center_slot = left_slot
    left_slot = old_right
    index = wrap_index(index - 1)
  end

  slide_dir = 0
  position_slots()
  sync_slots()
  last_switch = ts_ms or (millis() or 0)
end

local function start_slide(dir_sign, ts_ms)
  if #images <= 1 then
    return
  end
  if animating then
    return
  end
  if dir_sign ~= -1 and dir_sign ~= 1 then
    return
  end

  slide_dir = dir_sign
  animating = true
  anim_end_ms = (ts_ms or (millis() or 0)) + slide_ms + 20

  pcall(function() lv_anim_delete(left_slot.id, ANIM_X) end)
  pcall(function() lv_anim_delete(center_slot.id, ANIM_X) end)
  pcall(function() lv_anim_delete(right_slot.id, ANIM_X) end)

  if dir_sign > 0 then
    lv_anim_start(left_slot.id, ANIM_X, -screen_w, -screen_w * 2, slide_ms, 0, ANIM_PATH_EASE_IN_OUT)
    lv_anim_start(center_slot.id, ANIM_X, 0, -screen_w, slide_ms, 0, ANIM_PATH_EASE_IN_OUT)
    lv_anim_start(right_slot.id, ANIM_X, screen_w, 0, slide_ms, 0, ANIM_PATH_EASE_IN_OUT)
  else
    lv_anim_start(left_slot.id, ANIM_X, -screen_w, 0, slide_ms, 0, ANIM_PATH_EASE_IN_OUT)
    lv_anim_start(center_slot.id, ANIM_X, 0, screen_w, slide_ms, 0, ANIM_PATH_EASE_IN_OUT)
    lv_anim_start(right_slot.id, ANIM_X, screen_w, screen_w * 2, slide_ms, 0, ANIM_PATH_EASE_IN_OUT)
  end
end

local function confirm_left(ts_ms)
  start_slide(-1, ts_ms)
end

local function confirm_right(ts_ms)
  start_slide(1, ts_ms)
end

position_slots()
sync_slots()

local long_repeat_state = {}

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
  if #images == 0 then
    return
  end

  local key_dir = nil
  if evt_code == key.LEFT then
    key_dir = "left"
  elseif evt_code == key.RIGHT then
    key_dir = "right"
  else
    return
  end

  if not should_trigger_press(evt_type, evt_code) then
    return
  end

  if key_dir == "left" then
    confirm_left(ts_ms or (millis() or 0))
  else
    confirm_right(ts_ms or (millis() or 0))
  end
end)

local tick_timer = tmr.create()
tick_timer:alarm(20, tmr.ALARM_AUTO, function()
  local ts_ms = millis() or 0

  if animating and ts_ms >= anim_end_ms then
    finish_slide(ts_ms)
  end

  if #images <= 1 then
    return
  end

  if (not animating) and play_ms > 0 and (ts_ms - last_switch) >= play_ms then
    start_slide(1, ts_ms)
  end
end)

function APP.shutdown()
  pcall(function() key.off() end)
  pcall(function() tick_timer:stop() end)
  pcall(function() tick_timer:unregister() end)
  pcall(function() lv_anim_delete(left_slot.id, ANIM_X) end)
  pcall(function() lv_anim_delete(center_slot.id, ANIM_X) end)
  pcall(function() lv_anim_delete(right_slot.id, ANIM_X) end)
end
