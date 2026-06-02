# LVGL UI Lua API

本文只覆盖 `src/lua_ui` 当前注册到 Lua 的 UI 接口。

说明：
- 对象返回值都是 Lua 层 `obj_id`；`0` 是 root 伪 id，可作为父对象。
- `LV_*` 常量按 LVGL 官方用法使用；本文只补充少量项目相关常量。
- table、handle、回调等 Lua 写法见各接口说明。

## 官方接口 / 官方兼容区

### Screen
- `lv_scr_act() -> screen_id`
- `lv_layer_top() -> layer_id`
- `lv_scr_load(screen_id)`
- `lv_scr_load_anim(screen_id, anim_type, time, delay, auto_del)`

说明：
- `lv_scr_act()` 通常返回 root `0`；也可用 `lv_obj_create(nil)` 创建独立 screen 后切换。
- `lv_layer_top()` 适合放弹窗、遮罩、浮层；不要删除 layer 本身，只清理其子对象。
- `lv_scr_load_anim()` 的 `anim_type` 使用 LVGL 官方 `LV_SCR_LOAD_ANIM_*` 常量

### Object
- `lv_obj_create(parent_id|nil) -> obj_id`
- `lv_obj_set_pos(obj_id, x, y)`
- `lv_obj_set_size(obj_id, w, h)`
- `lv_obj_set_x(obj_id, x)`
- `lv_obj_set_y(obj_id, y)`
- `lv_obj_set_width(obj_id, width)`
- `lv_obj_set_height(obj_id, height)`
- `lv_obj_set_align(obj_id, align[, x_ofs[, y_ofs]])`
- `lv_obj_align(obj_id, align[, x_ofs[, y_ofs]])`
- `lv_obj_align_to(obj_id, base_id, align[, x_ofs[, y_ofs]])`
- `lv_obj_center(obj_id)`
- `lv_obj_set_parent(obj_id, new_parent_id)`
- `lv_obj_get_child(parent_id, idx) -> child_id|nil`
- `lv_obj_get_child_cnt(parent_id) -> n`
- `lv_obj_get_index(obj_id) -> idx`
- `lv_obj_move_foreground(obj_id)`
- `lv_obj_move_background(obj_id)`
- `lv_obj_move_to_index(obj_id, idx)`
- `lv_obj_swap(obj1_id, obj2_id)`
- `lv_obj_del(obj_id)`
- `lv_obj_del_async(obj_id)`
- `lv_obj_clean(obj_id)`
- `lv_obj_invalidate(obj_id)`
- `lv_obj_get_x(obj_id) -> x`
- `lv_obj_get_y(obj_id) -> y`
- `lv_obj_get_width(obj_id) -> width`
- `lv_obj_get_height(obj_id) -> height`
- `lv_obj_get_parent(obj_id) -> parent_id|nil`

说明：
- `lv_obj_create(nil)` 用于创建可被 `lv_scr_load*()` 切换的独立 screen
- `lv_obj_get_child(parent_id, idx)` 支持 LVGL 官方索引语义：`0` 是最早创建的 child，`-1` 是最后一个 child
- `lv_obj_move_to_index(obj_id, idx)` 同样支持 LVGL 官方负索引语义；`0` 可移到背景，`-1` 表示移到最前景
- `lv_obj_set_parent(obj_id, new_parent_id)` 会保持相对坐标；父对象不能设为自己或自己的子对象

### Event
- `lv_event_send(obj_id, event_code[, param]) -> bool`

### Layout / Flag / State / Scroll
- `lv_obj_set_layout(obj_id, layout)`
- `lv_obj_set_flex_flow(obj_id, flow)`
- `lv_obj_set_flex_align(obj_id, main_place, cross_place, track_place)`
- `lv_obj_set_grid_cell(obj_id, col_align, col_pos, col_span, row_align, row_pos, row_span)`
- `lv_obj_add_flag(obj_id, flag)`
- `lv_obj_clear_flag(obj_id, flag)`
- `lv_obj_add_state(obj_id, state)`
- `lv_obj_clear_state(obj_id, state)`
- `lv_obj_has_flag(obj_id, flag) -> bool`
- `lv_obj_has_state(obj_id, state) -> bool`
- `lv_obj_scroll_to_view(obj_id[, anim])`
- `lv_obj_scroll_to_view_recursive(obj_id[, anim])`
- `lv_obj_scroll_to_x(obj_id, value[, anim])`
- `lv_obj_scroll_to_y(obj_id, value[, anim])`
- `lv_obj_set_scroll_dir(obj_id, dir)`
- `lv_obj_set_scroll_snap_x(obj_id, snap)`
- `lv_obj_set_scroll_snap_y(obj_id, snap)`

### Style
共享 style：
- `lv_style_t() -> style`
- `lv_style_init(style)`
- `lv_style_reset(style)`
- `lv_style_set_bg_color(style, color_hex)`
- `lv_style_set_bg_opa(style, opa)`
- `lv_style_set_border_width(style, width)`
- `lv_style_set_border_color(style, color_hex)`
- `lv_style_set_radius(style, radius)`
- `lv_style_set_pad_all(style, value)`
- `lv_style_set_text_color(style, color_hex)`
- `lv_style_set_text_font(style, font)`
- `lv_style_set_opa(style, opa)`
- `lv_style_set_transform_width(style, value)`
- `lv_style_set_transform_height(style, value)`
- `lv_style_set_blend_mode(style, blend_mode)`

