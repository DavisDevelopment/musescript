package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.indicators.prim.Atr;
import musescript.types.MuseType;

/** Chande Kroll Stop output: the long and short trailing-stop lines. */
typedef ChandeKrollStopOutput = {
	var longStop:Float;
	var shortStop:Float;
}

/**
 * Chande Kroll Stop: a two-stage ATR trailing stop. First an ATR-offset
 * high/low is computed over `atrPeriod` bars, then that offset series is
 * itself smoothed by taking its own highest/lowest over `stopPeriod` bars.
 *
 * firstHighStop = highestHigh(atrPeriod) - multiplier * ATR(atrPeriod)
 * firstLowStop  = lowestLow(atrPeriod) + multiplier * ATR(atrPeriod)
 * shortStop     = highest(firstHighStop, stopPeriod)
 * longStop      = lowest(firstLowStop, stopPeriod)
 */
class ChandeKrollStop implements MuseIndicator<Bar, ChandeKrollStopOutput> {
	var atrPeriod:Int;
	var stopPeriod:Int;
	var multiplier:Float;
	var atr:Atr;
	var highs:RingBuffer<Float>;
	var lows:RingBuffer<Float>;
	var firstHighStops:RingBuffer<Float>;
	var firstLowStops:RingBuffer<Float>;

	public function new(atrPeriod:Int, multiplier:Float, stopPeriod:Int) {
		if (!Math.isFinite(multiplier) || multiplier <= 0.0) throw "ChandeKrollStop: multiplier must be positive and finite";
		this.atrPeriod = atrPeriod;
		this.stopPeriod = stopPeriod;
		this.multiplier = multiplier;
		atr = new Atr(atrPeriod);
		reset();
	}

	public function update(bar:Bar):Null<ChandeKrollStopOutput> {
		var atrVal = atr.update(bar);

		highs.push(bar.high);
		lows.push(bar.low);

		if (atrVal == null) return null;

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

		var firstHigh = hh - multiplier * atrVal;
		var firstLow = ll + multiplier * atrVal;

		firstHighStops.push(firstHigh);
		firstLowStops.push(firstLow);
		if (firstHighStops.length < stopPeriod) return null;

		var shortStop = firstHighStops.oldest(0);
		for (i in 1...firstHighStops.length) {
			var v = firstHighStops.oldest(i);
			if (v > shortStop) shortStop = v;
		}
		var longStop = firstLowStops.oldest(0);
		for (i in 1...firstLowStops.length) {
			var v = firstLowStops.oldest(i);
			if (v < longStop) longStop = v;
		}

		return { longStop: longStop, shortStop: shortStop };
	}

	public function reset():Void {
		atr.reset();
		highs = new RingBuffer(atrPeriod);
		lows = new RingBuffer(atrPeriod);
		firstHighStops = new RingBuffer(stopPeriod);
		firstLowStops = new RingBuffer(stopPeriod);
	}

	public function warmupPeriod():Int return atrPeriod + stopPeriod;
	public function isReady():Bool return firstHighStops.length == stopPeriod;
	public function name():String return "ChandeKrollStop";

	public static function spec():IndicatorSpec {
		return {
			name: "chande_kroll_stop", args: [TWindow, TScalar, TWindow], ret: TObject([
				{name: "longStop", ty: TScalar}, {name: "shortStop", ty: TScalar}
			]), minArgs: 3,
			eval: function(h, args) {
				var atrPeriod = IndicatorCache.intArg(args, 0, 10);
				var m = IndicatorCache.floatArg(args, 1, 1.0);
				var stopPeriod = IndicatorCache.intArg(args, 2, 9);
				var key = "chande_kroll_stop:" + atrPeriod + ":" + m + ":" + stopPeriod;
				return IndicatorCache.evalBar(h, key, { longStop: Math.NaN, shortStop: Math.NaN },
					() -> new ChandeKrollStop(atrPeriod, m, stopPeriod), (i, b) -> (cast i : ChandeKrollStop).update(b));
			}
		};
	}
}
