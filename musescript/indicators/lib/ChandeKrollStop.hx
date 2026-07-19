package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
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
	var highs:Array<Float>;
	var lows:Array<Float>;
	var firstHighStops:Array<Float>;
	var firstLowStops:Array<Float>;

	public function new(atrPeriod:Int, multiplier:Float, stopPeriod:Int) {
		if (!Math.isFinite(multiplier) || multiplier <= 0.0) throw "ChandeKrollStop: multiplier must be positive and finite";
		this.atrPeriod = atrPeriod;
		this.stopPeriod = stopPeriod;
		this.multiplier = multiplier;
		atr = new Atr(atrPeriod);
		highs = [];
		lows = [];
		firstHighStops = [];
		firstLowStops = [];
	}

	public function update(bar:Bar):Null<ChandeKrollStopOutput> {
		var atrVal = atr.update(bar);

		if (highs.length == atrPeriod) highs.shift();
		highs.push(bar.high);
		if (lows.length == atrPeriod) lows.shift();
		lows.push(bar.low);

		if (atrVal == null) return null;

		var hh = highs[0];
		for (v in highs) if (v > hh) hh = v;
		var ll = lows[0];
		for (v in lows) if (v < ll) ll = v;

		var firstHigh = hh - multiplier * atrVal;
		var firstLow = ll + multiplier * atrVal;

		if (firstHighStops.length == stopPeriod) firstHighStops.shift();
		firstHighStops.push(firstHigh);
		if (firstLowStops.length == stopPeriod) firstLowStops.shift();
		firstLowStops.push(firstLow);
		if (firstHighStops.length < stopPeriod) return null;

		var shortStop = firstHighStops[0];
		for (v in firstHighStops) if (v > shortStop) shortStop = v;
		var longStop = firstLowStops[0];
		for (v in firstLowStops) if (v < longStop) longStop = v;

		return { longStop: longStop, shortStop: shortStop };
	}

	public function reset():Void {
		atr.reset();
		highs = [];
		lows = [];
		firstHighStops = [];
		firstLowStops = [];
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
