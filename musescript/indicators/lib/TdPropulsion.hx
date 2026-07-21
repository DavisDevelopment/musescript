package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Tom DeMark TD Propulsion — ported from wickra-core's `TdPropulsion`
 * (vendor/wickra/crates/wickra-core/src/indicators/td_propulsion.rs).
 *
 * 2-bar trend-continuation thrust signal:
 * - +1.0 (propulsion up): open >= close[-1] AND close > high[-1]
 * - -1.0 (propulsion down): open <= close[-1] AND close < low[-1]
 * - 0.0 otherwise.
 * The very first bar seeds the lookback and emits 0.0.
 */
class TdPropulsion implements MuseIndicator<Bar, Float> {
	var prev:Null<Bar>;
	var lastValue:Null<Float>;

	public function new() {
		reset();
	}

	/** Latest emitted signal if available. */
	public function value():Null<Float> return lastValue;

	public function update(bar:Bar):Null<Float> {
		if (prev == null) {
			prev = bar;
			lastValue = 0.0;
			return 0.0;
		}
		var v = if (bar.open >= prev.close && bar.close > prev.high) 1.0
			else if (bar.open <= prev.close && bar.close < prev.low) -1.0
			else 0.0;
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
	public function name():String return "TDPropulsion";

	public static function spec():IndicatorSpec {
		return {
			name: "td_propulsion", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "td_propulsion", Math.NaN,
				() -> new TdPropulsion(), (i, b) -> (cast i : TdPropulsion).update(b))
		};
	}
}
