local M = {}

local PAGE = [=[<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>小智助手</title>
<style>body{margin:0;background:#0f172a;color:#f8fafc;font:16px/1.5 system-ui}.wrap{max-width:620px;margin:auto;padding:24px}.card{background:#1e293b;border:1px solid #475569;border-radius:18px;padding:20px;margin:14px 0}.code{font-size:42px;font-weight:800;letter-spacing:10px;color:#c4b5fd}.muted{color:#cbd5e1;word-break:break-all}button{min-height:48px;border:0;border-radius:12px;padding:12px 18px;background:#8b5cf6;color:white;font-weight:700;font-size:16px;cursor:pointer;touch-action:manipulation;transition:opacity .15s ease,background .15s ease}button:hover{background:#7c3aed}button:active{background:#6d28d9}button:focus-visible{outline:3px solid #c4b5fd;outline-offset:3px}button:disabled{opacity:.45;cursor:not-allowed}.dot{display:inline-block;width:10px;height:10px;border-radius:50%;background:#64748b;margin-right:8px}.on{background:#22c55e}.err{color:#fca5a5}.volume{display:grid;grid-template-columns:minmax(0,1fr) 64px;align-items:center;gap:16px;margin-top:16px}.volume input{width:100%;height:44px;margin:0;accent-color:#8b5cf6;cursor:pointer;touch-action:pan-x}.volume input:focus-visible{outline:3px solid #c4b5fd;outline-offset:2px;border-radius:8px}.volume output{text-align:right;font-size:22px;font-weight:700;font-variant-numeric:tabular-nums}.linkbtn{display:block;min-height:44px;margin-top:10px;padding:8px 2px;background:transparent;color:#94a3b8;font-size:13px;font-weight:500}.linkbtn:hover,.linkbtn:active{background:transparent;color:#cbd5e1}.advanced{display:grid;gap:12px;margin-top:10px;padding-top:16px;border-top:1px solid #475569}.advanced[hidden]{display:none}.advanced label{display:grid;gap:5px;color:#cbd5e1;font-size:14px}.advanced input,.advanced select{box-sizing:border-box;width:100%;min-height:44px;border:1px solid #64748b;border-radius:10px;padding:10px 12px;background:#0f172a;color:#f8fafc;font:16px system-ui}.advanced input:focus,.advanced select:focus{outline:3px solid #8b5cf6;outline-offset:1px}.hint{margin:0;color:#94a3b8;font-size:12px}.secondary{background:#475569}.secondary:hover{background:#64748b}@media(prefers-reduced-motion:reduce){button{transition:none}}</style></head><body><main class="wrap"><h1>小智助手</h1><section class="card"><div><i id="dot" class="dot"></i><b id="status">读取状态…</b></div><p id="message" class="muted" aria-live="polite"></p><div id="code" class="code"></div></section><section class="card"><b>播放音量</b><div class="volume"><input id="volumeSlider" type="range" min="0" max="100" step="1" value="100" aria-label="播放音量"><output id="volume" for="volumeSlider">100%</output></div></section><section class="card"><b>官方服务</b><p class="muted">配对码请在小智控制台的“添加设备”中输入。绑定成功后，设备会自动保存官方下发的 WebSocket 地址。</p><p id="server" class="muted"></p><button id="pair">重新获取配对码</button><button id="customToggle" class="linkbtn" aria-expanded="false" aria-controls="customPanel">自定义服务</button><div id="customPanel" class="advanced" hidden><label>WebSocket 地址<input id="customUrl" type="url" inputmode="url" placeholder="wss://example.com/xiaozhi/v1/"></label><label>访问 Token（留空即清除）<input id="customToken" type="password" autocomplete="off" placeholder="可选"></label><label>协议版本<select id="customVersion"><option value="1">1</option><option value="2">2</option><option value="3">3</option></select></label><button id="saveCustom">保存自定义服务</button><label>设备 MAC<input id="deviceMac" type="text" inputmode="text" autocomplete="off" placeholder="02:12:34:56:78:9a"></label><p class="hint">修改 MAC 会切换为新的设备身份；使用官方服务时必须用新配对码重新配对。</p><button id="saveMac" class="secondary">保存设备 MAC</button></div></section></main><script>
const q=s=>document.querySelector(s);let volume=100,volumeTimer=0,serverLoaded=false;async function api(p,o){let r=await fetch(p,o);let j=await r.json();if(!r.ok)throw Error(j.error||r.status);return j}function showVolume(v){volume=Math.max(0,Math.min(100,Number(v)||0));q('#volumeSlider').value=String(volume);q('#volume').textContent=volume+'%'}function pushVolume(v){fetch('./api/volume',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({volume:v}),keepalive:true}).catch(()=>{})}function queueVolume(v,now){showVolume(v);clearTimeout(volumeTimer);if(now)pushVolume(volume);else volumeTimer=setTimeout(()=>pushVolume(volume),150)}async function refresh(){try{let s=await api('./api/state');q('#status').textContent=s.connected?'已连接服务':(s.activation_status||'等待连接');q('#dot').className='dot '+(s.connected?'on':'');q('#message').textContent=s.message||s.last_error||'';q('#code').textContent=s.pairing_code||'';q('#server').textContent=s.websocket_url?'服务器：'+s.websocket_url:'尚未绑定设备';if(document.activeElement!==q('#volumeSlider'))showVolume(s.volume==null?100:s.volume);if(!serverLoaded){q('#customUrl').value=s.websocket_url||'';q('#customVersion').value=String(s.websocket_version||1);q('#customToken').placeholder=s.websocket_token_set?'已设置；留空将清除':'可选';q('#deviceMac').value=s.device_mac||'';serverLoaded=true}}catch(e){q('#status').textContent='状态读取失败';q('#message').textContent=e.message;q('#message').className='muted err'}}q('#volumeSlider').oninput=e=>queueVolume(e.target.value,false);q('#volumeSlider').onchange=e=>queueVolume(e.target.value,true);q('#customToggle').onclick=()=>{let p=q('#customPanel'),open=p.hidden;p.hidden=!open;q('#customToggle').setAttribute('aria-expanded',String(open));if(open)q('#customUrl').focus()};q('#saveCustom').onclick=async()=>{let b=q('#saveCustom');b.disabled=true;try{let s=await api('./api/server',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({url:q('#customUrl').value,token:q('#customToken').value,version:Number(q('#customVersion').value)})});q('#message').textContent='自定义服务已保存，唤醒后连接';q('#server').textContent='服务器：'+s.url;q('#customToken').value='';q('#customToken').placeholder=s.token_set?'已设置；留空将清除':'可选'}catch(e){q('#message').textContent=e.message}finally{b.disabled=false}};q('#saveMac').onclick=async()=>{let b=q('#saveMac');b.disabled=true;try{let s=await api('./api/mac',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({mac:q('#deviceMac').value})});q('#deviceMac').value=s.mac;q('#message').textContent=s.unchanged?'MAC 未变化':(s.pairing_required?'设备身份已修改，正在重新获取配对码':'设备身份已修改，正在重启服务');if(s.restarting)setTimeout(refresh,1800);else b.disabled=false}catch(e){q('#message').textContent=e.message;b.disabled=false}};q('#pair').onclick=async()=>{q('#pair').disabled=true;try{await api('./api/repair',{method:'POST'});q('#message').textContent='正在请求官方配对码…';setTimeout(refresh,1800)}catch(e){q('#message').textContent=e.message}finally{setTimeout(()=>q('#pair').disabled=false,2500)}};refresh();setInterval(refresh,2000)</script></body></html>]=]

