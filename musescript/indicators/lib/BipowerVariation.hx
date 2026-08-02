package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.RingBuffer;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Realized Bipower Variation (Barndorff-Nielsen & Shephard) — a jump-robust
 * estimator of realized variance over a rolling window of `period` log-returns.
 *
 * BV = (pi/2) * sum_{i=2}^{n} |r_i| * |r_{i-1}|
 *
 * Unlike realized variance (sum of squared returns), bipower variation
 * downweights isolated single-bar jumps: a jump return only ever pairs with
 * one adjacent (typically small, continuous) return rather than contributing
 * a squared term on its own.
 */
class BipowerVariation implements MuseIndicator<Float, Float> {
	static var HALF_PI:Float = Math.PI / 2.0;

	var period:Int;
	var lastPrice:Null<Float>;
	var returns:RingBuffer<Float>;

	public function new(period:Int) {
		if (period < 2) throw "BipowerVariation: period must be >= 2";
		this.period = period;
		reset();
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price) || price <= 0.0) return null;
		if (lastPrice == null) {
			lastPrice = price;
			return null;
		}
		var r = Math.log(price / lastPrice);
		lastPrice = price;

		returns.push(r);

		if (returns.length < period) return null;

		var sum = 0.0;
		for (i in 1...returns.length) sum += Math.abs(returns.oldest(i)) * Math.abs(returns.oldest(i - 1));
		return HALF_PI * sum;
	}

	public function reset():Void {
		lastPrice = null;
		returns = new RingBuffer(period);
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return returns.length == period;
	public function name():String return "BipowerVariation";

	public static function spec():IndicatorSpec {
		return {
			name: "bipower_variation", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "bipower_variation:" + series + ":" + p, series, Math.NaN,
					() -> new BipowerVariation(p), (i, v) -> (cast i : BipowerVariation).update(v));
			}
		};
	}
}
