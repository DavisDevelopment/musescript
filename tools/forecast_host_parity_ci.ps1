# Initiative 2.1 — CI auto-diff: ForecastHostParityDump byte-identical on JVM vs node.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if (-not $Root) { $Root = (Resolve-Path "$PSScriptRoot\..").Path }
Set-Location $Root

haxe build-forecast-host-parity-node.hxml
haxe build-forecast-host-parity-jvm.hxml

$nodeOut = Join-Path $Root "build\forecast-host-parity-node.txt"
$jvmOut = Join-Path $Root "build\forecast-host-parity-jvm.txt"
node build/js/forecast-host-parity.js | Set-Content -Encoding ascii $nodeOut
java -jar build/jvm/forecast-host-parity.jar | Set-Content -Encoding ascii $jvmOut

$hNode = (Get-FileHash $nodeOut).Hash
$hJvm = (Get-FileHash $jvmOut).Hash
if ($hNode -ne $hJvm) {
  Write-Error "FORECAST HOST PARITY FAIL: JVM vs node differ"
  Compare-Object (Get-Content $nodeOut) (Get-Content $jvmOut) | Select-Object -First 40
  exit 1
}

$golden = Join-Path $Root "testdata\forecast-host-parity.golden.txt"
if (Test-Path $golden) {
  $a = [IO.File]::ReadAllText($nodeOut) -replace "`r`n", "`n"
  $b = [IO.File]::ReadAllText($golden) -replace "`r`n", "`n"
  if ($a -ne $b) {
    Write-Error "FORECAST HOST PARITY FAIL: node output drifted from testdata/forecast-host-parity.golden.txt"
    exit 1
  }
}

Write-Host "FORECAST_HOST_PARITY_OK (jvm == node == golden)"
