package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.geom.SwingGraph;
import musescript.types.MuseType;

/**
 * Flag / Pennant continuation chart pattern.
 * Ported from wickra-core's `FlagPennant`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/flag_pennant.rs).
 *
 * Built on confirmed swing pivots (5% threshold); evaluated from the last three
 * pivots `pole_start → pole_end → consolidation`:
 *
 * - pole = |pole_end − pole_start| (the sharp impulse)
 * - pullback = |consolidation − pole_end| (the shallow counter-move)
 * - qualifies when pullback < 0.5 · pole
 * - bull flag: pole_end is a swing high → +1 (up-pole, continuation up)
 * - bear flag: pole_end is a swing low → -1 (down-pole, continuation down)
 * - otherwise → 0
 *
 * The detector fires on the bar that confirms the consolidation pivot (the flag
 * is complete; the breakout is expected to follow). Output is always a Float
 * (+1.0 / -1.0 / 0.0); never null. Swings via shared `SwingGraph`.
 */
class FlagPennant implements MuseIndicator<Bar, Float> {
	var swing:SwingGraph;
	var hasEmitted:Bool;
	static inline var MAX_RETRACE_FRACTION = 0.5;

	public function new() {
		swing = new SwingGraph(0.05, 3);
		hasEmitted = false;
	}

	public function update(bar:Bar):Null<Float> {
		hasEmitted = true;
		if (!swing.update(bar)) {
			return 0.0;
		}

		var n = swing.pivotCount();
		if (n < 3) {
			return 0.0;
		}

		var poleStart = swing.pivotAt(n - 3);
		var poleEnd = swing.pivotAt(n - 2);
		var consolidation = swing.pivotAt(n - 1);

		var pole = Math.abs(poleEnd.price - poleStart.price);
		var pullback = Math.abs(consolidation.price - poleEnd.price);

		if (pole > 0.0 && pullback < MAX_RETRACE_FRACTION * pole) {
			// pole_end a high → up-pole → bull flag; a low → bear flag.
			return poleEnd.direction > 0.0 ? 1.0 : -1.0;
		}
		return 0.0;
	}

	public function reset():Void {
		swing.reset();
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 4;
	public function isReady():Bool return hasEmitted;
	public function name():String return "FLAGPENN";

	public static function spec():IndicatorSpec {
		return {
			name: "flag_pennant", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				return IndicatorCache.evalBar(h, "flag_pennant", Math.NaN,
					() -> new FlagPennant(), (i, b) -> (cast i : FlagPennant).update(b));
			}
		};
	}
}
