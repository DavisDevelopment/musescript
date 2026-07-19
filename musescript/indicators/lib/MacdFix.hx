package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.lib.MacdExt.MacdExtOutput;
import musescript.types.MuseType;

/**
 * MACD Fix: the classic MACD with fast/slow periods pinned to their
 * original Gerald Appel values (12, 26) — only the signal period is
 * configurable, matching TA-Lib's `MACDFIX`. See `MacdExt` for the fully
 * configurable variant.
 */
class MacdFix implements MuseIndicator<Float, MacdExtOutput> {
	var inner:MacdExt;

	public function new(signalPeriod:Int) {
		inner = new MacdExt(12, 26, signalPeriod);
	}

	public function update(price:Float):Null<MacdExtOutput> return inner.update(price);
	public function reset():Void inner.reset();
	public function warmupPeriod():Int return inner.warmupPeriod();
	public function isReady():Bool return inner.isReady();
	public function name():String return "MacdFix";

	public static function spec():IndicatorSpec {
		return {
			name: "macd_fix", args: [TSeries, TWindow], ret: TObject([
				{name: "macd", ty: TScalar}, {name: "signal", ty: TScalar}, {name: "histogram", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var signalPeriod = IndicatorCache.intArg(args, 1, 9);
				var key = "macd_fix:" + series + ":" + signalPeriod;
				var nanFill = { macd: Math.NaN, signal: Math.NaN, histogram: Math.NaN };
				return IndicatorCache.evalSeries(h, key, series, nanFill,
					() -> new MacdFix(signalPeriod), (i, v) -> (cast i : MacdFix).update(v));
			}
		};
	}
}
