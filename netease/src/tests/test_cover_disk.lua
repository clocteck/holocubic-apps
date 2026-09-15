local Disk=dofile(ROOT..'/package/cover_disk.lua')
local Covers=dofile(ROOT..'/package/covers.lua')
local raw=string.char(255,216,255,192,0,11,8,0,136,0,136,1,1,17,0,255,217)
local root=Disk.ROOT
local files={['/sd/data/netease/session.json']='secret-session',['/sd/data/netease/settings.json']='saved-settings'}
local dirs={};local removed={};local fail_write,fail_rename=false,false
local fs={}
function fs.exists(path)return files[path]~=nil or dirs[path]end
function fs.mkdir(path)dirs[path]=true;return true end
function fs.stat(path)
  if dirs[path]then return {is_dir=true,size=0}end
  if files[path]then return {is_dir=false,size=#files[path]}end
end
function fs.listdir(path)
  assert(path==root);local list={}
  for name,data in pairs(files)do
    if name:sub(1,#root+1)==root..'/'then list[#list+1]={name=name:sub(#root+2),size=#data,is_dir=false}end
  end
  table.sort(list,function(a,b)return a.name>b.name end);return list
end
local function scoped(path)assert(path:sub(1,#root+1)==root..'/'and not path:find('%.%.'),path)end
function fs.getcontents(path)scoped(path);return files[path]end
function fs.putcontents(path,data)
  scoped(path)
  files[path]=fail_write and data:sub(1,3)or data
  if not fail_write then return true end
end
function fs.remove(path)scoped(path);files[path]=nil;removed[#removed+1]=path end
function fs.rename(a,b)
  scoped(a);scoped(b)
  if fail_rename then return nil end
  files[b]=files[a];files[a]=nil;return true
end
local u1=Covers.thumbnail('https://p3.music.126.net/1.jpg')
local u2=Covers.thumbnail('https://p3.music.126.net/2.jpg')
local u3=Covers.thumbnail('https://p3.music.126.net/3.jpg')
local size=#('NCM-COVER-1\n'..u1..'\n'..raw)
local d=Disk.new(fs,Covers.jpeg_size,size*2)
assert(d.put(u1,raw));assert(d.put(u2,raw));assert(d.state().files==2)
local oldest=d.order[1].name
assert(d.get(u1)==raw);assert(d.put(u1,raw))
assert(d.order[1].name==oldest) -- Reads/repeated puts do not turn FIFO into LRU.
assert(d.put(u3,raw));assert(not files[root..'/'..oldest])
assert(d.get(u1)==nil and d.get(u2)==raw and d.get(u3)==raw)
assert(d.state().bytes<=size*2 and d.state().evicted==1)
local restarted=Disk.new(fs,Covers.jpeg_size,size*2)
assert(restarted.get(u2)==raw and restarted.state().hits==1)
assert(restarted.order[1].seq<restarted.order[2].seq)
-- Corrupt/missing cached image falls back to a miss, never an unrelated file.
files[root..'/'..restarted.order[1].name]='bad'
assert(restarted.get(u2)==nil)
assert(files['/sd/data/netease/session.json']=='secret-session')
assert(files['/sd/data/netease/settings.json']=='saved-settings')
fail_write=true;assert(not restarted.put(u1,raw));fail_write=false
assert(restarted.put(u1,raw))
fail_rename=true;assert(not restarted.put(u2,raw));fail_rename=false
assert(restarted.put(u2,raw))
local orphan='0000000123-'..Disk.key(u3)..'.ncmc.tmp'
files[root..'/'..orphan]='partial'
local recovered=Disk.new(fs,Covers.jpeg_size,size*2)
recovered.get(u2);assert(files[root..'/'..orphan]==nil)
assert(recovered.state().bytes<=size*2)
-- Read from SD before constructing any HTTP request, including after restart.
assert(recovered.put(u3,raw))
local net={create=function()error('SD cache hit must not start HTTP')end}
local clock=0
local c=Covers.new(net,{busy=false},{status='idle'},function()return clock end,Disk.new(fs,Covers.jpeg_size,size*2))
c.want({u3});clock=300;c.poll()
assert(c.get(u3)==raw and c.state(u3).source=='sd'and c.requests==0)
c.close()
assert(Disk.LIMIT==10*1024*1024)
-- Full-file URL validation protects against a filename key collision.
local keyfn=Disk.key;Disk.key=function()return '0000000000000000'end
local collision=Disk.new(fs,Covers.jpeg_size,size*2)
assert(collision.put(u1,raw));assert(collision.get(u2)==nil)
Disk.key=keyfn
-- Upgrade a p4-only legacy cache without renaming, rewriting, or refreshing age.
local p3=Covers.thumbnail('https://p3.music.126.net/legacy.jpg')
local p4=Covers.thumbnail('https://p4.music.126.net/legacy.jpg')
local budget=2*#('NCM-COVER-1\n'..p4..'\n'..raw)
files={};dirs={};removed={}
local legacy=Disk.new(fs,Covers.jpeg_size,budget)
assert(legacy.put(p4,raw))
local legacy_name=legacy.order[1].name
local legacy_blob=files[root..'/'..legacy_name]
local upgraded=Disk.new(fs,Covers.jpeg_size,budget,Covers.identity)
assert(upgraded.get(p3)==raw)
assert(upgraded.put(p3,raw)and upgraded.put(p4,raw))
assert(upgraded.state().files==1 and upgraded.state().writes==0)
assert(upgraded.order[1].name==legacy_name and files[root..'/'..legacy_name]==legacy_blob)
local rebooted=Disk.new(fs,Covers.jpeg_size,budget,Covers.identity)
assert(rebooted.get(p3)==raw and rebooted.get(p4)==raw)
-- The integrated loader must never construct HTTP even for the other CDN host.
clock=0
c=Covers.new(net,{busy=false},{status='idle'},function()return clock end,rebooted)
c.want({p3,p4});clock=300;c.poll()
assert(c.get(p3)==raw and c.get(p4)==raw and #c.order==1 and c.requests==0)
c.want({p4});clock=600;c.poll();assert(c.requests==0)
c.close()
assert(rebooted.put(u2,raw));assert(rebooted.get(p3)==raw)
assert(rebooted.put(u3,raw))
assert(not files[root..'/'..legacy_name]and rebooted.state().evicted==1)
-- New p4 downloads use a p3 identity filename, but retain the original URL header.
files={};dirs={}
local fresh=Disk.new(fs,Covers.jpeg_size,budget,Covers.identity)
assert(fresh.put(p4,raw));assert(fresh.order[1].key==Disk.key(p3))
assert(files[root..'/'..fresh.order[1].name]:sub(1,#('NCM-COVER-1\n'..p4..'\n'))=='NCM-COVER-1\n'..p4..'\n')
assert(fresh.get(p3)==raw and fresh.get(p4)==raw)
local bytes_before=fresh.state().bytes
assert(fresh.put(p3,raw)and fresh.state().bytes==bytes_before and fresh.state().writes==1)
-- Two old aliases remain untouched; use the oldest valid file, not the newer alias.
files={};dirs={}
legacy=Disk.new(fs,Covers.jpeg_size,budget+1)
assert(legacy.put(p4,raw))
local older=legacy.order[1].name
local different=raw:sub(1,-3)..'x'..raw:sub(-2)
assert(legacy.put(p3,different))
upgraded=Disk.new(fs,Covers.jpeg_size,budget+1,Covers.identity)
assert(upgraded.get(p3)==raw and upgraded.get(p4)==raw)
assert(upgraded.state().writes==0 and files[root..'/'..older])
-- Corrupt the oldest file: recover from the valid second alias, without HTTP.
files[root..'/'..older]='bad'
assert(upgraded.get(p4)==different and upgraded.state().files==1)
-- Identity comparisons preserve sizes/paths and never merge unverified hosts.
assert(Covers.identity(p3)==Covers.identity(p4))
for _,other in ipairs({p3:gsub('/legacy.jpg','/other.jpg'),p3:gsub('92y92','136y136'),
  p3:gsub('p3.music','p5.music'),(p3:gsub('p3.music.126.net','p3.music.126.net.evil.test'))})do
  assert(Covers.identity(other)~=Covers.identity(p3))
end
