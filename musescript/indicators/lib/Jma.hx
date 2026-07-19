package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Jurik Moving Average (JMA) — ported from wickra-core's `Jma`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/jma.rs).
 *
 * Mark Jurik's adaptive moving average using the three-stage filter
 * reconstruction widely used since the 1999 TASC article. Parameters:
 * - period: smoothing length (default 14)
 * - phase: phase shift in [-100, 100], clamped to determine phase_ratio in [0.5, 2.5]
 * - power: kernel exponent in [1, 4] (default 2)
 *
 * The state is seeded so a constant input stream is reproduced exactly
 * from the first output onward.
 */
class Jma implements MuseIndicator<Float, Float> {
	var period:Int;
	var phase:Float;
	var power:Int;
	var beta:Float;
	var alpha:Float;
	var phaseRatio:Float;
	var e0:Float;
	var e1:Float;
	var e2:Float;
	var output:Null<Float>;

	public function new(period:Int, phase:Float, power:Int) {
		if (period <= 0) throw "Jma: period must be > 0";
		if (!Math.isFinite(phase)) throw "Jma: phase must be a finite value";
		if (power < 1 || power > 4) throw "Jma: power must be in 1..=4";

		this.period = period;
		this.phase = phase;
		this.power = power;

		var len = (period - 1 : Float);
		beta = 0.45 * len / (0.45 * len + 2.0);
		alpha = Math.pow(beta, power);
		phaseRatio = Math.max(0.5, Math.min(2.5, phase / 100.0 + 1.5));

		e0 = 0.0;
		e1 = 0.0;
		e2 = 0.0;
		output = null;
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return output;

		if (output == null) {
			// Seed e0 and JMA to the first input so a flat series is reproduced exactly.
			e0 = input;
			output = input;
			return output;
		}

		var prevJma = output;
		e0 = (1.0 - alpha) * input + alpha * e0;
		e1 = (input - e0) * (1.0 - beta) + beta * e1;
		var oneMinusAlpha = 1.0 - alpha;
		e2 = (e0 + phaseRatio * e1 - prevJma) * oneMinusAlpha * oneMinusAlpha + alpha * alpha * e2;
		var next = prevJma + e2;
		output = next;
		return next;
	}

	public function reset():Void {
		e0 = 0.0;
		e1 = 0.0;
		e2 = 0.0;
		output = null;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return output != null;
	public function name():String return "JMA";

	public static function spec():IndicatorSpec {
		return {
			name: "jma", args: [TSeries, TWindow, TScalar, TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var period = IndicatorCache.intArg(args, 1, 14);
				var phase = IndicatorCache.floatArg(args, 2, 0.0);
				var power = IndicatorCache.intArg(args, 3, 2);
				var key = "jma:" + series + ":" + period + ":" + phase + ":" + power;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new Jma(period, phase, power), (i, v) -> (cast i : Jma).update(v));
			}
		};
	}
}
