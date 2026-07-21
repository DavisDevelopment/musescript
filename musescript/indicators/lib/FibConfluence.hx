package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Fibonacci Confluence output: the densest cluster price and strength. */
typedef FibConfluenceOutput = {
	var price:Float;
	var strength:Float;
}

private typedef Pivot = {
	var price:Float;
	var direction:Float; // +1.0 for high, -1.0 for low
	var bar:Int;
}

private typedef SwingState = {
	var direction:Float; // +1.0 tracking high, -1.0 tracking low
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

	public function currentBar():Int return barsSeen - 1;

	public function reset():Void {
		barsSeen = 0;
		state = null;
		pivots = [];
	}
}

private function approxEqual(a:Float, b:Float, tol:Float):Bool {
	var scale = Math.max(Math.abs(a), Math.abs(b));
	if (scale < 1.0e-12) scale = 1.0e-12;
	return Math.abs(a - b) <= tol * scale;
}

/**
 * Fibonacci Confluence — the strongest retracement cluster across recent legs.
 * Ported from wickra-core's `FibConfluence`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/fib_confluence.rs).
 *
 * Computes the 38.2% / 50% / 61.8% retracement prices of every leg among the
 * last six confirmed pivots, then reports the densest price cluster — where
 * levels from different legs stack up. `price` is the cluster mean; `strength`
 * is how many levels it gathers.
 */
class FibConfluence implements MuseIndicator<Bar, FibConfluenceOutput> {
	var swing:SwingTracker;
	static inline var PIVOT_HISTORY = 6;
	static var RATIOS = [0.382, 0.5, 0.618];

	public function new() {
		swing = new SwingTracker(0.05, PIVOT_HISTORY);
	}

	public function update(bar:Bar):Null<FibConfluenceOutput> {
		swing.update(bar);
		return confluence();
	}

	function confluence():Null<FibConfluenceOutput> {
		var pivots = swing.getPivots();
		if (pivots.length < 3) return null;

		// Collect retracement levels from all legs
		var levels:Array<Float> = [];
		var i = 0;
		while (i < pivots.length - 1) {
			var start = pivots[i].price;
			var end = pivots[i + 1].price;
			for (r in RATIOS) {
				levels.push(end + r * (start - end));
			}
			i++;
		}

		// Find the densest cluster
		var maxCount = 0;
		var maxTotal = 0.0;
		for (center in levels) {
			var members:Array<Float> = [];
			for (x in levels) {
				if (approxEqual(x, center, 0.03)) {
					members.push(x);
				}
			}
			if (members.length > maxCount) {
				maxCount = members.length;
				var sum = 0.0;
				for (m in members) sum += m;
				maxTotal = sum;
			}
		}

		if (maxCount == 0) return null;
		return {
			price: maxTotal / maxCount,
			strength: maxCount
		};
	}

	public function reset():Void {
		swing.reset();
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return swing.getPivots().length >= 3;
	public function name():String return "FIBCONF";

	public static function spec():IndicatorSpec {
		return {
			name: "fib_confluence", args: [], ret: TObject([
				{name: "price", ty: TScalar}, {name: "strength", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill = {price: Math.NaN, strength: Math.NaN};
				return IndicatorCache.evalBar(h, "fib_confluence", nanFill,
					() -> new FibConfluence(), (i, b) -> (cast i : FibConfluence).update(b));
			}
		};
	}
}
