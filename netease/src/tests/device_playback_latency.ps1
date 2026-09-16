param([ValidateSet('netease','qqmusic')][string]$App='qqmusic',[string]$Device='http://192.168.0.226')
$ErrorActionPreference='Stop'
function Status { Invoke-RestMethod "$Device/$App/status" -TimeoutSec 10 }
function Control($Action,$Fields=@{}) {
  $s=Status;$body=@{action=$Action;token=$s.token};foreach($k in $Fields.Keys){$body[$k]=$Fields[$k]}
  $r=Invoke-RestMethod "$Device/$App/control" -Method POST -ContentType 'application/json' -Body ($body|ConvertTo-Json -Compress) -TimeoutSec 10
  if(-not $r.ok){throw 'Control failed'}
}
if((Invoke-RestMethod "$Device/api/system/state").current_app.id){throw 'Start from device home page'}
$null=Invoke-RestMethod "$Device/api/system/launch?id=$App" -Method POST -TimeoutSec 15
try {
  $deadline=[DateTime]::UtcNow.AddSeconds(40)
  do {Start-Sleep -Milliseconds 500;try{$s=Status}catch{continue};if($s.logged_in -and $s.list.items[0].index -and $s.list.ready -ne $false){break}}while([DateTime]::UtcNow -lt $deadline)
  if(-not $s.logged_in){throw 'No account available; no login attempted'}
  if(-not $s.boot_icon_loaded -or $s.boot_icon_error){throw 'Startup icon did not preload successfully'}
  Write-Host "$App startup icon preloaded; UI version $($s.ui_version)."
  $favorite=if($App -eq 'netease'){1}else{3}
  $round=0
  foreach($index in @(1,1,2)) {
    $round++
    Control 'library' @{tab=$favorite}
    $deadline=[DateTime]::UtcNow.AddSeconds(25)
    do {Start-Sleep -Milliseconds 300;$s=Status;if($s.list.items[$index-1].index -and $s.list.ready -ne $false){break}}while([DateTime]::UtcNow -lt $deadline)
    $fields=if($App -eq 'netease'){@{index=$index;list_revision=$s.list.revision}}else{@{index=$index;revision=$s.revision}}
    $watch=[Diagnostics.Stopwatch]::StartNew()
    Control 'select' $fields
    if($round -eq 1){Control 'library' @{tab=2}}
    $deadline=[DateTime]::UtcNow.AddSeconds(35)
    do {Start-Sleep -Milliseconds 250;$s=Status;if($s.status -eq 'playing' -or $s.status -eq 'error'){break}}while([DateTime]::UtcNow -lt $deadline)
    $playing=$watch.ElapsedMilliseconds
    Control 'page' @{page='player'}
    $lyricMs=$null;$coverMs=$null
    $deadline=[DateTime]::UtcNow.AddSeconds(12)
    do {
      Start-Sleep -Milliseconds 400;$s=Status
      if($null -eq $lyricMs -and $s.lyric_status -in @('ready','empty')){$lyricMs=$watch.ElapsedMilliseconds}
      if($null -eq $coverMs -and $s.covers.ready){$coverMs=$watch.ElapsedMilliseconds}
      if($null -ne $lyricMs -and $null -ne $coverMs){break}
    }while([DateTime]::UtcNow -lt $deadline)
    [pscustomobject]@{time=(Get-Date -Format HH:mm:ss);app=$App;round=$round;index=$index;status=$s.status;error=$s.error;
      click_to_play_ms=$playing;lyrics_ms=$lyricMs;cover_ms=$coverMs;lyric_status=$s.lyric_status;
      url=$s.url_resolution.last;cdn=$s.playback_timing;metadata=$s.metadata_request;
      psram_free=$s.stats.psram_free;internal_free=$s.stats.internal_free} | ConvertTo-Json -Depth 5 -Compress | Write-Host
    if($s.status -ne 'playing'){throw 'Playback did not succeed'}
    Start-Sleep -Seconds 3
  }
}finally {
  $current=(Invoke-RestMethod "$Device/api/system/state" -TimeoutSec 10).current_app.id
  if($current -eq $App){
    $null=Invoke-RestMethod "$Device/api/system/exit" -Method POST -TimeoutSec 15
    Write-Host 'Returned to device home page.'
  }elseif($current){Write-Host "Foreground changed to $current; left it untouched."}
}
