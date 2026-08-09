package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/** Donchian Stop output: the long and short trailing-stop levels. */
typedef DonchianStopOutput = {
	var longStop:Float;
	var shortStop:Float;
}

/**
 * Donchian Stop: a trailing stop pair anchored to the highest high / lowest
 * low of the `period` bars *strictly before* the current one (a one-bar-lag
 * variant of `Donchian` suited to stop-placement, where the current bar's
 * own extreme should never determine its own stop).
 *
 * longStop  = lowestLow(previous `period` bars)
 * shortStop = highestHigh(previous `period` bars)
 */
class DonchianStop implements MuseIndicator<Bar, DonchianStopOutput> {
	var period:Int;
	var highs:RingBuffer<Float>;
	var lows:RingBuffer<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "DonchianStop: period must be > 0";
		this.period = period;
		reset();
	}

	public function update(bar:Bar):Null<DonchianStopOutput> {
		var out:Null<DonchianStopOutput> = if (highs.length < period) null else {
			var hh = highs.oldest(0);
			for (i in 1...highs.length) {
				var v = highs.oldest(i);
				if (v > hh) hh = v;
			}
			var ll = lows.oldest(0);
			for (i in 1...lows.length) {
				var v = lows.oldest(i);
				if (v < ll) ll = v;
			}
			{ longStop: ll, shortStop: hh };
		}

		highs.push(bar.high);
		lows.push(bar.low);

		return out;
	}

	public function reset():Void {
		highs = new RingBuffer(period);
		lows = new RingBuffer(period);
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return highs.length == period;
	public function name():String return "DonchianStop";

	public static function spec():IndicatorSpec {
		return {
			name: "donchian_stop", args: [TWindow], ret: TObject([
				{name: "longStop", ty: TScalar}, {name: "shortStop", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				return IndicatorCache.evalBar(h, "donchian_stop:" + p, { longStop: Math.NaN, shortStop: Math.NaN },
					() -> new DonchianStop(p), (i, b) -> (cast i : DonchianStop).update(b));
			}
		};
	}
}
