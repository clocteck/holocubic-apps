local Boot=dofile(ROOT..'/package/boot_icon.lua')
local shown,loaded,cleared,freed,created=false,false,false,0,0
lv_img_load_bmp565=function(path)assert(path=='/sd/apps/test/boot.bmp');return 7 end
lv_img_create=function(root)created=created+1;return 9 end
lv_obj_add_flag=function()shown=false end
lv_img_set_src=function(id,source)
  if source==nil then cleared=true else assert(not shown and source==7);loaded=true end
end
lv_img_set_pivot=function()assert(not shown)end
lv_img_set_zoom=function(id,zoom)assert(not shown and zoom==213)end
lv_obj_set_pos=function(id,x,y)assert(not shown and x==120 and y==64)end
lv_obj_clear_flag=function()assert(loaded);shown=true end
lv_img_free_handle=function(h)assert(h==7 and cleared);freed=freed+1 end
lv_obj_del=function()end
local b=Boot.show(1,'/sd/apps/test/')
assert(b.ready and shown and b.error=='')
b.close();b.close();assert(freed==1)
lv_img_load_bmp565=function()return 0 end
b=Boot.show(1,'/sd/apps/test/');assert(not b.ready and created==1,'must not create an unresolved image')
lv_img_load_bmp565=function()error('missing')end
b=Boot.show(1,'/sd/apps/test/');assert(not b.ready and created==1)
lv_img_load_bmp565=function()return 7 end
lv_img_set_zoom=function()error('display failure')end
b=Boot.show(1,'/sd/apps/test/');assert(not b.ready and freed==2)
