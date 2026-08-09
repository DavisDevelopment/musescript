package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.SortedWindow;
import musescript.types.MuseType;

/**
 * Rolling Spearman rank correlation — ported from wickra-core's
 * `SpearmanCorrelation`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/spearman_correlation.rs).
 *
 * Over the trailing window of `period` (x, y) pairs, the values in each
 * channel are replaced by their ranks (mid-ranks for ties) and the Pearson
 * correlation of those ranks is reported:
 *
 *   Spearman = Pearson( rank(x), rank(y) )
 *
 * The non-linear, MONOTONE analogue of `pearson_correlation`: +1 means any
 * monotone co-movement (not just linear), −1 opposite movement. A window in
 * which one channel is constant has no rank dispersion and 0 is returned.
 * Output clamped to [−1, +1].
 *
 * SortedWindow invent (landed): dual value spines (`wx`/`wy`) stay ascending
 * via binary insert/remove. Per-chrono mid-ranks materialize without
 * `Array.sort` by (1) walking the sorted multiset for mid-tie groups into
 * `midAt[sortedPos]`, then (2) lower_bound of each chrono value into that
 * table. Equal values share one mid — tie order in the spine does not matter.
 * Full Pearson over the rank arrays is kept (Δ-Pearson of ranks stays
 * ULP-hostile through five sums + √; do not invent it). Proven bit-lock vs
 * IndicatorGolden + port suite.
 */
class SpearmanCorrelation implements MuseIndicator<SpearmanPair, Float> {
	var period:Int;
	var wx:SortedWindow;
	var wy:SortedWindow;
	var rx:Array<Float>;
	var ry:Array<Float>;
	/** Mid-rank at each position of the current sorted spine (length = period when ready). */
	var midAt:Array<Float>;

	public function new(period:Int) {
		if (period < 2) throw "SpearmanCorrelation: period must be >= 2";
		this.period = period;
		wx = new SortedWindow(period);
		wy = new SortedWindow(period);
		rx = [for (_ in 0...period) 0.0];
		ry = [for (_ in 0...period) 0.0];
		midAt = [for (_ in 0...period) 0.0];
	}

	/**
	 * Fill `ranksOut[chronoIndex] = mid-rank` from a SortedWindow's ascending
	 * spine + chronological ring — same mid-tie formula as the former
	 * scratch.sort `rankInto`.
	 */
	function rankFromWindow(w:SortedWindow, ranksOut:Array<Float>):Void {
		var sorted = w.sorted;
		var n = sorted.length;
		var i = 0;
		while (i < n) {
			var j = i + 1;
			while (j < n && sorted[j] == sorted[i]) j++;
			// Mid-rank of positions [i, j−1] in 1-indexed terms: (i + 1 + j) / 2.
			var mid = (i + 1.0 + j) / 2.0;
			for (k in i...j) midAt[k] = mid;
			i = j;
		}
		for (ci in 0...n) {
			var v = w.oldest(ci);
			var lo = 0;
			var hi = n;
			while (lo < hi) {
				var m = (lo + hi) >> 1;
				if (sorted[m] < v) lo = m + 1;
				else hi = m;
			}
			ranksOut[ci] = midAt[lo];
		}
	}

	public function update(input:SpearmanPair):Null<Float> {
		if (!Math.isFinite(input.x) || !Math.isFinite(input.y)) return null;
		wx.push(input.x);
		wy.push(input.y);
		if (wx.length < period) return null;
		rankFromWindow(wx, rx);
		rankFromWindow(wy, ry);
		// Pearson over the rank arrays (mid-ranks make the closed forms
		// inapplicable; the generic Pearson keeps the code uniform).
		var n:Float = period;
		var sumX = 0.0, sumY = 0.0, sumXx = 0.0, sumYy = 0.0, sumXy = 0.0;
		for (i in 0...period) {
			var x = rx[i];
			var y = ry[i];
			sumX += x;
			sumY += y;
			sumXx += x * x;
			sumYy += y * y;
			sumXy += x * y;
		}
		var meanX = sumX / n;
		var meanY = sumY / n;
		var varX = sumXx / n - meanX * meanX;
		if (varX < 0.0) varX = 0.0;
		var varY = sumYy / n - meanY * meanY;
		if (varY < 0.0) varY = 0.0;
		var cov = sumXy / n - meanX * meanY;
		var denom = Math.sqrt(varX * varY);
		if (denom == 0.0) return 0.0;
		var r = cov / denom;
		if (r > 1.0) r = 1.0;
		if (r < -1.0) r = -1.0;
		return r;
	}

	public function reset():Void {
		wx = new SortedWindow(period);
		wy = new SortedWindow(period);
		rx = [for (_ in 0...period) 0.0];
		ry = [for (_ in 0...period) 0.0];
		midAt = [for (_ in 0...period) 0.0];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return wx.length == period;
	public function name():String return "SpearmanCorrelation";

	public static function spec():IndicatorSpec {
		return {
			name: "spearman_correlation", args: [TSeries, TSeries, TWindow], ret: TScalar, minArgs: 3,
			eval: function(h, args) {
				var seriesX = IndicatorCache.seriesArg(args, 0, "close");
				var seriesY = IndicatorCache.seriesArg(args, 1, "close");
				var p = IndicatorCache.intArg(args, 2, 20);
				var key = "spearman_correlation:" + seriesX + ":" + seriesY + ":" + p;
				return IndicatorCache.evalPair(h, key, seriesX, seriesY, Math.NaN,
					() -> new SpearmanCorrelation(p), (i, x, y) -> (cast i : SpearmanCorrelation).update({ x: x, y: y }));
			}
		};
	}
}

@:structInit
class SpearmanPair {
	public var x:Float;
	public var y:Float;
}
