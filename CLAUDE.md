# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 仓库定位

HoloCubic（ESP32-S3，320×240 屏）**Lua app 集合**，不是固件仓库。每个顶层目录是一个 app，
其中 `package/` 就是部署包：复制到设备 `/sd/apps/<app-id>/` 后，launcher 重扫即可显示。
固件本体（Lua 运行时、LVGL 绑定、dynmod loader）在另一个工程里，本仓库只写 Lua 脚本、
少量 C 动态模块（`.so`）和资源。

## 目录约定

- `<app>/package/` — 唯一的部署产物。`app.info`（元信息，必须）+ `entry` 指定的入口 Lua
  （多为 `main.lua`，`photos`/`videos` 是 `photos.lua`/`videos.lua`）+ `main.png` 图标 +
  `info.html`（launcher 内嵌介绍页）+ 可选 `font/`、`assets/`、`modules/`。
- `<app>/src/` — C 动态模块（`.so`）的 ESP-IDF 工程源码，**绝不部署到设备**
  （见 `xiaozhi/src/AGENTS.md`、`mp3_player/src/AGENTS.md`）。
- `<app>/tests/`、`<app>/tools/` — 主机侧（PC）测试与资源生成脚本。
- `tools/` — 跨 app 的 i18n 字符集/字体生成。
- 例外：`weather/` 根目录还留着一份旧快照（`app.info` version 0.0.0），部署以
  `weather/package/`（version 1.14）为准。

## 部署与调试（DevTools 工作流）

设备端没有串口烧写这一步——改 Lua 就是往 SD 卡传文件。`devtools/package` 是
`kind = service` + `autostart_service = true` 的常驻服务，入口固定 `/devtools/`：

```bash
# 列目录
curl "http://<device-ip>/devtools/api/list?path=/sd/apps"
# 存 + 跑 DevRun 草稿（/sd/apps/devrun/main.lua）
curl -X POST --data-binary @hello/package/main.lua "http://<device-ip>/devtools/api/code/run"
# 改完 devtools 自身后热重载（202 Accepted，不重启设备）
curl -X POST "http://<device-ip>/devtools/api/reload"
```

上传走固件原生 `PUT /api/system/fs/upload?path=...`（单文件上限 64MB）；旧
`PUT /devtools/api/upload` 仍兼容但慢。完整 API 表见 `README.md`。
新装 app 后需 `app.rescan()`（launcher 里短按 `DOWN`）。

## 构建命令

### C 动态模块（`.so`）

用 ESP-IDF（PlatformIO 自带的那套），**只 build `so` target，不编译整个固件**：

```powershell
cmake -S <app>/src -B <app>/src/build -G Ninja -DIDF_TARGET=esp32s3
cmake --build <app>/src/build --target so --config Release
```

- `aida_monitor/src` → `aida_font.so`（ESP-IDF 5.5.2，stb_truetype 字形栅格化）
- `mp3_player/src` → `audio.so`（额外要 `-DPYTHON="$env:PYTHON" -DPYTHON_DEPS_CHECKED=1`）
- `xiaozhi/src` → `xiaozhi.so`（Opus 编解码）、`xiaozhi/src/wake` → `wake.so`（WakeNet9s）
- 头文件解析顺序见 `xiaozhi/src/CMakeLists.txt`：`-DMODULE_ABI_DIR=`、`$CUBICLUA_ROOT/src/dynmod`、
  同目录 vendored `module_abi.h`。
- 产物要手动拷回 `package/modules/`（或 `package/*.so`）再部署。
- 各 `src/README.md` 里的构建命令是 Windows PowerShell + `E:\cubicsrc\...` 绝对路径，
  在 Linux 上要自己换 `IDF_PATH`/`IDF_TOOLS_PATH`/工具链路径。

### 资源生成

```powershell
# 多语言字符集 + LVGL 字体（launcher / BTC / weather 的 zh_cn/zh_tw/ja bin）
python tools/generate_i18n_charsets.py
pwsh tools/build_i18n_fonts.ps1            # 需要 node + lv_font_conv，路径可用 -ConverterPath 覆盖
# AIDA Monitor 的 GB2312 子集 TTF
python aida_monitor/tools/build_vector_font.py NotoSansSC-wght.ttf
# WakeNet9s SD 卡模型目录
pwsh xiaozhi/src/wake/build_sd_models.ps1
```

## 测试

主机侧跑 Lua，无设备也能验证纯逻辑模块：

```bash
# AIDA64 RemoteSensor 协议/布局解析（必须在仓库根目录跑，脚本用相对路径 dofile）
npx -y -p fengari-node-cli fengari aida_monitor/tests/protocol_test.lua
# 语法检查
npx -y luaparse -q aida_monitor/package/aida_layout.lua
# DevTools reload 生命周期（mock 掉 app/file/httpd/tmr 全局）
lua devtools/tests/reload_api_test.lua devtools/package/main.lua
# 本机没装 lua 时用 fengari 跑同一个文件（已验证可跑通）
npx -y -p fengari-node-cli fengari devtools/tests/reload_api_test.lua devtools/package/main.lua
```

`aida_monitor/tools/render_layout_previews.py` 可在 PC 上按 1:1 320×240 渲染布局预览，
支持 `--aida <url>` 拉真实 AIDA64、`--device <url>` 从设备管理接口发现 host。

