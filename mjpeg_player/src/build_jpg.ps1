$ErrorActionPreference = "Stop"

$srcRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$stage = Join-Path ([System.IO.Path]::GetTempPath()) "mjpeg_player_jpg_build"
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$stageFull = [System.IO.Path]::GetFullPath($stage)

if (-not $stageFull.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refuse to clean staging directory outside temp: $stageFull"
}

if (Test-Path -LiteralPath $stageFull) {
    Remove-Item -LiteralPath $stageFull -Recurse -Force
}
New-Item -ItemType Directory -Path $stageFull | Out-Null

Copy-Item -LiteralPath (Join-Path $srcRoot "CMakeLists.txt") -Destination $stageFull -Force
Copy-Item -LiteralPath (Join-Path $srcRoot "exports.map") -Destination $stageFull -Force
Copy-Item -LiteralPath (Join-Path $srcRoot "sdkconfig.defaults") -Destination $stageFull -Force
Copy-Item -LiteralPath (Join-Path $srcRoot "main") -Destination $stageFull -Recurse -Force

$exportCandidates = @()
if ($env:IDF_PATH) {
    $exportCandidates += (Join-Path $env:IDF_PATH "export.ps1")
}
$exportCandidates += (Join-Path $env:USERPROFILE "Documents\nodemcu-firmware\sdk\esp32-esp-idf\export.ps1")
$exportCandidates += (Join-Path $env:USERPROFILE ".platformio\packages\framework-espidf\export.ps1")

$exportScript = $exportCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $exportScript) {
    throw "ESP-IDF export.ps1 not found. Set IDF_PATH or install ESP-IDF."
}

