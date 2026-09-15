local Account=dofile(ROOT..'/package/account.lua')
local Modes=dofile(ROOT..'/package/play_mode.lua')
local a=Account.parse({account={id='98765432109'},profile={nickname='Alice',vipType=11},cookie='never expose'})
assert(a.id=='98765432109'and a.nickname=='Alice'and a.membership=='member'and a.cookie==nil)
assert(Account.parse({profile={userId=1,vipType=0}}).membership=='non_member')
assert(Account.parse({profile={userId=1}}).membership=='unknown')
assert(Account.parse({})==nil)
assert(Modes.step('ordered',1,3,1,true)==2)
assert(Modes.step('ordered',3,3,1,true)==nil)
assert(Modes.step('repeat_one',2,3,1,true)==2)
assert(Modes.step('repeat_one',2,3,1,false)==3)
assert(Modes.step('ordered',1,3,-1,false)==3)
assert(Modes.step('shuffle',1,1,1,true)==1)
assert(Modes.step('shuffle',1,0,1,true)==nil)
for index=1,5 do for value=1,4 do
  local next_index=Modes.step('shuffle',index,5,1,true,function(n)assert(n==4);return value end)
  assert(next_index>=1 and next_index<=5 and next_index~=index)
end end
assert(not Modes.valid('unknown'))
local Effects=dofile(ROOT..'/package/effects.lua')
local defaults=dofile(ROOT..'/package/settings.lua')
assert(Effects.validate(defaults,{play_mode='shuffle'}).play_mode=='shuffle')
assert(not Effects.validate(defaults,{play_mode='bad'}))
-- Logout deletes only the three exact session files, never settings or cover data.
local files={['/sd/data/netease/session.json']='session',['/sd/data/netease/session.bak']='backup',
  ['/sd/data/netease/session.json.tmp']='temp',['/sd/data/netease/settings.json']='settings',
  ['/sd/data/netease/covers/a.ncmc']='cover'}
local block=false
local fs={exists=function(p)return files[p]~=nil end,remove=function(p)if not block then files[p]=nil end end}
local store=dofile(ROOT..'/package/storage.lua').new(fs,{})
block=true;assert(not store.clear_session())
block=false;assert(store.clear_session())
assert(not files['/sd/data/netease/session.json']and not files['/sd/data/netease/session.bak']and not files['/sd/data/netease/session.json.tmp'])
assert(files['/sd/data/netease/settings.json']=='settings'and files['/sd/data/netease/covers/a.ncmc']=='cover')
assert(store.clear_session())
