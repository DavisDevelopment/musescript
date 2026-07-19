package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
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
 */
class Abcd implements MuseIndicator<Bar, Float> {
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
		var len = pivots.length;
		var pa = pivots[len - 4];
		var pb = pivots[len - 3];
		var pc = pivots[len - 2];
		var pd = pivots[len - 1];

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
