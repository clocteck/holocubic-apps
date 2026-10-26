-- Web configuration module for Ollama Usage app.
-- Mimics the BTC web.lua pattern: serves an HTML config page at the app's
-- route_base and exposes JSON APIs to read/save the API key.
--
-- Routes:
--   GET  <route_base>              -> config HTML page
--   GET  <route_base>/             -> config HTML page
--   GET  <route_base>/logo.png     -> Ollama logo image
--   GET  <route_base>/api/state    -> {ok, has_key, last_error, session_usage, weekly_usage, updated}
--   GET  <route_base>/api/key      -> {ok, has_key, key_preview}
--   POST <route_base>/api/key      -> body=raw key text, saves to api_key.txt
--   POST <route_base>/api/refresh  -> triggers an immediate usage fetch

local Web = {}

local JSON = rawget(_G, "sjson") or rawget(_G, "json")

local function text_or(value, fallback)
  if value == nil then return fallback or "" end
  local text = tostring(value)
  if text == "" then return fallback or "" end
  return text
end

local function json_response(status, value)
  local ok, raw, err = pcall(function() return JSON.encode(value) end)
  if not ok or not raw then
    status = "500 Internal Server Error"
    raw = string.format("{\"ok\":false,\"error\":%q}", text_or(err, "json encode failed"))
  end
  return {
    status = status or "200 OK",
    type = "application/json; charset=utf-8",
    headers = {
      ["cache-control"] = "no-store",
      ["connection"] = "close",
      ["access-control-allow-origin"] = "*",
    },
    body = raw,
  }
end

local function text_response(status, content_type, body)
  return {
    status = status or "200 OK",
    type = content_type or "text/plain; charset=utf-8",
    headers = {
      ["cache-control"] = "no-store",
      ["connection"] = "close",
    },
    body = body or "",
  }
end

local function js_string(text)
  text = tostring(text or "")
  text = text:gsub("\\", "\\\\")
  text = text:gsub("\"", "\\\"")
  return text
end

