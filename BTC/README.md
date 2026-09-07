# Ticker 3.0.0 / 行情看板

Ticker 是运行在 HoloCubic ESP32 设备上的多市场行情应用，支持币价、A 股、港股、美股、台股、指数、金银铜和货币汇率。使用设备菜单、手柄、重力操作或浏览器控制；当前标的与显示设置保存在 SD 卡，重新进入应用后恢复。

Ticker is a multi-market quote app for HoloCubic ESP32 devices, covering crypto, A-shares, Hong Kong, US and Taiwan stocks, indexes, metals, and FX. Control it through the device menu, a controller, tilt input, or a browser. The selected instrument and display settings are saved on the SD card and restored when the app starts.

## 3.0.0 更新说明 / Release notes

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

[完整更新记录 / Full changelog](CHANGELOG.md) · [应用介绍页 / App information page](package/info.html)

## 安装与升级 / Install and upgrade

1. 将 `package/` 内的文件复制到设备 `/sd/apps/BTC/`，然后在 Launcher 扫描应用并进入 Ticker。升级时仅覆盖应用文件，保留 `settings.json`、`settings.json.bak` 和 `catalog/`。
   Copy the contents of `package/` to `/sd/apps/BTC/`, rescan apps in Launcher, and open Ticker. During upgrades, replace app files while preserving `settings.json`, `settings.json.bak`, and `catalog/`.
2. 在应用运行时，从设备主页打开 Web 控制页，或访问 `http://<device-ip>/BTC`。升级后刷新网页，加载新版脚本。
   While the app is running, open its Web console from the device home page or visit `http://<device-ip>/BTC`. Refresh the browser after upgrading to load the new scripts.
3. 展开“股票与货币目录”，按市场下载或更新。之后可在本地目录搜索名称和代码；不需要运行电脑端服务。
   Open **Stock and currency directories** and download/update the required markets. Search names and symbols from the local directory afterward; no PC companion service is required.

> 安装包不包含个人配置或已下载目录。固件是否在开机时自动启动 Ticker，由固件的启动设置决定。
>
> The package contains neither personal settings nor downloaded directories. Whether Ticker launches automatically at boot depends on the firmware's startup settings.

## 使用 / Usage

- **搜索与自选 / Search and saved instruments**：选择市场，输入名称或代码，再点击结果显示行情。目录结果保存为自定义标的，支持删除管理。
  Choose a market, search by name or symbol, and select a result to display it. Directory selections are saved as custom instruments and can be removed later.
- **港股 / Hong Kong**：例如 `00700` 腾讯控股、`01810` 小米集团。自定义 Eastmoney 市场编号为 `116`；`700`、`00700`、`00700.HK` 均可归一化。普通港股使用 HKD，人民币和美元柜台按港交所代码范围识别。
  Examples include Tencent `00700` and Xiaomi `01810`. The custom Eastmoney market is `116`; `700`, `00700`, and `00700.HK` are normalized. Ordinary HK stocks use HKD; RMB/USD counters follow HKEX code ranges.
- **周期与图表 / Intervals and charts**：支持 5m、1h、1d、1w，折线、K 线、MA10/MA20；兼容旧配置中的 `1day` 与 `7day`。
  Supports 5m, 1h, 1d, and 1w; line/candlestick charts and MA10/MA20. Legacy `1day` and `7day` settings remain supported.
- **汇率 / FX**：选择原货币和目标货币，点击“保存并显示汇率”。使用每日参考汇率；股票图表偏好在切换至汇率后仍会保留。
  Choose base and quote currencies, then select **Save and display rate**. FX uses daily reference rates; stock chart preferences are preserved when switching to FX.
- **自定义接口 / Custom sources**：保留 Binance、Eastmoney、Yahoo Finance、TWSE MIS 和 Frankfurter 的来源/代码配置。保存多个自定义标的，无需手动修改 SD 配置文件。
  Retains source/symbol configuration for Binance, Eastmoney, Yahoo Finance, TWSE MIS, and Frankfurter. Save multiple custom instruments without editing SD configuration files manually.
- **设置保存 / Saved settings**：每次改变设置时写入 SD，先校验临时文件再替换配置并保留备份；保存失败会显示错误。
  Changes are written to SD after verifying a temporary file, with a backup retained. Save failures are reported.

## 目录与空间 / Directories and storage