Push-Location $stageFull
try {
    . $exportScript
    idf.py reconfigure
    if ($LASTEXITCODE -ne 0) {
        throw "idf.py reconfigure failed with exit code $LASTEXITCODE"
    }
    $jpgLog = Join-Path $stageFull "build_jpg_so.log"
    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        idf.py jpg.so *> $jpgLog
        $jpgExit = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }
    if ($jpgExit -ne 0) {
        Write-Host "idf.py jpg.so exited with $jpgExit; trying custom esp_new_jpeg shared-object link"
    }

    $toolRoot = Split-Path -Parent (Get-Command xtensa-esp32s3-elf-gcc.exe).Source
    $gcc = Join-Path $toolRoot "xtensa-esp32s3-elf-gcc.exe"
    $ar = Join-Path $toolRoot "xtensa-esp32s3-elf-ar.exe"
    $objcopy = Join-Path $toolRoot "xtensa-esp32s3-elf-objcopy.exe"
    $readelf = Join-Path $toolRoot "xtensa-esp32s3-elf-readelf.exe"
    $strip = Join-Path $toolRoot "xtensa-esp32s3-elf-strip.exe"

    $buildDir = Join-Path $stageFull "build"
    $mainObj = Join-Path $buildDir "so_objs\main_jpg_module.o"
    $mainLib = Join-Path $buildDir "esp-idf\main\libmain.a"
    $espJpegLib = Join-Path $buildDir "esp-idf\espressif__esp_jpeg\libespressif__esp_jpeg.a"
    $newJpegLib = Join-Path $stageFull "managed_components\espressif__esp_new_jpeg\lib\esp32s3\libesp_new_jpeg.a"
    $checkScript = Join-Path $stageFull "managed_components\espressif__elf_loader\check_shared_object.cmake"

    foreach ($required in @($gcc, $ar, $objcopy, $readelf, $strip, $mainObj, $mainLib, $espJpegLib, $newJpegLib, $checkScript)) {
        if (-not (Test-Path -LiteralPath $required)) {
            if (Test-Path -LiteralPath $jpgLog) {
                Get-Content -LiteralPath $jpgLog -Tail 80 | Write-Host
            }
            throw "Required build input was not found: $required"
        }
    }

    $customDir = Join-Path $buildDir "esp_new_jpeg_so"
    if (Test-Path -LiteralPath $customDir) {
        Remove-Item -LiteralPath $customDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $customDir | Out-Null

    Push-Location $customDir
    try {
        & $ar x $newJpegLib
        if ($LASTEXITCODE -ne 0) {
            throw "extract esp_new_jpeg archive failed"
        }

        $newJpegObjs = Get-ChildItem -LiteralPath $customDir -Filter "*.obj" | ForEach-Object { $_.FullName }
        & $gcc -nostdlib -r -o esp_new_jpeg_combined.o @newJpegObjs
        if ($LASTEXITCODE -ne 0) {
            throw "partial link esp_new_jpeg failed"
        }

        & $gcc -nostdlib -r -o all_module.o $mainObj $mainLib $espJpegLib (Join-Path $customDir "esp_new_jpeg_combined.o")
        if ($LASTEXITCODE -ne 0) {
            throw "partial link module failed"
        }

        Copy-Item -LiteralPath "all_module.o" -Destination "all_module_local.o" -Force
        & $objcopy `
            --keep-global-symbol=module_query_v1 `
            --keep-global-symbol=module_create_v2 `
            --keep-global-symbol=module_luaopen_v1 `
            --keep-global-symbol=module_destroy_v1 `
            all_module_local.o
        if ($LASTEXITCODE -ne 0) {
            throw "localize module symbols failed"
        }

        $roSections = (& $readelf -SW all_module_local.o) | ForEach-Object {
            if ($_ -match '^\s*\[\s*\d+\]\s+(\.rodata\.(process|idct_array)[^\s]*)\s+') {
                $matches[1]
            }
        } | Sort-Object -Unique
        $renameArgs = @()
        $renameIndex = 0
        foreach ($section in $roSections) {
            $renameArgs += "--rename-section"
            $renameArgs += "$section=.data.rorel$renameIndex,alloc,load,data,contents"
            $renameIndex++
        }
        $renameArgs += "--rename-section"
        $renameArgs += ".rodata=.data.rodata,alloc,load,data,contents"
        $renameArgs += "--rename-section"
        $renameArgs += ".iram1.literal=.text.iram1_literal,alloc,load,readonly,code,contents"
        $renameArgs += "--rename-section"
        $renameArgs += ".iram1=.text.iram1,alloc,load,readonly,code,contents"
        & $objcopy @renameArgs all_module_local.o
        if ($LASTEXITCODE -ne 0) {
            throw "make relocatable rodata writable failed"
        }

        $customSo = Join-Path $buildDir "jpg.so"
        & $gcc `
            -shared `
            -fPIC `
            -static-libgcc `
            -nostdlib `
            -nostartfiles `
            -fdata-sections `
            -ffunction-sections `
            "-Wl,--gc-sections" `
            -fvisibility=hidden `
            "-Wl,--strip-debug" `
            "-Wl,--strip-discarded" `
            -o $customSo `
            all_module_local.o `
            "-Wl,--allow-shlib-undefined"
        if ($LASTEXITCODE -ne 0) {
            throw "custom shared-object link failed"
        }

        & cmake "-DOUT=$customSo" -P $checkScript
        if ($LASTEXITCODE -ne 0) {
            throw "shared-object validation failed"
        }

        & $strip `
            --strip-unneeded `
            --remove-section=.comment `
            --remove-section=.got.loc `
            --remove-section=.dynamic `
            --remove-section=.xt.lit `
            --remove-section=.xt.prop `
            --remove-section=.xtensa.info `
            $customSo
        if ($LASTEXITCODE -ne 0) {
            throw "strip shared object failed"
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    Pop-Location
}

$artifact = Join-Path $stageFull "build\jpg.so"
if (-not (Test-Path -LiteralPath $artifact)) {
    throw "Build finished but jpg.so was not found: $artifact"
}

$outDir = Join-Path $srcRoot "build"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
Copy-Item -LiteralPath $artifact -Destination (Join-Path $outDir "jpg.so") -Force
Write-Host "Copied jpg.so to $(Join-Path $outDir "jpg.so")"
