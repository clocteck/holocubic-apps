param([string]$Device='http://192.168.0.226',[int[]]$Tabs=@(1,2,3))
$ErrorActionPreference='Stop'
function Status { Invoke-RestMethod ($Device+'/netease/status') -TimeoutSec 10 }
$deadline=[DateTime]::UtcNow.AddSeconds(30)
do {
  $state=Status
  if ($state.logged_in -and $state.ui_ready) { break }
  if ([DateTime]::UtcNow -ge $deadline) { throw 'Login/UI not ready; credentials were not inspected.' }
  Start-Sleep -Milliseconds 500
} while ($true)
foreach ($tab in $Tabs) {
  $body=@{action='library';tab=$tab;token=$state.token}|ConvertTo-Json -Compress
  $reply=Invoke-RestMethod ($Device+'/netease/control') -Method POST -ContentType 'application/json' -Body $body -TimeoutSec 10
  if (-not $reply.ok) { throw 'Library control failed' }
  $deadline=[DateTime]::UtcNow.AddSeconds(30)
  do {
    Start-Sleep -Milliseconds 500
    $state=Status
    if ($state.error -or ($state.page -eq 'songs' -and $state.message -ne '加载中…' -and $state.provider.phase -eq 'complete')) { break }
    if ([DateTime]::UtcNow -ge $deadline) { throw "Library $tab timed out" }
  } while ($true)
  [PSCustomObject]@{Tab=$tab;Title=$state.list.title;Page=$state.page;Items=@($state.list.items).Count;Error=$state.error;Http=$state.provider.http;Code=$state.provider.code;Path=$state.provider.path;Version=$state.ui_version}|ConvertTo-Json -Compress
  if ($state.error) { throw "Library $tab returned an error" }
}
