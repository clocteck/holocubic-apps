local Covers=dofile(ROOT..'/package/covers.lua')
local Disk=dofile(ROOT..'/package/cover_disk.lua')
local w,h,format=Covers.image_size(PNG_SAMPLE)
assert(w==92 and h==92 and format=='png')
assert(Covers.image_size(PNG_MAX)==136 and #PNG_MAX==98304)
assert(not Covers.image_size(PNG_OVER))
assert(not Covers.image_size(PNG_SAMPLE:sub(1,-2)))
assert(not Covers.image_size(PNG_SAMPLE..'x'))
local files,dirs={},{}
local fs={}
function fs.exists(p)return files[p]~=nil or dirs[p]end
function fs.mkdir(p)dirs[p]=true end
function fs.stat(p)
  if dirs[p]then return {is_dir=true,size=0}end
  if files[p]then return {is_dir=false,size=#files[p]}end
end
function fs.listdir(p)
  local result={}
  for name,data in pairs(files)do result[#result+1]={name=name:sub(#p+2),size=#data,is_dir=false}end
  return result
end
function fs.getcontents(p)return files[p]end
function fs.putcontents(p,data)files[p]=data;return true end
function fs.remove(p)files[p]=nil end
function fs.rename(a,b)files[b]=files[a];files[a]=nil;return true end
local function disk()return Disk.new(fs,Covers.image_size,nil,Covers.identity)end
local d=disk();local url='https://p4.music.126.net/disguised.jpg?param=92y92'
local clock,requests=0,{}
local net={}
function net.create(u,opts)
  local c={cb={}}
  function c:on(k,f)self.cb[k]=f end
  function c:request()requests[#requests+1]=self end
  function c:close()self.finished=true end
  return c
end
local cache=Covers.new(net,{busy=false},{status='idle'},function()return clock end,d)
cache.want({url});clock=300;cache.poll()
local c=requests[1]
c.cb.headers(200,{['content-length']=tostring(#PNG_SAMPLE),['content-type']='image/jpg'})
c.cb.data(200,PNG_SAMPLE);c.cb.complete();c.finished=true
cache.poll();cache.poll()
assert(cache.get(url)==PNG_SAMPLE and cache.state(url).format=='png')
assert(d.state().writes==1 and d.state().files==1 and cache.state(url).max_bytes==98304)
cache.close()
local restarted=disk()
local alternate=url:gsub('p4.music','p3.music')
local data,info=restarted.get(alternate)
assert(data==PNG_SAMPLE and info.format=='png'and info.source=='sd')
local offline=Covers.new({create=function()error('cached PNG must not use HTTP')end},
  {busy=false},{status='idle'},function()return clock end,restarted)
offline.want({alternate});clock=600;offline.poll()
assert(offline.get(alternate)==PNG_SAMPLE and offline.requests==0)
offline.close()
assert(restarted.put('https://p3.music.126.net/max.jpg',PNG_MAX))
assert(not restarted.put('https://p3.music.126.net/over.jpg',PNG_OVER))
cache=Covers.new(net,{busy=false},{status='idle'},function()return clock end)
cache.want({url});clock=900;cache.poll();c=requests[#requests]
c.cb.headers(200,{['content-length']='98305'})
assert(cache.state(url).last_error=='too_large')
cache.close()
