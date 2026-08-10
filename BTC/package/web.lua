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
local function build_html(api_prefix, language)
  api_prefix = js_string(api_prefix)
  language = js_string(language or "zh-CN")
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
#groupButtons{grid-template-columns:repeat(3,minmax(0,1fr))}
.currency-seg{grid-template-columns:repeat(3,minmax(0,1fr))}
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
.custom-section{display:grid;gap:14px}
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
  #groupButtons{grid-template-columns:repeat(2,minmax(0,1fr))}
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
      <a class="main-link" href="/main" data-i18n="main">Main</a>
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
        <div class="stat"><span data-i18n="interval">周期</span><strong id="statInterval">--</strong></div>
        <div class="stat"><span data-i18n="high">最高</span><strong id="statHigh">--</strong></div>
        <div class="stat"><span data-i18n="low">最低</span><strong id="statLow">--</strong></div>
        <div class="stat"><span data-i18n="updated">更新</span><strong id="statUpdate">--</strong></div>
      </div>
    </article>

    <aside class="panel controls">
      <div class="seg" id="groupButtons">
        <button data-group="fx" data-i18n="fx">汇率</button>
        <button data-group="crypto" data-i18n="crypto">币价</button>
        <button data-group="nasdaq" data-i18n="nasdaq">纳斯达克</button>
        <button data-group="metal" data-i18n="metal">金银铜</button>
        <button data-group="ashare" data-i18n="ashare">A股</button>
        <button data-group="taiwan" data-i18n="taiwan">台股</button>
      </div>

      <div class="field" id="currencyField">
        <label data-i18n="currency">显示币种</label>
        <div class="seg currency-seg" id="currencyButtons">
          <button data-currency="USD" data-i18n="usd">美金</button>
          <button data-currency="CNY" data-i18n="cny">人民币</button>
          <button data-currency="TWD" data-i18n="twd">新台币</button>
        </div>
        <select class="hidden" id="currencySelect"></select>
      </div>

      <div class="field" id="assetField">
        <label for="assetSelect" data-i18n="asset">标的</label>
        <select id="assetSelect"></select>
      </div>

      <div class="grid2 hidden" id="fxPairField">
        <div class="field">
          <label for="baseCurrencyInput" data-i18n="base_currency">原货币</label>
          <select id="baseCurrencyInput"></select>
        </div>
        <div class="field">
          <label for="quoteCurrencyInput" data-i18n="quote_currency">目标货币</label>
          <select id="quoteCurrencyInput"></select>
        </div>
      </div>

      <div class="field">
        <label for="intervalSelect" data-i18n="trend_interval">走势周期</label>
        <select id="intervalSelect"></select>
      </div>

      <div class="field" id="modeField">
        <label for="modeSelect" data-i18n="chart">图表</label>
        <select id="modeSelect">
          <option value="line" data-i18n="line">折线</option>
          <option value="candle" data-i18n="candle">K线</option>
        </select>
      </div>

      <div class="field" id="maField">
        <label for="maSelect" data-i18n="ma">均线</label>
        <select id="maSelect">
          <option value="off" data-i18n="off">不显示</option>
          <option value="10">MA10</option>
          <option value="20">MA20</option>
        </select>
      </div>

      <div class="actions">
        <button class="secondary" id="refreshNow" data-i18n="refresh">刷新</button>
      </div>

      <div class="custom-section" id="customSection">
      <div class="divider"></div>

      <div class="subhead" data-i18n="custom">自定义</div>
      <div class="grid2">
        <div class="field">
          <label for="sourceSelect" data-i18n="source">来源</label>
          <select id="sourceSelect">
            <option value="binance" data-i18n="crypto">币价</option>
            <option value="eastmoney" data-i18n="eastmoney">Eastmoney公开</option>
            <option value="twse" data-i18n="twse">台湾行情 (TWSE MIS)</option>
          </select>
        </div>
        <div class="field" id="marketField">
          <label for="marketSelect" data-i18n="market">市场</label>
          <select id="marketSelect">
            <option value="1" data-i18n="shanghai">沪市/指数</option>
            <option value="0" data-i18n="shenzhen">深市</option>
            <option value="100" data-i18n="nasdaq_index">纳斯达克指数</option>
            <option value="105" data-i18n="us_stock">美股</option>
            <option value="101" data-i18n="metal_futures">金银铜期货</option>
          </select>
        </div>
      </div>
      <div class="grid2" id="symbolFields">
        <div class="field">
          <label for="symbolInput" data-i18n="symbol">代码</label>
          <input id="symbolInput" value="BTCUSDT" autocomplete="off">
        </div>
        <div class="field">
          <label for="nameInput" data-i18n="name">名称</label>
          <input id="nameInput" value="BTC / USDT" autocomplete="off">
        </div>
      </div>
      <div class="actions">
        <button class="primary" id="applyCustom" data-i18n="add_view">添加并查看</button>
        <button class="secondary" id="clearCustom" data-i18n="clear">清空</button>
      </div>
      </div>
      <div class="hint" id="hint"></div>
    </aside>
  </section>
  <footer class="site-footer">
    <div>Copyright &copy; 2026 clocteck. Licensed under GPL-3.0. Open source: <a href="https://github.com/clocteck" target="_blank" rel="noopener">github.com/clocteck</a>.</div>
    <div>Data sources: Binance, Eastmoney, TWSE MIS, Open ER-API, and Frankfurter daily FX history. For display only; not financial advice.</div>
  </footer>
