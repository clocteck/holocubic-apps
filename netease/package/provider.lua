-- Direct NetEase EAPI. No proxy server or account/rights bypass.
local M={}
-- The host has 32-bit Lua integers/floats. Keep large integral IDs exact BEFORE
-- JSON decoding; converting an already rounded/wrapped Lua number is too late.
function M.protect_ids(raw)
  local parts,at,last={},1,1
  while at<=#raw do
    local start=raw:find('["%d%-]',at)
    if not start then break end
    if raw:sub(start,start)=='"'then
      at=start+1
      while at<=#raw do
        local stop=raw:find('["\\]',at)
        if not stop then at=#raw+1;break end
        if raw:sub(stop,stop)=='"'then at=stop+1;break end
        at=stop+2
      end
    else
      local token=raw:match('^-?%d+%.?%d*[eE]?[+%-]?%d*',start)
      if token then
        at=start+#token
        if token:match('^%d+$')and (#token>10 or (#token==10 and token>'2147483647'))then
          parts[#parts+1]=raw:sub(last,start-1);parts[#parts+1]='"'..token..'"';last=at
        end
      else at=start+1 end
    end
  end
  if last==1 then return raw end
  parts[#parts+1]=raw:sub(last);return table.concat(parts)
end
function M.new(native,net,json,storage,now)
  local P={cookie={},generation=0,busy=false,alive=true,diagnostics={}}
  local saved=storage.load('session')
  if saved and type(saved.cookie)=='table' then
    for k,v in pairs(saved.cookie)do
      if type(k)=='string' and type(v)=='string' and #v<16384 and not v:find('[\r\n;]')then P.cookie[k]=v end
    end
  end
  local function header(h,name)
    for k,v in pairs(h or {})do if tostring(k):lower()==name then return v end end
  end
  local function cookies(headers)
    local values=header(headers,'set-cookie')
    if type(values)=='string'then values={values}end
    for _,line in ipairs(type(values)=='table' and values or {})do
      -- Headers may combine Set-Cookie fields; do not split Expires dates.
      for name,value in tostring(line):gmatch('([%w_%-]+)=([^;,\r\n]*)')do
        if name=='MUSIC_U' or name=='__csrf' or name=='NMTID' or name=='MUSIC_A' then
          P.cookie[name]=value~='' and value or nil
        end
      end
    end
  end
  local function cookie_header()
    local parts={'os=pc','appver=3.1.17.204416'}
    for _,k in ipairs({'MUSIC_U','__csrf','NMTID','MUSIC_A'})do
      if P.cookie[k]then parts[#parts+1]=k..'='..P.cookie[k]end
    end
    return table.concat(parts,'; ')
  end
  function P.cancel()
    P.generation=P.generation+1;P.busy=false;P.timeout=nil;net.cancel()
  end
  function P.request(path,data,done,limit)
    if not P.alive then return end
    P.cancel();local generation=P.generation;P.busy=true
    P.diagnostics={path=path,phase='encrypt',started=now()}
    data.e_r=false
    data.header={os='pc',appver='3.1.17.204416',osver='Microsoft-Windows-10',
      deviceId='CubicESP32S3',channel='netease',resolution='320x240',
      requestId=tostring(math.floor(now()))..'_0001',__csrf=P.cookie.__csrf or ''}
    for _,k in ipairs({'MUSIC_U','MUSIC_A','NMTID'})do data.header[k]=P.cookie[k]end
    local weapi=path=='/api/user/playlist' or path=='/api/v3/song/detail' or
      path=='/api/v3/discovery/recommend/songs' or path=='/api/play-record/song/list'
    local body,err,url
    if weapi then
      data.header=nil;data.csrf_token=P.cookie.__csrf or ''
      body,err=native.weapi(json.encode(data))
      url='https://music.163.com/weapi/'..path:sub(6)
    else
      body,err=native.eapi(path,json.encode(data))
      url='https://interface.music.163.com/eapi/'..path:sub(6)
    end
    P.diagnostics.crypto=weapi and 'weapi'or 'eapi'
    if not body then P.busy=false;done(nil,err);return end
    local c=net.create(url,{
      method='POST',body=body,async=true,timeout=12000,bufsz=4096,max_redirects=0,
      headers={['Content-Type']='application/x-www-form-urlencoded',
        ['Accept-Encoding']='identity',Cookie=cookie_header(),
        ['User-Agent']='NeteaseMusicDesktop/3.1.17.204416',Referer='https://music.163.com/'}})
    local chunks,bytes,status={},0,0
    local function finish(doc,error)
      if not P.alive or generation~=P.generation then return end
      P.generation=P.generation+1;P.busy=false;P.timeout=nil
      P.diagnostics.phase=error and 'error' or 'complete'
      local good=pcall(done,doc,error)
      if not good then
        P.diagnostics.phase='callback_error'
        if P.on_error then P.on_error('账号响应处理失败，请重试')end
      end
    end
    P.timeout=function()
      net.cancel();finish(nil,'网易云请求超时')
    end
    c:on('headers',function(code,h)
      if generation~=P.generation then c:close();return end
      status=code;cookies(h)
      P.diagnostics.http=code;P.diagnostics.phase='headers'
      P.diagnostics.has_music_u=P.cookie.MUSIC_U~=nil
      P.diagnostics.has_csrf=P.cookie.__csrf~=nil
      if code~=200 then c:close();finish(nil,'网易云 HTTP '..tostring(code))end
    end)
    c:on('data',function(code,chunk)
      if generation~=P.generation then c:close();return end
      if code~=200 then return end
      bytes=bytes+#chunk
      if bytes>(limit or 262144) then
        c:close();chunks={};finish(nil,'响应超过内存上限，请缩小歌单');return
      end
      chunks[#chunks+1]=chunk
    end)
    c:on('error',function()finish(nil,'网易云连接失败，请重试')end)
    c:on('complete',function()
      if generation~=P.generation then return end
      if status~=200 then finish(nil,'网易云未返回有效响应');return end
      local raw=table.concat(chunks);chunks={}
      local ok,doc=pcall(json.decode,M.protect_ids(raw))
      if not ok or type(doc)~='table'then finish(nil,'网易云返回格式不兼容');return end
      local shape={};for k,v in pairs(doc)do shape[tostring(k)]=type(v)end
      P.diagnostics.shape=shape;P.diagnostics.code=doc.code
      if doc.code==301 or doc.code==302 then
        finish(nil,'登录已失效，请重新扫码');return
      end
      if doc.code and doc.code~=200 and not (doc.code>=800 and doc.code<=803)then
        finish(nil,'网易云接口错误 '..tostring(doc.code));return
      end
      finish(doc)
    end)
    c:request()
  end
  function P.save_session()
    if not P.cookie.MUSIC_U then return nil,'未收到登录凭据' end
    return storage.save('session',{version=1,cookie=P.cookie})
  end
  function P.poll()
    if P.busy and now()-(P.diagnostics.started or now())>20000 then
      if P.timeout then P.timeout()
      else P.cancel();if P.on_error then P.on_error('网易云请求超时，Home 重试')end end
    end
  end
  function P.account(done)P.request('/api/nuser/account/get',{},done)end
  function P.logout()
    P.cancel()
    local ok,err=storage.clear_session()
    if not ok then return nil,err end
    P.cookie={};return true
  end
  function P.qr_key(done)P.request('/api/login/qrcode/unikey',{type=3},done)end
  function P.qr_check(key,done)P.request('/api/login/qrcode/client/login',{type=3,key=key},done)end
  function P.playlists(uid,offset,done)
    P.request('/api/user/playlist',{uid=uid,limit=20,offset=offset or 0,includeVideo=false},done)
  end
  function P.likes(uid,done)
    P.request('/api/song/like/get',{uid=tostring(uid)},done,524288)
  end
  function P.recent(done)
    P.request('/api/play-record/song/list',{limit=50},done,524288)
  end
  function P.playlist(id,done)
    P.request('/api/v6/playlist/detail',{id=id,n=0,s=0},done,524288)
  end
  function P.details(ids,done)
    local c={};for _,id in ipairs(ids)do c[#c+1]={id=id}end
    P.request('/api/v3/song/detail',{c=json.encode(c)},done)
  end
  function P.daily(done)P.request('/api/v3/discovery/recommend/songs',{},done)end
  function P.url(id,done)
    P.request('/api/song/enhance/player/url/v1',
      {ids='['..tostring(id)..']',level='standard',encodeType='mp3'},function(doc,err)
      local item=doc and doc.data and doc.data[1]
      if not item then done(nil,err or '没有播放地址');return end
      if type(item.url)~='string' or item.url=='' then done(nil,'歌曲不可播：版权或账号权限限制');return end
      if item.type~='mp3' then done(nil,'平台未返回 MP3，已拒绝播放');return end
      if item.freeTrialInfo and type(item.freeTrialInfo)=='table' then
        done(nil,'仅提供试听，当前版本不自动播放试听');return
      end
      done(item)
    end)
  end
  function P.lyric(id,done)P.request('/api/song/lyric',{id=id,lv=-1,kv=-1,tv=-1},done,65536)end
  function P.close()P.alive=false;P.cancel();P.cookie={}end
  return P
end
return M
