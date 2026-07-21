package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Fibonacci Time Zones output: on-zone flag and bars to next zone. */
typedef FibTimeZonesOutput = {
	var onZone:Float;
	var barsToNext:Float;
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
 * Fibonacci Time Zones — vertical markers at Fibonacci bar-distances from the
 * most recent swing pivot.
 * Ported from wickra-core's `FibTimeZones`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/fib_time_zones.rs).
 *
 * Anchored on the most recent confirmed swing pivot, the Fibonacci sequence
 * `1, 2, 3, 5, 8, 13, …` marks bars at which trend changes are classically
 * anticipated. Reports whether the current bar is on a zone and how many bars
 * remain until the next one.
 */
class FibTimeZones implements MuseIndicator<Bar, FibTimeZonesOutput> {
	var swing:SwingTracker;
	var barsSeen:Int;

	public function new() {
		swing = new SwingTracker(0.05, 2);
		barsSeen = 0;
	}

	public function update(bar:Bar):Null<FibTimeZonesOutput> {
		swing.update(bar);
		barsSeen++;
		return zones();
	}

	function zones():Null<FibTimeZonesOutput> {
		var pivots = swing.getPivots();
		if (pivots.length == 0) return null;

		var anchor = pivots[pivots.length - 1];
		var distance = (barsSeen - 1) - anchor.bar; // currentBar() = barsSeen - 1

		// Walk the time-zone sequence 1, 2, 3, 5, 8, …
		var lo = 1;
		var hi = 2;
		var onZone = false;
		while (lo <= distance) {
			if (lo == distance) {
				onZone = true;
			}
			var next = lo + hi;
			lo = hi;
			hi = next;
		}

		return {
			onZone: onZone ? 1.0 : 0.0,
			barsToNext: lo - distance
		};
	}

	public function reset():Void {
		swing.reset();
		barsSeen = 0;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return swing.getPivots().length > 0;
	public function name():String return "FIBTIMEZ";

	public static function spec():IndicatorSpec {
		return {
			name: "fib_time_zones", args: [], ret: TObject([
				{name: "onZone", ty: TScalar}, {name: "barsToNext", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill = {onZone: Math.NaN, barsToNext: Math.NaN};
				return IndicatorCache.evalBar(h, "fib_time_zones", nanFill,
					() -> new FibTimeZones(), (i, b) -> (cast i : FibTimeZones).update(b));
			}
		};
	}
}
