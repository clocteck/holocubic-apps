local U = {}
function U.now() return time and time.get and select(1,time.get()) or 0 end
function U.ms() return millis and millis() or math.floor(tmr.now()/1000) end
function U.decode(s) local ok,v=pcall(sjson.decode,s or "");return ok and type(v)=="table" and v or nil end
function U.read(p) local ok,s=pcall(file.getcontents,p);return ok and U.decode(s) or nil end
function U.save(p,v)
 local ok,s=pcall(sjson.encode,v);if not ok then return false end
 local function matches(path)local ok,value=pcall(file.getcontents,path);return ok and value==s end
 local temp=p..".tmp";local wrote=pcall(file.putcontents,temp,s)
 if not wrote or not matches(temp) then return false end
 pcall(file.rename,temp,p)
 if matches(p)then return true end
 local copied=pcall(file.putcontents,p,s)
 local saved=copied and matches(p);if saved then pcall(file.remove,temp)end;return saved
end
function U.encode(s) return (tostring(s or ""):gsub("[^%w%-._~]",function(c)return string.format("%%%02X",c:byte())end)) end
function U.unescape(s) return (tostring(s or ""):gsub("+"," "):gsub("%%(%x%x)",function(h)return string.char(tonumber(h,16))end)) end
function U.query(s) local t={};for k,v in tostring(s or ""):gmatch("([^&=?]+)=([^&]*)") do t[U.unescape(k)]=U.unescape(v) end;return t end
function U.str(s,n)
 s=tostring(s or ""):gsub("[\r\n\t]"," ");local out={};local count=0
 for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do count=count+1;if count>n then return table.concat(out).."…" end;out[#out+1]=ch end
 return table.concat(out)
end
function U.number(v) if type(v)=="number" then return v end;return tonumber(v) end
function U.fmt(v)
 v=tonumber(v);if not v then return "--" end
 local s=tostring(math.floor(math.abs(v)));local r=s:reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")
 return (v<0 and "-" or "")..r
end
function U.short(v) v=tonumber(v);if not v then return "--" end;if math.abs(v)>=10000 then return string.format("%.1f万",v/10000) end;return U.fmt(v) end
function U.date(ts,fmt)
 local cal=time.epoch2cal(ts or U.now()) or {};local current=time.getlocal and time.getlocal() or {}
 local utc=time.epoch2cal(U.now()) or {};local offset=((current.hour or 0)-(utc.hour or 0))*3600+((current.min or current.minute or 0)-(utc.min or utc.minute or 0))*60
 if offset>43200 then offset=offset-86400 elseif offset < -43200 then offset=offset+86400 end
 cal=time.epoch2cal((ts or U.now())+offset) or cal
 local values={Y=string.format('%04d',cal.year or 1970),m=string.format('%02d',cal.mon or cal.month or 1),d=string.format('%02d',cal.day or 1),H=string.format('%02d',cal.hour or 0),M=string.format('%02d',cal.min or cal.minute or 0),S=string.format('%02d',cal.sec or cal.second or 0)}
 return ((fmt or '%m-%d %H:%M'):gsub('%%([YmdHMS])',values))
end
function U.day(ts) return U.date(ts,"%Y-%m-%d") end
function U.duration(sec) sec=math.max(0,tonumber(sec) or 0);return string.format("%02d:%02d",math.floor(sec/60),sec%60) end
-- MD5 is used only by Bilibili's WBI request signing, never for password storage.
local shifts={7,12,17,22,5,9,14,20,4,11,16,23,6,10,15,21}
local K={0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,0x6b901122,0xfd987193,0xa679438e,0x49b40821,0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,0xd62f105d,0x2441453,0xd8a1e681,0xe7d3fbc8,0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,0x289b7ec6,0xeaa127fa,0xd4ef3085,0x4881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391}
local function rot(x,n) return ((x<<n)|(x>>(32-n)))&0xffffffff end
function U.md5(s)
 local len=#s;local tail=string.char(128)..string.rep(string.char(0),(55-len)%64)
 local bits=len*8;for i=0,7 do tail=tail..string.char(math.floor(bits/2^(8*i))%256) end;s=s..tail
 local a0,b0,c0,d0=0x67452301,0xefcdab89,0x98badcfe,0x10325476
 for off=1,#s,64 do
  local M={};for j=0,15 do local p=off+j*4;M[j]=(s:byte(p)|(s:byte(p+1)<<8)|(s:byte(p+2)<<16)|(s:byte(p+3)<<24))&0xffffffff end
  local a,b,c,d=a0,b0,c0,d0
  for i=0,63 do
   local f,g,r
   if i<16 then f=(b&c)|((~b)&d);g=i;r=shifts[i%4+1]
   elseif i<32 then f=(d&b)|((~d)&c);g=(5*i+1)%16;r=shifts[5+i%4]
   elseif i<48 then f=b~c~d;g=(3*i+5)%16;r=shifts[9+i%4]
   else f=c~(b|(~d));g=(7*i)%16;r=shifts[13+i%4] end
   local t=d;d=c;c=b;b=(b+rot((a+f+K[i+1]+M[g])&0xffffffff,r))&0xffffffff;a=t
  end
  a0=(a0+a)&0xffffffff;b0=(b0+b)&0xffffffff;c0=(c0+c)&0xffffffff;d0=(d0+d)&0xffffffff
 end
 local out={};for _,v in ipairs({a0,b0,c0,d0}) do for i=0,3 do out[#out+1]=string.format("%02x",(v>>(i*8))&255) end end;return table.concat(out)
end
local MIX={46,47,18,2,53,8,23,32,15,50,10,31,58,3,45,35,27,43,5,49,33,9,42,19,29,28,14,39,12,38,41,13,37,48,7,16,24,55,40,61,26,17,0,1,60,51,30,4,22,25,54,21,56,59,6,63,57,62,11,36,20,34,44,52}
function U.wbi(params,key)
 local mix="";for i=1,32 do local j=MIX[i]+1;mix=mix..key:sub(j,j) end
 params.wts=tostring(U.now());local keys={};for k in pairs(params) do keys[#keys+1]=k end;table.sort(keys)
 local out={};for _,k in ipairs(keys) do out[#out+1]=U.encode(k).."="..U.encode(tostring(params[k]):gsub("[!'()*]","")) end
 local qs=table.concat(out,"&");return qs.."&w_rid="..U.md5(qs..mix)
end
return U
