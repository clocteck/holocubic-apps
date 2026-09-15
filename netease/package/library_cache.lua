-- Login-scoped compact library cache; background work yields to playback/foreground requests.
local M={}
local function compact(song)
  if type(song)~='table'or not song.id then return nil end
  local album=type(song.al)=='table'and song.al or type(song.album)=='table'and song.album or {}
  local artists={}
  local source=type(song.ar)=='table'and song.ar or type(song.artists)=='table'and song.artists or {}
  for _,a in ipairs(source)do if type(a)=='table'then artists[#artists+1]={name=a.name or ''}end end
  return {id=song.id,name=song.name or ('歌曲 '..tostring(song.id)),dt=song.dt or song.duration or 0,
    ar=artists,al={name=album.name or '',picUrl=album.picUrl or album.coverImgUrl or song.picUrl},
    _ncm_details=song._ncm_details or (song.name~=nil and #artists>0 and album.picUrl~=nil)}
end
function M.new(provider,normalize,now)
  local C={tabs={},epoch=0,active=nil,next_at=0}
  local function entry(tab)
    if not C.tabs[tab]then C.tabs[tab]={ids={},songs={},ready=false,attempts=0,retry_at=0,failed_details={}}end
    return C.tabs[tab]
  end
  function C.clear()C.epoch=C.epoch+1;C.tabs={};C.active=nil;C.next_at=0 end
  local function receive(e,songs,details)
    local result={}
    for _,song in ipairs(songs or {})do
      local s=compact(song)
      if s then if details then s._ncm_details=true end;e.songs[tostring(s.id)]=s;result[#result+1]=s end
    end
    return result
  end
  local function request(tab,fn,done)
    local job={epoch=C.epoch};C.active=job
    fn(function(...)
      if job.epoch~=C.epoch or C.active~=job then return end
      C.active=nil;C.next_at=now()+500;done(...)
    end)
    job.generation=provider.generation
  end
  function C.load(tab,uid,done,force)
    local e=entry(tab)
    if e.ready and not force then done(e.ids,e.songs);return end
    e.attempts=e.attempts+1
    request(tab,function(cb)
      if tab==1 then provider.likes(uid,cb)elseif tab==2 then provider.recent(cb)else provider.daily(cb)end
    end,function(doc,err)
      local ids,songs
      if doc and not err then
        if tab==1 then ids,songs=normalize.likes(doc)
        elseif tab==2 then ids,songs=normalize.recent(doc)
        else ids,songs=normalize.daily(doc)end
      end
      if not ids then e.retry_at=now()+3000;done(nil,nil,err or '榜单响应不可用');return end
      e.ids=ids;e.songs={};e.failed_details={};receive(e,songs,false);e.ready=true;e.attempts=0
      done(e.ids,e.songs)
    end)
  end
  function C.details(tab,ids,done)
    local e=entry(tab);local missing={}
    for _,id in ipairs(ids)do if not(e.songs[tostring(id)]or {})._ncm_details then missing[#missing+1]=id end end
    if #missing==0 then done({songs={}});return end
    request(tab,function(cb)provider.details(missing,cb)end,function(doc,err)
      if not doc or type(doc.songs)~='table'then
        for _,id in ipairs(missing)do local key=tostring(id);e.failed_details[key]=(e.failed_details[key]or 0)+1 end
        C.next_at=now()+3000;done(nil,err or '歌曲信息不可用');return
      end
      local songs=receive(e,doc.songs,true)
      -- Unavailable/deleted tracks must not cause an endless background loop.
      for _,id in ipairs(missing)do
        local key=tostring(id)
        if not e.songs[key]then e.songs[key]={id=id,name='歌曲 '..key,ar={},al={},_ncm_details=true}end
        e.songs[key]._ncm_details=true
      end
      done({songs=songs})
    end)
  end
  function C.poll(uid,allow,preferred)
    if C.active and C.active.generation~=provider.generation then C.active=nil;C.next_at=now()+500 end
    if not uid or not allow or C.active or provider.busy or now()<C.next_at then return end
    local order={preferred or 1};for tab=1,3 do if tab~=order[1]then order[#order+1]=tab end end
    for _,tab in ipairs(order)do
      local e=entry(tab)
      if not e.ready and e.attempts<3 and now()>=e.retry_at then C.load(tab,uid,function()end);return end
      if e.ready then
        local missing={}
        for _,id in ipairs(e.ids)do local key=tostring(id)
          if not(e.songs[key]or {})._ncm_details and (e.failed_details[key]or 0)<3 then
            missing[#missing+1]=id;if #missing==20 then break end
          end
        end
        if #missing>0 then C.details(tab,missing,function()end);return end
      end
    end
  end
  function C.cover(tab)
    local e=entry(tab);local song=e.ids[1]and e.songs[tostring(e.ids[1])]
    return song and song.al and song.al.picUrl
  end
  function C.state()
    local out={}
    for tab=1,3 do local e=entry(tab);local loaded=0
      for _,id in ipairs(e.ids)do if(e.songs[tostring(id)]or {})._ncm_details then loaded=loaded+1 end end
      out[tab]={ready=e.ready,total=#e.ids,loaded=loaded,complete=e.ready and loaded==#e.ids}
    end
    return out
  end
  return C
end
return M
