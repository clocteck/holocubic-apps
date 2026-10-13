param(
  [Parameter(Mandatory=$true)][string]$Catalog,
  [Parameter(Mandatory=$true)][string]$Device,
  [Parameter(Mandatory=$true)][string]$BackupDirectory
)
$ErrorActionPreference='Stop'
function Api([string]$Path,[string]$Method='GET',$Body=$null) {
  $arguments=@{Uri=$Device.TrimEnd('/')+$Path;Method=$Method;TimeoutSec=30}
  if ($null -ne $Body) { $arguments.Body=$Body; $arguments.ContentType='application/json' }
  $result=Invoke-RestMethod @arguments
  if ($result -is [string] -or $result.ok -eq $false) { throw ('Unexpected API response: '+$Path) }
  return $result
}
function RenameRemote([string]$From,[string]$To) {
  Api ('/api/system/fs/rename?from='+[uri]::EscapeDataString($From)+'&to='+[uri]::EscapeDataString($To)) 'POST' | Out-Null
}
$content=[IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Catalog).Path)
$catalogDoc=[Text.Encoding]::UTF8.GetString($content)|ConvertFrom-Json
if ($catalogDoc.stations.Count -lt 1 -or $catalogDoc.stations.Count -gt 2000) { throw 'Invalid catalog count' }
$system=Api '/api/system/state'
$currentId=$system.current_app.id
if ($currentId -and $currentId -ne 'radio') { throw 'Another App is foreground; refusing to close it' }
$previous=$null
if ($currentId -eq 'radio') { $previous=Api '/radio/api/state' }
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$target='/sd/data/radio/stations.json'
$temporary='/sd/data/radio/stations.import-'+$stamp+'.json'
$backup='/sd/data/radio/stations.before-import-'+$stamp+'.json'
$originalStat=Api ('/api/system/fs/stat?path='+[uri]::EscapeDataString($target))
if ($originalStat.entry.is_dir) { throw 'Catalog target is a directory' }
# Stage first, before taking the current App offline. No whole-file readback.
$uploaded=Api ('/api/system/fs/upload?path='+[uri]::EscapeDataString($temporary)) 'PUT' $content
if ($uploaded.entry.size -ne $content.Length) { throw 'Staged upload size mismatch; original catalog untouched' }
if ($currentId -eq 'radio') { Api '/api/system/exit' 'POST' | Out-Null }
$deadline=(Get-Date).AddSeconds(20)
while ((Api '/api/system/state').current_app.id -eq 'radio') {
  if ((Get-Date) -gt $deadline) { throw 'Radio did not exit; original catalog untouched' }
  Start-Sleep -Milliseconds 300
}
# Retain the old file on SD and also download it for recovery, not upload checking.
RenameRemote $target $backup
New-Item -ItemType Directory -Force -Path $BackupDirectory | Out-Null
$localBackup=Join-Path $BackupDirectory ('stations.before-import-'+$stamp+'.json')
try {
  Invoke-WebRequest -Uri ($Device.TrimEnd('/')+'/api/system/fs/file?path='+[uri]::EscapeDataString($backup)) -OutFile $localBackup -TimeoutSec 30
  Get-Content -LiteralPath $localBackup -Raw -Encoding utf8 | ConvertFrom-Json | Out-Null
  RenameRemote $temporary $target
} catch {
  RenameRemote $backup $target
  throw
}
$installed=Api ('/api/system/fs/stat?path='+[uri]::EscapeDataString($target))
if ($installed.entry.size -ne $content.Length) { throw 'Installed size mismatch; old catalog retained in backup' }
Api '/api/system/launch?id=radio' 'POST' | Out-Null
$deadline=(Get-Date).AddSeconds(25)
do {
  $state=$null
  try { $state=Api '/radio/api/state' } catch { }
  if ($state.storage) { break }
  if ((Get-Date) -gt $deadline) { throw 'App load timed out; catalog backups retained' }
  Start-Sleep -Milliseconds 400
} while ($true)
if ($state.storage_error) { throw $state.storage_error }
$loaded=Api '/radio/api/stations'
if ($loaded.stations.Count -ne $catalogDoc.stations.Count) { throw 'App did not load the full catalog' }
if ($previous) {
  Api '/radio/api/control' 'POST' (@{action='volume';value=$previous.volume}|ConvertTo-Json -Compress) | Out-Null
  $same=@($loaded.stations|Where-Object {$_.url -eq $previous.station.url}|Select-Object -First 1)
  if ($same.Count -and $previous.status -ne 'idle') {
    Api '/radio/api/control' 'POST' (@{action='play';id=$same[0].id}|ConvertTo-Json -Compress) | Out-Null
  } elseif ($previous.status -eq 'idle') {
    Api '/radio/api/control' 'POST' '{"action":"stop"}' | Out-Null
  }
}
[PSCustomObject]@{Count=$loaded.stations.Count;DeviceFile=$target;Bytes=$installed.entry.size;LocalFile=(Resolve-Path $Catalog).Path;DeviceBackup=$backup;LocalBackup=$localBackup;Source=$state.storage.stations_source}|ConvertTo-Json
