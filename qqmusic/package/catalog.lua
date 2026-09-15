-- Bounded, paginated metadata prefetch. Audio and foreground requests win.
local M={MAX_SONGS=1000,TTL=6*3600}
function M.new(provider,now,storage,epoch)
  local C={entries={},order={},next_at=0,save_queue={},disk_hits=0,disk_writes=0}
  function C.reset(logged)
    C.entries={};C.order=logged and {'favorites','top26','top27'}or {'top26','top27'}
    C.inflight=nil;C.next_at=now()+2000
    for _,id in ipairs(C.order)do C.entries[id]={pages={},loaded=0,total=nil,next_offset=0,failures=0,checked={},stale={}}end
  end
  function C.put(id,offset,doc,from_disk)
    local e=C.entries[id];if not e or type(doc.songs)~='table'then return end
    if e.pages[offset]==doc then return end
    e.loaded=e.loaded+#doc.songs-(e.pages[offset]and #e.pages[offset].songs or 0)
    e.pages[offset]=doc;e.total=doc.total;e.failures=0
    if not from_disk then
      e.stale[offset]=nil
      if storage and id~='favorites'and offset<M.MAX_SONGS then
        C.save_queue[#C.save_queue+1]={name='catalog_'..id..'_'..offset,doc={version=1,created=epoch and epoch()or 0,data=doc}}
      end
    end
    while e.pages[e.next_offset]do
      local d=e.pages[e.next_offset];if #d.songs==0 then e.done=true;break end
      e.next_offset=e.next_offset+20
    end
    e.done=e.done or (e.total~=nil and e.next_offset>=e.total)or e.next_offset>=M.MAX_SONGS
    e.limited=e.total~=nil and e.total>M.MAX_SONGS
  end
  function C.get(id,offset)
    local e=C.entries[id];if not e then return end
    if not e.pages[offset]and storage and id~='favorites'and offset<M.MAX_SONGS and not e.checked[offset]then
      e.checked[offset]=true;local cached=storage.load('catalog_'..id..'_'..offset)
      if cached and cached.version==1 and type(cached.data)=='table'and type(cached.data.songs)=='table'and
        #cached.data.songs<=20 and type(cached.data.total)=='number'then
        local valid=true
        for _,s in ipairs(cached.data.songs)do if type(s)~='table'or type(s.id)~='string'or type(s.mid)~='string'then valid=false;break end end
        if valid then
          C.put(id,offset,cached.data,true);C.disk_hits=C.disk_hits+1
          local stamp=epoch and epoch()or 0
          if stamp<1700000000 or type(cached.created)~='number'or cached.created>stamp or stamp-cached.created>M.TTL then e.stale[offset]=true end
        end
      end
    end
    return e.pages[offset]
  end
  function C.all(id)
    local e=C.entries[id];local songs={};if not e then return songs end
    for offset=0,M.MAX_SONGS-20,20 do local page=e.pages[offset];if not page then break end
      for _,s in ipairs(page.songs)do songs[#songs+1]=s end
    end;return songs
  end
  function C.poll()
    if C.inflight then if not provider.busy then C.inflight=nil end;return end
    if now()<C.next_at then return end
    if #C.save_queue>0 then
      local item=table.remove(C.save_queue,1);local ok=storage.save(item.name,item.doc)
      if ok then C.disk_writes=C.disk_writes+1 end;C.next_at=now()+150;return
    end
    for _,id in ipairs(C.order)do local e=C.entries[id]
      local stale=next(e.stale)
      if (not e.done or stale)and e.failures<3 and now()>=(e.retry_at or 0)then
        local offset=stale or e.next_offset
        if not stale and C.get(id,offset)then C.next_at=now()+150;return end
        C.inflight=id;C.next_at=now()+1800
        local function done(d)
          C.inflight=nil;if C.entries[id]~=e then return end
          if d then C.put(id,offset,d)else e.failures=e.failures+1;e.retry_at=now()+30000 end
        end
        if id=='favorites'then provider.favorites(offset,done)else provider.top(tonumber(id:sub(4)),offset,done)end
        return
      end
    end
  end
  function C.state()
    local out={};for _,id in ipairs(C.order)do local e=C.entries[id]
      out[id]={loaded=e.loaded,total=e.total or 0,done=not not e.done,limited=not not e.limited,failures=e.failures}
    end;out.disk={hits=C.disk_hits,writes=C.disk_writes};return out
  end
  return C
end
return M
