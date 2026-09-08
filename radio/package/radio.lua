local DIR='/sd/apps/radio'
local SETTINGS='/sd/apps/settings.json'
local JSON=rawget(_G,'sjson') or rawget(_G,'json')
local P=dofile(DIR..'/protocol.lua')
local A={running=true,timers={},generation=0,index=1,volume=25,default_volume=25,language='zh-CN',status='idle',title='',error='',list_open=false,cursor=1,stats={}}
local Transport=dofile(DIR..'/transport.lua')
A.net=Transport.new(http,Transport.clock(tmr.now))
A.service_phase='manual';A.service_error='';A.want_play=true
local function decode(raw) if type(raw)~='string' then return nil end;local ok,v=pcall(JSON.decode,raw);return ok and type(v)=='table' and v or nil end
local function read(path) local ok,v=pcall(file.getcontents,path);return ok and v or nil end
local function read_json(path) return decode(read(path)) end
local function write_json(path,doc)
  local raw=JSON.encode(doc);local tmp=path..'.radio.tmp';local backup=path..'.radio.bak'
  if not file.putcontents(tmp,raw) then return nil,'write failed' end
  if not read_json(tmp) then return nil,'verification failed' end
  if file.exists(path) then
    if file.exists(backup) then file.remove(backup) end
    if not file.rename(path,backup) then return nil,'backup failed' end
  end
  if not file.rename(tmp,path) then if file.exists(backup) then file.rename(backup,path) end;return nil,'rename failed' end
  return true
end
local function clamp(v) return math.max(0,math.min(100,math.floor(tonumber(v) or 25))) end
local settings=read_json(SETTINGS)
if settings then
  A.language=settings.language or settings.locale or settings.lang or A.language
  A.default_volume=clamp(settings.radio_volume);A.volume=A.default_volume
  if settings.radio_volume==nil then settings.radio_volume=A.default_volume;write_json(SETTINGS,settings) end
else A.error='Cannot read shared settings; using safe volume 25' end
local Storage=dofile(DIR..'/storage.lua').new(file,JSON)
local catalog=Storage.load('stations')
A.stations=(catalog and catalog.stations) or dofile(DIR..'/stations.lua')
local saved=Storage.load('config') or {}
A.storage_error=Storage.error()
for i,s in ipairs(A.stations) do if s.id==saved.station_id then A.index=i end end
A.cursor=A.index
local audio_ok,audio=pcall(require,DIR..'/modules/radio.so')
if audio_ok then A.audio=audio;audio.volume(A.volume) else A.error=tostring(audio);A.status='error' end
local function after(name,ms,fn)
  if A.timers[name] then A.timers[name]:unregister() end
  local t=tmr.create();A.timers[name]=t;t:alarm(ms,tmr.ALARM_SINGLE,function() if A.running then fn() end end)
end
local function active(g) return A.running and g==A.generation end
local function close_connections()
  -- Transport retains a closing request until complete, and wakes DELAYACK.
  A.net.cancel();A.ack=nil;A.pending=nil
end
local function halt()
  A.generation=A.generation+1;close_connections()
  for _,n in ipairs({'retry','request','segment','playlist'}) do if A.timers[n] then A.timers[n]:unregister();A.timers[n]=nil end end
  if A.audio then pcall(A.audio.close) end
  A.codec=nil;A.status='idle';A.title=''
end
local play,retry,request,start_hls
local function feed(data)
  local accepted,err=A.audio.feed(data)
  if not accepted then error(err or 'audio feed failed') end
end
local function start_decoder(codec)
  if A.codec==codec then return true end
  local ok,err=A.audio.open(codec)
  if not ok then error(err or 'decoder open failed') end
  A.audio.volume(A.volume);A.codec=codec;A.status='buffering'
end
local function header(h,key)
  for k,v in pairs(h or {}) do if tostring(k):lower()==key then return tostring(v) end end
  return ''
