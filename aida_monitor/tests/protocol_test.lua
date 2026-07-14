local Layout = dofile("aida_monitor/package/aida_layout.lua")
local AidaClient = dofile("aida_monitor/package/aida_client.lua")
local Pager = dofile("aida_monitor/package/aida_pager.lua")

local html = dofile("aida_monitor/tests/fixtures/remotesensor-layout.lua")

local model, err = Layout.parse(html)
assert(model, err)
assert(model.background == 0x101010, "background")
assert(model.page_count == 2, "page count")
assert(model.item_count == 9, "item count: " .. tostring(model.item_count))
assert(model.counts.label == 2, "labels")
assert(model.counts.image == 1, "images")
assert(model.counts.sensor == 1, "sensors")
assert(model.counts.graph == 3, "graphs")
assert(model.counts.arc == 1, "arcs")
assert(model.counts.simple == 1, "simple")
assert(model.items.Gph4.params.graph_type == "LG", "line graph")
assert(model.items.Gph5.params.graph_type == "AG", "area graph")
assert(model.items.Gph6.params.graph_type == "HG", "hist graph")
assert(model.items.Arc7.params.thickness == 10, "arc thickness")
assert(model.items.Image1.src == "probe.png", "image source")
assert(model.items.Image1.geometry.w == 16 and model.items.Image1.geometry.h == 16, "image display size")
assert(model.items.Label1.text_style.font.size == 16, "point size converted to pixels")
assert(model.items.Label1.text_style.font.bold and model.items.Label1.text_style.font.italic, "font styles")
assert(model.items.Label1.text_style.underline and model.items.Label1.text_style.strike, "decorations")
assert(model.items.Label1.text_style.shadow.x == 2 and model.items.Label1.text_style.shadow.blur == 1, "shadow")
assert(model.items.Gph4.params.font_size == 11, "graph point size converted to pixels")

