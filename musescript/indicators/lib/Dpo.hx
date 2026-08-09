package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/**
 * Detrended Price Oscillator: strips the trend component out of price by
 * comparing an older price to a moving average centered near it, isolating
 * shorter-term cycles.
 *
 * shift = floor(period / 2) + 1
 * DPO_t = price[t - shift] - SMA(price, period)_t
 *
 * Both terms are causal (no lookahead): `price[t - shift]` is a bar strictly
 * in the past, and the SMA is computed from the `period` bars ending at `t`.
 */
class Dpo implements MuseIndicator<Float, Float> {
	var sma:Sma;
	var shift:Int;
	var history:RingBuffer<Float>;

	public function new(period:Int) {
		sma = new Sma(period);
		shift = Std.int(period / 2) + 1;
		history = new RingBuffer(shift + 1);
	}

	public function update(price:Float):Null<Float> {
		var avg = sma.update(price);
		history.push(price);

		if (avg == null || history.length <= shift) return null;
		var past = history.oldest(0);
		return past - avg;
	}

	public function reset():Void {
		sma.reset();
		history = new RingBuffer(shift + 1);
	}

	public function warmupPeriod():Int return sma.period + shift;
	public function isReady():Bool return sma.isReady() && history.length > shift;
	public function name():String return "Dpo";

	public static function spec():IndicatorSpec {
		return {
			name: "dpo", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "dpo:" + series + ":" + p, series, Math.NaN,
					() -> new Dpo(p), (i, v) -> (cast i : Dpo).update(v));
			}
		};
	}
}
