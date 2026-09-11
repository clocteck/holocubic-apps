local DIR='/sd/apps/bilibili'
local old=rawget(_G,'BILIBILI_APP');if old and old.stop then pcall(old.stop)end
local APP={stopped=false};_G.BILIBILI_APP=APP
local function module(name)local f,err=loadfile(DIR..'/'..name..'.lua');assert(f,err);return f()end
local function boot()
 local U=module('util');local QR=module('qrcode');local Backend=module('backend');local UI=module('ui');local Input=module('input');local Web=module('web')
 APP.U=U;APP.backend=Backend.new(U,QR,DIR);APP.ui=UI.new(U,DIR)
 local B,V=APP.backend,APP.ui
 if B.uid=='' then V.page=8 end
 B.on_change=function()V.dirty=true;if not V.busy then V:render(B:snapshot())end end
 local function snapshot()local s=B:snapshot();s.ui={page=V.page,index=V.index,metric=V.metric,period=V.period,creator_latest=V.creator_latest,animating=V.busy,error=V.error};s.input={events=APP.input and APP.input.events or 0,last=APP.input and APP.input.last or '',profile='launcher-v1.30'};s.version='0.1.0';s.runtime_error=APP.last_error;return s end
 APP.snapshot=snapshot
 local function login()local ok,err=B:start_login();V:jump(8,B:snapshot());return ok,err end
 local function confirm()
  if V.busy then return end
  if V.editor then local uid=table.concat(V.editor.digits):gsub('^0+','');local ok,err=B:set_uid(uid);if ok then V:jump(1,B:snapshot())else V.editor.error=err;V:render(B:snapshot())end
  elseif V.page==8 then
   if B.qr.matrix then login()
   elseif B.signed_in then
    if V.account_selection==1 then V:jump(1,B:snapshot())elseif V.account_selection==2 then login()else B:logout();V:jump(8,B:snapshot())end
   elseif V.account_selection==2 then V:edit_uid(B.uid,B:snapshot())else login()end
  elseif (V.page==2 or V.page==5 or V.page==6 or V.page==7 or V.page==9) and not B.signed_in then login()
  elseif V.page==7 then V.period=V.period==7 and 30 or 7;V:render(B:snapshot())
  elseif V.page==2 then V.creator_latest=not V.creator_latest;V:render(B:snapshot())
  elseif V.page==1 then V:jump(2,B:snapshot())
  else B:refresh()end
 end
 local function back()if V.editor then V.editor=nil;V:render(B:snapshot())elseif V.page==1 then app.exit()else V:jump(1,B:snapshot())end end
 local function home()if V.editor then V.editor=nil;V:render(B:snapshot())else app.exit()end end
 APP.input=Input.new({move=function(d)V:move(d,B:snapshot())end,item=function(d)V:item(d,B:snapshot())end,confirm=confirm,back=back,exit=home})
 function APP.control(p)
  local action=p.action
  if action=='reload_ui' then local page=V.page;local UpdatedUI=module('ui');V:stop();APP.ui=UpdatedUI.new(U,DIR);V=APP.ui;V:jump(page,B:snapshot());return true
  elseif action=='page' then local n=tonumber(p.page);if not n or n%1~=0 or n<1 or n>9 then return false,'页面无效' end;return V:jump(n,B:snapshot())
  elseif action=='previous' then return V:move(-1,B:snapshot())
  elseif action=='next' then return V:move(1,B:snapshot())
  elseif action=='up' then V:item(-1,B:snapshot())
  elseif action=='down' then V:item(1,B:snapshot())
  elseif action=='confirm' then confirm()
  elseif action=='back' then back()
  elseif action=='login' then return login()
  elseif action=='logout' then B:logout();V:jump(8,B:snapshot())
  elseif action=='uid' then local ok,err=B:set_uid(p.uid);if ok then V:jump(1,B:snapshot())end;return ok,err
  elseif action=='refresh' then return B:refresh()
  elseif action=='capture' then return V:capture()
  else return false,'未知操作' end;return true
 end
 APP.web=Web.new(U,DIR,APP);APP.web:start();APP.input:start()
 if app.set_home_exit then app.set_home_exit(false)end
 V:render(B:snapshot());B:refresh()
 APP.tick=tmr.create();local last_second=0
 APP.tick:alarm(200,tmr.ALARM_AUTO,function()
  if APP.stopped then return end
  if app.exiting and app.exiting() then APP.stop();return end
  local ok,err=pcall(function()
   B:prioritize_image(V.page,V.index);B:tick()
   if B.auto_login_needed and not V.busy then login()
   elseif V.page==8 and not V.editor and not B.signed_in and B.qr.status=='expired' then B:start_login() end
   local second=U.now();if V.dirty or (V.page==8 and second~=last_second)then V:render(B:snapshot())end;last_second=second
  end)
  if not ok then APP.last_error=tostring(err):sub(1,180)end
 end)
end
function APP.stop()
 if APP.stopped then return end;APP.stopped=true
 if APP.tick then pcall(function()APP.tick:unregister()end)end
 if APP.input then pcall(function()APP.input:stop()end)end
 if APP.backend then pcall(function()APP.backend:stop()end)end
 if APP.web then pcall(function()APP.web:stop()end)end
 if APP.ui then pcall(function()APP.ui:stop()end)end
 if app.set_home_exit then pcall(app.set_home_exit,true)end
 _G.BILIBILI_APP=nil
end
APP.shutdown=APP.stop
local ok,err=pcall(boot)
if not ok then
 local message=tostring(err);APP.stop();pcall(file.putcontents,DIR..'/startup-error.txt',message)
 error('Bilibili startup: '..message)
end
