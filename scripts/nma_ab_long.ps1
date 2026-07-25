# Longer multi-seed full-stack sweep (A cold vs C full)
# pop 40 / gens 16 / threads 1 / 5 seeds — expect ~10-40 min total
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

$OUTDIR = "build\graal\nma-ab-long"
New-Item -ItemType Directory -Force -Path $OUTDIR | Out-Null
$TSV = Join-Path $OUTDIR "results.tsv"

Write-Host "Building corpus-evo.jar..."
haxe build-corpus-evo.hxml
if ($LASTEXITCODE -ne 0) { throw "build failed" }

$CP = (Get-Content graal\cp.txt -Raw).Trim()
$JAR = "build\jvm\corpus-evo.jar"
$JAVA = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME "bin\java.exe" } else { "java" }
$TAPE = "corpus\tapes\spy_oos_2022_2026.csv"
$SEEDS = @(42, 7, 123, 99, 31337)

"arm`tseed`tchamp_fitness`toos_held`toos_checked`tqd_last`tniches_last`tfuse_calls`twork_hits`twall_s`tok" |
  Set-Content $TSV

function Invoke-Arm($arm, $seed, $extra) {
  $log = Join-Path $OUTDIR "${arm}_s${seed}.log"
  Write-Host "`n=== $arm seed=$seed ==="
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $prev = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $common = @(
    "--pop","40","--gens","16","--seed","$seed","--threads","1",
    "--tape",$TAPE,
    "--fitness-windows","1","--attr-bars","256","--no-cache",
    "--nma"
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
  $niches = ""; $nm = [regex]::Matches($body, 'niches=(\d+)'); if ($nm.Count -gt 0) { $niches = $nm[$nm.Count-1].Groups[1].Value }
  $fuseSum = 0; foreach ($m in [regex]::Matches($body, 'fuseCalls=(\d+)')) { $fuseSum += [int]$m.Groups[1].Value }
  $workSum = 0; foreach ($m in [regex]::Matches($body, 'workHits=(\d+)')) { $workSum += [int]$m.Groups[1].Value }
  $ok = if ($body -match 'CORPUS_EVO_OK') { "1" } else { "0" }
  Add-Content $TSV "$arm`t$seed`t$fit`t$oosH`t$oosC`t$qd`t$niches`t$fuseSum`t$workSum`t$wall`t$ok"
  Write-Host "  fit=$fit oos=$oosH/$oosC qd=$qd fuseSum=$fuseSum workHits=$workSum wall=${wall}s ok=$ok"
}

foreach ($seed in $SEEDS) {
  Invoke-Arm "A" $seed @("--no-nma-dirty-spine","--no-nma-fuse-host")
  Invoke-Arm "C" $seed @(
    "--nma-dirty-spine",
    "--cvt-cells","64","--lexicase","--fitness-windows","4"
  )
}

Write-Host "`n=== RESULTS ==="
Get-Content $TSV
