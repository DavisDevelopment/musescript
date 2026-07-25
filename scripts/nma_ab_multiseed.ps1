# Multi-seed A/B: A_nma_only vs C_full_stack
# Writes TSV + per-run logs under build/graal/nma-ab-seeds/
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

$OUTDIR = "build\graal\nma-ab-seeds"
New-Item -ItemType Directory -Force -Path $OUTDIR | Out-Null
$TSV = Join-Path $OUTDIR "results.tsv"

Write-Host "Building corpus-evo.jar..."
haxe build-corpus-evo.hxml
if ($LASTEXITCODE -ne 0) { throw "haxe build-corpus-evo.hxml failed" }

$CP = (Get-Content graal\cp.txt -Raw).Trim()
$JAR = "build\jvm\corpus-evo.jar"
$JAVA = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME "bin\java.exe" } else { "java" }
$TAPE = "corpus\tapes\spy_oos_2022_2026.csv"
$SEEDS = @(42, 7, 123, 99, 31337)

"arm`tseed`tchamp_fitness`toos_held`toos_checked`tqd_last`tniches_last`twork_hits_sum`twall_s`tok" |
  Set-Content $TSV

function Get-Match($text, $pattern) {
  $m = [regex]::Match($text, $pattern)
  if ($m.Success) { return $m.Groups[1].Value }
  return ""
}

function Invoke-Arm($arm, $seed, $extra) {
  $log = Join-Path $OUTDIR "${arm}_s${seed}.log"
  Write-Host "`n=== $arm seed=$seed ==="
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $prev = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $common = @(
    "--pop","24","--gens","8","--seed","$seed","--threads","1",
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

  $fit = Get-Match $body 'REAL CHAMPION \(fitness=([-0-9.eE+]+)'
  $oos = Get-Match $body 'OOS summary: (\d+)/(\d+)'
  $oosH = ""; $oosC = ""
  if ($oos -ne "") {
    $mm = [regex]::Match($body, 'OOS summary: (\d+)/(\d+)')
    $oosH = $mm.Groups[1].Value
    $oosC = $mm.Groups[2].Value
  }
  # last qd / niches from final gen line
  $qdMatches = [regex]::Matches($body, 'qd=([-0-9.eE+]+)')
  $qd = if ($qdMatches.Count -gt 0) { $qdMatches[$qdMatches.Count - 1].Groups[1].Value } else { "" }
  $nicheMatches = [regex]::Matches($body, 'niches=(\d+)')
  $niches = if ($nicheMatches.Count -gt 0) { $nicheMatches[$nicheMatches.Count - 1].Groups[1].Value } else { "" }
  $hitMatches = [regex]::Matches($body, 'workHits=(\d+)')
  $hitSum = 0
  foreach ($h in $hitMatches) { $hitSum += [int]$h.Groups[1].Value }
  $ok = if ($body -match 'CORPUS_EVO_OK') { "1" } else { "0" }

  $line = "$arm`t$seed`t$fit`t$oosH`t$oosC`t$qd`t$niches`t$hitSum`t$wall`t$ok"
  Add-Content $TSV $line
  Write-Host "  fit=$fit oos=$oosH/$oosC qd=$qd niches=$niches workHitsSum=$hitSum wall=${wall}s ok=$ok"
}

foreach ($seed in $SEEDS) {
  # A = NMA without dirty-spine (cold fromEnum every evaluate)
  Invoke-Arm "A" $seed @("--no-nma-dirty-spine")
  Invoke-Arm "C" $seed @(
    "--nma-dirty-spine",
    "--speculative-growth-k","4",
    "--cvt-cells","64","--lexicase","--fitness-windows","4"
  )
}

Write-Host "`n=== RESULTS ==="
Get-Content $TSV
Write-Host "`nWrote $TSV"