</main>

<script>
const API = "]=], api_prefix, [=[";
const LANG = "]=], language, [=[";
const MESSAGES = {
  "zh-CN": {main:"主页",interval:"周期",high:"最高",low:"最低",updated:"更新",fx:"汇率",crypto:"币价",nasdaq:"纳斯达克",metal:"金银铜",ashare:"A股",taiwan:"台股",currency:"显示币种",usd:"美金",cny:"人民币",twd:"新台币",asset:"标的",trend_interval:"走势周期",chart:"图表",line:"折线",candle:"K线",ma:"均线",off:"不显示",refresh:"刷新",custom:"自定义",source:"来源",fx_source:"公开汇率",base_currency:"原货币",quote_currency:"目标货币",eastmoney:"Eastmoney公开",yahoo:"Yahoo Finance",twse:"台湾行情 (TWSE MIS)",market:"市场",shanghai:"沪市/指数",shenzhen:"深市",nasdaq_index:"纳斯达克指数",us_stock:"美股",metal_futures:"金银铜期货",symbol:"代码",name:"名称",add_view:"添加并查看",clear:"清空",loading:"加载中",ready:"就绪",cold:"启动中",error:"错误"},
  en: {main:"Main",interval:"Interval",high:"High",low:"Low",updated:"Updated",fx:"FX",crypto:"Crypto",nasdaq:"Nasdaq",metal:"Metals",ashare:"A-shares",taiwan:"Taiwan",currency:"Display currency",usd:"USD",cny:"CNY",twd:"TWD",asset:"Asset",trend_interval:"Trend interval",chart:"Chart",line:"Line",candle:"Candles",ma:"Moving average",off:"Off",refresh:"Refresh",custom:"Custom",source:"Source",fx_source:"Public FX rates",base_currency:"Base currency",quote_currency:"Quote currency",eastmoney:"Eastmoney public",yahoo:"Yahoo Finance",twse:"Taiwan quotes (TWSE MIS)",market:"Market",shanghai:"Shanghai / Index",shenzhen:"Shenzhen",nasdaq_index:"Nasdaq index",us_stock:"US stocks",metal_futures:"Metal futures",symbol:"Symbol",name:"Name",add_view:"Add and view",clear:"Clear",loading:"Loading",ready:"Ready",cold:"Starting",error:"Error"},
  ja: {main:"メイン",interval:"期間",high:"高値",low:"安値",updated:"更新",fx:"為替",crypto:"暗号資産",nasdaq:"ナスダック",metal:"金銀銅",ashare:"中国A株",taiwan:"台湾株",currency:"表示通貨",usd:"米ドル",cny:"人民元",twd:"台湾ドル",asset:"銘柄",trend_interval:"表示期間",chart:"チャート",line:"折線",candle:"ローソク",ma:"移動平均",off:"表示しない",refresh:"更新",custom:"カスタム",source:"データ元",fx_source:"公開為替レート",base_currency:"基準通貨",quote_currency:"換算先通貨",eastmoney:"Eastmoney公開",yahoo:"Yahoo Finance",twse:"台湾相場 (TWSE MIS)",market:"市場",shanghai:"上海 / 指数",shenzhen:"深圳",nasdaq_index:"ナスダック指数",us_stock:"米国株",metal_futures:"金属先物",symbol:"コード",name:"名称",add_view:"追加して表示",clear:"クリア",loading:"読込中",ready:"準備完了",cold:"起動中",error:"エラー"},
  "zh-TW": {main:"主頁",interval:"週期",high:"最高",low:"最低",updated:"更新",fx:"匯率",crypto:"幣價",nasdaq:"那斯達克",metal:"金銀銅",ashare:"A股",taiwan:"台股",currency:"顯示幣別",usd:"美元",cny:"人民幣",twd:"新台幣",asset:"標的",trend_interval:"走勢週期",chart:"圖表",line:"折線",candle:"K線",ma:"均線",off:"不顯示",refresh:"重新整理",custom:"自訂",source:"來源",fx_source:"公開匯率",base_currency:"來源貨幣",quote_currency:"目標貨幣",eastmoney:"Eastmoney公開",yahoo:"Yahoo Finance",twse:"臺灣行情 (TWSE MIS)",market:"市場",shanghai:"滬市/指數",shenzhen:"深市",nasdaq_index:"那斯達克指數",us_stock:"美股",metal_futures:"金銀銅期貨",symbol:"代碼",name:"名稱",add_view:"新增並檢視",clear:"清除",loading:"載入中",ready:"就緒",cold:"啟動中",error:"錯誤"}
};
const MSG = MESSAGES[LANG] || MESSAGES["zh-CN"];
const tr = (key) => MSG[key] || MESSAGES["zh-CN"][key] || key;
const ERROR_TEXT = {
  "zh-CN": {state:"状态读取失败：",choose:"请选择标的",switch:"切换失败：",custom:"自定义失败：",refresh:"刷新失败："},
  en: {state:"Failed to read status: ",choose:"Select an asset",switch:"Switch failed: ",custom:"Custom asset failed: ",refresh:"Refresh failed: "},
  ja: {state:"状態の取得に失敗: ",choose:"銘柄を選択してください",switch:"切り替え失敗: ",custom:"カスタム銘柄の追加に失敗: ",refresh:"更新失敗: "},
  "zh-TW": {state:"讀取狀態失敗：",choose:"請選擇標的",switch:"切換失敗：",custom:"自訂標的失敗：",refresh:"重新整理失敗："}
};
const errText = ERROR_TEXT[LANG] || ERROR_TEXT["zh-CN"];
document.documentElement.lang = LANG;
document.querySelectorAll("[data-i18n]").forEach((node) => { node.textContent = tr(node.dataset.i18n); });
const groupText = { fx: tr("fx"), crypto: tr("crypto"), nasdaq: tr("nasdaq"), metal: tr("metal"), ashare: tr("ashare"), taiwan: tr("taiwan") };
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
  assetField: document.getElementById("assetField"),
  assetSelect: document.getElementById("assetSelect"),
  fxPairField: document.getElementById("fxPairField"),
  intervalSelect: document.getElementById("intervalSelect"),
  modeField: document.getElementById("modeField"),
  modeSelect: document.getElementById("modeSelect"),
  maField: document.getElementById("maField"),
  maSelect: document.getElementById("maSelect"),
  currencySelect: document.getElementById("currencySelect"),
  currencyField: document.getElementById("currencyField"),
  sourceSelect: document.getElementById("sourceSelect"),
  customSection: document.getElementById("customSection"),
  marketField: document.getElementById("marketField"),
  marketSelect: document.getElementById("marketSelect"),
  symbolInput: document.getElementById("symbolInput"),
  nameInput: document.getElementById("nameInput"),
  symbolFields: document.getElementById("symbolFields"),
  baseCurrencyInput: document.getElementById("baseCurrencyInput"),
  quoteCurrencyInput: document.getElementById("quoteCurrencyInput"),
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
  return mode === "candle" ? tr("candle") : tr("line");
}

