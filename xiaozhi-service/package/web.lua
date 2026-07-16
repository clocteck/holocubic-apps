local M = {}

local PAGE = [=[<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>小智助手</title>
<style>body{margin:0;background:#0f172a;color:#f8fafc;font:16px system-ui}.wrap{max-width:620px;margin:auto;padding:24px}.card{background:#1e293b;border:1px solid #475569;border-radius:18px;padding:20px;margin:14px 0}.code{font-size:42px;font-weight:800;letter-spacing:10px;color:#c4b5fd}.muted{color:#cbd5e1;word-break:break-all}button{border:0;border-radius:12px;padding:12px 18px;background:#8b5cf6;color:white;font-weight:700;font-size:16px}button:disabled{opacity:.5}.dot{display:inline-block;width:10px;height:10px;border-radius:50%;background:#64748b;margin-right:8px}.on{background:#22c55e}.err{color:#fca5a5}</style></head><body><main class="wrap"><h1>小智助手</h1><section class="card"><div><i id="dot" class="dot"></i><b id="status">读取状态…</b></div><p id="message" class="muted"></p><div id="code" class="code"></div></section><section class="card"><b>官方服务</b><p class="muted">配对码请在小智控制台的“添加设备”中输入。绑定成功后，设备会自动保存官方下发的 WebSocket 地址。</p><p id="server" class="muted"></p><button id="pair">重新获取配对码</button></section></main><script>
const q=s=>document.querySelector(s);async function api(p,o){let r=await fetch(p,o);let j=await r.json();if(!r.ok)throw Error(j.error||r.status);return j}async function refresh(){try{let s=await api('./api/state');q('#status').textContent=s.connected?'已连接官方服务':(s.activation_status||'等待连接');q('#dot').className='dot '+(s.connected?'on':'');q('#message').textContent=s.message||s.last_error||'';q('#code').textContent=s.pairing_code||'';q('#server').textContent=s.websocket_url?'服务器：'+s.websocket_url:'尚未绑定设备';}catch(e){q('#status').textContent='状态读取失败';q('#message').textContent=e.message;q('#message').className='muted err'}}q('#pair').onclick=async()=>{q('#pair').disabled=true;try{await api('./api/repair',{method:'POST'});q('#message').textContent='正在请求官方配对码…';setTimeout(refresh,1800)}catch(e){q('#message').textContent=e.message}finally{setTimeout(()=>q('#pair').disabled=false,2500)}};refresh();setInterval(refresh,2000)</script></body></html>]=]

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
