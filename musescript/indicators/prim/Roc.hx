package musescript.indicators.prim;

import musescript.indicators.MuseIndicator;

/**
 * Rate of Change — ported from wickra-core's `Roc`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/roc.rs).
 *
 * `(close − close[period]) / close[period] * 100`, as a percentage. A zero
 * previous price yields `0` (divide-by-zero guard). A non-finite input is
 * ignored: the window is left untouched and the last computed value is
 * returned instead, matching the SMA/EMA convention.
 *
 * A `prim/` PRIMITIVE, not a builtin (MuseScript already exposes `roc`).
 * Reusable streaming building block for `lib/` composites. See Ema.hx and
 * ROADMAP.md epic 9.
 */
class Roc implements MuseIndicator<Float, Float> {
	public var period(default, null):Int;
	var window:Array<Float>;
	var last:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "Roc: period must be > 0";
		this.period = period;
		reset();
	}

	public function update(input:Float):Null<Float> {
		// Non-finite inputs are ignored: return the last value, leave state as is.
		if (!Math.isFinite(input)) return last;
		if (window.length == period + 1) window.shift();
		window.push(input);
		if (window.length < period + 1) return null;
		var prev = window[0];
		var roc = prev == 0.0 ? 0.0 : (input - prev) / prev * 100.0;
		last = roc;
		return roc;
	}

	public function reset():Void {
		window = [];
		last = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return window.length == period + 1;
	public function name():String return "ROC";

	/** Latest value, or NaN before warmup — for composites reading state directly. */
	public function value():Float return last == null ? Math.NaN : last;
}
