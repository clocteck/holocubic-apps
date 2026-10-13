param(
  [string]$ConverterPath = 'E:\cubicsrc\cubic_lua\cubic_arduino\cubic-develop\.tools\lv_font_conv\node_modules\lv_font_conv\lv_font_conv.js',
  [string]$App = '*',
  [string[]]$Locales = @('zh_cn', 'zh_tw', 'ja', 'de')
)

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$node = (Get-Command node -ErrorAction Stop).Source
$temp = Join-Path $env:TEMP 'cubic_i18n_fonts'
New-Item -ItemType Directory -Force -Path $temp | Out-Null

if (-not (Test-Path -LiteralPath $ConverterPath)) {
  throw "Missing LVGL font converter: $ConverterPath"
}

python -X utf8 (Join-Path $PSScriptRoot 'generate_i18n_charsets.py')
if ($LASTEXITCODE -ne 0) { throw 'Charset generation failed' }

function Get-NotoFont {
  param([string]$Name, [string]$Url)
  $output = Join-Path $temp $Name
  if (-not (Test-Path -LiteralPath $output)) {
    Write-Host "[font] download $Name"
    Invoke-WebRequest -Uri $Url -OutFile $output
  }
  return $output
}

$rawRoot = 'https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/OTF'
$scFont = Get-NotoFont 'NotoSansCJKsc-Medium.otf' "$rawRoot/SimplifiedChinese/NotoSansCJKsc-Medium.otf"
$twFont = Get-NotoFont 'NotoSansCJKtc-Medium.otf' "$rawRoot/TraditionalChinese/NotoSansCJKtc-Medium.otf"
$jaFont = Get-NotoFont 'NotoSansCJKjp-Medium.otf' "$rawRoot/Japanese/NotoSansCJKjp-Medium.otf"
$licensePath = Join-Path $temp 'OFL-NotoSansCJK.txt'
if (-not (Test-Path -LiteralPath $licensePath)) {
  Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/LICENSE' -OutFile $licensePath
}
foreach ($fontDir in @('launcher\package\font', 'BTC\package\font', 'weather\package\font')) {
  Copy-Item -LiteralPath $licensePath -Destination (Join-Path $root "$fontDir\OFL-NotoSansCJK.txt") -Force
}

$fonts = @{
  zh_cn = $scFont
  zh_tw = $twFont
  ja = $jaFont
  de = $scFont
}

$targets = @(
  @{ Locale='zh_cn'; Size=16; Output='launcher\package\font\launcher_ui_zh_cn_16.bin' },
  @{ Locale='zh_tw'; Size=16; Output='launcher\package\font\launcher_ui_zh_tw_16.bin' },
  @{ Locale='ja'; Size=16; Output='launcher\package\font\launcher_ui_ja_16.bin' },
  @{ Locale='zh_cn'; Size=12; Output='BTC\package\font\btc_ui_zh_cn_12.bin' },
  @{ Locale='zh_tw'; Size=12; Output='BTC\package\font\btc_ui_zh_tw_12.bin' },
  @{ Locale='ja'; Size=12; Output='BTC\package\font\btc_ui_ja_12.bin' },
  @{ Locale='zh_cn'; Size=12; Output='weather\package\font\weather_ui_zh_cn_12.bin' },
  @{ Locale='zh_cn'; Size=16; Output='weather\package\font\weather_ui_zh_cn_16.bin' },
  @{ Locale='zh_tw'; Size=12; Output='weather\package\font\weather_ui_zh_tw_12.bin' },
  @{ Locale='zh_tw'; Size=16; Output='weather\package\font\weather_ui_zh_tw_16.bin' },
  @{ Locale='ja'; Size=12; Output='weather\package\font\weather_ui_ja_12.bin' },
  @{ Locale='ja'; Size=16; Output='weather\package\font\weather_ui_ja_16.bin' }
)

$targets += @(
  @{ Locale='de'; Size=16; Output='launcher\package\font\launcher_ui_de_16.bin' },
  @{ Locale='de'; Size=12; Output='BTC\package\font\btc_ui_de_12.bin' },
  @{ Locale='de'; Size=12; Output='weather\package\font\weather_ui_de_12.bin' },
  @{ Locale='de'; Size=16; Output='weather\package\font\weather_ui_de_16.bin' },
  @{ Locale='zh_cn'; Size=16; Output='ebook\package\font\launcher_ui_zh_cn_16.bin' },
  @{ Locale='zh_tw'; Size=16; Output='ebook\package\font\launcher_ui_zh_tw_16.bin' },
  @{ Locale='ja'; Size=16; Output='ebook\package\font\launcher_ui_ja_16.bin' }
)
foreach ($locale in @('ja', 'de')) {
  foreach ($size in @(12, 15, 18)) {
    $targets += @{ Locale=$locale; Size=$size; Output="settings\package\font\settings_${locale}_${size}.bin" }
  }
  foreach ($size in @(11, 12, 14, 16)) {
    $targets += @{ Locale=$locale; Size=$size; Output="NixieClock\package\font\time_i18n_${locale}_${size}.bin" }
  }
  if (Test-Path -LiteralPath (Join-Path $root '..\youxia173-holocubic-apps\gold-miner\package\app.info')) {
    foreach ($size in @(12, 16, 20, 24)) {
      $targets += @{ Locale=$locale; Size=$size; Output="..\youxia173-holocubic-apps\gold-miner\package\font\ui_${locale}_${size}.bin" }
    }
  }
}
$targets = @($targets | Where-Object { $_.Locale -in $Locales -and $_.Output -like "$App*" })
if (-not $targets.Count) { throw "No font targets match App=$App Locales=$Locales" }

foreach ($target in $targets) {
  $charset = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot ("charset_{0}.txt" -f $target.Locale)), [System.Text.UTF8Encoding]::new($false))
  $output = Join-Path $root $target.Output
  New-Item -ItemType Directory -Force -Path (Split-Path $output) | Out-Null
  Copy-Item -LiteralPath $licensePath -Destination (Join-Path (Split-Path $output) 'OFL-NotoSansCJK.txt') -Force
  Write-Host "[font] $($target.Locale) $($target.Size)px -> $output"
  & $node $ConverterPath `
    --size $target.Size `
    --bpp 2 `
    --format bin `
    --font $fonts[$target.Locale] `
    -r 0x20-0x7F `
    --symbols $charset `
    --no-kerning `
    -o $output
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output)) {
    throw "Font build failed: $output"
  }
}

Get-Item ($targets | ForEach-Object { Join-Path $root $_.Output }) | Select-Object Name,Length,FullName
