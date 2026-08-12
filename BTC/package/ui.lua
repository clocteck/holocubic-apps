local Ui = {}

local MAIN_STYLE = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
local FONT_10 = rawget(_G, "LV_FONT_MONTSERRAT_10") or 10
local FONT_12 = rawget(_G, "LV_FONT_MONTSERRAT_12") or 12
local FONT_16 = rawget(_G, "LV_FONT_MONTSERRAT_16") or 16
local FONT_28 = rawget(_G, "LV_FONT_MONTSERRAT_28") or 28
local ALIGN_RIGHT = rawget(_G, "LV_TEXT_ALIGN_RIGHT") or 2
local ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1
local LONG_CLIP = rawget(_G, "LV_LABEL_LONG_CLIP") or 2
local CANVAS_FMT = rawget(_G, "LV_IMG_CF_TRUE_COLOR") or rawget(_G, "CANVAS_FMT_TRUE_COLOR")
local CANVAS_FMT_TEXT = CANVAS_FMT and tostring(CANVAS_FMT) or "default"

local C = {
  bg = 0x000000,
  panel = 0x101212,
  panel_hi = 0x171A1A,
  border = 0x2B3330,
  grid = 0x24302B,
  text = 0xFFFFFF,
  sub = 0xAEBAB5,
  dim = 0x6F7B76,
  up = 0x22C55E,
  down = 0xEF4444,
  warn = 0xF59E0B,
  line = 0x38BDF8,
  wick = 0x8A9490,
  menu_selected = 0x12384A,
}

local W = 320
local H = 240
local CHART_X = 12
local CHART_Y = 97
local CHART_W = 296
local CHART_H = 112
local CANVAS_W = 292
local CANVAS_H = 108

-- 设置标签通用文本样式。
local function label_style(id, font, color, width, align)
  if not id then
    return
  end
  pcall(function() lv_obj_set_style_text_font(id, font, MAIN_STYLE) end)
  pcall(function() lv_obj_set_style_text_color(id, color, MAIN_STYLE) end)
  pcall(function() lv_obj_set_width(id, width) end)
  if lv_label_set_long_mode then
    pcall(function() lv_label_set_long_mode(id, LONG_CLIP) end)
  end
  if align and lv_obj_set_style_text_align then
    pcall(function() lv_obj_set_style_text_align(id, align, MAIN_STYLE) end)
  end
end

-- 安全设置标签文本。
local function set_text(id, text)
  if id then
    pcall(function() lv_label_set_text(id, tostring(text or "")) end)
  end
end

-- 安全设置标签颜色。
local function set_color(id, color)
  if id then
    pcall(function() lv_obj_set_style_text_color(id, color, MAIN_STYLE) end)
  end
end

local function set_hidden(id, hidden)
  if not id then return end
  local flag = rawget(_G, "LV_OBJ_FLAG_HIDDEN")
  if flag and lv_obj_add_flag and lv_obj_clear_flag then
    pcall(function()
      if hidden then lv_obj_add_flag(id, flag) else lv_obj_clear_flag(id, flag) end
    end)
  elseif lv_obj_set_hidden then
    pcall(function() lv_obj_set_hidden(id, hidden) end)
  end
end

-- 判断字体文件是否存在，优先加载较小的中文字体，避免标的名称缺字。
local function path_exists(path)
  if not path or path == "" then
    return false
  end
  if file and file.exists then
    local ok, ret = pcall(function() return file.exists(path) end)
    if ok then return ret and true or false end
  end
  if file and file.stat then
    local ok, st = pcall(function() return file.stat(path) end)
    return ok and st ~= nil
  end
  return false
end

-- 启动页已显示后，仅加载当前语言所需的字库。
local function load_ui_font(path)
  if not lv_font_load then
    return nil, ""
  end
  if path and path_exists(path) then
    local ok, handle = pcall(function() return lv_font_load(path) end)
    if ok and type(handle) == "number" and handle > 0 then
      return handle, path
    end
  end
  return nil, ""
end

local last_draw_error = ""
local draw_error_seen = {}

-- 绘图 pcall 失败时打印到串口，避免静默吞掉折线错误。
local function draw_call(name, fn)
  local ok, err = pcall(fn)
  if not ok then
    last_draw_error = tostring(name) .. " " .. tostring(err)
    if not draw_error_seen[last_draw_error] then
      draw_error_seen[last_draw_error] = true
      print("[btc_ui] draw " .. tostring(name) .. " failed: " .. tostring(err))
    end
    return false
  end
  return true
