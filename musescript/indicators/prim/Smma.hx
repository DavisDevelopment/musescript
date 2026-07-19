package musescript.indicators.prim;

import musescript.indicators.MuseIndicator;

/**
 * Smoothed Moving Average (Wilder's RMA) — ported from wickra-core's `Smma`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/smma.rs).
 *
 * Seeded with the simple average of the first `period` inputs, then advanced
 * by `SMMA_t = (SMMA_{t-1} * (period - 1) + price_t) / period`. This is an
 * exponential average with a slow `1 / period` smoothing factor and is the
 * average underlying Wilder's RSI and ATR.
 *
 * A `prim/` PRIMITIVE, not a builtin: reusable streaming building block for
 * composites that use SMMA (e.g., Alligator, Ichimoku).
 */
class Smma implements MuseIndicator<Float, Float> {
	public var period(default, null):Int;
	var seed:Array<Float>;
	var seedSum:Float;
	var current:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "Smma: period must be > 0";
		this.period = period;
		reset();
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return current;
		if (current != null) {
			var p:Float = period;
			current = (current * (p - 1.0) + input) / p;
		} else {
			seed.push(input);
			seedSum += input;
			if (seed.length == period) {
				current = seedSum / period;
			}
		}
		return current;
	}

	public function reset():Void {
		seed = [];
		seedSum = 0.0;
		current = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return current != null;
	public function name():String return "SMMA";

	/** Latest value, or NaN before seeding — for composites reading sub-SMMA state directly. */
	public function value():Float return current != null ? current : Math.NaN;
}
