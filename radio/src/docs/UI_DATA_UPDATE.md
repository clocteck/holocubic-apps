# Radio 0.1.3 — UI and persistent data

Device: black/amber, 24px station name with ellipsis, UTF-8 initial badge,
localized status dot, category or actual program metadata, minute clock,
thin volume rail and quieter input hints. No continuous animation. The UI
skips unchanged label, volume and visibility writes. Time uses the device's
existing local-time configuration; an unsynchronized clock shows `--:--`.

Web: matching hierarchy, collapsible diagnostics, four languages, retained
station editor and `/main` link. Audio format is available inside Details.
Sampling, filters, gain, decoder and transport behavior are unchanged.

User catalog: `/sd/data/radio/stations.json` (the entire edited catalog).
Last station: `/sd/data/radio/config.json`. Legacy install-directory files
are copied on first load only when no new-location data exists, and retained.
Saves verify a temporary JSON, rotate `.bak`, and commit by rename. Corrupt
primary files disable saving instead of replacing user data with defaults.
Shared default volume/language/weather remain in `/sd/apps/settings.json`.
App package uploads exclude mutable JSON files. Uninstall removes the app
directory only; formatting/deleting the SD data directory still removes data.

Fonts: Noto Sans CJK under the bundled OFL license. `tools/build_ui_fonts.py`
converts bitmap assets using lv_font_conv; it does not compile firmware.
The 13px and 24px files total about 1.11 MiB on disk. Existing 18px font is
not loaded. Font coverage includes GB2312, kana and current UI translations;
uncommon custom-name characters outside the subset may lack a glyph.

Verification (2026-09-08): 54 local tests passed (Lua mock-LVGL behavior,
storage migration/recovery, transport/protocol and HTML/JS structure/syntax).
On the device, uploaded file sizes matched; App started and reported playing,
clock and no storage error. A uniquely named temporary station survived an App
restart from the new data path, then only that test row was deleted. Original
20-station catalog was unchanged. Config exists in the new directory.
No real uninstall, firmware compile or firmware flash was performed.
Browser automation timed out: rendered screenshot visual QA remains unverified.
Decoder internal-memory delta is not a whole-App RAM budget measurement.
