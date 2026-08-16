package musescript.evo;

import musescript.builtins.PortfolioBuiltins;

/**
 * Rewrite closed `SPanel` leaves into plain `SPrice` / `SInd` over `field@SYM` series keys so
 * columnar NMA can evaluate panel predicates without a new `NmaKind` — same shape as
 * `ProjInline` for `PSPoint` `SProj`.
 *
 * Supported (maps onto WASM/panel packing):
 * - OHLCV `close`/`open`/`high`/`low`/`volume` with window null/0 → `SPrice("field@SYM")`
 * - `mom`/`sma`/`ema`/`rsi` with window → `SInd(kind, "close@SYM", window)` (matches
 *   `mom_of`/`sma_of`/… → indicator over `close@SYM`)
 * - `fund` with window null/0 → `SPrice("<fundField>@SYM")`
 *
 * Unsupported (returns `null` → Expand→interp/WASM): OHLCV/fund lookbacks, unknown kinds.
 * Closed bag templates are NMA-hosted separately: `PABagScanTop` (equal bag) and
 * `PABagRankWeights` (percentile xs_rank → `bag_norm` → `applyBag`). Callers keep original
 * genomes for Expand; rewrite is NMA-only.
 *
 * «ἓν ὕφασμα ἐκ πολλῶν στημόνων· μὴ σχίζε.»
 */
