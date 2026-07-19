package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Omega Ratio: the ratio of cumulative gains above a threshold return to
 * cumulative losses below it, over a trailing window of `period`
 * bar-over-bar returns — a probability-weighted alternative to Sharpe that
 * doesn't assume a normal return distribution.
 *
 * gains  = sum( max(return - threshold, 0), period )
 * losses = sum( max(threshold - return, 0), period )
 * Omega  = gains / losses
 *
 * Falls back to 0 when there are no sub-threshold returns in the window
 * (undefined ratio with zero in the denominator).
 */
class OmegaRatio implements MuseIndicator<Float, Float> {
	var period:Int;
	var threshold:Float;
	var window:Array<Float>;
	var lastPrice:Null<Float>;

	public function new(period:Int, threshold:Float = 0.0) {
		if (period <= 0) throw "OmegaRatio: period must be > 0";
		this.period = period;
		this.threshold = threshold;
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

		var gains = 0.0;
		var losses = 0.0;
		for (r in window) {
			if (r > threshold) gains += r - threshold;
			else losses += threshold - r;
		}
		if (losses == 0.0) return 0.0;
		return gains / losses;
	}

	public function reset():Void {
		window = [];
		lastPrice = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return window.length == period;
	public function name():String return "OmegaRatio";

	public static function spec():IndicatorSpec {
		return {
			name: "omega_ratio", args: [TSeries, TWindow, TScalar], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 30);
				var threshold = IndicatorCache.floatArg(args, 2, 0.0);
				var key = "omega_ratio:" + series + ":" + p + ":" + threshold;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new OmegaRatio(p, threshold), (i, v) -> (cast i : OmegaRatio).update(v));
			}
		};
	}
}
