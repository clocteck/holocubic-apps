local Web={}
local JSON=rawget(_G,"sjson") or rawget(_G,"json")
local function unescape(s) return tostring(s or ""):gsub("+"," "):gsub("%%(%x%x)",function(h)return string.char(tonumber(h,16))end) end
local function query(req)
 local out={}
 for item in tostring(req and req.query or ""):gmatch("[^&]+") do local k,v=item:match("^([^=]+)=(.*)$");if k then out[unescape(k)]=unescape(v) end end
 return out
end
local function response(body,mime,status)
 return {status=status or "200 OK",type=mime or "application/json; charset=utf-8",headers={["cache-control"]="no-store",["connection"]="close",["x-content-type-options"]="nosniff"},body=body}
end
local function json(value,status) return response(JSON.encode(value),nil,status) end
local function params(req)
 if not req.getbody then return query(req) end
 local pieces={};local size=0
 while true do local c=req.getbody();if not c then break end;size=size+#c;if size>8192 then return nil end;pieces[#pieces+1]=c end
 if size==0 then return query(req) end
 local ok,v=pcall(JSON.decode,table.concat(pieces));return ok and type(v)=="table" and v or nil
end
function Web.new(backend,opts)
 local self={backend=backend,catalog=opts.catalog,dir=opts.app_dir,base=opts.route_base or "/btc",language=opts.language or "zh-CN",routes={}}
 local function snapshot() local s=backend:snapshot();s.catalog=self.catalog:status();return s end
 local function set(req)
  local p=params(req);if not p then return json({ok=false,error="Invalid settings"},"400 Bad Request") end
  if not backend:apply_settings(p,true) then local s=snapshot();s.ok=false;s.error=backend.save_error~="" and backend.save_error or s.error;return json(s,"400 Bad Request") end
  backend.catalog_busy=self.catalog.busy;backend:tick();return json(snapshot())
 end
 function self:register(method,suffix,handler)
  local route=self.base..suffix;local err=httpd.dynamic(method,route,handler)
  if err then error("Ticker route: "..tostring(err)) end;self.routes[#self.routes+1]={method,route}
 end
 function self:start()
  pcall(function()httpd.start({webroot="/sd",auto_index=httpd.INDEX_NONE,max_handlers=128})end)
  local function index()
   local html=file.getcontents(self.dir.."/index.html")
   if not html then return response("Web page missing","text/plain","500 Internal Server Error") end
   return response(html:gsub("__BASE__",self.base):gsub("__LANG__",self.language),"text/html; charset=utf-8")
  end
  self:register(httpd.GET,"",index);self:register(httpd.GET,"/",index)
  for _,item in ipairs({{"/ui.js","ui.js","application/javascript; charset=utf-8"},{"/ui.css","ui.css","text/css; charset=utf-8"},{"/labels.js","labels.js","application/javascript; charset=utf-8"}}) do
   local route,name,mime=item[1],item[2],item[3]
   self:register(httpd.GET,route,function()return response(file.getcontents(self.dir.."/"..name) or "",mime)end)
  end
  self:register(httpd.GET,"/api/state",function()return json(snapshot())end)
  self:register(httpd.GET,"/api/health",function()return response("ok","text/plain")end)
  self:register(httpd.GET,"/api/set",set);self:register(httpd.POST,"/api/set",set)
  local function refresh()backend:queue_refresh();backend.catalog_busy=self.catalog.busy;backend:tick();return json(snapshot())end
  self:register(httpd.GET,"/api/refresh",refresh);self:register(httpd.POST,"/api/refresh",refresh)
  self:register(httpd.POST,"/api/custom/remove",function(req)
   local p=params(req)
   if not p or not backend:remove_custom(p.id) then return json({ok=false,error=backend.save_error~="" and backend.save_error or "Saved asset not found"},"400 Bad Request") end
   return json(snapshot())
  end)
  self:register(httpd.GET,"/api/catalog/status",function()return json(self.catalog:status())end)
  self:register(httpd.GET,"/api/catalog/search",function(req)local q=query(req);return json(self.catalog:search(q.group,q.q,q.cursor,q.generation))end)
  self:register(httpd.GET,"/api/catalog/currencies",function()return json({ok=true,items=self.catalog:currencies()})end)
  self:register(httpd.POST,"/api/catalog/update",function(req)
   local p=params(req);local ok,err=self.catalog:start(p and p.group or "all")
   if not ok then return json({ok=false,error=err},"400 Bad Request") end
   return json({ok=true,catalog=self.catalog:status()})
  end)
  self:register(httpd.POST,"/api/catalog/cancel",function()self.catalog:cancel();return json({ok=true,catalog=self.catalog:status()})end)
  if app and app.set_webui then app.set_webui(true) end
 end
 function self:stop()
  for i=#self.routes,1,-1 do local r=self.routes[i];pcall(httpd.unregister,r[1],r[2]) end
  self.routes={};if app and app.set_webui then pcall(app.set_webui,false) end
 end
 return self
end
return Web
