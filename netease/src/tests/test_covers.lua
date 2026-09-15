local covers=dofile(ROOT..'/package/covers.lua')
local url='https://p3.music.126.net/example.jpg'
assert(covers.thumbnail(url)==url..'?param=92y92')
assert(covers.thumbnail(url..'?param=136y136#old')==url..'?param=92y92')
assert(covers.thumbnail('http://p4.music.126.net/example.jpg')=='https://p4.music.126.net/example.jpg?param=92y92')
assert(covers.thumbnail('https://example.org/no.jpg')==nil)
local jpeg=string.char(255,216,255,192,0,11,8,0,92,0,92,1,1,17,0,255,217)
local w,h=covers.jpeg_size(jpeg);assert(w==92 and h==92)
local clock,requests=0,{}
local provider={busy=false};local player={status='idle',stats={buffer_bytes=200000}}
local net={}
function net.create(u,opts)
  local c={callbacks={},url=u,options=opts}
  function c:on(k,fn)self.callbacks[k]=fn end
  function c:request()requests[#requests+1]=self end
  function c:close()self.finished=true end
  return c
end
local cache=covers.new(net,provider,player,function()return clock end)
local function respond(code,data,length)
  local c=requests[#requests]
  c.callbacks.headers(code,{['content-length']=tostring(length or #data)})
  c.callbacks.data(code,data);c.callbacks.complete();c.finished=true;cache.poll()
end
cache.want({url});clock=300;cache.poll();assert(#requests==1)
respond(503,'');assert(cache.state(url).last_error=='http_503')
cache.poll();assert(#requests==1)
clock=2300;cache.poll();assert(#requests==2)
respond(200,jpeg);assert(cache.get(url)==jpeg and cache.state(url).ready)
for i=1,10 do clock=clock+1000;cache.poll()end
assert(#requests==2 and #cache.order==1)
local p4=url:gsub('p3.music','p4.music')
cache.want({p4,url});clock=clock+300;cache.poll()
assert(cache.get(p4)==jpeg and #requests==2 and #cache.order==1)
assert(#cache.wanted==1 and cache.wanted[1]==covers.thumbnail(p4))
local retry='https://p3.music.126.net/retry.jpg'
cache.want({retry});clock=clock+300
for i=1,3 do
  cache.poll();respond(200,'truncated',100)
  assert(cache.state(retry).last_error=='incomplete')
  clock=clock+7000
end
local count=#requests;cache.poll();assert(#requests==count)
cache.want({});cache.want({retry});clock=clock+300;cache.poll()
assert(#requests==count+1);respond(200,jpeg)
local extra='https://p3.music.126.net/next.jpg'
cache.want({extra});clock=clock+300
provider.busy=true;cache.poll();assert(#requests==count+1)
provider.busy=false;player.status='playing';player.stats.buffer_bytes=100
cache.poll();assert(#requests==count+1)
player.stats.buffer_bytes=200000;cache.poll();assert(#requests==count+2)
respond(200,jpeg,999999);assert(cache.state(extra).last_error=='too_large')
assert(cache.state('no-url').has_url==false)
cache.close()
-- A cache miss must still download the exact host supplied by the provider.
cache=covers.new(net,provider,{status='idle'},function()return clock end)
local before=#requests
cache.want({p4});clock=clock+300;cache.poll()
assert(#requests==before+1 and requests[#requests].url==covers.thumbnail(p4))
respond(200,jpeg)
cache.want({url});clock=clock+300;cache.poll()
assert(cache.get(url)==jpeg and #requests==before+1 and #cache.order==1)
cache.close()
