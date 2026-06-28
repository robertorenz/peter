# Render the theme MIDIs to WAV using FluidSynth + a real GM soundfont, so each
# character's line plays on its proper instrument. Output -> audio\<name>.wav
$fs  = "C:\ai\peter\tools\fluidsynth\fluidsynth-v2.5.5-win10-x64-glib\bin\fluidsynth.exe"
$sf  = "C:\ai\peter\tools\FluidR3Mono_GM.sf3"
$out = "C:\ai\peter\audio"
New-Item -ItemType Directory -Force -Path $out | Out-Null

$jobs = @(
  @("themes\01_peter.mid",        "peter.wav"),
  @("themes\02_duck.mid",         "duck.wav"),
  @("themes\03_bird.mid",         "bird.wav"),
  @("themes\04_cat.mid",          "cat.wav"),
  @("themes\05_grandfather.mid",  "grandfather.wav"),
  @("themes\06_wolf.mid",         "wolf.wav"),
  @("themes\07_hunters.mid",      "hunters.wav"),
  @("themes\full_excerpt.mid",    "full.wav")
)
foreach ($j in $jobs) {
  $mid = Join-Path "C:\ai\peter" $j[0]
  $wav = Join-Path $out $j[1]
  & $fs -ni -g 1.4 -R 1 -F $wav -r 44100 $sf $mid *> $null
  $kb = [int]((Get-Item $wav -ErrorAction SilentlyContinue).Length / 1KB)
  Write-Output ("{0,-18} -> {1,-16} {2} KB" -f (Split-Path $j[0] -Leaf), $j[1], $kb)
}