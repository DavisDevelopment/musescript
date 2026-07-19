package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Quartile Bands output: upper (Q3), middle (median), lower (Q1) */
typedef QuartileBandsOutput = {
	var upper:Float;
	var middle:Float;
	var lower:Float;
}

/**
 * Quartile Bands — ported from wickra-core's `QuartileBands`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/quartile_bands.rs).
 *
 * A distribution-based envelope drawn at the rolling quartiles (25th, 50th, 75th percentiles).
 * Non-parametric, robust to outliers.
 */
class QuartileBands implements MuseIndicator<Float, QuartileBandsOutput> {
	var period:Int;
	var window:Array<Float>;
	var scratch:Array<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "QuartileBands: period must be > 0";
		this.period = period;
		this.window = [];
		this.scratch = [];
	}

	/** Linearly-interpolated quantile of a sorted, non-empty slice (type-7). */
	static function quantileSorted(sorted:Array<Float>, quantile:Float):Float {
		var n = sorted.length;
		if (n == 1) return sorted[0];
		var h = (n - 1) * quantile;
		var lower = Math.floor(h);
		var idx = Std.int(lower);
		if (idx >= n - 1) return sorted[n - 1];
		var frac = h - lower;
		return sorted[idx] + frac * (sorted[idx + 1] - sorted[idx]);
	}

	public function update(value:Float):Null<QuartileBandsOutput> {
		if (!Math.isFinite(value)) {
			return null;
		}
		if (window.length == period) {
			window.shift();
		}
		window.push(value);
		if (window.length < period) {
			return null;
		}
		scratch = window.copy();
		scratch.sort((a, b) -> {
			if (a < b) return -1;
			if (a > b) return 1;
			// Handle NaN comparison: NaN is equal to NaN and sorts to the end
			if (Math.isNaN(a) && Math.isNaN(b)) return 0;
			if (Math.isNaN(a)) return 1;
			if (Math.isNaN(b)) return -1;
			return 0;
		});
		return {
			upper: quantileSorted(scratch, 0.75),
			middle: quantileSorted(scratch, 0.5),
			lower: quantileSorted(scratch, 0.25)
		};
	}

	public function reset():Void {
		window = [];
		scratch = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "QuartileBands";

	public static function spec():IndicatorSpec {
		return {
			name: "quartile_bands", args: [TWindow], ret: TObject([
				{name: "upper", ty: TScalar}, {name: "middle", ty: TScalar}, {name: "lower", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				var nanFill:QuartileBandsOutput = {upper: Math.NaN, middle: Math.NaN, lower: Math.NaN};
				return IndicatorCache.evalSeries(h, "quartile_bands:" + p, "close", nanFill,
					() -> new QuartileBands(p), (i, v) -> (cast i : QuartileBands).update(v));
			}
		};
	}
}
