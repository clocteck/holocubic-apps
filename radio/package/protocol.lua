local P = {}
function P.url(base, ref)
  ref = tostring(ref):match('^%s*(.-)%s*$')
  if ref:match('^https?://') then return ref end
  local scheme, authority, path = base:match('^(https?)://([^/]+)(.*)$')
  if not scheme then return nil end
  if ref:sub(1,2)=='//' then return scheme..':'..ref end
  path=(path or '/'):gsub('[?#].*$','')
  if ref:sub(1,1)=='?' then return scheme..'://'..authority..path..ref end
  if ref:sub(1,1)~='/' then ref=(path:match('^(.*)/') or '')..'/'..ref end
  local clean={}
  for v in ref:gmatch('[^/]+') do if v=='..' then table.remove(clean) elseif v~='.' then clean[#clean+1]=v end end
  return scheme..'://'..authority..'/'..table.concat(clean,'/')
end
function P.attributes(line)
  local out={}
  for k,v in line:gmatch('([%w%-]+)="([^"]*)"') do out[k]=v end
  for k,v in line:gmatch('([%w%-]+)=([^,"]+)') do if not out[k] then out[k]=v end end
  return out
end
function P.playlist(text,base)
  if #text>65536 or not text:find('#EXTM3U',1,true) then return nil,'Invalid/oversized HLS playlist' end
  local p={segments={},variants={},target=6,sequence=0,ended=false}
  local duration,variant,discontinuity,sequence=nil,nil,false,0
  for raw_line in (text..'\n'):gmatch('(.-)\n') do
    local line=raw_line:gsub('\r',''):match('^%s*(.-)%s*$')
    if line:find('#EXT-X-KEY:',1,true)==1 then
      if P.attributes(line).METHOD~='NONE' then return nil,'Encrypted HLS is not supported' end
    elseif line:find('#EXT-X-MAP:',1,true)==1 then return nil,'fMP4 HLS is not supported; use TS/ADTS audio'
    elseif line:find('#EXT-X-BYTERANGE:',1,true)==1 then return nil,'HLS byte ranges are not supported'
    elseif line:find('#EXT-X-MEDIA:',1,true)==1 then
      local a=P.attributes(line)
      if a.TYPE=='AUDIO' and a.URI and not p.audio then p.audio=P.url(base,a.URI) end
    elseif line:find('#EXT-X-STREAM-INF:',1,true)==1 then variant=P.attributes(line)
    elseif line:find('#EXT-X-MEDIA-SEQUENCE:',1,true)==1 then sequence=tonumber(line:match(':(%d+)')) or 0;p.sequence=sequence
    elseif line:find('#EXT-X-TARGETDURATION:',1,true)==1 then p.target=tonumber(line:match(':(%d+)')) or 6
    elseif line=='#EXT-X-ENDLIST' then p.ended=true
    elseif line=='#EXT-X-DISCONTINUITY' then discontinuity=true
    elseif line:find('#EXTINF:',1,true)==1 then duration=tonumber(line:match(':([%d%.]+)')) or p.target
    elseif line~='' and line:sub(1,1)~='#' then
      if variant then p.variants[#p.variants+1]={url=P.url(base,line),bandwidth=tonumber(variant.BANDWIDTH) or 999999999};variant=nil
      else p.segments[#p.segments+1]={url=P.url(base,line),sequence=sequence,duration=duration or p.target,discontinuity=discontinuity};sequence=sequence+1;duration=nil;discontinuity=false end
    end
  end
  table.sort(p.variants,function(a,b)return a.bandwidth<b.bandwidth end)
  return p
end
function P.icy(interval,on_audio,on_title)
  local left=tonumber(interval) or 0
  local every=left
  local remaining,parts=0,{}
  return function(chunk)
    if every<=0 then on_audio(chunk);return end
    local pos=1
    while pos<=#chunk do
      if remaining>0 then
        local n=math.min(remaining,#chunk-pos+1);parts[#parts+1]=chunk:sub(pos,pos+n-1);remaining=remaining-n;pos=pos+n
        if remaining==0 then local meta=table.concat(parts);parts={};left=every;local title=meta:match("StreamTitle='(.-)';");if title then on_title(title) end end
      elseif left==0 then remaining=chunk:byte(pos)*16;pos=pos+1;if remaining==0 then left=every end
      else local n=math.min(left,#chunk-pos+1);on_audio(chunk:sub(pos,pos+n-1));left=left-n;pos=pos+n end
    end
  end
end
function P.codec(url,ctype,explicit)
  if explicit and explicit~='auto' and explicit~='hls' then return explicit end
  local u=url:lower():gsub('[?#].*$','');ctype=(ctype or ''):lower()
  if u:match('%.m3u8$') or ctype:find('mpegurl',1,true) then return 'hls' end
  if u:match('%.flac$') or ctype:find('flac',1,true) then return 'flac' end
  if u:match('%.aac$') or ctype:find('aac',1,true) then return 'aac' end
  if u:match('%.ts$') or ctype:find('mp2t',1,true) then return 'ts' end
  return 'mp3'
end
return P
