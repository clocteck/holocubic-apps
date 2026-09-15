param([string]$Device='http://192.168.0.226')
$ErrorActionPreference='Stop'
function State { Invoke-RestMethod "$Device/qqmusic/status" -TimeoutSec 10 }
function Control($Action,$Fields=@{}) {
  $s=State;$doc=@{action=$Action;token=$s.token};foreach($k in $Fields.Keys){$doc[$k]=$Fields[$k]}
  $null=Invoke-RestMethod "$Device/qqmusic/control" -Method POST -ContentType 'application/json' -Body ($doc|ConvertTo-Json -Depth 5 -Compress) -TimeoutSec 10
}
$start=State
if (-not $start.logged_in) { throw 'Account library verification requires user login; no login was attempted.' }
$restoreName=$start.song.name
if ($start.page -eq 'login') { Control 'home' }
foreach ($tab in @(4,5)) {
  Control 'library' @{tab=$tab}
  $deadline=[DateTime]::UtcNow.AddSeconds(22)
  do {
    Start-Sleep -Milliseconds 500;$s=State
    if ($s.error -or $s.message -ne '加载中…') { break }
  } while ([DateTime]::UtcNow -lt $deadline)
  [pscustomobject]@{tab=$tab;title=$s.list.title;items=$s.list.items.Count;error=$s.error;operation=$s.provider.operation;http=$s.provider.http}
}
Control 'library' @{tab=3}
$deadline=[DateTime]::UtcNow.AddSeconds(20)
do {Start-Sleep -Milliseconds 500;$s=State;if($s.error -or $s.list.items.Count -gt 0){break}}while([DateTime]::UtcNow -lt $deadline)
$item=$s.list.items|Where-Object name -eq $restoreName|Select-Object -First 1
if ($item) {
  $revision=$s.revision;$count=$s.list.items.Count
  Control 'select' @{index=$item.index;revision=$revision}
  Start-Sleep -Milliseconds 700;$s=State
  [pscustomobject]@{test='list survives playback';page=$s.page;before=$count;after=$s.list.items.Count;revision_stable=($s.revision -eq $revision);song=$s.song.name;error=$s.error}
}
