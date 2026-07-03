# MP3 Module Agent Notes

This app now uses the standard two-folder layout:

- `src/`: C dynamic module source, build files, old app snapshots, README, and test probes.
- `package/`: deployable Lua music app plus module snapshot.

Build `audio.so` from `mp3_module/src`:

```powershell
cmake -S . -B build -G Ninja -DIDF_TARGET=esp32s3 -DPYTHON="$env:PYTHON" -DPYTHON_DEPS_CHECKED=1
cmake --build build --target so --config Release
```

Deploy:

- Copy `package/` contents to `/sd/apps/mp3_player/`.

Runtime entry is `package/main.lua`; it loads the module from `/sd/apps/mp3_player/modules/audio.so`.
