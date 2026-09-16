-- Preload a bounded RGB565 image; never expose an unresolved file source.
local M={}
function M.show(root,dir)
  local B={ready=false,error='',handle=nil,image=nil}
  function B.close()
    if B.image then pcall(lv_img_set_src,B.image,nil);B.image=nil end
    if B.handle then pcall(lv_img_free_handle,B.handle);B.handle=nil end
  end
  if type(lv_img_load_bmp565)~='function'then B.error='image loader unavailable';return B end
  local ok,handle=pcall(lv_img_load_bmp565,dir..'boot.bmp')
  if not ok or type(handle)~='number'or handle<=0 then B.error='startup icon unavailable';return B end
  B.handle=handle
  local good=pcall(function()
    B.image=lv_img_create(root)
    lv_obj_add_flag(B.image,LV_OBJ_FLAG_HIDDEN)
    lv_img_set_src(B.image,handle)
    lv_img_set_pivot(B.image,0,0);lv_img_set_zoom(B.image,213)
    lv_obj_set_pos(B.image,120,64)
    lv_obj_clear_flag(B.image,LV_OBJ_FLAG_HIDDEN)
  end)
  if not good then
    local image=B.image;B.close()
    if image and lv_obj_del then pcall(lv_obj_del,image)end
    B.error='startup icon display failed';return B
  end
  B.ready=true;return B
end
return M
