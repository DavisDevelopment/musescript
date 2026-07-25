# Short CorpusEvoRun A/B (Windows PowerShell)
# Fair wall compare: BOTH arms use --nma (JS-fallback). Diff is dirty-spine + speculative-K only.
# Search compare: arm C adds CVT + lexicase (no --credit-map-axis — hurt OOS 26/50 vs CVT 41/50).
#
# Usage (from muse-script root):
#   powershell -File scripts/nma_ab_smoke.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

New-Item -ItemType Directory -Force -Path build\graal | Out-Null

# Slim tape for smoke (~320 bars → IS still ≥200 after OOS/embargo)
$smoke = "build\graal\smoke_spy_320.csv"
if (-not (Test-Path $smoke)) {
  Get-Content corpus\tapes\spy_oos_2022_2026.csv -TotalCount 321 | Set-Content $smoke
}

Write-Host "Building corpus-evo.jar..."
haxe build-corpus-evo.hxml
if ($LASTEXITCODE -ne 0) { throw "haxe build-corpus-evo.hxml failed" }

$CP = (Get-Content graal\cp.txt -Raw).Trim()
$JAR = "build\jvm\corpus-evo.jar"
$JAVA = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME "bin\java.exe" } else { "java" }

$COMMON = @(
  "--pop","16","--gens","5","--seed","42","--threads","1",
  "--tape",$smoke,
  "--fitness-windows","1","--attr-bars","128","--no-cache",
  "--nma"
)

function Invoke-Arm($name, $extra) {
  $log = "build\graal\ab_$name.log"
  Write-Host "`n=== ARM $name ==="
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  & $JAVA --sun-misc-unsafe-memory-access=allow -cp "$CP;$JAR" `
    musescript.evo.graal.CorpusEvoRun @COMMON @extra `
    2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $log
  $ErrorActionPreference = $prevEap
  $sw.Stop()
  Write-Host "arm $name wall(stopwatch)=$(([math]::Round($sw.Elapsed.TotalSeconds,1)))s  log=$log"
  return $log
}

$logA = Invoke-Arm "A_nma_only" @("--no-nma-dirty-spine")
$logB = Invoke-Arm "B_dirty_spec" @("--nma-dirty-spine","--speculative-growth-k","3")
$logC = Invoke-Arm "C_full_stack" @(
  "--nma-dirty-spine","--speculative-growth-k","3",
  "--cvt-cells","64","--lexicase","--fitness-windows","4"
)

Write-Host "`n=== EXTRACT ==="
Select-String -Path build\graal\ab_A_nma_only.log,build\graal\ab_B_dirty_spec.log,build\graal\ab_C_full_stack.log -Pattern `
  'qd=|niches=|workHits=|popMemoHits=|REAL CHAMPION|OOS summary|total wall|CORPUS_EVO_OK'
