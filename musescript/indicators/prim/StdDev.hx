package musescript.indicators.prim;

import musescript.indicators.MuseIndicator;

/**
 * Standard Deviation (sample, with Bessel correction) — ported from wickra-core's `StdDev`.
 *
 * Computes the sample standard deviation (N-1 denominator) over a rolling window
 * of the last `period` values, using running sum/sum-of-squares (O(1) per tick).
 *
 * A `prim/` PRIMITIVE, reusable building block for indicators that depend on
 * standard deviation, like DynamicMomentumIndex. Not registered as a builtin.
 */
class StdDev implements MuseIndicator<Float, Float> {
	public var period(default, null):Int;
	var buf:Array<Float>;
	var sum:Float;
	var sumSq:Float;

	public function new(period:Int) {
		if (period <= 1) throw "StdDev: period must be > 1 (need at least 2 for sample std dev)";
		this.period = period;
		reset();
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return isReady() ? value() : null;
		buf.push(input);
		sum += input;
		sumSq += input * input;
		if (buf.length > period) {
			var old = buf.shift();
			sum -= old;
			sumSq -= old * old;
		}
		if (buf.length < period) return null;
		return value();
	}

	public function reset():Void {
		buf = [];
		sum = 0.0;
		sumSq = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return buf.length == period;
	public function name():String return "StdDev";

	/** Latest value, or NaN before the window fills. */
	public function value():Float {
		if (buf.length < period) return Math.NaN;
		var mean = sum / period;
		// Sample variance: divide by (n-1) instead of n
		var variance = ((sumSq / period) - mean * mean) * period / (period - 1);
		variance = Math.max(0.0, variance);
		return Math.sqrt(variance);
	}
}
