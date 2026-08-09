package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.indicators.prim.Wma;
import musescript.types.MuseType;

/**
 * Coppock Curve: a long-term momentum oscillator built from a WMA-smoothed
 * sum of two rate-of-change lookbacks.
 *
 * ROC_n(price) = (price - price[n bars ago]) / price[n bars ago] * 100
 * Coppock = WMA(ROC_longRoc(price) + ROC_shortRoc(price), wmaPeriod)
 *
 * Classic parameters: longRoc=14, shortRoc=11, wmaPeriod=10.
 */
class Coppock implements MuseIndicator<Float, Float> {
	var longRoc:Int;
	var shortRoc:Int;
	var history:RingBuffer<Float>;
	var wma:Wma;

	public function new(longRoc:Int, shortRoc:Int, wmaPeriod:Int) {
		if (longRoc <= 0 || shortRoc <= 0) throw "Coppock: ROC lookbacks must be > 0";
		this.longRoc = longRoc;
		this.shortRoc = shortRoc;
		var maxLookback = longRoc > shortRoc ? longRoc : shortRoc;
		history = new RingBuffer(maxLookback + 1);
		wma = new Wma(wmaPeriod);
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		history.push(price);

		if (history.length <= longRoc || history.length <= shortRoc) return null;

		var longPast = history.at(longRoc);
		var shortPast = history.at(shortRoc);
		var cur = history.at(0);
		if (longPast == 0.0 || shortPast == 0.0) return null;

		var rocSum = (cur - longPast) / longPast * 100.0 + (cur - shortPast) / shortPast * 100.0;
		return wma.update(rocSum);
	}

	public function reset():Void {
		var maxLookback = longRoc > shortRoc ? longRoc : shortRoc;
		history = new RingBuffer(maxLookback + 1);
		wma.reset();
	}

	public function warmupPeriod():Int {
		var maxRoc = longRoc > shortRoc ? longRoc : shortRoc;
		return maxRoc + wma.period;
	}
	public function isReady():Bool return wma.isReady();
	public function name():String return "Coppock";

	public static function spec():IndicatorSpec {
		return {
			name: "coppock", args: [TSeries, TWindow, TWindow, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var longRoc = IndicatorCache.intArg(args, 1, 14);
				var shortRoc = IndicatorCache.intArg(args, 2, 11);
				var wmaPeriod = IndicatorCache.intArg(args, 3, 10);
				var key = "coppock:" + series + ":" + longRoc + ":" + shortRoc + ":" + wmaPeriod;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new Coppock(longRoc, shortRoc, wmaPeriod), (i, v) -> (cast i : Coppock).update(v));
			}
		};
	}
}
