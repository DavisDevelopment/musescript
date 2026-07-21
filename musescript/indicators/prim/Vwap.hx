package musescript.indicators.prim;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;

/**
 * Cumulative session Volume-Weighted Average Price — ported from
 * wickra-core's `Vwap`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/vwap.rs).
 *
 * Accumulates `typical_price * volume` and `volume` forever (the intraday
 * convention); call `reset()` at each session boundary. Returns null while
 * the cumulative volume is zero. Faithful to the Rust source, there is NO
 * non-finite-input guard on either variant in this module. The rolling
 * finite-memory variant from the same Rust file is ported alongside as
 * `RollingVwap` below.
 *
 * A `prim/` PRIMITIVE, not a builtin (MuseScript already exposes `vwap`).
 * Reusable streaming building block for `lib/` composites. See Ema.hx and
 * ROADMAP.md epic 9.
 */
class Vwap implements MuseIndicator<Bar, Float> {
	var sumPv:Float;
	var sumV:Float;
	var hasEmitted:Bool;

	public function new() {
		reset();
	}

	public function update(candle:Bar):Null<Float> {
		var tp = (candle.high + candle.low + candle.close) / 3.0;
		sumPv += tp * candle.volume;
		sumV += candle.volume;
		if (sumV == 0.0) return null;
		hasEmitted = true;
		return sumPv / sumV;
	}

	public function reset():Void {
		sumPv = 0.0;
		sumV = 0.0;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "VWAP";

	/** Current VWAP, or NaN before any non-zero-volume candle — for composites reading state directly. */
	public function value():Float return sumV == 0.0 ? Math.NaN : sumPv / sumV;
}

/**
 * Rolling-window VWAP: the finite-memory variant from the same Rust source
 * file (`RollingVwap`), for consumers that don't want unbounded accumulation.
 */
class RollingVwap implements MuseIndicator<Bar, Float> {
	public var period(default, null):Int;
	/** Rolling window of `{pv, v}` = (typical_price * volume, volume). */
	var window:Array<{pv:Float, v:Float}>;
	var sumPv:Float;
	var sumV:Float;

	public function new(period:Int) {
		if (period <= 0) throw "RollingVwap: period must be > 0";
		this.period = period;
		reset();
	}

	public function update(candle:Bar):Null<Float> {
		var tp = (candle.high + candle.low + candle.close) / 3.0;
		var pv = tp * candle.volume;
		if (window.length == period) {
			var old = window.shift();
			sumPv -= old.pv;
			sumV -= old.v;
		}
		window.push({pv: pv, v: candle.volume});
		sumPv += pv;
		sumV += candle.volume;
		if (window.length < period || sumV == 0.0) return null;
		return sumPv / sumV;
	}

	public function reset():Void {
		window = [];
		sumPv = 0.0;
		sumV = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period && sumV > 0.0;
	public function name():String return "RollingVWAP";

	/** Current rolling VWAP, or NaN before the window fills — for composites reading state directly. */
	public function value():Float return isReady() ? sumPv / sumV : Math.NaN;
}
