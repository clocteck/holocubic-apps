param(
  [string]$FontPath = 'C:\Windows\Fonts\msyh.ttc',
  [string]$NodePath = $env:NODE_EXE,
  [string]$ConverterPath = $env:LV_FONT_CONV_JS
)

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$charsetPath = Join-Path $scriptDir 'common_hanzi_3000_unique.txt'

if (-not (Test-Path -LiteralPath $FontPath)) {
  throw "Missing source font: $FontPath"
}
if (-not (Test-Path -LiteralPath $charsetPath)) {
  throw "Missing charset: $charsetPath"
}

$actualFontPath = $FontPath
if ([System.IO.Path]::GetExtension($FontPath).ToLowerInvariant() -eq '.ttc') {
  $tempDir = Join-Path $env:TEMP 'settings_font_build'
  New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
  $actualFontPath = Join-Path $tempDir 'settings_face0.ttf'
  python -c "import sys; from fontTools.ttLib import TTFont; f=TTFont(sys.argv[1], fontNumber=0); f.save(sys.argv[2])" $FontPath $actualFontPath
}

if ([string]::IsNullOrWhiteSpace($NodePath)) {
  $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
  if ($nodeCommand) {
    $NodePath = $nodeCommand.Source
  }
}
if ([string]::IsNullOrWhiteSpace($ConverterPath)) {
  $localConverter = Join-Path $scriptDir 'node_modules\lv_font_conv\lv_font_conv.js'
  if (Test-Path -LiteralPath $localConverter) {
    $ConverterPath = $localConverter
  }
}

if ([string]::IsNullOrWhiteSpace($NodePath) -or -not (Test-Path -LiteralPath $NodePath)) {
  throw "Missing node.exe. Set NODE_EXE or put node on PATH."
}
if ([string]::IsNullOrWhiteSpace($ConverterPath) -or -not (Test-Path -LiteralPath $ConverterPath)) {
  throw "Missing lv_font_conv.js. Set LV_FONT_CONV_JS or install lv_font_conv under this font directory."
}

$commonSymbols = [System.IO.File]::ReadAllText($charsetPath, [System.Text.UTF8Encoding]::new($false)).TrimEnd()
$commonNonAsciiSymbols = -join ($commonSymbols.ToCharArray() | Where-Object { [int]$_ -gt 127 })
if ([string]::IsNullOrEmpty($commonNonAsciiSymbols)) {
  throw "Filtered non-ASCII symbols are empty: $charsetPath"
}

$usedText = @'
设置设备信息蓝牙亮度关闭客户端热点不可用已连接配对中已开启未启用等待设备降低提高切换开启读取失败设置失败启动失败关闭失败已关闭重新扫描操作失败左右切换页面上下选择调整返回处理器运存卡系统版本地址未分配强制退出上级按键映射
'@
$usedSymbols = -join ($usedText.ToCharArray() | Where-Object { [int]$_ -gt 127 } | Select-Object -Unique)
if ([string]::IsNullOrEmpty($usedSymbols)) {
  throw "Used Chinese charset is empty."
}
[System.IO.File]::WriteAllText((Join-Path $scriptDir 'settings_used_cn.txt'), $usedSymbols, [System.Text.UTF8Encoding]::new($false))

$targets = @(
  @{ Size = 12; Name = 'settings_cn_12_common3000.bin'; Symbols = $commonNonAsciiSymbols },
  @{ Size = 15; Name = 'settings_cn_15_used.bin'; Symbols = $usedSymbols },
  @{ Size = 18; Name = 'settings_cn_18_used.bin'; Symbols = $usedSymbols }
)

foreach ($target in $targets) {
  $outputPath = Join-Path $scriptDir $target.Name
  Write-Host "[font] size   = $($target.Size)"
  Write-Host "[font] output = $outputPath"

  & $NodePath $ConverterPath `
    --size $target.Size `
    --bpp 2 `
    --format bin `
    --font $actualFontPath `
    -r 0x20-0x7F `
    --symbols $target.Symbols `
    --force-fast-kern-format `
    -o $outputPath

  if (-not (Test-Path -LiteralPath $outputPath)) {
    throw "Font build failed, output file missing: $outputPath"
  }
  $item = Get-Item -LiteralPath $outputPath
  Write-Host "[font] done   = $($item.Name) $($item.Length) bytes"
}
