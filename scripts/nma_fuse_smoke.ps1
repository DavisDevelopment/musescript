# Quick fuse-host smoke on JVM (one short corpus run, print fuseCalls)
$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot\..
haxe build-corpus-evo.hxml
if ($LASTEXITCODE -ne 0) { throw "build failed" }
$CP = (Get-Content graal\cp.txt -Raw).Trim()
$JAR = "build\jvm\corpus-evo.jar"
$JAVA = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME "bin\java.exe" } else { "java" }
$smoke = "build\graal\smoke_spy_320.csv"
if (-not (Test-Path $smoke)) {
  Get-Content corpus\tapes\spy_oos_2022_2026.csv -TotalCount 321 | Set-Content $smoke
}
$log = "build\graal\fuse_smoke.log"
& $JAVA --sun-misc-unsafe-memory-access=allow -cp "$CP;$JAR" musescript.evo.graal.CorpusEvoRun `
  --pop 16 --gens 5 --seed 42 --threads 1 --tape $smoke `
  --fitness-windows 1 --attr-bars 128 --no-cache --nma `
  --nma-fuse-host --nma-fuse-min-bars 0 `
  2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $log | Out-Null
Select-String -Path $log -Pattern 'fuse-host|fuseCalls|fuseFb|CORPUS_EVO_OK|init failed'
