local M={}
function M.new(audio,net,now)
  local P={generation=0,status='idle',error='',paused=false,alive=true,bytes=0}
  function P.stop()
    P.generation=P.generation+1;net.cancel();P.pending=nil;P.connection=nil
    P.paused=false;P.status='idle';P.error=''
    return audio.close()
  end
  local function fail(msg)
    P.stop();P.status='error';P.error=msg
  end
  function P.play(url)
    local ok,err=P.stop()
    if not ok then P.status='error';P.error=err;return end
    if type(url)~='string' or not url:match('^https?://')then fail('无效音频地址');return end
    ok,err=audio.open('mp3')
    if not ok then fail(err or '解码器启动失败');return end
    P.bytes=0;P.status='buffering';local generation=P.generation
    local c=net.create(url,{async=true,timeout=15000,bufsz=6144,max_redirects=4,
      headers={['Accept-Encoding']='identity',['User-Agent']='CubicNetEase/0.1'}})
    P.connection=c;P.last_data=now()
    local status,expected=0,nil
    local function active()return P.alive and generation==P.generation end
    c:on('headers',function(code,h)
      if not active()then c:close();return end
      status=code
      if code~=200 then fail('音频 HTTP '..tostring(code));return end
      for k,v in pairs(h or {})do
        if tostring(k):lower()=='content-length'then expected=tonumber(v)end
        if tostring(k):lower()=='content-type' and tostring(v):find('text/')then fail('收到非音频内容');return end
      end
    end)
    c:on('data',function(code,data)
      if not active()then c:close();return end
      if code~=200 then return end
      P.last_data=now();P.bytes=P.bytes+#data
      local state=audio.state()
      if state.buffer_free<#data then P.pending=data;return http.DELAYACK end
      local accepted=audio.feed(data)
      if not accepted then fail('音频缓冲写入失败')end
    end)
    c:on('error',function()if active()then fail('音频连接失败，Home 重试')end end)
    c:on('complete',function()
      if not active()then return end
      P.connection=nil
      if status~=200 or P.bytes==0 or (expected and P.bytes~=expected)then
        fail('音频下载中断，Home 重试');return
      end
      audio.eos()
    end)
    c:request()
  end
  function P.pause()
    if P.status=='idle' or P.status=='error' or P.status=='ended'then return end
    P.paused=not P.paused;audio.pause(P.paused)
  end
  function P.poll()
    if not P.alive then return end
    net.poll()
    local st=audio.state();P.stats=st
    if P.pending and st.buffer_free>=#P.pending then
      local accepted=audio.feed(P.pending)
      if not accepted then fail('音频缓冲恢复失败');return end
      P.pending=nil;if P.connection then P.connection:ack()end
    end
    if P.status=='idle' or P.status=='error'then return end
    if st.error~=0 then fail('解码/音频错误 '..tostring(st.error));return end
    if st.status==4 then P.status='ended'
    elseif P.paused then P.status='paused'
    elseif st.status==2 then P.status='playing'
    else P.status='buffering'end
    P.position=st.source_rate>0 and st.written_bytes/(st.source_rate*2) or 0
  end
  function P.close()P.stop();P.alive=false end
  return P
end
return M
