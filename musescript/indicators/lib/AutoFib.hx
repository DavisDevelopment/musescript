package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Auto-Fibonacci output: the standard ratio levels over the dominant recent swing leg. */
typedef AutoFibOutput = {
	var level0:Float;
	var level236:Float;
	var level382:Float;
	var level500:Float;
	var level618:Float;
	var level786:Float;
	var level1000:Float;
}

/**
 * Auto-Fibonacci — ported from wickra-core's `AutoFib`
 * (vendor/wickra/crates/wickra-core/src/indicators/auto_fib.rs).
 *
 * Like FibRetracement, but instead of always using the immediate last leg it
 * scans the last six confirmed pivots and anchors the retracement on the
 * single largest-magnitude leg among them — the dominant swing the market is
 * most likely respecting.
 *
 * Parameter-free; returns `null` until two pivots have confirmed. Uses a 5%
 * swing reversal threshold for non-repainting pivot detection.
 */
class AutoFib implements MuseIndicator<Bar, AutoFibOutput> {
	var swing:SwingTracker;

	public function new() {
		swing = new SwingTracker(0.05, 6);
	}

	public function update(candle:Bar):Null<AutoFibOutput> {
		swing.update(candle);
		return levels();
	}

	function levels():Null<AutoFibOutput> {
		var pivots = swing.getPivots();
		if (pivots.length < 2) return null;

		// The dominant leg: the largest-magnitude adjacent pivot pair.
		// (Rust max_by keeps the LAST of equal maxima, hence >=.)
		var bestIdx = 0;
		var bestMag = -1.0;
		for (i in 0...pivots.length - 1) {
			var mag = Math.abs(pivots[i].price - pivots[i + 1].price);
			if (mag >= bestMag) {
				bestMag = mag;
				bestIdx = i;
			}
		}
		var start = pivots[bestIdx].price;
		var end = pivots[bestIdx + 1].price;
		function level(r:Float):Float return end + r * (start - end);
		return {
			level0: level(0.0),
			level236: level(0.236),
			level382: level(0.382),
			level500: level(0.5),
			level618: level(0.618),
			level786: level(0.786),
			level1000: level(1.0)
		};
	}

	public function reset():Void {
		swing.reset();
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return swing.getPivots().length >= 2;
	public function name():String return "AutoFib";

	public static function spec():IndicatorSpec {
		return {
			name: "auto_fib", args: [], ret: TObject([
				{name: "level0", ty: TScalar}, {name: "level236", ty: TScalar}, {name: "level382", ty: TScalar},
				{name: "level500", ty: TScalar}, {name: "level618", ty: TScalar}, {name: "level786", ty: TScalar},
				{name: "level1000", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill = {
					level0: Math.NaN, level236: Math.NaN, level382: Math.NaN, level500: Math.NaN,
					level618: Math.NaN, level786: Math.NaN, level1000: Math.NaN
				};
				return IndicatorCache.evalBar(h, "auto_fib", nanFill,
					() -> new AutoFib(), (i, b) -> (cast i : AutoFib).update(b));
			}
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
