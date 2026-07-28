package musescript.evo;

import musescript.harness.Bar;

/**
 * Leakage-free forecast-skill scoring for a genome's projections (PROJECTION_COEVOLUTION_PLAN.md §6).
 *
 * A projection's CENTRAL forecast series `p_t` (its `p50`/`mean`) is PIT-causal — built from data
 * `≤ t` by the same columnar indicator tier the strategy uses (`NmaFitness.seriesColumnOf`). The
 * realized target `y_t` for the projection's `kind`/`horizon` is derived from bars STRICTLY AFTER `t`.
 * Skill is the association between the two: rank-IC (Spearman) for continuous kinds, directional
 * accuracy for `PDirection`, over the bars that have a target (the last `H` bars are excluded — no
 * future to score against). **Future data appears ONLY here, never in the eval the policy consumes.**
 *
 * This is the fitness SIGNAL for forecast quality; how it feeds selection (a MAP-Elites descriptor
 * axis per §7) and its out-of-sample / purge-embargo reporting are the next slices. The guarantee at
 * this layer is that `p_t ⊥ future` and `y_t ⊂ future` — a projection that could see ahead is a bug.
 *
 * «τὸ μέλλον σκιά· μέτρησον, μὴ μαντεύου.»
 */
class ProjectionScore {
	/**
	 * Aggregate skill (mean of finite per-projection skills) + the per-projection breakdown, aligned
	 * to `g.projections`. Only REFERENCED projections are scored — an unread forecast has no effect on
	 * behaviour and earns no skill. `agg` is `NaN` when nothing is scoreable.
	 */
	public static function score(
		g:StrategyGenome, bars:Array<Bar>, ?provider:ProjectionProvider
	):{agg:Float, per:Array<Float>} {
		var per:Array<Float> = [];
		if (g.projections == null || g.projections.length == 0)
			return {agg: Math.NaN, per: per};
		var refs = referencedNames(g);
		var sum = 0.0;
		var cnt = 0;
		for (decl in g.projections) {
			var s = refs.exists(decl.name) ? skill(decl, g.params, bars, provider) : Math.NaN;
			per.push(s);
			if (finite(s)) {
				sum += s;
				cnt++;
			}
		}
		return {agg: cnt > 0 ? sum / cnt : Math.NaN, per: per};
	}

	/** Skill of one projection: rank-IC (or directional accuracy for `PDirection`) of its central
	 * forecast vs the realized target. `NaN` when the forecast can't be evaluated or there's no signal.
	 * Host-backed (`PSHost`) projections need a `ProjectionProvider` with an `EwForecastHost`. */
	public static function skill(
		decl:ProjectionDecl, params:Array<EvoParam>, bars:Array<Bar>, ?provider:ProjectionProvider
	):Float {
		var p = centralSeries(decl, params, bars, provider);
		if (p == null)
			return Math.NaN;
		var y = realizedTarget(bars, decl.kind, decl.horizon < 1 ? 1 : decl.horizon);
		var point = switch (decl.kind) {
			case PDirection: directionalSkill(p, y);
			default: rankIC(p, y);
		};
		// Host projections: blend forward point skill with band coverage so UQ width is scored
		// without rewarding hard-rule soft hits (lattice already ranked those into the cloud).
		if (decl.sampler.match(PSHost(_)) && provider != null) {
			var cov = provider.bandCoverage(bars, decl.horizon < 1 ? 1 : decl.horizon);
			if (finite(cov)) {
				var covSkill = 2.0 * cov - 1.0; // map [0,1] → [-1,1]
				if (finite(point))
					return 0.5 * point + 0.5 * covSkill;
				return covSkill;
			}
		}
		return point;
	}

	/** The projection's central (median) forecast series over the tape; `null` if un-evaluable. */
	public static function centralSeries(
		decl:ProjectionDecl, params:Array<EvoParam>, bars:Array<Bar>, ?provider:ProjectionProvider
	):Array<Float> {
		try {
			return switch (decl.sampler) {
				case PSPoint(node):
					musescript.evo.nma.NmaFitness.seriesColumnOf(node, bars, params);
				case PSNoise(base, vol, model):
					var baseCol = musescript.evo.nma.NmaFitness.seriesColumnOf(base, bars, params);
					var volCol = musescript.evo.nma.NmaFitness.scalarColumnOf(vol, bars, params);
					var k = decl.samples < 1 ? 1 : decl.samples;
					var c50 = McFan.quantile(McFan.sortedCopy(McFan.shocks(decl.seed, k, model)), 0.5);
					var n = baseCol.length < volCol.length ? baseCol.length : volCol.length;
					[for (i in 0...n) baseCol[i] + c50 * volCol[i]];
				case PSHost(_):
					if (provider == null)
						return null;
					provider.fieldColumn("p50", bars);
			};
		} catch (e:Dynamic) {
			return null;
		}
	}

