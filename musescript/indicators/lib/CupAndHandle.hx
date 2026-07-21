package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
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
 * never null.
 */
class CupAndHandle implements MuseIndicator<Bar, Float> {
	var swing:SwingTracker;
	var hasEmitted:Bool;

	public function new() {
		swing = new SwingTracker(0.05, 4);
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
		var pivots = swing.getPivots();
		if (pivots.length < 4) {
			return 0.0;
		}
		var n = pivots.length;
		var rimLeft = pivots[n - 4];
		var extreme = pivots[n - 3];
		var rimRight = pivots[n - 2];
		var handle = pivots[n - 1];
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
