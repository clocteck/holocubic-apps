-- Shared input adapter. Firmware already converts IMU movements into key events.
local M={}
function M.new(key,now,emit)
  local I={buttons=0,axis=0,connected=false,started={},home_at=nil,home_long=false}
  local dirs={[key.LEFT]={'horizontal',-1},[key.RIGHT]={'horizontal',1},
    [key.UP]={'vertical',-1},[key.DOWN]={'vertical',1}}
  function I.physical(code,event)
    if code==key.HOME then
      if event==key.START then I.physical_long=false
      elseif event==key.LONG_START then I.physical_long=true;emit('exit')
      elseif event==key.SHORT and not I.physical_long then emit('confirm')
      elseif event==key.LONG_END then I.physical_long=false end
      return
    end
    local d=dirs[code];if not d then return end
    if event==key.START then I.started[code]=true;emit('direction',d[1],d[2])
    elseif event==key.SHORT then
      if not I.started[code]then emit('direction',d[1],d[2])end
      I.started[code]=nil
    elseif event==key.LONG_END then I.started[code]=nil end
  end
  function I.pad(pad)
    if type(pad)~='table' or not pad.connected then
      I.buttons=0;I.axis=0;I.connected=false;I.home_at=nil;I.home_long=false;return
    end
    local mask=math.floor(tonumber(pad.buttons)or 0)
    I.connected=true
    local pressed=mask & (~I.buttons);local released=I.buttons & (~mask)
    I.buttons=mask
    if (pressed & 32768)~=0 then I.home_at=now();I.home_long=false end
    if (mask & 32768)~=0 and I.home_at and not I.home_long and now()-I.home_at>=800 then
      I.home_long=true;emit('exit');return
    end
    if (released & 32768)~=0 then
      if not I.home_long then emit('confirm')end
      I.home_at=nil;I.home_long=false
    end
    if (pressed & 16)~=0 then emit('confirm')
    elseif (pressed & 32)~=0 then emit('back')
    elseif (pressed & 8192)~=0 then emit('pause')
    elseif (pressed & 256)~=0 then emit('previous')
    elseif (pressed & 512)~=0 then emit('next')
    elseif (pressed & 4)~=0 then emit('direction','horizontal',-1)
    elseif (pressed & 8)~=0 then emit('direction','horizontal',1)
    elseif (pressed & 1)~=0 then emit('direction','vertical',-1)
    elseif (pressed & 2)~=0 then emit('direction','vertical',1)end
    local x,y=tonumber(pad.lx)or 0,tonumber(pad.ly)or 0
    if math.abs(x)<7000 and math.abs(y)<7000 then I.axis=0 end
    if I.axis==0 and (mask & 15)==0 and math.max(math.abs(x),math.abs(y))>=16000 then
      I.axis=1
      if math.abs(x)>math.abs(y)then emit('direction','horizontal',x>0 and 1 or -1)
      else emit('direction','vertical',y>0 and 1 or -1)end
    end
  end
  return I
end
return M