对象 style：
- `lv_obj_add_style(obj_id, style, selector)`
- `lv_obj_remove_style(obj_id, style_or_nil, selector)`
- `lv_obj_remove_style_all(obj_id)`
- `lv_obj_report_style_change(style_or_nil)`
- `lv_obj_refresh_style(obj_id, part, prop)`
- `lv_obj_set_style_bg_color(obj_id, color_hex, selector)`
- `lv_obj_set_style_bg_opa(obj_id, opa, selector)`
- `lv_obj_set_style_bg_grad_color(obj_id, color_hex, selector)`
- `lv_obj_set_style_bg_grad_dir(obj_id, dir, selector)`
- `lv_obj_set_style_bg_main_stop(obj_id, stop, selector)`
- `lv_obj_set_style_bg_grad_stop(obj_id, stop, selector)`
- `lv_obj_set_style_bg_img_opa(obj_id, opa, selector)`
- `lv_obj_set_style_bg_img_recolor(obj_id, color_hex, selector)`
- `lv_obj_set_style_bg_img_recolor_opa(obj_id, opa, selector)`
- `lv_obj_set_style_bg_img_tiled(obj_id, enabled, selector)`
- `lv_obj_set_style_border_width(obj_id, width, selector)`
- `lv_obj_set_style_border_color(obj_id, color_hex, selector)`
- `lv_obj_set_style_border_opa(obj_id, opa, selector)`
- `lv_obj_set_style_border_side(obj_id, side, selector)`
- `lv_obj_set_style_min_width(obj_id, value, selector)`
- `lv_obj_set_style_max_width(obj_id, value, selector)`
- `lv_obj_set_style_min_height(obj_id, value, selector)`
- `lv_obj_set_style_max_height(obj_id, value, selector)`
- `lv_obj_set_style_radius(obj_id, radius, selector)`
- `lv_obj_set_style_clip_corner(obj_id, enabled, selector)`
- `lv_obj_set_style_border_post(obj_id, enabled, selector)`
- `lv_obj_set_style_outline_width(obj_id, width, selector)`
- `lv_obj_set_style_outline_color(obj_id, color_hex, selector)`
- `lv_obj_set_style_outline_opa(obj_id, opa, selector)`
- `lv_obj_set_style_outline_pad(obj_id, pad, selector)`
- `lv_obj_set_style_shadow_width(obj_id, width, selector)`
- `lv_obj_set_style_shadow_ofs_x(obj_id, value, selector)`
- `lv_obj_set_style_shadow_ofs_y(obj_id, value, selector)`
- `lv_obj_set_style_shadow_spread(obj_id, value, selector)`
- `lv_obj_set_style_shadow_color(obj_id, color_hex, selector)`
- `lv_obj_set_style_shadow_opa(obj_id, opa, selector)`
- `lv_obj_set_style_translate_x(obj_id, value, selector)`
- `lv_obj_set_style_translate_y(obj_id, value, selector)`
- `lv_obj_set_style_transform_width(obj_id, value, selector)`
- `lv_obj_set_style_transform_height(obj_id, value, selector)`
- `lv_obj_set_style_transform_zoom(obj_id, value, selector)`
- `lv_obj_set_style_transform_angle(obj_id, value, selector)`
- `lv_obj_set_style_transform_pivot_x(obj_id, value, selector)`
- `lv_obj_set_style_transform_pivot_y(obj_id, value, selector)`
- `lv_obj_set_style_anim_time(obj_id, ms, selector)`
- `lv_obj_set_style_blend_mode(obj_id, blend_mode, selector)`
- `lv_obj_set_style_opa(obj_id, opa, selector)`
- `lv_obj_set_style_pad_left(obj_id, left, selector)`
- `lv_obj_set_style_pad_top(obj_id, top, selector)`
- `lv_obj_set_style_pad_right(obj_id, right, selector)`
- `lv_obj_set_style_pad_bottom(obj_id, bottom, selector)`
- `lv_obj_set_style_pad_row(obj_id, value, selector)`
- `lv_obj_set_style_pad_column(obj_id, value, selector)`
- `lv_obj_set_style_pad_all(obj_id, value, selector)`
- `lv_obj_set_style_text_color(obj_id, color_hex, selector)`
- `lv_obj_set_style_text_opa(obj_id, opa, selector)`
- `lv_obj_set_style_text_align(obj_id, align, selector)`
- `lv_obj_set_style_text_font(obj_id, font, selector)`
- `lv_obj_set_style_text_letter_space(obj_id, value, selector)`
- `lv_obj_set_style_text_line_space(obj_id, value, selector)`
- `lv_obj_set_style_img_opa(obj_id, opa, selector)`
- `lv_obj_set_style_img_recolor(obj_id, color_hex, selector)`
- `lv_obj_set_style_img_recolor_opa(obj_id, opa, selector)`
- `lv_obj_set_style_line_width(obj_id, width, selector)`
- `lv_obj_set_style_line_color(obj_id, color_hex, selector)`
- `lv_obj_set_style_line_opa(obj_id, opa, selector)`
- `lv_obj_set_style_line_rounded(obj_id, enabled, selector)`
- `lv_obj_set_style_line_dash_width(obj_id, width, selector)`
- `lv_obj_set_style_line_dash_gap(obj_id, gap, selector)`
- `lv_obj_set_style_arc_width(obj_id, width, selector)`
- `lv_obj_set_style_arc_color(obj_id, color_hex, selector)`
- `lv_obj_set_style_arc_opa(obj_id, opa, selector)`
- `lv_obj_set_style_arc_rounded(obj_id, enabled, selector)`

