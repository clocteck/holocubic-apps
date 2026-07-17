param(
  [string]$ConverterPath = 'E:\cubicsrc\cubic_lua\cubic_arduino\cubic-develop\.tools\lv_font_conv\node_modules\lv_font_conv\lv_font_conv.js',
  [string]$SourceFont = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$fontDir = Join-Path $PSScriptRoot 'package\assets\fonts'
$charsetPath = Join-Path $fontDir 'common3500.txt'
$outputPath = Join-Path $fontDir 'xiaozhi_common3500_16.bin'

if (-not $SourceFont) {
  $SourceFont = Join-Path $root 'aida_monitor\package\font\aida_noto_sans_sc.ttf'
}
if (-not (Test-Path -LiteralPath $ConverterPath)) {
  throw "Missing lv_font_conv: $ConverterPath"
}
if (-not (Test-Path -LiteralPath $SourceFont)) {
  throw "Missing source font: $SourceFont"
}

# Keep the legacy filenames for deployed-config compatibility, but generate the
# complete 3,755-character GB2312 level-1 set instead of truncating it at 3,500.
python -c @'
import pathlib, sys
chars = []
for high in range(0xB0, 0xD8):
    for low in range(0xA1, 0xFF):
        try:
            char = bytes((high, low)).decode("gb2312")
        except UnicodeDecodeError:
            continue
        if "\u4e00" <= char <= "\u9fff":
            chars.append(char)
if len(chars) != 3755:
    raise SystemExit(f"unexpected GB2312 level-1 count: {len(chars)}")
pathlib.Path(sys.argv[1]).write_text("".join(chars) + "\n", encoding="utf-8")
'@ $charsetPath
if ($LASTEXITCODE -ne 0) { throw 'Failed to generate GB2312 charset' }

$charset = [IO.File]::ReadAllText($charsetPath, [Text.Encoding]::UTF8).Trim()
node $ConverterPath `
  --size 16 `
  --bpp 2 `
  --format bin `
  --font $SourceFont `
  -r 0x20-0x7F `
  --symbols $charset `
  --no-kerning `
  -o $outputPath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputPath)) {
  throw 'Failed to build XiaoZhi native font'
}

Get-Item -LiteralPath $charsetPath, $outputPath | Select-Object Name, Length, FullName
