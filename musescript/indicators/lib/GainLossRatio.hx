package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Gain/Loss Ratio: the simple (non-Wilder) rolling ratio of average gain to
 * average loss over a trailing window of `period` bar-over-bar changes —
 * the raw ratio RSI derives its 0-100 scale from, exposed directly.
 *
 * avgGain = mean(positive changes over period)   (0 if none)
 * avgLoss = mean(|negative changes| over period)  (0 if none)
 * GainLossRatio = avgGain / avgLoss
 *
 * Falls back to 0 when there have been no losses in the window (undefined
 * ratio with zero in the denominator).
 */
class GainLossRatio implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:Array<Float>;
	var lastPrice:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "GainLossRatio: period must be > 0";
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
		var change = price - lastPrice;
		lastPrice = price;

		if (window.length == period) window.shift();
		window.push(change);
		if (window.length < period) return null;

		var sumGain = 0.0;
		var sumLoss = 0.0;
		for (c in window) {
			if (c > 0.0) sumGain += c;
			else if (c < 0.0) sumLoss += -c;
		}
		var avgGain = sumGain / period;
		var avgLoss = sumLoss / period;
		if (avgLoss == 0.0) return 0.0;
		return avgGain / avgLoss;
	}

	public function reset():Void {
		window = [];
		lastPrice = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return window.length == period;
	public function name():String return "GainLossRatio";

	public static function spec():IndicatorSpec {
		return {
			name: "gain_loss_ratio", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "gain_loss_ratio:" + series + ":" + p, series, Math.NaN,
					() -> new GainLossRatio(p), (i, v) -> (cast i : GainLossRatio).update(v));
			}
		};
	}
}
