# AIDA Monitor

Lua/LVGL app for displaying AIDA64 RemoteSensor values. The PC only needs AIDA64 running; this app connects directly to AIDA64's HTTP SSE endpoint.

## AIDA64 setup

1. Open AIDA64.
2. Go to `File -> Preferences -> Hardware Monitoring -> LCD`.
3. Enable RemoteSensor/LCD support.
4. Open `设置 > LCD > LCD 项目 > 导入` and import `holo-aida.rslcd`.
5. The profile uses labels that match `config.lua`, for example:
   - `CPU Usage`
   - `CPU Frequency`
   - `CPU Temperature`
   - `GPU Usage`
   - `GPU Frequency`
   - `GPU Temperature`
   - `Memory Usage`
   - `VRAM Usage`
   - `CPU Fan`

RemoteSensor commonly exposes an SSE stream at:

```text
http://<pc-ip>:80/sse
```

If port 80 is busy, set another RemoteSensor port in AIDA64 and update `config.lua`.

If `/sse` only shows `data: ReLoad`, RemoteSensor is running but no sensor item data is being emitted yet. Import the profile from `设置 > LCD > LCD 项目 > 导入`, click `Apply`, then refresh `/sse`; it should become a longer line such as `data: Page0|{|}Simple1|CPU Usage 12%...`.

## Configure

Open the app Web control page from the launcher, enter the IP address of the PC running AIDA64, then save. The page writes `config.lua` and reconnects the stream.

You can still edit `package/config.lua` manually:

```lua
config.host = "192.168.31.100"
config.port = 80
```

If a value does not show up, add the exact LCD label to that metric's `aliases` list.

## Import the AIDA64 LCD profile

Open the app Web control page and download `holo-aida.rslcd`, or use the copy in `package/holo-aida.rslcd`.

In AIDA64, import it from:

```text
设置 > LCD > LCD 项目 > 导入
```

After importing, click `Apply`. The browser URL `http://<pc-ip>:80/sse` should show `data:` lines containing labels such as `CPU Usage`, `GPU Temperature`, and `Memory Usage`.

## Install to device

This app follows the project app layout:

```text
aida_monitor/package/app.info
aida_monitor/package/main.lua
aida_monitor/package/aida_client.lua
aida_monitor/package/config.lua
aida_monitor/package/main.png
aida_monitor/package/info.html
```

Upload the `package` contents to:

```text
/sd/apps/aida_monitor
```

Minimum files:

```text
/sd/apps/aida_monitor/main.lua
/sd/apps/aida_monitor/aida_client.lua
/sd/apps/aida_monitor/config.lua
/sd/apps/aida_monitor/web.lua
/sd/apps/aida_monitor/app.info
/sd/apps/aida_monitor/main.png
/sd/apps/aida_monitor/info.html
/sd/apps/aida_monitor/holo-aida.rslcd
```

Then rescan apps and launch `aida_monitor`.

Or run the helper from this folder:

```powershell
.\deploy.ps1 -Device http://192.168.31.200 -Launch
```

## Notes

- This app parses AIDA64 RemoteSensor `data:` lines split by `{|}`.
- It automatically reconnects when the stream closes or no data arrives for a few seconds.
- The HOME key exits the app when available.
