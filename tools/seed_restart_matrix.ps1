# Multi-CLI --seed restart matrix → SeedRobustness.verdict
# Bounded planted co-evo restarts (CI-friendly). For full CorpusEvoRun scrape, set MODE=corpus-evo.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

$TAPE = if ($env:SEED_MATRIX_TAPE) { $env:SEED_MATRIX_TAPE } else { "corpus\tapes\spy_oos_2022_2026.csv" }
$SEEDS = if ($env:SEED_MATRIX_SEEDS) { $env:SEED_MATRIX_SEEDS } else { "42,7,99" }
$POP = if ($env:SEED_MATRIX_POP) { $env:SEED_MATRIX_POP } else { "6" }
$GENS = if ($env:SEED_MATRIX_GENS) { $env:SEED_MATRIX_GENS } else { "2" }
$MAXBARS = if ($env:SEED_MATRIX_MAX_BARS) { $env:SEED_MATRIX_MAX_BARS } else { "800" }

Write-Host "Building seed-restart-matrix..."
haxe build-seed-restart-matrix.hxml
if ($LASTEXITCODE -ne 0) { throw "build failed" }

node build/js/seed-restart-matrix.js `
  --tape $TAPE `
  --seeds $SEEDS `
  --pop $POP `
  --gens $GENS `
  --max-bars $MAXBARS `
  --n-trials 5
exit $LASTEXITCODE