end

local missing_draw_api = {}
local function draw_missing(name)
  if not missing_draw_api[name] then
    missing_draw_api[name] = true
    print("[btc_ui] draw api missing: " .. tostring(name))
  end
  last_draw_error = "missing " .. tostring(name)
  return false
end

-- 为深色面板设置统一样式。
local function style_panel(id)
  if not id then
    return
  end
  pcall(function() lv_obj_set_style_bg_color(id, C.panel, MAIN_STYLE) end)
  pcall(function() lv_obj_set_style_bg_opa(id, 255, MAIN_STYLE) end)
  if lv_obj_set_style_bg_grad_color and lv_obj_set_style_bg_grad_dir then
    pcall(function() lv_obj_set_style_bg_grad_color(id, C.panel_hi, MAIN_STYLE) end)
    pcall(function() lv_obj_set_style_bg_grad_dir(id, LV_GRAD_DIR_VER, MAIN_STYLE) end)
  end
  pcall(function() lv_obj_set_style_border_width(id, 1, MAIN_STYLE) end)
  pcall(function() lv_obj_set_style_border_color(id, C.border, MAIN_STYLE) end)
  pcall(function() lv_obj_set_style_radius(id, 6, MAIN_STYLE) end)
  if lv_obj_set_style_pad_all then
    pcall(function() lv_obj_set_style_pad_all(id, 0, MAIN_STYLE) end)
  end
  if lv_obj_clear_flag then
    pcall(function() lv_obj_clear_flag(id, LV_OBJ_FLAG_SCROLLABLE) end)
  end
end

-- A 股和金银铜沿用红涨绿跌，币圈和美股沿用绿涨红跌。
local function red_up_market(snap)
  local group = snap and snap.active and snap.active.group
  return group == "ashare" or group == "metal" or group == "taiwan"
end

local function market_colors(red_up)
  if red_up then
    return C.down, C.up
  end
  return C.up, C.down
end

-- 根据状态 tone 和市场习惯取屏幕颜色。
local function tone_color(tone, red_up)
  if tone == "error" then
    return C.down
  elseif tone == "down" then
    local _, down_color = market_colors(red_up)
    return down_color
  elseif tone == "warn" then
    return C.warn
  elseif tone == "up" then
    local up_color = market_colors(red_up)
    return up_color
  end
  return C.sub
end

-- 开始 canvas 绘制帧，兼容不同函数名。
local function canvas_begin(id)
  local fn = rawget(_G, "lv_canvas_frame_begin") or rawget(_G, "lv_canvas_begin")
  if fn then
    return draw_call("canvas_begin", function() fn(id) end)
  end
  return false
end

-- 结束 canvas 绘制帧，必要时主动 invalidate。
local function canvas_end(id, explicit)
  local fn = rawget(_G, "lv_canvas_frame_end") or rawget(_G, "lv_canvas_end")
  if explicit and fn then
    return draw_call("canvas_end", function() fn(id) end)
  elseif lv_obj_invalidate then
    return draw_call("canvas_invalidate", function() lv_obj_invalidate(id) end)
  end
  return true
end

-- 填充 canvas 背景。
local function canvas_fill(id, color)
  local fn = rawget(_G, "lv_canvas_fill_bg") or rawget(_G, "lv_canvas_fill")
  if fn then
    return draw_call("canvas_fill", function() fn(id, color, 255) end)
  elseif lv_canvas_draw_rect then
    return draw_call("canvas_fill_rect", function() lv_canvas_draw_rect(id, 0, 0, CANVAS_W, CANVAS_H, color, 255) end)
  end
  return draw_missing("lv_canvas_fill_bg")
end

-- 绘制一条线段。
local function draw_line(id, x1, y1, x2, y2, color, opa, width)
  if lv_canvas_draw_line then
    return draw_call("line", function() lv_canvas_draw_line(id, x1, y1, x2, y2, color, opa or 255, width or 1) end)
  end
  return draw_missing("lv_canvas_draw_line")
end

-- 绘制小矩形，主要用于最新点。
local function draw_rect(id, x, y, w, h, color, opa)
  if lv_canvas_draw_rect then
    return draw_call("rect", function() lv_canvas_draw_rect(id, x, y, w, h, color, opa or 255) end)
  end
  return draw_missing("lv_canvas_draw_rect")
