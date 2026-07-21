package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;
import musescript.indicators.prim.Mama.MamaOutput;

/**
 * Ehlers' MESA Adaptive Moving Average (MAMA) — ported from wickra-core's
 * `Mama`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/mama.rs).
 *
 * MAMA adapts its smoothing constant from the rate-of-change of price phase,
 * derived via a truncated Hilbert transform. The `(fast_limit, slow_limit)`
 * pair bounds the adaptive alpha; defaults `(0.5, 0.05)` match the canonical
 * EasyLanguage implementation. Emits both the MAMA line and its lagging
 * companion FAMA.
 *
 * The lib builtin (`mama(close, fast_limit, slow_limit)`) wraps the
 * `prim/Mama` streaming engine — same class name, different package,
 * following the RoofingFilter/SuperSmoother precedent.
 */
class Mama implements MuseIndicator<Float, MamaOutput> {
	var inner:musescript.indicators.prim.Mama;
	var fastLimit:Float;
	var slowLimit:Float;

	public function new(fastLimit:Float, slowLimit:Float) {
		// prim/Mama throws on invalid (fast_limit, slow_limit), matching the
		// Rust Error::InvalidPeriod.
		inner = new musescript.indicators.prim.Mama(fastLimit, slowLimit);
		this.fastLimit = fastLimit;
		this.slowLimit = slowLimit;
	}

	/** Default `(0.5, 0.05)` parameters from Ehlers' original publication. */
	public static function classic():Mama {
		return new Mama(0.5, 0.05);
	}

	/** Configured `(fast_limit, slow_limit)`. */
	public function limits():{fast_limit:Float, slow_limit:Float} {
		return {fast_limit: fastLimit, slow_limit: slowLimit};
	}

	/** Current `(mama, fama)` pair if available. */
	public function value():Null<MamaOutput> {
		return inner.value();
	}

	public function update(input:Float):Null<MamaOutput> {
		return inner.update(input);
	}

	public function reset():Void {
		inner.reset();
	}

	public function warmupPeriod():Int return inner.warmupPeriod();
	public function isReady():Bool return inner.isReady();
	public function name():String return "MAMA";

	public static function spec():IndicatorSpec {
		return {
			name: "mama", args: [TSeries, TScalar, TScalar], ret: TObject([
				{name: "mama", ty: TScalar}, {name: "fama", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var fastLimit = IndicatorCache.floatArg(args, 1, 0.5);
				var slowLimit = IndicatorCache.floatArg(args, 2, 0.05);
				var key = "mama:" + series + ":" + fastLimit + ":" + slowLimit;
				var nanFill = { mama: Math.NaN, fama: Math.NaN };
				return IndicatorCache.evalSeries(h, key, series, nanFill,
					() -> new Mama(fastLimit, slowLimit), (i, v) -> (cast i : Mama).update(v));
			}
		};
	}
}
