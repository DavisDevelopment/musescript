# Aggregate jdk.ObjectAllocationSample weights from a JFR recording, by allocated class
# and by innermost musescript.* stack frame.
#
#   scripts\jfr_alloc.ps1 build\before.jfr
#
# NOTE: never pipe the `java` invocation that produces the recording into
# `Select-Object -First N` -- that closes the pipe early, kills the JVM before JFR
# flushes, and leaves an empty recording. Use `Select-String` to filter instead.
param(
    [Parameter(Mandatory = $true)][string]$Jfr,
    [int]$Top = 20,
    # Restrict the by-frame table to one allocated class, e.g. -Class java/lang/Double
    [string]$Class = "",
    # Skip musescript frames matching this regex when picking the innermost one, so a shared
    # container (e.g. GrowableFloatImpl.grow) attributes to whoever actually allocated it.
    [string]$ExcludeFrame = ""
)

$jfrTool = Join-Path $env:JAVA_HOME "bin\jfr.exe"
$json = & $jfrTool print --json --events jdk.ObjectAllocationSample $Jfr | ConvertFrom-Json

$byClass = @{}
$byFrame = @{}
$total = 0.0

foreach ($e in $json.recording.events) {
    $v = $e.values
    $w = [double]$v.weight
    $total += $w

    $cls = $v.objectClass.name
    if ($null -eq $cls) { $cls = "?" }
    $byClass[$cls] = [double]$byClass[$cls] + $w

    $frame = "(no musescript frame)"
    if ($v.stackTrace -and $v.stackTrace.frames) {
        foreach ($f in $v.stackTrace.frames) {
            $t = $f.method.type.name
            # JFR reports internal (slash-separated) class names.
            if ($t -and $t.StartsWith("musescript/")) {
                $cand = "$($t -replace '/', '.').$($f.method.name)"
                if ($ExcludeFrame -ne "" -and $cand -match $ExcludeFrame) { continue }
                $frame = $cand
                break
            }
        }
    }
    if ($Class -eq "" -or $Class -eq $cls) { $byFrame[$frame] = [double]$byFrame[$frame] + $w }
}

function Show($title, $map) {
    Write-Host ""
    Write-Host $title
    $map.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First $Top |
        ForEach-Object { "{0,10:N1} MB  {1}" -f ($_.Value / 1MB), $_.Key }
}

Write-Host ("total sampled allocation: {0:N1} MB over {1} samples" -f ($total / 1MB), $json.recording.events.Count)
Show "by objectClass:" $byClass
Show "by innermost musescript.* frame:" $byFrame