`devtools/tests/reload_api_test.lua` 现在只断言 `DEVTOOLS.VERSION` 是非空字符串（2026-07-29 改；原来硬编码
`...-v6`，而 `main.lua` 已是 `...-v7`，每次 bump 版本都会假失败）——别把具体版本号写回断言。

## 架构要点

### launcher / app / service 三者关系

- `launcher/package` 是桌面 app：读 `app.list()` 渲染图标转盘、`app.launch(id)` 拉起 app、
  从 `/sd/apps/settings.json` 读 `language` 决定 UI 语言和字体，并把自带的
  `services/display_schedule/`（息屏与闹钟）安装/升级到 `/sd/apps/display_schedule` 后
  `app.start_service()`。它还负责 `httpd.start({ max_handlers = 256 })` 抬高全局 HTTP handler 容量。
- `kind = app`：前台独占，同一时刻只有一个，退出回 launcher。
- `kind = service`：后台常驻（`devtools`、`xiaozhi-service`、`display_schedule`）。
  `autostart_service = true` 的服务被停掉后应用管理器约 2 秒会再拉起——要长期停用得改 manifest。
  服务画浮层用 `service_ui.acquire/show/hide`（见 `xiaozhi-service/package/service_ui.lua`），
  不能直接抢前台 LVGL 屏幕。

### Lua app 的单例 + 可重载生命周期

这是全仓库最重要的约定（`README.md` 有完整模板）：入口脚本会被**重复执行**（热重载），
所以每个 app 把状态挂在一个全局 key 上，脚本开头先把上一代实例 `stop()` 掉：

```lua
local prev = rawget(_G, "APP_HELLO")
if prev and prev.stop then pcall(prev.stop, "reload") end
```

`APP.stop(reason)` 里必须释放：`timer:stop()/unregister()`、`key.off()`、`app.on(name, nil)`、
`ipc.listen(ep, nil)`、`lv_font_free()`、`lv_obj_clean(root)`，最后清掉全局 key
（`APP.shutdown = APP.stop` 是惯例别名）。漏释放会在下次进入 app 时表现为定时器叠加、
按键重复响应或 I2S 被占用。

### WebUI

app 通过 `app.route_base()` 拿到自己的路由前缀（如 `/aida_monitor`），用 `httpd.dynamic(method, path, fn)`
注册；固件靠是否存在 `route_base .. "/"` 首页路由来判定该 app「有 WebUI」。`app.info` 里
`allow_webui = true` 用于 service。大 app 把这部分拆成独立 `web.lua`
（`aida_monitor`、`holo_pc_monitor`、`BTC`、`xiaozhi-service`），静态页面放 `main.html`。

### Host ABI 动态模块

`package/modules/*.so` 用 `require("/sd/apps/<app>/modules/x.so")` 显式绝对路径加载。
四个导出符号 `module_query_v1 / module_create_v2 / module_luaopen_v1 / module_destroy_v1`，
生命周期 `query → create → luaopen → destroy → dlclose`。当前
`MODULE_SDK_VERSION == 0x00030000`；Host API 按 `MODULE_PROC_*` ID 逐项解析，
`socket/netif/mdns/ble/dir/sync` 等分组是 optional，**用前必须判空函数指针**。
完整说明见 `README_HOST_ABI.md`；权威头文件是固件工程的 `src/dynmod/module_abi.h`，
仓库内 vendored 副本可能落后。

### 设备侧 Lua 环境

模块（`tmr`/`file`/`wifi`/`http`/`httpd`/`net`/`mqtt`/`sjson`/`np`/`viper`/`key`/`sys`/`app`/`i2s`/`nes`）
已注册为全局表，无需 `require`。风格贴近 NodeMCU ESP32；LVGL 以 `lv_*` 全局函数 + 整数
`obj_id` 暴露（`0` 是 root）。回调都在 Lua 运行时里跑，不能长阻塞；周期任务用 `tmr`，
长循环查 `app.exiting()`。接口清单见 `README_LUA.md`（Lua 模块）和 `README_LVGL.md`（LVGL 绑定）。

### i18n

语言由 `/sd/apps/settings.json` 的 `language`/`locale`/`lang` 决定，归一化到
`zh-CN`/`zh-TW`/`ja`/`en` 四档（`launcher/package/main.lua`、`BTC/package/i18n.lua` 同一套逻辑）。
`app.info` 支持 `name_zh_cn`/`name_zh_tw`/`name_ja`/`name_en` 与 `description_*` 变体。
每档语言对应一个预生成的 LVGL `.bin` 子集字体，新增中文文案后要重跑 `tools/` 里的字体流程，
否则字形缺失显示成方框。

## 注意事项

- 设备上的用户配置（`config.json`、`service.json`）不入库，只提交 `*.example.json`；
  `xiaozhi-service/package/` 里现存的 `config.json`/`service.json` 属历史遗留。
- `info页面要求.md`（info.html 生成规范）和 `.agents/` 被 `.gitignore` 排除，仓库里看不到。
- commit message 用 `type(scope): summary` 英文小写（`feat(launcher):`、`fix(ticker):`、`release(devtools):`）。
- app 版本号在 `app.info` 的 `version`，改行为时要一并更新，launcher 和 WebUI 都会显示。
