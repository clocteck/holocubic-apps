local Lyrics=dofile(ROOT..'/package/lyrics.lua')
local View=dofile(ROOT..'/package/ui_view.lua')
local clock=0
local requests={}
local p={busy=false,generation=0}
function p.lyric(id,cb)
  p.busy=true;p.generation=p.generation+1
  requests[#requests+1]={id=id,cb=cb}
end
local function reply(doc,err)
  p.busy=false;p.generation=p.generation+1
  requests[#requests].cb(doc,err)
end
local l=Lyrics.new(p,function()return clock end)
local good={code=200,lrc={lyric='[00:02.50]second\n[00:00.10][00:01.20]first'}}
l.start(1)
assert(l.status=='loading'and View.lyrics(l.lines,0,l.status)[3]=='加载中')
l.poll(true);assert(#requests==0)
l.enable();l.poll(false);assert(#requests==0)
l.poll(true);assert(#requests==1 and l.attempts==1)
reply(nil,'network');assert(l.status=='loading')
l.poll(true);assert(#requests==1)
clock=999;l.poll(true);assert(#requests==1)
clock=1000;l.poll(true);assert(#requests==2)
reply(good)
assert(l.status=='ready'and #l.lines==3 and l.lines[1].at==.1)
assert(View.lyrics(l.lines,1.5,l.status)[3]=='first')
-- A successful explicit empty result needs no retry.
for _,doc in ipairs({{code=200,nolyric=true},{code=200,uncollected=true},{code=200,lrc={lyric=''}}})do
  l.start(2);l.enable();l.poll(true);local count=#requests;reply(doc)
  assert(l.status=='empty'and View.lyrics(l.lines,0,l.status)[3]=='暂无歌词')
  clock=clock+9999;l.poll(true);assert(#requests==count)
end
-- Failures and malformed replies exhaust exactly three attempts, never flash empty in between.
l.start(3);l.enable()
for attempt=1,3 do
  l.poll(true);assert(l.attempts==attempt)
  reply(attempt==2 and {code=200}or nil,'failed')
  assert(l.status==(attempt==3 and 'empty'or 'loading'))
  clock=clock+attempt*1000
end
local count=#requests;l.poll(true);assert(#requests==count)
-- Blank whitespace-only lines and metadata do not occupy rows or become the active lyric.
local parsed=Lyrics.parse({code=200,lrc={lyric='[ar:artist]\n[00:00] \t\n[00:01]　\n[00:02]\194\160\n[00:03]\226\128\139\n[00:04]first\n[00:05]\n[00:06][00:07]second'}})
assert(#parsed==3 and parsed[1].at==4 and parsed[2].at==6 and parsed[3].at==7)
assert(View.lyrics(parsed,5,'ready')[3]=='first')
assert(#Lyrics.parse({lrc={lyric='[00:01] \t　'}})==0)
assert(Lyrics.parse({code=200,lrc={}})==nil)
assert(Lyrics.parse({code=500})==nil)
-- Old song responses and callbacks after shutdown cannot overwrite the new state.
l.start(4);l.enable();l.poll(true);local old=requests[#requests]
l.start(5);old.cb(good);assert(l.status=='loading'and #l.lines==0)
p.busy=false;l.enable();l.poll(true);reply(good);assert(l.status=='ready')
l.start(6);l.enable();l.poll(true);old=requests[#requests]
l.cancel();old.cb(good);assert(l.status=='empty'and #l.lines==0)
-- Shared-provider cancellation is noticed and retried when the provider becomes idle.
p.busy=false;l.start(7);l.enable();l.poll(true)
p.generation=p.generation+1;l.poll(true);assert(not l.active and l.status=='loading')
clock=clock+1000;p.busy=false;l.poll(true);reply(good)
assert(l.status=='ready'and l.attempts==2)
