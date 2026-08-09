package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Choppiness Index: how "choppy" (range-bound) vs. "trending" the market has
 * been over the trailing `period` bars, on a 0-100 scale.
 *
 * CHOP = 100 * log10( sum(trueRange, period) / (highestHigh(period) - lowestLow(period)) ) / log10(period)
 *
 * Near 100 means price has covered a lot of true-range ground without net
 * progress (choppy/range-bound); near 0 means the bulk of that range was
 * covered in a single direction (trending).
 */
class ChoppinessIndex implements MuseIndicator<Bar, Float> {
	var period:Int;
	var log10Period:Float;
	var trWindow:RingBuffer<Float>;
	var highs:RingBuffer<Float>;
	var lows:RingBuffer<Float>;
	var sumTr:Float;
	var hasPrevClose:Bool;
	var prevClose:Float;

	public function new(period:Int) {
		if (period < 2) throw "ChoppinessIndex: period must be >= 2";
		this.period = period;
		log10Period = Math.log(period) / Math.log(10.0);
		reset();
	}

	public function update(bar:Bar):Null<Float> {
		var hl = bar.high - bar.low;
		var tr = hl;
		if (hasPrevClose) {
			tr = Math.max(hl, Math.max(Math.abs(bar.high - prevClose), Math.abs(bar.low - prevClose)));
		}
		prevClose = bar.close;
		hasPrevClose = true;

		// Fullness checked before push — `Null<Float>` of `0.0` is nullish on JS.
		var wasFull = trWindow.isFull();
		var oldTr = trWindow.push(tr);
		if (wasFull) sumTr -= oldTr;
		sumTr += tr;

		highs.push(bar.high);
		lows.push(bar.low);

		if (trWindow.length < period) return null;

		var hh = highs.at(0);
		for (i in 0...highs.length) {
			var v = highs.at(i);
			if (v > hh) hh = v;
		}
		var ll = lows.at(0);
		for (i in 0...lows.length) {
			var v = lows.at(i);
			if (v < ll) ll = v;
		}

		var range = hh - ll;
		if (range <= 0.0) return 0.0;
		return 100.0 * (Math.log(sumTr / range) / Math.log(10.0)) / log10Period;
	}

	public function reset():Void {
		trWindow = new RingBuffer(period);
		highs = new RingBuffer(period);
		lows = new RingBuffer(period);
		sumTr = 0.0;
		hasPrevClose = false;
		prevClose = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return trWindow.length == period;
	public function name():String return "ChoppinessIndex";

	public static function spec():IndicatorSpec {
		return {
			name: "choppiness_index", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				return IndicatorCache.evalBar(h, "choppiness_index:" + p, Math.NaN,
					() -> new ChoppinessIndex(p), (i, b) -> (cast i : ChoppinessIndex).update(b));
			}
		};
	}
}
