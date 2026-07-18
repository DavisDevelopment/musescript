package musescript.indicators.prim;

import musescript.indicators.MuseIndicator;

/**
 * Weighted Moving Average — ported from wickra-core's `Wma`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/wma.rs).
 *
 * Linear weights [1, 2, ..., period]; the newest bar carries the most weight.
 * O(1) per tick via the sliding-window identity
 * `new_weight_sum = old_weight_sum - old_value_sum + period * new_input`
 * (every retained element's weight drops by one, the newcomer enters at
 * weight = period). Order matters — subtract value_sum BEFORE updating it.
 *
 * A `prim/` PRIMITIVE, not a builtin (MuseScript already exposes `wma`).
 * Reusable streaming building block for `lib/` composites (Hull MA, etc.).
 */
class Wma implements MuseIndicator<Float, Float> {
	public var period(default, null):Int;
	var window:Array<Float>;
	var weightSum:Float;
	var valueSum:Float;
	var weightsTotal:Float;

	public function new(period:Int) {
		if (period <= 0) throw "Wma: period must be > 0";
		this.period = period;
		var n:Float = period;
		weightsTotal = n * (n + 1.0) / 2.0;
		reset();
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return isReady() ? value() : null;
		if (window.length < period) {
			window.push(input);
			valueSum += input;
			if (window.length == period) {
				weightSum = 0.0;
				for (i in 0...window.length) weightSum += (i + 1.0) * window[i];
				return value();
			}
			return null; // still warming up
		}
		var oldest = window.shift();
		weightSum = weightSum - valueSum + period * input;
		valueSum = valueSum - oldest + input;
		window.push(input);
		return value();
	}

	public function reset():Void {
		window = [];
		weightSum = 0.0;
		valueSum = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "WMA";

	/** Latest value, or NaN before the window fills. */
	public function value():Float return window.length == period ? weightSum / weightsTotal : Math.NaN;
}
