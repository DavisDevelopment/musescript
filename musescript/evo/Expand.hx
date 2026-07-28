package musescript.evo;

/**
 * Deterministic MuseGene -> MuseScript expansion.
 *
 * Emits the MODERN typed surface (`strategy Name(...) { onBar { when cond: { ... } } }`),
 * NOT the legacy `{ @strategy("Name") @on(bar) { if (...) ...; } }` hscript-annotation dialect
 * this used to emit -- switched because (a) nobody hand-writes the annotation dialect anymore
 * (every real file under corpus/strategies/ already uses the modern surface) and (b) the
 * annotation dialect's braceless `if (cond) long(qty);` doesn't reverse-compile through
 * CorpusSeed.translateBool/translateStrategy at all (`guardedOrders` only recognizes `When`/the
 * general-`if` `EIf` shape with an `EBlock` then-branch, both modern-surface constructs) -- a real
 * gap surfaced by HumanLoopWindow's edit-source round trip, but really a pre-existing mismatch
 * between this file's OWN output and CorpusSeed's expectations any caller doing a Fitness.evaluate
 * -> Expand.expand -> CorpusSeed.translateSource round trip would have hit. `MuseParser.parse`
 * auto-dispatches to `StrategyParser` via `StrategyParser.looksLike` (checks for a leading
 * `strategy` token), so every EXISTING caller of `Expand.expand` (Fitness.evaluate, CorpusEvoRun's
 * champion printout, GeneRunner) needs zero changes -- same `new MuseParser().parse(...)` entry
 * point, it just now routes to the other front-end.
 */
class Expand {
	public static function expand(g:StrategyGenome):String {
		var paramList = g.params.length == 0 ? "" :
			"(" + [for (p in g.params) '${p.name} = ${num(p.defaultValue)}'].join(", ") + ")";
		var size = scalar(g.size, g.params);
		var lines = ['strategy ${g.name}$paramList {'];
		// Projection fields sit at strategy-body level (re-evaluated each bar, in scope for the onBar
		// guards — the same shape corpus strategies use for `maFast = sma(close, 5)`). Emitted ONLY
		// for projections the policy actually references, so a declared-but-unread projection stays
		// byte-inert (the P0.a parity contract). PROJECTION_COEVOLUTION_PLAN.md §4.
		if (g.projections != null && g.projections.length > 0) {
			for (r in collectProjRefs(g)) {
				var decl = findProj(g, r.name);
				if (decl == null) throw 'Expand: policy references undeclared projection "${r.name}"';
				lines.push('  ${projRef(r.name, r.field)} = ${projReductionExpr(decl, r.field, g.params)}');
			}
		}
		lines.push("  onBar {");
		// Guarded on `position()` so a STICKY entry condition (BCmp/BTrend-based, e.g. `rsi(...) <
		// 55` staying true for many consecutive bars -- unlike a transient crossover, which only
		// fires once) doesn't re-fire `long`/`short` every single bar it holds and pyramid an
		// unbounded position. `long`/`short` themselves stay generically additive at the LANGUAGE
		// level (a hand-written strategy that WANTS pyramiding can still call them directly,
		// unguarded) -- this guard is specific to genome-EXPANDED source, where `size` is meant as
		// a target exposure, not a per-bar increment. `<= 0`/`>= 0` (not `== 0`) deliberately still
		// allows a same-bar REVERSAL (short flips to long, long flips to short) to fire -- only
		// same-direction re-entry is blocked, matching executeLong/executeShort's own existing
		// "close the opposite side first" behavior.
		lines.push('    when (${bool(g.entryLong, g.params)}) && position() <= 0: { long($size) }');
		lines.push('    when (${bool(g.entryShort, g.params)}) && position() >= 0: { short($size) }');
		lines.push('    when (${bool(g.exitLong, g.params)}) || (${bool(g.exitShort, g.params)}): { flat() }');
		lines.push("  }");
		lines.push("}");
		return lines.join("\n");
	}

	static function num(x:Float):String {
		if (x == Std.int(x)) return Std.string(Std.int(x));
		return Std.string(x);
	}

