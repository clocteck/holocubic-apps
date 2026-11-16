# NetEase 1.0.3: virtual bass and dry-priority output

Ported the independent QQ Music DSP implementation into this app's own source.
The build does not reference another app's files. MP3-only streaming, provider,
credentials, PSRAM buffers and five-band Lua interface are unchanged.

The dry EQ pre-gain no longer divides by `1+2*mix`. Bass extraction precedes
that pre-gain, uses an HPF plus three cascaded LPFs, then soft even/odd excitation
and output band-pass filtering. Mix fades over 10 ms; unchanged dry filters retain
history on toggles. The two branches meet only after the final 4x volume curve.

The output stage uses 256 samples of lookahead (5.80 ms at 44.1 kHz), an 80 ms
release and independently constrained dry/bass gains. Bass cannot lower dry gain:
dry overload alone controls the dry target; bass yields when remaining peak
space is insufficient. Normal sample ceiling is .96, emergency hard guard .98.
Delay storage is 3148 bytes in the existing PSRAM instance; EOF drains the tail.
`clipped_samples`, `limited_samples`, `bass_limited_samples` and gain telemetry
distinguish hard clipping from normal protection.

New defaults, from the user's screenshot: 180/420/1000/2500/4300 Hz EQ gains
6/4.2/-3.5/-2.5/-.8 dB; HPF 150 Hz; bass on, mix .20, drive 3; extraction
75–200 Hz; harmonic output 150–495 Hz. Existing saved settings are not migrated
or overwritten. Native fallback and package/settings.lua are tested together.

Architecture reference: [Bankstown](https://github.com/chadmed/bankstown) for
filtered additive harmonic generation; [audiojs/dynamics](https://github.com/audiojs/dynamics)
for lookahead/stream flushing concepts. No third-party DSP source was copied;
no runtime dependency was added.

Validation on 2026-11-16: ESP32-S3 build, 32 app/native host tests, seven DSP test
groups, two web suites and 100-cycle native memory/failure injection all passed.
Host DSP tests compile production float32 code: dry identity, vocal probes,
harmonic generation, 8–48 kHz stress, volume 0–100, overload, toggles, silence,
block boundaries and tail drain. Hard-clip guard hits were zero in these tests.

This is sample-peak protection, not oversampled true-peak or analog speaker
protection. This port was not installed/recorded on hardware in this release task.
