package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Vertical Horizontal Filter — ported from wickra-core's
 * `VerticalHorizontalFilter`
 * (vendor/wickra/crates/wickra-core/src/indicators/vertical_horizontal_filter.rs).
 *
 * Adam White's trend-versus-range gauge:
 *
 *   VHF = (highest_close(n) − lowest_close(n)) / Σ|close − close_prev|(n)
 *
 * Net distance covered over the window vs. total distance walked; lives in
 * [0, 1] — near 1 in a clean trend, near 0 in chop. A non-finite input is
 * rejected (returns null, state untouched). A flat window yields 0. First
 * value after `period + 1` inputs.
 */
class VerticalHorizontalFilter implements MuseIndicator<Float, Float> {
	var period:Int;
	var closes:RingBuffer<Float>;
	var prevClose:Null<Float>;
	var diffs:RingBuffer<Float>;
	var diffSum:Float;

	public function new(period:Int) {
		if (period <= 0) throw "VerticalHorizontalFilter: period must be > 0";
		this.period = period;
		reset();
	}

	public function update(value:Float):Null<Float> {
		if (!Math.isFinite(value)) return null;
		closes.push(value);

		if (prevClose != null) {
			var diff = Math.abs(value - prevClose);
			var wasFull = diffs.isFull();
			var old = diffs.push(diff);
			if (wasFull) diffSum -= old;
			diffSum += diff;
		}
		prevClose = value;

		if (closes.length < period || diffs.length < period) return null;
		var highest = Math.NEGATIVE_INFINITY;
		var lowest = Math.POSITIVE_INFINITY;
		for (c in closes) {
			if (c > highest) highest = c;
			if (c < lowest) lowest = c;
		}
		if (diffSum == 0.0) {
			// A flat window walked nowhere — no trend to filter.
			return 0.0;
		}
		return (highest - lowest) / diffSum;
	}

	public function reset():Void {
		closes = new RingBuffer(period);
		prevClose = null;
		diffs = new RingBuffer(period);
		diffSum = 0.0;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return diffs.length == period;
	public function name():String return "VerticalHorizontalFilter";

	public static function spec():IndicatorSpec {
		return {
			name: "vertical_horizontal_filter", args: [TSeries, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 28);
				var key = "vertical_horizontal_filter:" + series + ":" + p;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new VerticalHorizontalFilter(p), (i, v) -> (cast i : VerticalHorizontalFilter).update(v));
			}
		};
	}
}
