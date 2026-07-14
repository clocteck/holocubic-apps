local Renderer = {}
Renderer.__index = Renderer

local MAIN = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
local ALIGN_LEFT = rawget(_G, "LV_TEXT_ALIGN_LEFT") or 0
local ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1
local ALIGN_RIGHT = rawget(_G, "LV_TEXT_ALIGN_RIGHT") or 2
local FLAG_SCROLLABLE = rawget(_G, "LV_OBJ_FLAG_SCROLLABLE")
local FLAG_HIDDEN = rawget(_G, "LV_OBJ_FLAG_HIDDEN")
local GRAD_VER = rawget(_G, "LV_GRAD_DIR_VER") or 1
local CANVAS_FMT = rawget(_G, "LV_IMG_CF_TRUE_COLOR") or rawget(_G, "CANVAS_FMT_TRUE_COLOR")
local CHROMA_KEY = rawget(_G, "LV_COLOR_CHROMA_KEY") or 0x00FF00
local BUILTIN_FONT_SIZES = { 8, 10, 12, 14, 16, 20, 24, 28 }

local function call(fn, ...)
  if not fn then return false end
  return pcall(fn, ...)
end

local function clamp(value, low, high)
  value = tonumber(value) or low
  if value < low then return low end
  if value > high then return high end
  return value
end

local function style_number(style, key, fallback)
  local value = style and style[key]
  if type(value) == "number" then return value end
  local parsed = tonumber(tostring(value or ""):match("([%-]?[%d%.]+)"))
  if parsed == nil then return fallback end
  return parsed
end

local function mix_color(first, second, ratio)
  ratio = clamp(ratio or 0, 0, 1)
  local inverse = 1 - ratio
  local r = math.floor((((first >> 16) & 0xFF) * inverse + ((second >> 16) & 0xFF) * ratio) + 0.5)
  local g = math.floor((((first >> 8) & 0xFF) * inverse + ((second >> 8) & 0xFF) * ratio) + 0.5)
  local b = math.floor(((first & 0xFF) * inverse + (second & 0xFF) * ratio) + 0.5)
  return (r << 16) | (g << 8) | b
end

local function builtin_font(size)
  size = tonumber(size) or 12
  local nearest = BUILTIN_FONT_SIZES[1]
  for _, candidate in ipairs(BUILTIN_FONT_SIZES) do
    if math.abs(candidate - size) < math.abs(nearest - size) then nearest = candidate end
  end
  return rawget(_G, "LV_FONT_MONTSERRAT_" .. tostring(nearest)) or nearest
end

local function set_hidden(object, hidden)
  if not object or not FLAG_HIDDEN then return end
  if hidden then
    call(lv_obj_add_flag, object, FLAG_HIDDEN)
  else
    call(lv_obj_clear_flag, object, FLAG_HIDDEN)
  end
end

local function make_panel(parent, x, y, w, h, color, opacity)
  local object = lv_obj_create(parent)
  call(lv_obj_set_pos, object, x or 0, y or 0)
  call(lv_obj_set_size, object, math.max(1, w or 1), math.max(1, h or 1))
  call(lv_obj_set_style_bg_color, object, color or 0, MAIN)
  call(lv_obj_set_style_bg_opa, object, opacity == nil and 255 or opacity, MAIN)
  call(lv_obj_set_style_border_width, object, 0, MAIN)
  call(lv_obj_set_style_radius, object, 0, MAIN)
  call(lv_obj_set_style_pad_all, object, 0, MAIN)
  if FLAG_SCROLLABLE then call(lv_obj_clear_flag, object, FLAG_SCROLLABLE) end
  return object
end

local function apply_gradient(object, colors)
  if not object or not colors then return end
  call(lv_obj_set_style_bg_color, object, colors[1] or 0, MAIN)
  if colors[2] and colors[2] ~= colors[1] then
    call(lv_obj_set_style_bg_grad_color, object, colors[2], MAIN)
    call(lv_obj_set_style_bg_grad_dir, object, GRAD_VER, MAIN)
    call(lv_obj_set_style_bg_main_stop, object, 0, MAIN)
    call(lv_obj_set_style_bg_grad_stop, object, 255, MAIN)
  end
end

local function style_align(value)
  value = tostring(value or "left"):lower()
  if value == "right" then return ALIGN_RIGHT end
  if value == "center" then return ALIGN_CENTER end
  return ALIGN_LEFT
end

local function is_bold(value)
  local text = tostring(value or ""):lower()
  return text:find("bold", 1, true) ~= nil or (tonumber(text:match("(%d+)")) or 0) >= 600
end

local function parameter_text_style(params, align)
  params = params or {}
  return {
    color = params.font_color or 0xFFFFFF,
    align = align or "left",
    font = {
      size = tonumber(params.font_size) or 10,
      family = params.font_family or "",
      bold = is_bold(params.font_weight),
      italic = tostring(params.font_style or ""):lower():find("italic", 1, true) ~= nil,
    },
  }
end

local function vector_text_height(text_style, available)
  local size = tonumber(text_style and text_style.font and text_style.font.size) or 12
  local shadow = text_style and text_style.shadow or nil
  local shadow_pad = shadow and math.max(0, (tonumber(shadow.y) or 0) + (tonumber(shadow.blur) or 0)) or 0
  -- CSS font-size describes the em square. Noto Sans SC needs roughly 1.45 em
  -- for its ascent/descent, plus a little room for decorations and shadows.
  local height = math.ceil(size * 1.52) + math.max(2, shadow_pad)
  return math.max(1, math.min(tonumber(available) or height, height))
end

local function make_label(parent, geometry, text_style, width, renderer)
  local object = lv_label_create(parent)
  local x = geometry and geometry.x or 0
  local y = geometry and geometry.y or 0
  local w = width or (geometry and geometry.w) or 0
  if w <= 0 then w = 320 - x end
  call(lv_obj_set_pos, object, x, y)
  call(lv_obj_set_width, object, math.max(1, w))
  call(lv_label_set_text, object, tostring(text_style and text_style.text or ""))
  call(lv_obj_set_style_text_color, object, text_style and text_style.color or 0xFFFFFF, MAIN)
  call(lv_obj_set_style_text_opa, object, 255, MAIN)
  local requested_size = text_style and text_style.font and text_style.font.size or 12
  local selected_font = renderer and renderer:font_for_size(requested_size) or builtin_font(requested_size)
  call(lv_obj_set_style_text_font, object, selected_font, MAIN)
  call(lv_obj_set_style_text_align, object, style_align(text_style and text_style.align), MAIN)
  return object
end

local function canvas_create(parent, width, height, format)
  if not lv_canvas_create then return nil end
  local selected_format = format or CANVAS_FMT
  if selected_format then
    local ok, object = pcall(lv_canvas_create, parent, width, height, selected_format)
    if ok then return object end
  end
  local ok, object = pcall(lv_canvas_create, parent, width, height)
  return ok and object or nil
end

local function canvas_begin(canvas)
  if lv_canvas_frame_begin then return call(lv_canvas_frame_begin, canvas) end
  if lv_canvas_begin then return call(lv_canvas_begin, canvas) end
  return false
end

local function canvas_end(canvas, explicit)
  if not explicit then return end
  if lv_canvas_frame_end then call(lv_canvas_frame_end, canvas)
  elseif lv_canvas_end then call(lv_canvas_end, canvas) end
end

local function fill(canvas, color)
  if lv_canvas_fill_bg then call(lv_canvas_fill_bg, canvas, color, 255)
  elseif lv_canvas_fill then call(lv_canvas_fill, canvas, color, 255) end
end

local function draw_rect(canvas, x, y, w, h, color, opacity)
  if w <= 0 or h <= 0 then return end
  local ok = call(lv_canvas_draw_rect, canvas, math.floor(x), math.floor(y), math.floor(w), math.floor(h), color, opacity or 255)
  if not ok then
    call(lv_canvas_draw_rect, canvas, math.floor(x), math.floor(y), math.floor(w), math.floor(h), {
      bg_color = color, bg_opa = opacity or 255, border_width = 0, radius = 0,
    })
  end
