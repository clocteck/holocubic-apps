# LVGL UI 附加提示词

只有当前用户明确要求显示、画图、动画、小程序、临时界面或可视化效果时，才使用本文件规则生成 `ui_code`。

## ctx 可用能力

- `ctx.SCREEN_W = 320`，`ctx.SCREEN_H = 240`
- `ctx.MAIN_STYLE`，`ctx.FONT`，`ctx.ALIGN_LEFT`，`ctx.ALIGN_CENTER`
- `ctx.C.bg`，`ctx.C.line`，`ctx.C.text`，`ctx.C.sub`，`ctx.C.dim`，`ctx.C.cyan`，`ctx.C.green`，`ctx.C.yellow`，`ctx.C.red`
- `ctx.new_screen() -> screen`
- `ctx.style_obj(obj, bg_color)`：清理对象样式并设置纯色背景
- `ctx.label(parent, x, y, w, h, text, color, align)`：创建自动换行 label
- `ctx.every(ms, fn)`：创建宿主管理的定时器；动画间隔建议不低于 50ms

## Lua/LVGL 白名单

只使用本节列出的 Lua/LVGL 能力。不要根据命名规律编造新的 `lv_*` 函数。带 `*` 的分组只表示 README_LVGL 对应小节中已记录的函数，不代表任意后缀都可用。

Lua 基础能力：

- `math`，`string`，`table`
- `ipairs`，`pairs`，`next`
- `tonumber`，`tostring`，`type`
- `pcall`，`select`

对象与布局：

- `lv_obj_create(parent)`
- `lv_obj_set_pos`，`lv_obj_set_size`，`lv_obj_set_x`，`lv_obj_set_y`，`lv_obj_set_width`，`lv_obj_set_height`
- `lv_obj_set_align`，`lv_obj_align`，`lv_obj_align_to`，`lv_obj_center`
- `lv_obj_invalidate`
- `lv_obj_get_x`，`lv_obj_get_y`，`lv_obj_get_width`，`lv_obj_get_height`，`lv_obj_get_index`
- `lv_obj_move_foreground`，`lv_obj_move_background`，`lv_obj_move_to_index`，`lv_obj_swap`
- `lv_obj_set_layout`，`lv_obj_set_flex_flow`，`lv_obj_set_flex_align`，`lv_obj_set_grid_cell`，`lv_obj_set_grid_dsc_array`
- `lv_obj_add_flag`，`lv_obj_clear_flag`，`lv_obj_has_flag`
- `lv_obj_add_state`，`lv_obj_clear_state`，`lv_obj_has_state`
- `lv_obj_scroll_to_view`，`lv_obj_scroll_to_view_recursive`，`lv_obj_scroll_to_x`，`lv_obj_scroll_to_y`
- `lv_obj_set_scroll_dir`，`lv_obj_set_scroll_snap_x`，`lv_obj_set_scroll_snap_y`
- `lv_pct`，`lv_grid_fr`

样式：

- `lv_obj_set_style_bg_color`，`lv_obj_set_style_bg_opa`，`lv_obj_set_style_bg_grad_color`，`lv_obj_set_style_bg_grad_dir`，`lv_obj_set_style_bg_main_stop`，`lv_obj_set_style_bg_grad_stop`
- `lv_obj_set_style_border_width`，`lv_obj_set_style_border_color`，`lv_obj_set_style_border_opa`，`lv_obj_set_style_border_side`
- `lv_obj_set_style_radius`，`lv_obj_set_style_clip_corner`
- `lv_obj_set_style_outline_width`，`lv_obj_set_style_outline_color`，`lv_obj_set_style_outline_opa`，`lv_obj_set_style_outline_pad`
- `lv_obj_set_style_shadow_width`，`lv_obj_set_style_shadow_ofs_x`，`lv_obj_set_style_shadow_ofs_y`，`lv_obj_set_style_shadow_spread`，`lv_obj_set_style_shadow_color`，`lv_obj_set_style_shadow_opa`
- `lv_obj_set_style_translate_x`，`lv_obj_set_style_translate_y`
- `lv_obj_set_style_transform_width`，`lv_obj_set_style_transform_height`，`lv_obj_set_style_transform_zoom`，`lv_obj_set_style_transform_angle`，`lv_obj_set_style_transform_pivot_x`，`lv_obj_set_style_transform_pivot_y`
- `lv_obj_set_style_anim_time`，`lv_obj_set_style_blend_mode`，`lv_obj_set_style_opa`
- `lv_obj_set_style_pad_left`，`lv_obj_set_style_pad_top`，`lv_obj_set_style_pad_right`，`lv_obj_set_style_pad_bottom`，`lv_obj_set_style_pad_row`，`lv_obj_set_style_pad_column`，`lv_obj_set_style_pad_all`
- `lv_obj_set_style_text_color`，`lv_obj_set_style_text_opa`，`lv_obj_set_style_text_align`，`lv_obj_set_style_text_letter_space`，`lv_obj_set_style_text_line_space`，`lv_obj_set_style_text_font`
- `lv_obj_set_style_img_opa`，`lv_obj_set_style_img_recolor`，`lv_obj_set_style_img_recolor_opa`
- `lv_obj_set_style_line_width`，`lv_obj_set_style_line_color`，`lv_obj_set_style_line_opa`，`lv_obj_set_style_line_rounded`，`lv_obj_set_style_line_dash_width`，`lv_obj_set_style_line_dash_gap`
- `lv_obj_set_style_arc_width`，`lv_obj_set_style_arc_color`，`lv_obj_set_style_arc_opa`，`lv_obj_set_style_arc_rounded`
- `lv_obj_add_style`，`lv_obj_remove_style`，`lv_obj_remove_style_all`
- `lv_style_init`，`lv_style_reset`，`lv_style_set_min_width`，`lv_style_set_max_width`，`lv_style_set_min_height`，`lv_style_set_max_height`，`lv_style_set_transform_width`，`lv_style_set_transform_height`，`lv_style_set_blend_mode`