说明：
- 共享 style：`lv_style_t()` -> `lv_style_init()` -> `lv_style_set_*()` -> `lv_obj_add_style()`
- 修改共享 style 后，可调用 `lv_obj_report_style_change(style)` 或 `lv_obj_refresh_style(obj_id, part, prop)` 刷新
- `lv_obj_set_style_*` 修改对象本地 style；`lv_obj_remove_style(obj_id, nil, selector)` 按 selector 移除 style
- `blend_mode` 可配合这些常量使用：`LV_BLEND_MODE_NORMAL`、`LV_BLEND_MODE_ADDITIVE`、`LV_BLEND_MODE_SUBTRACTIVE`、`LV_BLEND_MODE_MULTIPLY`

### Label
- `lv_label_create(parent_id) -> label_id`
- `lv_label_set_text(label_id, text)`
- `lv_label_set_text_fmt(label_id, fmt, ...)`
- `lv_label_set_long_mode(label_id, mode)`

### Line
- `lv_line_create(parent_id) -> line_id`
- `lv_line_set_points(line_id, point_array[, point_cnt])`
- `lv_line_set_points(line_id, nil)` -- 清空点数组
- `lv_line_set_y_invert(line_id, enabled)`
- `lv_line_get_y_invert(line_id) -> bool`

说明：
- `point_array` 可用扁平数组 `{x1, y1, x2, y2, ...}`，也可用点表数组 `{{x=0, y=0}, {x=20, y=12}}`
- `point_cnt` 可选；不传时自动推导，传 `0` 等价于清空
- 非清空调用至少需要 2 个点

### Button
- `lv_btn_create(parent_id) -> btn_id`

### Checkbox
- `lv_checkbox_create(parent_id) -> cb_id`
- `lv_checkbox_set_text(cb_id, text)`
- `lv_checkbox_get_text(cb_id) -> string|nil`

### Dropdown
- `lv_dropdown_create(parent_id) -> dd_id`
- `lv_dropdown_set_options(dd_id, options_text)`
- `lv_dropdown_set_options_static(dd_id, options_text)`
- `lv_dropdown_add_option(dd_id, text, pos)`
- `lv_dropdown_clear_options(dd_id)`
- `lv_dropdown_set_selected(dd_id, index)`
- `lv_dropdown_get_selected(dd_id) -> index`
- `lv_dropdown_get_selected_str(dd_id) -> string`
- `lv_dropdown_set_dir(dd_id, dir)`
- `lv_dropdown_set_symbol(dd_id, symbol)`
- `lv_dropdown_open(dd_id)`
- `lv_dropdown_close(dd_id)`
- `lv_dropdown_is_open(dd_id) -> bool`
- `lv_dropdown_set_selected_highlight(dd_id, enabled)`

说明：
- `options_text` 按 LVGL 8.3 官方语义使用 `"\n"` 分隔各个选项
- 可配合 `LV_DROPDOWN_POS_LAST` 与 `LV_DIR_*` 常量使用
- `lv_dropdown_get_selected_str()` 直接返回当前选项字符串
- `lv_dropdown_set_options_static()` 适合固定选项文本
- `symbol` 可为 `LV_SYMBOL_*`、普通文本、图片源、路径或 `nil`；传 `nil` 可清除右侧符号

### Button Matrix
- `lv_btnmatrix_create(parent_id) -> btnm_id`
- `lv_btnmatrix_set_map(btnm_id, map_table)`
- `lv_btnmatrix_set_ctrl_map(btnm_id, ctrl_map_table)`
- `lv_btnmatrix_set_btn_ctrl(btnm_id, btn_index, ctrl)`
- `lv_btnmatrix_clear_btn_ctrl(btnm_id, btn_index, ctrl)`
- `lv_btnmatrix_set_btn_ctrl_all(btnm_id, ctrl)`
- `lv_btnmatrix_clear_btn_ctrl_all(btnm_id, ctrl)`
- `lv_btnmatrix_set_one_checked(btnm_id, enabled)`
- `lv_btnmatrix_set_selected_btn(btnm_id, btn_index)`
- `lv_btnmatrix_get_selected_btn(btnm_id) -> btn_index`
- `lv_btnmatrix_get_btn_text(btnm_id, btn_index) -> string|nil`
- `lv_btnmatrix_has_btn_ctrl(btnm_id, btn_index, ctrl) -> bool`

说明：
- 可配合这些常量使用：`LV_BTNMATRIX_BTN_NONE`、`LV_BTNMATRIX_CTRL_HIDDEN`、`LV_BTNMATRIX_CTRL_NO_REPEAT`、`LV_BTNMATRIX_CTRL_DISABLED`、`LV_BTNMATRIX_CTRL_CHECKABLE`、`LV_BTNMATRIX_CTRL_CHECKED`、`LV_BTNMATRIX_CTRL_CLICK_TRIG`、`LV_BTNMATRIX_CTRL_POPOVER`、`LV_BTNMATRIX_CTRL_RECOLOR`、`LV_BTNMATRIX_CTRL_CUSTOM_1`、`LV_BTNMATRIX_CTRL_CUSTOM_2`
- `lv_btnmatrix_set_map(btnm_id, map_table)` 会自动追加 LVGL 所需的终止空串 `""`；换行请在表里写 `"\n"`
- `lv_btnmatrix_set_ctrl_map(btnm_id, ctrl_map_table)` 的长度按“实际按钮数”计算，不包含 `"\n"` 换行项
- `ctrl_map_table` 每个元素都可以把宽度 `1..7` 和 `LV_BTNMATRIX_CTRL_*` 控制位按位或在一起

