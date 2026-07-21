package musescript.indicators.prim;

import musescript.indicators.MuseIndicator;

/**
 * Rolling Maximum Drawdown — ported from wickra-core's `MaxDrawdown`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/max_drawdown.rs).
 *
 * The input is treated as an equity-curve sample. For each bar the indicator
 * reports the deepest peak-to-trough fractional decline inside the trailing
 * `period`-bar window, as a non-negative fraction (`0.20` = 20% drop from
 * peak). A monotonically rising equity curve has a max drawdown of `0`; a
 * non-positive peak skips the division and contributes `0`. A non-finite
 * input is ignored (state untouched, last value returned). The
 * monotonically-decreasing peak deque of the Rust source is kept verbatim
 * even though the emitted value comes from the window scan.
 *
 * A `prim/` PRIMITIVE, not a builtin (MuseScript already exposes
 * `max_drawdown`). Reusable streaming building block for `lib/` composites.
 * See Ema.hx and ROADMAP.md epic 9.
 */
class MaxDrawdown implements MuseIndicator<Float, Float> {
	public var period(default, null):Int;
	var count:Int;
	/** Monotonically-decreasing deque of `{idx, v}` over the trailing window. Front is the trailing peak. */
	var peakDq:Array<{idx:Int, v:Float}>;
	var window:Array<Float>;
	var last:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "MaxDrawdown: period must be > 0";
		this.period = period;
		reset();
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return last;
		count++;
		// Drop tail entries dominated by the new value (running peak from the
		// back side of the window).
		while (peakDq.length > 0 && peakDq[peakDq.length - 1].v <= input) peakDq.pop();
		peakDq.push({idx: count, v: input});
		// Window slide.
		if (window.length == period) window.shift();
		window.push(input);
		var windowLo = count - (period - 1);
		while (peakDq.length > 0 && peakDq[0].idx < windowLo) peakDq.shift();
		if (window.length < period) return null;
		// Scan the window for the deepest drawdown vs running peak so far.
		var peak = Math.NEGATIVE_INFINITY;
		var worst = 0.0;
		for (v in window) {
			if (v > peak) peak = v;
			if (peak > 0.0) {
				var dd = (peak - v) / peak;
				if (dd > worst) worst = dd;
			}
		}
		last = worst;
		return worst;
	}

	public function reset():Void {
		count = 0;
		peakDq = [];
		window = [];
		last = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return last != null;
	public function name():String return "MaxDrawdown";

	/** Latest value, or NaN before warmup — for composites reading state directly. */
	public function value():Float return last == null ? Math.NaN : last;
}
