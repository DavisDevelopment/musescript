package musescript.ew;

import musescript.harness.Bar;
import musescript.indicators.ew.EwLattice;
import musescript.indicators.ew.EwPhiParams;
import musescript.indicators.ew.EwProject;
import musescript.indicators.geom.SwingGraph;
import musescript.indicators.geom.SwingGraphStack;
import musescript.ew.EwForecastHost.EwCountMass;
import musescript.ew.ForecastCloud.ForecastCloudUtil;

/**
 * Pragmatic soft MCMC host: multinomial samples among **already rule-valid** top-K lattice
 * rivals (mass ∝ soft score), then aggregates projected bands. Not a full Metropolis–Hastings
 * chain — cheap posterior-mass resampling of the discrete count set LatticeForecastHost already
 * exposes via `topCounts`. Hard grammar never leaves the lattice.
 */
class McmcForecastHost implements EwForecastHost {
	var inner:LatticeForecastHost;
	var params:EwPhiParams;
	var draws:Int;
	var seed:Int;
	var key:Null<String>;

	public function new(
		?params:EwPhiParams, k:Int = 5, draws:Int = 8, seed:Int = 0, ?phiKey:String
	) {
		this.params = params != null ? params : EwPhiParams.current();
		this.inner = new LatticeForecastHost(this.params, k, phiKey);
		this.draws = draws < 1 ? 1 : (draws > 32 ? 32 : draws);
		this.seed = seed;
		this.key = phiKey;
	}

	public static function withGraph(
		g:SwingGraph, ?params:EwPhiParams, k:Int = 5, draws:Int = 8, seed:Int = 0, ?phiKey:String
	):McmcForecastHost {
		var h = new McmcForecastHost(params, k, draws, seed, phiKey);
		h.inner.bindGraph(g);
		return h;
	}

	public static function withStack(
		s:SwingGraphStack, ?params:EwPhiParams, k:Int = 5, draws:Int = 8, seed:Int = 0, ?phiKey:String
	):McmcForecastHost {
		var h = new McmcForecastHost(params, k, draws, seed, phiKey);
		h.inner.bindStack(s);
		return h;
	}

	public function bindGraph(g:SwingGraph):Void inner.bindGraph(g);
	public function bindStack(s:SwingGraphStack):Void inner.bindStack(s);
	public inline function latticeRef():EwLattice return inner.latticeRef();

	public function phiKey():Null<String> return key != null ? key : inner.phiKey();

	public function onBar(bar:Bar, index:Int):Void inner.onBar(bar, index);

	public function topCounts(t:Int, kMax:Int):Array<EwCountMass> return inner.topCounts(t, kMax);

	public function cloudAt(t:Int):ForecastCloud {
		var masses = inner.topCounts(t, inner.topK());
		if (masses.length == 0) return ForecastCloudUtil.empty(0);

		// Degenerate: one rival / single draw → lattice preferred cloud (deterministic).
		if (masses.length == 1 || draws <= 1)
			return inner.cloudAt(t);

		var base = inner.cloudAt(t); // ensure rebuilt + reuse entropy / dist
		var lattice = inner.latticeRef();
		var scratch = lattice.scratch();

		var cdf:Array<Float> = [];
		var acc = 0.0;
		for (m in masses) {
			acc += Math.max(0.0, m.mass);
			cdf.push(acc);
		}
		if (acc <= 0) return base;
		for (i in 0...cdf.length) cdf[i] /= acc;

		var priceLo = Math.POSITIVE_INFINITY;
		var priceHi = Math.NEGATIVE_INFINITY;
		var barLo = Math.POSITIVE_INFINITY;
		var barHi = Math.NEGATIVE_INFINITY;
		var midSum = 0.0;
		var up = 0;
		var sampleN = 0;
		var nestSum = 0.0;
		var labelCode = 0.0;
		var labelW = -1.0;

		var ref = Math.isFinite(base.priceMid) ? base.priceMid : Math.NaN;
		var rngState = mixSeed(seed, t);
		for (_ in 0...draws) {
			var u = nextUnit(rngState);
			rngState = nextState(rngState);
			var idx = 0;
			while (idx < cdf.length - 1 && u > cdf[idx]) idx++;
			var h = lattice.at(idx);
			var band = EwProject.fromHypothesis(h, scratch, params);
			if (band == null) continue;
			sampleN++;
			if (band.priceLo < priceLo) priceLo = band.priceLo;
			if (band.priceHi > priceHi) priceHi = band.priceHi;
			if (band.barLo < barLo) barLo = band.barLo;
			if (band.barHi > barHi) barHi = band.barHi;
			var mid = (band.priceLo + band.priceHi) * 0.5;
			midSum += mid;
			if (Math.isFinite(ref) && mid > ref) up++;
			nestSum += h.nestScore;
			var w = Math.max(0.0, h.score);
			if (w >= labelW) {
				labelW = w;
				labelCode = LatticeForecastHost.labelCodeOf(h.label);
			}
		}

		if (sampleN == 0) return base;

		var priceMid = midSum / sampleN;
		var horizon = 0;
		if (Math.isFinite(barHi)) horizon = Std.int(Math.max(0, Math.ceil(barHi - t)));
		// Invalidate stays on the preferred (top-mass) rule-valid count — do not average
		// rivals into a synthetic level that no single hyp owns.
		var inv = base.invalidatePrice;

		return {
			horizon: horizon,
			priceLo: priceLo, priceHi: priceHi,
			barLo: barLo, barHi: barHi,
			priceMid: priceMid,
			spread: priceHi - priceLo,
			probUp: up / sampleN,
			topMass: masses[0].mass,
			countEntropy: base.countEntropy,
			invalidatePrice: inv,
			distToInvalidation: base.distToInvalidation,
			nestScore: nestSum / sampleN,
			labelCode: labelCode,
			samples: sampleN
		};
	}

	static inline function mixSeed(seed:Int, t:Int):Int {
		var x = seed ^ (t * 0x9E3779B9);
		x ^= (x >>> 16);
		x *= 0x7FEB352D;
		x ^= (x >>> 15);
		return x;
	}

	static inline function nextState(s:Int):Int {
		var x = s;
		x ^= (x << 13);
		x ^= (x >>> 17);
		x ^= (x << 5);
		return x;
	}

	static inline function nextUnit(s:Int):Float {
		var u = (s & 0x7fffffff) / 2147483647.0;
		return u < 0 ? -u : u;
	}
}
