package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Bollinger %b — where price sits within the Bollinger Bands.
 * Ported from wickra-core's `PercentB`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/percent_b.rs).
 *
 * %b = (price − lower) / (upper − lower)
 *
 * `%b = 1` means price is exactly on the upper band, `%b = 0` on the lower
 * band, `%b = 0.5` on the middle band. The value is not clamped: price
 * breaking above the upper band gives `%b > 1`, breaking below the lower band
 * gives `%b < 0`. That makes %b a clean, scale-free way to compare a price's
 * band position across instruments and to spot band overshoots.
 */
class PercentB implements MuseIndicator<Float, Float> {
	var bands:Bollinger;
	var last:Null<Float>;

	public function new(period:Int, multiplier:Float) {
		if (period <= 0) throw "PercentB: period must be > 0";
		if (!Math.isFinite(multiplier) || multiplier <= 0.0) throw "PercentB: multiplier must be positive and finite";
		this.bands = new Bollinger(period, multiplier);
		this.last = null;
	}

	public function update(input:Float):Null<Float> {
		var bandsOut = bands.update(input);
		if (bandsOut == null) return null;

		var width = bandsOut.upper - bandsOut.lower;
		var percent_b = if (width == 0.0) {
			0.5;
		} else {
			(input - bandsOut.lower) / width;
		};
		last = percent_b;
		return percent_b;
	}

	public function reset():Void {
		bands.reset();
		last = null;
	}

	public function warmupPeriod():Int return bands.warmupPeriod();
	public function isReady():Bool return last != null;
	public function name():String return "PercentB";

	public static function spec():IndicatorSpec {
		return {
			name: "percent_b", args: [TSeries, TWindow, TScalar], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				var m = IndicatorCache.floatArg(args, 2, 2.0);
				return IndicatorCache.evalSeries(h, "percent_b:" + series + ":" + p + ":" + m, series, Math.NaN,
					() -> new PercentB(p, m), (i, v) -> (cast i : PercentB).update(v));
			}
		};
	}
}
