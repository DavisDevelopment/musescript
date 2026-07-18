package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Chande Momentum Oscillator — ported from wickra-core's `Cmo`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/cmo.rs).
 *
 * `CMO = 100 * (sum_gain - sum_loss) / (sum_gain + sum_loss)` over the
 * `period`-bar window of successive price changes; a flat window returns 0.
 * The first bar only seeds the previous price (no change yet), so the first
 * value lands at `period + 1` bars. Series-input (Wickra `type Input = f64`):
 * called `cmo(close, period)`, reading the chosen price series.
 */
class Cmo implements MuseIndicator<Float, Float> {
	var period:Int;
	var hasPrev:Bool;
	var prevPrice:Float;
	var gains:Array<Float>;
	var losses:Array<Float>;
	var sumGain:Float;
	var sumLoss:Float;
	var emitted:Bool;

	public function new(period:Int) {
		if (period <= 0) throw "Cmo: period must be > 0";
		this.period = period;
		reset();
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		if (!hasPrev) {
			prevPrice = price;
			hasPrev = true;
			return null;
		}
		var change = price - prevPrice;
		prevPrice = price;
		var gain = change > 0 ? change : 0.0;
		var loss = change < 0 ? -change : 0.0;

		if (gains.length == period) {
			sumGain -= gains.shift();
			sumLoss -= losses.shift();
		}
		gains.push(gain);
		losses.push(loss);
		sumGain += gain;
		sumLoss += loss;

		if (gains.length < period) return null;
		var denom = sumGain + sumLoss;
		var cmo = denom == 0 ? 0.0 : 100.0 * (sumGain - sumLoss) / denom;
		emitted = true;
		return cmo;
	}

	public function reset():Void {
		hasPrev = false;
		prevPrice = 0.0;
		gains = [];
		losses = [];
		sumGain = 0.0;
		sumLoss = 0.0;
		emitted = false;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return emitted;
	public function name():String return "CMO";

	public static function spec():IndicatorSpec {
		return {
			name: "cmo", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "cmo:" + series + ":" + p, series, Math.NaN,
					() -> new Cmo(p), (i, v) -> (cast i : Cmo).update(v));
			}
		};
	}
}
