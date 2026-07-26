package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.geom.SwingGraph;
import musescript.types.MuseType;

/**
 * Rectangle / Range detector — ported from wickra-core's `RectangleRange`
 * (vendor/wickra/crates/wickra-core/src/indicators/rectangle_range.rs).
 *
 * Price oscillating between a roughly horizontal support and resistance, a
 * mean-reversion (range-trading) structure. Recognised when the last two
 * highs and the last two lows are each flat within 3%:
 *
 *   flat highs (resistance) AND flat lows (support):
 *     last pivot a low  → +1  (a bounce off support — buy the range)
 *     last pivot a high → -1  (a rejection at resistance — sell the range)
 *
 * Uses a 5% swing reversal threshold. Output is `+1.0` / `-1.0` / `0.0`;
 * never null. Swings via shared `SwingGraph` (no private Array.shift tracker).
 */
class RectangleRange implements MuseIndicator<Bar, Float> {
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
		if (flatHighs && flatLows) {
			var lastIsHigh = swing.pivotAt(n - 1).direction > 0.0;
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
	public function name():String return "RectangleRange";

	public static function spec():IndicatorSpec {
		return {
			name: "rectangle_range", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "rectangle_range", Math.NaN,
				() -> new RectangleRange(), (i, b) -> (cast i : RectangleRange).update(b))
		};
	}
}
