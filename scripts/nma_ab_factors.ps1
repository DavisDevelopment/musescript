# Factor ablation (same seeds/tape as multiseed): which flags buy OOS/QD?
# A = nma, no dirty-spine
# B = nma + dirty + speculative-k 4
# C = B + cvt + credit-map + lexicase
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

$OUTDIR = "build\graal\nma-ab-factors"
New-Item -ItemType Directory -Force -Path $OUTDIR | Out-Null
$TSV = Join-Path $OUTDIR "results.tsv"

Write-Host "Building corpus-evo.jar..."
haxe build-corpus-evo.hxml
if ($LASTEXITCODE -ne 0) { throw "build failed" }

$CP = (Get-Content graal\cp.txt -Raw).Trim()
$JAR = "build\jvm\corpus-evo.jar"
$JAVA = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME "bin\java.exe" } else { "java" }
$TAPE = "corpus\tapes\spy_oos_2022_2026.csv"
$SEEDS = @(42, 7, 123)

"arm`tseed`tchamp_fitness`toos_held`toos_checked`tqd_last`twall_s`tok" | Set-Content $TSV

function Invoke-Arm($arm, $seed, $extra) {
  $log = Join-Path $OUTDIR "${arm}_s${seed}.log"
  Write-Host "`n=== $arm seed=$seed ==="
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $prev = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $common = @(
    "--pop","24","--gens","8","--seed","$seed","--threads","1",
    "--tape",$TAPE, "--fitness-windows","1","--attr-bars","256","--no-cache","--nma"
  )
  & $JAVA --sun-misc-unsafe-memory-access=allow -cp "$CP;$JAR" `
    musescript.evo.graal.CorpusEvoRun @common @extra `
    2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $log | Out-Null
  $ErrorActionPreference = $prev
  $sw.Stop()
  $wall = [math]::Round($sw.Elapsed.TotalSeconds, 1)
  $body = Get-Content $log -Raw
  $fit = if ($body -match 'REAL CHAMPION \(fitness=([-0-9.eE+]+)') { $Matches[1] } else { "" }
  $oosH = ""; $oosC = ""
  if ($body -match 'OOS summary: (\d+)/(\d+)') { $oosH = $Matches[1]; $oosC = $Matches[2] }
  $qd = ""; $qm = [regex]::Matches($body, 'qd=([-0-9.eE+]+)'); if ($qm.Count -gt 0) { $qd = $qm[$qm.Count-1].Groups[1].Value }
  $ok = if ($body -match 'CORPUS_EVO_OK') { "1" } else { "0" }
  Add-Content $TSV "$arm`t$seed`t$fit`t$oosH`t$oosC`t$qd`t$wall`t$ok"
  Write-Host "  fit=$fit oos=$oosH/$oosC qd=$qd wall=${wall}s ok=$ok"
}

foreach ($seed in $SEEDS) {
  Invoke-Arm "A_cold" $seed @("--no-nma-dirty-spine")
  Invoke-Arm "B_dirty_spec" $seed @("--nma-dirty-spine","--speculative-growth-k","4")
  Invoke-Arm "C_full" $seed @(
    "--nma-dirty-spine","--speculative-growth-k","4",
    "--cvt-cells","64","--lexicase","--fitness-windows","4"
  )
}

Write-Host "`n=== RESULTS ==="
Get-Content $TSV