### Textarea
- `lv_textarea_create(parent_id) -> ta_id`
- `lv_textarea_set_text(ta_id, text)`
- `lv_textarea_get_text(ta_id) -> string`
- `lv_textarea_add_text(ta_id, text)`
- `lv_textarea_add_char(ta_id, ch)`
- `lv_textarea_del_char(ta_id)`
- `lv_textarea_del_char_forward(ta_id)`
- `lv_textarea_set_placeholder_text(ta_id, text)`
- `lv_textarea_set_one_line(ta_id, enabled)`
- `lv_textarea_set_password_mode(ta_id, enabled)`
- `lv_textarea_set_password_show_time(ta_id, ms)`
- `lv_textarea_set_password_bullet(ta_id, text)`
- `lv_textarea_set_accepted_chars(ta_id, chars_or_nil)`
- `lv_textarea_set_max_length(ta_id, n)`
- `lv_textarea_set_cursor_pos(ta_id, pos)`
- `lv_textarea_get_cursor_pos(ta_id) -> pos`
- `lv_textarea_set_cursor_click_pos(ta_id, enabled)`
- `lv_textarea_set_text_selection(ta_id, enabled)`
- `lv_textarea_clear_selection(ta_id)`

说明：
- `lv_textarea_add_char(ta_id, ch)` 的 `ch` 支持单个字符字符串或 Unicode 码点整数；多字符字符串请改用 `lv_textarea_add_text()`
- `lv_textarea_set_accepted_chars(ta_id, chars_or_nil)` 传 `nil` 可清除字符白名单限制
- 可配合 `LV_TEXTAREA_CURSOR_LAST` 与 `LV_PART_TEXTAREA_PLACEHOLDER` 常量使用

### Keyboard
- `lv_keyboard_create(parent_id) -> kb_id`
- `lv_keyboard_set_textarea(kb_id, ta_id_or_nil)`
- `lv_keyboard_get_textarea(kb_id) -> ta_id|nil`
- `lv_keyboard_set_mode(kb_id, mode)`
- `lv_keyboard_get_mode(kb_id) -> mode`
- `lv_keyboard_set_popovers(kb_id, enabled)`

说明：
- 可配合这些常量使用：`LV_KEYBOARD_MODE_TEXT_LOWER`、`LV_KEYBOARD_MODE_TEXT_UPPER`、`LV_KEYBOARD_MODE_SPECIAL`、`LV_KEYBOARD_MODE_NUMBER`、`LV_KEYBOARD_MODE_USER_1`、`LV_KEYBOARD_MODE_USER_2`、`LV_KEYBOARD_MODE_USER_3`、`LV_KEYBOARD_MODE_USER_4`
- `lv_keyboard_set_textarea(kb_id, nil)` 可解除和输入框的绑定
- 绑定后，keyboard 默认事件会把按键内容自动写入目标 textarea

### Roller
- `lv_roller_create(parent_id) -> roller_id`
- `lv_roller_set_options(roller_id, options_text, mode)`
- `lv_roller_set_selected(roller_id, index[, anim])`
- `lv_roller_get_selected(roller_id) -> index`
- `lv_roller_get_selected_str(roller_id) -> string`
- `lv_roller_set_visible_row_count(roller_id, n)`
- `lv_roller_get_option_cnt(roller_id) -> n`

说明：
- `options_text` 按 LVGL 8.3 官方语义使用 `"\n"` 分隔各个选项
- 可配合这些常量使用：`LV_ROLLER_MODE_NORMAL`、`LV_ROLLER_MODE_INFINITE`
- `lv_roller_set_selected(...[, anim])` 的 `anim` 可传 `LV_ANIM_OFF` 或 `LV_ANIM_ON`
- `lv_roller_get_selected_str()` 直接返回当前选项字符串

### Spinbox
- `lv_spinbox_create(parent_id) -> spinbox_id`
- `lv_spinbox_set_value(spinbox_id, value)`
- `lv_spinbox_get_value(spinbox_id) -> value`
- `lv_spinbox_set_range(spinbox_id, min, max)`
- `lv_spinbox_set_digit_format(spinbox_id, digit_count, separator_position)`
- `lv_spinbox_set_step(spinbox_id, step)`
- `lv_spinbox_set_rollover(spinbox_id, enabled)`
- `lv_spinbox_step_next(spinbox_id)`
- `lv_spinbox_step_prev(spinbox_id)`
- `lv_spinbox_increment(spinbox_id)`
- `lv_spinbox_decrement(spinbox_id)`

说明：
- `digit_count` 不包含符号和小数点；`separator_position = 0` 表示不显示小数点
- `step` 按 LVGL 官方语义通常使用 `1`、`10`、`100`、`1000` 这类 10 的幂

