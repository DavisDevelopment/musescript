package musescript.evo.rigor;

import musescript.ew.mcmc.DetRng;
import haxe.Int64;

/**
 * Stationary / moving-block bootstrap for Sharpe confidence intervals.
 * Returns are autocorrelated; i.i.d. bootstrap understates variance.
 */
class BlockBootstrap {
	/**
	 * Percentile CI for annualized Sharpe of `returns` via moving-block bootstrap.
	 * `blockLen` default ≈ √n. Uses `DetRng` for determinism.
	 * Returns `{lo, hi, point}` where point is the sample Sharpe (√252).
	 */
	public static function sharpeCi(
		returns:Array<Float>,
		?seed:Int = 42,
		?nBoot:Int = 400,
		?blockLen:Int = 0,
		?level:Float = 0.95
	):{lo:Float, hi:Float, point:Float} {
		var point = annSharpe(returns);
		var n = returns.length;
		if (n < 4) return {lo: Math.NaN, hi: Math.NaN, point: point};
		var bl = blockLen > 0 ? blockLen : Std.int(Math.max(2, Math.ffloor(Math.sqrt(n))));
		if (bl > n) bl = n;
		var rng = new DetRng(Int64.ofInt(seed), Int64.ofInt(0xB007));
		var scores:Array<Float> = [];
		var buf:Array<Float> = [for (_ in 0...n) 0.0];
		for (_ in 0...nBoot) {
			var filled = 0;
			while (filled < n) {
				var start = rng.nextInt(n);
				var k = 0;
				while (k < bl && filled < n) {
					buf[filled++] = returns[(start + k) % n];
					k++;
				}
			}
			scores.push(annSharpe(buf));
		}
		scores.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		var alpha = (1.0 - level) / 2.0;
		var loI = Std.int(Math.ffloor(alpha * (scores.length - 1)));
		var hiI = Std.int(Math.ceil((1.0 - alpha) * (scores.length - 1)));
		if (loI < 0) loI = 0;
		if (hiI >= scores.length) hiI = scores.length - 1;
		return {lo: scores[loI], hi: scores[hiI], point: point};
	}

	/** True when the CI excludes `nullValue` on the positive side (beat). */
	public static function excludesNull(ci:{lo:Float, hi:Float, point:Float}, nullValue:Float = 0.0):Bool {
		return Math.isFinite(ci.lo) && ci.lo > nullValue;
	}

	/** Annualized Sharpe of `returns`. `periodsPerYear` must MATCH whatever
	 *  `ProbSharpe.rankFromAnnualized` is later given to un-annualize with — they are a
	 *  round-trip pair, and a mismatch silently rescales the PSR/DSR rank. */
	static function annSharpe(returns:Array<Float>,
			periodsPerYear:Float = musescript.harness.Metrics.DAILY_PERIODS_PER_YEAR):Float {
		var m = ProbSharpe.moments(returns);
		if (m.n < 2 || m.std <= 0) return 0;
		return (m.mean / m.std) * Math.sqrt(periodsPerYear);
	}
}
