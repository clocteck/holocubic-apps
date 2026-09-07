-- On-demand directories: pages on SD, bounded searches, no complete directory in RAM.
local Catalog = {}
local JSON = rawget(_G, "sjson") or rawget(_G, "json")
local GROUPS = {"ashare", "nasdaq", "taiwan", "hongkong", "fx"}
local FILTERS = {
  ashare = "m:0+t:6+f:!2,m:0+t:80+f:!2,m:1+t:2+f:!2,m:1+t:23+f:!2,m:0+t:81+s:2048+f:!2",
  nasdaq = "m:105,m:106,m:107", taiwan = "m:178",
  hongkong = "m:116+t:3+f:!2,m:116+t:4+f:!2,m:116+t:1+f:!2",
}
local function ms() return millis and millis() or math.floor(tmr.now()/1000) end
local function epoch() local ok, v = pcall(function() return time.get() end); return ok and tonumber(v) or 0 end
local function encode(s) return tostring(s):gsub("([^%w%-%_%.%~])", function(c) return string.format("%%%02X", c:byte()) end) end
local function decode(raw)
  if type(raw) ~= "string" then return nil end
  local ok, value = pcall(JSON.decode, raw)
  return ok and type(value) == "table" and value or nil
end
local function clean(s, max) s=tostring(s or ""):gsub("[%c]", " "); if #s > max then return nil end; return s end
function Catalog.new(opts)
  local self = {dir=opts.dir, store=opts.store, manifests={}, errors={}, queue={}, job=nil, busy=false, seq=0, stopped=false, next_at=0}
  local function manifest_path(g) return self.dir .. "/" .. g .. ".json" end
  local function page_path(g, slot, page) return self.dir .. "/" .. g .. "_" .. slot .. "_" .. tostring(page) .. ".json" end
  local function valid_manifest(v)
    return (v.slot=="a" or v.slot=="b") and type(v.pages)=="number" and v.pages>0 and v.pages<=1000
      and type(v.count)=="number" and v.count>0 and type(v.generation)=="string"
  end
  for _, g in ipairs(GROUPS) do self.manifests[g]=self.store.read(manifest_path(g), valid_manifest) end
  function self:status()
    local groups={}
    for _, g in ipairs(GROUPS) do
      local m=self.manifests[g] or {}
      groups[#groups+1]={group=g,count=m.count or 0,bytes=m.bytes or 0,updated=m.updated or 0,generation=m.generation or "",error=self.errors[g] or "",outdated=g=="ashare" and m.count~=nil and m.filter~=FILTERS[g]}
    end
    local j=self.job
    return {groups=groups,running=j~=nil or #self.queue>0,group=j and j.group or "",downloaded=j and j.count or 0,total=j and j.total or 0,queued=#self.queue,error=self.error or ""}
  end
  function self:start(group)
    if self.job or #self.queue>0 then return false,"Directory update already running" end
    if group~="all" and group~="fx" and not FILTERS[group] then return false,"Unsupported directory" end
    local ok=pcall(function() if not file.exists(self.dir) and not file.mkdir(self.dir) then error("SD directory unavailable") end end)
    if not ok then return false,"SD directory unavailable" end
    self.stopped=false; self.error=""; self.next_at=0
    for _,g in ipairs(GROUPS) do if group=="all" or group==g then self.queue[#self.queue+1]=g; self.errors[g]="" end end
    return true
  end
  function self:cancel()
    self.seq=self.seq+1; self.queue={}; self.job=nil; self.busy=false; self.error="Cancelled"; self.stopped=true
  end
  local function fail(message)
    local j=self.job
    if j then self.errors[j.group]=message end
    self.error=message; self.job=nil; self.busy=false; self.next_at=ms()+1000
  end
  local function retry(message)
    local j=self.job
    j.attempt=j.attempt+1
    if j.attempt>=3 then fail(message); return end
    self.next_at=ms()+j.attempt*2500
  end
  local function complete()
    local j=self.job
    local value={slot=j.slot,pages=j.page-1,count=j.count,bytes=j.bytes,updated=epoch(),generation=j.generation,filter=FILTERS[j.group]}
    local ok,err=self.store.write(manifest_path(j.group),value)
    if not ok then fail(err);return end
    self.manifests[j.group]=value; self.errors[j.group]=""; self.job=nil
  end
  local function write_page(rows)
    local j=self.job
    local raw=JSON.encode(rows)
    local p=page_path(j.group,j.slot,j.page)
    if not file.putcontents(p,raw) or file.getcontents(p)~=raw then error("SD directory page write failed") end
    j.bytes=j.bytes+#raw; j.count=j.count+#rows; j.page=j.page+1; j.attempt=0
  end
  function self:tick(network_busy)
    if self.stopped then return end
    if self.busy then
      if ms()-self.started_at>25000 then self.seq=self.seq+1;self.busy=false;retry("Directory request timed out") end
      return
    end
    if network_busy or ms()<self.next_at then return end
    if not self.job and #self.queue>0 then
      local g=table.remove(self.queue,1); local old=self.manifests[g]
      self.job={group=g,slot=old and old.slot=="a" and "b" or "a",generation=tostring(epoch()).."-"..tostring(ms()),page=1,count=0,bytes=0,attempt=0}
    end
    local j=self.job
    if not j then return end
    local url
    if j.group=="fx" then url="https://api.frankfurter.dev/v2/currencies"
    else
      local host=j.attempt==1 and "push2.eastmoney.com" or "push2delay.eastmoney.com"
      url="https://"..host.."/api/qt/clist/get?pn="..j.page.."&pz=100&po=0&np=1&fltt=2&invt=2&fid=f12&fs="..encode(FILTERS[j.group]).."&fields=f12,f13,f14"
    end
    self.seq=self.seq+1;local seq=self.seq;self.busy=true;self.started_at=ms()
    local started,err=pcall(function()
      http.get(url,{timeout=20000,headers={Accept="application/json",["Accept-Encoding"]="identity",["User-Agent"]="Mozilla/5.0"}},function(code,body)
        if self.stopped or seq~=self.seq or self.job~=j then return end
        self.busy=false;self.next_at=ms()+350
        if code~=200 then retry("Directory HTTP "..tostring(code));return end
        local doc=decode(body)
        if not doc then retry("Invalid directory JSON");return end
        local success,message=pcall(function()
          local rows={}
          if j.group=="fx" then
            for _,v in ipairs(doc) do
              local c=type(v)=="table" and v.iso_code
              if type(c)=="string" and c:match("^%u%u%u$") then rows[#rows+1]={c,clean(v.name,180) or c} end
            end
            if #rows<10 or #rows>300 then error("Invalid currency directory") end
            table.sort(rows,function(a,b)return a[1]<b[1] end)
            j.total=#rows;write_page(rows);complete();return
          end
          local d=doc.data
          if doc.rc~=0 or type(d)~="table" or type(d.diff)~="table" then error("Invalid stock directory") end
          local total=tonumber(d.total)
          if not total or total<1 or total>100000 then error("Invalid stock count") end
          if j.total and total~=j.total then error("Directory changed during download; retry update") end
          j.total=total
          -- Reject truncated, repeated or unexpected pages before publishing a generation.
          if #d.diff<1 or #d.diff>100 then error("Empty or oversized stock page") end
          local signature=tostring(d.diff[1].f13)..":"..tostring(d.diff[1].f12)
          if signature==j.last_signature then error("Stock server repeated a page") end
          for _,v in ipairs(d.diff) do
            local symbol=clean(v.f12,32);local name=clean(v.f14,180);local market=tonumber(v.f13)
            if not symbol or symbol=="" or not name or not market then error("Invalid stock record") end
            if (j.group=="ashare" and market~=0 and market~=1) or (j.group=="nasdaq" and market~=105 and market~=106 and market~=107) or (j.group=="taiwan" and market~=178) or (j.group=="hongkong" and market~=116) then error("Unexpected stock market") end
            rows[#rows+1]={symbol,name,market}
          end
          if j.count+#rows>total then error("Stock page exceeds total") end
          write_page(rows);j.last_signature=signature
          if j.count==total then complete() elseif #rows<100 then error("Incomplete stock directory") end
        end)
        if not success then fail(tostring(message)) end
      end)
    end)
    if not started then self.busy=false;retry(tostring(err)) end
  end
  function self:search(group,query,cursor,generation)
    if group~="fx" and not FILTERS[group] then return {ok=false,error="Unsupported directory"} end
    local m=self.manifests[group]
    if not m then return {ok=true,items={},next_cursor=0,available=false} end
    if group=="ashare" and m.filter~=FILTERS[group] then return {ok=true,items={},next_cursor=0,available=false,outdated=true} end
    if generation and generation~="" and generation~=m.generation then return {ok=false,error="Directory updated; search again",changed=true} end
    query=tostring(query or ""):lower():sub(1,96)
    local start=math.max(0,math.floor(tonumber(cursor) or 0))
    local page=math.floor(start/100)+1; local row=start%100+1
    if group=="fx" then page=1;row=start+1 end
    local results={};local scanned=0
    while page<=m.pages and scanned<8 do
      local rows=decode(file.getcontents(page_path(group,m.slot,page)))
      if not rows then return {ok=false,error="SD directory damaged; download again"} end
      while row<=#rows do
        local v=rows[row];local matches=true
        local hay=(v[1].." "..v[2]):lower()
        for word in query:gmatch("%S+") do if not hay:find(word,1,true) then matches=false;break end end
        if matches then results[#results+1]={symbol=v[1],text=v[2],market=v[3],group=group} end
        row=row+1
        if #results>=30 then
          local next_cursor=group=="fx" and row-1 or (page-1)*100+row-1
          if row>#rows and page>=m.pages then next_cursor=0 end
          return {ok=true,items=results,next_cursor=next_cursor,available=true,generation=m.generation,total=m.count}
        end
      end
      page=page+1;row=1;scanned=scanned+1
    end
    return {ok=true,items=results,next_cursor=page<=m.pages and (page-1)*100 or 0,available=true,generation=m.generation,total=m.count}
  end
  function self:currencies()
    local m=self.manifests.fx
    return m and decode(file.getcontents(page_path("fx",m.slot,1))) or {}
  end
  return self
end
return Catalog
