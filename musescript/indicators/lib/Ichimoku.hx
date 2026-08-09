package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/** Ichimoku output: the five classic lines (unshifted — see class doc). */
typedef IchimokuOutput = {
	var tenkan:Float;
	var kijun:Float;
	var senkouA:Float;
	var senkouB:Float;
	var chikou:Float;
}

/**
 * Ichimoku Kinko Hyo: five lines built from rolling highest-high/lowest-low
 * midpoints at three different lookback periods.
 *
 * tenkan  = (highestHigh(tenkanPeriod) + lowestLow(tenkanPeriod)) / 2
 * kijun   = (highestHigh(kijunPeriod) + lowestLow(kijunPeriod)) / 2
 * senkouA = (tenkan + kijun) / 2
 * senkouB = (highestHigh(senkouBPeriod) + lowestLow(senkouBPeriod)) / 2
 * chikou  = close
 *
 * Traditional Ichimoku charts plot senkouA/senkouB `kijunPeriod` bars
 * *ahead* and chikou `kijunPeriod` bars *behind*; this streaming port
 * reports all five as of the current bar (unshifted) and leaves any
 * display-time shifting to the charting layer.
 */
class Ichimoku implements MuseIndicator<Bar, IchimokuOutput> {
	var tenkanPeriod:Int;
	var kijunPeriod:Int;
	var senkouBPeriod:Int;
	var highs:RingBuffer<Float>;
	var lows:RingBuffer<Float>;

	public function new(tenkanPeriod:Int, kijunPeriod:Int, senkouBPeriod:Int) {
		if (tenkanPeriod <= 0 || kijunPeriod <= 0 || senkouBPeriod <= 0) throw "Ichimoku: all periods must be > 0";
		this.tenkanPeriod = tenkanPeriod;
		this.kijunPeriod = kijunPeriod;
		this.senkouBPeriod = senkouBPeriod;
		reset();
	}

	public function update(bar:Bar):Null<IchimokuOutput> {
		highs.push(bar.high);
		lows.push(bar.low);

		if (highs.length < senkouBPeriod || highs.length < kijunPeriod) return null;

		var tenkan = midpoint(tenkanPeriod);
		var kijun = midpoint(kijunPeriod);
		var senkouB = midpoint(senkouBPeriod);

		return { tenkan: tenkan, kijun: kijun, senkouA: (tenkan + kijun) / 2.0, senkouB: senkouB, chikou: bar.close };
	}

	function midpoint(period:Int):Float {
		var n = highs.length;
		var start = n - period;
		var hh = highs.oldest(start);
		var ll = lows.oldest(start);
		for (i in start...n) {
			var hv = highs.oldest(i);
			var lv = lows.oldest(i);
			if (hv > hh) hh = hv;
			if (lv < ll) ll = lv;
		}
		return (hh + ll) / 2.0;
	}

	static inline function maxOf(a:Int, b:Int):Int return a > b ? a : b;

	public function reset():Void {
		var maxPeriod = maxOf(tenkanPeriod, maxOf(kijunPeriod, senkouBPeriod));
		highs = new RingBuffer(maxPeriod);
		lows = new RingBuffer(maxPeriod);
	}

	public function warmupPeriod():Int return maxOf(tenkanPeriod, maxOf(kijunPeriod, senkouBPeriod));
	public function isReady():Bool return highs.length >= senkouBPeriod && highs.length >= kijunPeriod;
	public function name():String return "Ichimoku";

	public static function spec():IndicatorSpec {
		return {
			name: "ichimoku", args: [TWindow, TWindow, TWindow], ret: TObject([
				{name: "tenkan", ty: TScalar}, {name: "kijun", ty: TScalar}, {name: "senkouA", ty: TScalar},
				{name: "senkouB", ty: TScalar}, {name: "chikou", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var tenkan = IndicatorCache.intArg(args, 0, 9);
				var kijun = IndicatorCache.intArg(args, 1, 26);
				var senkouB = IndicatorCache.intArg(args, 2, 52);
				var key = "ichimoku:" + tenkan + ":" + kijun + ":" + senkouB;
				var nanFill = { tenkan: Math.NaN, kijun: Math.NaN, senkouA: Math.NaN, senkouB: Math.NaN, chikou: Math.NaN };
				return IndicatorCache.evalBar(h, key, nanFill,
					() -> new Ichimoku(tenkan, kijun, senkouB), (i, b) -> (cast i : Ichimoku).update(b));
			}
		};
	}
}
