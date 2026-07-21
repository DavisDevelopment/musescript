package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Shark harmonic pattern detector — ported from wickra-core's `Shark`
 * (vendor/wickra/crates/wickra-core/src/indicators/shark.rs).
 *
 * A 5-point (X-A-B-C-D) harmonic pattern characterised by an EXPANSION leg
 * (AB longer than XA) and a 0.886–1.13 D completion:
 *
 *   AB / XA in [1.13, 1.618]  (expansion — B overshoots X)
 *   BC / AB in [1.618, 2.24]
 *   CD / BC in [0.382, 0.886]
 *   AD / XA in [0.886, 1.13]  (the defining D completion near A)
 *
 * Returns `+1.0` (bullish, D a swing low), `-1.0` (bearish, D a swing high),
 * or `0.0` (no pattern). Uses a 5% swing reversal threshold.
 */
class Shark implements MuseIndicator<Bar, Float> {
	var swing:SwingTracker;
	var hasEmitted:Bool;

	public function new() {
		swing = new SwingTracker(0.05, 5);
		hasEmitted = false;
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
		var ad = Math.abs(pd - pa);

		var matched = ab / xa >= 1.13 && ab / xa <= 1.618
			&& bc / ab >= 1.618 && bc / ab <= 2.24
			&& cd / bc >= 0.382 && cd / bc <= 0.886
			&& ad / xa >= 0.886 && ad / xa <= 1.13;

		if (matched) {
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
	public function name():String return "Shark";

	public static function spec():IndicatorSpec {
		return {
			name: "shark", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "shark", Math.NaN,
				() -> new Shark(), (i, b) -> (cast i : Shark).update(b))
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
