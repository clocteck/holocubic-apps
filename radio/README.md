# 网络收音机 / Radio

独立项目：仅修改本目录，构建不引用其他 App 源码。

- `src/main`：ESP32-S3 动态音频模块。
- `src/vendor/esp_audio_codec`：Espressif 2.5.0 独立依赖副本，保留其许可证。
- `package`：部署到 `/sd/apps/radio` 的完整 App。
- `src/web`：四语言介绍页模板。
- `prototype`：设备屏幕 HTML 设计稿。
- `tools/package_branding.cjs`：图标尺寸导出和介绍页内嵌资源打包。

目标：MP3、ADTS AAC、FLAC、HLS 音频直播；输出 16 kHz、16-bit、单声道。
两级参数 EQ 使用几何中心频率 316 Hz / 1342 Hz，对应带宽 200–500 Hz / 900–2000 Hz，峰值增益 +5 / -2.5 dB，非理想砖墙频响。
音量 0–100 的 PCM 增益较初版翻倍（0.56→1.12，+6.02 dB），保留 ±31000 饱和保护；已达到限幅的峰值不能继续翻倍，不代表主观响度翻倍。

0.1.4 按用户要求移除 Radio Audio Restore 恢复助手及 App 依赖。收音机不再自动停止/恢复小智或 AirPlay；请在控制主页手动管理可能占用音频的服务。安装包不会重新安装恢复助手。旧源码仅保留在 src/archive 供回溯。

公共默认音量使用 `/sd/apps/settings.json` 的 `radio_volume`（0–100），读取并合并保存，保留天气等其他字段。

## 安装与数据

将 `package/` 内的内容复制到设备 `/sd/apps/radio/`，不要额外套一层 package 目录。
刷新应用列表后启动 Radio，在同一局域网通过 `http://<设备地址>/radio/` 控制。
需要兼容的 ESP32-S3 Cubic 固件（支持动态模块、异步 HTTP 和 PSRAM）；旧版 HTTP
取消实现可能导致快速切台时连接池耗尽。此仓库不包含底层固件修复。

编辑后的完整电台列表保存于 `/sd/data/radio/stations.json`，上次电台保存于
`/sd/data/radio/config.json`。首次运行会尝试迁移旧安装目录的数据并保留旧文件。
更新安装包不应覆盖数据目录。当前版本移除了独立的服务恢复助手。

`src/build.ps1` 是可选的动态模块构建脚本，需要 ESP-IDF 环境、`IDF_PATH` 和
`xtensa-esp32s3-elf-*` 工具链；常规安装直接使用已附带的 `package/modules/radio.so`。
本次发布没有重新编译音频模块或固件。

第三方音频依赖许可证见 `src/vendor/esp_audio_codec/LICENSE`，字体许可证见
`package/font/OFL.txt`。未对整个 App 作新增许可证声明。
