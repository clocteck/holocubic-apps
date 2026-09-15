-- FIFO SD thumbnail cache. Never touches session/settings or other directories.
local M={ROOT='/sd/data/qqmusic/covers',LIMIT=10*1024*1024}
local MAGIC='NCM-COVER-1\n'
local MAX_IMAGE=96*1024
local MAX_FILE=MAX_IMAGE+2048+#MAGIC+1
function M.key(url)
  local a,b=0x811c9dc5,5381
  for i=1,#url do
    local byte=url:byte(i)
    a=((a~byte)*16777619)&0xffffffff;b=((b<<5)+b+byte)&0xffffffff
  end
  return string.format('%08x%08x',a,b)
end
local function owned(name)
  local seq,key=name:match('^(%d%d%d%d%d%d%d%d%d%d)%-([0-9a-f]+)%.ncmc$')
  seq=tonumber(seq)
  if seq and seq>0 and seq<2147483647 and key and #key==16 then return seq,key end
end
function M.new(fs,validate,limit,identity)
  identity=identity or function(url)return url end
  local D={entries={},order={},bytes=0,files=0,next_seq=1,initialized=false,
    limit=math.min(limit or M.LIMIT,M.LIMIT),hits=0,writes=0,evicted=0,last_error=''}
  local function err(reason)D.last_error=reason;return nil end
  local function path(name)assert(owned(name)or (name:sub(-4)=='.tmp'and owned(name:sub(1,-5))));return M.ROOT..'/'..name end
  local function remove(entry,evict)
    fs.remove(path(entry.name))
    if fs.exists(path(entry.name))then return err('remove_failed')end
    D.bytes=math.max(0,D.bytes-entry.size);D.files=D.files-1
    if D.entries[entry.key]==entry then D.entries[entry.key]=nil end
    for i,v in ipairs(D.order)do if v==entry then table.remove(D.order,i);break end end
    if evict then D.evicted=D.evicted+1 end
    return true
  end
  local function initialize()
    if D.initialized then return not D.blocked end
    for _,dir in ipairs({'/sd/data','/sd/data/qqmusic',M.ROOT})do
      if not fs.exists(dir)then fs.mkdir(dir)end
      local st=fs.stat(dir)
      if not st or not st.is_dir then return err('directory_unavailable')end
    end
    local listing=fs.listdir(M.ROOT)
    if type(listing)~='table'then return err('scan_failed')end
    D.entries={};D.order={};D.bytes=0;D.files=0;D.next_seq=1;D.blocked=false
    for _,item in ipairs(listing)do
      local name=item.name
      if type(name)=='string'and not name:find('[/\\]')then
        if item.is_dir then D.blocked=true;D.last_error='unexpected_directory'
        else
          local size=tonumber(item.size)or 0
          D.bytes=D.bytes+size
          local seq,key=owned(name)
          if not seq and name:sub(-4)=='.tmp'and owned(name:sub(1,-5))then
            fs.remove(path(name))
            if not fs.exists(path(name))then D.bytes=D.bytes-size
            else D.blocked=true;D.last_error='temp_cleanup_failed'end
          elseif seq then
            local entry={name=name,key=key,seq=seq,size=size}
            D.order[#D.order+1]=entry;D.files=D.files+1
            D.next_seq=math.max(D.next_seq,seq+1)
          end
        end
      end
    end
    table.sort(D.order,function(a,b)return a.seq<b.seq end)
    for _,entry in ipairs(D.order)do D.entries[entry.key]=entry end
    D.initialized=true
    while D.bytes>D.limit and #D.order>0 do if not remove(D.order[1],true)then D.blocked=true;break end end
    return not D.blocked
  end
  local function read(entry,url)
    local stat=fs.stat(path(entry.name))
    if not stat or stat.is_dir or stat.size~=entry.size or entry.size>MAX_FILE then return nil end
    local blob=fs.getcontents(path(entry.name))
    if type(blob)~='string'or #blob~=entry.size or blob:sub(1,#MAGIC)~=MAGIC then return nil end
    local split=blob:find('\n',#MAGIC+1,true)
    if not split or split-#MAGIC-1>2048 then return nil end
    local stored_url=blob:sub(#MAGIC+1,split-1)
    if identity(stored_url)~=identity(url)then return nil end
    local raw=blob:sub(split+1);local w,h,format=validate(raw)
    if #raw>MAX_IMAGE or not w or w<1 or h<1 or w>136 or h>136 then return nil end
    if format~='png'and raw:sub(-2)~='\255\217'then return nil end
    return raw,{width=w,height=h,format=format or 'jpeg',source='sd'}
  end
  local function lookup(url)
    local id,alias=identity(url)
    local first=D.entries[M.key(id)]
    local second=alias and D.entries[M.key(alias)]
    if first==second then second=nil end
    if not first or (second and second.seq<first.seq)then first,second=second,first end
    -- At most two indexed reads, no full-directory image scan or migration writes.
    -- Prefer the earliest valid legacy file so FIFO age survives CDN rotation.
    for _,entry in ipairs({first,second})do
      local data,info=read(entry,url)
      if data then return data,info end
      if not remove(entry,false)then return nil end
    end
  end
  function D.get(url)
    local ok,raw,item=pcall(function()
      if not initialize()then return nil end
      local data,info=lookup(url)
      if not data then return nil end
      D.hits=D.hits+1;D.last_error='';return data,info
    end)
    if not ok then return err('read_failed')end
    return raw,item
  end
  function D.put(url,raw)
    local ok,result=pcall(function()
      if type(url)~='string'or #url>2048 or url:find('[\r\n]')or type(raw)~='string'or #raw>MAX_IMAGE then return err('invalid_entry')end
      local w,h,format=validate(raw)
      if not w or w<1 or h<1 or w>136 or h>136 then return err('invalid_image')end
      if format~='png'and raw:sub(-2)~='\255\217'then return err('invalid_image')end
      if not initialize()then return nil end
      if lookup(url)then return true end -- Cache hits do not refresh FIFO age.
      local key=M.key(identity(url))
      -- A failed removal must not create a newer duplicate over the same key.
      local _,alias=identity(url)
      if D.entries[key]or (alias and D.entries[M.key(alias)])then return nil end
      local blob=MAGIC..url..'\n'..raw
      if #blob>D.limit then return err('entry_exceeds_budget')end
      while D.bytes+#blob>D.limit and #D.order>0 do if not remove(D.order[1],true)then return nil end end
      if D.bytes+#blob>D.limit then return err('budget_occupied')end
      if D.next_seq>=2147483647 then return err('sequence_exhausted')end
      local name=string.format('%010d-%s.ncmc',D.next_seq,key);D.next_seq=D.next_seq+1
      local tmp=name..'.tmp'
      local wrote=fs.putcontents(path(tmp),blob)
      local st=fs.stat(path(tmp))
      if not wrote or not st or st.size~=#blob or fs.getcontents(path(tmp))~=blob then
        fs.remove(path(tmp));D.initialized=false;return err('write_failed')
      end
      if not fs.rename(path(tmp),path(name))then fs.remove(path(tmp));D.initialized=false;return err('commit_failed')end
      local entry={name=name,key=key,seq=D.next_seq-1,size=#blob}
      D.entries[key]=entry;D.order[#D.order+1]=entry;D.bytes=D.bytes+#blob;D.files=D.files+1
      D.writes=D.writes+1;D.last_error='';return true
    end)
    if not ok then D.initialized=false;return err('write_failed')end
    return result
  end
  function D.state()
    return {limit_bytes=D.limit,bytes=D.bytes,files=D.files,hits=D.hits,writes=D.writes,
      evicted=D.evicted,ready=D.initialized and not D.blocked,last_error=D.last_error}
  end
  return D
end
return M
