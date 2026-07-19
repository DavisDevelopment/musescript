package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Adaptive RSI — ported from wickra-core's `AdaptiveRsi`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/adaptive_rsi.rs).
 *
 * Wilder's RSI in which the smoothing of the average gain and average loss
 * **adapts to trendiness** via Kaufman's efficiency ratio. Output is bounded
 * in `[0, 100]`; a flat market returns the neutral `50`. The first value lands
 * after `period + 1` inputs.
 *
 * Series input (f64): called `adaptive_rsi(close, period)`.
 */
class AdaptiveRsi implements MuseIndicator<Float, Float> {
	var period:Int;
	var prices:Array<Float>;
	var absChanges:Array<Float>;
	var absSum:Float;
	var prev:Null<Float>;
	var seedGain:Float;
	var seedLoss:Float;
	var seedCount:Int;
	var avgGain:Null<Float>;
	var avgLoss:Null<Float>;
	var last:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "AdaptiveRsi: period must be > 0";
		this.period = period;
		reset();
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return last;

		if (prev == null) {
			prev = price;
			prices.push(price);
			return null;
		}

		var change = price - prev;
		prev = price;
		var gain = change > 0 ? change : 0.0;
		var loss = change < 0 ? -change : 0.0;

		// Maintain the price window (period + 1) and the |Δ| window (period).
		prices.push(price);
		if (prices.length > period + 1) {
			prices.shift();
		}
		if (absChanges.length == period) {
			absSum -= absChanges.shift();
		}
		absChanges.push(Math.abs(change));
		absSum += Math.abs(change);

		if (avgGain != null && avgLoss != null) {
			var er = efficiencyRatio(price);
			var fast = 2.0 / 3.0;
			var slow = 2.0 / 31.0;
			var sc = Math.pow(er * (fast - slow) + slow, 2);
			var newAg = avgGain + sc * (gain - avgGain);
			var newAl = avgLoss + sc * (loss - avgLoss);
			avgGain = newAg;
			avgLoss = newAl;
			var v = rsiFromAvgs(newAg, newAl);
			last = v;
			return v;
		}

		seedGain += gain;
		seedLoss += loss;
		seedCount++;
		if (seedCount == period) {
			var ag = seedGain / period;
			var al = seedLoss / period;
			avgGain = ag;
			avgLoss = al;
			var v = rsiFromAvgs(ag, al);
			last = v;
			return v;
		}
		return null;
	}

	public function reset():Void {
		prices = [];
		absChanges = [];
		absSum = 0.0;
		prev = null;
		seedGain = 0.0;
		seedLoss = 0.0;
		seedCount = 0;
		avgGain = null;
		avgLoss = null;
		last = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return last != null;
	public function name():String return "AdaptiveRsi";

	function efficiencyRatio(price:Float):Float {
		var oldest = prices[0];
		var direction = Math.abs(price - oldest);
		if (absSum == 0.0) return 0.0;
		var er = direction / absSum;
		return Math.max(0.0, Math.min(1.0, er));
	}

	static inline function rsiFromAvgs(ag:Float, al:Float):Float {
		var denom = ag + al;
		return denom == 0 ? 50.0 : 100.0 * ag / denom;
	}

	public static function spec():IndicatorSpec {
		return {
			name: "adaptive_rsi", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "adaptive_rsi:" + series + ":" + p, series, Math.NaN,
					() -> new AdaptiveRsi(p), (i, v) -> (cast i : AdaptiveRsi).update(v));
			}
		};
	}
}
