# Afterglow 余辉 1.0.1

适用于 HoloCubic 320 × 240 屏幕的复古仪表时钟，显示 IBM 3270 等宽时间码、日期和实时麦克风波形。

## 安装

将 `package/` 内全部文件复制到 `/sd/apps/afterglow/`，重新扫描应用后打开 Afterglow。入口为 `/sd/apps/afterglow/main.lua`。

已在固件 1.206 的设备上部署并启动。手柄功能依赖固件的 `controller.state("ble-main")` 接口。

## 操作

- 左右倾斜设备切换 EL 琥珀、VFD 青蓝、CRT 绿色主题；回正后可再次切换。
- 手柄左／上切上一主题，右／下、A／Menu 切下一主题。
- 手柄 Select／Home 或设备短按 HOME 返回启动器。
- 手柄按下触发一次，长按不连跳；切换间隔约 390ms。
- 介绍页跟随设备 `/sd/apps/settings.json` 中的系统语言；中文显示中文，其他语言显示英文。

请先设置设备时区并校时。缺少麦克风接口时显示内部示意波形。COMP 和 dB 表示显示增益压缩状态，并非声压测量；应用不录制或保存音频。

## 致谢

感谢 [baigemozhengliu/afterglow-a-holocubic-apps](https://github.com/baigemozhengliu/afterglow-a-holocubic-apps) 开源原项目。本版本在原版 1.0.0 基础上增加手柄控制、中英文介绍与系统语言跟随，并根据设备实测修正左右倾斜轴。

原项目采用 MIT 许可，版权声明与许可证保留在 `package/LICENSE`；字体许可证见 `package/FONT-LICENSE.txt`。

## English

Afterglow is a retro instrument clock for the 320 × 240 HoloCubic display. Copy all files from `package/` to `/sd/apps/afterglow/`, rescan apps and launch Afterglow.

Tilt left/right to cycle themes. On a gamepad, Left/Up selects the previous theme; Right/Down, A/Menu selects the next. Select/Home returns to Launcher. Holding a button does not repeat; theme changes have an approximately 390ms cooldown. The information page follows the device system language.

Based on the original open-source Afterglow project linked above. Original application and font licenses are included. Microphone samples are used for visualization only; audio is not recorded or saved.
