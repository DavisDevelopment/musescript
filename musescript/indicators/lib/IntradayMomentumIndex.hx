package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Intraday Momentum Index: RSI's gain/loss ratio formula applied to each
 * bar's *intraday* move (close vs. its own open) instead of close-to-close
 * changes.
 *
 * gain_t = close_t - open_t   if close_t > open_t, else 0
 * loss_t = open_t - close_t   if close_t < open_t, else 0
 * IMI    = sum(gain, period) / (sum(gain, period) + sum(loss, period)) * 100
 *
 * Falls back to the neutral 50 when the window has no intraday movement at
 * all (both sums zero).
 */
class IntradayMomentumIndex implements MuseIndicator<Bar, Float> {
	var period:Int;
	var gains:Array<Float>;
	var losses:Array<Float>;
	var sumGain:Float;
	var sumLoss:Float;

	public function new(period:Int) {
		if (period <= 0) throw "IntradayMomentumIndex: period must be > 0";
		this.period = period;
		gains = [];
		losses = [];
		sumGain = 0.0;
		sumLoss = 0.0;
	}

	public function update(bar:Bar):Null<Float> {
		var gain = bar.close > bar.open ? bar.close - bar.open : 0.0;
		var loss = bar.close < bar.open ? bar.open - bar.close : 0.0;

		if (gains.length == period) sumGain -= gains.shift();
		gains.push(gain);
		sumGain += gain;
		if (losses.length == period) sumLoss -= losses.shift();
		losses.push(loss);
		sumLoss += loss;

		if (gains.length < period) return null;
		var denom = sumGain + sumLoss;
		if (denom == 0.0) return 50.0;
		return sumGain / denom * 100.0;
	}

	public function reset():Void {
		gains = [];
		losses = [];
		sumGain = 0.0;
		sumLoss = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return gains.length == period;
	public function name():String return "IntradayMomentumIndex";

	public static function spec():IndicatorSpec {
		return {
			name: "intraday_momentum_index", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				return IndicatorCache.evalBar(h, "intraday_momentum_index:" + p, Math.NaN,
					() -> new IntradayMomentumIndex(p), (i, b) -> (cast i : IntradayMomentumIndex).update(b));
			}
		};
	}
}
