-- Fixed QR version 8 / error correction L / byte mode / mask 0.
-- Capacity 192 UTF-8 bytes, sufficient for Bilibili web login URLs.
local QR={}
local function mul(x,y)
 local z=0;for _=1,8 do if (y&1)~=0 then z=z~x end;y=y>>1;x=x<<1;if (x&256)~=0 then x=x~0x11d end end;return z
end
local function ecc(data,count)
 local gen={1};local root=1
 for _=1,count do local nextgen={};for i=1,#gen+1 do nextgen[i]=0 end
  for i=1,#gen do nextgen[i]=nextgen[i]~gen[i];nextgen[i+1]=nextgen[i+1]~mul(gen[i],root) end
  gen=nextgen;root=mul(root,2)
 end
 local rem={};for i=1,count do rem[i]=0 end
 for _,b in ipairs(data) do local factor=b~rem[1];table.remove(rem,1);rem[count]=0;for i=1,count do rem[i]=rem[i]~mul(gen[i+1],factor) end end
 return rem
end
function QR.encode(text)
 if type(text)~="string" or #text>192 then return nil,"二维码内容过长" end
 local bits={};local function append(v,n) for i=n-1,0,-1 do bits[#bits+1]=(v>>i)&1 end end
 append(4,4);append(#text,8);for i=1,#text do append(text:byte(i),8) end
 for _=1,math.min(4,194*8-#bits) do bits[#bits+1]=0 end
 while #bits%8~=0 do bits[#bits+1]=0 end
 local bytes={};for i=1,#bits,8 do local v=0;for j=0,7 do v=(v<<1)|bits[i+j] end;bytes[#bytes+1]=v end
 local pad=0;while #bytes<194 do bytes[#bytes+1]=pad%2==0 and 236 or 17;pad=pad+1 end
 local b1,b2={},{};for i=1,97 do b1[i]=bytes[i];b2[i]=bytes[i+97] end
 local e1,e2=ecc(b1,24),ecc(b2,24);local codewords={}
 for i=1,97 do codewords[#codewords+1]=b1[i];codewords[#codewords+1]=b2[i] end
 for i=1,24 do codewords[#codewords+1]=e1[i];codewords[#codewords+1]=e2[i] end
 local size=49;local matrix,used={},{};for y=0,size-1 do matrix[y]={};used[y]={};for x=0,size-1 do matrix[y][x]=false end end
 local function set(x,y,on) if x>=0 and y>=0 and x<size and y<size then matrix[y][x]=on;used[y][x]=true end end
 for i=0,size-1 do set(6,i,i%2==0);set(i,6,i%2==0) end
 local function finder(cx,cy) for dy=-4,4 do for dx=-4,4 do local d=math.max(math.abs(dx),math.abs(dy));set(cx+dx,cy+dy,d~=2 and d~=4) end end end
 finder(3,3);finder(size-4,3);finder(3,size-4)
 local centers={6,24,42};for i,cx in ipairs(centers) do for j,cy in ipairs(centers) do
  if not ((i==1 and j==1) or (i==1 and j==3) or (i==3 and j==1)) then
   for dy=-2,2 do for dx=-2,2 do set(cx+dx,cy+dy,math.max(math.abs(dx),math.abs(dy))~=1) end end
  end
 end end
 local function bit(v,i) return ((v>>i)&1)~=0 end
 local format=8;local rem=format;for _=1,10 do rem=(rem<<1)~(((rem>>9)&1)*0x537) end;format=((format<<10)|rem)~0x5412
 for i=0,5 do set(8,i,bit(format,i)) end;set(8,7,bit(format,6));set(8,8,bit(format,7));set(7,8,bit(format,8))
 for i=9,14 do set(14-i,8,bit(format,i)) end
 for i=0,7 do set(size-1-i,8,bit(format,i)) end;for i=8,14 do set(8,size-15+i,bit(format,i)) end;set(8,size-8,true)
 local version=8;rem=version;for _=1,12 do rem=(rem<<1)~(((rem>>11)&1)*0x1f25) end;version=(version<<12)|rem
 for i=0,17 do local a=size-11+i%3;local b=math.floor(i/3);set(a,b,bit(version,i));set(b,a,bit(version,i)) end
 local idx=0;local right=size-1
 while right>=1 do
  if right==6 then right=5 end
  for vert=0,size-1 do for j=0,1 do local x=right-j;local upward=((right+1)&2)==0;local y=upward and size-1-vert or vert
   if not used[y][x] then local v=false;if idx<#codewords*8 then v=bit(codewords[math.floor(idx/8)+1],7-idx%8) end
    if (x+y)%2==0 then v=not v end;matrix[y][x]=v;idx=idx+1
   end
  end end;right=right-2
 end
 local rows={};for y=0,size-1 do local row={};for x=0,size-1 do row[#row+1]=matrix[y][x] and "1" or "0" end;rows[#rows+1]=table.concat(row) end
 return {size=size,bits=table.concat(rows)}
end
return QR
