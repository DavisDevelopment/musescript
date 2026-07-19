package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Recovery Factor — ported from wickra-core's `RecoveryFactor`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/recovery_factor.rs).
 *
 * Cumulative net return over max drawdown from first observation.
 * Input treated as equity curve. Recovery > 1 means the strategy earned more than it ever lost.
 * Pure up-trend (no drawdown) reports 0.0 by convention.
 */
class RecoveryFactor implements MuseIndicator<Float, Float> {
	var first:Float;
	var last:Float;
	var peak:Float;
	var maxDd:Float;
	var seen:Bool;

	public function new() {
		first = 0.0;
		last = 0.0;
		peak = Math.NEGATIVE_INFINITY;
		maxDd = 0.0;
		seen = false;
	}

	function value():Null<Float> {
		if (!seen || first == 0.0) return null;
		if (maxDd == 0.0) return 0.0;

		var netReturn = (last / first) - 1.0;
		return netReturn / maxDd;
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) {
			return value();
		}

		if (seen) {
			if (input > peak) {
				peak = input;
			}
			if (peak > 0.0) {
				var dd = (peak - input) / peak;
				if (dd > maxDd) {
					maxDd = dd;
				}
			}
		} else {
			first = input;
			peak = input;
			seen = true;
		}

		last = input;
		return value();
	}

	public function reset():Void {
		first = 0.0;
		last = 0.0;
		peak = Math.NEGATIVE_INFINITY;
		maxDd = 0.0;
		seen = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return seen && first != 0.0;
	public function name():String return "RecoveryFactor";

	public static function spec():IndicatorSpec {
		return {
			name: "recovery_factor", args: [TSeries], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				return IndicatorCache.evalSeries(h, "recovery_factor:" + series, series, Math.NaN,
					() -> new RecoveryFactor(), (i, v) -> (cast i : RecoveryFactor).update(v));
			}
		};
	}
}
