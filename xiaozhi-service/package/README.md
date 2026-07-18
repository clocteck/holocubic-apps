# XiaoZhi Service

这是裁剪移植官方 `xiaozhi-esp32` 的 Lua 版应用层。`xiaozhi-service`
作为 `xiaozhi` 的扩展服务运行：服务持有唤醒、音频、激活、协议、MCP
等非 UI 资源。前台 App UI 从 `/sd/apps/xiaozhi/ui` 读取，后台悬浮 UI 从
`/sd/apps/xiaozhi-service/ui` 读取。

## 单 Service 模式

当前包以 `kind = service` 运行，唤醒、联网对话、MCP、录音和播放都在同一个 Lua
runtime 内完成。空闲时不显示界面；检测到唤醒词后通过 `xiaozhi-service/ui.lua`
进入 UI 驱动，再按 `ui_type` 加载 `/sd/apps/xiaozhi-service/ui/<type>.lua`
呈现悬浮 UI，回到空闲状态后自动隐藏。Launcher 使用
`/sd/apps/xiaozhi-service/service.json` 启停服务并读取音频资源冲突黑名单。
`ui_mode` 控制唤醒后的 UI 呈现：

- `"app"`：唤醒时记录当前前台应用并启动 `/sd/apps/xiaozhi`，前台 app 只通过 IPC 呈现 UI；对话回到待命后自动跳回唤醒前应用。
- `"floating"`：服务通过 `xiaozhi-service/ui.lua` 进入 UI 驱动，加载 `/sd/apps/xiaozhi-service/ui/<type>.lua`，并用固件 `service_ui` API 绘制悬浮 UI；服务启动时不显示，只有唤醒、验证码、对话或错误时显示。

`deny_apps` 中的前台应用会独占性能、麦克风或扬声器。启动这些应用前 Launcher 会停止
小智服务；绕过 Launcher 启动时，小智也会检测真实前台应用并自行退出。返回 Launcher
后，只要 `enabled` 仍为 `true`，服务会自动恢复。MCP 的应用校验、结果返回和延迟启动
流程保持不变。

## API 配置

设备端不直接填写 OpenAI / DeepSeek API Key。小智协议要求设备连接“小智服务端”，由服务端配置 ASR、LLM、TTS 的 API Key。

`xiaozhi-service` 不再保存协议配置。`websocket.url/token/version`、`ota`、音量、唤醒词和主应用 UI 风格都读取并写回主应用配置：

```text
/sd/apps/xiaozhi/config.json
```

服务目录只保留服务配置：

```text
/sd/apps/xiaozhi-service/service.json
```

`service.json` 只控制后台服务开关、后台 UI 呈现模式、后台 UI 类型和资源冲突黑名单；不要在这里放 token、音量或小智协议参数。

示例文件见 `/sd/apps/xiaozhi-service/service.example.json`；设备实际读取
`/sd/apps/xiaozhi-service/service.json`。示例：

```json
{
  "enabled": true,
  "ui_mode": "app",
  "ui_type": "window",
  "ui_character": "xiaozhi_chibi",
  "deny_apps": {
    "videos": true,
    "holo-retro-go": true,
    "mp3_player": true,
    "Spectrum": true,
    "2048": true
  }
}
```

字段说明：

- `enabled`：是否允许后台唤醒服务运行。
- `ui_mode`：`"app"` 表示唤醒后打开小智前台 App；`"floating"` 表示使用悬浮 UI。
- `ui_type`：后台悬浮 UI 类型，对应 `/sd/apps/xiaozhi-service/ui/<type>.lua`。当前内置 `window` 小窗模式、`subtitle` 字幕模式、`wechat` 微信气泡、`assistant` 助手形象。
- `ui_character`：`assistant` 样式使用的角色资源名，对应 `/sd/apps/xiaozhi-service/ui/character/<name>.rgb565`。
- `deny_apps`：这些前台应用运行时暂停或停止小智服务，避免音频、性能或输入冲突。

服务 WebUI 提供两个 UI 配置区：

- “主应用 UI”：写入 `/sd/apps/xiaozhi/config.json` 的 `ui.type`，控制前台小智 App。
- “启用后台唤醒”：写入 `/sd/apps/xiaozhi-service/service.json` 的 `enabled`。关闭后立即停止后台唤醒监听和当前后台对话；再次开启后在空闲状态恢复唤醒监听。
- “后台服务 UI”：写入 `/sd/apps/xiaozhi-service/service.json` 的 `ui_mode`、`ui_type` 和 `ui_character`，控制后台唤醒后打开 App 还是使用悬浮 UI。
- “退避 App”：写入 `/sd/apps/xiaozhi-service/service.json` 的 `deny_apps`。勾选的 App 在前台运行时会暂停小智后台唤醒/音频，避免音频、性能或输入冲突。
- “自定义服务”：写入 `/sd/apps/xiaozhi/config.json` 的 `ota.url` 和可选 `websocket.url/token/version`。这里只要求 OTA 地址必填；WebSocket 地址可留空，由 OTA 激活流程下发。

## 回复流程

1. `wake.so` 检测到 `你好小智`。
2. Lua 进入 `connecting`，按官方 WebSocket 协议发送 hello。
3. 服务端返回 `session_id` 后，Lua 发送 `listen.detect/start`。
4. 麦克风 PCM 经 `xiaozhi.so` 编成 Opus，通过 WebSocket 发给服务端。
5. 服务端返回 STT/LLM/TTS 文本事件和二进制 Opus。
6. Lua 解码 Opus，写入独占 I2S 扬声器输出。

## 设备控制

连接建立后，小智会通过 MCP 向服务端公布默认插件里的以下工具：

