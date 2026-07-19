package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Atr;
import musescript.types.MuseType;

/** ATR Bands output: upper/middle/lower bands. */
typedef AtrBandsOutput = {
	var upper:Float;
	var middle:Float;
	var lower:Float;
}

/**
 * ATR Bands — ported from wickra-core's `AtrBands`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/atr_bands.rs).
 *
 * A close-anchored envelope of width `multiplier · ATR`. The centerline is
 * the raw close rather than a smoothed average — the band rides the price
 * tick-for-tick.
 *
 * upper = close + multiplier · ATR(period)
 * middle = close
 * lower = close − multiplier · ATR(period)
 */
class AtrBands implements MuseIndicator<Bar, AtrBandsOutput> {
	var atr:Atr;
	var multiplier:Float;

	public function new(period:Int, multiplier:Float) {
		if (!Math.isFinite(multiplier) || multiplier <= 0.0) throw "AtrBands: multiplier must be positive and finite";
		this.atr = new Atr(period);
		this.multiplier = multiplier;
	}

	public function update(bar:Bar):Null<AtrBandsOutput> {
		var atrVal = atr.update(bar);
		if (atrVal == null) return null;

		return {
			upper: bar.close + multiplier * atrVal,
			middle: bar.close,
			lower: bar.close - multiplier * atrVal
		};
	}

	public function reset():Void {
		atr.reset();
	}

	public function warmupPeriod():Int return atr.period;
	public function isReady():Bool return atr.isReady();
	public function name():String return "AtrBands";

	public static function spec():IndicatorSpec {
		return {
			name: "atr_bands", args: [TWindow, TScalar], ret: TObject([
				{name: "upper", ty: TScalar}, {name: "middle", ty: TScalar}, {name: "lower", ty: TScalar}
			]), minArgs: 2,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				var m = IndicatorCache.floatArg(args, 1, 3.0);
				var key = "atr_bands:" + p + ":" + m;
				return IndicatorCache.evalBar(h, key, { upper: Math.NaN, middle: Math.NaN, lower: Math.NaN },
					() -> new AtrBands(p, m), (i, b) -> (cast i : AtrBands).update(b));
			}
		};
	}
}
