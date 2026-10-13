-- Lua-only A/B test: preload the next GIF in a hidden second canvas.
-- There is no first-frame-ready API: this gives it almost 3 seconds to load,
-- not a guarantee that decoding succeeded. Hidden GIFs continue animating.
GIF_SWITCH_TEST = {}
local APP = GIF_SWITCH_TEST
local root = lv_scr_act()
lv_obj_clean(root)
local style = LV_PART_MAIN | LV_STATE_DEFAULT
lv_obj_set_style_bg_color(root, 0x000000, style)
lv_obj_set_style_bg_opa(root, 255, style)

local names = {"happy", "angry", "surprised"}
local slots = {lv_gif_create(root), lv_gif_create(root)}
for _, gif in ipairs(slots) do
  assert(gif and gif ~= 0, "GIF canvas creation failed")
  lv_obj_add_flag(gif, LV_OBJ_FLAG_HIDDEN)
  lv_obj_set_align(gif, LV_ALIGN_CENTER, 0, 0)
end
local index = 1
local front = 1
local function load_slot(slot, item)
  local path = "/apps/xiaozhi/assets/emojis/gif/" .. names[item] .. ".gif"
  lv_gif_set_src(slots[slot], path)
  lv_obj_set_align(slots[slot], LV_ALIGN_CENTER, 0, 0)
end

load_slot(front, index)
lv_obj_clear_flag(slots[front], LV_OBJ_FLAG_HIDDEN)
local last_switch = millis()
local preload_pending = true
local timer = tmr.create()
timer:alarm(25, tmr.ALARM_AUTO, function()
  local now = millis()
  local elapsed = now - last_switch
  if elapsed >= 3000 and not preload_pending then
    local old_front = front
    front = 3 - front
    index = index % #names + 1
    -- Reveal the already-loaded canvas before hiding the old one.
    -- Do not call set_src on the new foreground canvas at the boundary.
    lv_obj_move_foreground(slots[front])
    lv_obj_clear_flag(slots[front], LV_OBJ_FLAG_HIDDEN)
    lv_obj_add_flag(slots[old_front], LV_OBJ_FLAG_HIDDEN)
    last_switch = now
    preload_pending = true
    print("GIF_SWITCH_TEST double-buffer " .. names[index] .. " t=" .. tostring(now))
  elseif preload_pending and elapsed >= 100 then
    -- Allow the visibility commands to take effect before reusing the old
    -- slot. Source replacement also disposes of its previous GIF runtime.
    load_slot(3 - front, index % #names + 1)
    preload_pending = false
  end
end)

function APP.shutdown(reason)
  if timer then
    timer:stop()
    timer:unregister()
    timer = nil
  end
  if GIF_SWITCH_TEST == APP then GIF_SWITCH_TEST = nil end
end
APP.stop = APP.shutdown
