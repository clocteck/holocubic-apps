return function(A)
  local U={labels={},fonts={},last={}}
  local root=lv_scr_act();lv_obj_clean(root)
  local part=LV_PART_MAIN or 0
  local function call(fn,...)if fn then return fn(...) end end
  local function reset(o)
    call(lv_obj_remove_style_all,o);lv_obj_set_style_pad_all(o,0,part);lv_obj_set_style_border_width(o,0,part)
    if LV_OBJ_FLAG_SCROLLABLE then lv_obj_clear_flag(o,LV_OBJ_FLAG_SCROLLABLE) end
  end
  lv_obj_set_style_bg_color(root,0x000000,part);lv_obj_set_style_bg_opa(root,255,part)
  local function font(path,fallback)
    local ok,f=pcall(lv_font_load,path)
    if ok and f and f~=0 then U.fonts[#U.fonts+1]=f;return f end
    return fallback
  end
  local small=font('/sd/apps/radio/font/ui13.bin',LV_FONT_MONTSERRAT_14)
  local large=font('/sd/apps/radio/font/ui24.bin',small)
  local function label(k,x,y,w,text,f,color)
    local o=lv_label_create(root);reset(o);lv_obj_set_pos(o,x,y);lv_obj_set_width(o,w)
    lv_obj_set_style_text_font(o,f or small,part);lv_obj_set_style_text_color(o,color or 0xEEEEEE,part)
    call(lv_label_set_long_mode,o,LV_LABEL_LONG_DOT or 1)
    lv_label_set_text(o,text);U.labels[k]=o;U.last[k]=text;return o
  end
  local function box(x,y,w,h,color)
    local o=lv_obj_create(root);reset(o);lv_obj_set_pos(o,x,y);lv_obj_set_size(o,w,h);lv_obj_set_style_bg_color(o,color,part);lv_obj_set_style_bg_opa(o,255,part);return o
  end
  label('brand',16,12,120,'RADIO',small,0xFFA857)
  label('clock',255,12,49,'--:--',small,0x9A9A9A)
  call(lv_obj_set_style_text_align,U.labels.clock,LV_TEXT_ALIGN_RIGHT or 2,part)
  box(16,36,288,1,0x292929)
  local badge=box(16,50,36,36,0x21170E);call(lv_obj_set_style_radius,badge,6,part)
  label('badge',22,52,28,'R',large,0xFFA857)
  U.dot=box(66,64,6,6,0x999999);call(lv_obj_set_style_radius,U.dot,3,part)
  label('status',80,57,112,'',small,0xFFA857)
  label('index',196,57,108,'01 / 20',small,0x777777)
  call(lv_obj_set_style_text_align,U.labels.index,LV_TEXT_ALIGN_RIGHT or 2,part)
  label('station',16,98,288,'网络收音机',large)
  label('title',16,137,288,'',small,0x999999)
  label('volumeLabel',16,177,180,'音量',small,0x999999)
  label('volume',263,177,41,'25%',small,0xFFA857)
  call(lv_obj_set_style_text_align,U.labels.volume,LV_TEXT_ALIGN_RIGHT or 2,part)
  box(16,201,288,3,0x252525);U.volume=box(16,201,72,3,0xFFA857)
  label('hint',16,219,288,'',small,0x666666)
  U.list=lv_obj_create(root);reset(U.list);lv_obj_set_pos(U.list,0,38);lv_obj_set_size(U.list,320,171);lv_obj_set_style_bg_color(U.list,0,part);lv_obj_set_style_bg_opa(U.list,255,part)
  U.rows={}
  for i=1,6 do
    local row=lv_label_create(U.list);reset(row);lv_obj_set_pos(row,16,(i-1)*27+7);lv_obj_set_width(row,290);lv_obj_set_style_text_font(row,small,part);call(lv_label_set_long_mode,row,LV_LABEL_LONG_CLIP or 4);U.rows[i]=row
  end
  lv_obj_add_flag(U.list,LV_OBJ_FLAG_HIDDEN)
  local function text(k,v)if U.last[k]~=v then lv_label_set_text(U.labels[k],v);U.last[k]=v end end
  local words={
    ['zh-CN']={playing='直播',connecting='连接中',buffering='缓冲中',waiting='等待服务',idle='已停止',error='播放失败',news='新闻',music='音乐',traffic='交通',finance='财经',custom='自定义',volume='音量',hint='左右切台  上下音量  Menu列表',list='上下选择  A播放  Menu返回'},
    ['zh-TW']={playing='直播',connecting='連線中',buffering='緩衝中',waiting='等待服務',idle='已停止',error='播放失敗',news='新聞',music='音樂',traffic='交通',finance='財經',custom='自訂',volume='音量',hint='左右切台  上下音量  Menu列表',list='上下選擇  A播放  Menu返回'},
    en={playing='Live',connecting='Connecting',buffering='Buffering',waiting='Waiting',idle='Stopped',error='Playback error',news='News',music='Music',traffic='Traffic',finance='Finance',custom='Custom',volume='Volume',hint='L/R: station  Up/down: volume',list='Up/down: select  A: play  Menu: back'},
    ja={playing='ライブ',connecting='接続中',buffering='読込中',waiting='待機中',idle='停止中',error='再生エラー',news='ニュース',music='音楽',traffic='交通',finance='経済',custom='カスタム',volume='音量',hint='左右: 選局  上下: 音量  Menu: 一覧',list='上下: 選択  A: 再生  Menu: 戻る'}
  }
  U.clock_text='--:--'
  local function clock()
    if not time or not time.get or not time.getlocal then return end
    local second=tmr.time()
    if second==U.clock_second then return end
    U.clock_second=second
    local epoch=time.get();local minute=math.floor((epoch or 0)/60)
    if minute==U.clock_minute then return end
    U.clock_minute=minute
    local d=time.getlocal()
    U.clock_text=d and d.year>=2020 and string.format('%02d:%02d',d.hour,d.min) or '--:--'
    text('clock',U.clock_text)
  end
  function U.update()
    local station=A.stations[A.index] or {}
    local w=words[A.language] or words.en
    text('status',w[A.status] or A.status);text('index',string.format('%02d/%02d',A.index,#A.stations))
    local name=station.name or 'Radio'
    text('station',name);text('badge',name:match('^[%z\1-\127\194-\244][\128-\191]*') or 'R')
    text('title',(A.error and A.error~='' and A.error) or (A.storage_error and A.storage_error~='' and A.storage_error) or (A.title and A.title~='' and A.title) or w[station.group] or '')
    local color=A.status=='playing' and 0xFFA857 or A.status=='error' and 0xFF9999 or 0x999999
    if U.status_color~=color then lv_obj_set_style_bg_color(U.dot,color,part);lv_obj_set_style_text_color(U.labels.status,color,part);U.status_color=color end
    text('volumeLabel',w.volume);text('volume',A.volume..'%')
    if U.last_volume~=A.volume then lv_obj_set_width(U.volume,math.floor(A.volume*2.88));U.last_volume=A.volume end
    text('hint',A.list_open and w.list or w.hint);clock()
    if U.list_open~=A.list_open then
      if A.list_open then lv_obj_clear_flag(U.list,LV_OBJ_FLAG_HIDDEN) else lv_obj_add_flag(U.list,LV_OBJ_FLAG_HIDDEN) end
      U.list_open=A.list_open
    end
    if A.list_open then
      local start=math.floor((A.cursor-1)/6)*6+1
      for i=1,6 do local n=start+i-1;local s=A.stations[n];local t=s and string.format('%s %02d  %s',n==A.cursor and '>' or ' ',n,s.name) or '';if U.last['row'..i]~=t then lv_label_set_text(U.rows[i],t);lv_obj_set_style_text_color(U.rows[i],n==A.cursor and 0xFFA857 or 0xAAAAAA,part);U.last['row'..i]=t end end
    end
  end
  function U.close()lv_obj_clean(root);for _,f in ipairs(U.fonts) do pcall(lv_font_free,f) end end
  U.update();return U
end
