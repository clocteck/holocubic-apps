# Ticker

Ticker 是面向 HoloCubic 的多市场行情应用，支持自定义货币汇率、加密货币、美股、A 股、台股、指数和金银铜行情，并提供折线图、K 线及 MA10/MA20 均线。

## 信息来源

- 加密货币：Binance 公共行情接口。
- A 股、内置美股、指数和金银铜的实时行情及各市场历史 K 线：Eastmoney 公共行情接口。
- 台股实时价、昨收和当日开高低：台湾证券交易所 TWSE MIS 公共行情接口。
- 任意 ISO 4217 三字母货币对及每日历史折线：Frankfurter；USD/CNY、USD/TWD 行情换算汇率：open.er-api.com。
- 兼容/备用证券来源：后端保留 Yahoo Finance 解析能力，用于兼容旧版自定义配置。该接口可能受地区访问策略限制，台股和内置美股不会依赖它。
- 离线汇率兜底：实时汇率接口不可用时，应用使用内置参考汇率维持币种换算显示。参考值不代表实时汇率。

所有在线请求均使用公开 HTTPS 原始域名，不依赖局域网代理地址。公开接口可能调整、限流或暂时不可用，行情仅用于展示，不构成投资建议。

## 2.0.1 更新说明 / Release Notes

- 中文：汇率的原货币和目标货币下拉框新增印尼盾（IDR），常用货币数量增加到 19 种。
  English: Adds Indonesian Rupiah (IDR) to both FX dropdowns, increasing the common-currency list to 19 entries.

## 2.0.0 更新说明 / Release Notes

- 中文：汇率控制区改为“原货币”和“目标货币”两个下拉框，内置 18 种常用货币，选择后立即刷新。
  English: The FX controls now use separate Base Currency and Quote Currency dropdowns with 18 common currencies and refresh immediately after selection.
- 中文：汇率模式不再显示“标的”行，并隐藏不适用的显示币种、K 线和均线设置。
  English: FX mode removes the Asset row and hides display-currency, candlestick, and moving-average controls that do not apply to currency pairs.
- 中文：新增 7 天、30 天、90 天和 1 年每日历史汇率，并修复单点数据与 32 位设备时间戳溢出导致折线不显示的问题。
  English: Adds 7-day, 30-day, 90-day, and 1-year daily FX history, and fixes missing line charts caused by single-point data and 32-bit timestamp overflow.
- 中文：当前汇率与折线图统一使用同一组 Frankfurter 历史数据，避免不同数据源混用造成末点偏差。
  English: The current FX rate and chart now share the same Frankfurter history dataset, preventing endpoint mismatches at the latest chart point.

## 1.3.0 更新说明

- 新增独立的“汇率”分类，内置 USD/CNY、EUR/CNY、USD/JPY、EUR/USD。
- Web 控制页可输入任意两个 ISO 4217 三字母货币代码，例如 `GBP` 与 `HKD`，保存并显示对应兑换汇率。
- 汇率按“1 单位源货币可兑换多少目标货币”显示，小数汇率自适应保留精度，并保存自定义货币对。
- 汇率数据每 30 分钟刷新。

## 1.2.1 更新说明

- 修复币价盘中涨跌错误使用图表区间首价的问题，改用 Binance 官方 24 小时行情基准。
- 修复美股、指数、A 股和金属错误使用历史请求区间前值作为昨收的问题。
- 台股实时价与涨跌改用 TWSE MIS，并修复周线重复追加当天日线的问题。
- 实时价同步合并到最新图表点；历史 K 线暂时不可用时仍可显示实时行情。
- 折线图改用收盘价范围缩放，并按真实时间间隔绘制，避免走势被压成直线或休市间距失真。

## 1.2.0 更新说明

- 新增台湾加权指数及台积电、鸿海、联发科、台达电、富邦金、环球晶等台股预设。
- 新增 TWD 显示和 USD/TWD 汇率换算。
- 新增繁体中文界面与台股名称翻译。
- 修复 Eastmoney 台股零成交量占位数据导致折线接近直线的问题。
- 修复台股涨跌额错误使用区间起始价格的问题。
- 修复简体中文资产名称表缺失导致 Web 控制页空白的问题。
- 修复旧版 Yahoo 台股自定义配置迁移后回退到 BTC 的问题。
- 清理旧的代理和 TWSE MIS 路径，台股改用 Eastmoney 公共 HTTPS 地址。
- Web HTTP handler 上限调整为 128。
