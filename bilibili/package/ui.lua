local UI={}
local TITLES={'BiliBili','创作中心','最新投稿','直播间','消息中心','关注动态','数据趋势','账号登录','最近观看'}
local KEYS={'fans','creator','posts','live','messages','feed','trends','account','recent'}
local METRICS={'view','like','fav','coin','fans'}
local LABELS={view='播放',like='点赞',fav='收藏',coin='投币',fans='涨粉'}
local C={bg=0x000000,panel=0x151517,edge=0x2b2b30,text=0xffffff,sub=0xaeb0b8,pink=0xfb7299,green=0x61d8ab,blue=0x76caff,warn=0xe3bc70}
function UI.new(U,dir)
 local root=lv_scr_act();lv_obj_clean(root);lv_obj_set_style_bg_color(root,C.bg,LV_PART_MAIN)
 local self={page=1,index=1,metric=1,period=7,creator_latest=true,busy=false,dirty=true,root=root,timers={},account_selection=1}
 self.font=assert(lv_font_load(dir..'/font/ui12.bin'),'Chinese font missing')
 self.large=assert(lv_font_load(dir..'/font/number40.bin'),'Number font missing')
 self.front=lv_canvas_create(root,320,240,LV_IMG_CF_TRUE_COLOR);self.back=lv_canvas_create(root,320,240,LV_IMG_CF_TRUE_COLOR)
 assert(self.front and self.back,'Screen canvas allocation failed')
 lv_obj_set_pos(self.front,0,0);lv_obj_set_pos(self.back,320,0)
 local canvas=self.front
 local function box(x,y,w,h,color,radius)
  lv_canvas_draw_rect(canvas,x,y,w,h,{bg_color=color or C.panel,bg_opa=255,radius=radius or 0,border_width=0})
 end
 local function text(x,y,w,value,color,size,align,handle)
  local aligns={[0]=rawget(_G,'LV_TEXT_ALIGN_LEFT') or 1,[1]=rawget(_G,'LV_TEXT_ALIGN_CENTER') or 2,[2]=rawget(_G,'LV_TEXT_ALIGN_RIGHT') or 3}
  local d={color=color or C.text,opa=255,align=aligns[align or 0],font_size=size or 12}
  if not size or size==12 then d.font_handle=self.font end;if handle then d.font_handle=handle end
  lv_canvas_draw_text(canvas,x,y,w,tostring(value or ''),d)
 end
 local function line(x,y,x2,y2,color,width)lv_canvas_draw_line(canvas,x,y,x2,y2,color or C.edge,255,width or 1)end
 local function panel(x,y,w,h)box(x,y,w,h,C.panel,5)end
 local function number(x,y,w,value,size,color)local value=U.fmt(value);if #value>9 then size=16 elseif #value>7 then size=20 end;text(x,y,w,value,color or C.text,size or 24)end
 local function empty(title,sub)
  text(12,87,296,title,C.text,12,1);text(22,116,276,sub or '',C.sub,12,1)
 end
 local function safe_status(s,key)
  local m=s.meta[key] or {};if m.status=='error' then return m.error end
  return s.busy and '正在获取数据…' or '暂无数据'
 end
 local function chart(points,x,y,w,h,color)
  if #points==0 then text(x,y+math.floor(h/2)-6,w,'暂无历史数据',C.sub,12,1);return end
  local lo,hi=0,0;for _,p in ipairs(points) do lo=math.min(lo,p.value);hi=math.max(hi,p.value) end;if hi==lo then hi=lo+1 end
  line(x,y,x+w,y,C.edge);line(x,y+h,x+w,y+h,C.edge)
  local px,py
  for i,p in ipairs(points) do local xx=x+math.floor((i-1)*w/math.max(1,#points-1));local yy=y+h-math.floor((p.value-lo)*h/(hi-lo))
   if px then line(px,py,xx,yy,color,2) end;px,py=xx,yy
  end
  box(px-2,py-2,4,4,color,2)
 end
 local function draw(s,target)
  canvas=target;lv_canvas_frame_begin(canvas);lv_canvas_fill_bg(canvas,C.bg,255)
  box(12,9,3,12,C.pink,1);text(23,8,222,TITLES[self.page],C.text);text(253,8,55,U.date(s.now,'%H:%M'),C.sub,12,2)
  line(12,29,308,29)
  local p=self.page;local no_uid=s.uid=='';local private=p==2 or p==5 or p==6 or p==9 or (p==7 and METRICS[self.metric]~='fans')
  if self.editor then
   text(12,43,296,'设置公开账号 UID');text(12,64,296,'左右选位 · 上下修改数字',C.sub)
   for i=1,16 do local x=16+(i-1)*18;if i==self.editor.cursor then box(x-1,96,17,24,0x462334,3)end;text(x+3,102,14,self.editor.digits[i],i==self.editor.cursor and C.pink or C.text)end
   text(12,150,296,'长后倾 / 手柄 A：保存',C.sub);text(12,174,296,'Home / B / 长前倾：取消',C.sub)
   if self.editor.error then text(12,196,296,self.editor.error,C.warn)end
  elseif private and not s.signed_in then
   empty('登录后查看','后倾长按 / 手柄 A 扫码登录')
  elseif no_uid and p~=8 and p~=9 then
   empty('绑定你的 Bilibili','打开控制页面设置 UID 或扫码登录')
  elseif p==1 then
   text(12,41,296,U.str(s.account.name or ('UID '..s.uid),23),C.sub,12,1)
   text(12,66,296,U.fmt(s.fans.count),C.text,40,1,self.large)
   text(12,112,296,'粉丝总数',C.sub,12,1)
   local gain=s.today.fans;local label=gain and ('今日观测 '..(gain>=0 and '+' or '')..U.fmt(gain)) or '等待首个粉丝数据'
   text(12,133,296,s.fans.count and label or safe_status(s,'fans'),C.pink,12,1)
   line(12,158,308,158);line(159,171,159,205)
   text(12,169,138,'今日观测播放',C.sub);number(12,185,138,s.today.view,20)
   text(174,169,134,'直播状态',C.sub);text(174,191,134,(s.live.status==1 and '正在直播' or s.live.status==2 and '轮播中' or '未开播'),s.live.status==1 and C.pink or C.text)
  elseif p==2 then
   local vals=self.creator_latest and (s.creator.latest or {}) or s.today
   text(12,40,296,self.creator_latest and '最近日统计 · 接口延迟更新' or ('今日观测 · 自 '..(s.today.since and U.date(s.today.since,'%H:%M') or '--:--')),C.sub)
   for i,k in ipairs({'view','like','fav','coin'}) do local x=i%2==1 and 12 or 163;local y=i<3 and 62 or 128
    panel(x,y,145,60);text(x+10,y+7,125,LABELS[k],C.sub);number(x+10,y+27,125,vals[k],24,i==1 and C.pink or C.text)
   end
   text(12,196,296,self.creator_latest and 'A / 后倾长按：今日观测' or 'A / 后倾长按：最近日统计',C.sub)
  elseif p==3 then
   local post=s.posts[self.index];if not post then empty('暂无投稿',safe_status(s,'posts'))
   else
    text(12,40,220,post.pubtime and U.date(post.pubtime) or '最新投稿',C.sub);text(262,40,46,self.index..'/'..#s.posts,C.sub,12,2)
    panel(12,62,296,78)
    if post.cover_path and file.exists(post.cover_path) then lv_canvas_draw_img(canvas,12,62,'S:'..post.cover_path:sub(4),{opa=255})
    else text(28,80,264,U.str(post.title,38),C.text) end
    box(249,121,54,16,0x111419,2);text(251,120,49,post.duration or '',C.text,12,2)
    text(12,147,296,U.str(post.title,42),C.text)
    line(12,186,308,186);text(12,195,98,'播 '..U.short(post.view),C.sub);text(115,195,90,'赞 '..U.short(post.like),C.sub);text(213,195,95,'币 '..U.short(post.coin),C.sub)
   end
  elseif p==4 then
   text(12,40,296,U.str(s.live.name or s.account.name or '我的直播间',23),C.sub)
   if s.live.status==1 then
    box(12,65,296,83,0x27131d,6);text(24,73,256,'● 正在直播',C.pink);text(24,97,265,U.str(s.live.title,40));text(12,160,140,'直播人气',C.sub);number(12,180,145,s.live.popularity,24,C.pink)
    text(174,160,134,'开播时间',C.sub);local t=tonumber(s.live.started);text(174,185,134,t and t>0 and U.date(t,'%H:%M') or U.str(s.live.started or '--',16))
   else empty(s.live.status==2 and '正在轮播' or '还没开播',s.live.title~='' and U.str(s.live.title,40) or safe_status(s,'live')) end
  elseif p==5 then
   local m=s.messages;local sum,known=0,0;for _,k in ipairs({'reply','at','like','system','private'}) do if tonumber(m[k]) then sum=sum+m[k];known=known+1 end end
   text(12,40,160,known<5 and '未读消息 · 部分待更新' or '全部未读消息',C.sub);text(186,37,122,U.short(known>0 and sum or nil),C.pink,28,2)
   for i,row in ipairs({{'回复我的','reply'},{'@ 我的','at'},{'收到的赞','like'},{'系统通知','system'},{'私信','private'}}) do local y=77+(i-1)*27
    text(12,y,188,row[1],C.sub);text(211,y,97,U.short(m[row[2]]),C.text,12,2);if i<5 then line(12,y+21,308,y+21)end
   end
  elseif p==6 then
   local f=s.feed[self.index];if not f then empty('暂无关注动态',safe_status(s,'feed'))
   else
    text(12,41,238,U.str(f.name,19),C.pink);text(250,41,58,self.index..'/'..#s.feed,C.sub,12,2)
    local published=tonumber(f.time) or 0
    text(12,62,296,(published>0 and U.date(published,'%m-%d %H:%M') or '')..' '..U.str(f.action,10),C.sub)
    line(12,84,308,84)
    if f.cover_path and file.exists(f.cover_path)then
     lv_canvas_draw_img(canvas,12,98,'S:'..f.cover_path:sub(4),{opa=255});text(112,97,196,U.str(f.text,66))
    else text(12,97,296,U.str(f.text,90))end
    line(12,184,308,184)
    text(12,195,296,'转 '..U.short(f.share)..'   评 '..U.short(f.reply)..'   赞 '..U.short(f.like),C.sub)
   end
  elseif p==7 then
   local key=METRICS[self.metric];local all=s.trends[key] or {};local points={};local sum=0
   for i=math.max(1,#all-self.period+1),#all do points[#points+1]=all[i];sum=sum+all[i].value end
   text(12,39,203,LABELS[key]..'趋势'..(key=='fans' and ' · 观测值' or ''),C.sub);box(247,38,61,20,0x462334,4);text(249,40,57,self.period..' 日',C.pink,12,1)
   number(12,66,210,#points>0 and sum or nil,28);text(219,80,90,#points..' 天合计',C.sub,12,2)
   chart(points,18,112,284,63,key=='view' and C.blue or C.pink)
   if #points>0 then text(16,180,102,U.date(points[1].ts,'%m-%d'),C.sub);text(204,180,102,U.date(points[#points].ts,'%m-%d'),C.sub,12,2) end
   text(12,201,296,'上下换指标 · A / 长后倾换周期',C.sub)
  elseif p==9 then
   local v=(s.recent or {})[self.index]
   if not v then empty('暂无观看记录',safe_status(s,'recent'))
   else
    text(12,41,235,U.str(v.author~='' and v.author or '账号观看历史',19),C.pink);text(253,41,55,self.index..'/'..#s.recent,C.sub,12,2)
    if v.pic and v.pic~=''then
     panel(12,66,112,63)
     if v.cover_path and file.exists(v.cover_path)then lv_canvas_draw_img(canvas,12,66,'S:'..v.cover_path:sub(4),{opa=255})else text(17,88,102,'封面加载中',C.sub,12,1)end
     text(135,66,173,U.str(v.title,53))
    else text(12,66,296,U.str(v.title,80))end
    text(12,141,296,'观看于 '..U.date(v.view_at,'%m-%d %H:%M'),C.sub)
    box(12,169,296,4,C.panel,2);box(12,169,math.max(1,math.floor(296*math.min(1,(v.progress or 0)/math.max(1,v.duration or 0)))),4,C.pink,2)
    text(12,188,200,v.finished and '已看完' or ('已看 '..U.duration(v.progress)),C.sub);text(218,188,90,U.duration(v.duration),C.sub,12,2)
   end
  else
   local q=s.qr;local status=q.status
   if status=='success' and s.signed_in then
    text(12,44,296,U.str(s.account.name or 'Bilibili',24));text(12,65,296,'已登录 · 上下选择，A / 长后倾确认',C.sub)
    for i,label in ipairs({'查看我的数据','重新扫码登录','退出本机登录'})do local y=95+(i-1)*32;if i==self.account_selection then box(12,y-3,296,27,0x462334,4)end;text(23,y,275,(i==self.account_selection and '› ' or '  ')..label,i==self.account_selection and C.pink or C.text)end
   elseif q.matrix and (status=='waiting' or status=='scanned') then
    local qr=q.matrix;local scale=3;local originx,originy=74,35;box(originx,originy,171,171,0xffffff,4)
    for y=0,qr.size-1 do local x=0;while x<qr.size do
     local idx=y*qr.size+x+1;if qr.bits:sub(idx,idx)=='1' then local start=x;repeat x=x+1;idx=y*qr.size+x+1 until x>=qr.size or qr.bits:sub(idx,idx)~='1';box(originx+12+start*scale,originy+12+y*scale,(x-start)*scale,scale,0x000000) else x=x+1 end
    end end
   elseif status=='generating' or status=='verifying' then empty(status=='generating' and '正在生成二维码…' or '正在验证账号…','请稍候')
   else
    text(12,45,296,status=='expired' and '二维码已过期' or status=='error' and '二维码获取失败' or '绑定你的 Bilibili')
    for i,label in ipairs({'扫码登录 Bilibili','设置公开账号 UID'})do local y=87+(i-1)*36;if i==self.account_selection then box(12,y-3,296,28,0x462334,4)end;text(23,y,276,(i==self.account_selection and '› ' or '  ')..label,i==self.account_selection and C.pink or C.text)end
    text(12,170,296,q.error or '上下选择 · 长后倾 / A 确认',C.sub)
   end
  end
  line(12,217,308,217);local foot=(p==3 or p==6 or p==9) and '上下翻页' or '左右切页'
  if p==8 and s.qr.matrix then text(12,221,296,s.qr.status=='scanned' and '扫码成功 · 请在手机确认' or ('哔哩哔哩扫一扫 · '..math.max(0,(s.qr.expires_at or 0)-s.now)..'s'),s.qr.status=='scanned' and C.green or C.sub,12,1);lv_canvas_frame_end(canvas);return end
  local meta=s.meta[KEYS[p]] or {};if s.network=='offline' then foot='离线缓存' elseif meta.status=='error' and p~=8 then foot=meta.updated and '数据未更新' or '接口暂不可用' end
  text(12,221,112,foot,C.sub);for i=1,9 do box(134+(i-1)*6,225,i==p and 5 or 3,3,i==p and C.pink or 0x424955,1) end
  text(243,221,65,string.format('%02d / 09',p),C.sub,12,2)
  lv_canvas_frame_end(canvas)
 end
 function self:render(s)
  if self.stopped then return end
  if self.busy then self.dirty=true;return end
  local count=self.page==3 and #s.posts or self.page==6 and #s.feed or self.page==9 and #(s.recent or {}) or 0;if count>0 and self.index>count then self.index=1 end
  self.dirty=false;local ok,err=pcall(draw,s,self.front);if not ok then pcall(lv_canvas_frame_end,self.front);self.error=tostring(err);return false,err end;self.error=nil;return true
 end
 function self:move(delta,s)
  if self.editor then self.editor.cursor=(self.editor.cursor-1+delta)%16+1;self:render(s);return true end
  if self.stopped or self.busy then return false end
  self.page=(self.page-1+delta)%9+1;self.index=1;self.busy=true;self.dirty=true
  local ok,err=pcall(draw,s,self.back);if not ok then self.busy=false;self.error=tostring(err);pcall(lv_canvas_frame_end,self.back);return false end
  local start=delta>0 and 320 or -320;lv_obj_set_x(self.back,start)
  local function animate(obj,a,b)
   local anim=lv_anim_t();lv_anim_init(anim);lv_anim_set_var(anim,obj);lv_anim_set_exec_cb(anim,lv_obj_set_x);lv_anim_set_values(anim,a,b);lv_anim_set_time(anim,360);lv_anim_set_path_cb(anim,lv_anim_path_ease_out);lv_anim_start(anim)
  end
  animate(self.front,0,-start);animate(self.back,start,0)
  local t=tmr.create();self.anim_timer=t;t:alarm(360,tmr.ALARM_SINGLE,function()
   t:unregister();if self.stopped then return end;self.front,self.back=self.back,self.front;lv_obj_set_x(self.front,0);lv_obj_set_x(self.back,320);self.busy=false;self.dirty=true;self.anim_timer=nil
  end);return true
 end
 function self:jump(page,s)if self.busy then return false end;self.editor=nil;self.page=page;self.index=1;self.account_selection=1;return self:render(s)end
 function self:item(delta,s)
  if self.busy then return end
  if self.editor then local e=self.editor;e.digits[e.cursor]=tostring((tonumber(e.digits[e.cursor])-delta)%10);e.error=nil;self:render(s);return end
  if self.page==8 and not s.qr.matrix and s.qr.status~='generating' and s.qr.status~='verifying' then local count=s.signed_in and 3 or 2;self.account_selection=(self.account_selection-1+delta)%count+1;self:render(s);return end
  local count=self.page==3 and #s.posts or self.page==6 and #s.feed or self.page==9 and #(s.recent or {}) or 0
  if count>0 then self.index=(self.index-1+delta)%count+1 elseif self.page==7 then self.metric=(self.metric-1+delta)%#METRICS+1 end
  self:render(s)
 end
 function self:capture()
  if self.busy then return false,'画面切换中' end
  local snap,err=lv_snapshot_take(self.front,LV_IMG_CF_TRUE_COLOR);if not snap then return false,err end
  local ok,result=pcall(lv_snapshot_save_to_png,snap,dir..'/screen.png');lv_snapshot_free(snap);return ok and result or false
 end
 function self:edit_uid(uid,s)
  local raw=tostring(uid or ''):gsub('%D','');raw=string.rep('0',math.max(0,16-#raw))..raw;self.editor={cursor=16,digits={}}
  for i=1,16 do self.editor.digits[i]=raw:sub(i,i)end;self:render(s)
 end
 function self:stop()
  self.stopped=true;if self.anim_timer then pcall(function()self.anim_timer:unregister()end) end
  if lv_anim_del then pcall(lv_anim_del,self.front,nil);pcall(lv_anim_del,self.back,nil) end
  pcall(lv_obj_clean,root);pcall(lv_font_free,self.font);pcall(lv_font_free,self.large)
 end
 return self
end
return UI
