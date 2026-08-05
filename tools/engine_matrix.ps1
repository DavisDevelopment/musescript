# Engine-matrix honesty gate (PowerShell wrapper -> node tools/engine_matrix.mjs)
# Source of truth: tools/engine_matrix.mjs. Fail only on non-zero exit (Haxe
# [WARNING] on stderr must not abort).

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
  $PSNativeCommandUseErrorActionPreference = $false
}

Set-Location $PSScriptRoot\..
& node tools/engine_matrix.mjs @args
exit $LASTEXITCODE
