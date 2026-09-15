# NetEase App

Only modify this netease directory. Do not modify other apps or firmware.
Runtime files belong in package; source, tools and tests belong in src.
Keep credentials in /sd/data/netease and never log or return their values.
Maintain MP3-only standard quality and PSRAM-only bulk allocations. The user's
50 KiB internal heap figure is an approximate reference, never a stop/reject limit.
Keep heap diagnostics; do not claim the global TLS peak is proven without measurement.
Run src/build.ps1 for the ESP32-S3 module and src/tests/test_app.py for host tests.