local layered = Layout.parse([=[<html><head><style>body {
background-color:#010203; background-image:url("wall paper.png") }</style></head><body>
<span id="Label2" style="position:absolute;left:0;top:0;z-index:5">TOP</span>
<span id="Label1" style="position:absolute;left:0;top:0;z-index:-1">BOTTOM</span>
</body></html>]=])
assert(layered and layered.background_image, "CSS body background image parsed")
assert(layered.background_image.src == "wall paper.png", "background URL decoded")
assert(layered.background_image.fit == "stretch", "background uses full-screen stretch")
assert(layered.background_image.geometry.w == 320 and layered.background_image.geometry.h == 240,
  "background is normalized to screen dimensions")
assert(layered.pages[1].items[1].id == "Label1" and layered.pages[1].items[2].id == "Label2",
  "z-index establishes stable page layers")

local generated_background = Layout.parse([=[<html><style>body { background-color:#000 }</style><body>
<div id="page0">
<div style="position:absolute; left:0px; top:0px"><img width=320 height=240 src="background.png"></div>
<span id="Simple2" style="position:absolute; left:0; top:0">LIVE</span>
<div style="position:absolute; left:200px; top:0px"><img width=60 height=60 src="foreground.gif"></div>
</div></body></html>]=])
assert(generated_background and generated_background.background_image, "generated BGIMG promoted")
assert(generated_background.background_image.src == "background.png"
  and generated_background.background_image.page == 1, "generated background retains page scope")
assert(generated_background.items.Image1 == nil and generated_background.items.Image2,
  "foreground image remains a normal page layer")
assert(#generated_background.pages[1].items == 2
  and generated_background.pages[1].items[2].id == "Image2", "background removed from foreground DOM")

local nested_sensor = Layout.parse([=[<html><style>body { background-color:#000000 }</style><body>
<div id="SI12" style="position:absolute; left:10px; top:210px; width:200px"><div id="Bar12bg" style="position:absolute; left:0px; width:100px; height:15px; background:#333333"><span id="Bar12fg" style="display:block; width:50%; height:100%; background:#00DF00"></span></div><div style="position:absolute; left:0; top:0"><div style="width:200px; height:15px; display:table-cell"><div style="float:left; font-size:8pt; color:#00AAAA">GPU1&nbsp;显存频率</div><div style="width:40px; font-size:8pt; color:#00AAAA; float:right">&nbsp;MHz</div><div id="SIV12" style="font-size:8pt; color:#FFFFFF; float:right">15201</div></div></div></div>
</body></html>]=])
assert(nested_sensor and nested_sensor.items.SI12, "nested SensorItem parsed")
assert(nested_sensor.items.SI12.label.text_style.text == "GPU1 显存频率", "nested sensor label")
assert(nested_sensor.items.SI12.value.text_style.text == "15201", "nested sensor value")
assert(nested_sensor.items.SI12.unit.text_style.text == " MHz", "nested sensor unit")
assert(nested_sensor.items.SI12.bar.percent == 50, "nested sensor bar")

local payload = "Page0{|}SIV3|42{|}Bar3p|42|#202020,#151515|#00FF00,#00AA00{|}Gph4p|42|{|}Gph5p|42|{|}Gph6p|42|{|}Arc7p|42|42|#202020|#00FF00{|}Simple11|CPU Temp 48&deg;C{|}"
local sample = AidaClient.parse_remote_payload(payload)
assert(sample.page == 1, "active page")
assert(#sample.updates == 7, "update count: " .. tostring(#sample.updates))
assert(sample.updates[1].id == "SIV3" and sample.updates[1].text == "42", "value update")
assert(sample.updates[2].kind == "bar" and sample.updates[2].percent == 42, "bar update")
assert(sample.updates[6].kind == "arc" and sample.updates[6].active_color == 0x00FF00, "arc update")
assert(sample.updates[7].text == "CPU Temp 48°C", "entity decode")
assert(AidaClient.parse_remote_payload("ReLoad").control == "ReLoad", "reload control")
assert(AidaClient.parse_remote_payload("Page1{|}Simple11|OK{|}").page == 2, "second page")
local hidden_sample = AidaClient.parse_remote_payload("Simple11||{|}Gph4p||{|}Arc7p||||{|}")
assert(hidden_sample.updates[1].visible == false, "empty text hides RemoteSensor item")
assert(hidden_sample.updates[2].kind == "graph_clear", "empty graph update clears canvas")
assert(hidden_sample.updates[3].visible == false, "empty arc text hides gauge")

local pager = Pager.new({ tilt_page_cooldown_ms = 1000 })
local page, changed = pager:step(1, 3, 1, 0)
assert(changed and page == 2, "right tilt advances one page")
page, changed = pager:step(page, 3, 1, 50)
assert(not changed and page == 2, "event burst is absorbed by cooldown")
page, changed = pager:step(page, 3, -1, 1000)
assert(changed and page == 1, "left tilt returns one page after cooldown")
page, changed = pager:step(page, 3, -1, 2000)
assert(changed and page == 3, "tilt paging wraps at the edge")
assert(pager:accept_remote(1, 3) == nil, "SSE Page does not override local tilt page")
assert(pager:restore(2) == 2, "local page is clamped across layout reload")

local captured_vector_options = nil
package.preload["aida_font_test"] = function()
  return {
    open = function(path) return path == "/font.ttf" end,
    render = function(_, width, height, _, _, _, _, options)
      captured_vector_options = options
      return string.rep("\0", width * height * 2)
    end,
    stats = function() return { loaded = true, engine = "stb_truetype" } end,
  }
end
local VectorFont = dofile("aida_monitor/package/aida_vector_font.lua")
local vector_wrapper = VectorFont.new({ vector_font_module = "aida_font_test", vector_font_path = "/font.ttf" })
assert(vector_wrapper.ready, vector_wrapper.error)
local vector_buffer = vector_wrapper:render("中文", 32, 18, model.items.Label1.text_style, 0, 0x00FF00)
assert(#vector_buffer == 32 * 18 * 2, "vector wrapper buffer")
assert(captured_vector_options.bold and captured_vector_options.italic, "vector wrapper face styles")
assert(captured_vector_options.underline and captured_vector_options.strike, "vector wrapper decorations")
assert(captured_vector_options.shadow_dx == 2 and captured_vector_options.shadow_blur == 1, "vector wrapper shadow")
assert(captured_vector_options.subpixel == 1, "RGB subpixel mode is forwarded")

local selected_paths = {}
package.preload["aida_font_select_test"] = function()
  return {
    open = function(path)
      selected_paths[#selected_paths + 1] = path
      if path == "/broken.ttf" then return false, "broken font" end
      return true
    end,
    render = function(_, width, height) return string.rep("\0", width * height * 2) end,
    stats = function() return { loaded = true, engine = "stb_truetype" } end,
  }
end
local font_select_config = {
  vector_font_module = "aida_font_select_test",
  vector_font_family = "Tahoma",
  vector_font_fallback_family = "AIDA Noto Sans SC",
  vector_font_default_path = "/default.ttf",
  vector_font_custom_family = "Tahoma",
  vector_font_custom_path = "/custom.ttf",
}
local font_select_layout = Layout.parse([=[<html><style>body { background-color:#000 }</style><body>
<span id="Label1" style="position:absolute;left:0;top:0;font-family:Tahoma">FONT</span>
</body></html>]=])
local font_selector = VectorFont.new(font_select_config)
assert(font_selector:select_for_layout(font_select_layout, font_select_config), "uploaded font selected")
assert(font_selector.source == "uploaded" and font_selector.match
  and font_selector.family == "Tahoma" and font_selector.face == "Tahoma",
  "layout Tahoma family matches uploaded TTF")
assert(selected_paths[#selected_paths] == "/custom.ttf", "custom TTF opened after match")
local unmatched_layout = Layout.parse([=[<html><style>body { background-color:#000 }</style><body>
<span id="Label1" style="position:absolute;left:0;top:0;font-family:'Noto Sans SC'">FONT</span>
</body></html>]=])
assert(font_selector:select_for_layout(unmatched_layout, font_select_config), "default font selected")
assert(font_selector.source == "default" and not font_selector.match
  and font_selector.family == "Tahoma" and font_selector.face == "AIDA Noto Sans SC"
  and selected_paths[#selected_paths] == "/default.ttf",
  "unmatched family preserves Tahoma semantics with bundled fallback face")
font_select_config.vector_font_custom_path = "/broken.ttf"
assert(font_selector:select_for_layout(font_select_layout, font_select_config), "broken custom falls back")
assert(font_selector.source == "default" and font_selector.family == "Tahoma"
  and font_selector.face == "AIDA Noto Sans SC"
  and font_selector.selection_error:find("broken font", 1, true),
  "custom load failure is reported while default remains available")

local next_object = 10
local canvas_formats = {}
local function object()
  next_object = next_object + 1
  return next_object
end
LV_PART_MAIN, LV_STATE_DEFAULT = 0, 0
LV_OBJ_FLAG_SCROLLABLE, LV_OBJ_FLAG_HIDDEN = 1, 2
LV_IMG_CF_TRUE_COLOR = 1
LV_IMG_CF_TRUE_COLOR_CHROMA_KEYED = 2
LV_COLOR_CHROMA_KEY = 0x00FF00
lv_scr_act = function() return 1 end
lv_obj_create = function() return object() end
lv_label_create = function() return object() end
lv_canvas_create = function(_, _, _, format)
  canvas_formats[#canvas_formats + 1] = format
  return object()
end
lv_obj_clean = function() end
lv_obj_set_pos = function() end
lv_obj_set_size = function() end
lv_obj_set_width = function() end
lv_obj_set_style_bg_color = function() end
lv_obj_set_style_bg_opa = function() end
lv_obj_set_style_border_width = function() end
lv_obj_set_style_radius = function() end
lv_obj_set_style_pad_all = function() end
lv_obj_set_style_text_color = function() end
lv_obj_set_style_text_opa = function() end
lv_obj_set_style_text_font = function() end
lv_obj_set_style_text_align = function() end
lv_obj_set_style_bg_grad_color = function() end
lv_obj_set_style_bg_grad_dir = function() end
lv_obj_set_style_bg_main_stop = function() end
lv_obj_set_style_bg_grad_stop = function() end
lv_obj_clear_flag = function() end
lv_obj_add_flag = function() end
lv_label_set_text = function() end
lv_canvas_fill_bg = function() end
lv_canvas_draw_rect = function() end
lv_canvas_draw_line = function() end
lv_canvas_draw_text = function() end
lv_canvas_draw_arc = function() end
local canvas_frame_begin_count = 0
local canvas_frame_end_count = 0
lv_canvas_frame_begin = function()
  canvas_frame_begin_count = canvas_frame_begin_count + 1
end
lv_canvas_frame_end = function()
  canvas_frame_end_count = canvas_frame_end_count + 1
end
lv_canvas_blit_rgb565 = function(_, _, _, width, height, data)
  assert(#data == width * height * 2, "vector RGB565 buffer")
end

local vector_render_count = 0
local vector_render_transparent_count = 0
local software_texts = {}
local software_ops = {}
local software_clear_count = 0
local software_copy_count = 0
local software_flush_count = 0
local vector_font = {
  ready = true,
  surface_ready = true,
  error = "",
  render = function(_, _, width, height, _, _, _, opaque)
    vector_render_count = vector_render_count + 1
    if not opaque then vector_render_transparent_count = vector_render_transparent_count + 1 end
    return string.rep("\0", width * height * 2)
  end,
  measure = function(_, text, style)
    return math.max(1, math.floor(#tostring(text or "") * (style.font.size or 12) * 0.6))
  end,
  surface_create = function() return 1 end,
  surface_free = function() return true end,
  surface_clear = function()
    software_clear_count = software_clear_count + 1
    return true
  end,
  surface_copy = function()
    software_copy_count = software_copy_count + 1
    return true
  end,
  surface_image = function() return true end,
  surface_rect = function(_, _, x, y, width, height, color, opacity)
    software_ops[#software_ops + 1] = {
      kind = "rect", x = x, y = y, width = width, height = height,
      color = color, opacity = opacity,
    }
    return true
  end,
  surface_circle = function() return true end,
  surface_line = function(_, _, x1, y1, x2, y2, color, opacity, width)
    software_ops[#software_ops + 1] = {
      kind = "line", x1 = x1, y1 = y1, x2 = x2, y2 = y2,
      color = color, opacity = opacity, width = width,
    }
    return true
  end,
  surface_arc = function(_, _, cx, cy, radius, start_angle, end_angle, color, opacity, width)
    software_ops[#software_ops + 1] = {
      kind = "arc", cx = cx, cy = cy, radius = radius,
      start_angle = start_angle, end_angle = end_angle,
      color = color, opacity = opacity, width = width,
    }
    return true
  end,
  surface_text = function(_, _, x, y, width, height, text)
    vector_render_count = vector_render_count + 1
    software_texts[#software_texts + 1] = {
      x = x, y = y, width = width, height = height, text = tostring(text),
    }
    software_ops[#software_ops + 1] = { kind = "text", x = x, y = y, text = tostring(text) }
    return true
  end,
  surface_pixels = function()
    software_flush_count = software_flush_count + 1
    return string.rep("\0", 320 * 240 * 2)
  end,
  stats = function()
    return { loaded = true, engine = "stb_truetype", font_bytes = 2432892,
      cache_bytes = 4096, cache_entries = 8, renders = vector_render_count,
      face = "AIDA Noto Sans SC", surface_bytes = 320 * 240 * 2,
      surface_flushes = software_flush_count }
  end,
}

local Renderer = dofile("aida_monitor/package/aida_renderer.lua")
local png40 = "\137PNG\13\10\26\10" .. string.char(0, 0, 0, 13) .. "IHDR"
  .. string.char(0, 0, 0, 40, 0, 0, 0, 40)
local png_kind, png_width, png_height = Renderer.image_info(png40)
assert(png_kind == "png" and png_width == 40 and png_height == 40, "PNG dimensions")
local png_large = "\137PNG\13\10\26\10" .. string.char(0, 0, 0, 13) .. "IHDR"
  .. string.char(0, 0, 8, 112, 0, 0, 8, 108)
local _, large_width, large_height = Renderer.image_info(png_large)
assert(large_width == 2160 and large_height == 2156, "large PNG dimensions")
local renderer = Renderer.new({ config = { history_points = 49,
  vector_font_family = "Tahoma", vector_font_fallback_family = "AIDA Noto Sans SC" },
  layout = model, root = 1,
  vector_font = vector_font })
renderer:build()
assert(vector_render_count > 0, "vector text rendered")
assert(vector_render_transparent_count == 0, "renderer avoids unsupported keyed text canvases")
for _, format in ipairs(canvas_formats) do
  assert(format == LV_IMG_CF_TRUE_COLOR, "renderer uses the proven true-color canvas path")
end
assert(canvas_frame_begin_count > 0 and canvas_frame_end_count == canvas_frame_begin_count,
  "standalone vector canvases commit frames")
assert(renderer:snapshot().compositor == "rgb565-a8", "software alpha compositor")
assert(renderer:snapshot().surface_bytes == 320 * 240 * 2, "software surface size")
renderer.background_surface = 2
renderer.background_ready = true
assert(renderer:software_render_page(1) and software_copy_count == 1,
  "background surface is copied below dynamic items")
renderer.background_surface = nil
renderer.background_ready = false
renderer:apply_sample(sample)
assert(renderer.active_page == 1, "renderer first page")
assert(#renderer.views.Gph4.item.history == 1, "graph history")
renderer:apply_sample({ updates = {
  { id = "Gph4", kind = "graph", value = 55 },
  { id = "Gph6", kind = "graph", value = 55 },
} })
renderer:apply_sample({ updates = {
  { id = "Gph4", kind = "graph", value = 70 },
  { id = "Gph6", kind = "graph", value = 70 },
} })
local line_reaches_graph_right = false
local line_uses_aida_spacing = false
local histogram_latest = false
local histogram_previous = false
local exact_arc_geometry = false
for _, operation in ipairs(software_ops) do
  if operation.kind == "line" and operation.color == 0x00FFFF then
    if operation.x1 == 98 then line_reaches_graph_right = true end
    if math.abs(operation.x1 - operation.x2) == 2 then line_uses_aida_spacing = true end
  elseif operation.kind == "rect" and operation.color == 0xFF00FF and operation.width == 2 then
    if operation.x == 305 then histogram_latest = true end
    if operation.x == 302 then histogram_previous = true end
  elseif operation.kind == "arc" and operation.color == 0x00FF00
    and operation.cx == 160 and operation.cy == 181 and operation.radius == 39 then
    exact_arc_geometry = true
  end
end
assert(line_reaches_graph_right, "graph scale does not reserve or black out plot width")
assert(line_uses_aida_spacing, "line graph uses AIDA64 step + 1 spacing")
assert(histogram_latest and histogram_previous, "histogram uses thick + step spacing")
assert(exact_arc_geometry, "arc uses AIDA64 width-derived circular geometry")
renderer:apply_sample(AidaClient.parse_remote_payload("Page1{|}Simple11|OK{|}"))
assert(renderer.active_page == 2, "renderer second page")
assert(renderer:snapshot().items == 9, "renderer snapshot")
assert(renderer:snapshot().font == "Tahoma", "renderer logical font snapshot")
assert(renderer:snapshot().font_face == "AIDA Noto Sans SC", "renderer physical font face snapshot")
assert(renderer:snapshot().font_engine == "stb_truetype", "renderer font engine")
assert(software_clear_count >= 3 and software_flush_count >= 3, "software pages rerender and flush")
local saw_sensor_value = false
local saw_sensor_label = false
local saw_sensor_unit = false
for _, rendered in ipairs(software_texts) do
  if rendered.text == "42" then saw_sensor_value = true end
  if rendered.text == "CPU" then saw_sensor_label = true end
  if rendered.text == "%" then saw_sensor_unit = true end
end
assert(saw_sensor_value, "sensor value alpha-composited into page surface")
assert(saw_sensor_label, "sensor label alpha-composited into page surface")
assert(saw_sensor_unit, "sensor unit alpha-composited into page surface")
local sensor_bar_op, sensor_label_op
for index, operation in ipairs(software_ops) do
  if operation.kind == "rect" and operation.x == 4 and operation.y == 47
    and operation.width == 145 and operation.height == 1 then sensor_bar_op = sensor_bar_op or index end
  if operation.kind == "text" and operation.text == "CPU" then sensor_label_op = sensor_label_op or index end
end
assert(sensor_bar_op and sensor_label_op and sensor_bar_op < sensor_label_op,
  "SensorItem bar is composited before its text row")

local routes = {}
local saved_config = ""
local virtual_files = {}
local virtual_dirs = { ["/sd/apps/aida_monitor/font"] = true }
file = {
  putcontents = function(path, body) saved_config = body virtual_files[path] = body return true end,
  stat = function(path)
    if virtual_dirs[path] then return { is_dir = true, size = 0 } end
    local body = virtual_files[path]
    if body == nil then return nil end
    return { is_dir = false, size = #body }
  end,
  mkdir = function(path) virtual_dirs[path] = true return true end,
  remove = function(path) virtual_files[path] = nil virtual_dirs[path] = nil return true end,
  rename = function(from, to)
    if virtual_files[from] == nil then return false end
    virtual_files[to], virtual_files[from] = virtual_files[from], nil
    return true
  end,
  open = function(path, mode)
    if mode == "w+" then virtual_files[path] = ""
    elseif mode == "a+" and virtual_files[path] == nil then return nil
    elseif mode == "r" and virtual_files[path] == nil then return nil end
    local pos = mode == "a+" and (#virtual_files[path] + 1) or 1
    return {
      write = function(_, chunk)
        local body = virtual_files[path] or ""
        if pos > #body then body = body .. chunk
        else body = body:sub(1, pos - 1) .. chunk .. body:sub(pos + #chunk) end
        virtual_files[path], pos = body, pos + #chunk
        return true
      end,
      read = function(_, size)
        local body = virtual_files[path] or ""
        if pos > #body then return nil end
        local chunk = body:sub(pos, pos + size - 1)
        pos = pos + #chunk
        return chunk
      end,
      flush = function() return true end,
      close = function() return true end,
    }
  end,
}
httpd = {
  GET = "GET",
  PUT = "PUT",
  start = function() end,
  dynamic = function(_, route, handler) routes[route] = handler end,
  unregister = function() end,
}
local Web = dofile("aida_monitor/package/web.lua")
local web = Web.new({
  config = { host = "192.168.0.232", port = 9999,
    vector_font_family = "Tahoma", vector_font_fallback_family = "AIDA Noto Sans SC" },
  config_path = "/tmp/config.lua",
  route_base = "/aida_monitor",
  state = function() return {} end,
})
web:start()
local page = routes["/aida_monitor/"]()
assert(page.body:find("Tahoma", 1, true), "AIDA64 default font guidance")
assert(page.body:find("AIDA Noto Sans SC", 1, true), "vector font guidance")
assert(page.body:find("上传并匹配 TTF", 1, true), "font upload control")
assert(page.body:find("下载内置中文字体", 1, true), "font download")
assert(page.body:find("下载示例布局模板", 1, true), "layout template download")
assert(page.body:find("holo%-aida%-template%.txt"), "template uses firmware-supported static MIME")
assert(page.body:find("子像素排列", 1, true), "subpixel configuration")
assert(page.body:find("翻页冷却 / MS", 1, true), "tilt page cooldown configuration")
assert(routes["/aida_monitor/api/font"], "font upload route registered within handler budget")
local saved = web:save({ query = "host=192.168.0.232&port=9999&layout_path=%2F&path=%2Fsse" })
assert(saved.status == "200 OK", "web config save")
assert(saved_config:find('config.vector_font_family = "Tahoma"', 1, true),
  "AIDA64 default family persisted")
assert(saved_config:find('config.vector_font_fallback_family = "AIDA Noto Sans SC"', 1, true),
  "physical fallback family persisted")
assert(saved_config:find("aida_font.so", 1, true), "vector module persisted")
assert(saved_config:find('config.font_subpixel = "rgb"', 1, true), "subpixel mode persisted")
assert(saved_config:find("config.tilt_page_cooldown_ms = 1000", 1, true),
  "tilt page cooldown persisted")
assert(not saved_config:find("config.font =", 1, true), "legacy font selection removed")

local ttf_payload = "\0\1\0\0" .. string.rep("\0", 1020)
local body_sent = false
local uploaded = web:upload_font({
  query = "offset=0&total=1024&name=tahoma.ttf&family=Tahoma",
  getbody = function()
    if body_sent then return nil end
    body_sent = true
    return ttf_payload
  end,
})
assert(uploaded.status == "200 OK", "font upload accepted")
assert(web.config.vector_font_custom_family == "Tahoma", "uploaded Tahoma family configured")
assert(virtual_files["/sd/apps/aida_monitor/font/uploaded.ttf"] == ttf_payload,
  "uploaded TTF atomically installed")
assert(saved_config:find('config.vector_font_custom_family = "Tahoma"', 1, true),
  "uploaded font match persisted")
local restored = web:reset_font()
assert(restored.status == "200 OK" and web.config.vector_font_custom_family == "",
  "default font can be restored")
assert(virtual_files["/sd/apps/aida_monitor/font/uploaded.ttf"] == nil,
  "restoring default removes uploaded font")

print("RemoteSensor protocol tests passed")
