local Web = {}

local JSON = rawget(_G, "sjson") or rawget(_G, "json")

local RSLCD = [=[<LCDVER>200</LCDVER><SWVER>8.20.8100</SWVER>
<LCDBGCOLOR>16777215</LCDBGCOLOR>
<LCDPAGE1>
 <ID>[SIMPLE]SCPUUTI</ID><TXTSIZ>8</TXTSIZ><FNTNAM>Tahoma</FNTNAM><TXTCOL>11184640</TXTCOL><TXTBIR>000</TXTBIR><SHWLBL>1</SHWLBL><LBL>CPU Usage</LBL><SHWUNT>1</SHWUNT><UNT>%</UNT><ITMX>0</ITMX><ITMY>0</ITMY>
 <ID>[SIMPLE]SCPUCLK</ID><TXTSIZ>8</TXTSIZ><FNTNAM>Tahoma</FNTNAM><TXTCOL>11184640</TXTCOL><TXTBIR>000</TXTBIR><SHWLBL>1</SHWLBL><LBL>CPU Frequency</LBL><SHWUNT>1</SHWUNT><UNT> MHz</UNT><ITMX>0</ITMX><ITMY>0</ITMY>
 <ID>[SIMPLE]TCPU</ID><TXTSIZ>8</TXTSIZ><FNTNAM>Tahoma</FNTNAM><TXTCOL>11184640</TXTCOL><TXTBIR>000</TXTBIR><SHWLBL>1</SHWLBL><LBL>CPU Temperature</LBL><SHWUNT>1</SHWUNT><UNT>°C</UNT><ITMX>0</ITMX><ITMY>0</ITMY>
 <ID>[SIMPLE]SGPU1UTI</ID><TXTSIZ>8</TXTSIZ><FNTNAM>Tahoma</FNTNAM><TXTCOL>11184640</TXTCOL><TXTBIR>000</TXTBIR><SHWLBL>1</SHWLBL><LBL>GPU Usage</LBL><SHWUNT>1</SHWUNT><UNT>%</UNT><ITMX>0</ITMX><ITMY>0</ITMY>
 <ID>[SIMPLE]SGPU1CLK</ID><TXTSIZ>8</TXTSIZ><FNTNAM>Tahoma</FNTNAM><TXTCOL>11184640</TXTCOL><TXTBIR>000</TXTBIR><SHWLBL>1</SHWLBL><LBL>GPU Frequency</LBL><SHWUNT>1</SHWUNT><UNT> MHz</UNT><ITMX>0</ITMX><ITMY>0</ITMY>
 <ID>[SIMPLE]TGPU1</ID><TXTSIZ>8</TXTSIZ><FNTNAM>Tahoma</FNTNAM><TXTCOL>11184640</TXTCOL><TXTBIR>000</TXTBIR><SHWLBL>1</SHWLBL><LBL>GPU Temperature</LBL><SHWUNT>1</SHWUNT><UNT>°C</UNT><ITMX>0</ITMX><ITMY>0</ITMY>
 <ID>[SIMPLE]SMEMUTI</ID><TXTSIZ>8</TXTSIZ><FNTNAM>Tahoma</FNTNAM><TXTCOL>11184640</TXTCOL><TXTBIR>000</TXTBIR><SHWLBL>1</SHWLBL><LBL>Memory Usage</LBL><SHWUNT>1</SHWUNT><UNT>%</UNT><ITMX>0</ITMX><ITMY>0</ITMY>
</LCDPAGE1>
]=]

local function text_or(value, fallback)
  if value == nil then
    return fallback or ""
  end
  local text = tostring(value)
  if text == "" then
    return fallback or ""
  end
  return text
end

local function json_escape(text)
  text = tostring(text or "")
  text = text:gsub("\\", "\\\\")
  text = text:gsub("\"", "\\\"")
  text = text:gsub("\r", "\\r")
  text = text:gsub("\n", "\\n")
  return text
end

local function encode_json(value)
  if JSON and JSON.encode then
    local ok, raw = pcall(JSON.encode, value)
    if ok and raw then
      return raw
    end
  end

  return string.format(
    '{"ok":%s,"host":"%s","port":%d,"path":"%s","url":"%s","message":"%s"}',
    value.ok and "true" or "false",
    json_escape(value.host),
    tonumber(value.port) or 0,
    json_escape(value.path),
    json_escape(value.url),
    json_escape(value.message or value.error or "")
  )
end

local function url_decode(text)
  text = tostring(text or "")
  text = text:gsub("+", " ")
  text = text:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
  return text
