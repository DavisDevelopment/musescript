package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.geom.SwingGraph;
import musescript.types.MuseType;

/**
 * Wedge (rising / falling) detector — ported from wickra-core's `Wedge`
 * (vendor/wickra/crates/wickra-core/src/indicators/wedge.rs).
 *
 * A pattern where both trendlines slope the same way but converge, signalling
 * exhaustion of the prevailing move. Evaluated from the last two swing highs
 * and lows:
 *
 *   rising wedge  : highs rising  AND lows rising,  lows rising faster  → -1
 *   falling wedge : highs falling AND lows falling, highs falling faster → +1
 *
 * Uses a 5% swing reversal threshold. Output is `+1.0` / `-1.0` / `0.0`;
 * never null. Swings via shared `SwingGraph`.
 */
class Wedge implements MuseIndicator<Bar, Float> {
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

		var highSlope = highNew - highOld;
		var lowSlope = lowNew - lowOld;

		if (highSlope > 0.0 && lowSlope > 0.0 && lowSlope > highSlope) {
			return -1.0;
		}
		if (highSlope < 0.0 && lowSlope < 0.0 && highSlope < lowSlope) {
			return 1.0;
		}
		return 0.0;
	}

	public function reset():Void {
		swing.reset();
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 5;
	public function isReady():Bool return hasEmitted;
	public function name():String return "Wedge";

	public static function spec():IndicatorSpec {
		return {
			name: "wedge", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "wedge", Math.NaN,
				() -> new Wedge(), (i, b) -> (cast i : Wedge).update(b))
		};
	}
}
