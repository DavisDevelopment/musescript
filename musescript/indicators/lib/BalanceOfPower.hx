package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Balance of Power — ported from wickra-core's `BalanceOfPower`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/balance_of_power.rs).
 *
 * Where the close settled within the bar's range relative to the open:
 * `BOP = (close − open) / (high − low)`.
 *
 * The result lives in `[−1, +1]`: `+1` is a bar that opened on its low and
 * closed on its high (buyers in full control), `−1` the mirror image. A
 * zero-range bar carries no directional information and yields `0`.
 */
class BalanceOfPower implements MuseIndicator<Bar, Float> {
	var hasEmitted:Bool;

	public function new() {
		reset();
	}

	public function update(bar:Bar):Null<Float> {
		hasEmitted = true;
		var range = bar.high - bar.low;
		var bop = if (range == 0.0) {
			// A zero-range bar carries no directional information.
			0.0;
		} else {
			(bar.close - bar.open) / range;
		};
		return bop;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "BalanceOfPower";

	public static function spec():IndicatorSpec {
		return {
			name: "balance_of_power", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "balance_of_power", Math.NaN,
				() -> new BalanceOfPower(), (i, b) -> (cast i : BalanceOfPower).update(b))
		};
	}
}