	/** Realized target `y_t` from bars STRICTLY after `t`. `y_t = NaN` for the last `h` bars. */
	public static function realizedTarget(bars:Array<Bar>, kind:ProjKind, h:Int):Array<Float> {
		var n = bars.length;
		var close = [for (b in bars) b.close];
		var out = [for (_ in 0...n) Math.NaN];
		var t = 0;
		while (t < n - h) {
			out[t] = switch (kind) {
				case PReturn: close[t] != 0 ? close[t + h] / close[t] - 1 : Math.NaN;
				case PLevel: close[t + h];
				case PDirection: sign(close[t + h] - close[t]);
				case PVol: realizedVol(close, t, h);
				case PRange: forwardRange(bars, t, h);
			};
			t++;
		}
		return out;
	}

	// ---------- metrics (pure, unit-tested directly) ----------

	/** Spearman rank correlation over pairs where both are finite; 0 when insufficient/degenerate. */
	public static function rankIC(p:Array<Float>, y:Array<Float>):Float {
		var xs:Array<Float> = [];
		var ys:Array<Float> = [];
		var n = p.length < y.length ? p.length : y.length;
		for (i in 0...n)
			if (finite(p[i]) && finite(y[i])) {
				xs.push(p[i]);
				ys.push(y[i]);
			}
		if (xs.length < 3)
			return 0;
		return pearson(ranks(xs), ranks(ys));
	}

	/** Directional skill in [-1,1]: `2·accuracy − 1` over pairs with a defined sign on the target. */
	public static function directionalSkill(p:Array<Float>, y:Array<Float>):Float {
		var acc = directionalAccuracy(p, y);
		return finite(acc) ? 2.0 * acc - 1.0 : Math.NaN;
	}

	/** Directional accuracy in [0,1]: fraction of bars where `sign(p)` matches `sign(y)`. */
	public static function directionalAccuracy(p:Array<Float>, y:Array<Float>):Float {
		var n = p.length < y.length ? p.length : y.length;
		var ok = 0;
		var tot = 0;
		for (i in 0...n) {
			if (!finite(p[i]) || !finite(y[i]))
				continue;
			var sy = sign(y[i]);
			if (sy == 0)
				continue; // no move to predict
			tot++;
			if (sign(p[i]) == sy)
				ok++;
		}
		return tot == 0 ? Math.NaN : ok / tot;
	}

	/**
	 * Interpretable predictive hit-rate in [0,1] for a projection: directional accuracy of the
	 * forecasted move (`p_t − close_t` vs `close_{t+H} − close_t`). Prefer this for on-screen
	 * "predictive accuracy"; `skill` remains the selection signal (rank-IC / blended coverage).
	 */
	public static function hitRate(
		decl:ProjectionDecl, params:Array<EvoParam>, bars:Array<Bar>, ?provider:ProjectionProvider
	):Float {
		var p = centralSeries(decl, params, bars, provider);
		if (p == null)
			return Math.NaN;
		var h = decl.horizon < 1 ? 1 : decl.horizon;
		var n = p.length < bars.length ? p.length : bars.length;
		var pred:Array<Float> = [];
		var real:Array<Float> = [];
		var t = 0;
		while (t < n - h) {
			if (finite(p[t]) && finite(bars[t].close) && finite(bars[t + h].close)) {
				pred.push(p[t] - bars[t].close);
				real.push(bars[t + h].close - bars[t].close);
			}
			t++;
		}
		return directionalAccuracy(pred, real);
	}

	/**
	 * Aggregate hit-rate over REFERENCED projections (mean of finite). `NaN` when nothing scoreable.
	 * Host genomes: also blend band coverage when a provider is bound (same honesty as `skill`).
	 */
	public static function hitRateAgg(
		g:StrategyGenome, bars:Array<Bar>, ?provider:ProjectionProvider
	):Float {
		if (g.projections == null || g.projections.length == 0)
			return Math.NaN;
		var refs = referencedNames(g);
		var sum = 0.0;
		var cnt = 0;
		for (decl in g.projections) {
			if (!refs.exists(decl.name))
				continue;
			var hr = hitRate(decl, g.params, bars, provider);
			if (decl.sampler.match(PSHost(_)) && provider != null) {
				var cov = provider.bandCoverage(bars, decl.horizon < 1 ? 1 : decl.horizon);
				if (finite(hr) && finite(cov))
					hr = 0.5 * hr + 0.5 * cov;
				else if (finite(cov))
					hr = cov;
			}
			if (finite(hr)) {
				sum += hr;
				cnt++;
			}
		}
		return cnt > 0 ? sum / cnt : Math.NaN;
	}

