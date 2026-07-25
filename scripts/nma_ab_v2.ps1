# Targeted isolation for mixed-result NMA components after v2 safeguards.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..
$OUTDIR = "build\graal\nma-ab-v2"
New-Item -ItemType Directory -Force -Path $OUTDIR | Out-Null
$TSV = Join-Path $OUTDIR "results.tsv"
haxe build-corpus-evo.hxml
if ($LASTEXITCODE -ne 0) { throw "build failed" }
$CP = (Get-Content graal\cp.txt -Raw).Trim()
$JAR = "build\jvm\corpus-evo.jar"
$JAVA = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME "bin\java.exe" } else { "java" }
$TAPE = "corpus\tapes\spy_oos_2022_2026.csv"
"arm`tseed`tchamp_fitness`toos_held`toos_checked`tqd_last`twall_s`twork_hits`tfuse_calls`tok" | Set-Content $TSV

function Last-Metric($body, $name) {
  $m = [regex]::Matches($body, "${name}=([0-9]+)")
  if ($m.Count -eq 0) { return "" }
  return $m[$m.Count - 1].Groups[1].Value
}

function Invoke-Arm($arm, $seed, $extra) {
  $log = Join-Path $OUTDIR "${arm}_s${seed}.log"
  Write-Host "=== $arm seed=$seed ==="
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $common = @(
    "--pop","24","--gens","8","--seed","$seed","--threads","1",
    "--tape",$TAPE,"--fitness-windows","1","--attr-bars","256","--no-cache","--nma"
  )
  & $JAVA --sun-misc-unsafe-memory-access=allow -cp "$CP;$JAR" `
    musescript.evo.graal.CorpusEvoRun @common @extra `
    2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $log | Out-Null
  $ErrorActionPreference = $prev; $sw.Stop()
  $body = Get-Content $log -Raw
  $fit = if ($body -match 'REAL CHAMPION \(fitness=([-0-9.eE+]+)') { $Matches[1] } else { "" }
  $oosH = ""; $oosC = ""
  if ($body -match 'OOS summary: (\d+)/(\d+)') { $oosH = $Matches[1]; $oosC = $Matches[2] }
  $qd = ""; $qm = [regex]::Matches($body, 'qd=([-0-9.eE+]+)')
  if ($qm.Count -gt 0) { $qd = $qm[$qm.Count - 1].Groups[1].Value }
  $work = Last-Metric $body "workHits"
  $fuse = Last-Metric $body "fuseCalls"
  $ok = if ($body -match 'CORPUS_EVO_OK') { "1" } else { "0" }
  $wall = [math]::Round($sw.Elapsed.TotalSeconds, 1)
  Add-Content $TSV "$arm`t$seed`t$fit`t$oosH`t$oosC`t$qd`t$wall`t$work`t$fuse`t$ok"
  Write-Host "  fit=$fit oos=$oosH/$oosC qd=$qd wall=${wall}s work=$work fuse=$fuse ok=$ok"
}

foreach ($seed in @(42, 7, 123)) {
  Invoke-Arm "cold" $seed @("--no-nma-dirty-spine")
  Invoke-Arm "dirty_guarded" $seed @("--nma-dirty-spine")
  Invoke-Arm "spec2_v2" $seed @("--speculative-growth-k","2")
  Invoke-Arm "spec4_v2" $seed @("--speculative-growth-k","4")
  Invoke-Arm "spec4_gate05" $seed @(
    "--speculative-growth-k","4","--speculative-growth-min-delta","0.05"
  )
  Invoke-Arm "spec4_gate10" $seed @(
    "--speculative-growth-k","4","--speculative-growth-min-delta","0.10"
  )
  Invoke-Arm "cvt4" $seed @("--cvt-cells","64")
  Invoke-Arm "credit5_v2" $seed @("--cvt-cells","64","--credit-map-axis")
  Invoke-Arm "fuse_explicit" $seed @("--nma-fuse-host","--nma-fuse-min-bars","0")
}

Write-Host "`n=== RESULTS ==="
Get-Content $TSV
