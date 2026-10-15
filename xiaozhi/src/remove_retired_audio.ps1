param([string]$Device='http://192.168.1.30')
$ErrorActionPreference='Stop'
# Exact retired targets only. Shared pairing/configuration is never a target.
$roots=@('/sd/apps/xiaozhi-aec-test','/sd/data/xiaozhi/aec-tests',
    '/sd/apps/xiaozhi/diag','/sd/apps/xiaozhi-service/diag')
$files=@('/sd/apps/xiaozhi/duplex_session.lua','/sd/apps/xiaozhi-service/duplex_session.lua',
    '/sd/data/xiaozhi/aec-apply-result.json','/sd/data/xiaozhi/aec-nlp-trial-result.json')
$script:removed=0
$script:bytes=0L
function Remove-ExactTree([string]$Path,[string]$Root) {
    if ($Root -notin $roots -or ($Path -ne $Root -and -not $Path.StartsWith($Root+'/')) -or $Path.Contains('..')) {
        throw "Deletion outside approved target: $Path"
    }
    $listed=Invoke-RestMethod "$Device/api/system/fs/list?path=$([uri]::EscapeDataString($Path))" -TimeoutSec 10
    foreach ($entry in $listed.entries) {
        if ($entry.name -match '[/\\]' -or $entry.name -in @('.','..')) { throw 'Invalid child path' }
        $child=$Path+'/'+$entry.name
        if ($entry.is_dir) { Remove-ExactTree $child $Root }
        else {
            $r=Invoke-RestMethod "$Device/api/system/fs/remove?path=$([uri]::EscapeDataString($child))" -Method Delete -TimeoutSec 10
            if (-not $r.ok) { throw "Remove failed: $child" }
            $script:removed++;$script:bytes+=[long]$entry.size
        }
    }
    $r=Invoke-RestMethod "$Device/api/system/fs/rmdir?path=$([uri]::EscapeDataString($Path))" -Method Delete -TimeoutSec 10
    if (-not $r.ok) { throw "rmdir failed: $Path" }
    Write-Host "Removed retired directory: $Path"
}
foreach ($root in $roots) {
    $parent=$root.Substring(0,$root.LastIndexOf('/'))
    $name=$root.Substring($root.LastIndexOf('/')+1)
    $list=Invoke-RestMethod "$Device/api/system/fs/list?path=$([uri]::EscapeDataString($parent))" -TimeoutSec 10
    if ($list.entries | Where-Object name -eq $name) { Remove-ExactTree $root $root }
}
foreach ($path in $files) {
    $parent=$path.Substring(0,$path.LastIndexOf('/'))
    $name=$path.Substring($path.LastIndexOf('/')+1)
    $list=Invoke-RestMethod "$Device/api/system/fs/list?path=$([uri]::EscapeDataString($parent))" -TimeoutSec 10
    $entry=$list.entries | Where-Object name -eq $name
    if ($entry) {
        $r=Invoke-RestMethod "$Device/api/system/fs/remove?path=$([uri]::EscapeDataString($path))" -Method Delete -TimeoutSec 10
        if (-not $r.ok) { throw "Remove failed: $path" }
        $script:removed++;$script:bytes+=[long]$entry.size
    }
}
Write-Host "Deleted $script:removed files, $script:bytes bytes; shared config preserved."
