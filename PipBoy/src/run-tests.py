"""Run the isolated Lua tests without a device or any network requests."""
from pathlib import Path
import struct
import base64
import re
from lupa import LuaRuntime

app_root = Path(__file__).resolve().parent.parent
runtime = LuaRuntime(unpack_returned_tuples=True)

def read_source(name):
    return (app_root / name).read_text(encoding="utf-8")

runtime.globals().read_source = read_source
runtime.execute(read_source("src/tests.lua"))

# Verify binary assets are deployable without another app installed.
package = app_root / "package"
def png_size(path):
    header = path.read_bytes()[:24]
    assert header[:8] == b"\x89PNG\r\n\x1a\n", path
    return struct.unpack(">II", header[16:24])

assert png_size(package / "assets/background.png") == (320, 240)
assert png_size(package / "main.png") == (64, 64)
icons = list((package / "assets/weather-line").glob("*.png"))
assert len(icons) == 12 and (package / "assets/weather-line/unknown.png").is_file()
assert all(png_size(icon) == (28, 28) for icon in icons)
for name in ("time_en_12", "time_en_14", "time_ui_12", "time_mono_56", "time_mono_24"):
    assert (package / "font" / (name + ".bin")).stat().st_size > 0

def font_codepoints(path):
    """Read LVGL v8 binary cmap tables to catch missing temperature/unit glyphs."""
    data = path.read_bytes()
    start = struct.unpack_from("<I", data)[0]
    assert data[start + 4:start + 8] == b"cmap"
    points = set()
    for i in range(struct.unpack_from("<I", data, start + 8)[0]):
        offset, first, length, glyph, entries, kind, _ = struct.unpack_from("<IIHHHBB", data, start + 12 + 16 * i)
        if kind == 2:
            points.update(range(first, first + length))
        elif kind in (1, 3):
            points.update(first + v for v in struct.unpack_from("<" + "H" * entries, data, start + offset))
        elif kind == 0:
            points.update(first + j for j in range(entries) if j == 0 or data[start + offset + j])
    return points

assert set(map(ord, "-0123456789°C F")) <= font_codepoints(package / "font/time_mono_24.bin")
assert set(map(ord, ":0123456789")) <= font_codepoints(package / "font/time_en_14.bin")
manifest = dict(line.split(" = ", 1) for line in read_source("package/app.info").splitlines() if " = " in line)
assert manifest["version"] == "0.0.0"
assert manifest["catalog_scope"] == "community"
assert manifest["author"] == "wzh"
expected = {"app.info", "main.lua", "data.lua", "main.png", "info.html", "assets/background.png"}
expected.update("font/" + name + ".bin" for name in ("time_en_12", "time_en_14", "time_ui_12", "time_mono_56", "time_mono_24"))
expected.update("assets/weather-line/" + name + ".png" for name in ("sun", "moon", "partly-day", "partly-night", "cloud", "rain", "storm", "snow", "fog", "wind", "sleet", "unknown"))
actual = {str(path.relative_to(package)).replace("\\", "/") for path in package.rglob("*") if path.is_file()}
assert actual == expected, f"Unexpected/missing package files: {actual ^ expected}"
html = read_source("package/info.html")
embedded_icon = re.search(r'src="data:image/png;base64,([A-Za-z0-9+/=]+)"', html)
assert embedded_icon and base64.b64decode(embedded_icon.group(1)) == (package / "main.png").read_bytes()
assert '<script src=' not in html and 'src="http' not in html
for source in package.glob("*.lua"):
    text = source.read_text(encoding="utf-8")
    assert "/sd/apps/NixieClock" not in text and "/sd/apps/weather" not in text
print(f"PASS: self-contained package, background/icon dimensions, {len(icons)} weather PNGs, 5 fonts")
print(f"PASS: 0.0.0 community release by wzh, {len(actual)} runtime files, matching Base64 info.html icon")
