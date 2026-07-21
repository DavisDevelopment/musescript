package musescript.indicators.prim;

import musescript.indicators.MuseIndicator;

/**
 * Ehlers Roofing Filter — ported from wickra-core's `RoofingFilter`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/roofing_filter.rs).
 *
 * A bandpass formed by feeding a 2-pole high-pass into a SuperSmoother.
 * The high-pass strips out the trend (periods longer than `hp_period`),
 * and the SuperSmoother removes noise (periods shorter than `lp_period`).
 * The result isolates the tradable cycle band (10–48 bars by default).
 *
 * A `prim/` PRIMITIVE, not a builtin: used as a building block by the
 * composite indicator ehlers_stochastic in `lib/`.
 */
class RoofingFilter implements MuseIndicator<Float, Float> {
	public var lpPeriod(default, null):Int;
	public var hpPeriod(default, null):Int;
	var alpha:Float;
	var prevIn1:Null<Float>;
	var prevHp1:Float;
	var prevHp2:Float;
	var smoother:SuperSmoother;
	var lastValue:Null<Float>;

	public function new(lpPeriod:Int, hpPeriod:Int) {
		if (lpPeriod <= 0 || hpPeriod <= 0) throw "RoofingFilter: periods must be > 0";
		if (lpPeriod >= hpPeriod) throw "RoofingFilter: lp_period must be < hp_period";

		this.lpPeriod = lpPeriod;
		this.hpPeriod = hpPeriod;

		// Single-pole high-pass alpha from Ehlers ch. 7.
		var arg = 2.0 * Math.PI / hpPeriod;
		alpha = (Math.cos(arg) + Math.sin(arg) - 1.0) / Math.cos(arg);

		prevIn1 = null;
		prevHp1 = 0.0;
		prevHp2 = 0.0;
		smoother = new SuperSmoother(lpPeriod);
		lastValue = null;
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return lastValue;

		var hp = if (prevIn1 != null) {
			var oneMinusHalfAlpha = 1.0 - alpha / 2.0;
			oneMinusHalfAlpha * (input - prevIn1) + (1.0 - alpha) * prevHp1;
		} else {
			0.0;
		}

		prevHp2 = prevHp1;
		prevHp1 = hp;
		prevIn1 = input;

		var v = smoother.update(hp);
		if (v != null) {
			lastValue = v;
		}
		return v;
	}

	public function reset():Void {
		prevIn1 = null;
		prevHp1 = 0.0;
		prevHp2 = 0.0;
		smoother.reset();
		lastValue = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return lastValue != null;
	public function name():String return "RoofingFilter";
}
