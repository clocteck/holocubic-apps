param([switch]$Playback)
$ErrorActionPreference='Stop'
function Rpc($Module,$Method,$Param) {
  $doc=@{comm=@{ct=24;cv=0;format='json';uin='0'};req_0=@{module=$Module;method=$Method;param=$Param}}
  $data=ConvertTo-Json $doc -Depth 12 -Compress
  Invoke-RestMethod ('https://u.y.qq.com/cgi-bin/musicu.fcg?data='+[uri]::EscapeDataString($data)) -Headers @{Referer='https://y.qq.com/'} -TimeoutSec 20
}
$top=Rpc 'musicToplist.ToplistInfoServer' 'GetDetail' @{topid=26;offset=0;num=20}
$songs=$top.req_0.data.songInfoList
[pscustomobject]@{probe='top';code=$top.req_0.code;count=$songs.Count;total=$top.req_0.data.data.totalNum;first=$songs[0].name}
$search=Rpc 'music.search.SearchCgiService' 'DoSearchForQQMusicDesktop' @{query='晴天';search_type=0;num_per_page=20;page_num=1}
[pscustomobject]@{probe='search';code=$search.req_0.code;keys=($search.req_0.data.PSObject.Properties.Name -join ',');count=$search.req_0.data.body.song.list.Count}
$lyric=Invoke-RestMethod 'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=0039MnYb0qxYhV&format=json&nobase64=1' -Headers @{Referer='https://y.qq.com/'} -TimeoutSec 20
[pscustomobject]@{probe='lyric';code=$lyric.code;length=$lyric.lyric.Length}
if ($Playback) {
  foreach ($song in $songs | Select-Object -First 3) {
    $v=Rpc 'vkey.GetVkeyServer' 'CgiGetVkey' @{guid='2796982635';songmid=@($song.mid);songtype=@(0);uin='0';loginflag=0;platform='20';filename=@('M500'+$song.file.media_mid+'.mp3')}
    $item=$v.req_0.data.midurlinfo[0]
    [pscustomobject]@{probe='vkey';name=$song.name;code=$v.req_0.code;has_url=[bool]$item.purl;keys=($item.PSObject.Properties.Name -join ',')}
  }
}
