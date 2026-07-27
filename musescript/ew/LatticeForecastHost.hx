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
 * MVP adapter: live / pre-fed SwingGraph(+Stack) + EwLattice → ForecastCloud.
 *
 * Hard grammar stays inside the lattice; this host only aggregates rule-valid
 * top-K rivals into cloud reductions (bands, invalidate, entropy, nest).
 * Never invents labels when the lattice finds nothing.
 */
class LatticeForecastHost implements EwForecastHost {
	var graph:Null<SwingGraph>;
	var stack:Null<SwingGraphStack>;
	var lattice:EwLattice;
	var params:EwPhiParams;
	var k:Int;
	var key:Null<String>;
	var lastClose:Float;
	var lastRebuildAt:Int;
	var dirty:Bool;

	public function new(?params:EwPhiParams, k:Int = 3, ?phiKey:String) {
		this.params = params != null ? params : EwPhiParams.current();
		this.lattice = new EwLattice(this.params);
		this.k = k < 1 ? 1 : (k > 8 ? 8 : k);
		this.key = phiKey;
		this.graph = null;
		this.stack = null;
		this.lastClose = Math.NaN;
		this.lastRebuildAt = -1;
		this.dirty = true;
	}

	public static function withGraph(
		g:SwingGraph, ?params:EwPhiParams, k:Int = 3, ?phiKey:String
	):LatticeForecastHost {
		var h = new LatticeForecastHost(params, k, phiKey);
		h.graph = g;
		return h;
	}

	public static function withStack(
		s:SwingGraphStack, ?params:EwPhiParams, k:Int = 3, ?phiKey:String
	):LatticeForecastHost {
		var h = new LatticeForecastHost(params, k, phiKey);
		h.stack = s;
		return h;
	}

	public function bindGraph(g:SwingGraph):Void {
		graph = g;
		stack = null;
		dirty = true;
	}

	public function bindStack(s:SwingGraphStack):Void {
		stack = s;
		graph = null;
		dirty = true;
	}

	public inline function latticeRef():EwLattice return lattice;
	public inline function topK():Int return k;

	public function phiKey():Null<String> return key;

	public function onBar(bar:Bar, index:Int):Void {
		lastClose = bar.close;
		if (stack != null) stack.update(bar);
		else if (graph != null) graph.update(bar);
		dirty = true;
	}

	public function cloudAt(t:Int):ForecastCloud {
		ensureRebuilt(t);
		return assembleCloud(t);
	}

	public function topCounts(t:Int, kMax:Int):Array<EwCountMass> {
		ensureRebuilt(t);
		var lim = kMax < 1 ? 1 : kMax;
		var n = lattice.hypothesisCount();
		if (n > lim) n = lim;
		var out:Array<EwCountMass> = [];
		var sum = scoreSum(n);
		for (i in 0...n) {
			var h = lattice.at(i);
			out.push({
				label: h.label,
				mass: Math.max(0.0, h.score) / sum,
				score: h.score,
				invalidatePrice: h.invalidatePrice,
				nestScore: h.nestScore,
				degree: h.degree
			});
		}
		return out;
	}

	function ensureRebuilt(t:Int):Void {
		if (!dirty && lastRebuildAt == t) return;
		if (stack != null) lattice.rebuildStack(stack, k);
		else if (graph != null) lattice.rebuild(graph, k);
		else {
			lastRebuildAt = t;
			dirty = false;
			return;
		}
		lastRebuildAt = t;
		dirty = false;
	}