function maLabel(value){
  if(value === "10"){
    return "MA10";
  }
  if(value === "20"){
    return "MA20";
  }
  return tr("off");
}

const ASSET_NAMES = {
  "zh-CN": {"nasdaq:100.NDX":"纳斯达克","nasdaq:100.NDX100":"纳斯达克100","metal:101.GC00Y":"COMEX黄金","metal:101.SI00Y":"COMEX白银","metal:101.HG00Y":"COMEX铜","ashare:1.000001":"上证指数","ashare:1.000300":"沪深300","ashare:1.000905":"中证500","ashare:1.000852":"中证1000","ashare:0.399001":"深证成指","ashare:0.399006":"创业板指","ashare:1.600519":"贵州茅台","ashare:0.000001":"平安银行","ashare:0.300750":"宁德时代"},
  en: {"nasdaq:100.NDX":"Nasdaq","nasdaq:100.NDX100":"Nasdaq 100","metal:101.GC00Y":"COMEX Gold","metal:101.SI00Y":"COMEX Silver","metal:101.HG00Y":"COMEX Copper","ashare:1.000001":"SSE Composite","ashare:1.000300":"CSI 300","ashare:1.000905":"CSI 500","ashare:1.000852":"CSI 1000","ashare:0.399001":"SZSE Component","ashare:0.399006":"ChiNext","ashare:1.600519":"Kweichow Moutai","ashare:0.000001":"Ping An Bank","ashare:0.300750":"CATL"},
  ja: {"nasdaq:100.NDX":"ナスダック","nasdaq:100.NDX100":"ナスダック100","metal:101.GC00Y":"COMEX金","metal:101.SI00Y":"COMEX銀","metal:101.HG00Y":"COMEX銅","ashare:1.000001":"上海総合","ashare:1.000300":"CSI 300","ashare:1.000905":"CSI 500","ashare:1.000852":"CSI 1000","ashare:0.399001":"深圳成分","ashare:0.399006":"創業板","ashare:1.600519":"貴州茅台","ashare:0.000001":"平安銀行","ashare:0.300750":"CATL"},
  "zh-TW": {"nasdaq:100.NDX":"那斯達克","nasdaq:100.NDX100":"那斯達克100","metal:101.GC00Y":"COMEX黃金","metal:101.SI00Y":"COMEX白銀","metal:101.HG00Y":"COMEX銅","ashare:1.000001":"上證指數","ashare:1.000300":"滬深300","ashare:1.000905":"中證500","ashare:1.000852":"中證1000","ashare:0.399001":"深證成指","ashare:0.399006":"創業板指","ashare:1.600519":"貴州茅台","ashare:0.000001":"平安銀行","ashare:0.300750":"寧德時代"}
};

