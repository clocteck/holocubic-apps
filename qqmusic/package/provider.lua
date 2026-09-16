-- Direct QQ Music API; never routes credentials through a third-party service.
local M={}
function M.encode(s)return (tostring(s):gsub('[^%w%-_.~]',function(c)return string.format('%%%02X',c:byte())end))end
function M.query(t)
  local keys,out={},{};for k in pairs(t)do keys[#keys+1]=k end;table.sort(keys)
  for _,k in ipairs(keys)do out[#out+1]=M.encode(k)..'='..M.encode(t[k])end;return table.concat(out,'&')
end
function M.hash33(s,seed)
  local n=seed or 0;for i=1,#s do n=((n<<5)+n+s:byte(i))&0x7fffffff end;return n
end
function M.header(h,name)for k,v in pairs(h or {})do if tostring(k):lower()==name then return v end end end
function M.cookies(headers)
  local jar={};local h=M.header(headers,'set-cookie');if type(h)=='string'then h={h}end
  for _,line in ipairs(type(h)=='table'and h or {})do
    for name,value in tostring(line):gmatch('([%w_%-]+)=([^;,\r\n]*)')do
      if name=='qrsig'or name=='p_skey'or name=='p_uin'or name=='pt4_token'or name=='pt_oauth_token'or name=='skey'or name=='uin'then jar[name]=value end
    end
  end;return jar
end
function M.cookie_header(jar)
  local keys,out={},{};for k in pairs(jar or {})do keys[#keys+1]=k end;table.sort(keys)
  for _,k in ipairs(keys)do local v=jar[k];if type(v)=='string'and not v:find('[\r\n;]')then out[#out+1]=k..'='..v end end
  return table.concat(out,'; ')
end
-- Preserve IDs before the device's 32-bit JSON decoder can round/wrap them.
function M.protect_ids(raw)
  local out,at,last={},1,1
  while at<=#raw do
    local start=raw:find('["%d%-]',at);if not start then break end
    if raw:sub(start,start)=='"'then
      at=start+1
      while at<=#raw do local stop=raw:find('["\\]',at);if not stop then at=#raw+1;break end
        if raw:sub(stop,stop)=='"'then at=stop+1;break end;at=stop+2 end
    else
      local token=raw:match('^-?%d+%.?%d*[eE]?[+%-]?%d*',start)
      if not token or token==''then at=start+1 else at=start+#token
        if token:match('^%d+$')and (#token>10 or (#token==10 and token>'2147483647'))then
          out[#out+1]=raw:sub(last,start-1);out[#out+1]='"'..token..'"';last=at end
      end
    end
  end
  if last==1 then return raw end;out[#out+1]=raw:sub(last);return table.concat(out)
end
function M.song(s)
  if type(s)~='table'then return end;s=s.songInfo or s
  local mid=s.mid or s.songmid;local album=s.album or {};local media=s.file or {}
  if type(mid)~='string'or not mid:match('^%w+$')then return end
  local am=album.pmid or album.mid or s.albummid
  local cover=type(am)=='string'and am:match('^[%w_]+$')and ('https://y.gtimg.cn/music/photo_new/T002R90x90M000'..am..'.jpg')or nil
  return {id=mid,mid=mid,songid=s.id or s.songid,name=s.title or s.name or s.songname or mid,
    ar=s.singer or {},al={name=album.name or s.albumname or '',picUrl=cover},
    dt=(tonumber(s.interval)or 0)*1000,media_mid=media.media_mid or mid,songtype=s.type or 0}
end
function M.new(native,net,json,storage,now,owner)
  local P={alive=true,busy=false,generation=0,diagnostics={},session={}}
  local saved=not owner and storage.load('session')
  if type(saved)=='table'and type(saved.musicid)=='string'and saved.musicid:match('^%d+$')and
    type(saved.musickey)=='string'and #saved.musickey<8192 and not saved.musickey:find('[\r\n;]')then P.session=saved end
  function P.fork(channel)return M.new(native,channel,json,storage,now,P)end
  function P.cancel()P.generation=P.generation+1;P.busy=false;P.finish=nil;net.cancel()end
  function P.raw(url,options,done)
    P.cancel();local g=P.generation;P.busy=true;options=options or {}
    P.diagnostics={phase='request',operation=options.operation or 'api',started=now(),retryable=false}
    local headers={['Accept-Encoding']='identity',['User-Agent']='Mozilla/5.0',Referer='https://y.qq.com/'}
    for k,v in pairs(options.headers or {})do headers[k]=v end
    P.network_timeout=(options.timeout or 12000)+8000
    local c=net.create(url,{method=options.method or 'GET',body=options.body,async=true,timeout=options.timeout or 12000,
      bufsz=4096,max_redirects=0,headers=headers})
    P.connection=c
    local chunks,bytes,status,response_headers={},0,0,{}
    local function finish(raw,err)
      if not P.alive or g~=P.generation then return end
      P.generation=P.generation+1;P.busy=false;P.finish=nil;P.diagnostics.phase=err and 'error'or 'complete'
      P.diagnostics.total_ms=now()-P.diagnostics.started
      local ok=pcall(done,raw,err,status,response_headers)
      if not ok and P.on_error then P.on_error('QQ音乐响应处理失败')end
    end
    P.finish=finish
    c:on('start',function()
      if g~=P.generation then return end
      P.diagnostics.phase='connecting';P.diagnostics.network_started=now()
      P.diagnostics.queue_ms=now()-P.diagnostics.started
    end)
    c:on('headers',function(code,h)
      if g~=P.generation then c:close();return end
      status=code;response_headers=h or {};P.diagnostics.http=code
      P.diagnostics.headers_ms=now()-(c.started_at or P.diagnostics.started)
      if code~=200 and not(options.redirect and (code==302 or code==303))then P.diagnostics.retryable=code==408 or code==429 or code>=500;c:close();finish(nil,'QQ音乐 HTTP '..tostring(code))end
    end)
    c:on('data',function(_,chunk)
      if g~=P.generation then return end
      if bytes==0 then P.diagnostics.first_byte_ms=now()-(c.started_at or P.diagnostics.started)end
      bytes=bytes+#chunk;if bytes>(options.limit or 262144)then chunks={};c:close();finish(nil,'响应超过内存上限');return end
      chunks[#chunks+1]=chunk
    end)
    c:on('error',function()P.diagnostics.retryable=true;finish(nil,'QQ音乐连接失败，请重试')end)
    c:on('complete',function()if status==0 then finish(nil,'QQ音乐未返回响应')else finish(table.concat(chunks))end end)
    c:request()
  end
  local function decode(raw,err,done)
    if not raw then done(nil,err);return end
    local ok,doc=pcall(json.decode,M.protect_ids(raw))
    if not ok or type(doc)~='table'then done(nil,'QQ音乐响应格式不兼容');return end
    if doc.code and doc.code~=0 then done(nil,'QQ音乐接口错误 '..tostring(doc.code));return end;done(doc)
  end
  function P.rpc(module,method,param,done,comm)
    if owner then P.session=owner.session end
    local common={ct=24,cv=0,format='json',uin=P.session.musicid or '0',g_tk=M.hash33(P.session.musickey or '',5381)}
    if P.session.musickey then common.authst=P.session.musickey;common.tmeLoginType=P.session.login_type or 2 end
    for k,v in pairs(comm or {})do common[k]=v end
    local body=json.encode({comm=common,req_0={module=module,method=method,param=param}})
    P.raw('https://u.y.qq.com/cgi-bin/musicu.fcg',{method='POST',body=body,
      headers={['Content-Type']='application/json',Cookie=M.cookie_header({uin=P.session.musicid,qqmusic_uin=P.session.musicid,qqmusic_key=P.session.musickey,qm_keyst=P.session.musickey})},operation=method},function(raw,e)
      decode(raw,e,function(doc,err)
        local result=doc and doc.req_0;if not result then done(nil,err or 'QQ音乐接口无数据');return end
        P.diagnostics.code=result.code
        if result.code~=0 then done(nil,'QQ音乐接口错误 '..tostring(result.code));return end;done(result.data)
      end)
    end)
  end
  local function list(raw,total)
    local songs={};for _,entry in ipairs(type(raw)=='table'and raw or {})do local song=M.song(entry);if song then songs[#songs+1]=song end end
    return {songs=songs,total=tonumber(total)or #songs}
  end
  function P.top(id,offset,done)
    P.rpc('musicToplist.ToplistInfoServer','GetDetail',{topid=id,offset=offset,num=20},function(d,e)
      if not d then done(nil,e);return end;done(list(d.songInfoList,d.data and d.data.totalNum))end)
  end
  function P.search(query,page,done)
    P.rpc('music.search.SearchCgiService','DoSearchForQQMusicDesktop',{query=query,search_type=0,num_per_page=20,page_num=page},function(d,e)
      if not d then done(nil,e);return end;local songs=d.body and d.body.song and d.body.song.list
      if type(songs)~='table'or #songs==0 then done(nil,'搜索未返回歌曲，可能需要登录或接口已调整');return end
      done(list(songs,d.meta and d.meta.sum))end)
  end
  function P.playlist(id,offset,done)
    P.rpc('music.srfDissInfo.aiDissInfo','uniform_get_Dissinfo',{disstid=id,enc_host_uin='',tag=1,userinfo=1,
      song_begin=offset,song_num=20,onlysong=0},function(d,e)
      if not d then done(nil,e);return end
      if type(d.songlist)~='table'then done(nil,'歌单响应格式不兼容');return end
      local result=list(d.songlist,d.total_song_num or (d.dirinfo and d.dirinfo.songnum));result.title=d.dirinfo and d.dirinfo.title;done(result)end)
  end
  function P.favorites(offset,done)
    if not P.session.musicid then done(nil,'请先登录');return end
    local function request(euin)
      P.rpc('music.srfDissInfo.DissInfo','CgiGetDiss',{disstid=0,dirid=201,tag=true,song_begin=offset,
        song_num=20,userinfo=true,orderlist=true,enc_host_uin=euin},function(d,e)
          if not d then done(nil,e);return end
          if type(d.songlist)~='table'then done(nil,'收藏响应格式不兼容');return end
          done(list(d.songlist,d.total_song_num))end)
    end
    if P.session.encrypt_uin and P.session.encrypt_uin~=''then request(P.session.encrypt_uin);return end
    P.raw('https://c.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg?'..M.query({format='json',cid=205360838,
      userid=P.session.musicid,reqfrom=1,g_tk=M.hash33(P.session.musickey,5381)}),{operation='profile',
      headers={Cookie=M.cookie_header({uin=P.session.musicid,qqmusic_uin=P.session.musicid,qqmusic_key=P.session.musickey,qm_keyst=P.session.musickey})}},function(raw,e)
      decode(raw,e,function(d,err)
        local info=d and d.data and d.data.creator
        local euin=info and (info.encrypt_uin or info.encryptUin)
        if not euin then done(nil,err or '缺少账号加密标识，请重新扫码');return end
        P.session.encrypt_uin=euin;request(euin)
      end)
    end)
  end
  function P.url(song,done)
    if owner then P.session=owner.session end
    P.rpc('vkey.GetVkeyServer','CgiGetVkey',{guid='2796982635',songmid={song.mid},songtype={song.songtype or 0},
      uin=P.session.musicid or '0',loginflag=P.session.musickey and 1 or 0,platform='20',filename={'M500'..song.media_mid..'.mp3'}},function(d,e)
      local item=d and d.midurlinfo and d.midurlinfo[1];local purl=item and item.purl
      if type(purl)~='string'or purl==''then done(nil,e or '歌曲不可播：请登录并确认账号播放权限');return end
      if not purl:match('^M500[%w]+%.mp3%?')or purl:find('[\r\n]')then done(nil,'未返回完整标准 MP3，已拒绝试听或其他格式');return end
      local urls,seen={},{}
      for _,sip in ipairs(d.sip or {})do
        local h=sip:match('^https?://([^/]+)/$')
        if h and h:match('%.stream%.qqmusic%.qq%.com$')then
          local url=sip:gsub('^http:','https:')..purl
          if not seen[url]and #urls<3 then seen[url]=true;urls[#urls+1]=url end
        end
      end
      if #urls==0 then done(nil,'音频 CDN 不兼容');return end;done({url=urls[1],urls=urls,expi=60})end)
  end
  function P.lyric(id,done)
    P.raw('https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?'..M.query({songmid=id,format='json',nobase64=1}),
      {operation='lyric',limit=65536},function(raw,e)decode(raw,e,function(d,err)done(d and {lrc={lyric=d.lyric}}or nil,err)end)end)
  end
  function P.save_session(session)
    if type(session)~='table'or type(session.musickey)~='string'or #session.musickey==0 or #session.musickey>8192 or
      session.musickey:find('[\r\n;]')then return nil,'未收到有效音乐凭据'end
    local id=tostring(session.str_musicid or session.musicid or '')
    if not id:match('^%d+$')or id=='0'then return nil,'无效账号标识'end
    local clean={musicid=id,musickey=session.musickey,login_type=session.login_type or session.loginType or 2,
      encrypt_uin=type(session.encryptUin)=='string'and session.encryptUin or '',
      nickname=type(session.nick)=='string'and session.nick or 'QQ音乐用户'}
    local saved,e=storage.save('session',clean);if not saved then return nil,e end;P.session=clean;return true
  end
  function P.account(done)
    if not P.session.musicid then done(nil,'未登录');return end
    local function fallback()
      P.raw('https://c.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg?'..M.query({format='json',cid=205360838,
        userid=P.session.musicid,reqfrom=1,g_tk=M.hash33(P.session.musickey,5381)}),{operation='account_profile',
        headers={Cookie=M.cookie_header({uin=P.session.musicid,qqmusic_uin=P.session.musicid,qqmusic_key=P.session.musickey,qm_keyst=P.session.musickey})}},function(raw,e)
          decode(raw,e,function(d,err)
            local info=d and d.data and d.data.creator
            if not info then done(nil,err or '用户资料暂不可用');return end
            local name=info.nick or info.nickname or info.hostname
            if type(name)~='string'or name==''then name='QQ音乐用户'end
            done({name=name,avatar=info.headpic or info.headurl or '',login_type=P.session.login_type or 2})
          end)
        end)
    end
    local euin=P.session.encrypt_uin
    if not euin or euin==''then fallback();return end
    P.rpc('music.UnifiedHomepage.UnifiedHomepageSrv','GetHomepageHeader',{uin=euin,IsQueryTabDetail=1},function(d,e)
      local info=d and d.Info and d.Info.BaseInfo
      if not info or not info.Name or info.Name==''then fallback();return end
      done({name=info.Name or P.session.nickname or 'QQ音乐用户',avatar=info.Avatar or '',login_type=P.session.login_type or 2})
    end)
  end
  function P.membership(done)
    if not P.session.musicid then done(nil,'未登录');return end
    P.rpc('VipLogin.VipLoginInter','vip_login_base',{},function(d,e)
      if not d or type(d.identity)~='table'then done(nil,e or '会员状态未知');return end
      local i=d.identity;local known=i.vip~=nil or i.HugeVip~=nil or d.svip~=nil
      local vip=tonumber(d.svip)==1 or tonumber(i.HugeVip)==1 or tonumber(i.vip)==1
      done({known=known,active=known and vip or false,
        name=not known and '未知'or tonumber(d.svip)==1 and '超级会员'or tonumber(i.HugeVip)==1 and '豪华绿钻'or vip and '绿钻会员'or '非会员',
        expires=type(i.HugeVipEnd)=='string'and i.HugeVipEnd or '',level=tonumber(i.level)or 0})
    end)
  end
  function P.logout()
    local ok,e=storage.clear_session();if not ok then return nil,e end
    P.cancel();P.session={};return true
  end
  function P.poll()
    local c=P.connection;local started=c and c.started_at
    local expired=started and (now()-started>(P.network_timeout or 20000)or
      (not P.diagnostics.first_byte_ms and now()-started>10000))or
      (not started and now()-(P.diagnostics.started or now())>10000)
    if P.busy and expired then
      P.diagnostics.retryable=true
      local finish=P.finish;net.cancel();if finish then finish(nil,'QQ音乐请求超时，请重试')end end
  end
  function P.close()P.alive=false;P.cancel();P.session={}end
  return P
end
return M