local function encode(value)
  local c = rawget(_G, "json") or rawget(_G, "sjson")
  if not c or not c.encode then return "{}" end
  local ok, raw = pcall(c.encode, value)
  return ok and raw or "{}"
end

local function response(status, typ, body)
  return { status = status, type = typ, headers = { ["cache-control"] = "no-store" }, body = body or "" }
end

function M.new(runtime, cfg)
  local instance_base = (app and app.route_base and app.route_base()) or "/xiaozhi-service"
  local self = { routes = {}, base = "/xiaozhi-service", instance_base = instance_base }
  local function register(method, path, fn)
    local err = httpd.dynamic(method, path, fn)
    if not err then self.routes[#self.routes + 1] = { method = method, path = path } end
  end
  function self:start()
    if not httpd or not httpd.dynamic then return false end
    pcall(function() httpd.start({ webroot = "/sd", auto_index = httpd.INDEX_NONE, max_handlers = 48 }) end)
    local function index() return response("200 OK", "text/html; charset=utf-8", PAGE) end
    local function state() return response("200 OK", "application/json; charset=utf-8", encode(runtime:snapshot())) end
    local function volume(req)
      local raw = req and (req.body or req.payload) or nil
      if not raw and req and req.getbody then
        local ok, value = pcall(req.getbody)
        if ok then raw = value end
      end
      local c = rawget(_G, "json") or rawget(_G, "sjson")
      local ok, doc = pcall(function() return c.decode(raw or "{}") end)
      local value = ok and type(doc) == "table" and tonumber(doc.volume) or nil
      local saved, result = runtime:set_volume(value)
      if not saved then
        return response("400 Bad Request", "application/json; charset=utf-8", encode({ ok = false, error = result }))
      end
      return response("204 No Content", "text/plain; charset=utf-8", "")
    end
    local function server(req)
      local raw = req and (req.body or req.payload) or nil
      if not raw and req and req.getbody then
        local ok, value = pcall(req.getbody)
        if ok then raw = value end
      end
      local c = rawget(_G, "json") or rawget(_G, "sjson")
      local ok, doc = pcall(function() return c.decode(raw or "{}") end)
      doc = ok and type(doc) == "table" and doc or {}
      local saved, result = runtime:set_server(doc.url, doc.token, doc.version)
      if not saved then
        return response("400 Bad Request", "application/json; charset=utf-8", encode({ ok = false, error = result }))
      end
      result.ok = true
      return response("200 OK", "application/json; charset=utf-8", encode(result))
    end
    local function mac(req)
      local raw = req and (req.body or req.payload) or nil
      if not raw and req and req.getbody then
        local ok, value = pcall(req.getbody)
        if ok then raw = value end
      end
      local c = rawget(_G, "json") or rawget(_G, "sjson")
      local ok, doc = pcall(function() return c.decode(raw or "{}") end)
      local value = ok and type(doc) == "table" and doc.mac or nil
      local saved, result = runtime:set_device_mac(value)
      if not saved then
        return response("400 Bad Request", "application/json; charset=utf-8", encode({ ok = false, error = result }))
      end
      result.ok = true
      return response("202 Accepted", "application/json; charset=utf-8", encode(result))
    end
    local function repair()
      local path = (cfg.APP_DIR or "/sd/apps/xiaozhi-service") .. "/config.json"
      local raw = file.getcontents(path)
      local c = rawget(_G, "json") or rawget(_G, "sjson")
      local ok, doc = pcall(function() return c.decode(raw or "{}") end)
      if not ok or type(doc) ~= "table" then return response("500 Internal Server Error", "application/json", '{"error":"配置读取失败"}') end
      doc.ota = doc.ota or {}; doc.ota.url = "https://api.tenclass.net/xiaozhi/ota/"; doc.ota.enabled = true; doc.ota.force = false
      doc.websocket = doc.websocket or {}; doc.websocket.url = ""; doc.websocket.token = ""; doc.websocket.version = 1
      file.putcontents(path, encode(doc))
      local t = tmr.create(); t:alarm(300, tmr.ALARM_SINGLE, function(x) pcall(function() x:unregister() end); app.start_service("xiaozhi-service") end)
      return response("202 Accepted", "application/json", '{"ok":true}')
    end
    local bases = { self.base }
    if self.instance_base ~= self.base then bases[#bases + 1] = self.instance_base end
    for _, base in ipairs(bases) do
      register(httpd.GET, base, index)
      register(httpd.GET, base .. "/", index)
      register(httpd.GET, base .. "/api/state", state)
      register(httpd.POST, base .. "/api/volume", volume)
      register(httpd.POST, base .. "/api/server", server)
      register(httpd.POST, base .. "/api/mac", mac)
      register(httpd.POST, base .. "/api/repair", repair)
    end
    if app and app.set_webui then pcall(function() app.set_webui(true) end) end
    return true
  end
  function self:stop()
    if httpd and httpd.unregister then for i=#self.routes,1,-1 do local r=self.routes[i]; pcall(httpd.unregister,r.method,r.path) end end
    self.routes = {}
  end
  return self
end

return M