### Table
- `lv_table_create(parent_id) -> table_id`
- `lv_table_set_row_cnt(table_id, row_cnt)`
- `lv_table_set_col_cnt(table_id, col_cnt)`
- `lv_table_set_col_width(table_id, col, width)`
- `lv_table_set_cell_value(table_id, row, col, text)`
- `lv_table_get_cell_value(table_id, row, col) -> string|nil`
- `lv_table_add_cell_ctrl(table_id, row, col, ctrl)`
- `lv_table_clear_cell_ctrl(table_id, row, col, ctrl)`
- `lv_table_get_selected_cell(table_id) -> row, col`

说明：
- `table` 是轻量绘制控件，不会为每个 cell 单独创建真实子对象，适合状态页、参数页、Wi-Fi 列表这类场景
- `lv_table_get_cell_value(table_id, row, col)` 越界或对象无效时返回 `nil`；合法单元格即使内容为空也会返回空字符串
- `lv_table_get_selected_cell()` 返回 `row, col`；无选中时返回 `nil, nil`
- 可配合这些常量使用：`LV_TABLE_CELL_NONE`、`LV_TABLE_CELL_CTRL_MERGE_RIGHT`、`LV_TABLE_CELL_CTRL_TEXT_CROP`、`LV_TABLE_CELL_CTRL_CUSTOM_1`、`LV_TABLE_CELL_CTRL_CUSTOM_2`、`LV_TABLE_CELL_CTRL_CUSTOM_3`、`LV_TABLE_CELL_CTRL_CUSTOM_4`

### Group / Focus
- `lv_group_create() -> group_handle`
- `lv_group_del(group_handle)`
- `lv_group_add_obj(group_handle, obj_id)`
- `lv_group_remove_obj(obj_id)`
- `lv_group_remove_all_objs(group_handle)`
- `lv_group_focus_obj(obj_id)`
- `lv_group_focus_next(group_handle)`
- `lv_group_focus_prev(group_handle)`
- `lv_group_get_focused(group_handle) -> obj_id|nil`
- `lv_group_set_wrap(group_handle, enabled)`
- `lv_group_set_editing(group_handle, enabled)`
- `lv_group_get_editing(group_handle) -> bool`
- `lv_group_set_default(group_handle)`

说明：
- 这里的 `group_handle` 是资源句柄，不是 `obj_id`
- `lv_group_set_default(group_handle)` 后，新创建且支持 group 的控件会自动加入这个默认 group
- 也支持 `lv_group_set_default(nil)` 清除默认 group

### List
- `lv_list_create(parent_id) -> list_id`
- `lv_list_add_text(list_id, text) -> text_id`
- `lv_list_add_btn(list_id[, icon], text) -> btn_id`
- `lv_list_get_btn_text(list_id, btn_id) -> string|nil`

### Menu
- `lv_menu_create(parent_id) -> menu_id`
- `lv_menu_page_create(menu_id[, title]) -> page_id`
- `lv_menu_section_create(parent_id) -> section_id`
- `lv_menu_cont_create(parent_id) -> cont_id`
- `lv_menu_separator_create(parent_id) -> separator_id`
- `lv_menu_set_page(menu_id[, page_id])`
- `lv_menu_set_sidebar_page(menu_id[, page_id])`
- `lv_menu_set_mode_header(menu_id, mode_header)`
- `lv_menu_set_mode_root_back_btn(menu_id, mode_root_back_btn)`
- `lv_menu_set_load_page_event(menu_id, obj_id, page_id)`
- `lv_menu_clear_history(menu_id)`
- `lv_menu_get_cur_main_page(menu_id) -> page_id|nil`
- `lv_menu_get_cur_sidebar_page(menu_id) -> page_id|nil`
- `lv_menu_get_main_header(menu_id) -> header_id|nil`
- `lv_menu_get_main_header_back_btn(menu_id) -> btn_id|nil`
- `lv_menu_get_sidebar_header(menu_id) -> header_id|nil`
- `lv_menu_get_sidebar_header_back_btn(menu_id) -> btn_id|nil`
- `lv_menu_back_btn_is_root(menu_id, obj_id) -> bool`

### Switch
- `lv_switch_create(parent_id) -> switch_id`

### Tabview
- `lv_tabview_create(parent_id, tab_pos, tab_size) -> tabview_id`
- `lv_tabview_add_tab(tabview_id, name) -> page_id`
- `lv_tabview_set_act(tabview_id, tab_index[, anim])`
- `lv_tabview_get_tab_act(tabview_id) -> tab_index`
- `lv_tabview_get_content(tabview_id) -> content_id|nil`
- `lv_tabview_get_tab_btns(tabview_id) -> tab_btns_id|nil`
- `lv_tabview_rename_tab(tabview_id, tab_index, new_name)`

### Image
- `lv_img_create(parent_id) -> img_id`
- `lv_img_set_offset_x(img_id, x)`
- `lv_img_set_offset_y(img_id, y)`
- `lv_img_set_zoom(img_id, zoom)`
- `lv_img_set_angle(img_id, angle)`
- `lv_img_set_pivot(img_id, x, y)`
- `lv_img_set_size_mode(img_id, mode)`
- `lv_img_set_antialias(img_id, enabled)`

