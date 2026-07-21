package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Smoothed Moving Average (Wilder's RMA) — ported from wickra-core's `Smma`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/smma.rs).
 *
 * Seeded with the simple average of the first `period` inputs, then advanced
 * by `SMMA_t = (SMMA_{t-1} * (period - 1) + price_t) / period` — an
 * exponential average with a slow `1 / period` smoothing factor, the average
 * underlying Wilder's RSI and ATR. First output after exactly `period`
 * inputs.
 *
 * The lib builtin (`smma(close, period)`); a `prim/Smma` with the identical
 * class name exists in its own package for composites, following the
 * RoofingFilter/SuperSmoother precedent.
 */
class Smma implements MuseIndicator<Float, Float> {
	var period:Int;
	/** Inputs collected while seeding (before the first value is produced). */
	var seed:Array<Float>;
	var seedSum:Float;
	var current:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "Smma: period must be > 0";
		this.period = period;
		reset();
	}

	/** Configured period. */
	public function getPeriod():Int return period;

	/** Current value if available. */
	public function value():Null<Float> return current;

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) {
			// Non-finite input is ignored, leaving state untouched.
			return current;
		}
		if (current != null) {
			var p:Float = period;
			current = (current * (p - 1.0) + input) / p;
		} else {
			seed.push(input);
			seedSum += input;
			if (seed.length == period) {
				current = seedSum / period;
			}
		}
		return current;
	}

	public function reset():Void {
		seed = [];
		seedSum = 0.0;
		current = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return current != null;
	public function name():String return "SMMA";

	public static function spec():IndicatorSpec {
		return {
			name: "smma", args: [TSeries, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "smma:" + series + ":" + p, series, Math.NaN,
					() -> new Smma(p), (i, v) -> (cast i : Smma).update(v));
			}
		};
	}
}
