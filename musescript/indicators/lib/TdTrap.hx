package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Tom DeMark TD Trap (inside-bar breakout) — ported from wickra-core's
 * `TdTrap` (vendor/wickra/crates/wickra-core/src/indicators/td_trap.rs).
 *
 * A trap forms when the prior bar was an inside bar (high below and low
 * above the bar before it). Buy (+1): the current close breaks above the
 * inside bar's high. Sell (−1): the current close breaks below its low.
 * Otherwise 0. The first two bars seed and emit 0.
 */
class TdTrap implements MuseIndicator<Bar, Float> {
	var prev1:Null<Bar>;
	var prev2:Null<Bar>;
	var lastValue:Null<Float>;

	public function new() {
		prev1 = null;
		prev2 = null;
		lastValue = null;
	}

	/** Latest emitted signal if available. */
	public function value():Null<Float> {
		return lastValue;
	}

	public function update(bar:Bar):Null<Float> {
		if (prev1 == null || prev2 == null) {
			// Not enough history yet: emit a neutral 0.0 while seeding.
			prev2 = prev1;
			prev1 = bar;
			lastValue = 0.0;
			return 0.0;
		}
		var trap = prev1;
		var before = prev2;
		var isInside = trap.high < before.high && trap.low > before.low;
		var v = if (isInside && bar.close > trap.high) {
			1.0;
		} else if (isInside && bar.close < trap.low) {
			-1.0;
		} else {
			0.0;
		}
		prev2 = prev1;
		prev1 = bar;
		lastValue = v;
		return v;
	}

	public function reset():Void {
		prev1 = null;
		prev2 = null;
		lastValue = null;
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return lastValue != null;
	public function name():String return "TDTrap";

	public static function spec():IndicatorSpec {
		return {
			name: "td_trap", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "td_trap", Math.NaN,
				() -> new TdTrap(), (i, b) -> (cast i : TdTrap).update(b))
		};
	}
}
