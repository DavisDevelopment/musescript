package musescript.indicators.prim;

import musescript.indicators.MuseIndicator;

/**
 * Exponential Moving Average — ported from wickra-core's `Ema`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/ema.rs).
 *
 * `alpha = 2 / (period + 1)`; seeded with the simple mean of the first
 * `period` inputs, then the recurrence `alpha*input + (1-alpha)*prev`. A
 * non-finite input is ignored (state untouched).
 *
 * A `prim/` PRIMITIVE, not a builtin: MuseScript already exposes its own
 * `ema` (a series-scanning, first-value-seeded variant — deliberately NOT
 * replaced, corpus/parity tests depend on it). This faithful Wickra port
 * exists as a reusable streaming building block for the composite indicators
 * in `lib/` that Wickra itself builds on `Ema` (MACD, TRIX, DEMA, ...). See
 * ROADMAP.md epic 9 and IndicatorSpec.hx for the prim/ vs lib/ distinction.
 */
class Ema implements MuseIndicator<Float, Float> {
	public var period(default, null):Int;
	var alpha:Float;
	var oneMinusAlpha:Float;
	var current:Float;
	var seeded:Bool;
	var warmupBuf:Array<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "Ema: period must be > 0";
		this.period = period;
		alpha = 2.0 / (period + 1.0);
		oneMinusAlpha = 1.0 - alpha;
		reset();
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return seeded ? current : null;
		if (seeded) {
			current = alpha * input + oneMinusAlpha * current;
			return current;
		}
		warmupBuf.push(input);
		if (warmupBuf.length == period) {
			var sum = 0.0;
			for (v in warmupBuf) sum += v;
			current = sum / period;
			seeded = true;
			return current;
		}
		return null;
	}

	public function reset():Void {
		current = 0.0;
		seeded = false;
		warmupBuf = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return seeded;
	public function name():String return "EMA";

	/** Latest value, or NaN before seeding — for composites reading sub-EMA state directly. */
	public function value():Float return seeded ? current : Math.NaN;
}
