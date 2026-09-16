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
    local song=type(A.song)=='table'and A.song or {}
    local album=type(song.al)=='table'and song.al or type(song.album)=='table'and song.album or {}
    local cover=View.song_cover(song)or ''
    if not cover:match('^https?://')then cover=''end
    local list=A.web_list and A.web_list.snapshot(song.id)or {items={},ready=false,revision=0,tab=S.tab}
    return {alive=A.alive,page=S.page,tab=S.tab,status=player.status,error=A.error,message=A.message,
      logged_in=A.uid~=nil,ui_ready=A.ui and A.ui.ready or false,ui_version=15,
      account=A.uid and A.account or nil,play_mode=A.config and A.config.play_mode or 'ordered',
      libraries=A.library_cache and A.library_cache.state()or {},
      lyric_status=A.lyric_loader and A.lyric_loader.status or 'idle',
      lyric_attempts=A.lyric_loader and A.lyric_loader.attempts or 0,
      lyric_generation=A.lyric_loader and A.lyric_loader.generation or 0,
      ui_cover_error=A.ui and A.ui.cover_error or '',
      boot_icon_loaded=A.ui and A.ui.boot_icon_loaded or false,boot_icon_error=A.ui and A.ui.boot_icon_error or '',
      covers=A.covers and A.covers.state(View.cover(S,A))or {},
      device_time=A.clock_text or '--:--',clock_dst=A.clock_dst,
      ui_fonts=A.ui and #A.ui.fonts or 0,
      stats=player.stats or {},api=apiNet.state(),stream=streamNet.state(),
      playback_timing=player.metrics or {},url_resolution=A.resolver and A.resolver.state()or {},
      playback_phase=A.resolver and A.resolver.foreground and 'resolving'or (player.metrics and player.metrics.phase or 'idle'),
      url_request=A.url_provider and A.url_provider.diagnostics or {},
      metadata_request=A.meta_provider and A.meta_provider.diagnostics or {},
      provider=provider.diagnostics,token=token,ready=A.control~=nil,revision=A.view_generation,
      config=A.config,controller=A.input and A.input.connected or false,
      list=list,
      song={id=song.id or 0,name=song.name or '',artist=A.artist or '',album=album.name or '',
        cover=cover,duration=(tonumber(song.dt or song.duration)or 0)/1000},
      position=player.position or 0,lyric=A.lyric or '',queue_index=S.index,queue_count=#S.queue}
  end
  httpd.start({webroot=dir,auto_index=httpd.INDEX_NONE,max_handlers=16})
  route(httpd.GET,'/netease/',function()
    return {status='200 OK',type='text/html; charset=utf-8',
      headers={['Cache-Control']='no-store',['X-Content-Type-Options']='nosniff'},
      body=file.getcontents(dir..'/control.html')or 'Missing control.html'}
  end)
  route(httpd.GET,'/netease/status',function()return response(snapshot())end)
  route(httpd.GET,'/netease/lyrics',function()
    local loader=A.lyric_loader
    return response({song_id=A.song and A.song.id or 0,lines=loader and loader.lines or {},
      status=loader and loader.status or 'idle',generation=loader and loader.generation or 0})
  end)
  route(httpd.POST,'/netease/control',function(req)
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
