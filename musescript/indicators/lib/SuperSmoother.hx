package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Ehlers' 2-pole Butterworth-style "SuperSmoother" lowpass filter.
 *
 * From John Ehlers' *Cycle Analytics for Traders* (2013, ch. 3). For a given
 * critical period `period`, the filter coefficients are calculated and the
 * filter is applied as: y[t] = c1 * (x[t] + x[t-1]) / 2 + c2 * y[t-1] + c3 * y[t-2]
 *
 * The implementation needs two prior inputs and two prior outputs to begin
 * running; until then it returns the input itself (a common Ehlers initial
 * condition), which lets downstream filters warm up without long delays.
 *
 * Ported from wickra-core's `SuperSmoother`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/super_smoother.rs).
 */
class SuperSmoother implements MuseIndicator<Float, Float> {
	var period:Int;
	var c1:Float;
	var c2:Float;
	var c3:Float;
	var prevInput:Null<Float>;
	var prevOutput1:Null<Float>;
	var prevOutput2:Null<Float>;
	var count:Int;

	public function new(period:Int) {
		if (period <= 0) throw "SuperSmoother: period must be > 0";
		this.period = period;
		var arg = Math.sqrt(2) * Math.PI / period;
		var a1 = Math.exp(-arg);
		var b1 = 2.0 * a1 * Math.cos(arg);
		var c2_tmp = b1;
		var c3_tmp = -a1 * a1;
		this.c1 = 1.0 - c2_tmp - c3_tmp;
		this.c2 = c2_tmp;
		this.c3 = c3_tmp;
		prevInput = null;
		prevOutput1 = null;
		prevOutput2 = null;
		count = 0;
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) {
			return prevOutput1;
		}
		count++;
		var output:Float;
		if (prevInput != null && prevOutput1 != null && prevOutput2 != null) {
			var avg = 0.5 * (input + prevInput);
			output = c1 * avg + c2 * prevOutput1 + c3 * prevOutput2;
		} else {
			output = input;
		}
		prevOutput2 = prevOutput1;
		prevOutput1 = output;
		prevInput = input;
		return output;
	}

	public function reset():Void {
		prevInput = null;
		prevOutput1 = null;
		prevOutput2 = null;
		count = 0;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return prevOutput1 != null;
	public function name():String return "SuperSmoother";

	public static function spec():IndicatorSpec {
		return {
			name: "super_smoother", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 10);
				return IndicatorCache.evalSeries(h, "super_smoother:" + p, "close", Math.NaN,
					() -> new SuperSmoother(p), (i, v) -> (cast i : SuperSmoother).update(v));
			}
		};
	}
}
