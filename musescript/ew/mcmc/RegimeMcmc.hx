package musescript.ew.mcmc;

import haxe.Int64;
import haxe.ds.Vector;

/**
 * Bayesian regime-switching MCMC — the first non-Elliott-Wave forecast substrate on the byte-identical
 * kernel foundation (FIDELITY_AND_BENCHMARK_PLAN successor direction, idea ①: the "meta-layer").
 *
 * A K-regime Gaussian hidden Markov model over log-returns: each bar is emitted from Normal(μ_z, σ_z)
 * with a latent regime z_t, and regimes persist through a fixed strong-diagonal transition matrix.
 * Metropolis–Hastings samples the joint posterior over the regime PATH and the soft emission params
 * (μ_k, σ_k) — the discrete/continuous hybrid the whole rig is built for. The posterior over the
 * CURRENT regime + a forward predictive band is what a host turns into a ForecastCloud.
 *
 * HARD constraints (non-learnable, identifiability): K fixed; σ strictly ascending (regime 0 = calm …
 * regime K-1 = volatile) so the chain can't relabel and blur the posterior. SOFT (sampled / later
 * evolved): μ_k, σ_k. Every random decision routes through DetRng/DetMath, so a given seed yields the
 * same posterior bit-for-bit on Graal-JVM and WASM — the parity contract the kernel must keep.
 *
 * Step-wise API (shared shape for future MCMC hosts): new → run(steps, burnIn) → regimeProb / predict.
 */
class RegimeMcmc {
	static inline var LOG2PI = 1.8378770664093453;

	public var K(default, null):Int;
	public var T(default, null):Int;

	var data:Vector<Float>;      // log-returns
	var z:Vector<Int>;           // current regime path
	var mu:Vector<Float>;        // emission means (K)
	var sigma:Vector<Float>;     // emission stddevs (K), kept strictly ascending
	var logA:Vector<Float>;      // log transition matrix (K*K), fixed
	var A:Vector<Float>;         // transition matrix (K*K), linear — for forward prediction
	var rng:DetRng;

	// posterior accumulation
	var counts:Vector<Float>;    // T*K soft counts of z_t == k after burn-in
	var accepted:Int = 0;
	var proposed:Int = 0;
	var samples:Int = 0;

	/**
	 * @param seed        deterministic seed (byte-identical stream across targets)
	 * @param returns     log-returns, length T
	 * @param k           number of regimes (>= 2)
	 * @param persist     self-transition prob (strong diagonal); off-diagonal split evenly
	 * @param sigmaSeed   optional ascending σ initialization; else derived from data spread
	 */
	public function new(seed:Int64, returns:Vector<Float>, k:Int = 2, persist:Float = 0.97, ?sigmaSeed:Vector<Float>) {
		this.K = k < 2 ? 2 : k;
		this.T = returns.length;
		this.data = returns;
		this.rng = new DetRng(seed);

		mu = new Vector<Float>(K);
		sigma = new Vector<Float>(K);
		for (i in 0...K) mu[i] = 0.0;
		if (sigmaSeed != null && sigmaSeed.length == K) {
			for (i in 0...K) sigma[i] = sigmaSeed[i];
		} else {
			// spread σ ascending across a plausible band derived from the data's own scale
			var sd = sampleStd(returns);
			if (!(sd > 0)) sd = 1e-4;
			for (i in 0...K) sigma[i] = sd * (0.5 + 1.5 * i); // e.g. 0.5σ, 2.0σ for K=2
		}
		enforceSigmaOrder();

		// fixed strong-diagonal transition (persistence is the regime prior)
		logA = new Vector<Float>(K * K);
		A = new Vector<Float>(K * K);
		var off = (1.0 - persist) / (K - 1);
		for (i in 0...K)
			for (j in 0...K) {
				var p = i == j ? persist : off;
				A[i * K + j] = p;
				logA[i * K + j] = DetMath.log(p);
			}

		// init path by nearest-σ emission (greedy, deterministic)
		z = new Vector<Int>(T);
		for (t in 0...T) z[t] = bestRegimeFor(t);

		counts = new Vector<Float>(T * K);
		for (i in 0...counts.length) counts[i] = 0.0;
	}

	// ---- likelihood pieces ----

	inline function emitLL(t:Int, k:Int):Float {
		var d = (data[t] - mu[k]) / sigma[k];
		return -0.5 * LOG2PI - DetMath.log(sigma[k]) - 0.5 * d * d;
	}

	function bestRegimeFor(t:Int):Int {
		var best = 0;
		var bestLL = emitLL(t, 0);
		for (k in 1...K) {
			var ll = emitLL(t, k);
			if (ll > bestLL) { bestLL = ll; best = k; }
		}
		return best;
	}

	// ---- MH moves ----