- `device.get_status`：查询设备、网络和内存状态。
- `device.list_apps`：列出设备上已安装的应用。
- `device.launch_app`：按应用 ID 启动应用；应用 ID 会先与本机安装列表校验。
- `device.sync_time`：通过 NTP 立即同步系统时间。
- `device.set_brightness`：设置屏幕亮度，范围 `0` 到 `100`。
- `device.set_wifi_ap`：开启或关闭 Wi-Fi AP 热点模式。
- `device.set_bluetooth`：开启或关闭蓝牙手柄服务，并返回当前蓝牙状态。

服务端必须支持小智协议的 MCP 消息转发，并在智能体中启用设备工具调用。启动应用会在工具结果发回后延迟执行，避免切换应用导致应答丢失。

### MCP 插件

默认工具也以插件形式放在 `xiaozhi/mcp/device.lua`。启动时会扫描：

```text
/sd/apps/xiaozhi/mcp/*.lua
```

每个插件文件应 `return` 一个 table。文件名只允许字母、数字、下划线、点和横线，并以 `.lua` 结尾；`init.lua` 会被忽略。插件工具名不能和默认工具或其他插件重复。

最小插件示例：

```lua
return {
  tool = {
    name = "demo.ping",
    description = "返回一个测试响应。",
    inputSchema = {
      type = "object",
      properties = {},
      additionalProperties = false,
    },
  },
  call = function(arguments, ctx)
    return { ok = true, message = "pong" }
  end,
}
```

一个文件也可以注册多个工具：

```lua
return {
  tools = {
    {
      name = "demo.echo",
      description = "回显文本。",
      inputSchema = {
        type = "object",
        properties = {
          text = { type = "string", description = "要回显的文本" },
        },
        required = { "text" },
        additionalProperties = false,
      },
    },
  },
  handlers = {
    ["demo.echo"] = function(arguments, ctx)
      return { text = tostring(arguments.text or "") }
    end,
  },
}
```

插件 handler 返回普通 Lua table 时，小智会自动编码为 MCP text 结果；也可以直接返回 `{ content = ... }` 形式的 MCP 结果。返回 `false, "错误信息"` 或抛出异常会被转换成 MCP 错误结果。handler 第二个参数 `ctx` 包含 `cfg`、`text_result`、`error_result` 等辅助对象。

## 本地资源布局

部署时复制整个 `package/` 到 `/sd/apps/xiaozhi-service/`。服务包只保留服务壳、
配置、Web 管理、IPC runtime 和服务专属 MCP 插件。小智公共逻辑和 native 资源从
`/sd/apps/xiaozhi/` 读取：

```text
/sd/apps/xiaozhi/audio.lua
/sd/apps/xiaozhi/protocol.lua
/sd/apps/xiaozhi/activation.lua
/sd/apps/xiaozhi/mcp.lua
/sd/apps/xiaozhi/xiaozhi.so
/sd/apps/xiaozhi/wake.so
/sd/apps/xiaozhi/wake/wn9s_nihaoxiaozhi/*
```

## UI 资源和插件化适配

小智 UI 分为两个插件域：

```text
/sd/apps/xiaozhi/ui/<type>.lua                 # 前台 App UI
/sd/apps/xiaozhi-service/ui/<type>.lua         # 后台悬浮 UI
/sd/apps/xiaozhi-service/ui/character/*.rgb565 # 助手形象角色
/sd/apps/xiaozhi/assets/fonts/xiaozhi_common3500_16.bin
```

WebUI 会扫描 `/sd/apps/xiaozhi/ui/*.lua` 生成“主应用 UI”选项，并过滤 `driver.lua`、`headless.lua`。WebUI 会扫描 `/sd/apps/xiaozhi-service/ui/*.lua` 生成“悬浮界面类型”选项，文件名就是 `ui_type`。

当前内置后台悬浮 UI：

- `window`：小窗模式，显示在右下角。
- `subtitle`：电影字幕模式，底部横向字幕条，只显示最新字幕文本。
- `wechat`：微信气泡模式，屏幕底部只显示最新一条气泡消息。
- `assistant`：助手形象模式，左侧角色图像加右侧气泡。

后台悬浮 UI 插件文件应返回 `{ new = function(cfg) ... end }`。对象方法和前台 UI 相同，但渲染方式应使用固件全局 `service_ui` 申请小画布，而不是清空整屏 LVGL：

```lua
return {
  new = function(cfg)
    local self = { canvas = nil }

    function self:setup()
      -- 可在这里加载字体或缓存资源。
    end

    function self:set_chat_message(role, content)
      -- 只在有内容时 acquire/show，空闲时不要占用悬浮层。
    end

    function self:on_state(state, old_state)
      -- idle 时通常 hide/release。
    end

    function self:stop(reason)
      -- 释放 timer、font 和 service_ui canvas。
    end

    return self
  end,
}
```

悬浮 UI 的常用方法包括 `setup`、`stop`、`on_state`、`set_status`、`show_notification`、`set_emotion`、`set_chat_message`、`clear_chat_messages`、`alert`、`set_metrics`。如果实现 `handle_event(event, payload)` 并返回 `true`，驱动会认为事件已处理。

角色资源只对 `assistant` 样式生效。添加角色时放入：

```text
/sd/apps/xiaozhi-service/ui/character/<name>.rgb565
```

文件名同样只允许字母、数字、下划线、点和横线。WebUI 会自动列出所有 `.rgb565` 角色并保存到 `service.json` 的 `ui_character`。

前台 UI 模式由 `xiaozhi/ui_ipc.lua` 通过 `xiaozhi-service` IPC endpoint
订阅服务快照并发送控制命令；`_G.XIAOZHI_SERVICE` 仅作为同状态机快速路径。
UI 同步不使用 HTTP。
