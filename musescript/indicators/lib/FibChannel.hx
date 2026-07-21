package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Fibonacci Channel output: base trendline and parallel offset levels. */
typedef FibChannelOutput = {
	var base:Float;
	var level618:Float;
	var level1000:Float;
	var level1618:Float;
}

/**
 * Fibonacci Channel — ported from wickra-core's `FibChannel`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/fib_channel.rs).
 *
 * From the last three confirmed pivots, the two same-direction outer pivots define
 * a sloped base trendline and the opposite middle pivot sets the channel width (its
 * signed distance from the base line). Parallel lines are then offset by Fibonacci
 * multiples of that width and reported at the current bar.
 *
 * Parameter-free; construction is infallible. Returns null until three pivots have confirmed.
 */
class FibChannel implements MuseIndicator<Bar, FibChannelOutput> {
	static inline var SWING_THRESHOLD = 0.05;
	static var RATIOS = [0.618, 1.0, 1.618];

	var swing:SwingTracker;

	public function new() {
		swing = new SwingTracker(SWING_THRESHOLD, 3);
	}

	public function update(candle:Bar):Null<FibChannelOutput> {
		swing.update(candle);
		return channel();
	}

	function channel():Null<FibChannelOutput> {
		var pivots = swing.getPivots();
		if (pivots.length < 3) return null;

		var p0 = pivots[0];
		var p1 = pivots[1];
		var p2 = pivots[2];

		// p0 and p2 are the same-direction outer pivots; their bars differ
		// strictly, so the slope denominator is non-zero.
		var slope = (p2.price - p0.price) / (p2.bar - p0.bar);

		var baseAt = function(bar:Int):Float {
			return p0.price + slope * (bar - p0.bar);
		};

		var width = p1.price - baseAt(p1.bar);
		var base = baseAt(swing.currentBar());

		return {
			base: base,
			level618: base + RATIOS[0] * width,
			level1000: base + RATIOS[1] * width,
			level1618: base + RATIOS[2] * width
		};
	}

	public function reset():Void {
		swing.reset();
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return swing.getPivots().length >= 3;
	public function name():String return "FibChannel";

	public static function spec():IndicatorSpec {
		return {
			name: "fib_channel", args: [], ret: TObject([
				{name: "base", ty: TScalar}, {name: "level618", ty: TScalar},
				{name: "level1000", ty: TScalar}, {name: "level1618", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				return IndicatorCache.evalBar(h, "fib_channel",
					{ base: Math.NaN, level618: Math.NaN, level1000: Math.NaN, level1618: Math.NaN },
					() -> new FibChannel(), (i, b) -> (cast i : FibChannel).update(b));
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
