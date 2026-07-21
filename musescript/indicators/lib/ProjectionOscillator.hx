package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.lib.ProjectionBands;
import musescript.types.MuseType;

/**
 * Projection Oscillator (Mel Widner) — ported from wickra-core's
 * `ProjectionOscillator`
 * (vendor/wickra/crates/wickra-core/src/indicators/projection_oscillator.rs).
 *
 * The close's position inside the ProjectionBands envelope, scaled to 0..100:
 *
 *   PO = 100 · (close − lower) / (upper − lower)
 *
 * PO = 0 means the close sits on the lower band, 100 on the upper, 50 at the
 * midline. When the bands collapse (upper == lower, a zero-range window) the
 * position is undefined and the oscillator returns the neutral 50.0.
 */
class ProjectionOscillator implements MuseIndicator<Bar, Float> {
	var bands:ProjectionBands;

	public function new(period:Int) {
		bands = new ProjectionBands(period);
	}

	public function update(bar:Bar):Null<Float> {
		var out = bands.update(bar);
		if (out == null) return null;
		var width = out.upper - out.lower;
		if (width == 0.0) return 50.0;
		return 100.0 * (bar.close - out.lower) / width;
	}

	public function reset():Void {
		bands.reset();
	}

	public function warmupPeriod():Int return bands.warmupPeriod();
	public function isReady():Bool return bands.isReady();
	public function name():String return "ProjectionOscillator";

	public static function spec():IndicatorSpec {
		return {
			name: "projection_oscillator", args: [TWindow], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				var key = "projection_oscillator:" + p;
				return IndicatorCache.evalBar(h, key, Math.NaN,
					() -> new ProjectionOscillator(p), (i, b) -> (cast i : ProjectionOscillator).update(b));
			}
		};
	}
}
