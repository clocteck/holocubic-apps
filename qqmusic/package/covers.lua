-- Four in-memory thumbnails, optionally backed by a bounded FIFO SD cache.
-- Shares the metadata transport: a user API request preempts a thumbnail.
local M={MAX_BYTES=96*1024}
function M.jpeg_size(raw)
  if type(raw)~='string' or raw:sub(1,2)~='\255\216' then return nil end
  local at=3
  while at+3<=#raw do
    if raw:byte(at)~=255 then return nil end
    while raw:byte(at)==255 do at=at+1 end
    local marker=raw:byte(at);at=at+1
    if not marker or marker==0xDA or marker==0xD9 then return nil end
    if marker~=0xD8 and marker~=1 and not(marker>=0xD0 and marker<=0xD7)then
      local a,b=raw:byte(at,at+1);if not b then return nil end
      local len=a*256+b;if len<2 or at+len-1>#raw then return nil end
      if marker==0xC0 or marker==0xC1 then
        if len<8 then return nil end
        local h1,h2,w1,w2=raw:byte(at+3,at+6)
        return w1*256+w2,h1*256+h2
      end
      at=at+len
    end
  end
end
function M.image_size(raw)
  if type(raw)~='string'or #raw>M.MAX_BYTES then return nil end
  if raw:sub(1,8)~='\137PNG\r\n\26\n' then
    local w,h=M.jpeg_size(raw)
    if w and raw:sub(-2)=='\255\217'then return w,h,'jpeg' end
    return nil
  end
  local function u32(at)
    local a,b,c,d=raw:byte(at,at+3)
    if not d then return nil end
    return a*16777216.0+b*65536+c*256+d
  end
  if #raw<45 or u32(9)~=13 or raw:sub(13,16)~='IHDR'then return nil end
  local w,h=u32(17),u32(21)
  if w<1 or h<1 or w>136 or h>136 then return nil end
  local at,has_data=9,false
  while at+11<=#raw do
    local n=u32(at);local kind=raw:sub(at+4,at+7)
    if n>#raw-at-11 then return nil end
    if kind=='IHDR'and at~=9 then return nil end
    if kind=='IDAT'then has_data=true end
    if kind=='IEND'then
      if n==0 and at+11==#raw and has_data then return w,h,'png' end
      return nil
    end
    at=at+n+12
  end
end
function M.thumbnail(url)
  if type(url)~='string' or #url>2048 then return nil end
  local host=url:match('^https?://([^/:?#]+)')
  if host~='y.gtimg.cn'then return nil end
  local clean=url:gsub('[?#].*$',''):gsub('^http:','https:')
  if not clean:match('^https://y%.gtimg%.cn/music/photo_new/T002R%d+x%d+M000[%w_]+%.jpg$')then return nil end
  return (clean:gsub('T002R%d+x%d+M000','T002R90x90M000'))
end
-- Only these two CDN hosts have been verified to serve interchangeable paths.
-- The first result is a cache identity, never a replacement download URL.
function M.identity(url)
  return url
