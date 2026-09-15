local E=dofile(ROOT..'/package/effects.lua')
local defaults=dofile(ROOT..'/package/settings.lua')
assert(E.validate(defaults,{eq_db={0,0,0,0,0}}))
assert(not E.validate(defaults,{eq_db={7,0,0,0,0}}))
assert(not E.validate(defaults,{volume='100'}))
assert(not E.validate(defaults,{vbass_mix=1}))
assert(not E.validate(defaults,{vbass_low_hpf=200,vbass_low_lpf=100}))
local c=assert(E.validate(defaults,{volume=35,eq_db={1,2,3,4,5}}))
assert(defaults.volume==25 and c.volume==35)
local args
local audio={effects=function(...)args={...};return true end,volume=function(v)assert(v==35)end}
assert(E.apply(audio,c));assert(args[1]==10 and args[5]==50)
