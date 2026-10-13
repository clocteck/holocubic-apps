# Unified volume integration

## Contract

Firmware owns the integer `volume` in `/sd/apps/settings.json` (0–100, default 25).
No additional persistent configuration file or Lua service is introduced.
`sys.getvolume()` reads RAM. `sys.setvolume(n)` changes RAM and schedules a
debounced save; `sys.getvolumestate()` distinguishes accepted, saved and failed.
HTTP GET/POST `/audio/api/settings` exposes the same state, with POST query `volume`.
The SD merge uses the shared FS lock and temporary/backup files, preserving other
settings. Known Lua file writes/renames and native HTTP uploads notify the manager
to re-merge the authoritative volume after other apps save stale settings.

New firmware clients poll RAM every 200ms; they do not poll the JSON file or use
an IPC endpoint/service slot. Legacy clients read the JSON once at startup and
apply local edits only for that session. New-API errors never trigger SD fallback.

## Packages

- `mp3_player`: normalized 0–1 player gain; volume no longer belongs to EQ JSON.
- `netease`, `qqmusic`: existing 0–100 native setters; private settings saves
  omit volume while preserving EQ and playback preferences.
- `radio`: `volume` replaces `radio_volume` as the source; native gain is unchanged.
- `mjpeg_player`: removes fixed 20% playback gain; uses the normalized master value.
- `display_schedule`: builtin tone amplitude and MP3 ringtone gain follow master volume.
- `holo-retro-go`: Lua connects firmware state to the native audio mailbox;
  game-menu edits return to Lua and then firmware. On legacy firmware they are
  session-only. Lua/audio tasks exchange atomic values, not live driver pointers.
- `launcher`: the browser uses firmware HTTP volume API, not JSON uploads. Its
  bundled alarm service installer also copies `volume.lua` and checks the bundle build.

Xiaozhi and AirPlay are deliberately excluded. Their existing behavior is unchanged.

## Build and deployment boundary

Firmware C++ changes require a new firmware build. Retro-Go C changes require both
`retrogo.so` and `gwenesis.so` to be rebuilt. Existing binaries were not overwritten
or rebuilt by this source change. Music/video/radio/alarm integrations use their
existing native interfaces; they do not require a new native module for this change.

Ship complete package contents, including each `volume.lua`. Deploy alarm service
files to `/sd/apps/display_schedule`, as well as its Launcher bundle. Deploy both
new Retro-Go modules together with its Lua files; old modules log that an update
is required and cannot implement this volume contract.

## Host regression checks

```powershell
python -X utf8 tools/test_volume.py
node launcher/src/volume-settings.test.cjs
python -B -X utf8 netease/src/tests/test_app.py LuaTests
python -B -X utf8 qqmusic/src/tests/test_app.py AppTests
python -X utf8 tools/test_i18n.py
node tools/test_i18n.cjs
```

These checks exercise Lua adapters, browser behavior, existing app flows and
source-level firmware wiring. They do not replace native compilation or hardware
testing. Hardware acceptance must include reboot persistence, SD failure/recovery,
all audio paths at 0/25/100, repeated cross-app changes, live game-menu volume,
and simultaneous weather/settings saves. A power cut before the debounced commit
can lose the latest unsaved change; the UI reports it as pending, not saved.
