package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Advance Block candlestick pattern — ported from wickra-core's `AdvanceBlock`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/advance_block.rs).
 *
 * A 3-bar bearish warning: three green candles still pushing to higher closes,
 * but visibly running out of steam — each real body shrinks while the upper
 * shadows lengthen, hinting the advance is about to stall.
 *
 * all three green & higher closes
 * each opens inside the prior body
 * shrinking bodies   (body3 < body2 < body1)
 * upper shadow of bar3 >= upper shadow of bar2 and bar3 has an upper shadow
 *
 * Output is −1.0 when the pattern completes and 0.0 otherwise.
 */
class AdvanceBlock implements MuseIndicator<Bar, Float> {
	var prev:Null<Bar>;
	var prevPrev:Null<Bar>;
	var hasEmitted:Bool;

	public function new() {
		prev = null;
		prevPrev = null;
		hasEmitted = false;
	}

	public function update(bar:Bar):Null<Float> {
		hasEmitted = true;
		var pp = prevPrev;
		var p = prev;
		prevPrev = prev;
		prev = bar;

		if (pp == null || p == null) {
			return 0.0;
		}

		var bar1 = pp;
		var bar2 = p;
		var bar3 = bar;

		var body1 = bar1.close - bar1.open;
		var body2 = bar2.close - bar2.open;
		var body3 = bar3.close - bar3.open;
		var upper2 = bar2.high - bar2.close;
		var upper3 = bar3.high - bar3.close;

		if (bar1.close > bar1.open
			&& bar2.close > bar2.open
			&& bar3.close > bar3.open
			&& bar2.close > bar1.close
			&& bar3.close > bar2.close
			&& bar2.open >= bar1.open
			&& bar2.open <= bar1.close
			&& bar3.open >= bar2.open
			&& bar3.open <= bar2.close
			&& body2 < body1
			&& body3 < body2
			&& upper3 >= upper2
			&& upper3 > 0.0) {
			return -1.0;
		}
		return 0.0;
	}

	public function reset():Void {
		prev = null;
		prevPrev = null;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return hasEmitted;
	public function name():String return "AdvanceBlock";

	public static function spec():IndicatorSpec {
		return {
			name: "advance_block", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				return IndicatorCache.evalBar(h, "advance_block", Math.NaN,
					() -> new AdvanceBlock(), (i, b) -> (cast i : AdvanceBlock).update(b));
			}
		};
	}
}
