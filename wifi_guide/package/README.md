# WiFi Setting Guide

WiFi Setting Guide 是适配 HoloCubic 320 × 240 屏幕的首次联网引导 app。设备未联网时显示热点与配网地址；PCAPP 完成 USB 串口握手后自动切换到独立串口配网页；获得 Station IP 后自动切换到成功页，展示 WiFi、RSSI、IP、域名和控制网页二维码。

## 2.2.1 更新内容

- 将经过实机验证的 USB 串口配网功能整合到 WiFi Setting Guide，无需再打开独立配网 App。
- PCAPP 串口握手成功后自动切换到独立串口配网页面。
- 使用原生 `wifi.sta.scan/config/connect` 完成热点扫描和联网，设备离线时也可工作。
- 串口配网页面新增当前 WiFi SSID 和 IP 地址；未联网时明确显示“未连接”。
- 根据 WiFi 鉴权断连原因识别常见密码错误，并在设备与 PCAPP 中显示“WiFi 密码错误”。
- 修复串口已连接但设备未响应时的引导文字，提示用户在设备上打开 WiFi Setting Guide App。
- 联网成功后自动返回配网成功页面，并继续显示信号、IP、域名及控制页面二维码。

## 主要功能

- 等待配网与配网成功两套纯黑界面，全部使用 LVGL 绝对坐标布局。
- 集成原生串口配网页面，使用 `wifi.sta.scan/config/connect` 完成离线扫描、鉴权和联网，不依赖设备 HTTP 接口。
- 读取 `/sd/apps/settings.json` 的 `language`、`locale` 或 `lang`；仅 `zh-CN` / `zh-Hans` 使用中文，缺失或其他语言默认英文。
- 通过设备本地 `/api/system/state` 获取网络状态。
- RSSI 规则与 Web 控制页一致：优先使用扫描列表第一条同名 SSID 的 `rssi`，缺失时回退到 `sta_rssi`。
- Lua 内置 QR Version 2-L 编码、Reed–Solomon 纠错与 Canvas 绘制，不依赖 `lv_qrcode_*` 或外部二维码服务。
- 定时检查联网状态、语言和信号强度；退出时释放定时器、按键监听和字体资源。

## 文件说明

```text
app.info                 app 元信息
main.lua                 设备端入口
main.png                 launcher 图标
info.html                launcher 中文介绍页
main.html                等待配网 HTML 设计稿
success.html             配网成功 HTML 设计稿
font/*.bin               LVGL 中文字体
assets/*                 设计资源
```

设备端字体路径：

```text
/sd/apps/wifi_guide/font/msyh_cn_13.bin
/sd/apps/wifi_guide/font/18chinese.bin
```

## HTML 预览

等待配网页：

```text
main.html
main.html?ssid=clocteck-cubic&portal=192.168.18.1
```

成功页：

```text
success.html
success.html?wifi=HomeWiFi&db=-62&ip=192.168.0.188
```

HTML 文件用于设计预览；设备实际界面由 `main.lua` 使用 LVGL 绘制。

## 部署

将整个 package 内容复制到：

```text
/sd/apps/wifi_guide/
```

然后调用 `app.rescan()` 或重启设备。运行 app 后可按 HOME 键返回。
