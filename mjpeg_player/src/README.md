# 视频播放器原生模块源码

此目录保存 `mjpeg_player/package/modules/jpg.so` 对应的原生源码：

- `main/jpg_module.c`：`esp_new_jpeg` RGB565 解码、双 LVGL 图像槽、异步任务及协作停止逻辑。
- `main/module_abi.h`：Clocteck Cubic Lua 模块 ABI 声明。
- `build_jpg.ps1`：按 ESP32-S3 性能配置构建并静态链接 `esp_new_jpeg 1.0.2`。

模块面向设备固件提供的 Lua 5.4 动态模块 ABI 编译。发布包中的 `jpg.so` 由这里的源码构建；第三方来源与许可见 `package/THIRD_PARTY_LICENSES.txt`。

构建命令：

```powershell
./build_jpg.ps1
```

脚本使用 `CONFIG_COMPILER_OPTIMIZATION_PERF=y`、ESP32-S3 预编译 `libesp_new_jpeg.a` 和仅四个 ABI 导出符号的共享对象链接流程。生成文件位于 `src/build/jpg.so`，确认后替换 `package/modules/jpg.so`。

1.0.1 固定启用 `JPG_USE_ESP_NEW_JPEG=1`；两个 320×240 RGB565 槽均持久分配并按 16 字节对齐，解码任务直接写入后台槽，LVGL 切换完成后才允许复用旧前台槽，因此每帧没有整屏 RGB565 复制。

为降低内部 RAM 压力，生产者侧的待提交 JPEG 邮箱优先分配到 PSRAM；工作任务使用的当前解码输入仍留在内部 RAM。Lua 侧使用 6×512 I²S DMA 队列，配合已经位于 PSRAM 的 PCM 环形缓冲，典型情况下可比旧的 12×1024 配置少占约 24 KB 内部 RAM。

0.2.7 将 JPEG 工作任务栈调整为 8 KB；停止时先请求任务退出并等待确认，只有超时才执行防御性清理；每帧解码后主动让出调度时间，避免持续满负载触发任务看门狗。
