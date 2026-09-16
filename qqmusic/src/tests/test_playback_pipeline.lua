local clock=0
local function now()return clock end
local function network()
  local n={requests={}}
  function n.cancel()end
  function n.poll()end
  function n.create(url,options)
    local c={callbacks={},options=options}
    function c:on(k,v)self.callbacks[k]=v end
    function c:request()self.submitted_at=clock;n.requests[#n.requests+1]=self;n.last=self end
    function c:close()self.closed=true end
    function c:ack()end
    return c
  end
  return n
end
local Provider=dofile(ROOT..'/package/provider.lua')
local doc={}
local json={encode=function()return '{}'end,decode=function()return doc end}
local store={load=function()return nil end}
local native={eapi=function()return 'test'end,weapi=function()return 'test'end}
local bgnet,urlnet=network(),network()
local bg=Provider.new(native,bgnet,json,store,now)
local urgent=bg.fork(urlnet)
local function get(p,done)
  if Provider.song then p.url({id='one',mid='one',media_mid='one'},done)else p.url(1,done)end
end
local reply,reason
get(urgent,function(item,e)reply=item;reason=e end)
bg.cancel()
local c=urlnet.last
clock=9000;c.started_at=clock;c.callbacks.start()
clock=15000;urgent.poll();assert(urgent.busy,'queue wait must not consume network budget')
c.callbacks.headers(200,{})
doc=Provider.song and {code=0,req_0={code=0,data={midurlinfo={{purl='M500one.mp3?vkey=fake'}},
  sip={'https://a.stream.qqmusic.qq.com/','https://b.stream.qqmusic.qq.com/','https://evil.example/'}}}}
  or {code=200,data={{url='https://example.test/one.mp3',type='mp3'}}}
c.callbacks.data(200,'{}');c.callbacks.complete()
assert(reply and not reason,'browse cancel must not invalidate URL channel')
if Provider.song then assert(#reply.urls==2)end
get(urgent,function(item,e)reply=item;reason=e end)
clock=clock+10001;urgent.poll();assert(not urgent.busy and reason,'queue timeout must be bounded')
get(urgent,function(item,e)reply=item;reason=e end)
c=urlnet.last;c.started_at=clock;c.callbacks.start()
clock=clock+10001;urgent.poll();assert(not urgent.busy and urgent.diagnostics.retryable,'first-byte timeout')

local p={diagnostics={retryable=false},cancel=function()end,poll=function()end}
local calls={}
local R=dofile(ROOT..'/package/url_cache.lua').new(p,now,function(song,done)calls[#calls+1]={song=song,done=done}end)
local got
R.get({id=1},function(v)got=v end)
calls[#calls].done({url='https://private.example/one?secret=never-log',expi=20})
assert(got and not R.busy)
local count=#calls
R.get({id=1},function(v)got=v end);assert(#calls==count and R.hits==1)
clock=clock+16000;R.get({id=1},function(v)got=v end);assert(#calls==count+1)
local stale=calls[#calls]
R.get({id=2},function(v)got=v end);stale.done({url='https://stale.example/'})
assert(R.busy,'stale result overwrote a newer request')
p.diagnostics.retryable=true;calls[#calls].done(nil,'network')
clock=clock+500;R.poll();assert(#calls==count+3)
calls[#calls].done({url='https://private.example/two'})
assert(not R.busy and got.url:find('/two'))
R.get({id=3},function(v)got=v end);p.diagnostics.retryable=false;calls[#calls].done(nil,'permission')
count=#calls;clock=clock+2000;R.poll();assert(#calls==count and not R.busy and not got)
for id=4,8 do R.get({id=id},function()end);calls[#calls].done({url='https://private.example/'..id})end
assert(R.state().entries==3 and #R.order==3)
local function safe(v)for _,x in pairs(v)do if type(x)=='table'then safe(x)elseif type(x)=='string'then assert(not x:find('https?://'))end end end
safe(R.state());R.clear();assert(R.state().entries==0)

local net=network()
http={DELAYACK=99}
local state={error=0,status=1,source_rate=44100,written_bytes=0,buffer_free=100000}
local audio={close=function()return true end,open=function()state.written_bytes=0;return true end,
  state=function()return state end,feed=function(s)return #s end,eos=function()end,pause=function()end}
local P=dofile(ROOT..'/package/player.lua').new(audio,net,now)
P.play({urls={'https://first.example/','https://second.example/'}})
c=net.last;c.started_at=clock;c.callbacks.start();c.callbacks.headers(503,{})
assert(P.retry_at and P.status=='buffering')
clock=clock+500;P.poll();assert(P.attempt==2 and P.metrics.node==2)
c=net.last;c.started_at=clock;c.callbacks.start();c.callbacks.headers(200,{})
c.callbacks.data(200,'frame');state.written_bytes=100;state.status=2;P.poll()
assert(P.audible and P.metrics.first_pcm_ms)
c.callbacks.error();assert(P.status=='error'and not P.retry_at,'do not restart already-audible audio from the beginning')
P.play('https://one.example/')
c=net.last;c.started_at=clock;c.callbacks.start();c.callbacks.headers(403,{})
assert(P.status=='error'and P.error_kind=='cdn_auth'and not P.retry_at)
P.play('https://one.example/')
clock=clock+9000;P.poll();assert(P.status~='error','queue time became first-byte timeout')
c=net.last;c.started_at=clock;c.callbacks.start()
clock=clock+7001;P.poll();assert(P.retry_at,'missing first byte must retry finitely')
P.stop();clock=clock+1000;P.poll();assert(P.status=='idle')
