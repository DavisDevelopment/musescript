package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Rogers-Satchell Volatility — ported from wickra-core's
 * `RogersSatchellVolatility`
 * (vendor/wickra/crates/wickra-core/src/indicators/rogers_satchell.rs).
 *
 * Drift-free OHLC realised-volatility estimator (Rogers, Satchell & Yoon 1994):
 *
 *   s_t = ln(H_t / C_t) · ln(H_t / O_t) + ln(L_t / C_t) · ln(L_t / O_t)
 *   out = sqrt(max(mean(s_t over `period`), 0)) · sqrt(trading_periods) · 100
 *
 * Exact under Brownian Motion with arbitrary drift — the drift component
 * cancels algebraically. First value after `period` bars.
 */
class RogersSatchell implements MuseIndicator<Bar, Float> {
	var period:Int;
	var tradingPeriods:Int;
	var window:Array<Float>;
	var sum:Float;
	var last:Null<Float>;

	public function new(period:Int, tradingPeriods:Int) {
		if (period <= 0 || tradingPeriods <= 0) throw "RogersSatchell: period must be > 0";
		this.period = period;
		this.tradingPeriods = tradingPeriods;
		reset();
	}

	public function update(candle:Bar):Null<Float> {
		var logHc = Math.log(candle.high / candle.close);
		var logHo = Math.log(candle.high / candle.open);
		var logLc = Math.log(candle.low / candle.close);
		var logLo = Math.log(candle.low / candle.open);
		var sample = logHc * logHo + logLc * logLo;

		if (window.length == period) {
			var old = window.shift();
			sum -= old;
		}
		window.push(sample);
		sum += sample;

		if (window.length < period) return null;

		var n:Float = period;
		// The clamp absorbs FP cancellation; the mathematical value is
		// already >= 0 by the sign argument in the Rust source.
		var variance = Math.max(sum / n, 0.0);
		var sigma = Math.sqrt(variance);
		var out = sigma * Math.sqrt(tradingPeriods) * 100.0;
		last = out;
		return out;
	}

	public function reset():Void {
		window = [];
		sum = 0.0;
		last = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return last != null;
	public function name():String return "RogersSatchellVolatility";

	public static function spec():IndicatorSpec {
		return {
			name: "rogers_satchell", args: [TWindow, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				var tp = IndicatorCache.intArg(args, 1, 252);
				return IndicatorCache.evalBar(h, "rogers_satchell:" + p + ":" + tp, Math.NaN,
					() -> new RogersSatchell(p, tp), (i, b) -> (cast i : RogersSatchell).update(b));
			}
		};
	}
}
