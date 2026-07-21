package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Tom DeMark TD Camouflage (hidden-strength/weakness 1-bar reversal) —
 * ported from wickra-core's `TdCamouflage`
 * (vendor/wickra/crates/wickra-core/src/indicators/td_camouflage.rs).
 *
 * Buy (+1): `close < close[-1]` yet `close > open` and `low < low[-1]` —
 * hidden accumulation. Sell (−1): `close > close[-1]`, `close < open`, and
 * `high > high[-1]` — hidden distribution. Otherwise 0. The first bar seeds
 * and emits 0.
 */
class TdCamouflage implements MuseIndicator<Bar, Float> {
	var prev:Null<Bar>;
	var lastValue:Null<Float>;

	public function new() {
		prev = null;
		lastValue = null;
	}

	/** Latest emitted signal if available. */
	public function value():Null<Float> {
		return lastValue;
	}

	public function update(bar:Bar):Null<Float> {
		if (prev == null) {
			prev = bar;
			lastValue = 0.0;
			return 0.0;
		}
		var p = prev;
		var v = if (bar.close < p.close && bar.close > bar.open && bar.low < p.low) {
			1.0;
		} else if (bar.close > p.close && bar.close < bar.open && bar.high > p.high) {
			-1.0;
		} else {
			0.0;
		}
		prev = bar;
		lastValue = v;
		return v;
	}

	public function reset():Void {
		prev = null;
		lastValue = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return lastValue != null;
	public function name():String return "TDCamouflage";

	public static function spec():IndicatorSpec {
		return {
			name: "td_camouflage", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "td_camouflage", Math.NaN,
				() -> new TdCamouflage(), (i, b) -> (cast i : TdCamouflage).update(b))
		};
	}
}
