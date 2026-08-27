# General App Development Reference

[English](#general-app-development-reference) | [简体中文](#普通-app-开发参考)

This repository contains example Lua apps that can run directly from the device's SD card. The
`package/` directory of each app is its deployment package. Copy it to
`/sd/apps/<app-id>/` on the device, then rescan apps in Launcher to make it available.

See [README_LUA.md](README_LUA.md) for the underlying Lua module APIs and
[README_LVGL.md](README_LVGL.md) for the LVGL UI bindings. This document focuses on the
project structure, common API entry points, and debugging workflow most useful for DIY apps.

A typical app directory looks like this:

```text
my_app/
└── package/
    ├── app.info              # App metadata; required
    ├── main.lua              # Entry script; required; filename is set by entry in app.info
    ├── main.png              # App icon; recommended
    ├── info.html             # Description page shown in Launcher; recommended
    ├── font/                 # Font resources; optional
    ├── assets/               # Images, GIFs, audio, and other assets; optional
    └── modules/              # .so extension modules; optional
```

After deploying `package/`, the files are normally located at:

```text
/sd/apps/my_app/app.info
/sd/apps/my_app/main.lua
/sd/apps/my_app/main.png
```

## app.info

`app.info` is a simple `key = value` text file. Common fields are:

| Field | Description | Example |
| --- | --- | --- |
| `name` | Display name in Launcher | `name = Hello` |
| `entry` | Lua entry file | `entry = main.lua` |
| `icon` | App icon, normally stored in the package root | `icon = main.png` |
| `description` | Short description | `description = Minimal demo` |
| `version` | Version number | `version = 0.1.0` |
| `kind` | Runtime type: `app`, `service`, or `launcher`; `launcher` is reserved for Launcher | `kind = app` |
| `category` | Store category: `game`, `weather`, `clock`, `media`, or `tool` | `category = tool` |
| `catalog_scope` | Store scope: `official` or `community`; new community apps should use `community` | `catalog_scope = community` |
| `name_zh` / `name_zh_cn` | Simplified Chinese name and compatibility alias | `name_zh_cn = 示例` |
| `name_zh_tw` / `name_zh_hant` | Traditional Chinese name and compatibility alias | `name_zh_tw = 範例` |
| `name_en` / `name_ja` | English and Japanese names | `name_en = Example` |
| `description_zh*` / `description_en` / `description_ja` | Short descriptions for each language | `description_en = Minimal demo` |
| `allow_webui` | Whether a service may provide a WebUI | `allow_webui = true` |
| `autostart_service` | Whether a service starts automatically at boot or after a rescan | `autostart_service = true` |

Minimal regular app:

```ini
name = Hello
name_zh = 示例
name_zh_cn = 示例
name_zh_tw = 範例
name_zh_hant = 範例
name_en = Hello
name_ja = サンプル
kind = app
category = tool
catalog_scope = community
entry = main.lua
icon = main.png
description = Minimal DIY app
description_zh = 最小 DIY 应用示例
description_zh_cn = 最小 DIY 应用示例
description_zh_tw = 最小 DIY 應用程式範例
description_zh_hant = 最小 DIY 應用程式範例
description_en = Minimal DIY app
description_ja = 最小構成の DIY アプリ例
version = 0.1.0
```

For an auto-start service app, refer to `devtools/package/app.info`:

```ini
name = DevTools
name_zh_cn = 开发工具
name_zh_tw = 開發工具
name_en = DevTools
name_ja = 開発ツール
kind = service
category = tool
catalog_scope = official
entry = main.lua
allow_webui = true
autostart_service = true
description = Developer tools service
description_zh = 开发工具服务
description_zh_tw = 開發工具服務
description_en = Developer tools service
description_ja = 開発ツールサービス
version = 0.0.0
```

## API Overview

### App management

These are the APIs most commonly used by regular apps:

| API | Usage |
| --- | --- |
| `app.exiting()` | Check whether the app is exiting from inside a long-running loop |
| `app.exit()` | Request that the current app exit |
| `app.list()` | Get the app list |
| `app.current()` | Get information about the current app |
| `app.launch(id)` | Launch a specific app |
| `app.rescan()` | Rescan `/sd/apps` |
| `app.on(name, fn)` | Listen for app-level events such as `"key"` and `"imu"` |
| `app.route_base()` | Get the current app's WebUI route prefix; commonly used by services and web apps |

### Key input

| API/constant | Usage |
| --- | --- |
| `key.on(code, fn)` | Listen for one key |
| `key.on(fn)` | Listen for all keys |
| `key.off()` | Remove the key listeners registered by the current app |
| `key.LEFT/RIGHT/UP/DOWN/HOME` | Physical keys |
| `key.START/SHORT/LONG_START/LONG_REPEAT/LONG_END` | Key event types |

Example:

```lua
key.on(key.HOME, function(evt_type)
  if evt_type == key.SHORT then
    app.exit()
  end
end)
```

### Timers

| API/constant | Usage |
| --- | --- |
| `tmr.create()` | Create a timer |
| `timer:alarm(ms, mode, fn)` | Start a timer |
| `timer:stop()` | Stop a timer |
| `timer:unregister()` | Release a timer |
| `tmr.ALARM_SINGLE` | One-shot mode |
| `tmr.ALARM_AUTO` | Repeating mode |

### Files

| API | Usage |
| --- | --- |
| `file.listdir(path)` | List a directory |
| `file.stat(path)` | Get file or directory information |
| `file.getcontents(path)` | Read a text file or small file in one operation |
| `file.putcontents(path, data)` | Write a text file or small file in one operation |
| `file.open(path, mode)` | Stream file reads and writes |
| `file.mkdir/rmdir/remove/rename` | Directory and file operations |

Use explicit `/sd/...` paths, for example `/sd/apps/hello/config.json`.

### UI / LVGL

Lua code uses the global `lv_*` functions and `LV_*` constants directly. Common entry points are:

| API | Usage |
| --- | --- |
| `lv_scr_act()` | Get the current screen/root object |
| `lv_obj_clean(root)` | Clear the current screen |
| `lv_obj_create(parent)` | Create a container |
| `lv_label_create(parent)` | Create a label |
| `lv_img_create(parent)` / `lv_img_set_src(img, path)` | Display an image |
| `lv_canvas_create(parent, w, h, fmt)` | Create a drawing canvas |
| `lv_obj_set_style_*` | Set colors, opacity, borders, fonts, and other styles |
| `lv_anim_t()` + `lv_anim_start()` | Create and start animations |

See `README_LVGL.md` for more widgets, including button, table, list, tabview, chart, GIF,
and canvas APIs.

### Networking and services

| Module | Usage |
| --- | --- |
| `wifi` | Station/AP configuration, connections, and IP information |
| `http.get/post/request` | Send requests from the device to external APIs |
| `httpd.start/static/dynamic` | Provide an HTTP service from the device |
| `websocket` | WebSocket client |
| `mqtt` | MQTT client |
| `net` | TCP/UDP sockets |

HTTP request example:

```lua
http.get("https://example.com/", {}, function(code, body, headers)
  print("status", code)
  print(body or "")
end)
```

### Device and computation

| Module | Usage |
| --- | --- |
| `sys` | Brightness, CPU frequency, RGB LED, version, and resource usage |
| `time` | Local time, NTP, and time zones |
| `sjson` | JSON encoding and decoding |
| `zlib` | gzip, inflate, and crc32 |
| `np` | Arrays, matrices, and FFT |
| `viper` | Compile C-like functions for hot paths |
| `i2s` | Audio input and output |
| `nes` | NES emulator APIs |

## Minimal App Example

Create `hello/package/app.info`:

```ini
name = Hello
name_zh_cn = 示例
name_zh_tw = 範例
name_en = Hello
name_ja = サンプル
kind = app
category = tool
catalog_scope = community
entry = main.lua
icon = main.png
description = Minimal DIY app
description_zh = 最小 DIY 应用示例
description_zh_tw = 最小 DIY 應用程式範例
description_en = Minimal DIY app
description_ja = 最小構成の DIY アプリ例
version = 0.1.0
```

Create `hello/package/main.lua`:

```lua
local APP_KEY = "APP_HELLO"

local prev = rawget(_G, APP_KEY)
if prev and prev.stop then
  pcall(function()
    prev.stop("reload")
  end)
end

local APP = {
  tick = 0,
  timer = nil
}
_G[APP_KEY] = APP

local root = lv_scr_act()
lv_obj_clean(root)

local MAIN = LV_PART_MAIN | LV_STATE_DEFAULT

lv_obj_set_style_bg_color(root, 0x101820, MAIN)
lv_obj_set_style_bg_opa(root, 255, MAIN)

local title = lv_label_create(root)
lv_label_set_text(title, "Hello DIY App")
lv_obj_set_style_text_color(title, 0xFFFFFF, MAIN)
lv_obj_set_style_text_font(title, LV_FONT_MONTSERRAT_20, MAIN)
lv_obj_align(title, LV_ALIGN_CENTER, 0, -20)

local sub = lv_label_create(root)
lv_label_set_text(sub, "tick: 0")
lv_obj_set_style_text_color(sub, 0x8FD6FF, MAIN)
lv_obj_set_style_text_font(sub, LV_FONT_MONTSERRAT_16, MAIN)
lv_obj_align(sub, LV_ALIGN_CENTER, 0, 18)

APP.timer = tmr.create()
APP.timer:alarm(1000, tmr.ALARM_AUTO, function()
  APP.tick = APP.tick + 1
  lv_label_set_text(sub, "tick: " .. tostring(APP.tick))
end)

key.on(key.HOME, function(evt_type)
  if evt_type == key.SHORT then
    app.exit()
  end
end)

function APP.stop(reason)
  if APP.timer then
    pcall(function() APP.timer:stop() end)
    pcall(function() APP.timer:unregister() end)
    APP.timer = nil
  end

  pcall(function() key.off() end)

  if lv_obj_clean then
    pcall(function() lv_obj_clean(root) end)
  end

  if rawget(_G, APP_KEY) == APP then
    _G[APP_KEY] = nil
  end
end

APP.shutdown = APP.stop
```

After deployment, the directory should look like this:

```text
/sd/apps/hello/app.info
/sd/apps/hello/main.lua
/sd/apps/hello/main.png
```

Then rescan apps in Launcher. In the current Launcher, a short press on `DOWN` calls
`app.rescan()`. You can also restart the device or call `app.rescan()` from your own script.

## IP / DevTools Usage

### 1. Find the device IP address

After the device connects to Wi-Fi, use one of the following methods to find its IP address:

- Open the `Settings` app and view the Wi-Fi/IP information.
- Print it from Lua:

```lua
local ip, netmask, gateway = wifi.sta.getip()
print("device ip:", ip, netmask, gateway)
```

- Register a network connection event:

```lua
wifi.sta.on("got_ip", function(_, info)
  print("ip:", info.ip)
end)
```

The computer and the device must be on the same LAN. If the device IP is `192.168.0.140`,
open the following URL in a browser:

```text
http://192.168.0.140/devtools/
```

### 2. DevTools page

`devtools/package` is an auto-start service with the fixed `/devtools/` entry point. The
compatibility route `/codeeditor/` redirects to `/devtools/`.

Main features:

| Feature | Usage |
| --- | --- |
| File manager | Browse `/sd`, preview small text files and images, download, upload, rename, delete, and create directories |
| Upload app | Upload local files to `/sd/apps/<app-id>/` |
| App update | Restart the DevTools service and load the new `main.lua` from the SD card |
| DevRun | Edit `/sd/apps/devrun/main.lua` online |
| Save | Save DevRun code only |
| Run | Save the code and call `app.launch("devrun")` |

DevRun is suitable for quickly testing code. Once the code is ready, organize it into a separate
app directory with its own `app.info`.

### 3. DevTools HTTP API

Base prefix: `/devtools/api`

| Method | Path | Usage |
| --- | --- | --- |
| `GET` | `/info` | Service information, read chunk size, 64 MB transfer limit, and DevRun path |
| `GET` | `/list?path=/sd/apps` | List a directory |
| `GET` | `/stat?path=/sd/apps/hello/main.lua` | Get file or directory information |
| `GET` | `/read?path=...&offset=0&size=262144` | Read a file in chunks |
| `GET` | `/apps` | List editable SD-card apps |
| `GET` | `/code/read` | Read the DevRun `main.lua` |
| `POST` | `/mkdir?path=/sd/apps/hello` | Create a directory |
| `POST` | `/rename?path=...&new_path=...` | Rename or move a file/directory |
| `POST` | `/reload` | Return `202`, restart the DevTools service, and load the new `main.lua` |
| `POST` | `/code/save` | Save the request body to the DevRun `main.lua` |
| `POST` | `/code/run` | Save the request body and launch DevRun |
| `PUT` | `/upload?path=...&offset=0&total=123` | Legacy-compatible Lua chunked upload API |
| `DELETE` | `/remove?path=...` | Delete a file |
| `DELETE` | `/rmdir?path=...&recursive=1` | Delete a directory, optionally recursively |

Examples:

```bash
curl "http://192.168.0.140/devtools/api/list?path=/sd/apps"

curl -X POST \
  --data-binary @hello/package/main.lua \
  "http://192.168.0.140/devtools/api/code/run"
```

DevTools uploads use the firmware-native `PUT /api/system/fs/upload?path=...` endpoint directly.
Read APIs still return data in chunks, while browser downloads use file streaming; none of these
paths load a complete file into Lua memory. The legacy `/devtools/api/upload` endpoint remains
available for existing clients, but it passes request bodies through Lua and is slower than the
firmware-native endpoint. The maximum size of a single file is 64 MB.

When upgrading for the first time from an old version without `/reload`, restart the device once.
After that, use **App update** at the top of the page.

To upload a complete app, first create `/sd/apps/hello` from the DevTools page, then upload
`app.info`, `main.lua`, `main.png`, and other files. Finally, rescan the app list.

## DIY Notes

- Release resources before exit or reload: `timer:unregister()`, `key.off()`, and
  `app.on(name, nil)`.
- Do not block for long periods inside callbacks. Use `tmr` for periodic work and check
  `app.exiting()` inside long-running loops.
- After deployment, UI asset paths should use `/sd/apps/<app-id>/...`.
- After loading a font with `lv_font_load()`, release it with `lv_font_free()` when the app exits.
- Handle network and file I/O failures using the `value | nil, err` convention.
- `info.html` is the description page embedded in Launcher. See `info页面要求.md` for generation
  requirements.

## Reference Apps

| App | Good reference for |
| --- | --- |
| `2048/package` | Keys, animations, game state, and resource cleanup |
| `launcher/package` | `app.list()`, `app.launch()`, icon loading, and rescanning |
| `settings/package` | Wi-Fi/IP, device settings, and form-based UI |
| `devtools/package` | `httpd.dynamic()`, WebUI services, and file APIs |
| `weather/package` | HTTP requests, JSON, image/font assets, and complex UI |
| `mp3_player/package` | Audio modules, lists, lyrics, and resource scanning |
| `Spectrum/package` | `np`/FFT and real-time visual effects |

---

# 普通 app 开发参考

[English](#general-app-development-reference) | [简体中文](#普通-app-开发参考)

这个仓库是一组可直接放到设备 SD 卡运行的 Lua app 示例。每个 app 的 `package/`
目录就是部署包，通常复制到设备的 `/sd/apps/<app-id>/` 后，launcher 重扫即可显示。

底层 Lua 模块接口见 [README_LUA.md](README_LUA.md)，LVGL UI 绑定见
[README_LVGL.md](README_LVGL.md)。本文只写 DIY app 最常用的结构、接口入口和调试方式。


常见 app 目录：

```text
my_app/
└── package/
    ├── app.info              # app 元信息，必须
    ├── main.lua              # 入口脚本，必须，文件名由 app.info 的 entry 指定
    ├── main.png              # 图标，推荐
    ├── info.html             # launcher 内展示的介绍页，推荐
    ├── font/                 # 字体资源，可选
    ├── assets/               # 图片、GIF、音频等资源，可选
    └── modules/              # .so 扩展模块，可选
```

`package/` 部署到设备后路径一般是：

```text
/sd/apps/my_app/app.info
/sd/apps/my_app/main.lua
/sd/apps/my_app/main.png
```

## app.info

`app.info` 是简单的 `key = value` 文本。常用字段：

| 字段 | 说明 | 示例 |
| --- | --- | --- |
| `name` | launcher 显示名 | `name = Hello` |
| `entry` | 入口 Lua 文件 | `entry = main.lua` |
| `icon` | app 图标，通常放在 package 根目录 | `icon = main.png` |
| `description` | 简短说明 | `description = Minimal demo` |
| `version` | 版本号 | `version = 0.1.0` |
| `kind` | 运行形态：`app`、`service` 或 `launcher`；`launcher` 只用于启动器 | `kind = app` |
| `category` | 商店分类：`game`、`weather`、`clock`、`media` 或 `tool` | `category = tool` |
| `catalog_scope` | 商店归属：`official` 或 `community`；新社区应用应使用 `community` | `catalog_scope = community` |
| `name_zh` / `name_zh_cn` | 简体中文名称及兼容别名 | `name_zh_cn = 示例` |
| `name_zh_tw` / `name_zh_hant` | 繁体中文名称及兼容别名 | `name_zh_tw = 範例` |
| `name_en` / `name_ja` | 英文和日文名称 | `name_en = Example` |
| `description_zh*` / `description_en` / `description_ja` | 对应语言的简短说明 | `description_en = Minimal demo` |
| `allow_webui` | service 是否允许 WebUI | `allow_webui = true` |
| `autostart_service` | service 是否开机/扫描后自启动 | `autostart_service = true` |

最小普通 app：

```ini
name = Hello
name_zh = 示例
name_zh_cn = 示例
name_zh_tw = 範例
name_zh_hant = 範例
name_en = Hello
name_ja = サンプル
kind = app
category = tool
catalog_scope = community
entry = main.lua
icon = main.png
description = Minimal DIY app
description_zh = 最小 DIY 应用示例
description_zh_cn = 最小 DIY 应用示例
description_zh_tw = 最小 DIY 應用程式範例
description_zh_hant = 最小 DIY 應用程式範例
description_en = Minimal DIY app
description_ja = 最小構成の DIY アプリ例
version = 0.1.0
```

自启动服务 app 可参考 `devtools/package/app.info`：

```ini
name = DevTools
name_zh_cn = 开发工具
name_zh_tw = 開發工具
name_en = DevTools
name_ja = 開発ツール
kind = service
category = tool
catalog_scope = official
entry = main.lua
allow_webui = true
autostart_service = true
description = Developer tools service
description_zh = 开发工具服务
description_zh_tw = 開發工具服務
description_en = Developer tools service
description_ja = 開発ツールサービス
version = 0.0.0
```

## 接口列表

### app 管理

普通 app 最常用：

| 接口 | 用法 |
| --- | --- |
| `app.exiting()` | 长循环里判断 app 是否正在退出 |
| `app.exit()` | 请求退出当前 app |
| `app.list()` | 获取 app 列表 |
| `app.current()` | 获取当前 app 信息 |
| `app.launch(id)` | 启动指定 app |
| `app.rescan()` | 重新扫描 `/sd/apps` |
| `app.on(name, fn)` | 监听 app 级事件，如 `"key"`、`"imu"` |
| `app.route_base()` | 当前 app 的 WebUI 路由前缀，service/web app 常用 |

### key 按键

| 接口/常量 | 用法 |
| --- | --- |
| `key.on(code, fn)` | 监听单个按键 |
| `key.on(fn)` | 监听全部按键 |
| `key.off()` | 清除当前 app 注册的按键监听 |
| `key.LEFT/RIGHT/UP/DOWN/HOME` | 物理按键 |
| `key.START/SHORT/LONG_START/LONG_REPEAT/LONG_END` | 按键事件 |

示例：

```lua
key.on(key.HOME, function(evt_type)
  if evt_type == key.SHORT then
    app.exit()
  end
end)
```

### tmr 定时器

| 接口/常量 | 用法 |
| --- | --- |
| `tmr.create()` | 创建定时器 |
| `timer:alarm(ms, mode, fn)` | 启动定时器 |
| `timer:stop()` | 停止 |
| `timer:unregister()` | 释放 |
| `tmr.ALARM_SINGLE` | 单次 |
| `tmr.ALARM_AUTO` | 循环 |

### file 文件

| 接口 | 用法 |
| --- | --- |
| `file.listdir(path)` | 列目录 |
| `file.stat(path)` | 取文件/目录信息 |
| `file.getcontents(path)` | 一次性读文本/小文件 |
| `file.putcontents(path, data)` | 一次性写文本/小文件 |
| `file.open(path, mode)` | 流式读写 |
| `file.mkdir/rmdir/remove/rename` | 目录和文件操作 |

路径建议显式写 `/sd/...`，例如 `/sd/apps/hello/config.json`。

### UI / LVGL

Lua 里直接使用全局 `lv_*` 函数和 `LV_*` 常量。常用入口：

| 接口 | 用法 |
| --- | --- |
| `lv_scr_act()` | 当前屏幕/root |
| `lv_obj_clean(root)` | 清空当前屏幕 |
| `lv_obj_create(parent)` | 创建容器 |
| `lv_label_create(parent)` | 创建文本 |
| `lv_img_create(parent)` / `lv_img_set_src(img, path)` | 图片 |
| `lv_canvas_create(parent, w, h, fmt)` | canvas 绘制 |
| `lv_obj_set_style_*` | 设置颜色、透明度、边框、字体等 |
| `lv_anim_t()` + `lv_anim_start()` | 动画 |

更多控件如 button、table、list、tabview、chart、gif、canvas 见 `README_LVGL.md`。

### 网络和服务

| 模块 | 用法 |
| --- | --- |
| `wifi` | Station/AP 配置、连接、查 IP |
| `http.get/post/request` | 设备主动请求外部接口 |
| `httpd.start/static/dynamic` | 设备提供 HTTP 服务 |
| `websocket` | WebSocket client |
| `mqtt` | MQTT client |
| `net` | TCP/UDP socket |

HTTP 请求示例：

```lua
http.get("https://example.com/", {}, function(code, body, headers)
  print("status", code)
  print(body or "")
end)
```

### 设备和计算

| 模块 | 用法 |
| --- | --- |
| `sys` | 亮度、CPU 频率、RGB LED、版本/资源占用 |
| `time` | 本地时间、NTP、时区 |
| `sjson` | JSON 编解码 |
| `zlib` | gzip/inflate/crc32 |
| `np` | 数组、矩阵、FFT |
| `viper` | 热路径 C-like 函数编译 |
| `i2s` | 音频输入输出 |
| `nes` | NES 模拟器接口 |

## 最简 app 示例

新建 `hello/package/app.info`：

```ini
name = Hello
name_zh_cn = 示例
name_zh_tw = 範例
name_en = Hello
name_ja = サンプル
kind = app
category = tool
catalog_scope = community
entry = main.lua
icon = main.png
description = Minimal DIY app
description_zh = 最小 DIY 应用示例
description_zh_tw = 最小 DIY 應用程式範例
description_en = Minimal DIY app
description_ja = 最小構成の DIY アプリ例
version = 0.1.0
```

新建 `hello/package/main.lua`：

```lua
local APP_KEY = "APP_HELLO"

local prev = rawget(_G, APP_KEY)
if prev and prev.stop then
  pcall(function()
    prev.stop("reload")
  end)
end

local APP = {
  tick = 0,
  timer = nil
}
_G[APP_KEY] = APP

local root = lv_scr_act()
lv_obj_clean(root)

local MAIN = LV_PART_MAIN | LV_STATE_DEFAULT

lv_obj_set_style_bg_color(root, 0x101820, MAIN)
lv_obj_set_style_bg_opa(root, 255, MAIN)

local title = lv_label_create(root)
lv_label_set_text(title, "Hello DIY App")
lv_obj_set_style_text_color(title, 0xFFFFFF, MAIN)
lv_obj_set_style_text_font(title, LV_FONT_MONTSERRAT_20, MAIN)
lv_obj_align(title, LV_ALIGN_CENTER, 0, -20)

local sub = lv_label_create(root)
lv_label_set_text(sub, "tick: 0")
lv_obj_set_style_text_color(sub, 0x8FD6FF, MAIN)
lv_obj_set_style_text_font(sub, LV_FONT_MONTSERRAT_16, MAIN)
lv_obj_align(sub, LV_ALIGN_CENTER, 0, 18)

APP.timer = tmr.create()
APP.timer:alarm(1000, tmr.ALARM_AUTO, function()
  APP.tick = APP.tick + 1
  lv_label_set_text(sub, "tick: " .. tostring(APP.tick))
end)

key.on(key.HOME, function(evt_type)
  if evt_type == key.SHORT then
    app.exit()
  end
end)

function APP.stop(reason)
  if APP.timer then
    pcall(function() APP.timer:stop() end)
    pcall(function() APP.timer:unregister() end)
    APP.timer = nil
  end

  pcall(function() key.off() end)

  if lv_obj_clean then
    pcall(function() lv_obj_clean(root) end)
  end

  if rawget(_G, APP_KEY) == APP then
    _G[APP_KEY] = nil
  end
end

APP.shutdown = APP.stop
```

部署后目录应类似：

```text
/sd/apps/hello/app.info
/sd/apps/hello/main.lua
/sd/apps/hello/main.png
```

然后在 launcher 中重扫 app。当前 launcher 里短按 `DOWN` 会调用 `app.rescan()`；也可以重启设备或用自己的脚本调用 `app.rescan()`。

## IP / DevTools 用法

### 1. 找设备 IP

设备连接 WiFi 后，可以用以下方式确认 IP：

- 打开 `Settings` app，查看 WiFi/IP 信息。
- 在 Lua 里打印：

```lua
local ip, netmask, gateway = wifi.sta.getip()
print("device ip:", ip, netmask, gateway)
```

- 注册联网事件：

```lua
wifi.sta.on("got_ip", function(_, info)
  print("ip:", info.ip)
end)
```

电脑和设备需要在同一个局域网。假设设备 IP 是 `192.168.0.140`，浏览器访问：

```text
http://192.168.0.140/devtools/
```

### 2. DevTools 页面

`devtools/package` 是自启动 service，入口固定为 `/devtools/`。兼容入口
`/codeeditor/` 会跳转到 `/devtools/`。

页面主要功能：

| 功能 | 用法 |
| --- | --- |
| 文件管理 | 浏览 `/sd`、预览小文本/图片、下载、上传、重命名、删除、建目录 |
| 上传 app | 把本地文件上传到 `/sd/apps/<app-id>/` |
| 应用更新 | 重新启动 DevTools service，读取 SD 卡上的新版 `main.lua` |
| DevRun | 在线编辑 `/sd/apps/devrun/main.lua` |
| Save | 只保存 DevRun 代码 |
| Run | 保存并 `app.launch("devrun")` |

DevRun 适合快速试代码；确认后再整理成独立 app 目录和 `app.info`。

### 3. DevTools HTTP API

基础前缀：`/devtools/api`

| 方法 | 路径 | 用法 |
| --- | --- | --- |
| `GET` | `/info` | 服务信息、读取 chunk 大小、64MB 文件传输上限、DevRun 路径 |
| `GET` | `/list?path=/sd/apps` | 列目录 |
| `GET` | `/stat?path=/sd/apps/hello/main.lua` | 文件/目录信息 |
| `GET` | `/read?path=...&offset=0&size=262144` | 分片读取文件 |
| `GET` | `/apps` | 可编辑 SD app 列表 |
| `GET` | `/code/read` | 读取 DevRun main.lua |
| `POST` | `/mkdir?path=/sd/apps/hello` | 创建目录 |
| `POST` | `/rename?path=...&new_path=...` | 重命名/移动 |
| `POST` | `/reload` | 返回 `202` 后重新启动 DevTools service 并加载新版 `main.lua` |
| `POST` | `/code/save` | 保存请求 body 到 DevRun main.lua |
| `POST` | `/code/run` | 保存请求 body 并启动 DevRun |
| `PUT` | `/upload?path=...&offset=0&total=123` | 兼容旧客户端的 Lua 分块上传接口 |
| `DELETE` | `/remove?path=...` | 删除文件 |
| `DELETE` | `/rmdir?path=...&recursive=1` | 删除目录，可递归 |

示例：

```bash
curl "http://192.168.0.140/devtools/api/list?path=/sd/apps"

curl -X POST \
  --data-binary @hello/package/main.lua \
  "http://192.168.0.140/devtools/api/code/run"
```

DevTools 上传直接使用固件原生 `PUT /api/system/fs/upload?path=...`，读取 API
仍按块返回，浏览器下载走文件流；这些路径都不会把完整文件一次性读入 Lua 内存。
旧 `/devtools/api/upload` 仍可用于已有客户端，但经过 Lua 请求体通道，速度低于固件原生接口。
单文件最大 64MB。
首次从不含 `/reload` 的旧版升级时仍需重启设备一次；此后可使用页面顶部的“应用更新”。

上传完整 app 时，推荐先在 DevTools 网页里创建 `/sd/apps/hello`，再上传
`app.info`、`main.lua`、`main.png` 等文件，最后重扫 app 列表。

## DIY 注意事项

- 退出或重载前释放资源：`timer:unregister()`、`key.off()`、`app.on(name, nil)`。
- 回调里不要长时间阻塞；周期任务用 `tmr`，长循环里检查 `app.exiting()`。
- UI 资源路径部署后使用 `/sd/apps/<app-id>/...`。
- 字体用 `lv_font_load()` 加载后，退出时用 `lv_font_free()` 释放。
- 网络请求、文件读写建议按 `value | nil, err` 风格处理失败。
- `info.html` 是 launcher 嵌入说明页，生成要求见 `info页面要求.md`。

## 可参考示例

| app | 适合参考 |
| --- | --- |
| `2048/package` | 按键、动画、游戏状态、资源释放 |
| `launcher/package` | `app.list()`、`app.launch()`、图标加载、重扫 |
| `settings/package` | WiFi/IP、设备设置、表单式 UI |
| `devtools/package` | `httpd.dynamic()`、WebUI service、文件 API |
| `weather/package` | HTTP 请求、JSON、图片/字体资源、复杂 UI |
| `mp3_player/package` | 音频模块、列表、歌词/资源扫描 |
| `Spectrum/package` | `np`/FFT、实时视觉效果 |
