# BiliBili

Bilibili account dashboard for HoloCubic, designed for a 320×240 display with tilt, Home button and controller navigation.

## 功能

- 粉丝总览、创作中心、最新投稿和直播状态。
- 未读消息统计、带缩略图的关注动态。
- 7 / 30 日数据趋势与最近 5 条视频观看记录。
- 未登录时自动生成二维码；保存登录信息并在下次启动时验证恢复。
- Web 控制页提供账号设置、数据概览和页面控制。

设备文字最小 12 像素。创作中心默认显示平台最近日统计；图片按当前浏览条目逐张下载并缓存，不等待全部图片加载。使用介绍见 [`package/info.html`](package/info.html)。

## 安装

将 `package/` 内的全部内容复制到设备的 `/sd/apps/bilibili/`，在 Launcher 重新扫描应用并启动 **BiliBili**。连接 Wi-Fi 后，用哔哩哔哩 App 扫描二维码确认登录。手机授权页面可能显示“云视听小电视”。

Web 控制页为 `http://<设备 IP>/bilibili/`，返回控制台指向同设备的 `/main`。不需要安装浏览器脚本。

## 操作

| 输入 | 功能 |
| --- | --- |
| 左右倾斜 / 手柄左右 | 切换页面 |
| 短前后倾 / 手柄上下 | 选择条目或趋势指标 |
| 长后倾 / A、Menu | 确认；切换统计口径或趋势周期 |
| 长前倾 / B、Select | 返回 |
| Home | 退出应用；编辑 UID 时取消 |

重感沿用 Launcher v1.30 的固件按键事件、长按重复节奏与 360 ms 切页动画。

## 数据与登录

“今日观测”从本机当天首次有效采样起计算，至少两次采样后显示，不等同于平台实时全日统计。观看历史展示平台已同步的记录，不代表实时播放状态。平台内部接口可能延迟更新或临时受限。

登录信息保存在设备 SD 卡，启动时验证有效性，主动退出时清除。不要公开共享设备的运行数据或将 SD 卡运行文件加入仓库。设备文件管理接口具有读取 SD 卡文件的能力，控制页适用于可信局域网。

本目录的安装包只包含应用源码、图标、字体与介绍页，不包含账号凭据、观看记录、缓存图片或设备截图。

## 字体

Noto Sans SC 字体按 SIL Open Font License 使用，许可见 [`package/font/OFL-NotoSansSC.txt`](package/font/OFL-NotoSansSC.txt)。

## English

Copy the contents of `package/` to `/sd/apps/bilibili/`, rescan apps and launch **BiliBili**. Scan the QR code with the Bilibili mobile app. The dashboard supports followers, creator statistics, uploads, live status, unread counts, following feed, trends and recent viewing history. Images load on demand. Saved sessions are validated on startup; no browser userscript is required.
