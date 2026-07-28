package musescript.evo.rigor;

/**
 * Probability of Backtest Overfitting via Combinatorially Symmetric Cross-Validation
 * (Bailey et al. CSCV).
 *
 * Partition `T` contiguous return-path slices into two equal sets S and S̄ in every
 * combination. For each partition, pick the IS-best strategy (max mean return on S)
 * and check whether it lands above the median OOS (on S̄). PBO = fraction of partitions
 * where the IS-best is ≤ median OOS.
 *
 * PBO ≈ 0.5 ⇒ selection is no better than chance; PBO ≫ 0.5 ⇒ overfit selection.
 */
class Pbo {
	/**
	 * `perf[strategy][slice]` = performance of strategy i on time-slice j.
	 * Requires even number of slices ≥ 2 and ≥ 1 strategy.
	 * When combinations exceed `maxCombos`, samples uniformly (DetRng-free: stride).
	 */
	public static function estimate(perf:Array<Array<Float>>, ?maxCombos:Int = 2000):Float {
		var nStrat = perf.length;
		if (nStrat < 1) return Math.NaN;
		var nSlices = perf[0].length;
		for (row in perf) if (row.length != nSlices) return Math.NaN;
		if (nSlices < 2 || (nSlices % 2) != 0) return Math.NaN;
		var half = Std.int(nSlices / 2);
		var combos = combinations(nSlices, half);
		var overfit = 0;
		var used = 0;
		var step = combos.length > maxCombos ? Std.int(Math.ceil(combos.length / maxCombos)) : 1;
		var c = 0;
		while (c < combos.length) {
			var isSet = combos[c];
			var inIs = [for (_ in 0...nSlices) false];
			for (ix in isSet) inIs[ix] = true;
			// IS mean per strategy
			var bestI = 0;
			var bestIs = Math.NEGATIVE_INFINITY;
			var oosOfBest = 0.0;
			var oosAll:Array<Float> = [];
			for (s in 0...nStrat) {
				var isSum = 0.0, isN = 0, oosSum = 0.0, oosN = 0;
				for (j in 0...nSlices) {
					if (inIs[j]) { isSum += perf[s][j]; isN++; }
					else { oosSum += perf[s][j]; oosN++; }
				}
				var isMean = isN > 0 ? isSum / isN : Math.NEGATIVE_INFINITY;
				var oosMean = oosN > 0 ? oosSum / oosN : Math.NaN;
				oosAll.push(oosMean);
				if (isMean > bestIs) {
					bestIs = isMean;
					bestI = s;
					oosOfBest = oosMean;
				}
			}
			oosAll.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
			var med = median(oosAll);
			if (!(oosOfBest > med)) overfit++;
			used++;
			c += step;
		}
		return used > 0 ? overfit / used : Math.NaN;
	}

	/** Gate: flag overfitting when PBO ≥ `threshold` (default 0.5). */
	public static function isOverfit(pbo:Float, threshold:Float = 0.5):Bool {
		return Math.isFinite(pbo) && pbo >= threshold;
	}

	static function median(xs:Array<Float>):Float {
		if (xs.length == 0) return Math.NaN;
		var m = Std.int(xs.length / 2);
		return (xs.length % 2 == 0) ? 0.5 * (xs[m - 1] + xs[m]) : xs[m];
	}

	/** All combinations of `k` indices from `0..n-1`. */
	static function combinations(n:Int, k:Int):Array<Array<Int>> {
		var out:Array<Array<Int>> = [];
		var cur:Array<Int> = [];
		function rec(start:Int, left:Int):Void {
			if (left == 0) {
				out.push(cur.copy());
				return;
			}
			var i = start;
			while (i <= n - left) {
				cur.push(i);
				rec(i + 1, left - 1);
				cur.pop();
				i++;
			}
		}
		rec(0, k);
		return out;
	}
}
