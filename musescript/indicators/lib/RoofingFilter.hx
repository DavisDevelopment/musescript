package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Ehlers' Roofing Filter — a bandpass formed by feeding a 2-pole high-pass
 * into a SuperSmoother.
 *
 * Defined in *Cycle Analytics for Traders* (Ehlers 2013, ch. 7) as the
 * canonical pre-filter for cycle-aware oscillators: the high-pass strips out
 * the trend (periods longer than `hp_period`), and the SuperSmoother removes
 * noise (periods shorter than `lp_period`). The result is essentially the
 * 10–48 bar cycle band by default.
 *
 * Ported from wickra-core's `RoofingFilter`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/roofing_filter.rs).
 */
class RoofingFilter implements MuseIndicator<Float, Float> {
	var lpPeriod:Int;
	var hpPeriod:Int;
	var alpha:Float;
	var prevIn1:Null<Float>;
	var prevHp1:Float;
	var prevHp2:Float;
	var smoother:SuperSmoother;
	var lastValue:Null<Float>;

	public function new(lpPeriod:Int, hpPeriod:Int) {
		if (lpPeriod <= 0 || hpPeriod <= 0) throw "RoofingFilter: both periods must be > 0";
		if (lpPeriod >= hpPeriod) throw "RoofingFilter: lp_period must be strictly less than hp_period";
		this.lpPeriod = lpPeriod;
		this.hpPeriod = hpPeriod;
		// Single-pole high-pass alpha from Ehlers ch. 7
		var arg = 2.0 * Math.PI / hpPeriod;
		this.alpha = (Math.cos(arg) + Math.sin(arg) - 1.0) / Math.cos(arg);
		prevIn1 = null;
		prevHp1 = 0.0;
		prevHp2 = 0.0;
		smoother = new SuperSmoother(lpPeriod);
		lastValue = null;
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) {
			return lastValue;
		}
		var hp:Float;
		if (prevIn1 != null) {
			var oneMinusHalfAlpha = 1.0 - alpha / 2.0;
			hp = oneMinusHalfAlpha * (input - prevIn1) + (1.0 - alpha) * prevHp1;
		} else {
			hp = 0.0;
		}
		prevHp2 = prevHp1;
		prevHp1 = hp;
		prevIn1 = input;
		var v = smoother.update(hp);
		if (v != null) {
			lastValue = v;
			return v;
		}
		return null;
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

	public static function spec():IndicatorSpec {
		return {
			name: "roofing_filter", args: [TWindow, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var lp = IndicatorCache.intArg(args, 0, 10);
				var hp = IndicatorCache.intArg(args, 1, 48);
				return IndicatorCache.evalSeries(h, "roofing_filter:" + lp + ":" + hp, "close", Math.NaN,
					() -> new RoofingFilter(lp, hp), (i, v) -> (cast i : RoofingFilter).update(v));
			}
		};
	}
}
