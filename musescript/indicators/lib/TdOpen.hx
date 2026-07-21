package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Tom DeMark TD Open (open-vs-prior-range gap-reversal) — ported from
 * wickra-core's `TdOpen`
 * (vendor/wickra/crates/wickra-core/src/indicators/td_open.rs).
 *
 * Buy (+1): the bar opens below the prior bar's low (gap-down) and its high
 * recovers back above that prior low. Sell (−1): opens above the prior high
 * (gap-up) and its low fades back under that prior high. Otherwise 0. The
 * first bar emits null (no seeded 0).
 */
class TdOpen implements MuseIndicator<Bar, Float> {
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
			return null;
		}
		var p = prev;
		var v = if (bar.open < p.low && bar.high > p.low) {
			1.0;
		} else if (bar.open > p.high && bar.low < p.high) {
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
	public function name():String return "TDOpen";

	public static function spec():IndicatorSpec {
		return {
			name: "td_open", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "td_open", Math.NaN,
				() -> new TdOpen(), (i, b) -> (cast i : TdOpen).update(b))
		};
	}
}
