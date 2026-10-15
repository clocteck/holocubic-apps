param([string]$BuildRoot = 'E:/cubicsrc/xiaozhi-build', [switch]$WakeOnly, [string[]]$Only, [switch]$SkipConfigure)
$ErrorActionPreference = 'Stop'
$pioRoot = Join-Path $env:USERPROFILE '.platformio'
$env:IDF_PATH = Join-Path $pioRoot 'packages/framework-espidf'
$env:IDF_TOOLS_PATH = Join-Path $env:USERPROFILE '.espressif'
$pythonDir = Join-Path $env:USERPROFILE '.espressif/python_env/idf5.5_py3.11_env/Scripts'
$env:IDF_PYTHON_ENV_PATH = Split-Path $pythonDir
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'
$env:PATH = "$pythonDir;$(Join-Path $pioRoot 'packages/toolchain-xtensa-esp-elf/bin');$env:PATH"
$ninja = (Get-Command ninja.exe).Source
$env:NINJA = $ninja
$builds = @(
    @{Name='wake'; Source=(Join-Path $PSScriptRoot 'wake'); Define='WAKE_MODULE_NAME'; Module='wake'; Output='wake.so'; Destination='../package/wake.so'},
    @{Name='xzwk'; Source=(Join-Path $PSScriptRoot 'wake'); Define='WAKE_MODULE_NAME'; Module='xzwk'; Output='wake.so'; Destination='../../xiaozhi-service/package/xzwk.so'}
)
if (-not $WakeOnly) {
    $builds += @(
        @{Name='voice'; Source=$PSScriptRoot; Define='XZ_MODULE_NAME'; Module='xiaozhi'; Output='xiaozhi.so'; Destination='../package/xiaozhi.so'},
        @{Name='xzvoice'; Source=$PSScriptRoot; Define='XZ_MODULE_NAME'; Module='xzvoice'; Output='xiaozhi.so'; Destination='../../xiaozhi-service/package/xzvoice.so'}
    )
}
foreach ($build in $builds) {
    if ($Only -and $build.Name -notin $Only) { continue }
    $dir = Join-Path $BuildRoot $build.Name
    if (-not $SkipConfigure -or -not (Test-Path (Join-Path $dir 'CMakeCache.txt'))) {
        & cmake -S $build.Source -B $dir -G Ninja '-DIDF_TARGET=esp32s3' "-DCMAKE_MAKE_PROGRAM=$ninja" "-DPYTHON=$(Join-Path $pythonDir 'python.exe')" "-D$($build.Define)=$($build.Module)"
        if ($LASTEXITCODE) { throw "Configure failed: $($build.Name)" }
    }
    & cmake --build $dir --target so --parallel 4
    if ($LASTEXITCODE) { throw "Build failed: $($build.Name)" }
    $nm = Join-Path $pioRoot 'packages/toolchain-xtensa-esp-elf/bin/xtensa-esp32s3-elf-nm.exe'
    $unresolved = & $nm -D -u (Join-Path $dir $build.Output)
    if ($unresolved) { throw "Unresolved native symbols: $unresolved" }
    $allowed = @('module_query_v1','module_create_v2','module_luaopen_v1','module_destroy_v1')
    $exported = & $nm -D --defined-only (Join-Path $dir $build.Output)
    foreach ($symbol in $exported) {
        $name = ($symbol.Trim() -split '\s+')[-1]
        if ($name -notin $allowed) { throw "Unexpected export (check ELF link flags): $name" }
    }
    Copy-Item -LiteralPath (Join-Path $dir $build.Output) -Destination (Join-Path $PSScriptRoot $build.Destination) -Force
}
