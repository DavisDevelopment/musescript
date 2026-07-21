package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Fibonacci Projection output: the C→D target zone of a measured move. */
typedef FibProjectionOutput = {
	var level618:Float;
	var level1000:Float;
	var level1618:Float;
	var level2618:Float;
}

private typedef Pivot = {
	var price:Float;
	var direction:Float;
	var bar:Int;
}

private typedef SwingState = {
	var direction:Float;
	var extreme:Float;
	var extremeBar:Int;
}

/** Non-repainting percent-threshold swing tracker with bounded pivot history. */
private class SwingTracker {
	var threshold:Float;
	var cap:Int;
	var barsSeen:Int;
	var state:Null<SwingState>;
	var pivots:Array<Pivot>;

	public function new(threshold:Float, cap:Int) {
		this.threshold = threshold;
		this.cap = cap;
		barsSeen = 0;
		state = null;
		pivots = [];
	}

	public function update(bar:Bar):Bool {
		var barIdx = barsSeen;
		barsSeen++;

		if (state == null) {
			state = { direction: 1.0, extreme: bar.high, extremeBar: barIdx };
			return false;
		}

		var s = state;
		if (s.direction > 0.0) {
			if (bar.high > s.extreme) {
				state = { direction: 1.0, extreme: bar.high, extremeBar: barIdx };
				return false;
			}
			if (bar.low <= s.extreme * (1.0 - threshold)) {
				push({ price: s.extreme, direction: 1.0, bar: s.extremeBar });
				state = { direction: -1.0, extreme: bar.low, extremeBar: barIdx };
				return true;
			}
			return false;
		} else {
			if (bar.low < s.extreme) {
				state = { direction: -1.0, extreme: bar.low, extremeBar: barIdx };
				return false;
			}
			if (bar.high >= s.extreme * (1.0 + threshold)) {
				push({ price: s.extreme, direction: -1.0, bar: s.extremeBar });
				state = { direction: 1.0, extreme: bar.high, extremeBar: barIdx };
				return true;
			}
			return false;
		}
	}

	function push(pivot:Pivot):Void {
		pivots.push(pivot);
		if (pivots.length > cap) pivots.shift();
	}

	public function getPivots():Array<Pivot> return pivots;

	public function reset():Void {
		barsSeen = 0;
		state = null;
		pivots = [];
	}
}

/**
 * Fibonacci Projection — a measured move from the last three swing pivots.
 * Ported from wickra-core's `FibProjection`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/fib_projection.rs).
 *
 * Reads the last three confirmed swing pivots as the points A, B and C of a
 * measured move and projects the A→B leg from C at the canonical ratios — the
 * price targets for the C→D leg.
 */
class FibProjection implements MuseIndicator<Bar, FibProjectionOutput> {
	var swing:SwingTracker;
	static var RATIOS = [0.618, 1.0, 1.618, 2.618];

	public function new() {
		swing = new SwingTracker(0.05, 3);
	}

	public function update(bar:Bar):Null<FibProjectionOutput> {
		swing.update(bar);
		return levels();
	}

	function levels():Null<FibProjectionOutput> {
		var pivots = swing.getPivots();
		if (pivots.length < 3) return null;

		var a = pivots[0].price;
		var b = pivots[1].price;
		var c = pivots[2].price;

		var project = function(p:Float):Float {
			return c + p * (b - a);
		};

		return {
			level618: project(RATIOS[0]),
			level1000: project(RATIOS[1]),
			level1618: project(RATIOS[2]),
			level2618: project(RATIOS[3])
		};
	}

	public function reset():Void {
		swing.reset();
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return swing.getPivots().length >= 3;
	public function name():String return "FIBPROJ";

	public static function spec():IndicatorSpec {
		return {
			name: "fib_projection", args: [], ret: TObject([
				{name: "level618", ty: TScalar}, {name: "level1000", ty: TScalar},
				{name: "level1618", ty: TScalar}, {name: "level2618", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill = {level618: Math.NaN, level1000: Math.NaN, level1618: Math.NaN, level2618: Math.NaN};
				return IndicatorCache.evalBar(h, "fib_projection", nanFill,
					() -> new FibProjection(), (i, b) -> (cast i : FibProjection).update(b));
			}
		};
	}
}
