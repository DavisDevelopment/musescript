# Same-seed cold-vs-dirty search parity probe. Any key/fitness drift needs explanation.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..
$OUTDIR = "build\graal\nma-dirty-parity"
New-Item -ItemType Directory -Force -Path $OUTDIR | Out-Null
$TSV = Join-Path $OUTDIR "results.tsv"
haxe build-corpus-evo.hxml
if ($LASTEXITCODE -ne 0) { throw "build failed" }
$CP = (Get-Content graal\cp.txt -Raw).Trim()
$JAR = "build\jvm\corpus-evo.jar"
$JAVA = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME "bin\java.exe" } else { "java" }
$TAPE = "corpus\tapes\spy_oos_2022_2026.csv"
"arm`tseed`tkey`tfitness`toos_held`twall_s`twork_hits`tok" | Set-Content $TSV

function Invoke-Arm($arm, $seed, $extra) {
  $log = Join-Path $OUTDIR "${arm}_s${seed}.log"
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
  $key = ""; $km = [regex]::Matches($body, 'champion="[^"]*" key=([0-9a-f?]+)')
  if ($km.Count -gt 0) { $key = $km[$km.Count - 1].Groups[1].Value }
  $oos = if ($body -match 'OOS summary: (\d+)/(\d+)') { $Matches[1] } else { "" }
  $work = ""; $wm = [regex]::Matches($body, 'workHits=([0-9]+)')
  if ($wm.Count -gt 0) { $work = $wm[$wm.Count - 1].Groups[1].Value }
  $ok = if ($body -match 'CORPUS_EVO_OK') { "1" } else { "0" }
  $wall = [math]::Round($sw.Elapsed.TotalSeconds, 1)
  Add-Content $TSV "$arm`t$seed`t$key`t$fit`t$oos`t$wall`t$work`t$ok"
  Write-Host "$arm seed=$seed key=$key fit=$fit oos=$oos wall=$wall work=$work ok=$ok"
}

foreach ($seed in @(42, 7, 123)) {
  Invoke-Arm "cold" $seed @("--no-nma-dirty-spine")
  Invoke-Arm "dirty" $seed @("--nma-dirty-spine")
}
Get-Content $TSV
