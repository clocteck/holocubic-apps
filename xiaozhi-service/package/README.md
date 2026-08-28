# XiaoZhi Service

Wake-word capture runs in `xzwk.so`'s native capture task when available, so WakeNet inference does not block Lua timers or HTTP handlers. The foreground XiaoZhi App and this service keep separate runtime globals and use distinct dynamic-module basenames; closing either runtime cannot unload native code still used by the other one.

The checked-in `xzwk.so` reuses the prebuilt wake implementation with a service-only module identity. Its compiled model base is `/sd/apps/xiaozhi/wake`. During initialization the service checks the three WakeNet model files there and copies any missing files from its own package. This creates only the native model cache path; it does not load foreground-app Lua or configuration.

这是裁剪移植官方 `xiaozhi-esp32` 的 Lua 版应用层。`xiaozhi-service` 是可独立部署的
后台服务包，自带唤醒、音频、激活、协议、MCP、native 模块、唤醒模型和悬浮 UI
资源。若另行安装前台 `xiaozhi` App，二者可通过 IPC 联动；前台 App 不存在或启动失败
不会阻止 service 运行。

## 单 Service 模式

当前包以 `kind = service` 运行，唤醒、联网对话、MCP、录音和播放都在同一个 Lua
runtime 内完成。空闲时不显示界面；检测到唤醒词后通过 `xiaozhi-service/ui.lua`
进入 UI 驱动，再按 `ui_type` 加载 `/sd/apps/xiaozhi-service/ui/<type>.lua`
呈现悬浮 UI，回到空闲状态后自动隐藏。Launcher 使用
`/sd/apps/xiaozhi-service/service.json` 启停服务并读取音频资源冲突黑名单。
`ui_mode` 控制唤醒后的 UI 呈现：

- `"app"`：唤醒时记录当前前台应用并尝试启动 `/sd/apps/xiaozhi`，前台 app 只通过 IPC 呈现 UI；对话回到待命后自动跳回唤醒前应用。前台 App 不可用时，本次运行自动退回 service 悬浮 UI。
- `"floating"`：服务通过 `xiaozhi-service/ui.lua` 进入 UI 驱动，加载 `/sd/apps/xiaozhi-service/ui/<type>.lua`，并用固件 `service_ui` API 绘制悬浮 UI；服务启动时不显示，只有唤醒、验证码、对话或错误时显示。

`deny_apps` 中的前台应用会独占性能、麦克风或扬声器。服务监听固件
`app-lifecycle` IPC，并在 `app.started` 时静默暂停小智音频、在 `launcher.started` 或进入
非退避 App 时恢复。自动退避不会播放告别语音。Service runtime 不会退出，因此不会触发常驻服务的自动重启。
老固件没有生命周期 IPC 时会每约 10 秒从 `app.list()` 核对一次前台 App，并向串口输出英文错误，
但不会中止服务。MCP 的应用校验、结果返回和延迟启动流程保持不变。

进入小智会话的连接、聆听或回答状态时，服务会先通过 `sys.getled()` 保存当前 RGB 指示灯颜色，
再按设备灯珠通道映射用 `sys.setled(0, 165, 239)` 将其设为橙色；会话退出、异常结束或服务停止时恢复唤醒前的颜色。
老固件缺少 RGB LED API 时只输出英文串口错误，不影响语音功能。

唤醒或讲话期间短按 HOME 会立即停止当前录音/回答、关闭协议会话并回到待命，
不会向服务端发送额外的 `listen.detect`，也不会播放告别语音；
这样兼容只允许 `detect` 上报唤醒词的官方服务端。
前台 App UI 模式会在 Service 进入待命后退出或返回唤醒前应用。空闲且悬浮 Canvas
不可见时，HOME 仍由 Launcher 或当前前台 App 处理。

## API 配置

设备端不直接填写 OpenAI / DeepSeek API Key。小智协议要求设备连接“小智服务端”，由服务端配置 ASR、LLM、TTS 的 API Key。

`xiaozhi-service` 的 `websocket.url/token/version`、`ota`、音量和唤醒词保存在自己的运行配置：

```text
/sd/apps/xiaozhi-service/config.json
```

首次升级且 service 配置不存在时，会兼容读取 `/sd/apps/xiaozhi/config.json`；该文件不存在时静默使用内置默认值。前台 App 的 UI 风格仍只在前台 App 已安装时读写其配置。

后台开关和呈现方式使用独立的服务配置：

```text
/sd/apps/xiaozhi-service/service.json
```

`service.json` 只控制后台服务开关、后台 UI 呈现模式、后台 UI 类型和资源冲突黑名单；不要在这里放 token、音量或小智协议参数。协议配置示例见 `/sd/apps/xiaozhi-service/config.example.json`。

示例文件见 `/sd/apps/xiaozhi-service/service.example.json`；设备实际读取
`/sd/apps/xiaozhi-service/service.json`。示例：

```json
{
  "enabled": true,
  "ui_mode": "app",
  "ui_type": "window",
  "ui_character": "xiaozhi_chibi",
  "session_idle_timeout_sec": 20,
  "deny_apps": {
    "Spectrum": true,
    "mp3_player": true,
    "holo-retro-go": true,
    "FluidPendant": true
  }
}
```

字段说明：

