# Batch OMR via the Audiveris jpackage launcher, piping output so PowerShell
# BLOCKS until each page's JVM exits (prevents runaway parallel spawns).
# Resumable: skips pages whose .mxl already exists. Progress -> omr/progress.log
$exe   = "C:\Program Files\Audiveris\Audiveris.exe"
$pages = "C:\ai\peter\omr\pages"
$xml   = "C:\ai\peter\omr\xml"
$plog  = "C:\ai\peter\omr\progress.log"
New-Item -ItemType Directory -Force -Path $xml | Out-Null

$pdfs = Get-ChildItem $pages -Filter "p_*.pdf" | Sort-Object Name
"START $(Get-Date -Format o)  pages=$($pdfs.Count)" | Out-File $plog -Append -Encoding utf8
$done = 0; $i = 0
foreach ($pdf in $pdfs) {
    $i++
    $base = [IO.Path]::GetFileNameWithoutExtension($pdf.Name)
    $mxl  = Join-Path $xml "$base.mxl"
    if (Test-Path $mxl) { $done++; "SKIP  $base ($i/$($pdfs.Count))" | Out-File $plog -Append -Encoding utf8; continue }
    $t0 = Get-Date
    # the pipe to Out-File keeps the launcher attached -> blocks until JVM exit
    & $exe -batch -export -output $xml -- $pdf.FullName 2>&1 | Out-File "$xml\$base.log" -Encoding utf8
    $secs = [int]((Get-Date) - $t0).TotalSeconds
    if (Test-Path $mxl) { $done++; "DONE  $base ($i/$($pdfs.Count)) ${secs}s" | Out-File $plog -Append -Encoding utf8 }
    else                {          "FAIL  $base ($i/$($pdfs.Count)) ${secs}s" | Out-File $plog -Append -Encoding utf8 }
}
"END   $(Get-Date -Format o)  ok=$done/$($pdfs.Count)" | Out-File $plog -Append -Encoding utf8
