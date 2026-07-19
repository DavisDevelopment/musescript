package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Modified Hikkake — the same inside-bar trap as `Hikkake`, but requiring an
 * extra confirmation bar: price must close back *inside* the original
 * inside bar's range after the false breakout before the signal fires,
 * filtering out traps that never actually reverse.
 *
 * Bars 1-3 set up exactly like `Hikkake` (inside bar + one-direction
 * breakout on bar3), latching a "pending trap" in that breakout's direction.
 * On each subsequent bar while a trap is pending: if its close falls back
 * inside bar2's [low, high] range, the trap is confirmed and the indicator
 * emits the reversal signal (opposite sign of the original breakout) on
 * that bar; if instead the breakout extends further in its own direction,
 * the trap is invalidated and cleared.
 */
class HikkakeModified implements MuseIndicator<Bar, Float> {
	var prevPrev:Null<Bar>;
	var prev:Null<Bar>;
	var pendingDirection:Int; // 0 = none, 1 = broke up (watching for bearish reversal), -1 = broke down
	var insideLow:Float;
	var insideHigh:Float;

	public function new() {
		prevPrev = null;
		prev = null;
		pendingDirection = 0;
		insideLow = 0.0;
		insideHigh = 0.0;
	}

	public function update(bar:Bar):Null<Float> {
		var result = 0.0;

		if (pendingDirection != 0) {
			if (bar.close >= insideLow && bar.close <= insideHigh) {
				result = pendingDirection > 0 ? -1.0 : 1.0; // confirmed reversal, opposite the trap direction
				pendingDirection = 0;
			} else if ((pendingDirection > 0 && bar.high > insideHigh) || (pendingDirection < 0 && bar.low < insideLow)) {
				// breakout extended further -> trap invalidated
				pendingDirection = 0;
			}
		}

		var pp = prevPrev;
		var p = prev;
		prevPrev = prev;
		prev = bar;

		if (pp != null && p != null && pendingDirection == 0) {
			var isInside = p.high <= pp.high && p.low >= pp.low;
			if (isInside) {
				if (bar.high > p.high) { pendingDirection = 1; insideLow = p.low; insideHigh = p.high; }
				else if (bar.low < p.low) { pendingDirection = -1; insideLow = p.low; insideHigh = p.high; }
			}
		}

		return result;
	}

	public function reset():Void {
		prevPrev = null;
		prev = null;
		pendingDirection = 0;
		insideLow = 0.0;
		insideHigh = 0.0;
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return prev != null && prevPrev != null;
	public function name():String return "HikkakeModified";

	public static function spec():IndicatorSpec {
		return {
			name: "hikkake_modified", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "hikkake_modified", Math.NaN,
				() -> new HikkakeModified(), (i, b) -> (cast i : HikkakeModified).update(b))
		};
	}
}
