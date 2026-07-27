package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.geom.SwingGraph;
import musescript.types.MuseType;

/**
 * Cup-and-Handle / Inverse detector — ported from wickra-core's
 * `CupAndHandle`
 * (vendor/wickra/crates/wickra-core/src/indicators/cup_and_handle.rs).
 *
 * A rounded base (the cup) followed by a shallow pullback (the handle) near
 * the rim, then a breakout in the cup's direction. Read from the last four
 * pivots:
 *
 *   cup-and-handle (bullish, +1): Rim(high), Cup(low), Rim(high), Handle(low)
 *     rims match (±3%) ; handle low ABOVE the cup low and below the right rim
 *   inverse (bearish, -1):        Rim(low), Cap(high), Rim(low), Handle(high)
 *     rims match ; handle high BELOW the cap high and above the right rim
 *
 * Uses a 5% swing reversal threshold. Output is `+1.0` / `-1.0` / `0.0`;
 * never null. Swings via shared `SwingGraph`.
 */
class CupAndHandle implements MuseIndicator<Bar, Float> {
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
		var rimLeft = swing.pivotAt(n - 4);
		var extreme = swing.pivotAt(n - 3);
		var rimRight = swing.pivotAt(n - 2);
		var handle = swing.pivotAt(n - 1);
		var rimsMatch = approxEqual(rimLeft.price, rimRight.price, 0.03);

		if (handle.direction < 0.0) {
			// Bullish cup-and-handle: rims are highs, cup is the low between them,
			// handle is a shallow low above the cup but below the right rim.
			if (rimsMatch && handle.price > extreme.price && handle.price < rimRight.price) {
				return 1.0;
			}
		} else if (rimsMatch && handle.price < extreme.price && handle.price > rimRight.price) {
			// Inverse: rims are lows, cap is the high, handle a shallow high.
			return -1.0;
		}
		return 0.0;
	}

	public function reset():Void {
		swing.reset();
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 5;
	public function isReady():Bool return hasEmitted;
	public function name():String return "CupAndHandle";

	public static function spec():IndicatorSpec {
		return {
			name: "cup_and_handle", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "cup_and_handle", Math.NaN,
				() -> new CupAndHandle(), (i, b) -> (cast i : CupAndHandle).update(b))
		};
	}
}
