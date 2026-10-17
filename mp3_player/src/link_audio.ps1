param(
    [Parameter(Mandatory = $true)][string]$BuildDir
)

# elf_loader 1.3.1 ignores ELF_SO_LINK_FLAGS. Relink its compiled inputs with
# the codec's required local-symbol binding and an explicit compiler runtime.
# Run after exporting the ESP-IDF environment and building the `so` target.
$ErrorActionPreference = "Stop"
$build = (Resolve-Path -LiteralPath $BuildDir).Path
$gcc = (Get-Command xtensa-esp32s3-elf-gcc.exe -ErrorAction Stop).Source
$toolDir = Split-Path -Parent $gcc
$strip = Join-Path $toolDir "xtensa-esp32s3-elf-strip.exe"
$libgcc = (& $gcc -print-libgcc-file-name).Trim()
if ($LASTEXITCODE -ne 0) { throw "Cannot locate libgcc" }
$inputs = @(
    "so_objs/main_audio_module.o",
    "esp-idf/espressif__esp_audio_codec/libespressif__esp_audio_codec.a",
    "esp-idf/espressif__esp-dsp/libespressif__esp-dsp.a",
    "patched_libs/libesp_audio_simple_dec_picfix.a",
    "patched_libs/libesp_audio_codec_picfix.a"
) | ForEach-Object { Join-Path $build $_ }
$check = Join-Path (Split-Path -Parent $build) "managed_components/espressif__elf_loader/check_shared_object.cmake"
foreach ($path in @($inputs) + @($libgcc, $check, $strip)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing build input: $path" }
}
$output = Join-Path $build "audio.so"
& $gcc -shared -fPIC -static-libgcc -nostdlib -nostartfiles `
    -fdata-sections -ffunction-sections "-Wl,--gc-sections" -fvisibility=hidden `
    "-Wl,--strip-debug" "-Wl,--strip-discarded" "-Wl,-Bsymbolic" `
    "-Wl,--exclude-libs,ALL" "-Wl,-z,notext" "-Wl,--no-check-sections" "-Wl,-N" `
    -o $output @inputs $libgcc "-Wl,--allow-shlib-undefined"
if ($LASTEXITCODE -ne 0) { throw "audio.so link failed" }
& cmake "-DOUT=$output" -P $check
if ($LASTEXITCODE -ne 0) { throw "audio.so validation failed" }
& $strip --strip-unneeded --remove-section=.comment --remove-section=.got.loc `
    --remove-section=.dynamic --remove-section=.xt.lit --remove-section=.xt.prop `
    --remove-section=.xtensa.info $output
if ($LASTEXITCODE -ne 0) { throw "audio.so strip failed" }
Get-Item -LiteralPath $output | Select-Object FullName, Length
