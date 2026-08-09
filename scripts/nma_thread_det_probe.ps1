# Multi-thread NMA score determinism probe (Node / NmaNodeEvalPool).
# N genomes x M threads x K reps must match serial fitness vectors.
# See NmaNodeBench --det-probe and JIT_AUTHORING_GUIDE.md §27 owed gate.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

haxe build-nma-node-bench.hxml
if ($LASTEXITCODE -ne 0) { throw "haxe build-nma-node-bench.hxml failed" }

$nodeArgs = @(
  "build/js/nma-node-bench.js",
  "--det-probe",
  "--pop", "64",
  "--reps", "3",
  "--threads-list", "2,4",
  "--seed", "42"
)
# Extra args append; NmaNodeBench keeps the first match for each flag name.
if ($args.Count -gt 0) { $nodeArgs += $args }

Write-Host "node $($nodeArgs -join ' ')"
& node @nodeArgs
if ($LASTEXITCODE -ne 0) { throw "NMA det probe failed (exit $LASTEXITCODE)" }
