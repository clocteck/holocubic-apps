-- Block unsupported firmware before loading native modules or account/network code.
local M={MINIMUM='1.211',MESSAGE='请更新到最新系统固件'}
function M.supported(value)
  if type(value)~='string' then return false end
  local text=value:match('^%s*(.-)%s*$'):gsub('^[vV]','')
  local core,suffix=text:match('^(%d+%.%d+%.?%d*)(.*)$')
  if not core or core:sub(-1)=='.' then return false end
  if suffix~='' and not suffix:match('^[%+%-][%w%.%-]+$')then return false end
  local parts={}
  for part in core:gmatch('%d+')do
    if #part>6 then return false end
    parts[#parts+1]=tonumber(part)
  end
  local minimum={1,211,0}
  for i=1,3 do
    local n=parts[i]or 0
    if n~=minimum[i]then return n>minimum[i]end
  end
  return suffix:sub(1,1)~='-'
end
function M.check(system)
  if type(system)~='table'or type(system.version)~='function'then return false,'unknown' end
  local ok,value=pcall(system.version)
  if not ok or type(value)~='string'then return false,'unknown'end
  return M.supported(value),value
end
function M.show(dir,current,on_exit)
  local root=lv_scr_act();lv_obj_clean(root)
  local part=LV_PART_MAIN or 0
  lv_obj_set_style_bg_color(root,0,part);lv_obj_set_style_bg_opa(root,255,part)
  local font
  if lv_font_load then local ok,f=pcall(lv_font_load,dir..'/font/ui13.bin');if ok and f and f~=0 then font=f end end
  local label=lv_label_create(root);lv_obj_set_width(label,296);lv_obj_set_pos(label,12,65)
  lv_obj_set_style_text_color(label,0xFFFFFF,part)
  if font then lv_obj_set_style_text_font(label,font,part)end
  local message=M.MESSAGE..'\n需要系统版本 1.211 及以上\n\n当前版本: '..tostring(current):sub(1,48)..'\n长按 Home 退出'
  if not font then message=M.MESSAGE..'\nUpdate system firmware to 1.211+\nHold Home to exit'end
  lv_label_set_text(label,message)
  if app and app.set_home_exit then pcall(app.set_home_exit,false)end
  if key and key.on then key.on(key.HOME,function(event)if event==key.LONG_START then on_exit()end end)end
  if lv_refr_now then pcall(lv_refr_now,nil)end
  return function()
    lv_obj_clean(root)
    if font and lv_font_free then pcall(lv_font_free,font);font=nil end
  end
end
return M
