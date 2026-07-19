# sync-mobile-runtime.ps1 — rebuild the MuseScript mobile runtime and copy it into the app.
#
# The mobile/Electron app ships a prebuilt `mobile/src/lab/muse-runtime.js` (the Haxe-compiled
# tree-walking runtime — interp + iterators/generators + kestrel ABI). It is a straight copy of
# `build/js/muse-runtime.js`; there is no bundler step between them, so it silently goes STALE
# whenever the MuseScript source changes. Run this after any runtime-affecting change so the app
# runs the current runtime (missing this is how it drifted a full day behind, dropping arrow
# lambdas + WASM lowering from the shipped app).
#
#   pwsh tools/sync-mobile-runtime.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Write-Host "Building mobile runtime (build-runtime.hxml)..."
haxe build-runtime.hxml
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$src = Join-Path $PSScriptRoot "..\build\js\muse-runtime.js"
$dst = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\mobile\src\lab\muse-runtime.js")

$srcHash = (Get-FileHash $src -Algorithm SHA256).Hash
$dstHash = if (Test-Path $dst) { (Get-FileHash $dst -Algorithm SHA256).Hash } else { "" }

if ($srcHash -eq $dstHash) {
  Write-Host "Already in sync ($([math]::Round((Get-Item $src).Length/1KB)) KB) — no change."
} else {
  Copy-Item $src $dst -Force
  Write-Host "Synced -> $dst ($([math]::Round((Get-Item $dst).Length/1KB)) KB)."
}
