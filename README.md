# 开源 APP 集合（Cubic 320x240）

本仓库用于管理 320x240 嵌入式屏幕上的 Lua + LVGL 应用，按“一个 app 一个目录”的方式组织。  
每个可安装的 app 目录内应包含标准元信息文件 `app.info`，并使用主入口脚本运行。

## 仓库结构

- 顶层每个子目录通常代表一个 app。
- 每个 App 目录内建议包含：
  - `app.info`（必需）
  - 对应入口 Lua 文件（`main.lua` 或自定义入口）
- 非 app 目录（如 `tools`）用于开发脚本/运行依赖，不应直接作为启动应用。

## app.info 规范

项目中所有 app 都遵循以下最小字段：

- `name`：启动器显示名
- `entry`：入口文件名，必须存在
- `description`：一句话功能说明

示例：

```ini
name = Clock
entry = main.lua
description = Minimal analog clock
```

服务类应用可包含：

- `kind = service`
- `allow_webui = true`
- `autostart_service = true`

## 当前 app 列表

- `2048`（`main.lua`）：2048 game
- `BTC`（`main.lua`）：Real-time viewing of digital currencies
- `clock`（`main.lua`）：Minimal analog clock
- `codex_buddy`（`main.lua`）：Codex desktop buddy
- `ConwayLife`（`main.lua`）：Game of Life screensaver
- `devtools`（`main.lua`）：Developer tools service
- `FireSand`（`main.lua`）：Falling-sand style fire cellular simulation
- `FluidPendant`（`main.lua`）：FLIP-style electronic liquid pendant
- `hwmon`（`main.lua`）：Desktop hardware monitor
- `lv-benchmark`（`main.lua`）：lvgl benchmark
- `MatrixRain`（`main.lua`）：Matrix code rain effect
- `mini_claw`（`main.lua`）：Minimal ESP-Claw style chat agent
- `nesgame`（`main.lua`）：nesgame v1.0 use XBOX pad
- `NixieClock`（`main.lua`）：Nixie style retro clock
- `photos`（`photos.lua`）：Play photos
- `plane`（`main.lua`）：plane war game
- `settings`（`main.lua`）：Device settings
- `Spectrum`（`main.lua`）：Real-time Spectrum Special effects
- `videos`（`videos.lua`）：play gif videos
- `voice_ai`（`main.lua`）：Voice assistant with desktop OpenAI bridge
- `weather`（`main.lua`）：Weather card


## 说明文档入口

- `README_LUA.md`
- `README_LVGL.md`
- `html-ui.md`
- `lua_app.md`
- 各 app 目录可选补充自己的 `README.md`
