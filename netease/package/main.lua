local DIR='/sd/apps/netease'
local previous=rawget(_G,'NETEASE_APP')
if previous and previous.stop then previous.stop()end
local A={alive=true,error='',message='正在启动',song=nil,lyric='',timers={},view_generation=0,play_generation=0}
if sys and sys.usage then
  local ok,usage=pcall(sys.usage);if ok then A.start_internal=usage.heap_free end
end
_G.NETEASE_APP=A
local JSON=rawget(_G,'sjson')or rawget(_G,'json')
local function boot()
  assert(app.set_home_exit,'固件缺少 Home 接管接口')
  local captured,capture_error=app.set_home_exit(false)
  assert(captured,capture_error or 'Home 接管失败')
  local Transport=dofile(DIR..'/transport.lua')
  local now=Transport.clock(tmr.now)
  local S=dofile(DIR..'/model.lua').new();A.model=S
  local U=A.ui
  A.audio=require(DIR..'/modules/ncm_music.so')
  if A.start_internal then A.audio.baseline(A.start_internal)end
  local apiNet=Transport.new(http,now);local streamNet=Transport.new(http,now)
  local store=dofile(DIR..'/storage.lua').new(file,JSON)
  local provider=dofile(DIR..'/provider.lua').new(A.audio,apiNet,JSON,store,now);A.provider=provider
  local player=dofile(DIR..'/player.lua').new(A.audio,streamNet,now);A.player=player
  local lyricLoader=dofile(DIR..'/lyrics.lua').new(provider,now);A.lyric_loader=lyricLoader
  local View=dofile(DIR..'/ui_view.lua')
  local Library=dofile(DIR..'/library.lua')
  local Account=dofile(DIR..'/account.lua')
  local PlayMode=dofile(DIR..'/play_mode.lua')
  local libraryCache=dofile(DIR..'/library_cache.lua').new(provider,Library,now);A.library_cache=libraryCache
  local Covers=dofile(DIR..'/covers.lua')
  local coverDisk=dofile(DIR..'/cover_disk.lua').new(file,Covers.image_size,nil,Covers.identity)
  A.covers=Covers.new(apiNet,provider,player,now,coverDisk)
  local browserList=dofile(DIR..'/web_list.lua').new();A.web_list=browserList
  A.web=dofile(DIR..'/web.lua').new(A,S,player,provider,apiNet,streamNet,JSON,DIR)
  local config=store.load('settings')or dofile(DIR..'/settings.lua')
  local defaults=dofile(DIR..'/settings.lua')
  for k,v in pairs(defaults)do if config[k]==nil then config[k]=v end end
  local Effects=dofile(DIR..'/effects.lua')
  local valid,validation_error=Effects.validate(defaults,config)
  if not valid then A.error=validation_error;config=defaults else config=valid end
  local ok,err=Effects.apply(A.audio,config)
  if not ok then error(err)end
  A.config=config
  if not store.load('settings')then
    local saved=store.save('settings',config);if not saved then A.error='设置无法保存到 SD'end
  end
  local function render()
    if not A.alive then return end
    A.lyrics=lyricLoader.lines;A.lyric_status=lyricLoader.status
    if not A.clock_check_at or now()>=A.clock_check_at then
      A.clock_check_at=now()+1000
      A.clock_text,A.clock_dst=View.clock(time)
    end
    local cover=View.cover(S,A);A.covers.want(cover and {cover}or {})
    U.render(S,A)
  end
  local function failure(msg)A.error=msg or '请求失败';A.message='';render()end
  local function list_failure(msg)browserList.fail();failure(msg)end
  provider.on_error=failure
  local function begin_view()
    A.view_generation=A.view_generation+1;A.error='';A.message='加载中…'
    return A.view_generation
  end
  local function view_valid(g)return A.alive and g==A.view_generation end
  local function artist(song)
    local names={};for _,ar in ipairs(song.ar or song.artists or {})do names[#names+1]=ar.name or ''end
    return table.concat(names,' / ')
  end
  local login,load_account,load_song_page,play_index,open_library
  local library_ids,cache={},{}
  load_song_page=function(offset)
    local g=begin_view();local ids={}
    browserList.begin(S.tab,A.list_title)
    for i=offset+1,math.min(offset+20,#library_ids)do ids[#ids+1]=library_ids[i]end
    local function show(songlist)
      if not view_valid(g)then return end
      for _,song in ipairs(songlist or {})do song._ncm_details=true;cache[tostring(song.id)]=song end
      local first=ids[1]and cache[tostring(ids[1])]
      if first then
        A.tab_covers=A.tab_covers or {};A.tab_covers[S.tab]=View.song_cover(first)
      end
      local items={}
      if offset>0 then items[#items+1]={name='‹ 上一页',page_offset=offset-20}end
      for i,id in ipairs(ids)do
        local song=cache[tostring(id)]or {id=id,name='歌曲 '..tostring(id)}
        items[#items+1]={name=song.name,id=id,queue_index=offset+i,cover=View.song_cover(song)}
      end
      if offset+#ids<#library_ids then items[#items+1]={name='下一页 ›',page_offset=offset+20}end
      S.items=items;S.cursor=1;S.page='songs';browserList.finish(items)
      A.message=#ids==0 and '暂无歌曲'or '';render()
    end
    if #ids==0 then show({});return end
    local missing=false
    for _,id in ipairs(ids)do
      local song=cache[tostring(id)]
      if not song or (not song._ncm_details and not View.song_cover(song))then missing=true;break end
    end
    if not missing then show({});return end
    libraryCache.details(S.tab,ids,function(doc,e)
      if not view_valid(g)then return end
      if not doc then list_failure(e);return end;show(doc.songs)
    end)
  end
  open_library=function(force)
    A.play_generation=A.play_generation+1
    local g=begin_view()
    A.list_title=Library.titles[S.tab];A.list_cover=nil
    browserList.begin(S.tab,A.list_title)
    S.items={};S.cursor=1;S.page='songs';render()
    local tab=S.tab
    libraryCache.load(tab,A.uid,function(ids,shared,e)
      if not view_valid(g)then return end
      if not ids then list_failure(e);return end
      library_ids=ids;cache=shared;load_song_page(0)
    end,force)
  end
  play_index=function(index)
    if #S.queue==0 then A.message='请先从音乐库选择歌曲';render();return end
    A.play_generation=A.play_generation+1;local g=A.play_generation
    A.view_generation=A.view_generation+1;provider.cancel();player.stop()
    S.index=(index-1)%#S.queue+1;S.page='player'
    A.error='';A.message='获取播放地址…';A.lyric='';A.lyrics=nil;A.ended_handled=false
    local id=S.queue[S.index]
    lyricLoader.start(id)
    local function valid()return A.alive and g==A.play_generation end
    local function fetch_url(song)
      if not valid()then return end
      A.song=song;A.artist=artist(song);render()
      provider.url(id,function(item,e)
        if not valid()then return end
        if not item then lyricLoader.cancel();failure(e);return end
        A.message='';player.play(item.url);render()
        -- Lyrics are deliberately deferred until streaming has built a buffer.
        lyricLoader.enable()
      end)
    end
    if A.queue_cache and A.queue_cache[tostring(id)]then fetch_url(A.queue_cache[tostring(id)])
    else provider.details({id},function(doc,e)
      if not valid()then return end
      if not doc or not doc.songs or not doc.songs[1]then lyricLoader.cancel();failure(e or '歌曲信息不可用');return end
      fetch_url(doc.songs[1])
    end)end
  end
  load_account=function()
    A.message='正在验证登录…';A.error='';render()
    provider.account(function(doc,e)
      if not A.alive then return end
      local account=Account.parse(doc)
      if not account then
        S.page='login';A.message='Home 重新扫码';failure(e or '登录失效');return
      end
      libraryCache.clear()
      A.account=account;A.uid=account.id;A.nickname=account.nickname
      A.qr_key=nil;U.qr(nil,A.audio)
      local saved,saveerr=provider.save_session()
      S.tab=1;open_library()
      if not saved then A.error=saveerr;render()end
    end)
  end
  login=function()
    A.view_generation=A.view_generation+1;A.play_generation=A.play_generation+1
    lyricLoader.cancel();player.stop();provider.cancel();S.page='login';A.qr_key=nil
    A.error='';A.message='获取二维码…';U.qr(nil,A.audio);render()
    provider.qr_key(function(doc,e)
      if not A.alive then return end
      local key=doc and (doc.unikey or (doc.data and doc.data.unikey))
      if not key then failure(e or '二维码获取失败，Home 重试');return end
      A.qr_key=key;A.qr_started=now();A.next_qr_poll=now()+2500
      local good,qrerr=U.qr('https://music.163.com/login?codekey='..key,A.audio)
      if not good then A.qr_key=nil;failure(qrerr);return end
      A.message='请使用网易云音乐扫码';render()
    end)
  end
  local function action(command)
    if command=='player'then S.page='player'
    elseif command=='previous'or command=='next'then
      local next_index=PlayMode.step(config.play_mode,S.index,#S.queue,command=='previous'and -1 or 1,false)
      if next_index then play_index(next_index)end
    elseif command=='pause'then
      if player.status=='error' or player.status=='idle' or player.status=='ended'then play_index(S.index)else player.pause()end
    elseif command=='login'then if not provider.busy then login()end
    elseif command=='library'then open_library()
    elseif command=='select'then
      local item=S.items[S.cursor];if not item then return end
      if item.page_offset~=nil then load_song_page(item.page_offset)
      else
        S.queue={};for i,id in ipairs(library_ids)do S.queue[i]=id end
        A.queue_cache=cache;play_index(item.queue_index)
      end
    end
    render()
  end
  local function direction(axis,delta)
    if S.page=='login'then return end
    if S.page~='player'then A.view_generation=A.view_generation+1;provider.cancel();A.message=''end
    action(S.direction(axis,delta))
  end
  local function input_action(command,axis,delta)
    if not A.alive then return end
    if command=='exit'then A.stop();app.exit()
    elseif not U.ready then return
    elseif command=='confirm'then action(S.home())
    elseif command=='direction'then direction(axis,delta)
    elseif command=='back'then
      if S.page~='login'then A.view_generation=A.view_generation+1;provider.cancel();S.page='library';A.error='';render()end
    else action(command)end
  end
  A.input=dofile(DIR..'/input.lua').new(key,now,input_action)
  key.on(function(code,event)if A.alive then A.input.physical(code,event)end end)
  -- Do not also subscribe to raw IMU: firmware already generates directional keys.
  if controller and controller.state then
    local pad_timer=tmr.create();A.timers[#A.timers+1]=pad_timer
    pad_timer:alarm(40,tmr.ALARM_AUTO,function()
      if not A.alive then return end
      local good,pad=pcall(controller.state,'ble-main')
      A.input.pad(good and pad or nil)
    end)
    if controller.on then
      pcall(controller.on,'ble-main',function(_,pad)if A.alive then A.input.pad(pad)end end)
      A.pad_subscribed=true
    end
  end
  A.control=function(doc)
    local cmd=doc.action
    if cmd=='logout'then
      A.play_generation=A.play_generation+1;A.view_generation=A.view_generation+1
      lyricLoader.cancel();player.stop()
      local ok,err=provider.logout()
      if not ok then failure(err);return nil,err end
      libraryCache.clear();browserList.clear();library_ids={};cache={}
      A.uid=nil;A.nickname=nil;A.account=nil;A.queue_cache=nil;A.tab_covers={}
      A.song=nil;A.artist='';A.lyric='';S.items={};S.queue={};S.index=1;S.tab=1
      login()
    elseif cmd=='play_mode'then
      if not PlayMode.valid(doc.mode)then return nil,'播放模式无效'end
      local changed={};for k,v in pairs(config)do changed[k]=v end;changed.play_mode=doc.mode
      local saved,err=store.save('settings',changed)
      if not saved then return nil,err end
      config=changed;A.config=config
    elseif cmd=='volume'then
      local updated,e=Effects.validate(config,{volume=doc.value})
      if type(doc.value)~='number'or not updated then return nil,e or '无效音量'end
      config.volume=updated.volume;A.audio.volume(config.volume);A.config=config
      A.settings_save_at=now()+1000
    elseif cmd=='effects'then
      local updated,e=Effects.validate(config,doc.settings)
      if not updated then return nil,e end
      local applied,apply_error=Effects.apply(A.audio,updated)
      if not applied then return nil,apply_error end
      config=updated;A.config=config
      local saved,save_error=store.save('settings',config)
      if not saved then A.error='已应用，但'..save_error;return nil,A.error end
      A.error='';A.message='音效已保存并应用'
    elseif cmd=='library'or cmd=='refresh_library'then
      if not A.uid then return nil,'请先扫码登录'end
      if type(doc.tab)~='number'or doc.tab%1~=0 or doc.tab<1 or doc.tab>3 then return nil,'无效音乐库'end
      S.tab=doc.tab;S.page='library';open_library(cmd=='refresh_library')
    elseif cmd=='select'then
      if not A.uid then return nil,'请先扫码登录'end
      local item,err=browserList.select(doc)
      if not item then return nil,err end
      S.tab=browserList.tab;S.items=browserList.items;S.cursor=doc.index;action('select')
    elseif cmd=='page'then
      if not A.uid then return nil,'请先登录'end
      A.view_generation=A.view_generation+1;provider.cancel()
      S.page=doc.page=='about'and 'about'or doc.page=='player'and 'player'or 'library';render()
    elseif cmd=='refresh_login'then
      if A.uid then return nil,'已登录，无需刷新'end
      login()
    elseif cmd=='home'then input_action('confirm')
    elseif cmd=='back'then input_action('back')
    elseif cmd=='previous'or cmd=='next'or cmd=='pause'then
      if not A.uid then return nil,'请先扫码登录'end
      action(cmd)
    else return nil,'未知操作'end
    render();return true
  end
  local timer=tmr.create();A.timers[#A.timers+1]=timer
  timer:alarm(100,tmr.ALARM_AUTO,function()
    if not A.alive then return end
    apiNet.poll();provider.poll();player.poll()
    if A.settings_save_at and now()>=A.settings_save_at then
      A.settings_save_at=nil;local saved,e=store.save('settings',config)
      if not saved then failure(e)end
    end
    if app.exiting()then A.stop();return end
    if player.status=='error'then A.error=player.error end
    if player.status=='ended' and not A.ended_handled then
      A.ended_handled=true
      local next_index=PlayMode.step(config.play_mode,S.index,#S.queue,1,true)
      if next_index then play_index(next_index)end
    end
    if S.page=='login' and A.qr_key and not provider.busy and now()>=A.next_qr_poll then
      if now()-A.qr_started>150000 then A.qr_key=nil;A.message='二维码已过期，Home 刷新'
      else
        A.next_qr_poll=now()+3000
        provider.qr_check(A.qr_key,function(doc,e)
          if not A.alive then return end
          if not doc then A.qr_key=nil;failure(e);return end
          if doc.code==803 then
            A.qr_key=nil
            local saved,saveerr=provider.save_session()
            if not saved then failure(saveerr);A.message='Home 重新扫码';return end
            load_account()
          elseif doc.code==802 then A.message='已扫码，请在手机确认'
          elseif doc.code==800 then A.qr_key=nil;A.message='二维码已过期，Home 刷新'
          else A.message='等待扫码'end
        end)
      end
    end
    lyricLoader.poll(player.status~='buffering'and
      ((player.stats and (player.stats.buffer_bytes or 0)>=65536)or player.status=='paused'))
    A.lyrics=lyricLoader.lines;A.lyric_status=lyricLoader.status
    if A.lyrics then
      local text='';for _,line in ipairs(A.lyrics)do if line.at>(player.position or 0)then break end;text=line.text end
      A.lyric=text
    end
    A.covers.poll()
    local background=A.uid and not provider.busy and not apiNet.current and not apiNet.pending and
      lyricLoader.status~='loading'and player.status~='buffering'and
      (player.status~='playing'or (player.stats.buffer_bytes or 0)>=196608)and
      ((player.stats.psram_free or 0)==0 or player.stats.psram_free>=524288)
    libraryCache.poll(A.uid,background,S.tab)
    A.tab_covers=A.tab_covers or {}
    for tab=1,3 do local cover=libraryCache.cover(tab);if cover then A.tab_covers[tab]=cover end end
    render()
  end)
  A.message=''
  if provider.cookie.MUSIC_U then load_account()else login()end
  -- Start the asynchronous account/QR connection before the full font loads.
  apiNet.poll()
  local fonts=tmr.create();A.timers[#A.timers+1]=fonts
  fonts:alarm(80,tmr.ALARM_AUTO,function()
    if not A.alive then return end
    local good,ready=pcall(U.load_next)
    if not good then fonts:unregister();A.boot_failed(ready);return end
    if ready then fonts:unregister();render()end
  end)
end
function A.stop()
  if not A.alive then return end;A.alive=false
  for _,t in ipairs(A.timers)do pcall(function()t:unregister()end)end
  pcall(function()key.off()end)
  if app.set_home_exit then pcall(app.set_home_exit,true)end
  if A.pad_subscribed then pcall(controller.on,'ble-main',nil)end
  if A.web then pcall(A.web.close)end
  if A.lyric_loader then A.lyric_loader.cancel()end
  if A.library_cache then A.library_cache.clear()end
  if A.covers then pcall(A.covers.close)end
  if A.provider then pcall(A.provider.close)end
  if A.player then pcall(A.player.close)elseif A.audio then pcall(A.audio.close)end
  if A.ui then pcall(A.ui.close)end
  if A.version_cleanup then pcall(A.version_cleanup);A.version_cleanup=nil end
  if rawget(_G,'NETEASE_APP')==A then _G.NETEASE_APP=nil end
end
A.shutdown=A.stop
function A.boot_failed(booterr)
  -- Startup has not accepted a login response; this error contains no credentials.
  pcall(function()file.putcontents('/sd/apps/netease/boot-error.txt',tostring(booterr))end)
  A.stop()
  if app.set_home_exit then pcall(app.set_home_exit,false)end
  local root=lv_scr_act();lv_obj_clean(root)
  lv_obj_set_style_bg_color(root,0,LV_PART_MAIN or 0)
  local label=lv_label_create(root);lv_obj_set_width(label,300)
  lv_label_set_text(label,'NetEase startup failed. Check module, fonts and settings.json.')
  key.on(key.HOME,function(event)if event==key.LONG_START then key.off();if app.set_home_exit then app.set_home_exit(true)end;app.exit()end end)
end
local Firmware=dofile(DIR..'/firmware_gate.lua')
local compatible,system_version=Firmware.check(sys)
if not compatible then
  A.error=Firmware.MESSAGE;A.version_blocked=true
  A.version_cleanup=Firmware.show(DIR,system_version,function()A.stop();app.exit()end)
  return
end
local shown,splasherr=pcall(function()A.ui=dofile(DIR..'/ui.lua')()end)
if not shown then A.boot_failed(splasherr)
else
  local startup=tmr.create();A.timers[#A.timers+1]=startup
  startup:alarm(60,tmr.ALARM_SINGLE,function()
    if not A.alive then return end
    local good,err=pcall(boot);if not good then A.boot_failed(err)end
  end)
end
