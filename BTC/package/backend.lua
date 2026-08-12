local Backend = {}

local JSON = rawget(_G, "sjson") or rawget(_G, "json")

local DEFAULT_LIMIT = 64
local MAIN_REFRESH_MS = 20000
local ERROR_RETRY_MS = 6000
local HTTP_TIMEOUT_MS = 12000
local FX_HTTP_TIMEOUT_MS = 25000
local FX_REFRESH_MS = 30 * 60 * 1000
local FX_FALLBACK_USD_CNY = 7.20
local FX_FALLBACK_USD_TWD = 32.50
local FX_URL = "https://open.er-api.com/v6/latest/USD"
local FX_HISTORY_URL = "https://api.frankfurter.dev/v2/rates"
local TROY_OUNCE_GRAMS = 31.1034768
local POUND_GRAMS = 453.59237

local CURRENCIES = {
  { value = "USD", text = "美金" },
  { value = "CNY", text = "人民币" },
  { value = "TWD", text = "新台币" },
}

local INTERVALS = {
  { label = "5m", api_binance = "5m", api_yahoo = "5m", range_yahoo = "5d", klt_em = "5", em_span = "month", fx_days = 7, fx_label = "7D" },
  { label = "1h", api_binance = "1h", api_yahoo = "60m", range_yahoo = "1mo", klt_em = "60", em_span = "year", fx_days = 30, fx_label = "30D" },
  { label = "1day", api_binance = "1d", api_yahoo = "1d", range_yahoo = "6mo", klt_em = "101", em_span = "prev_year", fx_days = 90, fx_label = "90D" },
  { label = "7day", api_binance = "1w", api_yahoo = "1wk", range_yahoo = "5y", klt_em = "102", em_span = "three_year", fx_days = 365, fx_label = "1Y" },
}

-- 设备端菜单与 Web 使用同一组常用汇率币种。
local FX_CURRENCIES = {
  "CNY", "USD", "EUR", "JPY", "GBP", "HKD", "TWD", "KRW", "AUD", "CAD",
  "CHF", "SGD", "NZD", "THB", "INR", "AED", "MYR", "IDR", "PHP",
}

local PRESET_ASSETS = {
  { id = "fx:USDCNY", group = "fx", source = "fx", symbol = "USDCNY", base = "USD", quote = "CNY", text = "USD / CNY" },
  { id = "fx:EURCNY", group = "fx", source = "fx", symbol = "EURCNY", base = "EUR", quote = "CNY", text = "EUR / CNY" },
  { id = "fx:USDJPY", group = "fx", source = "fx", symbol = "USDJPY", base = "USD", quote = "JPY", text = "USD / JPY" },
  { id = "fx:EURUSD", group = "fx", source = "fx", symbol = "EURUSD", base = "EUR", quote = "USD", text = "EUR / USD" },
  { id = "crypto:BTCUSDT", group = "crypto", source = "binance", symbol = "BTCUSDT", text = "BTC / USDT", quote = "USD" },
  { id = "crypto:ETHUSDT", group = "crypto", source = "binance", symbol = "ETHUSDT", text = "ETH / USDT", quote = "USD" },
  { id = "crypto:SOLUSDT", group = "crypto", source = "binance", symbol = "SOLUSDT", text = "SOL / USDT", quote = "USD" },
  { id = "crypto:BNBUSDT", group = "crypto", source = "binance", symbol = "BNBUSDT", text = "BNB / USDT", quote = "USD" },
  { id = "crypto:XRPUSDT", group = "crypto", source = "binance", symbol = "XRPUSDT", text = "XRP / USDT", quote = "USD" },
  { id = "crypto:DOGEUSDT", group = "crypto", source = "binance", symbol = "DOGEUSDT", text = "DOGE / USDT", quote = "USD" },
  { id = "crypto:ADAUSDT", group = "crypto", source = "binance", symbol = "ADAUSDT", text = "ADA / USDT", quote = "USD" },
  { id = "crypto:AVAXUSDT", group = "crypto", source = "binance", symbol = "AVAXUSDT", text = "AVAX / USDT", quote = "USD" },
  { id = "nasdaq:100.NDX", group = "nasdaq", source = "eastmoney", symbol = "NDX", secid = "100.NDX", text = "纳斯达克", quote = "USD" },
  { id = "nasdaq:100.NDX100", group = "nasdaq", source = "eastmoney", symbol = "NDX100", secid = "100.NDX100", text = "纳斯达克100", quote = "USD" },
  { id = "nasdaq:105.AAPL", group = "nasdaq", source = "eastmoney", symbol = "AAPL", secid = "105.AAPL", text = "Apple", quote = "USD" },
  { id = "nasdaq:105.MSFT", group = "nasdaq", source = "eastmoney", symbol = "MSFT", secid = "105.MSFT", text = "Microsoft", quote = "USD" },
  { id = "nasdaq:105.NVDA", group = "nasdaq", source = "eastmoney", symbol = "NVDA", secid = "105.NVDA", text = "NVIDIA", quote = "USD" },
  { id = "metal:101.GC00Y", group = "metal", source = "eastmoney", symbol = "GC00Y", secid = "101.GC00Y", text = "COMEX黄金", quote = "USD", metal_unit = "oz" },
  { id = "metal:101.SI00Y", group = "metal", source = "eastmoney", symbol = "SI00Y", secid = "101.SI00Y", text = "COMEX白银", quote = "USD", metal_unit = "oz" },
  { id = "metal:101.HG00Y", group = "metal", source = "eastmoney", symbol = "HG00Y", secid = "101.HG00Y", text = "COMEX铜", quote = "USD", metal_unit = "lb" },
  { id = "ashare:1.000001", group = "ashare", source = "eastmoney", symbol = "000001", secid = "1.000001", text = "上证指数", quote = "CNY" },
  { id = "ashare:1.000300", group = "ashare", source = "eastmoney", symbol = "000300", secid = "1.000300", text = "沪深300", quote = "CNY" },
  { id = "ashare:1.000905", group = "ashare", source = "eastmoney", symbol = "000905", secid = "1.000905", text = "中证500", quote = "CNY" },
  { id = "ashare:1.000852", group = "ashare", source = "eastmoney", symbol = "000852", secid = "1.000852", text = "中证1000", quote = "CNY" },
  { id = "ashare:0.399001", group = "ashare", source = "eastmoney", symbol = "399001", secid = "0.399001", text = "深证成指", quote = "CNY" },
  { id = "ashare:0.399006", group = "ashare", source = "eastmoney", symbol = "399006", secid = "0.399006", text = "创业板指", quote = "CNY" },
  { id = "ashare:1.600519", group = "ashare", source = "eastmoney", symbol = "600519", secid = "1.600519", text = "贵州茅台", quote = "CNY" },
  { id = "ashare:0.000001", group = "ashare", source = "eastmoney", symbol = "000001", secid = "0.000001", text = "平安银行", quote = "CNY" },
  { id = "ashare:0.300750", group = "ashare", source = "eastmoney", symbol = "300750", secid = "0.300750", text = "宁德时代", quote = "CNY" },
  { id = "taiwan:^TWII", group = "taiwan", source = "eastmoney", symbol = "^TWII", secid = "100.TWII", text = "台湾加权指数", quote = "TWD" },
  { id = "taiwan:2330.TW", group = "taiwan", source = "eastmoney", symbol = "2330.TW", secid = "178.2330", text = "台积电", quote = "TWD" },
  { id = "taiwan:2317.TW", group = "taiwan", source = "eastmoney", symbol = "2317.TW", secid = "178.2317", text = "鸿海", quote = "TWD" },
  { id = "taiwan:2454.TW", group = "taiwan", source = "eastmoney", symbol = "2454.TW", secid = "178.2454", text = "联发科", quote = "TWD" },
  { id = "taiwan:2308.TW", group = "taiwan", source = "eastmoney", symbol = "2308.TW", secid = "178.2308", text = "台达电", quote = "TWD" },
  { id = "taiwan:2881.TW", group = "taiwan", source = "eastmoney", symbol = "2881.TW", secid = "178.2881", text = "富邦金", quote = "TWD" },
  { id = "taiwan:6488.TWO", group = "taiwan", source = "eastmoney", symbol = "6488.TWO", secid = "178.6488", text = "环球晶", quote = "TWD" },
}

-- 返回单调毫秒时间，用于刷新队列和按键节流。
local function now_ms()
  if millis then
    local ok, value = pcall(millis)
    if ok and type(value) == "number" then
      return value
    end
  end
  if tmr and tmr.now then
    local ok, value = pcall(function() return tmr.now() end)
    if ok and type(value) == "number" then
      return math.floor(value / 1000)
    end
  end
  if tmr and tmr.time then
    local ok, value = pcall(function() return tmr.time() end)
    if ok and type(value) == "number" then
      return value * 1000
    end
  end
  return 0
end

