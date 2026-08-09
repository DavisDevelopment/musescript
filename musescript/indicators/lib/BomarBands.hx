package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.SortedWindow;
import musescript.types.MuseType;

/** Bomar Bands output: upper/middle/lower bands. */
typedef BomarBandsOutput = {
	var upper:Float;
	var middle:Float;
	var lower:Float;
}

/**
 * Bomar Bands — ported from wickra-core's `BomarBands`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/bomar_bands.rs).
 *
 * Adaptive percentage bands whose width adjusts so that a fixed `coverage`
 * fraction of recent closes falls inside them. Unlike Bollinger Bands, the
 * width is an order statistic of the actual deviations rather than a multiple
 * of the standard deviation.
 *
 * middle = SMA(close, period)
 * dev_i  = |close_i / middle - 1|      // relative distance from midline
 * p      = coverage-quantile of {dev_i}  // type-7 interpolation
 * upper  = middle + |middle| * p
 * lower  = middle - |middle| * p
 *
 * Closes live in a `SortedWindow` (stable multiset). Relative deviations are
 * SMA-dependent — every middle move regenerates all `dev_i` — so they are *not*
 * stored incrementally. Invent: the map `c ↦ |c−μ|/|μ|` folds left-of-μ and
 * right-of-μ into two already-ascending abs-dev streams that merge in O(n) to
 * the same sorted multiset as `scratch.sort`, then type-7 quantile. Never
 * shortcut to `quantile(|c−μ|)*|μ|` (ULP ≠ relative-then-scale).
 */
class BomarBands implements MuseIndicator<Float, BomarBandsOutput> {
	var period:Int;
	var coverage:Float;
	var closes:SortedWindow;
	/** Scratch for fold-merged ascending relative deviations (reused). */
	var scratch:Array<Float>;

	public function new(period:Int, coverage:Float) {
		if (period <= 0) throw "BomarBands: period must be > 0";
		if (!Math.isFinite(coverage) || coverage <= 0.0 || coverage > 1.0) {
			throw "BomarBands: coverage must be a finite value in (0.0, 1.0]";
		}
		this.period = period;
		this.coverage = coverage;
		closes = new SortedWindow(period);
		scratch = [];
	}

	/**
	 * Type-7 interpolation quantile (linear interpolation) of a sorted, non-empty array.
	 * `q` is a percentage in (0, 100] matching the historical Bomar path.
	 */
	function quantileSorted(sorted:Array<Float>, q:Float):Float {
		var lastIndex = sorted.length - 1;
		var rank = (q / 100.0) * lastIndex;
		var floor = Math.floor(rank);
		var lower = Std.int(floor);
		if (lower >= lastIndex) {
			return sorted[lastIndex];
		}
		var frac = rank - floor;
		return sorted[lower] + frac * (sorted[lower + 1] - sorted[lower]);
	}

	/**
	 * Build ascending relative-dev multiset without Array.sort.
	 * Left-of-μ (descending through sorted closes) and right-of-μ (ascending)
	 * each produce increasing `|c−μ|/|μ|`; zeros land first. Merge preserves the
	 * sorted multiset the old push+sort path emitted.
	 */
	function foldRelativeDevs(middle:Float, denom:Float):Void {
		var sorted = closes.sorted;
		var n = sorted.length;
		scratch.resize(0);

		if (denom == 0.0) {
			for (_ in 0...n) scratch.push(0.0);
			return;
		}

		var leftEnd = 0;
		while (leftEnd < n && sorted[leftEnd] < middle) leftEnd++;
		var rightStart = leftEnd;
		while (rightStart < n && sorted[rightStart] == middle) rightStart++;

		for (_ in leftEnd...rightStart) scratch.push(0.0);

		var i = leftEnd - 1;
		var j = rightStart;
		while (i >= 0 || j < n) {
			if (i < 0) {
				scratch.push(Math.abs((sorted[j] - middle) / denom));
				j++;
			} else if (j >= n) {
				scratch.push(Math.abs((sorted[i] - middle) / denom));
				i--;
			} else {
				var dL = Math.abs((sorted[i] - middle) / denom);
				var dR = Math.abs((sorted[j] - middle) / denom);
				if (dL <= dR) {
					scratch.push(dL);
					i--;
				} else {
					scratch.push(dR);
					j++;
				}
			}
		}
	}

	public function update(value:Float):Null<BomarBandsOutput> {
		if (!Math.isFinite(value)) return null;
		closes.push(value);
		if (closes.length < period) return null;

		// Chronological SMA — do not re-sum from `sorted` (order / ULP).
		var sum = 0.0;
		for (i in 0...closes.length) sum += closes.oldest(i);
		var middle = sum / period;
		var denom = Math.abs(middle);

		foldRelativeDevs(middle, denom);
		var p = quantileSorted(scratch, coverage * 100.0);
		var offset = denom * p;

		return {
			upper: middle + offset,
			middle: middle,
			lower: middle - offset
		};
	}

	public function reset():Void {
		closes = new SortedWindow(period);
		scratch = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return closes.length == period;
	public function name():String return "BomarBands";

	public static function spec():IndicatorSpec {
		return {
			name: "bomar_bands", args: [TSeries, TWindow, TScalar], ret: TObject([
				{name: "upper", ty: TScalar}, {name: "middle", ty: TScalar}, {name: "lower", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var period = IndicatorCache.intArg(args, 1, 20);
				var coverage = IndicatorCache.floatArg(args, 2, 0.85);
				var key = "bomar_bands:" + series + ":" + period + ":" + coverage;
				return IndicatorCache.evalSeries(h, key, series, { upper: Math.NaN, middle: Math.NaN, lower: Math.NaN },
					() -> new BomarBands(period, coverage), (i, v) -> (cast i : BomarBands).update(v));
			}
		};
	}
}
