-- A short-lived pairing card, kept outside ui/ so it is not offered as a chat style.
local I18n = dofile((rawget(_G, "XIAOZHI_UI_APP_DIR") or "/sd/apps/xiaozhi-service") .. "/i18n.lua")
local M = {}

function M.new(cfg)
  local self = { canvas = nil, timer = nil, font = nil, code = nil }

  function self:close()
    if self.timer then self.timer:unregister(); self.timer = nil end
    if self.canvas then
      pcall(service_ui.hide, self.canvas)
      pcall(service_ui.release, self.canvas)
      self.canvas = nil
    end
    if self.font and type(lv_font_free) == "function" then pcall(lv_font_free, self.font) end
    self.font, self.code = nil, nil
  end

  function self:show(code, update_only)
    code = tostring(code or "")
    if code == "" or (update_only and not self.canvas) then return false end
    if update_only and self.code == code then return true end
    if not self.canvas then
      if not service_ui or not service_ui.acquire then return false end
      self.canvas = service_ui.acquire(20, 152, 280, 80)
      if not self.canvas then return false end
      if type(lv_font_load) == "function" then
        local ok, font = pcall(lv_font_load, (cfg.SERVICE_DIR or cfg.APP_DIR)
          .. "/assets/fonts/xiaozhi_common3500_16.bin")
        if ok and type(font) == "number" and font > 0 then self.font = font end
      end
    end
    self.code = code
    local title, hint = I18n.pairing_prompt(code, cfg)
    if lv_canvas_frame_begin then pcall(lv_canvas_frame_begin, self.canvas) end
    pcall(lv_canvas_draw_rect, self.canvas, 0, 0, 280, 80, {
      bg_color = 0x111827, bg_opa = 245, radius = 8, border_width = 0,
    })
    for index, line in ipairs({ title, hint }) do
      pcall(lv_canvas_draw_text, self.canvas, 12, 12 + (index - 1) * 28, 256, line, {
        color = index == 1 and 0x86EFAC or 0xF9FAFB, opa = 255,
        align = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1,
        font_size = 16, font_handle = self.font,
      })
    end
    if lv_canvas_frame_end then pcall(lv_canvas_frame_end, self.canvas) end
    pcall(service_ui.show, self.canvas)
    -- Polls may update an expired code, but never extend the popup lifetime.
    if not update_only and tmr and tmr.create then
      if self.timer then self.timer:unregister() end
      self.timer = tmr.create()
      self.timer:alarm(10000, tmr.ALARM_SINGLE, function() self:close() end)
    end
    return true
  end
  return self
end
return M
