-- Splash first, then one full font per timer turn; only 13/16 px Chinese.
return function()
  local DIR='/sd/apps/netease/'
  local U={fonts={},cache={},hidden={},colors={},stage=0,ready=false}
  local root=lv_scr_act();lv_obj_clean(root);local part=LV_PART_MAIN or 0
  lv_obj_set_style_bg_color(root,0,part);lv_obj_set_style_bg_opa(root,255,part)
  lv_obj_clear_flag(root,LV_OBJ_FLAG_SCROLLABLE)
  local View=dofile(DIR..'ui_view.lua');local About=dofile(DIR..'about.lua')
  local Library=dofile(DIR..'library.lua')
  local function font(name,fallback)
    local ok,f=pcall(lv_font_load,DIR..'font/'..name..'.bin')
    if ok and f and f~=0 then U.fonts[#U.fonts+1]=f;return f end
    return fallback
  end
  local function label(x,y,w,f,color,h)
    local o=lv_label_create(root);lv_obj_set_pos(o,x,y);lv_obj_set_width(o,w)
    lv_obj_set_style_text_font(o,f,part);lv_obj_set_style_text_color(o,color,part)
    lv_label_set_long_mode(o,LV_LABEL_LONG_DOT or 1)
    if h then lv_obj_set_height(o,h)end
    lv_label_set_text(o,'');return o
  end
  local function text(o,v)
    v=tostring(v or '')
    if U.cache[o]~=v then lv_label_set_text(o,v);U.cache[o]=v end
  end
  local function hide(o,yes)
    yes=not not yes
    if U.hidden[o]==yes then return end
    U.hidden[o]=yes
    if yes then lv_obj_add_flag(o,LV_OBJ_FLAG_HIDDEN)else lv_obj_clear_flag(o,LV_OBJ_FLAG_HIDDEN)end
  end
  local function color(o,value)
    if U.colors[o]==value then return end
    lv_obj_set_style_text_color(o,value,part);U.colors[o]=value
  end
  local function box(x,y,w,h,color)
    local o=lv_obj_create(root);lv_obj_remove_style_all(o)
    lv_obj_set_pos(o,x,y);lv_obj_set_size(o,w,h)
    lv_obj_set_style_bg_color(o,color,part);lv_obj_set_style_bg_opa(o,255,part)
    lv_obj_clear_flag(o,LV_OBJ_FLAG_SCROLLABLE);return o
  end
  local bootfont=font('boot13',LV_FONT_MONTSERRAT_14)
  local logo=lv_img_create(root);lv_img_set_src(logo,DIR..'main.png')
  lv_img_set_pivot(logo,0,0);lv_img_set_zoom(logo,42);lv_obj_set_pos(logo,120,64)
  local bootlabel=label(0,165,320,bootfont,0xAAAAAA)
  lv_obj_set_style_text_align(bootlabel,LV_TEXT_ALIGN_CENTER,part);text(bootlabel,'启动中…')
  if lv_refr_now then pcall(lv_refr_now,nil)end
  local function build()
    lv_obj_clean(root);U.cache={};U.hidden={};U.colors={};U.page=nil
    U.brand=label(12,9,186,U.small,0xEC4141,18)
    U.badge=label(196,9,112,U.small,0x888891,18)
    lv_obj_set_style_text_align(U.badge,LV_TEXT_ALIGN_RIGHT,part)
    U.artbox=box(12,40,92,92,0x151518)
    U.art=lv_img_create(root);hide(U.art,true);lv_img_set_pivot(U.art,0,0)
    -- ui13 line height is 17px: two title lines fit in 36px, then 4px gap.
    U.title=label(12,139,92,U.small,0xFFFFFF,36)
    lv_label_set_long_mode(U.title,LV_LABEL_LONG_DOT or 1)
    U.sub=label(12,179,92,U.small,0x888891,17)
    U.lines={}
    for i=1,5 do
      local y,height=View.lyric_row(i)
      U.lines[i]=label(116,y,192,U.small,0x9999A2,height)
    end
    U.status=label(12,198,296,U.small,0xAAAAAA,18)
    U.rule=box(12,216,296,1,0x252529);U.progress=box(12,216,1,2,0xEC4141)
    U.time=label(12,222,150,U.small,0x777780,17)
    U.hint=label(150,222,158,U.small,0x9999A2,17)
    lv_obj_set_style_text_align(U.hint,LV_TEXT_ALIGN_RIGHT,part)
    U.about={}
    local function about(x,y,w,f,c,h)
      local o=label(x,y,w,f,c,h);U.about[#U.about+1]=o;return o
    end
    U.accountLabel=about(12,33,220,U.small,0x777780,18)
    U.account=about(12,51,220,U.large,0xFFFFFF,22)
    U.accountState=about(240,48,68,U.small,0x99B7A3,18)
    for i,s in ipairs(About.shortcuts)do
      local col=(i-1)%2;local row=math.floor((i-1)/2)
      text(about(12+col*150,82+row*23,148,U.small,i==4 and 0xEE9999 or 0xCCCCD3,21),s[1]..' '..s[2])
    end
    text(about(12,155,296,U.small,0xDDDDDD,20),'开源 '..About.github_label)
    for i,v in ipairs(About.privacy)do text(about(12,179+(i-1)*18,296,U.small,0x888891,18),v)end
    U.ready=true
    if U.pending_qr then U.qr(U.pending_qr.url,U.pending_qr.native)end
  end
  function U.load_next()
    if U.ready then return true end
    U.stage=U.stage+1
    if U.stage==1 then U.small=font('ui13',LV_FONT_MONTSERRAT_14)
    elseif U.stage==2 then U.large=font('ui16',U.small)
    else build()end
    return U.ready
  end
  function U.qr(url,native)
    U.pending_qr=url and {url=url,native=native}or nil
    if not U.ready then return true end
    if U.canvas then lv_obj_del(U.canvas);U.canvas=nil end
    if not url then return true end
    local size,pixels=native.qr(url)
    if not size then return nil,pixels end
    local scale=math.floor(154/(size+8));if scale<1 then return nil,'二维码过大'end
    local width=(size+8)*scale
    U.canvas=lv_canvas_create(root,width,width,LV_IMG_CF_TRUE_COLOR)
    lv_obj_set_pos(U.canvas,math.floor((320-width)/2),38)
    lv_canvas_frame_begin(U.canvas);lv_canvas_fill_bg(U.canvas,0xFFFFFF,255)
    for y=0,size-1 do
      local x=0
      while x<size do
        if pixels:byte(y*size+x+1)==1 then
          local start=x;repeat x=x+1 until x>=size or pixels:byte(y*size+x+1)~=1
          lv_canvas_draw_rect(U.canvas,(start+4)*scale,(y+4)*scale,(x-start)*scale,scale,0,255)
        else x=x+1 end
      end
    end
    lv_canvas_frame_end(U.canvas);return true
  end
  function U.render(S,A)
    if not U.ready then return end
    local login=S.page=='login';local playing=S.page=='player';local about=S.page=='about'
    local library=S.page=='library'
    local layout_changed=U.page~=S.page;U.page=S.page
    for _,o in ipairs(U.about)do hide(o,not about)end
    for _,o in ipairs({U.title,U.artbox})do hide(o,login or about)end
    hide(U.sub,not playing)
    for _,o in ipairs(U.lines)do hide(o,login or about)end
    hide(U.progress,not playing)
    if U.canvas then hide(U.canvas,not login)end
    text(U.brand,login and '扫码登录' or playing and '网易云音乐' or about and About.title or library and '音乐库' or A.list_title or '歌曲')
    -- Compute final values once: never clear a label before restoring its text.
    text(U.badge,about and About.badge or playing and ((A.clock_text or '--:--')..' · '..View.rate(A.player.stats)) or
      login and '' or library and (S.tab..' / 3')or
      string.format('%d / %d',#S.items>0 and S.cursor or 0,#S.items))
    text(U.status,about and ''or (A.error~=''and A.error or A.message or ''))
    local raw,item;if A.covers then raw,item=A.covers.get(View.cover(S,A))end
    if login or about then hide(U.art,true)end
    local cover_changed=raw~=U.artdata
    if cover_changed then
      -- Queue hide BEFORE replacing/clearing the source. The GUI may draw
      -- between queued commands; never expose a visible source-less image.
      hide(U.art,true)
      local src=raw;U.cover_error=''
      if raw and item.format=='png'then
        local ok,result,err=pcall(A.audio.png_image,raw)
        src=ok and result or nil
        if not src then U.cover_error=ok and (err or 'PNG image unavailable')or 'PNG image handle failed' end
      end
      lv_img_set_src(U.art,src)
      U.artsource=src
      -- lv_img_set_src resets the pivot to the new image center. Restore it
      -- AFTER every source change so scaling cannot shift the cover down/right.
      if raw then lv_img_set_pivot(U.art,0,0)end
      U.artdata=raw
    end
    if not login and not about then
      local size=playing and 92 or 128
      if layout_changed then lv_obj_set_pos(U.artbox,12,40);lv_obj_set_size(U.artbox,size,size)end
      if raw and (cover_changed or layout_changed)then
        local zoom=math.floor(size*256/math.max(item.width,item.height))
        lv_img_set_zoom(U.art,zoom)
        lv_obj_set_pos(U.art,12+math.floor((size-item.width*zoom/256)/2),40+math.floor((size-item.height*zoom/256)/2))
      end
    end
    if login then text(U.hint,'Home 刷新二维码');text(U.time,'长按 Home 退出');return end
    if about then
      text(U.accountLabel,'当前账户')
      text(U.account,A.nickname or '未登录');text(U.accountState,A.uid and '已登录'or '未登录')
      text(U.time,'上下切页');text(U.hint,'Home 回到播放');return
    end
    if playing then
      local song=A.song or {};local state=A.player.status
      if layout_changed then
        lv_obj_set_pos(U.title,12,139);lv_obj_set_size(U.title,92,36)
        lv_obj_set_pos(U.sub,12,179);lv_obj_set_width(U.sub,92)
      end
      text(U.title,song.name or '还没有歌曲');text(U.sub,A.artist or '先到音乐库选歌')
      local lines=View.lyrics(A.lyrics,A.player.position or 0,A.lyric_status)
      for i,o in ipairs(U.lines)do
        if layout_changed then
          local y,height=View.lyric_row(i)
          lv_obj_set_pos(o,116,y);lv_obj_set_size(o,192,height)
          lv_obj_set_style_text_align(o,LV_TEXT_ALIGN_CENTER,part)
          lv_obj_set_style_text_font(o,i==3 and U.large or U.small,part)
        end
        color(o,i==3 and 0xFFFFFF or (i==1 or i==5)and 0x55555E or 0x9999A2)
        text(o,lines[i])
      end
      local pos=math.floor(A.player.position or 0);local total=math.floor((song.dt or song.duration or 0)/1000)
      text(U.time,string.format('%02d:%02d / %02d:%02d',pos//60,pos%60,total//60,total%60))
      local names={idle='待播放',playing='播放中',paused='已暂停',buffering='缓冲中',error='播放失败',ended='播放结束'}
      text(U.hint,(names[state]or state)..' · Home 暂停')
      local pixels=math.max(1,math.floor(296*math.min(1,total>0 and pos/total or 0)))
      if U.progress_pixels~=pixels then lv_obj_set_width(U.progress,pixels);U.progress_pixels=pixels end
    else
      if layout_changed then lv_obj_set_pos(U.title,12,174);lv_obj_set_size(U.title,296,20)end
      text(U.title,library and Library.titles[S.tab]or (S.items[S.cursor]or {}).name or '暂无项目')
      local start=math.floor((S.cursor-1)/4)*4+1
      for i,o in ipairs(U.lines)do
        if layout_changed then
          lv_obj_set_pos(o,152,43+(i-1)*31);lv_obj_set_size(o,156,25)
          lv_obj_set_style_text_align(o,LV_TEXT_ALIGN_LEFT,part)
          lv_obj_set_style_text_font(o,U.small,part)
        end
        local idx=start+i-1;local selected=not library and idx==S.cursor
        color(o,selected and 0xEC4141 or 0xAAAAAA)
        local item=S.items[idx]
        text(o,library and ({'左右选择音乐库','Home 进入','上下切换页面','',''})[i]or i<=4 and item and ((selected and '> 'or '')..item.name)or '')
      end
      text(U.time,library and '左右选择音乐库'or '左右选择 · 上下返回')
      text(U.hint,'Home 确认')
    end
    -- Reveal only after source, pivot, zoom and placement have been queued.
    hide(U.art,login or about or not U.artsource or (U.cover_error or '')~='')
  end
  function U.close()lv_obj_clean(root);U.artdata=nil;U.artsource=nil;U.pending_qr=nil;for _,f in ipairs(U.fonts)do pcall(lv_font_free,f)end end
  return U
end
