local I18n = {}

local SETTINGS_PATH = "/sd/apps/settings.json"
local DEFAULT_LANGUAGE = "zh-CN"

local function normalize(value)
  local text = tostring(value or ""):gsub("_", "-")
  if text == "en" or text:match("^en%-") then return "en" end
  if text == "ja" or text:match("^ja%-") then return "ja" end
  if text == "zh-TW" or text == "zh-Hant" or text:match("^zh%-Hant") or text:match("^zh%-HK") then return "zh-TW" end
  return DEFAULT_LANGUAGE
end

local function read_language()
  if not file or not file.getcontents then return DEFAULT_LANGUAGE end
  local ok, raw = pcall(function() return file.getcontents(SETTINGS_PATH) end)
  if not ok or type(raw) ~= "string" or raw == "" then return DEFAULT_LANGUAGE end
  local codec = rawget(_G, "json") or rawget(_G, "sjson")
  if not codec or not codec.decode then return DEFAULT_LANGUAGE end
  local decoded, doc = pcall(function() return codec.decode(raw) end)
  if not decoded or type(doc) ~= "table" then return DEFAULT_LANGUAGE end
  return normalize(doc.language or doc.locale or doc.lang)
end

local TEXT = {
  ["zh-CN"] = {
    starting = "正在启动", waiting = "等待数据", no_price = "暂无价格", market = "行情",
    sync = "同步", ready = "就绪", loading = "加载中", cold = "启动中", error = "错误",
    line = "折线", updated = "更新", points = "点", usd = "美金", cny = "人民币", twd = "新台币",
    menu = "行情控制", category = "分类", asset = "标的", base_currency = "原货币", quote_currency = "目标货币",
    interval = "周期", chart = "图表", candle = "K线", ma = "均线", display_currency = "显示币种",
    tilt = "重力切换", refresh_now = "立即刷新", on = "开启", off = "关闭", controller_hint = "上下选择  左右修改  MENU返回",
    group_fx = "汇率", group_crypto = "币价", group_nasdaq = "纳斯达克", group_metal = "金银铜", group_ashare = "A股", group_taiwan = "台股",
  },
  en = {
    starting = "Starting", waiting = "Waiting for data", no_price = "No price", market = "Market",
    sync = "SYNC", ready = "READY", loading = "LOADING", cold = "STARTING", error = "ERROR",
    line = "Line", updated = "UPD", points = "pts", usd = "USD", cny = "CNY", twd = "TWD",
    menu = "Market Control", category = "Category", asset = "Asset", base_currency = "Base", quote_currency = "Quote",
    interval = "Interval", chart = "Chart", candle = "Candles", ma = "Moving Avg", display_currency = "Currency",
    tilt = "Tilt Switch", refresh_now = "Refresh Now", on = "On", off = "Off", controller_hint = "UP/DOWN Select  LEFT/RIGHT Change",
    group_fx = "FX", group_crypto = "Crypto", group_nasdaq = "Nasdaq", group_metal = "Metals", group_ashare = "A-shares", group_taiwan = "Taiwan",
  },
  ja = {
    starting = "起動中", waiting = "データ待ち", no_price = "価格なし", market = "相場",
    sync = "同期", ready = "準備完了", loading = "読込中", cold = "起動中", error = "エラー",
    line = "折線", updated = "更新", points = "点", usd = "米ドル", cny = "人民元", twd = "台湾ドル",
    menu = "相場コントロール", category = "カテゴリ", asset = "銘柄", base_currency = "基準通貨", quote_currency = "換算先",
    interval = "期間", chart = "チャート", candle = "ローソク", ma = "移動平均", display_currency = "表示通貨",
    tilt = "傾き切替", refresh_now = "今すぐ更新", on = "オン", off = "オフ", controller_hint = "上下:選択  左右:変更  MENU:戻る",
    group_fx = "為替", group_crypto = "暗号資産", group_nasdaq = "ナスダック", group_metal = "金銀銅", group_ashare = "中国A株", group_taiwan = "台湾株",
  },
  ["zh-TW"] = {
    starting = "正在啟動", waiting = "等待資料", no_price = "暫無價格", market = "行情",
    sync = "同步", ready = "就緒", loading = "載入中", cold = "啟動中", error = "錯誤",
    line = "折線", updated = "更新", points = "點", usd = "美元", cny = "人民幣", twd = "新台幣",
    menu = "行情控制", category = "分類", asset = "標的", base_currency = "來源貨幣", quote_currency = "目標貨幣",
    interval = "週期", chart = "圖表", candle = "K線", ma = "均線", display_currency = "顯示幣別",
    tilt = "重力切換", refresh_now = "立即更新", on = "開啟", off = "關閉", controller_hint = "上下選擇  左右修改  MENU返回",
    group_fx = "匯率", group_crypto = "幣價", group_nasdaq = "那斯達克", group_metal = "金銀銅", group_ashare = "A股", group_taiwan = "台股",
  },
}

