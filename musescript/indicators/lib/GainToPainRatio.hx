package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Gain to Pain Ratio (Schwager): the sum of all bar-over-bar returns over a
 * trailing window of `period` bars, divided by the sum of the magnitude of
 * only the negative ("painful") ones.
 *
 * GPR = sum(returns) / sum(|negative returns|)
 *
 * A value of 2 means the strategy/asset earned twice as much as the total
 * pain endured to get there. Falls back to 0 when there has been no pain in
 * the window (undefined ratio with zero in the denominator).
 */
class GainToPainRatio implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:Array<Float>;
	var lastPrice:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "GainToPainRatio: period must be > 0";
		this.period = period;
		window = [];
		lastPrice = null;
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		if (lastPrice == null) {
			lastPrice = price;
			return null;
		}
		var ret = lastPrice != 0.0 ? (price - lastPrice) / lastPrice : 0.0;
		lastPrice = price;

		if (window.length == period) window.shift();
		window.push(ret);
		if (window.length < period) return null;

		var sumReturn = 0.0;
		var sumPain = 0.0;
		for (r in window) {
			sumReturn += r;
			if (r < 0.0) sumPain += -r;
		}
		if (sumPain == 0.0) return 0.0;
		return sumReturn / sumPain;
	}

	public function reset():Void {
		window = [];
		lastPrice = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return window.length == period;
	public function name():String return "GainToPainRatio";

	public static function spec():IndicatorSpec {
		return {
			name: "gain_to_pain_ratio", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 30);
				return IndicatorCache.evalSeries(h, "gain_to_pain_ratio:" + series + ":" + p, series, Math.NaN,
					() -> new GainToPainRatio(p), (i, v) -> (cast i : GainToPainRatio).update(v));
			}
		};
	}
}
