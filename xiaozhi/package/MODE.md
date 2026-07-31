# XiaoZhi modes

`xiaozhi` can run in two modes.

## Standalone

Install only `xiaozhi`.

`main.lua` cannot find the `xiaozhi-service` IPC endpoint or
`XIAOZHI_SERVICE` fast-path bridge, so it starts the normal runtime. Wake word
detection, audio capture/playback, activation, protocol, MCP, and UI are all
owned by `xiaozhi`.

## Service backed UI

Install `xiaozhi` and `xiaozhi-service`.

`xiaozhi-service` owns the non-UI resources: wake word detection, audio,
activation, protocol, MCP, config, and web management. It exposes the
`xiaozhi-service` firmware IPC endpoint, with `_G.XIAOZHI_SERVICE` kept as a
same-state-machine fast path.

When `xiaozhi` is launched while that endpoint exists, it starts `ui_ipc.lua`
instead of the full runtime. The UI subscribes to service snapshots and sends
controls through IPC:

- `snapshot()` returns the current UI state.
- `subscribe(callback)` pushes UI state changes.
- `control(action, value)` handles `toggle`, `start`, `stop`, and `wake`.

No UI synchronization uses HTTP. If `xiaozhi-service` is installed but its
endpoint is not ready yet, `xiaozhi` starts/waits for the service and remains
UI-only. If the service package is not installed, standalone mode is used.
In IPC mode the status bar network label shows `IPC`, and activation/pairing
codes are rendered from service snapshots just like standalone activation.

## Floating service UI

When `xiaozhi-service` is configured for floating UI mode, it loads
`ui.lua` from `/sd/apps/xiaozhi-service`, then the shared UI driver selects a
floating style from:

```text
/sd/apps/xiaozhi-service/ui/<type>.lua
```

The service still owns non-UI runtime resources and uses the firmware
`service_ui` canvas API for floating drawing. Foreground app UI styles are a
separate plugin domain under:

```text
/sd/apps/xiaozhi/ui/<type>.lua
```

The WebUI scans both directories. App styles named `driver` or `headless` are
internal and are not shown as selectable app UI styles. Floating styles can also
use assistant character resources from:

```text
/sd/apps/xiaozhi-service/ui/character/*.rgb565
```
