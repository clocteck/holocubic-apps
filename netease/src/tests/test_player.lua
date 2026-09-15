http={DELAYACK=99}
local net={pending=nil}
function net.cancel()net.cancelled=true end
function net.poll()end
function net.create(url,opts)
  assert(opts.bufsz==6144)
  local c={cb={},acks=0}
  function c:on(k,f)self.cb[k]=f;return self end
  function c:request()net.last=self end
  function c:close()self.closed=true end
  function c:ack()self.acks=self.acks+1 end
  return c
end
local st={internal_peak_delta=0,buffer_free=0,error=0,status=1,source_rate=44100,written_bytes=0}
local fed=0
local audio={
  close=function()return true end,open=function()return true end,
  pause=function(v)st.paused=v end,state=function()return st end,
  feed=function(data)fed=fed+#data;return #data end,eos=function()st.eos=true end}
local p=dofile(ROOT..'/package/player.lua').new(audio,net,function()return 0 end)
p.play('https://example/audio')
net.last.cb.headers(200,{['content-length']='4'})
assert(net.last.cb.data(200,'abcd')==http.DELAYACK)
assert(fed==0)
st.buffer_free=8192;p.poll();assert(fed==4 and net.last.acks==1)
st.internal_peak_delta=100*1024;st.status=2;p.poll()
assert(p.status=='playing'and p.stats.internal_peak_delta==100*1024 and p.error=='')
p.pause();assert(st.paused)
p.pause();assert(not st.paused)
net.last.cb.complete();assert(st.eos)
st.status=4;p.poll();assert(p.status=='ended')
p.play('https://example/two');local old=net.last
p.play('https://example/three')
old.cb.data(200,'stale');assert(fed==4)
net.last.cb.headers(403,{});assert(p.status=='error')
p.play('https://example/four');net.last.cb.headers(200,{['content-length']='10'})
net.last.cb.data(200,'ab');net.last.cb.complete();assert(p.status=='error')
p.close()
