local M={}
function M.new(audio,net,now)
  local P={generation=0,status='idle',error='',paused=false,alive=true,bytes=0,metrics={}}
  local function halt()
    P.generation=P.generation+1;net.cancel();P.pending=nil;P.connection=nil
    P.paused=false
    return audio.close()
  end
  function P.stop()
    P.retry_at=nil;P.urls=nil;P.status='idle';P.error='';P.error_kind=nil
    P.metrics={phase='idle'}
    return halt()
  end
  local start_attempt
  local function fail(msg,retryable,kind)
    local can_retry=retryable and not P.audible and P.urls and P.attempt<math.max(2,#P.urls)
    halt();P.error_kind=kind or 'network';P.metrics.phase='error'
    if can_retry then
      P.status='buffering';P.retry_at=now()+500;P.metrics.phase='retrying'
    else P.status='error';P.error=msg end
  end
  start_attempt=function()
    P.retry_at=nil
    local ok,err=halt()
    if not ok then P.status='error';P.error=err;return end
    ok,err=audio.open('mp3')
    if not ok then fail(err or '解码器启动失败',false,'decoder');return end
    P.attempt=P.attempt+1;P.bytes=0;P.position=0;P.status='buffering';P.error=''
    local generation=P.generation;local submitted=now()
    local url=P.urls[math.min(P.attempt,#P.urls)]
    P.metrics.attempts=P.attempt;P.metrics.node=math.min(P.attempt,#P.urls);P.metrics.phase='queued'
    local c=net.create(url,{async=true,timeout=8000,queue_timeout=10000,bufsz=6144,max_redirects=4,
      headers={['Accept-Encoding']='identity',['User-Agent']='CubicMusic/1.0.1'}})
    P.connection=c;P.last_data=nil;P.attempt_started=nil;P.first_data=nil
    local status,expected=0,nil
    local function active()return P.alive and generation==P.generation end
    c:on('start',function()
      if not active()then return end
      P.attempt_started=now();P.last_data=now();P.metrics.queue_ms=now()-submitted;P.metrics.phase='connecting'
    end)
    c:on('headers',function(code,h)
      if not active()then c:close();return end
      status=code;P.metrics.http=code;P.metrics.headers_ms=now()-(P.attempt_started or submitted)
      if code~=200 then
        fail('音频 HTTP '..tostring(code),code==408 or code==429 or code>=500,(code==401 or code==403)and 'cdn_auth'or 'http')
        return
      end
      for k,v in pairs(h or {})do
        if tostring(k):lower()=='content-length'then expected=tonumber(v)end
        if tostring(k):lower()=='content-type'and tostring(v):find('text/')then fail('收到非音频内容',false,'format');return end
      end
    end)
    c:on('data',function(code,data)
      if not active()then c:close();return end
      if code~=200 or type(data)~='string'then return end
      if not P.first_data then
        P.first_data=now();P.metrics.first_byte_ms=now()-(P.attempt_started or submitted);P.metrics.phase='buffering'
      end
      P.last_data=now();P.bytes=P.bytes+#data
      local state=audio.state()
      if (state.written_bytes or 0)>0 then P.audible=true end
      if state.buffer_free<#data then P.pending=data;return http.DELAYACK end
      if not audio.feed(data)then fail('音频缓冲写入失败',false,'decoder')end
    end)
    c:on('error',function()if active()then fail('音频连接失败，请重试',true,'network')end end)
    c:on('complete',function()
      if not active()then return end
      P.connection=nil
      if status~=200 or P.bytes==0 or (expected and P.bytes~=expected)then
        fail('音频下载中断，请重试',true,'network');return
      end
      audio.eos()
    end)
    c:request()
  end
  function P.play(source)
    P.stop();P.urls={}
    local candidates=type(source)=='table'and (source.urls or {source.url})or {source}
    for _,url in ipairs(candidates)do
      if type(url)=='string'and url:match('^https?://')and #P.urls<3 then P.urls[#P.urls+1]=url end
    end
    if #P.urls==0 then fail('无效音频地址',false,'format');return end
    P.attempt=0;P.audible=false;P.began=now();P.metrics={phase='queued',attempts=0}
    start_attempt()
  end
  function P.pause()
    if P.status=='idle'or P.status=='error'or P.status=='ended'then return end
    P.paused=not P.paused
    if P.paused then P.paused_at=now()
    else
      local elapsed=now()-(P.paused_at or now())
      if P.attempt_started then P.attempt_started=P.attempt_started+elapsed end
      if P.last_data then P.last_data=now()end
      P.paused_at=nil
    end
    audio.pause(P.paused)
  end
  function P.poll()
    if not P.alive then return end
    net.poll()
    if P.retry_at then
      if now()>=P.retry_at then start_attempt()end
      return
    end
    local st=audio.state();P.stats=st
    if P.pending and st.buffer_free>=#P.pending then
      if not audio.feed(P.pending)then fail('音频缓冲恢复失败',false,'decoder');return end
      P.pending=nil;P.last_data=now();if P.connection then P.connection:ack()end
    end
    if P.status=='idle'or P.status=='error'then return end
    if st.error~=0 then fail('解码/音频错误 '..tostring(st.error),false,'decoder');return end
    if (st.written_bytes or 0)>0 and not P.metrics.first_pcm_ms then
      P.audible=true;P.metrics.first_pcm_ms=now()-(P.began or now());P.metrics.phase='playing'
    end
    local c=P.connection
    if c and not P.paused and not P.pending then
      if not c.started_at and now()-(c.submitted_at or P.began or now())>10000 then fail('音频排队超时',true,'queue');return end
      local started=P.attempt_started or c.started_at
      if started and not P.first_data and now()-started>7000 then fail('音频首包超时',true,'first_byte');return end
      if P.last_data and now()-P.last_data>10000 then fail('音频传输超时',true,'network');return end
    end
    if st.status==4 then P.status='ended'
    elseif P.paused then P.status='paused'
    elseif st.status==2 then P.status='playing'
    else P.status='buffering'end
    P.position=st.source_rate>0 and st.written_bytes/(st.source_rate*2)or 0
  end
  function P.close()P.stop();P.alive=false end
  return P
end
return M
