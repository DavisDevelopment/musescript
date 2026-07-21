package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
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
 * never null.
 */
class Wedge implements MuseIndicator<Bar, Float> {
	var swing:SwingTracker;
	var hasEmitted:Bool;

	public function new() {
		swing = new SwingTracker(0.05, 4);
		hasEmitted = false;
	}

	public function update(candle:Bar):Null<Float> {
		hasEmitted = true;
		if (!swing.update(candle)) {
			return 0.0;
		}
		var pivots = swing.getPivots();
		if (pivots.length < 4) {
			return 0.0;
		}

		// recent_legs: the two most recent swing highs and lows from the last
		// four (strictly alternating) pivots.
		var n = pivots.length;
		var highOld:Float, highNew:Float, lowOld:Float, lowNew:Float;
		if (pivots[n - 1].direction > 0.0) {
			highOld = pivots[n - 3].price;
			highNew = pivots[n - 1].price;
			lowOld = pivots[n - 4].price;
			lowNew = pivots[n - 2].price;
		} else {
			highOld = pivots[n - 4].price;
			highNew = pivots[n - 2].price;
			lowOld = pivots[n - 3].price;
			lowNew = pivots[n - 1].price;
		}

		var highSlope = highNew - highOld;
		var lowSlope = lowNew - lowOld;

		// Rising wedge: both lines slope up, lower line steeper (converging) → bearish.
		if (highSlope > 0.0 && lowSlope > 0.0 && lowSlope > highSlope) {
			return -1.0;
		}
		// Falling wedge: both lines slope down, upper line steeper → bullish.
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

/** Internal Pivot structure: price, direction (1.0/-1.0), bar index. */
private class Pivot {
	public var price:Float;
	public var direction:Float;
	public var bar:Int;

	public function new(price:Float, direction:Float, bar:Int) {
		this.price = price;
		this.direction = direction;
		this.bar = bar;
	}
}

/** Internal swing tracker: non-repainting percent-threshold swing detector. */
private class SwingTracker {
	var threshold:Float;
	var cap:Int;
	var barsSeen:Int;
	var state:Null<SwingState>;
	var pivots:Array<Pivot>;

	public function new(threshold:Float, cap:Int) {
		this.threshold = threshold;
		this.cap = cap;
		reset();
	}

	public function update(candle:Bar):Bool {
		var bar = barsSeen;
		barsSeen++;

		if (state == null) {
			// Bootstrap: seed an uptrend tracking the first candle's high.
			state = {
				direction: 1.0,
				extreme: candle.high,
				extremeBar: bar
			};
			return false;
		}

		var s = state;
		if (s.direction > 0.0) {
			// Tracking a high.
			if (candle.high > s.extreme) {
				// Extend the candidate high.
				state = {
					direction: 1.0,
					extreme: candle.high,
					extremeBar: bar
				};
				return false;
			}
			if (candle.low <= s.extreme * (1.0 - threshold)) {
				// Confirm the swing high; flip to tracking this bar's low.
				pushPivot(new Pivot(s.extreme, 1.0, s.extremeBar));
				state = {
					direction: -1.0,
					extreme: candle.low,
					extremeBar: bar
				};
				return true;
			}
			return false;
		} else {
			// Tracking a low.
			if (candle.low < s.extreme) {
				// Extend the candidate low.
				state = {
					direction: -1.0,
					extreme: candle.low,
					extremeBar: bar
				};
				return false;
			}
			if (candle.high >= s.extreme * (1.0 + threshold)) {
				// Confirm the swing low; flip to tracking this bar's high.
				pushPivot(new Pivot(s.extreme, -1.0, s.extremeBar));
				state = {
					direction: 1.0,
					extreme: candle.high,
					extremeBar: bar
				};
				return true;
			}
			return false;
		}
	}

	public function reset():Void {
		barsSeen = 0;
		state = null;
		pivots = [];
	}

	public function getPivots():Array<Pivot> {
		return pivots;
	}

	function pushPivot(pivot:Pivot):Void {
		pivots.push(pivot);
		if (pivots.length > cap) {
			pivots.shift();
		}
	}
}

private typedef SwingState = {
	var direction:Float;
	var extreme:Float;
	var extremeBar:Int;
}
