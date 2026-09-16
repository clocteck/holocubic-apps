param(
  [string]$LuaSource='E:/cubicsrc/cubic_lua/cubic_arduino/cubic-develop/lib/ESP-Arduino-Lua-master/src/lua',
  [string]$VcVars='C:/Program Files/Microsoft Visual Studio/2022/Professional/VC/Auxiliary/Build/vcvars64.bat'
)
$ErrorActionPreference='Stop'
$appRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$build=Join-Path $appRoot 'src/build/clock32'
$null=New-Item -ItemType Directory -Force $build
$luaDir=(Resolve-Path $LuaSource).Path
$sources=@(Get-ChildItem -LiteralPath $luaDir -Filter '*.c' | Where-Object {$_.Name -notin @('lua.c','luac.c')} | ForEach-Object {'"'+$_.FullName+'"'})
$runner=Join-Path $PSScriptRoot 'clock32_runner.c'
$exe=Join-Path $build 'clock32.exe'
# This builds read-only firmware sources into an app-local ignored directory.
$command='"'+$VcVars+'" >nul && cl /nologo /O2 /std:c11 /D_CRT_SECURE_NO_WARNINGS /I"'+$luaDir+'" '+($sources -join ' ')+' "'+$runner+'" /Fe:"'+$exe+'"'
Push-Location $build
try {
  & cmd /d /s /c $command
  if($LASTEXITCODE){throw '32-bit Lua test build failed'}
  & $exe ($appRoot.Replace('\','/')) ((Join-Path $PSScriptRoot 'test_clock.lua').Replace('\','/'))
  if($LASTEXITCODE){throw '32-bit clock regression failed'}
} finally {Pop-Location}
