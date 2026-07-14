# AIDA Monitor

HoloCubic app that renders the **AIDA64 RemoteSensor LCD layout itself**, instead of mapping a fixed list of sensor names to a hard-coded dashboard.

The app first downloads the HTML layout from `/`, creates the corresponding 320×240 LVGL objects, and then applies live updates from `/sse`. Changing the LCD layout in AIDA64 and clicking **Apply** emits `ReLoad`; the device automatically downloads and rebuilds the layout.

## Supported RemoteSensor features

- Static labels and Simple Sensor Items
- Composite sensor label/value/unit items
- Horizontal bars, including AIDA64 foreground/background gradients
- Line Graph, Area Graph, and Histogram Graph
- Arc Gauge
- Static PNG/JPEG/BMP images and animated GIF resources served by AIDA64
- Multiple LCD pages and live `PageN` switching
- Dynamic layout reload without reinstalling the app
- On-device TrueType rendering from a bundled Chinese fallback or one WebUI-uploaded TTF at 6–96 px
- Synthetic bold/italic plus underline, strikethrough, and CSS text shadow

This target is the complete **RemoteSensor LCD** feature set. SensorPanel-only Custom Gauges are not emitted by the RemoteSensor web protocol; use AIDA64 Arc Gauge instead.

## AIDA64 setup

1. Open `File → Preferences → Hardware Monitoring → LCD`.
2. Enable RemoteSensor support.
3. Set the RemoteSensor port (this checkout defaults to `9999`).
4. Set Preview Resolution to **320 × 240**.
5. Use AIDA64's normal LCD Items editor to build the screen and pages.
6. Keep AIDA64's default LCD family, `Tahoma`. For an exact Windows match,
   upload the host's own `tahoma.ttf`; the bundled Noto Sans SC face remains a
   CJK-safe device fallback and does not need to be selected in AIDA64.
7. Click **Apply**.

You should now be able to open both URLs from another LAN device:

```text
http://<aida-host>:9999/
http://<aida-host>:9999/sse
```

The included `package/holo-aida.rslcd` mirrors the current 320×240 example
layout and can also be downloaded directly from the app WebUI.

## Device configuration

Open the AIDA Monitor management page from HoloCubic WebUI. It exposes:

- AIDA64 host/IP
- RemoteSensor port
- Layout path (normally `/`)
- SSE path (normally `/sse`)
- Chunked TTF upload (up to 4 MB), font-family match state, and automatic
  fallback to the bundled Chinese face when the layout does not request it
- Download buttons for the bundled TTF and the shipping `.rslcd` example
- Runtime status, active page, page count, and parsed item count

The defaults in this checkout are:

```lua
config.host = "192.168.0.232"
config.port = 9999
config.layout_path = "/"
config.path = "/sse"
config.vector_font_family = "Tahoma"
config.vector_font_fallback_family = "AIDA Noto Sans SC"
config.vector_font_module = "/sd/apps/aida_monitor/modules/aida_font.so"
config.vector_font_path = "/sd/apps/aida_monitor/font/aida_noto_sans_sc.ttf"
config.vector_font_custom_family = ""
config.vector_font_custom_path = "/sd/apps/aida_monitor/font/uploaded.ttf"
```

## Rendering model

RemoteSensor uses browser coordinates and does not put a canonical canvas size into the HTML response. The app therefore uses AIDA64's 320×240 preview coordinates **1:1 with no scaling**. Content outside the device viewport is clipped just like a 320×240 browser viewport.

AIDA64 font size, color, alignment, style metadata, positions, gradients,
histories, scales, grids, frames, and active page are parsed. Font sizes in
points are converted to CSS pixels (`pt × 4/3`) and rendered at the resulting
integer size rather than snapped to a firmware bitmap size.

