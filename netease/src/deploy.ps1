param([string]$Device='http://192.168.0.226')
$ErrorActionPreference='Stop'
$package=(Resolve-Path (Join-Path $PSScriptRoot '../package')).Path
function Api([string]$Path,[string]$Method='GET') {
  $result=Invoke-RestMethod ($Device+$Path) -Method $Method -TimeoutSec 30
  if ($result.ok -eq $false) { throw "Device operation failed: $Path" }
  return $result
}
$state=Api '/api/system/state'
$current=$state.current_app
if ($current -isnot [string]) { $current=$current.id }
if ($current -and $current -ne 'netease') { throw 'Another foreground app is running; left untouched.' }
if ($current -eq 'netease') { $null=Api '/api/system/exit' 'POST' }
$deadline=[DateTime]::UtcNow.AddSeconds(15)
do {
  $current=(Api '/api/system/state').current_app
  if (-not $current) { break }
  if ([DateTime]::UtcNow -gt $deadline) { throw 'App has not exited; no files uploaded.' }
  Start-Sleep -Milliseconds 300
} while ($true)
# Deliberately never enumerate or write /sd/data/netease (session/settings).
$files=Get-ChildItem -LiteralPath $package -File -Recurse | Where-Object {
  $_.Name -notin @('ui18.bin','ui24.bin','qa-screen.png','boot-error.txt')
}
foreach ($entry in $files) {
  $relative=[IO.Path]::GetRelativePath($package,$entry.FullName).Replace('\','/')
  $path='/sd/apps/netease/'+$relative
  $reply=Invoke-RestMethod ($Device+'/api/system/fs/upload?path='+[uri]::EscapeDataString($path)) -Method PUT -InFile $entry.FullName -ContentType 'application/octet-stream' -TimeoutSec 60
  if ($reply.ok -eq $false -or $reply.entry.size -ne $entry.Length) { throw "Upload verification failed: $relative" }
  Write-Output "Uploaded $relative ($($entry.Length) bytes)"
}
$null=Api '/devtools/api/apps/rescan' 'POST'
$null=Api '/api/system/launch?id=netease' 'POST'
Write-Output 'NetEase launched; credentials and settings were not uploaded or deleted.'