end

local function parse_query(query)
  local out = {}
  for pair in tostring(query or ""):gmatch("([^&]+)") do
    local key, value = pair:match("^([^=]*)=(.*)$")
    if not key then
      key = pair
      value = ""
    end
    out[url_decode(key)] = url_decode(value)
  end
  return out
end

local function response(status, content_type, body, headers)
  local h = {
    ["cache-control"] = "no-store",
    ["connection"] = "close",
  }
  for k, v in pairs(headers or {}) do
    h[k] = v
  end
  return {
    status = status or "200 OK",
    type = content_type or "text/plain; charset=utf-8",
    headers = h,
    body = body or "",
  }
end

local function json_response(status, value)
  return response(status, "application/json; charset=utf-8", encode_json(value), {
    ["access-control-allow-origin"] = "*",
  })
end

local function js_string(text)
  text = tostring(text or "")
  text = text:gsub("\\", "\\\\")
  text = text:gsub("\"", "\\\"")
  return text
end

local function trim(text)
  return tostring(text or ""):match("^%s*(.-)%s*$") or ""
end

local function valid_ipv4(host)
  local a, b, c, d = tostring(host or ""):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  if not a then
    return false
  end
  local parts = { tonumber(a), tonumber(b), tonumber(c), tonumber(d) }
  for i = 1, 4 do
    if not parts[i] or parts[i] < 0 or parts[i] > 255 then
      return false
    end
  end
  return true
end

local function normalize_path(path)
  path = trim(path)
  if path == "" then
    return "/sse"
  end
  if path:sub(1, 1) ~= "/" then
    path = "/" .. path
  end
  return path
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

config.history_points = %d

config.thresholds = {
  warm_temp = %d,
  hot_temp = %d,
  warm_load = %d,
  hot_load = %d
}

config.metrics = {
  {
    id = "cpu_usage",
    title = "CPU",
    unit = "%%",
    kind = "percent",
    aliases = { "CPU Usage", "CPU Utilization" }
  },
  {
    id = "gpu_usage",
    title = "GPU",
    unit = "%%",
    kind = "percent",
    aliases = { "GPU Usage", "GPU1 Usage", "GPU Utilization" }
  },
  {
    id = "memory_usage",
    title = "RAM",
    unit = "%%",
    kind = "percent",
    aliases = { "Memory Usage", "Memory Utilization", "RAM Usage" }
  },
  {
    id = "vram_usage",
    title = "VRAM",
    unit = "%%",
    kind = "percent",
    aliases = { "GPU Memory Usage", "VRAM Usage", "Video Memory Usage" }
  },
  {
    id = "cpu_clock",
    title = "CPU Clock",
    unit = "MHz",
    kind = "clock",
    aliases = { "CPU Frequency", "CPU Clock", "CPU Core Clock" }
  },
  {
    id = "gpu_clock",
    title = "GPU Clock",
    unit = "MHz",
    kind = "clock",
    aliases = { "GPU Frequency", "GPU Clock", "GPU Core Clock" }
  },
  {
    id = "cpu_temp",
    title = "CPU Temp",
    unit = "C",
    kind = "temperature",
    aliases = { "CPU Temperature", "CPU Package", "CPU Diode" }
  },
  {
    id = "gpu_temp",
    title = "GPU Temp",
    unit = "C",
    kind = "temperature",
    aliases = { "GPU Temperature", "GPU Diode", "GPU1 Temperature" }
  },
  {
    id = "fan",
    title = "Fan",
    unit = "RPM",
    kind = "speed",
    aliases = { "CPU Fan", "GPU Fan", "Chassis Fan", "Fan" }
  }
}

return config
]=],
    tostring(config.host or "192.168.0.80"),
    tonumber(config.port) or 80,
    tostring(config.path or "/sse"),
    tonumber(config.timeout_ms) or 7000,
    tonumber(config.reconnect_ms) or 2000,
    tonumber(config.stale_ms) or 5000,
    tonumber(config.watchdog_ms) or 1000,
    config.serial_log == false and "false" or "true",
    tonumber(config.history_points) or 48,
    tonumber(config.thresholds and config.thresholds.warm_temp) or 70,
    tonumber(config.thresholds and config.thresholds.hot_temp) or 85,
    tonumber(config.thresholds and config.thresholds.warm_load) or 75,
    tonumber(config.thresholds and config.thresholds.hot_load) or 92
  )
end

