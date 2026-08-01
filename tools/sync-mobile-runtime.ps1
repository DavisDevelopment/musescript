# sync-mobile-runtime.ps1 — rebuild MuseScript mobile runtime and copy into the app.
#
# Dev (default): readable raw → mobile/src/lab/muse-runtime.js
# Ship (-Ship): locked preset → mobile/src/lab/muse-runtime.ship.js
#   (Vite --mode ship aliases muse-runtime.js → muse-runtime.ship.js; see vite.config.js)
#
#   pwsh tools/sync-mobile-runtime.ps1
#   pwsh tools/sync-mobile-runtime.ps1 -Ship

param(
  [switch]$Ship,
  [ValidateSet("medium", "heavy", "")]
  [string]$Preset = ""
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Write-Host "Building mobile runtime (build-runtime.hxml)..."
haxe build-runtime.hxml
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$labDir = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\mobile\src\lab")
$rawDst = Join-Path $labDir "muse-runtime.js"
$shipDst = Join-Path $labDir "muse-runtime.ship.js"
$rawSrc = Join-Path $PSScriptRoot "..\build\js\muse-runtime.js"

function Sync-File([string]$src, [string]$dst, [string]$label) {
  if (-not (Test-Path $src)) {
    Write-Error "Missing source: $src"
  }
  $srcHash = (Get-FileHash $src -Algorithm SHA256).Hash
  $dstHash = if (Test-Path $dst) { (Get-FileHash $dst -Algorithm SHA256).Hash } else { "" }
  if ($srcHash -eq $dstHash) {
    Write-Host "$label already in sync ($([math]::Round((Get-Item $src).Length/1KB)) KB)"
  } else {
    Copy-Item $src $dst -Force
    Write-Host "$label synced -> $dst ($([math]::Round((Get-Item $src).Length/1KB)) KB)"
  }
}

# Always refresh readable raw for day-to-day Vite/dev.
Sync-File $rawSrc $rawDst "raw"

if ($Ship) {
  $lockFile = Join-Path $PSScriptRoot "..\build\ship\LOCKED_PRESET"
  $usePreset = $Preset
  if (-not $usePreset) {
    if (Test-Path $lockFile) {
      $usePreset = (Get-Content $lockFile -Raw).Trim().ToLower()
    } else {
      $usePreset = "medium"
      Write-Host "No LOCKED_PRESET — defaulting to medium"
    }
  }
  $src = Join-Path $PSScriptRoot "..\build\ship\$usePreset\muse-runtime.js"
  if (-not (Test-Path $src)) {
    Write-Host "Missing ship artifact $src — run: npm run ship-js && npm run ship-ab"
    exit 1
  }
  Write-Host "Ship sync preset=$usePreset"
  Sync-File $src $shipDst "ship"
}
