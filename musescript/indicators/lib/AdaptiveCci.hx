package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Adaptive CCI — ported from wickra-core's `AdaptiveCci`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/adaptive_cci.rs).
 *
 * Lambert's Commodity Channel Index whose centre line adapts to an efficiency
 * ratio, so it leads in trends and stays calm in chop.
 *
 * TP   = (high + low + close) / 3
 * ER   = |TP_t − TP_oldest| / Σ |ΔTP| over the window      (0..1)
 * sc   = ( ER·(2/3 − 2/31) + 2/31 )²
 * mean += sc·(TP_t − mean)                                  (adaptive centre)
 * MD   = mean(|TP_i − mean|) over the window               (mean deviation)
 * CCI  = (TP_t − mean) / (0.015 · MD)
 */
class AdaptiveCci implements MuseIndicator<Bar, Float> {
	var period:Int;
	var window:Array<Float>;
	var mean:Null<Float>;
	var last:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "AdaptiveCci: period must be > 0";
		if (period < 2) throw "AdaptiveCci: period must be >= 2 (efficiency ratio needs at least one step)";
		this.period = period;
		window = [];
		mean = null;
		last = null;
	}

	public function update(bar:Bar):Null<Float> {
		var tp = (bar.high + bar.low + bar.close) / 3.0;
		if (window.length == period) {
			window.shift();
		}
		window.push(tp);

		if (window.length < period) return null;

		var n = period;

		// Efficiency ratio over the window.
		var oldest = window[0];
		var direction = Math.abs(tp - oldest);
		var path = 0.0;
		for (i in 0...(window.length - 1)) {
			path += Math.abs(window[i + 1] - window[i]);
		}
		var er = if (path > 0.0) {
			Math.min(Math.max(direction / path, 0.0), 1.0);
		} else {
			0.0;
		}

		var fast = 2.0 / 3.0;
		var slow = 2.0 / 31.0;
		var sc = Math.pow(er * (fast - slow) + slow, 2);

		var newMean = if (mean == null) {
			var sum = 0.0;
			for (v in window) sum += v;
			sum / n;
		} else {
			mean + sc * (tp - mean);
		};
		mean = newMean;

		var md = 0.0;
		for (v in window) {
			md += Math.abs(v - newMean);
		}
		md /= n;

		var cci = if (md > 0.0) {
			(tp - newMean) / (0.015 * md);
		} else {
			0.0;
		};
		last = cci;
		return cci;
	}

	public function reset():Void {
		window = [];
		mean = null;
		last = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return last != null;
	public function name():String return "AdaptiveCci";

	public static function spec():IndicatorSpec {
		return {
			name: "adaptive_cci", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				return IndicatorCache.evalBar(h, "adaptive_cci:" + p, Math.NaN,
					() -> new AdaptiveCci(p), (i, b) -> (cast i : AdaptiveCci).update(b));
			}
		};
	}
}