local function write_config(path, config)
  local raw = config_text(config)
  if file and file.putcontents then
    local ok, ret = pcall(function()
      return file.putcontents(path, raw)
    end)
    if ok and ret ~= false then
      return true
    end
    return false, tostring(ret)
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
  api_prefix = js_string(api_prefix)
  return table.concat({
[=[<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>AIDA Monitor 控制台</title>
<style>
:root{color-scheme:light;--bg:#f4f7fb;--panel:#fff;--panel2:#f8fbff;--line:#dbe3ef;--text:#152033;--muted:#667085;--blue:#1476c8;--blue2:#eaf5ff;--green:#188a5c;--red:#d92d20;--shadow:0 16px 40px rgba(32,48,72,.08);--radius:8px}
*{box-sizing:border-box}
html,body{min-height:100%}
body{margin:0;background:linear-gradient(180deg,#fff 0%,var(--bg) 100%);color:var(--text);font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif}
button,input{font:inherit;color:inherit}
.page{width:min(980px,calc(100% - 32px));margin:0 auto;padding:24px 0 32px}
.top{display:flex;align-items:flex-end;justify-content:space-between;gap:16px;margin-bottom:14px}
h1{margin:0;font-size:28px;line-height:1.1;letter-spacing:0}
.summary{margin:6px 0 0;color:var(--muted)}
.main-link{min-height:40px;display:inline-flex;align-items:center;justify-content:center;padding:0 14px;border:1px solid var(--line);border-radius:var(--radius);background:#fff;color:var(--text);text-decoration:none}
.layout{display:grid;grid-template-columns:minmax(0,1fr) minmax(280px,.82fr);gap:14px}
.panel{padding:16px;border:1px solid var(--line);border-radius:var(--radius);background:linear-gradient(135deg,var(--panel),var(--panel2));box-shadow:var(--shadow)}
h2{margin:0 0 12px;font-size:18px;line-height:1.25;letter-spacing:0}
.form{display:grid;gap:12px}
.grid2{display:grid;grid-template-columns:1fr 140px;gap:10px}
label{display:block;margin-bottom:6px;color:var(--muted);font-size:13px;font-weight:700}
input{width:100%;min-height:44px;border:1px solid var(--line);border-radius:var(--radius);background:#fff;padding:0 11px;outline:none}
input:focus,button:focus-visible,.download:focus-visible{border-color:rgba(20,118,200,.55);box-shadow:0 0 0 4px rgba(20,118,200,.14)}
.actions{display:flex;flex-wrap:wrap;gap:8px;align-items:center}
button,.download{min-height:44px;border-radius:var(--radius);cursor:pointer;touch-action:manipulation}
button{border:1px solid var(--line);background:#fff;padding:0 14px}
.primary{border-color:transparent;background:linear-gradient(135deg,#1476c8,#46a3e8);color:#fff;font-weight:800;box-shadow:0 10px 22px rgba(20,118,200,.2)}
.download{display:inline-flex;align-items:center;justify-content:center;padding:0 14px;border:1px solid rgba(24,138,92,.28);background:#edf9f4;color:var(--green);font-weight:800;text-decoration:none}
.status{min-height:24px;color:var(--muted);font-size:13px}
.status.ok{color:var(--green)}.status.error{color:var(--red)}
.steps{display:grid;gap:9px;margin:0;padding:0;list-style:none}
.steps li{display:grid;grid-template-columns:28px minmax(0,1fr);gap:8px;color:var(--muted);font-size:13px}
.num{display:grid;place-items:center;width:28px;height:28px;border-radius:var(--radius);background:var(--blue2);color:var(--blue);font-weight:850}
.steps strong{display:block;color:var(--text);font-size:14px}
.code{display:block;margin-top:6px;padding:8px 10px;border-radius:var(--radius);background:#111827;color:#e5eefb;font:12px/1.45 ui-monospace,SFMono-Regular,Consolas,"Liberation Mono",monospace;overflow-wrap:anywhere}
.note{margin:12px 0 0;padding:10px;border-left:3px solid var(--blue);border-radius:var(--radius);background:#eef6ff;color:#385c7e;font-size:13px}
.footer{margin-top:14px;color:#8a94a6;font-size:12px;text-align:center}
@media(max-width:760px){.page{width:min(100% - 20px,980px);padding-top:14px}.top{align-items:flex-start}.layout{grid-template-columns:1fr}.grid2{grid-template-columns:1fr}h1{font-size:24px}}
</style>
</head>
<body>
<main class="page">
  <header class="top">
    <div>
      <h1>AIDA Monitor 控制台</h1>
      <p class="summary">设置 AIDA64 所在电脑 IP，并下载可导入的 LCD 配置。</p>
    </div>
    <a class="main-link" href="/main">返回主界面</a>
  </header>

  <section class="layout">
    <section class="panel" aria-labelledby="config-title">
      <h2 id="config-title">连接设置</h2>
      <form class="form" id="configForm">
        <div class="grid2">
          <div>
            <label for="hostInput">电脑 IP</label>
            <input id="hostInput" name="host" inputmode="decimal" autocomplete="off" placeholder="192.168.0.80" required>
          </div>
          <div>
            <label for="portInput">端口</label>
            <input id="portInput" name="port" inputmode="numeric" autocomplete="off" placeholder="80" required>
          </div>
        </div>
        <div>
          <label for="pathInput">SSE 路径</label>
          <input id="pathInput" name="path" autocomplete="off" placeholder="/sse">
        </div>
        <div class="actions">
          <button class="primary" type="submit">保存并重连</button>
          <button type="button" id="testUrl">打开数据地址</button>
        </div>
        <div class="status" id="statusLine" role="status" aria-live="polite">正在读取配置...</div>
      </form>
    </section>

    <aside class="panel" aria-labelledby="aida-title">
      <h2 id="aida-title">AIDA64 设置方法</h2>
      <ol class="steps">
        <li><span class="num">1</span><span><strong>下载配置文件</strong><span>保存 holo-aida.rslcd，然后在 AIDA64 的 设置 > LCD > LCD 项目 > 导入 中导入。</span></span></li>
        <li><span class="num">2</span><span><strong>开启 RemoteSensor</strong><span>进入 File > Preferences > Hardware Monitoring > LCD，启用 RemoteSensor / LCD 支持。</span></span></li>
        <li><span class="num">3</span><span><strong>确认数据输出</strong><span>在电脑浏览器打开下面地址，应该看到 data: 开头的内容。</span><code class="code" id="urlPreview">http://--:80/sse</code></span></li>
      </ol>
      <p class="note">如果只看到 data: ReLoad，请在 LCD 项目中导入配置后点击 Apply。</p>
      <p class="actions"><a class="download" id="downloadLink" href="]=], api_prefix, [=[/download" download="holo-aida.rslcd">下载 holo-aida.rslcd</a></p>
    </aside>
  </section>

  <div class="footer">Open source license: GPL-3.0 · github.com/clocteck</div>
</main>

<script>
const API = "]=], api_prefix, [=[";
const hostInput = document.getElementById("hostInput");
const portInput = document.getElementById("portInput");
const pathInput = document.getElementById("pathInput");
const statusLine = document.getElementById("statusLine");
const urlPreview = document.getElementById("urlPreview");
const downloadLink = document.getElementById("downloadLink");

function setStatus(text, tone){
  statusLine.textContent = text || "";
  statusLine.className = "status " + (tone || "");
}

function normalizePath(value){
  value = (value || "").trim();
  if(!value) return "/sse";
  return value[0] === "/" ? value : "/" + value;
}

function currentUrl(){
  const host = hostInput.value.trim() || "--";
  const port = portInput.value.trim() || "80";
  const path = normalizePath(pathInput.value);
  return "http://" + host + ":" + port + path;
}

function syncPreview(){
  urlPreview.textContent = currentUrl();
}

async function loadState(){
  const res = await fetch(API + "/state?_=" + Date.now(), {cache:"no-store"});
  if(!res.ok) throw new Error("HTTP " + res.status);
  const data = await res.json();
  hostInput.value = data.host || "";
  portInput.value = data.port || 80;
  pathInput.value = data.path || "/sse";
  downloadLink.href = API + "/download";
  syncPreview();
  setStatus("当前配置已载入。", "ok");
}

async function saveConfig(ev){
  ev.preventDefault();
  syncPreview();
  setStatus("正在保存...", "");
  const params = new URLSearchParams({
    host: hostInput.value.trim(),
    port: portInput.value.trim(),
    path: normalizePath(pathInput.value)
  });
  const res = await fetch(API + "/save?" + params.toString(), {cache:"no-store"});
  const data = await res.json();
  if(!res.ok || !data.ok){
    throw new Error(data.error || data.message || "保存失败");
  }
  hostInput.value = data.host || hostInput.value;
  portInput.value = data.port || portInput.value;
  pathInput.value = data.path || pathInput.value;
  syncPreview();
  setStatus("已保存，AIDA Monitor 正在按新地址重连。", "ok");
}

document.getElementById("configForm").addEventListener("submit", (ev) => {
  saveConfig(ev).catch((err) => setStatus(err.message, "error"));
});
document.getElementById("testUrl").addEventListener("click", () => {
  syncPreview();
  window.open(currentUrl(), "_blank", "noopener");
});
[hostInput, portInput, pathInput].forEach((input) => input.addEventListener("input", syncPreview));

loadState().catch((err) => setStatus("配置读取失败：" + err.message, "error"));
</script>
</body>
</html>
]=]
  })
end

function Web.new(opts)
  opts = opts or {}
  local self = {
    config = opts.config or {},
    config_path = opts.config_path or "/sd/apps/aida_monitor/config.lua",
    route_base = opts.route_base or "/aida_monitor",
    api_prefix = (opts.route_base or "/aida_monitor") .. "/api",
    restart = opts.restart,
    routes = {},
    started = false,
  }

  function self:snapshot(ok, message)
    local host = tostring(self.config.host or "")
    local port = tonumber(self.config.port) or 80
    local path = normalize_path(self.config.path or "/sse")
    return {
      ok = ok ~= false,
      host = host,
      port = port,
      path = path,
      url = "http://" .. host .. ":" .. tostring(port) .. path,
      message = message or "",
    }
  end

  function self:register(method, route, handler)
    if not httpd or not httpd.dynamic then
      return false, "httpd missing"
    end
    local ok, err = pcall(function()
      return httpd.dynamic(method, route, handler)
    end)
    if not ok then
      return false, tostring(err)
    end
    if err then
      return false, tostring(err)
    end
    self.routes[#self.routes + 1] = { method = method, route = route }
    return true
  end

  function self:route_index(req)
    return response("200 OK", "text/html; charset=utf-8", build_html(self.api_prefix))
  end

  function self:route_state(req)
    return json_response("200 OK", self:snapshot(true, "loaded"))
  end

  function self:route_save(req)
    local q = parse_query(req and req.query or "")
    local host = trim(q.host)
    local port = tonumber(q.port) or 80
    local path = normalize_path(q.path)

    if not valid_ipv4(host) then
      return json_response("400 Bad Request", {
        ok = false,
        host = self.config.host,
        port = self.config.port,
        path = self.config.path,
        error = "请输入有效的 IPv4 地址",
      })
    end
    if port < 1 or port > 65535 then
      return json_response("400 Bad Request", {
        ok = false,
        host = self.config.host,
        port = self.config.port,
        path = self.config.path,
        error = "端口需在 1 到 65535 之间",
      })
    end

    self.config.host = host
    self.config.port = math.floor(port)
    self.config.path = path

    local ok, err = write_config(self.config_path, self.config)
    if not ok then
      return json_response("500 Internal Server Error", {
        ok = false,
        host = host,
        port = port,
        path = path,
        error = "配置写入失败: " .. text_or(err, "unknown"),
      })
    end

    if self.restart then
      pcall(self.restart)
    end

    return json_response("200 OK", self:snapshot(true, "saved"))
  end

  function self:route_download(req)
    return response("200 OK", "application/octet-stream", RSLCD, {
      ["content-disposition"] = "attachment; filename=\"holo-aida.rslcd\"",
    })
  end

  function self:start()
    if self.started then
      return
    end
    if not httpd or not httpd.start then
      return
    end

    pcall(function()
      httpd.start({
        webroot = "/sd",
        auto_index = httpd.INDEX_NONE,
        max_handlers = 32,
      })
    end)

    self:register(httpd.GET, self.route_base, function(req) return self:route_index(req) end)
    self:register(httpd.GET, self.route_base .. "/", function(req) return self:route_index(req) end)
    self:register(httpd.GET, self.api_prefix .. "/state", function(req) return self:route_state(req) end)
    self:register(httpd.GET, self.api_prefix .. "/save", function(req) return self:route_save(req) end)
    self:register(httpd.GET, self.api_prefix .. "/download", function(req) return self:route_download(req) end)
    self:register(httpd.GET, self.api_prefix .. "/health", function(req)
      return response("200 OK", "text/plain; charset=utf-8", "ok")
    end)

    self.started = true
  end

  function self:stop(reason)
    if httpd and httpd.unregister then
      for i = #self.routes, 1, -1 do
        local item = self.routes[i]
        pcall(function() httpd.unregister(item.method, item.route) end)
      end
    end
    self.routes = {}
    self.started = false
  end

  return self
end

return Web
