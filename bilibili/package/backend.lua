local Backend={}
function Backend.new(U,QR,dir)
 local FeedJSON=assert(loadfile(dir..'/feed_json.lua'))()
 local SESSION_PATH='/sd/.bilibili-session'
 local session=U.read(SESSION_PATH) or U.read('/tmp/bilibili-session.json') or {}
 if type(session.cookie)~='string' or not tostring(session.uid or ''):match('^%d+$') then session={}end
 local config=U.read(dir..'/settings.json') or {}
 local s={uid=tostring(session.uid or config.uid or ''),account={},signed_in=false,stopped=false,busy=false,queue={},next_http=0,revision=0,
  fans={},creator={},posts={},live={},messages={},feed={},recent={},trends={},meta={},qr={status='idle'},network='idle',observations=U.read(dir..'/observations.json') or {},generation=0,session_saved=session.cookie~=nil}
 local wbi_key='';local qr_key='';local qr_generation=0;local next_poll=0;local poll_deadline=0;local round_at=0
 local pending_images={};local image_cache={}
 local function changed() s.revision=s.revision+1;if s.on_change then s.on_change() end end
 local function error_text(code)
  if code==-101 then return '登录已失效，请重新扫码' end
  if code==-352 or code==-412 or code==412 then return '请求受限，稍后重试' end
  if not code or code<=0 then return '网络连接失败' end
  return '接口暂不可用 ('..tostring(code)..')'
 end
 local function observe(follower,totals)
  if s.uid=='' then return end
  local o=s.observations;if o.uid~=s.uid then o={uid=s.uid,days={}};s.observations=o end;o.days=o.days or {}
  local day=U.day();local d=o.days[#o.days]
  if not d or d.date~=day then d={date=day,since=U.now(),timestamp=U.now(),samples=0};o.days[#o.days+1]=d end
  if follower then d.first_fans=d.first_fans or follower;d.fans=follower end
  if totals then d.first=d.first or totals;d.last=totals;d.samples=d.samples+1 end
  while #o.days>31 do table.remove(o.days,1) end
  U.save(dir..'/observations.json',o)
 end
 local function set_meta(key,ok,err)
  local m=s.meta[key] or {};s.meta[key]=m;m.attempt=U.now();m.status=ok and 'ok' or 'error';m.error=err or ''
  if ok then m.updated=U.now();s.network='online' end
 end
 local function enqueue(job,front)
  if s.stopped then return end
  for _,j in ipairs(s.queue) do if j.key==job.key then return end end
  if front then table.insert(s.queue,1,job) else s.queue[#s.queue+1]=job end
 end
 local function defer_image(job,target,path)
  local cached=image_cache[job.key]
  if cached and cached.url==job.url and file.exists(path)then target.cover_path=path;return end
  local callback=job.callback
  job.callback=function(data)callback(data);if target.cover_path then image_cache[job.key]={url=job.url,path=path}end end
  pending_images[job.key]=job
 end
 function s:prioritize_image(page,index)
  local key=page==3 and ('cover'..index) or page==6 and ('feed_image'..index) or page==9 and ('recent_image'..index)
  local job=key and pending_images[key]
  if job and self.active_job~=key then pending_images[key]=nil;enqueue(job,true)end
 end
 local function cookie_value(headers,name)
  if type(headers)=='string' then return headers:match(name..'=([^;\r\n]+)') end
  for k,v in pairs(type(headers)=='table' and headers or {}) do
   if tostring(k):lower()=='set-cookie' then
    local values=type(v)=='table' and v or {v};for _,line in pairs(values) do
     local found=tostring(line):match(name..'=([^;\r\n]+)');if found then return found end
    end
   elseif type(v)=='table' and tostring(v.name or v.key or v[1] or ''):lower()=='set-cookie' then
    local found=tostring(v.value or v[2] or ''):match(name..'=([^;\r\n]+)');if found then return found end
   elseif type(k)=='number' and type(v)=='string' and v:lower():find('set-cookie:',1,true) then
    local found=v:match(name..'=([^;\r\n]+)');if found then return found end
   end
  end
 end
 local function store_login(data,headers)
  local values=U.query(tostring(data.url or ''):match('%?(.*)') or '')
  for _,entry in ipairs(type(data.cookie_info)=='table' and data.cookie_info.cookies or {}) do
   if type(entry)=='table' and type(entry.name)=='string' and type(entry.value)=='string' then values[entry.name]=entry.value end
  end
  local fields={};for k in pairs(values)do fields[#fields+1]=k end;table.sort(fields)
  local header_shapes={};for k,v in pairs(type(headers)=='table' and headers or {})do
   local entry={key=tostring(k),kind=type(v)};if type(v)=='table'then entry.fields={};for name,part in pairs(v)do entry.fields[#entry.fields+1]=tostring(name)..':'..type(part)end elseif type(v)=='string'then entry.length=#v end;header_shapes[#header_shapes+1]=entry
  end
  s.login_diagnostic={url_fields=fields,url_length=#tostring(data.url or ''),headers_type=type(headers),header_shapes=header_shapes}
  local pairs_out={};for _,name in ipairs({'SESSDATA','bili_jct','DedeUserID','DedeUserID__ckMd5'}) do
   local v=values[name] or cookie_value(headers,name);if v and v~='' and not v:find('[;\r\n]') then pairs_out[#pairs_out+1]=name..'='..v;values[name]=v else values[name]=nil end
  end
  if not values.SESSDATA or not tostring(values.DedeUserID or ''):match('^%d+$') then return false end
  session={uid=tostring(values.DedeUserID),cookie=table.concat(pairs_out,'; ')}
  s.uid=session.uid;s.account={};s.signed_in=false
  -- Extensionless private file is not served by the firmware's static-file handler.
  -- Never include credentials in snapshots, logs or the application package.
  s.session_saved=U.save(SESSION_PATH,session)
  U.save(dir..'/settings.json',{uid=s.uid});return true
 end
 local function tv_form(key)
  local body='appkey=4409e2ce8ffd12b8'..(key and '&auth_code='..U.encode(key) or '')..'&local_id=0&ts='..tostring(U.now())
  return body..'&sign='..U.md5(body..'59b43e04ad6965f34319062b478f83dd')
 end
 local function nav_job() return {key='account',url='https://api.bilibili.com/x/web-interface/nav',accept_error_data=true,callback=function(data,headers,code)
  local w=data.wbi_img or {};local a=tostring(w.img_url or ''):match('/([^/]+)%.');local b=tostring(w.sub_url or ''):match('/([^/]+)%.')
  if a and b then wbi_key=a..b end
  local was_signed_in=s.signed_in
  s.signed_in=code==0 and data.isLogin==true
  if (code==0 or code==-101) and (not s.auth_checked or was_signed_in) and not s.signed_in then s.auto_login_needed=true end
  if code==0 or code==-101 then s.auth_checked=true end
  if s.signed_in then s.uid=tostring(data.mid);s.account={uid=s.uid,name=U.str(data.uname,40),face=data.face};s.qr.status='success';qr_key='';U.save(dir..'/settings.json',{uid=s.uid})
  elseif session.cookie and code==-101 then
   session={};s.session_saved=false;pcall(file.remove,SESSION_PATH);pcall(file.remove,SESSION_PATH..'.tmp')
   s.qr.status='expired';s.meta.account={status='error',error='登录已失效，请重新扫码'}
  end
 end} end
 local function posts_from(items)
  local out={};for i,p in ipairs(items or {}) do if i>5 then break end;out[#out+1]={title=U.str(p.title,90),pic=p.pic or p.cover,bvid=p.bvid,aid=p.aid,pubtime=p.created or p.pubtime,duration=p.length or U.duration(p.duration),view=p.play or (p.stat or {}).view,like=p.like or (p.stat or {}).like,coin=p.coin or (p.stat or {}).coin} end
  table.sort(out,function(a,b)return (tonumber(a.pubtime) or 0)>(tonumber(b.pubtime) or 0)end);s.posts=out
  for i,p in ipairs(out) do
   local pic=tostring(p.pic or ''):gsub('^http:','https:');local host=pic:match('^https://([^/]+)/')
   if host and (host=='hdslb.com' or host:sub(-10)=='.hdslb.com') then
    local cover=pic:gsub('@.*$','')..'@296w_78h_1c.jpg';local path=dir..'/cover'..i..'.jpg'
    defer_image({key='cover'..i,url=cover,no_cookie=true,binary=true,callback=function(data)
     if s.posts[i]==p and type(data)=='string' and #data<=200000 and data:byte(1)==255 and data:byte(2)==216 then
      if lv_img_cache_invalidate_src then pcall(lv_img_cache_invalidate_src,'S:'..path:sub(4))end
      local wrote=file.putcontents(path,data);if wrote then p.cover_path=path end
     end
    end},p,path)
   end
  end
 end
 local function public_jobs()
  enqueue({key='fans',url=function()if s.uid=='' then return end;return 'https://api.bilibili.com/x/relation/stat?vmid='..s.uid end,callback=function(d)s.fans={count=d.follower,following=d.following};observe(tonumber(d.follower))end})
  enqueue({key='live',url=function()if s.uid=='' then return end;return 'https://api.live.bilibili.com/room/v1/Room/get_status_info_by_uids?uids[]='..s.uid end,callback=function(d)
   local l=d[s.uid] or d[tonumber(s.uid)] or {};s.live={status=l.live_status or 0,title=U.str(l.title or '',80),name=U.str(l.uname or '',40),room=l.room_id,popularity=l.online,started=l.live_time,cover=l.cover_from_user or l.keyframe}
   if not s.account.name or s.account.name=='' then s.account.name=l.uname end
  end})
  enqueue({key='posts',url=function()
   if s.uid=='' then return end
   if s.signed_in then return 'https://member.bilibili.com/x/web/data/archive_diagnose/compare?size=5' end
   if #wbi_key<64 then return nil,'签名信息暂不可用' end
   return 'https://api.bilibili.com/x/space/wbi/arc/search?'..U.wbi({mid=s.uid,pn=1,ps=5,order='pubdate'},wbi_key)
  end,callback=function(d)posts_from(d.list and (d.list.vlist or d.list) or {})end})
 end
 local function private_jobs()
  enqueue({key='recent',private=true,url='https://api.bilibili.com/x/web-interface/history/cursor?ps=5&type=archive',callback=function(d)
   local out={};for _,v in ipairs(d.list or {})do
    local business=(v.history or {}).business
    if business=='archive' or business=='pgc' then
     local duration=math.max(0,tonumber(v.duration) or 0);local progress=tonumber(v.progress) or 0
     out[#out+1]={title=U.str(v.title,100),author=U.str(v.author_name,30),view_at=tonumber(v.view_at) or 0,duration=duration,progress=progress<0 and duration or math.min(duration,progress),finished=progress<0 or (duration>0 and progress>=duration),bvid=(v.history or {}).bvid,pic=type(v.cover)=='string' and v.cover or nil}
    end;if #out>=5 then break end
   end;s.recent=out
   for i,v in ipairs(out)do
    local pic=tostring(v.pic or ''):gsub('^//','https://'):gsub('^http:','https:');local host=pic:match('^https://([^/]+)/')
    if host and (host=='hdslb.com' or host:sub(-10)=='.hdslb.com')then
     local path=dir..'/recent'..i..'.jpg'
     defer_image({key='recent_image'..i,url=pic:gsub('@.*$','')..'@112w_63h_1c.jpg',no_cookie=true,binary=true,callback=function(bytes)
      if s.recent[i]==v and type(bytes)=='string' and #bytes<=50000 and bytes:byte(1)==255 and bytes:byte(2)==216 then
       if lv_img_cache_invalidate_src then pcall(lv_img_cache_invalidate_src,'S:'..path:sub(4))end
       if file.putcontents(path,bytes)then v.cover_path=path end
      end
     end},v,path)
    end
   end
  end})
  enqueue({key='creator',private=true,url='https://member.bilibili.com/x/web/index/stat',callback=function(d)
   s.creator={latest={view=U.number(d.incr_click or d.incr_view),like=U.number(d.inc_like or d.incr_like),fav=U.number(d.inc_fav or d.incr_fav),coin=U.number(d.inc_coin or d.incr_coin)},totals={view=U.number(d.total_click or d.view),like=U.number(d.total_like or d.like),fav=U.number(d.total_fav or d.fav),coin=U.number(d.total_coin or d.coin)}}
   observe(nil,s.creator.totals)
  end})
  enqueue({key='messages',private=true,url='https://api.vc.bilibili.com/x/im/web/msgfeed/unread',callback=function(d)
   s.messages.reply=U.number(d.reply);s.messages.at=U.number(d.at);s.messages.like=U.number(d.like or d.recv_like);s.messages.system=U.number(d.sys_msg);s.messages.combined=U.number(d.recv_reply)
  end})
  enqueue({key='private_messages',private=true,url='https://api.vc.bilibili.com/session_svr/v1/session_svr/single_unread',callback=function(d)
   s.messages.private=(tonumber(d.follow_unread) or 0)+(tonumber(d.unfollow_unread) or 0)
  end})
  enqueue({key='feed',private=true,url='https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all?type=all',callback=function(d)
   local out={};for _,item in ipairs(d.items or {}) do if #out>=8 then break end
    local m=item.modules or {};local a=m.module_author or {};local dyn=m.module_dynamic or {};local st=m.module_stat or {};local major=dyn.major or {};local arc=major.archive or {};local text=dyn.desc and dyn.desc.text or arc.title or (major.article or {}).title or ''
    if text=='' and item.orig then local od=((item.orig.modules or {}).module_dynamic or {});text='转发：'..tostring((od.desc or {}).text or (((od.major or {}).archive or {}).title) or '查看原动态') end
    local image_major=major
    if item.orig and next(major)==nil then image_major=((((item.orig.modules or {}).module_dynamic or {}).major) or {})end
    local pic=(image_major.archive or {}).cover or (((image_major.draw or {}).items or {})[1] or {}).src or ((image_major.article or {}).covers or {})[1]
    if text~='' or pic then out[#out+1]={id=item.id_str,name=U.str(a.name,24),text=U.str(text,110),time=a.pub_ts or 0,action=U.str(a.pub_action or '',20),like=(st.like or {}).count,reply=(st.comment or {}).count,share=(st.forward or {}).count,pic=pic} end
   end;s.feed=out
   for i,f in ipairs(out) do
    local pic=tostring(f.pic or ''):gsub('^//','https://'):gsub('^http:','https:');local host=pic:match('^https://([^/]+)/')
    if host and (host=='hdslb.com' or host:sub(-10)=='.hdslb.com')then
     local path=dir..'/feed'..i..'.jpg'
     defer_image({key='feed_image'..i,url=pic:gsub('@.*$','')..'@88w_66h_1c.jpg',no_cookie=true,binary=true,callback=function(bytes)
      if s.feed[i]==f and type(bytes)=='string' and #bytes<=50000 and bytes:byte(1)==255 and bytes:byte(2)==216 then
       if lv_img_cache_invalidate_src then pcall(lv_img_cache_invalidate_src,'S:'..path:sub(4))end
       if file.putcontents(path,bytes)then f.cover_path=path end
      end
     end},f,path)
    end
   end
  end})
  for _,pair in ipairs({{'view',1},{'like',8},{'fav',6},{'coin',5}}) do local metric=pair[1];local typ=pair[2]
   if not s.meta['trend_'..metric] or U.now()-(s.meta['trend_'..metric].updated or 0)>1800 then
    enqueue({key='trend_'..metric,private=true,url='https://member.bilibili.com/x/web/data/pandect?type='..typ,callback=function(d)
     local points={};for _,v in ipairs(d or {}) do if tonumber(v.date_key) and tonumber(v.total_inc) then points[#points+1]={ts=tonumber(v.date_key),value=tonumber(v.total_inc)} end end
     table.sort(points,function(a,b)return a.ts<b.ts end);s.trends[metric]=points
    end})
   end
  end
 end
 function s:refresh()
  if U.ms()<(self.refresh_after or 0) then return false,'请稍候再刷新' end;self.refresh_after=U.ms()+10000
  enqueue(nav_job());public_jobs();private_jobs();round_at=U.ms()+120000;changed();return true
 end
 function s:set_uid(uid)
  uid=tostring(uid or ''):match('^%s*(.-)%s*$');if not uid:match('^%d+$') or #uid>16 or tonumber(uid)<=0 then return false,'请输入有效的数字 UID' end
  if self.signed_in and uid~=self.account.uid then return false,'登录后展示当前账号；切换其他 UID 请先退出登录' end
  pending_images={};image_cache={}
  self.generation=self.generation+1;self.uid=uid;self.account={};self.fans={};self.creator={};self.posts={};self.live={};self.messages={};self.feed={};self.recent={};self.trends={};self.meta={};self.queue={};self.refresh_after=0
  U.save(dir..'/settings.json',{uid=uid});self:refresh();return true
 end
 function s:start_login()
  self.auto_login_needed=false
  if self.qr.status=='generating' then return false,'二维码正在生成' end
  if U.ms()<(self.login_after or 0) then return false,'请稍候再获取' end;self.login_after=U.ms()+5000
  qr_generation=qr_generation+1;local gen=qr_generation;qr_key='';self.qr={status='generating'}
  enqueue({key='qr_generate',url='https://passport.bilibili.com/x/passport-tv-login/qrcode/auth_code',body=function()return tv_form()end,no_cookie=true,callback=function(d)
   if gen~=qr_generation then return end
   local matrix,err=QR.encode(d.url or '');if not matrix or type(d.auth_code)~='string' then s.qr={status='error',error=err or '二维码响应不完整'};return end
   qr_key=d.auth_code;poll_deadline=U.ms()+175000;next_poll=U.ms()+2000;s.qr={status='waiting',matrix=matrix,expires_at=U.now()+175}
  end,on_error=function(err)if gen==qr_generation then s.qr={status='error',error=err} end end},true);changed();return true
 end
 function s:logout()
  pending_images={};image_cache={}
  pcall(file.remove,SESSION_PATH);pcall(file.remove,SESSION_PATH..'.tmp');self.session_saved=false
  self.generation=self.generation+1;qr_generation=qr_generation+1;qr_key='';session={};pcall(file.remove,'/tmp/bilibili-session.json');pcall(file.remove,'/tmp/bilibili-session.json.tmp')
  self.signed_in=false;self.creator={};self.messages={};self.feed={};self.recent={};self.trends={};self.qr={status='idle'};self.queue={};self.meta={};self.refresh_after=0;self:refresh();changed()
  self.auto_login_needed=true
 end
 function s:snapshot()
  local today={};local days=self.observations.uid==self.uid and self.observations.days or {};local d=days and days[#days]
  if d and d.date==U.day() then
   today.since=d.since;today.samples=d.samples;today.fans=d.fans and d.first_fans and d.fans-d.first_fans
   if self.signed_in and (d.samples or 0)>1 then for _,key in ipairs({'view','like','fav','coin'}) do if tonumber((d.last or {})[key]) and tonumber((d.first or {})[key]) then today[key]=d.last[key]-d.first[key] end end end
  end
  local follower_trend={};for _,row in ipairs(days or {}) do if row.first_fans and row.fans then follower_trend[#follower_trend+1]={ts=row.timestamp,value=row.fans-row.first_fans,partial=true} end end
  local trends={fans=follower_trend};for k,v in pairs(self.trends) do trends[k]=v end
  return {ok=true,uid=self.uid,account=self.account,signed_in=self.signed_in,fans=self.fans,today=today,creator=self.creator,posts=self.posts,live=self.live,messages=self.messages,feed=self.feed,recent=self.recent,trends=trends,meta=self.meta,qr=self.qr,network=self.network,busy=self.busy,revision=self.revision,now=U.now(),session_saved=self.session_saved,login_diagnostic=self.login_diagnostic,feed_diagnostic=self.feed_diagnostic}
 end
 function s:tick()
  if self.stopped then return end;local now=U.ms()
  if qr_key~='' and now>=poll_deadline then qr_key='';self.qr.status='expired';self.qr.matrix=nil;changed() end
  if qr_key~='' and now>=next_poll and not self.busy then
   local gen=qr_generation;local this_key=qr_key;next_poll=now+2500
   enqueue({key='qr_poll',url='https://passport.bilibili.com/x/passport-tv-login/qrcode/poll',body=function()return tv_form(this_key)end,accept_codes={[86039]=true,[86090]=true,[86038]=true},no_cookie=true,callback=function(d,h,api_code)
    if gen~=qr_generation then return end
    if api_code==0 then
     qr_key='';s.qr.matrix=nil
     if store_login(d,h) then s.qr.status='verifying';s.queue={};s.refresh_after=0;s:refresh()
     else s.qr={status='error',error='未获取完整登录凭据，请重新扫码'} end
    elseif api_code==86090 then s.qr.status='scanned'
    elseif api_code==86038 then qr_key='';s.qr={status='expired'} end
   end,on_error=function(err)if gen==qr_generation then qr_key='';s.qr={status='error',error=err}end end},true)
  end
  if now>=round_at and qr_key=='' then self:refresh() end
  if self.busy or now<self.next_http or #self.queue==0 then return end
  local job=table.remove(self.queue,1);if job.private and not self.signed_in then return end
  local url,err=job.url,nil;if type(url)=='function' then url,err=url() end
  if not url then if err then set_meta(job.key,false,err);changed() end;return end
  self.busy=true;local gen=self.generation;self.active_job=job.key
  local headers={['User-Agent']='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36',['Referer']=url:find('member.bilibili.com',1,true) and 'https://member.bilibili.com/' or 'https://www.bilibili.com/',['Accept']='application/json',['Accept-Encoding']='identity'}
  if session.cookie and not job.no_cookie then headers.Cookie=session.cookie end
  local function complete(code,body,response_headers)
   if s.stopped then return end;s.busy=false;s.active_job=nil;s.next_http=U.ms()+600
   if gen~=s.generation then return end
   if job.binary then
    if code==200 and type(body)=='string' then local ok=pcall(job.callback,body);set_meta(job.key,ok,ok and nil or '封面读取失败')else set_meta(job.key,false,'封面暂不可用')end;changed();return
   end
   local doc
   if job.key=='feed' then
    local projected,reason=FeedJSON.project(body)
    local decoded,result=false,nil;if projected then decoded,result=pcall(sjson.decode,projected)end
    if decoded and type(result)=='table'then doc=result end
    s.feed_diagnostic={http_code=code,bytes=type(body)=='string' and #body or 0,projected_bytes=projected and #projected or 0,decoded=doc~=nil,reason=reason or (doc and 'ok' or 'decode_failed')}
   else doc=type(body)=='string' and #body<=524288 and U.decode(body) or nil end
   local api_code=doc and tonumber(doc.code);local ok=code==200 and api_code==0 and doc.data~=nil
   if job.key=='qr_generate' or job.key=='qr_poll' then s.login_diagnostic={http_code=code,api_code=api_code,body_length=type(body)=='string' and #body or 0} end
   if ok or (code==200 and job.accept_codes and job.accept_codes[api_code]) or (job.accept_error_data and code==200 and doc and type(doc.data)=='table') then
    local good,result=pcall(job.callback,type(doc.data)=='table' and doc.data or {},response_headers or {},api_code)
    if good then set_meta(job.key,true) else set_meta(job.key,false,'数据格式不兼容');s.last_callback_error=tostring(result):gsub('https?://%S+','[url]'):sub(1,180) end
   else
    local why=code==200 and not doc and '响应数据解析失败' or error_text(api_code or code);set_meta(job.key,false,why)
    if tonumber(code)==nil or code<=0 then s.network='offline' end
    if api_code==-352 or api_code==-412 or code==412 then s.next_http=U.ms()+60000 end
    if job.on_error then job.on_error(why) end
   end;changed()
  end
  local options={timeout=12000,max_redirects=0,bufsz=4096,headers=headers}
  local ok,request_error
  if job.body then
   headers['Content-Type']='application/x-www-form-urlencoded'
   local body=type(job.body)=='function' and job.body() or job.body
   ok,request_error=pcall(http.post,url,options,body,complete)
  else ok=pcall(http.get,url,options,complete) end
  if not ok then complete(-1) end
 end
 function s:stop()self.stopped=true;self.queue={};self.generation=self.generation+1;qr_key='';session={} end
 return s
end
return Backend
