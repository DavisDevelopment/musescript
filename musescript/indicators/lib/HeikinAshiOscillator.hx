package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Heikin-Ashi Oscillator: the synthetic Heikin-Ashi candle's own body size
 * (see `HeikinAshi`), signed by direction — a simple trend-strength read
 * off the smoothed candles without needing to inspect them visually.
 *
 * HAOsc = haClose - haOpen
 *
 * Positive means the current smoothed candle is green (trend up), negative
 * means red (trend down); magnitude tracks trend strength.
 */
class HeikinAshiOscillator implements MuseIndicator<Bar, Float> {
	var ha:HeikinAshi;

	public function new() {
		ha = new HeikinAshi();
	}

	public function update(bar:Bar):Null<Float> {
		var out = ha.update(bar);
		if (out == null) return null;
		return out.close - out.open;
	}

	public function reset():Void {
		ha.reset();
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return ha.isReady();
	public function name():String return "HeikinAshiOscillator";

	public static function spec():IndicatorSpec {
		return {
			name: "heikin_ashi_oscillator", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "heikin_ashi_oscillator", Math.NaN,
				() -> new HeikinAshiOscillator(), (i, b) -> (cast i : HeikinAshiOscillator).update(b))
		};
	}
}
