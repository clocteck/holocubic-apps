-- Temporary diagnostic module. Buffered spans keep UART logging out of startup.
local P={rows={},sent=0,seen={}}
local start=tmr.now()&0xffffffff
function P.now()return ((tmr.now()&0xffffffff)-start)&0xffffffff end
function P.mark(name,begin,detail)
  local finish=P.now()
  P.rows[#P.rows+1]={name=name,start_us=begin or finish,end_us=finish,detail=detail or ''}
end
function P.once(name,detail)if not P.seen[name]then P.seen[name]=true;P.mark(name,nil,detail)end end
function P.flush()
  for i=P.sent+1,#P.rows do
    local r=P.rows[i]
    print(string.format('[RADIO_PROFILE] %s start_ms=%.3f duration_ms=%.3f end_ms=%.3f %s',r.name,r.start_us/1000,(r.end_us-r.start_us)/1000,r.end_us/1000,r.detail))
  end
  P.sent=#P.rows
end
local function wrap(owner,key,name,describe)
  local original=owner[key]
  owner[key]=function(...)
    local started=P.now();local out=table.pack(original(...))
    P.mark(name,started,describe and describe(out,...) or '')
    return table.unpack(out,1,out.n)
  end
end
wrap(file,'getcontents','file.read',function(out,path)return tostring(path)..' bytes='..(type(out[1])=='string' and #out[1] or 0)end)
local J=rawget(_G,'sjson') or rawget(_G,'json')
wrap(J,'decode','json.decode',function(out,raw)return 'bytes='..(type(raw)=='string' and #raw or 0)end)
wrap(_G,'lv_font_load','font.load',function(out,path)return tostring(path)..' ok='..tostring(out[1]~=nil and out[1]~=0)end)
local original_dofile=dofile
_G.dofile=function(path)
  local started=P.now();local result=original_dofile(path);P.mark('lua.dofile',started,tostring(path))
  if path:match('/storage.lua$') then
    local original_new=result.new
    result.new=function(...)
      local s=original_new(...)
      wrap(s,'load','storage.load',function(out,kind)return tostring(kind)..(type(out[1])=='table' and out[1].stations and ' count='..#out[1].stations or '')end)
      return s
    end
  end
  return result
end
wrap(_G,'require','module.require',function(out,path)return tostring(path)end)
P.mark('lua.entry',0)
return P
