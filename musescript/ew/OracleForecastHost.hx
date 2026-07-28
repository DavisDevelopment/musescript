package musescript.ew;

import musescript.harness.Bar;
import musescript.ew.mcmc.DetRng;
import musescript.ew.EwForecastHost.EwCountMass;
import haxe.Int64;

/**
 * Bucket J2 positive control: planted, tunable edge.
 * Peeks a bounded, noisy amount at the future close `horizon` bars ahead.
 * `signal ∈ [0,1]`: 0 ≡ pure noise (== J1); as signal↑ detection must strengthen monotonically.
 *
 * Causality note: this host INTENTIONALLY leaks future information — it is a synthetic
 * oracle for instrument validation only, never a production host.
 */
class OracleForecastHost implements EwForecastHost {
	var closes:Array<Float>;
	var signal:Float;
	var horizon:Int;
	var seed:Int;

	public function new(bars:Array<Bar>, signal:Float = 0.5, ?horizon:Int = 5, ?seed:Int = 0x0ACE) {
		this.closes = [for (b in bars) b.close];
		this.signal = signal < 0 ? 0 : (signal > 1 ? 1 : signal);
		this.horizon = horizon < 1 ? 1 : horizon;
		this.seed = seed;
	}

	/** Rebuild with a new signal strength (same tape length; closes re-copied from `bars`). */
	public static function fromBars(bars:Array<Bar>, signal:Float, ?horizon:Int = 5, ?seed:Int = 0x0ACE):OracleForecastHost {
		return new OracleForecastHost(bars, signal, horizon, seed);
	}

	public function phiKey():Null<String> return 'oracle-s=${signal}';

	public function onBar(bar:Bar, index:Int):Void {
		while (closes.length <= index) closes.push(Math.NaN);
		closes[index] = bar.close;
	}

	public function cloudAt(t:Int):ForecastCloud {
		var noise = new DetRng(Int64.ofInt(seed ^ (t * 0x85EBCA6B)), Int64.ofInt(0x0ACE));
		var close = (t >= 0 && t < closes.length) ? closes[t] : Math.NaN;
		var futureIx = t + horizon;
		var future = (futureIx >= 0 && futureIx < closes.length) ? closes[futureIx] : close;
		var noiseMid = Math.isFinite(close) ? close * (1.0 + (noise.nextUnit() - 0.5) * 0.02) : noise.nextUnit() * 100;
		var oracleMid = Math.isFinite(future) ? future : noiseMid;
		var mid = signal * oracleMid + (1.0 - signal) * noiseMid;
		var half = Math.isFinite(mid) ? Math.abs(mid) * (0.005 + (1.0 - signal) * 0.02) : 1.0;
		var up = Math.isFinite(close) && Math.isFinite(future) ? (future > close ? 1.0 : 0.0) : 0.5;
		var probUp = signal * up + (1.0 - signal) * noise.nextUnit();
		return {
			horizon: horizon,
			priceLo: mid - half,
			priceHi: mid + half,
			barLo: t + 0.0,
			barHi: t + horizon + 0.0,
			priceMid: mid,
			spread: 2 * half,
			probUp: probUp,
			topMass: 0.5 + 0.5 * signal,
			countEntropy: (1.0 - signal),
			invalidatePrice: Math.NaN,
			distToInvalidation: Math.NaN,
			nestScore: 1.0,
			labelCode: 1,
			samples: 8
		};
	}

	public function topCounts(t:Int, kMax:Int):Array<EwCountMass> {
		return [];
	}
}
