package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Three Drives harmonic pattern detector — ported from wickra-core's
 * `ThreeDrives` (vendor/wickra/crates/wickra-core/src/indicators/three_drives.rs).
 *
 * A symmetric harmonic pattern of two visible drives separated by two
 * retracements, read from the last five pivots X-A-B-C-D (the two drive legs
 * are A→B and C→D):
 *
 *   AB / XA in [1.13, 1.75]  (drive 1 extends the prior retracement)
 *   CD / BC in [1.13, 1.75]  (drive 2 extends symmetrically)
 *   AB ≈ CD (within 20%)     (the two drives are similar in size)
 *   XA ≈ BC (within 30%)     (the two retracements are similar)
 *
 * Returns `+1.0` (bullish, terminal D a swing low — drives down), `-1.0`
 * (bearish, drives up), or `0.0` (no pattern). Uses a 5% swing threshold.
 */
class ThreeDrives implements MuseIndicator<Bar, Float> {
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
		var px = pivots[n - 5].price;
		var pa = pivots[n - 4].price;
		var pb = pivots[n - 3].price;
		var pc = pivots[n - 2].price;
		var pd = pivots[n - 1].price;
		var bullish = pivots[n - 1].direction < 0.0;

		var xa = Math.abs(pa - px);
		var ab = Math.abs(pb - pa);
		var bc = Math.abs(pc - pb);
		var cd = Math.abs(pd - pc);

		var extensions = ab / xa >= 1.13 && ab / xa <= 1.75
			&& cd / bc >= 1.13 && cd / bc <= 1.75;
		var symmetric = approxEqual(ab, cd, 0.20) && approxEqual(xa, bc, 0.30);

		if (extensions && symmetric) {
			return bullish ? 1.0 : -1.0;
		}
		return 0.0;
	}

	public function reset():Void {
		swing.reset();
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 6;
	public function isReady():Bool return hasEmitted;
	public function name():String return "ThreeDrives";

	public static function spec():IndicatorSpec {
		return {
			name: "three_drives", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "three_drives", Math.NaN,
				() -> new ThreeDrives(), (i, b) -> (cast i : ThreeDrives).update(b))
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
