package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.geom.SwingGraph;
import musescript.types.MuseType;

/**
 * AB=CD harmonic pattern detector — ported from wickra-core's `Abcd`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/abcd.rs).
 *
 * The simplest four-point harmonic pattern: an A→B leg, a B→C retracement,
 * and a C→D leg that mirrors A→B in length. Returns `+1.0` (bullish, D a
 * swing low), `-1.0` (bearish, D a swing high), or `0.0` (no pattern).
 *
 * Uses a 5% swing reversal threshold for non-repainting pivot detection.
 * Swings via shared `SwingGraph`.
 */
class Abcd implements MuseIndicator<Bar, Float> {
	var swing:SwingGraph;
	var hasEmitted:Bool;

	public function new() {
		swing = new SwingGraph(0.05, 4);
		hasEmitted = false;
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
		var pa = swing.pivotAt(n - 4);
		var pb = swing.pivotAt(n - 3);
		var pc = swing.pivotAt(n - 2);
		var pd = swing.pivotAt(n - 1);

		var ab = Math.abs(pb.price - pa.price);
		var bc = Math.abs(pc.price - pb.price);
		var cd = Math.abs(pd.price - pc.price);

		// Ratios must fall in [0.382, 0.886] and [1.13, 2.618], legs within 10%.
		var bcRatioOk = bc / ab >= 0.382 && bc / ab <= 0.886;
		var cdRatioOk = cd / bc >= 1.13 && cd / bc <= 2.618;
		var legsEqual = approxEqual(ab, cd, 0.10);

		if (bcRatioOk && cdRatioOk && legsEqual) {
			return pd.direction < 0.0 ? 1.0 : -1.0;
		}
		return 0.0;
	}

	public function reset():Void {
		swing.reset();
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 5;
	public function isReady():Bool return hasEmitted;
	public function name():String return "Abcd";

	static inline function approxEqual(a:Float, b:Float, tol:Float):Bool {
		var scale = Math.max(Math.abs(a), Math.abs(b));
		if (scale < 2.2250738585072014e-308) scale = 2.2250738585072014e-308;
		return Math.abs(a - b) <= tol * scale;
	}

	public static function spec():IndicatorSpec {
		return {
			name: "abcd", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "abcd", Math.NaN,
				() -> new Abcd(), (i, b) -> (cast i : Abcd).update(b))
		};
	}
}