目录分页下载、分批搜索，不会一次把完整股票列表读入设备内存。仅在完整下载校验成功后启用新目录。更新失败保留上一份完整目录；旧版 A 股筛选目录需重新下载。

Directories are downloaded in pages and searched in bounded batches without loading the full stock list into RAM. A new directory becomes active only after the complete download passes validation. Failed updates preserve the previous complete directory; A-share caches made with the old filters must be downloaded again.

以下为开发期间的实际缓存示例，目录内容和大小会随数据源变化；不包含 SD 文件系统开销及更新备用槽。

The following are measured cache examples from development. Contents and sizes vary by provider and exclude SD filesystem overhead and update backup slots.

| 目录 / Directory | 条目 / Entries | 数据大小 / Data size |
| --- | ---: | ---: |
| A 股 / A-shares | 5,570 | 153,288 bytes |
| 港股 / Hong Kong | 3,361 | 104,298 bytes |
| 台股 / Taiwan | 2,322 | 55,419 bytes |
| 货币 / Currencies | 165 | 4,386 bytes |

美股目录支持下载，但本次没有完成全量实机下载验证。更新采用双槽保留当前有效数据，建议为目录预留额外空间。

US-directory downloads are supported, but a complete US-directory download was not verified on hardware for this release. Updates use two slots to retain the active data, so allow additional space.

## 信息来源 / Data sources

| 用途 / Purpose | 来源 / Provider |
| --- | --- |
| 币价和 K 线 / Crypto quotes and candles | Binance public market data |
| 股票目录、股票/指数/金属行情及历史图表 / Stock directories, stock/index/metal quotes and history | Eastmoney |
| 台股实时行情 / Taiwan live quotes | TWSE MIS |
| 货币目录和每日历史汇率 / Currency directory and daily FX history | Frankfurter |
| USD/CNY、USD/TWD、USD/HKD 换算 / Currency conversion | Open ER-API |
| 兼容自定义证券来源 / Compatible custom securities source | Yahoo Finance |

公开接口可能限流、调整或延迟。离线换算使用内置参考汇率，不代表实时汇率。行情用于展示，不构成投资建议。

Public APIs may change, rate-limit requests, or return delayed data. Offline conversion uses built-in reference rates rather than live rates. Quotes are for display, not financial advice.

## 验证与边界 / Validation and limits

20 项 Lua 回归测试及 Web DOM 测试通过，覆盖配置恢复、写入失败回滚、目录搜索、港股代码/币种、时间精度和请求占用。实机验证了港股目录搜索与报价、BTC 5m 点距，以及退出再进入应用后的设置恢复；未进行整机断电或网页视觉验收测试。

20 Lua regression tests and Web DOM tests passed, covering settings recovery, failed-write rollback, directory search, HK symbols/currencies, timestamp precision, and request ownership. Hardware checks verified HK directory search/quotes, BTC 5m spacing, and settings restoration after restarting the app. Full power-loss and browser visual tests were not performed.

连接错误 `http -1` 并非服务器 HTTP 状态码。本版改善应用层超时与重试，但没有宣称修复所有 DNS/TCP/TLS 或固件重启问题。`http.get` 没有暴露取消句柄；连接释放仍依赖固件回调，若固件一直不回调，应用保持等待以避免继续堆积连接。Binance 仍使用原官方域名。

Connection error `http -1` is not a server HTTP status. This release improves application-level timeouts/retries without claiming to fix every DNS/TCP/TLS or firmware-reset issue. `http.get` exposes no cancellation handle; connection release still depends on the firmware callback. If that callback never arrives, the app waits rather than piling up connections. Binance continues to use its original official domain.

## 交互参考 / Interaction references

- [TradingView symbol search](https://www.tradingview.com/charting-library-docs/latest/ui_elements/Symbol-Search/)
- [TradingView watchlists](https://www.tradingview.com/support/solutions/43000745825-mastering-the-tradingview-watchlists/)
- [ESP32 CYD Stock Ticker](https://github.com/Zaitronics/esp32-cyd-stock-ticker)
- [HKEX stock-code allocation](https://www.hkex.com.hk/Products/Securities/Stock-Code-Allocation-Plan?sc_lang=en)

参考市场分类、搜索、自选列表与设备控制的交互方式；Web 控制页使用本地 HTML/CSS/JavaScript，无外部前端运行库依赖。

These references informed market categories, search, watchlists, and device controls. The Web console uses local HTML/CSS/JavaScript without external frontend runtime dependencies.
