# Web ↔ app EquityDigest parity (CURSOR_TODO Task 1 accept).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if (-not $Root) { $Root = (Resolve-Path "$PSScriptRoot\..").Path }
Set-Location $Root
if (-not (Test-Path "build/js/muse-runtime.js")) {
  Write-Host "building muse-runtime.js…"
  haxe build-runtime.hxml
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
node tools/equity_digest_web_app_parity.mjs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