-- 格式化当前时间，设备未同步时也能给出可读占位。
local function clock_text()
  if time and time.getlocal then
    local ok, t = pcall(function() return time.getlocal() end)
    if ok and type(t) == "table" and t.hour then
      return string.format("%02d:%02d:%02d", t.hour or 0, t.min or 0, t.sec or 0)
    end
  end
  if time and time.get and time.epoch2cal then
    local ok, sec = pcall(function() return time.get() end)
    if ok and type(sec) == "number" then
      local ok_cal, t = pcall(function() return time.epoch2cal(sec) end)
      if ok_cal and type(t) == "table" and t.hour then
        return string.format("%02d:%02d:%02d", t.hour or 0, t.min or 0, t.sec or 0)
      end
    end
  end
  if os and os.date then
    local ok, t = pcall(os.date, "*t")
    if ok and type(t) == "table" and t.hour then
      return string.format("%02d:%02d:%02d", t.hour or 0, t.min or 0, t.sec or 0)
    end
  end
  local s = math.floor(now_ms() / 1000)
  return string.format("%02d:%02d:%02d", math.floor((s / 3600) % 24), math.floor((s / 60) % 60), s % 60)
end

-- 返回本地日期，东方财富 beg 用它限制返回体大小，避免 JSON/字符串处理爆内存。
local function local_date_parts()
  local year = 2026
  local month = 6
  local day = 1
  if time and time.getlocal then
    local ok, t = pcall(function() return time.getlocal() end)
    if ok and type(t) == "table" then
      year = tonumber(t.year or t.y or t[1]) or year
      month = tonumber(t.mon or t.month or t[2]) or month
      day = tonumber(t.day or t.mday or t[3]) or day
      if year < 100 then
        year = year + 2000
      end
    end
  end
  if year < 2024 or year > 2100 then year = 2026 end
  if month < 1 or month > 12 then month = 6 end
  if day < 1 or day > 31 then day = 1 end
  return year, month, day
end

