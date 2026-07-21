package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Time Series Forecast Oscillator — ported from wickra-core's `TsfOscillator`
 * (vendor/wickra/crates/wickra-core/src/indicators/tsf_oscillator.rs).
 *
 * The percentage gap between the close and the one-bar-ahead time-series
 * forecast of the close:
 *
 * TSFOsc_t = 100 · (close_t − TSF(close, period)_t) / close_t
 *
 * Positive readings mean the close sits above its forward forecast (price
 * has overshot the projected trend); negative readings mean it sits below.
 * On a trending series it reads more negative in an uptrend (the forecast
 * has already stepped above price). Wraps `Tsf` so the warmup matches; a
 * zero close holds the previous value (the percentage form is undefined).
 */
class TsfOscillator implements MuseIndicator<Float, Float> {
	var period:Int;
	var tsf:Tsf;
	var current:Null<Float>;

	public function new(period:Int) {
		if (period < 2) throw "TsfOscillator: TSF oscillator needs period >= 2";
		this.period = period;
		tsf = new Tsf(period);
		current = null;
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return null;
		var forecast = tsf.update(input);
		if (forecast == null) return null;
		// Hold the previous value if the close is zero — the percentage form
		// is undefined and a return of inf would propagate badly.
		if (input == 0.0) return current;
		var value = 100.0 * (input - forecast) / input;
		current = value;
		return value;
	}

	public function reset():Void {
		tsf.reset();
		current = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return current != null;
	public function name():String return "TsfOscillator";

	public static function spec():IndicatorSpec {
		return {
			name: "tsf_oscillator", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "tsf_oscillator:" + series + ":" + p, series, Math.NaN,
					() -> new TsfOscillator(p), (i, v) -> (cast i : TsfOscillator).update(v));
			}
		};
	}
}