	/** A projection fan-reduction (`SProj`) renders as the bare `let` identifier it binds to in the
	 * onBar prelude (`proj_0__p50`), NOT a quoted field like `SPrice` — it is a variable, not a
	 * price-field name. See PROJECTION_COEVOLUTION_PLAN.md §3-§4. */
	public static inline function projRef(name:String, field:String):String return '${name}__${field}';

	static function findProj(g:StrategyGenome, name:String):Null<ProjectionDecl> {
		if (g.projections == null) return null;
		for (p in g.projections) if (p.name == name) return p;
		return null;
	}

	/** Render one fan-reduction of a projection as a series expression for its prelude field.
	 * `PSPoint` (K=1): every reduction (`p50`/`mean`/`sample_0`/…) IS the single series, so reuse the
	 * scalar-context series renderer. `PSNoise` fans need the MC builtin (P1.5) — not renderable yet. */
	static function projReductionExpr(decl:ProjectionDecl, field:String, params:Array<EvoParam>):String {
		switch (decl.sampler) {
			case PSPoint(node):
				// K=1: every location reduction is the single series; spread is 0; only sample_0 exists.
				var baseE = scalar(KSeries(node), params);
				if (field == "spread") return "0";
				if (field == "prob_up")
					// Owed: the strategy surface has no ternary/bool→float, so prob_up needs a dedicated
					// builtin (deliberately avoided to keep fan reductions pure arithmetic). See plan §6.
					throw 'Expand: prob_up is not yet renderable (needs a builtin) for "${decl.name}"';
				if (StringTools.startsWith(field, "sample_")) {
					var i = Std.parseInt(field.substr(7));
					if (i != 0)
						throw 'Expand: $field out of range for point projection "${decl.name}" (K=1)';
				}
				return baseE;
			case PSNoise(base, vol, model):
				// Location-scale fan: reductions are closed-form `base + coef*vol` with the coefficient
				// a seed-fixed shock statistic (McFan). Exact, deterministic, pure arithmetic.
				var K = decl.samples < 1 ? 1 : decl.samples;
				var z = McFan.shocks(decl.seed, K, model); // throws for NBlockBootstrap (owed)
				var zs = McFan.sortedCopy(z);
				var baseE = scalar(KSeries(base), params);
				var volE = scalar(vol, params);
				function loc(coef:Float):String return '(${baseE}) + (${num(coef)}) * (${volE})';
				if (StringTools.startsWith(field, "sample_")) {
					var i = Std.parseInt(field.substr(7));
					if (i == null || i < 0 || i >= K)
						throw 'Expand: $field out of range for projection "${decl.name}" (K=$K)';
					return loc(z[i]);
				}
				return switch (field) {
					case "mean": loc(McFan.mean(z));
					case "p05": loc(McFan.quantile(zs, 0.05));
					case "p25": loc(McFan.quantile(zs, 0.25));
					case "p50": loc(McFan.quantile(zs, 0.50));
					case "p75": loc(McFan.quantile(zs, 0.75));
					case "p95": loc(McFan.quantile(zs, 0.95));
					case "spread": '(${num(McFan.quantile(zs, 0.95) - McFan.quantile(zs, 0.05))}) * (${volE})';
					case "prob_up":
						// Owed: a K-term count needs ternary/bool→float, which the strategy surface lacks;
						// this reduction wants a dedicated builtin (fan reductions stay pure arithmetic). §6.
						throw 'Expand: prob_up is not yet renderable (needs a builtin) for "${decl.name}"';
					default:
						throw 'Expand: unknown projection field "$field" for projection "${decl.name}"';
				};
			case PSHost(kind):
				// Host clouds are columnar via ProjectionProvider — no MuseScript prelude yet
				// (needs a host builtin or interp column injection). Boundary X score path works.
				throw 'Expand: PSHost($kind) projection "${decl.name}" is host-backed; '
					+ 'use ProjectionProvider columns (Expand trading prelude not wired)';
		}
	}

