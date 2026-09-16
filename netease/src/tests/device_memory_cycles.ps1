param([ValidateSet('netease','qqmusic')][string]$App='qqmusic',[int]$Cycles=2,[int]$HoldSeconds=0,[string]$Device='http://192.168.0.226')
$ErrorActionPreference='Stop'
function Snapshot([string]$Phase) {
  $s=Invoke-RestMethod "$Device/$App/status" -TimeoutSec 10
  [pscustomobject]@{time=(Get-Date -Format HH:mm:ss);app=$App;phase=$Phase;status=$s.status;error=$s.error;position=$s.position;psram_free=$s.stats.psram_free;internal_free=$s.stats.internal_free;bitrate=$s.stats.bitrate;favorites_loaded=$s.catalog.favorites.loaded;charts_loaded=($s.catalog.top26.loaded+$s.catalog.top27.loaded)} | ConvertTo-Json -Compress | Write-Host
  return $s
}
function Control($Action,$Fields=@{}) {
  $s=Invoke-RestMethod "$Device/$App/status" -TimeoutSec 10
  $b=@{action=$Action;token=$s.token};foreach($k in $Fields.Keys){$b[$k]=$Fields[$k]}
  $r=Invoke-RestMethod "$Device/$App/control" -Method POST -ContentType 'application/json' -Body ($b|ConvertTo-Json -Compress) -TimeoutSec 10
  if(-not $r.ok){throw 'Control failed'}
}
for($cycle=1;$cycle -le $Cycles;$cycle++) {
  $current=(Invoke-RestMethod "$Device/api/system/state").current_app.id
  if($current){throw 'Start this test from the device home page; another app is active.'}
  Write-Host ((Get-Date -Format HH:mm:ss)+" $App cycle=$cycle launch")
  $null=Invoke-RestMethod "$Device/api/system/launch?id=$App" -Method POST -TimeoutSec 15
  try {
    $deadline=[DateTime]::UtcNow.AddSeconds(40)
    do {
      Start-Sleep -Seconds 2
      try {$s=Invoke-RestMethod "$Device/$App/status" -TimeoutSec 5}catch{continue}
      if($s.logged_in -and @($s.list.items).Count -gt 0){break}
    }while([DateTime]::UtcNow -lt $deadline)
    if(-not $s.logged_in -or @($s.list.items).Count -eq 0){throw 'No logged-in song list; no credentials were accessed.'}
    Start-Sleep -Seconds 5
    $s=Snapshot 'opened'
    $html=(Invoke-WebRequest "$Device/$App/" -TimeoutSec 10).Content
    if($html -notmatch 'href="/main"[^>]*>回到主页'){throw 'Deployed home link is not /main'}
    if($App -eq 'qqmusic' -and $html.Contains('每日推荐')){throw 'Daily tab still deployed'}
    $selection=if($App -eq 'netease'){@{index=1;list_revision=$s.list.revision}}else{@{index=1;revision=$s.revision}}
    Control 'select' $selection
    for($song=1;$song -le 3;$song++) {
      $deadline=[DateTime]::UtcNow.AddSeconds(35)
      do {
        Start-Sleep -Seconds 2
        $s=Invoke-RestMethod "$Device/$App/status" -TimeoutSec 5
        if($s.status -eq 'playing' -or $s.error){break}
      }while([DateTime]::UtcNow -lt $deadline)
      $null=Snapshot "song-$song-start"
      Start-Sleep -Seconds 10
      $null=Snapshot "song-$song-end"
      if($song -lt 3){Control 'next'}
    }
    for($remaining=$HoldSeconds;$remaining -gt 0;$remaining-=15){
      Start-Sleep -Seconds ([Math]::Min(15,$remaining))
      $null=Snapshot 'continuous-play'
    }
  } finally {
    $null=Invoke-RestMethod "$Device/api/system/exit" -Method POST -TimeoutSec 15
    Write-Host ((Get-Date -Format HH:mm:ss)+" $App cycle=$cycle exited; settle 15 seconds")
    Start-Sleep -Seconds 15
  }
}
