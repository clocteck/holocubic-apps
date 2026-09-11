-- Project the response before sjson allocates Lua tables for rich dynamic cards.
-- Unselected values are scanned in place; no credentials or body are logged.
local F={}
local author={name=true,pub_ts=true,pub_action=true}
local dynamic={desc={text=true},major={archive={title=true,cover=true},article={title=true,covers={array=true}},draw={items={array={src=true}}}}}
local modules={module_author=author,module_dynamic=dynamic,module_stat={like={count=true},comment={count=true},forward={count=true}}}
local schema={code=true,data={items={array={id_str=true,modules=modules,orig={modules={module_dynamic=dynamic}}}}}}
function F.project(source)
 if type(source)~='string' or #source>1048576 then return nil,'size' end
 local pos,n=1,#source
 local function fail()error('invalid JSON structure',0)end
 local function ws()while pos<=n and source:sub(pos,pos):match('%s')do pos=pos+1 end end
 local function quoted()
  local start=pos;if source:sub(pos,pos)~='"'then fail()end;pos=pos+1
  while pos<=n do local b=source:byte(pos)
   if b==34 then pos=pos+1;return start,pos-1
   elseif b==92 then
    local e=source:sub(pos+1,pos+1)
    if e=='u' then if not source:sub(pos+2,pos+5):match('^%x%x%x%x$')then fail()end;pos=pos+6
    elseif e:match('^["\\/bfnrt]$')then pos=pos+2 else fail()end
   elseif b<32 then fail()else pos=pos+1 end
  end;fail()
 end
 local parse
 parse=function(spec,depth)
  if depth>64 then fail()end;ws();local ch=source:sub(pos,pos)
  if ch=='{' then
   pos=pos+1;ws();local out=spec and {} or nil
   if source:sub(pos,pos)=='}'then pos=pos+1;return out and '{}' end
   while true do
    ws();local a,b=quoted();local rawkey=source:sub(a,b);ws();if source:sub(pos,pos)~=':'then fail()end;pos=pos+1
    local child=type(spec)=='table' and spec[rawkey:sub(2,-2)] or nil
    local value=parse(child,depth+1);if out and value then out[#out+1]=rawkey..':'..value end
    ws();local sep=source:sub(pos,pos);pos=pos+1;if sep=='}'then break elseif sep~=','then fail()end
   end
   return out and '{'..table.concat(out,',')..'}'
  elseif ch=='[' then
   pos=pos+1;ws();local out=spec and {} or nil;local count=0
   if source:sub(pos,pos)==']'then pos=pos+1;return out and '[]'end
   while true do count=count+1;local value=parse(type(spec)=='table' and count<=8 and spec.array or nil,depth+1);if out and value then out[#out+1]=value end
    ws();local sep=source:sub(pos,pos);pos=pos+1;if sep==']'then break elseif sep~=','then fail()end
   end;return out and '['..table.concat(out,',')..']'
  elseif ch=='"'then
   local a,b=quoted();if spec==true then
    if b-a>8192 then return '"正文过长，请在哔哩哔哩查看"'end
    return source:sub(a,b)
   end
  else
   local start=pos;while pos<=n and not source:sub(pos,pos):match('[%s,%]}]')do pos=pos+1 end
   local value=source:sub(start,pos-1)
   if value~='null' and value~='true' and value~='false' and not tonumber(value)then fail()end
   if spec==true then return value end
  end
 end
 local ok,value=pcall(function()local value=parse(schema,0);ws();if pos<=n then fail()end;return value end)
 if not ok then return nil,'invalid' end
 return value
end
return F
