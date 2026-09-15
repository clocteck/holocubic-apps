# QQ Music for Cubic

Only change qqmusic. Keep runtime files in package and development material in src.
Credentials belong only in /sd/data/qqmusic; never log/return cookies, QR signatures,
authorization codes, or signed playback URLs. No third-party API proxy or rights bypass.
Retain MP3 standard quality, PSRAM bulk buffers, 96 KiB thumbnails, 10 MiB FIFO SD cache.
Run src/build.ps1 and python src/tests/test_app.py before deployment.
50 KiB is a rough memory reference only, never a stop threshold. Keep measured heap
statistics and real allocation/decoder error handling; do not reintroduce a 50 KiB cutoff.
