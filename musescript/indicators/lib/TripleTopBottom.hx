package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.geom.SwingGraph;
import musescript.types.MuseType;

/**
 * Triple Top / Triple Bottom detector — ported from wickra-core's
 * `TripleTopBottom`
 * (vendor/wickra/crates/wickra-core/src/indicators/triple_top_bottom.rs).
 *
 * A three-peak (or three-trough) reversal pattern, a stronger variant of the
 * double top/bottom. Recognised on the bar that confirms the THIRD matching
 * extreme:
 *
 *   triple top    : High1, Low, High2, Low, High3   High1 ≈ High2 ≈ High3 → -1
 *   triple bottom : Low1, High, Low2, High, Low3    Low1 ≈ Low2 ≈ Low3    → +1
 *
 * The three same-direction extremes (positions n-5, n-3, n-1 in the pivot
 * history) must all lie within 3% of one another. Uses a 5% swing reversal
 * threshold. Output is `+1.0` / `-1.0` / `0.0`; never null.
 * Swings via shared `SwingGraph`.
 */
class TripleTopBottom implements MuseIndicator<Bar, Float> {
	var swing:SwingGraph;
	var hasEmitted:Bool;

	public function new() {
		swing = new SwingGraph(0.05, 5);
		hasEmitted = false;
	}

	/** Relative-tolerance equality, mirroring pattern_swing::approx_equal. */
	static function approxEqual(a:Float, b:Float, tol:Float):Bool {
		var scale = Math.max(Math.max(Math.abs(a), Math.abs(b)), 2.2250738585072014e-308);
		return Math.abs(a - b) <= tol * scale;
	}

	public function update(candle:Bar):Null<Float> {
		hasEmitted = true;
		if (!swing.update(candle)) {
			return 0.0;
		}
		var n = swing.pivotCount();
		if (n < 5) {
			return 0.0;
		}
		var first = swing.pivotAt(n - 5);
		var middle = swing.pivotAt(n - 3);
		var last = swing.pivotAt(n - 1);
		var outerMatch = approxEqual(first.price, middle.price, 0.03);
		var innerMatch = approxEqual(middle.price, last.price, 0.03);
		if (outerMatch && innerMatch) {
			return last.direction > 0.0 ? -1.0 : 1.0;
		}
		return 0.0;
	}

	public function reset():Void {
		swing.reset();
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 6;
	public function isReady():Bool return hasEmitted;
	public function name():String return "TripleTopBottom";

	public static function spec():IndicatorSpec {
		return {
			name: "triple_top_bottom", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "triple_top_bottom", Math.NaN,
				() -> new TripleTopBottom(), (i, b) -> (cast i : TripleTopBottom).update(b))
		};
	}
}
