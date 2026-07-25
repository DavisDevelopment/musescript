# Isolated credit-axis sweep: no lexicase, no novelty bonus, no dirty-spine.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..
$OUTDIR = "build\graal\nma-ab-credit-axis"
New-Item -ItemType Directory -Force -Path $OUTDIR | Out-Null
$TSV = Join-Path $OUTDIR "results.tsv"
haxe build-corpus-evo.hxml
if ($LASTEXITCODE -ne 0) { throw "build failed" }
$CP = (Get-Content graal\cp.txt -Raw).Trim()
$JAR = "build\jvm\corpus-evo.jar"
$JAVA = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME "bin\java.exe" } else { "java" }
$TAPE = "corpus\tapes\spy_oos_2022_2026.csv"
"arm`tseed`tfitness`toos_held`toos_checked`tqd_last`tniches_last`twall_s`tok" | Set-Content $TSV

function Invoke-Arm($arm, $seed, $extra) {
  $log = Join-Path $OUTDIR "${arm}_s${seed}.log"
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $common = @(
    "--pop","24","--gens","12","--seed","$seed","--threads","6",
    "--tape",$TAPE,"--fitness-windows","1","--attr-bars","256",
    "--no-cache","--nma","--no-nma-dirty-spine","--novelty-weight","0"
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
  $niches = ""; $nm = [regex]::Matches($body, 'niches=([0-9]+)')
  if ($nm.Count -gt 0) { $niches = $nm[$nm.Count - 1].Groups[1].Value }
  $ok = if ($body -match 'CORPUS_EVO_OK') { "1" } else { "0" }
  $wall = [math]::Round($sw.Elapsed.TotalSeconds, 1)
  Add-Content $TSV "$arm`t$seed`t$fit`t$oosH`t$oosC`t$qd`t$niches`t$wall`t$ok"
  Write-Host "$arm seed=$seed fit=$fit oos=$oosH/$oosC qd=$qd niches=$niches wall=$wall ok=$ok"
}

foreach ($seed in @(42, 7, 123, 99, 31337)) {
  Invoke-Arm "classic48" $seed @()
  Invoke-Arm "cvt4" $seed @("--cvt-cells","64")
  Invoke-Arm "credit5_v2" $seed @("--cvt-cells","64","--credit-map-axis")
}
Get-Content $TSV
