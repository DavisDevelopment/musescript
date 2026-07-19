package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Ehlers' Laguerre RSI: a low-lag RSI variant built from the same 4-stage
 * Laguerre cascade as `AdaptiveLaguerreFilter`, but with a *fixed* damping
 * factor `gamma` (not error-adaptive), and an RSI-style ratio computed
 * directly from the cascade's stage-to-stage differences instead of
 * bar-over-bar price changes.
 *
 * L0 = (1-gamma)*price + gamma*L0_prev
 * L1 = -gamma*L0 + L0_prev + gamma*L1_prev
 * L2 = -gamma*L1 + L1_prev + gamma*L2_prev
 * L3 = -gamma*L2 + L2_prev + gamma*L3_prev
 * CU = sum of positive (L0-L1), (L1-L2), (L2-L3)
 * CD = sum of |negative (L0-L1), (L1-L2), (L2-L3)|
 * LaguerreRSI = CU / (CU + CD)      (0 when both are zero)
 */
class LaguerreRsi implements MuseIndicator<Float, Float> {
	var gamma:Float;
	var l0:Float;
	var l1:Float;
	var l2:Float;
	var l3:Float;
	var hasEmitted:Bool;

	public function new(gamma:Float = 0.5) {
		if (!Math.isFinite(gamma) || gamma <= 0.0 || gamma >= 1.0) throw "LaguerreRsi: gamma must be in (0, 1)";
		this.gamma = gamma;
		l0 = 0.0; l1 = 0.0; l2 = 0.0; l3 = 0.0;
		hasEmitted = false;
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return hasEmitted ? value() : null;

		var newL0 = (1.0 - gamma) * price + gamma * l0;
		var newL1 = -gamma * newL0 + l0 + gamma * l1;
		var newL2 = -gamma * newL1 + l1 + gamma * l2;
		var newL3 = -gamma * newL2 + l2 + gamma * l3;
		l0 = newL0; l1 = newL1; l2 = newL2; l3 = newL3;
		hasEmitted = true;
		return value();
	}

	function value():Float {
		var cu = 0.0;
		var cd = 0.0;
		for (diff in [l0 - l1, l1 - l2, l2 - l3]) {
			if (diff >= 0.0) cu += diff;
			else cd -= diff;
		}
		var denom = cu + cd;
		return denom == 0.0 ? 0.5 : cu / denom;
	}

	public function reset():Void {
		l0 = 0.0; l1 = 0.0; l2 = 0.0; l3 = 0.0;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "LaguerreRsi";

	public static function spec():IndicatorSpec {
		return {
			name: "laguerre_rsi", args: [TSeries, TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var gamma = IndicatorCache.floatArg(args, 1, 0.5);
				return IndicatorCache.evalSeries(h, "laguerre_rsi:" + series + ":" + gamma, series, Math.NaN,
					() -> new LaguerreRsi(gamma), (i, v) -> (cast i : LaguerreRsi).update(v));
			}
		};
	}
}
