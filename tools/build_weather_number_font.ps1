param(
  [string]$ConverterPath = 'E:\cubicsrc\cubic_lua\cubic_arduino\cubic-develop\.tools\lv_font_conv\node_modules\lv_font_conv\lv_font_conv.js',
  [string]$FontPath = 'C:\Windows\Fonts\segoeuib.ttf'
)

# The existing weather_num_28.bin was reproduced byte-for-byte using Segoe UI
# Bold, 28 px, 4 bpp, ASCII 0x20-0x7E, compression enabled, and no kerning.
# Temperature.symbol() now emits U+00B0 followed by ASCII C/F. Keep the original
# glyphs and metrics, adding only the missing degree sign. Do not substitute ℃.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ConverterPath)) { throw "Missing converter: $ConverterPath" }
if (-not (Test-Path -LiteralPath $FontPath)) { throw "Missing font: $FontPath" }
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$output = Join-Path $root 'weather\package\font\weather_num_28.bin'
& node $ConverterPath --size 28 --bpp 4 --format bin --font $FontPath -r '0x20-0x7E,0xB0' --no-kerning -o $output
if ($LASTEXITCODE -ne 0) { throw 'Weather number font generation failed' }
& python -X utf8 (Join-Path $PSScriptRoot 'check_font_coverage.py') $output --text ('0123456789-CF' + [char]0xB0)
if ($LASTEXITCODE -ne 0) { throw 'Weather temperature glyph coverage check failed' }
Get-Item -LiteralPath $output | Select-Object Name,Length
