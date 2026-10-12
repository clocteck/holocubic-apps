# Pip Boy Clock

独立的 320×240 Lua/LVGL 时钟 app，固定坐标布局。设备运行时不依赖 NixieClock 或 weather app。

首次社区发布：`0.0.0`，开发者 `wzh`，`catalog_scope = community`。之前 `1.0.0/1.0.1` 为真机测试期间的临时版本号，不作为正式发行版本。

## 安装

将 `PipBoy/package/` 的全部内容复制到设备 `/sd/apps/PipBoy/`，然后 `app.rescan()`，从桌面启动 Pip Boy，或执行 `app.launch("PipBoy")`。不要将 `package` 目录本身复制进去。纯 Lua，无需编译。

已在用户指定的设备 192.168.1.30 上上传并测试，测试截图与结果位于 `src/validation/`。这是当次验收记录，不代表后续网络或设备状态。

## 数据及界面

- 时间：与 Holo Clock 一样，读取 `/sd/apps/settings.json` 的 `timezone`，缺省 `CST-8`；调用 `time.settimezone()` 和 `time.initntp("ntp.aliyun.com")`，用 `time.getlocal()` 显示设备当地时间。未校时显示 `--`，不伪造日期。
- 天气：读取 `weather_location_id`、`weather_address` / `weatherAddress`，兼容 `weather_city` / `city_name` / `city`。优先位置 ID；地址先经 `/v1/weather/cities` 查找，再调用 `/v1/weather/now`。通过 `http.cubicserver.get()`，支持 gzip；30 分钟刷新，错误后 60 秒重试，请求超时 20 秒。
- 温度：服务端始终 `unit=m`，根据 `temperature_unit` 在显示时转为 °C/°F；语言遵循现有时钟的英文/中文规则。
- 右上角：根据真实天气码选择 12 种浅绿色线稿 PNG（晴/晴夜/日夜多云/阴/雨/雷雨/雪/雾/风沙/雨夹雪/未知）；没有实况时显示 `--`。素材在开发电脑预先切片到 28×28，设备只调用 PNG，不现场绘制。
- 右下角 `BRI`：`sys.getbrightness()` 的实际屏幕亮度百分比，每秒读取；只读，不修改亮度。原 `PWR 98%` 是原型假电量，已移除。
- 底栏 `RH` 是真实相对湿度；`WX OK` 表示实况可用，`WX --` 表示尚不可用。原 HP/RAD 装饰数据已移除。
- 系统设置每 30 秒重新读取；切换地点后作废旧请求；退出后忽略迟到回调。

背景为 imagegen 已生成素材的 320×240 PNG，不包含 SVG。当前天气线稿素材由内置 imagegen 生成，源图与提示词在 `src/assets/`，成品在 `package/assets/weather-line/`。安装包已移除 61 张旧彩色天气图标、其不再适用的许可证副本及未使用的 `time_num_28.bin`，打包脚本也不再复制它们；这些旧图标原件仍在本仓库 weather app 中。五个在用字体随包分发。星期使用 LVGL 的 CENTER 枚举并留 3px 内边距，秒数使用 14px 字体，温度使用含 °/C/F 的 24px 字体。运行时保持背景图片不变，仅更新变化的文本与天气图标，不每秒重绘/解码整张背景。退出时先删除自己创建的 LVGL 子树，再释放字体和计时器，不清空其他 app 的屏幕。

`package/info.html` 是商店介绍页，内嵌 Base64 PNG 图标，无外部字体或脚本，不需要 `main.html`。开发源图、提示词、测试脚本、HTML 表盘预览、真机截图均在 `src/` 下，不进入设备安装包。运行包仅 23 个文件；测试截图和本地打包产物不提交 Git。

## 开发与验证

`prepare-assets.ps1` 将已生成素材缩放到设备尺寸，切片天气线稿图集，并复制本仓库字体。重新打包只需要：

```powershell
powershell -NoProfile -File PipBoy/src/prepare-assets.ps1
python PipBoy/src/run-tests.py
python -m http.server 8766 --bind 127.0.0.1 --directory PipBoy
```

浏览器预览：`http://127.0.0.1:8766/src/preview.html`。预览显示浏览器本地时间，天气和硬件亮度默认为 `--`，不会声称是设备实时值；`?demo=1` 可看明确标识的示例天气。Lua 测试使用已安装的 `lupa`，不访问网络和设备，覆盖 NTP、天气查询/异常、设置更新、单位转换、亮度以及退出清理。字体渲染和实际服务端响应仍需真机验收。
