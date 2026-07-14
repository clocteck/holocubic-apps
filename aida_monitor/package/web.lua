local Web = {}
local JSON = rawget(_G, "sjson") or rawget(_G, "json")

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function normalize_path(value, fallback)
  local path = trim(value)
  if path == "" then path = fallback or "/" end
  if path:sub(1, 1) ~= "/" then path = "/" .. path end
  return path
end

local function url_decode(text)
  text = tostring(text or ""):gsub("+", " ")
  return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function parse_query(query)
  local result = {}
  for pair in tostring(query or ""):gmatch("([^&]+)") do
    local key, value = pair:match("^([^=]*)=(.*)$")
    result[url_decode(key or pair)] = url_decode(value or "")
  end
  return result
end

local function json_escape(text)
  return tostring(text or ""):gsub("\\", "\\\\"):gsub('"', '\\"')
    :gsub("\r", "\\r"):gsub("\n", "\\n"):gsub("\t", "\\t")
end

local function fallback_json(value)
  local kind = type(value)
  if kind == "nil" then return "null" end
  if kind == "boolean" or kind == "number" then return tostring(value) end
  if kind == "string" then return '"' .. json_escape(value) .. '"' end
  if kind ~= "table" then return '"' .. json_escape(tostring(value)) .. '"' end
  local parts = {}
  for key, item in pairs(value) do
    parts[#parts + 1] = '"' .. json_escape(key) .. '":' .. fallback_json(item)
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function encode_json(value)
  if JSON and JSON.encode then
    local ok, encoded = pcall(JSON.encode, value)
    if ok and encoded then return encoded end
  end
  return fallback_json(value)
end

local function response(status, content_type, body)
  return {
    status = status or "200 OK",
    type = content_type or "text/plain; charset=utf-8",
    headers = { ["cache-control"] = "no-store", ["connection"] = "close",
      ["access-control-allow-origin"] = "*" },
    body = body or "",
  }
end

local function json_response(status, value)
  return response(status, "application/json; charset=utf-8", encode_json(value))
end

local function valid_host(host)
  if host == "" or #host > 253 then return false end
  if host:find("[^%w%.%-:]") then return false end
  return true
end

local function valid_family(family)
  family = trim(family)
  if family == "" then return nil, "请填写 AIDA64 中显示的字体名称" end
  if #family > 96 or family:find("[%c]") then return nil, "字体名称需为 1–96 个字符" end
  return family
end

local function safe_font_name(name)
  name = trim(name)
  if name == "" or #name > 128 or name:find("[/\\%c]") then
    return nil, "字体文件名无效"
  end
  if not name:lower():match("%.ttf$") then return nil, "只支持 .ttf 字体文件" end
  return name
end

local function config_text(config)
  return string.format([=[local config = {}

config.host = %q
config.port = %d
config.layout_path = %q
config.path = %q
config.vector_font_family = %q
config.vector_font_fallback_family = %q
config.vector_font_module = %q
config.vector_font_path = %q
config.vector_font_default_path = %q
config.vector_font_custom_family = %q
config.vector_font_custom_path = %q
config.vector_font_custom_name = %q
config.vector_font_custom_bytes = %d
config.font_upload_max_bytes = %d
config.font_subpixel = %q
config.tilt_page_cooldown_ms = %d

config.timeout_ms = %d
config.reconnect_ms = %d
config.stale_ms = %d
config.watchdog_ms = %d
config.layout_retry_ms = %d
config.reload_delay_ms = %d
config.max_layout_bytes = %d
config.history_points = %d
config.cache_dir = %q
config.max_image_bytes = %d
config.max_image_pixels = %d
config.image_timeout_ms = %d
config.serial_log = %s

return config
]=],
    tostring(config.host or "192.168.0.232"),
    tonumber(config.port) or 9999,
    normalize_path(config.layout_path, "/"),
    normalize_path(config.path, "/sse"),
    tostring(config.vector_font_family or "Tahoma"),
    tostring(config.vector_font_fallback_family or "AIDA Noto Sans SC"),
    tostring(config.vector_font_module or "/sd/apps/aida_monitor/modules/aida_font.so"),
    tostring(config.vector_font_path or "/sd/apps/aida_monitor/font/aida_noto_sans_sc.ttf"),
    tostring(config.vector_font_default_path or config.vector_font_path
      or "/sd/apps/aida_monitor/font/aida_noto_sans_sc.ttf"),
    tostring(config.vector_font_custom_family or ""),
    tostring(config.vector_font_custom_path or "/sd/apps/aida_monitor/font/uploaded.ttf"),
    tostring(config.vector_font_custom_name or ""),
    tonumber(config.vector_font_custom_bytes) or 0,
    tonumber(config.font_upload_max_bytes) or 4194304,
    tostring(config.font_subpixel or "rgb"),
    tonumber(config.tilt_page_cooldown_ms) or 1000,
    tonumber(config.timeout_ms) or 7000,
    tonumber(config.reconnect_ms) or 2000,
    tonumber(config.stale_ms) or 5000,
    tonumber(config.watchdog_ms) or 1000,
    tonumber(config.layout_retry_ms) or 3000,
    tonumber(config.reload_delay_ms) or 500,
    tonumber(config.max_layout_bytes) or 196608,
    tonumber(config.history_points) or 96,
    tostring(config.cache_dir or "/sd/apps/aida_monitor/cache"),
    tonumber(config.max_image_bytes) or 262144,
    tonumber(config.max_image_pixels) or 307200,
    tonumber(config.image_timeout_ms) or 7000,
    config.serial_log == false and "false" or "true")
end

local function write_config(path, config)
  local raw = config_text(config)
  if file and file.putcontents then
    local ok, result = pcall(file.putcontents, path, raw)
    if ok and result ~= false then return true end
    return false, tostring(result)
  end
  return false, "file.putcontents unavailable"
end

local function ensure_directory(path)
  if not file or not file.stat then return false, "file api unavailable" end
  local st = file.stat(path)
  if st and st.is_dir then return true end
  if st then return false, "font directory path is not a directory" end
  if file.mkdir and file.mkdir(path) then return true end
  return false, "font directory creation failed"
end

local function open_upload(path, offset)
  if offset == 0 then
    if file.stat(path) then file.remove(path) end
    local fd = file.open(path, "w+")
    if not fd then return nil, "upload temp open failed" end
    return fd
  end
  local st = file.stat(path)
  if not st or st.is_dir or tonumber(st.size) ~= offset then
    return nil, "upload offset mismatch"
  end
  local fd = file.open(path, "a+")
  if not fd then return nil, "upload resume failed" end
  return fd
end

local function write_upload_body(req, fd, offset, total)
  if not req or type(req.getbody) ~= "function" then return nil, "request body unavailable" end
  local written = 0
  while true do
    local chunk = req.getbody()
    if not chunk then break end
    if #chunk > 0 then
      if offset + written + #chunk > total then return nil, "request body exceeds total size" end
      if not fd:write(chunk) then return nil, "font write failed" end
      written = written + #chunk
      if tmr and tmr.wdclr then pcall(tmr.wdclr) end
    end
  end
  if fd.flush then fd:flush() end
  return written
end

local function validate_ttf(path, total)
  local st = file.stat(path)
  if not st or st.is_dir or tonumber(st.size) ~= total then return false, "字体文件大小不完整" end
  local fd = file.open(path, "r")
  if not fd then return false, "无法读取字体文件" end
  local header = fd:read(4) or ""
  fd:close()
  local valid = header == "\0\1\0\0" or header == "true" or header == "typ1" or header == "OTTO"
  if not valid then return false, "文件不是有效的 TrueType/OpenType 字体" end
  return true
end

local function replace_file(temp_path, final_path)
  if not file.rename then return false, "file.rename unavailable" end
  local backup = final_path .. ".bak"
  if file.stat(backup) then file.remove(backup) end
  local had_final = file.stat(final_path) ~= nil
  if had_final and not file.rename(final_path, backup) then return false, "旧字体备份失败" end
  if not file.rename(temp_path, final_path) then
    if had_final then file.rename(backup, final_path) end
    return false, "字体安装失败"
  end
  if had_final and file.stat(backup) then file.remove(backup) end
  return true
end

local function build_html(api)
  api = tostring(api):gsub("\\", "\\\\"):gsub('"', '\\"')
  return [=[<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>AIDA RemoteSensor Bridge</title>
<style>
:root{color-scheme:dark;--bg:#17140f;--surface:#211c15;--surface2:#191610;--line:#574936;--line2:#372f24;--text:#f0e2c7;--muted:#ae9d81;--rust:#d7873d;--rust2:#efb66d;--ok:#9bbd7c;--bad:#df705d;--ink:#20150b}
*{box-sizing:border-box}html{background:var(--bg)}body{margin:0;background:var(--bg);color:var(--text);font:14px/1.55 ui-monospace,SFMono-Regular,Consolas,"Microsoft YaHei",monospace}.page{width:min(1040px,calc(100% - 24px));margin:auto;padding:24px 0 40px}.mast{display:grid;grid-template-columns:1fr auto;gap:16px;align-items:end;border-bottom:1px solid var(--line);padding:0 0 16px;margin-bottom:12px}.eyebrow{color:var(--rust2);font-size:11px;letter-spacing:.18em;margin:0 0 6px}.mast h1{font-size:clamp(22px,4vw,34px);line-height:1.05;margin:0;letter-spacing:-.04em}.mast p{margin:7px 0 0;color:var(--muted);max-width:62ch}.back,.button,button{min-height:42px;border:1px solid var(--line);border-radius:2px;background:var(--surface);color:var(--text);padding:9px 13px;font:inherit;cursor:pointer;text-decoration:none;display:inline-flex;align-items:center;justify-content:center}.button:hover,button:hover,.back:hover{border-color:var(--rust2);color:var(--rust2)}button:focus-visible,.button:focus-visible,.back:focus-visible,input:focus-visible,select:focus-visible{outline:2px solid var(--rust2);outline-offset:2px}.primary{background:var(--rust);border-color:var(--rust);color:var(--ink);font-weight:900}.primary:hover{background:var(--rust2);color:var(--ink)}.board{display:grid;grid-template-columns:minmax(0,1.18fr) minmax(300px,.82fr);gap:12px}.panel{border:1px solid var(--line);border-radius:2px;background:var(--surface);padding:16px}.panel-title{display:flex;align-items:center;justify-content:space-between;gap:10px;border-bottom:1px solid var(--line2);padding-bottom:10px;margin-bottom:14px}.panel h2{font-size:13px;letter-spacing:.12em;color:var(--rust2);margin:0}.serial{color:var(--muted);font-size:10px}.runtime{display:grid;grid-template-columns:repeat(4,1fr);gap:1px;background:var(--line);border:1px solid var(--line);margin-bottom:14px}.metric{background:var(--surface2);padding:10px}.metric b{display:block;color:var(--rust2);font-size:18px;font-variant-numeric:tabular-nums}.metric b.warn{color:var(--bad)}.metric span{color:var(--muted);font-size:10px;letter-spacing:.1em}.form{display:grid;gap:12px}.row{display:grid;grid-template-columns:1fr 138px;gap:10px}label{display:block;color:var(--muted);font-size:11px;letter-spacing:.06em;margin-bottom:5px}input,select{width:100%;min-height:42px;border:1px solid var(--line);border-radius:1px;background:var(--surface2);color:var(--text);padding:0 10px;font:inherit}input::placeholder{color:#7f715d}.actions{display:flex;gap:8px;flex-wrap:wrap}.status{min-height:22px;color:var(--muted)}.status.ok{color:var(--ok)}.status.err{color:var(--bad)}.font-bay{border:1px dashed var(--line);padding:12px;background:var(--surface2)}.font-head{display:flex;justify-content:space-between;gap:12px;align-items:start}.font-head strong{display:block;color:var(--rust2);font-size:15px}.font-head small{display:block;color:var(--muted);margin-top:3px}.flag{border:1px solid var(--line);padding:2px 6px;color:var(--muted);font-size:10px;white-space:nowrap}.flag.match{border-color:var(--ok);color:var(--ok)}.font-grid{display:grid;grid-template-columns:1fr 148px;gap:10px;margin-top:12px}.file{padding:8px;height:auto}.file::file-selector-button{border:1px solid var(--line);background:var(--surface);color:var(--text);font:inherit;padding:6px 9px;margin-right:9px;cursor:pointer}.upload-actions{display:flex;gap:8px;align-items:center;margin-top:10px;flex-wrap:wrap}progress{width:100%;height:7px;margin-top:10px;accent-color:var(--rust)}.micro{font-size:11px;color:var(--muted);margin:8px 0 0}.font-state{display:block;margin-top:10px;color:var(--ok);overflow-wrap:anywhere}.font-state.warn{color:var(--rust2)}.guide{margin:0;padding:0;list-style:none;counter-reset:step}.guide li{counter-increment:step;display:grid;grid-template-columns:25px 1fr;gap:9px;padding:9px 0;border-bottom:1px solid var(--line2);color:var(--muted)}.guide li:before{content:counter(step,decimal-leading-zero);color:var(--rust2);font-weight:800}.guide strong{display:block;color:var(--text);font-size:13px}.links{display:grid;gap:8px;margin-top:14px}.download{display:flex;justify-content:space-between;align-items:center;gap:12px;border:1px solid var(--line);padding:10px 11px;color:var(--text);text-decoration:none}.download:hover{border-color:var(--rust2);color:var(--rust2)}.download small{color:var(--muted)}.note{border-left:2px solid var(--rust);padding:9px 10px;margin:14px 0 0;background:var(--surface2);color:var(--muted);font-size:12px}code{color:var(--ok);overflow-wrap:anywhere}.preview{display:block;margin-top:10px;color:var(--ok);font-size:11px;overflow-wrap:anywhere}@media(max-width:760px){.board{grid-template-columns:1fr}.mast{align-items:start}.runtime{grid-template-columns:repeat(2,1fr)}.row,.font-grid{grid-template-columns:1fr}.font-head{flex-direction:column}}@media(max-width:440px){.page{width:min(100% - 16px,1040px);padding-top:14px}.mast{grid-template-columns:1fr}.back{justify-self:start}.panel{padding:12px}.actions>*{width:100%}}
</style></head><body><main class="page">
<header class="mast"><div><p class="eyebrow">DISPLAY PROTOCOL / CALIBRATION CONSOLE</p><h1>AIDA64 REMOTESENSOR</h1><p>把 Windows 端 AIDA64 的 LCD 布局、传感器数据与字体样式原样桥接到 HoloCubic 320×240 屏幕。</p></div><a class="back" href="/main">← 返回主界面</a></header>
<section class="board"><section class="panel"><div class="panel-title"><h2>01 / LINK & RENDER</h2><span class="serial">PORT 9999 · 320×240</span></div>
<div class="runtime"><div class="metric"><b id="rtStatus">--</b><span>LINK</span></div><div class="metric"><b id="rtPage">--</b><span>PAGE</span></div><div class="metric"><b id="rtItems">--</b><span>ITEMS</span></div><div class="metric"><b id="rtImages">--</b><span>IMAGES</span></div></div>
<form class="form" id="form"><div class="row"><div><label for="host">主机 IP / HOST</label><input id="host" required placeholder="192.168.0.232"></div><div><label for="port">REMOTESENSOR 端口</label><input id="port" inputmode="numeric" required placeholder="9999"></div></div><div class="row"><div><label for="layout">布局路径 / LAYOUT</label><input id="layout" value="/"></div><div><label for="stream">数据路径 / SSE</label><input id="stream" value="/sse"></div></div><div class="row"><div><label>重力翻页 / PAGE SELECT</label><input value="LEFT / RIGHT · LOOP" disabled></div><div><label for="tiltCooldown">翻页冷却 / MS</label><input id="tiltCooldown" type="number" min="250" max="5000" step="50" value="1000"></div></div>
<div class="font-bay"><div class="font-head"><div><strong>TTF FONT MATCHER</strong><small>AIDA64 默认使用 Tahoma，可直接保持默认；上传 Windows 的 tahoma.ttf 后命中即使用真实 Tahoma，否则由内置中文字形安全回退。</small></div><span class="flag" id="fontFlag">CHECKING</span></div><div class="font-grid"><div><label for="fontFile">TTF 文件 / 最大 4 MB</label><input class="file" id="fontFile" type="file" accept=".ttf,font/ttf,application/x-font-ttf"></div><div><label for="fontFamily">AIDA64 字体名称</label><input id="fontFamily" placeholder="Tahoma"></div></div><div class="row" style="margin-top:10px"><div><label for="subpixel">子像素排列</label><select id="subpixel"><option value="rgb">RGB（推荐）</option><option value="bgr">BGR</option><option value="off">关闭</option></select></div><div><label>内置中文回退字形</label><input value="AIDA Noto Sans SC" disabled></div></div><div class="upload-actions"><button class="primary" type="button" id="uploadFont">上传并匹配 TTF</button><button type="button" id="resetFont">恢复 AIDA 默认字体</button><a class="button" href="/apps/aida_monitor/font/aida_noto_sans_sc.ttf" download>下载内置 TTF</a></div><progress id="fontProgress" max="100" value="0"></progress><p class="micro" id="fontHint">选择字体后会自动读取字体族名称；如识别不准，请按 AIDA64 字体下拉框中的名称修改。</p><code class="font-state" id="fontState">FONT ENGINE // CHECKING</code></div>
<div class="actions"><button class="primary" type="submit">保存并重载布局</button><button type="button" id="openLayout">打开布局</button><button type="button" id="openStream">打开数据流</button></div><div id="status" class="status">正在读取设备状态...</div></form></section>
<aside class="panel"><div class="panel-title"><h2>02 / AIDA64 SETUP</h2><span class="serial">REMOTE LCD</span></div><ol class="guide"><li><span><strong>启用 RemoteSensor</strong>Preferences → Hardware Monitoring → LCD。</span></li><li><span><strong>设定画布</strong>端口 <code>9999</code>，Preview Resolution <code>320 × 240</code>。</span></li><li><span><strong>建立布局</strong>使用 LCD Items 添加标签、图片、Bar、Graph、Arc 与多页面。</span></li><li><span><strong>默认字体</strong>保持 Tahoma；若要与 Windows 预览最接近，上传本机 tahoma.ttf。</span></li></ol><div class="links"><a class="download" href="/apps/aida_monitor/holo-aida-template.txt" download="HoloCubic-AIDA64-320x240.rslcd"><span>下载示例布局模板</span><small>.RSLCD ↓</small></a><a class="download" href="/apps/aida_monitor/font/aida_noto_sans_sc.ttf" download><span>下载内置中文字体</span><small>.TTF ↓</small></a></div><p class="note">模板来自当前 AIDA64 生效布局。导入后可直接修改传感器项目；设备按 320×240 原始坐标渲染，不做整体缩放。</p><code class="preview" id="preview">http://--:9999/</code></aside></section></main>
<script>
const API="]=] .. api .. [=[";const $=id=>document.getElementById(id);let state={};
function path(v,d){v=(v||"").trim()||d;return v[0]==="/"?v:"/"+v}function base(){return "http://"+$("host").value.trim()+":"+$("port").value.trim()}function sync(){$("preview").textContent=base()+path($("layout").value,"/")}
function tone(text,kind){$("status").textContent=text;$("status").className="status "+(kind||"")}function bytes(n){n=Number(n)||0;return n>1048576?(n/1048576).toFixed(1)+" MB":n>1024?Math.round(n/1024)+" KB":n+" B"}
function runtime(d){$("rtStatus").textContent=d.status||"--";$("rtPage").textContent=(d.page||0)+"/"+(d.pages||0)+(d.page_source==="tilt"?"·TILT":"");$("rtItems").textContent=d.items||0;let img=$("rtImages"),skip=d.images_skipped||0;img.textContent=(d.images_loaded||0)+"/"+((d.images_loaded||0)+skip);img.className=skip?"warn":"";let uploaded=d.font_source==="uploaded"&&d.font_match,aidDefault=!uploaded&&(d.font||"Tahoma")==="Tahoma";$("fontFlag").textContent=uploaded?"MATCHED":aidDefault?"AIDA DEFAULT":"FALLBACK";$("fontFlag").className="flag "+(uploaded?"match":"");let request=d.font_requested_families||"none reported";$("fontState").textContent="FONT // "+(d.font||"Tahoma")+" · FACE "+(d.font_face||"AIDA Noto Sans SC")+" · "+(d.font_source||"default").toUpperCase()+" · "+(d.font_selection||"AIDA default")+" · REQUEST ["+request+"] · "+bytes(d.font_bytes);$("fontState").className="font-state "+(uploaded||aidDefault?"":"warn")}
function apply(d){state=d;$("host").value=d.host||"";$("port").value=d.port||9999;$("layout").value=d.layout_path||"/";$("stream").value=d.path||"/sse";$("subpixel").value=d.font_subpixel||"rgb";$("tiltCooldown").value=d.tilt_page_cooldown_ms||1000;$("fontFamily").value=d.font_custom_family||"Tahoma";runtime(d);sync()}
async function load(){let r=await fetch(API+"/state?_="+Date.now(),{cache:"no-store"});if(!r.ok)throw Error("HTTP "+r.status);let d=await r.json();apply(d);let msg=d.font_error?"字体已安全回退："+d.font_error:d.image_error?"图像已安全跳过："+d.image_error:"设备状态已同步。";tone(msg,(d.font_error||d.image_error)?"err":"ok")}
function tag(view,offset){return String.fromCharCode(view.getUint8(offset),view.getUint8(offset+1),view.getUint8(offset+2),view.getUint8(offset+3))}function utf16be(view,offset,length){let out="";for(let p=offset;p+1<offset+length;p+=2)out+=String.fromCharCode(view.getUint16(p,false));return out.replace(/\0/g,"").trim()}function byteText(view,offset,length){let out="";for(let p=offset;p<offset+length;p++)out+=String.fromCharCode(view.getUint8(p));return out.replace(/\0/g,"").trim()}
async function fontFamily(file){try{let view=new DataView(await file.arrayBuffer()),tables=view.getUint16(4,false),name=-1,size=0;for(let i=0;i<tables;i++){let p=12+i*16;if(tag(view,p)==="name"){name=view.getUint32(p+8,false);size=view.getUint32(p+12,false);break}}if(name<0||name+6>view.byteLength)throw Error("name table missing");let count=view.getUint16(name+2,false),strings=name+view.getUint16(name+4,false),best="",score=-1;for(let i=0;i<count;i++){let p=name+6+i*12,platform=view.getUint16(p,false),language=view.getUint16(p+4,false),id=view.getUint16(p+6,false),length=view.getUint16(p+8,false),offset=strings+view.getUint16(p+10,false);if((id!==1&&id!==16)||offset+length>view.byteLength||offset+length>name+size)continue;let value=(platform===0||platform===3)?utf16be(view,offset,length):byteText(view,offset,length),rank=(id===16?100:50)+(platform===3?20:0)+(language===0x409?5:0);if(value&&rank>score){best=value;score=rank}}return best}catch(e){return ""}}
$("fontFile").addEventListener("change",async()=>{let f=$("fontFile").files[0];if(!f)return;$("fontHint").textContent="正在读取字体元数据...";let family=await fontFamily(f);if(family)$("fontFamily").value=family;else if(!$("fontFamily").value.trim())$("fontFamily").value=f.name.replace(/\.ttf$/i,"");$("fontHint").textContent=family?"已识别字体族："+family:"未读到字体族，请按 AIDA64 中显示的字体名称填写。"});
$("uploadFont").onclick=async()=>{let f=$("fontFile").files[0],family=$("fontFamily").value.trim();if(!f)return tone("请选择一个 .ttf 字体文件。","err");if(!/\.ttf$/i.test(f.name))return tone("只支持 .ttf 字体文件。","err");if(!family)return tone("请填写 AIDA64 中显示的字体名称。","err");if(f.size<1024||f.size>4194304)return tone("字体大小需在 1 KB–4 MB 之间。","err");try{let offset=0,chunk=48*1024;$("fontProgress").value=0;tone("正在分块上传 "+f.name+"...");while(offset<f.size){let end=Math.min(offset+chunk,f.size),q=new URLSearchParams({offset,total:f.size,name:f.name,family});let r=await fetch(API+"/font?"+q,{method:"PUT",headers:{"content-type":"application/octet-stream"},body:f.slice(offset,end)}),d=await r.json();if(!r.ok||!d.ok)throw Error(d.error||"字体上传失败");offset=d.next_offset;if(offset<=0||offset>end)throw Error("设备返回了无效上传进度");$("fontProgress").value=Math.round(offset*100/f.size);tone("字体上传中 · "+$("fontProgress").value+"%")};tone("字体已安装，正在按布局字体名称重新匹配。","ok");setTimeout(()=>load().catch(e=>tone(e.message,"err")),700)}catch(e){tone(e.message,"err")}};
$("resetFont").onclick=async()=>{try{tone("正在恢复 AIDA64 默认字体...");let q=new URLSearchParams({font_default:"1",host:$("host").value.trim(),port:$("port").value.trim()}),r=await fetch(API+"/save?"+q,{cache:"no-store"}),d=await r.json();if(!r.ok||!d.ok)throw Error(d.error||"恢复失败");$("fontProgress").value=0;$("fontFamily").value="Tahoma";apply(d);tone("已恢复 AIDA64 默认 Tahoma（内置中文回退）。","ok")}catch(e){tone(e.message,"err")}};
$("form").addEventListener("submit",async e=>{e.preventDefault();try{tone("正在保存并重新读取布局...");let q=new URLSearchParams({host:$("host").value.trim(),port:$("port").value.trim(),layout_path:path($("layout").value,"/"),path:path($("stream").value,"/sse"),font_subpixel:$("subpixel").value,tilt_page_cooldown_ms:$("tiltCooldown").value});let r=await fetch(API+"/save?"+q,{cache:"no-store"}),d=await r.json();if(!r.ok||!d.ok)throw Error(d.error||"保存失败");apply(d);tone("配置已保存，布局正在重载。","ok")}catch(err){tone(err.message,"err")}});
$("openLayout").onclick=()=>window.open(base()+path($("layout").value,"/"),"_blank");$("openStream").onclick=()=>window.open(base()+path($("stream").value,"/sse"),"_blank");["host","port","layout","stream"].forEach(id=>$(id).addEventListener("input",sync));load().catch(e=>tone(e.message,"err"));setInterval(()=>fetch(API+"/state?_="+Date.now(),{cache:"no-store"}).then(r=>r.json()).then(runtime).catch(()=>{}),3000);
</script></body></html>]=]
end

function Web.new(opts)
  opts = opts or {}
  local self = {
    config = opts.config or {}, config_path = opts.config_path,
    route_base = opts.route_base or "/aida_monitor", restart = opts.restart,
    runtime_state = opts.state, routes = {}, started = false,
  }
  self.api_prefix = self.route_base .. "/api"

  function self:snapshot(ok, message)
    local runtime = self.runtime_state and self.runtime_state() or {}
    local host = tostring(self.config.host or "")
    local port = tonumber(self.config.port) or 9999
    local custom_path = tostring(self.config.vector_font_custom_path
      or "/sd/apps/aida_monitor/font/uploaded.ttf")
    local custom_st = file and file.stat and file.stat(custom_path) or nil
    return {
      ok = ok ~= false, message = message or "", host = host, port = port,
      layout_path = normalize_path(self.config.layout_path, "/"),
      path = normalize_path(self.config.path, "/sse"),
      font_subpixel = tostring(self.config.font_subpixel or "rgb"),
      tilt_page_cooldown_ms = tonumber(self.config.tilt_page_cooldown_ms) or 1000,
      font = runtime.font or tostring(self.config.vector_font_family or "Tahoma"),
      font_face = runtime.font_face or tostring(self.config.vector_font_fallback_family
        or "AIDA Noto Sans SC"),
      font_custom_family = tostring(self.config.vector_font_custom_family or ""),
      font_custom_name = tostring(self.config.vector_font_custom_name or ""),
      font_custom_bytes = tonumber(self.config.vector_font_custom_bytes) or 0,
      font_custom_present = custom_st ~= nil and not custom_st.is_dir,
      layout_url = "http://" .. host .. ":" .. port .. normalize_path(self.config.layout_path, "/"),
      stream_url = "http://" .. host .. ":" .. port .. normalize_path(self.config.path, "/sse"),
      status = runtime.status or "STARTING", detail = runtime.detail or "",
      page = runtime.page or 0, pages = runtime.pages or 0, items = runtime.items or 0,
      page_source = runtime.page_source or "remote",
      counts = runtime.counts or {}, last_event_ms = runtime.last_event_ms or 0,
      images_loaded = runtime.images_loaded or 0,
      images_skipped = runtime.images_skipped or 0,
      image_error = runtime.image_error or "",
      font_loaded = runtime.font_loaded ~= false,
      font_engine = runtime.font_engine or "firmware fallback",
      font_error = runtime.font_error or "",
      font_bytes = runtime.font_bytes or 0,
      font_cache_bytes = runtime.font_cache_bytes or 0,
      font_cache_entries = runtime.font_cache_entries or 0,
      font_renders = runtime.font_renders or 0,
      font_missing_glyphs = runtime.font_missing_glyphs or 0,
      font_source = runtime.font_source or "default",
      font_match = runtime.font_match == true,
      font_selection = runtime.font_selection or "bundled default",
      font_requested_families = runtime.font_requested_families or "",
      font_path = runtime.font_path or tostring(self.config.vector_font_default_path
        or self.config.vector_font_path or ""),
      internal_free = runtime.internal_free or 0,
      psram_free = runtime.psram_free or 0,
      psram_largest = runtime.psram_largest or 0,
      compositor = runtime.compositor or "legacy-canvas",
      background_ready = runtime.background_ready == true,
      layer_model = runtime.layer_model or "legacy-dom",
      subpixel = runtime.subpixel or tostring(self.config.font_subpixel or "off"),
      antialiasing = runtime.antialiasing or "firmware",
      surface_bytes = runtime.surface_bytes or 0,
      surface_flushes = runtime.surface_flushes or 0,
    }
  end

  function self:register(method, route, handler)
    if not httpd or not httpd.dynamic or not method then return false end
    local ok, err = pcall(httpd.dynamic, method, route, handler)
    if ok and not err then
      self.routes[#self.routes + 1] = { method = method, route = route }
      return true
    end
    return false
  end

  function self:save(req)
    local query = parse_query(req and req.query or "")
    if tostring(query.font_default or "") == "1" then return self:reset_font() end
    local host, port = trim(query.host), tonumber(query.port)
    if not valid_host(host) then return json_response("400 Bad Request", { ok = false, error = "主机地址无效" }) end
    if not port or port < 1 or port > 65535 then return json_response("400 Bad Request", { ok = false, error = "端口需为 1–65535" }) end
    self.config.host, self.config.port = host, math.floor(port)
    self.config.layout_path = normalize_path(query.layout_path, "/")
    self.config.path = normalize_path(query.path, "/sse")
    local subpixel = tostring(query.font_subpixel or self.config.font_subpixel or "rgb"):lower()
    if subpixel ~= "rgb" and subpixel ~= "bgr" and subpixel ~= "off" then subpixel = "off" end
    self.config.font_subpixel = subpixel
    self.config.tilt_page_cooldown_ms = math.max(250,
      math.min(5000, math.floor(tonumber(query.tilt_page_cooldown_ms)
        or tonumber(self.config.tilt_page_cooldown_ms) or 1000)))
    local ok, err = write_config(self.config_path, self.config)
    if not ok then return json_response("500 Internal Server Error", { ok = false, error = "配置写入失败: " .. tostring(err) }) end
    if self.restart then pcall(self.restart) end
    return json_response("200 OK", self:snapshot(true, "saved"))
  end

  function self:upload_font(req)
    if not file or not file.open or not file.stat then
      return json_response("500 Internal Server Error", { ok = false, error = "设备文件接口不可用" })
    end
    local query = parse_query(req and req.query or "")
    local name, name_err = safe_font_name(query.name)
    if not name then return json_response("400 Bad Request", { ok = false, error = name_err }) end
    local family, family_err = valid_family(query.family)
    if not family then return json_response("400 Bad Request", { ok = false, error = family_err }) end
    local offset = math.floor(tonumber(query.offset) or -1)
    local total = math.floor(tonumber(query.total) or -1)
    local max_bytes = tonumber(self.config.font_upload_max_bytes) or 4194304
    if offset < 0 or total < 1024 or offset > total then
      return json_response("400 Bad Request", { ok = false, error = "上传偏移或字体大小无效" })
    end
    if total > max_bytes then
      return json_response("413 Payload Too Large", { ok = false, error = "字体不能超过 4 MB" })
    end
    local final_path = tostring(self.config.vector_font_custom_path
      or "/sd/apps/aida_monitor/font/uploaded.ttf")
    local directory = final_path:match("^(.*)/[^/]+$") or "/sd/apps/aida_monitor/font"
    local dir_ok, dir_err = ensure_directory(directory)
    if not dir_ok then return json_response("500 Internal Server Error", { ok = false, error = dir_err }) end
    local temp_path = final_path .. ".upload"
    local fd, open_err = open_upload(temp_path, offset)
    if not fd then
      local status = open_err == "upload offset mismatch" and "409 Conflict" or "500 Internal Server Error"
      return json_response(status, { ok = false, error = open_err })
    end
    local written, write_err = write_upload_body(req, fd, offset, total)
    fd:close()
    if not written then return json_response("400 Bad Request", { ok = false, error = write_err }) end
    local next_offset = offset + written
    if next_offset > total then return json_response("400 Bad Request", { ok = false, error = "上传大小溢出" }) end
    if next_offset >= total then
      local valid, valid_err = validate_ttf(temp_path, total)
      if not valid then
        if file.remove then file.remove(temp_path) end
        return json_response("400 Bad Request", { ok = false, error = valid_err })
      end
      local installed, install_err = replace_file(temp_path, final_path)
      if not installed then return json_response("500 Internal Server Error", { ok = false, error = install_err }) end
      self.config.vector_font_custom_family = family
      self.config.vector_font_custom_name = name
      self.config.vector_font_custom_path = final_path
      self.config.vector_font_custom_bytes = total
      local saved, save_err = write_config(self.config_path, self.config)
      if not saved then return json_response("500 Internal Server Error", { ok = false, error = "字体已写入但配置保存失败: " .. tostring(save_err) }) end
      if self.restart then pcall(self.restart) end
    end
    return json_response("200 OK", {
      ok = true, name = name, family = family, next_offset = next_offset,
      total = total, done = next_offset >= total,
    })
  end

  function self:reset_font()
    local path = tostring(self.config.vector_font_custom_path
      or "/sd/apps/aida_monitor/font/uploaded.ttf")
    self.config.vector_font_custom_family = ""
    self.config.vector_font_custom_name = ""
    self.config.vector_font_custom_bytes = 0
    local ok, err = write_config(self.config_path, self.config)
    if not ok then return json_response("500 Internal Server Error", { ok = false, error = "配置写入失败: " .. tostring(err) }) end
    if file and file.stat and file.remove and file.stat(path) then file.remove(path) end
    if self.restart then pcall(self.restart) end
    return json_response("200 OK", self:snapshot(true, "default font restored"))
  end

  function self:start()
    if self.started or not httpd or not httpd.start then return end
    pcall(httpd.start, { webroot = "/sd", auto_index = httpd.INDEX_NONE, max_handlers = 32 })
    local page_html = build_html(self.api_prefix)
    self:register(httpd.GET, self.route_base, function() return response("200 OK", "text/html; charset=utf-8", page_html) end)
    self:register(httpd.GET, self.route_base .. "/", function() return response("200 OK", "text/html; charset=utf-8", page_html) end)
    self:register(httpd.GET, self.api_prefix .. "/state", function() return json_response("200 OK", self:snapshot(true, "loaded")) end)
    self:register(httpd.GET, self.api_prefix .. "/save", function(req) return self:save(req) end)
    self:register(httpd.PUT, self.api_prefix .. "/font", function(req) return self:upload_font(req) end)
    self.started = true
  end

  function self:stop()
    if httpd and httpd.unregister then
      for i = #self.routes, 1, -1 do pcall(httpd.unregister, self.routes[i].method, self.routes[i].route) end
    end
    self.routes, self.started = {}, false
  end
  return self
end

return Web
