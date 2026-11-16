param([string]$DependencyBuild = (Join-Path $PSScriptRoot 'build_ascii'))
# Recompile CURRENT module source against an existing ESP-IDF dependency build.
# No cached audio_module object is reused. Dependency libraries are unchanged.
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$dep=(Resolve-Path -LiteralPath $DependencyBuild).Path
$gcc=(Get-Command xtensa-esp32s3-elf-gcc.exe -ErrorAction Stop).Source
$cm=Get-Content -Raw (Join-Path $root 'main/CMakeLists.txt')
$block=[regex]::Match($cm,'(?s)set\(audio_so_include_dirs\s+(.*?)\r?\n\)').Groups[1].Value
if(-not $block){throw 'Cannot read declared module includes'}
$inc=@()
foreach($m in [regex]::Matches($block,'"([^"]+)"')){
  $p=$m.Groups[1].Value.Replace('${CMAKE_CURRENT_SOURCE_DIR}',(Join-Path $root 'main')).Replace('${CMAKE_BINARY_DIR}',$dep).Replace('${IDF_PATH}',$env:IDF_PATH).Replace('${IDF_TARGET}','esp32s3').Replace('${audio_codec_dir}',(Join-Path $root 'managed_components/espressif__esp_audio_codec')).Replace('${audio_dsp_dir}',(Join-Path $root 'managed_components/espressif__esp-dsp'))
  $inc+='-I'+$p
}
$obj=Join-Path $dep 'so_objs/main_audio_module.o'
New-Item -ItemType Directory -Force (Split-Path $obj) | Out-Null
& $gcc -c -O2 -fPIC -fvisibility=hidden -ffunction-sections -fdata-sections -fno-builtin -fno-jump-tables -fno-tree-switch-conversion -DCONFIG_IDF_TARGET_ESP32S3=1 @inc (Join-Path $root 'main/audio_module.c') -o $obj
if($LASTEXITCODE){throw 'Audio module compilation failed'}
& (Join-Path $root 'link_audio.ps1') -BuildDir $dep
if($LASTEXITCODE){throw 'Audio module link failed'}
Copy-Item -LiteralPath (Join-Path $dep 'audio.so') -Destination (Join-Path $root '../package/modules/audio.so') -Force
Get-Item (Join-Path $root '../package/modules/audio.so') | Select-Object FullName,Length