	/** Referenced (projection name, fan field) pairs across the policy trees, in first-appearance
	 * order, de-duplicated. Only these get a prelude field; unread projections stay inert. Walks the
	 * policy roots only (P0.b samplers reference market data, not other projections — cross-projection
	 * DAG refs are a later concern). */
	static function collectProjRefs(g:StrategyGenome):Array<{name:String, field:String}> {
		var out:Array<{name:String, field:String}> = [];
		var seen = new Map<String, Bool>();
		function addSeries(s:SeriesNode):Void {
			switch (s) {
				case SPrice(_):
				case SInd(_, _, _, src): if (src != null) addSeries(src);
				case SProj(n, f):
					var k = n + "\t" + f;
					if (!seen.exists(k)) { seen.set(k, true); out.push({ name: n, field: f }); }
			}
		}
		function addScalar(sc:ScalarNode):Void {
			switch (sc) {
				case KConst(_) | KParam(_) | KFeature(_):
				case KSeries(s): addSeries(s);
				case KLookback(s, _): addSeries(s);
				case KArith(_, a, b): addScalar(a); addScalar(b);
				case KHole(inner): addScalar(inner);
			}
		}
		function addBool(b:BoolNode):Void {
			switch (b) {
				case BCross(_, a, bb): addSeries(a); addSeries(bb);
				case BCmp(_, a, bb): addScalar(a); addScalar(bb);
				case BTrend(_, s, _): addSeries(s);
				case BAnd(a, bb) | BOr(a, bb): addBool(a); addBool(bb);
				case BNot(a): addBool(a);
				case BHole(inner): addBool(inner);
			}
		}
		addBool(g.entryLong); addBool(g.entryShort); addBool(g.exitLong); addBool(g.exitShort);
		addScalar(g.size);
		return out;
	}

	public static function series(n:SeriesNode):String {
		return switch (n) {
			case SPrice(f): '"' + f + '"';
			case SInd(name, field, window, src):
				if (src != null) '${name}(${series(src)}, $window)';
				else '${name}("$field", $window)';
			case SProj(pn, pf): projRef(pn, pf);
		};
	}

	public static function scalar(n:ScalarNode, params:Array<EvoParam>):String {
		return switch (n) {
			case KConst(v): num(v);
			case KParam(i): params[i].name;
			case KSeries(s):
				switch (s) {
					case SPrice(f): f;
					case SInd(name, field, window, src):
						src != null ? '${name}(${series(src)}, $window)' : '${name}("$field", $window)';
					case SProj(pn, pf): projRef(pn, pf);
				}
			case KLookback(s, k):
				switch (s) {
					case SPrice(f): '$f[$k]';
					default: '(${series(s)})[$k]';
				}
			case KFeature(name):
				name;
			case KArith(op, a, b):
				var as = scalar(a, params);
				var bs = scalar(b, params);
				if (op == "min" || op == "max") return '$op($as, $bs)';
				'($as $op $bs)';
			// Transparent: a hole is a mutation-eligibility marker only, invisible to the emitted
			// MuseScript -- see BoolNode.BHole's doc comment.
			case KHole(inner): scalar(inner, params);
		};
	}

	public static function bool(n:BoolNode, params:Array<EvoParam>):String {
		return switch (n) {
			case BCross(dir, a, b):
				var fn = dir == "over" ? "crossover" : "crossunder";
				'$fn(${series(a)}, ${series(b)})';
			case BCmp(op, a, b):
				'(${scalar(a, params)} $op ${scalar(b, params)})';
			case BTrend(dir, s, w):
				// dir is "over"/"under" (the SAME Palette.CROSS pool BCross's dir is drawn from
				// -- Variation.growBool literally does `rng.pick(Palette.CROSS)` for both), NOT
				// "up"/"down". This case used to check `dir == "up"`, which is never true for
				// any BTrend this codebase actually constructs (Variation.hx, CorpusSeed.hx) --
				// every BTrend genome, grown or reverse-compiled, silently rendered as "falling"
				// regardless of its real dir. Found via a corpus-evo walk-forward run reporting
				// suspiciously identical champion stats across unrelated genomes/tapes; traced
				// to this always-false comparison.
				var fn = dir == "over" ? "rising" : "falling";
				'$fn(${series(s)}, $w)';
			case BAnd(a, b): '(${bool(a, params)} && ${bool(b, params)})';
			case BOr(a, b): '(${bool(a, params)} || ${bool(b, params)})';
			case BNot(a): '(!${bool(a, params)})';
			case BHole(inner): bool(inner, params); // see scalar's KHole case
		};
	}
}
