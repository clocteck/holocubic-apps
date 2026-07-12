local Web = {}
local JSON = rawget(_G, "sjson") or rawget(_G, "json")

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function url_decode(value)
  value = tostring(value or ""):gsub("+", " ")
  return value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
end

local function parse_query(query)
  local out = {}
  for pair in tostring(query or ""):gmatch("([^&]+)") do
    local key, value = pair:match("^([^=]*)=(.*)$")
    out[url_decode(key or pair)] = url_decode(value or "")
  end
  return out
end

local function valid_ipv4(host)
  local a, b, c, d = tostring(host or ""):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  if not a then return false end
  for _, value in ipairs({ tonumber(a), tonumber(b), tonumber(c), tonumber(d) }) do
    if not value or value < 0 or value > 255 then return false end
  end
  return true
end

local function normalize_path(path)
  path = trim(path)
  if path == "" then return "/events" end
  return path:sub(1, 1) == "/" and path or ("/" .. path)
end

local function response(status, content_type, body)
  return {
    status = status or "200 OK",
    type = content_type or "text/plain; charset=utf-8",
    headers = { ["cache-control"] = "no-store", ["connection"] = "close" },
    body = body or "",
  }
end

local function json_response(status, value)
  local ok, raw = pcall(function() return JSON.encode(value) end)
  return response(ok and status or "500 Internal Server Error", "application/json; charset=utf-8", ok and raw or "{\"ok\":false}")
end

local function config_text(config)
  return string.format([=[local config = {}

config.host = %q
config.port = %d
config.path = %q

config.timeout_ms = %d
config.reconnect_ms = %d
config.stale_ms = %d
config.watchdog_ms = %d
config.serial_log = %s

return config
]=],
    tostring(config.host or "192.168.0.100"),
    tonumber(config.port) or 17321,
    normalize_path(config.path),
    tonumber(config.timeout_ms) or 7000,
    tonumber(config.reconnect_ms) or 2000,
    tonumber(config.stale_ms) or 120000,
    tonumber(config.watchdog_ms) or 1000,
    config.serial_log == false and "false" or "true"
  )
end

local function write_config(path, config)
  local raw = config_text(config)
  if file and file.putcontents then
    local ok, result = pcall(function() return file.putcontents(path, raw) end)
    if ok and result ~= false then return true end
    return false, tostring(result)
  end
  if file and file.open then
    local ok = pcall(function()
      file.open(path, "w+")
      file.write(raw)
      file.close()
    end)
    return ok, ok and nil or "write failed"
  end
  return false, "file api missing"
end

