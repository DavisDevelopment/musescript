package musescript.indicators.prim;

import musescript.indicators.MuseIndicator;

/**
 * Ehlers' 2-pole Butterworth-style "SuperSmoother" lowpass filter.
 * Ported from wickra-core's `SuperSmoother`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/super_smoother.rs).
 *
 * From John Ehlers' *Cycle Analytics for Traders* (2013, ch. 3). For a given
 * critical period `period`, the filter coefficients are computed such that
 * the filter acts as a lowpass and dampens high-frequency noise while
 * preserving the underlying trend.
 *
 * The implementation needs two prior inputs and two prior outputs to begin
 * running; until then it returns the input itself (a common Ehlers initial
 * condition).
 *
 * A `prim/` PRIMITIVE: not registered as a builtin. Used as a building block
 * for composite indicators like EvenBetterSinewave.
 */
class SuperSmoother implements MuseIndicator<Float, Float> {
	var period:Int;
	var c1:Float;
	var c2:Float;
	var c3:Float;
	var prevInput:Null<Float>;
	var prevOutput1:Null<Float>;
	var prevOutput2:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "SuperSmoother: period must be > 0";
		this.period = period;

		var arg = Math.sqrt(2.0) * Math.PI / period;
		var a1 = Math.exp(-arg);
		var b1 = 2.0 * a1 * Math.cos(arg);
		var c2val = b1;
		var c3val = -a1 * a1;
		var c1val = 1.0 - c2val - c3val;

		this.c1 = c1val;
		this.c2 = c2val;
		this.c3 = c3val;
		this.prevInput = null;
		this.prevOutput1 = null;
		this.prevOutput2 = null;
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return prevOutput1;

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
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return prevOutput1 != null;
	public function name():String return "SuperSmoother";
}