local function days_in_month(year, month)
  if month == 2 then
    local leap = (year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0
    return leap and 29 or 28
  end
  if month == 4 or month == 6 or month == 9 or month == 11 then
    return 30
  end
  return 31
end

-- 嵌入式 Lua 不保证提供 os.time；直接按日回退生成历史查询起始日期。
local function date_days_ago(days)
  local year, month, day = local_date_parts()
  days = math.max(0, math.floor(tonumber(days) or 0))
  while days > 0 do
    if day > 1 then
      local step = math.min(days, day - 1)
      day = day - step
      days = days - step
    else
      month = month - 1
      if month < 1 then
        month = 12
        year = year - 1
      end
      day = days_in_month(year, month)
      days = days - 1
    end
  end
  return string.format("%04d-%02d-%02d", year, month, day)
end

local function local_date_text()
  local year, month, day = local_date_parts()
  return string.format("%04d-%02d-%02d", year, month, day)
end

-- 东方财富日线如果 beg=0 会返回几十万字节历史数据，设备 JSON 解码会 NoMemory。
local function eastmoney_begin(interval)
  local year, month = local_date_parts()
  local span = interval and interval.em_span or "year"
  if span == "month" then
    return string.format("%04d%02d01", year, month)
  elseif span == "prev_year" then
    return string.format("%04d0101", year - 1)
  elseif span == "three_year" then
    return string.format("%04d0101", year - 3)
  end
  return string.format("%04d0101", year)
end

-- 去掉首尾空白，避免 Web 传入的自定义代码带空格。
local function trim(text)
  return tostring(text or ""):match("^%s*(.-)%s*$") or ""
end

-- 对 URL 路径/参数做最小编码，支持 Yahoo 的 ^IXIC、GC=F 等符号。
local function url_encode(text)
  text = tostring(text or "")
  return text:gsub("([^%w%-%_%.%~])", function(ch)
    return string.format("%%%02X", string.byte(ch))
  end)
end

-- 安全截断文本，屏幕端和 Web 状态都复用。
local function short_text(text, limit)
  text = tostring(text or ""):gsub("[\r\n]+", " ")
  limit = tonumber(limit) or 40
  if #text <= limit then
    return text
  end
  if limit <= 3 then
    return text:sub(1, limit)
  end
  return text:sub(1, limit - 3) .. "..."
end

-- 价格数值统一保留 2 位小数。
local function fmt_price(value)
  value = tonumber(value)
  if not value then
    return "--"
  end
  return string.format("%.2f", value)
end

-- 汇率需要保留足够的小数位，避免 JPY/USD 等小汇率被四舍五入成 0.01。
local function fmt_rate(value)
  value = tonumber(value)
  if not value then
    return "--"
  end
  local text
  if math.abs(value) >= 100 then
    text = string.format("%.3f", value)
  elseif math.abs(value) >= 1 then
    text = string.format("%.4f", value)
  else
    text = string.format("%.6f", value)
  end
  return text:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
end

-- 带正负号的涨跌额格式化，统一保留 2 位小数。
local function fmt_signed(value)
  value = tonumber(value)
  if not value then
    return "--"
  end
  return string.format("%+.2f", value)
end

-- 百分比格式化。
local function fmt_pct(value)
  value = tonumber(value)
  if not value then
    return "--%"
  end
  return string.format("%+.2f%%", value)
end

-- 找到周期配置。
local function find_interval(label)
  for i = 1, #INTERVALS do
    if INTERVALS[i].label == label then
      return INTERVALS[i], i
    end
  end
  return INTERVALS[1], 1
end

-- 归一化图表模式，兼容 Web/按键传入的简写。
local function normalize_mode(mode)
  mode = tostring(mode or "")
  if mode == "candle" or mode == "kline" or mode == "k" then
    return "candle"
  elseif mode == "line" then
    return "line"
  end
  return nil
end

-- 归一化均线周期，0 表示不显示，当前只开放 MA10/MA20。
local function normalize_ma_period(value)
  local text = tostring(value or ""):lower()
  if text == "" or text == "0" or text == "off" or text == "none" then
    return 0
  end
  local period = tonumber(text:match("ma(%d+)") or text)
  if period == 10 or period == 20 then
    return period
  end
  return nil
end

-- 屏幕和 Web 复用的短模式名。
local function mode_text(mode)
  if normalize_mode(mode) == "candle" then
    return "K"
  end
  return "Line"
end

-- 归一化显示币种，Web 可以传 CNY/RMB/人民币。
local function normalize_currency(value)
  local text = tostring(value or ""):upper()
  if text == "CNY" or text == "RMB" or tostring(value or "") == "人民币" then
    return "CNY"
  elseif text == "TWD" or text == "NTD" or text == "NT$" or tostring(value or "") == "新台币" then
    return "TWD"
  end
  return "USD"
end

-- 自定义汇率使用 ISO 4217 三字母代码，不限制为行情换算所用的三种币种。
local function normalize_currency_code(value)
  local code = trim(value):upper()
  if code:match("^[A-Z][A-Z][A-Z]$") then
    return code
  end
  return nil
end

local function normalize_bool(value, fallback)
  if type(value) == "boolean" then return value end
  if type(value) == "number" then return value ~= 0 end
  local text = trim(value):lower()
  if text == "1" or text == "true" or text == "on" or text == "yes" then return true end
  if text == "0" or text == "false" or text == "off" or text == "no" then return false end
  return fallback and true or false
end

local function currency_text(value)
  local code = normalize_currency_code(value)
  if code and code ~= "USD" and code ~= "CNY" and code ~= "TWD" then
    return code
  end
  local currency = normalize_currency(value)
  if currency == "CNY" then
    return "人民币"
  elseif currency == "TWD" then
    return "新台币"
  end
  return "美金"
end

-- 复制币种选项，避免 Web 快照污染常量表。
local function public_currencies()
  local out = {}
  for i = 1, #CURRENCIES do
    out[#out + 1] = {
      value = CURRENCIES[i].value,
      text = CURRENCIES[i].text,
    }
  end
  return out
end

-- 金银默认是美元/金衡盎司，铜默认是美元/磅，显示时统一换成每克。
local function infer_metal_unit(symbol)
  local text = tostring(symbol or ""):upper()
  if text:find("HG", 1, true) or text:find("CU", 1, true) then
    return "lb"
  end
  return "oz"
end

local function metal_unit(asset)
  if asset and asset.metal_unit then
    return asset.metal_unit
  end
  return infer_metal_unit(asset and asset.symbol or "")
end

local function unit_text(asset)
  if asset and asset.group == "metal" then
    return "/g"
  end
  return ""
end

local function convert_currency(value, from_currency, to_currency, usd_cny, usd_twd)
  value = tonumber(value)
  if not value then
    return nil
  end
  from_currency = normalize_currency(from_currency)
  to_currency = normalize_currency(to_currency)
  usd_cny = tonumber(usd_cny) or FX_FALLBACK_USD_CNY
  usd_twd = tonumber(usd_twd) or FX_FALLBACK_USD_TWD
  if from_currency == to_currency then
    return value
  end

  local usd_value = value
  if from_currency == "CNY" and usd_cny ~= 0 then
    usd_value = value / usd_cny
  elseif from_currency == "TWD" and usd_twd ~= 0 then
    usd_value = value / usd_twd
  end

  if to_currency == "CNY" then
    return usd_value * usd_cny
  elseif to_currency == "TWD" then
    return usd_value * usd_twd
  end
  return usd_value
end

-- 把源价格转换为屏幕/Web 当前显示价格。
local function display_price(asset, value, target_currency, usd_cny, usd_twd)
  local v = tonumber(value)
  if not v then
    return nil
  end

  if asset and asset.group == "fx" then
    return v
  end

  local base_currency = asset and asset.quote or "USD"
  if asset and asset.group == "metal" then
    if metal_unit(asset) == "lb" then
      v = v / POUND_GRAMS
    else
      v = v / TROY_OUNCE_GRAMS
    end
    base_currency = "USD"
  end

  return convert_currency(v, base_currency, target_currency, usd_cny, usd_twd)
end

-- 复制资产字段，避免 Web 修改快照时污染运行状态。
local function public_asset(asset)
  if not asset then
    return nil
  end
  return {
    id = asset.id,
    group = asset.group,
    source = asset.source,
    symbol = asset.symbol,
    secid = asset.secid,
    text = asset.text,
    quote = asset.quote,
    base = asset.base,
    metal_unit = asset.metal_unit,
  }
end

-- 返回响应头字段，兼容大小写差异。
local function header_value(headers, key)
  if type(headers) ~= "table" then
    return nil
  end
  return headers[key] or headers[key:lower()] or headers[key:upper()]
end

-- 必要时解 gzip，保持公开接口返回体解析稳定。
local function maybe_decompress(body, headers)
  if type(body) ~= "string" then
    return body, nil
  end
  local enc = header_value(headers, "content-encoding")
  if type(enc) ~= "string" or not enc:find("gzip", 1, true) then
    return body, nil
  end
  if not zlib or not zlib.isgzip or not zlib.gunzip then
    return nil, "gzip no zlib"
  end
  if not zlib.isgzip(body) then
    return nil, "gzip bad body"
  end
  local plain, err = zlib.gunzip(body)
  if not plain then
    return nil, err or "gunzip failed"
  end
  return plain, nil
end

-- JSON 解码封装，统一错误文本。
local function decode_json(raw)
  if not JSON or not JSON.decode then
    return nil, "json missing"
  end
  local ok, doc, err = pcall(function()
    return JSON.decode(raw)
  end)
  if not ok then
    return nil, tostring(doc)
  end
  if not doc then
    return nil, tostring(err or "json decode failed")
  end
  return doc, nil
end

-- JSON 编码封装，保存设置失败时只记录错误，不影响行情刷新。
local function encode_json(value)
  if not JSON or not JSON.encode then
    return nil, "json missing"
  end
  local ok, raw, err = pcall(function()
    return JSON.encode(value)
  end)
  if not ok then
    return nil, tostring(raw)
  end
  if type(raw) ~= "string" then
    return nil, tostring(err or "json encode failed")
  end
  return raw, nil
end

-- 从配置文件恢复自定义资产，只接受 app 自己会生成的字段。
local function restore_custom_asset(value)
  if type(value) ~= "table" then
    return nil
  end
  local id = tostring(value.id or "")
  local source = tostring(value.source or "")
  local symbol = tostring(value.symbol or "")
  if id == "" or source == "" or symbol == "" then
    return nil
  end
  if source ~= "binance" and source ~= "yahoo" and source ~= "eastmoney" and source ~= "twse" and source ~= "fx" then
    return nil
  end

  local group = tostring(value.group or "")
  if group ~= "crypto" and group ~= "nasdaq" and group ~= "metal" and group ~= "ashare" and group ~= "taiwan" and group ~= "fx" then
    group = "crypto"
  end

  local base = nil
  local quote = nil
  if source == "fx" then
    base = normalize_currency_code(value.base)
    quote = normalize_currency_code(value.quote)
    if not base or not quote or base == quote then
      return nil
    end
    group = "fx"
    symbol = base .. quote
    id = "custom:fx:" .. symbol
  end

  local migrated_secid = nil
  if group == "taiwan" then
    symbol = symbol:upper()
    local code = symbol:gsub("%.TWO$", ""):gsub("%.TW$", "")
    migrated_secid = symbol == "^TWII" and "100.TWII" or ("178." .. code)
    source = "eastmoney"
    id = "custom:eastmoney:" .. symbol
  end

  local asset = {
    id = id,
    group = group,
    source = source,
    symbol = symbol,
    text = tostring(value.text or symbol),
    quote = quote or normalize_currency(value.quote or (group == "ashare" and "CNY" or (group == "taiwan" and "TWD" or "USD"))),
    base = base,
  }
  if migrated_secid or value.secid then
    asset.secid = migrated_secid or tostring(value.secid)
  end
  local unit = tostring(value.metal_unit or "")
  if unit == "oz" or unit == "lb" then
    asset.metal_unit = unit
  end
  return asset
end

-- 解析 open.er-api.com 的 USD -> CNY/TWD 汇率。
local function parse_fx_rates(doc)
  local rates = type(doc) == "table" and doc.rates
  local cny = rates and tonumber(rates.CNY)
  local twd = rates and tonumber(rates.TWD)
  if cny and cny > 0 and cny < 20 and twd and twd > 10 and twd < 100 then
    return cny, twd, nil
  end
  return nil, nil, "fx CNY/TWD missing"
end

-- 解析任意货币对的每日历史汇率，并均匀压缩为屏幕可绘制的点数。
local function parse_fx_pair(doc, asset)
  if type(doc) ~= "table" then
    return nil, "fx history missing"
  end
  local quote = asset and normalize_currency_code(asset.quote)
  local raw = {}
  for i = 1, #doc do
    local row = doc[i]
    local rate = type(row) == "table" and tonumber(row.rate)
    local row_quote = type(row) == "table" and normalize_currency_code(row.quote)
    if rate and rate > 0 and row_quote == quote then
      raw[#raw + 1] = {
        time = tostring(row.date or clock_text()),
        open = rate,
        high = rate,
        low = rate,
        close = rate,
      }
    end
  end

  if #raw == 0 then
    return nil, "fx rate missing: " .. tostring(quote or "?")
  end

  local candles = raw
  if #raw > DEFAULT_LIMIT then
    candles = {}
    local last_index = 0
    for i = 0, DEFAULT_LIMIT - 1 do
      local index = math.floor(i * (#raw - 1) / (DEFAULT_LIMIT - 1)) + 1
      if index ~= last_index then
        candles[#candles + 1] = raw[index]
        last_index = index
      end
    end
  end

  local closes = {}
  local min_rate = nil
  local max_rate = nil
  for i = 1, #candles do
    local rate = candles[i].close
    closes[#closes + 1] = rate
    min_rate = not min_rate and rate or math.min(min_rate, rate)
    max_rate = not max_rate and rate or math.max(max_rate, rate)
  end
  local current = closes[#closes]
  local previous = closes[#closes - 1] or current
  return {
    current_price = current,
    prev_close = previous,
    first_price = closes[1],
    candles = candles,
    closes = closes,
    min_price = min_rate,
    max_price = max_rate,
    currency = quote,
    live_source = "Frankfurter daily FX",
  }, nil
end

-- 简单 CSV 行拆分，东方财富 K 线字段不含引号。
local function split_csv(line)
  local out = {}
  for item in tostring(line or ""):gmatch("([^,]+)") do
    out[#out + 1] = item
  end
  return out
end

-- 将不同来源的时间统一为毫秒数，图表据此保留休市和缺口的真实间距。
local function chart_time_value(value)
  local numeric = tonumber(value)
  if numeric then
    return numeric
  end
  local y, m, d, hh, mm = tostring(value or ""):match(
    "^(%d%d%d%d)%-(%d%d)%-(%d%d)%s*(%d?%d?):?(%d?%d?)"
  )
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if not y or not m or not d then
    return nil
  end
  hh = tonumber(hh) or 0
  mm = tonumber(mm) or 0
  y = y - (m <= 2 and 1 or 0)
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local mp = m + (m > 2 and -3 or 9)
  local doy = math.floor((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  local days = era * 146097 + doe - 719468
  -- Keep date-derived values in seconds.  The device Lua runtime stores integers
  -- as signed 32-bit values, so Unix milliseconds overflow and can make the
  -- chart X axis run backwards.  Ratios only need a monotonic time value.
  return days * 86400 + hh * 3600 + mm * 60
end

-- 统计 K 线范围和收盘序列。
local function summarize(candles, parsed)
  if #candles < 1 then
    return nil, "points<1"
  end

  local closes = {}
  local minp = nil
  local maxp = nil
  for i = 1, #candles do
    local c = candles[i]
    closes[#closes + 1] = c.close
    local lo = tonumber(c.low) or tonumber(c.close)
    local hi = tonumber(c.high) or tonumber(c.close)
    if lo and (not minp or lo < minp) then
      minp = lo
    end
    if hi and (not maxp or hi > maxp) then
      maxp = hi
    end
  end

  parsed.candles = candles
  parsed.closes = closes
  parsed.min_price = minp
  parsed.max_price = maxp
  parsed.first_price = closes[1]
  parsed.current_price = parsed.current_price or closes[#closes]
  return parsed, nil
end

-- 解析 Binance kline 数组。
local function parse_binance(doc, asset)
  if type(doc) ~= "table" then
    return nil, "json type"
  end
  local candles = {}
  for _, row in ipairs(doc) do
    if type(row) == "table" then
      local open_p = tonumber(row[2])
      local high_p = tonumber(row[3])
      local low_p = tonumber(row[4])
      local close_p = tonumber(row[5])
      if open_p and high_p and low_p and close_p then
        candles[#candles + 1] = {
          time = tonumber(row[1]) or 0,
          open = open_p,
          high = high_p,
          low = low_p,
          close = close_p,
        }
      end
    end
  end
  return summarize(candles, { currency = asset.quote or "USD" })
end

-- Binance K 线不包含 24 小时涨跌基准；单独读取官方 24hr ticker。
local function build_binance_quote_url(asset)
  return "https://data-api.binance.vision/api/v3/ticker/24hr?symbol="
    .. url_encode(asset.symbol)
end

local function parse_binance_quote(doc)
  if type(doc) ~= "table" then
    return nil, "binance quote empty"
  end
  local current = tonumber(doc.lastPrice)
  local prev = tonumber(doc.openPrice)
  if not current or not prev or prev == 0 then
    return nil, "binance quote price missing"
  end
  return {
    current_price = current,
    prev_close = prev,
    live_source = "Binance 24h",
  }, nil
end

-- 解析 Yahoo chart 结构，覆盖纳指、美股和金银铜。
local function parse_yahoo(doc, asset)
  local chart = type(doc) == "table" and doc.chart
  local result = chart and chart.result and chart.result[1]
  if type(result) ~= "table" and type(doc) == "table" and type(doc.data) == "table"
      and type(doc.data[1]) == "table" then
    result = doc.data[1].chart
  end
  if type(result) ~= "table" then
    return nil, "chart empty"
  end

  local meta = result.meta or {}
  local quote = result.indicators and result.indicators.quote and result.indicators.quote[1]
  local ts = result.timestamp
  if type(quote) ~= "table" or type(ts) ~= "table" then
    return nil, "quote empty"
  end

  local opens = quote.open or {}
  local highs = quote.high or {}
  local lows = quote.low or {}
  local closes = quote.close or {}
  local candles = {}
  for i = 1, #ts do
    local close_p = tonumber(closes[i])
    if close_p then
      local open_p = tonumber(opens[i]) or close_p
      local high_p = tonumber(highs[i]) or math.max(open_p, close_p)
      local low_p = tonumber(lows[i]) or math.min(open_p, close_p)
      candles[#candles + 1] = {
        time = (tonumber(ts[i]) or 0) * 1000,
        open = open_p,
        high = high_p,
        low = low_p,
        close = close_p,
      }
    end
  end

  return summarize(candles, {
    currency = meta.currency or asset.quote or "",
    prev_close = tonumber(meta.chartPreviousClose) or tonumber(meta.previousClose),
    current_price = tonumber(meta.regularMarketPrice),
  })
end

-- 解析东方财富 K 线，覆盖 A 股个股和指数。
local function parse_eastmoney(doc, asset)
  if type(doc) == "string" then
    local block = doc:match('"klines"%s*:%s*%[(.-)%]')
    if not block then
      return nil, "kline empty"
    end

    local lines = {}
    for line in block:gmatch('"([^"]+)"') do
      local fields = split_csv(line)
      local volume = tonumber(fields[6]) or 0
      -- Eastmoney 会为台湾市场补齐大量零成交量、价格不变的时间格；
      -- 先丢弃这些占位行，否则最后 64 点几乎全是水平线。
      if asset.group ~= "taiwan" or volume > 0 then
        lines[#lines + 1] = line
        if #lines > DEFAULT_LIMIT then
          table.remove(lines, 1)
        end
      end
    end

    local candles = {}
    for _, line in ipairs(lines) do
      local fields = split_csv(line)
      local open_p = tonumber(fields[2])
      local close_p = tonumber(fields[3])
      local high_p = tonumber(fields[4])
      local low_p = tonumber(fields[5])
      if open_p and close_p and high_p and low_p then
        candles[#candles + 1] = {
          time = fields[1] or "",
          open = open_p,
          high = high_p,
          low = low_p,
          close = close_p,
        }
      end
    end

    local prev_close = tonumber(doc:match('"preKPrice"%s*:%s*"?([%-%d%.]+)"?'))
    if asset.group == "taiwan" and #candles > 1 then
      prev_close = candles[#candles - 1].close
    end
    return summarize(candles, {
      currency = asset.quote or "CNY",
      prev_close = prev_close,
      name = doc:match('"name"%s*:%s*"([^"]*)"'),
    })
  end

  local data = type(doc) == "table" and doc.data
  if type(data) ~= "table" or type(data.klines) ~= "table" then
    return nil, "kline empty"
  end

  local candles = {}
  for _, line in ipairs(data.klines) do
    local fields = split_csv(line)
    local open_p = tonumber(fields[2])
    local close_p = tonumber(fields[3])
    local high_p = tonumber(fields[4])
    local low_p = tonumber(fields[5])
    local volume = tonumber(fields[6]) or 0
    if open_p and close_p and high_p and low_p and (asset.group ~= "taiwan" or volume > 0) then
      candles[#candles + 1] = {
        time = fields[1] or "",
        open = open_p,
        high = high_p,
        low = low_p,
        close = close_p,
      }
    end
  end

  local prev_close = tonumber(data.preKPrice)
  if asset.group == "taiwan" and #candles > 1 then
    prev_close = candles[#candles - 1].close
  end
  return summarize(candles, {
    currency = asset.quote or "CNY",
    prev_close = prev_close,
    name = data.name,
  })
end

-- TWSE MIS 的台股代码：上市 tse_CODE.tw、上柜 otc_CODE.tw、加权指数 tse_t00.tw。
local function twse_channel(asset)
  local symbol = tostring(asset and asset.symbol or ""):upper()
  if symbol == "^TWII" then
    return "tse_t00.tw"
  end
  local code = symbol:gsub("%.TWO$", ""):gsub("%.TW$", "")
  if code == "" then
    return nil
  end
  return (symbol:match("%.TWO$") and "otc_" or "tse_") .. code .. ".tw"
end

local function build_twse_quote_url(asset)
  local channel = twse_channel(asset)
  if not channel then
    return nil, "twse channel missing"
  end
  return "https://mis.twse.com.tw/stock/api/getStockInfo.jsp?ex_ch="
    .. url_encode(channel)
    .. "&json=1&delay=0"
end

local function positive_number(value)
  local n = tonumber(value)
  if n and n > 0 then
    return n
  end
  return nil
end

-- 解析 TWSE MIS 即时快照。z 是最新成交价，y 是昨收，o/h/l 是当日开高低。
local function parse_twse_quote(doc)
  local rows = type(doc) == "table" and doc.msgArray
  local row = type(rows) == "table" and rows[1]
  if type(row) ~= "table" then
    return nil, "twse quote empty"
  end

  local current = positive_number(row.z) or positive_number(row.pz) or positive_number(row.y)
  local prev_close = positive_number(row.y)
  if not current or not prev_close then
    return nil, "twse price missing"
  end

  local date = tostring(row.d or row["^"] or ""):gsub("[^%d]", "")
  local quote_time = tostring(row.t or row["%"] or "")
  if #date ~= 8 then
    return nil, "twse date missing"
  end

  return {
    current_price = current,
    prev_close = prev_close,
    open = positive_number(row.o) or current,
    high = positive_number(row.h) or current,
    low = positive_number(row.l) or current,
    date = date,
    time = quote_time,
    timestamp = tonumber(row.tlong),
    volume = tonumber(row.v) or 0,
    name = tostring(row.n or ""),
  }, nil
end

-- Eastmoney K 线里的 preKPrice 是请求区间前一根 K 线，并非昨收。
-- f43/f60 分别是实时价和昨收，f59 是价格小数位。
local function build_eastmoney_quote_url(asset)
  return "https://push2.eastmoney.com/api/qt/stock/get?secid="
    .. url_encode(asset.secid or asset.symbol)
    .. "&fields=f43,f44,f45,f46,f57,f58,f59,f60,f169,f170"
end

local function eastmoney_quote_field(doc, key)
  if type(doc) == "table" then
    local data = doc.data
    return type(data) == "table" and data[key] or nil
  end
  if type(doc) == "string" then
    return doc:match('"' .. key .. '"%s*:%s*"?([%-%d%.]+)"?')
  end
  return nil
end

local function parse_eastmoney_quote(doc)
  local decimals = tonumber(eastmoney_quote_field(doc, "f59")) or 2
  if decimals < 0 or decimals > 8 then
    decimals = 2
  end
  local scale = 10 ^ decimals
  local function price(key)
    local n = tonumber(eastmoney_quote_field(doc, key))
    if not n or n <= 0 then
      return nil
    end
    return n / scale
  end
  local current = price("f43")
  local prev = price("f60")
  if not current or not prev then
    return nil, "eastmoney quote price missing"
  end
  return {
    current_price = current,
    prev_close = prev,
    open = price("f46"),
    high = price("f44"),
    low = price("f45"),
    live_source = "Eastmoney quote",
  }, nil
end

-- 按来源构建公开接口 URL。
local function build_url(asset, interval)
  if asset.source == "binance" then
    return "https://data-api.binance.vision/api/v3/klines?symbol="
      .. url_encode(asset.symbol)
      .. "&interval=" .. interval.api_binance
      .. "&limit=" .. tostring(DEFAULT_LIMIT)
  elseif asset.source == "yahoo" then
    return "https://query2.finance.yahoo.com/v8/finance/chart/"
      .. url_encode(asset.symbol)
      .. "?range=" .. interval.range_yahoo
      .. "&interval=" .. interval.api_yahoo
      .. "&includePrePost=false"
  elseif asset.source == "eastmoney" then
    return "https://push2his.eastmoney.com/api/qt/stock/kline/get?secid="
      .. url_encode(asset.secid or asset.symbol)
      .. "&fields1=f1,f2,f3,f4,f5,f6"
      .. "&fields2=f51,f52,f53,f54,f55,f56,f57,f58"
      .. "&klt=" .. interval.klt_em
      .. "&fqt=1&beg=" .. eastmoney_begin(interval) .. "&end=20500101&lmt=" .. tostring(DEFAULT_LIMIT)
  elseif asset.source == "fx" then
    local base = normalize_currency_code(asset.base)
    local quote = normalize_currency_code(asset.quote)
    if not base or not quote then
      return nil, "bad currency pair"
    end
    return FX_HISTORY_URL
      .. "?from=" .. date_days_ago(interval.fx_days or 30)
      .. "&to=" .. local_date_text()
      .. "&base=" .. url_encode(base)
      .. "&quotes=" .. url_encode(quote)
  end
  return nil, "source unsupported"
end

-- 按来源选择解析器。
local function parse_by_source(asset, doc)
  if asset.source == "binance" then
    return parse_binance(doc, asset)
  elseif asset.source == "yahoo" then
    return parse_yahoo(doc, asset)
  elseif asset.source == "eastmoney" then
    return parse_eastmoney(doc, asset)
  elseif asset.source == "fx" then
    return parse_fx_pair(doc, asset)
  end
  return nil, "source unsupported"
end

-- 推断 A 股市场编号；Web 仍可显式覆盖。
local function infer_eastmoney_market(symbol)
  symbol = tostring(symbol or "")
  if symbol:sub(1, 1) == "6" or symbol:sub(1, 1) == "9" then
    return "1"
  end
  return "0"
end

-- Eastmoney 的 market 前缀同时覆盖 A 股、海外指数/股票和国际期货。
local function normalize_eastmoney_market(market, symbol)
  market = trim(market)
  if market == "0" or market == "1" or market == "100" or market == "101" or market == "105" or market == "178" then
    return market
  end
  return infer_eastmoney_market(symbol)
end

-- 根据 Eastmoney market 前缀决定 Web 分类和显示币种。
local function eastmoney_meta(market)
  if market == "178" then
    return "taiwan", "TWD"
  end
  if market == "100" or market == "105" then
    return "nasdaq", "USD"
  elseif market == "101" then
    return "metal", "USD"
  end
  return "ashare", "CNY"
end

-- 创建 Web 输入的自定义资产。
local function make_custom_asset(params)
  local source = trim(params.source)
  local symbol = trim(params.symbol)
  if source == "" then
    return nil, "source required"
  end

  if source == "fx" then
    local base = normalize_currency_code(params.base_currency or params.base)
    local quote = normalize_currency_code(params.quote_currency or params.quote)
    if not base or not quote then
      return nil, "currency code must be 3 letters"
    end
    if base == quote then
      return nil, "base and quote currencies must differ"
    end
    local pair = base .. quote
    return {
      id = "custom:fx:" .. pair,
      group = "fx",
      source = "fx",
      symbol = pair,
      base = base,
      quote = quote,
      text = base .. " / " .. quote,
    }
  end

  if symbol == "" then
    return nil, "symbol required"
  end

  local text = trim(params.name)
  if text == "" then
    text = symbol
  end

  if source == "binance" then
    symbol = symbol:upper()
    return {
      id = "custom:binance:" .. symbol,
      group = "crypto",
      source = "binance",
      symbol = symbol,
      text = text,
      quote = "USD",
    }
  elseif source == "yahoo" or source == "twse" then
    symbol = symbol:upper()
    local is_taiwan = params.group == "taiwan"
      or symbol:match("%.TW$") ~= nil
      or symbol:match("%.TWO$") ~= nil
      or symbol == "^TWII"
    local group = is_taiwan and "taiwan" or (params.group == "metal" and "metal" or "nasdaq")
    local taiwan_code = symbol:gsub("%.TWO$", ""):gsub("%.TW$", "")
    local taiwan_secid = symbol == "^TWII" and "100.TWII" or ("178." .. taiwan_code)
    return {
      id = "custom:" .. (is_taiwan and "eastmoney" or "yahoo") .. ":" .. symbol,
      group = group,
      source = is_taiwan and "eastmoney" or "yahoo",
      symbol = symbol,
      text = text,
      quote = is_taiwan and "TWD" or "USD",
      secid = is_taiwan and taiwan_secid or nil,
      metal_unit = group == "metal" and infer_metal_unit(symbol) or nil,
    }
  elseif source == "eastmoney" then
    symbol = symbol:upper()
    local is_taiwan = params.group == "taiwan"
      or symbol:match("%.TW$") ~= nil
      or symbol:match("%.TWO$") ~= nil
      or symbol == "^TWII"
    if is_taiwan then
      local code = symbol:gsub("%.TWO$", ""):gsub("%.TW$", "")
      local secid = symbol == "^TWII" and "100.TWII" or ("178." .. code)
      return {
        id = "custom:eastmoney:" .. symbol,
        group = "taiwan",
        source = "eastmoney",
        symbol = symbol,
        secid = secid,
        text = text,
        quote = "TWD",
      }
    end
    local market = normalize_eastmoney_market(params.market, symbol)
    local group, quote = eastmoney_meta(market)
    local secid = market .. "." .. symbol
    return {
      id = "custom:eastmoney:" .. secid,
      group = group,
      source = "eastmoney",
      symbol = symbol,
      secid = secid,
      text = text,
      quote = quote,
      metal_unit = group == "metal" and infer_metal_unit(symbol) or nil,
    }
  end

  return nil, "source unsupported"
end

-- 构造 backend 实例。
function Backend.new(opts)
  opts = opts or {}
  local self = {
    version = opts.version or "dev",
    app_id = opts.app_id or "btc",
    config_path = opts.config_path or "/sd/apps/btc/settings.json",
    assets = PRESET_ASSETS,
    intervals = INTERVALS,
    settings = {
      asset_id = "crypto:BTCUSDT",
      interval = "5m",
      mode = "line",
      currency = "USD",
      ma_period = 0,
      tilt_enabled = true,
    },
    custom_asset = nil,
    intraday = {},
    state = {
      valid = false,
      loading = false,
      http_busy = false,
      http_job = "",
      http_req_id = 0,
      http_started_ms = 0,
      status = "cold",
      tone = "idle",
      last_error = "",
      last_http_code = 0,
      candles = {},
      closes = {},
      min_price = nil,
      max_price = nil,
      current_price = nil,
      prev_close = nil,
      change = nil,
      change_pct = nil,
      currency = "",
      live_source = "",
      fx_rate = FX_FALLBACK_USD_CNY,
      fx_twd_rate = FX_FALLBACK_USD_TWD,
      fx_updated_text = "--",
      fx_last_error = "",
      fx_next_fetch_at = 0,
      fx_loading = false,
      last_update_ms = 0,
      last_update_text = "--:--:--",
      next_fetch_at = 0,
      chart_dirty = true,
    },
  }

  -- 查找预设或自定义资产。
  function self:find_asset(id)
    if self.custom_asset and self.custom_asset.id == id then
      return self.custom_asset
    end
    for i = 1, #self.assets do
      if self.assets[i].id == id then
        return self.assets[i]
      end
    end
    return nil
  end

  -- 返回当前资产，配置异常时回到第一个预设。
  function self:current_asset()
    return self:find_asset(self.settings.asset_id) or self.assets[1]
  end

  -- 生成需要持久化的轻量配置，行情数据不写入 SD。
  function self:config_payload()
    return {
      asset_id = self.settings.asset_id,
      interval = self.settings.interval,
      mode = self.settings.mode,
      currency = self.settings.currency,
      ma_period = self.settings.ma_period,
      tilt_enabled = self.settings.tilt_enabled,
      custom_asset = public_asset(self.custom_asset),
    }
  end

  -- 从 app 自己目录读取上次设置；失败时安静回到默认配置。
  function self:load_settings()
    if not self.config_path or self.config_path == "" or not file or not file.getcontents then
      return false
    end
    local ok, raw = pcall(function()
      return file.getcontents(self.config_path)
    end)
    if not ok or type(raw) ~= "string" or raw == "" then
      return false
    end

    local cfg, err = decode_json(raw)
    if type(cfg) ~= "table" then
      print("[btc_backend] load settings failed: " .. tostring(err or "bad config"))
      return false
    end

    local custom = restore_custom_asset(cfg.custom_asset)
    if custom then
      self.custom_asset = custom
    end

    local asset_id = cfg.asset_id or cfg.asset
    if asset_id and self:find_asset(asset_id) then
      self.settings.asset_id = asset_id
    elseif custom and tostring(asset_id or ""):match("^custom:") then
      -- 旧版台股自定义项可能保存为 custom:yahoo:*；restore 后已经迁移成
      -- custom:eastmoney:*，同步更新选中 ID，避免重启后意外回退到 BTC。
      self.settings.asset_id = custom.id
    end
    if cfg.interval then
      local interval = find_interval(cfg.interval)
      if interval then
        self.settings.interval = interval.label
      end
    end
    if cfg.mode then
      local mode = normalize_mode(cfg.mode)
      if mode then
        self.settings.mode = mode
      end
    end
    if cfg.currency then
      self.settings.currency = normalize_currency(cfg.currency)
    end
    local ma_period = normalize_ma_period(cfg.ma_period or cfg.ma)
    if ma_period ~= nil then
      self.settings.ma_period = ma_period
    end
    if cfg.tilt_enabled ~= nil then
      self.settings.tilt_enabled = normalize_bool(cfg.tilt_enabled, true)
    end

    self.state.chart_dirty = true
    return true
  end

  -- 保存 Web 或实体按键改动后的配置。
  function self:save_settings()
    if not self.config_path or self.config_path == "" or not file or not file.putcontents then
      return false
    end
    local raw, err = encode_json(self:config_payload())
    if not raw then
      print("[btc_backend] save settings encode failed: " .. tostring(err))
      return false
    end
    local ok, ret = pcall(function()
      return file.putcontents(self.config_path, raw)
    end)
    if not ok or not ret then
      print("[btc_backend] save settings failed: " .. tostring(ok and ret or ret))
      return false
    end
    return true
  end

  -- 清空旧走势，切换资产或周期时调用。
  function self:clear_data(status)
    local s = self.state
    -- 快速翻页时让旧请求回调失效，避免上一标的的数据覆盖当前页面。
    s.http_req_id = (s.http_req_id or 0) + 1
    s.http_busy = false
    s.http_job = ""
    s.http_started_ms = 0
    s.valid = false
    s.status = status or "loading"
    s.tone = "warn"
    s.last_error = ""
    s.candles = {}
    s.closes = {}
    s.min_price = nil
    s.max_price = nil
    s.current_price = nil
    s.prev_close = nil
    s.change = nil
    s.change_pct = nil
    s.live_source = ""
    s.chart_dirty = true
  end

  -- 请求尽快刷新。
  function self:queue_refresh()
    self.state.next_fetch_at = 0
  end

  -- 标记图表已绘制。
  function self:clear_chart_dirty()
    self.state.chart_dirty = false
  end

  -- 应用解析后的统一行情数据。
  function self:apply_parsed(asset, parsed)
    local s = self.state
    local current = tonumber(parsed.current_price) or parsed.closes[#parsed.closes]
    local base = tonumber(parsed.prev_close) or tonumber(parsed.first_price) or current

    s.valid = true
    s.loading = false
    s.status = "ready"
    s.tone = current and base and current < base and "down" or "up"
    s.last_error = ""
    s.last_http_code = 200
    s.candles = parsed.candles or {}
    s.closes = parsed.closes or {}
    s.min_price = parsed.min_price
    s.max_price = parsed.max_price
    s.current_price = current
    s.prev_close = base
    s.change = current and base and (current - base) or nil
    if current and base and base ~= 0 then
      s.change_pct = (current - base) * 100 / base
    else
      s.change_pct = nil
    end
    s.currency = parsed.currency or asset.quote or ""
    s.live_source = parsed.live_source or asset.source or ""
    s.last_update_ms = now_ms()
    s.last_update_text = clock_text()
    s.next_fetch_at = now_ms() + MAIN_REFRESH_MS
    s.chart_dirty = true
  end

  -- 将实时价写入最新一根 K 线，同时保留该周期原有开高低。
  function self:merge_live_quote(asset, historical, quote)
    local candles = {}
    for i = 1, #(historical.candles or {}) do
      local c = historical.candles[i]
      candles[#candles + 1] = {
        time = c.time,
        open = c.open,
        high = c.high,
        low = c.low,
        close = c.close,
      }
    end

    local current = tonumber(quote.current_price)
    local last = candles[#candles]
    if last and current then
      last.close = current
      last.high = math.max(tonumber(last.high) or current, current)
      last.low = math.min(tonumber(last.low) or current, current)
    elseif current then
      candles[1] = {
        time = clock_text(),
        open = tonumber(quote.open) or current,
        high = tonumber(quote.high) or current,
        low = tonumber(quote.low) or current,
        close = current,
      }
    end

    return summarize(candles, {
      currency = historical.currency or asset.quote or "",
      prev_close = quote.prev_close,
      current_price = current,
      name = historical.name,
      live_source = quote.live_source,
    })
  end

  -- 将 TWSE 实时快照合并到图表。5m/1h 使用运行期间采样合成，
  -- 日线及周线保留历史 K 线，并追加/更新当天实时 OHLC。
  function self:merge_taiwan_quote(asset, interval, historical, quote)
    local label = interval and interval.label or "5m"
    local candles = {}
    local date_text = quote.date:sub(1, 4) .. "-" .. quote.date:sub(5, 6) .. "-" .. quote.date:sub(7, 8)

    if label == "5m" or label == "1h" then
      local period_min = label == "1h" and 60 or 5
      local hour, minute = tostring(quote.time or ""):match("^(%d%d):(%d%d)")
      hour = tonumber(hour) or 0
      minute = tonumber(minute) or 0
      local bucket_minute = math.floor(minute / period_min) * period_min
      local bucket_key = string.format("%s-%02d-%02d", quote.date, hour, bucket_minute)
      local store_key = asset.id .. ":" .. label
      local store = self.intraday[store_key]
      if not store or store.date ~= quote.date then
        store = { date = quote.date, candles = {} }
        self.intraday[store_key] = store
      end

      local last = store.candles[#store.candles]
      if last and last.key == bucket_key then
        last.close = quote.current_price
        last.high = math.max(last.high, quote.current_price)
        last.low = math.min(last.low, quote.current_price)
      else
        store.candles[#store.candles + 1] = {
          key = bucket_key,
          time = string.format("%s %02d:%02d", date_text, hour, bucket_minute),
          open = quote.current_price,
          high = quote.current_price,
          low = quote.current_price,
          close = quote.current_price,
        }
        while #store.candles > DEFAULT_LIMIT do
          table.remove(store.candles, 1)
        end
      end
      for i = 1, #store.candles do
        local c = store.candles[i]
        candles[#candles + 1] = {
          time = c.time,
          open = c.open,
          high = c.high,
          low = c.low,
          close = c.close,
        }
      end
    else
      for i = 1, #(historical.candles or {}) do
        local c = historical.candles[i]
        candles[#candles + 1] = {
          time = c.time,
          open = c.open,
          high = c.high,
          low = c.low,
          close = c.close,
        }
      end

      local live = {
        time = date_text,
        open = quote.open,
        high = quote.high,
        low = quote.low,
        close = quote.current_price,
      }
      local last = candles[#candles]
      local merge_last = last and tostring(last.time or ""):sub(1, 10) == date_text
      if label == "7day" and last then
        local function civil_days(text)
          local y, m, d = tostring(text or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
          y, m, d = tonumber(y), tonumber(m), tonumber(d)
          if not y or not m or not d then return nil end
          y = y - (m <= 2 and 1 or 0)
          local era = math.floor(y / 400)
          local yoe = y - era * 400
          local mp = m + (m > 2 and -3 or 9)
          local doy = math.floor((153 * mp + 2) / 5) + d - 1
          local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
          return era * 146097 + doe - 719468
        end
        local last_day = civil_days(last.time)
        local live_day = civil_days(date_text)
        if last_day and live_day then
          local last_week = last_day - ((last_day + 3) % 7)
          local live_week = live_day - ((live_day + 3) % 7)
          merge_last = last_week == live_week
        end
      end
      if merge_last then
        if label == "7day" then
          last.time = date_text
          last.high = math.max(tonumber(last.high) or quote.high, quote.high)
          last.low = math.min(tonumber(last.low) or quote.low, quote.low)
          last.close = quote.current_price
        else
          candles[#candles] = live
        end
      else
        candles[#candles + 1] = live
      end
      while #candles > DEFAULT_LIMIT do
        table.remove(candles, 1)
      end
    end

    return summarize(candles, {
      currency = "TWD",
      prev_close = quote.prev_close,
      current_price = quote.current_price,
      name = quote.name,
      live_source = "TWSE MIS",
    })
  end

  -- 记录请求失败并安排较短重试。
  function self:fail(message, code)
    local s = self.state
    s.loading = false
    s.status = "error"
    s.tone = "error"
    s.last_error = short_text(message or "request failed", 120)
    s.last_http_code = tonumber(code) or -1
    s.next_fetch_at = now_ms() + ERROR_RETRY_MS
    s.chart_dirty = true
  end

  -- 记录汇率同步失败，保留兜底汇率，30 分钟后再试。
  function self:fail_fx(message)
    local s = self.state
    s.fx_loading = false
    s.fx_last_error = short_text(message or "fx failed", 80)
    s.fx_next_fetch_at = now_ms() + FX_REFRESH_MS
  end

  -- 应用 USD/CNY、USD/TWD 汇率，切换显示币种时自动重绘图表。
  function self:apply_fx(cny_rate, twd_rate)
    local s = self.state
    s.fx_rate = tonumber(cny_rate) or s.fx_rate or FX_FALLBACK_USD_CNY
    s.fx_twd_rate = tonumber(twd_rate) or s.fx_twd_rate or FX_FALLBACK_USD_TWD
    s.fx_updated_text = clock_text()
    s.fx_last_error = ""
    s.fx_next_fetch_at = now_ms() + FX_REFRESH_MS
    s.fx_loading = false
    s.chart_dirty = true
  end

  -- 发起一次 JSON GET，请求结束后调用 callback。
  function self:request_json(job, url, callback)
    local s = self.state
    if s.http_busy then
      return false
    end
    if not http or not http.get then
      self:fail("http missing", -1)
      return false
    end

    s.http_busy = true
    s.http_job = job
    self.request_seq = (self.request_seq or 0) + 1
    local req_id = self.request_seq
    s.http_req_id = req_id
    s.http_started_ms = now_ms()
    if job == "fx" then
      s.fx_loading = true
    else
      s.loading = true
      s.status = "loading"
      s.tone = "warn"
    end

    -- 某些固件不会把响应 Content-Encoding 头完整传回 Lua；固定请求明文，
    -- 避免 Yahoo 返回 gzip 后被误当作 JSON/文本解析。
    local accept_encoding = "identity"
    local headers =
      "Accept: application/json\r\n"
      .. "Accept-Language: zh-CN,zh;q=0.9,en;q=0.8\r\n"
      .. "Accept-Encoding: " .. accept_encoding .. "\r\n"
      .. "Cache-Control: no-cache\r\n"
      .. "Pragma: no-cache\r\n"
      .. "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36\r\n"

    http.get(url, headers, function(code, body, resp_headers)
      if s.http_req_id ~= req_id then
        return
      end
      s.http_busy = false
      s.http_job = ""
      s.http_started_ms = 0
      if job == "fx" then
        s.fx_loading = false
      end

      if code ~= 200 then
        callback(false, nil, "http " .. tostring(code), code)
        return
      end
      if type(body) ~= "string" or body == "" then
        callback(false, nil, "empty body", code)
        return
      end

      local plain, derr = maybe_decompress(body, resp_headers)
      if not plain then
        callback(false, nil, derr or "decode body", code)
        return
      end

      if job == "eastmoney" then
        callback(true, plain, nil, code)
        return
      end

      local doc, jerr = decode_json(plain)
      if not doc then
        callback(false, nil, "json " .. tostring(jerr), code)
        return
      end

      callback(true, doc, nil, code)
    end)

    return true
  end

  -- 拉取当前资产走势，所有来源统一走串行请求。
  function self:fetch_current()
    if self.state.http_busy then
      return false
    end

    local asset = self:current_asset()
    local interval = find_interval(self.settings.interval)
    local url, uerr = build_url(asset, interval)
    if not url then
      self:fail(uerr or "bad url", -1)
      return false
    end

    local req_asset_id = asset.id
    local req_interval = interval.label
    local request_job = asset.source == "fx" and "fx_pair" or asset.source
    return self:request_json(request_job, url, function(ok, doc, err, code)
      if req_asset_id ~= self.settings.asset_id or req_interval ~= self.settings.interval then
        return
      end
      local parsed = nil
      local history_error = nil
      if ok then
        local perr = nil
        parsed, perr = parse_by_source(asset, doc)
        if not parsed then
          history_error = "parse " .. tostring(perr)
        end
      else
        history_error = tostring(err or ("http " .. tostring(code)))
      end

      if asset.source == "fx" then
        if parsed then
          self:apply_parsed(asset, parsed)
          self.state.next_fetch_at = now_ms() + FX_REFRESH_MS
        else
          self:fail(history_error, code)
        end
        return
      end

      if asset.group ~= "taiwan" then
        local quote_url
        local quote_job
        local quote_parser
        if asset.source == "binance" then
          quote_url = build_binance_quote_url(asset)
          quote_job = "binance_quote"
          quote_parser = parse_binance_quote
        elseif asset.source == "eastmoney" then
          quote_url = build_eastmoney_quote_url(asset)
          quote_job = "eastmoney"
          quote_parser = parse_eastmoney_quote
        end

        -- 未知/自定义来源仍使用原始 K 线结果。
        if not quote_url or not quote_parser then
          if parsed then
            self:apply_parsed(asset, parsed)
          else
            self:fail(history_error, code)
          end
          return
        end

        local historical = parsed or {
          candles = {},
          closes = {},
          currency = asset.quote or "",
        }

        local quote_started = self:request_json(quote_job, quote_url, function(quote_ok, quote_doc, quote_err)
          if req_asset_id ~= self.settings.asset_id or req_interval ~= self.settings.interval then
            return
          end
          if not quote_ok then
            if parsed then
              self:apply_parsed(asset, parsed)
              self.state.last_error = short_text("live " .. tostring(quote_err), 120)
              self.state.tone = "warn"
            else
              self:fail("history " .. tostring(history_error) .. "; live " .. tostring(quote_err), -1)
            end
            return
          end
          local quote, quote_parse_err = quote_parser(quote_doc)
          if not quote then
            if parsed then
              self:apply_parsed(asset, parsed)
              self.state.last_error = short_text("live " .. tostring(quote_parse_err), 120)
              self.state.tone = "warn"
            else
              self:fail("history " .. tostring(history_error) .. "; live " .. tostring(quote_parse_err), -1)
            end
            return
          end
          local merged, merge_err = self:merge_live_quote(asset, historical, quote)
          if not merged then
            self:fail("live merge " .. tostring(merge_err), -1)
            return
          end
          self:apply_parsed(asset, merged)
          if history_error then
            self.state.last_error = short_text("history " .. history_error, 120)
            self.state.tone = "warn"
          end
        end)
        if not quote_started then
          if parsed then
            self:apply_parsed(asset, parsed)
            self.state.last_error = "live quote busy"
            self.state.tone = "warn"
          else
            self:fail("live quote busy", -1)
          end
        end
        return
      end

      -- 台股实时报价独立于历史图表：Eastmoney 暂时失败时仍继续请求 TWSE，
      -- 以保证当前价、昨收和今日涨跌保持准确。
      local historical = parsed or { candles = {}, closes = {}, currency = "TWD" }

      local quote_url, quote_url_err = build_twse_quote_url(asset)
      if not quote_url then
        if parsed then
          self:apply_parsed(asset, parsed)
          self.state.last_error = short_text(quote_url_err or "twse url", 120)
          self.state.tone = "warn"
        else
          self:fail(quote_url_err or history_error or "twse url", -1)
        end
        return
      end

      local quote_started = self:request_json("twse_quote", quote_url, function(quote_ok, quote_doc, quote_err)
        if req_asset_id ~= self.settings.asset_id or req_interval ~= self.settings.interval then
          return
        end
        if not quote_ok then
          if parsed then
            self:apply_parsed(asset, parsed)
            self.state.last_error = short_text("live " .. tostring(quote_err), 120)
            self.state.tone = "warn"
          else
            self:fail("history " .. tostring(history_error) .. "; live " .. tostring(quote_err), -1)
          end
          return
        end

        local quote, quote_parse_err = parse_twse_quote(quote_doc)
        if not quote then
          if parsed then
            self:apply_parsed(asset, parsed)
            self.state.last_error = short_text("live " .. tostring(quote_parse_err), 120)
            self.state.tone = "warn"
          else
            self:fail("history " .. tostring(history_error) .. "; live " .. tostring(quote_parse_err), -1)
          end
          return
        end

        local merged, merge_err = self:merge_taiwan_quote(asset, interval, historical, quote)
        if not merged then
          self:fail("live merge " .. tostring(merge_err), -1)
          return
        end
        self:apply_parsed(asset, merged)
        if history_error then
          self.state.last_error = short_text("history " .. history_error, 120)
          self.state.tone = "warn"
        end
      end)

      if not quote_started then
        if parsed then
          self:apply_parsed(asset, parsed)
          self.state.last_error = "live quote busy"
          self.state.tone = "warn"
        else
          self:fail("live quote busy", -1)
        end
      end
    end)
  end

  -- 开机和每 30 分钟同步一次公开 USD/CNY、USD/TWD 汇率。
  function self:fetch_fx()
    if self.state.http_busy then
      return false
    end
    return self:request_json("fx", FX_URL, function(ok, doc, err, code)
      if not ok then
        self:fail_fx(err or ("fx http " .. tostring(code)))
        return
      end
      local cny_rate, twd_rate, perr = parse_fx_rates(doc)
      if not cny_rate or not twd_rate then
        self:fail_fx(perr or "fx parse")
        return
      end
      self:apply_fx(cny_rate, twd_rate)
    end)
  end

  -- 周期调度入口，由 main.lua 的 timer 调用。
  function self:tick()
    local s = self.state
    if s.http_busy then
      local timeout_ms = s.http_job == "fx_pair" and FX_HTTP_TIMEOUT_MS or HTTP_TIMEOUT_MS
      if s.http_started_ms > 0 and (now_ms() - s.http_started_ms) > timeout_ms then
        s.http_busy = false
        local timeout_job = s.http_job
        s.http_job = ""
        s.http_req_id = (s.http_req_id or 0) + 1
        s.http_started_ms = 0
        if timeout_job == "fx" then
          self:fail_fx("http timeout")
        else
          self:fail("http timeout", -1)
        end
      end
      return
    end
    if now_ms() >= (s.next_fetch_at or 0) then
      if self:fetch_current() then
        return
      end
    end
    if now_ms() >= (s.fx_next_fetch_at or 0) then
      self:fetch_fx()
    end
  end

  -- 切换资产，delta 用于实体按键。
  function self:select_asset_delta(delta)
    local idx = 1
    for i = 1, #self.assets do
      if self.assets[i].id == self.settings.asset_id then
        idx = i
        break
      end
    end
    idx = idx + (tonumber(delta) or 1)
    if idx < 1 then idx = #self.assets end
    if idx > #self.assets then idx = 1 end
    self:apply_settings({ asset = self.assets[idx].id }, true)
  end

  -- 只在当前分类内切换标的，重力与手柄左右键共用。
  function self:select_group_asset_delta(delta)
    local active = self:current_asset()
    local group = active.group
    local choices = {}
    for i = 1, #self.assets do
      if self.assets[i].group == group then
        choices[#choices + 1] = self.assets[i]
      end
    end
    if self.custom_asset and self.custom_asset.group == group then
      choices[#choices + 1] = self.custom_asset
    end
    if #choices == 0 then return end
    local idx = 1
    for i = 1, #choices do
      if choices[i].id == active.id then idx = i break end
    end
    idx = idx + (tonumber(delta) or 1)
    if idx < 1 then idx = #choices end
    if idx > #choices then idx = 1 end
    self:apply_settings({ asset = choices[idx].id }, true)
  end

  -- 切换周期，delta 用于实体按键。
  function self:select_interval_delta(delta)
    local _, idx = find_interval(self.settings.interval)
    idx = idx + (tonumber(delta) or 1)
    if idx < 1 then idx = #self.intervals end
    if idx > #self.intervals then idx = 1 end
    self:apply_settings({ interval = self.intervals[idx].label }, true)
  end

  -- 切换图表模式，按键长按和 Web 选择共用。
  function self:set_mode(mode)
    local normalized = normalize_mode(mode)
    if self:current_asset().group == "fx" then
      normalized = "line"
    end
    if normalized and normalized ~= self.settings.mode then
      self.settings.mode = normalized
      self.state.chart_dirty = true
      self:save_settings()
    end
  end

  -- 折线/K 线互切。
  function self:toggle_mode()
    if self.settings.mode == "candle" then
      self:set_mode("line")
    else
      self:set_mode("candle")
    end
  end

  -- 应用 Web 或按键传入的设置。
  function self:apply_settings(params, refresh)
    params = params or {}
    local data_changed = false
    local chart_changed = false
    local settings_changed = false

    local custom_requested = params.source
      and (trim(params.source) == "fx" or (params.symbol and trim(params.symbol) ~= ""))
    if custom_requested then
      local custom, err = make_custom_asset(params)
      if custom then
        self.custom_asset = custom
        params.asset = custom.id
        settings_changed = true
      else
        self:fail(err or "bad custom asset", -1)
        return false
      end
    end

    local asset_id = params.asset or params.asset_id
    if asset_id and self:find_asset(asset_id) and asset_id ~= self.settings.asset_id then
      self.settings.asset_id = asset_id
      data_changed = true
      settings_changed = true
      if not params.currency and not params.display_currency then
        local selected_asset = self:find_asset(asset_id)
        local native_currency = normalize_currency(selected_asset and selected_asset.quote)
        if native_currency ~= self.settings.currency then
          self.settings.currency = native_currency
          chart_changed = true
        end
      end
    end

    if params.interval then
      local interval = find_interval(params.interval)
      if interval and interval.label ~= self.settings.interval then
        self.settings.interval = interval.label
        data_changed = true
        settings_changed = true
      end
    end

    if params.mode then
      local mode = normalize_mode(params.mode)
      if mode and mode ~= self.settings.mode then
        self.settings.mode = mode
        chart_changed = true
        settings_changed = true
      end
    end

    if params.ma or params.ma_period then
      local ma_period = normalize_ma_period(params.ma or params.ma_period)
      if ma_period ~= nil and ma_period ~= self.settings.ma_period then
        self.settings.ma_period = ma_period
        chart_changed = true
        settings_changed = true
      end
    end

    if params.currency or params.display_currency then
      local currency = normalize_currency(params.currency or params.display_currency)
      if currency ~= self.settings.currency then
        self.settings.currency = currency
        chart_changed = true
        settings_changed = true
      end
    end

    if params.tilt_enabled ~= nil then
      local enabled = normalize_bool(params.tilt_enabled, self.settings.tilt_enabled)
      if enabled ~= self.settings.tilt_enabled then
        self.settings.tilt_enabled = enabled
        settings_changed = true
      end
    end

    if self:current_asset().group == "fx" then
      if self.settings.mode ~= "line" then
        self.settings.mode = "line"
        chart_changed = true
        settings_changed = true
      end
      if self.settings.ma_period ~= 0 then
        self.settings.ma_period = 0
        chart_changed = true
        settings_changed = true
      end
    end

    if data_changed then
      self:clear_data("switching")
    elseif chart_changed then
      self.state.chart_dirty = true
    end
    if data_changed or (refresh and not chart_changed) then
      self:queue_refresh()
    end
    if settings_changed then
      self:save_settings()
    end
    return true
  end

  -- 生成给 Web 和屏幕端复用的状态快照。
  function self:snapshot()
    local s = self.state
    local asset = self:current_asset()
    local interval = find_interval(self.settings.interval)
    local assets = {}
    for i = 1, #self.assets do
      assets[#assets + 1] = public_asset(self.assets[i])
    end
    if self.custom_asset then
      assets[#assets + 1] = public_asset(self.custom_asset)
    end

    local intervals = {}
    for i = 1, #self.intervals do
      intervals[#intervals + 1] = {
        label = self.intervals[i].label,
        fx_label = self.intervals[i].fx_label,
      }
    end

    local target_currency = asset.group == "fx"
      and (normalize_currency_code(asset.quote) or "USD")
      or normalize_currency(self.settings.currency)
    local fx_rate = tonumber(s.fx_rate) or FX_FALLBACK_USD_CNY
    local fx_twd_rate = tonumber(s.fx_twd_rate) or FX_FALLBACK_USD_TWD
    local points = {}
    local display_min = nil
    local display_max = nil
    local start_i = 1
    if #s.candles > DEFAULT_LIMIT then
      start_i = #s.candles - DEFAULT_LIMIT + 1
    end
    for i = start_i, #s.candles do
      local c = s.candles[i]
      local close_p = display_price(asset, c.close, target_currency, fx_rate, fx_twd_rate)
      if close_p then
        local open_p = display_price(asset, c.open, target_currency, fx_rate, fx_twd_rate) or close_p
        local high_p = display_price(asset, c.high, target_currency, fx_rate, fx_twd_rate) or math.max(open_p, close_p)
        local low_p = display_price(asset, c.low, target_currency, fx_rate, fx_twd_rate) or math.min(open_p, close_p)
        local range_low = self.settings.mode == "line" and close_p or low_p
        local range_high = self.settings.mode == "line" and close_p or high_p
        if range_low and (not display_min or range_low < display_min) then
          display_min = range_low
        end
        if range_high and (not display_max or range_high > display_max) then
          display_max = range_high
        end
        points[#points + 1] = {
          time = c.time,
          time_value = chart_time_value(c.time),
          open = open_p,
          high = high_p,
          low = low_p,
          close = close_p,
        }
      end
    end

    local display_current = display_price(asset, s.current_price, target_currency, fx_rate, fx_twd_rate)
    if not display_current and #points > 0 then
      display_current = points[#points].close
    end
    local display_prev = display_price(asset, s.prev_close, target_currency, fx_rate, fx_twd_rate)
    local display_change = display_current and display_prev and (display_current - display_prev) or nil
    local display_pct = s.change_pct
    if not display_pct and display_current and display_prev and display_prev ~= 0 then
      display_pct = (display_current - display_prev) * 100 / display_prev
    end
    display_min = display_min or display_price(asset, s.min_price, target_currency, fx_rate, fx_twd_rate)
    display_max = display_max or display_price(asset, s.max_price, target_currency, fx_rate, fx_twd_rate)

    return {
      ok = true,
      version = self.version,
      app_id = self.app_id,
      assets = assets,
      intervals = intervals,
      currencies = public_currencies(),
      fx_currencies = FX_CURRENCIES,
      active = public_asset(asset),
      settings = {
        asset = asset.id,
        interval = interval.label,
        interval_text = asset.group == "fx" and (interval.fx_label or interval.label) or interval.label,
        mode = self.settings.mode,
        currency = target_currency,
        ma = self.settings.ma_period > 0 and tostring(self.settings.ma_period) or "off",
        ma_period = self.settings.ma_period,
        tilt_enabled = self.settings.tilt_enabled,
      },
      mode_text = mode_text(self.settings.mode),
      valid = s.valid,
      loading = s.loading or (s.http_busy and s.http_job ~= "fx"),
      status = s.status,
      tone = s.tone,
      error = s.last_error,
      http_code = s.last_http_code,
      price = display_current,
      price_text = asset.group == "fx" and fmt_rate(display_current) or fmt_price(display_current),
      change = display_change,
      change_text = fmt_signed(display_change),
      change_pct = display_pct,
      change_pct_text = fmt_pct(display_pct),
      currency = target_currency,
      currency_text = currency_text(target_currency),
      source_currency = s.currency or asset.quote or "",
      live_source = s.live_source ~= "" and s.live_source or asset.source,
      unit_text = unit_text(asset),
      min_price = display_min,
      max_price = display_max,
      min_price_text = asset.group == "fx" and fmt_rate(display_min) or fmt_price(display_min),
      max_price_text = asset.group == "fx" and fmt_rate(display_max) or fmt_price(display_max),
      updated_text = s.last_update_text,
      now_text = clock_text(),
      fx_rate = fx_rate,
      fx_twd_rate = fx_twd_rate,
      fx_updated_text = s.fx_updated_text,
      fx_loading = s.fx_loading,
      fx_error = s.fx_last_error,
      next_fetch_in_s = math.max(0, math.floor(((s.next_fetch_at or 0) - now_ms() + 999) / 1000)),
      chart_dirty = s.chart_dirty,
      points = points,
    }
  end

  -- 停止后端，当前实现无持久资源，只保留接口对称。
  function self:stop(reason)
    self.state.http_req_id = (self.state.http_req_id or 0) + 1
    self.state.http_busy = false
    self.state.http_job = ""
    self.state.http_started_ms = 0
    self.state.loading = false
    self.state.fx_loading = false
  end

  self:load_settings()
  return self
end

return Backend