说明：
- `LV_IMG_SIZE_MODE_VIRTUAL`：图片对象尺寸大于源图时，LVGL 会按对象区域平铺图片。
- `LV_IMG_SIZE_MODE_REAL`：配合 `lv_obj_set_size(img_id, LV_SIZE_CONTENT, LV_SIZE_CONTENT)` 使用时，对象尺寸跟随图片实际绘制尺寸，适合“按内容居中”或“缩小后居中”。

### Slider / Bar
- `lv_slider_create(parent_id) -> slider_id`
- `lv_slider_set_range(slider_id, min, max)`
- `lv_slider_set_mode(slider_id, mode)`
- `lv_slider_set_value(slider_id, value[, anim])`
- `lv_slider_set_left_value(slider_id, value[, anim])`
- `lv_slider_get_value(slider_id) -> value`
- `lv_slider_get_left_value(slider_id) -> value`
- `lv_slider_get_min_value(slider_id) -> value`
- `lv_slider_get_max_value(slider_id) -> value`
- `lv_slider_get_mode(slider_id) -> mode`
- `lv_slider_is_dragged(slider_id) -> bool`
- `lv_bar_create(parent_id) -> bar_id`
- `lv_bar_set_range(bar_id, min, max)`
- `lv_bar_set_mode(bar_id, mode)`
- `lv_bar_set_value(bar_id, value[, anim])`
- `lv_bar_set_start_value(bar_id, value[, anim])`
- `lv_bar_get_value(bar_id) -> value`

### Arc
- `lv_arc_create(parent_id) -> arc_id`
- `lv_arc_set_range(arc_id, min, max)`
- `lv_arc_set_value(arc_id, value)`
- `lv_arc_get_value(arc_id) -> value`
- `lv_arc_set_bg_angles(arc_id, start, end)`
- `lv_arc_set_angles(arc_id, start, end)`
- `lv_arc_set_rotation(arc_id, rotation)`
- `lv_arc_set_mode(arc_id, mode)`
- `lv_arc_set_change_rate(arc_id, rate)`

### Chart
- `lv_chart_create(parent_id) -> chart_id`
- `lv_chart_set_type(chart_id, type)`
- `lv_chart_set_point_count(chart_id, count)`
- `lv_chart_set_range(chart_id, axis, min, max)`
- `lv_chart_set_update_mode(chart_id, mode)`
- `lv_chart_set_div_line_count(chart_id, hdiv, vdiv)`
- `lv_chart_set_zoom_x(chart_id, zoom)`
- `lv_chart_set_zoom_y(chart_id, zoom)`
- `lv_chart_set_axis_tick(chart_id, axis, major_len, minor_len, major_cnt, minor_cnt, label_en, draw_size)`
- `lv_chart_get_point_count(chart_id) -> n`
- `lv_chart_get_pressed_point(chart_id) -> idx`
- `lv_chart_refresh(chart_id)`

### Meter
- `lv_meter_create(parent_id) -> meter_id`

### Resource APIs
- `lv_img_set_src(img_id, src)`
- `lv_obj_set_style_bg_img_src(obj_id, src, selector)`
- `lv_obj_set_style_text_font(obj_id, font, selector)`
- `lv_font_load(path) -> font`
- `lv_font_free(font)`
- `lv_snapshot_take(obj_id[, cf]) -> snapshot`
- `lv_snapshot_free(snapshot)`
- `lv_snapshot_buf_size_needed(obj_id[, cf]) -> size`

说明：
- `src` 可为路径、symbol 或图片 handle
- `font` 可为内置字体或 `lv_font_load()` 返回值
- 内置字体格式如 `LV_FONT_MONTSERRAT_14`，可用字号：8、10、12、14、16、20、24、28
- snapshot 默认 `cf=LV_IMG_CF_TRUE_COLOR_ALPHA`；失败返回 `nil, err`
- handle 仍被对象引用时不要提前释放

### Chart / Meter Handles
- `lv_chart_add_series(chart_id, color[, axis]) -> series`
- `lv_chart_add_cursor(chart_id, color, dir) -> cursor`
- `lv_chart_set_series_color(chart_id, series, color)`
- `lv_chart_hide_series(chart_id, series, hidden)`
- `lv_chart_set_x_start_point(chart_id, series, start_point)`
- `lv_chart_set_all_value(chart_id, series, value)`
- `lv_chart_set_next_value(chart_id, series, value)`
- `lv_chart_set_next_value2(chart_id, series, x_value, y_value)`
- `lv_chart_set_value_by_id(chart_id, series, index, value)`
- `lv_chart_set_value_by_id2(chart_id, series, index, x_value, y_value)`
- `lv_chart_set_cursor_pos(chart_id, cursor, x, y)`
- `lv_chart_set_cursor_point(chart_id, cursor, series_or_nil, point_id)`
- `lv_chart_get_point_pos_by_id(chart_id, series, point_id) -> x, y`
- `lv_meter_add_scale(meter_id) -> scale`
- `lv_meter_set_scale_ticks(meter_id, scale, cnt, width, len, color)`
- `lv_meter_set_scale_major_ticks(meter_id, scale, nth, width, len, color, label_gap)`
- `lv_meter_set_scale_range(meter_id, scale, min, max, angle_range, rotation)`
- `lv_meter_add_arc(meter_id, scale, width, color[, r_mod]) -> indicator`
- `lv_meter_add_needle_line(meter_id, scale, width, color[, r_mod]) -> indicator`
- `lv_meter_add_needle_img(meter_id, scale, img_src, pivot_x, pivot_y) -> indicator`
- `lv_meter_add_scale_lines(meter_id, scale, color_start, color_end, local, width_mod) -> indicator`
- `lv_meter_set_indicator_value(meter_id, indicator, value)`
- `lv_meter_set_indicator_start_value(meter_id, indicator, value)`
- `lv_meter_set_indicator_end_value(meter_id, indicator, value)`

