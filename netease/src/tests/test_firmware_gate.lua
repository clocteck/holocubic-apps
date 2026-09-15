local gate=dofile((ROOT and (ROOT..'/package/')or '')..'firmware_gate.lua')
for _,v in ipairs({'1.211','1.212','1.999','1.1000','2.0','1.211.1','v1.211',' 1.211 ','1.211+build'})do
  assert(gate.supported(v),'must accept '..v)
end
for _,v in ipairs({'1.210','1.20','0.999','1.211-rc1','','unknown','1.211oops','1.211.','1.211.1.2','1','NaN'})do
  assert(not gate.supported(v),'must reject '..v)
end
assert(not gate.supported(1.211))
assert(not gate.check(nil))
assert(not gate.check({}))
assert(not gate.check({version=function()error('unavailable')end}))
assert(gate.check({version=function()return '1.211'end}))
-- An unsupported main must show an actionable error before UI/native/network startup.
local main=read_source and read_source(ROOT..'/package/main.lua')or read_module('main.lua')
local original=dofile
dofile=function(path)
  assert(path:match('firmware_gate%.lua$'),'unexpected startup module '..path)
  return gate
end
local shown,freed,exited,home='',0,0,nil
lv_scr_act=function()return 0 end;lv_obj_clean=function()end
lv_obj_set_style_bg_color=function()end;lv_obj_set_style_bg_opa=function()end
lv_label_create=function()return 1 end;lv_obj_set_width=function()end;lv_obj_set_pos=function()end
lv_obj_set_style_text_color=function()end;lv_obj_set_style_text_font=function()end
lv_label_set_text=function(_,text)shown=text end
lv_font_load=function()return 12 end;lv_font_free=function()freed=freed+1 end
app={set_home_exit=function()return true end,exit=function()exited=exited+1 end}
key={HOME=1,LONG_START=2,on=function(_,fn)home=fn end,off=function()end}
tmr={create=function()error('must not schedule normal startup')end}
require=function()error('must not load native module')end
file={getcontents=function()error('must not read account data')end}
sys={version=function()return '1.210'end}
assert(load(main))()
assert(shown:find('请更新到最新系统固件',1,true)and shown:find('1.211',1,true))
local a=rawget(_G,'NETEASE_APP')or rawget(_G,'QQMUSIC_APP')
assert(a.version_blocked and a.audio==nil and a.provider==nil)
home(key.LONG_START);assert(exited==1 and freed==1)
dofile=original
