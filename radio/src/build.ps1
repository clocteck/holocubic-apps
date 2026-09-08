$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$build = Join-Path $root 'build'
New-Item -ItemType Directory -Force $build | Out-Null
$gcc = (Get-Command xtensa-esp32s3-elf-gcc.exe).Source
$tool = Split-Path $gcc
$objcopy = Join-Path $tool 'xtensa-esp32s3-elf-objcopy.exe'
$readelf = Join-Path $tool 'xtensa-esp32s3-elf-readelf.exe'
$vendor = Join-Path $root 'vendor/esp_audio_codec'
$inc = @('-I'+(Join-Path $root 'main'))
foreach ($part in @('include','include/decoder','include/decoder/impl','include/simple_dec','include/simple_dec/impl')) { $inc += '-I'+(Join-Path $vendor $part) }
foreach ($part in @('components/esp_hw_support/include','components/esp_system/include','components/esp_common/include')) { $inc += '-I'+(Join-Path $env:IDF_PATH $part) }
$obj = Join-Path $build 'radio.o'
& $gcc -c -O2 -fPIC -fvisibility=hidden -ffunction-sections -fdata-sections -fno-builtin -fno-jump-tables -fno-tree-switch-conversion @inc (Join-Path $root 'main/radio_module.c') -o $obj
if ($LASTEXITCODE) { throw 'Compile failed' }
$simple = Join-Path $build 'simple.a'
$codec = Join-Path $build 'codec.a'
Copy-Item (Join-Path $vendor 'lib/esp32s3/libesp_audio_simple_dec.a') $simple -Force
Copy-Item (Join-Path $vendor 'lib/esp32s3/libesp_audio_codec.a') $codec -Force
Push-Location $build
& $objcopy --rename-section .rodata=.data.parser_ro,alloc,load,contents,data simple.a
if ($LASTEXITCODE) { throw 'Parser patch failed' }
& $objcopy '--rename-section' '.rodata.dec_lib$0=.data.codec_ro,alloc,load,contents,data' '--rename-section' '.iram1=.text.codec_iram,alloc,load,contents,code' '--rename-section' '.iram1.literal=.literal.codec_iram,alloc,load,contents' codec.a
if ($LASTEXITCODE) { throw 'Codec patch failed' }
$libgcc = & $gcc -print-libgcc-file-name
$out = Join-Path $build 'radio.so'
& $gcc -nostdlib -r radio.o '-Wl,--start-group' simple.a codec.a $libgcc '-Wl,--end-group' -o combined.o
if ($LASTEXITCODE) { throw 'Partial link failed' }
& $objcopy --keep-global-symbol=module_query_v1 --keep-global-symbol=module_create_v2 --keep-global-symbol=module_luaopen_v1 --keep-global-symbol=module_destroy_v1 combined.o
$ro = & $readelf -SW combined.o | ForEach-Object { if ($_ -match '\]\s+(\.rodata\S*)\s+PROGBITS') { $matches[1] } }
$rename = @()
foreach ($s in $ro) { $rename += '--rename-section'; $rename += "$s=.data$s,alloc,load,contents,data" }
for ($i=0; $i -lt $rename.Count; $i+=40) { $batch=$rename[$i..([Math]::Min($i+39,$rename.Count-1))]; & $objcopy @batch combined.o; if ($LASTEXITCODE) { throw 'Relocation patch failed' } }
& $gcc -shared -fPIC -nostdlib -nostartfiles '-Wl,-Bsymbolic' '-Wl,--gc-sections' '-Wl,-z,notext' "-Wl,-Map,radio.map" combined.o -o radio.so
if ($LASTEXITCODE) { throw 'Link failed' }
$undefined = & $readelf -Ws $out | Select-String 'GLOBAL\s+DEFAULT\s+UND'
if ($undefined) { $undefined; throw 'Unresolved module symbols' }
Copy-Item $out (Join-Path $root '../package/modules/radio.so') -Force
Get-Item $out | Select-Object FullName,Length
Pop-Location