说明：
- `series`、`cursor`、`scale`、`indicator` 是后续接口继续使用的 handle
- `lv_chart_set_cursor_point(..., series_or_nil, ...)` 的 `series_or_nil` 可传 `nil`

### Event Callback
说明：`fn(e)` 接收事件表；`lv_obj_add_event_cb()` 返回的 `event_dsc` 可用于移除回调。
- `lv_obj_add_event_cb(obj_id, fn, event_code[, user_data]) -> event_dsc|nil`
- `lv_obj_remove_event_cb(obj_id, fn) -> bool`
- `lv_obj_remove_event_dsc(obj_id, event_dsc) -> bool`
- `lv_event_get_code(e) -> event_code`
- `lv_event_get_target(e) -> target_id`
- `lv_event_get_current_target(e) -> current_target_id`
- `lv_event_get_user_data(e) -> any`
- `lv_event_get_param(e) -> any`

### Animation
说明：
- 常用顺序：`lv_anim_t()` -> `lv_anim_init()` -> 设置目标/执行函数/取值/时间 -> `lv_anim_start()`
- `exec_cb` 传 `lv_obj_set_x` 等函数 token；自定义执行函数参数为 `(anim_handle, value)`
- `path_cb` 传 `lv_anim_path_linear`、`lv_anim_path_ease_out` 等函数 token

接口：
- `lv_anim_t() -> anim_id`
- `lv_anim_init(anim_id)`
- `lv_anim_reset(anim_id)`
- `lv_anim_set_var(anim_id, obj_id)`
- `lv_anim_set_exec_cb(anim_id, exec_cb)`
- `lv_anim_set_custom_exec_cb(anim_id, lua_fn)`
- `lv_anim_set_values(anim_id, start_value, end_value)`
- `lv_anim_set_time(anim_id, time_ms)`
- `lv_anim_set_delay(anim_id, delay_ms)`
- `lv_anim_set_path_cb(anim_id, path_cb)`
- `lv_anim_set_playback_time(anim_id, time_ms)`
- `lv_anim_set_playback_delay(anim_id, delay_ms)`
- `lv_anim_set_repeat_count(anim_id, count)`
- `lv_anim_set_repeat_delay(anim_id, delay_ms)`
- `lv_anim_set_early_apply(anim_id, en)`
- `lv_anim_set_start_cb(anim_id, lua_fn_or_nil)`
- `lv_anim_set_ready_cb(anim_id, lua_fn_or_nil)`
- `lv_anim_set_deleted_cb(anim_id, lua_fn_or_nil)`
- `lv_anim_set_user_data(anim_id, data)`
- `lv_anim_get_user_data(anim_id) -> data`
- `lv_anim_start(anim_id) -> running_anim_handle|nil`
- `lv_anim_del(obj_id, exec_cb_or_nil) -> bool`
- `lv_anim_del_all()`
- `lv_anim_count_running() -> n`
- `lv_anim_speed_to_time(speed, start, end) -> time_ms`

支持的执行函数：
- `lv_obj_set_x`
- `lv_obj_set_y`
- `lv_obj_set_width`
- `lv_obj_set_height`

路径函数 token：
- `lv_anim_path_linear`
- `lv_anim_path_step`
- `lv_anim_path_ease_in`
- `lv_anim_path_ease_out`
- `lv_anim_path_ease_in_out`
- `lv_anim_path_overshoot`
- `lv_anim_path_bounce`

其他常量：
- `LV_ANIM_REPEAT_INFINITE`

说明：
- `lv_anim_set_start_cb()`、`lv_anim_set_ready_cb()`、`lv_anim_set_deleted_cb()` 的 Lua 回调参数为 `(anim_handle)`
- `lv_anim_get_user_data()` 可在这些回调里通过 `anim_handle` 取回 Lua 侧 user data
- `lv_anim_del(obj_id, nil)` 删除该对象上的全部普通动画，并删除通过 `lv_anim_set_custom_exec_cb()` 启动且 var 为该对象的自定义动画

示例：
```lua
local a = lv_anim_t()
lv_anim_init(a)
lv_anim_set_var(a, obj_id)
lv_anim_set_exec_cb(a, lv_obj_set_x)
lv_anim_set_values(a, 0, 120)
lv_anim_set_time(a, 300)
lv_anim_set_delay(a, 0)
lv_anim_set_path_cb(a, lv_anim_path_ease_out)
lv_anim_start(a)
```

## 半官方 / 项目差异

### GIF
- `lv_gif_create(parent_id) -> gif_id`
- `lv_gif_set_src(gif_id, path_or_nil)`

说明：
- `lv_gif_set_src(gif_id, nil)` 停止并保留最后一帧
- 播放会自动推进；删除对象用 `lv_obj_del(gif_id)`

### Layout Helper
- `lv_pct(value) -> coord` -- 百分比坐标
- `lv_grid_fr(value) -> coord` -- grid fr 单位
- `lv_obj_set_grid_dsc_array(obj_id, col_dsc, row_dsc)` -- Lua table 转 grid 描述数组

