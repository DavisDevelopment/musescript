# JVM CorpusEvoRun fallback-pool NMA determinism probe.
# N genomes x M fb workers x K reps must match serial (ok/trades/sharpe/equity).
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

haxe build-corpus-evo.hxml
if ($LASTEXITCODE -ne 0) { throw "haxe build-corpus-evo.hxml failed" }

$CP = (Get-Content graal\cp.txt -Raw).Trim()
$JAR = "build\jvm\corpus-evo.jar"
$JAVA = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME "bin\java.exe" } else { "java" }

$javaArgs = @(
  "--sun-misc-unsafe-memory-access=allow",
  "-cp", "$CP;$JAR",
  "musescript.evo.graal.CorpusEvoRun",
  "--det-probe",
  "--pop", "64",
  "--reps", "3",
  "--threads-list", "2,4",
  "--seed", "42",
  "--tape", "build/graal/smoke_spy_320.csv"
)
if ($args.Count -gt 0) { $javaArgs += $args }

Write-Host "$JAVA $($javaArgs -join ' ')"
& $JAVA @javaArgs
if ($LASTEXITCODE -ne 0) { throw "NMA JVM det probe failed (exit $LASTEXITCODE)" }
