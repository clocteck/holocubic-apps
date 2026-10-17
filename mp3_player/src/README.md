# cubic-mp3-audio-dynmod

`audio.so` 是给 Lua music app 使用的低开销音频解码动态模块。

目标：

- 使用 `espressif/esp_audio_codec` 的 simple decoder 解析 MP3/WAV。
- 兼容旧 Lua 表面：`open()`、`info()`、`read()`、`close()`、`version()`、`set_effects()`。
- 默认输出 mono s16le，减少 I2S 写入量和 CPU0 压力。
- `audio.read(8192)` 在 C 侧聚合多帧 PCM，减少 Lua/C 往返。
- 7 段 EQ/HPF/limiter 走 `esp-dsp` biquad，ESP32-S3 使用 `dsps_biquad_f32_aes3`。
- 虚拟低音 `vbass` 走 80-180Hz 提取、2/3 次谐波生成、180-650Hz 输出滤波。
- 模块固定缓冲约 15.5 KB；MP3 decoder heap 由 `esp_audio_codec` 管理。
- `stats()`/`get_stats()` 可查看 `vbass_mix`、`vbass_active` 和 `limiter_active_percent`。

`package/main.lua` 是配套的 Lua music app 入口，`package/` 内是可部署运行包。

源码 `audio.so` 1.12.1 增加可选的 `i2s_play_start({producer_stack_psram=true})`：仅将 `audio_fill` 栈放入 PSRAM，`audio_i2s` 和 DMA 保持内部 RAM。默认不启用，因此现有音乐 App 行为不变。扩展任务 API 单独按过程 ID 解析，不改变 v1 宿主表布局；显式启用但固件不支持时返回错误。需要启用外部栈的固件，且生产者任务不得执行 Flash/NVS 写入。`i2s_play_state().producer_stack_psram` 表示最后成功创建的生产者使用的策略，不代表任务当前仍运行。

该修改供视频播放器使用；已重编译并更新 `../../mjpeg_player/package/modules/audio.so`，本音乐 App 自身的发布模块未替换。

构建，在 `mp3_module/src` 目录执行：

```powershell
cmake -S . -B build -G Ninja -DIDF_TARGET=esp32s3 -DPYTHON="$env:PYTHON" -DPYTHON_DEPS_CHECKED=1
cmake --build build --target so --config Release
```
`elf_loader` 1.3.1 不使用此项目设置的 `ELF_SO_LINK_FLAGS`，默认 `so` 链接可能报库内符号的 dangerous relocation。对象文件和依赖库编译完成后，在已导出 ESP-IDF 环境的 PowerShell 中执行：

```powershell
./link_audio.ps1 -BuildDir ./build
```

此脚本复用已有对象和库，显式设置 `-Bsymbolic`、链接 `libgcc.a`，执行共享对象校验后再剥离非运行时段，产物为 `build/audio.so`。可在 ASCII 路径暂存源文件构建，并将该暂存目录的 `build` 绝对路径传给脚本，避免 Windows 中文/长路径构建问题。

设备路径：

```text
/sd/apps/mp3_player/modules/audio.so
```

本仓库中的当前模块快照在：

```text
package/modules/audio.so
```
