# XiaoZhi Service

这是裁剪移植官方 `xiaozhi-esp32` 的 Lua 版应用层。底层动态模块只负责唤醒、Opus 编解码和音频播放；联网协议、状态机和 LVGL UI 放在 Lua。

## 单 Service 模式

当前包以 `kind = service` 运行，唤醒、联网对话、MCP、录音和播放都在同一个 Lua
runtime 内完成。空闲时不显示界面；检测到唤醒词后通过 `service_ui` 显示二次元人物和
对话气泡，回到空闲状态后自动隐藏。Launcher 使用
`/sd/apps/xiaozhi-service/service.json` 启停服务并读取音频资源冲突黑名单。

`deny_apps` 中的前台应用会独占性能、麦克风或扬声器。启动这些应用前 Launcher 会停止
小智服务；绕过 Launcher 启动时，小智也会检测真实前台应用并自行退出。返回 Launcher
后，只要 `enabled` 仍为 `true`，服务会自动恢复。MCP 的应用校验、结果返回和延迟启动
流程保持不变。

## API 配置

设备端不直接填写 OpenAI / DeepSeek API Key。小智协议要求设备连接“小智服务端”，由服务端配置 ASR、LLM、TTS 的 API Key。

若使用官方服务器，直接打开应用即可，如果使用自建服务端，需要在 SD 卡创建：

```json
{
  "ota": {
    "url": "https://your-xiaozhi-server/xiaozhi/ota/",
    "enabled": true,
    "force": false
  },
  "websocket": {
    "url": "",
    "token": "",
    "version": 1
  },
  "audio": {
    "sample_rate": 16000,
    "channels": 1,
    "frame_duration": 60,
    "bitrate": 12000
  },
  "wake_word": "你好小智",
  "default_ui_style": "default"
}
```

路径：`/sd/apps/xiaozhi-service/config.json`

可通过顶层字段 `default_ui_style` 设置启动时的默认 UI 风格：`default` 为官方字幕风格，`wechat` 为微信气泡风格。运行时仍可使用左右倾斜切换。

`audio` 控制设备上行 Opus 参数，并会原样用于 WebSocket `hello.audio_params`。自建服务端建议保持 `16000 Hz / 单声道 / 60 ms`。加载器也兼容服务端常用的 `audio_params` 名称，以及 `rate`、`frame_ms` 字段别名。

若使用自建服务端（`xinnan-tech/xiaozhi-esp32-server`），`websocket.version` 必须设置为 `1`。这类服务端的 WebSocket 接口直接接收原始 Opus 帧；版本 `3` 会给每帧增加 4 字节协议头，仅适用于能解析 v3 二进制包头的服务端。

官方控制台 `https://xiaozhi.me/console/agents` 是网页管理页，不是设备 OTA 接口。使用官方控制台时，`ota.url` 通常填官方固件默认的 `https://api.tenclass.net/xiaozhi/ota/`；使用自建 xinnan 服务端时，填自建服务端暴露的 `/xiaozhi/ota/` 地址。

启动后如果 `websocket.url` 为空，Lua 会请求 `ota.url` 获取 6 位验证码，并在屏幕上显示。后台“添加设备”输入该验证码后，Lua 会轮询 `ota.url + activate`，绑定成功后再次请求 OTA，并把服务端下发的 `websocket.url/token/version` 写回 `config.json`。

如果你不使用后台添加设备，也可以手动填写 `websocket.url` 和 `token`，此时会跳过 OTA 激活。

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
- `test.ping`：测试MCP工具读取是否正常。

服务端必须支持小智协议的 MCP 消息转发，并在智能体中启用设备工具调用。启动应用会在工具结果发回后延迟执行，避免切换应用导致应答丢失。

### MCP 插件

默认工具也以插件形式放在 `mcp/device.lua`。启动时会扫描：

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

部署时复制整个 `package/` 到 `/sd/apps/xiaozhi-service/`。动态模块和唤醒模型都从 app
目录内读取：

```text
/sd/apps/xiaozhi-service/xiaozhi.so
/sd/apps/xiaozhi-service/wake.so
/sd/apps/xiaozhi-service/wake/wn9s_nihaoxiaozhi/_MODEL_INFO_
/sd/apps/xiaozhi-service/wake/wn9s_nihaoxiaozhi/wn9_index
/sd/apps/xiaozhi-service/wake/wn9s_nihaoxiaozhi/wn9_data
```

## 官方资源

资源来自官方 `78/xiaozhi-fonts`：

- `assets/emojis/gif/*.gif`：`gif/noto-emoji_64`
- `assets/emojis/png/*.png`：`png/twemoji_64`
- `assets/fonts/xiaozhi_common3500_16.bin`：服务浮层默认加载的 LVGL 16px 字体；为兼容旧部署保留文件名，实际包含完整 3755 个 GB2312 一级汉字及 ASCII
- `assets/fonts/font_puhui_common_20_4.bin`：官方普惠字体，当前仅预留，不默认加载

Lua UI 会优先查找 GIF，再查找 PNG，最后退回文字表情。表情文件名与官方 emotion 名保持一致，例如 `neutral.gif`、`happy.gif`、`thinking.gif`。
