-- Run under both the normal host suite and the firmware's int32/float32 Lua.
local T=dofile(ROOT..'/package/transport.lua')
local function source(seed)
  local stamp=seed or 0
  local now=T.clock(function()return stamp end)
  local function advance(us)stamp=(stamp+us)&0xffffffff;return now()end
  return now,advance
end
-- Signed boundary, hardware wrap, and app uptime beyond 35.8/71.6 minutes.
for _,seed in ipairs({0,0x7ffff000,0xfffff000})do
  local now,advance=source(seed)
  assert(now()==0)
  for i=1,50000 do assert(advance(100000)==i*100,'clock wrapped or drifted')end
end
-- Frequent reads must retain fractional microseconds, not round each delta.
do
  local now,advance=source()
  for i=1,100000 do assert(advance(17)==(i*17)//1000)end
  assert(now()==1700)
end
-- Also decode a delta whose high bit is set, without a signed/float conversion.
do
  local now,advance=source()
  assert(advance(0x80000000)==2147483)
  assert(advance(352)==2147484)
  now,advance=source();assert(advance(0xffffffff)==4294967)
  assert(advance(705)==4294968)
end
-- Exact small increments after seven days; a float32 accumulator would stall.
do
  local now,advance=source()
  for i=1,604 do advance(1000000000)end
  advance(800000000)
  assert(now()==604800000 and math.type(now())=='integer')
  for i=1,1000 do advance(1000)end
  assert(now()==604801000)
end
-- Thirty days, beyond the int32 millisecond range: no backward jump or stall.
-- Switch readings before deadline additions approach the signed boundary.
do
  local now,advance=source()
  for i=1,1999 do advance(1000000000)end
  advance(999999000)
  local before=now()
  assert(before==1999999999 and before+86400000>before)
  advance(1000)
  assert(now()>=before and now()+120000>now())
end
do
  local now,advance=source()
  local previous=0
  for i=1,2592 do
    local current=advance(1000000000)
    assert(current>previous and math.abs(current-i*1000000.0)<=256)
    previous=current
  end
  local before=now()
  for i=1,10000 do advance(1000)end
  assert(now()>before+9000,'long-uptime clock stopped progressing')
end
-- Real transport dispatch/200ms cooldown/10s queue expiry across old overflow.
do
  local now,advance=source()
  advance(1000000000);advance(1000000000);advance(147400000)
  local requests={}
  local http={}
  function http.createConnection()
    local c={cb={}}
    function c:on(event,fn)self.cb[event]=fn end
    function c:request()requests[#requests+1]=self end
    function c:close()end
    return c
  end
  local net=T.new(http,now)
  local a=net.create('https://example.invalid/one',{});a:request();net.poll()
  assert(#requests==1);requests[1].cb.complete()
  local b=net.create('https://example.invalid/two',{});b:request()
  advance(100000);net.poll();assert(#requests==1)
  advance(100000);net.poll();assert(#requests==2,'request stuck after old overflow')
  requests[2].cb.complete()
  local c=net.create('https://example.invalid/three',{})
  local failed=false;c:on('error',function()failed=true end);c:request()
  advance(10001000);net.poll(false)
  assert(failed and #requests==2 and not net.state().pending)
end
print('Clock checks passed: int32 boundaries, 7/30-day uptime, fractions, transport dispatch/timeout.')
