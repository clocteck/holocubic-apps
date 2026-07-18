local M = {}

local W, H = 320, 58
local X, Y = 0, 182
local BG = 0x000000
local TEXT = 0xFFFFFF
local LV_TEXT_ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1
local LV_TEXT_ALIGN_LEFT = rawget(_G, "LV_TEXT_ALIGN_LEFT") or 0

local function text_or(value, fallback)
  if value == nil then return fallback or "" end
  local text = tostring(value)
  if text == "" then return fallback or "" end
  return text
end

local function clip_utf8(text, max_chars)
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

local function path_exists(path)
  if not path or path == "" then return false end
  if file and file.exists then
    local ok, exists = pcall(function() return file.exists(path) end)
    if ok then return exists == true end
  end
  if file and file.stat then
    local ok, stat = pcall(function() return file.stat(path) end)
    return ok and stat ~= nil
  end
  return false
end

function M.new(cfg)
  local self = {
    canvas = nil,
    message = "",
    role = "assistant",
    state = "idle",
    native_font = nil,
    native_font_path = nil,
    render_timer = nil,
    hide_timer = nil,
    stopped = false,
  }

  local function ensure_canvas()
    if self.canvas then return true end
    if not service_ui or not service_ui.acquire then return false end
    local id, err = service_ui.acquire(X, Y, W, H)
    if not id then
      print("[xiaozhi] subtitle float acquire failed", tostring(err or ""))
      return false
    end
    self.canvas = id
    if service_ui.clear then pcall(service_ui.clear, self.canvas) end
    return true
  end

  local function release_canvas()
    if self.render_timer then pcall(function() self.render_timer:unregister() end); self.render_timer = nil end
    if self.hide_timer then pcall(function() self.hide_timer:unregister() end); self.hide_timer = nil end
    if self.canvas then
      if service_ui.hide then pcall(service_ui.hide, self.canvas) end
      if service_ui.release then pcall(service_ui.release, self.canvas) end
      self.canvas = nil
    end
  end

  local function rect(x, y, w, h, color, radius, opa)
    if not self.canvas or not lv_canvas_draw_rect then return end
    pcall(lv_canvas_draw_rect, self.canvas, x, y, w, h, {
      bg_color = color,
      bg_opa = opa == nil and 190 or opa,
      radius = radius or 0,
      border_width = 0,
    })
  end

  local function draw_text(x, y, w, value, align)
    if not lv_canvas_draw_text then return end
    pcall(lv_canvas_draw_text, self.canvas, x, y, w, tostring(value or ""), {
      color = TEXT,
      opa = 255,
      align = align or LV_TEXT_ALIGN_CENTER,
      font_size = 18,
      font_handle = self.native_font,
    })
  end

  local function render_now()
    if self.stopped or self.message == "" or not ensure_canvas() then return end
    if service_ui.clear then pcall(service_ui.clear, self.canvas) end
    if lv_canvas_frame_begin then pcall(lv_canvas_frame_begin, self.canvas) end
    rect(0, 0, W, H, BG, 0, 185)
    local line = clip_utf8(self.message, 28)
    draw_text(16, 18, 288, line, LV_TEXT_ALIGN_CENTER)
    if lv_canvas_frame_end then pcall(lv_canvas_frame_end, self.canvas) end
    if service_ui.show then pcall(service_ui.show, self.canvas) end
  end

  local function render()
    if not tmr or not tmr.create then render_now(); return end
    if self.render_timer then return end
    local timer = tmr.create()
    self.render_timer = timer
    timer:alarm(60, tmr.ALARM_SINGLE, function(instance)
      pcall(function() instance:unregister() end)
      if self.render_timer == timer then self.render_timer = nil end
      render_now()
    end)
  end

  local function show_line(role, content)
    role = text_or(role, "assistant")
    content = text_or(content, "")
    if content == "" then return end
    if role == "system" and content ~= "验证码" and not content:find("验证码", 1, true) then return end
    self.role = role
    self.message = content
    if self.hide_timer then pcall(function() self.hide_timer:unregister() end); self.hide_timer = nil end
    render()
    if tmr and tmr.create then
      local timer = tmr.create()
      self.hide_timer = timer
      timer:alarm(6000, tmr.ALARM_SINGLE, function(instance)
        pcall(function() instance:unregister() end)
        if self.hide_timer == timer then self.hide_timer = nil end
        if self.state == "idle" then release_canvas() end
      end)
    end
  end

  function self:set_view_mode() end
  function self:set_metrics() end
  function self:update_status_bar() end
  function self:set_emotion() end
  function self:set_status() end

  function self:show_notification(value)
    local text = tostring(value or "")
    if text:find("验证码", 1, true) then show_line("system", text) end
  end

  function self:set_chat_message(role, content)
    show_line(role, content)
  end

  function self:clear_chat_messages()
    self.message = ""
    release_canvas()
  end

  function self:on_state(state)
    self.state = tostring(state or "idle")
    if self.state == "idle" and self.message == "" then release_canvas() end
  end

  function self:alert(status, message)
    self.state = "fatal_error"
    show_line("system", tostring(message or status or "发生错误"))
  end

  function self:setup()
    self.stopped = false
    self.native_font_path = (cfg.UI_APP_DIR or cfg.APP_DIR or "/sd/apps/xiaozhi")
      .. "/assets/fonts/xiaozhi_common3500_16.bin"
    if path_exists(self.native_font_path) and type(rawget(_G, "lv_font_load")) == "function" then
      local ok, handle = pcall(lv_font_load, self.native_font_path)
      if ok and type(handle) == "number" and handle > 0 then self.native_font = handle end
    end
  end

  function self:diagnostics()
    return {
      mode = "subtitle",
      native_font = self.native_font,
      native_font_path = self.native_font_path,
    }
  end

  function self:stop()
    self.stopped = true
    release_canvas()
    if self.native_font and type(rawget(_G, "lv_font_free")) == "function" then
      pcall(lv_font_free, self.native_font)
    end
    self.native_font = nil
  end

  return self
end

return M