local function build_html(api_prefix)
  api_prefix = tostring(api_prefix):gsub("\\", "\\\\"):gsub('"', '\\"')
  return [=[<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Clawd Monitor 设置</title><style>
:root{color-scheme:dark;--bg:#090604;--panel:#17100c;--line:#563528;--text:#fff2e7;--muted:#aa8170;--rust:#d97757;--mint:#8fe0c7;--red:#ff6b6b}
*{box-sizing:border-box}body{margin:0;background:radial-gradient(circle at 72% 0,#2b1610 0,transparent 38%),var(--bg);color:var(--text);font:15px/1.55 "Segoe UI","PingFang SC",sans-serif}
.page{width:min(900px,calc(100% - 28px));margin:auto;padding:28px 0}.top{display:flex;justify-content:space-between;gap:18px;align-items:end;margin-bottom:18px}h1{margin:0;font-size:30px}.sub{margin:5px 0 0;color:var(--muted)}
.back,button{min-height:42px;border:1px solid var(--line);border-radius:8px;background:#21150f;color:var(--text);padding:0 15px;text-decoration:none;cursor:pointer}.grid{display:grid;grid-template-columns:1.2fr .8fr;gap:14px}.panel{padding:18px;border:1px solid var(--line);border-radius:10px;background:linear-gradient(145deg,#1b120e,#110c09)}h2{margin:0 0 14px;font-size:18px}
.form{display:grid;gap:13px}.row{display:grid;grid-template-columns:1fr 150px;gap:10px}label{display:block;margin-bottom:5px;color:var(--muted);font-size:13px;font-weight:700}input{width:100%;height:44px;border:1px solid var(--line);border-radius:8px;background:#090604;color:var(--text);padding:0 11px;outline:none}input:focus{border-color:var(--rust);box-shadow:0 0 0 3px #d9775730}.actions{display:flex;gap:9px;flex-wrap:wrap}.primary{border-color:transparent;background:var(--rust);color:#170b07;font-weight:800}.status{min-height:24px;color:var(--muted)}.ok{color:var(--mint)}.bad{color:var(--red)}
.state{display:grid;gap:11px}.metric{padding:11px;border:1px solid #3a261e;border-radius:8px;background:#0d0907}.metric span{display:block;color:var(--muted);font-size:12px}.metric strong{display:block;margin-top:4px;overflow-wrap:anywhere}.dot{display:inline-block;width:8px;height:8px;border-radius:50%;background:var(--red);margin-right:7px}.dot.on{background:var(--mint)}code{color:#f4c1a7}@media(max-width:700px){.grid{grid-template-columns:1fr}.row{grid-template-columns:1fr}.top{align-items:start}h1{font-size:25px}}
</style></head><body><main class="page"><header class="top"><div><h1>CODEX // CLAWD</h1><p class="sub">配置全息桌面精灵连接的 Codex 主机。</p></div><a class="back" href="/main">返回主界面</a></header>
<section class="grid"><section class="panel"><h2>主机连接</h2><form class="form" id="form"><div class="row"><div><label for="host">主机 IP</label><input id="host" inputmode="decimal" placeholder="192.168.0.100" required></div><div><label for="port">端口</label><input id="port" inputmode="numeric" placeholder="17321" required></div></div><div><label for="path">事件路径</label><input id="path" placeholder="/events" required></div><div class="actions"><button class="primary" type="submit">保存并重连</button><button id="test" type="button">测试连接</button></div><div class="status" id="message">正在读取配置…</div></form></section>
<aside class="panel"><h2>连接状态</h2><div class="state"><div class="metric"><span>设备 → 主机</span><strong><i class="dot" id="dot"></i><b id="online">未连接</b></strong></div><div class="metric"><span>事件流</span><strong><code id="url">-</code></strong></div><div class="metric"><span>最近信息</span><strong id="detail">-</strong></div></div></aside></section></main>
<script>const API="]=] .. api_prefix .. [=[";const $=id=>document.getElementById(id);function path(v){v=(v||"").trim();return !v?"/events":v[0]==="/"?v:"/"+v}function url(){return "http://"+$('host').value.trim()+":"+$('port').value.trim()+path($('path').value)}function msg(t,c){$('message').textContent=t;$('message').className="status "+(c||"")}function paint(d){$('host').value=d.host||"";$('port').value=d.port||17321;$('path').value=d.path||"/events";$('url').textContent=d.url||url();$('online').textContent=d.online?"已连接":"未连接";$('dot').className="dot "+(d.online?"on":"");$('detail').textContent=d.detail||"等待连接"}
async function load(){const r=await fetch(API+"/state?_="+Date.now(),{cache:"no-store"});const d=await r.json();if(!r.ok)throw Error(d.error||"读取失败");paint(d);msg("当前配置已载入。","ok")}
$('form').onsubmit=async e=>{e.preventDefault();msg("正在保存…","");try{const q=new URLSearchParams({host:$('host').value.trim(),port:$('port').value.trim(),path:path($('path').value)});const r=await fetch(API+"/save?"+q,{cache:"no-store"});const d=await r.json();if(!r.ok||!d.ok)throw Error(d.error||"保存失败");paint(d);msg("已保存，Clawd 正在按新地址重连。","ok")}catch(e){msg(e.message,"bad")}};
$('test').onclick=async()=>{msg("正在测试 "+url()+" …","");const ctrl=new AbortController();const timer=setTimeout(()=>ctrl.abort(),3000);try{const base="http://"+$('host').value.trim()+":"+$('port').value.trim();const r=await fetch(base+"/health?_="+Date.now(),{cache:"no-store",signal:ctrl.signal});if(!r.ok)throw Error("HTTP "+r.status);msg("连接成功，Codex 桥接服务在线。","ok")}catch(e){msg("连接失败："+(e.name==="AbortError"?"超时":e.message),"bad")}finally{clearTimeout(timer)}};load().catch(e=>msg("配置读取失败："+e.message,"bad"));setInterval(()=>fetch(API+"/state?_="+Date.now(),{cache:"no-store"}).then(r=>r.json()).then(paint).catch(()=>{}),2500);</script></body></html>]=]
end

function Web.new(opts)
  opts = opts or {}
  local self = {
    config = opts.config or {},
    config_path = opts.config_path or "/sd/apps/holo_pet/config.lua",
    route_base = opts.route_base or "/holo_pet",
    api_prefix = (opts.route_base or "/holo_pet") .. "/api",
    restart = opts.restart,
    set_page = opts.set_page,
    connection_state = opts.connection_state,
    routes = {},
    started = false,
  }

  function self:snapshot(ok, message)
    local extra = self.connection_state and self.connection_state() or {}
    local host = tostring(self.config.host or "")
    local port = tonumber(self.config.port) or 17321
    local path = normalize_path(self.config.path)
    return {
      ok = ok ~= false, host = host, port = port, path = path,
      url = "http://" .. host .. ":" .. tostring(port) .. path,
      online = extra.online == true, detail = extra.detail or message or "",
      state = extra.state or "idle", event = extra.event or "",
      source = extra.source or "",
      model = extra.model or "",
      effort = extra.effort or "",
      context = extra.context,
      usage = extra.usage,
      idle_variant = extra.idle_variant,
      idle_delay_minutes = extra.idle_delay_minutes,
      clock = extra.clock,
      page = extra.page,
      visual_group = extra.visual_group,
      visual_index = extra.visual_index,
      weather = extra.weather,
      weather_visual = extra.weather_visual,
      activity = extra.activity,
      session_meme = extra.session_meme,
      chat_timer = extra.chat_timer or "", state_timer = extra.state_timer or "",
      error = ok == false and message or nil,
    }
  end

  function self:register(method, route, handler)
    if not httpd or not httpd.dynamic then return false, "httpd missing" end
    local ok, err = pcall(function() return httpd.dynamic(method, route, handler) end)
    if not ok or err then return false, tostring(err) end
    self.routes[#self.routes + 1] = { method = method, route = route }
    return true
  end

  function self:save(req)
    local q = parse_query(req and req.query or "")
    local host, port, path = trim(q.host), tonumber(q.port), normalize_path(q.path)
    if not valid_ipv4(host) then return json_response("400 Bad Request", self:snapshot(false, "请输入有效的 IPv4 地址")) end
    if not port or port < 1 or port > 65535 then return json_response("400 Bad Request", self:snapshot(false, "端口需为 1 到 65535")) end
    self.config.host, self.config.port, self.config.path = host, math.floor(port), path
    local ok, err = write_config(self.config_path, self.config)
    if not ok then return json_response("500 Internal Server Error", self:snapshot(false, "配置写入失败: " .. tostring(err))) end
    if self.restart then pcall(self.restart) end
    return json_response("200 OK", self:snapshot(true, "saved"))
  end

  function self:start()
    if self.started or not httpd or not httpd.start then return end
    pcall(function() httpd.start({ webroot = "/sd", auto_index = httpd.INDEX_NONE, max_handlers = 36 }) end)
    self:register(httpd.GET, self.route_base, function() return response("200 OK", "text/html; charset=utf-8", build_html(self.api_prefix)) end)
    self:register(httpd.GET, self.route_base .. "/", function() return response("200 OK", "text/html; charset=utf-8", build_html(self.api_prefix)) end)
    self:register(httpd.GET, self.api_prefix .. "/state", function() return json_response("200 OK", self:snapshot(true, "loaded")) end)
    self:register(httpd.GET, self.api_prefix .. "/page", function(req)
      local q = parse_query(req and req.query or "")
      if self.set_page then pcall(self.set_page, q.name or "status") end
      return json_response("200 OK", self:snapshot(true, "page"))
    end)
    self:register(httpd.GET, self.api_prefix .. "/save", function(req) return self:save(req) end)
    if app and app.set_webui then pcall(function() app.set_webui(true) end) end
    self.started = true
  end

  function self:stop()
    if httpd and httpd.unregister then
      for i = #self.routes, 1, -1 do
        local item = self.routes[i]
        pcall(function() httpd.unregister(item.method, item.route) end)
      end
    end
    self.routes = {}
    if app and app.set_webui then pcall(function() app.set_webui(false) end) end
    self.started = false
  end

  return self
end

return Web
