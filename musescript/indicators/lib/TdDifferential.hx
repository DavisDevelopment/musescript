package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Tom DeMark TD Differential (2-bar momentum-divergence reversal) — ported
 * from wickra-core's `TdDifferential`
 * (vendor/wickra/crates/wickra-core/src/indicators/td_differential.rs).
 *
 * Compares buying pressure (`close - low`) and selling pressure
 * (`high - close`) against the prior bar. Buy (+1): a down close with more
 * buying pressure and less selling pressure than the prior bar. Sell (−1):
 * an up close with more selling pressure and less buying pressure.
 * Otherwise 0. Unlike the other 2-bar TD patterns, the first bar emits
 * null (no seeded 0).
 */
class TdDifferential implements MuseIndicator<Bar, Float> {
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
		var buyingNow = bar.close - bar.low;
		var buyingPrev = p.close - p.low;
		var sellingNow = bar.high - bar.close;
		var sellingPrev = p.high - p.close;

		var v = if (bar.close < p.close && buyingNow > buyingPrev && sellingNow < sellingPrev) {
			1.0;
		} else if (bar.close > p.close && sellingNow > sellingPrev && buyingNow < buyingPrev) {
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
	public function name():String return "TDDifferential";

	public static function spec():IndicatorSpec {
		return {
			name: "td_differential", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "td_differential", Math.NaN,
				() -> new TdDifferential(), (i, b) -> (cast i : TdDifferential).update(b))
		};
	}
}
