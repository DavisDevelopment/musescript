package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Tom DeMark TD Clop (2-bar open/close engulfing reversal) — ported from
 * wickra-core's `TdClop`
 * (vendor/wickra/crates/wickra-core/src/indicators/td_clop.rs).
 *
 * Buy (+1): the bar opens below both the prior bar's open and close and
 * closes above both. Sell (−1): opens above both and closes below both.
 * Otherwise 0. The first bar seeds and emits 0.
 */
class TdClop implements MuseIndicator<Bar, Float> {
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
		var belowBody = bar.open < p.open && bar.open < p.close;
		var aboveBody = bar.close > p.open && bar.close > p.close;
		var overBody = bar.open > p.open && bar.open > p.close;
		var underBody = bar.close < p.open && bar.close < p.close;
		var v = if (belowBody && aboveBody) {
			1.0;
		} else if (overBody && underBody) {
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
	public function name():String return "TDClop";

	public static function spec():IndicatorSpec {
		return {
			name: "td_clop", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "td_clop", Math.NaN,
				() -> new TdClop(), (i, b) -> (cast i : TdClop).update(b))
		};
	}
}