	// ---------- helpers ----------

	static inline function sign(x:Float):Float
		return x > 0 ? 1 : (x < 0 ? -1 : 0);

	static inline function finite(x:Float):Bool
		return !Math.isNaN(x) && Math.isFinite(x);

	static function realizedVol(close:Array<Float>, t:Int, h:Int):Float {
		var rets:Array<Float> = [];
		var i = t;
		while (i < t + h) {
			if (close[i] > 0 && close[i + 1] > 0)
				rets.push(Math.log(close[i + 1] / close[i]));
			i++;
		}
		if (rets.length < 2)
			return Math.NaN;
		var m = 0.0;
		for (r in rets)
			m += r;
		m /= rets.length;
		var v = 0.0;
		for (r in rets)
			v += (r - m) * (r - m);
		v /= rets.length - 1;
		return Math.sqrt(v);
	}

	static function forwardRange(bars:Array<Bar>, t:Int, h:Int):Float {
		var hi = bars[t + 1].high;
		var lo = bars[t + 1].low;
		var i = t + 1;
		while (i <= t + h) {
			if (bars[i].high > hi)
				hi = bars[i].high;
			if (bars[i].low < lo)
				lo = bars[i].low;
			i++;
		}
		return hi - lo;
	}

	/** Fractional ranks (average rank for ties). */
	static function ranks(a:Array<Float>):Array<Float> {
		var n = a.length;
		var idx = [for (i in 0...n) i];
		idx.sort(function(i, j) return a[i] < a[j] ? -1 : (a[i] > a[j] ? 1 : 0));
		var r = [for (_ in 0...n) 0.0];
		var i = 0;
		while (i < n) {
			var j = i;
			while (j + 1 < n && a[idx[j + 1]] == a[idx[i]])
				j++;
			var avg = (i + j) / 2.0;
			var k = i;
			while (k <= j) {
				r[idx[k]] = avg;
				k++;
			}
			i = j + 1;
		}
		return r;
	}

	static function pearson(x:Array<Float>, y:Array<Float>):Float {
		var n = x.length;
		var mx = 0.0;
		var my = 0.0;
		for (i in 0...n) {
			mx += x[i];
			my += y[i];
		}
		mx /= n;
		my /= n;
		var sxy = 0.0;
		var sxx = 0.0;
		var syy = 0.0;
		for (i in 0...n) {
			var dx = x[i] - mx;
			var dy = y[i] - my;
			sxy += dx * dy;
			sxx += dx * dx;
			syy += dy * dy;
		}
		return (sxx <= 0 || syy <= 0) ? 0 : sxy / Math.sqrt(sxx * syy);
	}

	/** Names of projections referenced by an `SProj` anywhere across the five policy roots. */
	static function referencedNames(g:StrategyGenome):Map<String, Bool> {
		var m = new Map<String, Bool>();
		function ws(n:SeriesNode):Void switch (n) {
			case SPrice(_):
			case SInd(_, _, _, src): if (src != null) ws(src);
			case SProj(name, _): m.set(name, true);
		}
		function wsc(n:ScalarNode):Void switch (n) {
			case KConst(_) | KParam(_) | KFeature(_):
			case KSeries(s): ws(s);
			case KLookback(s, _): ws(s);
			case KArith(_, a, b): wsc(a); wsc(b);
			case KHole(inner): wsc(inner);
		}
		function wb(n:BoolNode):Void switch (n) {
			case BCross(_, a, b): ws(a); ws(b);
			case BCmp(_, a, b): wsc(a); wsc(b);
			case BTrend(_, s, _): ws(s);
			case BAnd(a, b) | BOr(a, b): wb(a); wb(b);
			case BNot(a): wb(a);
			case BHole(inner): wb(inner);
		}
		wb(g.entryLong);
		wb(g.entryShort);
		wb(g.exitLong);
		wb(g.exitShort);
		wsc(g.size);
		return m;
	}
}
