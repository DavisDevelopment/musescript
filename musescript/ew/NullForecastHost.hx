package musescript.ew;

import musescript.harness.Bar;
import musescript.ew.mcmc.DetRng;
import musescript.ew.EwForecastHost.EwCountMass;
import haxe.Int64;

/**
 * Bucket J1 negative control: pure-noise forecast host.
 * Emits random clouds via `DetRng` keyed by bar index — no dependence on future bars.
 * The hardened pipeline MUST report NO-GO / no skill for genomes using this host.
 */
class NullForecastHost implements EwForecastHost {
	var rngSeed:Int;
	var horizon:Int;
	var closes:Array<Float>;

	public function new(?seed:Int = 0x0011, ?horizon:Int = 5) {
		this.rngSeed = seed;
		this.horizon = horizon;
		this.closes = [];
	}

	public function phiKey():Null<String> return "null-noise";

	public function onBar(bar:Bar, index:Int):Void {
		while (closes.length <= index) closes.push(Math.NaN);
		closes[index] = bar.close;
	}

	public function cloudAt(t:Int):ForecastCloud {
		// Per-t RNG so cloudAt(t) is a pure function of (seed, t, close[t]) — causal.
		var rng = new DetRng(Int64.ofInt(rngSeed ^ (t * 0x9E3779B9)), Int64.ofInt(0x4E554C));
		var close = (t >= 0 && t < closes.length) ? closes[t] : Math.NaN;
		var mid = Math.isFinite(close) ? close * (1.0 + (rng.nextUnit() - 0.5) * 0.02) : rng.nextUnit() * 100;
		var half = mid * (0.005 + rng.nextUnit() * 0.02);
		return {
			horizon: horizon,
			priceLo: mid - half,
			priceHi: mid + half,
			barLo: t + 0.0,
			barHi: t + horizon + 0.0,
			priceMid: mid,
			spread: 2 * half,
			probUp: rng.nextUnit(),
			topMass: rng.nextUnit(),
			countEntropy: rng.nextUnit(),
			invalidatePrice: Math.NaN,
			distToInvalidation: Math.NaN,
			nestScore: 1.0,
			labelCode: 0,
			samples: 8
		};
	}

	public function topCounts(t:Int, kMax:Int):Array<EwCountMass> {
		return [];
	}
}
