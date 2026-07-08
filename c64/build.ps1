# Build the C64 port of Peter and the Wolf - all six chapters
#   .\build.ps1                  build meadow.prg + meadow.d64
#   .\build.ps1 -Run             build, then launch in VICE
#   .\build.ps1 -Auto            autopilot build (plays itself; testing)
#   .\build.ps1 -StartLevel 3    boot straight into chapter 4
param([switch]$Run, [switch]$Auto, [int]$StartLevel = 0)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# 1. art + music -> dasm includes
py -3 tools\gen_assets.py
if ($LASTEXITCODE -ne 0) { throw "asset generation failed" }
py -3 tools\gen_music.py
if ($LASTEXITCODE -ne 0) { throw "music generation failed" }

# 2. assemble
$defs = @("-DSTART_LEVEL=$StartLevel")
if ($Auto) { $defs += "-DAUTO=1" }
bin\dasm.exe meadow.asm -f1 "-obuild/meadow.prg" "-lbuild/meadow.lst" "-sbuild/meadow.sym" @defs
if ($LASTEXITCODE -ne 0) { throw "dasm failed" }

# 3. disk image (needs VICE's c1541 on C:\vice)
$c1541 = "C:\vice\bin\c1541.exe"
if (Test-Path $c1541) {
    if (Test-Path build\meadow.d64) { Remove-Item build\meadow.d64 }
    & $c1541 -format "meadow,01" d64 build\meadow.d64 -write build\meadow.prg meadow | Out-Null
    Write-Host "built build\meadow.prg and build\meadow.d64"
} else {
    Write-Host "built build\meadow.prg (c1541 not found, skipped .d64)"
}

if ($Run) {
    & "C:\vice\bin\x64sc.exe" (Resolve-Path build\meadow.prg)
}
