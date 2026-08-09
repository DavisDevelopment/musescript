package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * MidPrice (TA-Lib `MIDPRICE`): the midpoint of the highest high and lowest
 * low over a trailing window of `period` bars — `MidPoint`'s Candle-input
 * counterpart, using the bar's own high/low rather than a single series.
 *
 * MidPrice = ( highestHigh(period) + lowestLow(period) ) / 2
 */
class MidPrice implements MuseIndicator<Bar, Float> {
	var period:Int;
	var highs:RingBuffer<Float>;
	var lows:RingBuffer<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "MidPrice: period must be > 0";
		this.period = period;
		highs = new RingBuffer(period);
		lows = new RingBuffer(period);
	}

	public function update(bar:Bar):Null<Float> {
		highs.push(bar.high);
		lows.push(bar.low);
		if (highs.length < period) return null;

		var hh = highs.oldest(0);
		var ll = lows.oldest(0);
		for (v in highs) if (v > hh) hh = v;
		for (v in lows) if (v < ll) ll = v;
		return (hh + ll) / 2.0;
	}

	public function reset():Void {
		highs = new RingBuffer(period);
		lows = new RingBuffer(period);
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return highs.length == period;
	public function name():String return "MidPrice";

	public static function spec():IndicatorSpec {
		return {
			name: "mid_price", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				return IndicatorCache.evalBar(h, "mid_price:" + p, Math.NaN,
					() -> new MidPrice(p), (i, b) -> (cast i : MidPrice).update(b));
			}
		};
	}
}
