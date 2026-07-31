local M = {}

local W, H = 320, 92
local X, Y = 0, 148
local TEXT = 0xFFFFFF
local USER_BG = 0x00FF00
local ASSISTANT_BG = 0x222222
local SYSTEM_BG = 0x000000
local USER_TEXT = 0x111111
local LV_TEXT_ALIGN_LEFT = rawget(_G, "LV_TEXT_ALIGN_LEFT") or 0
local PAD_X = 12
local PAD_Y = 10
local BUBBLE_PAD_X = 9
local BUBBLE_PAD_Y = 7
local MAX_BUBBLE_W = 236
local MIN_BUBBLE_W = 52
local MAX_BUBBLE_H = 72

local function text_or(value, fallback)
  if value == nil then return fallback or "" end
  local text = tostring(value)
  if text == "" then return fallback or "" end
  return text
end

local function text_units(text)
  local units = {}
  local i = 1
  while i <= #text do
    local b = string.byte(text, i)
    local size = 1
    if b >= 0xF0 then
      size = 4
    elseif b >= 0xE0 then
      size = 3
    elseif b >= 0xC0 then
      size = 2
    end
    local ch = string.sub(text, i, i + size - 1)
    local width = 16
    if b < 0x80 then
      if ch == "\t" then
        width = 16
      elseif string.find("ilI1.,:;!'|`", ch, 1, true) then
        width = 5
      elseif string.find("MWmw@#%&", ch, 1, true) then
        width = 13
      else
        width = 9
      end
    end
    units[#units + 1] = { text = ch, width = width }
    i = i + size
  end
  return units
end

local function bubble_layout(value, max_w, min_w)
  local text = text_or(value, ""):gsub("[%c]+", " ")
  local natural_w = 0
  for _, unit in ipairs(text_units(text)) do
    natural_w = natural_w + unit.width
  end
  local width = math.max(min_w or MIN_BUBBLE_W, math.min(max_w, natural_w + BUBBLE_PAD_X * 2))
  local content_w = math.max(8, width - BUBBLE_PAD_X * 2)
  local out, line_w, lines = {}, 0, 1
  for _, unit in ipairs(text_units(text)) do
    if line_w > 0 and line_w + unit.width > content_w then
      if lines >= 3 then
        out[#out + 1] = "..."
        break
      end
      out[#out + 1] = "\n"
      lines = lines + 1
      line_w = 0
    end
    out[#out + 1] = unit.text
    line_w = line_w + unit.width
  end
  return width, math.min(MAX_BUBBLE_H, BUBBLE_PAD_Y * 2 + lines * 20), table.concat(out)
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
    role = "system",
    message = "",
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
      print("[xiaozhi] wechat float acquire failed", tostring(err or ""))
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
      bg_opa = opa == nil and 255 or opa,
      radius = radius or 0,
      border_width = 0,
    })
  end

  local function draw_text(x, y, w, value, color)
    if not lv_canvas_draw_text then return end
    pcall(lv_canvas_draw_text, self.canvas, x, y, w, tostring(value or ""), {
      color = color or TEXT,
      opa = 255,
      align = LV_TEXT_ALIGN_LEFT,
      font_size = 16,
      font_handle = self.native_font,
    })
  end

  local function render_now()
    if self.stopped or self.message == "" or not ensure_canvas() then return end
    if service_ui.clear then pcall(service_ui.clear, self.canvas) end
    if lv_canvas_frame_begin then pcall(lv_canvas_frame_begin, self.canvas) end
    local role = tostring(self.role or "system")
    local max_w = role == "system" and 236 or 230
    local min_w = role == "system" and 52 or 48
    local bw, bh, wrapped = bubble_layout(self.message, max_w, min_w)
    local bx = PAD_X
    local bg = ASSISTANT_BG
    local fg = TEXT
    if role == "user" then
      bx = W - PAD_X - bw
      bg = USER_BG
      fg = USER_TEXT
    elseif role == "system" then
      bx = math.floor((W - bw) / 2)
      bg = SYSTEM_BG
    end
    local by = H - PAD_Y - bh
    rect(bx, by, bw, bh, bg, 8, role == "system" and 220 or 255)
    draw_text(bx + BUBBLE_PAD_X, by + BUBBLE_PAD_Y, bw - BUBBLE_PAD_X * 2, wrapped, fg)
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

  local function show_message(role, content)
    content = text_or(content, "")
    if content == "" then return end
    self.role = text_or(role, "system")
    self.message = content
    if self.hide_timer then pcall(function() self.hide_timer:unregister() end); self.hide_timer = nil end
    render()
    if tmr and tmr.create then
      local timer = tmr.create()
      self.hide_timer = timer
      timer:alarm(5000, tmr.ALARM_SINGLE, function(instance)
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

  function self:set_status(value)
    if self.state ~= "idle" then show_message("system", value) end
  end

  function self:show_notification(value)
    if tostring(value or "") == "你好小智" then return end
    show_message("system", value)
  end

  function self:set_chat_message(role, content)
    show_message(role, content)
  end

  function self:clear_chat_messages()
    self.message = ""
    release_canvas()
  end

  function self:on_state(state)
    self.state = tostring(state or "idle")
    if self.state == "idle" then
      if self.message == "" then release_canvas() end
    elseif self.message ~= "" then
      render()
    end
  end

  function self:alert(status, message)
    self.state = "fatal_error"
    show_message("system", tostring(message or status or "发生错误"))
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
      mode = "wechat",
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