end

-- 绘制 canvas 文本。
local function draw_text(id, x, y, w, text, color, align, font)
  if lv_canvas_draw_text then
    return draw_call("text", function()
      lv_canvas_draw_text(id, x, y, w, tostring(text or ""), color, 255, align or ALIGN_CENTER, font or 12)
    end)
  end
  return draw_missing("lv_canvas_draw_text")
end

-- 把数值映射到图表 y 坐标。
local function chart_y(value, minp, maxp, top, height)
  if maxp <= minp then
    return top + math.floor(height / 2)
  end
  local ratio = (maxp - value) / (maxp - minp)
  if ratio < 0 then ratio = 0 end
  if ratio > 1 then ratio = 1 end
  return top + math.floor(ratio * (height - 1) + 0.5)
end

-- 返回图表模式短文本，保证小屏 footer 不拥挤。
local function mode_text(mode)
  if mode == "candle" then
    return "K"
  end
  return "Line"
end

local function ma_text(period)
  period = tonumber(period) or 0
  if period == 10 or period == 20 then
    return "MA" .. tostring(period)
  end
  return ""
end

local function chart_x(points, index, left, width)
  if #points <= 1 then
    return left + math.floor(width / 2)
  end
  local first = tonumber(points[1] and points[1].time_value)
  local last = tonumber(points[#points] and points[#points].time_value)
  local current = tonumber(points[index] and points[index].time_value)
  local ratio
  if first and last and current and last > first then
    ratio = (current - first) / (last - first)
  else
    ratio = (index - 1) / (#points - 1)
  end
  if ratio < 0 then ratio = 0 end
  if ratio > 1 then ratio = 1 end
  return left + math.floor(ratio * (width - 1) + 0.5)
end

-- 绘制收盘折线。
local function draw_line_series(id, points, minp, maxp, left, top, width, height, tone, red_up)
  local color = tone_color(tone, red_up)
  if tone ~= "up" and tone ~= "down" then
    color = C.line
  end

  local ok = true
  local prev_x, prev_y
  for i = 1, #points do
    local close = tonumber(points[i].close)
    if close then
      local x = chart_x(points, i, left, width)
      local y = chart_y(close, minp, maxp, top, height)
      if prev_x then
        ok = draw_line(id, prev_x, prev_y, x, y, color, 255, 2) and ok
      end
      prev_x, prev_y = x, y
    end
  end

  if prev_x and prev_y then
    ok = draw_rect(id, prev_x - 2, prev_y - 2, 5, 5, color, 255) and ok
  end
  return ok
end

-- 绘制收盘价均线，Web 选择 MA10/MA20 后设备端同步显示。
local function draw_ma_series(id, points, period, minp, maxp, left, top, width, height)
  period = tonumber(period) or 0
  if period < 2 or #points < period then
    return true
  end

  local ok = true
  local prev_x, prev_y
  for i = period, #points do
    local sum = 0
    local count = 0
    for j = i - period + 1, i do
      local close = tonumber(points[j] and points[j].close)
      if close then
        sum = sum + close
        count = count + 1
      end
    end

    if count == period then
      local x = chart_x(points, i, left, width)
      local y = chart_y(sum / period, minp, maxp, top, height)
      if prev_x then
        ok = draw_line(id, prev_x, prev_y, x, y, C.line, 255, 1) and ok
      end
      prev_x, prev_y = x, y
    else
      prev_x, prev_y = nil, nil
    end
  end
  return ok
end

-- 绘制 K 线，使用整数坐标避免 canvas 绑定吃到小数。
local function draw_candles(id, points, minp, maxp, left, top, width, height, red_up)
  local n = #points
  if n < 1 then
    return true
  end

  local ok = true
  local up_color, down_color = market_colors(red_up)
  local step = width / n
  local body_w = math.floor(step * 0.62)
  if body_w < 2 then body_w = 2 end
  if body_w > 7 then body_w = 7 end

  for i = 1, n do
    local c = points[i]
    local close = tonumber(c.close)
    local open_p = tonumber(c.open) or close
    local high_p = tonumber(c.high) or math.max(open_p or 0, close or 0)
    local low_p = tonumber(c.low) or math.min(open_p or 0, close or 0)

    if open_p and high_p and low_p and close then
      local cx = chart_x(points, i, left, width)
      local y_open = chart_y(open_p, minp, maxp, top, height)
      local y_close = chart_y(close, minp, maxp, top, height)
      local y_high = chart_y(high_p, minp, maxp, top, height)
      local y_low = chart_y(low_p, minp, maxp, top, height)

      ok = draw_line(id, cx, y_high, cx, y_low, C.wick, 210, 1) and ok

      local body_top = math.min(y_open, y_close)
      local body_bottom = math.max(y_open, y_close)
      local body_h = body_bottom - body_top + 1
      if body_h < 1 then body_h = 1 end

      local color = up_color
      if close < open_p then
        color = down_color
      end

      local x = cx - math.floor(body_w / 2)
      local w = body_w
      if x < left then
        w = w - (left - x)
        x = left
      end
      if x + w > left + width then
        w = left + width - x
      end
      if w > 0 then
        ok = draw_rect(id, x, body_top, w, body_h, color, 245) and ok
      end
    end
  end
  return ok
end

-- 图表整体 Lua 错误也打印出来，避免 render 静默跳过折线。
local function chart_error_handler(err)
  err = tostring(err)
  local log_key = "chart " .. err
  if debug and debug.traceback then
    local ok, trace = pcall(function() return debug.traceback(err, 2) end)
    if ok and trace then
      if not draw_error_seen[log_key] then
        draw_error_seen[log_key] = true
        print("[btc_ui] chart redraw error: " .. tostring(trace))
      end
      return trace
    end
  end
  if not draw_error_seen[log_key] then
    draw_error_seen[log_key] = true
    print("[btc_ui] chart redraw error: " .. err)
  end
  return err
end

-- 构造 UI 实例。
function Ui.new(backend, i18n)
  local self = {
    backend = backend,
    i18n = i18n,
    root = nil,
    bg = nil,
    title = nil,
    status = nil,
    price = nil,
    change = nil,
    detail = nil,
    updated = nil,
    chart_card = nil,
    chart = nil,
    footer_left = nil,
    footer_right = nil,
    ui_font = nil,
    ui_font_path = "",
    last_chart_key = "",
    menu_overlay = nil,
    menu_title = nil,
    menu_page = nil,
    menu_hint = nil,
    menu_rows = {},
    menu_visible = false,
  }

  -- 创建 LVGL 控件，一次性完成位置和文本宽度约束。
  function self:build()
    if lv_clear then
      pcall(function() lv_clear() end)
    end
    self.root = lv_scr_act and lv_scr_act() or nil
    if not self.root then
      return
    end

    local splash = lv_obj_create(self.root)
    lv_obj_set_pos(splash, 0, 0)
    lv_obj_set_size(splash, W, H)
    lv_obj_set_style_bg_color(splash, C.bg, MAIN_STYLE)
    lv_obj_set_style_bg_opa(splash, 255, MAIN_STYLE)
    lv_obj_set_style_border_width(splash, 0, MAIN_STYLE)
    local splash_title = lv_label_create(self.root)
    lv_label_set_text(splash_title, "Ticker")
    label_style(splash_title, FONT_16, C.text, W, ALIGN_CENTER)
    lv_obj_set_pos(splash_title, 0, 102)
    if lv_refr_now then
      pcall(function() lv_refr_now(nil) end)
    elseif lv_timer_handler then
      pcall(lv_timer_handler)
    elseif lv_task_handler then
      pcall(lv_task_handler)
    end

    self.ui_font, self.ui_font_path = load_ui_font(self.i18n and self.i18n.font_path or nil)
    if lv_obj_clean then pcall(function() lv_obj_clean(self.root) end) end

    self.bg = lv_obj_create(self.root)
    lv_obj_set_pos(self.bg, 0, 0)
    lv_obj_set_size(self.bg, W, H)
    lv_obj_set_style_bg_color(self.bg, C.bg, MAIN_STYLE)
    lv_obj_set_style_bg_opa(self.bg, 255, MAIN_STYLE)
    lv_obj_set_style_border_width(self.bg, 0, MAIN_STYLE)
    if lv_obj_clear_flag then
      pcall(function() lv_obj_clear_flag(self.bg, LV_OBJ_FLAG_SCROLLABLE) end)
    end

    self.title = lv_label_create(self.root)
    lv_obj_set_pos(self.title, 12, 13)
    label_style(self.title, self.ui_font or FONT_12, C.sub, 194)

    self.status = lv_label_create(self.root)
    lv_obj_set_pos(self.status, 222, 15)
    label_style(self.status, self.ui_font or FONT_12, C.dim, 86, ALIGN_RIGHT)

    self.price = lv_label_create(self.root)
    lv_obj_set_pos(self.price, 12, 32)
    label_style(self.price, FONT_28, C.text, 296)

    self.change = lv_label_create(self.root)
    lv_obj_set_pos(self.change, 12, 64)
    label_style(self.change, FONT_12, C.sub, 148)

    self.detail = lv_label_create(self.root)
    lv_obj_set_pos(self.detail, 168, 64)
    label_style(self.detail, self.ui_font or FONT_12, C.dim, 140, ALIGN_RIGHT)

    self.updated = lv_label_create(self.root)
    lv_obj_set_pos(self.updated, 12, 80)
    label_style(self.updated, self.ui_font or FONT_10, C.dim, 296)

    self.chart_card = lv_obj_create(self.root)
    lv_obj_set_pos(self.chart_card, CHART_X, CHART_Y)
    lv_obj_set_size(self.chart_card, CHART_W, CHART_H)
    style_panel(self.chart_card)

    if CANVAS_FMT then
      self.chart = lv_canvas_create(self.chart_card, CANVAS_W, CANVAS_H, CANVAS_FMT)
    else
      self.chart = lv_canvas_create(self.chart_card, CANVAS_W, CANVAS_H)
    end
    lv_obj_set_pos(self.chart, 2, 2)
    lv_obj_set_style_radius(self.chart, 2, MAIN_STYLE)
    lv_obj_set_style_bg_opa(self.chart, 0, MAIN_STYLE)
    lv_obj_set_style_border_width(self.chart, 0, MAIN_STYLE)
    if lv_obj_set_style_clip_corner then
      pcall(function() lv_obj_set_style_clip_corner(self.chart, true, MAIN_STYLE) end)
    end

    self.footer_left = lv_label_create(self.root)
    lv_obj_set_pos(self.footer_left, 12, 219)
    label_style(self.footer_left, self.ui_font or FONT_10, C.dim, 145)

    self.footer_right = lv_label_create(self.root)
    lv_obj_set_pos(self.footer_right, 170, 219)
    label_style(self.footer_right, FONT_10, C.dim, 138, ALIGN_RIGHT)

    -- 手柄菜单使用独立遮罩层，只显示五行，保持 320x240 屏幕简洁清晰。
    self.menu_overlay = lv_obj_create(self.root)
    -- 必须在创建后的第一时间隐藏；否则 LVGL 可能在子控件构建期间刷新，造成启动闪现菜单。
    set_hidden(self.menu_overlay, true)
    lv_obj_set_pos(self.menu_overlay, 10, 10)
    lv_obj_set_size(self.menu_overlay, 300, 220)
    style_panel(self.menu_overlay)
    pcall(function() lv_obj_set_style_bg_color(self.menu_overlay, 0x080B0D, MAIN_STYLE) end)
    pcall(function() lv_obj_set_style_border_color(self.menu_overlay, C.line, MAIN_STYLE) end)

    self.menu_title = lv_label_create(self.menu_overlay)
    lv_obj_set_pos(self.menu_title, 12, 10)
    label_style(self.menu_title, self.ui_font or FONT_16, C.text, 210)
    set_text(self.menu_title, self.i18n and self.i18n:t("menu") or "Menu")

    self.menu_page = lv_label_create(self.menu_overlay)
    lv_obj_set_pos(self.menu_page, 225, 12)
    label_style(self.menu_page, FONT_10, C.dim, 61, ALIGN_RIGHT)

    for slot = 1, 5 do
      local row = lv_obj_create(self.menu_overlay)
      lv_obj_set_pos(row, 8, 38 + (slot - 1) * 30)
      lv_obj_set_size(row, 284, 26)
      style_panel(row)
      pcall(function() lv_obj_set_style_radius(row, 4, MAIN_STYLE) end)

      local marker = lv_label_create(row)
      lv_obj_set_pos(marker, 7, 5)
      label_style(marker, FONT_12, C.line, 12)

      local label = lv_label_create(row)
      lv_obj_set_pos(label, 22, 5)
      label_style(label, self.ui_font or FONT_12, C.sub, 108)

      local value = lv_label_create(row)
      lv_obj_set_pos(value, 132, 5)
      label_style(value, self.ui_font or FONT_12, C.text, 142, ALIGN_RIGHT)
      self.menu_rows[slot] = { root = row, marker = marker, label = label, value = value }
    end

    self.menu_hint = lv_label_create(self.menu_overlay)
    lv_obj_set_pos(self.menu_hint, 9, 196)
    label_style(self.menu_hint, self.ui_font or FONT_10, C.dim, 282, ALIGN_CENTER)
    set_text(self.menu_hint, self.i18n and self.i18n:t("controller_hint") or "UP/DOWN Select")
  end

  function self:show_menu(rows, selected)
    rows = rows or {}
    selected = math.max(1, math.min(#rows, tonumber(selected) or 1))
    self.menu_visible = true
    set_hidden(self.menu_overlay, false)
    if lv_obj_move_foreground then pcall(function() lv_obj_move_foreground(self.menu_overlay) end) end
    set_text(self.menu_title, self.i18n and self.i18n:t("menu") or "Menu")
    set_text(self.menu_page, tostring(selected) .. "/" .. tostring(#rows))

    local first = selected - 2
    if first < 1 then first = 1 end
    if first > math.max(1, #rows - 4) then first = math.max(1, #rows - 4) end
    for slot = 1, 5 do
      local view = self.menu_rows[slot]
      local index = first + slot - 1
      local item = rows[index]
      if item then
        set_hidden(view.root, false)
        local active = index == selected
        set_text(view.marker, active and ">" or "")
        set_text(view.label, item.label or "")
        set_text(view.value, item.value or "")
        set_color(view.label, active and C.text or C.sub)
        set_color(view.value, active and C.line or C.text)
        pcall(function() lv_obj_set_style_bg_color(view.root, active and C.menu_selected or C.panel, MAIN_STYLE) end)
        pcall(function() lv_obj_set_style_border_color(view.root, active and C.line or C.border, MAIN_STYLE) end)
      else
        set_hidden(view.root, true)
      end
    end
  end

  function self:hide_menu()
    self.menu_visible = false
    set_hidden(self.menu_overlay, true)
  end

  -- 绘制空状态和错误状态。
  function self:draw_empty(text, color)
    if not self.chart then
      return false
    end
    last_draw_error = ""
    local explicit = canvas_begin(self.chart)
    local ok = true
    ok = canvas_fill(self.chart, C.panel) and ok
    ok = draw_text(self.chart, 0, 42, CANVAS_W, text or (self.i18n and self.i18n:t("waiting") or "Waiting"), color or C.sub, ALIGN_CENTER, self.ui_font or 14) and ok
    ok = canvas_end(self.chart, explicit) and ok
    return ok
  end

  -- 绘制走势图，根据设置切换折线或 K 线。
  function self:draw_chart(snap)
    if not self.chart then
      return false
    end
    last_draw_error = ""
    local points = snap.points or {}
    local red_up = red_up_market(snap)
    if #points < 1 then
      return self:draw_empty(snap.error ~= "" and snap.error or (self.i18n and self.i18n:t("waiting") or "Waiting data"), tone_color(snap.tone, red_up))
    end

    local minp = tonumber(snap.min_price)
    local maxp = tonumber(snap.max_price)
    if not minp or not maxp then
      for i = 1, #points do
        local point = points[i]
        local lo = tonumber(point.low) or tonumber(point.close)
        local hi = tonumber(point.high) or tonumber(point.close)
        if lo then
          if not minp or lo < minp then minp = lo end
        end
        if hi then
          if not maxp or hi > maxp then maxp = hi end
        end
      end
    end
    if not minp or not maxp then
      return self:draw_empty(self.i18n and self.i18n:t("no_price") or "No price", C.sub)
    end
    if math.abs(maxp - minp) < 0.000001 then
      maxp = maxp + 1
      minp = minp - 1
    end

    local explicit = canvas_begin(self.chart)
    local ok = true
    ok = canvas_fill(self.chart, C.panel) and ok

    local left = 8
    local top = 8
    local width = CANVAS_W - 16
    local height = CANVAS_H - 18

    for i = 1, 2 do
      local y = top + math.floor(i * (height - 1) / 3 + 0.5)
      ok = draw_line(self.chart, left, y, left + width - 1, y, C.grid, 255, 1) and ok
    end
    for i = 1, 3 do
      local x = left + math.floor(i * (width - 1) / 4 + 0.5)
      ok = draw_line(self.chart, x, top, x, top + height - 1, C.grid, 160, 1) and ok
    end

    local mode = snap.settings and snap.settings.mode or "line"
    if mode == "candle" then
      ok = draw_candles(self.chart, points, minp, maxp, left, top, width, height, red_up) and ok
    else
      ok = draw_line_series(self.chart, points, minp, maxp, left, top, width, height, snap.tone, red_up) and ok
    end
    local ma_period = snap.settings and tonumber(snap.settings.ma_period) or 0
    ok = draw_ma_series(self.chart, points, ma_period, minp, maxp, left, top, width, height) and ok

    ok = draw_text(self.chart, CANVAS_W - 78, 8, 70, snap.max_price_text, C.sub, ALIGN_RIGHT, 10) and ok
    ok = draw_text(self.chart, CANVAS_W - 78, CANVAS_H - 20, 70, snap.min_price_text, C.sub, ALIGN_RIGHT, 10) and ok
    ok = canvas_end(self.chart, explicit) and ok
    return ok
  end

  -- 刷新屏幕文本和图表，只有图表脏时才重绘 canvas。
  function self:render(force)
    if not self.root then
      return
    end
    local snap = self.backend:snapshot()
    local active = snap.active or {}
    local title = self.i18n and self.i18n:asset_name(active) or active.text or active.symbol or "Market"
    local status = snap.loading and (self.i18n and self.i18n:t("sync") or "SYNC")
      or (self.i18n and self.i18n:status(snap.status) or string.upper(tostring(snap.status or "idle")))
    local trend_color = tone_color(snap.tone, red_up_market(snap))

    set_text(self.title, title)
    set_text(self.status, status)
    set_color(self.status, trend_color)

    set_text(self.price, snap.price_text)
    set_color(self.price, trend_color)

    set_text(self.change, snap.change_text .. "  " .. snap.change_pct_text)
    set_color(self.change, trend_color)

    local mode = snap.settings and snap.settings.mode or "line"
    local unit = tostring(snap.unit_text or "")
    local ma = ma_text(snap.settings and snap.settings.ma_period)
    local ma_suffix = ma ~= "" and ("  " .. ma) or ""
    local localized_mode = mode == "candle" and "K" or (self.i18n and self.i18n:t("line") or mode_text(mode))
    set_text(self.detail, (snap.settings.interval_text or snap.settings.interval or "--") .. "  " .. localized_mode .. ma_suffix .. "  " .. (snap.currency or "") .. unit)
    set_text(self.updated, snap.error ~= "" and snap.error or ((self.i18n and self.i18n:t("updated") or "UPD") .. " " .. tostring(snap.now_text or snap.updated_text or "--")))
    set_color(self.updated, snap.error ~= "" and C.warn or C.dim)

    local chart_key = tostring(snap.settings.asset) .. "|" .. tostring(snap.settings.interval) .. "|"
      .. tostring(snap.settings.mode) .. "|"
      .. tostring(snap.settings.ma_period) .. "|"
      .. tostring(snap.settings.currency) .. "|"
      .. tostring(snap.fx_rate) .. "|"
      .. tostring(snap.fx_twd_rate) .. "|"
      .. tostring(snap.updated_text) .. "|" .. tostring(#(snap.points or {})) .. "|" .. tostring(snap.error)
    if force or snap.chart_dirty or chart_key ~= self.last_chart_key then
      local ok, drawn = xpcall(function() return self:draw_chart(snap) end, chart_error_handler)
      if ok and drawn then
        self.last_chart_key = chart_key
        self.backend:clear_chart_dirty()
      end
    end

    set_text(self.footer_left, (self.i18n and self.i18n:t("points") or "pts") .. " " .. tostring(#(snap.points or {})) .. "  " .. localized_mode .. (ma ~= "" and (" " .. ma) or ""))
    if last_draw_error ~= "" then
      set_text(self.footer_right, "ERR " .. tostring(last_draw_error):sub(1, 18))
    else
      set_text(self.footer_right, tostring(snap.settings.interval or "--") .. "  " .. tostring(snap.next_fetch_in_s or 0) .. "s")
    end
  end

  -- 页面销毁时清屏，避免退出后残留行情 UI。
  function self:stop(reason)
    if lv_clear then
      pcall(function() lv_clear() end)
    end
    if self.ui_font and lv_font_free then
      pcall(function() lv_font_free(self.ui_font) end)
    end
    self.ui_font = nil
    self.ui_font_path = ""
    self.root = nil
  end

  return self
end

return Ui