### Image Resource
- `lv_img_set_src()`

说明：
- `src` 支持 `S:/...`、`/sd/...`、`.jpg/.jpeg`、`.sjpg`、RGB565 BMP、JPEG binary string

## 自定义接口

### List Internal Objects
说明：以下接口读取 list button 内部子对象。
- `lv_list_get_btn_label(list_id, btn_id) -> label_id|nil`
- `lv_list_get_btn_icon(list_id, btn_id) -> img_id|nil`

### Canvas
说明：
- 推荐格式为 `LV_IMG_CF_TRUE_COLOR`；需要黑色透明键时用 `LV_IMG_CF_TRUE_COLOR_CHROMA_KEYED`
- 高频刷新建议用 `lv_canvas_frame_begin()` / `lv_canvas_frame_end()` 包住一帧
- 用法顺序：`create -> frame_begin -> fill/draw -> frame_end`
- `color` 使用 `0xRRGGBB`，`opa` 使用 `0..255`

常用接口：
- `lv_canvas_create(parent_id, w, h[, fmt]) -> canvas_id`
- `lv_canvas_fill_bg(canvas_id, color[, opa])` -- 填充背景
- `lv_canvas_set_px_color(canvas_id, x, y, color)` / `lv_canvas_set_px_opa(canvas_id, x, y[, opa])`
- `lv_canvas_blit_rgb565(canvas_id, x, y, w, h, data[, opts])`
- `lv_canvas_draw_rect(canvas_id, x, y, w, h, dsc_or_color[, opa])`
- `lv_canvas_draw_line(canvas_id, points[, point_cnt[, dsc]])` 或 `lv_canvas_draw_line(canvas_id, x1, y1, x2, y2, color[, opa[, width]])`
- `lv_canvas_draw_arc(canvas_id, cx, cy, radius, start_deg, end_deg[, dsc_or_color[, opa[, width]]])`
- `lv_canvas_draw_img(canvas_id, x, y, src[, dsc])`
- `lv_canvas_draw_text(canvas_id, x, y, max_w, text[, dsc])`
- `lv_canvas_transform(canvas_id, src_canvas_id, angle, zoom, x, y[, pivot_x, pivot_y[, antialias]])`
- `lv_canvas_blur_hor(canvas_id, area, radius)` / `lv_canvas_blur_ver(canvas_id, area, radius)`
- `lv_canvas_frame_begin(canvas_id)` / `lv_canvas_frame_end(canvas_id)`

参数约定：
- `rect dsc`：`bg_color` `bg_opa` `radius` `border_width` `border_color` `border_opa`
- `line/arc dsc`：`color` `opa` `width`
- `text dsc`：`color` `opa` `align` `font_size` `font_handle`
- `img dsc`：`opa`
- `points` 使用扁平数组：`{x1, y1, x2, y2, ...}`；`point_cnt` 不传时自动推导
- `src` 支持路径字符串、`{ handle = image_or_snapshot_handle }`、`{ canvas_id = other_canvas_id }`
- `area` 传 `nil` 表示整张 canvas，或传 `{x1=..., y1=..., x2=..., y2=...}`
- `lv_canvas_draw_arc()` 的角度单位是度；`lv_canvas_transform()` 的 `angle` 单位是 `0.1` 度，`zoom=256` 表示 `1x`
- `lv_canvas_blit_rgb565()` 的 `data` 是 RGB565 Lua binary string；`opts` 可传 `offset`、`stride`/`stride_bytes`、`byte_order`、`swap_rb`、`full_rewrite`/`full`

兼容接口：
- `lv_canvas_begin(canvas_id)` 等价于 `lv_canvas_frame_begin(canvas_id)`
- `lv_canvas_end(canvas_id)` 等价于 `lv_canvas_frame_end(canvas_id)`
- `lv_canvas_fill(canvas_id, color[, opa])` 等价于 `lv_canvas_fill_bg(canvas_id, color[, opa])`
- `lv_canvas_draw_polyline(canvas_id, points, point_cnt, color[, opa[, width]])` 等价于 `lv_canvas_draw_line(...)`

可用常量：
- `LV_IMG_CF_TRUE_COLOR` `LV_IMG_CF_TRUE_COLOR_ALPHA` `LV_IMG_CF_TRUE_COLOR_CHROMA_KEYED` `LV_RADIUS_CIRCLE`

示例：

```lua
local cvs = lv_canvas_create(root, 304, 186, LV_IMG_CF_TRUE_COLOR)
lv_canvas_frame_begin(cvs)
lv_canvas_fill_bg(cvs, 0x0C1218, 255)
lv_canvas_draw_rect(cvs, 0, 0, 304, 186, {
  bg_color = 0x17222D,
  bg_opa = 255,
  radius = 12
})
lv_canvas_draw_text(cvs, 10, 8, 160, "Canvas", { color = 0xEAF2FA, font_size = 14 })
lv_canvas_frame_end(cvs)
```

## 常量说明

- `LV_ANIM_REPEAT_INFINITE` 是 LVGL 官方常量，可用于 `lv_anim_set_repeat_count()`。
- 动画执行器和路径不再注册项目自定义常量；执行器使用 `lv_obj_set_x` 等函数 token，路径使用 `lv_anim_path_ease_out` 等函数 token。
