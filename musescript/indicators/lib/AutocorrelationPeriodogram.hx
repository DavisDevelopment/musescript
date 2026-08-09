package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Ehlers Autocorrelation Periodogram — estimates the dominant market cycle
 * by correlating a roofing-filtered price with lagged copies of itself and
 * reading off the spectral peak.
 *
 * From John Ehlers' *Cycle Analytics for Traders* (2013, ch. 8), the
 * autocorrelation function emphasises whatever cycle is actually present and
 * suppresses noise; transforming it into a periodogram and taking the
 * power-weighted centre of gravity gives a smooth, robust estimate of the
 * dominant cycle length. The output is a period in bars within `[min_period, max_period]`.
 *
 * Ported from wickra-core's `AutocorrelationPeriodogram`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/autocorrelation_periodogram.rs).
 */
class AutocorrelationPeriodogram implements MuseIndicator<Float, Float> {
	static inline var AVG_LENGTH:Int = 3;

	var minPeriod:Int;
	var maxPeriod:Int;
	var roof:RoofingFilter;
	var buffer:RingBuffer<Float>;
	var r:Array<Float>;
	var maxPwr:Float;
	var last:Null<Float>;

	public function new(minPeriod:Int, maxPeriod:Int) {
		if (minPeriod <= 0 || maxPeriod <= 0) throw "AutocorrelationPeriodogram: periods must be > 0";
		if (minPeriod < AVG_LENGTH + 1 || maxPeriod <= minPeriod)
			throw "AutocorrelationPeriodogram: need AvgLength < min_period < max_period";
		this.minPeriod = minPeriod;
		this.maxPeriod = maxPeriod;
		this.roof = new RoofingFilter(10, maxPeriod);
		this.buffer = new RingBuffer(maxPeriod + AVG_LENGTH);
		this.r = [for (_ in 0...maxPeriod + 1) 0.0];
		this.maxPwr = 0.0;
		this.last = null;
	}

	/** Pearson correlation of the AvgLength-deep slices offset by lag. */
	function correlation(lag:Int):Float {
		var len = buffer.length;
		if (len < lag + AVG_LENGTH) return 0.0;
		var filt = function(k:Int):Float {
			return buffer.oldest(len - 1 - k);
		};
		var m = AVG_LENGTH;
		var sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0;
		for (count in 0...AVG_LENGTH) {
			var x = filt(count);
			var y = filt(lag + count);
			sx += x;
			sy += y;
			sxx += x * x;
			syy += y * y;
			sxy += x * y;
		}
		var m_f = m;
		var denom = (m_f * sxx - sx * sx) * (m_f * syy - sy * sy);
		if (denom > 0.0) {
			return (m_f * sxy - sx * sy) / Math.sqrt(denom);
		} else {
			return 0.0;
		}
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) {
			return last;
		}
		var filt = roof.update(price);
		if (filt == null) return null;
		buffer.push(filt);
		if (buffer.length < maxPeriod + AVG_LENGTH) {
			return null;
		}

		// Autocorrelation across lags
		var corr:Array<Float> = [for (_ in 0...maxPeriod + 1) 0.0];
		for (lag in 0...maxPeriod + 1) {
			corr[lag] = correlation(lag);
		}

		// Periodogram: spectral power for each candidate period, EMA'd over time
		maxPwr *= 0.995;
		for (period in minPeriod...maxPeriod + 1) {
			var cosine = 0.0;
			var sine = 0.0;
			for (n in AVG_LENGTH...maxPeriod + 1) {
				var cn = corr[n];
				var angle = 2 * Math.PI * n / period;
				cosine += cn * Math.cos(angle);
				sine += cn * Math.sin(angle);
			}
			var power = cosine * cosine + sine * sine;
			r[period] = 0.2 * power + 0.8 * r[period];
			if (r[period] > maxPwr) {
				maxPwr = r[period];
			}
		}

		// Power-weighted centre of gravity of the strong periods
		var spx = 0.0;
		var sp = 0.0;
		for (period in minPeriod...maxPeriod + 1) {
			var pwr = if (maxPwr > 0.0) r[period] / maxPwr else 0.0;
			if (pwr >= 0.5) {
				spx += period * pwr;
				sp += pwr;
			}
		}
		var dominant = if (sp > 0.0) {
			var cand = spx / sp;
			if (cand < minPeriod) minPeriod else if (cand > maxPeriod) maxPeriod else cand;
		} else {
			minPeriod;
		};
		last = dominant;
		return dominant;
	}

	public function reset():Void {
		roof.reset();
		buffer = new RingBuffer(maxPeriod + AVG_LENGTH);
		for (i in 0...r.length) r[i] = 0.0;
		maxPwr = 0.0;
		last = null;
	}

	public function warmupPeriod():Int return maxPeriod + AVG_LENGTH;
	public function isReady():Bool return last != null;
	public function name():String return "AutocorrelationPeriodogram";

	public static function spec():IndicatorSpec {
		return {
			name: "autocorrelation_periodogram", args: [TWindow, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var minP = IndicatorCache.intArg(args, 0, 10);
				var maxP = IndicatorCache.intArg(args, 1, 48);
				return IndicatorCache.evalSeries(h, "autocorrelation_periodogram:" + minP + ":" + maxP, "close", Math.NaN,
					() -> new AutocorrelationPeriodogram(minP, maxP), (i, v) -> (cast i : AutocorrelationPeriodogram).update(v));
			}
		};
	}
}
