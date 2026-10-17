# 视频播放器原生模块源码

当前发布包包含已重编译的 `jpg.so` 1.0.3（114868 字节）及 `audio.so` 1.12.1（119948 字节）。7376 字节 JPEG 解码栈改为 PSRAM，保留 1.0.2 的轻量帧统计；不要仅凭 Lua App 版本判断模块已更新。

## PSRAM 任务栈

- `jpg_decode`：7376 字节，使用 `MODULE_HEAP_PSRAM | MODULE_HEAP_8BIT`，分配失败直接报错，不回退占用内部 RAM。
- `audio_fill`：5536 字节，Lua 显式传入 `producer_stack_psram=true`。对应音频源码在 `../../mp3_player/src/main/audio_module.c`，版本为 `audio.so` 1.12.1；重编译后复制到本 App 的 `package/modules/audio.so`。不需要替换其他音乐 App 的模块。
- `audio_i2s`：4608 字节，继续使用内部 RAM；I²S DMA 分配保持不变。
- 与三个任务栈都在内部 RAM 相比，预计释放 12912 字节（约 12.6 KiB）的内部栈分配；TCB、宿主任务记录及删除辅助任务仍需要内部 RAM，不能保证彻底消除内存不足。
- 固件必须启用 `CONFIG_FREERTOS_TASK_CREATE_ALLOW_EXT_MEM` 并提供 `task.create_ex`，当前 1.213 构建已具备。两条 PSRAM 工作任务链只处理 SD/内存解码，不能在其上加入 Flash 擦写、NVS 或 OTA 操作。
- 新音频模块默认仍用内部栈，旧固件缺少扩展接口不影响默认路径；显式请求 PSRAM 而接口不可用时返回错误，不静默降级。`i2s_play_state().producer_stack_psram` 可查询本次成功创建的生产者栈策略。
- 必须一起更新 Lua、`jpg.so` 和 `audio.so`；旧音频二进制会忽略新选项，单独上传 Lua 不会迁移音频栈。

实机验收：日志中 `jpg_decode` 与 `audio_fill` 应为 `caps=0x12`，`audio_i2s` 仍为 `caps=0x11`；测试连续播放、暂停恢复、循环和多次退出重进，记录内部空闲量/最大连续块和帧率。PSRAM 栈可能增加缓存访问开销，帧率及长期稳定性仍需实测。

2026-10-17 在固件 1.213 上完成启动冒烟测试：状态接口确认两个新模块版本，`audio.producer_stack_psram=true`，音频生产者及 I²S 任务运行、写入字节和视频呈现帧数持续增长，错误计数为 0；小智服务保持运行并为 `mjpeg_player` 暂停音频。固件音量与播放器 `volume_applied` 同步（包括 0 静音）。这是短时验证，不代表长期泄漏/稳定性测试，也未修复固件 WithCaps 删除辅助任务创建失败时的回收问题。

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