Object.assign(ASSET_NAMES["zh-CN"], {"taiwan:^TWII":"台湾加权指数","taiwan:2330.TW":"台积电","taiwan:2317.TW":"鸿海","taiwan:2454.TW":"联发科","taiwan:2308.TW":"台达电","taiwan:2881.TW":"富邦金","taiwan:6488.TWO":"环球晶"});
Object.assign(ASSET_NAMES.en, {"taiwan:^TWII":"TAIEX","taiwan:2330.TW":"TSMC","taiwan:2317.TW":"Hon Hai","taiwan:2454.TW":"MediaTek","taiwan:2308.TW":"Delta Electronics","taiwan:2881.TW":"Fubon Financial","taiwan:6488.TWO":"GlobalWafers"});
Object.assign(ASSET_NAMES.ja, {"taiwan:^TWII":"台湾加権指数","taiwan:2330.TW":"TSMC","taiwan:2317.TW":"鴻海","taiwan:2454.TW":"MediaTek","taiwan:2308.TW":"デルタ電子","taiwan:2881.TW":"富邦金控","taiwan:6488.TWO":"GlobalWafers"});
Object.assign(ASSET_NAMES["zh-TW"], {"taiwan:^TWII":"臺灣加權指數","taiwan:2330.TW":"台積電","taiwan:2317.TW":"鴻海","taiwan:2454.TW":"聯發科","taiwan:2308.TW":"台達電","taiwan:2881.TW":"富邦金","taiwan:6488.TWO":"環球晶"});

function assetDisplayName(asset){
  const map = ASSET_NAMES[LANG] || {};
  return map[asset && asset.id] || safe(asset && asset.text, asset && asset.symbol || "--");
}