local function read_request_body(req, max_bytes)
  if not req or not req.getbody then return nil end
  local parts = {}
  local total = 0
  while true do
    local chunk = req.getbody()
    if not chunk then break end
    total = total + #chunk
    if max_bytes and total > max_bytes then
      return nil, "request body too large"
    end
    parts[#parts + 1] = chunk
  end
  return table.concat(parts)
end

-- Read an entire binary file from /sd path. Returns raw string or nil.
local function read_file_bytes(path)
  if not file then return nil end
  if file.getcontents then
    local ok, raw = pcall(function() return file.getcontents(path) end)
    if ok and type(raw) == "string" then return raw end
  end
  if not file.open then return nil end
  local fd = file.open(path, "r")
  if not fd then return nil end
  -- Binary-safe read: use "rb" mode if supported, otherwise plain "r".
  local chunks = {}
  while true do
    local part = fd:read(1024)
    if not part or part == "" then break end
    chunks[#chunks + 1] = part
  end
  pcall(function() fd:close() end)
  return table.concat(chunks)
end

local function binary_response(status, content_type, body)
  return {
    status = status or "200 OK",
    type = content_type or "application/octet-stream",
    headers = {
      ["cache-control"] = "public, max-age=3600",
      ["connection"] = "close",
    },
    body = body or "",
  }
end

local function build_html(api_prefix)
  api_prefix = js_string(api_prefix)
  return table.concat({
[==[<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Ollama Usage</title>
<style>
:root{
  color-scheme:light;
  --bg:#eef3fb;
  --panel:#ffffff;
  --line:rgba(15,23,42,.11);
  --text:#111827;
  --muted:#64748b;
  --dim:#94a3b8;
  --green:#16a34a;
  --green-soft:#dcfce7;
  --red:#e2553f;
  --red-soft:#ffe4dd;
  --blue:#0a84ff;
  --blue-soft:#eff5ff;
  --radius:8px;
}
*{box-sizing:border-box}
html,body{min-height:100%}
body{
  margin:0;
  background:linear-gradient(180deg,#f7faff 0%,var(--bg) 100%);
  color:var(--text);
  font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
}
main{max-width:640px;margin:0 auto;padding:24px 16px 48px}
h1{margin:0 0 4px;font-size:22px;font-weight:600}
.sub{color:var(--muted);margin:0 0 24px}
.card{
  background:var(--panel);
  border:1px solid var(--line);
  border-radius:var(--radius);
  padding:20px;
  margin-bottom:16px;
}
.card h2{margin:0 0 12px;font-size:15px;font-weight:600;color:var(--text)}
label{display:block;font-size:13px;color:var(--muted);margin:0 0 6px;font-weight:500}
input[type="text"],input[type="password"]{
  width:100%;padding:10px 12px;font:14px/1.4 inherit;
  border:1px solid var(--line);border-radius:6px;background:#fff;color:var(--text);
  outline:none;transition:border-color .15s;
}
input:focus{border-color:var(--blue)}
button{
  padding:9px 16px;font:14px/1.4 inherit;font-weight:500;
  border:0;border-radius:6px;cursor:pointer;transition:background .15s;
}
button.primary{background:var(--blue);color:#fff}
button.primary:hover{background:#0974e4}
button.ghost{background:transparent;color:var(--muted);border:1px solid var(--line)}
button.ghost:hover{background:#f1f5f9}
.row{display:flex;gap:10px;margin-top:12px;align-items:center;flex-wrap:wrap}
.hint{font-size:12px;color:var(--muted);margin:8px 0 0}
.err{font-size:12px;color:var(--red);margin:8px 0 0}
.ok{font-size:12px;color:var(--green);margin:8px 0 0}
.status{display:inline-block;padding:2px 8px;border-radius:999px;font-size:12px;font-weight:500}
.status.idle{background:#e2e8f0;color:#475569}
.status.ok{background:var(--green-soft);color:var(--green)}
.status.err{background:var(--red-soft);color:var(--red)}
.usage-grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:12px}
.usage-tile{background:#f8fafc;border:1px solid var(--line);border-radius:6px;padding:14px;text-align:center}
.usage-tile .label{font-size:12px;color:var(--muted);margin:0 0 4px}
.usage-tile .value{font-size:22px;font-weight:600;color:var(--text)}
.mono{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
</style>
</head>
<body>
<main>
  <h1><img src="logo.png" alt="Ollama" style="width:28px;height:28px;vertical-align:middle;margin-right:8px">Ollama Usage</h1>
  <p class="sub">Configure your Ollama Cloud API key and monitor usage limits.</p>

  <section class="card">
    <h2>API Key</h2>
    <label for="apiKey">Ollama API Key</label>
    <input type="password" id="apiKey" placeholder="Paste your OLLAMA_API_KEY here" autocomplete="off">
    <div class="row">
      <button class="primary" id="saveBtn">Save</button>
      <button class="ghost" id="refreshBtn">Refresh now</button>
    </div>
    <div class="hint" id="keyHint">Loading key status...</div>
  </section>

  <section class="card">
    <h2>Usage</h2>
    <div class="usage-grid">
      <div class="usage-tile">
        <div class="label">Session</div>
        <div class="value mono" id="sessionUsage">--</div>
      </div>
      <div class="usage-tile">
        <div class="label">Weekly</div>
        <div class="value mono" id="weeklyUsage">--</div>
      </div>
    </div>
    <div class="row">
      <span class="status idle" id="statusBadge">idle</span>
      <span class="hint" id="updatedText"></span>
    </div>
  </section>
</main>

<script>
const API = "]==], api_prefix, [==[";
const els = {
  apiKey: document.getElementById("apiKey"),
  saveBtn: document.getElementById("saveBtn"),
  refreshBtn: document.getElementById("refreshBtn"),
  keyHint: document.getElementById("keyHint"),
  sessionUsage: document.getElementById("sessionUsage"),
  weeklyUsage: document.getElementById("weeklyUsage"),
  statusBadge: document.getElementById("statusBadge"),
  updatedText: document.getElementById("updatedText"),
};

function setStatus(kind, text){
  els.statusBadge.className = "status " + kind;
  els.statusBadge.textContent = text;
}

async function loadKey(){
  try{
    const r = await fetch(API + "/key");
    const d = await r.json();
    if(d.ok){
      els.keyHint.textContent = d.has_key
        ? "Key stored (preview: " + (d.key_preview || "") + ")"
        : "No key configured yet. Paste it above and click Save.";
    } else {
      els.keyHint.textContent = d.error || "Failed to read key status.";
    }
  }catch(e){
    els.keyHint.textContent = "Request failed: " + (e.message || e);
  }
}

async function loadState(){
  try{
    const r = await fetch(API + "/state");
    const d = await r.json();
    if(!d.ok){
      setStatus("err", "error");
      els.sessionUsage.textContent = "--";
      els.weeklyUsage.textContent = "--";
      els.updatedText.textContent = d.error || "";
      return;
    }
    if(d.last_error){
      setStatus("err", "error");
      els.updatedText.textContent = d.last_error;
    } else if(d.has_key){
      setStatus("ok", "ok");
    } else {
      setStatus("idle", "no key");
    }
    els.sessionUsage.textContent = d.session_usage || "--";
    els.weeklyUsage.textContent = d.weekly_usage || "--";
    if(d.updated){
      els.updatedText.textContent = "Updated: " + d.updated;
    }
  }catch(e){
    setStatus("err", "error");
    els.updatedText.textContent = "Request failed: " + (e.message || e);
  }
}

async function saveKey(){
  const key = els.apiKey.value;
  if(!key || key.trim() === ""){
    els.keyHint.className = "err";
    els.keyHint.textContent = "Please enter an API key first.";
    return;
  }
  els.saveBtn.disabled = true;
  els.keyHint.className = "hint";
  els.keyHint.textContent = "Saving...";
  try{
    const r = await fetch(API + "/key", {
      method: "POST",
      headers: { "Content-Type": "text/plain; charset=utf-8" },
      body: key.trim(),
    });
    const d = await r.json();
    if(d.ok){
      els.keyHint.className = "ok";
      els.keyHint.textContent = "Saved.";
      els.apiKey.value = "";
      await loadState();
    } else {
      els.keyHint.className = "err";
      els.keyHint.textContent = d.error || "Save failed.";
    }
  }catch(e){
    els.keyHint.className = "err";
    els.keyHint.textContent = "Request failed: " + (e.message || e);
  }finally{
    els.saveBtn.disabled = false;
  }
}

async function refreshNow(){
  els.refreshBtn.disabled = true;
  try{
    await fetch(API + "/refresh", { method: "POST" });
    await loadState();
  }catch(e){
    setStatus("err", "error");
    els.updatedText.textContent = "Refresh failed: " + (e.message || e);
  }finally{
    els.refreshBtn.disabled = false;
  }
}

els.saveBtn.addEventListener("click", saveKey);
els.refreshBtn.addEventListener("click", refreshNow);
loadKey();
loadState();
setInterval(loadState, 10000);
</script>
</body>
</html>
]==]
  })
end

function Web.new(app, opts)
  opts = opts or {}
  local self = {
    app = app,
    route_base = opts.route_base or "/ollama_usage",
    api_prefix = (opts.route_base or "/ollama_usage") .. "/api",
    routes = {},
    started = false,
  }

  function self:register(method, route, handler)
    if not httpd or not httpd.dynamic then
      return false, "httpd missing"
    end
    local ok, err = pcall(function() return httpd.dynamic(method, route, handler) end)
    if not ok then return false, tostring(err) end
    if err then return false, tostring(err) end
    self.routes[#self.routes + 1] = { method = method, route = route }
    return true, nil
  end

function self:route_index(req)
  return text_response("200 OK", "text/html; charset=utf-8", build_html(self.api_prefix))
end

function self:route_logo(req)
  local logo_path = "/sd/apps/ollama_usage/ollama.png"
  local raw = read_file_bytes(logo_path)
  if not raw or raw == "" then
    return text_response("404 Not Found", "text/plain; charset=utf-8", "logo not found")
  end
  return binary_response("200 OK", "image/png", raw)
end

  function self:route_state(req)
    local app = self.app
    local has_key = false
    if app and app.has_api_key then
      has_key = app.has_api_key()
    end
    return json_response("200 OK", {
      ok = true,
      has_key = has_key,
      session_usage = app and app.state and app.state.session_usage or "--",
      weekly_usage = app and app.state and app.state.weekly_usage or "--",
      last_error = app and app.state and app.state.last_error or nil,
      updated = app and app.state and app.state.last_update_text or "",
    })
  end

  function self:route_key_get(req)
    local app = self.app
    local has_key = false
    local preview = ""
    if app and app.get_api_key_preview then
      has_key, preview = app.get_api_key_preview()
    end
    return json_response("200 OK", {
      ok = true,
      has_key = has_key,
      key_preview = preview,
    })
  end

  function self:route_key_set(req)
    local body, err = read_request_body(req, 4096)
    if not body then
      return json_response("400 Bad Request", { ok = false, error = text_or(err, "empty body") })
    end
    body = body:match("^%s*(.-)%s*$") or ""
    if body == "" then
      return json_response("400 Bad Request", { ok = false, error = "key must not be empty" })
    end
    local app = self.app
    if not app or not app.save_api_key then
      return json_response("500 Internal Server Error", { ok = false, error = "app cannot save key" })
    end
    local ok, save_err = app.save_api_key(body)
    if not ok then
      return json_response("500 Internal Server Error", { ok = false, error = text_or(save_err, "save failed") })
    end
    return json_response("200 OK", { ok = true })
  end

  function self:route_refresh(req)
    local app = self.app
    if app and app.fetch_usage then
      pcall(function() app.fetch_usage() end)
    end
    return json_response("200 OK", { ok = true })
  end

  function self:start()
    if self.started then return end
    if not httpd or not httpd.start then return end

    pcall(function()
      httpd.start({
        webroot = "/sd",
        auto_index = httpd.INDEX_NONE,
        max_handlers = 32,
      })
    end)

    self:register(httpd.GET, self.route_base, function(req) return self:route_index(req) end)
    self:register(httpd.GET, self.route_base .. "/", function(req) return self:route_index(req) end)
    self:register(httpd.GET, self.route_base .. "/logo.png", function(req) return self:route_logo(req) end)
    self:register(httpd.GET, self.api_prefix .. "/state", function(req) return self:route_state(req) end)
    self:register(httpd.GET, self.api_prefix .. "/key", function(req) return self:route_key_get(req) end)
    self:register(httpd.POST, self.api_prefix .. "/key", function(req) return self:route_key_set(req) end)
    self:register(httpd.POST, self.api_prefix .. "/refresh", function(req) return self:route_refresh(req) end)

    if app and app.set_webui then
      pcall(function() app.set_webui(true) end)
    end
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
    if app and app.set_webui then
      pcall(function() app.set_webui(false) end)
    end
    self.started = false
  end

  return self
end

return Web