local function netmock()
  local n={}
  function n.cancel()end
  function n.create(url,opts)
    local c={callbacks={},url=url,options=opts}
    function c:on(k,fn)self.callbacks[k]=fn;return self end
    function c:request()n.last=self end
    function c:close()self.closed=true end
    return c
  end
  return n
end
local net=netmock()
local nextdoc,requestdata
local json={encode=function(t)requestdata=t;return '{}'end,decode=function()return nextdoc end}
local saved
local store={load=function()return nil end,save=function(_,value)saved=value;return true end}
local native={eapi=function(path,raw)return 'params=ABC'end,weapi=function(raw)return 'params=DEF&encSecKey=123'end}
local p=dofile(ROOT..'/package/provider.lua').new(native,net,json,store,function()return 1000 end)
local got,err
p.qr_key(function(d,e)got=d;err=e end)
assert(net.last.url=='https://interface.music.163.com/eapi/login/qrcode/unikey')
assert(requestdata.type==3 and requestdata.e_r==false)
nextdoc={code=200,unikey='key'}
net.last.callbacks.headers(200,{['Set-Cookie']={'MUSIC_U=test-token; Path=/; HttpOnly','__csrf=csrf-value; Path=/'}})
net.last.callbacks.data(200,'{}');net.last.callbacks.complete()
assert(got.unikey=='key' and p.cookie.MUSIC_U=='test-token')
assert(p.save_session() and saved.cookie.MUSIC_U=='test-token')
p.qr_check('key',function(d,e)got=d;err=e end)
nextdoc={code=803}
net.last.callbacks.headers(200,{['set-cookie']='MUSIC_U=second-token; Expires=Wed, 09 Jun 2030 10:18:14 GMT; Path=/\n__csrf=second-csrf; Path=/\nNMTID=device; Path=/'})
net.last.callbacks.data(200,'{}');net.last.callbacks.complete()
assert(p.cookie.MUSIC_U=='second-token' and p.cookie.__csrf=='second-csrf' and p.cookie.NMTID=='device')
assert(p.save_session() and saved.cookie.MUSIC_U=='second-token')
p.url(123,function(d,e)got=d;err=e end)
assert(requestdata.encodeType=='mp3' and requestdata.level=='standard')
nextdoc={code=200,data={{url='https://example/audio',type='flac'}}}
net.last.callbacks.headers(200,{})
net.last.callbacks.data(200,'{}');net.last.callbacks.complete()
assert(got==nil and err:find('MP3'))
local called=false
p.account(function()called=true end);local old=net.last;p.cancel()
old.callbacks.headers(200,{});old.callbacks.data(200,'{}');old.callbacks.complete()
assert(not called)
p.request('/api/test',{},function(d,e)got=d;err=e end,2)
net.last.callbacks.headers(200,{});net.last.callbacks.data(200,'123')
assert(got==nil and err:find('内存'))
p.close()
local n2=netmock()
local p2=dofile(ROOT..'/package/provider.lua').new(native,n2,json,store,function()return 1000 end)
p2.playlists(123,0,function()end)
assert(n2.last.url=='https://music.163.com/weapi/user/playlist')
assert(requestdata.csrf_token~=nil and requestdata.header==nil)
p2.close()
local n3=netmock()
local p3=dofile(ROOT..'/package/provider.lua').new(native,n3,json,store,function()return 1000 end)
p3.likes('98765432109',function(d,e)got=d;err=e end)
assert(n3.last.url=='https://interface.music.163.com/eapi/song/like/get')
assert(requestdata.uid=='98765432109')
nextdoc={code=200,ids={123,'98765432109'}}
n3.last.callbacks.headers(200,{})
n3.last.callbacks.data(200,'{}');n3.last.callbacks.complete()
assert(got.ids[2]=='98765432109' and err==nil)
p3.recent(function(d,e)got=d;err=e end)
assert(n3.last.url=='https://music.163.com/weapi/play-record/song/list')
assert(requestdata.limit==50 and requestdata.header==nil)
nextdoc={code=200,data={list={{data={id=123,name='recent'}}}}}
n3.last.callbacks.headers(200,{})
n3.last.callbacks.data(200,'{}');n3.last.callbacks.complete()
assert(got.data.list[1].data.id==123)
p3.close()
-- Timeouts must reach the request callback once, allowing lyric-specific retry.
local clock=0;local n4=netmock()
local p4=dofile(ROOT..'/package/provider.lua').new(native,n4,json,store,function()return clock end)
local callbacks,global_errors=0,0
p4.on_error=function()global_errors=global_errors+1 end
p4.lyric(1,function(doc,e)assert(doc==nil and e);callbacks=callbacks+1 end)
local timedout=n4.last;clock=20001;p4.poll()
assert(callbacks==1 and global_errors==0 and not p4.busy)
timedout.callbacks.error();timedout.callbacks.complete();p4.poll()
assert(callbacks==1)
p4.close()
local clear_ok=false
local n5=netmock()
local p5=dofile(ROOT..'/package/provider.lua').new(native,n5,json,
  {load=function()return {cookie={MUSIC_U='fake'}}end,clear_session=function()return clear_ok,'cleanup failed'end},function()return 0 end)
assert(not p5.logout()and p5.cookie.MUSIC_U=='fake')
p5.account(function()error('stale account callback after logout')end)
local stale=n5.last;clear_ok=true;assert(p5.logout()and next(p5.cookie)==nil)
stale.callbacks.headers(200,{['set-cookie']='MUSIC_U=stale; Path=/'})
stale.callbacks.complete();assert(next(p5.cookie)==nil)
p5.close()