end
request=function(url,g,opt)
  if not active(g) then return end
  local c=A.net.create(url,{async=true,timeout=12000,bufsz=4096,max_redirects=4,headers={['Icy-MetaData']=opt.text and '0' or '1',['Accept-Encoding']='identity',['User-Agent']='CubicRadio/0.1'}})
  c:on('error',function(err)retry(g,err)end)
  local body,bytes={},0
  local on_audio=function(data) feed(data) end
  local seen_code=0
  local finite=false
  c:on('headers',function(code,h)
    if not active(g) then c:close();return end
    seen_code=code
    finite=(tonumber(header(h,'content-length')) or 0)>0
    if code~=200 and code~=206 then c:close();retry(g,'HTTP '..tostring(code));return end
    if not opt.text then
      local codec=P.codec(url,header(h,'content-type'),opt.codec)
      if codec=='hls' then c:close();after('playlist',20,function()start_hls(url,g)end);return end
      local ok,err=pcall(start_decoder,codec)
      if not ok then c:close();retry(g,tostring(err));return end
      on_audio=P.icy(header(h,'icy-metaint'),feed,function(title)A.title=title end)
    end
  end)
  c:on('data',function(code,data)
    if not active(g) then c:close();return end
    if code~=200 and code~=206 then return end
    if opt.text then
      bytes=bytes+#data
      if bytes>65536 then c:close();retry(g,'Playlist exceeds 64 KB');return end
      body[#body+1]=data;return
    end
    local st=A.audio.state()
    if st.buffer_free<#data then A.pending={data=data,consume=on_audio};A.ack=c;return http.DELAYACK end
    local ok,err=pcall(on_audio,data)
    if not ok then c:close();retry(g,tostring(err));return end
    A.last_data=tmr.now();A.retries=0
    if A.audio.state().buffer_free<16384 then A.ack=c;return http.DELAYACK end
  end)
  c:on('complete',function(code)
    if not active(g) then return end
    if code and code<0 then retry(g,'HTTP stream interrupted');return end
    if seen_code~=200 and seen_code~=206 then retry(g,'HTTP connection ended before valid headers');return end
    if opt.done then opt.done(table.concat(body),code) elseif finite then A.audio.eos() elseif A.status~='idle' then retry(g,'Stream disconnected') end
  end)
  c:request()
end
start_hls=function(url,g,depth)
  depth=depth or 0;if depth>5 then retry(g,'HLS redirect nesting limit');return end
  local last=-1
  local function refresh()
    request(url,g,{text=true,done=function(body)
      local pl,err=P.playlist(body,url)
      if not pl then retry(g,err,true);return end
      if pl.audio or pl.variants[1] then start_hls(pl.audio or pl.variants[1].url,g,depth+1);return end
      if last<0 and not pl.ended and #pl.segments>3 then last=pl.segments[#pl.segments-2].sequence-1 end
      local queue={};for _,s in ipairs(pl.segments) do if s.sequence>last then queue[#queue+1]=s end end
      local pos=1
      local function next_segment()
        if not active(g) then return end
        local s=queue[pos]
        if not s then if pl.ended then if A.audio then A.audio.eos() end else after('playlist',math.max(1000,pl.target*500),refresh) end;return end
        if s.discontinuity and A.codec then
          local st=A.audio.state();if st.buffer_bytes>0 then after('segment',100,next_segment);return end
          A.audio.close();A.codec=nil
        end
        request(s.url,g,{done=function()last=s.sequence;pos=pos+1;after('segment',10,next_segment)end})
      end
      next_segment()
    end})
  end
  refresh()
end
retry=function(g,err,permanent)
  if not active(g) then return end
  halt();A.error=tostring(err);A.status='error'
  if not permanent then A.retries=(A.retries or 0)+1;after('retry',math.min(15000,1000*2^math.min(A.retries-1,4)),function()play(A.index,false)end) end
end
play=function(index,save)
  if not A.audio then return nil,A.error end
  halt();A.index=((index-1)%#A.stations)+1;A.cursor=A.index;A.status='connecting';A.error=''
  local station=A.stations[A.index];local g=A.generation
  if save then Storage.save('config',{station_id=station.id});A.storage_error=Storage.error() end
  A.want_play=true
  after('request',400,function()
    local ok,err=pcall(function()
      if station.codec=='hls' or P.codec(station.url)=='hls' then start_hls(station.url,g) else request(station.url,g,{codec=station.codec}) end
    end)
    if not ok then retry(g,tostring(err)) end
  end)
  return true
end
function A.set_volume(value) A.volume=clamp(value);if A.audio then A.audio.volume(A.volume) end end
function A.next(delta) A.list_open=false;return play(A.index+delta,true) end
function A.toggle() if A.status=='idle' or A.status=='error' then return play(A.index,true) else A.want_play=false;halt();return true end end
function A.exit() if not A.running then return end;halt();A.running=false;for _,t in pairs(A.timers) do pcall(function()t:unregister()end) end;if key then key.off() end;if controller and controller.on then controller.on('ble-main',nil) end;if A.ui then A.ui.close() end;if app then app.exit() end end
local function response(doc,status) return {status=status or '200 OK',type='application/json; charset=utf-8',headers={['Cache-Control']='no-store'},body=JSON.encode(doc)} end
local function api(req)
  local path=(req.uri or ''):match('/api/([^?]+)')
  if req.method==httpd.GET then
    if path=='state' then
      if A.audio then A.stats=A.audio.state() end
      return response({ok=true,status=A.status,error=A.error,title=A.title,station=A.stations[A.index],index=A.index,volume=A.volume,default_volume=A.default_volume,language=A.language,stats=A.stats,service_phase=A.service_phase,service_error=A.service_error,gain_multiplier=2,transport=A.net.state(),storage=Storage.state(),storage_error=Storage.error(),clock=A.ui and A.ui.clock_text or '--:--'})
    elseif path=='stations' then return response({ok=true,stations=A.stations}) end
  elseif req.method==httpd.POST then
    local raw=req.getbody and req.getbody() or '';if #raw>8192 then return response({ok=false,error='Request too large'},'413 Payload Too Large') end
    local d=decode(raw) or {}
    if path=='control' then
      if d.action=='play' then for i,s in ipairs(A.stations) do if s.id==tonumber(d.id) then play(i,true);break end end
      elseif d.action=='next' then A.next(1)
      elseif d.action=='prev' then A.next(-1)
      elseif d.action=='toggle' then A.toggle()
      elseif d.action=='volume' then A.set_volume(d.value)
      elseif d.action=='stop' then A.want_play=false;halt()
      elseif d.action=='exit' then after('exit',100,A.exit)
      else return response({ok=false,error='Unknown action'},'400 Bad Request') end
      return response({ok=true})
    elseif path=='settings' then
      local doc=read_json(SETTINGS);if not doc then return response({ok=false,error='Shared settings invalid; refusing overwrite'},'409 Conflict') end
      if d.default_volume~=nil then doc.radio_volume=clamp(d.default_volume) end
      if d.language and ({['zh-CN']=true,['zh-TW']=true,en=true,ja=true})[d.language] then doc.language=d.language end
      local ok,err=write_json(SETTINGS,doc);if not ok then return response({ok=false,error=err},'500 Internal Server Error') end
      A.default_volume=doc.radio_volume or A.default_volume;A.language=doc.language or A.language
      return response({ok=true})
    elseif path=='station' then
      local list={};for i,s in ipairs(A.stations) do list[i]=s end
      local id=tonumber(d.id);local found,maxid=nil,0;for i,s in ipairs(list) do if s.id==id then found=i end;maxid=math.max(maxid,s.id) end
      if d.remove then
        if not found or #list<=1 then return response({ok=false,error='Keep at least one station'},'400 Bad Request') end
        table.remove(list,found)
      else
        local name=tostring(d.name or ''):match('^%s*(.-)%s*$');local url=tostring(d.url or ''):match('^%s*(.-)%s*$')
        if #name<1 or #name>120 or #url>2048 or not url:match('^https?://[^%s]+$') or url:find('[%c]') then return response({ok=false,error='Invalid name or HTTP(S) URL'},'400 Bad Request') end
        if not found and #list>=2000 then return response({ok=false,error='2000 station limit'},'400 Bad Request') end
        local codec=d.codec or 'auto';if not ({auto=true,mp3=true,aac=true,flac=true,hls=true,ts=true})[codec] then return response({ok=false,error='Invalid codec'},'400 Bad Request') end
        list[found or (#list+1)]={id=id and found and id or maxid+1,name=name,url=url,codec=codec,group='custom'}
      end
      local ok,err=Storage.save('stations',{stations=list});A.storage_error=Storage.error();if not ok then return response({ok=false,error=err},'500 Internal Server Error') end
      local current=A.stations[A.index].id;A.stations=list;A.index=1;for i,s in ipairs(list) do if s.id==current then A.index=i end end;A.cursor=A.index
      if id==current then if d.remove then halt() elseif A.status~='idle' then play(A.index,false) end end
      return response({ok=true})
    end
  end
  return response({ok=false,error='Not found'},'404 Not Found')
end
local base=app.route_base() or '/radio'
httpd.start({webroot='/sd',auto_index=httpd.INDEX_NONE,max_handlers=12})
httpd.dynamic(httpd.GET,base..'/',function()
  return {status='200 OK',type='text/html; charset=utf-8',body=read(DIR..'/control.html') or 'Missing control.html'}
end)
for _,method in ipairs({httpd.GET,httpd.POST}) do httpd.dynamic(method,base..'/api/*',function(req)local ok,res=pcall(api,req);if ok then return res end;return response({ok=false,error=tostring(res)},'500 Internal Server Error')end) end
A.ui=dofile(DIR..'/ui.lua')(A)
local function key_action(code)
  if code==key.HOME then A.exit()
  elseif code==key.LEFT then A.next(-1)
  elseif code==key.RIGHT then A.next(1)
  elseif code==key.UP then if A.list_open then A.cursor=(A.cursor-2)%#A.stations+1 else A.set_volume(A.volume+5) end
  elseif code==key.DOWN then if A.list_open then A.cursor=A.cursor%#A.stations+1 else A.set_volume(A.volume-5) end end
end
if app.set_home_exit then app.set_home_exit(false) end
if key then key.on(function(code,event)if event==key.SHORT then key_action(code)end end) end
local last_buttons,last_repeat,lt,rt=0,0,false,false
A.timers.input=tmr.create();A.timers.input:alarm(40,tmr.ALARM_AUTO,function()
  if not A.running or not controller then return end
  local pad=controller.state('ble-main') or {};local b=tonumber(pad.buttons) or 0;local pressed=b&(~last_buttons);last_buttons=b
  if pressed&(4096|32768)~=0 then A.exit();return end
  if pressed&8192~=0 then A.list_open=not A.list_open;A.cursor=A.index end
  if pressed&4~=0 then A.next(-1) elseif pressed&8~=0 then A.next(1) end
  if pressed&16~=0 then if A.list_open then A.list_open=false;play(A.cursor,true) else A.toggle() end end
  local function trigger(v,old)if v==true then return true end;v=tonumber(v) or 0;return v>=(old and 8000 or 16000) or v==1 end
  local nl,nr=trigger(pad.lt or pad.l2,lt),trigger(pad.rt or pad.r2,rt)
  local now=tmr.now()/1000;local repeat_due=now-last_repeat>250
  if (pressed& (1|2|256|512)~=0) or (nl and not lt) or (nr and not rt) or (repeat_due and (nl or nr or b&(1|2|256|512)~=0)) then
    last_repeat=now
    if A.list_open and b&3~=0 then A.cursor=(A.cursor-1+(b&1~=0 and -1 or 1))%#A.stations+1
    elseif nl or b&(2|256)~=0 then A.set_volume(A.volume-5)
    elseif nr or b&(1|512)~=0 then A.set_volume(A.volume+5) end
  end
  lt,rt=nl,nr
end)
A.timers.tick=tmr.create();A.timers.tick:alarm(100,tmr.ALARM_AUTO,function()
  A.net.poll()
  local network=A.net.state()
  if network.blocked and A.want_play then
    A.transport_error='Previous stream did not close. HTTP cancellation is blocked.'
    A.error=A.transport_error;A.status='error'
  elseif A.transport_error then
    if A.error==A.transport_error then
      A.error='';if A.status=='error' and A.want_play then A.status='connecting' end
    end
    A.transport_error=nil
  end
  if A.audio then
    A.stats=A.audio.state()
    if A.ack and A.stats.buffer_free>32768 then
      local c=A.ack;A.ack=nil
      if A.pending then local pending=A.pending;A.pending=nil;local ok,err=pcall(pending.consume,pending.data);if not ok then retry(A.generation,err);return end end
      local ok,err=c:ack();if not ok then retry(A.generation,err);return end
    end
    if A.codec and A.stats.error~=0 and A.status~='error' then retry(A.generation,'Decoder error '..A.stats.error) end
    if A.status=='buffering' or A.status=='playing' then A.status=A.stats.status==2 and 'playing' or 'buffering' end
    if A.stats.status==4 then A.status='idle' end
  end
  A.ui.update()
end)
if A.audio then play(A.index,false) end
