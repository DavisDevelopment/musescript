package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
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
 */
class HeadAndShoulders implements MuseIndicator<Bar, Float> {
	var swing:SwingTracker;
	var hasEmitted:Bool;

	public function new() {
		swing = new SwingTracker(0.05, 5);
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
		if (pivots.length < 5) {
			return 0.0;
		}
		var n = pivots.length;
		var leftShoulder = pivots[n - 5];
		var neck1 = pivots[n - 4];
		var head = pivots[n - 3];
		var neck2 = pivots[n - 2];
		var rightShoulder = pivots[n - 1];

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