function rateLabel(value){
  const rate = Number(value);
  return Number.isFinite(rate) ? rate.toFixed(4) : "--";
}

function currencyLabel(value){
  if(value === "CNY") return tr("cny");
  if(value === "TWD") return tr("twd");
  if(value === "USD") return tr("usd");
  return safe(value, "--");
}

const FX_CURRENCIES = [
  {code:"CNY", zh:"人民币", en:"Chinese Yuan", ja:"中国人民元", tw:"人民幣"},
  {code:"USD", zh:"美元", en:"US Dollar", ja:"米ドル", tw:"美元"},
  {code:"EUR", zh:"欧元", en:"Euro", ja:"ユーロ", tw:"歐元"},
  {code:"JPY", zh:"日元", en:"Japanese Yen", ja:"日本円", tw:"日圓"},
  {code:"GBP", zh:"英镑", en:"British Pound", ja:"英ポンド", tw:"英鎊"},
  {code:"HKD", zh:"港币", en:"Hong Kong Dollar", ja:"香港ドル", tw:"港幣"},
  {code:"TWD", zh:"新台币", en:"Taiwan Dollar", ja:"台湾ドル", tw:"新台幣"},
  {code:"KRW", zh:"韩元", en:"South Korean Won", ja:"韓国ウォン", tw:"韓元"},
  {code:"AUD", zh:"澳元", en:"Australian Dollar", ja:"豪ドル", tw:"澳元"},
  {code:"CAD", zh:"加元", en:"Canadian Dollar", ja:"カナダドル", tw:"加元"},
  {code:"CHF", zh:"瑞士法郎", en:"Swiss Franc", ja:"スイスフラン", tw:"瑞士法郎"},
  {code:"SGD", zh:"新加坡元", en:"Singapore Dollar", ja:"シンガポールドル", tw:"新加坡元"},
  {code:"NZD", zh:"新西兰元", en:"New Zealand Dollar", ja:"NZドル", tw:"紐西蘭元"},
  {code:"THB", zh:"泰铢", en:"Thai Baht", ja:"タイバーツ", tw:"泰銖"},
  {code:"INR", zh:"印度卢比", en:"Indian Rupee", ja:"インドルピー", tw:"印度盧比"},
  {code:"AED", zh:"阿联酋迪拉姆", en:"UAE Dirham", ja:"UAEディルハム", tw:"阿聯酋迪拉姆"},
  {code:"MYR", zh:"马来西亚林吉特", en:"Malaysian Ringgit", ja:"マレーシアリンギット", tw:"馬來西亞令吉"},
  {code:"PHP", zh:"菲律宾比索", en:"Philippine Peso", ja:"フィリピンペソ", tw:"菲律賓披索"}
];

function fxCurrencyName(item){
  if(LANG === "en") return item.en;
  if(LANG === "ja") return item.ja;
  if(LANG === "zh-TW") return item.tw;
  return item.zh;
}

function populateFxCurrencies(){
  [els.baseCurrencyInput, els.quoteCurrencyInput].forEach((select) => {
    select.innerHTML = "";
    FX_CURRENCIES.forEach((item) => {
      const option = document.createElement("option");
      option.value = item.code;
      option.textContent = item.code + " · " + fxCurrencyName(item);
      select.appendChild(option);
    });
  });
  els.baseCurrencyInput.value = "USD";
  els.quoteCurrencyInput.value = "CNY";
}

function redUpMarket(state){
  const group = state && state.active && state.active.group;
  return group === "ashare" || group === "metal" || group === "taiwan";
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
  return assetDisplayName(asset) + " · " + safe(asset.symbol || asset.secid, "");
}

