# XiaoZhi 1.3

## Installation and ownership

Deploy the complete `package/` contents to this app's directory on the SD card.
Both packages are independently installable. With only XiaoZhi installed, its
foreground runtime owns speech. With only XiaoZhi Service installed, the service
owns speech and displays floating UI. With both installed, Service owns speech
and the foreground app uses IPC only; opening the UI does not reload the model
or establish a second server connection.

## Shared configuration and identities

Both packages read and update **/sd/data/xiaozhi/config.json**. Do not deploy a
runtime config from the source tree. On first startup, migration prefers an
existing configured service connection, then a configured foreground connection.
Old files are retained. Conflicting foreground configuration is archived under
`legacy_foreground`; tokens from different servers are never merged. Subsequent
starts use only the shared configuration. Atomic save keeps `config.json.bak`.

The shared document stores `websocket`, `ota`, `audio`, `ui`, `language`,
`wake`, the active `identity` and archived `identities`. A migrated hardware
identity remains valid until explicitly replaced. A new identity uses a locally
administered virtual MAC for the XiaoZhi protocol, not the Wi-Fi interface.
Client-ID, OTA body and WebSocket headers all use that same persisted identity.

The settings page supports new identity + pairing, retry without rotating identity,
rename, restore and delete archived identities. Archived profiles retain their own
server credentials. Active identities cannot be deleted. Changing identity does
not remove old devices from the cloud console; server pairing policy still applies.

Background enabled state, deny-app list and floating UI remain in
`/sd/apps/xiaozhi-service/service.json`, since these control Service/Launcher rather
than the shared device identity. Foreground style is in the shared `ui.type`.

## Settings

- App alone: `/xiaozhi/`.
- Service (alone or together): `/xiaozhi-service/`; the IPC app redirects there.
- Interface languages: system/default, Simplified Chinese and English. Chat text is
  not translated. ASR/LLM/TTS language remains a server-side setting.
- Wake words: **你好小智** (`wn9s_nihaoxiaozhi`) or **Hi ESP** (`wn9s_hiesp`).
  Both models ship with each package; only one is loaded. End the session before
  changing voice settings. Missing models reject the change without saving it.
- Model paths are local to each package, not a cache in the other app's directory.
- Volume uses the same master-volume adapter as other apps: firmware
  `sys.getvolume/setvolume` when available, otherwise a one-time read of
  `/sd/apps/settings.json`. Legacy edits are session-only, matching those apps.
  The shared XiaoZhi `audio.volume` field is no longer the volume authority.

## Half-duplex audio (native 0.5.0)

The microphone is captured/encoded/uploaded only during listening. TTS uses a
TX-only I2S stream and one playback worker. Spoken interruption and echo
cancellation are not implemented; buttons/web controls can cancel playback.

listen.start uses mode=auto (or manual for push-to-talk). tts.stop only ends
network delivery: the local Opus queue and PCM ring drain first. The worker
writes one DMA ring of silence and waits its duration, then the session waits
another 80–120 ms for the acoustic tail before reopening RX.

Playback retains a 16 KiB PSRAM PCM ring, 120 ms prebuffer and bounded packet
queues. PCM is concatenated across Opus packets; only the final short block is
padded. Playback and capture each use a 32 KiB PSRAM stack, never concurrently.
I2S uses four 128-sample DMA blocks; Opus complexity=0 and -O2 remain enabled.
Native failures remain visible instead of switching to another audio path.

Volume follows the firmware API, with the legacy settings-file compatibility
path preserved. Shared configuration, virtual identities, pairing, language,
wake choices and Web controls are unchanged. Old echo/full-duplex fields are
removed during configuration loading without changing credentials.
