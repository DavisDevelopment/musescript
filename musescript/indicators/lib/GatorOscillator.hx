package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Gator Oscillator output: the upper (jaw-teeth) and lower (teeth-lips) histogram bars. */
typedef GatorOscillatorOutput = {
	var upper:Float;
	var lower:Float;
}

/**
 * Gator Oscillator: the absolute convergence/divergence of Bill Williams'
 * Alligator lines, split into an upper bar (jaw vs. teeth) and a lower bar
 * (teeth vs. lips, negated so it plots below the zero line).
 *
 * upper =  |jaw - teeth|
 * lower = -|teeth - lips|
 *
 * Growing bars mean the Alligator's lines are spreading apart (a trend is
 * "waking up" / accelerating); shrinking bars mean they're converging (the
 * Alligator is "sleeping" / consolidating).
 */
class GatorOscillator implements MuseIndicator<Bar, GatorOscillatorOutput> {
	var alligator:Alligator;

	public function new(jawPeriod:Int, teethPeriod:Int, lipsPeriod:Int) {
		alligator = new Alligator(jawPeriod, teethPeriod, lipsPeriod);
	}

	public function update(bar:Bar):Null<GatorOscillatorOutput> {
		var a = alligator.update(bar);
		if (a == null) return null;
		return { upper: Math.abs(a.jaw - a.teeth), lower: -Math.abs(a.teeth - a.lips) };
	}

	public function reset():Void {
		alligator.reset();
	}

	public function warmupPeriod():Int return alligator.warmupPeriod();
	public function isReady():Bool return alligator.isReady();
	public function name():String return "GatorOscillator";

	public static function spec():IndicatorSpec {
		return {
			name: "gator_oscillator", args: [TWindow, TWindow, TWindow], ret: TObject([
				{name: "upper", ty: TScalar}, {name: "lower", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var jaw = IndicatorCache.intArg(args, 0, 13);
				var teeth = IndicatorCache.intArg(args, 1, 8);
				var lips = IndicatorCache.intArg(args, 2, 5);
				var key = "gator_oscillator:" + jaw + ":" + teeth + ":" + lips;
				return IndicatorCache.evalBar(h, key, { upper: Math.NaN, lower: Math.NaN },
					() -> new GatorOscillator(jaw, teeth, lips), (i, b) -> (cast i : GatorOscillator).update(b));
			}
		};
	}
}
