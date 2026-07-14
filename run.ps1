# Run MuseScript examples / tests (Windows PowerShell)
param(
  [string]$Target = "01"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$Py = Join-Path $PSScriptRoot ".venv\Scripts\python.exe"
if (-not (Test-Path $Py)) {
  Write-Host "Creating local venv..."
  python -m venv .venv
  & $Py -m pip install --upgrade pip
  & $Py -m pip install -r requirements.txt
}

function Build-Js {
  Write-Host "Building JS..."
  haxe build.hxml
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Build-Py {
  Write-Host "Building Python..."
  haxe build-py.hxml
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

switch ($Target) {
  "01" { Build-Js; node build/js/01-hello-bar.js }
  "02" { Build-Js; node build/js/02-params-tune.js }
  "03" { Build-Js; node build/js/03-discovery-pipeline.js }
  "04" { Build-Js; node build/js/04-order-flow.js }
  "05" { Build-Js; node build/js/05-generators.js }
  "06" { Build-Js; node build/js/06-benchmark.js }
  "07" {
    Build-Js
    Build-Py
    Write-Host "`n--- JS host (pure-js + wasm) ---"
    node build/js/07-runtime-stress.js
    Write-Host "`n--- Python host (pure-python + numba + wasm) ---"
    & $Py build/py/07-runtime-stress.py
  }
  "08" {
    Build-Js
    Write-Host "`n--- Indicator suite (JS host) ---"
    node build/js/08-indicator-suite.js
    Build-Py
    Write-Host "`n--- Indicator suite (Python host) ---"
    & $Py build/py/08-indicator-suite.py
  }
  "09" {
    Build-Js
    Write-Host "`n--- Indicator kernels JS/WASM ---"
    node build/js/09-indicator-kernels.js
    Build-Py
    Write-Host "`n--- Indicator kernels Python/numba/WASM ---"
    & $Py build/py/09-indicator-kernels.py
  }
  "fetch-ohlcv" {
    & $Py -m pip install yfinance --quiet
    & $Py tools/fetch_ohlcv.py
  }
  "04b" { Build-Js; node build/js/04b-order-flow-live.js }
  "test" { Build-Js; node build/js/tests.js }
  "test-py" { Build-Py; & $Py build/py/tests.py }
  "venv" {
    Write-Host "venv ready: $Py"
    & $Py -c "import numba,numpy,wasmtime; print('numba', numba.__version__); print('numpy', numpy.__version__)"
  }
  "all" {
    Build-Js
    Build-Py
    node build/js/01-hello-bar.js
    node build/js/02-params-tune.js
    node build/js/03-discovery-pipeline.js
    node build/js/04-order-flow.js
    node build/js/04b-order-flow-live.js
    node build/js/05-generators.js
    node build/js/06-benchmark.js
    node build/js/07-runtime-stress.js
    node build/js/08-indicator-suite.js
    node build/js/09-indicator-kernels.js
    node build/js/tests.js
    & $Py build/py/07-runtime-stress.py
    & $Py build/py/08-indicator-suite.py
    & $Py build/py/09-indicator-kernels.py
    & $Py build/py/tests.py
  }
  default { Build-Js; node build/js/01-hello-bar.js }
}
