package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Aroon Oscillator — ported from wickra-core's `AroonOscillator`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/aroon_oscillator.rs).
 *
 * The single-line difference: AroonUp − AroonDown, in range [−100, 100].
 * Strongly positive means the most recent high is much fresher than the most
 * recent low (an up-trend); strongly negative is the mirror image. Readings
 * near zero mean neither extreme is recent — a range.
 */
class AroonOscillator implements MuseIndicator<Bar, Float> {
	var aroon:Aroon;
	var last:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "AroonOscillator: period must be > 0";
		this.aroon = new Aroon(period);
		this.last = null;
	}

	public function update(bar:Bar):Null<Float> {
		var out = aroon.update(bar);
		if (out == null) return null;
		var osc = out.up - out.down;
		last = osc;
		return osc;
	}

	public function reset():Void {
		aroon.reset();
		last = null;
	}

	public function warmupPeriod():Int return aroon.warmupPeriod();
	public function isReady():Bool return last != null;
	public function name():String return "AroonOscillator";

	public static function spec():IndicatorSpec {
		return {
			name: "aroon_oscillator", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				return IndicatorCache.evalBar(h, "aroon_oscillator:" + p, Math.NaN,
					() -> new AroonOscillator(p), (i, b) -> (cast i : AroonOscillator).update(b));
			}
		};
	}
}
