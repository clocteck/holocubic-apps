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

构建，在 `mp3_module/src` 目录执行：

```powershell
cmake -S . -B build -G Ninja -DIDF_TARGET=esp32s3 -DPYTHON="$env:PYTHON" -DPYTHON_DEPS_CHECKED=1
cmake --build build --target so --config Release
```
补上 -Bsymbolic 和显式 libgcc.a

设备路径：

```text
/sd/apps/mp3_player/modules/audio.so
```

本仓库中的当前模块快照在：

```text
package/modules/audio.so
```
