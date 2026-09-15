local M={}
function M.new(A,S,player,provider,apiNet,streamNet,json,dir)
  local W={routes={}}
  local View=dofile(dir..'/ui_view.lua')
  local token=tostring(tmr.now())..'-'..tostring(math.random(1,0x7fffffff))
  local function response(doc,status)
    return {status=status or '200 OK',type='application/json; charset=utf-8',
      headers={['Cache-Control']='no-store',['X-Content-Type-Options']='nosniff'},body=json.encode(doc)}
  end
  local function route(method,path,fn)
    httpd.dynamic(method,path,fn);W.routes[#W.routes+1]={method,path}
  end
  local function snapshot()
    local api_state,stream_state=apiNet.state(),streamNet.state()
    api_state.error=api_state.error~=''and 'HTTP transport error'or ''
    stream_state.error=stream_state.error~=''and 'HTTP transport error'or ''
    local song=type(A.song)=='table'and A.song or {}
    local album=type(song.al)=='table'and song.al or type(song.album)=='table'and song.album or {}
    local cover=View.song_cover(song)or ''
    if not cover:match('^https?://')then cover=''end
    local items={}
    for i,item in ipairs(S.items or {})do
      if i>22 then break end
      items[#items+1]={index=i,name=item.name or '',page=item.page_offset~=nil or item.playlist_offset~=nil}
    end
    return {alive=A.alive,page=S.page,tab=S.tab,status=player.status,error=A.error,message=A.message,
      logged_in=A.uid~=nil,login_status=A.login and A.login.status or 'idle',login_mode=A.login and A.login.mode or 'qq',
      login_revision=A.login and A.login.generation or 0,ui_ready=A.ui and A.ui.ready or false,ui_version=3,
      account=A.account or {name='游客'},catalog=A.catalog and A.catalog.state()or {},
      ui_cover_error=A.ui and A.ui.cover_error or '',
      covers=A.covers and A.covers.state(View.cover(S,A))or {},
      device_time=A.clock_text or '--:--',clock_dst=A.clock_dst,
      ui_fonts=A.ui and #A.ui.fonts or 0,
      stats=player.stats or {},api=api_state,stream=stream_state,
      provider=provider.diagnostics,token=token,ready=A.control~=nil,revision=A.list_revision,
      config=A.config,controller=A.input and A.input.connected or false,
      list={title=A.list_title or '',items=items,cursor=S.cursor,tab_count=S.tab_count or 2},
      song={id=song.id or 0,name=song.name or '',artist=A.artist or '',album=album.name or '',
        cover=cover,duration=(tonumber(song.dt or song.duration)or 0)/1000},
      position=player.position or 0,lyric=A.lyric or '',queue_index=S.index,queue_count=#S.queue}
  end
  httpd.start({webroot=dir,auto_index=httpd.INDEX_NONE,max_handlers=16})
  route(httpd.GET,'/qqmusic/',function()
    return {status='200 OK',type='text/html; charset=utf-8',
      headers={['Cache-Control']='no-store',['X-Content-Type-Options']='nosniff'},
      body=file.getcontents(dir..'/control.html')or 'Missing control.html'}
  end)
  route(httpd.GET,'/qqmusic/status',function()return response(snapshot())end)
  route(httpd.GET,'/qqmusic/qr.png',function()
    local raw=A.login and A.login.image
    return {status=raw and '200 OK'or '404 Not Found',type=raw and raw:sub(1,2)=='\255\216'and 'image/jpeg'or 'image/png',
      headers={['Cache-Control']='no-store',['X-Content-Type-Options']='nosniff'},body=raw or ''}
  end)
  route(httpd.GET,'/qqmusic/lyrics',function()
    return response({song_id=A.song and A.song.id or 0,lines=A.lyrics or {}})
  end)
  route(httpd.POST,'/qqmusic/control',function(req)
    if not A.alive or not A.control then return response({ok=false,error='App 尚未就绪'},'503 Service Unavailable')end
    local raw=req.getbody and req.getbody()or ''
    if type(raw)~='string'or #raw>4096 then return response({ok=false,error='请求过大'},'413 Payload Too Large')end
    local parsed,doc=pcall(json.decode,raw)
    if not parsed or type(doc)~='table'then return response({ok=false,error='无效 JSON'},'400 Bad Request')end
    -- Same-origin status fetch supplies an ephemeral anti-CSRF token.
    -- This is not account authentication: use only on a trusted LAN.
    if doc.token~=token then return response({ok=false,error='页面已过期，请刷新'},'403 Forbidden')end
    local good,ok,err=pcall(A.control,doc)
    if not good then return response({ok=false,error='控制请求处理失败'},'500 Internal Server Error')end
    if not ok then return response({ok=false,error=err or '操作失败'},'400 Bad Request')end
    return response({ok=true})
  end)
  function W.close()
    for _,r in ipairs(W.routes)do pcall(httpd.unregister,r[1],r[2])end
  end
  return W
end
return M
