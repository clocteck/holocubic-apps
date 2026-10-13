param(
  [string]$ConverterPath = 'E:\cubicsrc\cubic_lua\cubic_arduino\cubic-develop\.tools\lv_font_conv\node_modules\lv_font_conv\lv_font_conv.js'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$fontCache = Join-Path $env:TEMP 'cubic_i18n_fonts'
$fonts = @{zh_cn='NotoSansCJKsc-Medium.otf'; zh_tw='NotoSansCJKtc-Medium.otf'; ja='NotoSansCJKjp-Medium.otf'; de='NotoSansCJKsc-Medium.otf'}
$source = Get-Content -Raw -Encoding utf8 (Join-Path $root 'NixieClock/package/main.lua')
$extra = -join ([regex]::Matches($source, '[^\x00-\x7F]') | ForEach-Object Value | Select-Object -Unique)
foreach ($locale in @('zh_cn','zh_tw','ja','de')) {
  $font = Join-Path $fontCache $fonts[$locale]
  if (!(Test-Path -LiteralPath $font)) { throw "Missing cached Noto font: $font (run build_i18n_fonts.ps1 first)" }
  $placeChars = -join (@(0x9547,0x911E,0x5DDE,0x5BBF,0x93AE,0x5BE7,0x5340,0xB0) | ForEach-Object { [char]$_ })
  $charset = (Get-Content -Raw -Encoding utf8 (Join-Path $PSScriptRoot "charset_$locale.txt")).Trim() + $extra + $placeChars
  foreach ($size in @(9,10,11,12,14,16)) {
    $output = Join-Path $root "NixieClock/package/font/time_i18n_${locale}_${size}.bin"
    & node $ConverterPath --size $size --bpp 2 --format bin --font $font -r 0x20-0x7F --symbols $charset --no-kerning -o $output
    if ($LASTEXITCODE -ne 0) { throw "Font build failed: $output" }
    Write-Host "Built $locale $size"
  }
}
