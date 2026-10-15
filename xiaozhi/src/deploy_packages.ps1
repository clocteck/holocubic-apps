param([string]$Device = 'http://192.168.1.30')
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$nm = Join-Path $env:USERPROFILE '.platformio/packages/toolchain-xtensa-esp-elf/bin/xtensa-esp32s3-elf-nm.exe'
foreach ($binary in @('xiaozhi/package/wake.so','xiaozhi/package/xiaozhi.so','xiaozhi-service/package/xzwk.so','xiaozhi-service/package/xzvoice.so')) {
    $imports = & $nm -D -u (Join-Path $root $binary)
    if ($LASTEXITCODE -or $imports) { throw "Invalid native binary: $binary $imports" }
}
$services = Invoke-RestMethod "$Device/api/system/services" -TimeoutSec 10
if ($services.services | Where-Object { $_.id -eq 'xiaozhi-service' -and $_.running }) {
    Invoke-RestMethod "$Device/api/system/services/stop?id=xiaozhi-service" -Method Post -TimeoutSec 10 | Out-Null
}
Invoke-RestMethod "$Device/api/system/exit" -Method Post -TimeoutSec 10 | Out-Null
foreach ($appName in @('xiaozhi','xiaozhi-service')) {
    $package = Join-Path $root "$appName/package"
    $dirs = @{}
    $files = Get-ChildItem -LiteralPath $package -Recurse -File | Sort-Object @{Expression={if($_.Name -eq 'app.info'){2}elseif($_.Name -eq 'main.lua'){1}else{0}}},FullName
    $count = 0
    foreach ($entry in $files) {
        if ($entry.Name -in @('config.json','service.json','device_mac.json')) { continue }
        $relative = [IO.Path]::GetRelativePath($package,$entry.FullName).Replace('\','/')
        $path = "/sd/apps/$appName/$relative"
        $dir = $path.Substring(0,$path.LastIndexOf('/'))
        if (-not $dirs.ContainsKey($dir)) {
            Invoke-RestMethod "$Device/api/system/fs/mkdir?path=$([uri]::EscapeDataString($dir))" -Method Post -TimeoutSec 10 | Out-Null
            $dirs[$dir]=$true
        }
        $result = Invoke-RestMethod "$Device/api/system/fs/upload?path=$([uri]::EscapeDataString($path))" -Method Put -ContentType 'application/octet-stream' -InFile $entry.FullName -TimeoutSec 60
        if (-not $result.ok -or [long]$result.entry.size -ne $entry.Length) { throw "Upload size mismatch: $path" }
        $count++
        Write-Host "$appName $count/$($files.Count) $relative ($($entry.Length))"
    }
}
Write-Host 'All package files uploaded; runtime data was not overwritten.'
