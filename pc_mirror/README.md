# PC Mirror / 电脑投屏

`pc_mirror` 是基于 [clocteck/desktop-mirror](https://github.com/clocteck/desktop-mirror) 纯 Lua 接收端整理的社区应用，版本为 `0.0.1`。

## 安装

将 `package/` 完整复制到设备：

```text
/sd/apps/pc_mirror/
```

主要文件：

- `app.info`：社区应用元数据。
- `main.lua`：纯 Lua WebSocket/JPEG 投屏接收端。
- `config.json`：由应用内置 Web 页面维护的持久连接设置，无需手动编辑。
- `main.png`：128×128 应用图标。
- `main.html`：完整使用说明页。
- `info.html`：Launcher 内嵌说明页。

## 使用

1. 在电脑安装 Python 3，并下载上游仓库。
2. 运行 `computer\install_deps.bat` 安装电脑端依赖。
3. 运行 `computer\start_mirror.bat --fps 20 --quality 65`。
4. 确保电脑和设备在同一局域网，然后从 Launcher 打开“电脑投屏”。
5. 用手机或电脑浏览器打开设备屏幕显示的 `SETUP` 地址（通常为 `http://设备IP/pc_mirror`）。
6. 在内置 Web 页面填写电脑端输出的 IPv4 地址和端口，点击“保存并重连”。应用会自动持久化设置，不需要用户修改 `config.json`。

按键：左键显示/隐藏状态，右键重载配置并重连，下键暂停/恢复。

## 开源

本应用基于上游纯 Lua 接收端修改，采用 GPL-3.0-only。修改来源和版本见 `package/NOTICE.txt`。
