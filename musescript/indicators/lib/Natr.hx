package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Atr;
import musescript.types.MuseType;

/**
 * Normalized ATR (TA-Lib `NATR`): Average True Range expressed as a
 * percentage of the current close, making volatility comparable across
 * instruments with very different price levels (raw `Atr` is not, since a
 * $500 stock's ATR dwarfs a $5 stock's in absolute terms even at identical
 * relative volatility).
 *
 * NATR = ATR(period) / close * 100
 */
class Natr implements MuseIndicator<Bar, Float> {
	var atr:Atr;

	public function new(period:Int) {
		atr = new Atr(period);
	}

	public function update(bar:Bar):Null<Float> {
		var atrVal = atr.update(bar);
		if (atrVal == null) return null;
		if (bar.close == 0.0) return 0.0;
		return atrVal / bar.close * 100.0;
	}

	public function reset():Void {
		atr.reset();
	}

	public function warmupPeriod():Int return atr.period;
	public function isReady():Bool return atr.isReady();
	public function name():String return "Natr";

	public static function spec():IndicatorSpec {
		return {
			name: "natr", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				return IndicatorCache.evalBar(h, "natr:" + p, Math.NaN,
					() -> new Natr(p), (i, b) -> (cast i : Natr).update(b));
			}
		};
	}
}
