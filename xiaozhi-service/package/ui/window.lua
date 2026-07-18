local M = {}

local W, H = 200, 100
local X, Y = 120, 140
local PANEL = 0x111827
local PANEL_ALT = 0x0F172A
local WHITE = 0xF9FAFB
local MUTED = 0xCBD5E1
local ACCENT = 0x22C55E
local ERROR = 0x7F1D1D

local function clip(text, max_chars)
  text = tostring(text or ""):gsub("[%c]+", " ")
  local pos, count, last = 1, 0, 0
  while pos <= #text and count < max_chars do
    local byte = text:byte(pos)
    local width = byte < 0x80 and 1 or (byte < 0xE0 and 2 or (byte < 0xF0 and 3 or 4))
    if pos + width - 1 > #text then break end
    last = pos + width - 1
    pos = pos + width
    count = count + 1
  end
  if last >= #text then return text end
  return text:sub(1, last) .. "..."
end

function M.new(cfg)
  local self = {
    canvas = nil,
    state = "idle",
    status = "小智待命中",
    emotion = "neutral",
    role = "system",
    text = "",
    notice = "",
    stopped = false,
    native_font = nil,
    native_font_path = nil,
    render_timer = nil,
  }

  local function rect(x, y, w, h, color, radius, opa)
    if not self.canvas or not lv_canvas_draw_rect then return end
    pcall(lv_canvas_draw_rect, self.canvas, x, y, w, h, {
      bg_color = color, bg_opa = opa or 255, radius = radius or 0,
      border_width = 0,
    })
  end

  local function text(x, y, w, value, color, size, align)
    if not lv_canvas_draw_text then return end
    pcall(lv_canvas_draw_text, self.canvas, x, y, w, tostring(value or ""), {
      color = color or WHITE,
      opa = 255,
      align = align or LV_TEXT_ALIGN_LEFT,
      font_size = size or 16,
      font_handle = self.native_font,
    })
  end

  local function ensure_canvas()
    if self.canvas then return true end
    if not service_ui or not service_ui.acquire then return false end
    local id, err = service_ui.acquire(X, Y, W, H)
    if not id then
      print("[xiaozhi] window float acquire failed", tostring(err or ""))
      return false
    end
    self.canvas = id
    if service_ui.clear then pcall(service_ui.clear, self.canvas) end
    return true
  end

  local function release_canvas()
    if not self.canvas then return end
    if service_ui.hide then pcall(service_ui.hide, self.canvas) end
    if service_ui.release then pcall(service_ui.release, self.canvas) end
    self.canvas = nil
  end

  local function render_now()
    if not self.canvas or self.stopped then return end
    if lv_canvas_frame_begin then pcall(lv_canvas_frame_begin, self.canvas) end
    rect(0, 0, W, H, self.state == "fatal_error" and ERROR or PANEL, 0)
    rect(0, 0, W, 22, PANEL_ALT, 0)
    local dot = self.state == "listening" and ACCENT
      or (self.state == "speaking" and 0x60A5FA or 0x64748B)
    rect(8, 7, 8, 8, dot, 4)
    text(22, 3, 168, clip(self.status, 12), MUTED, 14)
    local line = self.text ~= "" and self.text or self.notice
    if line == "" then line = self.status end
    text(12, 34, 176, clip(line, 18), WHITE, 18)
    if lv_canvas_frame_end then pcall(lv_canvas_frame_end, self.canvas) end
    if service_ui.show then pcall(service_ui.show, self.canvas) end
  end

  local function render()
    if not ensure_canvas() then return end
    if not tmr or not tmr.create then render_now(); return end
    if self.render_timer then return end
    local timer = tmr.create()
    self.render_timer = timer
    timer:alarm(80, tmr.ALARM_SINGLE, function(instance)
      pcall(function() instance:unregister() end)
      if self.render_timer == timer then self.render_timer = nil end
      render_now()
    end)
  end

  function self:set_view_mode() end
  function self:set_metrics() end
  function self:update_status_bar() end

  function self:set_status(value)
    self.status = tostring(value or "")
    render()
  end

  function self:show_notification(value)
    self.notice = tostring(value or "")
    render()
  end

  function self:set_emotion(value)
    self.emotion = tostring(value or "neutral")
  end

  function self:set_chat_message(role, content)
    self.role = tostring(role or "system")
    self.text = tostring(content or "")
    render_now()
  end

  function self:clear_chat_messages()
    self.text = ""
  end

  function self:on_state(state)
    self.state = tostring(state or "idle")
    local labels = {
      starting = "正在启动", activating = "正在连接服务", connecting = "正在连接",
      listening = "我在听", speaking = "小智正在回答", fatal_error = "启动失败",
      idle = "小智待命中",
    }
    self.status = labels[self.state] or self.status
    if self.state == "idle" then
      release_canvas()
    elseif self.state == "starting" or self.state == "activating" then
      if self.canvas then release_canvas() end
    else
      render()
    end
  end

  function self:alert(status, message)
    self.state = "fatal_error"
    self.status = tostring(status or "发生错误")
    self.text = tostring(message or "")
    render()
  end

  function self:setup()
    self.stopped = false
    self.native_font_path = (cfg.UI_APP_DIR or cfg.APP_DIR or "/sd/apps/xiaozhi")
      .. "/assets/fonts/xiaozhi_common3500_16.bin"
    if not self.native_font and type(rawget(_G, "lv_font_load")) == "function" then
      local ok, handle = pcall(lv_font_load, self.native_font_path)
      if ok and type(handle) == "number" and handle > 0 then self.native_font = handle end
    end
  end

  function self:diagnostics()
    return {
      mode = "window",
      native_font = self.native_font,
      native_font_path = self.native_font_path,
    }
  end

  function self:stop()
    self.stopped = true
    if self.render_timer then pcall(function() self.render_timer:unregister() end); self.render_timer = nil end
    release_canvas()
    if self.native_font and type(rawget(_G, "lv_font_free")) == "function" then
      pcall(lv_font_free, self.native_font)
    end
    self.native_font = nil
    self.native_font_path = nil
  end

  return self
end

return M
