-- Per-song lyric state. Failures retry twice; stale responses cannot replace a new song.
local M={MAX_ATTEMPTS=3}
function M.parse(doc)
  if type(doc)~='table'or (doc.code and doc.code~=200)then return nil end
  if doc.nolyric==true or doc.uncollected==true then return {} end
  local raw=type(doc.lrc)=='table'and doc.lrc.lyric
  if type(raw)~='string'then return nil end
  local lines={};local text_bytes=0
  for line in raw:gmatch('[^\r\n]+')do
    local text=line:gsub('%[[^%]]*%]','')
    local visible=text:gsub('\194\160',' '):gsub('　',' '):gsub('\226\128\139',''):match('%S')
    if visible then
      for m,s in line:gmatch('%[(%d+):([%d%.]+)%]')do
        local minute,second=tonumber(m),tonumber(s)
        if minute and second and second>=0 and second<60 then
          if #lines>=1024 or text_bytes+#text>65536 then table.sort(lines,function(a,b)return a.at<b.at end);return lines end
          text_bytes=text_bytes+#text
          lines[#lines+1]={at=minute*60+second,text=text}
        end
      end
    end
  end
  table.sort(lines,function(a,b)return a.at<b.at end)
  return lines
end
function M.new(provider,now)
  local L={status='idle',lines={},attempts=0,generation=0,active=false,enabled=false,cache={},order={},hits=0}
  function L.start(id)
    L.generation=L.generation+1;L.id=id;L.lines={};L.status='loading'
    L.attempts=0;L.active=false;L.enabled=false;L.retry_at=0
    local hit=L.cache[tostring(id)]
    if hit then L.lines=hit;L.status=#hit>0 and 'ready'or 'empty';L.hits=L.hits+1 end
  end
  function L.enable()L.enabled=true end
  function L.cancel()
    L.generation=L.generation+1;L.active=false;L.enabled=false
    L.lines={};L.status='empty'
  end
  function L.clear()L.cancel();L.cache={};L.order={}end
  local function failed()
    L.active=false
    if L.attempts>=M.MAX_ATTEMPTS then L.status='empty';L.enabled=false
    else L.retry_at=now()+1000*L.attempts end
  end
  function L.poll(allow)
    if L.status~='loading'or not L.enabled then return end
    if L.active then
      -- Browsing may preempt the shared metadata connection without a callback.
      if L.request_generation~=provider.generation then failed()end
      return
    end
    if not allow or provider.busy or now()<L.retry_at then return end
    L.attempts=L.attempts+1;L.active=true
    local generation=L.generation
    local attempt=L.attempts
    local ok=pcall(provider.lyric,L.id,function(doc,err)
      if generation~=L.generation or attempt~=L.attempts or not L.active then return end
      L.active=false
      local lines=not err and M.parse(doc)
      if not lines then failed();return end
      L.lines=lines;L.status=#lines>0 and 'ready'or 'empty';L.enabled=false
      local id=tostring(L.id)
      for i=#L.order,1,-1 do if L.order[i]==id then table.remove(L.order,i)end end
      L.order[#L.order+1]=id;L.cache[id]=lines
      while #L.order>3 do L.cache[table.remove(L.order,1)]=nil end
    end)
    L.request_generation=provider.generation
    if not ok then failed()end
  end
  return L
end
return M
