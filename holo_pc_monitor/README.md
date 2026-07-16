# Holo PC Monitor

Holo PC Monitor 是一款面向 HoloCubic 320×240 屏幕的电脑硬件监控应用。应用直接连接 AIDA64 RemoteSensor，在设备上显示 CPU、GPU、内存、温度、频率和风扇转速，并提供天气、时间、日期和历史趋势曲线。

## 功能特点

- CPU、GPU 和内存使用率实时显示
- CPU/GPU 温度、频率与风扇转速监控
- 经典双环布局与 320×240 四卡片仪表盘切换
- CPU、GPU 和温度历史趋势曲线
- 天气、时间和日期信息
- 中文网页控制页面，可配置数据地址和显示布局
- 温度与风扇多传感器备用机制：主传感器缺失或返回 `0` 时自动使用备用值

## AIDA64 设置

1. 打开 AIDA64。
2. 进入“文件 → 设置 → 硬件监控 → LCD”。
3. 启用 RemoteSensor，并设置监听端口。
4. 进入“LCD 项目”，导入 `package/holo-aida.rslcd`。
5. 点击“应用”，然后通过浏览器访问 `http://电脑IP:端口/sse` 检查数据。

正常情况下，页面会持续输出包含 `CPU Usage`、`GPU Temperature`、`Memory Usage` 等字段的 `data:` 数据。

## 传感器备用顺序

- CPU 温度：`CPU Diode` → `CPU Temperature` → `CPU Package`
- GPU 温度：`GPU Temperature` → `GPU Diode` → `GPU1 Temperature`
- 风扇：`CPU Fan` → `GPU Fan` → `Chassis Fan 1/2` → 其他风扇
- 温度、频率和风扇值为 `0` 或未获取时，会继续查找下一项
- 所有来源均不可用时，界面显示 `--`

CPU、GPU 和内存使用率允许正常显示 `0%`。

## 安装到设备

将 `package` 目录中的文件上传至：

```text
/sd/apps/holo_pc_monitor/
```

最少需要以下文件：

```text
app.info
main.lua
aida_client.lua
config.lua
web.lua
main.png
info.html
holo-aida.rslcd
```

上传后重新扫描应用列表，并启动 `holo_pc_monitor`。

## 网页配置

在 HoloCubic 启动器中打开 Holo PC Monitor 的网页控制页面，填写运行 AIDA64 的电脑 IP、端口和 SSE 路径。常见地址格式为：

```text
http://192.168.0.80:80/sse
```

控制页面也可以切换经典布局与仪表盘布局，设置会保存在设备的 `config.lua` 中。

## 文件说明

- `package/holo-aida.rslcd`：供用户导入 AIDA64 的正式 RemoteSensor 配置
- `package/holo-aida-required-metrics.rslcd`：与正式配置内容同步的开发参考文件
- `package/info.html`：应用商店介绍页，默认中文并支持英文切换
- `package/app.info`：应用名称、版本号、图标和简介

## 版本

当前版本：`1.0.1`

许可证：GPL-3.0
