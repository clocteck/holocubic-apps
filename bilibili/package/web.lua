local Web={}
function Web.new(U,dir,APP)
 local self={routes={},base=app.route_base and app.route_base() or '/bilibili',token=U.md5(tostring({})..tostring(U.ms())..tostring(U.now())..tostring(math.random()))}
 if not self.base or self.base=='' then self.base='/bilibili' end
 local function response(body,mime,status)return {status=status or '200 OK',type=mime or 'application/json; charset=utf-8',headers={['Cache-Control']='no-store',['X-Content-Type-Options']='nosniff'},body=body}end
 local function json(value,status)return response(sjson.encode(value),nil,status)end
 local function body(req)
  local chunks={};local size=0;if req.getbody then while true do local part=req.getbody();if not part or part=='' then break end;size=size+#part;if size>2048 then return nil,'请求过长' end;chunks[#chunks+1]=part end end
  local p=U.decode(table.concat(chunks));if not p or p.token~=self.token then return nil,'控制页面已过期，请刷新页面' end;return p
 end
 function self:register(method,path,handler)
  local route=self.base..path;local err=httpd.dynamic(method,route,handler);if err then error('WebUI route failed: '..route) end;self.routes[#self.routes+1]={method,route}
 end
 function self:start()
  httpd.start({webroot='/sd',auto_index=httpd.INDEX_NONE,max_handlers=256})
  local function snapshot()local s=APP.snapshot();s.control_token=self.token;return s end
  local function index()return response((file.getcontents(dir..'/index.html') or ''):gsub('__BASE__',self.base):gsub('__CONTROL_TOKEN__',self.token),'text/html; charset=utf-8')end
  self:register(httpd.GET,'/',index);self:register(httpd.GET,'',index)
  self:register(httpd.GET,'/api/state',function()return json(snapshot())end)
  self:register(httpd.GET,'/screen.png',function()
   local fd=file.open(dir..'/screen.png','r');if not fd then return response('No screenshot','text/plain','404 Not Found') end
   return {status='200 OK',type='image/png',headers={['Cache-Control']='no-store'},getbody=function()local piece=fd:read(8192);if not piece or #piece==0 then fd:close();return nil end;return piece end}
  end)
  self:register(httpd.POST,'/api/control',function(req)
   local p,err=body(req);if not p then return json({ok=false,error=err},'400 Bad Request') end
   local ok,result=APP.control(p);if not ok then return json({ok=false,error=result or '操作未完成'},'400 Bad Request') end
   return json(snapshot())
  end)
  if app.set_webui then app.set_webui(true) end
 end
 function self:stop()for _,r in ipairs(self.routes) do pcall(httpd.unregister,r[1],r[2])end;self.routes={};if app.set_webui then pcall(app.set_webui,false)end end
 return self
end
return Web