function renderOptions(state){
  const assets = Array.isArray(state.assets) ? state.assets : [];
  const intervals = Array.isArray(state.intervals) ? state.intervals : [];
  const currencies = Array.isArray(state.currencies) ? state.currencies : [];
  const signature = activeGroup + "|" + assets.map((a) => a.id + ":" + a.group).join(",") + "|" + intervals.map((i) => i.label + ":" + safe(i.fx_label, "")).join(",") + "|" + currencies.map((c) => c.value).join(",");
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
    option.textContent = activeGroup === "fx" ? safe(item.fx_label, item.label) : item.label;
    els.intervalSelect.appendChild(option);
  });

  els.currencySelect.innerHTML = "";
  (currencies.length ? currencies : [{ value: "USD", text: "美金" }, { value: "CNY", text: "人民币" }, { value: "TWD", text: "新台币" }]).forEach((item) => {
    const option = document.createElement("option");
    option.value = item.value;
    option.textContent = currencyLabel(item.value);
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
    if(points.length === 1){
      return padL + cw / 2;
    }
    const first = Number(points[0] && points[0].time_value);
    const last = Number(points[points.length - 1] && points[points.length - 1].time_value);
    const current = Number(points[index] && points[index].time_value);
    if(Number.isFinite(first) && Number.isFinite(last) && Number.isFinite(current) && last > first){
      return padL + cw * Math.max(0, Math.min(1, (current - first) / (last - first)));
    }
    return padL + cw * index / Math.max(1, points.length - 1);
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

      const cx = xOf(index);
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
    els.sourceSelect.value = activeGroup === "crypto" ? "binance" : (activeGroup === "taiwan" ? "twse" : "eastmoney");
    syncSourceFields();
  }

  groupButtons();
  renderOptions(state);
  els.assetSelect.value = state.settings && state.settings.asset || "";
  els.intervalSelect.value = state.settings && state.settings.interval || "5m";
  els.modeSelect.value = state.settings && state.settings.mode || "line";
  els.maSelect.value = state.settings && state.settings.ma || "off";
  els.currencySelect.value = state.settings && state.settings.currency || "USD";
  currencyButtons();
  const isFx = active.group === "fx";
  els.currencyField.classList.toggle("hidden", isFx);
  els.assetField.classList.toggle("hidden", isFx);
  els.fxPairField.classList.toggle("hidden", !isFx);
  els.modeField.classList.toggle("hidden", isFx);
  els.maField.classList.toggle("hidden", isFx);
  els.customSection.classList.toggle("hidden", isFx);
  if(isFx){
    els.baseCurrencyInput.value = safe(active.base, "USD");
    els.quoteCurrencyInput.value = safe(active.quote, "CNY");
  }

  setBadge(state.tone, state.loading ? tr("loading") : tr(state.status), state);
  const unit = safe(state.unit_text, "");
  const currency = currencyLabel(state.currency) + unit;
  const fx = active.group === "fx" ? "" : (state.currency === "CNY"
    ? " · USD/CNY " + rateLabel(state.fx_rate)
    : (state.currency === "TWD" ? " · USD/TWD " + rateLabel(state.fx_twd_rate) : ""));
  els.routeMeta.textContent = safe(state.live_source || active.source, "--") + " · " + safe(active.symbol || active.secid, "--") + fx;
  els.assetName.textContent = assetDisplayName(active);
  els.assetMeta.textContent = (groupText[active.group] || safe(active.group, "--")) + " · " + currency;
  els.priceText.textContent = safe(state.price_text, "--");
  els.changeText.textContent = safe(state.change_text, "--") + "  " + safe(state.change_pct_text, "--%");
  els.changeText.className = "change " + (state.tone === "down" ? "down" : "up");
  const trendColor = toneColor(state, state.tone);
  els.priceText.style.color = trendColor;
  els.changeText.style.color = trendColor;
  els.changeText.style.background = toneSoftColor(state, state.tone);
  const maText = maLabel(els.maSelect && els.maSelect.value);
  const maSuffix = maText === tr("off") ? "" : " · " + maText;
  els.statInterval.textContent = safe(state.settings && (state.settings.interval_text || state.settings.interval), "--") + " · " + modeLabel(state.settings && state.settings.mode) + maSuffix + " · " + safe(state.currency, "--") + unit;
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
    setHint(errText.state + err.message, true);
  }finally{
    busy = false;
  }
}

