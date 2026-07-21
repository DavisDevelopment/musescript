package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Rsi;
import musescript.types.MuseType;

/**
 * Stochastic RSI — ported from wickra-core's `StochRsi`
 * (vendor/wickra/crates/wickra-core/src/indicators/stoch_rsi.rs).
 *
 * The Stochastic Oscillator formula applied to the RSI series instead of to
 * price:
 *
 *   StochRSI = 100 · (RSI − min(RSI, stochPeriod)) / (max(RSI, …) − min(RSI, …))
 *
 * Bounded in [0, 100]. A flat RSI window (zero range) is reported as the
 * neutral 50.0, matching the Stochastic convention. A non-finite input is
 * ignored (state untouched, last value returned).
 */
class StochRsi implements MuseIndicator<Float, Float> {
	var rsiPeriod:Int;
	var stochPeriod:Int;
	var rsi:Rsi;
	/** Rolling window of the last `stochPeriod` RSI values. */
	var window:Array<Float>;
	var last:Null<Float>;

	public function new(rsiPeriod:Int, stochPeriod:Int) {
		if (rsiPeriod <= 0 || stochPeriod <= 0) throw "StochRsi: periods must be > 0";
		this.rsiPeriod = rsiPeriod;
		this.stochPeriod = stochPeriod;
		rsi = new Rsi(rsiPeriod);
		window = [];
		last = null;
	}

	/** Current value if available. */
	public function value():Null<Float> return last;

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) {
			// Non-finite input is ignored; state is left untouched.
			return last;
		}
		var rsiValue = rsi.update(input);
		if (rsiValue == null) return null;

		if (window.length == stochPeriod) window.shift();
		window.push(rsiValue);
		if (window.length < stochPeriod) return null;

		var max = window[0];
		var min = window[0];
		for (v in window) {
			if (v > max) max = v;
			if (v < min) min = v;
		}
		var range = max - min;
		// Flat RSI window: report the neutral midpoint.
		var stoch = range == 0.0 ? 50.0 : 100.0 * (rsiValue - min) / range;
		last = stoch;
		return stoch;
	}

	public function reset():Void {
		rsi.reset();
		window = [];
		last = null;
	}

	public function warmupPeriod():Int {
		// RSI emits its first value at input rsiPeriod + 1; the stochastic
		// window then needs stochPeriod RSI values.
		return rsiPeriod + stochPeriod;
	}

	public function isReady():Bool return last != null;
	public function name():String return "StochRSI";

	public static function spec():IndicatorSpec {
		return {
			name: "stoch_rsi", args: [TSeries, TWindow, TWindow], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var rp = IndicatorCache.intArg(args, 1, 14);
				var sp = IndicatorCache.intArg(args, 2, 14);
				var key = "stoch_rsi:" + series + ":" + rp + ":" + sp;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new StochRsi(rp, sp), (i, v) -> (cast i : StochRsi).update(v));
			}
		};
	}
}
