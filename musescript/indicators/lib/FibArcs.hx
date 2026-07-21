package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Fibonacci Arc prices at the current bar. */
typedef FibArcsOutput = {
	var arc382:Float;
	var arc500:Float;
	var arc618:Float;
}

/**
 * Fibonacci Arcs — ported from wickra-core's `FibArcs`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/fib_arcs.rs).
 *
 * Three arcs centred on the end of the most recent confirmed swing leg. Each arc
 * sits exactly on its retracement level at the leg's end bar and curves back toward
 * the swing-end price as time elapses, reaching it one leg-width later.
 *
 * Parameter-free; construction is infallible. Returns null until the first leg is complete.
 */
class FibArcs implements MuseIndicator<Bar, FibArcsOutput> {
	static inline var SWING_THRESHOLD = 0.05;
	static var RATIOS = [0.382, 0.5, 0.618];

	var swing:SwingTracker;

	public function new() {
		swing = new SwingTracker(SWING_THRESHOLD, 2);
	}

	public function update(candle:Bar):Null<FibArcsOutput> {
		swing.update(candle);
		return arcs();
	}

	function arcs():Null<FibArcsOutput> {
		var pivots = swing.getPivots();
		if (pivots.length < 2) return null;

		var start = pivots[0];
		var end = pivots[1];

		var spanBars = (end.bar - start.bar) * 1.0;
		var u = (swing.currentBar() - end.bar) * 1.0 / spanBars;
		var curve = Math.sqrt(Math.max(0.0, 1.0 - u * u));

		var arc = function(r:Float):Float {
			return end.price + (start.price - end.price) * r * curve;
		};

		return {
			arc382: arc(RATIOS[0]),
			arc500: arc(RATIOS[1]),
			arc618: arc(RATIOS[2])
		};
	}

	public function reset():Void {
		swing.reset();
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return swing.getPivots().length >= 2;
	public function name():String return "FibArcs";

	public static function spec():IndicatorSpec {
		return {
			name: "fib_arcs", args: [], ret: TObject([
				{name: "arc382", ty: TScalar}, {name: "arc500", ty: TScalar}, {name: "arc618", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				return IndicatorCache.evalBar(h, "fib_arcs", { arc382: Math.NaN, arc500: Math.NaN, arc618: Math.NaN },
					() -> new FibArcs(), (i, b) -> (cast i : FibArcs).update(b));
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

	public function currentBar():Int {
		return barsSeen - 1;
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
