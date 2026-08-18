# 视频播放器原生模块源码

此目录保存 `mjpeg_player/package/modules/jpg.so` 对应的原生源码：

- `src/jpg_module.c`：ESP32-S3 ROM TJpgDec 调用、RGB565 转换、异步解码任务及协作停止逻辑。
- `src/module_abi.h`：Clocteck Cubic Lua 模块 ABI 声明。

模块面向设备固件提供的 Lua 5.4 ABI 和 ESP32-S3 ROM 符号编译。发布包中的 `jpg.so` 由这里的源码构建；第三方来源与许可见 `package/THIRD_PARTY_LICENSES.txt`。

0.2.7 将 JPEG 工作任务栈调整为 8 KB；停止时先请求任务退出并等待确认，只有超时才执行防御性清理；每帧解码后主动让出调度时间，避免持续满负载触发任务看门狗。
