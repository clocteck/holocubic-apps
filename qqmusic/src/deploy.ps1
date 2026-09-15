param([string]$Device='http://192.168.0.226',[switch]$SwitchApp)
$ErrorActionPreference='Stop'
$package=(Resolve-Path (Join-Path $PSScriptRoot '../package')).Path
function Api([string]$Path,[string]$Method='GET') {
  $r=Invoke-RestMethod ($Device+$Path) -Method $Method -TimeoutSec 20
  if ($r.ok -eq $false) { throw "Device operation failed: $Path" }; return $r
}
$current=(Api '/api/system/state').current_app.id
if ($current -and $current -ne 'qqmusic' -and -not $SwitchApp) { throw 'Another app is running; use -SwitchApp only when a foreground switch is authorized.' }
if ($current) { $null=Api '/api/system/exit' 'POST' }
$deadline=[DateTime]::UtcNow.AddSeconds(15)
do {
  if (-not (Api '/api/system/state').current_app) { break }
  if ([DateTime]::UtcNow -gt $deadline) { throw 'App exit timed out.' }
  Start-Sleep -Milliseconds 250
} while ($true)
# Only upload package files. Never read, overwrite, or remove account data.
foreach ($entry in Get-ChildItem -LiteralPath $package -File -Recurse) {
  $relative=[IO.Path]::GetRelativePath($package,$entry.FullName).Replace('\','/')
  $path='/sd/apps/qqmusic/'+$relative
  $reply=Invoke-RestMethod ($Device+'/api/system/fs/upload?path='+[uri]::EscapeDataString($path)) -Method PUT -InFile $entry.FullName -ContentType 'application/octet-stream' -TimeoutSec 60
  if ($reply.ok -eq $false -or $reply.entry.size -ne $entry.Length) { throw "Upload length check failed: $relative" }
  Write-Output "Uploaded $relative ($($entry.Length) bytes)"
}
$null=Api '/devtools/api/apps/rescan' 'POST'
$null=Api '/api/system/launch?id=qqmusic' 'POST'
Write-Output 'QQ Music launched; existing account data preserved.'
