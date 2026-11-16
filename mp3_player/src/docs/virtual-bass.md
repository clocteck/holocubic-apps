# Music 1.14 audio update

The Music mono playback path now uses the same dry-priority protection design as
QQ/NetEase, adapted to its seven-band esp-dsp filters, existing volume/track-RMS
gain, MP3/WAV decoder/read/producer paths and configurable limiter threshold.
Other apps' copies of audio.so are not replaced. Stereo-source downmix is covered;
the separate native stereo-output path retains its existing behavior.

## Processing and state

- Extract the original low band with HPF + three cascaded LPFs, drive, rational
  soft excitation `s=x/(1+abs(x))`, even/odd mix, then harmonic band-pass.
- Keep original dry EQ/HPF and volume/loudness gain. No bass-dependent dry pre-gain.
- Fade wet mix over 10 ms. Reuse unchanged filter coefficients/history.
- After combined volume and track gain, apply a 256-sample dual-path lookahead
  limiter. Dry gain depends on dry alone; wet gain uses remaining signed headroom.
  Adjacent-block minima and linear interpolation constrain every output sample.
  Release is approximately 80 ms, using the module's existing base-2 pow routine.
- Honor configured mono peak threshold up to the .96 safety ceiling; emergency
  guard at .98. Add clipped/bass-limited/delay/state-byte telemetry. State adds
  about 3.1 KiB inside the existing instance, with no per-sample allocation.
- Drain delayed PCM once at EOF, including short tracks and partial blocks.
- Stage Lua effect values on the stack, then take a short audio lock only for
  native config/filter updates. No Lua API call is inside that lock (OOM-safe).
  Decoder PCM processing uses the same lock. Loudness state stays outside the
  staged settings so updates cannot overwrite measured track RMS.
  If the existing stop path forcibly removes a stalled producer, it clears the
  orphaned DSP lock only after both worker tasks have stopped.

The peak limiter is sample-based, not true-peak, and cannot guarantee that the
physical speaker/amplifier remains undistorted at extreme volume.

## Default preset and compatibility

The new default reproduces the user's 2026-11-16 five EQ bands, with two optional
Music bands at unity: frequencies [180,250,420,1000,1250,2500,4300], gains
[6,0,4.2,-3.5,0,-2.5,-.8] dB, Q=1. HPF=150, bass on, mix=.20, drive=3,
extraction 75–200 Hz, output 150–495 Hz. Even/odd weights are 1.6/.8, matching the
ported excitation. The existing firmware volume remains authoritative.

`package/effects_defaults.lua`, native fallback and web reset values match.
Saved old seven-band gains retain frequencies [160,250,420,780,1250,2800,4300]
and the original Q values; snapshots now include `eq_freqs` / `eq_q` for lossless
round trips. Reset explicitly selects the new preset. Output-LPF slider step is
1 Hz so 495 Hz is not rounded to 500 Hz by the browser.

## Build and validation

`src/build.ps1 -DependencyBuild <existing-IDF-build>` recompiles current module
source, links existing unchanged codec/esp-dsp libraries, checks undefined symbols
before stripping, and refreshes package/modules/audio.so. It needs the installed
ESP32-S3 toolchain and the dependency build described in README.md. Existing RWX
LOAD warnings are a known property of this dynamic-module format.

On 2026-11-16, six native DSP/lifecycle groups, three package/web/default-migration tests,
and seven shared volume tests passed. Native tests extract actual production
functions plus the vendor scalar biquad reference and the module's own float math
approximations. They cover 8–48 kHz, up to 6x combined gain, peak thresholds,
first/last/block-edge impulses, exact EOF drain, arbitrary decoder fragmentation,
stereo-to-mono, dry filter identity, low-band harmonics, toggles and silence.
No hard-clip guard hits. Vocal probes at 400/1000/2500 Hz changed <.15 dB.

The host harness mocks codec/file IO; it does not run MP3/WAV decoding or the S3
vector assembly on Windows. No new hardware deployment/listening claim is made.
Package tests execute real Lua defaults/merge/native-call logic and parse/check
the actual embedded web JavaScript.

Reference: [Bankstown](https://github.com/chadmed/bankstown), additive band-limited
bass excitation. Implementation is local C, with no copied third-party DSP source
or new runtime package dependency.