The bundled native `aida_font.so` module uses `stb_truetype` to rasterize an
OFL-licensed, GB2312-subsetted Noto Sans SC fallback or one uploaded TrueType
face. The default logical family is AIDA64's `Tahoma`, while the physical face
is the bundled CJK-safe fallback until the user uploads `tahoma.ttf`. Before
building a layout, the app compares AIDA64's requested font families with the
uploaded family; a mismatch or load failure reopens the bundled fallback while
preserving AIDA64's default-family semantics. The renderer maintains a
320×240 RGB565 page surface in PSRAM and blends glyph A8 coverage, shadows,
graphs, arcs, and Sensor text before the firmware sees the frame. This avoids
firmware chroma-key limitations and preserves overlapping content. A 512 KiB
LRU glyph cache avoids rebuilding common digits and labels on each SSE update.
The regular outline is also used to synthesize bold and italic variants;
underline, strikethrough, and `text-shadow` are composited by the renderer. If
the uploaded TTF cannot load, the app reports the reason in WebUI and keeps the
bundled vector fallback visible.

Remote images are stored under `/sd/apps/aida_monitor/cache`. A layout `ReLoad` rebuilds the UI and refreshes the resources so replacing an image under the same filename is reflected on the device.

AIDA64 serves the original image file even when the generated HTML asks the browser to display it at a much smaller size. To prevent an oversized source image from exhausting the HoloCubic's memory, the app checks both the HTTP body length and the source pixel dimensions before saving or decoding it. The defaults accept up to 256 KiB and 307,200 source pixels; rejected resources render as an `IMG` placeholder and are reported by the management state API. Resize images close to their intended LCD dimensions before adding them to RemoteSensor.

## Install

Upload the package directory to `/sd/apps/aida_monitor` and rescan apps. Required runtime files are:

```text
main.lua
aida_layout.lua
aida_renderer.lua
aida_vector_font.lua
aida_client.lua
config.lua
web.lua
app.info
main.png
info.html
font/aida_noto_sans_sc.ttf
font/OFL.txt
modules/aida_font.so
holo-aida.rslcd
holo-aida-template.txt
```

## Rebuilding the vector assets

Download `NotoSansSC[wght].ttf` from the Google Fonts `ofl/notosanssc`
directory, install `fonttools`, then build the static GB2312 subset:

```powershell
python aida_monitor/tools/build_vector_font.py NotoSansSC-wght.ttf
```

Build the ESP32-S3 module with ESP-IDF 5.5.2 and copy `aida_font.so` into
`package/modules`:

```powershell
cmake -S aida_monitor/src -B aida_monitor/src/build -G Ninja -DIDF_TARGET=esp32s3
cmake --build aida_monitor/src/build --target so
```

## Tests

The protocol fixture covers labels, images, composite items, bars, all three graph types, Arc Gauge, two pages, `ReLoad`, HTML entity decoding, and renderer updates:

```powershell
npx -y -p fengari-node-cli fengari aida_monitor/tests/protocol_test.lua
```

Syntax check:

```powershell
npx -y luaparse -q aida_monitor/package/aida_layout.lua
npx -y luaparse -q aida_monitor/package/aida_renderer.lua
npx -y luaparse -q aida_monitor/package/aida_client.lua
```

## Local screenshot previews

Render the comprehensive two-page protocol fixture locally at the native
320×240 device size:

```powershell
python aida_monitor/tools/render_layout_previews.py
```

The output is written to `aida_monitor/art/local-previews` and contains one PNG
per RemoteSensor page plus `overview.png`.

To preview the layout and current values directly from a running AIDA64 host:

```powershell
python aida_monitor/tools/render_layout_previews.py `
  --aida http://192.168.0.232:9999 `
  --output aida_monitor/art/live-previews
```

Like HoloPet's preview helper, it can also discover the configured AIDA64 host
through the HoloCubic management endpoint:

```powershell
python aida_monitor/tools/render_layout_previews.py `
  --device http://192.168.0.102 `
  --output aida_monitor/art/device-previews
```

The local renderer mirrors the app's 1:1 positions, font-size mapping,
gradients, graph histories, Arc Gauge, Image width/height, page background, and
SSE field updates. It uses the first GIF frame, matching a static screenshot.

## Official AIDA64 references

- [RemoteSensor LCD for smartphones and tablets](https://forums.aida64.com/topic/2636-remotesensor-lcd-for-smartphones-and-tablets/)
- [External display support](https://www.aida64.com/products/features/external-display-support)
- [AIDA64 LCD Guide](https://download.aida64.com/resources/lcd/aida64_lcd_guide.pdf)
- [RemoteSensor Custom Gauge limitation](https://forums.aida64.com/topic/10160-remotesensor/)
