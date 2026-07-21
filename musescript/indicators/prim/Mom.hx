package musescript.indicators.prim;

import musescript.indicators.MuseIndicator;

/**
 * Momentum — ported from wickra-core's `Mom`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/mom.rs).
 *
 * The raw price change over `period` bars, `price_t − price_{t−period}`, in
 * absolute price units (unlike ROC, which divides by the old price for a
 * percentage). A non-finite input is ignored: the window is left untouched
 * and the last computed value is returned instead.
 *
 * A `prim/` PRIMITIVE, not a builtin (MuseScript already exposes `mom`).
 * Reusable streaming building block for `lib/` composites. See Ema.hx and
 * ROADMAP.md epic 9.
 */
class Mom implements MuseIndicator<Float, Float> {
	public var period(default, null):Int;
	/** Rolling buffer of the last `period + 1` inputs, oldest at the front. */
	var window:Array<Float>;
	var last:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "Mom: period must be > 0";
		this.period = period;
		reset();
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return last;
		if (window.length == period + 1) window.shift();
		window.push(input);
		if (window.length < period + 1) return null;
		var prev = window[0];
		var mom = input - prev;
		last = mom;
		return mom;
	}

	public function reset():Void {
		window = [];
		last = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return window.length == period + 1;
	public function name():String return "MOM";

	/** Latest value, or NaN before warmup — for composites reading state directly. */
	public function value():Float return last == null ? Math.NaN : last;
}
