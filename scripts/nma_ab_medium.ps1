# Medium A/B: A_nma_only vs C_full_stack on full short OOS tape
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..
New-Item -ItemType Directory -Force -Path build\graal | Out-Null

$TAPE = "corpus\tapes\spy_oos_2022_2026.csv"
Write-Host "Building corpus-evo.jar..."
haxe build-corpus-evo.hxml
if ($LASTEXITCODE -ne 0) { throw "build failed" }

$CP = (Get-Content graal\cp.txt -Raw).Trim()
$JAR = "build\jvm\corpus-evo.jar"
$JAVA = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME "bin\java.exe" } else { "java" }

$COMMON = @(
  "--pop","24","--gens","8","--seed","7","--threads","1",
  "--tape",$TAPE,
  "--fitness-windows","1","--attr-bars","256","--no-cache",
  "--nma"
)

function Invoke-Arm($name, $extra) {
  $log = "build\graal\ab_med_$name.log"
  Write-Host "`n=== ARM $name ==="
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $prev = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  & $JAVA --sun-misc-unsafe-memory-access=allow -cp "$CP;$JAR" `
    musescript.evo.graal.CorpusEvoRun @COMMON @extra `
    2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $log
  $ErrorActionPreference = $prev
  $sw.Stop()
  Write-Host "arm $name wall=$(([math]::Round($sw.Elapsed.TotalSeconds,1)))s"
}

Invoke-Arm "A" @("--no-nma-dirty-spine")
Invoke-Arm "C" @(
  "--nma-dirty-spine","--speculative-growth-k","4",
  "--cvt-cells","64","--lexicase","--fitness-windows","4"
)

Write-Host "`n=== EXTRACT ==="
Select-String -Path build\graal\ab_med_A.log,build\graal\ab_med_C.log -Pattern `
  'workHits=|REAL CHAMPION|OOS summary|total wall|CORPUS_EVO_OK|qd='