文本与简单控件：

- `lv_label_create`，`lv_label_set_text`，`lv_label_set_text_fmt`，`lv_label_set_text_static`，`lv_label_set_long_mode`
- `lv_line_create`，`lv_line_set_points`，`lv_line_set_y_invert`，`lv_line_get_y_invert`
- `lv_btn_create`
- `lv_checkbox_create`，`lv_checkbox_set_text`，`lv_checkbox_get_text`
- `lv_switch_create`

输入、列表、菜单、媒体与数据控件：

- `lv_dropdown_*`
- `lv_btnmatrix_*`
- `lv_textarea_*`
- `lv_keyboard_*`
- `lv_roller_*`
- `lv_spinbox_*`
- `lv_table_*`
- `lv_list_create`，`lv_list_add_text`，`lv_list_add_btn`，`lv_list_get_btn_text`，`lv_list_get_btn_label`，`lv_list_get_btn_icon`
- `lv_menu_*`
- `lv_img_create`，`lv_img_set_src`，`lv_img_set_offset_x`，`lv_img_set_offset_y`，`lv_img_set_zoom`，`lv_img_set_angle`，`lv_img_set_pivot`，`lv_img_set_size_mode`，`lv_img_set_antialias`
- `lv_gif_create`，`lv_gif_set_src`
- `lv_slider_*`
- `lv_bar_*`
- `lv_arc_*`
- `lv_chart_*`，包括 `lv_chart_add_series`，`lv_chart_add_cursor`，`lv_chart_set_*_value`，`lv_chart_get_*_array`，`lv_chart_get_point_pos_by_id`
- `lv_meter_*`，包括 `lv_meter_add_scale`，`lv_meter_add_needle_line`，`lv_meter_add_arc`，`lv_meter_set_indicator_*`

事件、焦点与动画：

- `lv_event_send`
- `lv_obj_add_event_cb`，`lv_obj_remove_event_cb`，`lv_obj_remove_event_dsc`
- `lv_event_get_code`，`lv_event_get_target`，`lv_event_get_current_target`，`lv_event_get_user_data`，`lv_event_get_param`
- `lv_group_*`，但不要创建持久全局焦点行为，除非用户明确要求
- `lv_anim_init`，`lv_anim_reset`，`lv_anim_set_var`，`lv_anim_set_exec_cb`，`lv_anim_set_values`，`lv_anim_set_time`，`lv_anim_set_delay`，`lv_anim_set_path_cb`，`lv_anim_set_playback_time`，`lv_anim_set_playback_delay`，`lv_anim_set_repeat_count`，`lv_anim_set_repeat_delay`，`lv_anim_set_early_apply`，`lv_anim_start`，`lv_anim_del`，`lv_anim_count_running`，`lv_anim_speed_to_time`
- 兼容动画接口：`lv_anim_start(obj, prop, ...)`，`lv_anim_delete(obj[, prop])`

Canvas：

- `lv_canvas_create`
- `lv_canvas_fill_bg`
- `lv_canvas_frame_begin`，`lv_canvas_frame_end`
- `lv_canvas_set_px_color`，`lv_canvas_set_px_opa`
- `lv_canvas_draw_rect`
- `lv_canvas_draw_line`
- `lv_canvas_draw_arc`
- `lv_canvas_draw_img`
- `lv_canvas_draw_text`
- `lv_canvas_transform`
- `lv_canvas_blur_hor`，`lv_canvas_blur_ver`

Canvas 约定：

