package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.geom.SwingGraph;
import musescript.types.MuseType;

/** Approximate equality for swing levels (within tolerance fraction). */
private function approxEqual(a:Float, b:Float, tol:Float):Bool {
	var scale = Math.max(Math.abs(a), Math.abs(b));
	if (scale < 1.0e-12) scale = 1.0e-12;
	return Math.abs(a - b) <= tol * scale;
}

/**
 * Double Top / Double Bottom — ported from wickra-core's `DoubleTopBottom`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/double_top_bottom.rs).
 *
 * A two-peak (or two-trough) reversal pattern detector. Tracks confirmed swing pivots
 * using a non-repainting percent-threshold zig-zag. A pattern is recognized on the bar
 * that confirms the second matching extreme:
 *
 * ```
 * double top    : … High₁ , Low , High₂   with  High₁ ≈ High₂   → -1 (bearish)
 * double bottom : … Low₁  , High , Low₂    with  Low₁  ≈ Low₂    → +1 (bullish)
 * ```
 *
 * Two extremes count as the same level when within 3% of each other.
 * Output is `+1.0` for double bottom, `-1.0` for double top, `0.0` otherwise.
 * Unlike most indicators, this never returns null (candlestick-pattern convention).
 * Swings via shared `SwingGraph`.
 */
class DoubleTopBottom implements MuseIndicator<Bar, Float> {
	var swing:SwingGraph;
	var hasEmitted:Bool;

	static inline var SWING_THRESHOLD:Float = 0.05;
	static inline var LEVEL_TOLERANCE:Float = 0.03;

	public function new() {
		swing = new SwingGraph(SWING_THRESHOLD, 3);
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

		var first = swing.pivotAt(n - 3);
		var last = swing.pivotAt(n - 1);

		if (approxEqual(first.price, last.price, LEVEL_TOLERANCE)) {
			// `last` is the just-confirmed extreme: a high → double top (bearish),
			// a low → double bottom (bullish).
			return if (last.direction > 0.0) -1.0 else 1.0;
		}

		return 0.0;
	}

	public function reset():Void {
		swing.reset();
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 5;
	public function isReady():Bool return hasEmitted;
	public function name():String return "DoubleTopBottom";

	public static function spec():IndicatorSpec {
		return {
			name: "double_top_bottom", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				return IndicatorCache.evalBar(h, "double_top_bottom", 0.0,
					() -> new DoubleTopBottom(), (i, b) -> (cast i : DoubleTopBottom).update(b));
			}
		};
	}
}