end

local function draw_line(canvas, x1, y1, x2, y2, color, opacity, width)
  call(lv_canvas_draw_line, canvas, math.floor(x1 + 0.5), math.floor(y1 + 0.5),
    math.floor(x2 + 0.5), math.floor(y2 + 0.5), color, opacity or 255, width or 1)
end

local function draw_text(canvas, x, y, width, text, color, size, align, opacity, font_handle)
  local px, py, draw_width = math.floor(x), math.floor(y), math.max(1, math.floor(width))
  local descriptor = { color = color or 0xFFFFFF, opa = opacity or 255,
    align = align or ALIGN_LEFT, font_size = size or 10, font_handle = font_handle }
  local ok = call(lv_canvas_draw_text, canvas, px, py, draw_width, tostring(text or ""), descriptor)
  if not ok then
    call(lv_canvas_draw_text, canvas, px, py, draw_width, tostring(text or ""),
      color or 0xFFFFFF, opacity or 255, align or ALIGN_LEFT, size or 10)
  end
end

local function graph_spacing(params)
  params = params or {}
  if params.graph_type == "HG" then
    return math.max(1, tonumber(params.thick) or 1) + math.max(0, tonumber(params.step) or 1)
  end
  return math.max(0, tonumber(params.step) or 1) + 1
end

local function graph_range(item, drawable_width)
  local p = item.params or {}
  if drawable_width == nil then
    drawable_width = tonumber(item.geometry and item.geometry.w) or 1
    if p.show_frame then drawable_width = math.max(1, drawable_width - 2) end
  end
  local minimum = tonumber(p.min_value) or 0
  local maximum = tonumber(p.max_value) or 100
  if p.autoscale and #item.history > 0 then
    -- AIDA64 only autoscales against samples that fit in the current canvas.
    local visible = math.min(#item.history,
      math.floor((math.max(1, tonumber(drawable_width) or 1) - 1) / graph_spacing(p)) + 1)
    local newest = #item.history
    minimum, maximum = item.history[newest], item.history[newest]
    for offset = 1, visible - 1 do
      local value = item.history[newest - offset]
      minimum = math.min(minimum, value)
      maximum = math.max(maximum, value)
    end
    if p.base_100 then
      minimum = math.floor(minimum * 0.009 + 0.5) * 100
      maximum = math.floor(maximum * 0.011 + 0.5) * 100
    else
      minimum = math.floor(minimum * 0.9 + 0.5)
      maximum = math.floor(maximum * 1.1 + 0.5)
    end
  end
  if maximum <= minimum then
    if minimum == 0 then maximum = 1 else maximum = minimum + math.abs(minimum * 0.1) end
  end
  return minimum, maximum
end

local function render_graph(view)
  local item, canvas = view.item, view.object
  if not canvas then return end
  local p = item.params or {}
  local width, height = item.geometry.w, item.geometry.h
  local explicit = canvas_begin(canvas)
  if item.graph_cleared then
    fill(canvas, item.canvas_background or 0x000000)
    canvas_end(canvas, explicit)
    return
  end
  fill(canvas, p.show_background and p.background or item.canvas_background or 0x000000)

  local left, top, right, bottom = 0, 0, width - 1, height - 1
  if p.show_frame then left, top, right, bottom = 1, 1, width - 2, height - 2 end
  local scale_width = p.show_scale and math.min(28, math.max(18, (p.font_size or 8) * 3)) or 0
  if p.show_scale then
    if p.right_align then right = right - scale_width else left = left + scale_width end
  end
  local plot_w, plot_h = math.max(1, right - left), math.max(1, bottom - top)
  local minimum, maximum = graph_range(item)

  if p.show_grid then
    local density = math.max(2, tonumber(p.grid_density) or 10)
    local offset = tonumber(item.grid_offset) or 0
    local x = left + (offset % density)
    while x <= right do
      draw_line(canvas, x, top, x, bottom, p.grid_color or 0x333333, 255, 1)
      x = x + density
    end
    local y = top
    while y <= bottom do
      draw_line(canvas, left, y, right, y, p.grid_color or 0x333333, 255, 1)
      y = y + density
    end
  end

  local history = item.history
  local count = #history
  local step = math.max(1, tonumber(p.step) or 1)
  local function point(i)
    local x = right - (count - i) * step
    local ratio = clamp((history[i] - minimum) / (maximum - minimum), 0, 1)
    local y = bottom - ratio * plot_h
    return x, y
  end

  if p.graph_type == "HG" then
    for i = 1, count do
      local x, y = point(i)
      if x >= left then draw_rect(canvas, x, y, math.max(1, step - 1), bottom - y + 1, p.graph_color or 0xFFFFFF, 255) end
    end
  else
    for i = 2, count do
      local x1, y1 = point(i - 1)
      local x2, y2 = point(i)
      if x2 >= left then
        if p.graph_type == "AG" then
          local start_x = math.floor(math.max(left, x1))
          local end_x = math.floor(math.max(left, x2))
          local span = math.max(1, x2 - x1)
          for x = start_x, end_x do
            local ratio = clamp((x - x1) / span, 0, 1)
            local y = y1 + (y2 - y1) * ratio
            draw_line(canvas, x, y, x, bottom, p.graph_color or 0xFFFFFF, 84, 1)
          end
        end
        draw_line(canvas, math.max(left, x1), y1, x2, y2, p.graph_color or 0xFFFFFF, 255, p.thick or 1)
      end
    end
  end

  if p.show_scale then
    local text_x = p.right_align and (right + 2) or 0
    local align = p.right_align and ALIGN_LEFT or ALIGN_RIGHT
    local text_width = math.max(1, scale_width - 2)
    local style = parameter_text_style(p, p.right_align and "left" or "right")
    local text_height = math.min(height, vector_text_height(style, height))
    local background = p.show_background and p.background or item.canvas_background or 0x000000
    local vector_top = view.renderer:render_canvas_text(canvas, text_x, top, text_width,
      text_height, tostring(math.floor(maximum + 0.5)), style, background, true)
    local bottom_y = math.max(top, bottom - text_height + 1)
    local vector_bottom = view.renderer:render_canvas_text(canvas, text_x, bottom_y, text_width,
      math.min(text_height, height - bottom_y), tostring(math.floor(minimum + 0.5)),
      style, background, true)
    if not vector_top then
      draw_text(canvas, text_x, top, text_width, tostring(math.floor(maximum + 0.5)),
        p.font_color, p.font_size, align, 255, view.renderer:font_for_size(p.font_size))
    end
    if not vector_bottom then
      draw_text(canvas, text_x, bottom_y, text_width, tostring(math.floor(minimum + 0.5)),
        p.font_color, p.font_size, align, 255, view.renderer:font_for_size(p.font_size))
    end
  end
  if p.show_frame then
    draw_line(canvas, 0, 0, width - 1, 0, p.frame_color, 255, 1)
    draw_line(canvas, width - 1, 0, width - 1, height - 1, p.frame_color, 255, 1)
    draw_line(canvas, width - 1, height - 1, 0, height - 1, p.frame_color, 255, 1)
    draw_line(canvas, 0, height - 1, 0, 0, p.frame_color, 255, 1)
  end
  canvas_end(canvas, explicit)
end

local function arc_span(canvas, cx, cy, radius, start_angle, span, color, width)
  if span <= 0 then return end
  if span >= 359.5 then
    call(lv_canvas_draw_arc, canvas, cx, cy, radius, 0, 359, color, 255, width)
    return
  end
  local first = start_angle % 360
  if first < 0 then first = first + 360 end
  local last = first + span
  if last <= 360 then
    call(lv_canvas_draw_arc, canvas, cx, cy, radius, math.floor(first), math.floor(last), color, 255, width)
  else
    call(lv_canvas_draw_arc, canvas, cx, cy, radius, math.floor(first), 359, color, 255, width)
    call(lv_canvas_draw_arc, canvas, cx, cy, radius, 0, math.floor(last - 360), color, 255, width)
  end
