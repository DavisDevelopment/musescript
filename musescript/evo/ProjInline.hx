package musescript.evo;

/**
 * Rewrite `SProj` references into plain series so columnar NMA can evaluate projection genomes
 * without a new `NmaKind` — when every referenced decl is `PSPoint` (K=1), every fan reduction
 * aliases the single series, so inlining is bit-identical to Expand's PSPoint fast path.
 *
 * `PSNoise` / `PSHost` stay on the Expand→decorate path (closed-form fan / aux columns). Returns
 * `null` when any referenced projection cannot be inlined.
 *
 * «εἷς λίθος, ἓν ῥεῦμα· μὴ διχάσῃς τὴν ὁδόν.»
 */
class ProjInline {
	/**
	 * Genome safe for `NmaBijection` / `NmaFitness`: all `SProj` leaves replaced by the underlying
	 * `PSPoint` series, `projections` cleared. `null` if the genome still needs Expand (host/noise/
	 * missing/undeclared name).
	 */
	public static function forNma(g:StrategyGenome):Null<StrategyGenome> {
		if (g.projections == null || g.projections.length == 0)
			return g;
		var refs = referencedNames(g);
		if (!refs.keys().hasNext()) {
			// Declared but unread — NMA never sees SProj; drop the inert root so Fitness does not
			// bail on `projections.length > 0`.
			return stripProjections(g);
		}
		var byName:Map<String, ProjectionDecl> = new Map();
		for (d in g.projections)
			byName.set(d.name, d);
		for (name in refs.keys()) {
			var d = byName.get(name);
			if (d == null)
				return null;
			switch (d.sampler) {
				case PSPoint(_):
				case PSNoise(_, _, _) | PSHost(_):
					return null;
			}
		}
		function ws(n:SeriesNode):SeriesNode {
			return switch (n) {
				case SPrice(f): SPrice(f);
				case SInd(name, field, window, src):
					SInd(name, field, window, src != null ? ws(src) : null);
				case SProj(name, _):
					switch (byName.get(name).sampler) {
						case PSPoint(node): ws(node);
						default: n; // unreachable — gated above
					}
				case SPanel(a, b, c, d): SPanel(a, b, c, d);
			};
		}
		function wsc(n:ScalarNode):ScalarNode {
			return switch (n) {
				case KConst(v): KConst(v);
				case KParam(i): KParam(i);
				case KFeature(name): KFeature(name);
				case KSeries(s): KSeries(ws(s));
				case KLookback(s, k): KLookback(ws(s), k);
				case KArith(op, a, b): KArith(op, wsc(a), wsc(b));
				case KHole(inner): KHole(wsc(inner));
			};
		}
		function wb(n:BoolNode):BoolNode {
			return switch (n) {
				case BCross(dir, a, b): BCross(dir, ws(a), ws(b));
				case BCmp(op, a, b): BCmp(op, wsc(a), wsc(b));
				case BTrend(dir, s, w): BTrend(dir, ws(s), w);
				case BAnd(a, b): BAnd(wb(a), wb(b));
				case BOr(a, b): BOr(wb(a), wb(b));
				case BNot(a): BNot(wb(a));
				case BHole(inner): BHole(wb(inner));
				case BFeature(src): BFeature(src);
			};
		}
		return {
			entryLong: wb(g.entryLong),
			entryShort: wb(g.entryShort),
			exitLong: wb(g.exitLong),
			exitShort: wb(g.exitShort),
			size: wsc(g.size),
			params: g.params,
			name: g.name,
			lineage: g.lineage,
			seedOrigin: g.seedOrigin,
			projections: null,
			panelAction: g.panelAction
		};
	}

	static function stripProjections(g:StrategyGenome):StrategyGenome {
		return {
			entryLong: g.entryLong,
			entryShort: g.entryShort,
			exitLong: g.exitLong,
			exitShort: g.exitShort,
			size: g.size,
			params: g.params,
			name: g.name,
			lineage: g.lineage,
			seedOrigin: g.seedOrigin,
			projections: null,
			panelAction: g.panelAction
		};
	}

	/** Names referenced by any `SProj` across the five policy roots. */
	public static function referencedNames(g:StrategyGenome):Map<String, Bool> {
		var m = new Map<String, Bool>();
		function ws(n:SeriesNode):Void switch (n) {
			case SPrice(_):
			case SInd(_, _, _, src): if (src != null) ws(src);
			case SProj(name, _): m.set(name, true);
			case SPanel(_, _, _, _):
		}
		function wsc(n:ScalarNode):Void switch (n) {
			case KConst(_) | KParam(_) | KFeature(_):
			case KSeries(s) | KLookback(s, _): ws(s);
			case KArith(_, a, b): wsc(a); wsc(b);
			case KHole(inner): wsc(inner);
		}
		function wb(n:BoolNode):Void switch (n) {
			case BCross(_, a, b): ws(a); ws(b);
			case BCmp(_, a, b): wsc(a); wsc(b);
			case BTrend(_, s, _): ws(s);
			case BAnd(a, b) | BOr(a, b): wb(a); wb(b);
			case BNot(a) | BHole(a): wb(a);
			case BFeature(_):
		}
		wb(g.entryLong);
		wb(g.entryShort);
		wb(g.exitLong);
		wb(g.exitShort);
		wsc(g.size);
		return m;
	}
}
