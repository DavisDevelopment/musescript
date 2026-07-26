# Equal-WALL comparison, which is the question that actually matters.
#
# The paired equal-generation test showed the hybrid path is 1.52x faster with a QD change of
# -3.28 (t=-1.91, not significant). But generations are not the budget -- time is. This gives the
# base arm 6 generations and the new arm 9, which is the same wall clock at the measured speeds,
# and asks which archive is better at the moment the clock runs out.

$seeds = @(42, 7, 123, 99, 31337, 2024, 555, 4242)
$tape = "build\graal\smoke_spy_320.csv"
$CP = (Get-Content graal\cp.txt -Raw).Trim()
$JAVA = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME "bin\java.exe" } else { "java" }

function Invoke-Arm($jar, $seed, $gens) {
	$prev = $ErrorActionPreference
	$ErrorActionPreference = "Continue"
	$sw = [Diagnostics.Stopwatch]::StartNew()
	$out = & $JAVA --sun-misc-unsafe-memory-access=allow -cp "$CP;$jar" `
		musescript.evo.graal.CorpusEvoRun --pop 1000 --gens $gens --seed $seed --threads 8 `
		--tape $tape --fitness-windows 1 --attr-bars 128 --no-cache --nma --phase-profile 2>&1 | Out-String
	$sw.Stop()
	$ErrorActionPreference = $prev
	$qdAll = [regex]::Matches($out, 'qd=([\d.]+)')
	$qd = if ($qdAll.Count) { [double]$qdAll[$qdAll.Count - 1].Groups[1].Value } else { [double]::NaN }
	$best = if ($out -match 'REAL CHAMPION \(fitness=([-\d.]+)') { [double]$Matches[1] } else { [double]::NaN }
	return [pscustomobject]@{ qd = $qd; best = $best; sec = $sw.Elapsed.TotalSeconds }
}

$dq = @(); $db = @(); $baseSec = @(); $newSec = @()
foreach ($s in $seeds) {
	$b = Invoke-Arm "..\muse-base\build\jvm\corpus-evo.jar" $s 6
	$n = Invoke-Arm "build\jvm\corpus-evo.jar" $s 9
	$dq += ($n.qd - $b.qd); $db += ($n.best - $b.best)
	$baseSec += $b.sec; $newSec += $n.sec
	Write-Host ("seed {0,-6} base(6g) qd {1,6:N2} best {2,5:N3} {3,5:N1}s   new(9g) qd {4,6:N2} best {5,5:N3} {6,5:N1}s   dQD {7,6:N2}" -f `
		$s, $b.qd, $b.best, $b.sec, $n.qd, $n.best, $n.sec, ($n.qd - $b.qd))
}

function Stat($vals) {
	$m = ($vals | Measure-Object -Average).Average
	$sd = [Math]::Sqrt((($vals | ForEach-Object { ($_ - $m) * ($_ - $m) } | Measure-Object -Sum).Sum) / ($vals.Count - 1))
	return @{ mean = $m; sd = $sd; t = if ($sd -gt 0) { $m / ($sd / [Math]::Sqrt($vals.Count)) } else { 0 } }
}

$q = Stat $dq; $bb = Stat $db
Write-Host ""
Write-Host ("EQUAL-WALL PAIRED n={0} (df={1})" -f $seeds.Count, ($seeds.Count - 1))
Write-Host ("  wall     base {0,5:N1}s   new {1,5:N1}s" -f `
	(($baseSec | Measure-Object -Average).Average), (($newSec | Measure-Object -Average).Average))
Write-Host ("  QD       mean {0,7:N2}  sd {1,6:N2}  t {2,6:N2}" -f $q.mean, $q.sd, $q.t)
Write-Host ("  champion mean {0,7:N3}  sd {1,6:N3}  t {2,6:N2}" -f $bb.mean, $bb.sd, $bb.t)
