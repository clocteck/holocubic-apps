-- Shared master-volume adapter. Keep package copies identical (tools/test_volume.py).
-- New firmware: memory-backed sys API; old firmware: one read, session-only edits.
local M = {}
local function valid(v)
  return type(v) == "number" and v == v and v >= 0 and v <= 100
end
function M.new()
  local V = {value=25, supported=type(sys)=="table" and type(sys.getvolume)=="function"
    and type(sys.setvolume)=="function", error=nil}
  local function report(err)
    err = err and tostring(err) or nil
    if V.error ~= err then
      V.error = err
      if V.on_error then V.on_error(err) end
    end
  end
  if V.supported then
    local ok,n = pcall(sys.getvolume)
    if ok and valid(n) then V.value=math.floor(n) else report("Cannot read firmware volume") end
  elseif file and file.getcontents then
    local ok,raw=pcall(file.getcontents,"/sd/apps/settings.json")
    local codec=rawget(_G,"json") or rawget(_G,"sjson")
    if ok and type(raw)=="string" and codec and codec.decode then
      local decoded,doc=pcall(codec.decode,raw)
      if decoded and type(doc)=="table" and valid(doc.volume) then V.value=math.floor(doc.volume) end
    end
  end
  local function apply()
    if V.apply and V.applied ~= V.value then
      local ok,result,err=pcall(V.apply,V.value)
      if not ok or result==false or (result==nil and err~=nil) then
        report(err or result or "Volume apply failed"); return nil,V.error
      end
      V.applied=V.value
    end
    return true
  end
  function V.poll()
    if V.supported then
      local ok,n=pcall(sys.getvolume)
      if not ok or not valid(n) then report("Cannot read firmware volume");return nil,V.error end
      V.value=math.floor(n)
    end
    local ok,err=apply()
    if not ok then return nil,err end
    if V.supported and type(sys.getvolumestate)=="function" then
      local good,state=pcall(sys.getvolumestate)
      if good and type(state)=="table" then
        V.pending=state.pending
        report(state.error~="" and state.error or nil)
      else report("Cannot read volume save status") end
    else report(nil) end
    return true
  end
  function V.set(n)
    if not valid(n) then return nil,"Volume must be 0..100" end
    n=math.floor(n+0.5)
    if V.supported then
      local ok,result,err=pcall(sys.setvolume,n)
      if not ok or not result then report(err or result or "Cannot set firmware volume");return nil,V.error end
    end
    V.value=n
    return V.poll()
  end
  function V.start(fn)
    V.stop()
    V.apply=fn
    V.applied=nil
    V.poll()
    if V.supported and tmr and tmr.create then
      V.timer=tmr.create()
      V.timer:alarm(200,tmr.ALARM_AUTO,function() V.poll() end)
    end
    return V
  end
  function V.stop()
    if V.timer then
      pcall(function() V.timer:unregister() end)
      V.timer=nil
    end
  end
  return V
end
return M
