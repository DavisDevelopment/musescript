package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Golden pocket output: low/mid/high band of 0.618-0.65 retracement. */
typedef GoldenPocketOutput = {
	var low:Float;
	var mid:Float;
	var high:Float;
}

/**
 * Golden Pocket — ported from wickra-core's `GoldenPocket`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/golden_pocket.rs).
 *
 * The 0.618-0.65 retracement band of the most recent confirmed swing leg — the
 * "optimal trade entry" zone. Returns `None` until the first leg is complete.
 *
 * Uses a 5% swing reversal threshold for non-repainting pivot detection.
 */
class GoldenPocket implements MuseIndicator<Bar, GoldenPocketOutput> {
	var swing:SwingTracker;

	public function new() {
		swing = new SwingTracker(0.05, 2);
	}

	public function update(candle:Bar):Null<GoldenPocketOutput> {
		swing.update(candle);
		return zone();
	}

	function zone():Null<GoldenPocketOutput> {
		var pivots = swing.getPivots();
		if (pivots.length < 2) return null;

		var start = pivots[0].price;
		var end = pivots[1].price;
		var span = start - end;

		var edge_low = end + 0.618 * span;
		var edge_high = end + 0.65 * span;

		var low = Math.min(edge_low, edge_high);
		var high = Math.max(edge_low, edge_high);

		return {
			low: low,
			mid: (low + high) / 2.0,
			high: high
		};
	}

	public function reset():Void {
		swing.reset();
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return swing.getPivots().length >= 2;
	public function name():String return "GoldenPocket";

	public static function spec():IndicatorSpec {
		return {
			name: "golden_pocket", args: [], ret: TObject([
				{name: "low", ty: TScalar},
				{name: "mid", ty: TScalar},
				{name: "high", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill:GoldenPocketOutput = {low: Math.NaN, mid: Math.NaN, high: Math.NaN};
				return IndicatorCache.evalBar(h, "golden_pocket", nanFill,
					() -> new GoldenPocket(), (i, b) -> (cast i : GoldenPocket).update(b));
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
