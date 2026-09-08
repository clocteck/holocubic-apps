-- One streaming HTTP request at a time. A cancelled request retains ownership
-- until its native complete callback; selecting another station only replaces
-- the pending request. No native socket/firmware changes are required.
local M={}
function M.clock(micros)
  local previous=micros()&0xffffffff
  local elapsed=0
  return function()
    local stamp=micros()&0xffffffff
    elapsed=elapsed+((stamp-previous)&0xffffffff);previous=stamp
    return elapsed/1000
  end
end
function M.new(http,now)
  local N={current=nil,pending=nil,not_before=0,last_error='',counts={started=0,completed=0,cancelled=0,acks=0,close_errors=0,request_errors=0,pool_full_errors=0,peak_active=0}}
  local function failure(c,err)
    N.last_error=tostring(err)
    if not c.cancelled and c.callbacks.error then
      local ok,nested=pcall(c.callbacks.error,N.last_error)
      if not ok then N.last_error=tostring(nested) end
    end
  end
  function N.create(url,options)
    local c={url=url,options=options,callbacks={},paused=false,cancelled=false,finished=false,in_callback=false,data_events=0,received_bytes=0}
    function c:on(event,fn) self.callbacks[event]=fn;return self end
    function c:ack()
      if not self.paused or self.in_callback or self.finished then return true end
      local ok,err=pcall(function()self.raw:ack()end)
      if not ok then N.last_error=tostring(err);return nil,N.last_error end
      self.paused=false;N.counts.acks=N.counts.acks+1;return true
    end
    function c:close()
      if self.finished then return true end
      if not self.cancelled then
        self.cancelled=true;self.cancelled_at=now();N.counts.cancelled=N.counts.cancelled+1
      end
      if N.pending==self then N.pending=nil;self.finished=true;return true end
      if self.close_sent then
        if self.paused and not self.in_callback then return self:ack() end
        return true
      end
      -- Native close is only legal in a callback or while DELAYACK is pending.
      -- In other states the next connect/headers/data callback performs it.
      if self.raw and (self.in_callback or self.paused) then
        local ok,err=pcall(function()self.raw:close()end)
        if not ok then
          N.counts.close_errors=N.counts.close_errors+1;N.last_error=tostring(err)
          return nil,N.last_error
        end
        self.close_sent=true
        -- close sets a flag; ack actually wakes a suspended HTTP task.
        if self.paused and not self.in_callback then return self:ack() end
      end
      return true
    end
    function c:request()
      assert(not self.submitted and not self.finished,'HTTP request already submitted or closed')
      self.submitted=true
      if N.pending then N.pending:close() end
      if N.current then N.current:close() end
      N.pending=self
    end
    return c
  end
  local function dispatch(c,event,...)
    c.last_event=event;c.last_event_at=now()
    if event=='data' then
      local _,data=...
      c.data_events=c.data_events+1
      if type(data)=='string' then c.received_bytes=c.received_bytes+#data end
    end
    if event=='complete' then
      if c.finished then return end
      c.finished=true;c.paused=false
      if N.current==c then N.current=nil end
      if c.close_timeout then N.last_error='' end
      N.counts.completed=N.counts.completed+1
      -- The native completion event can arrive just before task reclamation.
      -- Do not start a successor synchronously inside that callback.
      N.not_before=now()+200
      if not c.cancelled and c.callbacks.complete then
        local ok,err=pcall(c.callbacks.complete,...)
        if not ok then failure(c,err) end
      end
      c.raw=nil;c.callbacks={}
      return
    end
    if c.finished then return end
    c.in_callback=true
    local ok,result=true,nil
    if c.cancelled then
      c:close()
    elseif c.callbacks[event] then
      ok,result=pcall(c.callbacks[event],...)
      if not ok then failure(c,result);c:close() end
    end
    -- A listener may cancel itself while handling data. Never leave that
    -- callback in DELAYACK mode; a normal return lets native code wake it.
    if c.cancelled then c:close();result=nil end
    c.in_callback=false
    if ok and result==http.DELAYACK and not c.cancelled then c.paused=true;return http.DELAYACK end
  end
  function N.poll()
    if N.current then
      local c=N.current
      if c.cancelled and c.paused then c:close() end
      if c.cancelled and now()-c.cancelled_at>15000 then
        c.close_timeout=true
        N.last_error='Waiting for previous HTTP request to finish; no new request opened'
      end
      return
    end
    if not N.pending or now()<N.not_before then return end
    local c=N.pending;N.pending=nil
    if c.cancelled then return end
    N.current=c;c.started_at=now()
    local ok,err=pcall(function()
      c.raw=http.createConnection(c.url,'GET',c.options)
      for _,event in ipairs({'connect','headers','data','complete'}) do
        c.raw:on(event,function(...)return dispatch(c,event,...)end)
      end
      c.raw:request()
    end)
    if not ok then
      N.current=nil;c.finished=true;N.counts.request_errors=N.counts.request_errors+1
      local busy=tostring(err):find('too many in%-flight http requests')~=nil
      if busy then N.counts.pool_full_errors=N.counts.pool_full_errors+1 end
      N.not_before=now()+(busy and 3000 or 1000)
      if c.raw then pcall(function()c.raw:close()end) end
      c.raw=nil;failure(c,err);return
    end
    N.last_error='';N.counts.started=N.counts.started+1;N.counts.peak_active=1
  end
  function N.cancel()
    if N.pending then N.pending:close() end
    if N.current then N.current:close() end
  end
  function N.state()
    local c=N.current;local s={active=c and 1 or 0,pending=N.pending~=nil,
      closing=c and c.cancelled or false,paused=c and c.paused or false,
      close_sent=c and c.close_sent or false,blocked=c and c.close_timeout or false,
      last_event=c and c.last_event or '',data_events=c and c.data_events or 0,
      received_bytes=c and c.received_bytes or 0,
      cancel_age_ms=c and c.cancelled_at and math.max(0,now()-c.cancelled_at) or 0,
      age_ms=c and math.max(0,now()-c.started_at) or 0,error=N.last_error}
    for k,v in pairs(N.counts) do s[k]=v end
    return s
  end
  return N
end
return M
