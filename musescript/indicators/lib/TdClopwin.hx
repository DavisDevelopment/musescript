package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Tom DeMark TD Clopwin (2-bar "close/open within" inside-body pattern) —
 * ported from wickra-core's `TdClopwin`
 * (vendor/wickra/crates/wickra-core/src/indicators/td_clopwin.rs).
 *
 * The current bar's open and close both sit within the prior bar's real
 * body: +1 if the inside bar is bullish (`close >= open`), −1 if bearish,
 * 0 when either end escapes the prior body. The first bar seeds and emits 0.
 */
class TdClopwin implements MuseIndicator<Bar, Float> {
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
		var bodyLow = Math.min(p.open, p.close);
		var bodyHigh = Math.max(p.open, p.close);
		var openIn = bar.open >= bodyLow && bar.open <= bodyHigh;
		var closeIn = bar.close >= bodyLow && bar.close <= bodyHigh;
		var v = if (openIn && closeIn) {
			bar.close >= bar.open ? 1.0 : -1.0;
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
	public function name():String return "TDClopwin";

	public static function spec():IndicatorSpec {
		return {
			name: "td_clopwin", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "td_clopwin", Math.NaN,
				() -> new TdClopwin(), (i, b) -> (cast i : TdClopwin).update(b))
		};
	}
}
