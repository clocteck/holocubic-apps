local M = {}

local W, H = 200, 100
local X, Y = 0, 140
local PANEL = 0x1F2937
local PANEL_ALT = 0x312E81
local BUBBLE_GREEN = 0x95EC69
local WHITE = 0xF9FAFB
local ACCENT = 0xA78BFA
local ERROR = 0x7F1D1D
local BUBBLE_PAGE_MS = 2200
local BUBBLE_LINE_WIDTH = 112
local BUBBLE_LINES = 4

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

local function split_bubble_pages(value)
  value = tostring(value or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  if value == "" then return { "" } end
  local pages, page, line_width, line_count = {}, {}, 0, 1
  local function finish_page()
    pages[#pages + 1] = table.concat(page)
    page, line_width, line_count = {}, 0, 1
  end
  local pos = 1
  while pos <= #value do
    local byte = value:byte(pos)
    local width = byte < 0x80 and 1 or (byte < 0xE0 and 2 or (byte < 0xF0 and 3 or 4))
    local ch = value:sub(pos, pos + width - 1)
    pos = pos + width
    if ch == "\n" then
      if line_count >= BUBBLE_LINES then finish_page()
      else page[#page + 1] = ch; line_count = line_count + 1; line_width = 0 end
    else
      local advance = byte < 0x80 and 8 or 16
      if line_width + advance > BUBBLE_LINE_WIDTH then
        if line_count >= BUBBLE_LINES then finish_page()
        else page[#page + 1] = "\n"; line_count = line_count + 1; line_width = 0 end
      end
      page[#page + 1] = ch
      line_width = line_width + advance
    end
  end
  if #page > 0 or #pages == 0 then finish_page() end
  return pages
end

function M.new(cfg)
  local self = {
    canvas = nil,
    state = "idle",
    status = "小智待命中",
    emotion = "neutral",
    user_text = "",
    assistant_text = "",
    notice = "",
    stopped = false,
    character_rgb565 = nil,
    cjk_font_path = nil,
    cjk_font_size = 0,
    cjk_font_fd = nil,
    native_font = nil,
    native_font_path = nil,
    glyph_cache = {},
    glyph_cache_order = {},
    bubble_cache_text = nil,
    bubble_cache_data = nil,
    render_timer = nil,
    bubble_timer = nil,
    bubble_page_timer = nil,
    bubble_pages = { "" },
    bubble_page_index = 1,
    bubble_visible = true,
  }

  local function read_binary(path)
    if file and file.getcontents then
      local ok, raw = pcall(function() return file.getcontents(path) end)
      if ok and type(raw) == "string" then return raw end
    end
    return nil
  end

  local function rect(x, y, w, h, color, radius, opa)
    if not self.canvas or not lv_canvas_draw_rect then return end
    pcall(lv_canvas_draw_rect, self.canvas, x, y, w, h, {
      bg_color = color, bg_opa = opa or 255, radius = radius or 0,
      border_width = 0,
    })
  end

  local function line(x1, y1, x2, y2, color, width)
    if lv_canvas_draw_line then
      pcall(lv_canvas_draw_line, self.canvas, x1, y1, x2, y2, color, 255, width or 2)
    end
  end

  local function arc(cx, cy, r, a1, a2, color, width)
    if lv_canvas_draw_arc then
      pcall(lv_canvas_draw_arc, self.canvas, cx, cy, r, a1, a2, color, 255, width or 2)
    end
  end

  local function text(x, y, w, value, color, size, align)
    if not lv_canvas_draw_text then return end
    pcall(lv_canvas_draw_text, self.canvas, x, y, w, tostring(value or ""), {
      color = color or WHITE,
      opa = 255,
      align = align or LV_TEXT_ALIGN_LEFT,
      font_size = size or 16,
    })
  end

  local function draw_character()
    if self.character_rgb565 and lv_canvas_blit_rgb565 then
      local ok, result = pcall(lv_canvas_blit_rgb565, self.canvas, 0, 1, 58, 98,
        self.character_rgb565, { byte_order = "little" })
      if ok and result ~= false then return end
    end
    -- Compact Canvas-only anime bust in the left 60 px.
    arc(29, 33, 24, 180, 360, ACCENT, 8)
    rect(10, 29, 40, 43, 0xFDE7D7, 16)
    line(14, 35, 22, 25, ACCENT, 5)
    line(22, 25, 29, 37, ACCENT, 5)
    line(29, 37, 38, 24, ACCENT, 5)
    line(38, 24, 48, 35, ACCENT, 5)
    arc(21, 49, 4, 190, 350, 0x312E81, 2)
    arc(39, 49, 4, 190, 350, 0x312E81, 2)
    if self.state == "speaking" or self.emotion == "happy" then
      arc(30, 60, 7, 10, 170, 0xBE123C, 2)
    elseif self.state == "listening" then
      arc(30, 60, 3, 0, 360, 0xBE123C, 2)
    else
      line(26, 61, 34, 61, 0xBE123C, 2)
    end
    rect(12, 70, 36, 28, ACCENT, 12)
  end

  local function utf8_chars(value, limit)
    local out, pos = {}, 1
    value = tostring(value or ""):gsub("[%c]+", " ")
    while pos <= #value and #out < (limit or 32) do
      local b1 = value:byte(pos)
      local width = b1 < 0x80 and 1 or (b1 < 0xE0 and 2 or (b1 < 0xF0 and 3 or 4))
      local cp
      if width == 1 then cp = b1
      elseif width == 2 then cp = (b1 - 0xC0) * 64 + (value:byte(pos + 1) or 0) - 0x80
      elseif width == 3 then cp = (b1 - 0xE0) * 4096 + ((value:byte(pos + 1) or 0) - 0x80) * 64 + (value:byte(pos + 2) or 0) - 0x80
      else cp = (b1 - 0xF0) * 262144 + ((value:byte(pos + 1) or 0) - 0x80) * 4096 + ((value:byte(pos + 2) or 0) - 0x80) * 64 + (value:byte(pos + 3) or 0) - 0x80 end
      out[#out + 1] = cp
      pos = pos + width
    end
    return out
  end

  local function glyph(cp)
    local cached = self.glyph_cache[cp]
    if cached ~= nil then return cached or nil end
    if not self.cjk_font_fd and file and file.open and self.cjk_font_path then
      self.cjk_font_fd = file.open(self.cjk_font_path, "r")
    end
    local fd = self.cjk_font_fd
    if not fd then return nil end
    local lo, hi = 0, math.floor(self.cjk_font_size / 36) - 1
    local found = nil
    while lo <= hi do
      local mid = math.floor((lo + hi) / 2)
      local p = mid * 36
      if fd:seek("set", p) == nil then break end
      local data = fd:read(36)
      if type(data) ~= "string" or #data < 36 then break end
      local a,b,c,d = data:byte(1, 4)
      local value = a + b * 256 + c * 65536 + d * 16777216
      if value == cp then found = data:sub(5, 36); break
      elseif value < cp then lo = mid + 1 else hi = mid - 1 end
    end
    self.glyph_cache[cp] = found or false
    self.glyph_cache_order[#self.glyph_cache_order + 1] = cp
    if #self.glyph_cache_order > 64 then
      local old = table.remove(self.glyph_cache_order, 1)
      self.glyph_cache[old] = nil
    end
    return found
  end

  local function bubble_rgb565(value)
    value = tostring(value or "")
    if self.bubble_cache_text == value and self.bubble_cache_data then
      return self.bubble_cache_data
    end
    local cps, masks = utf8_chars(value, 32), {}
    for i, cp in ipairs(cps) do masks[i] = glyph(cp) end
    local foreground = {}
    local cursor_x, line_no = 0, 0
    for i, cp in ipairs(cps) do
      local advance = cp < 128 and 8 or 16
      if cursor_x + advance > 112 then cursor_x, line_no = 0, line_no + 1 end
      if line_no >= 4 then break end
      local mask = masks[i]
      if mask then
        local origin_x = 6 + cursor_x - (cp < 128 and 4 or 0)
        local origin_y = 3 + line_no * 18
        for gy = 0, 15 do
          for gx = 0, 15 do
            local byte = mask:byte(gy * 2 + math.floor(gx / 8) + 1) or 0
            if (byte % (2 ^ (8 - (gx % 8)))) >= (2 ^ (7 - (gx % 8))) then
              local px, py = origin_x + gx, origin_y + gy
              if px >= 0 and px < 126 and py >= 0 and py < 76 then foreground[py * 126 + px] = true end
            end
          end
        end
      end
      cursor_x = cursor_x + advance
    end
    local chunks = {}
    local transparent_px = string.char(0, 0)
    local green_px = string.char(0x6D, 0x97)
    local white_px = string.char(0x82, 0x10)
    for y = 0, 75 do
      local row, run_pixel, run_length = {}, nil, 0
      for x = 0, 125 do
        local outside = (x < 8 and y < 8 and (x-8)^2+(y-8)^2 > 64)
          or (x > 117 and y < 8 and (x-117)^2+(y-8)^2 > 64)
          or (x < 8 and y > 67 and (x-8)^2+(y-67)^2 > 64)
          or (x > 117 and y > 67 and (x-117)^2+(y-67)^2 > 64)
        local pixel = outside and transparent_px or green_px
        if foreground[y * 126 + x] then pixel = white_px end
        if pixel == run_pixel then
          run_length = run_length + 1
        else
          if run_length > 0 then row[#row + 1] = string.rep(run_pixel, run_length) end
          run_pixel, run_length = pixel, 1
        end
      end
      if run_length > 0 then row[#row + 1] = string.rep(run_pixel, run_length) end
      chunks[#chunks + 1] = table.concat(row)
    end
    local data = table.concat(chunks)
    self.bubble_cache_text = value
    self.bubble_cache_data = data
    return data
  end

  local function glyph_rgb565(mask, ascii)
    if not mask then return nil, 0 end
    local width, start_x = ascii and 8 or 16, ascii and 4 or 0
    local green_px, white_px = string.char(0x6D, 0x97), string.char(0x82, 0x10)
    local rows = {}
    for gy = 0, 15 do
      local row = {}
      for x = 0, width - 1 do
        local gx = start_x + x
        local byte = mask:byte(gy * 2 + math.floor(gx / 8) + 1) or 0
        local set = (byte % (2 ^ (8 - (gx % 8)))) >= (2 ^ (7 - (gx % 8)))
        row[#row + 1] = set and white_px or green_px
      end
      rows[#rows + 1] = table.concat(row)
    end
    return table.concat(rows), width
  end

  local function draw_reply(value)
    if not lv_canvas_blit_rgb565 then return end
    local x, y = 78, 15
    for _, cp in ipairs(utf8_chars(value, 32)) do
      local ascii = cp < 128
      local data, width = glyph_rgb565(glyph(cp), ascii)
      if x + width > 194 then x, y = 78, y + 18 end
      if y + 16 > 86 then break end
      if data then
        pcall(lv_canvas_blit_rgb565, self.canvas, x, y, width, 16, data,
          { byte_order = "little" })
      end
      x = x + width
    end
  end

  local function render_now()
    if not self.canvas or self.stopped then return end
    if lv_canvas_frame_begin then pcall(lv_canvas_frame_begin, self.canvas) end
    draw_character()
    local point_color = self.state == "speaking" and 0x2563EB
      or (self.state == "listening" and 0x22C55E or 0xDC2626)
    rect(61, 13, 8, 8, point_color, 4)
    local reply = self.assistant_text ~= "" and self.assistant_text
      or (self.notice ~= "" and self.notice or self.status)
    if self.assistant_text ~= "" and #self.bubble_pages > 0 then
      reply = self.bubble_pages[self.bubble_page_index] or self.bubble_pages[1] or reply
    end
    if lv_canvas_blit_rgb565 then
      local rendered_text = self.native_font and "" or reply
      local data = self.bubble_visible and bubble_rgb565(rendered_text) or string.rep("\0", 126 * 76 * 2)
      pcall(lv_canvas_blit_rgb565, self.canvas, 72, 12, 126, 76, data, { byte_order = "little" })
      if self.bubble_visible then
        if self.native_font and lv_canvas_draw_text then
          pcall(lv_canvas_draw_text, self.canvas, 78, 15, 114, reply, {
            color = 0x111111, opa = 255, align = LV_TEXT_ALIGN_LEFT,
            font_size = 16, font_handle = self.native_font,
          })
        else
          draw_reply(reply)
        end
      end
    end
    if lv_canvas_frame_end then pcall(lv_canvas_frame_end, self.canvas) end
    local visible = false
    if service_ui.is_visible then local ok,v=pcall(service_ui.is_visible,self.canvas); visible=ok and v==true end
    if not visible then pcall(service_ui.show, self.canvas) end
  end

  local function render()
    if not self.canvas or self.stopped then return end
    local visible = false
    if service_ui.is_visible then local ok,v=pcall(service_ui.is_visible,self.canvas); visible=ok and v==true end
    if not visible or not tmr or not tmr.create then render_now(); return end
    if self.render_timer then return end
    local timer = tmr.create(); self.render_timer = timer
    timer:alarm(120, tmr.ALARM_SINGLE, function(instance)
      pcall(function() instance:unregister() end)
      if self.render_timer == timer then self.render_timer = nil end
      render_now()
    end)
  end

  local function ensure_canvas()
    if self.canvas then return true end
    if not service_ui or not service_ui.acquire then return false end
    if not self.character_rgb565 then
      self.character_rgb565 = read_binary((cfg.APP_DIR or "/sd/apps/xiaozhi-service")
        .. "/assets/character/xiaozhi_chibi.rgb565")
    end
    local id, err = service_ui.acquire(X, Y, W, H)
    if not id then
      print("[xiaozhi] service_ui.acquire failed", tostring(err or ""))
      return false
    end
    self.canvas = id
    pcall(service_ui.clear, self.canvas)
    return true
  end

  local function release_canvas()
    if self.render_timer then
      pcall(function() self.render_timer:unregister() end)
      self.render_timer = nil
    end
    if self.canvas then
      pcall(service_ui.hide, self.canvas)
      pcall(service_ui.release, self.canvas)
      self.canvas = nil
    end
    if self.bubble_timer then
      pcall(function() self.bubble_timer:unregister() end)
      self.bubble_timer = nil
    end
    if self.bubble_page_timer then
      pcall(function() self.bubble_page_timer:unregister() end)
      self.bubble_page_timer = nil
    end
    self.bubble_visible = false
    if self.cjk_font_fd then pcall(function() self.cjk_font_fd:close() end) end
    self.cjk_font_fd = nil
    self.glyph_cache = {}
    self.glyph_cache_order = {}
    self.bubble_cache_text = nil
    self.bubble_cache_data = nil
    self.character_rgb565 = nil
    if collectgarbage then pcall(collectgarbage, "collect") end
  end

  local function show()
    if ensure_canvas() then
      render()
    end
  end

  local function show_bubble_temporarily()
    self.bubble_visible = true
    if self.bubble_timer then pcall(function() self.bubble_timer:unregister() end); self.bubble_timer = nil end
    if self.bubble_page_timer then
      pcall(function() self.bubble_page_timer:unregister() end)
      self.bubble_page_timer = nil
    end
    if tmr and tmr.create then
      local timer = tmr.create(); self.bubble_timer = timer
      local page_count = math.max(1, #self.bubble_pages)
      local visible_ms = math.max(5000, page_count * BUBBLE_PAGE_MS + 600)
      timer:alarm(visible_ms, tmr.ALARM_SINGLE, function(instance)
        pcall(function() instance:unregister() end)
        if self.bubble_timer == timer then self.bubble_timer = nil end
        self.bubble_visible = false
        render()
      end)
      if page_count > 1 then
        local page_timer = tmr.create(); self.bubble_page_timer = page_timer
        page_timer:alarm(BUBBLE_PAGE_MS, tmr.ALARM_AUTO, function(instance)
          if self.bubble_page_index >= #self.bubble_pages then
            pcall(function() instance:unregister() end)
            if self.bubble_page_timer == page_timer then self.bubble_page_timer = nil end
            return
          end
          self.bubble_page_index = self.bubble_page_index + 1
          render_now()
        end)
      end
    end
  end

  function self:set_view_mode() end
  function self:set_metrics() end
  function self:update_status_bar() end

  function self:set_status(value)
    self.status = tostring(value or "")
    show_bubble_temporarily()
    show()
  end

  function self:show_notification(value)
    self.notice = tostring(value or "")
    show_bubble_temporarily()
    show()
  end

  function self:set_emotion(value)
    self.emotion = tostring(value or "neutral")
    if self.canvas and service_ui.is_visible(self.canvas) then render() end
  end

  function self:set_chat_message(role, content)
    content = tostring(content or "")
    if role == "user" then self.user_text = content
    elseif role == "assistant" then
      self.assistant_text = content
      self.bubble_pages = split_bubble_pages(content)
      self.bubble_page_index = 1
    else self.notice = content end
    show_bubble_temporarily()
    -- Chat text is latency-sensitive: commit it before the first queued TTS
    -- audio frame instead of waiting for the normal 120 ms render coalescer.
    if ensure_canvas() then render_now() end
  end

  function self:clear_chat_messages()
    self.user_text, self.assistant_text = "", ""
    self.bubble_pages, self.bubble_page_index = { "" }, 1
  end

  function self:on_state(state)
    self.state = tostring(state or "idle")
    local labels = {
      starting = "正在启动", activating = "正在连接服务", connecting = "正在连接",
      listening = "我在听", speaking = "小智正在回答", fatal_error = "启动失败",
    }
    self.status = labels[self.state] or self.status
    if self.state == "idle" then
      release_canvas()
    else
      show()
    end
  end

  function self:alert(status, message)
    self.state = "fatal_error"
    self.status = tostring(status or "发生错误")
    self.notice = tostring(message or "")
    show_bubble_temporarily()
    if ensure_canvas() then
      render()
      pcall(service_ui.show, self.canvas)
    end
  end

  function self:setup()
    self.stopped = false
    self.cjk_font_path = (cfg.APP_DIR or "/sd/apps/xiaozhi-service") .. "/assets/fonts/cjk16_1bpp.bin"
    self.native_font_path = (cfg.APP_DIR or "/sd/apps/xiaozhi-service")
      .. "/assets/fonts/xiaozhi_common3500_16.bin"
    local stat = file and file.stat and file.stat(self.cjk_font_path) or nil
    self.cjk_font_size = stat and tonumber(stat.size) or 0
    -- A successful acquire grants the service its restricted Canvas/font API.
    ensure_canvas()
    if not self.native_font and type(rawget(_G, "lv_font_load")) == "function" then
      local ok, handle = pcall(lv_font_load, self.native_font_path)
      if ok and type(handle) == "number" and handle > 0 then self.native_font = handle end
    end
  end

  function self:diagnostics()
    local sample = glyph(0x4E2D)
    local bits = 0
    if sample then
      for i = 1, #sample do
        local byte = sample:byte(i)
        for _ = 1, 8 do bits = bits + (byte % 2); byte = math.floor(byte / 2) end
      end
    end
    return {
      font_size = self.cjk_font_size,
      sample_bytes = sample and #sample or 0,
      sample_bits = bits,
      lv_font_load = type(rawget(_G, "lv_font_load")),
      lv_font_free = type(rawget(_G, "lv_font_free")),
      native_font = self.native_font,
    }
  end

  function self:stop()
    self.stopped = true
    if self.bubble_timer then pcall(function() self.bubble_timer:unregister() end); self.bubble_timer = nil end
    release_canvas()
    if self.native_font and type(rawget(_G, "lv_font_free")) == "function" then
      pcall(lv_font_free, self.native_font)
    end
    self.native_font = nil
    self.native_font_path = nil
    self.cjk_font_path = nil
    self.cjk_font_size = 0
  end

  return self
end

return M
