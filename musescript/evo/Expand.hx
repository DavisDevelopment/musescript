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
		//
		// PSHost reductions are NOT prelude-bound: a `let ew_0__p50 = …` would shadow the aux
		// Bar.data series `ProjectionProvider.decorateBars` injects under the same name. Bare
		// identifiers in when-guards resolve to those causal aux columns (same as `sentiment`).
		if (g.projections != null && g.projections.length > 0) {
			for (r in collectProjRefs(g)) {
				var decl = findProj(g, r.name);
				if (decl == null) throw 'Expand: policy references undeclared projection "${r.name}"';
				switch (decl.sampler) {
					case PSHost(_): // bare ident → aux series; no prelude assign
					default:
						lines.push('  ${projRef(r.name, r.field)} = ${projReductionExpr(decl, r.field, g.params)}');
				}
			}
		}
		lines.push("  onBar {");
		// PanelActions emit HostABI portfolio verbs. Closed `KPd` (xs_rank) genomes also take
		// this path — never a classic long/short skeleton that ignores the cross-section.
		var action = g.panelAction != null ? g.panelAction : inferPanelActionForPd(g);
		if (action != null) {
			// Panel genomes v1: HostABI portfolio verbs with literal symbols (WASM-native).
			// No `position()`/`pos()` guards — `pos` is PANEL_HOST_ESCAPE; panel smokes leave
			// apply unguarded. Short slot unused under these templates.
			emitPanelActionBody(lines, action, g, size);
		} else {
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
		}
		lines.push("  }");
		lines.push("}");
		return lines.join("\n");
	}

	/** Emit HostABI / closed-bag panel apply lines for a panel-action template. */
	static function emitPanelActionBody(
		lines:Array<String>, action:PanelAction, g:StrategyGenome, size:String
	):Void {
		var entry = bool(g.entryLong, g.params);
		var exit = bool(g.exitLong, g.params);
		switch (action) {
			case PABuy(sym):
				lines.push('    when ($entry): { buy("$sym", $size) }');
				lines.push('    when ($exit): { sell_all("$sym") }');
			case PARebalance(syms):
				var list = [for (s in syms) '"$s"'].join(", ");
				lines.push('    when ($entry): { rebalance_equal([$list]) }');
				lines.push('    when ($exit): { ${sellAllUniverse(syms)} }');
			case PATargetWeight(sym):
				lines.push('    when ($entry): { target_weight("$sym", $size) }');
				lines.push('    when ($exit): { sell_all("$sym") }');
			case PABagScanTop(kind, window, topK, syms):
				var k = clampBagTopK(topK, syms);
				var bag = 'bag_from_scan(${panelScoreDict(kind, window, syms)}, $k)';
				lines.push('    when ($entry): { portfolio_apply($bag) }');
				lines.push('    when ($exit): { ${sellAllUniverse(syms)} }');
			case PABagRankWeights(kind, window, syms):
				var bag = 'bag_norm(bag_from_dict(${panelRankWeightDict(kind, window, syms)}))';
				lines.push('    when ($entry): { portfolio_apply($bag) }');
				lines.push('    when ($exit): { ${sellAllUniverse(syms)} }');
		}
	}

	static inline function sellAllUniverse(syms:Array<String>):String
		return [for (s in syms) 'sell_all("$s")'].join("; ");

	/** Clamp top-k into `1..|syms|` for closed bag scan templates. */
	public static function clampBagTopK(topK:Int, syms:Array<String>):Int {
		var n = syms != null ? syms.length : 0;
		if (n < 1) return 1;
		var k = topK < 1 ? 1 : topK;
		return k > n ? n : k;
	}

	/**
	 * Fixed-universe score object literal `{SYM: panel_of…, …}` — closed alternative to
	 * `dict_new`/`symbols()` loops. Keys must be safe object-literal idents
	 * (`^[A-Za-z_][A-Za-z0-9_]*$`).
	 */
	public static function panelScoreDict(kind:String, window:Int, syms:Array<String>):String {
		if (syms == null || syms.length == 0)
			throw 'Expand: panel score dict needs a non-empty universe';
		var parts = [for (s in syms) '${s}: ${panelOfExpr(kind, s, null, window > 0 ? window : null)}'];
		return '{${parts.join(", ")}}';
	}

	/**
	 * Object literal of percentile xs_rank cells for each symbol (same dual path as
	 * `pdXsRankExpr`: packed `pd_rank1d` when `|syms| ≤ PD_RANK1D_MAX`, else frame).
	 */
	public static function panelRankWeightDict(kind:String, window:Int, syms:Array<String>):String {
		if (syms == null || syms.length == 0)
			throw 'Expand: panel rank-weight dict needs a non-empty universe';
		var parts = [for (s in syms) '${s}: ${pdXsRankExpr(kind, window, s, syms)}'];
		return '{${parts.join(", ")}}';
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
					// K=1 fan: P(up move) = whether the single forecast sample exceeds the current close
					// (0 or 1). `count_true(x)` is the bool->0/1 coercion the strategy surface now has
					// (was the missing primitive that blocked this). Reference = `close`, matching
					// ForecastCloud.probUp's "probability price rises from here" semantics.
					return 'count_true((${baseE}) > close)';
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
						// Fraction of the K fan samples above the current close = P(up move), in [0,1].
						// `count_true(...)` counts the up samples (the bool->float coercion the surface now
						// has); `/K` normalizes. Replaces the old hard throw. Reference = `close`.
						var ups = [for (i in 0...K) '(${loc(z[i])}) > close'];
						'(count_true(${ups.join(", ")})) / ${num(K)}';
					default:
						throw 'Expand: unknown projection field "$field" for projection "${decl.name}"';
				};
			case PSHost(kind):
				// Should not be reached — expand() skips prelude for PSHost. Kept as a hard fail
				// so a future caller of projReductionExpr alone cannot invent a fake series expr.
				throw 'Expand: PSHost($kind) "${decl.name}" uses aux Bar.data columns '
					+ '(ProjectionProvider.decorateBars); do not inline-render host reductions';
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
				case SPanel(_, _, _, _): // literal-panel leaf — no projection prelude
				case SInd(_, _, _, src): if (src != null) addSeries(src);
				case SProj(n, f):
					var k = n + "\t" + f;
					if (!seen.exists(k)) { seen.set(k, true); out.push({ name: n, field: f }); }
			}
		}
		function addScalar(sc:ScalarNode):Void {
			switch (sc) {
				case KConst(_) | KParam(_) | KFeature(_) | KPd(_, _, _, _, _):
				case KSeries(s): addSeries(s);
				case KLookback(s, _): addSeries(s);
				case KNp(_, a, _, b):
					addSeries(a);
					if (b != null) addSeries(b);
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
					case BFeature(_): // opaque leaf: no structured series/scalar children to collect
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
			case SPanel(kind, sym, field, window): panelOfExpr(kind, sym, field, window);
		};
	}

	/**
	 * Render a fixed-universe panel leaf: `close_of("AAA")`, `mom_of("AAA", 5)`,
	 * `fund_of("AAA", "revenue")`. Shared by scalar and series Expand paths.
	 */
	public static function panelOfExpr(kind:String, sym:String, ?field:String, ?window:Int):String {
		if (kind == "fund") {
			var fname = field != null && field.length > 0 ? field : "revenue";
			if (window != null && window != 0) return 'fund_of("$sym", "$fname", $window)';
			return 'fund_of("$sym", "$fname")';
		}
		if (Palette.PANEL_OF_INDS.indexOf(kind) >= 0) {
			var w = window != null && window > 0 ? window : 14;
			return '${kind}_of("$sym", $w)';
		}
		// OHLCV*_of
		if (window != null && window != 0) return '${kind}_of("$sym", $window)';
		return '${kind}_of("$sym")';
	}

	/**
	 * Series expression usable as `window(<expr>, n)` / nesting operand — bare field
	 * for `SPrice`, full call for indicators / panel-of / proj refs.
	 */
	public static function seriesForWindow(s:SeriesNode):String {
		return switch (s) {
			case SPrice(f): f;
			case SInd(name, field, window, src):
				src != null ? '${name}(${series(src)}, $window)' : '${name}("$field", $window)';
			case SProj(pn, pf): projRef(pn, pf);
			case SPanel(kind, sym, field, window): panelOfExpr(kind, sym, field, window);
		};
	}

	/** Clamp genome window into the NP size cap (fail-closed vs WasmNpEligibility). */
	public static function clampNpWindow(window:Int):Int {
		var w = window < 1 ? 1 : window;
		return w > Palette.NP_MAX_WIN ? Palette.NP_MAX_WIN : w;
	}

	/**
	 * Closed NP Expand: `np_mean(window(close, 5))`, `np_dot(window(a,w), window(b,w))`.
	 * Never open muse.np trees — flat names only, size-capped windows.
	 */
	public static function npExpr(op:String, a:SeriesNode, window:Int, ?b:SeriesNode):String {
		var w = clampNpWindow(window);
		var wa = 'window(${seriesForWindow(a)}, $w)';
		return switch (op) {
			case "mean": 'np_mean($wa)';
			case "sum": 'np_sum($wa)';
			case "dot":
				var bb = b != null ? b : a;
				'np_dot($wa, window(${seriesForWindow(bb)}, $w))';
			default: throw 'Expand: unknown NP op "$op" (closed Palette.NP_OPS only)';
		};
	}

	/**
	 * Closed PD Expand: percentile cross-section rank of a fixed-universe score
	 * vector, or size-capped Series `pd_shift` → scalar extract.
	 *
	 * Dual xs_rank path (no open groupby/merge/HTTP):
	 * - `|syms| ≤ Palette.PD_RANK1D_MAX` (= WASM `pd_rank1d` cap): pack panel
	 *   scores into a 1-D literal and emit `pd_rank1d(..., true)` so gated genomes
	 *   can hit claimed-native `$vec_rank_pct` when eligible.
	 * - Wider / oversized universe: one-row frame `pd_xs_rank` (opaque U on WASM).
	 *
	 * Cell extract via `np_get_flat(..., i)` (NdArray is not Muse-subscriptable).
	 */
	public static function pdExpr(op:String, kind:String, window:Int, sym:String, syms:Array<String>):String {
		return switch (op) {
			case "xs_rank":
				pdXsRankExpr(kind, window, sym, syms);
			case "shift":
				pdShiftExpr(kind, window);
			default:
				throw 'Expand: unknown PD op "$op" (closed Palette.PD_OPS only)';
		};
	}

	/**
	 * Percentile xs_rank → scalar for `sym`. Prefers packed `pd_rank1d` when the
	 * universe fits the WASM N cap; otherwise the opaque one-row frame path.
	 */
	public static function pdXsRankExpr(kind:String, window:Int, sym:String, syms:Array<String>):String {
		if (syms == null || syms.length == 0)
			throw 'Expand: PD xs_rank needs a non-empty universe';
		var idx = syms.indexOf(sym);
		if (idx < 0)
			throw 'Expand: PD xs_rank symbol "$sym" not in universe';
		if (syms.length <= Palette.PD_RANK1D_MAX) {
			var scores = [for (s in syms) panelOfExpr(kind, s, null, window)];
			return 'np_get_flat(pd_rank1d([${scores.join(", ")}], true), $idx)';
		}
		var cols = [for (s in syms) '${s}: [${panelOfExpr(kind, s, null, window)}]'];
		// Frame path: pd_series_values → NdArray; Muse `[0]` does not scalarize it.
		return 'np_get_flat(pd_series_values(pd_get(pd_xs_rank(pd_from_columns({${cols.join(", ")}}), true), "$sym")), 0)';
	}

	/**
	 * Size-safe Series lag: `pd_shift(pd_series(window(field, w)), p)` then last-cell
	 * extract. `w = clamp(p+1)` so index `w-1` is always defined and equals lookback `p`.
	 */
	public static function pdShiftExpr(kind:String, periods:Int):String {
		var p = periods < 1 ? 1 : periods;
		if (p > Palette.PD_SHIFT_MAX) p = Palette.PD_SHIFT_MAX;
		if (p >= Palette.NP_MAX_WIN) p = Palette.NP_MAX_WIN - 1;
		var w = clampNpWindow(p + 1);
		var field = Palette.FIELDS.indexOf(kind) >= 0 ? kind : "close";
		var last = w - 1;
		return 'np_get_flat(pd_series_values(pd_shift(pd_series(window($field, $w)), $p)), $last)';
	}

	/** True when any policy root contains a closed `KPd` leaf. */
	public static function hasKPd(g:StrategyGenome):Bool {
		return firstKPd(g) != null;
	}

	/** True when any policy root has `KPd("xs_rank", …)` (panel fitness / target_weight coerce). */
	public static function hasKPdXsRank(g:StrategyGenome):Bool {
		var pd = firstKPd(g);
		if (pd == null) return false;
		return switch (pd) {
			case KPd("xs_rank", _, _, _, _): true;
			default: false;
		};
	}

	/**
	 * First `KPd` leaf in policy roots (entry/exit/size), or null.
	 * Used to coerce PD-bearing genomes onto panel HostABI templates.
	 */
	public static function firstKPd(g:StrategyGenome):Null<ScalarNode> {
		function wsc(n:ScalarNode):Null<ScalarNode> {
			return switch (n) {
				case KPd(_, _, _, _, _): n;
				case KArith(_, a, b):
					var xa = wsc(a);
					xa != null ? xa : wsc(b);
				case KHole(inner): wsc(inner);
				case KSeries(_) | KLookback(_, _) | KConst(_) | KParam(_) | KFeature(_) | KNp(_, _, _, _): null;
			};
		}
		function wb(n:BoolNode):Null<ScalarNode> {
			return switch (n) {
				case BCmp(_, a, b):
					var xa = wsc(a);
					xa != null ? xa : wsc(b);
				case BAnd(a, b) | BOr(a, b):
					var xa = wb(a);
					xa != null ? xa : wb(b);
				case BNot(a) | BHole(a): wb(a);
				case BCross(_, _, _) | BTrend(_, _, _) | BFeature(_): null;
			};
		}
		var hit = wb(g.entryLong);
		if (hit != null) return hit;
		hit = wb(g.entryShort);
		if (hit != null) return hit;
		hit = wb(g.exitLong);
		if (hit != null) return hit;
		hit = wb(g.exitShort);
		if (hit != null) return hit;
		return wsc(g.size);
	}

	/**
	 * When a genome has `KPd("xs_rank")` but no explicit `PanelAction`, emit `PATargetWeight`
	 * on the ranked symbol so Expand→panel fitness sees the cross-section (not single-name
	 * long/short). Size-safe `shift` leaves classic / single-name templates alone.
	 */
	public static function inferPanelActionForPd(g:StrategyGenome):Null<PanelAction> {
		var pd = firstKPd(g);
		if (pd == null) return null;
		return switch (pd) {
			case KPd("xs_rank", _, _, sym, _): PATargetWeight(sym);
			default: null;
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
					case SPanel(kind, sym, field, window): panelOfExpr(kind, sym, field, window);
				}
			case KLookback(s, k):
				switch (s) {
					case SPrice(f): '$f[$k]';
					case SPanel(kind, sym, field, _):
						// Fold lookback into the of-call (subscript on close_of is not strategy surface).
						panelOfExpr(kind, sym, field, k);
					default: '(${series(s)})[$k]';
				}
			case KFeature(name):
				name;
			case KNp(op, a, window, b):
				npExpr(op, a, window, b);
			case KPd(op, kind, window, sym, syms):
				pdExpr(op, kind, window, sym, syms);
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
			case BFeature(src): '($src)'; // opaque boolean: verbatim source, already boolean-typed
		};
	}
}
