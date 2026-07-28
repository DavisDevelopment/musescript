# Bucket D4 — CI auto-diff: DetParityDump must be byte-identical on JVM vs node.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if (-not $Root) { $Root = (Resolve-Path "$PSScriptRoot\..").Path }
Set-Location $Root

haxe build-det-parity-node.hxml
haxe build-det-parity-jvm.hxml

$nodeOut = Join-Path $Root "build\det-parity-node.txt"
$jvmOut = Join-Path $Root "build\det-parity-jvm.txt"
node build/js/det-parity.js | Set-Content -Encoding ascii $nodeOut
java -jar build/jvm/det-parity.jar | Set-Content -Encoding ascii $jvmOut

$hNode = (Get-FileHash $nodeOut).Hash
$hJvm = (Get-FileHash $jvmOut).Hash
if ($hNode -ne $hJvm) {
  Write-Error "DET PARITY FAIL: JVM vs node differ"
  Compare-Object (Get-Content $nodeOut) (Get-Content $jvmOut) | Select-Object -First 40
  exit 1
}

$golden = Join-Path $Root "testdata\det-parity.golden.txt"
if (Test-Path $golden) {
  # Normalize line endings for compare
  $a = [IO.File]::ReadAllText($nodeOut) -replace "`r`n", "`n"
  $b = [IO.File]::ReadAllText($golden) -replace "`r`n", "`n"
  if ($a -ne $b) {
    Write-Error "DET PARITY FAIL: node output drifted from testdata/det-parity.golden.txt"
    exit 1
  }
}

Write-Host "DET_PARITY_OK (jvm == node == golden)"
