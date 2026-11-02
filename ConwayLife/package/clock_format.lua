-- Display-only global preference; every app ships its own copy.
-- Never mutate calendar values used by alarms, weather, or hourly events.
local M = {}
local mode, checked = "24", nil
function M.normalize(value)
  return (value == "12" or value == 12) and "12" or "24"
end
function M.mode()
  local now = tmr and tmr.now and tmr.now() / 1000000
    or (os and os.time and os.time() or 0)
  if checked and now >= checked and now - checked < 3 then return mode end
  checked = now
  local ok, doc = pcall(function()
    local raw = file and file.getcontents and file.getcontents("/sd/apps/settings.json")
    local codec = rawget(_G, "json") or rawget(_G, "sjson")
    return raw and codec and codec.decode and codec.decode(raw)
  end)
  -- Keep the last valid preference on transient IO/JSON failure.
  if ok and type(doc) == "table" then mode = M.normalize(doc.time_format) end
  return mode
end
function M.hour(hour, preference)
  if (preference or M.mode()) ~= "12" then return hour end
  return hour % 12 == 0 and 12 or hour % 12
end
function M.period(hour, preference)
  if hour == nil or (preference or M.mode()) ~= "12" then return "" end
  return hour < 12 and "AM" or "PM"
end
function M.text(hour, minute, preference)
  if hour == nil or minute == nil then return "--:--" end
  return string.format("%02d:%02d", M.hour(hour, preference), minute)
end
function M.badge(parent, x, y, color)
  local id = lv_label_create(parent)
  local part = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
  lv_obj_set_pos(id, x, y)
  lv_obj_set_size(id, 30, 16)
  lv_obj_set_style_text_font(id, rawget(_G, "LV_FONT_MONTSERRAT_12") or 12, part)
  lv_obj_set_style_text_color(id, color or 0xFFFFFF, part)
  lv_label_set_text(id, "")
  return id
end
return M
