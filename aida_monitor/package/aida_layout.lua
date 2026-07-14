local Layout = {}

local function trim(value)
  if value == nil then
    return ""
  end
  return (tostring(value):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function utf8_char(code)
  if utf8 and utf8.char then
    local ok, value = pcall(utf8.char, code)
    if ok then
      return value
    end
  end
  if code >= 0 and code <= 255 then
    return string.char(code)
  end
  return "?"
end

local function html_decode(value)
  local text = tostring(value or "")
  text = text:gsub("&#x([%x]+);", function(code)
    return utf8_char(tonumber(code, 16) or 63)
  end)
  text = text:gsub("&#(%d+);", function(code)
    return utf8_char(tonumber(code, 10) or 63)
  end)
  text = text:gsub("&nbsp;", " ")
  text = text:gsub("&deg;", "°")
  text = text:gsub("&quot;", '"')
  text = text:gsub("&#39;", "'")
  text = text:gsub("&lt;", "<")
  text = text:gsub("&gt;", ">")
  text = text:gsub("&amp;", "&")
  return text
end

local function parse_style(raw)
  local style = {}
  for part in tostring(raw or ""):gmatch("[^;]+") do
    local key, value = part:match("^%s*([%w%-]+)%s*:%s*(.-)%s*$")
    if key and value then
      style[key:lower()] = value
    end
  end
  return style
end

local function css_number(style, key, fallback)
  local value = style and style[key]
  local number = value and value:match("([%-+]?%d+%.?%d*)")
  return tonumber(number) or fallback
end

local function css_color(value, fallback)
  local hex = tostring(value or ""):match("#([%x][%x][%x][%x][%x][%x])")
  if hex then
    return tonumber(hex, 16)
  end
  local short = tostring(value or ""):match("#([%x][%x][%x])")
  if short then
    local r, g, b = short:sub(1, 1), short:sub(2, 2), short:sub(3, 3)
    return tonumber(r .. r .. g .. g .. b .. b, 16)
  end
  return fallback or 0
end

local function parse_gradient(value, fallback)
  local colors = {}
  for hex in tostring(value or ""):gmatch("#([%x][%x][%x][%x][%x][%x])") do
    colors[#colors + 1] = tonumber(hex, 16)
    if #colors == 2 then
      break
    end
  end
  if #colors == 0 then
    colors[1] = fallback or 0
  end
  if #colors == 1 then
    colors[2] = colors[1]
  end
  return colors
end

local function font_size(value, fallback)
  local text = tostring(value or "")
  local raw_size = tonumber(text:match("([%-+]?%d+%.?%d*)")) or fallback or 10
  local pixels = raw_size
  if text:lower():find("pt", 1, true) then
    pixels = math.floor(raw_size * 4 / 3 + 0.5)
  end
  if pixels < 6 then pixels = 6 elseif pixels > 96 then pixels = 96 end
  return pixels, raw_size
end

local function font_from_style(style)
  local pixels, raw_size = font_size(style and style["font-size"], 10)
  local weight = tostring(style and style["font-weight"] or ""):lower()
  local numeric_weight = tonumber(weight:match("(%d+)")) or 0
  return {
    size = pixels,
    source_size = raw_size,
    family = style and style["font-family"] or "",
    bold = weight:find("bold", 1, true) ~= nil or numeric_weight >= 600,
    italic = tostring(style and style["font-style"] or ""):lower():find("italic", 1, true) ~= nil,
  }
end

local function shadow_from_style(style)
  local raw = trim(style and style["text-shadow"] or "")
  if raw == "" or raw:lower() == "none" then return nil end
  local lengths = {}
  for value in raw:gmatch("([%-+]?%d+%.?%d*)px") do
    lengths[#lengths + 1] = tonumber(value) or 0
    if #lengths == 3 then break end
  end
  return {
    x = math.floor((lengths[1] or 0) + 0.5),
    y = math.floor((lengths[2] or 0) + 0.5),
    blur = math.max(0, math.floor((lengths[3] or 0) + 0.5)),
    color = css_color(raw, 0x000000),
    opacity = 192,
  }
end

local function split_csv(raw)
  local result = {}
  local buffer = {}
  local quoted = false
  local escaped = false
  for i = 1, #raw do
    local ch = raw:sub(i, i)
    if escaped then
      buffer[#buffer + 1] = ch
      escaped = false
    elseif ch == "\\" and quoted then
      buffer[#buffer + 1] = ch
      escaped = true
    elseif ch == '"' then
      quoted = not quoted
      buffer[#buffer + 1] = ch
    elseif ch == "," and not quoted then
      result[#result + 1] = trim(table.concat(buffer))
      buffer = {}
    else
      buffer[#buffer + 1] = ch
    end
  end
  result[#result + 1] = trim(table.concat(buffer))
  return result
end

local function js_value(value)
  local text = trim(value)
  local quoted = text:match('^"(.*)"$')
  if quoted ~= nil then
    return quoted
  end
  local number = tonumber(text)
  if number ~= nil then
    return number
  end
  return text
end

local function style_geometry(style)
  return {
    x = math.floor(css_number(style, "left", 0) + 0.5),
    y = math.floor(css_number(style, "top", 0) + 0.5),
    w = math.floor(css_number(style, "width", 0) + 0.5),
    h = math.floor(css_number(style, "height", 0) + 0.5),
  }
end

local function style_visible(style)
  local visibility = tostring(style and style.visibility or ""):lower()
  local display = tostring(style and style.display or ""):lower()
  return visibility ~= "hidden" and display ~= "none"
end

local function css_url(value)
  local raw = trim(tostring(value or ""):match("url%s*%((.-)%)") or "")
  if raw == "" or raw:lower() == "none" then return nil end
  if (raw:sub(1, 1) == '"' and raw:sub(-1) == '"')
    or (raw:sub(1, 1) == "'" and raw:sub(-1) == "'") then
    raw = raw:sub(2, -2)
  end
  return html_decode(raw)
end

local function parse_background_image(html)
  local style_block = tostring(html or ""):match("<style[^>]*>(.-)</style>") or ""
  local body_css = style_block:match("body%s*{(.-)}") or ""
  local body_style = tostring(html or ""):match('<body[^>]-style="([^"]*)"') or ""
  local body_tag = tostring(html or ""):match("<body[^>]*>") or ""
  local src = css_url((parse_style(body_style)["background-image"]))
    or css_url((parse_style(body_css)["background-image"]))
    or html_decode(body_tag:match('background="([^"]+)"') or "")
  if src == "" then return nil end
  if not src then return nil end
  return {
    id = "BackgroundImage",
    kind = "image",
    src = src,
    is_background = true,
    fit = "stretch",
    geometry = { x = 0, y = 0, w = 320, h = 240 },
    order = 0,
    z_index = -2147483647,
  }
end

local function text_fields(style, text)
  local font = font_from_style(style)
  local decoration = tostring(style and style["text-decoration"] or ""):lower()
  return {
    text = html_decode(text),
    color = css_color(style and style.color, 0xFFFFFF),
    font = font,
    align = style and (style.float == "right" and "right" or style["text-align"]) or "left",
    underline = decoration:find("underline", 1, true) ~= nil,
    strike = decoration:find("line-through", 1, true) ~= nil
      or decoration:find("strikethrough", 1, true) ~= nil,
    shadow = shadow_from_style(style),
  }
end

local function ensure_page(model, index)
  local page = model.pages[index]
  if not page then
    page = { index = index, items = {} }
    model.pages[index] = page
  end
  return page
end

local function add_item(model, page_index, item)
  local page = ensure_page(model, page_index)
  item.page = page_index
  item.order = #page.items + 1
  page.items[#page.items + 1] = item
  if item.id and item.id ~= "" then
    model.items[item.id] = item
  end
  model.item_count = model.item_count + 1
  model.counts[item.kind] = (model.counts[item.kind] or 0) + 1
end

local function parse_label(model, page_index, line)
  local id, raw_style, text = line:match('<span id="(Label%d+)" style="([^"]*)">(.-)</span>')
  if not id then
    return false
  end
  local style = parse_style(raw_style)
  local item = {
    id = id,
    kind = "label",
    style = style,
    geometry = style_geometry(style),
    text_style = text_fields(style, text),
    visible = style_visible(style),
    z_index = css_number(style, "z-index", nil),
  }
  add_item(model, page_index, item)
  return true
end

local function parse_simple(model, page_index, line)
  local outer_raw, id, inner_raw, text = line:match('<span style="([^"]*)"><span id="(Simple%d+)" style="([^"]*)">(.-)</span></span>')
  if id then
    local outer = parse_style(outer_raw)
    local inner = parse_style(inner_raw)
    local merged = {}
    for key, value in pairs(outer) do merged[key] = value end
    for key, value in pairs(inner) do merged[key] = value end
    add_item(model, page_index, {
      id = id,
      update_id = id,
      kind = "simple",
      style = merged,
      geometry = style_geometry(outer),
      text_style = text_fields(merged, text),
      visible = style_visible(merged),
      z_index = css_number(merged, "z-index", nil),
    })
    return true
  end

  id, outer_raw, text = line:match('<span id="(Simple%d+)" style="([^"]*)">(.-)</span>')
  if not id then
    return false
  end
  local style = parse_style(outer_raw)
  add_item(model, page_index, {
    id = id,
    update_id = id,
    kind = "simple",
    style = style,
    geometry = style_geometry(style),
    text_style = text_fields(style, text),
    visible = style_visible(style),
    z_index = css_number(style, "z-index", nil),
  })
  return true
end

local function parse_sensor(model, page_index, line)
  local id, outer_raw, inner = line:match('<div id="(SI%d+)" style="([^"]*)">(.*)</div>')
  if not id then
    return false
  end
  local outer = parse_style(outer_raw)
  local item = {
    id = id,
    kind = "sensor",
    style = outer,
    geometry = style_geometry(outer),
    visible = style_visible(outer),
    z_index = css_number(outer, "z-index", nil),
  }

  -- AIDA64 emits both a flat SensorItem and a nested table-cell variant when
  -- Bar is enabled. Match leaf divs only so wrapper markup cannot consume the
  -- actual label/unit nodes.
  for raw_style, text in inner:gmatch('<div style="([^"]*)">([^<]-)</div>') do
    local style = parse_style(raw_style)
    local fields = text_fields(style, text)
    if tostring(style.float or ""):lower() == "left" and not item.label then
      item.label = { style = style, text_style = fields }
    elseif style.right == "0" or style.right == "0px"
      or tostring(style.float or ""):lower() == "right" then
      item.unit = { style = style, text_style = fields }
    end
  end

  local value_id, value_raw, value_text = inner:match('<div id="(SIV%d+)" style="([^"]*)">(.-)</div>')
  if value_id then
    local value_style = parse_style(value_raw)
    item.value = {
      id = value_id,
      style = value_style,
      text_style = text_fields(value_style, value_text),
    }
    item.value_update = value_id
  end

  local bg_id, bg_raw, fg_id, fg_raw = inner:match('<div id="(Bar%d+bg)" style="([^"]*)"><span id="(Bar%d+fg)" style="([^"]*)"></span></div>')
  if bg_id then
    local bg_style = parse_style(bg_raw)
    local fg_style = parse_style(fg_raw)
    local number = bg_id:match("Bar(%d+)bg")
    item.bar = {
      bg_id = bg_id,
      fg_id = fg_id,
      update_id = number and ("Bar" .. number .. "p") or bg_id,
      style = bg_style,
      fg_style = fg_style,
      geometry = style_geometry(bg_style),
      percent = css_number(fg_style, "width", 0),
      background = parse_gradient(bg_style.background, 0x202020),
      foreground = parse_gradient(fg_style.background, 0x00AA00),
      margin_top = css_number(bg_style, "margin-top", 0),
      border_width = math.max(0, math.floor(css_number(bg_style, "border", 0) + 0.5)),
      border_color = css_color(bg_style.border, 0),
      orientation = (css_number(bg_style, "height", 0) > css_number(bg_style, "width", 0))
        and "vertical" or "horizontal",
      reverse = tostring(fg_style.float or ""):lower() == "right"
        or fg_style.bottom == "0" or fg_style.bottom == "0px",
    }
  end

  add_item(model, page_index, item)
  return true
end

local function parse_canvas(model, page_index, line)
  local id, width, height, raw_style = line:match('<canvas id="([GA][pr][hc]%d+)" width="(%d+)px" height="(%d+)px" style="([^"]*)"></canvas>')
  if not id then
    id, width, height, raw_style = line:match('<canvas id="(Gph%d+)" width="(%d+)px" height="(%d+)px" style="([^"]*)"></canvas>')
  end
  if not id then
    id, width, height, raw_style = line:match('<canvas id="(Arc%d+)" width="(%d+)px" height="(%d+)px" style="([^"]*)"></canvas>')
  end
  if not id then
    return false
  end
  local style = parse_style(raw_style)
  local geometry = style_geometry(style)
  geometry.w = tonumber(width) or geometry.w
  geometry.h = tonumber(height) or geometry.h
  local kind = id:match("^Gph") and "graph" or "arc"
  add_item(model, page_index, {
    id = id,
    update_id = id .. "p",
    kind = kind,
    style = style,
    geometry = geometry,
    history = {},
    visible = style_visible(style),
    z_index = css_number(style, "z-index", nil),
  })
  return true
end

local function parse_image(model, page_index, line)
  local raw_style, tag = line:match('<div style="([^"]*)">(<img.-</?[^>]*>)</div>')
  if not raw_style then
    raw_style, tag = line:match('<div style="([^"]*)">(<img.-)></div>')
  end
  if not raw_style then
    return false
  end
  local src = tag and tag:match('src="([^"]+)"')
  if not src then
    return false
  end
  model.image_count = model.image_count + 1
  local style = parse_style(raw_style)
  local item_geometry = style_geometry(style)
  local width = tag:match('width%s*=%s*"?(%d+)')
  local height = tag:match('height%s*=%s*"?(%d+)')
  if tonumber(width) then item_geometry.w = tonumber(width) end
  if tonumber(height) then item_geometry.h = tonumber(height) end
  add_item(model, page_index, {
    id = "Image" .. tostring(model.image_count),
    kind = "image",
    src = html_decode(src),
    style = style,
    geometry = item_geometry,
    visible = style_visible(style),
    z_index = css_number(style, "z-index", nil),
    fit = (tonumber(width) or tonumber(height)) and "stretch" or "native",
  })
  return true
end

local function promote_generated_background(model)
  if model.background_image then return end
  -- BGIMG=1 is not identified in AIDA64's generated HTML. Its observable ABI
  -- is the first page item: an image forced to the complete preview rectangle.
  -- Promote only that exact shape/order so ordinary large foreground images
  -- keep their DOM stacking semantics.
  local page = model.pages[1]
  local item = page and page.items and page.items[1]
  local geometry = item and item.geometry or {}
  if not item or item.kind ~= "image" or item.order ~= 1
    or geometry.x ~= 0 or geometry.y ~= 0
    or geometry.w ~= 320 or geometry.h ~= 240 then
    return
  end
  table.remove(page.items, 1)
  model.items[item.id] = nil
  item.id = "BackgroundImage"
  item.is_background = true
  item.fit = "stretch"
  item.z_index = -2147483647
  model.background_image = item
end

local function parse_graph_call(model, line)
  if not line:find('DrawGraph("Gph', 1, true) then
    return
  end
  local raw = line:match("DrawGraph%((.*)%)")
  if not raw then
    return
  end
  local values = split_csv(raw)
  for i = 1, #values do values[i] = js_value(values[i]) end
  local id = values[1]
  local item = model.items[id]
  if not item or item.kind ~= "graph" or item.params then
    return
  end
  item.params = {
    graph_type = values[4] or "LG",
    step = tonumber(values[5]) or 1,
    thick = tonumber(values[6]) or 1,
    grid_density = tonumber(values[7]) or 10,
    min_value = tonumber(values[8]) or 0,
    max_value = tonumber(values[9]) or 100,
    autoscale = tonumber(values[10]) == 1,
    base_100 = tonumber(values[11]) == 1,
    show_background = tonumber(values[12]) == 1,
    background = css_color(values[13], model.background),
    show_frame = tonumber(values[14]) == 1,
    frame_color = css_color(values[15], 0x666666),
    show_grid = tonumber(values[16]) == 1,
    grid_color = css_color(values[17], 0x333333),
    graph_color = css_color(values[18], 0xFFFFFF),
    show_scale = tonumber(values[19]) == 1,
    font_family = values[20] or "",
    font_color = css_color(values[21], 0xFFFFFF),
    font_size = font_size(values[22], 8),
    font_style = values[23] or "normal",
    font_weight = values[25] or "normal",
    right_align = tonumber(values[26]) == 1,
  }
  item.grid_offset = tonumber(model.html:match("var gphgridofs" .. id:match("%d+") .. " = ([%-]?%d+);")) or 0
  item.max_points = tonumber(model.html:match("gpharray" .. id:match("%d+") .. "%.length > (%d+)")) or 49
end

local function parse_arc_call(model, line)
  if not line:find('DrawArcGauge("Arc', 1, true) then
    return
  end
  local raw = line:match("DrawArcGauge%((.*)%)")
  if not raw then
    return
  end
  local values = split_csv(raw)
  for i = 1, #values do values[i] = js_value(values[i]) end
  local id = values[1]
  local item = model.items[id]
  if not item or item.kind ~= "arc" or item.params then
    return
  end
  item.params = {
    thickness = tonumber(values[2]) or 4,
    start_angle = tonumber(values[3]) or 0,
    fill = tonumber(values[7]) == 1,
    fill_color = css_color(values[8], model.background),
    show_text = tonumber(values[9]) == 1,
    font_family = values[11] or "",
    font_color = css_color(values[12], 0xFFFFFF),
    font_size = font_size(values[13], 10),
    font_style = values[14] or "normal",
    font_weight = values[16] or "normal",
  }
end

function Layout.parse(html)
  if type(html) ~= "string" or html == "" then
    return nil, "empty layout"
  end
  local model = {
    html = html,
    background = css_color(html:match("background%-color:%s*(#[%x]+)"), 0x000000),
    pages = {},
    items = {},
    counts = {},
    item_count = 0,
    image_count = 0,
    active_page = 1,
  }
  model.background_image = parse_background_image(html)
  if model.background_image then
    model.image_count = 1
    model.item_count = 1
    model.counts.image = 1
  end
  local page_index = 1
  ensure_page(model, page_index)

  for line in html:gmatch("[^\r\n]+") do
    local remote_page = line:match('<div id="page(%d+)"')
    if remote_page then
      page_index = tonumber(remote_page) + 1
      ensure_page(model, page_index)
    elseif not parse_sensor(model, page_index, line)
      and not parse_label(model, page_index, line)
      and not parse_simple(model, page_index, line)
      and not parse_canvas(model, page_index, line)
      and not parse_image(model, page_index, line) then
      -- The rest of the document is AIDA64's renderer implementation.
    end
  end

  for line in html:gmatch("[^\r\n]+") do
    parse_graph_call(model, line)
    parse_arc_call(model, line)
  end

  promote_generated_background(model)

  -- AIDA normally relies on DOM order, but also permits explicit CSS z-index.
  -- Preserve source order inside each z-plane and keep the body background in
  -- its own compositor layer below every page item.
  for _, page in ipairs(model.pages) do
    table.sort(page.items, function(left, right)
      local left_z = tonumber(left.z_index) or 0
      local right_z = tonumber(right.z_index) or 0
      if left_z == right_z then return (left.order or 0) < (right.order or 0) end
      return left_z < right_z
    end)
  end

  model.page_count = #model.pages
  model.html = nil
  if model.item_count == 0 then
    return nil, "layout contains no supported RemoteSensor items"
  end
  return model
end

local function normalize_path(value, fallback)
  local path = trim(value)
  if path == "" then path = fallback or "/" end
  if path:sub(1, 1) ~= "/" then path = "/" .. path end
  return path
end

function Layout.base_url(config)
  return "http://" .. tostring(config.host or "127.0.0.1") .. ":" .. tostring(config.port or 80)
end

function Layout.url(config)
  return Layout.base_url(config) .. normalize_path(config.layout_path, "/")
end

function Layout.resource_url(config, src)
  local value = trim(src)
  if value:match("^https?://") then
    return value
  end
  if value:sub(1, 1) ~= "/" then
    value = "/" .. value
  end
  value = value:gsub(" ", "%%20")
  return Layout.base_url(config) .. value
end

function Layout.fetch(config, callback)
  if not http or not http.get then
    callback(false, nil, "HTTP module missing")
    return false
  end
  local headers = table.concat({
    "Accept: text/html,application/xhtml+xml",
    "Accept-Encoding: identity",
    "Cache-Control: no-cache",
    "Pragma: no-cache",
    "Connection: close",
    "",
    "",
  }, "\r\n")
  local ok, err = pcall(function()
    http.get(Layout.url(config), headers, function(code, body)
      if tonumber(code) ~= 200 then
        callback(false, nil, "layout HTTP " .. tostring(code))
        return
      end
      if type(body) ~= "string" or body == "" then
        callback(false, nil, "empty layout response")
        return
      end
      local max_bytes = tonumber(config.max_layout_bytes) or 196608
      if #body > max_bytes then
        callback(false, nil, "layout exceeds " .. tostring(max_bytes) .. " bytes")
        return
      end
      local model, parse_err = Layout.parse(body)
      if not model then
        callback(false, nil, parse_err)
        return
      end
      callback(true, model, nil)
    end)
  end)
  if not ok then
    callback(false, nil, tostring(err))
    return false
  end
  return true
end

Layout.html_decode = html_decode
Layout.parse_style = parse_style
Layout.css_color = css_color
Layout.split_csv = split_csv

return Layout