	function assembleCloud(t:Int):ForecastCloud {
		var n = lattice.hypothesisCount();
		if (n <= 0) return ForecastCloudUtil.empty(0);

		var scratch = lattice.scratch();
		var sum = scoreSum(n);
		var pref = lattice.at(0);

		var priceLo = Math.POSITIVE_INFINITY;
		var priceHi = Math.NEGATIVE_INFINITY;
		var barLo = Math.POSITIVE_INFINITY;
		var barHi = Math.NEGATIVE_INFINITY;
		var sampleN = 0;
		var massSumProj = 0.0;
		var midWeighted = 0.0;
		var upMass = 0.0;

		var ref = Math.isFinite(lastClose) ? lastClose : Math.NaN;

		for (i in 0...n) {
			var h = lattice.at(i);
			var band = EwProject.fromHypothesis(h, scratch, params);
			if (band == null) continue;
			sampleN++;
			if (band.priceLo < priceLo) priceLo = band.priceLo;
			if (band.priceHi > priceHi) priceHi = band.priceHi;
			if (band.barLo < barLo) barLo = band.barLo;
			if (band.barHi > barHi) barHi = band.barHi;
			var m = Math.max(0.0, h.score) / sum;
			var mid = (band.priceLo + band.priceHi) * 0.5;
			massSumProj += m;
			midWeighted += m * mid;
			if (Math.isFinite(ref) && mid > ref) upMass += m;
		}

		// Preferred-only last-leg fallback when no hyp projected (still rule-valid count).
		if (sampleN == 0) {
			var fallback = null;
			if (stack != null) fallback = EwProject.fromLastLeg(stack.fine, params);
			else if (graph != null) fallback = EwProject.fromLastLeg(graph, params);
			if (fallback != null) {
				priceLo = fallback.priceLo;
				priceHi = fallback.priceHi;
				barLo = fallback.barLo;
				barHi = fallback.barHi;
				sampleN = 1;
				massSumProj = 1.0;
				midWeighted = (priceLo + priceHi) * 0.5;
				if (Math.isFinite(ref) && midWeighted > ref) upMass = 1.0;
			}
		}

		if (sampleN == 0) {
			// Count mass / invalidate still useful; no invented band.
			return {
				horizon: 0,
				priceLo: Math.NaN, priceHi: Math.NaN,
				barLo: Math.NaN, barHi: Math.NaN,
				priceMid: Math.NaN, spread: Math.NaN,
				probUp: Math.NaN,
				topMass: Math.max(0.0, pref.score) / sum,
				countEntropy: entropyFromScores(n, sum),
				invalidatePrice: pref.invalidatePrice,
				distToInvalidation: distToInv(pref.invalidatePrice, ref),
				nestScore: pref.nestScore,
				labelCode: labelCodeOf(pref.label),
				samples: 1
			};
		}

		var priceMid = massSumProj > 0 ? midWeighted / massSumProj : (priceLo + priceHi) * 0.5;
		if (!Math.isFinite(ref)) ref = priceMid;

		var horizon = 0;
		if (Math.isFinite(barHi)) horizon = Std.int(Math.max(0, Math.ceil(barHi - t)));

		var probUp = Math.NaN;
		if (Math.isFinite(ref) && massSumProj > 0) probUp = upMass / massSumProj;

		return {
			horizon: horizon,
			priceLo: priceLo, priceHi: priceHi,
			barLo: barLo, barHi: barHi,
			priceMid: priceMid,
			spread: priceHi - priceLo,
			probUp: probUp,
			topMass: Math.max(0.0, pref.score) / sum,
			countEntropy: entropyFromScores(n, sum),
			invalidatePrice: pref.invalidatePrice,
			distToInvalidation: distToInv(pref.invalidatePrice, ref),
			nestScore: pref.nestScore,
			labelCode: labelCodeOf(pref.label),
			samples: sampleN
		};
	}

	function scoreSum(n:Int):Float {
		var sum = 0.0;
		for (i in 0...n) sum += Math.max(0.0, lattice.at(i).score);
		return sum > 0 ? sum : 1.0;
	}

	/** Shannon entropy (nats) over score-mass of top-K rivals. */
	function entropyFromScores(n:Int, sum:Float):Float {
		if (n <= 1) return 0.0;
		var ent = 0.0;
		for (i in 0...n) {
			var m = Math.max(0.0, lattice.at(i).score) / sum;
			if (m > 0) ent -= m * Math.log(m);
		}
		return ent;
	}

	function distToInv(inv:Float, ref:Float):Float {
		if (!Math.isFinite(inv)) return Math.NaN;
		var r = Math.isFinite(ref) ? ref : lastClose;
		if (!Math.isFinite(r)) r = inv;
		var scale = atrishScale();
		if (!(scale > 0) || !Math.isFinite(scale))
			scale = Math.max(1e-12, Math.abs(r) * 0.01);
		return Math.abs(r - inv) / scale;
	}

	function atrishScale():Float {
		var n = lattice.scratchLen();
		if (n < 2) return Math.NaN;
		var scratch = lattice.scratch();
		var sum = 0.0;
		for (i in 1...n) sum += Math.abs(scratch[i].price - scratch[i - 1].price);
		return sum / (n - 1);
	}

	/** Stable opaque codes aligned with EwHypothesisIndicator (viz / columns). */
	public static function labelCodeOf(label:String):Float {
		return switch (label) {
			case "zigzag": 1.0;
			case "impulse5": 2.0;
			case "flat", "flat_expanded", "flat_running": 3.0;
			case "diagonal", "diagonal_ending": 4.0;
			case "triangle": 5.0;
			case "double_zigzag": 6.0;
			case "diagonal_leading": 7.0;
			case "impulse5_trunc": 8.0;
			case "impulse5_ext1": 9.0;
			case "impulse5_ext3": 10.0;
			case "impulse5_ext5": 11.0;
			case "double_three": 12.0;
			case "triangle_expanding": 13.0;
			default: 0.0;
		};
	}
}
