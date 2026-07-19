package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Ehlers' Adaptive Laguerre Filter — ported from wickra-core's `AdaptiveLaguerreFilter`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/adaptive_laguerre_filter.rs).
 *
 * A four-stage Laguerre polynomial smoother whose damping factor `gamma` is
 * recomputed every bar from how well the filter is currently tracking price.
 * The Laguerre cascade adapts: it measures the recent absolute error,
 * normalises those errors across a window of `period` bars to `[0, 1]`, and
 * takes their **median** as `gamma`. When price is tracking smoothly the errors
 * are small (low `gamma`, fast response); when price jumps, the errors widen
 * and `gamma` rises, slowing the filter to reject noise.
 *
 * Series input (f64): called `adaptive_laguerre_filter(close, period)`.
 */
class AdaptiveLaguerreFilter implements MuseIndicator<Float, Float> {
	var period:Int;
	var l0:Float;
	var l1:Float;
	var l2:Float;
	var l3:Float;
	var filter:Null<Float>;
	var diffs:Array<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "AdaptiveLaguerreFilter: period must be > 0";
		this.period = period;
		reset();
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return value();

		// Absolute tracking error against the previous filter (0 on the first bar).
		var diff = filter != null ? Math.abs(price - filter) : 0.0;
		if (diffs.length == period) {
			diffs.shift();
		}
		diffs.push(diff);

		var gamma = adaptiveGamma();
		var alpha = 1.0 - gamma;

		var newL0 = alpha * price + gamma * l0;
		var newL1 = -gamma * newL0 + l0 + gamma * l1;
		var newL2 = -gamma * newL1 + l1 + gamma * l2;
		var newL3 = -gamma * newL2 + l2 + gamma * l3;
		l0 = newL0;
		l1 = newL1;
		l2 = newL2;
		l3 = newL3;

		var newFilter = (l0 + 2.0 * l1 + 2.0 * l2 + l3) / 6.0;
		filter = newFilter;
		return value();
	}

	public function reset():Void {
		l0 = 0.0;
		l1 = 0.0;
		l2 = 0.0;
		l3 = 0.0;
		filter = null;
		diffs = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return diffs.length == period;
	public function name():String return "AdaptiveLaguerre";

	/** Latest filter value; the Laguerre cascade is recursive and emits from the first bar. */
	public function value():Null<Float> return filter;

	function adaptiveGamma():Float {
		var hh = Math.NEGATIVE_INFINITY;
		var ll = Math.POSITIVE_INFINITY;
		for (d in diffs) {
			if (d > hh) hh = d;
			if (d < ll) ll = d;
		}
		var range = hh - ll;
		if (range <= 0.0) return 0.0;

		var norm:Array<Float> = [];
		for (d in diffs) {
			norm.push((d - ll) / range);
		}
		norm.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		var mid = Math.floor(norm.length / 2);
		if (norm.length % 2 == 1) {
			return norm[mid];
		} else {
			return (norm[mid - 1] + norm[mid]) / 2.0;
		}
	}

	public static function spec():IndicatorSpec {
		return {
			name: "adaptive_laguerre_filter", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 13);
				return IndicatorCache.evalSeries(h, "adaptive_laguerre_filter:" + series + ":" + p, series, Math.NaN,
					() -> new AdaptiveLaguerreFilter(p), (i, v) -> (cast i : AdaptiveLaguerreFilter).update(v));
			}
		};
	}
}
