-- Account-scoped, RAM-only signed-URL cache. Never downloads audio or exposes URLs in state().
local M={MAX_ENTRIES=3,MAX_ATTEMPTS=2}
function M.new(provider,now,fetch)
  local R={busy=false,foreground=false,generation=0,cache={},order={},failed={},hits=0,requests=0}
  local active
  function R.cancel()
    R.generation=R.generation+1;active=nil;R.busy=false;R.foreground=false;provider.cancel()
  end
  function R.clear()R.cancel();R.cache={};R.order={};R.failed={}end
  local function key(song)return tostring(song.id or song.mid or '')end
  local function touch(id)
    for i=#R.order,1,-1 do if R.order[i]==id then table.remove(R.order,i)end end
    R.order[#R.order+1]=id
    while #R.order>M.MAX_ENTRIES do local old=table.remove(R.order,1);R.cache[old]=nil;R.failed[old]=nil end
  end
  local function cached(song)
    local id=key(song);local entry=R.cache[id]
    if entry and now()<entry.expires then touch(id);return entry.item end
    R.cache[id]=nil
  end
  function R.invalidate(song)R.cache[key(song)]=nil end
  local function attempt()
    local job=active;if not job then return end
    job.retry_at=nil;job.attempts=job.attempts+1;R.requests=R.requests+1
    fetch(job.song,function(item,err)
      if active~=job or job.generation~=R.generation then return end
      if not item and provider.diagnostics.retryable and job.attempts<(job.prefetch and 1 or M.MAX_ATTEMPTS)then
        job.retry_at=now()+500;return
      end
      local metrics={cache_hit=false,attempts=job.attempts,total_ms=now()-job.at,
        queue_ms=provider.diagnostics.queue_ms or 0,headers_ms=provider.diagnostics.headers_ms or 0,
        first_byte_ms=provider.diagnostics.first_byte_ms or 0,prefetch=job.prefetch,error=not not err}
      if job.prefetch then R.prefetch_metrics=metrics else R.metrics=metrics end
      local id=key(job.song)
      if item then
        local urls={}
        for _,url in ipairs(item.urls or {item.url})do
          if type(url)=='string'and url:match('^https?://')and #urls<3 then urls[#urls+1]=url end
        end
        if #urls==0 then urls={item.url}end
        local compact={url=item.url,urls=urls}
        local ttl=math.max(0,math.min(120,tonumber(item.expi)or 60)-5)*1000
        R.cache[id]={item=compact,expires=now()+ttl};touch(id);R.failed[id]=ttl==0 and now()+15000 or nil;item=compact
      else
        -- Bounded cooldown uses the same three-entry LRU as successful results.
        touch(id);R.failed[id]=now()+15000
      end
      active=nil;R.busy=false;R.foreground=false
      if job.done then job.done(item,err)end
    end)
  end
  function R.get(song,done,force)
    R.cancel()
    if force then R.invalidate(song)end
    local hit=not force and cached(song)
    if hit then R.hits=R.hits+1;R.metrics={cache_hit=true,attempts=0,total_ms=0};done(hit);return end
    R.busy=true;R.foreground=true
    active={song=song,done=done,generation=R.generation,at=now(),attempts=0}
    attempt()
  end
  function R.prefetch(song)
    if not song or R.busy or cached(song)or now()<(R.failed[key(song)]or 0)then return end
    R.generation=R.generation+1;R.busy=true;R.foreground=false
    active={song=song,prefetch=true,generation=R.generation,at=now(),attempts=0}
    attempt()
  end
  function R.poll()
    provider.poll()
    if active and active.retry_at and now()>=active.retry_at then attempt()end
  end
  function R.state()
    local count=0;for _,entry in pairs(R.cache)do if now()<entry.expires then count=count+1 end end
    return {busy=R.busy,foreground=R.foreground,entries=count,hits=R.hits,requests=R.requests,last=R.metrics,prefetch=R.prefetch_metrics}
  end
  return R
end
return M