- 点数组必须是扁平数组：`{x1,y1,x2,y2,...}`。
- `lv_line_set_points` 和 `lv_canvas_draw_line` 的点数组长度必须是偶数，至少包含两个点，也就是至少 4 个数字。
- 不要在点数组中直接使用返回多个值的函数，例如禁止 `{p(x1,y1), p(x2,y2)}`。Lua 只会完整展开最后一个多返回值，前面的调用会丢失 y 值。必须先写 `local px1, py1 = ...`，再写 `{px1, py1, px2, py2}`。
- 画单条 Canvas 线段时优先使用坐标重载：`lv_canvas_draw_line(cvs, x1, y1, x2, y2, color, opa, width)`。
- 使用点数组重载时不要传 `nil` 占位参数。要么写 `lv_canvas_draw_line(cvs, points)`，要么写 `lv_canvas_draw_line(cvs, points, point_cnt, dsc)`；`point_cnt` 必须是点数量，不是数字个数，例如 `{x1,y1,x2,y2}` 的 `point_cnt` 是 `2`。
- `dsc` 常用字段：`bg_color`，`bg_opa`，`radius`，`border_width`，`border_color`，`border_opa`，`color`，`opa`，`width`，`align`，`font_size`，`font_handle`。

常量：

- 已存在的 `LV_*` 与 `LABEL_LONG_*` 常量可用。
- 样式 selector 优先使用 `ctx.MAIN_STYLE`。
- 字体优先使用 `ctx.FONT`。

## 禁止调用

- 禁止 `file`，`http`，`i2s`，`key`，`app`，`dofile`，`loadfile`，`require`，`_G`，`debug`，`os`，`io`
- 禁止 `lv_scr_act`，`lv_scr_load`，`lv_scr_load_anim`
- 禁止 `lv_clear`，`lv_begin`，`lv_end`，`lv_get_root`
- 禁止 `lv_obj_del`，`lv_obj_del_async`，`lv_obj_clean`，`lv_obj_set_parent`
- 禁止 parent/child discovery API：`lv_obj_get_parent`，`lv_obj_get_child`，`lv_obj_get_child_cnt`
- 禁止 `lv_font_load`，`lv_font_free`
- 禁止 `lv_img_load_bmp565`，`lv_img_free_handle`
- 禁止 snapshot API
- 禁止 `lv_avi_canvas_*`
- 禁止全局动画删除：`lv_anim_del_all`，`lv_anim_delete_all`
- 禁止访问 SD 卡、网络、麦克风、按键、应用退出或系统 API
- 不要假设存在外部图片、字体或资源；除非用户明确说明，默认只有 `ctx.FONT`
- `ctx.new_screen()`、`ctx.label()`、`lv_*_create()` 返回的 LVGL 对象都是数字 id，不是对象表。禁止 `screen.xxx`、`obj.xxx`、`screen:xxx()`、`obj:xxx()`；只能把数字 id 作为参数传给 `lv_*` 或 `ctx.*` 函数。

## 视觉质量规则

- UI 必须适配 320x240，元素不得超出 `0..319 x 0..239`。
- 一屏只保留一个视觉中心，文字短，控件少。
- 文本必须放在固定宽高内，并设置合适的长文本策略。
- 默认黑色背景，高对比文字，1-2个主强调色，2-5个其他颜色。
- 用户要求画图或显示图形时，`ui_code` 不能只创建文字 label 或 Unicode 符号，必须包含至少一个非文本图形元素，例如 `lv_line_create`、`lv_canvas_create`、`lv_arc_create` 或带尺寸和颜色的 `lv_obj_create`。
- 生成前检查：图形是否像用户要求的对象，是否居中清晰，是否太小或被文字遮挡。
- 用户要求倒计时或动画时，使用 `ctx.every(ms, fn)`，间隔不低于 50ms。
- 优先纯黑色0x0000背景

## 常用正确写法

Line：

```lua
local line = lv_line_create(screen)
local x1, y1 = 80, 120
local x2, y2 = 160, 80
local x3, y3 = 240, 120
lv_line_set_points(line, {x1, y1, x2, y2, x3, y3})
lv_obj_set_style_line_color(line, 0xFF69B4, ctx.MAIN_STYLE)
lv_obj_set_style_line_width(line, 8, ctx.MAIN_STYLE)
lv_obj_set_style_line_opa(line, 255, ctx.MAIN_STYLE)
```

Canvas：

```lua
local cvs = lv_canvas_create(screen, 320, 240, LV_IMG_CF_TRUE_COLOR)
lv_canvas_frame_begin(cvs)
lv_canvas_fill_bg(cvs, 0x000000, 255)
lv_canvas_draw_line(cvs, 100, 120, 140, 80, 0xFF69B4, 255, 6)
lv_canvas_draw_line(cvs, 140, 80, 180, 120, 0xFF69B4, 255, 6)
lv_canvas_frame_end(cvs)
```

### timer 对象方法

- `timer:register(interval_ms, mode, callback)`
- `timer:alarm(interval_ms, mode, callback) -> bool`
- `timer:start() -> bool`
- `timer:stop() -> bool`
- `timer:unregister()`
- `timer:interval(interval_ms)`
- `timer:state() -> started, mode | nil`
