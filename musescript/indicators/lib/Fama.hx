package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;
import musescript.indicators.prim.Mama;

/**
 * FAMA (Following Adaptive Moving Average) — ported from wickra-core's `Fama`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/fama.rs).
 *
 * Scalar wrapper that exposes only the FAMA line from a MAMA indicator.
 * FAMA is MAMA's lagging companion — MAMA crossing above FAMA marks a trend
 * confirmation; MAMA below FAMA marks a reversal.
 */
class Fama implements MuseIndicator<Float, Float> {
	var inner:Mama;
	var lastValue:Null<Float>;

	public function new(fastLimit:Float, slowLimit:Float) {
		inner = new Mama(fastLimit, slowLimit);
		lastValue = null;
	}

	/** Default (0.5, 0.05) parameters. */
	public static function classic():Fama {
		return new Fama(0.5, 0.05);
	}

	/** Configured (fast_limit, slow_limit). */
	public function limits():{fast_limit:Float, slow_limit:Float} {
		return {fast_limit: 0.5, slow_limit: 0.05}; // These are constants; could extract from Mama if needed
	}

	/** Current FAMA value if available. */
	public function value():Null<Float> {
		return lastValue;
	}

	public function update(input:Float):Null<Float> {
		var output = inner.update(input);
		if (output != null) {
			lastValue = output.fama;
			return lastValue;
		}
		return lastValue;
	}

	public function reset():Void {
		inner.reset();
		lastValue = null;
	}

	public function warmupPeriod():Int return inner.warmupPeriod();
	public function isReady():Bool return lastValue != null;
	public function name():String return "FAMA";

	public static function spec():IndicatorSpec {
		return {
			name: "fama", args: [TSeries, TScalar, TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var fastLimit = IndicatorCache.floatArg(args, 1, 0.5);
				var slowLimit = IndicatorCache.floatArg(args, 2, 0.05);
				var key = "fama:" + series + ":" + fastLimit + ":" + slowLimit;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new Fama(fastLimit, slowLimit), (i, v) -> (cast i : Fama).update(v));
			}
		};
	}
}