	/** Flip a single z_t to another regime; accept on the LOCAL log-posterior delta (O(1)). */
	function moveFlip():Void {
		var t = rng.nextInt(T);
		var cur = z[t];
		var nw = rng.nextInt(K - 1);
		if (nw >= cur) nw++; // uniform over the other K-1 regimes
		var delta = emitLL(t, nw) - emitLL(t, cur);
		if (t > 0) delta += logA[z[t - 1] * K + nw] - logA[z[t - 1] * K + cur];
		if (t < T - 1) delta += logA[nw * K + z[t + 1]] - logA[cur * K + z[t + 1]];
		proposed++;
		if (acceptLog(delta)) {
			z[t] = nw;
			accepted++;
		}
	}

	/** Perturb σ_k (log-scale random walk); reject if it breaks the ascending-σ hard order. */
	function moveSigma():Void {
		var k = rng.nextInt(K);
		var old = sigma[k];
		var proposedSig = old * DetMath.exp(0.12 * rng.nextGaussian()); // DetMath, not native Math (parity)
		// hard identifiability gate
		if (k > 0 && proposedSig <= sigma[k - 1]) return;
		if (k < K - 1 && proposedSig >= sigma[k + 1]) return;
		// local delta: only emissions currently assigned to regime k change
		var delta = 0.0;
		for (t in 0...T) if (z[t] == k) {
			var dn = (data[t] - mu[k]) / proposedSig;
			var dOld = (data[t] - mu[k]) / old;
			delta += (-DetMath.log(proposedSig) - 0.5 * dn * dn) - (-DetMath.log(old) - 0.5 * dOld * dOld);
		}
		// weak prior favoring the log-scale move symmetry (proposal is multiplicative → +log ratio)
		delta += DetMath.log(proposedSig) - DetMath.log(old);
		proposed++;
		if (acceptLog(delta)) {
			sigma[k] = proposedSig;
			accepted++;
		}
	}

	/** Perturb μ_k (additive random walk scaled to σ_k). */
	function moveMu():Void {
		var k = rng.nextInt(K);
		var old = mu[k];
		var proposedMu = old + 0.15 * sigma[k] * rng.nextGaussian();
		var delta = 0.0;
		for (t in 0...T) if (z[t] == k) {
			var dn = (data[t] - proposedMu) / sigma[k];
			var dOld = (data[t] - old) / sigma[k];
			delta += (-0.5 * dn * dn) - (-0.5 * dOld * dOld);
		}
		proposed++;
		if (acceptLog(delta)) {
			mu[k] = proposedMu;
			accepted++;
		}
	}

	inline function acceptLog(deltaLogP:Float):Bool {
		if (deltaLogP >= 0) return true;
		return DetMath.log(rng.nextUnit()) < deltaLogP; // u→0 ⇒ log→-inf ⇒ accept (correct)
	}

	/** One MCMC step: mostly path flips, occasional param moves. */
	public function step():Void {
		var r = rng.nextUnit();
		if (r < 0.80) moveFlip();
		else if (r < 0.90) moveSigma();
		else moveMu();
	}

	/** Run `nSteps` MH steps, accumulating regime posterior over the last `nSteps - burnIn`.
	 * When `traceCurrent` is true, also records the post-burn-in current-regime indicator for ESS. */
	public function run(nSteps:Int, burnIn:Int, ?traceCurrent:Bool = false):Void {
		var b = burnIn < 0 ? 0 : (burnIn > nSteps ? nSteps : burnIn);
		if (traceCurrent) currentTrace = [];
		for (i in 0...nSteps) {
			step();
			if (i >= b) {
				for (t in 0...T) counts[t * K + z[t]] += 1.0;
				samples++;
				if (traceCurrent) currentTrace.push(z[T - 1] + 0.0);
			}
		}
	}

	/** Post-burn-in trace of the last-bar regime id (populated when `run(..., traceCurrent=true)`). */
	var currentTrace:Array<Float> = [];

	/**
	 * Effective sample size of the last-bar regime indicator via lag-1 AR approximation:
	 * ESS ≈ N · (1−ρ)/(1+ρ). Returns NaN if no trace was collected.
	 */
	public function essCurrentRegime():Float {
		return essFromTrace(currentTrace);
	}

	/** ESS of a real-valued trace (Bucket E1). */
	public static function essFromTrace(xs:Array<Float>):Float {
		var n = xs.length;
		if (n < 4) return Math.NaN;
		var mean = 0.0;
		for (x in xs) mean += x;
		mean /= n;
		var var0 = 0.0;
		var cov1 = 0.0;
		for (i in 0...n) {
			var d = xs[i] - mean;
			var0 += d * d;
			if (i + 1 < n) cov1 += d * (xs[i + 1] - mean);
		}
		var0 /= n;
		cov1 /= (n - 1);
		// Degenerate: every draw identical → estimator variance 0, treat as ESS = N.
		if (!(var0 > 0)) return n + 0.0;
		var rho = cov1 / var0;
		if (rho >= 1) return 1.0;
		if (rho <= -1) return n + 0.0;
		return n * (1.0 - rho) / (1.0 + rho);
	}

