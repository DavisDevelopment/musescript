package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.geom.SwingGraph;
import musescript.types.MuseType;

/**
 * Triangle (ascending / descending / symmetrical) detector — ported from
 * wickra-core's `Triangle`
 * (vendor/wickra/crates/wickra-core/src/indicators/triangle.rs).
 *
 * A consolidation pattern bounded by two converging trendlines, detected from
 * the two most recent swing highs and lows:
 *
 *   ascending   : flat highs    + rising lows  → +1 (bullish bias)
 *   descending  : falling highs + flat lows    → -1 (bearish bias)
 *   symmetrical : falling highs + rising lows  → +1 if the last pivot is a
 *                 low (an up-bounce), else -1
 *
 * "Flat" means within 3%; "rising"/"falling" means beyond that tolerance.
 * Uses a 5% swing reversal threshold. Output is `+1.0` / `-1.0` / `0.0`;
 * never null. Swings via shared `SwingGraph`.
 */
class Triangle implements MuseIndicator<Bar, Float> {
	var swing:SwingGraph;
	var hasEmitted:Bool;

	public function new() {
		swing = new SwingGraph(0.05, 4);
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
		if (n < 4) {
			return 0.0;
		}

		var highOld:Float, highNew:Float, lowOld:Float, lowNew:Float;
		if (swing.pivotAt(n - 1).direction > 0.0) {
			highOld = swing.pivotAt(n - 3).price;
			highNew = swing.pivotAt(n - 1).price;
			lowOld = swing.pivotAt(n - 4).price;
			lowNew = swing.pivotAt(n - 2).price;
		} else {
			highOld = swing.pivotAt(n - 4).price;
			highNew = swing.pivotAt(n - 2).price;
			lowOld = swing.pivotAt(n - 3).price;
			lowNew = swing.pivotAt(n - 1).price;
		}

		var flatHighs = approxEqual(highOld, highNew, 0.03);
		var flatLows = approxEqual(lowOld, lowNew, 0.03);
		var risingLows = lowNew > lowOld * (1.0 + 0.03);
		var fallingHighs = highNew < highOld * (1.0 - 0.03);
		var lastIsHigh = swing.pivotAt(n - 1).direction > 0.0;

		if (flatHighs && risingLows) {
			return 1.0; // ascending
		}
		if (fallingHighs && flatLows) {
			return -1.0; // descending
		}
		if (fallingHighs && risingLows) {
			return lastIsHigh ? -1.0 : 1.0;
		}
		return 0.0;
	}

	public function reset():Void {
		swing.reset();
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 5;
	public function isReady():Bool return hasEmitted;
	public function name():String return "Triangle";

	public static function spec():IndicatorSpec {
		return {
			name: "triangle", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "triangle", Math.NaN,
				() -> new Triangle(), (i, b) -> (cast i : Triangle).update(b))
		};
	}
}
