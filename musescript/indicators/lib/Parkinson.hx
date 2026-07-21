package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Parkinson Volatility — ported from wickra-core's `ParkinsonVolatility`
 * (vendor/wickra/crates/wickra-core/src/indicators/parkinson.rs).
 *
 * High-low realised-volatility estimator (Parkinson 1980):
 *
 *   sigma² = (1 / (4n · ln 2)) · Σ (ln(H_i / L_i))²
 *   out    = sqrt(sigma²) · sqrt(trading_periods) · 100
 *
 * `trading_periods` is the annualisation factor (252 daily, 52 weekly,
 * 12 monthly, 1 for the raw per-bar figure). First value after `period` bars.
 */
class Parkinson implements MuseIndicator<Bar, Float> {
	/** 1 / (4 · ln 2) — the Parkinson normalisation constant. */
	static inline var PARKINSON_FACTOR:Float = 0.3606737602222412;

	var period:Int;
	var tradingPeriods:Int;
	var window:Array<Float>;
	var sumSq:Float;
	var last:Null<Float>;

	public function new(period:Int, tradingPeriods:Int) {
		if (period <= 0 || tradingPeriods <= 0) throw "Parkinson: period must be > 0";
		this.period = period;
		this.tradingPeriods = tradingPeriods;
		reset();
	}

	public function update(candle:Bar):Null<Float> {
		var logHl = Math.log(candle.high / candle.low);
		var sample = logHl * logHl;

		if (window.length == period) {
			var old = window.shift();
			sumSq -= old;
		}
		window.push(sample);
		sumSq += sample;

		if (window.length < period) return null;

		var n:Float = period;
		var variance = Math.max(PARKINSON_FACTOR * sumSq / n, 0.0);
		var sigma = Math.sqrt(variance);
		var out = sigma * Math.sqrt(tradingPeriods) * 100.0;
		last = out;
		return out;
	}

	public function reset():Void {
		window = [];
		sumSq = 0.0;
		last = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return last != null;
	public function name():String return "ParkinsonVolatility";

	public static function spec():IndicatorSpec {
		return {
			name: "parkinson", args: [TWindow, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				var tp = IndicatorCache.intArg(args, 1, 252);
				return IndicatorCache.evalBar(h, "parkinson:" + p + ":" + tp, Math.NaN,
					() -> new Parkinson(p, tp), (i, b) -> (cast i : Parkinson).update(b));
			}
		};
	}
}
