package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.indicators.prim.Atr;
import musescript.types.MuseType;

/** Keltner Channel output: upper/middle/lower bands. */
typedef KeltnerOutput = {
	var upper:Float;
	var middle:Float;
	var lower:Float;
}

/**
 * Keltner Channel: an EMA centerline with ATR-scaled bands — the
 * volatility-adaptive cousin of Bollinger Bands (which use stddev instead
 * of ATR).
 *
 * middle = EMA(close, emaPeriod)
 * upper  = middle + multiplier * ATR(atrPeriod)
 * lower  = middle - multiplier * ATR(atrPeriod)
 */
class Keltner implements MuseIndicator<Bar, KeltnerOutput> {
	var ema:Ema;
	var atr:Atr;
	var multiplier:Float;

	public function new(emaPeriod:Int, atrPeriod:Int, multiplier:Float) {
		if (!Math.isFinite(multiplier) || multiplier <= 0.0) throw "Keltner: multiplier must be positive and finite";
		ema = new Ema(emaPeriod);
		atr = new Atr(atrPeriod);
		this.multiplier = multiplier;
	}

	public function update(bar:Bar):Null<KeltnerOutput> {
		var mid = ema.update(bar.close);
		var atrVal = atr.update(bar);
		if (mid == null || atrVal == null) return null;
		return { upper: mid + multiplier * atrVal, middle: mid, lower: mid - multiplier * atrVal };
	}

	public function reset():Void {
		ema.reset();
		atr.reset();
	}

	public function warmupPeriod():Int return Std.int(Math.max(ema.period, atr.period));
	public function isReady():Bool return ema.isReady() && atr.isReady();
	public function name():String return "Keltner";

	public static function spec():IndicatorSpec {
		return {
			name: "keltner", args: [TWindow, TWindow, TScalar], ret: TObject([
				{name: "upper", ty: TScalar}, {name: "middle", ty: TScalar}, {name: "lower", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var emaPeriod = IndicatorCache.intArg(args, 0, 20);
				var atrPeriod = IndicatorCache.intArg(args, 1, 10);
				var m = IndicatorCache.floatArg(args, 2, 2.0);
				var key = "keltner:" + emaPeriod + ":" + atrPeriod + ":" + m;
				return IndicatorCache.evalBar(h, key, { upper: Math.NaN, middle: Math.NaN, lower: Math.NaN },
					() -> new Keltner(emaPeriod, atrPeriod, m), (i, b) -> (cast i : Keltner).update(b));
			}
		};
	}
}
