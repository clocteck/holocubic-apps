# Clawd Monitor for HoloCubic

Clawd Monitor displays live Codex lifecycle state and local hourly weather on a
320 x 240 HoloCubic. Every mascot frame is generated from the canonical 12 x 8
sprite from clawdmoji project.

## Display

- Codex state animations are native 160 x 160 indexed GIFs. There is no runtime
  scaling or cropped desktop artwork.
- IDLE rotates every random 2 to 5 whole minutes through 24 narrative loops:
  12 everyday micro-stories with two reactions/directions each. Every story
  uses varied frame timing, a calm setup, an interaction, and a seamless return
  over roughly 6.8 seconds instead of repeating a short mascot-plus-prop pose.
- Each supported Codex Hook event has 4 distinct expressions (Stop has 5),
  with separate Error and Sleeping families.
- The launcher icon is a native 75 x 75 ClawdMoji render with no resampling.
- Codex state, project, tool category, and connection state appear below Clawd.
- The lower panel uses a square-edged Powerline/Oh My Zsh prompt treatment.
  Its state and state-timer segments inherit the current Clawd state color.
- Non-idle states show `Cmm:ss` for the current chat/turn and `Smm:ss` for the
  uninterrupted current state, followed by 5h usage, reset time, and week use.
- A fresh IDLE screen labels those slots as `C CHAT / S STATE`; after a session
  completes, it keeps the previous total as `Cmm:ss / LAST`.
- The top bar shows the current China Standard Time beside the bridge status.

## Weather instrument

The weather page reads the location already stored by the system in
`/sd/apps/settings.json`. It resolves that city through Open-Meteo geocoding and
requests current conditions plus 8 hours of hourly temperature, humidity,
precipitation probability/amount, wind direction/speed, and gusts.

The hero animation is selected from 60 generated ClawdMoji scenes: 10 weather
families multiplied by 6 temperature/humidity moods. The rail prioritizes the
next three hours' rain probability/time and maximum gust, followed by four
hourly cells. The last good forecast remains visible if a refresh fails.

## Connection

The data path follows the same host-configured pattern as AIDA Monitor:

```text
Codex command hook ----> localhost:17321/event
Codex session JSONL ---> fallback monitor (1.2s poll)
                         -> SSE bridge on the PC
HoloCubic             <- http://HOST:17321/events
```

Open the device management UI and select **Clawd Monitor**. Its independent
page at `/holo_pet/` lets you edit the Codex host IP and port, save/reconnect,
and test `/health`. Defaults:

```text
Host: 192.168.0.100 (replace with the Codex PC's LAN address)
Port: 17321
Path: /events
```

The installer starts `codex-holocubic-server.js` immediately and registers a
hidden per-user Windows logon startup entry. The hook also starts it on demand.
The bridge listens on the LAN so the HoloCubic can maintain an SSE connection.

Official hooks remain the primary path. Until Codex writes a trusted hook hash
after the user reviews `/hooks`, the bridge follows Clawd on Desk's fallback
strategy and incrementally maps the active Codex JSONL session:

- `task_started` / `user_message` -> thinking
- function, custom tool, and web search calls -> working
- `task_complete` -> done

The fallback reads record type metadata and state fields only; it does not send
prompt, assistant, tool argument, or tool output contents to the device.

## Usage limits

Codex App Server officially exposes `account/rateLimits/read` and
`account/rateLimits/updated`. The installed Codex desktop process owns its
App Server over stdio, so this bridge does not start or interfere with a second
authenticated Codex process. Instead, every 30 seconds it reads only the most
recent local `rate_limits` object already emitted into Codex session telemetry.

Only these fields are retained and sent to the device:

- 300-minute window `used_percent`
- 300-minute window `resets_at`, formatted as local `HH:MM`
- 10080-minute window `used_percent`

Prompts, responses, tool arguments, and tool results are not parsed or sent.

## Generating the ClawdMoji pack

Regenerate all status and weather assets plus their Lua manifest:

```powershell
python tools\generate_clawdmoji_pack.py
```

The generator also writes contact sheets under `art/` and a build report beside
the generated assets. `art/idle-stories-preview.gif` is a 4 x 3 animated QA
sheet containing one representative variant of every IDLE story.

## Codex hooks

Install or repair the hooks:

```powershell
node bridge/install-codex-hook.js
```

Uninstall only the Clawd Monitor entries:

```powershell
node bridge/install-codex-hook.js --uninstall
```

Codex may ask you to review the command hook. Open `/hooks` and approve it when
prompted. The hook always returns `{}` for `PermissionRequest`, leaving the
decision in Codex's native approval UI.

The installed release exposes these 10 events, all registered by the installer:

- `SessionStart`, `UserPromptSubmit`
- `PreToolUse`, `PermissionRequest`, `PostToolUse`
- `PreCompact`, `PostCompact`
- `SubagentStart`, `SubagentStop`, `Stop`

Only lifecycle state, event, project directory name, normalized tool category,
session id, model slug, and subagent id are forwarded. Prompt and assistant
contents are not sent.

## Tests

```powershell
node --test bridge/codex-holocubic-hook.test.js
npx -y luaparse -q package/weather_client.lua package/config.lua package/codex_client.lua package/web.lua
```
