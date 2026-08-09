package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
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
	var gains:RingBuffer<Float>;
	var losses:RingBuffer<Float>;
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

		// Fullness checked before push — `Null<Float>` of `0.0` is nullish on JS.
		var wasFull = gains.isFull();
		var oldGain = gains.push(gain);
		var oldLoss = losses.push(loss);
		if (wasFull) {
			sumGain -= oldGain;
			sumLoss -= oldLoss;
		}
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
		gains = new RingBuffer(period);
		losses = new RingBuffer(period);
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

	/**
	 * Native MuseScript reimplementation, forkable/tunable in-language (see
	 * TaSourceEntry.nativeSource's doc comment). Same recurrence as `update()`
	 * above, translated 1:1: a bounded window of gains/losses fed via a running
	 * sum, first value at `period + 1` bars (one bar to seed `prevPrice`, `period`
	 * more to fill the window). Verified byte-for-byte equal to the Haxe port
	 * over a shared synthetic tape by TestNativeIndicatorParity.
	 *
	 * MuseScript arrays have no RingBuffer — eviction stays index-rebuild so
	 * the native source matches the Haxe ring without an Array head-remove call.
	 */
	public static function nativeSource():String {
		return '@indicator("cmo") function(period) {
	if (state.hasPrev != true) {
		state.hasPrev = true;
		state.prevPrice = close;
		state.gains = [];
		state.losses = [];
		state.sumGain = 0.0;
		state.sumLoss = 0.0;
		return null;
	}
	var change = close - state.prevPrice;
	state.prevPrice = close;
	var gain = change > 0.0 ? change : 0.0;
	var loss = change < 0.0 ? -change : 0.0;

	if (state.gains.length == period) {
		state.sumGain = state.sumGain - state.gains[0];
		state.sumLoss = state.sumLoss - state.losses[0];
		var ng = [];
		var nl = [];
		for (i in 1...state.gains.length) {
			ng.push(state.gains[i]);
			nl.push(state.losses[i]);
		}
		state.gains = ng;
		state.losses = nl;
	}
	state.gains.push(gain);
	state.losses.push(loss);
	state.sumGain = state.sumGain + gain;
	state.sumLoss = state.sumLoss + loss;

	if (state.gains.length < period) return null;
	var denom = state.sumGain + state.sumLoss;
	return denom == 0.0 ? 0.0 : 100.0 * (state.sumGain - state.sumLoss) / denom;
}';
	}
}
