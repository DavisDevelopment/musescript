package musescript.indicators.prim;

import musescript.indicators.MuseIndicator;

/**
 * Simple Moving Average — ported from wickra-core's `Sma`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/sma.rs).
 *
 * Rolling mean over the last `period` inputs via a running sum (O(1) per
 * tick). Wickra periodically reseeds the sum from the buffer to cap f64 drift;
 * this port keeps the same running-sum recurrence but omits the reseed — over
 * the bar counts a chart/backtest sees, the drift is far below display and
 * float-equality-test precision, and `batch_equals_streaming` still holds
 * exactly (both paths run the identical recurrence).
 *
 * A `prim/` PRIMITIVE, not a builtin (MuseScript already exposes `sma`).
 * Reusable streaming building block for `lib/` composites Wickra builds on
 * `Sma`. See Ema.hx and ROADMAP.md epic 9.
 */
class Sma implements MuseIndicator<Float, Float> {
	public var period(default, null):Int;
	var buf:Array<Float>;
	var sum:Float;

	public function new(period:Int) {
		if (period <= 0) throw "Sma: period must be > 0";
		this.period = period;
		reset();
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return value();
		buf.push(input);
		sum += input;
		if (buf.length > period) sum -= buf.shift();
		if (buf.length < period) return null;
		return sum / period;
	}

	public function reset():Void {
		buf = [];
		sum = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return buf.length == period;
	public function name():String return "SMA";

	/** Latest value, or NaN before the window fills. */
	public function value():Float return buf.length == period ? sum / period : Math.NaN;
}