async function applySelectedAsset(){
  if(!els.assetSelect.value){
    setHint(errText.choose, true);
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

async function applyFxPair(changed){
  let base = els.baseCurrencyInput.value || "USD";
  let quote = els.quoteCurrencyInput.value || "CNY";
  if(base === quote){
    const replacement = FX_CURRENCIES.find((item) => item.code !== base);
    if(changed === "base"){
      quote = replacement ? replacement.code : "CNY";
      els.quoteCurrencyInput.value = quote;
    }else{
      base = replacement ? replacement.code : "USD";
      els.baseCurrencyInput.value = base;
    }
  }
  const query = new URLSearchParams({
    source: "fx",
    group: "fx",
    base_currency: base,
    quote_currency: quote,
    interval: els.intervalSelect.value,
    mode: "line",
    ma: "off"
  });
  renderState(await getJson("/set?" + query.toString()));
  window.setTimeout(refreshState, 260);
}

async function applyCustom(){
  const source = els.sourceSelect.value;
  const query = new URLSearchParams({
    source,
    group: activeGroup,
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
  }else if(source === "twse"){
    if(activeGroup === "taiwan"){
      els.symbolInput.value = "2330.TW";
      els.nameInput.value = assetDisplayName({id:"taiwan:2330.TW", text:"台积电", symbol:"2330.TW"});
    }else if(activeGroup === "metal"){
      els.symbolInput.value = "GC=F";
      els.nameInput.value = "COMEX Gold";
    }else{
      els.symbolInput.value = "AAPL";
      els.nameInput.value = "Apple";
    }
  }else{
    if(activeGroup === "nasdaq"){
      els.marketSelect.value = "100";
      els.symbolInput.value = "NDX";
      els.nameInput.value = assetDisplayName({id:"nasdaq:100.NDX", text:"纳斯达克", symbol:"NDX"});
    }else if(activeGroup === "metal"){
      els.marketSelect.value = "101";
      els.symbolInput.value = "GC00Y";
      els.nameInput.value = assetDisplayName({id:"metal:101.GC00Y", text:"COMEX黄金", symbol:"GC00Y"});
    }else{
      els.marketSelect.value = "1";
      els.symbolInput.value = "000300";
      els.nameInput.value = assetDisplayName({id:"ashare:1.000300", text:"沪深300", symbol:"000300"});
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
    els.sourceSelect.value = activeGroup === "crypto" ? "binance" : (activeGroup === "taiwan" ? "twse" : "eastmoney");
    if(activeGroup === "fx"){
      els.modeSelect.value = "line";
      els.maSelect.value = "off";
    }
    if(activeGroup === "taiwan"){
      els.currencySelect.value = "TWD";
      currencyButtons();
    }
    syncSourceFields();
    applySelectedAsset().catch((err) => setHint(errText.switch + err.message, true));
  });
});

document.querySelectorAll("[data-currency]").forEach((button) => {
  button.addEventListener("click", () => {
    els.currencySelect.value = button.dataset.currency || "USD";
    currencyButtons();
    applySelectedAsset().catch((err) => setHint(errText.switch + err.message, true));
  });
});

document.getElementById("applyCustom").addEventListener("click", () => {
  applyCustom().catch((err) => setHint(errText.custom + err.message, true));
});
document.getElementById("refreshNow").addEventListener("click", () => {
  refreshNow().catch((err) => setHint(errText.refresh + err.message, true));
});
document.getElementById("clearCustom").addEventListener("click", () => {
  els.symbolInput.value = "";
  els.nameInput.value = "";
  setHint("");
});
els.sourceSelect.addEventListener("change", syncSourceFields);
els.baseCurrencyInput.addEventListener("change", () => {
  applyFxPair("base").catch((err) => setHint(errText.switch + err.message, true));
});
els.quoteCurrencyInput.addEventListener("change", () => {
  applyFxPair("quote").catch((err) => setHint(errText.switch + err.message, true));
});
els.assetSelect.addEventListener("change", () => {
  applySelectedAsset().catch((err) => setHint(errText.switch + err.message, true));
});
els.intervalSelect.addEventListener("change", () => {
  applySelectedAsset().catch((err) => setHint(errText.switch + err.message, true));
});
els.modeSelect.addEventListener("change", () => {
  applySelectedAsset().catch((err) => setHint(errText.switch + err.message, true));
});
els.maSelect.addEventListener("change", () => {
  applySelectedAsset().catch((err) => setHint(errText.switch + err.message, true));
});
window.addEventListener("resize", () => current && drawChart(current));

populateFxCurrencies();
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
    language = opts.language or "zh-CN",
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
    return text_response("200 OK", "text/html; charset=utf-8", build_html(self.api_prefix, self.language))
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
        max_handlers = 128,
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
