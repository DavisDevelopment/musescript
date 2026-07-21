package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Fibonacci Fan output: the three fan lines evaluated at current bar. */
typedef FibFanOutput = {
	var fan382:Float;
	var fan500:Float;
	var fan618:Float;
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
 * Fibonacci Fan — trendlines fanning from a swing start through the
 * retracement levels at the swing end, extended to the current bar.
 * Ported from wickra-core's `FibFan`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/fib_fan.rs).
 *
 * Anchored at the start of the most recent confirmed swing leg, three lines fan
 * out through the 38.2% / 50% / 61.8% retracement levels located at the leg's
 * end bar, then extend to the current bar.
 */
class FibFan implements MuseIndicator<Bar, FibFanOutput> {
	var swing:SwingTracker;
	var barsSeen:Int;
	static var RATIOS = [0.382, 0.5, 0.618];

	public function new() {
		swing = new SwingTracker(0.05, 2);
		barsSeen = 0;
	}

	public function update(bar:Bar):Null<FibFanOutput> {
		swing.update(bar);
		barsSeen++;
		return fan();
	}

	function fan():Null<FibFanOutput> {
		var pivots = swing.getPivots();
		if (pivots.length < 2) return null;

		var start = pivots[0];
		var end = pivots[1];
		var spanBars = end.bar - start.bar;
		if (spanBars <= 0) return null;
		var elapsed = barsSeen - 1 - start.bar; // currentBar() = barsSeen - 1
		var progress = elapsed / spanBars;

		var line = function(r:Float):Float {
			return start.price + r * (end.price - start.price) * progress;
		};

		return {
			fan382: line(RATIOS[0]),
			fan500: line(RATIOS[1]),
			fan618: line(RATIOS[2])
		};
	}

	public function reset():Void {
		swing.reset();
		barsSeen = 0;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return swing.getPivots().length >= 2;
	public function name():String return "FIBFAN";

	public static function spec():IndicatorSpec {
		return {
			name: "fib_fan", args: [], ret: TObject([
				{name: "fan382", ty: TScalar}, {name: "fan500", ty: TScalar}, {name: "fan618", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill = {fan382: Math.NaN, fan500: Math.NaN, fan618: Math.NaN};
				return IndicatorCache.evalBar(h, "fib_fan", nanFill,
					() -> new FibFan(), (i, b) -> (cast i : FibFan).update(b));
			}
		};
	}
}
