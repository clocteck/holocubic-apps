local original=dofile
local clock,timers,pending=0,{},{}
local audio={baseline=function()end,effects=function()return true end,volume=function()end}
local player={status='idle',position=0,stats={buffer_bytes=300000,psram_free=3000000},plays=0}
function player.stop()player.status='idle';return true end
function player.play(item)player.status='playing';player.plays=player.plays+1 end
function player.pause()end
function player.poll()end
function player.close()end
local p={session={musicid='1',nickname='Tester'},diagnostics={},generation=0}
function p.cancel()p.generation=p.generation+1;p.busy=false end
function p.poll()end
function p.close()end
local songs={}
for i=1,3 do songs[i]={id=tostring(i),mid=tostring(i),media_mid=tostring(i),name='song'..i,ar={},al={}}end
function p.favorites(offset,done)done({songs=songs,total=3})end
function p.top(id,offset,done)done({songs=songs,total=3})end
function p.account(done)done({name='Tester'})end
function p.membership(done)done({name='未知',known=false})end
function p.logout()p.session={};return true end
function p.fork()
  local child={generation=0,diagnostics={},busy=false}
  function child.cancel()child.generation=child.generation+1;child.busy=false end
  function child.poll()end
  function child.close()end
  function child.url(song,done)child.busy=true;pending[#pending+1]=done end
  function child.lyric(id,done)done({lrc={lyric='[00:00]line'}})end
  return child
end
local ui={ready=true,render=function()end,load_next=function()return true end,qr=function()end,close=function()end}
local replacements={
 ['ui.lua']=function()return ui end,
 ['provider.lua']={new=function()return p end},
 ['player.lua']={new=function()return player end},
 ['transport.lua']={clock=function()return function()return clock end end,new=function()return {
   poll=function()end,cancel=function()end,state=function()return {}end}end},
 ['storage.lua']={new=function()return {load=function()end,save=function()return true end}end},
 ['covers.lua']={new=function()return {want=function()end,poll=function()end,suspend=function()end,close=function()end}end},
 ['cover_disk.lua']={new=function()return {}end},
 ['web.lua']={new=function()return {close=function()end}end},
 ['input.lua']={new=function()return {physical=function()end}end},
 ['login.lua']={new=function()return {cancel=function()end,poll=function()end}end}
}
dofile=function(path)
 local name=path:match('([^/]+)$')
 return replacements[name]or original(path)
end
require=function()return audio end
sys={version=function()return '1.212'end,usage=function()return {heap_free=100000}end}
key={on=function()end,off=function()end};controller=nil;file={};http={}
app={set_home_exit=function()return true end,exiting=function()return false end}
time={get=function()return 1789500000 end,getlocal=function()return {year=2026,hour=12,min=0}end}
tmr={now=function()return clock end,ALARM_SINGLE=0,ALARM_AUTO=1,create=function()return {
 alarm=function(self,ms,mode,fn)timers[ms]=fn end,unregister=function()end}end}
original('main.lua');timers[60]()
local a=QQMUSIC_APP
assert(a.model.tab_count==4 and a.model.tab==3)
assert(a.control({action='select',index=1,revision=a.list_revision}))
assert(player.plays==0)
local g=a.play_generation
assert(a.control({action='library',tab=2}))
assert(a.control({action='back'}))
assert(a.play_generation==g,'browsing invalidated pending playback')
pending[1]({url='https://example/first.mp3'})
assert(player.plays==1)
assert(a.control({action='library',tab=3}))
assert(a.control({action='select',index=2,revision=a.list_revision}))
local old=pending[#pending]
assert(a.control({action='select',index=3,revision=a.list_revision}))
old({url='https://example/stale.mp3'});assert(player.plays==1)
pending[#pending]({url='https://example/current.mp3'});assert(player.plays==2)
a.stop();assert(not a.alive)
dofile=original
