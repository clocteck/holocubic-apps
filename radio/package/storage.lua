-- User data lives outside the install directory. Never ship these JSON files
-- in the App package, and never delete the legacy copy during migration.
local M={ROOT='/sd/data/radio',LEGACY='/sd/apps/radio'}
local allowed={stations=true,config=true}
local function valid(kind,doc)
  if type(doc)~='table' then return false end
  if kind=='config' then
    return doc.station_id==nil or (type(doc.station_id)=='number' and doc.station_id%1==0 and doc.station_id>0)
  end
  local list=doc.stations
  if type(list)~='table' or #list<1 or #list>2000 then return false end
  local ids={};local count=0
  for k in pairs(list) do
    if type(k)~='number' or k%1~=0 or k<1 or k>#list then return false end
    count=count+1
  end
  if count~=#list then return false end
  for _,s in ipairs(list) do
    if type(s)~='table' or type(s.id)~='number' or s.id%1~=0 or s.id<1 or ids[s.id]
      or type(s.name)~='string' or #s.name==0 or type(s.url)~='string'
      or not s.url:match('^https?://[^%s]+$') or s.url:find('[%c]') then return false end
    ids[s.id]=true
  end
  return true
end
function M.new(fs,json)
  local S={root=M.ROOT,errors={},blocked={},sources={}}
  local function path(kind)
    assert(allowed[kind],'Unknown Radio data file')
    return M.ROOT..'/'..kind..'.json'
  end
  local function fail(kind,message,block)
    S.errors[kind]=message
    if block then S.blocked[kind]=true end
    return nil,message
  end
  local function read_doc(filename,kind)
    if not fs.exists(filename) then return nil,nil,false end
    local ok,raw=pcall(fs.getcontents,filename)
    if not ok or type(raw)~='string' then return nil,'Cannot read '..filename,true end
    local decoded,doc=pcall(json.decode,raw)
    if not decoded or not valid(kind,doc) then return nil,'Invalid Radio data: '..filename,true end
    return doc,nil,true
  end
  local function ensure_directory()
    for _,dir in ipairs({'/sd/data',M.ROOT}) do
      local info=fs.stat(dir)
      if info then
        if not info.is_dir then return nil,'Not a directory: '..dir end
      elseif not fs.mkdir(dir) then return nil,'Cannot create '..dir end
    end
    return true
  end
  function S.save(kind,doc)
    local target=path(kind)
    if S.blocked[kind] then return nil,S.errors[kind] end
    if not valid(kind,doc) then return fail(kind,'Invalid '..kind..' document') end
    local ready,dir_error=ensure_directory()
    if not ready then return fail(kind,dir_error) end
    -- Never overwrite an unreadable/corrupt primary with defaults.
    local current,current_error,present=read_doc(target,kind)
    if present and not current then return fail(kind,current_error,true) end
    local encoded,raw=pcall(json.encode,doc)
    if not encoded then return fail(kind,'Cannot encode '..kind) end
    local tmp,backup=target..'.tmp',target..'.bak'
    if not fs.putcontents(tmp,raw) then return fail(kind,'Cannot write '..tmp) end
    local verified=read_doc(tmp,kind)
    if not verified or fs.getcontents(tmp)~=raw then return fail(kind,'Write verification failed: '..tmp) end
    if present then
      if fs.exists(backup) then
        fs.remove(backup)
        if fs.exists(backup) then return fail(kind,'Cannot rotate '..backup) end
      end
      if not fs.rename(target,backup) then return fail(kind,'Cannot back up '..target) end
    end
    if not fs.rename(tmp,target) then
      if present then fs.rename(backup,target) end
      return fail(kind,'Cannot commit '..target..'; previous data retained')
    end
    S.errors[kind]=nil;S.sources[kind]='data'
    return true
  end
  function S.load(kind)
    local target=path(kind)
    local doc,err,present=read_doc(target,kind)
    if present then
      if doc then S.sources[kind]='data';return doc end
      -- A valid backup may still be played, but don't replace the damaged
      -- primary automatically; it can contain newer user data to recover.
      local backup=read_doc(target..'.bak',kind)
      fail(kind,err..'; saving disabled to protect existing data',true)
      if backup then S.sources[kind]='backup-readonly';return backup,S.errors[kind] end
      return nil,S.errors[kind]
    end
    -- Interrupted rename: prefer the last committed backup over a temp file.
    local any_new_file=false
    for _,suffix in ipairs({'.bak','.tmp'}) do
      local recovered,recovery_error,exists=read_doc(target..suffix,kind)
      any_new_file=any_new_file or exists
      if recovered then
        local ok,write_error=S.save(kind,recovered)
        S.sources[kind]=ok and 'data' or 'recovery-readonly'
        return recovered,write_error
      end
      if exists then err=recovery_error end
    end
    if any_new_file then return fail(kind,err..'; saving disabled to protect existing data',true) end
    -- No new-location data exists: migrate the complete edited catalog,
    -- preserving additions, edits, deletions, order and IDs without merging.
    local legacy=M.LEGACY..'/'..kind..'.json'
    local old,old_error,old_exists=read_doc(legacy,kind)
    if old_exists and not old then return fail(kind,old_error..'; migration stopped',true) end
    if not old then
      old,old_error,old_exists=read_doc(legacy..'.radio.bak',kind)
      if old_exists and not old then return fail(kind,old_error..'; migration stopped',true) end
    end
    if old then
      local ok,write_error=S.save(kind,old)
      S.sources[kind]=ok and 'data' or 'legacy-readonly'
      return old,write_error -- legacy files are deliberately never removed
    end
    S.sources[kind]='defaults'
    return nil
  end
  function S.error()
    local errors={}
    for _,kind in ipairs({'stations','config'}) do if S.errors[kind] then errors[#errors+1]=S.errors[kind] end end
    return table.concat(errors,'; ')
  end
  function S.state()
    return {directory=M.ROOT,stations_path=path('stations'),config_path=path('config'),
      stations_source=S.sources.stations or 'defaults',error=S.error()}
  end
  return S
end
return M
