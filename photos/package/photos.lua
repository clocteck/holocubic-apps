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
local root = lv_scr_act()
clear_root()

local screen_w = 320
local screen_h = 240
local MAIN_STYLE = LV_PART_MAIN | LV_STATE_DEFAULT

local dir = "/sd/images"
local play_ms = 10000
local slide_ms = 280

local function stop_x_anim(id)
  if id and lv_anim_del and lv_obj_set_x then
    pcall(function() lv_anim_del(id, lv_obj_set_x) end)
  end
end

local function start_x_anim(id, from_x, to_x)
  if not id or not lv_anim_t or not lv_anim_init or not lv_anim_set_var or not lv_anim_set_exec_cb or
      not lv_anim_set_values or not lv_anim_set_time or not lv_anim_set_delay or
      not lv_anim_start or not lv_obj_set_x then
    return
  end

  local a = lv_anim_t()
  lv_anim_init(a)
  lv_anim_set_var(a, id)
  lv_anim_set_exec_cb(a, lv_obj_set_x)
  lv_anim_set_values(a, from_x, to_x)
  lv_anim_set_time(a, slide_ms)
  lv_anim_set_delay(a, 0)
  if lv_anim_set_path_cb and lv_anim_path_ease_in_out then
    lv_anim_set_path_cb(a, lv_anim_path_ease_in_out)
  end
  lv_anim_start(a)
end

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
  if lv_obj_clear_flag then
    local scrollable = rawget(_G, "LV_OBJ_FLAG_SCROLLABLE")
    local overflow_visible = rawget(_G, "LV_OBJ_FLAG_OVERFLOW_VISIBLE")
    if scrollable then
      pcall(function() lv_obj_clear_flag(id, scrollable) end)
    end
    if overflow_visible then
      pcall(function() lv_obj_clear_flag(id, overflow_visible) end)
    end
  end

  local image = lv_img_create(id)
  if lv_img_set_size_mode then
    local real_size = rawget(_G, "LV_IMG_SIZE_MODE_REAL")
    if real_size then
      pcall(function() lv_img_set_size_mode(image, real_size) end)
    end
  end
  local hidden = rawget(_G, "LV_OBJ_FLAG_HIDDEN")
  if hidden and lv_obj_add_flag then
    pcall(function() lv_obj_add_flag(image, hidden) end)
  end

  return {
    id = id,
    image = image,
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
  local hidden = rawget(_G, "LV_OBJ_FLAG_HIDDEN")
  if slot.image and hidden and lv_obj_add_flag then
    pcall(function() lv_obj_add_flag(slot.image, hidden) end)
  end
  slot.name = nil
end

-- 图片作为 canvas 的子对象显示，尺寸不足 320x240 时默认在黑色画布中居中；
-- 尺寸超过屏幕时也会从中心向四周裁切，不再固定贴在左上角。
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
  canvas_frame_end(slot.id, explicit_frame)

  lv_img_set_src(slot.image, src)
  if lv_obj_center then
    lv_obj_center(slot.image)
  else
    lv_obj_align(slot.image, LV_ALIGN_CENTER, 0, 0)
  end
  local hidden = rawget(_G, "LV_OBJ_FLAG_HIDDEN")
  if hidden and lv_obj_clear_flag then
    pcall(function() lv_obj_clear_flag(slot.image, hidden) end)
  end
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

  stop_x_anim(left_slot.id)
  stop_x_anim(center_slot.id)
  stop_x_anim(right_slot.id)

  if dir_sign > 0 then
    start_x_anim(left_slot.id, -screen_w, -screen_w * 2)
    start_x_anim(center_slot.id, 0, -screen_w)
    start_x_anim(right_slot.id, screen_w, 0)
  else
    start_x_anim(left_slot.id, -screen_w, 0)
    start_x_anim(center_slot.id, 0, screen_w)
    start_x_anim(right_slot.id, screen_w, screen_w * 2)
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

local controller_timer = nil
if controller and controller.state and tmr and tmr.create then
  local controller_buttons = 0
  controller_timer = tmr.create()
  controller_timer:alarm(40, tmr.ALARM_AUTO, function()
    local ok, pad = pcall(function() return controller.state("ble-main") end)
    local buttons = ok and type(pad) == "table" and (tonumber(pad.buttons) or 0) or 0
    local pressed = buttons & (~controller_buttons)
    controller_buttons = buttons
    if (pressed & (4096 | 32768)) ~= 0 then
      APP.shutdown()
      if app and app.exit then pcall(function() app.exit() end) end
    elseif (pressed & 4) ~= 0 then
      confirm_left(millis() or 0)
    elseif (pressed & 8) ~= 0 then
      confirm_right(millis() or 0)
    end
  end)
end

function APP.shutdown()
  pcall(function() key.off() end)
  pcall(function() tick_timer:stop() end)
  pcall(function() tick_timer:unregister() end)
  if controller_timer then
    pcall(function() controller_timer:stop() end)
    pcall(function() controller_timer:unregister() end)
    controller_timer = nil
  end
  stop_x_anim(left_slot.id)
  stop_x_anim(center_slot.id)
  stop_x_anim(right_slot.id)
end
