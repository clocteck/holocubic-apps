local M = {}

local PAGE = [=[<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>小智助手</title>
  <style>
    body{margin:0;background:#0f172a;color:#f8fafc;font:16px/1.5 system-ui}
    .wrap{max-width:680px;margin:auto;padding:24px}
    .card{background:#1e293b;border:1px solid #475569;border-radius:8px;padding:20px;margin:14px 0}
    .code{font-size:42px;font-weight:800;letter-spacing:10px;color:#c4b5fd}
    .muted{color:#cbd5e1;word-break:break-all}
    .hint{margin:0;color:#94a3b8;font-size:12px}
    .err{color:#fca5a5}
    .dot{display:inline-block;width:10px;height:10px;border-radius:50%;background:#64748b;margin-right:8px}
    .on{background:#22c55e}
    button{min-height:48px;border:0;border-radius:8px;padding:12px 18px;background:#8b5cf6;color:white;font-weight:700;font-size:16px;cursor:pointer;touch-action:manipulation;transition:opacity .15s ease,background .15s ease}
    button:hover{background:#7c3aed}
    button:active{background:#6d28d9}
    button:focus-visible,input:focus-visible,select:focus-visible{outline:3px solid #c4b5fd;outline-offset:2px}
    button:disabled{opacity:.45;cursor:not-allowed}
    .secondary{background:#475569}
    .secondary:hover{background:#64748b}
    .linkbtn{display:block;min-height:44px;margin-top:10px;padding:8px 2px;background:transparent;color:#94a3b8;font-size:13px;font-weight:500}
    .linkbtn:hover,.linkbtn:active{background:transparent;color:#cbd5e1}
    .volume{display:grid;grid-template-columns:minmax(0,1fr) 64px;align-items:center;gap:16px;margin-top:16px}
    .volume input{width:100%;height:44px;margin:0;accent-color:#8b5cf6;cursor:pointer;touch-action:pan-x}
    .volume output{text-align:right;font-size:22px;font-weight:700;font-variant-numeric:tabular-nums}
    .advanced{display:grid;gap:12px;margin-top:10px;padding-top:16px;border-top:1px solid #475569}
    .advanced[hidden]{display:none}
    .field{display:grid;gap:5px;color:#cbd5e1;font-size:14px}
    input,select{box-sizing:border-box;width:100%;min-height:44px;border:1px solid #64748b;border-radius:8px;padding:10px 12px;background:#0f172a;color:#f8fafc;font:16px system-ui}
    .grid2{display:grid;grid-template-columns:1fr 1fr;gap:12px}
    .checks{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:8px;margin-top:12px}
    .check{display:flex;align-items:center;gap:8px;min-height:36px;color:#cbd5e1;font-size:14px}
    .check input{width:18px;min-height:18px;height:18px;margin:0;accent-color:#8b5cf6}
    @media(max-width:560px){.wrap{padding:16px}.grid2{grid-template-columns:1fr}.code{font-size:34px;letter-spacing:7px}}
    @media(prefers-reduced-motion:reduce){button{transition:none}}
  </style>
</head>
<body>
<main class="wrap">
  <h1>小智助手</h1>
  <section class="card">
    <div><i id="dot" class="dot"></i><b id="status">读取状态…</b></div>
    <p id="message" class="muted" aria-live="polite"></p>
    <div id="code" class="code"></div>
  </section>

  <section class="card">
    <b>播放音量</b>
    <div class="volume">
      <input id="volumeSlider" type="range" min="0" max="100" step="1" value="100" aria-label="播放音量">
      <output id="volume" for="volumeSlider">100%</output>
    </div>
  </section>

  <section class="card">
    <b>官方服务</b>
    <p class="muted">配对码请在小智控制台的“添加设备”中输入。绑定成功后，设备会自动保存官方下发的 WebSocket 地址。</p>
    <p id="server" class="muted"></p>
    <button id="pair">重新获取配对码</button>
    <button id="customToggle" class="linkbtn" aria-expanded="false" aria-controls="customPanel">自定义服务</button>
    <div id="customPanel" class="advanced" hidden>
      <label class="field">OTA 地址<input id="customOtaUrl" type="url" inputmode="url" required placeholder="https://api.tenclass.net/xiaozhi/ota/"></label>
      <label class="field">WebSocket 地址（可选）<input id="customUrl" type="url" inputmode="url" placeholder="wss://example.com/xiaozhi/v1/"></label>
      <label class="field">访问 Token（留空即清除）<input id="customToken" type="password" autocomplete="off" placeholder="可选"></label>
      <label class="field">协议版本<select id="customVersion"><option value="1">1</option><option value="2">2</option><option value="3">3</option></select></label>
      <button id="saveCustom">保存自定义服务</button>
      <label class="field">设备 MAC<input id="deviceMac" type="text" inputmode="text" autocomplete="off" placeholder="02:12:34:56:78:9a"></label>
      <p class="hint">修改 MAC 会切换为新的设备身份；使用官方服务时必须用新配对码重新配对。</p>
      <button id="saveMac" class="secondary">保存设备 MAC</button>
    </div>
  </section>

  <section class="card">
    <b>主应用 UI</b>
    <!--p class="muted">这里写入 /sd/apps/xiaozhi/config.json，控制打开小智前台 App 时使用的界面。</p-->
    <label class="field">界面类型
      <select id="appUiType"></select>
    </label>
    <p class="hint">保存后重新打开前台生效。选项来自 /sd/apps/xiaozhi/ui 。</p>
  </section>

  <section class="card">
    <b>后台服务 UI</b>
    <!--p class="muted">这里写入 /sd/apps/xiaozhi-service/service.json，控制后台唤醒后的呈现方式。</p-->
    <label class="check"><input id="wakeEnabled" type="checkbox">启用后台唤醒</label>
    <div class="grid2">
      <label class="field">呈现模式
        <select id="serviceUiMode">
          <option value="app">打开小智 App</option>
          <option value="floating">悬浮显示</option>
        </select>
      </label>
      <label class="field"></label>
      <label class="field">悬浮界面类型
        <select id="serviceUiType"></select>
      </label>
      <label class="field">悬浮角色
        <select id="serviceUiCharacter"></select>
      </label>
      <p class="hint">保存后立即生效。选项来自 /sd/apps/xiaozhi-service/ui。</p>
    </div>
    <label class="field">退避 App
      <div id="denyApps" class="checks"></div>
    </label>
    <p class="hint">勾选后，这些 App 在前台运行时会暂停小智后台唤醒/音频，避免资源冲突。</p>
    <button id="saveUi">保存 UI 配置</button>
  </section>
</main>
<script>
const q=s=>document.querySelector(s);
let volume=100,volumeTimer=0,serverLoaded=false,uiLoaded=false;
async function api(p,o){let r=await fetch(p,o);let j=await r.json();if(!r.ok)throw Error(j.error||r.status);return j}
function optionLabel(v){return v==='window'?'小窗模式':(v==='subtitle'?'字幕模式':(v==='wechat'?'微信气泡':(v==='assistant'?'助手形象':v)))}
function fillOptions(el,items,value,fallback){items=Array.isArray(items)?items:[];if(!items.length)items=[fallback||'subtitle'];el.innerHTML='';let seen={};items.forEach(v=>{v=String(v||'').trim();if(!v||seen[v])return;seen[v]=1;let o=document.createElement('option');o.value=v;o.textContent=optionLabel(v);el.appendChild(o)});if(value&&seen[value])el.value=value;else if(seen[fallback])el.value=fallback;else el.selectedIndex=0}
function fillDenyApps(options,selected){let box=q('#denyApps');options=Array.isArray(options)?options:[];selected=selected||{};box.innerHTML='';options.forEach(item=>{let id=String((item&&item.id)||item||'').trim();if(!id)return;let name=String((item&&item.name)||id);let label=document.createElement('label');label.className='check';let input=document.createElement('input');input.type='checkbox';input.value=id;input.checked=selected[id]===true;let span=document.createElement('span');span.textContent=name===id?id:(name+' · '+id);label.appendChild(input);label.appendChild(span);box.appendChild(label)})}
function collectDenyApps(){let out={};document.querySelectorAll('#denyApps input[type=checkbox]').forEach(i=>{if(i.checked)out[i.value]=true});return out}
function syncServiceUiDisabled(){let floating=q('#serviceUiMode').value==='floating';q('#serviceUiType').disabled=!floating;q('#serviceUiCharacter').disabled=!floating||q('#serviceUiType').value!=='assistant'}
async function pushWakeEnabled(v){try{let s=await api('./api/wake',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({enabled:v})});q('#wakeEnabled').checked=s.wake_service_enabled===true;q('#message').textContent=s.wake_service_enabled?'后台唤醒已开启':'后台唤醒已关闭'}catch(e){q('#message').textContent=e.message;refresh()}}
function showVolume(v){volume=Math.max(0,Math.min(100,Number(v)||0));q('#volumeSlider').value=String(volume);q('#volume').textContent=volume+'%'}
function pushVolume(v){fetch('./api/volume',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({volume:v}),keepalive:true}).catch(()=>{})}
function queueVolume(v,now){showVolume(v);clearTimeout(volumeTimer);if(now)pushVolume(volume);else volumeTimer=setTimeout(()=>pushVolume(volume),150)}
async function refresh(){
  try{
    let s=await api('./api/state');
    q('#status').textContent=s.connected?'已连接服务':(s.activation_status||'等待连接');
    q('#dot').className='dot '+(s.connected?'on':'');
    q('#message').textContent=s.message||s.last_error||'';
    q('#code').textContent=s.pairing_code||'';
    q('#server').textContent=s.websocket_url?'服务器：'+s.websocket_url:'尚未绑定设备';
    if(document.activeElement!==q('#volumeSlider'))showVolume(s.volume==null?100:s.volume);
    if(!serverLoaded){
      q('#customOtaUrl').value=s.ota_url||'https://api.tenclass.net/xiaozhi/ota/';
      q('#customUrl').value=s.websocket_url||'';
      q('#customVersion').value=String(s.websocket_version||1);
      q('#customToken').placeholder=s.websocket_token_set?'已设置；留空将清除':'可选';
      q('#deviceMac').value=s.device_mac||'';
      serverLoaded=true;
    }
    if(!uiLoaded){
      fillOptions(q('#appUiType'),s.ui_options&&s.ui_options.app,s.app_ui_type,'subtitle');
      q('#serviceUiMode').value=s.service_ui_mode==='floating'?'floating':'app';
      fillOptions(q('#serviceUiType'),s.ui_options&&s.ui_options.float,s.service_ui_type,'window');
      fillOptions(q('#serviceUiCharacter'),s.ui_options&&s.ui_options.characters,s.service_ui_character,'xiaozhi_chibi');
      fillDenyApps(s.deny_app_options,s.deny_apps);
      q('#wakeEnabled').checked=s.wake_service_enabled===true;
      syncServiceUiDisabled();
      uiLoaded=true;
    }
  }catch(e){
    q('#status').textContent='状态读取失败';
    q('#message').textContent=e.message;
    q('#message').className='muted err';
  }
}
q('#volumeSlider').oninput=e=>queueVolume(e.target.value,false);
q('#volumeSlider').onchange=e=>queueVolume(e.target.value,true);
q('#customToggle').onclick=()=>{let p=q('#customPanel'),open=p.hidden;p.hidden=!open;q('#customToggle').setAttribute('aria-expanded',String(open));if(open)q('#customOtaUrl').focus()};
q('#serviceUiMode').onchange=syncServiceUiDisabled;
q('#serviceUiType').onchange=syncServiceUiDisabled;
q('#wakeEnabled').onchange=e=>pushWakeEnabled(e.target.checked);
q('#saveCustom').onclick=async()=>{let b=q('#saveCustom');b.disabled=true;try{let s=await api('./api/server',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({ota_url:q('#customOtaUrl').value,url:q('#customUrl').value,token:q('#customToken').value,version:Number(q('#customVersion').value)})});q('#message').textContent='自定义服务已保存，唤醒后连接';q('#server').textContent=s.url?'服务器：'+s.url:'OTA：'+s.ota_url;q('#customToken').value='';q('#customToken').placeholder=s.token_set?'已设置；留空将清除':'可选'}catch(e){q('#message').textContent=e.message}finally{b.disabled=false}};
q('#saveMac').onclick=async()=>{let b=q('#saveMac');b.disabled=true;try{let s=await api('./api/mac',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({mac:q('#deviceMac').value})});q('#deviceMac').value=s.mac;q('#message').textContent=s.unchanged?'MAC 未变化':(s.pairing_required?'设备身份已修改，正在重新获取配对码':'设备身份已修改，正在重启服务');if(s.restarting)setTimeout(refresh,1800);else b.disabled=false}catch(e){q('#message').textContent=e.message;b.disabled=false}};
q('#pair').onclick=async()=>{q('#pair').disabled=true;try{await api('./api/repair',{method:'POST'});q('#message').textContent='正在请求官方配对码…';setTimeout(refresh,1800)}catch(e){q('#message').textContent=e.message}finally{setTimeout(()=>q('#pair').disabled=false,2500)}};
q('#saveUi').onclick=async()=>{let b=q('#saveUi');b.disabled=true;try{let s=await api('./api/ui',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({app_ui_type:q('#appUiType').value,service_ui_mode:q('#serviceUiMode').value,service_ui_type:q('#serviceUiType').value,service_ui_character:q('#serviceUiCharacter').value,deny_apps:collectDenyApps()})});q('#message').textContent='UI 配置已保存，已立即生效';q('#appUiType').value=s.app_ui_type;q('#serviceUiMode').value=s.service_ui_mode==='floating'?'floating':'app';q('#serviceUiType').value=s.service_ui_type;q('#serviceUiCharacter').value=s.service_ui_character;if(s.deny_apps)fillDenyApps(s.deny_app_options,s.deny_apps);syncServiceUiDisabled()}catch(e){q('#message').textContent=e.message}finally{b.disabled=false}};
refresh();
setInterval(refresh,2000);
</script>
</body>
</html>]=]

local function encode(value)
  local c = rawget(_G, "json") or rawget(_G, "sjson")
  if not c or not c.encode then return "{}" end
  local ok, raw = pcall(c.encode, value)
  return ok and raw or "{}"
end

local function decode(raw)
  local c = rawget(_G, "json") or rawget(_G, "sjson")
  if not c or not c.decode then return {} end
  local ok, value = pcall(c.decode, raw or "{}")
  return ok and type(value) == "table" and value or {}
end

local function request_json(req)
  local raw = req and (req.body or req.payload) or nil
  if not raw and req and req.getbody then
    local ok, value = pcall(req.getbody)
    if ok then raw = value end
  end
  return decode(raw)
end

local function response(status, typ, body)
  return { status = status, type = typ, headers = { ["cache-control"] = "no-store" }, body = body or "" }
end

local function json_response(status, body)
  return response(status, "application/json; charset=utf-8", encode(body))
end

function M.new(runtime, cfg)
  local default_base = cfg and cfg.SERVICE_MODE and "/xiaozhi-service" or "/xiaozhi"
  local instance_base = (app and app.route_base and app.route_base()) or default_base
  local self = { routes = {}, base = default_base, instance_base = instance_base }

  local function register(method, path, fn)
    local err = httpd.dynamic(method, path, fn)
    if not err then self.routes[#self.routes + 1] = { method = method, path = path } end
  end

  function self:start()
    if not httpd or not httpd.dynamic then return false end
    pcall(function() httpd.start({ webroot = "/sd", auto_index = httpd.INDEX_NONE, max_handlers = 48 }) end)

    local function index()
      return response("200 OK", "text/html; charset=utf-8", PAGE)
    end

    local function state()
      return json_response("200 OK", runtime:snapshot())
    end

    local function volume(req)
      local doc = request_json(req)
      local saved, result = runtime:set_volume(tonumber(doc.volume))
      if not saved then return json_response("400 Bad Request", { ok = false, error = result }) end
      return response("204 No Content", "text/plain; charset=utf-8", "")
    end

    local function server(req)
      local doc = request_json(req)
      local saved, result = runtime:set_server(doc.url, doc.token, doc.version, doc.ota_url or doc.otaUrl)
      if not saved then return json_response("400 Bad Request", { ok = false, error = result }) end
      result.ok = true
      return json_response("200 OK", result)
    end

    local function ui(req)
      local doc = request_json(req)
      local saved, result = runtime:set_ui_config(doc.app_ui_type, doc.service_ui_mode, doc.service_ui_type, doc.service_ui_character, doc.deny_apps)
      if not saved then return json_response("400 Bad Request", { ok = false, error = result }) end
      result.ok = true
      return json_response("200 OK", result)
    end

    local function wake(req)
      local doc = request_json(req)
      local saved, result = runtime:set_wake_enabled(doc.enabled == true)
      if not saved then return json_response("400 Bad Request", { ok = false, error = result }) end
      result.ok = true
      return json_response("200 OK", result)
    end

    local function mac(req)
      local doc = request_json(req)
      local saved, result = runtime:set_device_mac(doc.mac)
      if not saved then return json_response("400 Bad Request", { ok = false, error = result }) end
      result.ok = true
      return json_response("202 Accepted", result)
    end

    local function repair()
      local path = cfg.CONFIG_PATH or "/sd/apps/xiaozhi/config.json"
      local raw = file.getcontents(path)
      local doc = decode(raw)
      if type(doc) ~= "table" then
        return json_response("500 Internal Server Error", { ok = false, error = "配置读取失败" })
      end
      doc.ota = doc.ota or {}
      doc.ota.url = "https://api.tenclass.net/xiaozhi/ota/"
      doc.ota.enabled = true
      doc.ota.force = false
      doc.websocket = doc.websocket or {}
      doc.websocket.url = ""
      doc.websocket.token = ""
      doc.websocket.version = 1
      file.putcontents(path, encode(doc))
      local t = tmr.create()
      t:alarm(300, tmr.ALARM_SINGLE, function(x)
        pcall(function() x:unregister() end)
        if cfg.SERVICE_MODE and app and app.start_service then
          app.start_service("xiaozhi-service")
        end
      end)
      return json_response("202 Accepted", { ok = true })
    end

    local bases = { self.base }
    if self.instance_base ~= self.base then bases[#bases + 1] = self.instance_base end
    for _, base in ipairs(bases) do
      register(httpd.GET, base, index)
      register(httpd.GET, base .. "/", index)
      register(httpd.GET, base .. "/api/state", state)
      register(httpd.POST, base .. "/api/volume", volume)
      register(httpd.POST, base .. "/api/server", server)
      register(httpd.POST, base .. "/api/ui", ui)
      register(httpd.POST, base .. "/api/wake", wake)
      register(httpd.POST, base .. "/api/mac", mac)
      register(httpd.POST, base .. "/api/repair", repair)
    end
    if app and app.set_webui then pcall(function() app.set_webui(true) end) end
    return true
  end

  function self:stop()
    if httpd and httpd.unregister then
      for i = #self.routes, 1, -1 do
        local r = self.routes[i]
        pcall(httpd.unregister, r.method, r.path)
      end
    end
    self.routes = {}
  end

  return self
end

return M
