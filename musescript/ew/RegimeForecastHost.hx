package musescript.ew;

import haxe.Int64;
import haxe.ds.Vector;
import musescript.harness.Bar;
import musescript.ew.EwForecastHost.EwCountMass;
import musescript.ew.ForecastCloud.ForecastCloudUtil;
import musescript.ew.mcmc.RegimeMcmc;
import musescript.ew.mcmc.DetMath;

/**
 * Regime-switching forecast host — wraps `RegimeMcmc` behind the shared `EwForecastHost` contract so
 * a non-Elliott-Wave substrate drops straight into the benchmark + co-evolution rig (nothing
 * downstream knows the difference between a wave lattice and a regime posterior).
 *
 * Streams closes by bar index; each `cloudAt(t)` runs an MH chain over the trailing window of
 * log-returns built from closes **≤ t only** (PIT-causal) and turns the posterior into a
 * `ForecastCloud`. No invalidation concept — regimes don't have a structural kill level (NaN
 * there is honest, not a gap).
 *
 * Cost note: a fresh chain per queried bar is heavy; this host is an elite-only / offline / benchmark
 * producer, never the per-bar hot path — same governance as the MCMC lattice host.
 */
class RegimeForecastHost implements EwForecastHost {
	/** Close at each bar index (sparse-filled via onBar). */
	var closes:Array<Float>;

	var seed:Int;
	var K:Int;
	var horizon:Int;
	var window:Int;
	var steps:Int;
	var burnIn:Int;
	var nPaths:Int;
	var persist:Float;
	var key:Null<String>;

	var cacheT:Int = -1;
	var cacheCloud:ForecastCloud;
	var lastProbs:Vector<Float>;

	/** Minimum return count before a non-empty cloud is emitted (warmup honesty). */
	public static inline var MIN_RETURNS:Int = 30;

	public function new(seed:Int = 0, k:Int = 2, horizon:Int = 20, window:Int = 160,
			steps:Int = 1500, burnIn:Int = 500, nPaths:Int = 200, persist:Float = 0.97, ?phiKey:String) {
		this.seed = seed;
		this.K = k < 2 ? 2 : k;
		this.horizon = horizon < 1 ? 1 : horizon;
		this.window = window < 30 ? 30 : window;
		this.steps = steps;
		this.burnIn = burnIn;
		this.nPaths = nPaths < 1 ? 1 : nPaths;
		this.persist = persist;
		this.key = phiKey;
		this.closes = [];
	}

	public function phiKey():Null<String> return key;

	public function onBar(bar:Bar, index:Int):Void {
		if (index < 0) return;
		while (closes.length <= index) closes.push(Math.NaN);
		closes[index] = bar.close;
		cacheT = -1;
	}

	public function cloudAt(t:Int):ForecastCloud {
		if (cacheT == t && cacheCloud != null) return cacheCloud;
		if (t < 0 || t >= closes.length || !Math.isFinite(closes[t]))
			return ForecastCloudUtil.empty(0);

		// Returns from bars 1..t only — never read closes > t (Bucket C1).
		var rets = returnsThrough(t);
		var n = rets.length;
		if (n < MIN_RETURNS) return ForecastCloudUtil.empty(0);

		var w = n < window ? n : window;
		var data = new Vector<Float>(w);
		for (i in 0...w) data[i] = rets[n - w + i];

		var m = new RegimeMcmc(Int64.make(seed, t), data, K, persist);
		m.run(steps, burnIn);
		var pred = m.predictCumReturn(horizon, nPaths);

		lastProbs = new Vector<Float>(K);
		var topMass = 0.0;
		for (k in 0...K) {
			var p = m.currentRegimeProb(k);
			lastProbs[k] = p;
			if (p > topMass) topMass = p;
		}

		var lc = closes[t];
		var a = lc * DetMath.exp(pred.p05);
		var b = lc * DetMath.exp(pred.p95);
		var lo = a < b ? a : b;
		var hi = a < b ? b : a;

		cacheCloud = {
			horizon: horizon,
			priceLo: lo, priceHi: hi,
			barLo: t + 1, barHi: t + horizon,
			priceMid: lc * DetMath.exp(pred.p50),
			spread: hi - lo,
			probUp: pred.probUp,
			topMass: topMass,
			countEntropy: m.currentEntropy(),
			invalidatePrice: Math.NaN,
			distToInvalidation: Math.NaN,
			nestScore: 1.0,
			labelCode: m.currentRegime() + 1.0, // 1-based: 1=calmest … K=most volatile
			samples: nPaths
		};
		cacheT = t;
		return cacheCloud;
	}

	public function topCounts(t:Int, kMax:Int):Array<EwCountMass> {
		if (cacheT != t) cloudAt(t);
		var out:Array<EwCountMass> = [];
		if (lastProbs == null) return out;
		var lim = kMax < K ? kMax : K;
		for (k in 0...lim) out.push({
			label: "regime_" + k,
			mass: lastProbs[k],
			score: lastProbs[k],
			invalidatePrice: Math.NaN,
			nestScore: 1.0,
			degree: k
		});
		return out;
	}

	/** Log-returns using closes[1..t] only. */
	function returnsThrough(t:Int):Array<Float> {
		var out:Array<Float> = [];
		var i = 1;
		while (i <= t) {
			var a = closes[i - 1];
			var b = closes[i];
			if (Math.isFinite(a) && a > 0 && Math.isFinite(b) && b > 0)
				out.push(DetMath.log(b / a));
			i++;
		}
		return out;
	}
}
