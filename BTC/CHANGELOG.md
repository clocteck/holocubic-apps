# 更新记录 / Changelog

## 3.0.0

| 更新 | Change |
| --- | --- |
| 新增港股分类、目录下载与名称/代码搜索，保留五位代码并支持 HKD 显示。 | Adds Hong Kong instruments, directory downloads, name/symbol search, five-digit symbols, and HKD display. |
| A 股、美股、台股、港股及货币目录按需下载至 SD 卡，不随应用预装。 | Downloads A-share, US, Taiwan, Hong Kong, and currency directories to SD on demand; no directory cache is bundled. |
| 重设计 Web 控制页，将行情图表、市场搜索、自定义标的及目录管理分开；浏览和搜索不会切换设备，点击结果才切换。 | Redesigns the Web console around charts, market search, custom instruments, and directory management. Browsing/searching does not switch the device until a result is selected. |
| 支持保存多个自定义标的，并迁移旧配置；持久保存当前标的、5m/1h/1d/1w 周期、图表、均线、币种和重力开关。 | Saves multiple custom instruments and migrates legacy settings. Persists the selected instrument, 5m/1h/1d/1w interval, chart mode, MA, currency, and tilt setting. |
| 保留用户输入草稿，避免后台状态轮询覆盖正在编辑的内容。 | Preserves input drafts while background status polling continues. |
| 修正 A 股目录的退市过滤与北交所范围；无有效行情时显示明确提示。 | Corrects delisting and Beijing-market filters for A-share directories and explains unavailable quotes. |
| 修复 Binance 毫秒时间戳在设备上的精度损失，5 分钟 K 线点距恢复为 300 秒。 | Preserves Binance timestamp precision on the device, restoring 300-second spacing for 5-minute candles. |
| 为请求传入底层超时参数，增加失败退避，并避免旧请求未返回时重复启动同一后端的 TLS 请求。 | Passes native timeout options, adds retry backoff, and prevents the same backend from starting overlapping TLS requests while an earlier request remains pending. |


## 2.1.1 更新说明 / Release Notes

- 中文：手柄 SELECT/View 或 HOME 键现在可随时退出 BTC 并返回 Launcher，行为与 Weather 应用一致。
  English: SELECT/View or HOME now exits BTC and returns to Launcher from any screen, matching the Weather app.
- 中文：确认行情刷新定时器只更新数据和 UI，不会自动切换当前分类或标的；页面仅由重力、手柄或 Web 操作切换。
  English: Confirms that refresh timers only update data and UI; categories and symbols change only through tilt, controller, or Web input.
- 中文：修复应用启动时菜单面板短暂闪现的问题，菜单遮罩在创建后立即隐藏。
  English: Fixes the controller menu briefly flashing during startup by hiding its overlay immediately upon creation.

## 2.1.0 更新说明 / Release Notes

- 中文：重力切换改用与 Launcher 相同的阈值触发事件和长持重复节奏，到达倾斜阈值时立即在当前分类内翻页；Web 控制页可随时关闭并持久保存重力切换设置。
  English: Tilt navigation now follows Launcher’s threshold-trigger and hold-repeat behavior, switching immediately within the current category; the Web console can disable it persistently.
- 中文：新增 40 ms 上升沿轮询的蓝牙手柄控制。行情页左右切标的、上下切周期、A 键刷新，MENU 键打开设备端控制菜单。
  English: Adds Bluetooth controller input with Launcher-style 40 ms rising-edge polling. Left/right switch symbols, up/down change intervals, A refreshes, and MENU opens the on-device control menu.
- 中文：新增简洁的设备端菜单，可控制分类、标的、汇率原/目标货币、周期、图表、均线、显示币种、重力开关和立即刷新，无需保持 Web 页面连接。
  English: Adds a compact on-device menu for category, symbol, FX base/quote, interval, chart, moving average, display currency, tilt, and refresh—without keeping the Web page open.

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

## 1.3.0 更新说明 / Release notes

English: Adds a dedicated FX category with USD/CNY, EUR/CNY, USD/JPY, and EUR/USD presets; accepts custom ISO 4217 pairs, saves the pair, adapts decimal precision, and refreshes every 30 minutes.

- 新增独立的“汇率”分类，内置 USD/CNY、EUR/CNY、USD/JPY、EUR/USD。
- Web 控制页可输入任意两个 ISO 4217 三字母货币代码，例如 `GBP` 与 `HKD`，保存并显示对应兑换汇率。
- 汇率按“1 单位源货币可兑换多少目标货币”显示，小数汇率自适应保留精度，并保存自定义货币对。
- 汇率数据每 30 分钟刷新。

## 1.2.1 更新说明 / Release notes

English: Corrects crypto changes against the Binance 24-hour baseline and securities changes against the previous close. Uses TWSE MIS for Taiwan live quotes, avoids duplicate weekly points, merges live quotes into chart data, and preserves real time gaps with close-price scaling.

- 修复币价盘中涨跌错误使用图表区间首价的问题，改用 Binance 官方 24 小时行情基准。
- 修复美股、指数、A 股和金属错误使用历史请求区间前值作为昨收的问题。
- 台股实时价与涨跌改用 TWSE MIS，并修复周线重复追加当天日线的问题。
- 实时价同步合并到最新图表点；历史 K 线暂时不可用时仍可显示实时行情。
- 折线图改用收盘价范围缩放，并按真实时间间隔绘制，避免走势被压成直线或休市间距失真。

## 1.2.0 更新说明 / Release notes

English: Adds Taiwan presets, TWD conversion, and Traditional Chinese. Fixes zero-volume history placeholders, change baselines, missing Simplified Chinese names, legacy custom-symbol migration, and obsolete proxy paths; raises the Web handler limit to 128.

- 新增台湾加权指数及台积电、鸿海、联发科、台达电、富邦金、环球晶等台股预设。
- 新增 TWD 显示和 USD/TWD 汇率换算。
- 新增繁体中文界面与台股名称翻译。
- 修复 Eastmoney 台股零成交量占位数据导致折线接近直线的问题。
- 修复台股涨跌额错误使用区间起始价格的问题。
- 修复简体中文资产名称表缺失导致 Web 控制页空白的问题。
- 修复旧版 Yahoo 台股自定义配置迁移后回退到 BTC 的问题。
- 清理旧的代理和 TWSE MIS 路径，台股改用 Eastmoney 公共 HTTPS 地址。
- Web HTTP handler 上限调整为 128。
