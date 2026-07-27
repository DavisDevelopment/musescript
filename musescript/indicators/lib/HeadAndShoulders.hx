package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.geom.SwingGraph;
import musescript.types.MuseType;

/**
 * Head-and-Shoulders / Inverse detector — ported from wickra-core's
 * `HeadAndShoulders`
 * (vendor/wickra/crates/wickra-core/src/indicators/head_and_shoulders.rs).
 *
 * A five-pivot reversal pattern with a central extreme (the head) flanked by
 * two lower/higher shoulders at a similar level, joined by a roughly
 * horizontal neckline. Recognised on the bar that confirms the right
 * shoulder:
 *
 *   top (bearish, -1):     LS(high), Trough, Head(high), Trough, RS(high)
 *     Head > both shoulders ; LS ≈ RS ; Trough1 ≈ Trough2
 *   inverse (bullish, +1): LS(low), Peak, Head(low), Peak, RS(low)
 *     Head < both shoulders ; LS ≈ RS ; Peak1 ≈ Peak2
 *
 * Shoulders and neckline points must match within 3%. Uses a 5% swing
 * reversal threshold. Output is `-1.0` / `+1.0` / `0.0`; never null.
 * Swings via shared `SwingGraph`.
 */
class HeadAndShoulders implements MuseIndicator<Bar, Float> {
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
		var leftShoulder = swing.pivotAt(n - 5);
		var neck1 = swing.pivotAt(n - 4);
		var head = swing.pivotAt(n - 3);
		var neck2 = swing.pivotAt(n - 2);
		var rightShoulder = swing.pivotAt(n - 1);

		var shouldersMatch = approxEqual(leftShoulder.price, rightShoulder.price, 0.03);
		var necklineFlat = approxEqual(neck1.price, neck2.price, 0.03);
		var headIsPeak = head.price > leftShoulder.price && head.price > rightShoulder.price;
		var headIsTrough = head.price < leftShoulder.price && head.price < rightShoulder.price;
		var frameMatches = shouldersMatch && necklineFlat;

		if (rightShoulder.direction > 0.0) {
			// Head-and-shoulders top: head is the highest of the three highs.
			if (headIsPeak && frameMatches) {
				return -1.0;
			}
		} else if (headIsTrough && frameMatches) {
			// Inverse: head is the lowest of the three lows.
			return 1.0;
		}
		return 0.0;
	}

	public function reset():Void {
		swing.reset();
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 6;
	public function isReady():Bool return hasEmitted;
	public function name():String return "HeadAndShoulders";

	public static function spec():IndicatorSpec {
		return {
			name: "head_and_shoulders", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "head_and_shoulders", Math.NaN,
				() -> new HeadAndShoulders(), (i, b) -> (cast i : HeadAndShoulders).update(b))
		};
	}
}