local ASSET_NAMES = {
  ["zh-CN"] = {
    ["nasdaq:100.NDX"] = "纳斯达克", ["nasdaq:100.NDX100"] = "纳斯达克100",
    ["metal:101.GC00Y"] = "COMEX黄金", ["metal:101.SI00Y"] = "COMEX白银", ["metal:101.HG00Y"] = "COMEX铜",
    ["ashare:1.000001"] = "上证指数", ["ashare:1.000300"] = "沪深300", ["ashare:1.000905"] = "中证500",
    ["ashare:1.000852"] = "中证1000", ["ashare:0.399001"] = "深证成指", ["ashare:0.399006"] = "创业板指",
    ["ashare:1.600519"] = "贵州茅台", ["ashare:0.000001"] = "平安银行", ["ashare:0.300750"] = "宁德时代",
    ["taiwan:^TWII"] = "台湾加权指数", ["taiwan:2330.TW"] = "台积电", ["taiwan:2317.TW"] = "鸿海",
    ["taiwan:2454.TW"] = "联发科", ["taiwan:2308.TW"] = "台达电", ["taiwan:2881.TW"] = "富邦金", ["taiwan:6488.TWO"] = "环球晶",
  },
  en = {
    ["nasdaq:100.NDX"] = "Nasdaq", ["nasdaq:100.NDX100"] = "Nasdaq 100",
    ["metal:101.GC00Y"] = "COMEX Gold", ["metal:101.SI00Y"] = "COMEX Silver", ["metal:101.HG00Y"] = "COMEX Copper",
    ["ashare:1.000001"] = "SSE Composite", ["ashare:1.000300"] = "CSI 300", ["ashare:1.000905"] = "CSI 500",
    ["ashare:1.000852"] = "CSI 1000", ["ashare:0.399001"] = "SZSE Component", ["ashare:0.399006"] = "ChiNext",
    ["ashare:1.600519"] = "Kweichow Moutai", ["ashare:0.000001"] = "Ping An Bank", ["ashare:0.300750"] = "CATL",
    ["taiwan:^TWII"] = "TAIEX", ["taiwan:2330.TW"] = "TSMC", ["taiwan:2317.TW"] = "Hon Hai",
    ["taiwan:2454.TW"] = "MediaTek", ["taiwan:2308.TW"] = "Delta Electronics", ["taiwan:2881.TW"] = "Fubon Financial", ["taiwan:6488.TWO"] = "GlobalWafers",
  },
  ja = {
    ["nasdaq:100.NDX"] = "ナスダック", ["nasdaq:100.NDX100"] = "ナスダック100",
    ["metal:101.GC00Y"] = "COMEX金", ["metal:101.SI00Y"] = "COMEX銀", ["metal:101.HG00Y"] = "COMEX銅",
    ["ashare:1.000001"] = "上海総合", ["ashare:1.000300"] = "CSI 300", ["ashare:1.000905"] = "CSI 500",
    ["ashare:1.000852"] = "CSI 1000", ["ashare:0.399001"] = "深圳成分", ["ashare:0.399006"] = "創業板",
    ["ashare:1.600519"] = "貴州茅台", ["ashare:0.000001"] = "平安銀行", ["ashare:0.300750"] = "CATL",
    ["taiwan:^TWII"] = "台湾加権指数", ["taiwan:2330.TW"] = "TSMC", ["taiwan:2317.TW"] = "鴻海",
    ["taiwan:2454.TW"] = "MediaTek", ["taiwan:2308.TW"] = "デルタ電子", ["taiwan:2881.TW"] = "富邦金控", ["taiwan:6488.TWO"] = "GlobalWafers",
  },
  ["zh-TW"] = {
    ["nasdaq:100.NDX"] = "那斯達克", ["nasdaq:100.NDX100"] = "那斯達克100",
    ["metal:101.GC00Y"] = "COMEX黃金", ["metal:101.SI00Y"] = "COMEX白銀", ["metal:101.HG00Y"] = "COMEX銅",
    ["ashare:1.000001"] = "上證指數", ["ashare:1.000300"] = "滬深300", ["ashare:1.000905"] = "中證500",
    ["ashare:1.000852"] = "中證1000", ["ashare:0.399001"] = "深證成指", ["ashare:0.399006"] = "創業板指",
    ["ashare:1.600519"] = "貴州茅台", ["ashare:0.000001"] = "平安銀行", ["ashare:0.300750"] = "寧德時代",
    ["taiwan:^TWII"] = "臺灣加權指數", ["taiwan:2330.TW"] = "台積電", ["taiwan:2317.TW"] = "鴻海",
    ["taiwan:2454.TW"] = "聯發科", ["taiwan:2308.TW"] = "台達電", ["taiwan:2881.TW"] = "富邦金", ["taiwan:6488.TWO"] = "環球晶",
  },
}

I18n.language = read_language()
I18n.font_path = ({
  ["zh-CN"] = "/sd/apps/btc/font/btc_ui_zh_cn_12.bin",
  ja = "/sd/apps/btc/font/btc_ui_ja_12.bin",
  ["zh-TW"] = "/sd/apps/btc/font/btc_ui_zh_tw_12.bin",
})[I18n.language]

function I18n:t(key)
  local dict = TEXT[self.language] or TEXT[DEFAULT_LANGUAGE]
  return dict[key] or TEXT.en[key] or tostring(key or "")
end

function I18n:status(value)
  local key = tostring(value or "idle"):lower()
  if key == "idle" then key = "cold" end
  return self:t(key)
end

function I18n:asset_name(asset)
  if not asset then return self:t("market") end
  local names = ASSET_NAMES[self.language] or ASSET_NAMES[DEFAULT_LANGUAGE]
  return names[asset.id] or asset.text or asset.symbol or self:t("market")
end

function I18n:group_name(group)
  return self:t("group_" .. tostring(group or ""))
end

return I18n
