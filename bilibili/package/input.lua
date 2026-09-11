-- Timing and key state machine are taken from the installed Launcher v1.30.
-- IMU uses the firmware's key events, exactly like Launcher. No app-side tilt thresholds.
local Input={}
function Input.new(actions)
 local s={left=0,right=0,up=0,up_fired=false,buttons=0,stopped=false,events=0,last="",timers={}}
 local function dispatch(name,...) if s.stopped then return end;s.events=s.events+1;s.last=name;return actions[name](...) end
 function s:handle(code,evt)
  if code==key.LEFT or code==key.RIGHT then
   local name=code==key.LEFT and "left" or "right";local delta=code==key.LEFT and -1 or 1
   if evt==key.START then dispatch("move",delta)
   elseif evt==key.LONG_START then self[name]=0;dispatch("move",delta)
   elseif evt==key.LONG_REPEAT then self[name]=self[name]+1;if self[name]%3==0 then dispatch("move",delta) end
   elseif evt==key.LONG_END then self[name]=0 end
  elseif code==key.UP then
   if evt==key.SHORT then dispatch("item",-1)
   elseif evt==key.LONG_START then self.up=0;self.up_fired=false
   elseif evt==key.LONG_REPEAT then self.up=self.up+1;if self.up>=1 and not self.up_fired then self.up_fired=true;dispatch("confirm") end
   elseif evt==key.LONG_END then self.up=0;self.up_fired=false end
  elseif code==key.DOWN then
   if evt==key.SHORT then dispatch("item",1)
   elseif evt==key.LONG_START then dispatch("back") end
  elseif code==key.HOME and evt==key.SHORT then dispatch("exit") end
 end
 function s:pad(pad)
  local buttons=type(pad)=="table" and tonumber(pad.buttons) or 0
  if type(pad)=="table" and pad.connected==false then buttons=0 end
  buttons=buttons or 0;local pressed=buttons&(~self.buttons);self.buttons=buttons
  -- Launcher uses the same source, masks, 40ms polling and edge-only dispatch.
  if (pressed&4)~=0 then dispatch("move",-1)
  elseif (pressed&8)~=0 then dispatch("move",1)
  elseif (pressed&1)~=0 then dispatch("item",-1)
  elseif (pressed&2)~=0 then dispatch("item",1)
  elseif (pressed&(16|8192))~=0 then dispatch("confirm")
  elseif (pressed&(32|4096))~=0 then dispatch("back")
  elseif (pressed&32768)~=0 then dispatch("exit") end
 end
 function s:start()
  for _,code in ipairs({key.LEFT,key.RIGHT,key.UP,key.DOWN,key.HOME}) do key.on(code,function(evt)self:handle(code,evt)end) end
  if controller and controller.state then local t=tmr.create();self.timers[#self.timers+1]=t;t:alarm(40,tmr.ALARM_AUTO,function()
   local ok,pad=pcall(controller.state,"ble-main");self:pad(ok and pad or nil)
  end) end
 end
 function s:stop() self.stopped=true;key.off();for _,t in ipairs(self.timers) do pcall(function()t:unregister()end) end end
 return s
end
return Input
