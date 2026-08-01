# Bounded multi-gen planted co-evo on a real tape → hardened OOS GO/NO-GO
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

$TAPE = if ($env:PLANTED_TAPE) { $env:PLANTED_TAPE } else {
  if (Test-Path "data\real\tsla.csv") { "data\real\tsla.csv" }
  else { "corpus\tapes\spy_oos_2022_2026.csv" }
}
$SEED = if ($env:PLANTED_SEED) { $env:PLANTED_SEED } else { "42" }
$POP = if ($env:PLANTED_POP) { $env:PLANTED_POP } else { "8" }
$GENS = if ($env:PLANTED_GENS) { $env:PLANTED_GENS } else { "4" }
$MAXBARS = if ($env:PLANTED_MAX_BARS) { $env:PLANTED_MAX_BARS } else { "1200" }

Write-Host "Building planted-coevo (tape=$TAPE)..."
haxe build-planted-coevo.hxml
if ($LASTEXITCODE -ne 0) { throw "build failed" }

node build/js/planted-coevo.js `
  --tape $TAPE `
  --seed $SEED `
  --pop $POP `
  --gens $GENS `
  --max-bars $MAXBARS `
  --n-trials 5 `
  --prereg `
  --prereg-threshold 0
exit $LASTEXITCODE
