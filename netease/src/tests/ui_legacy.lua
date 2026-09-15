-- Pre-redesign UI retained as a local rollback reference; not deployed.
return function()
  local U={fonts={},cache={}}
  local root=lv_scr_act();lv_obj_clean(root);local part=LV_PART_MAIN or 0
  lv_obj_set_style_bg_color(root,0,part);lv_obj_set_style_bg_opa(root,255,part)
  local function font(name,fallback)
    local ok,f=pcall(lv_font_load,'/sd/apps/netease/font/'..name..'.bin')
    if ok and f and f~=0 then U.fonts[#U.fonts+1]=f;return f end
    return fallback
  end
  local small=font('ui13',LV_FONT_MONTSERRAT_14)
  local large=font('ui24',small)
  local medium=font('ui18',small)
  local function label(x,y,w,f,color)
    local o=lv_label_create(root);lv_obj_set_pos(o,x,y);lv_obj_set_width(o,w)
    lv_obj_set_style_text_font(o,f,part);lv_obj_set_style_text_color(o,color,part)
    if lv_label_set_long_mode then lv_label_set_long_mode(o,LV_LABEL_LONG_DOT or 1)end
    return o
  end
  U.brand=label(14,10,292,small,0xEC4141)
  U.title=label(14,44,292,large,0xFFFFFF)
  U.sub=label(14,78,292,small,0xAAAAAA)
  U.lines={}
  for i=1,4 do U.lines[i]=label(14,100+(i-1)*25,292,medium,0xDDDDDD)end
  U.status=label(14,202,292,small,0xAAAAAA)
  U.hint=label(14,222,292,small,0x777777)
  local function text(o,v)
    v=tostring(v or '')
    if U.cache[o]~=v then lv_label_set_text(o,v);U.cache[o]=v end
  end
  local function hide(o,yes)
    if yes then lv_obj_add_flag(o,LV_OBJ_FLAG_HIDDEN)else lv_obj_clear_flag(o,LV_OBJ_FLAG_HIDDEN)end
  end
  function U.qr(url,native)
    if U.canvas then lv_obj_del(U.canvas);U.canvas=nil end
    if not url then return end
    local size,pixels=native.qr(url)
    if not size then return nil,pixels end
    local scale=math.floor(154/(size+8));if scale<1 then return nil,'二维码过大'end
    local width=(size+8)*scale
    U.canvas=lv_canvas_create(root,width,width,LV_IMG_CF_TRUE_COLOR)
    lv_obj_set_pos(U.canvas,math.floor((320-width)/2),43)
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
    local login=S.page=='login'
    if U.canvas then hide(U.canvas,not login)end
    hide(U.title,login);hide(U.sub,login)
    for _,o in ipairs(U.lines)do hide(o,login)end
    text(U.brand,login and '网易云音乐 / 扫码登录' or S.page=='player' and '网易云音乐 / 正在播放' or '网易云音乐 / 音乐库')
    text(U.status,A.error~='' and A.error or A.message or '')
    if login then text(U.hint,'网易云 App 扫码 · Home 刷新 · 长按退出');return end
    local lines={'','','',''}
    if S.page=='player'then
      local song=A.song or {}
      text(U.title,song.name or '还没有播放歌曲')
      text(U.sub,A.artist or '上下进入音乐库')
      local state=A.player.status
      local names={idle='待播放',playing='正在播放',paused='已暂停',buffering='缓冲中',error='播放失败',ended='播放结束'}
      lines[1]=names[state] or state
      lines[2]=A.lyric or ''
      local pos=math.floor(A.player.position or 0);local total=math.floor((song.dt or song.duration or 0)/1000)
      lines[3]=string.format('%02d:%02d / %02d:%02d',pos//60,pos%60,total//60,total%60)
      lines[4]=string.format('%d / %d  ·  MP3 普通音质',S.index,#S.queue)
      text(U.hint,'左右切歌 · 上下音乐库 · Home 暂停')
    elseif S.page=='library'then
      text(U.title,({'我的歌单','收藏','每日推荐'})[S.tab])
      text(U.sub,string.format('%d / 3  ·  %s',S.tab,A.nickname or '网易云音乐'))
      lines[2]=({'个人创建与收藏的歌单','我喜欢的音乐','今日为你推荐的歌曲'})[S.tab]
      text(U.hint,'左右换库 · Home 进入 · 上下播放页')
    else
      text(U.title,A.list_title or '歌曲')
      text(U.sub,string.format('%d / %d  ·  左右选择',#S.items>0 and S.cursor or 0,#S.items))
      local start=math.floor((S.cursor-1)/4)*4+1
      for i=1,4 do local idx=start+i-1;local item=S.items[idx]
        lines[i]=item and ((idx==S.cursor and '> ' or '  ')..(item.name or '未命名'))or ''
      end
      text(U.hint,'左右选择 · Home 确认 · 上下返回')
    end
    for i,o in ipairs(U.lines)do text(o,lines[i])end
  end
  function U.close()lv_obj_clean(root);for _,f in ipairs(U.fonts)do pcall(lv_font_free,f)end end
  return U
end
