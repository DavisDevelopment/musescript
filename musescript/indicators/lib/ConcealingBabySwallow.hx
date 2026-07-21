package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Concealing Baby Swallow — ported from wickra-core's `ConcealingBabySwallow`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/concealing_baby_swallow.rs).
 *
 * A rare 4-bar bullish reversal. Two black marubozu lead a steep decline; the third
 * is a black candle that gaps down on the open yet throws a long upper shadow back
 * up into the second body; the fourth is a large black candle that completely
 * engulfs the third, shadows included.
 */
class ConcealingBabySwallow implements MuseIndicator<Bar, Float> {
	var c1:Null<Bar>;
	var c2:Null<Bar>;
	var c3:Null<Bar>;
	var hasEmitted:Bool;

	public function new() {
		c1 = null;
		c2 = null;
		c3 = null;
		hasEmitted = false;
	}

	private function blackMarubozu(bar:Bar):Bool {
		var range = bar.high - bar.low;
		if (range <= 0.0) return false;

		var upper = bar.high - bar.open;
		var lower = bar.close - bar.low;

		return bar.open > bar.close && upper <= 0.05 * range && lower <= 0.05 * range;
	}

	public function update(bar:Bar):Null<Float> {
		hasEmitted = true;

		var bar1 = c1;
		var bar2 = c2;
		var bar3 = c3;

		c1 = c2;
		c2 = c3;
		c3 = bar;

		if (bar1 == null || bar2 == null || bar3 == null) {
			return 0.0;
		}

		// bar1 and bar2 must be black marubozu
		if (!blackMarubozu(bar1) || !blackMarubozu(bar2)) {
			return 0.0;
		}

		// bar3 must be black, gap down on open, throw upper shadow into bar2
		if (bar3.open <= bar3.close) {
			return 0.0;
		}
		if (bar3.open >= bar2.close) {
			return 0.0; // no downside gap
		}
		if (bar3.high <= bar2.close) {
			return 0.0; // upper shadow does not reach into bar2's body
		}

		// bar4 (current bar) must be black and engulf bar3 including shadows
		if (bar.open <= bar.close) {
			return 0.0;
		}
		if (bar.open > bar3.high && bar.close < bar3.low) {
			return 1.0;
		}

		return 0.0;
	}

	public function reset():Void {
		c1 = null;
		c2 = null;
		c3 = null;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 4;
	public function isReady():Bool return hasEmitted;
	public function name():String return "ConcealingBabySwallow";

	public static function spec():IndicatorSpec {
		return {
			name: "concealing_baby_swallow", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var nanFill = Math.NaN;
				return IndicatorCache.evalBar(h, "concealing_baby_swallow", nanFill,
					() -> new ConcealingBabySwallow(), (i, bar) -> (cast i : ConcealingBabySwallow).update(bar));
			}
		};
	}
}
