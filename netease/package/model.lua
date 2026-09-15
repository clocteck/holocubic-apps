-- Pure navigation/gesture logic, independently testable without LVGL.
local M={}
function M.new()
  local S={page='login',tab=1,cursor=1,items={},queue={},index=1,armed=true,last_gesture=-10000}
  function S.direction(axis,delta)
    if S.page=='login'then return 'none' end
    if axis=='vertical'then
      if S.page=='player'or S.page=='library'or S.page=='about'then
        local pages={'player','library','about'}
        local index=S.page=='player'and 1 or S.page=='library'and 2 or 3
        S.page=pages[(index-1+delta)%3+1]
      else S.page='library';S.cursor=1 end
      return 'render'
    end
    if S.page=='player'then return delta<0 and 'previous' or 'next'
    elseif S.page=='about'then return 'render'
    elseif S.page=='library'then S.tab=(S.tab-1+delta)%3+1
    elseif #S.items>0 then S.cursor=(S.cursor-1+delta)%#S.items+1 end
    return 'render'
  end
  function S.home()
    if S.page=='login'then return 'login'
    elseif S.page=='player'then return 'pause'
    elseif S.page=='library'then return 'library'
    elseif S.page=='about'then return 'player'
    else return 'select'end
  end
  function S.gesture(roll,pitch,ms)
    roll=tonumber(roll)or 0;pitch=tonumber(pitch)or 0
    if math.abs(roll)<10 and math.abs(pitch)<10 then S.armed=true;return end
    if not S.armed or ms-S.last_gesture<650 then return end
    if math.max(math.abs(roll),math.abs(pitch))<24 then return end
    S.armed=false;S.last_gesture=ms
    if math.abs(roll)>=math.abs(pitch)then return 'horizontal',roll>0 and 1 or -1 end
    return 'vertical',pitch>0 and 1 or -1
  end
  return S
end
return M
