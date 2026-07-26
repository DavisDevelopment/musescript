# Paired A/B for the sim-coupled hybrid evaluation path.
#
# Interleaves base and new seed-by-seed rather than running one arm then the other: this machine
# drifts (thermal, background load) by more than the effects being measured, and a blocked
# A-then-B design charges all of that drift to the arm that ran second.
#
# base = HEAD 6368600, built in the ../muse-base worktree.
# new  = the working tree.

$seeds = @(42, 7, 123, 99, 31337, 2024, 555, 4242)
$tape = "build\graal\smoke_spy_320.csv"
$CP = (Get-Content graal\cp.txt -Raw).Trim()
$JAVA = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME "bin\java.exe" } else { "java" }
$jars = @{ base = "..\muse-base\build\jvm\corpus-evo.jar"; new = "build\jvm\corpus-evo.jar" }

function Invoke-Arm($jar, $seed) {
	$prev = $ErrorActionPreference
	$ErrorActionPreference = "Continue"
	$out = & $JAVA --sun-misc-unsafe-memory-access=allow -cp "$CP;$jar" `
		musescript.evo.graal.CorpusEvoRun --pop 1000 --gens 6 --seed $seed --threads 8 `
		--tape $tape --fitness-windows 1 --attr-bars 128 --no-cache --nma --phase-profile 2>&1 | Out-String
	$ErrorActionPreference = $prev

	$ms = if ($out -match 'mean ([\d.]+) ms/gen') { [double]$Matches[1] } else { [double]::NaN }
	# Last generation's qd= line is the end-of-run archive quality.
	$qdAll = [regex]::Matches($out, 'qd=([\d.]+)')
	$qd = if ($qdAll.Count) { [double]$qdAll[$qdAll.Count - 1].Groups[1].Value } else { [double]::NaN }
	$best = if ($out -match 'REAL CHAMPION \(fitness=([-\d.]+)') { [double]$Matches[1] } else { [double]::NaN }
	$cov = if ($out -match 'coverage=([\d.]+)[\s\S]*$') { [double]$Matches[1] } else { [double]::NaN }
	# Did a sim-coupled genome win? The two position-state builtins are the tell.
	$riskWin = $out -match 'REAL CHAMPION[\s\S]{0,600}?(bars_in_trade|unrealized_pnl)'
	return [pscustomobject]@{ ms = $ms; qd = $qd; best = $best; cov = $cov; riskWin = $riskWin }
}

$rows = @()
foreach ($s in $seeds) {
	$b = Invoke-Arm $jars.base $s
	$n = Invoke-Arm $jars.new  $s
	$rows += [pscustomobject]@{
		seed = $s
		baseMs = $b.ms; newMs = $n.ms; dMs = $n.ms - $b.ms
		baseQd = $b.qd; newQd = $n.qd; dQd = $n.qd - $b.qd
		baseBest = $b.best; newBest = $n.best
		newRiskWin = $n.riskWin
	}
	Write-Host ("seed {0,-6} ms {1,7:N1} -> {2,7:N1} (d {3,7:N1})   qd {4,6:N2} -> {5,6:N2} (d {6,6:N2})   best {7,5:N3} -> {8,5:N3}  riskChamp={9}" -f `
		$s, $b.ms, $n.ms, ($n.ms - $b.ms), $b.qd, $n.qd, ($n.qd - $b.qd), $b.best, $n.best, $n.riskWin)
}

function Stat($vals) {
	$m = ($vals | Measure-Object -Average).Average
	$sd = if ($vals.Count -gt 1) {
		[Math]::Sqrt((($vals | ForEach-Object { ($_ - $m) * ($_ - $m) } | Measure-Object -Sum).Sum) / ($vals.Count - 1))
	} else { 0 }
	return @{ mean = $m; sd = $sd; t = if ($sd -gt 0) { $m / ($sd / [Math]::Sqrt($vals.Count)) } else { 0 } }
}

$dms = Stat ($rows | ForEach-Object { $_.dMs })
$dqd = Stat ($rows | ForEach-Object { $_.dQd })
$speedup = (($rows | ForEach-Object { $_.baseMs } | Measure-Object -Average).Average) /
	(($rows | ForEach-Object { $_.newMs } | Measure-Object -Average).Average)

Write-Host ""
Write-Host ("PAIRED n={0} (df={1})" -f $rows.Count, ($rows.Count - 1))
Write-Host ("  ms/gen  mean {0,8:N1}  sd {1,7:N1}  t {2,7:N2}" -f $dms.mean, $dms.sd, $dms.t)
Write-Host ("  QD      mean {0,8:N2}  sd {1,7:N2}  t {2,7:N2}" -f $dqd.mean, $dqd.sd, $dqd.t)
Write-Host ("  speedup {0,5:N2}x" -f $speedup)
Write-Host ("  champions that are sim-coupled (new arm): {0}/{1}" -f `
	(($rows | Where-Object { $_.newRiskWin }).Count), $rows.Count)