	/** Flag a too-short budget: ESS below `minEss` or accept rate outside `[lo, hi]`. */
	public function mixingOk(?minEss:Float = 20.0, ?acceptLo:Float = 0.05, ?acceptHi:Float = 0.6):Bool {
		var ar = acceptRate();
		if (ar < acceptLo || ar > acceptHi) return false;
		var ess = essCurrentRegime();
		if (!Math.isFinite(ess)) return false;
		return ess >= minEss;
	}

	// ---- posterior / prediction ----

	/** Posterior P(z_t = k) from accumulated samples (uniform prior before any samples). */
	public function regimeProb(t:Int, k:Int):Float {
		if (samples == 0) return 1.0 / K;
		return counts[t * K + k] / samples;
	}

	/** Posterior over the CURRENT (last) regime — what a host reads for "what regime are we in". */
	public inline function currentRegimeProb(k:Int):Float
		return regimeProb(T - 1, k);

	/** Argmax current regime. */
	public function currentRegime():Int {
		var best = 0;
		var bp = currentRegimeProb(0);
		for (k in 1...K) {
			var p = currentRegimeProb(k);
			if (p > bp) { bp = p; best = k; }
		}
		return best;
	}

	/** Shannon entropy (nats) of the current-regime posterior — the "how sure are we" scalar. */
	public function currentEntropy():Float {
		var e = 0.0;
		for (k in 0...K) {
			var p = currentRegimeProb(k);
			if (p > 0) e -= p * DetMath.log(p);
		}
		return e;
	}

	/**
	 * Forward predictive distribution of the cumulative log-return over the next `H` bars: start from
	 * the current-regime posterior, walk the transition matrix, emit Normal(μ_z, σ_z) each step,
	 * repeat over `nPaths`. Returns p05/p50/p95 cumulative-return quantiles + P(up). Deterministic
	 * (all draws via DetRng); this is what a host turns into a ForecastCloud price band.
	 */
	public function predictCumReturn(H:Int, nPaths:Int):{p05:Float, p50:Float, p95:Float, probUp:Float, mean:Float} {
		var cur = new Vector<Float>(K);
		for (k in 0...K) cur[k] = currentRegimeProb(k);
		var sums = new Vector<Float>(nPaths);
		var up = 0;
		var msum = 0.0;
		for (p in 0...nPaths) {
			var zt = sampleCat(cur);
			var s = 0.0;
			for (h in 0...H) {
				s += mu[zt] + sigma[zt] * rng.nextGaussian();
				zt = sampleRow(zt);
			}
			sums[p] = s;
			msum += s;
			if (s > 0) up++;
		}
		insertionSort(sums);
		return {
			p05: quantile(sums, 0.05),
			p50: quantile(sums, 0.50),
			p95: quantile(sums, 0.95),
			probUp: nPaths > 0 ? up / nPaths : Math.NaN,
			mean: nPaths > 0 ? msum / nPaths : Math.NaN
		};
	}

	function sampleCat(pr:Vector<Float>):Int {
		var u = rng.nextUnit();
		var acc = 0.0;
		for (k in 0...K) {
			acc += pr[k];
			if (u < acc) return k;
		}
		return K - 1;
	}

	function sampleRow(i:Int):Int {
		var u = rng.nextUnit();
		var acc = 0.0;
		for (j in 0...K) {
			acc += A[i * K + j];
			if (u < acc) return j;
		}
		return K - 1;
	}

	static function quantile(sorted:Vector<Float>, q:Float):Float {
		var n = sorted.length;
		if (n == 0) return Math.NaN;
		if (n == 1) return sorted[0];
		var pos = q * (n - 1);
		var lo = Std.int(pos);
		var hi = lo + 1 < n ? lo + 1 : lo;
		return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
	}

	static function insertionSort(a:Vector<Float>):Void {
		for (i in 1...a.length) {
			var key = a[i];
			var j = i - 1;
			while (j >= 0 && a[j] > key) {
				a[j + 1] = a[j];
				j--;
			}
			a[j + 1] = key;
		}
	}

	/** Emission mean / std of a regime (for a host's predictive band). */
	public inline function regimeMu(k:Int):Float return mu[k];
	public inline function regimeSigma(k:Int):Float return sigma[k];
	public inline function acceptRate():Float return proposed == 0 ? 0.0 : accepted / proposed;

	// ---- helpers ----

	function enforceSigmaOrder():Void {
		// insertion sort μ alongside σ so ascending-σ holds at init (K is tiny)
		for (i in 1...K) {
			var s = sigma[i];
			var m = mu[i];
			var j = i - 1;
			while (j >= 0 && sigma[j] > s) {
				sigma[j + 1] = sigma[j];
				mu[j + 1] = mu[j];
				j--;
			}
			sigma[j + 1] = s;
			mu[j + 1] = m;
		}
	}

	static function sampleStd(x:Vector<Float>):Float {
		var n = x.length;
		if (n < 2) return 0.0;
		var m = 0.0;
		for (i in 0...n) m += x[i];
		m /= n;
		var v = 0.0;
		for (i in 0...n) v += (x[i] - m) * (x[i] - m);
		return Math.sqrt(v / (n - 1));
	}
}