end
function M.new(net,provider,player,now,disk)
  local C={cache={},order={},wanted={},active=nil,requests=0,errors=0,successes=0,last_error=''}
  local MAX_BYTES=M.MAX_BYTES
  local save_queue={}
  local function put(url,value)
    url=M.identity(url)
    C.cache[url]=value
    for i=#C.order,1,-1 do if C.order[i]==url then table.remove(C.order,i)end end
    C.order[#C.order+1]=url
    while #C.order>4 do C.cache[table.remove(C.order,1)]=nil end
  end
  function C.want(urls)
    local wanted,ids,seen={},{},{}
    for _,url in ipairs(urls)do
      local u=M.thumbnail(url);local id=u and M.identity(u)
      if id and not seen[id]then seen[id]=true;wanted[#wanted+1]=u;ids[#ids+1]=id end
    end
    local signature=table.concat(ids,'\n')
    C.wanted=wanted -- Keep the provider's latest URL even when identity is unchanged.
    if signature~=C.signature then
      C.signature=signature;C.not_before=now()+300
      for _,url in ipairs(wanted)do
        local item=C.cache[M.identity(url)]
        if item and item.failed and (item.attempts or 0)>=3 then item.attempts=0;item.retry_at=now()+300 end
      end
    end
  end
  function C.get(url)
    local u=M.thumbnail(url);local item=u and C.cache[M.identity(u)]
    return item and item.data or nil,item
  end
  function C.suspend()
    if C.active and not C.active.finished then C.active:close()end
  end
  function C.poll(allow_network)
    if C.active then
      if C.active.finished then C.active=nil;C.abort=nil
      elseif now()-(C.started_at or now())>12000 and C.abort then C.abort('timeout')end
    end
    if now()<(C.not_before or 0)then return end
    local st=player.stats or {}
    if disk and #save_queue>0 then
      local entry=table.remove(save_queue,1);disk.put(entry.url,entry.data);return
    end
    local url
    for _,u in ipairs(C.wanted)do
      local item=C.cache[M.identity(u)]
      if not item or (item.failed and item.attempts<3 and now()>=item.retry_at)then url=u;break end
    end
    if not url then return end
    if disk then
      local data,info=disk.get(url)
      if data then info.data=data;put(url,info);C.last_error='';return end
    end
    if allow_network==false or player.status=='buffering'or
      (player.status=='playing'and (st.buffer_bytes or 0)<32768)then return end
    if C.active or provider.busy or net.current or net.pending then return end
    local attempts=((C.cache[M.identity(url)]or {}).attempts or 0)+1
    local c=net.create(url,{async=true,timeout=10000,bufsz=2048,max_redirects=0,
      headers={['Accept-Encoding']='identity',['User-Agent']='CubicQQMusic/1.0.0'}})
    C.active=c;C.requests=C.requests+1;C.started_at=now()
    local chunks,bytes,valid,status,expected={},0,true,0,nil
    local function bad(reason)
      if not valid then return end
      valid=false;chunks={};C.errors=C.errors+1;C.last_error=reason or 'network'
      put(url,{failed=true,attempts=attempts,retry_at=now()+2000*attempts,reason=C.last_error})
    end
    C.abort=function(reason)bad(reason);c:close()end
    c:on('headers',function(code,h)
      status=code;C.last_http=code
      if code~=200 then bad('http_'..tostring(code));c:close();return end
      for k,v in pairs(h or {})do
        if tostring(k):lower()=='content-length'then
          expected=tonumber(v)
          if expected and expected>MAX_BYTES then bad('too_large');c:close()end
        end
      end
    end)
    c:on('data',function(code,data)
      if not valid then return end
      if code~=200 or type(data)~='string'then bad('invalid_data');c:close();return end
      bytes=bytes+#data
      if bytes>MAX_BYTES then bad('too_large');c:close();return end
      chunks[#chunks+1]=data
    end)
    c:on('error',function()bad('network')end)
    c:on('complete',function()
      if not valid then return end
      if status~=200 or bytes==0 or (expected and bytes~=expected)then bad('incomplete');return end
      local raw=table.concat(chunks);chunks={}
      local w,h,format=M.image_size(raw)
      if not w or w<1 or h<1 or w>136 or h>136 then bad('unsupported_image');return end
      put(url,{data=raw,width=w,height=h,format=format,source='network'})
      if disk then save_queue[#save_queue+1]={url=url,data=raw}end
      C.successes=C.successes+1;C.last_error=''
    end)
    c:request()
  end
  function C.state(url)
    local normalized=M.thumbnail(url);local item=normalized and C.cache[M.identity(normalized)]
    return {has_url=normalized~=nil,ready=item and item.data~=nil or false,
      bytes=item and item.data and #item.data or 0,width=item and item.width or 0,height=item and item.height or 0,
      attempts=item and item.attempts or 0,retry_ms=item and item.retry_at and math.max(0,item.retry_at-now())or 0,
      active=C.active~=nil,requests=C.requests,successes=C.successes,errors=C.errors,
      source=item and item.source or '',format=item and item.format or '',max_bytes=MAX_BYTES,
      disk=disk and disk.state()or nil,
      last_http=C.last_http or 0,last_error=C.last_error}
  end
  function C.close()
    if C.active then C.active:close()end
    if disk then for _,entry in ipairs(save_queue)do disk.put(entry.url,entry.data)end end
    save_queue={};C.cache={};C.order={};C.wanted={}
  end
  return C
end
return M
