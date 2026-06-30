local Web = {}

local JSON = rawget(_G, "sjson") or rawget(_G, "json")

-- 文本兜底，避免响应里出现 nil。
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

-- URL 解码，用于 GET query。
local function url_decode(text)
  text = tostring(text or "")
  text = text:gsub("+", " ")
  text = text:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
  return text
end

-- 解析 query string。
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

-- 返回 JSON 响应。
local function json_response(status, value)
  local ok, raw, err = pcall(function()
    return JSON.encode(value)
  end)
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

-- 返回 HTML 或纯文本响应。
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

-- 转义 JS 字符串中的路径。
local function js_string(text)
  text = tostring(text or "")
  text = text:gsub("\\", "\\\\")
  text = text:gsub("\"", "\\\"")
  return text
end

-- 构造 Web 控制页，页面脚本使用注入的 API 前缀。
local function build_html(api_prefix)
  api_prefix = js_string(api_prefix)
  return table.concat({
[=[<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Ticker</title>
<style>
:root{
  color-scheme:light;
  --bg:#eef3fb;
  --panel:#ffffff;
  --panel-hi:#f8fbff;
  --line:rgba(15,23,42,.11);
  --text:#111827;
  --muted:#64748b;
  --dim:#94a3b8;
  --green:#16a34a;
  --green-soft:#dcfce7;
  --red:#e2553f;
  --red-soft:#ffe4dd;
  --amber:#d97706;
  --amber-soft:#fff1d6;
  --blue:#0a84ff;
  --blue-soft:#eff5ff;
  --soft:#f1f5f9;
  --shadow:0 18px 44px rgba(15,23,42,.08);
  --radius:8px;
}
*{box-sizing:border-box}
html,body{min-height:100%}
body{
  margin:0;
  background:linear-gradient(180deg,#f7faff 0%,var(--bg) 100%);
  color:var(--text);
  font:14px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif;
}
button,input,select{font:inherit;color:inherit}
.page{width:min(1320px,calc(100% - 48px));margin:0 auto;padding:24px 0 32px}
.topbar{display:flex;align-items:flex-end;justify-content:space-between;gap:16px;margin-bottom:16px}
.top-actions{display:flex;align-items:center;gap:8px}
h1{margin:0;font-size:28px;line-height:1.08;letter-spacing:0;color:var(--text)}
.meta{color:var(--muted);margin-top:5px}
.main-link{
  min-height:32px;
  display:inline-flex;
  align-items:center;
  justify-content:center;
  padding:0 12px;
  border:1px solid var(--line);
  border-radius:999px;
  background:rgba(255,255,255,.86);
  color:var(--text);
  text-decoration:none;
  box-shadow:0 6px 18px rgba(15,23,42,.05);
}
.badge{
  min-width:74px;
  min-height:32px;
  display:inline-flex;
  align-items:center;
  justify-content:center;
  padding:0 12px;
  border:1px solid var(--line);
  border-radius:999px;
  color:var(--muted);
  background:var(--soft);
  font-size:12px;
  font-weight:700;
  letter-spacing:.04em;
  text-transform:uppercase;
}
.badge.up{color:var(--green);border-color:rgba(22,163,74,.22);background:var(--green-soft)}
.badge.down,.badge.error{color:var(--red);border-color:rgba(226,85,63,.22);background:var(--red-soft)}
.badge.warn{color:var(--amber);border-color:rgba(217,119,6,.22);background:var(--amber-soft)}
.layout{display:grid;grid-template-columns:minmax(0,2fr) minmax(320px,1fr);gap:18px;align-items:stretch}
.panel{
  border:1px solid var(--line);
  border-radius:var(--radius);
  background:linear-gradient(135deg,var(--panel),var(--panel-hi));
  box-shadow:var(--shadow);
  height:100%;
}
.quote{padding:20px;display:flex;flex-direction:column}
.quote-head{display:flex;justify-content:space-between;gap:14px;align-items:flex-start;margin-bottom:14px}
.symbol{min-width:0}
.symbol h2{margin:0;font-size:22px;line-height:1.2;color:var(--text)}
.symbol p{margin:5px 0 0;color:var(--muted)}
.price-row{display:flex;flex-wrap:wrap;align-items:baseline;gap:12px;margin-bottom:12px}
.price{font-size:48px;line-height:1;font-weight:760;letter-spacing:0}
.change{
  display:inline-flex;
  align-items:center;
  min-height:34px;
  padding:7px 11px;
  border-radius:var(--radius);
  background:var(--soft);
  font-size:17px;
  font-weight:700;
}
.change.up{color:var(--green)}
.change.down{color:var(--red)}
.chart-wrap{flex:1;min-height:286px;border:1px solid var(--line);border-radius:var(--radius);background:#fff;overflow:hidden;box-shadow:inset 0 1px 0 rgba(255,255,255,.8)}
canvas{display:block;width:100%;height:100%}
.stats{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px;margin-top:10px}
.stat{padding:12px;border:1px solid var(--line);border-radius:var(--radius);background:rgba(255,255,255,.72);min-width:0}
.stat span{display:block;color:var(--dim);font-size:12px;margin-bottom:4px}
.stat strong{display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.controls{padding:16px;display:grid;gap:14px}
.seg{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:6px}
.currency-seg{grid-template-columns:repeat(2,minmax(0,1fr))}
.seg button,.actions button{
  min-height:38px;
  border:1px solid var(--line);
  border-radius:var(--radius);
  background:rgba(255,255,255,.78);
  cursor:pointer;
  transition:border-color .18s ease,box-shadow .18s ease,transform .18s ease,background .18s ease;
}
.seg button:hover,.actions button:hover{transform:translateY(-1px)}
.seg button.active{border-color:rgba(10,132,255,.42);color:var(--blue);background:var(--blue-soft);box-shadow:0 8px 22px rgba(10,132,255,.12)}
.field{display:grid;gap:6px}
.field label,.subhead{color:var(--muted);font-size:12px;font-weight:650}
select,input{
  width:100%;
  min-height:40px;
  border:1px solid var(--line);
  border-radius:var(--radius);
  background:rgba(255,255,255,.88);
  padding:0 10px;
  outline:none;
}
select:focus,input:focus,button:focus-visible{border-color:rgba(10,132,255,.5);box-shadow:0 0 0 4px rgba(10,132,255,.12)}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.actions{display:grid;grid-template-columns:repeat(auto-fit,minmax(120px,1fr));gap:8px}
.actions .primary{background:linear-gradient(135deg,#0a84ff,#45b2ff);border-color:transparent;color:#fff;font-weight:750;box-shadow:0 10px 24px rgba(10,132,255,.2)}
.actions .secondary{color:var(--text)}
.divider{height:1px;background:var(--line)}
.hint{min-height:20px;color:var(--muted)}
.hint.error{color:var(--red)}
.site-footer{
  margin:18px auto 0;
  padding:8px 2px 0;
  color:var(--muted);
  font-size:12px;
  line-height:1.7;
  text-align:center;
}
.site-footer div+div{margin-top:2px}
.site-footer a{color:var(--blue);text-decoration:none;font-weight:650}
.site-footer a:hover{text-decoration:underline}
.hidden{display:none!important}
@media (max-width:920px){
  .layout{grid-template-columns:1fr}
  .stats{grid-template-columns:repeat(2,minmax(0,1fr))}
}
@media (max-width:520px){
  .page{width:min(100% - 16px,1320px);padding-top:12px}
  .topbar{align-items:flex-start}
  .top-actions{align-self:flex-end}
  .price{font-size:34px}
  .chart-wrap{min-height:230px}
  .seg{grid-template-columns:repeat(2,minmax(0,1fr))}
  .grid2,.actions{grid-template-columns:1fr}
}
</style>
</head>
<body>
<main class="page">
  <header class="topbar">
    <div>
      <h1>Ticker</h1>
      <div class="meta" id="routeMeta">loading</div>
    </div>
    <div class="top-actions">
      <a class="main-link" href="/main">Main</a>
      <div class="badge" id="statusBadge">idle</div>
    </div>
  </header>

  <section class="layout">
    <article class="panel quote">
      <div class="quote-head">
        <div class="symbol">
          <h2 id="assetName">--</h2>
          <p id="assetMeta">--</p>
        </div>
      </div>

      <div class="price-row">
        <div class="price" id="priceText">--</div>
        <div class="change" id="changeText">--</div>
      </div>

      <div class="chart-wrap">
        <canvas id="chart"></canvas>
      </div>

      <div class="stats">
        <div class="stat"><span>周期</span><strong id="statInterval">--</strong></div>
        <div class="stat"><span>最高</span><strong id="statHigh">--</strong></div>
        <div class="stat"><span>最低</span><strong id="statLow">--</strong></div>
        <div class="stat"><span>更新</span><strong id="statUpdate">--</strong></div>
      </div>
    </article>

    <aside class="panel controls">
      <div class="seg" id="groupButtons">
        <button data-group="crypto">币价</button>
        <button data-group="nasdaq">纳斯达克</button>
        <button data-group="metal">金银铜</button>
        <button data-group="ashare">A股</button>
      </div>

      <div class="field">
        <label>显示币种</label>
        <div class="seg currency-seg" id="currencyButtons">
          <button data-currency="USD">美金</button>
          <button data-currency="CNY">人民币</button>
        </div>
        <select class="hidden" id="currencySelect"></select>
      </div>

      <div class="field">
        <label for="assetSelect">标的</label>
        <select id="assetSelect"></select>
      </div>

      <div class="field">
        <label for="intervalSelect">走势周期</label>
        <select id="intervalSelect"></select>
      </div>

      <div class="field">
        <label for="modeSelect">图表</label>
        <select id="modeSelect">
          <option value="line">折线</option>
          <option value="candle">K线</option>
        </select>
      </div>

      <div class="field">
        <label for="maSelect">均线</label>
        <select id="maSelect">
          <option value="off">不显示</option>
          <option value="10">MA10</option>
          <option value="20">MA20</option>
        </select>
      </div>

      <div class="actions">
        <button class="secondary" id="refreshNow">刷新</button>
      </div>

      <div class="divider"></div>

      <div class="subhead">自定义</div>
      <div class="grid2">
        <div class="field">
          <label for="sourceSelect">来源</label>
          <select id="sourceSelect">
            <option value="binance">币价</option>
            <option value="eastmoney">Eastmoney公开</option>
          </select>
        </div>
        <div class="field" id="marketField">
          <label for="marketSelect">市场</label>
          <select id="marketSelect">
            <option value="1">沪市/指数</option>
            <option value="0">深市</option>
            <option value="100">纳斯达克指数</option>
            <option value="105">美股</option>
            <option value="101">金银铜期货</option>
          </select>
        </div>
      </div>
      <div class="grid2">
        <div class="field">
          <label for="symbolInput">代码</label>
          <input id="symbolInput" value="BTCUSDT" autocomplete="off">
        </div>
        <div class="field">
          <label for="nameInput">名称</label>
          <input id="nameInput" value="BTC / USDT" autocomplete="off">
        </div>
      </div>
      <div class="actions">
        <button class="primary" id="applyCustom">添加并查看</button>
        <button class="secondary" id="clearCustom">清空</button>
      </div>
      <div class="hint" id="hint"></div>
    </aside>
  </section>
  <footer class="site-footer">
    <div>Copyright &copy; 2026 clocteck. Licensed under GPL-3.0. Open source: <a href="https://github.com/clocteck" target="_blank" rel="noopener">github.com/clocteck</a>.</div>
    <div>Data sources: Binance public market data, Eastmoney public market data, and open.er-api.com FX rates. For display only; not financial advice.</div>
  </footer>
</main>

<script>
const API = "]=], api_prefix, [=[";
const groupText = { crypto: "币价", nasdaq: "纳斯达克", metal: "金银铜", ashare: "A股" };
const els = {
  routeMeta: document.getElementById("routeMeta"),
  statusBadge: document.getElementById("statusBadge"),
  assetName: document.getElementById("assetName"),
  assetMeta: document.getElementById("assetMeta"),
  priceText: document.getElementById("priceText"),
  changeText: document.getElementById("changeText"),
  statInterval: document.getElementById("statInterval"),
  statHigh: document.getElementById("statHigh"),
  statLow: document.getElementById("statLow"),
  statUpdate: document.getElementById("statUpdate"),
  chart: document.getElementById("chart"),
  assetSelect: document.getElementById("assetSelect"),
  intervalSelect: document.getElementById("intervalSelect"),
  modeSelect: document.getElementById("modeSelect"),
  maSelect: document.getElementById("maSelect"),
  currencySelect: document.getElementById("currencySelect"),
  sourceSelect: document.getElementById("sourceSelect"),
  marketField: document.getElementById("marketField"),
  marketSelect: document.getElementById("marketSelect"),
  symbolInput: document.getElementById("symbolInput"),
  nameInput: document.getElementById("nameInput"),
  hint: document.getElementById("hint")
};

let current = null;
let activeGroup = "crypto";
let optionsSignature = "";
let busy = false;

function safe(value, fallback){
  return value === undefined || value === null || value === "" ? fallback : String(value);
}

function modeLabel(mode){
  return mode === "candle" ? "K线" : "折线";
}

function maLabel(value){
  if(value === "10"){
    return "MA10";
  }
  if(value === "20"){
    return "MA20";
  }
  return "不显示";
}

function rateLabel(value){
  const rate = Number(value);
  return Number.isFinite(rate) ? rate.toFixed(4) : "--";
}

function redUpMarket(state){
  const group = state && state.active && state.active.group;
  return group === "ashare" || group === "metal";
}

function marketColors(state){
  if(redUpMarket(state)){
    return { up: "#ef4444", down: "#22c55e" };
  }
  return { up: "#22c55e", down: "#ef4444" };
}

function toneColor(state, tone){
  if(tone === "error"){
    return "#ef4444";
  }
  if(tone === "warn"){
    return "#f59e0b";
  }
  const colors = marketColors(state);
  if(tone === "down"){
    return colors.down;
  }
  if(tone === "up"){
    return colors.up;
  }
  return "";
}

function toneSoftColor(state, tone){
  if(tone === "warn"){
    return "#fff1d6";
  }
  if(tone === "error"){
    return "#ffe4dd";
  }
  const color = toneColor(state, tone);
  if(color === "#16a34a" || color === "#22c55e"){
    return "#dcfce7";
  }
  if(color === "#ef4444" || color === "#e2553f"){
    return "#ffe4dd";
  }
  return "#eef2f7";
}

function setHint(text, error){
  els.hint.textContent = text || "";
  els.hint.className = error ? "hint error" : "hint";
}

function setBadge(tone, text, state){
  const color = toneColor(state, tone);
  els.statusBadge.className = "badge " + safe(tone, "");
  els.statusBadge.textContent = safe(text, "idle");
  els.statusBadge.style.color = color;
  els.statusBadge.style.borderColor = color;
  els.statusBadge.style.background = toneSoftColor(state, tone);
}

async function getJson(path){
  const response = await fetch(API + path, { cache: "no-store" });
  if(!response.ok){
    throw new Error("HTTP " + response.status);
  }
  return await response.json();
}

function groupButtons(){
  document.querySelectorAll("[data-group]").forEach((button) => {
    button.classList.toggle("active", button.dataset.group === activeGroup);
  });
}

function currencyButtons(){
  const selected = els.currencySelect.value || "USD";
  document.querySelectorAll("[data-currency]").forEach((button) => {
    button.classList.toggle("active", button.dataset.currency === selected);
  });
}

function assetLabel(asset){
  return safe(asset.text, asset.symbol) + " · " + safe(asset.symbol || asset.secid, "");
}

function renderOptions(state){
  const assets = Array.isArray(state.assets) ? state.assets : [];
  const intervals = Array.isArray(state.intervals) ? state.intervals : [];
  const currencies = Array.isArray(state.currencies) ? state.currencies : [];
  const signature = activeGroup + "|" + assets.map((a) => a.id + ":" + a.group).join(",") + "|" + intervals.map((i) => i.label).join(",") + "|" + currencies.map((c) => c.value).join(",");
  if(signature === optionsSignature){
    return;
  }
  optionsSignature = signature;

  els.assetSelect.innerHTML = "";
  assets.filter((asset) => asset.group === activeGroup).forEach((asset) => {
    const option = document.createElement("option");
    option.value = asset.id;
    option.textContent = assetLabel(asset);
    els.assetSelect.appendChild(option);
  });

  els.intervalSelect.innerHTML = "";
  intervals.forEach((item) => {
    const option = document.createElement("option");
    option.value = item.label;
    option.textContent = item.label;
    els.intervalSelect.appendChild(option);
  });

  els.currencySelect.innerHTML = "";
  (currencies.length ? currencies : [{ value: "USD", text: "美金" }, { value: "CNY", text: "人民币" }]).forEach((item) => {
    const option = document.createElement("option");
    option.value = item.value;
    option.textContent = item.text || item.value;
    els.currencySelect.appendChild(option);
  });
  currencyButtons();
}

function resizeCanvas(canvas){
  const rect = canvas.getBoundingClientRect();
  const ratio = Math.max(1, window.devicePixelRatio || 1);
  const w = Math.max(1, Math.floor(rect.width * ratio));
  const h = Math.max(1, Math.floor(rect.height * ratio));
  if(canvas.width !== w || canvas.height !== h){
    canvas.width = w;
    canvas.height = h;
  }
  return { w, h, ratio };
}

function drawChart(state){
  const canvas = els.chart;
  const ctx = canvas.getContext("2d");
  const size = resizeCanvas(canvas);
  const points = Array.isArray(state.points) ? state.points : [];
  ctx.clearRect(0, 0, size.w, size.h);
  ctx.fillStyle = "#ffffff";
  ctx.fillRect(0, 0, size.w, size.h);

  const padL = 36 * size.ratio;
  const padR = 14 * size.ratio;
  const padT = 18 * size.ratio;
  const padB = 28 * size.ratio;
  const cw = size.w - padL - padR;
  const ch = size.h - padT - padB;

  ctx.strokeStyle = "rgba(15,23,42,.09)";
  ctx.lineWidth = Math.max(1, size.ratio);
  for(let i = 1; i <= 2; i++){
    const y = padT + ch * i / 3;
    ctx.beginPath();
    ctx.moveTo(padL, y);
    ctx.lineTo(padL + cw, y);
    ctx.stroke();
  }

  if(points.length < 1){
    ctx.fillStyle = "#64748b";
    ctx.font = `${14 * size.ratio}px system-ui, sans-serif`;
    ctx.textAlign = "center";
    ctx.fillText(safe(state.error, "Waiting data"), size.w / 2, size.h / 2);
    return;
  }

  let min = Number(state.min_price);
  let max = Number(state.max_price);
  if(!Number.isFinite(min) || !Number.isFinite(max)){
    min = Infinity;
    max = -Infinity;
    points.forEach((point) => {
      [Number(point.low), Number(point.high), Number(point.close)].forEach((v) => {
        if(Number.isFinite(v)){
          min = Math.min(min, v);
          max = Math.max(max, v);
        }
      });
    });
  }
  if(!Number.isFinite(min) || !Number.isFinite(max)){
    return;
  }
  if(Math.abs(max - min) < 0.000001){
    max += 1;
    min -= 1;
  }

  function yOf(v){
    return padT + ch - ((v - min) / (max - min)) * ch;
  }

  const mode = state.settings && state.settings.mode || "line";
  const colors = marketColors(state);
  const upColor = colors.up;
  const downColor = colors.down;
  function xOf(index){
    return points.length === 1 ? padL + cw / 2 : padL + cw * index / Math.max(1, points.length - 1);
  }

  function drawMovingAverage(period){
    if(!period || points.length < period){
      return;
    }
    ctx.strokeStyle = "#0a84ff";
    ctx.lineWidth = Math.max(1, 1.6 * size.ratio);
    ctx.beginPath();
    let moved = false;
    for(let i = 0; i < points.length; i++){
      if(i + 1 < period){
        continue;
      }
      let sum = 0;
      let ok = true;
      for(let j = i - period + 1; j <= i; j++){
        const close = Number(points[j].close);
        if(!Number.isFinite(close)){
          ok = false;
          break;
        }
        sum += close;
      }
      if(!ok){
        moved = false;
        continue;
      }
      const x = xOf(i);
      const y = yOf(sum / period);
      if(!moved){
        ctx.moveTo(x, y);
        moved = true;
      }else{
        ctx.lineTo(x, y);
      }
    }
    ctx.stroke();
  }

  if(mode === "candle"){
    const step = cw / Math.max(1, points.length);
    const bodyW = Math.max(2 * size.ratio, Math.min(7 * size.ratio, step * 0.62));
    ctx.lineWidth = Math.max(1, size.ratio);
    points.forEach((point, index) => {
      const open = Number(point.open);
      const high = Number(point.high);
      const low = Number(point.low);
      const close = Number(point.close);
      if(!Number.isFinite(open) || !Number.isFinite(high) || !Number.isFinite(low) || !Number.isFinite(close)){
        return;
      }

      const cx = padL + step * (index + 0.5);
      const yHigh = yOf(high);
      const yLow = yOf(low);
      const yOpen = yOf(open);
      const yClose = yOf(close);
      const color = close >= open ? upColor : downColor;

      ctx.strokeStyle = "rgba(138,148,144,.8)";
      ctx.beginPath();
      ctx.moveTo(cx, yHigh);
      ctx.lineTo(cx, yLow);
      ctx.stroke();

      ctx.fillStyle = color;
      const bodyTop = Math.min(yOpen, yClose);
      const bodyH = Math.max(1 * size.ratio, Math.abs(yClose - yOpen));
      ctx.fillRect(cx - bodyW / 2, bodyTop, bodyW, bodyH);
    });
  }else{
    ctx.strokeStyle = state.tone === "down" ? downColor : upColor;
    ctx.lineWidth = 2 * size.ratio;
    ctx.beginPath();
    let moved = false;
    points.forEach((point, index) => {
      const close = Number(point.close);
      if(!Number.isFinite(close)){
        return;
      }
      const x = xOf(index);
      const y = yOf(close);
      if(!moved){
        ctx.moveTo(x, y);
        moved = true;
      }else{
        ctx.lineTo(x, y);
      }
    });
    ctx.stroke();

    const last = points[points.length - 1];
    if(last && Number.isFinite(Number(last.close))){
      const x = xOf(points.length - 1);
      const y = yOf(Number(last.close));
      ctx.fillStyle = state.tone === "down" ? downColor : upColor;
      ctx.beginPath();
      ctx.arc(x, y, 4 * size.ratio, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  const maPeriod = Number(els.maSelect && els.maSelect.value);
  if(maPeriod === 10 || maPeriod === 20){
    drawMovingAverage(maPeriod);
  }

  ctx.fillStyle = "#64748b";
  ctx.font = `${11 * size.ratio}px system-ui, sans-serif`;
  ctx.textAlign = "left";
  ctx.fillText(safe(state.max_price_text, "--"), 8 * size.ratio, padT + 4 * size.ratio);
  ctx.fillText(safe(state.min_price_text, "--"), 8 * size.ratio, padT + ch);
}

function renderState(state){
  current = state;
  const active = state.active || {};
  if(active.group && active.group !== activeGroup){
    activeGroup = active.group;
    optionsSignature = "";
  }

  groupButtons();
  renderOptions(state);
  els.assetSelect.value = state.settings && state.settings.asset || "";
  els.intervalSelect.value = state.settings && state.settings.interval || "5m";
  els.modeSelect.value = state.settings && state.settings.mode || "line";
  els.maSelect.value = state.settings && state.settings.ma || "off";
  els.currencySelect.value = state.settings && state.settings.currency || "USD";
  currencyButtons();

  setBadge(state.tone, state.loading ? "sync" : state.status, state);
  const unit = safe(state.unit_text, "");
  const currency = safe(state.currency_text, safe(state.currency, "--")) + unit;
  const fx = state.currency === "CNY" ? " · USD/CNY " + rateLabel(state.fx_rate) : "";
  els.routeMeta.textContent = safe(active.source, "--") + " · " + safe(active.symbol || active.secid, "--") + fx;
  els.assetName.textContent = safe(active.text, "--");
  els.assetMeta.textContent = (groupText[active.group] || safe(active.group, "--")) + " · " + currency;
  els.priceText.textContent = safe(state.price_text, "--");
  els.changeText.textContent = safe(state.change_text, "--") + "  " + safe(state.change_pct_text, "--%");
  els.changeText.className = "change " + (state.tone === "down" ? "down" : "up");
  const trendColor = toneColor(state, state.tone);
  els.priceText.style.color = trendColor;
  els.changeText.style.color = trendColor;
  els.changeText.style.background = toneSoftColor(state, state.tone);
  const maText = maLabel(els.maSelect && els.maSelect.value);
  const maSuffix = maText === "不显示" ? "" : " · " + maText;
  els.statInterval.textContent = safe(state.settings && state.settings.interval, "--") + " · " + modeLabel(state.settings && state.settings.mode) + maSuffix + " · " + safe(state.currency, "--") + unit;
  els.statHigh.textContent = safe(state.max_price_text, "--");
  els.statLow.textContent = safe(state.min_price_text, "--");
  els.statUpdate.textContent = safe(state.updated_text, "--");
  setHint(state.error || "", state.tone === "error");
  drawChart(state);
}

async function refreshState(){
  if(busy){
    return;
  }
  busy = true;
  try{
    renderState(await getJson("/state?_=" + Date.now()));
  }catch(err){
    setBadge("error", "err", null);
    setHint("状态读取失败：" + err.message, true);
  }finally{
    busy = false;
  }
}

async function applySelectedAsset(){
  if(!els.assetSelect.value){
    setHint("请选择标的", true);
    return;
  }
  const query = new URLSearchParams({
    asset: els.assetSelect.value,
    interval: els.intervalSelect.value,
    mode: els.modeSelect.value,
    ma: els.maSelect.value,
    currency: els.currencySelect.value
  });
  renderState(await getJson("/set?" + query.toString()));
  window.setTimeout(refreshState, 260);
}

async function applyCustom(){
  const source = els.sourceSelect.value;
  const query = new URLSearchParams({
    source,
    symbol: els.symbolInput.value.trim(),
    name: els.nameInput.value.trim(),
    market: els.marketSelect.value,
    interval: els.intervalSelect.value,
    mode: els.modeSelect.value,
    ma: els.maSelect.value,
    currency: els.currencySelect.value
  });
  renderState(await getJson("/set?" + query.toString()));
  window.setTimeout(refreshState, 260);
}

async function refreshNow(){
  renderState(await getJson("/refresh?_=" + Date.now()));
  window.setTimeout(refreshState, 260);
}

function syncSourceFields(){
  const source = els.sourceSelect.value;
  els.marketField.classList.toggle("hidden", source !== "eastmoney");
  if(source === "binance"){
    els.symbolInput.value = "BTCUSDT";
    els.nameInput.value = "BTC / USDT";
  }else{
    if(activeGroup === "nasdaq"){
      els.marketSelect.value = "100";
      els.symbolInput.value = "NDX";
      els.nameInput.value = "纳斯达克";
    }else if(activeGroup === "metal"){
      els.marketSelect.value = "101";
      els.symbolInput.value = "GC00Y";
      els.nameInput.value = "COMEX黄金";
    }else{
      els.marketSelect.value = "1";
      els.symbolInput.value = "000300";
      els.nameInput.value = "沪深300";
    }
  }
}

document.querySelectorAll("[data-group]").forEach((button) => {
  button.addEventListener("click", () => {
    activeGroup = button.dataset.group;
    optionsSignature = "";
    groupButtons();
    if(current){
      renderOptions(current);
    }
    if(els.assetSelect.options.length > 0){
      els.assetSelect.selectedIndex = 0;
    }
    syncSourceFields();
    applySelectedAsset().catch((err) => setHint("切换失败：" + err.message, true));
  });
});

document.querySelectorAll("[data-currency]").forEach((button) => {
  button.addEventListener("click", () => {
    els.currencySelect.value = button.dataset.currency || "USD";
    currencyButtons();
    applySelectedAsset().catch((err) => setHint("切换失败：" + err.message, true));
  });
});

document.getElementById("applyCustom").addEventListener("click", () => {
  applyCustom().catch((err) => setHint("自定义失败：" + err.message, true));
});
document.getElementById("refreshNow").addEventListener("click", () => {
  refreshNow().catch((err) => setHint("刷新失败：" + err.message, true));
});
document.getElementById("clearCustom").addEventListener("click", () => {
  els.symbolInput.value = "";
  els.nameInput.value = "";
  setHint("");
});
els.sourceSelect.addEventListener("change", syncSourceFields);
els.assetSelect.addEventListener("change", () => {
  applySelectedAsset().catch((err) => setHint("切换失败：" + err.message, true));
});
els.intervalSelect.addEventListener("change", () => {
  applySelectedAsset().catch((err) => setHint("切换失败：" + err.message, true));
});
els.modeSelect.addEventListener("change", () => {
  applySelectedAsset().catch((err) => setHint("切换失败：" + err.message, true));
});
els.maSelect.addEventListener("change", () => {
  applySelectedAsset().catch((err) => setHint("切换失败：" + err.message, true));
});
window.addEventListener("resize", () => current && drawChart(current));

syncSourceFields();
refreshState();
setInterval(refreshState, 2000);
</script>
</body>
</html>
]=]
  })
end

-- 构造 Web 模块实例。
function Web.new(backend, opts)
  opts = opts or {}
  local self = {
    backend = backend,
    route_base = opts.route_base or "/btc",
    api_prefix = (opts.route_base or "/btc") .. "/api",
    routes = {},
    started = false,
  }

  -- 注册路由并记录，停止时逐项注销。
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
    return true, nil
  end

  -- 页面入口响应。
  function self:route_index(req)
    return text_response("200 OK", "text/html; charset=utf-8", build_html(self.api_prefix))
  end

  -- 状态 API。
  function self:route_state(req)
    return json_response("200 OK", self.backend:snapshot())
  end

  -- 设置 API，支持预设 asset 或自定义 source/symbol。
  function self:route_set(req)
    local q = parse_query(req and req.query or "")
    local ok = self.backend:apply_settings(q, true)
    if not ok then
      return json_response("400 Bad Request", self.backend:snapshot())
    end
    self.backend:tick()
    return json_response("200 OK", self.backend:snapshot())
  end

  -- 手动刷新 API。
  function self:route_refresh(req)
    self.backend:queue_refresh()
    self.backend:tick()
    return json_response("200 OK", self.backend:snapshot())
  end

  -- 启动 HTTPD 路由。
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
    self:register(httpd.GET, self.api_prefix .. "/set", function(req) return self:route_set(req) end)
    self:register(httpd.GET, self.api_prefix .. "/refresh", function(req) return self:route_refresh(req) end)
    self:register(httpd.GET, self.api_prefix .. "/health", function(req)
      return text_response("200 OK", "text/plain; charset=utf-8", "ok")
    end)

    if app and app.set_webui then
      pcall(function() app.set_webui(true) end)
    end
    self.started = true
  end

  -- 注销路由并关闭 app WebUI 标记。
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
