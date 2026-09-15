-- Run the real main controller with fake I/O, never a device or account.
local real_dofile=dofile
local clock,timers,requests=0,{},{}
local current_settings=real_dofile(ROOT..'/package/settings.lua')
local session=true
local audio={effects=function()return true end,volume=function()end,baseline=function()end}
local net={poll=function()end,state=function()return {}end,cancel=function()end}
local player={status='idle',position=0,stats={buffer_bytes=300000,psram_free=2000000},plays=0}
function player.stop()player.status='idle';return true end
function player.play(url)player.status='playing';player.plays=player.plays+1 end
function player.pause()player.status=player.status=='paused'and 'playing'or 'paused'end
function player.poll()end
function player.close()end
local p={cookie={MUSIC_U='fake'},generation=0,busy=false,diagnostics={}}
function p.cancel()p.generation=p.generation+1;p.busy=false end
local function send(kind,done,doc)
  p.cancel();requests[kind]=(requests[kind]or 0)+1;done(doc)
end
local function song(id)return {id=id,name='song '..id,ar={{name='artist'}},al={picUrl='https://p3.music.126.net/'..id..'.jpg'}}end
function p.account(done)send('account',done,{profile={userId=1,nickname='Tester',vipType=0}})end
function p.likes(uid,done)send('likes',done,{ids={1,2,3}})end
function p.recent(done)send('recent',done,{data={list={{data=song(4)}}}})end
function p.daily(done)send('daily',done,{data={dailySongs={song(5)}}})end
function p.details(ids,done)local songs={};for _,id in ipairs(ids)do songs[#songs+1]=song(id)end;send('details',done,{songs=songs})end
function p.url(id,done)send('url',done,{url='https://example/'..id..'.mp3'})end
function p.lyric(id,done)send('lyric',done,{lrc={lyric='[00:00]line'}})end
function p.qr_key(done)send('qr',done,{unikey='test-qr'})end
function p.save_session()return true end
function p.logout()p.cancel();p.cookie={};session=false;return true end
function p.poll()end
function p.close()end
local ui={ready=true,render=function()end,load_next=function()return true end,qr=function()return true end,close=function()end}
local covers={want=function()end,poll=function()end,close=function()end}
local replacements={
  ['ui.lua']=function()return ui end,
  ['transport.lua']={clock=function()return function()return clock end end,new=function()return net end},
  ['storage.lua']={new=function()return {load=function(name)return name=='settings'and current_settings or nil end,
    save=function(name,value)if name=='settings'then current_settings=value end;return true end}end},
  ['provider.lua']={new=function()return p end},['player.lua']={new=function()return player end},
  ['covers.lua']={new=function()return covers end,image_size=function()end,identity=function(u)return u end},
  ['cover_disk.lua']={new=function()return {}end},['web.lua']={new=function()return {close=function()end}end},
  ['input.lua']={new=function()return {physical=function()end}end}
}
dofile=function(path)
  local name=path:match('([^/]+)$')
  if replacements[name]then return replacements[name]end
  return real_dofile((path:gsub('/sd/apps/netease',ROOT..'/package')))
end
require=function()return audio end
sys={version=function()return '1.211'end,usage=function()return {heap_free=100000}end};sjson={};file={};http={};controller=nil
key={on=function()end,off=function()end}
app={set_home_exit=function()return true end,exiting=function()return false end}
tmr={now=function()return clock end,ALARM_AUTO=1,ALARM_SINGLE=0,create=function()
  return {alarm=function(self,ms,mode,fn)timers[ms]=fn end,unregister=function()end}
end}
time={getlocal=function()return {year=2026,hour=12,min=0}end}
real_dofile(ROOT..'/package/main.lua');timers[60]()
local a=NETEASE_APP
assert(a.uid=='1'and a.model.tab==1 and a.model.page=='songs'and a.web_list.ready)
assert(#a.web_list.items==3 and requests.likes==1)
assert(a.account.nickname=='Tester'and a.account.membership=='non_member')
assert(a.control({action='library',tab=2}));assert(requests.recent==1)
assert(a.control({action='library',tab=1}));assert(requests.likes==1)
for i=1,5 do clock=clock+1000;timers[100]()end
assert(a.library_cache.state()[3].complete)
assert(a.control({action='select',index=1,list_revision=a.web_list.revision}))
assert(a.control({action='play_mode',mode='repeat_one'}));assert(current_settings.play_mode=='repeat_one')
local plays=player.plays;player.status='ended';timers[100]()
assert(player.plays==plays+1 and a.model.index==1)
assert(a.control({action='play_mode',mode='ordered'}))
assert(a.control({action='select',index=3,list_revision=a.web_list.revision}))
plays=player.plays;player.status='ended';timers[100]();assert(player.plays==plays)
assert(a.control({action='refresh_library',tab=1}));assert(requests.likes==2)
assert(a.control({action='logout'}))
assert(not session and a.uid==nil and a.account==nil and #a.model.queue==0 and a.model.page=='login')
assert(not a.web_list.ready and not a.library_cache.state()[1].ready and requests.qr==1)
a.stop();dofile=real_dofile
