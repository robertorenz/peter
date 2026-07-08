# Build the Commander X16 port of Peter and the Wolf
#   .\build.ps1               build build\PETER.PRG
#   .\build.ps1 -Run          build, then launch in the X16 emulator
#   .\build.ps1 -Chapter 5    attract demo starts at chapter 6 (0-based; testing)
param([switch]$Run, [int]$Chapter = 0)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$cl65 = Join-Path $PSScriptRoot "bin\cc65\bin\cl65.exe"
$emu  = Join-Path $PSScriptRoot "bin\x16emu\x16emu.exe"

# 1. art + music -> ca65 includes
if (Test-Path tools\gen_assets.py) {
    py -3 tools\gen_assets.py
    if ($LASTEXITCODE -ne 0) { throw "asset generation failed" }
}
if (Test-Path tools\gen_music.py) {
    py -3 tools\gen_music.py
    if ($LASTEXITCODE -ne 0) { throw "music generation failed" }
}

# 2. assemble + link (cx16 target, BASIC SYS header)
$ca65 = Join-Path $PSScriptRoot "bin\cc65\bin\ca65.exe"
$ld65 = Join-Path $PSScriptRoot "bin\cc65\bin\ld65.exe"
& $ca65 -t cx16 --cpu 65C02 -D ATTRACT_CHAPTER=$Chapter -o build\main.o main.asm
if ($LASTEXITCODE -ne 0) { throw "ca65 failed" }
& $ld65 -C peter.cfg -o build\PETER.PRG -u __EXEHDR__ `
    -Ln build\peter.sym build\main.o (Join-Path $PSScriptRoot "bin\cc65\lib\cx16.lib")
if ($LASTEXITCODE -ne 0) { throw "ld65 failed" }
Write-Host "built build\PETER.PRG ($((Get-Item build\PETER.PRG).Length) bytes)"

if ($Run) {
    & $emu -prg (Resolve-Path build\PETER.PRG) -run
}
