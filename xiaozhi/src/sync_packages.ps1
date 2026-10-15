$ErrorActionPreference = 'Stop'
$front = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../package'))
$service = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../xiaozhi-service/package'))
# Canonical shared Lua modules live in xiaozhi/package; packaged copies remain standalone.
foreach ($name in @('store.lua','preferences.lua','i18n.lua','identity.lua','settings_controller.lua','settings.html','playback_session.lua','audio.lua','playback_queue.lua','volume.lua','protocol.lua')) {
    Copy-Item -LiteralPath (Join-Path $front $name) -Destination (Join-Path $service $name) -Force
}
