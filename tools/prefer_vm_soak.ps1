# preferVm regression soak - DetParity (cheap) + MuseVm corpus/evolved + Fitness.preferVm path.
# preferVm defaults ON; this suite keeps Fitness-path parity green. See docs/ENGINE_MATRIX.md.
#
# Usage:
#   .\tools\prefer_vm_soak.ps1
#   .\tools\prefer_vm_soak.ps1 -Quick
#   .\tools\prefer_vm_soak.ps1 -FitnessOnly
param(
  [switch]$Quick,
  [switch]$FitnessOnly
)

# Fail on cmdlet errors; native haxe/node stderr warnings must not terminate.
$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
  $PSNativeCommandUseErrorActionPreference = $false
}

Set-Location $PSScriptRoot\..

Write-Host "============================================================"
Write-Host " preferVm soak (regression - default ON)"
Write-Host "============================================================"

if (-not $FitnessOnly) {
  Write-Host ""
  Write-Host "-- DetParityDump (node == golden) --"
  # Do not merge stderr (2>&1): under Stop, Haxe [WARNING] ErrorRecords would abort.
  & haxe build-det-parity-node.hxml
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  $out = Join-Path $env:TEMP "det-parity-soak.txt"
  # Capture stdout only; leave stderr alone so warnings are not ErrorRecords.
  $stdout = & node build/js/det-parity.js
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  $stdout | Out-File -Encoding utf8NoBOM $out
  $golden = "testdata/det-parity.golden.txt"
  $got = (Get-Content -Raw $out) -replace "`r`n", "`n"
  $exp = (Get-Content -Raw $golden) -replace "`r`n", "`n"
  if ($got.TrimEnd() + "`n" -ne $exp.TrimEnd() + "`n") {
    Write-Host "DET PARITY FAIL: drifted from testdata/det-parity.golden.txt" -ForegroundColor Red
    exit 1
  }
  Write-Host "DET_PARITY_OK (node == golden)"
}

if (-not $FitnessOnly -and -not $Quick) {
  Write-Host ""
  Write-Host "-- vm-parity (corpus + evolved MuseVm) --"
  & node tools/engine_matrix.mjs --only vm-parity
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host ""
Write-Host "-- prefer-vm-soak (Fitness.preferVm / vmParityCheck) --"
& node tools/engine_matrix.mjs --soak
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "PREFER_VM_SOAK_OK (preferVm default ON - Fitness-path parity green)"
