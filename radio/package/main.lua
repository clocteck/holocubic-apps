local ok,err=xpcall(function() dofile('/sd/apps/radio/radio.lua') end,function(e)return tostring(e)..'\n'..(debug and debug.traceback and debug.traceback() or '') end)
if not ok then
  print('[radio boot]',err)
  file.putcontents('/sd/apps/radio/boot-error.txt',err)
  local root=lv_scr_act();lv_obj_clean(root)
  local label=lv_label_create(root);lv_obj_set_width(label,300);lv_label_set_text(label,'Radio error\n'..tostring(err))
end
