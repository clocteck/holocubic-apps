# Codex Buddy Bridge

This is a small local bridge for the `codex_buddy` Lua app. It exposes a Claude Desktop Buddy style state model over HTTP so the device can poll the computer instead of speaking BLE.

## Run

```powershell
python .\tools\codex_buddy_bridge\server.py --host 0.0.0.0 --port 8788
```

The Lua app defaults to:

```text
http://192.168.0.80:8788
```

If your computer IP changes, copy `codex_buddy/config.example.json` to `codex_buddy/config.json` on the SD card and edit `bridge_url`.

## Endpoints

```text
GET  /state
POST /permission
```

Permission body:

```json
{"id":"req_abc","decision":"once"}
```

Supported decisions: `once`, `approve`, `deny`.

`server.py` reads the newest `~/.codex/sessions/**/*.jsonl` file. It maps Codex `task_started`, `task_complete`, `turn_aborted`, `error`, and `token_count.rate_limits` events into the Buddy state model.

Quota fields are remaining percentages:

```text
quota_5h_pct = 100 - rate_limits.primary.used_percent
quota_7d_pct = 100 - rate_limits.secondary.used_percent
```

`POST /permission` validates and records `once`, `approve`, or `deny`, but it does not apply the decision inside VSCode Codex. The current VSCode Codex app-server does not expose an external approval API to this bridge. The bridge only shows `waiting` when the session log contains a pending escalated shell call.

You can still pass `--state-file state.json`; its fields are merged into `/state` for local testing or manual overrides.
