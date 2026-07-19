package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Smma;
import musescript.types.MuseType;

/** Alligator output: three smoothed moving averages of the median price. */
typedef AlligatorOutput = {
	var jaw:Float;
	var teeth:Float;
	var lips:Float;
}

/**
 * Bill Williams' Alligator — ported from wickra-core's `Alligator`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/alligator.rs).
 *
 * Three `SMMA`s of the median price `(high + low) / 2` with different periods.
 * Classic parameters are `(jaw = 13, teeth = 8, lips = 5)`. The indicator emits
 * values once all three `SMMA`s have warmed up, i.e. after `max(jaw, teeth, lips)`
 * candles.
 */
class Alligator implements MuseIndicator<Bar, AlligatorOutput> {
	var jawPeriod:Int;
	var teethPeriod:Int;
	var lipsPeriod:Int;
	var jaw:Smma;
	var teeth:Smma;
	var lips:Smma;

	public function new(jawPeriod:Int, teethPeriod:Int, lipsPeriod:Int) {
		if (jawPeriod <= 0 || teethPeriod <= 0 || lipsPeriod <= 0) {
			throw "Alligator: all periods must be > 0";
		}
		this.jawPeriod = jawPeriod;
		this.teethPeriod = teethPeriod;
		this.lipsPeriod = lipsPeriod;
		this.jaw = new Smma(jawPeriod);
		this.teeth = new Smma(teethPeriod);
		this.lips = new Smma(lipsPeriod);
	}

	/** Classic Alligator with parameters (jaw=13, teeth=8, lips=5). */
	public static function classic():Alligator {
		return new Alligator(13, 8, 5);
	}

	public function update(candle:Bar):Null<AlligatorOutput> {
		var median = (candle.high + candle.low) / 2.0;
		// Feed every SMMA on every bar so they warm up in parallel.
		var lipsVal = lips.update(median);
		var teethVal = teeth.update(median);
		var jawVal = jaw.update(median);

		if (jawVal == null || teethVal == null || lipsVal == null) {
			return null;
		}
		return { jaw: jawVal, teeth: teethVal, lips: lipsVal };
	}

	public function reset():Void {
		jaw.reset();
		teeth.reset();
		lips.reset();
	}

	public function warmupPeriod():Int {
		return Std.int(Math.max(jawPeriod, Math.max(teethPeriod, lipsPeriod)));
	}

	public function isReady():Bool {
		return jaw.isReady() && teeth.isReady() && lips.isReady();
	}

	public function name():String return "Alligator";

	public static function spec():IndicatorSpec {
		return {
			name: "alligator", args: [TWindow, TWindow, TWindow], ret: TObject([
				{name: "jaw", ty: TScalar}, {name: "teeth", ty: TScalar}, {name: "lips", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var jaw = IndicatorCache.intArg(args, 0, 13);
				var teeth = IndicatorCache.intArg(args, 1, 8);
				var lips = IndicatorCache.intArg(args, 2, 5);
				var nanFill = { jaw: Math.NaN, teeth: Math.NaN, lips: Math.NaN };
				return IndicatorCache.evalBar(h, "alligator:" + jaw + ":" + teeth + ":" + lips, nanFill,
					() -> new Alligator(jaw, teeth, lips), (i, b) -> (cast i : Alligator).update(b));
			}
		};
	}
}