end

local function render_arc(view)
  local item, canvas = view.item, view.object
  if not canvas then return end
  local p = item.params or {}
  local width, height = item.geometry.w, item.geometry.h
  local radius = math.max(1, math.floor(math.min(width, height) / 2) - 1)
  local thickness = clamp(p.thickness or 4, 1, radius)
  local cx, cy = math.floor(width / 2), math.floor(height / 2)
  local explicit = canvas_begin(canvas)
  fill(canvas, item.canvas_background or 0x000000)
  if p.fill and radius > thickness then
    local inner_radius = math.max(1, radius - thickness)
    arc_span(canvas, cx, cy, math.floor(inner_radius / 2), 0, 359.5,
      p.fill_color or item.canvas_background or 0x000000, inner_radius)
  end
  arc_span(canvas, cx, cy, radius - math.floor(thickness / 2), 0, 359.5,
    item.background_color or 0x202020, thickness)
  arc_span(canvas, cx, cy, radius - math.floor(thickness / 2), p.start_angle or 0,
    clamp(item.percent or 0, 0, 100) * 3.6, item.active_color or 0x00FF00, thickness)
  if p.show_text then
    local size = p.font_size or 10
    if view.renderer.vector_font and view.renderer.vector_font.ready then
      view.renderer:update_arc_text(view)
    else
      draw_text(canvas, 0, math.floor((height - size) / 2), width, item.display_text or "",
        p.font_color or 0xFFFFFF, size, ALIGN_CENTER, 255, view.renderer:font_for_size(size))
    end
  end
  canvas_end(canvas, explicit)
end

local function safe_filename(index, src)
  local name = tostring(src or ""):gsub("[?#].*$", ""):match("([^/\\]+)$") or ("image" .. index .. ".bin")
  name = name:gsub("[^%w%._%-]", "_")
  if name == "" then name = "image" .. index .. ".bin" end
  return tostring(index) .. "_" .. name
end

local function be16(data, offset)
  local a, b = data:byte(offset, offset + 1)
  if not a or not b then return nil end
  return a * 256 + b
end

local function be32(data, offset)
  local a, b, c, d = data:byte(offset, offset + 3)
  if not a or not b or not c or not d then return nil end
  return ((a * 256 + b) * 256 + c) * 256 + d
end

local function le16(data, offset)
  local a, b = data:byte(offset, offset + 1)
  if not a or not b then return nil end
  return a + b * 256
end

local function le32(data, offset)
  local a, b, c, d = data:byte(offset, offset + 3)
  if not a or not b or not c or not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

local function jpeg_size(data)
  if data:sub(1, 2) ~= "\255\216" then return nil end
  local position = 3
  while position + 8 <= #data do
    if data:byte(position) ~= 0xFF then
      position = position + 1
    else
      local marker = data:byte(position + 1)
      while marker == 0xFF do
        position = position + 1
        marker = data:byte(position + 1)
      end
      if marker == 0xD8 or marker == 0xD9 then
        position = position + 2
      else
        local length = be16(data, position + 2)
        if not length or length < 2 then return nil end
        local is_sof = marker >= 0xC0 and marker <= 0xCF
          and marker ~= 0xC4 and marker ~= 0xC8 and marker ~= 0xCC
        if is_sof then
          local height = be16(data, position + 5)
          local width = be16(data, position + 7)
          if width and height then return "jpeg", width, height end
          return nil
        end
        position = position + 2 + length
      end
    end
  end
  return nil
end

local function image_info(data)
  if type(data) ~= "string" then return nil, nil, nil, "not binary data" end
  if #data >= 24 and data:sub(1, 8) == "\137PNG\13\10\26\10" then
    local width, height = be32(data, 17), be32(data, 21)
    if width and height and width > 0 and height > 0 then return "png", width, height end
    return nil, nil, nil, "invalid PNG dimensions"
  end
  if #data >= 10 and (data:sub(1, 6) == "GIF87a" or data:sub(1, 6) == "GIF89a") then
    local width, height = le16(data, 7), le16(data, 9)
    if width and height and width > 0 and height > 0 then return "gif", width, height end
    return nil, nil, nil, "invalid GIF dimensions"
  end
  if #data >= 26 and data:sub(1, 2) == "BM" then
    local width, height = le32(data, 19), le32(data, 23)
    if height and height >= 2147483648 then height = 4294967296 - height end
    if width and height and width > 0 and height > 0 then return "bmp", width, height end
    return nil, nil, nil, "invalid BMP dimensions"
  end
  local kind, width, height = jpeg_size(data)
  if kind then return kind, width, height end
  return nil, nil, nil, "unsupported or invalid image"
end

local function callback_string_arg(...)
  for index = 1, select("#", ...) do
    local value = select(index, ...)
    if type(value) == "string" then return value end
  end
  return nil
end

local function parse_http_url(url)
  local authority, path = tostring(url or ""):match("^http://([^/]+)(/.*)$")
  if not authority then authority = tostring(url or ""):match("^http://([^/]+)$") path = "/" end
  if not authority then return nil, nil, nil, "only http:// image URLs are supported" end
  local host, port = authority:match("^([^:]+):(%d+)$")
  if not host then host, port = authority, 80 end
  return host, tonumber(port), path or "/"
end

