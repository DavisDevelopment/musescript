package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
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
 */
class SpearmanCorrelation implements MuseIndicator<SpearmanPair, Float> {
	var period:Int;
	var window:Array<SpearmanPair>;
	var rx:Array<Float>;
	var ry:Array<Float>;

	public function new(period:Int) {
		if (period < 2) throw "SpearmanCorrelation: period must be >= 2";
		this.period = period;
		window = [];
		rx = [for (_ in 0...period) 0.0];
		ry = [for (_ in 0...period) 0.0];
	}

	/**
	 * Fill `ranksOut[originalIndex] = rank` for the supplied values, using
	 * mid-ranks for ties.
	 */
	static function rankInto(values:Array<Float>, ranksOut:Array<Float>):Void {
		var scratch = [for (i in 0...values.length) { v: values[i], idx: i }];
		scratch.sort((a, b) -> a.v < b.v ? -1 : (a.v > b.v ? 1 : 0));
		var n = scratch.length;
		var i = 0;
		while (i < n) {
			var j = i + 1;
			while (j < n && scratch[j].v == scratch[i].v) j++;
			// Mid-rank of positions [i, j−1] in 1-indexed terms: (i + 1 + j) / 2.
			var mid = (i + 1.0 + j) / 2.0;
			for (k in i...j) ranksOut[scratch[k].idx] = mid;
			i = j;
		}
	}

	public function update(input:SpearmanPair):Null<Float> {
		if (!Math.isFinite(input.x) || !Math.isFinite(input.y)) return null;
		if (window.length == period) window.shift();
		window.push({ x: input.x, y: input.y });
		if (window.length < period) return null;
		// Rank each channel.
		rankInto([for (p in window) p.x], rx);
		rankInto([for (p in window) p.y], ry);
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
		window = [];
		rx = [for (_ in 0...period) 0.0];
		ry = [for (_ in 0...period) 0.0];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
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
