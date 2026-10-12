$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$appRoot = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path $appRoot -Parent
$packageRoot = Join-Path $appRoot 'package'
foreach ($subdir in @('assets', 'assets/weather-line', 'font')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot $subdir) | Out-Null
}

# Deterministic device-size packaging of the previously generated PNGs.
function Resize-Png([string]$Source, [string]$Destination, [int]$Width, [int]$Height) {
    $sourceImage = [System.Drawing.Image]::FromFile($Source)
    $targetImage = [System.Drawing.Bitmap]::new($Width, $Height)
    $graphics = [System.Drawing.Graphics]::FromImage($targetImage)
    try {
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $scale = [Math]::Min($Width / $sourceImage.Width, $Height / $sourceImage.Height)
        $drawWidth = [int][Math]::Round($sourceImage.Width * $scale)
        $drawHeight = [int][Math]::Round($sourceImage.Height * $scale)
        $drawX = [int][Math]::Floor(($Width - $drawWidth) / 2)
        $drawY = [int][Math]::Floor(($Height - $drawHeight) / 2)
        $graphics.DrawImage($sourceImage, [System.Drawing.Rectangle]::new($drawX, $drawY, $drawWidth, $drawHeight))
        $targetImage.Save($Destination, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $targetImage.Dispose()
        $sourceImage.Dispose()
    }
}

Resize-Png (Join-Path $PSScriptRoot 'assets/background-source.png') (Join-Path $packageRoot 'assets/background.png') 320 240
Resize-Png (Join-Path $PSScriptRoot 'assets/icon-source.png') (Join-Path $packageRoot 'main.png') 64 64
foreach ($fontName in @('time_en_12', 'time_en_14', 'time_ui_12', 'time_mono_56', 'time_mono_24')) {
    Copy-Item -LiteralPath (Join-Path $repoRoot "NixieClock/package/font/$fontName.bin") -Destination (Join-Path $packageRoot "font/$fontName.bin")
}
# Slice the generated sprite sheet; all raster processing happens during packaging.
# The device only selects and loads one finished 28x28 PNG, with no SVG or drawing code.
$iconNames = @('sun', 'moon', 'partly-day', 'partly-night', 'cloud', 'rain', 'storm', 'snow', 'fog', 'wind', 'sleet', 'unknown')
$sheet = [System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot 'assets/weather-line-sheet.png'))
try {
    for ($index = 0; $index -lt $iconNames.Length; $index++) {
        $cellWidth = $sheet.Width / 4.0
        $cellHeight = $sheet.Height / 3.0
        $sourceRect = [System.Drawing.RectangleF]::new(($index % 4) * $cellWidth, [Math]::Floor($index / 4) * $cellHeight, $cellWidth, $cellHeight)
        $iconBitmap = [System.Drawing.Bitmap]::new(28, 28)
        $iconGraphics = [System.Drawing.Graphics]::FromImage($iconBitmap)
        try {
            $iconGraphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
            $iconGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $iconGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $iconGraphics.DrawImage($sheet, [System.Drawing.RectangleF]::new(0, 0, 28, 28), $sourceRect, [System.Drawing.GraphicsUnit]::Pixel)
            $iconBitmap.Save((Join-Path $packageRoot "assets/weather-line/$($iconNames[$index]).png"), [System.Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $iconGraphics.Dispose()
            $iconBitmap.Dispose()
        }
    }
} finally { $sheet.Dispose() }
Write-Output 'PipBoy package assets ready: background, twelve 28x28 line-art weather PNGs, five local fonts.'
