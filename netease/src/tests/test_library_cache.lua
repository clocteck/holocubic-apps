local Module=dofile(ROOT..'/package/library_cache.lua')
local Normalize=dofile(ROOT..'/package/library.lua')
local clock,requests=0,{}
local p={generation=0,busy=false}
local function request(kind,ids,done)
  p.generation=p.generation+1;p.busy=true
  requests[#requests+1]={kind=kind,ids=ids,done=done}
end
function p.likes(uid,done)request('likes',nil,done)end
function p.recent(done)request('recent',nil,done)end
function p.daily(done)request('daily',nil,done)end
function p.details(ids,done)assert(#ids<=20);request('details',ids,done)end
local function song(id)return {id=id,name='song '..id,ar={{name='artist'}},al={name='album',picUrl='https://p3.music.126.net/'..id..'.jpg'},extra='discard me'}end
local function reply(doc,err)
  p.busy=false;p.generation=p.generation+1;requests[#requests].done(doc,err)
end
local c=Module.new(p,Normalize,function()return clock end)
c.poll('1',false,1);assert(#requests==0)
local ids={};for i=1,45 do ids[i]=i end
local loaded
c.load(1,'1',function(found,map)loaded=found;assert(map)end)
assert(requests[1].kind=='likes');reply({ids=ids});assert(#loaded==45)
local count=#requests;c.load(1,'1',function(found)assert(found==loaded)end);assert(#requests==count)
for batch=1,3 do
  clock=clock+1000;c.poll('1',true,1)
  local job=requests[#requests];assert(job.kind=='details'and #job.ids==(batch<3 and 20 or 5))
  local rows={};for _,id in ipairs(job.ids)do rows[#rows+1]=song(id)end;reply({songs=rows})
end
assert(c.state()[1].complete and c.state()[1].loaded==45)
assert(c.tabs[1].songs['1'].extra==nil)
clock=clock+1000;c.poll('1',true,1);assert(requests[#requests].kind=='recent')
reply({data={list={{data=song(46)}}}})
clock=clock+1000;c.poll('1',true,1);assert(requests[#requests].kind=='daily')
reply({data={dailySongs={song(47)}}})
assert(c.state()[2].complete and c.state()[3].complete)
count=#requests
for tab=1,3 do c.load(tab,'1',function(found,map)assert(found and map)end)end
c.poll('1',true,1);assert(#requests==count)
c.details(1,{1,2,3},function(doc)assert(doc)end);assert(#requests==count)
c.load(1,'1',function()end,true);assert(#requests==count+1)
local stale=requests[#requests];c.clear();stale.done({ids=ids});assert(not c.state()[1].ready)
-- Interrupted background request is rescheduled, but cannot overwrite a newer account cache.
p.busy=false;clock=clock+1000;c.poll('2',true,1)
p.generation=p.generation+1;p.busy=false;c.poll('2',true,1)
clock=clock+1000;c.poll('2',true,1);reply({ids={9}})
clock=clock+1000;c.poll('2',true,1);reply({songs={}})
assert(c.state()[1].complete) -- Deleted/unavailable song doesn't loop forever.
