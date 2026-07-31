# PanelRunner smoke gate: build the panel CLI and run the reference 2-symbol
# momentum-scan panel (tools/panel_momscan.ms) on real tapes. PASS iff the JSON
# line has ok:true, panel:true and trades > 0. Tapes come from the standard
# pipeline: python tools/fetch_ohlcv.py --tickers MSFT --out data/real/msft.csv
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

haxe build-panel-cli.hxml
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$line = node build/js/panel-runner.js --source tools/panel_momscan.ms `
  --tapes AAPL=data/real/aapl.csv,MSFT=data/real/msft.csv `
  --cost-bps 20 --tier js --seed 42
Write-Output $line

$res = $line | ConvertFrom-Json
if ($res.ok -and $res.panel -and $res.trades -gt 0) {
  Write-Output "panel_smoke: PASS (trades=$($res.trades) sharpe=$($res.sharpe))"
  exit 0
}
Write-Output "panel_smoke: FAIL"
exit 1
