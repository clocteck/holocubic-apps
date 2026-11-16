# Virtual bass v2 / QQ Music 1.0.3

## Problem and design

The old `headroom = EQ_pre_gain / (1 + 2 * mix)` lowered the entire dry signal
by 3.52 dB at mix=0.25. Harmonics were also generated from this attenuated signal.
The final 4x volume curve could still clip after the DSP's earlier clamp.

The new chain retains the existing EQ-only pre-gain and volume curve. It does not
overwrite saved settings or the user's volume. Fresh-install defaults follow the
user's 2026-11-16 screenshot: EQ [6,4.2,-3.5,-2.5,-0.8] dB at
[180,420,1000,2500,4300] Hz, HPF=150, bass enabled, mix=.20, drive=3,
extraction 75–200 Hz, output 150–495 Hz. Lua defaults and native fallback match.

1. Dry: input -> EQ pre-gain -> main HPF -> five EQ bands.
2. Bass: original input -> extraction HPF -> three cascaded extraction LPFs ->
   drive -> smooth even/odd excitation -> output band-pass -> mix.
3. Apply final volume to both paths, then pass them through independent,
   coordinated lookahead gains before converting to int16 PCM.

The excitation is independently implemented using `s = x / (1 + abs(x))` and
`1.6 * abs(s) + 0.8 * (s - x)`. The output high-pass removes the rectifier's DC.
The three low-pass stages reduce excitation of vocal/midrange content. Their
cutoffs are all the configured extraction LPF value (combined response is not
a single Butterworth filter). Mix slews over 10 ms. Unchanged filters retain
their history across effect changes. The source track resets DSP/output history.

## Peak protection and dry priority

The limiter operates after volume, using three 128-sample buffers and a fixed
256-sample delay (5.80 ms at 44.1 kHz, 5.33 ms at 48 kHz). State is 3148 bytes in
the existing PSRAM-backed Music object; no per-sample allocations.

Each complete block has a safe dry target derived ONLY from its dry peak, capped
at unity. The bass target is the minimum remaining signed peak margin over the
block, safe for any dry gain from zero to that dry target. Both targets have an
80 ms release. Adjacent-block minima give the gain at each block boundary;
linear interpolation keeps every intermediate gain below the current safe
target, with continuous gain and lookahead attack. Thus dry gain is identical
whether bass is enabled or disabled, including overload. When room runs out,
the added bass yields first; the dry limiter reacts only to dry overload.

Normal sample ceiling is 0.96 (-0.35 dBFS). The old-style hard clamp at 0.98 is
only an emergency guard, with `clipped_samples` counting actual guard hits.
`limited_samples` and `bass_limited_samples` separately count active protection;
`dry_gain_permille` / `bass_gain_permille` expose current gain. Toggling effects
does not reset these counters or the limiter. EOF drains the lookahead tail.

This is a sample-peak limiter, not an oversampled true-peak limiter. It does not
promise an undistorted analog amplifier/speaker at maximum volume. Psychoacoustic
bass deliberately adds low-band harmonics; perceived vocal loudness and masking
still depend on the music and speaker. Sustained overload necessarily reduces
available bass enhancement. No loudness normalization or vocal separation is used.

## Open-source references

- [Bankstown](https://github.com/chadmed/bankstown), MIT, and its
  [DSP implementation](https://github.com/chadmed/bankstown/blob/main/src/lib.rs):
  reference for a separate filtered nonlinear bass branch added to the dry signal,
  with even/odd excitation and output band-limiting. No source code was copied;
  no Rust/LV2 runtime or external dependency was introduced.
- [audiojs/dynamics](https://github.com/audiojs/dynamics): reference for lookahead
  limiting, ceiling/release controls and draining delayed streaming output.
  The dry-priority dual-path block limiter here is an independent implementation,
  not a port of its limiter.

## Reproducible verification

Run `python qqmusic/src/tests/test_dsp.py` (VS 2022 + numpy on Windows, cc + numpy
elsewhere). The bridge compiles the actual production float32 C DSP and limiter.

- 400 / 1000 / 2500 Hz probes mixed with 73 Hz bass, at 32 / 44.1 / 48 kHz,
  using the device's saved EQ/filters/drive and volume 100: <0.1 dB on/off probe
  change, dry branch bit-identical.
- 55 / 80 / 110 Hz inputs, amplitudes 0.05 / 0.20 / 0.50, legacy baseline preset:
  second-harmonic level +5.44 to +14.75 dB versus the old analytic rectifier
  reference. These are harmonic measurements, NOT total loudness gains.
- Random stress at 8 / 16 / 22.05 / 32 / 44.1 / 48 kHz; volume 0 / 25 / 50 / 100;
  maximum EQ, oversized raw dry/wet inputs, first/last/block-edge impulses:
  zero hard-clamp hits; final PCM peak <=0.96004.
- Bass overload preserves a 997 Hz dry probe within 0.1 dB.
- On/off toggles preserve dry filter history; silence produces exact silence;
  unprocessed output is transparent to int16 quantization; partial final blocks
  and single-sample inputs are correctly drained.

Also run the app/web/native-memory regressions and `src/build.ps1` before deployment.
The added `test_user_defaults` checks the new Lua/native preset, dry identity and
audible-band harmonic generation independently of the legacy-preset comparison.

## Initial deployment verification — 2026-11-16 (before the default-preset update)

Deployed to `http://192.168.1.131/` using `src/deploy.ps1`. The system reports
QQ Music 1.0.3 and the uploaded module stat is 225532 bytes, matching the local
build. All package upload responses passed size checks. Login remained active;
comparison immediately before/after deployment found no changed settings. No
account files were read or written. Baseline tracked package rollback archive:
`src/build/rollback-1.0.2-package.zip` (local build artifact).

All 6 native DSP test groups, 31 app tests, web regression and 100-cycle native
memory/failure-injection checks passed. The ESP32-S3 module built with no unresolved
symbols (the existing linker layout still reports an RWX LOAD-segment warning).

During the user's subsequent active listening, observed read-only status at seven
points over roughly 30 seconds: bass enabled, volume 75, 44.1 kHz MP3, decoded
frames advancing from 1083 to 2301, `clipped_samples=0`, `underflows=0`, native
error=0 throughout. Protection counters increased during peaks (so protection was
actually exercised), with dry gain 0.920 and bass gain 0.165 at one snapshot,
recovering toward unity. Worker CPU telemetry was 261–269 permille. The user's
live volume/switch changes were not overridden. Acoustic output was not recorded.