- `enabled`：是否允许后台唤醒服务运行。
- `ui_mode`：`"app"` 表示唤醒后打开小智前台 App；`"floating"` 表示使用悬浮 UI。
- `ui_type`：后台悬浮 UI 类型，对应 `/sd/apps/xiaozhi-service/ui/<type>.lua`。当前内置 `window` 小窗模式、`subtitle` 字幕模式、`wechat` 微信气泡、`assistant` 助手形象。
- `ui_character`：`assistant` 样式使用的角色资源名，对应 `/sd/apps/xiaozhi-service/ui/character/<name>.rgb565`。
- `session_idle_timeout_sec`：自动会话在无交互时回到待命的时间，只支持 `10`、`20`、`30`、`60` 秒，默认 `20` 秒。
- `deny_apps`：这些前台应用运行时静默暂停小智服务，避免音频、性能或输入冲突；默认是 `Spectrum`、`mp3_player`、`holo-retro-go`、`FluidPendant`。

服务 WebUI 提供两个 UI 配置区：

- “主应用 UI”：写入 `/sd/apps/xiaozhi/config.json` 的 `ui.type`，控制前台小智 App。
- “启用后台唤醒”：写入 `/sd/apps/xiaozhi-service/service.json` 的 `enabled`。关闭后立即停止后台唤醒监听和当前后台对话；再次开启后在空闲状态恢复唤醒监听。
- “后台服务 UI”：写入 `/sd/apps/xiaozhi-service/service.json` 的 `ui_mode`、`ui_type`、`ui_character` 和 `session_idle_timeout_sec`，控制后台呈现及无交互自动休眠时间。
- “退避 App”：写入 `/sd/apps/xiaozhi-service/service.json` 的 `deny_apps`。勾选的 App 在前台运行时会暂停小智后台唤醒/音频，避免音频、性能或输入冲突。
- “自定义服务”：写入 `/sd/apps/xiaozhi-service/config.json` 的 `ota.url` 和可选 `websocket.url/token/version`。这里只要求 OTA 地址必填；WebSocket 地址可留空，由 OTA 激活流程下发。

## 回复流程

1. `xzwk.so` 检测到 `你好小智`。
2. Lua 进入 `connecting`，按官方 WebSocket 协议发送 hello。
3. 服务端返回 `session_id` 后，Lua 发送 `listen.detect/start`。
4. 麦克风 PCM 经 `xzvoice.so` 编成 Opus，通过 WebSocket 发给服务端。
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
- `memo.get`：读取 `/sd/apps/time-calendar-weather-memo/memos.json` 的三条备忘录。
- `memo.add`：在第一条空白位置新建备忘录。
- `memo.set`：修改指定序号的一条备忘录。
- `memo.delete`：删除指定序号的备忘录并清空该位置。
- `memo.set_all`：一次替换全部三条备忘录。

备忘录 App 未安装时工具会明确返回“请先安装备忘录 App”。App 已安装但
`memos.json` 尚不存在时会安全初始化为三条空记录。

备忘录写入成功后会向 `time-calendar-weather-memo` endpoint 发送 `memos.reload`，
使正在前台运行的日历立即刷新。没有 IPC 或日历未运行时文件仍会保存，并在下次进入
应用时加载；串口会输出英文兼容性提示。

服务端必须支持小智协议的 MCP 消息转发，并在智能体中启用设备工具调用。启动应用会在工具结果发回后延迟执行，避免切换应用导致应答丢失。

### MCP 插件

默认工具也以插件形式放在 `xiaozhi-service/mcp/device.lua`。启动时会扫描：

```text
/sd/apps/xiaozhi-service/mcp/*.lua
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

部署时复制整个 `package/` 到 `/sd/apps/xiaozhi-service/`。服务运行所需资源全部位于
该目录，不从其他 App 目录加载 Lua 或 native 模块：

```text
/sd/apps/xiaozhi-service/audio.lua
/sd/apps/xiaozhi-service/protocol.lua
/sd/apps/xiaozhi-service/activation.lua
/sd/apps/xiaozhi-service/mcp.lua
/sd/apps/xiaozhi-service/xzwk.so
/sd/apps/xiaozhi-service/xzvoice.so
/sd/apps/xiaozhi-service/wake/wn9s_nihaoxiaozhi/*
```

## UI 资源和插件化适配

小智 UI 分为两个插件域：

```text
/sd/apps/xiaozhi/ui/<type>.lua                 # 前台 App UI
/sd/apps/xiaozhi-service/ui/<type>.lua         # 后台悬浮 UI
/sd/apps/xiaozhi-service/ui/character/*.rgb565 # 助手形象角色
/sd/apps/xiaozhi-service/assets/fonts/xiaozhi_common3500_16.bin
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

其他后台应用临时需要 I2S 时，可以向 `xiaozhi-service` 发送临时唤醒退避事件：

```lua
ipc.send("xiaozhi-service", "temporary_wake_backoff", json.encode({
  source = "ntfy-service",
  duration_ms = 1500
}))
```

`duration_ms` 会被限制在 `1000` 到 `10000` 毫秒；也可以传 `seconds`，范围等价于
`1` 到 `10` 秒。退避只临时关闭空闲状态下的后台唤醒 I2S，不会修改
`service.json` 的 `enabled`，并且优先级高于 Launcher 或前台 App 变化触发的唤醒恢复。
