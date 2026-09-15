-- QQ authorization QR protocol; do not evaluate returned ptuiCB JavaScript.
local Q=dofile('/sd/apps/qqmusic/provider.lua')
local M={}
function M.parse(raw)
  if type(raw)~='string'then return end
  local body=raw:match('^%s*ptuiCB%((.*)%)%s*;?%s*$');if not body then return end
  local args={};for value in body:gmatch("'([^']*)'")do args[#args+1]=value end
  return tonumber(args[1]),args[3]
end
function M.new(provider,now)
  local L={generation=0,status='idle',image=nil,mode='qq'}
  local function get(url,param,options,done)provider.raw(url..'?'..Q.query(param),options,done)end
  function L.cancel()
    L.generation=L.generation+1;L.qrsig=nil;L.uuid=nil;L.image=nil;L.status='idle';provider.cancel()
  end
  local function save(session,err)
    if not session then L.update('error',err);return end
    session.login_type=L.mode=='wx'and 1 or 2
    local ok,e=provider.save_session(session);L.qrsig=nil;L.uuid=nil;L.image=nil;L.update(ok and 'done'or 'error',e)
  end
  function L.start(changed,mode)
    if mode and mode~='qq'and mode~='wx'then return nil,'不支持的登录方式'end
    L.changed=changed
    L.cancel();L.mode=mode or L.mode;local g=L.generation;L.status='loading';L.started=now()
    function L.update(status,error)
      if g~=L.generation then return end;L.status=status;L.error=error;changed(status,error)
    end
    if L.mode=='wx'then
      get('https://open.weixin.qq.com/connect/qrconnect',{appid='wx48db31d50e334801',
        redirect_uri='https://y.qq.com/portal/wx_redirect.html?login_type=2&surl=https://y.qq.com/',
        response_type='code',scope='snsapi_login',state='STATE'},{operation='wx_qr'},function(raw,e)
          if g~=L.generation then return end
          local uuid=raw and raw:match('uuid=([%w_%-]+)')
          if not uuid then L.update('error',e or '微信二维码标识缺失');return end;L.uuid=uuid
          provider.raw('https://open.weixin.qq.com/connect/qrcode/'..uuid,{operation='wx_qr_image',limit=98304},function(image,why)
            if g~=L.generation then return end
            if not image or image:sub(1,2)~='\255\216'then L.update('error',why or '微信二维码格式不兼容');return end
            L.image=image;L.next=now()+1500;L.update('waiting')
          end)
        end);return
    end
    get('https://ssl.ptlogin2.qq.com/ptqrshow',{appid=716027609,e=2,l='M',s=3,d=72,v=4,t=tostring(now()),daid=383,pt_3rd_aid=100497308},
      {operation='qr_image',limit=16384,headers={Referer='https://xui.ptlogin2.qq.com/'}},function(raw,e,_,h)
        if g~=L.generation then return end;local sig=Q.cookies(h).qrsig
        if not raw or raw:sub(1,8)~='\137PNG\r\n\26\n'or not sig then L.update('error',e or '二维码或登录签名缺失');return end
        L.qrsig=sig;L.image=raw;L.next=now()+2500;L.update('waiting')end)
  end
  local function authorize(url,g)
    local uin=url and url:match('[?&]uin=(%d+)');local sig=url and url:match('[?&]ptsigx=([%w]+)')
    if not uin or not sig then L.update('error','授权参数不兼容');return end;L.update('authorizing')
    get('https://ssl.ptlogin2.graph.qq.com/check_sig',{uin=uin,pttype=1,service='ptqrlogin',nodirect=0,ptsigx=sig,
      s_url='https://graph.qq.com/oauth2.0/login_jump',ptlang=2052,ptredirect=100,aid=716027609,daid=383,j_later=0,
      low_login_hour=0,regmaster=0,pt_login_type=3,pt_aid=0,pt_aaid=16,pt_light=0,pt_3rd_aid=100497308},
      {operation='qr_exchange',redirect=true,limit=16384,headers={Referer='https://xui.ptlogin2.qq.com/'}},function(raw,e,_,h)
        if g~=L.generation then return end;local jar=Q.cookies(h)
        if not raw or not jar.p_skey then L.update('error',e or 'QQ授权凭据缺失，请重新扫码');return end
        local state='cubic'..tostring(math.floor(now()))..tostring(math.random(100000,999999))
        provider.raw('https://graph.qq.com/oauth2.0/authorize',{operation='qr_authorize',method='POST',redirect=true,limit=16384,
          headers={['Content-Type']='application/x-www-form-urlencoded',Cookie=Q.cookie_header(jar),Referer='https://graph.qq.com/'},
          body=Q.query({response_type='code',client_id=100497308,
            redirect_uri='https://y.qq.com/portal/wx_redirect.html?login_type=1&surl=https://y.qq.com/',
            scope='get_user_info,get_app_friends',state=state,switch='',from_ptlogin=1,src=1,update_auth=1,
            openapi='1010_1030',g_tk=Q.hash33(jar.p_skey,5381),auth_time=tostring(math.floor(now())),ui=state})},function(body,err,_,headers)
              if g~=L.generation then return end
              local location=Q.header(headers,'location');if type(location)=='table'then location=location[1]end
              local code=type(location)=='string'and location:match('[?&]code=([%w_%-]+)')
              local returned=type(location)=='string'and location:match('[?&]state=([^&#]+)')
              if not body or not code or returned~=state or not location:match('^https://y%.qq%.com/portal/wx_redirect%.html%?')then
                L.update('error',err or 'QQ授权未完成或状态不匹配');return end
              provider.rpc('QQConnectLogin.LoginServer','QQLogin',{code=code},function(session,why)
                if g~=L.generation then return end;if not session then L.update('error',why);return end
                save(session)
              end,{tmeLoginType=2})
            end)
      end)
  end
  function L.poll()
    if L.status~='waiting'and L.status~='scanned'then return end
    if now()-L.started>150000 then
      L.generation=L.generation+1;provider.cancel();L.qrsig=nil;L.uuid=nil;L.image=nil
      L.status='expired';L.error=nil;if L.changed then L.changed('expired')end;return
    end
    if provider.busy or now()<(L.next or 0)then return end;L.next=now()+3000;local g=L.generation
    if L.mode=='wx'then
      get('https://lp.open.weixin.qq.com/connect/l/qrconnect',{uuid=L.uuid,_=tostring(math.floor(now()))},
        {operation='wx_poll',timeout=35000,limit=16384,headers={Referer='https://open.weixin.qq.com/'}},function(raw,e)
          if g~=L.generation then return end
          if not raw then L.next=now()+3000;L.error=e;return end
          local code=tonumber(raw:match('wx_errcode=(%d+)'));local auth=raw:match("wx_code='([%w_%-]+)'")
          if code==405 and auth then L.update('authorizing')
            provider.rpc('music.login.LoginServer','Login',{code=auth,strAppid='wx48db31d50e334801'},function(session,err)
              if g==L.generation then save(session,err)end
            end,{tmeLoginType=1})
          elseif code==404 then L.update('scanned')elseif code==408 then L.update('waiting')
          elseif code==402 or code==403 then L.uuid=nil;L.image=nil;L.update('expired')
          else L.update('error','微信扫码响应不兼容，请刷新')end
        end);return
    end
    get('https://ssl.ptlogin2.qq.com/ptqrlogin',{u1='https://graph.qq.com/oauth2.0/login_jump',ptqrtoken=Q.hash33(L.qrsig),
      ptredirect=0,h=1,t=1,g=1,from_ui=1,ptlang=2052,action='0-0-'..tostring(math.floor(now())),js_ver=20102616,
      js_type=1,pt_uistyle=40,aid=716027609,daid=383,pt_3rd_aid=100497308,has_onekey=1},
      {operation='qr_poll',limit=16384,headers={Cookie=Q.cookie_header({qrsig=L.qrsig}),Referer='https://xui.ptlogin2.qq.com/'}},function(raw,e)
        if g~=L.generation then return end;if not raw then L.update('error',e);return end;local code,url=M.parse(raw)
        if code==66 then L.update('waiting')elseif code==67 then L.update('scanned')
        elseif code==65 then L.qrsig=nil;L.image=nil;L.update('expired')elseif code==0 then authorize(url,g)
        else L.qrsig=nil;L.image=nil;L.update('error','QQ登录被取消或接口不兼容')end end)
  end
  return L
end
return M