local function bounded_http_get(url, max_bytes, timeout_ms, callback)
  if not net or not net.createConnection then
    return false, "TCP module missing"
  end
  local host, port, path, parse_error = parse_http_url(url)
  if not host then return false, parse_error end

  local connection
  local timeout_timer
  local completed = false
  local header_buffer = ""
  local body_parts = {}
  local body_bytes = 0
  local headers = nil
  local content_length = nil

  local function stop_timeout()
    if timeout_timer then pcall(function() timeout_timer:unregister() end) timeout_timer = nil end
  end

  local function finish(ok, body, meta, reason)
    if completed then return end
    completed = true
    stop_timeout()
    if connection then pcall(function() connection:close() end) end
    callback(ok, body, meta, reason)
  end

  local function parse_headers(raw)
    local result = {}
    local status = tonumber(raw:match("^HTTP/%d+%.%d+%s+(%d+)") or 0)
    for line in raw:gmatch("[^\r\n]+") do
      local key, value = line:match("^([^:]+):%s*(.-)%s*$")
      if key then result[key:lower()] = value end
    end
    result.status = status
    return result
  end

  local function accept_body(chunk)
    if not headers then
      header_buffer = header_buffer .. chunk
      if #header_buffer > 16384 then finish(false, nil, nil, "image response headers too large") return end
      local first, last = header_buffer:find("\r\n\r\n", 1, true)
      if not first then return end
      local raw_headers = header_buffer:sub(1, first - 1)
      local first_body = header_buffer:sub(last + 1)
      header_buffer = ""
      headers = parse_headers(raw_headers)
      if headers.status ~= 200 then finish(false, nil, headers, "image HTTP " .. tostring(headers.status)) return end
      if headers["transfer-encoding"] and headers["transfer-encoding"]:lower():find("chunked", 1, true) then
        finish(false, nil, headers, "chunked image response unsupported")
        return
      end
      content_length = tonumber(headers["content-length"])
      if content_length and content_length > max_bytes then
        finish(false, nil, headers, "image is " .. tostring(content_length) .. " bytes; limit is " .. tostring(max_bytes))
        return
      end
      chunk = first_body
    end
    if chunk and #chunk > 0 then
      body_bytes = body_bytes + #chunk
      if body_bytes > max_bytes then finish(false, nil, headers, "image exceeds " .. tostring(max_bytes) .. " bytes") return end
      body_parts[#body_parts + 1] = chunk
    end
    if content_length and body_bytes >= content_length then
      finish(true, table.concat(body_parts):sub(1, content_length), headers, nil)
    end
  end

  local ok, connection_or_error = pcall(function()
    if net.TCP then return net.createConnection(net.TCP, false) end
    return net.createConnection()
  end)
  if not ok or not connection_or_error then
    return false, "socket create failed: " .. tostring(connection_or_error)
  end
  connection = connection_or_error
  local function abort_start(reason)
    completed = true
    stop_timeout()
    pcall(function() connection:close() end)
    return false, reason
  end
  local function bind(event, handler)
    local bound = pcall(function() connection:on(event, handler) end)
    return bound
  end
  if not bind("connection", function()
    local request = table.concat({
      "GET " .. path .. " HTTP/1.1",
      "Host: " .. host .. ":" .. tostring(port),
      "Accept: image/png,image/jpeg,image/gif,image/bmp",
      "Accept-Encoding: identity",
      "Cache-Control: no-cache",
      "Connection: close", "", "",
    }, "\r\n")
    local sent, send_error = pcall(function() connection:send(request) end)
    if not sent then finish(false, nil, nil, "image request failed: " .. tostring(send_error)) end
  end) then return abort_start("socket connection handler unavailable") end
  if not bind("receive", function(...)
    local chunk = callback_string_arg(...)
    if chunk and #chunk > 0 and not completed then
      local handled, handle_error = pcall(accept_body, chunk)
      if not handled then finish(false, nil, headers, "image receive failed: " .. tostring(handle_error)) end
    end
  end) then return abort_start("socket receive handler unavailable") end
  if not bind("disconnection", function()
    if completed then return end
    if headers and body_bytes > 0 and (not content_length or body_bytes >= content_length) then
      finish(true, table.concat(body_parts), headers, nil)
    else
      finish(false, nil, headers, "image connection closed early")
    end
  end) then return abort_start("socket disconnection handler unavailable") end

  if tmr and tmr.create then
    timeout_timer = tmr.create()
    timeout_timer:alarm(timeout_ms or 7000, tmr.ALARM_SINGLE, function()
      finish(false, nil, headers, "image timeout")
    end)
  end
  local connected, connect_error = pcall(function() connection:connect(port, host) end)
  if not connected then return abort_start("image connect failed: " .. tostring(connect_error)) end
  return true
end

local function create_image_object(parent, path)
  local is_gif = path:lower():match("%.gif$") ~= nil
  if is_gif and lv_gif_create and lv_gif_set_src then
    local object = lv_gif_create(parent)
    call(lv_gif_set_src, object, path)
    return object
  end
  if lv_img_create and lv_img_set_src then
    local object = lv_img_create(parent)
    call(lv_img_set_src, object, path)
    return object
  end
  return nil
end

function Renderer.new(opts)
  local self = setmetatable({}, Renderer)
  self.config = opts.config or {}
  self.layout = opts.layout
  self.root = opts.root or lv_scr_act()
  self.resource_url = opts.resource_url
  self.log = opts.log or function() end
  self.pages = {}
  self.views = {}
  self.image_queue = {}
  self.image_busy = false
  self.image_loaded = 0
  self.image_skipped = 0
  self.last_image_error = ""
  self.background_surface = nil
  self.background_ready = false
  self.vector_font = opts.vector_font
  self.font_choice = tostring(self.vector_font and self.vector_font.family
    or self.config.vector_font_family or "Tahoma")
  self.font_error = ""
  self.active_page = 1
  return self
end

function Renderer:prepare_font()
  self.font_error = self.vector_font and self.vector_font.error or "vector font engine unavailable"
  if self.vector_font and self.vector_font.ready then self.font_error = "" end
end

function Renderer:font_for_size(size)
  return builtin_font(size)
end

function Renderer:surface_text(x, y, width, height, text, text_style)
  if not self.software_surface then return false end
  local ok, err = self.vector_font:surface_text(self.software_surface,
    x, y, width, height, text, text_style)
  if not ok then self.font_error = tostring(err or "surface text failed") end
  return ok
end

function Renderer:surface_gradient(x, y, width, height, colors, opacity)
  colors = colors or { 0 }
  local first = tonumber(colors[1]) or 0
  local second = tonumber(colors[2]) or first
  height = math.max(1, math.floor(height or 1))
  if first == second or height == 1 then
    return self.vector_font:surface_rect(self.software_surface, x, y, width, height,
      first, opacity or 255)
  end
  local ok = true
  for row = 0, height - 1 do
    local color = mix_color(first, second, row / math.max(1, height - 1))
    local row_ok, err = self.vector_font:surface_rect(self.software_surface,
      x, y + row, width, 1, color, opacity or 255)
    if not row_ok then self.font_error = tostring(err or "surface gradient failed") ok = false break end
  end
  return ok
end

function Renderer:software_draw_text_item(item)
  if item.visible == false then return true end
  local g = item.geometry or {}
  local style = item.text_style or {}
  local width = tonumber(g.w) or 0
  if width <= 0 then width = math.max(1, 320 - (tonumber(g.x) or 0)) end
  local height = tonumber(g.h) or 0
  if height <= 0 then height = vector_text_height(style, 240 - (tonumber(g.y) or 0)) end
  return self:surface_text(g.x or 0, g.y or 0, width, height,
    style.text or "", style)
end

function Renderer:software_draw_sensor(item)
  if item.visible == false then return true end
  local g = item.geometry or {}
  local base_x, base_y = tonumber(g.x) or 0, tonumber(g.y) or 0
  local width = tonumber(g.w) or 0
  if width <= 0 then width = math.max(1, 320 - base_x) end

  local function entry_metrics(entry)
    if not entry then return nil end
    local css = entry.style or {}
    local style = entry.text_style or {}
    local measured = self.vector_font:measure(style.text or "", style)
      or math.max(1, math.floor((style.font and style.font.size or 12) * #(style.text or "") * 0.6))
    local box_width = style_number(css, "width", measured + 3)
    box_width = math.max(1, math.min(width, math.floor(box_width + 0.5)))
    return { css = css, style = style, width = box_width,
      height = vector_text_height(style, 240 - base_y) }
  end

  local function entry_x(metrics, fallback_x)
    if not metrics then return fallback_x or 0 end
    local css = metrics.css
    local right = style_number(css, "right", nil)
    local left = style_number(css, "left", nil)
    if right ~= nil then return width - right - metrics.width end
    if left ~= nil then return left end
    if tostring(css.float or ""):lower() == "right" then return width - metrics.width end
    return fallback_x or 0
  end

  local function draw_entry(entry, metrics, local_x)
    if not entry or not metrics then return true end
    return self:surface_text(base_x + local_x, base_y, metrics.width, metrics.height,
      metrics.style.text or "", metrics.style)
  end

  local label_metrics = entry_metrics(item.label)
  local value_metrics = entry_metrics(item.value)
  local unit_metrics = entry_metrics(item.unit)
  local unit_x = entry_x(unit_metrics, 0)
  local value_x = entry_x(value_metrics, 0)
  if value_metrics and tostring(value_metrics.css.float or ""):lower() == "right"
    and style_number(value_metrics.css, "right", nil) == nil then
    value_x = (unit_metrics and unit_x or width) - value_metrics.width
  end
  local label_x = entry_x(label_metrics, 0)

  if item.bar then
    local bar = item.bar
    local bg = bar.geometry or {}
    local bar_x = base_x + (tonumber(bg.x) or 0)
    local bar_y = base_y + (tonumber(bg.y) or 0) + (bar.margin_top or 0)
    local bar_w = tonumber(bg.w) or 0
    if bar_w <= 0 then bar_w = width end
    local bar_h = tonumber(bg.h) or 0
    if bar_h <= 0 then bar_h = 4 end
    local border = math.max(0, tonumber(bar.border_width) or 0)
    border = math.min(border, math.floor(math.min(bar_w, bar_h) / 2))
    local inner_x, inner_y = bar_x + border, bar_y + border
    local inner_w, inner_h = math.max(0, bar_w - border * 2), math.max(0, bar_h - border * 2)
    if inner_w > 0 and inner_h > 0 then
      self:surface_gradient(inner_x, inner_y, inner_w, inner_h, bar.background, 255)
      local percent = clamp(bar.percent or 0, 0, 100) / 100
      if bar.orientation == "vertical" then
        local foreground_h = math.max(0, math.floor(inner_h * percent + 0.5))
        if foreground_h > 0 then
          local foreground_y = bar.reverse and inner_y or (inner_y + inner_h - foreground_h)
          self:surface_gradient(inner_x, foreground_y, inner_w, foreground_h, bar.foreground, 255)
        end
      else
        local foreground_w = math.max(0, math.floor(inner_w * percent + 0.5))
        if foreground_w > 0 then
          local foreground_x = bar.reverse and (inner_x + inner_w - foreground_w) or inner_x
          self:surface_gradient(foreground_x, inner_y, foreground_w, inner_h, bar.foreground, 255)
        end
      end
    end
    if border > 0 then
      local color = bar.border_color or 0
      self.vector_font:surface_rect(self.software_surface, bar_x, bar_y, bar_w, border, color, 255)
      self.vector_font:surface_rect(self.software_surface, bar_x, bar_y + bar_h - border,
        bar_w, border, color, 255)
      self.vector_font:surface_rect(self.software_surface, bar_x, bar_y, border, bar_h, color, 255)
      self.vector_font:surface_rect(self.software_surface, bar_x + bar_w - border, bar_y,
        border, bar_h, color, 255)
    end
  end

  -- AIDA64 places the Sensor bar first in the DOM and overlays its text row.
  -- Alpha-composite the leaf text after the bar so Label/Value/Unit stay visible.
  draw_entry(item.label, label_metrics, label_x)
  draw_entry(item.value, value_metrics, value_x)
  draw_entry(item.unit, unit_metrics, unit_x)
end

function Renderer:software_draw_graph(item)
  if item.visible == false or item.graph_cleared then return true end
  local g, p = item.geometry or {}, item.params or {}
  local ox, oy = tonumber(g.x) or 0, tonumber(g.y) or 0
  local width, height = math.max(1, tonumber(g.w) or 1), math.max(1, tonumber(g.h) or 1)
  if p.show_background then
    self.vector_font:surface_rect(self.software_surface, ox, oy, width, height,
      p.background or self.layout.background or 0, 255)
  end
  local left, top, right, bottom = 0, 0, width - 1, height - 1
  local drawable_width, drawable_height = width, height
  if p.show_frame then
    left, top, right, bottom = 1, 1, width - 2, height - 2
    drawable_width, drawable_height = math.max(1, width - 2), math.max(1, height - 2)
  end
  local minimum, maximum = graph_range(item, drawable_width)
  if p.show_grid then
    local density = math.max(2, tonumber(p.grid_density) or 10)
    local offset = (tonumber(item.grid_offset) or 0) % density
    for index = 0, drawable_width - 1 do
      if index % density == offset then
        self.vector_font:surface_line(self.software_surface, ox + left + index, oy + top,
          ox + left + index, oy + bottom, p.grid_color or 0x333333, 255, 1)
      end
    end
    for index = drawable_height - 1, 0, -1 do
      if index % density == 0 and (not p.show_frame or index > 0) then
        local gy = bottom - index
        self.vector_font:surface_line(self.software_surface, ox + left, oy + gy,
          ox + right, oy + gy, p.grid_color or 0x333333, 255, 1)
      end
    end
  end
  local history = item.history or {}
  local count = #history
  local spacing = graph_spacing(p)
  local function point(offset)
    local index = count - offset
    local px = right - offset * spacing
    local ratio = clamp((history[index] - minimum) / (maximum - minimum), 0, 1)
    return px, bottom - math.floor(ratio * drawable_height)
  end
  if p.graph_type == "HG" then
    local thick = math.max(1, tonumber(p.thick) or 1)
    for offset = 0, count - 1 do
      local px, py = point(offset)
      if px < left then break end
      local bar_left = px - (thick - 1)
      if bar_left <= right then
        self.vector_font:surface_rect(self.software_surface, ox + math.max(left, bar_left),
          oy + math.max(top, py), math.min(thick, px - left + 1),
          math.max(1, bottom - math.max(top, py) + 1),
          p.graph_color or 0xFFFFFF, 255)
      end
    end
  else
    for offset = 0, count - 2 do
      local x1, y1 = point(offset)
      local x2, y2 = point(offset + 1)
      if x1 < left then break end
      if x2 >= left then
        if p.graph_type == "AG" then
          local start_x = math.floor(math.max(left, x2))
          local end_x = math.floor(x1)
          local span = math.max(1, x1 - x2)
          for px = start_x, end_x do
            local ratio = clamp((px - x2) / span, 0, 1)
            local py = y2 + (y1 - y2) * ratio
            self.vector_font:surface_line(self.software_surface, ox + px, oy + py,
              ox + px, oy + bottom, p.graph_color or 0xFFFFFF, 84, 1)
          end
        end
        self.vector_font:surface_line(self.software_surface, ox + x1, oy + y1,
          ox + x2, oy + y2, p.graph_color or 0xFFFFFF, 255, p.thick or 1)
      end
    end
  end
  if p.show_scale then
    local style = parameter_text_style(p, "left")
    local maximum_text = tostring(math.floor(maximum + 0.5))
    local minimum_text = tostring(math.floor(minimum + 0.5))
    local maximum_width = math.max(1, self.vector_font:measure(maximum_text, style) or 1)
    local minimum_width = math.max(1, self.vector_font:measure(minimum_text, style) or 1)
    local text_height = math.min(height, vector_text_height(style, height))
    local maximum_x = p.right_align and (right - maximum_width) or (left + 1)
    local minimum_x = p.right_align and (right - minimum_width) or (left + 1)
    self:surface_text(ox + maximum_x, oy + top + 1, maximum_width, text_height,
      maximum_text, style)
    local bottom_y = math.max(top, bottom - text_height + 1)
    self:surface_text(ox + minimum_x, oy + bottom_y, minimum_width,
      math.min(text_height, height - bottom_y), minimum_text, style)
  end
  if p.show_frame then
    local color = p.frame_color or 0x666666
    self.vector_font:surface_line(self.software_surface, ox, oy, ox + width - 1, oy, color, 255, 1)
    self.vector_font:surface_line(self.software_surface, ox + width - 1, oy,
      ox + width - 1, oy + height - 1, color, 255, 1)
    self.vector_font:surface_line(self.software_surface, ox + width - 1, oy + height - 1,
      ox, oy + height - 1, color, 255, 1)
    self.vector_font:surface_line(self.software_surface, ox, oy + height - 1, ox, oy, color, 255, 1)
  end
end

function Renderer:software_draw_arc(item)
  if item.visible == false then return true end
  local g, p = item.geometry or {}, item.params or {}
  local ox, oy = tonumber(g.x) or 0, tonumber(g.y) or 0
  local width, height = math.max(1, tonumber(g.w) or 1), math.max(1, tonumber(g.h) or 1)
  local display_text = tostring(item.display_text or "")
  if display_text == "" then return end
  local thickness = clamp(p.thickness or 4, 1, math.max(1, width / 2))
  local cx, cy = ox + width / 2, oy + height / 2
  local ring_radius = math.max(0.5, (width - thickness) / 2)
  if p.fill then
    self.vector_font:surface_circle(self.software_surface, cx, cy,
      math.max(0, width / 2 - thickness / 2), p.fill_color or self.layout.background or 0, 255)
  end
  local span = clamp(item.percent or 0, 0, 100) * 3.6
  local start_angle = tonumber(p.start_angle) or 0
  if span <= 0 then
    self.vector_font:surface_arc(self.software_surface, cx, cy,
      ring_radius, 0, 360, item.background_color or 0x202020, 255, thickness)
  elseif span < 360 then
    self.vector_font:surface_arc(self.software_surface, cx, cy,
      ring_radius, start_angle + span, start_angle + 360,
      item.background_color or 0x202020, 255, thickness)
  end
  if span > 0 then
    self.vector_font:surface_arc(self.software_surface, cx, cy,
      ring_radius, start_angle, start_angle + span,
      item.active_color or 0x00FF00, 255, thickness)
  end
  if p.show_text then
    local style = parameter_text_style(p, "center")
    local text_height = vector_text_height(style, height)
    self:surface_text(ox, oy + math.max(0, math.floor((height - text_height) / 2)),
      width, text_height, display_text, style)
  end
end

function Renderer:software_flush(page_index)
  local canvas = self.page_canvases and self.page_canvases[page_index]
  if not canvas then return false end
  local data, err = self.vector_font:surface_pixels(self.software_surface)
  if not data then self.font_error = tostring(err or "surface export failed") return false end
  local explicit = canvas_begin(canvas)
  local ok, result = call(lv_canvas_blit_rgb565, canvas, 0, 0, 320, 240,
    data, { byte_order = "little", full_rewrite = true })
  if not ok or result == false then
    ok, result = call(lv_canvas_blit_rgb565, canvas, 0, 0, 320, 240, data)
  end
  canvas_end(canvas, explicit)
  if not ok or result == false then self.font_error = "software surface blit failed" return false end
  return true
end

function Renderer:software_render_page(page_index)
  local page = self.layout.pages[page_index]
  if not page or not self.software_surface then return false end
  local ok, err
  local background_page = self.layout.background_image and self.layout.background_image.page
  if self.background_surface and self.background_ready
    and (background_page == nil or background_page == page_index) then
    ok, err = self.vector_font:surface_copy(self.software_surface, self.background_surface)
  else
    ok, err = self.vector_font:surface_clear(self.software_surface, self.layout.background or 0)
  end
  if not ok then self.font_error = tostring(err or "surface clear failed") return false end
  for _, item in ipairs(page.items or {}) do
    if item.kind == "label" or item.kind == "simple" then self:software_draw_text_item(item)
    elseif item.kind == "sensor" then self:software_draw_sensor(item)
    elseif item.kind == "graph" then self:software_draw_graph(item)
    elseif item.kind == "arc" then self:software_draw_arc(item) end
  end
  return self:software_flush(page_index)
end

function Renderer:render_canvas_text(canvas, x, y, width, height, text, text_style, background, opaque, full)
  if not canvas or not self.vector_font or not self.vector_font.ready or not lv_canvas_blit_rgb565 then
    return false
  end
  width, height = math.floor(width or 0), math.floor(height or 0)
  if width < 1 or height < 1 then return false end
  local data, render_error = self.vector_font:render(text, width, height, text_style,
    background or self.layout.background or 0, CHROMA_KEY, opaque)
  if not data then
    self.font_error = tostring(render_error or "vector render failed")
    return false
  end
  local ok, result = call(lv_canvas_blit_rgb565, canvas, math.floor(x or 0), math.floor(y or 0),
    width, height, data, { byte_order = "little", full_rewrite = full == true })
  if not ok or result == false then
    ok, result = call(lv_canvas_blit_rgb565, canvas, math.floor(x or 0), math.floor(y or 0),
      width, height, data)
  end
  if not ok or result == false then
    self.font_error = "lv_canvas_blit_rgb565 failed"
    return false
  end
  return true
end

function Renderer:update_text_view(text_view, text)
  if not text_view then return false end
  text_view.text = tostring(text or "")
  if text_view.vector then
    -- Standalone text canvases are not part of a graph/arc frame. Commit their
    -- direct RGB565 rewrite explicitly so LVGL invalidates the canvas object.
    local explicit = canvas_begin(text_view.object)
    local rendered = self:render_canvas_text(text_view.object, 0, 0,
      text_view.width, text_view.height, text_view.text,
      text_view.text_style, text_view.background, true, true)
    canvas_end(text_view.object, explicit)
    return rendered
  end
  if text_view.object then call(lv_label_set_text, text_view.object, text_view.text) return true end
  return false
end

function Renderer:create_text_view(parent, geometry, text_style, width)
  geometry, text_style = geometry or {}, text_style or {}
  local x, y = tonumber(geometry.x) or 0, tonumber(geometry.y) or 0
  local text_width = tonumber(width) or tonumber(geometry.w) or 0
  if text_width <= 0 then text_width = 320 - x end
  text_width = math.max(1, math.min(320 - x, math.floor(text_width)))
  local available_height = math.max(1, 240 - y)
  local text_height = tonumber(geometry.h) or 0
  if text_height <= 0 then text_height = vector_text_height(text_style, available_height) end
  text_height = math.max(1, math.min(available_height, math.floor(text_height)))

  if self.vector_font and self.vector_font.ready and lv_canvas_blit_rgb565 then
    -- Use the same TRUE_COLOR path as graphs. The firmware exposes the
    -- chroma-keyed format but not its key and drops standalone keyed canvases.
    local canvas = canvas_create(parent, text_width, text_height, CANVAS_FMT)
    if canvas then
      call(lv_obj_set_pos, canvas, x, y)
      call(lv_obj_set_style_bg_opa, canvas, 0, MAIN)
      local text_view = {
        object = canvas, vector = true, width = text_width, height = text_height,
        text_style = text_style, background = self.layout.background or 0,
      }
      if self:update_text_view(text_view, text_style.text or "") then return text_view end
      if lv_obj_del then call(lv_obj_del, canvas) end
    end
  end

  local object = make_label(parent, geometry, text_style, text_width, self)
  return { object = object, vector = false, text_style = text_style,
    width = text_width, height = text_height }
end

function Renderer:update_arc_text(view)
  if not view or not view.page then return false end
  local item, params = view.item, view.item.params or {}
  local style = parameter_text_style(params, "center")
  local available = math.max(1, item.geometry.h)
  local height = vector_text_height(style, available)
  if not view.arc_text then
    view.arc_text = self:create_text_view(view.page, {
      x = item.geometry.x,
      y = item.geometry.y + math.max(0, math.floor((item.geometry.h - height) / 2)),
      w = item.geometry.w,
      h = height,
    }, style, item.geometry.w)
    local background = params.fill and params.fill_color or item.canvas_background or self.layout.background or 0
    view.arc_text.background = background
  end
  return self:update_text_view(view.arc_text, item.display_text or "")
end

function Renderer:make_text(page, item, geometry, text_style, width)
  local text_view = self:create_text_view(page, geometry, text_style, width)
  return { object = text_view.object, text = text_view, item = item, kind = "text" }
end

function Renderer:build_sensor(page, item)
  local g = item.geometry
  local view = { item = item, kind = "sensor" }
  local width = g.w > 0 and g.w or math.max(1, 320 - g.x)
  if item.label then
    view.label = self:create_text_view(page, { x = g.x, y = g.y }, item.label.text_style, width)
  end
  if item.value then
    local vg = item.value.style or {}
    local x = g.x + (tonumber((vg.left or ""):match("([%-]?%d+)")) or 0)
    view.value = self:create_text_view(page, { x = x, y = g.y }, item.value.text_style, width - (x - g.x))
  end
  if item.unit then
    local ug = item.unit.style or {}
    local unit_style = item.unit.text_style
    unit_style.align = "right"
    view.unit = self:create_text_view(page, { x = g.x, y = g.y }, unit_style, width)
  end
  if item.bar then
    local bg = item.bar.geometry
    local bar_x = g.x + bg.x
    local bar_y
    if item.bar.style and item.bar.style.top == nil then
      local line_size = 8
      for _, text_item in ipairs({ item.label, item.value, item.unit }) do
        line_size = math.max(line_size,
          tonumber(text_item and text_item.text_style and text_item.text_style.font
            and text_item.text_style.font.size) or 0)
      end
      bar_y = g.y + math.ceil(line_size * 1.2) + (item.bar.margin_top or 0)
    else
      bar_y = g.y + bg.y + (item.bar.margin_top or 0)
    end
    local bar_w = bg.w > 0 and bg.w or width
    local bar_h = bg.h > 0 and bg.h or 4
    view.bar_bg = make_panel(page, bar_x, bar_y, bar_w, bar_h, item.bar.background[1], 255)
    apply_gradient(view.bar_bg, item.bar.background)
    view.bar_fg = make_panel(view.bar_bg, 0, 0, math.max(1, bar_w * (item.bar.percent or 0) / 100), bar_h,
      item.bar.foreground[1], 255)
    apply_gradient(view.bar_fg, item.bar.foreground)
    view.bar_width = bar_w
  end
  return view
end

function Renderer:build_item(page, item)
  local view
  if item.kind == "label" or item.kind == "simple" then
    view = self:make_text(page, item, item.geometry, item.text_style)
  elseif item.kind == "sensor" then
    view = self:build_sensor(page, item)
  elseif item.kind == "graph" or item.kind == "arc" then
    item.canvas_background = self.layout.background or 0
    local canvas = canvas_create(page, math.max(1, item.geometry.w), math.max(1, item.geometry.h))
    if canvas then call(lv_obj_set_pos, canvas, item.geometry.x, item.geometry.y) end
    view = { object = canvas, item = item, kind = item.kind, renderer = self, page = page }
    if item.kind == "graph" then render_graph(view) else render_arc(view) end
  elseif item.kind == "image" then
    view = { item = item, kind = "image", object = nil }
    self.image_queue[#self.image_queue + 1] = { page = page, item = item, view = view }
  end
  if view then
    self.views[item.id] = view
    if item.value_update then self.views[item.value_update] = view end
    if item.bar and item.bar.update_id then self.views[item.bar.update_id] = view end
    if item.update_id then self.views[item.update_id] = view end
  end
end

function Renderer:index_software_item(page, page_index, item)
  local view = { item = item, kind = item.kind, page = page, page_index = page_index }
  if item.kind == "image" then
    self.image_queue[#self.image_queue + 1] = { page = page, item = item, view = view }
  end
  self.views[item.id] = view
  if item.value_update then self.views[item.value_update] = view end
  if item.bar and item.bar.update_id then self.views[item.bar.update_id] = view end
  if item.update_id then self.views[item.update_id] = view end
  return view
end

function Renderer:build()
  self:prepare_font()
  call(lv_obj_clean, self.root)
  call(lv_obj_set_style_bg_color, self.root, self.layout.background or 0, MAIN)
  call(lv_obj_set_style_bg_opa, self.root, 255, MAIN)
  if FLAG_SCROLLABLE then call(lv_obj_clear_flag, self.root, FLAG_SCROLLABLE) end
  self.software_mode = self.vector_font and self.vector_font.surface_ready
    and lv_canvas_blit_rgb565 and CANVAS_FMT and true or false
  if self.software_mode then
    local surface, surface_error = self.vector_font:surface_create(320, 240, self.layout.background or 0)
    if not surface then
      self.software_mode = false
      self.font_error = tostring(surface_error or "software surface unavailable")
    else
      self.software_surface = surface
      if self.layout.background_image and self.vector_font.layered_surface then
        local background_surface, background_error = self.vector_font:surface_create(
          320, 240, self.layout.background or 0)
        if background_surface then
          self.background_surface = background_surface
          self.image_queue[#self.image_queue + 1] = {
            page = nil,
            item = self.layout.background_image,
            view = { item = self.layout.background_image, kind = "background" },
          }
        else
          self.last_image_error = tostring(background_error or "background surface unavailable")
          self.image_skipped = self.image_skipped + 1
        end
      elseif self.layout.background_image then
        self.last_image_error = "font module does not provide background composition"
        self.image_skipped = self.image_skipped + 1
      end
      self.page_canvases = {}
      for index = 1, self.layout.page_count do
        local page = make_panel(self.root, 0, 0, 320, 240, self.layout.background or 0, 255)
        self.pages[index] = page
        set_hidden(page, index ~= self.active_page)
        local canvas = canvas_create(page, 320, 240, CANVAS_FMT)
        if canvas then call(lv_obj_set_pos, canvas, 0, 0) end
        self.page_canvases[index] = canvas
        for _, item in ipairs(self.layout.pages[index].items) do
          self:index_software_item(page, index, item)
        end
        if not canvas or not self:software_render_page(index) then
          self.software_mode = false
          break
        end
      end
      if self.software_mode then
        self:load_next_image()
        return
      end
      self.vector_font:surface_free(self.software_surface)
      self.software_surface = nil
      if self.background_surface then
        self.vector_font:surface_free(self.background_surface)
        self.background_surface = nil
      end
      self.background_ready = false
      self.page_canvases = nil
      self.pages = {}
      self.views = {}
      self.image_queue = {}
      call(lv_obj_clean, self.root)
    end
  end
  for index = 1, self.layout.page_count do
    local page = make_panel(self.root, 0, 0, 320, 240, self.layout.background or 0, 255)
    self.pages[index] = page
    set_hidden(page, index ~= self.active_page)
    for _, item in ipairs(self.layout.pages[index].items) do self:build_item(page, item) end
  end
  self:load_next_image()
end

function Renderer:load_next_image()
  if self.image_busy or #self.image_queue == 0 then return end
  local pending = table.remove(self.image_queue, 1)
  local cache_dir = self.config.cache_dir or "/sd/apps/aida_monitor/cache"
  if file and file.mkdir then call(file.mkdir, cache_dir) end
  local path = cache_dir .. "/" .. safe_filename(pending.item.id:match("%d+") or 1, pending.item.src)
  local function placeholder(reason)
    self.image_skipped = self.image_skipped + 1
    self.last_image_error = tostring(reason or "image unavailable")
    self.log("image_skipped", pending.item.src, self.last_image_error)
    if pending.item.is_background then
      self.background_ready = false
      return
    end
    local g = pending.item.geometry
    local width = g.w > 0 and g.w or 40
    local height = g.h > 0 and g.h or 40
    local inner_width = math.max(1, width - 2)
    local panel = make_panel(pending.page, g.x, g.y, width, height, 0x151515, 255)
    call(lv_obj_set_style_border_width, panel, 1, MAIN)
    call(lv_obj_set_style_border_color, panel, 0xFF5D5D, MAIN)
    local label = make_label(panel, { x = 1, y = math.max(0, math.floor(height / 2) - 6), w = inner_width }, {
      text = "IMG", color = 0xFF5D5D, font = { size = 8 }, align = "center",
    }, inner_width, self)
    pending.view.object = panel
    pending.view.placeholder = label
  end
  local function attach(info)
    if pending.item.is_background then
      local cleared, clear_error = self.vector_font:surface_clear(
        self.background_surface, self.layout.background or 0)
      local rendered, render_error = false, nil
      if cleared then
        rendered, render_error = self.vector_font:surface_image(self.background_surface,
          info.data, 0, 0, 320, 240, pending.item.fit or "stretch")
      end
      if not cleared or not rendered then
        placeholder(clear_error or render_error or "background decode failed")
      else
        self.background_ready = true
        self.image_loaded = self.image_loaded + 1
        for index = 1, #self.pages do self:software_render_page(index) end
      end
      return
    end
    local object = create_image_object(pending.page, path)
    pending.view.object = object
    if object then
      local g = pending.item.geometry
      call(lv_obj_set_pos, object, g.x, g.y)
      if lv_img_set_pivot then call(lv_img_set_pivot, object, 0, 0) end
      if lv_img_set_zoom and info and info.width > 0 and info.height > 0 and (g.w > 0 or g.h > 0) then
        local scale_x = g.w > 0 and g.w / info.width or nil
        local scale_y = g.h > 0 and g.h / info.height or nil
        local scale = scale_x and scale_y and math.min(scale_x, scale_y) or scale_x or scale_y
        call(lv_img_set_zoom, object, math.max(1, math.floor(scale * 256 + 0.5)))
      end
      self.image_loaded = self.image_loaded + 1
    else
      placeholder("image widget unavailable")
    end
  end
  if not self.resource_url then
    if file and file.exists then
      local ok, exists = pcall(file.exists, path)
      if ok and exists then placeholder("network unavailable; cached image not trusted")
      else placeholder("image resource URL missing") end
    else
      placeholder("image resource URL missing")
    end
    self:load_next_image()
    return
  end
  self.image_busy = true
  local started, start_error = bounded_http_get(self.resource_url(pending.item.src),
    tonumber(self.config.max_image_bytes) or 262144,
    tonumber(self.config.image_timeout_ms) or 7000,
    function(ok, body, headers, reason)
      self.image_busy = false
      if not ok then
        placeholder(reason)
        self:load_next_image()
        return
      end
      local kind, width, height, info_error = image_info(body)
      local max_pixels = tonumber(self.config.max_image_pixels) or 307200
      if not kind then
        placeholder(info_error)
      elseif width * height > max_pixels then
        placeholder("image is " .. tostring(width) .. "x" .. tostring(height)
          .. "; pixel limit is " .. tostring(max_pixels))
      elseif pending.item.is_background then
        if file and file.putcontents then pcall(file.putcontents, path, body) end
        attach({ kind = kind, width = width, height = height, data = body })
      elseif not file or not file.putcontents then
        placeholder("file API missing")
      else
        local saved, result = pcall(file.putcontents, path, body)
        if saved and result ~= false then
          attach({ kind = kind, width = width, height = height })
        else
          placeholder("image save failed")
        end
      end
      self:load_next_image()
    end)
  if not started then
    self.image_busy = false
    placeholder(start_error or "image request could not start")
    self:load_next_image()
  end
end

function Renderer:set_page(index)
  index = clamp(index, 1, #self.pages)
  if index == self.active_page then return end
  for i, page in ipairs(self.pages) do set_hidden(page, i ~= index) end
  self.active_page = index
end

function Renderer:apply_update(update, defer_render)
  local view = self.views[update.id]
  if not view then return false end
  if self.software_mode then
    local item = view.item
    if update.kind == "text" then
      if item.kind == "sensor" and item.value then
        item.value.text_style.text = tostring(update.text or "")
      elseif item.text_style then
        item.text_style.text = tostring(update.text or "")
      end
      item.visible = update.visible ~= false
    elseif update.kind == "bar" and item.bar then
      item.bar.percent = tonumber(update.percent) or 0
      item.visible = update.visible ~= false
      if update.background then item.bar.background = update.background end
      if update.foreground then item.bar.foreground = update.foreground end
    elseif update.kind == "graph" then
      item.graph_cleared = false
      local history = item.history
      history[#history + 1] = tonumber(update.value) or 0
      local max_points = item.max_points or self.config.history_points or 49
      while #history > max_points do table.remove(history, 1) end
      local density = math.max(1, tonumber(item.params and item.params.grid_density) or 10)
      local delta = math.max(1, (tonumber(item.params and item.params.step) or 1) + 1)
      item.grid_offset = ((tonumber(item.grid_offset) or 0) - delta) % density
    elseif update.kind == "graph_clear" then
      item.history = {}
      item.graph_cleared = true
    elseif update.kind == "arc" then
      item.percent = tonumber(update.percent) or 0
      item.display_text = update.text or ""
      item.visible = update.visible ~= false
      item.background_color = update.background_color
      item.active_color = update.active_color
    end
    if not defer_render then self:software_render_page(view.page_index or self.active_page) end
    return true
  end
  if update.kind == "text" then
    if view.kind == "sensor" and view.value then self:update_text_view(view.value, update.text or "")
    elseif view.text then self:update_text_view(view.text, update.text or "")
    elseif view.object then call(lv_label_set_text, view.object, tostring(update.text or "")) end
  elseif update.kind == "bar" and view.bar_fg then
    local width = math.max(1, math.floor(view.bar_width * clamp(update.percent, 0, 100) / 100 + 0.5))
    call(lv_obj_set_width, view.bar_fg, width)
    if update.background then apply_gradient(view.bar_bg, update.background) end
    if update.foreground then apply_gradient(view.bar_fg, update.foreground) end
  elseif update.kind == "graph" then
    view.item.graph_cleared = false
    local history = view.item.history
    history[#history + 1] = tonumber(update.value) or 0
    local max_points = view.item.max_points or self.config.history_points or 49
    while #history > max_points do table.remove(history, 1) end
    local density = math.max(1, tonumber(view.item.params and view.item.params.grid_density) or 10)
    local delta = math.max(1, (tonumber(view.item.params and view.item.params.step) or 1) + 1)
    view.item.grid_offset = ((tonumber(view.item.grid_offset) or 0) - delta) % density
    render_graph(view)
  elseif update.kind == "graph_clear" then
    view.item.history = {}
    view.item.graph_cleared = true
    render_graph(view)
  elseif update.kind == "arc" then
    view.item.percent = tonumber(update.percent) or 0
    view.item.display_text = update.text or ""
    view.item.visible = update.visible ~= false
    view.item.background_color = update.background_color
    view.item.active_color = update.active_color
    render_arc(view)
  end
  return true
end

function Renderer:apply_sample(sample)
  if sample.page then self:set_page(sample.page) end
  local changed = false
  for _, update in ipairs(sample.updates or {}) do
    if self:apply_update(update, self.software_mode) then changed = true end
  end
  if self.software_mode and changed then self:software_render_page(self.active_page) end
end

function Renderer:snapshot()
  local font_stats = self.vector_font and self.vector_font:stats() or {}
  return {
    page = self.active_page,
    pages = #self.pages,
    items = self.layout.item_count or 0,
    counts = self.layout.counts or {},
    images_loaded = self.image_loaded,
    images_skipped = self.image_skipped,
    image_error = self.last_image_error,
    font = self.font_choice,
    font_face = font_stats.face or self.font_choice,
    font_engine = font_stats.engine or "firmware fallback",
    font_loaded = font_stats.loaded == true and self.font_error == "",
    font_error = self.font_error ~= "" and self.font_error or font_stats.error or "",
    font_bytes = font_stats.font_bytes or 0,
    font_cache_bytes = font_stats.cache_bytes or 0,
    font_cache_entries = font_stats.cache_entries or 0,
    font_renders = font_stats.renders or 0,
    font_missing_glyphs = font_stats.missing_glyphs or 0,
    font_source = font_stats.source or "default",
    font_match = font_stats.match == true,
    font_selection = font_stats.selection or "",
    font_requested_families = font_stats.requested_families or "",
    font_path = font_stats.path or "",
    internal_free = font_stats.internal_free or 0,
    psram_free = font_stats.psram_free or 0,
    psram_largest = font_stats.psram_largest or 0,
    compositor = self.software_mode and "rgb565-a8" or "legacy-canvas",
    background_ready = self.background_ready,
    layer_model = self.software_mode and "background/compositor/foreground" or "legacy-dom",
    subpixel = font_stats.subpixel or tostring(self.config.font_subpixel or "off"),
    antialiasing = font_stats.antialiasing or "firmware",
    surface_bytes = font_stats.surface_bytes or 0,
    surface_flushes = font_stats.surface_flushes or 0,
  }
end

function Renderer:destroy()
  if self.software_surface and self.vector_font then
    self.vector_font:surface_free(self.software_surface)
    self.software_surface = nil
  end
  if self.background_surface and self.vector_font then
    self.vector_font:surface_free(self.background_surface)
    self.background_surface = nil
  end
  self.background_ready = false
  call(lv_obj_clean, self.root)
  self.image_queue = {}
  self.image_busy = false
  self.pages = {}
  self.views = {}
  self.page_canvases = nil
end

Renderer.image_info = image_info

return Renderer
