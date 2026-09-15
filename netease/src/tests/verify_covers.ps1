$ErrorActionPreference='Stop'
$device='http://192.168.0.226'
foreach ($tab in @(2,3,1)) {
  & "$PSScriptRoot/verify_libraries.ps1" -Device $device -Tabs $tab
  $state=Invoke-RestMethod "$device/netease/status"
  $body=@{action='back';token=$state.token}|ConvertTo-Json -Compress
  $null=Invoke-RestMethod "$device/netease/control" -Method POST -ContentType 'application/json' -Body $body
  $deadline=[DateTime]::UtcNow.AddSeconds(25)
  do {
    Start-Sleep -Milliseconds 500
    $state=Invoke-RestMethod "$device/netease/status"
    if ($state.covers.ready) { break }
    if ([DateTime]::UtcNow -ge $deadline) { throw "Cover $tab not ready: $($state.covers.last_error)" }
  } while ($true)
  [PSCustomObject]@{Tab=$tab;Page=$state.page;Cover=$state.covers}|ConvertTo-Json -Depth 3 -Compress
}
