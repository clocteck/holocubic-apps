# Deterministic device-asset compilation: source artwork is preserved in assets/.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$source=Join-Path $PSScriptRoot 'assets/icon-source.png'
$package=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../package'))
$image=[Drawing.Image]::FromFile($source)
$icon=[Drawing.Bitmap]::new(96,96,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics=[Drawing.Graphics]::FromImage($icon)
try {
  $graphics.Clear([Drawing.Color]::Transparent)
  $graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $graphics.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $graphics.CompositingQuality=[Drawing.Drawing2D.CompositingQuality]::HighQuality
  $graphics.DrawImage($image,[Drawing.Rectangle]::new(0,0,96,96))
  $icon.Save((Join-Path $package 'main.png'),[Drawing.Imaging.ImageFormat]::Png)
  # RGB565 / BI_BITFIELDS: predecoded by the firmware before the splash image is shown.
  $stream=[IO.File]::Create((Join-Path $package 'boot.bmp'))
  $writer=[IO.BinaryWriter]::new($stream)
  try {
    $bytes=96*96*2
    $writer.Write([byte[]](66,77));$writer.Write([uint32](66+$bytes))
    $writer.Write([uint32]0);$writer.Write([uint32]66)
    $writer.Write([uint32]40);$writer.Write([int32]96);$writer.Write([int32]-96)
    $writer.Write([uint16]1);$writer.Write([uint16]16);$writer.Write([uint32]3)
    $writer.Write([uint32]$bytes);$writer.Write([int32]2835);$writer.Write([int32]2835)
    $writer.Write([uint32]0);$writer.Write([uint32]0)
    $writer.Write([uint32]0xf800);$writer.Write([uint32]0x07e0);$writer.Write([uint32]0x001f)
    for($y=0;$y -lt 96;$y++){for($x=0;$x -lt 96;$x++){
      $pixel=$icon.GetPixel($x,$y)
      $red=[int][Math]::Round($pixel.R*$pixel.A/255)
      $green=[int][Math]::Round($pixel.G*$pixel.A/255)
      $blue=[int][Math]::Round($pixel.B*$pixel.A/255)
      $rgb=(($red -shr 3) -shl 11) -bor (($green -shr 2) -shl 5) -bor ($blue -shr 3)
      $writer.Write([uint16]$rgb)
    }}
  }finally{$writer.Dispose();$stream.Dispose()}
}finally{$graphics.Dispose();$icon.Dispose();$image.Dispose()}
Get-Item (Join-Path $package 'main.png'),(Join-Path $package 'boot.bmp') | Select-Object Name,Length