class PanelInline {
	/**
	 * Genome safe for `NmaBijection` / columnar NMA: every `SPanel` replaced. `null` if any
	 * leaf is outside the closed subset. Unchanged identity when there are no `SPanel`s.
	 */
	public static function forNma(g:StrategyGenome):Null<StrategyGenome> {
		if (!hasPanel(g)) return g;
		var ok = true;
		function ws(n:SeriesNode):SeriesNode {
			return switch (n) {
				case SPrice(f): SPrice(f);
				case SInd(name, field, window, src):
					SInd(name, field, window, src != null ? ws(src) : null);
				case SProj(a, b): SProj(a, b);
				case SPanel(kind, sym, field, window):
					var re = rewritePanel(kind, sym, field, window);
					if (re == null) {
						ok = false;
						n;
					} else re;
			};
		}
		function wsc(n:ScalarNode):ScalarNode {
			return switch (n) {
				case KConst(v): KConst(v);
				case KParam(i): KParam(i);
				case KFeature(name): KFeature(name);
				case KSeries(s): KSeries(ws(s));
				case KLookback(s, k):
					// Expand folds lookback into `*_of(..., k)` for SPanel; keep that closed form
					// by rewriting the leaf with window=k when the child is a bare SPanel.
					switch (s) {
						case SPanel(kind, sym, field, _):
							var re = rewritePanel(kind, sym, field, k);
							if (re == null) {
								ok = false;
								KLookback(s, k);
							} else KSeries(re); // of-call already carries lookback
						default:
							KLookback(ws(s), k);
					}
				case KNp(op, a, w, b):
					KNp(op, ws(a), w, b != null ? ws(b) : null);
				case KPd(op, kind, w, sym, syms):
					KPd(op, kind, w, sym, syms.copy());
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
		var out:StrategyGenome = {
			entryLong: wb(g.entryLong),
			entryShort: wb(g.entryShort),
			exitLong: wb(g.exitLong),
			exitShort: wb(g.exitShort),
			size: wsc(g.size),
			params: g.params,
			name: g.name,
			lineage: g.lineage,
			seedOrigin: g.seedOrigin,
			projections: g.projections,
			panelAction: g.panelAction
		};
		return ok ? out : null;
	}

	/** Series keys (`close@AAA`, …) demanded by a genome's closed `SPanel` leaves. */
	public static function seriesKeys(g:StrategyGenome):Array<String> {
		var set = new Map<String, Bool>();
		function add(k:String):Void if (k != null && k.length > 0) set.set(k, true);
		function ws(n:SeriesNode):Void switch (n) {
			case SPrice(_):
			case SInd(_, _, _, src): if (src != null) ws(src);
			case SProj(_, _):
			case SPanel(kind, sym, field, window):
				for (k in keysForPanel(kind, sym, field, window)) add(k);
		}
		function wsc(n:ScalarNode):Void switch (n) {
			case KConst(_) | KParam(_) | KFeature(_):
			case KPd(op, kind, w, _, syms):
				if (op == "xs_rank")
					for (k in keysForBagScoreUniverse(kind, w, syms)) add(k);
			case KSeries(s) | KLookback(s, _): ws(s);
			case KNp(_, a, _, b):
				ws(a);
				if (b != null) ws(b);
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
		var out = [for (k in set.keys()) k];
		out.sort(Reflect.compare);
		return out;
	}

	/** True when any policy root contains an `SPanel` leaf. */
	public static function hasPanel(g:StrategyGenome):Bool {
		function ws(n:SeriesNode):Bool return switch (n) {
			case SPanel(_, _, _, _): true;
			case SInd(_, _, _, src): src != null && ws(src);
			case SPrice(_) | SProj(_, _): false;
		};
		function wsc(n:ScalarNode):Bool return switch (n) {
			case KSeries(s) | KLookback(s, _): ws(s);
			case KNp(_, a, _, b): ws(a) || (b != null && ws(b));
			case KArith(_, a, b): wsc(a) || wsc(b);
			case KHole(inner): wsc(inner);
			case KConst(_) | KParam(_) | KFeature(_) | KPd(_, _, _, _, _): false;
		};
		function wb(n:BoolNode):Bool return switch (n) {
			case BCross(_, a, b): ws(a) || ws(b);
			case BCmp(_, a, b): wsc(a) || wsc(b);
			case BTrend(_, s, _): ws(s);
			case BAnd(a, b) | BOr(a, b): wb(a) || wb(b);
			case BNot(a) | BHole(a): wb(a);
			case BFeature(_): false;
		};
		return wb(g.entryLong) || wb(g.entryShort) || wb(g.exitLong) || wb(g.exitShort) || wsc(g.size);
	}

	/**
	 * Closed HostABI / bag panel actions NMA can drive via `PortfolioSim`.
	 * `PABagScanTop` (equal-weight top-k) and `PABagRankWeights` (percentile xs_rank →
	 * `bag_norm`) are nma-fast when `kind` packs as `SPrice`/`SInd` columns.
	 * Open `bag_rank_*` / `symbols()` never appear here (not PanelAction).
	 */
	public static function isNmaPanelAction(a:Null<PanelAction>):Bool {
		if (a == null) return false;
		return switch (a) {
			case PABuy(_) | PARebalance(_) | PATargetWeight(_): true;
			case PABagScanTop(kind, _, _, _) | PABagRankWeights(kind, _, _):
				bagScoreKindSupported(kind);
		};
	}

	/**
	 * `field@SYM` keys needed to materialize closed bag template scores from a `PanelFeed`
	 * (`PABagScanTop` / `PABagRankWeights` score dicts — same leaves as Expand `panelScoreDict`).
	 */
	public static function seriesKeysForPanelAction(a:Null<PanelAction>):Array<String> {
		if (a == null) return [];
		return switch (a) {
			case PABagScanTop(kind, window, _, syms) | PABagRankWeights(kind, window, syms):
				keysForBagScoreUniverse(kind, window, syms);
			case PABuy(_) | PARebalance(_) | PATargetWeight(_): [];
		};
	}

	/** True when bag template `kind` can be scored as packed `SPrice`/`SInd` columns. */
	public static function bagScoreKindSupported(kind:String):Bool {
		if (kind == null || kind.length == 0) return false;
		return kind == "fund"
			|| Palette.PANEL_OF_INDS.indexOf(kind) >= 0
			|| Palette.FIELDS.indexOf(kind) >= 0;
	}

	static function keysForBagScoreUniverse(kind:String, window:Int, syms:Array<String>):Array<String> {
		if (syms == null || syms.length == 0) return [];
		var set = new Map<String, Bool>();
		var w:Null<Int> = window > 0 ? window : null;
		for (sym in syms) {
			for (k in keysForPanel(kind, sym, null, w)) {
				if (k != null && k.length > 0) set.set(k, true);
			}
		}
		var out = [for (k in set.keys()) k];
		out.sort(Reflect.compare);
		return out;
	}

	static function rewritePanel(kind:String, sym:String, field:Null<String>, window:Null<Int>):Null<SeriesNode> {
		if (sym == null || sym.length == 0) return null;
		if (kind == "fund") {
			if (window != null && window != 0) return null;
			var fname = field != null && field.length > 0 ? field : "revenue";
			return SPrice(PortfolioBuiltins.seriesKey(fname, sym));
		}
		if (Palette.PANEL_OF_INDS.indexOf(kind) >= 0) {
			var w = window != null && window > 0 ? window : 14;
			return SInd(kind, PortfolioBuiltins.seriesKey("close", sym), w, null);
		}
		if (Palette.FIELDS.indexOf(kind) >= 0) {
			if (window != null && window != 0) return null;
			return SPrice(PortfolioBuiltins.seriesKey(kind, sym));
		}
		return null;
	}

	static function keysForPanel(kind:String, sym:String, field:Null<String>, window:Null<Int>):Array<String> {
		if (sym == null || sym.length == 0) return [];
		if (kind == "fund") {
			var fname = field != null && field.length > 0 ? field : "revenue";
			return [PortfolioBuiltins.seriesKey(fname, sym)];
		}
		if (Palette.PANEL_OF_INDS.indexOf(kind) >= 0)
			return [PortfolioBuiltins.seriesKey("close", sym)];
		if (Palette.FIELDS.indexOf(kind) >= 0)
			return [PortfolioBuiltins.seriesKey(kind, sym)];
		return [];
	}
}
