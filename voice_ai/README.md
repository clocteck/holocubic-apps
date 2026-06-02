# Voice AI

320x240 voice assistant app. The device records audio and sends it to a desktop bridge. The bridge transcribes the audio, calls `gpt-5.4-mini`, and returns a short Chinese reply plus a sandboxed LVGL Lua UI snippet.

When `ui_code` is returned, the app creates a temporary LVGL screen and loads it full-screen. The next short `HOME` press cleans up that temporary screen, switches back to the app screen, and starts a new recording.

The raw bridge JSON response is written to UART0 with the `bridge_json` prefix, including `reply` and any returned `ui_code`.

## Device config

Copy `config.example.json` to `config.json` on the SD card and adjust the computer IP:

```json
{
  "bridge_url": "http://192.168.0.80:8790",
  "sample_rate": 16000,
  "sample_bits": 32,
  "max_record_ms": 10000,
  "reply_limit": 100,
  "use_gif": true
}
```

## Controls

- Short press `HOME`: start or stop recording.
- Short press `HOME` while an AI screen is visible: close it and start recording.
- Long press `HOME`: exit the app.

## AI UI snippets

The bridge asks the model to return Lua in this shape:

```lua
return function(ctx)
  local screen = ctx.new_screen()
  ctx.label(screen, 18, 76, 284, 72, "Hello", 0xF4F7FA, ctx.ALIGN_CENTER)
  return { screen = screen, cleanup = function() end }
end
```

The snippet runs in a restricted environment. It can use most `lv_*` LVGL bindings and `LV_*` constants available on the device. Screen switching, root cleanup, object deletion, parent discovery, resource load/free, AVI playback, global animation delete, file, HTTP, I2S, keys, app exit, `require`, `_G`, `debug`, `os`, and `io` are blocked.

Normal text replies can return an empty `ui_code`; the app will keep showing the regular reply screen.

## Font

The app loads:

```text
/sd/apps/voice_ai/font/msyh_cn_13.bin
```

Use `font/build_msyh_cn_13.ps1` to rebuild it from Microsoft YaHei and the common 3500 Chinese character set.

The script expects Node and `lv_font_conv`. Set these when they are not on `PATH`:

```powershell
$env:NODE_EXE="C:\path\to\node.exe"
$env:LV_FONT_CONV_JS="C:\path\to\lv_font_conv.js"
.\font\build_msyh_cn_13.ps1
```
