local DIR='/sd/apps/qqmusic'
local previous=rawget(_G,'QQMUSIC_APP');if previous and previous.stop then previous.stop()end
local A={alive=true,error='',message='正在启动',timers={},view_generation=0,play_generation=0,list_revision=0}
_G.QQMUSIC_APP=A
if sys and sys.usage then local ok,s=pcall(sys.usage);if ok then A.start_internal=s.heap_free end end
local JSON=rawget(_G,'sjson')or rawget(_G,'json')
local function boot()
  assert(app.set_home_exit and app.set_home_exit(false),'Home 接管失败')
  local T=dofile(DIR..'/transport.lua');local now=T.clock(tmr.now)
  local S=dofile(DIR..'/model.lua').new();A.model=S;S.page='library'
  local U=A.ui;A.audio=require(DIR..'/modules/qq_music.so')
  if A.start_internal then A.audio.baseline(A.start_internal)end
  local apiNet,streamNet=T.new(http,now),T.new(http,now)
  local store=dofile(DIR..'/storage.lua').new(file,JSON)
  local provider=dofile(DIR..'/provider.lua').new(A.audio,apiNet,JSON,store,now);A.provider=provider
  local login=dofile(DIR..'/login.lua').new(provider,now);A.login=login
  local player=dofile(DIR..'/player.lua').new(A.audio,streamNet,now);A.player=player
  local View=dofile(DIR..'/ui_view.lua');local Library=dofile(DIR..'/library.lua')
  local Playback=dofile(DIR..'/playback.lua')
  local Covers=dofile(DIR..'/covers.lua')
  A.covers=Covers.new(apiNet,provider,player,now,dofile(DIR..'/cover_disk.lua').new(file,Covers.image_size,nil,Covers.identity))
  local Effects=dofile(DIR..'/effects.lua');local defaults=dofile(DIR..'/settings.lua')
  local config=store.load('settings')or defaults
  local valid=Effects.validate(defaults,config);config=valid or defaults;A.config=config
  local ok,err=Effects.apply(A.audio,config);assert(ok,err)
  A.uid=provider.session.musicid;A.nickname=provider.session.nickname or '游客'
  S.tab_count=A.uid and 5 or 2
  local Catalog=dofile(DIR..'/catalog.lua')
  local catalog=Catalog.new(provider,now,store,function()local ok,t=pcall(time.get);return ok and tonumber(t)or 0 end)
  A.catalog=catalog;catalog.reset(A.uid~=nil)
  A.account={name=A.nickname,login_type=provider.session.login_type or 2,membership={name='未知',known=false},loading=A.uid~=nil}
  local account_stage=A.uid and 'profile'or nil
  local account_active=nil
  local recent=store.load('recent')or {};if recent.owner~=A.uid then recent={owner=A.uid,songs={}}end
  recent.songs=type(recent.songs)=='table'and recent.songs or {}
  local function render()
    if not A.alive then return end
    if not A.clock_at or now()>=A.clock_at then A.clock_at=now()+1000;A.clock_text,A.clock_dst=View.clock(time)end
    local cover=View.cover(S,A);A.covers.want(cover and {cover}or {});U.render(S,A)
  end
  local function failure(e)A.error=e or '请求失败';A.message='';render()end;provider.on_error=failure
  local function timer(ms,fn,once)
    local t=tmr.create();A.timers[#A.timers+1]=t;t:alarm(ms,once and tmr.ALARM_SINGLE or tmr.ALARM_AUTO,fn);return t
  end
  local browsing={kind='top',id=26,offset=0};local page_songs={}
  local load_page,play_index,start_login
  local function leave_login()
    if S.page=='login'then login.cancel();U.qr(nil,A.audio)end
  end
  load_page=function(offset)
    A.list_revision=A.list_revision+1
    leave_login();A.view_generation=A.view_generation+1;A.play_generation=A.play_generation+1
    local g=A.view_generation;provider.cancel();A.pending_lyric=nil
    browsing.offset=offset;S.page='songs';S.items={};S.cursor=1;A.error='';A.message='加载中…';render()
    local function accept(d,e)
      if not A.alive or g~=A.view_generation then return end
      if not d then failure(e);return end
      local cache_key=browsing.kind=='top'and ('top'..browsing.id)or browsing.kind=='favorites'and 'favorites'
      if cache_key then catalog.put(cache_key,offset,d)end
      page_songs=d.songs or {};S.items={}
      if offset>0 then S.items[#S.items+1]={name='‹ 上一页',page_offset=offset-20}end
      for i,song in ipairs(page_songs)do S.items[#S.items+1]={name=song.name,queue_index=i,cover=View.song_cover(song)}end
      if offset+#page_songs<(d.total or 0)and #page_songs>0 then S.items[#S.items+1]={name='下一页 ›',page_offset=offset+20}end
      if d.title then A.list_title=d.title end
      A.tab_covers=A.tab_covers or {};if page_songs[1]then A.tab_covers[S.tab]=View.song_cover(page_songs[1])end
      A.message=#page_songs==0 and '暂无歌曲'or '';render()
    end
    local cache_key=browsing.kind=='top'and ('top'..browsing.id)or browsing.kind=='favorites'and 'favorites'
    local cached=cache_key and catalog.get(cache_key,offset)
    if cached then accept(cached);return end
    if browsing.kind=='search'then provider.search(browsing.query,offset//20+1,accept)
    elseif browsing.kind=='playlist'then provider.playlist(browsing.id,offset,accept)
    elseif browsing.kind=='favorites'then provider.favorites(offset,accept)
    elseif browsing.kind=='daily'then provider.daily(offset,accept)
    elseif browsing.kind=='recent'then
      local songs={};for i=offset+1,math.min(offset+20,#recent.songs)do songs[#songs+1]=recent.songs[i]end
      accept({songs=songs,total=#recent.songs})
    else provider.top(browsing.id,offset,accept)end
  end
  local function open_library()
    A.list_title=Library.titles[S.tab]
    if S.tab>2 and not A.uid then S.tab=1;failure('请先登录');return end
    if S.tab==3 then browsing={kind='favorites'}
    elseif S.tab==4 then browsing={kind='daily'}
    elseif S.tab==5 then browsing={kind='recent'};A.list_title='最近播放 · 本机'
    else browsing={kind='top',id=Library.topids[S.tab]}end
    load_page(0)
  end
  play_index=function(index)
    if #S.queue==0 then A.message='请先从音乐库选择歌曲';render();return end
    leave_login();A.play_generation=A.play_generation+1;A.view_generation=A.view_generation+1
    local g=A.play_generation;provider.cancel();player.stop();A.pending_lyric=nil
    S.index=(index-1)%#S.queue+1;S.page='player';A.song=S.queue[S.index]
    local names={};for _,ar in ipairs(A.song.ar or {})do names[#names+1]=ar.name or ''end;A.artist=table.concat(names,' / ')
    A.lyrics=nil;A.lyric='';A.error='';A.message='获取播放地址…';A.ended_handled=false;A.recorded=false;render()
    provider.url(A.song,function(item,e)
      if not A.alive or g~=A.play_generation then return end
      if not item then failure(e);return end
      A.message='';player.play(item.url);A.pending_lyric={id=A.song.id,generation=g};render()
    end)
  end
  start_login=function(mode)
    A.view_generation=A.view_generation+1;A.play_generation=A.play_generation+1
    A.pending_lyric=nil;player.stop();A.error='';A.message='正在获取登录二维码';S.page='login';U.qr(nil,A.audio);render()
    login.start(function(status,e)
      if not A.alive or S.page~='login'then return end
      local appname=login.mode=='wx'and '微信'or '手机 QQ'
      local messages={waiting='使用'..appname..'扫码',scanned='已扫码，请在'..appname..'确认',authorizing='正在交换音乐凭据',expired='二维码已过期，Home 刷新',done='QQ音乐登录成功'}
      A.message=messages[status]or '';A.error=e or ''
      if status=='waiting'and login.image then
        local good,why=U.qr(login.image,A.audio);if not good then failure(why);login.cancel();return end
      elseif status=='expired'or status=='error'then U.qr(nil,A.audio)
      elseif status=='done'then
        U.qr(nil,A.audio);A.uid=provider.session.musicid;A.nickname=provider.session.nickname;S.tab_count=5;S.page='library'
        if recent.owner~=A.uid then recent={owner=A.uid,songs={}}end
        catalog.reset(true);A.account={name=A.nickname,login_type=provider.session.login_type or 2,membership={name='未知',known=false},loading=true}
        account_stage='profile';S.tab=3;open_library()
      end;render()
    end,mode)
  end
  local function back()
    leave_login();A.view_generation=A.view_generation+1;A.play_generation=A.play_generation+1
    provider.cancel();A.pending_lyric=nil;S.page='library';A.message='';A.error='';render()
  end
  local function action(cmd)
    if cmd=='previous'then play_index(S.index-1)
    elseif cmd=='next'then play_index(Playback.next_index(S.index,#S.queue,config.play_mode,false))
    elseif cmd=='pause'then
      if player.status=='idle'or player.status=='error'or player.status=='ended'then play_index(S.index)else player.pause()end
    elseif cmd=='player'then S.page='player'
    elseif cmd=='login'then start_login()
    elseif cmd=='library'then open_library()
    elseif cmd=='select'then
      local item=S.items[S.cursor];if not item then return end
      if item.page_offset~=nil then load_page(item.page_offset)
      else
        local id=browsing.kind=='top'and ('top'..browsing.id)or browsing.kind=='favorites'and 'favorites'
        local all=id and catalog.all(id)or {};local index=(browsing.offset or 0)+item.queue_index
        if #all>=index then S.queue=all;play_index(index)
        else S.queue={};for i,song in ipairs(page_songs)do S.queue[i]=song end;play_index(item.queue_index)end
      end
    end;render()
  end
  local function input(cmd,axis,delta)
    if not A.alive then return end
    if cmd=='exit'then A.stop();app.exit();return end
    if not U.ready then return end
    if cmd=='back'then back()
    elseif cmd=='confirm'then
      if S.page=='login'then back()
      elseif S.page=='about'and not A.uid then start_login()else action(S.home())end
    elseif cmd=='direction'then
      if S.page=='login'then
        if axis=='horizontal'then start_login(login.mode=='qq'and 'wx'or 'qq')end
        return
      end
      local page=S.page
      if page~='player'then A.view_generation=A.view_generation+1;provider.cancel();A.message=''end
      action(S.direction(axis,delta))
    else action(cmd)end
  end
  A.input=dofile(DIR..'/input.lua').new(key,now,input)
  key.on(function(code,event)if A.alive then A.input.physical(code,event)end end)
  if controller and controller.state then
    timer(40,function()if A.alive then local good,pad=pcall(controller.state,'ble-main');A.input.pad(good and pad or nil)end end)
  end
  A.control=function(doc)
    local cmd=doc.action
    if cmd=='play_mode'then
      if not Playback.modes[doc.mode]then return nil,'无效播放模式'end
      config.play_mode=doc.mode;A.settings_save_at=now()+500
    elseif cmd=='volume'then
      local updated,e=Effects.validate(config,{volume=doc.value});if type(doc.value)~='number'or not updated then return nil,e or '无效音量'end
      config.volume=updated.volume;A.audio.volume(config.volume);A.settings_save_at=now()+1000
    elseif cmd=='effects'then
      local updated,e=Effects.validate(config,doc.settings);if not updated then return nil,e end
      local good,why=Effects.apply(A.audio,updated);if not good then return nil,why end
      config=updated;A.config=config;local saved,se=store.save('settings',config);if not saved then return nil,se end
    elseif cmd=='library'then
      if type(doc.tab)~='number'or doc.tab%1~=0 or doc.tab<1 or doc.tab>S.tab_count then return nil,'无效音乐库或需要登录'end
      leave_login();S.tab=doc.tab;S.page='library';open_library()
    elseif cmd=='search'then
      if type(doc.query)~='string'or #doc.query==0 or #doc.query>120 or doc.query:find('[%c]')then return nil,'请输入有效关键词'end
      browsing={kind='search',query=doc.query};A.list_title='搜索 · '..doc.query;load_page(0)
    elseif cmd=='playlist'then
      if not A.uid then return nil,'请先登录'end
      if type(doc.id)~='string'or #doc.id>20 or not doc.id:match('^%d+$')then return nil,'请输入数字歌单 ID'end
      A.playlist_id=doc.id;S.tab=3;browsing={kind='playlist',id=doc.id};A.list_title='我的歌单';load_page(0)
    elseif cmd=='select'then
      if doc.revision~=A.list_revision or S.page=='login'then return nil,'列表已变化，请重新选择'end
      if type(doc.index)~='number'or doc.index%1~=0 or not S.items[doc.index]then return nil,'无效项目'end
      S.cursor=doc.index;action('select')
    elseif cmd=='refresh_login'then
      if doc.mode~=nil and doc.mode~='qq'and doc.mode~='wx'then return nil,'不支持的登录方式'end
      start_login(doc.mode)
    elseif cmd=='account'then
      if A.uid then account_stage='profile';A.account.loading=true end
    elseif cmd=='logout'then
      local ok,e=provider.logout();if not ok then return nil,e end
      login.cancel();player.stop();A.uid=nil;A.nickname='游客';A.account={name='游客',membership={name='未知',known=false}}
      account_stage=nil;account_active=nil;A.pending_lyric=nil;A.song=nil;A.artist=nil;A.lyrics=nil;A.lyric='';S.tab=1;S.tab_count=2
      S.items={};S.queue={};page_songs={};A.list_revision=A.list_revision+1;catalog.reset(false)
      recent={songs={}};A.recent_save_at=nil;A.tab_covers={};start_login('qq')
    elseif cmd=='back'or cmd=='guest'then back()
    elseif cmd=='home'then input('confirm')
    elseif cmd=='page'then back();S.page=doc.page=='about'and 'about'or doc.page=='player'and 'player'or 'library'
    elseif cmd=='previous'or cmd=='next'or cmd=='pause'then action(cmd)
    else return nil,'未知操作'end
    render();return true
  end
  A.web=dofile(DIR..'/web.lua').new(A,S,player,provider,apiNet,streamNet,JSON,DIR)
  timer(100,function()
    if not A.alive then return end
    if app.exiting()then A.stop();return end
    apiNet.poll();provider.poll();player.poll();if S.page=='login'then login.poll()end
    if A.settings_save_at and now()>=A.settings_save_at then
      A.settings_save_at=nil;local saved,e=store.save('settings',config);if not saved then failure(e)end end
    if player.status=='error'then A.error=player.error end
    if A.uid and A.song and player.status=='playing'and not A.recorded then
      A.recorded=true
      for i=#recent.songs,1,-1 do if recent.songs[i].id==A.song.id then table.remove(recent.songs,i)end end
      table.insert(recent.songs,1,A.song);while #recent.songs>50 do table.remove(recent.songs)end
      A.recent_save_at=now()+1500
    end
    if A.recent_save_at and now()>=A.recent_save_at and (player.stats.buffer_bytes or 0)>=65536 then
      A.recent_save_at=nil;local saved,e=store.save('recent',recent);if not saved then failure(e)end
    end
    if player.status=='ended'and not A.ended_handled then
      A.ended_handled=true;play_index(Playback.next_index(S.index,#S.queue,config.play_mode,true))end
    if A.pending_lyric and not provider.busy and player.stats and player.stats.buffer_bytes>=65536 then
      local pending=A.pending_lyric;A.pending_lyric=nil
      provider.lyric(pending.id,function(doc)
        if not A.alive or pending.generation~=A.play_generation then return end
        local raw=doc and doc.lrc and doc.lrc.lyric;if type(raw)~='string'then return end
        A.lyrics=Playback.lyrics(raw)
      end)
    end
    if A.lyrics then A.lyric='';for _,line in ipairs(A.lyrics)do if line.at>(player.position or 0)then break end;A.lyric=line.text end end
    local available=S.page~='login'and U.ready and not provider.busy and not apiNet.current and not apiNet.pending
      and not A.pending_lyric and player.status~='buffering'
      and (player.status~='playing'or (player.stats.buffer_bytes or 0)>=196608)
    if available and account_active then account_stage=account_active;account_active=nil end
    if available and account_stage and A.uid then
      local stage=account_stage;local owner=A.uid;account_stage=nil
      account_active=stage
      if stage=='profile'then provider.account(function(d,e)
        if not A.alive or A.uid~=owner then return end
        account_active=nil
        if d then A.account.name=d.name;A.account.avatar=d.avatar;A.nickname=d.name end
        A.account.error=e;account_stage='membership'
      end)
      else provider.membership(function(d,e)
        if not A.alive or A.uid~=owner then return end
        account_active=nil
        if d then A.account.membership=d end;A.account.loading=false;A.account.error=e or A.account.error
      end)end
    elseif available then catalog.poll()end
    if S.page~='login'then A.covers.poll()end;render()
  end)
  A.message=A.uid and '已恢复保存的会话'or '游客浏览 · 说明页 Home 扫码登录'
  if not A.uid then start_login('qq')else S.tab=3;open_library()end
  local fonts;fonts=timer(80,function()
    local good,ready=pcall(U.load_next);if not good then fonts:unregister();A.boot_failed(ready);return end
    if ready then fonts:unregister();render()end
  end)
end
function A.stop()
  if not A.alive then return end;A.alive=false
  for _,t in ipairs(A.timers)do pcall(function()t:unregister()end)end
  pcall(function()key.off()end);if app.set_home_exit then pcall(app.set_home_exit,true)end
  if A.web then pcall(A.web.close)end
  if A.login then pcall(A.login.cancel)end
  if A.covers then pcall(A.covers.close)end
  if A.provider then pcall(A.provider.close)end
  if A.player then pcall(A.player.close)elseif A.audio then pcall(A.audio.close)end
  if A.ui then pcall(A.ui.close)end
  if A.version_cleanup then pcall(A.version_cleanup);A.version_cleanup=nil end
  if rawget(_G,'QQMUSIC_APP')==A then _G.QQMUSIC_APP=nil end
end
A.shutdown=A.stop
function A.boot_failed(err)
  pcall(function()file.putcontents(DIR..'/boot-error.txt',tostring(err))end);A.stop()
  if app.set_home_exit then pcall(app.set_home_exit,false)end
  local root=lv_scr_act();lv_obj_clean(root);local label=lv_label_create(root);lv_obj_set_width(label,300)
  lv_label_set_text(label,'QQ Music startup failed. Check module and fonts.')
  key.on(key.HOME,function(e)if e==key.LONG_START then key.off();if app.set_home_exit then app.set_home_exit(true)end;app.exit()end end)
end
local Firmware=dofile(DIR..'/firmware_gate.lua')
local compatible,system_version=Firmware.check(sys)
if not compatible then
  A.error=Firmware.MESSAGE;A.version_blocked=true
  A.version_cleanup=Firmware.show(DIR,system_version,function()A.stop();app.exit()end)
  return
end
local shown,e=pcall(function()A.ui=dofile(DIR..'/ui.lua')()end)
if not shown then A.boot_failed(e)else
  local t=tmr.create();A.timers[#A.timers+1]=t;t:alarm(60,tmr.ALARM_SINGLE,function()
    if A.alive then local good,err=pcall(boot);if not good then A.boot_failed(err)end end
  end)
end
