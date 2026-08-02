package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.RingBuffer;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Trend Label — ported from wickra-core's `TrendLabel`
 * (vendor/wickra/crates/wickra-core/src/indicators/trend_label.rs).
 *
 * A discrete `{−1, 0, +1}` classification of the local trend from the sign
 * of the ordinary-least-squares slope over the last `period` values:
 *
 * slope = Σ (tᵢ − t̄)(xᵢ − x̄) / Σ (tᵢ − t̄)²
 * label = +1 if slope > 0, −1 if slope < 0, 0 if slope == 0
 *
 * Scale-invariant: the slope sign does not depend on the nominal price
 * level. The denominator is strictly positive for `period ≥ 2`, so the sign
 * is always well-defined.
 */
class TrendLabel implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;

	public function new(period:Int) {
		if (period < 2) throw "TrendLabel: trend label needs period >= 2";
		this.period = period;
		reset();
	}

	public function update(value:Float):Null<Float> {
		if (!Math.isFinite(value)) return null;
		window.push(value);
		if (window.length < period) return null;
		var count = period;
		var meanT = (count - 1) / 2.0;
		var sumX = 0.0;
		for (x in window) sumX += x;
		var meanX = sumX / count;
		// Slope numerator: Σ (t − t̄)(x − x̄); denominator > 0 for period >= 2,
		// so the slope sign equals the numerator sign.
		var numerator = 0.0;
		for (t in 0...window.length) {
			numerator += (t - meanT) * (window.oldest(t) - meanX);
		}
		return numerator > 0.0 ? 1.0 : (numerator < 0.0 ? -1.0 : 0.0);
	}

	public function reset():Void {
		window = new RingBuffer(period);
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "TrendLabel";

	public static function spec():IndicatorSpec {
		return {
			name: "trend_label", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 10);
				return IndicatorCache.evalSeries(h, "trend_label:" + series + ":" + p, series, Math.NaN,
					() -> new TrendLabel(p), (i, v) -> (cast i : TrendLabel).update(v));
			}
		};
	}
}
