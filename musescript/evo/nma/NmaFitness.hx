package musescript.evo.nma;

import musescript.evo.StrategyGenome;
import musescript.evo.FitnessResult;
import musescript.evo.PanelAction;
import musescript.evo.PanelInline;
import musescript.evo.Expand;
import musescript.evo.Palette;
import musescript.evo.SeriesNode;
import musescript.builtins.PortfolioBuiltins;
import musescript.builtins.BagBuiltins;
import musescript.dataframe.GroupBy;
import musescript.ndarray.NdArrayF64;
import musescript.harness.Bar;
import musescript.harness.OrderSim;
import musescript.harness.PanelFeed;
import musescript.harness.PortfolioSim;
import musescript.harness.Metrics;
import musescript.indicators.GrowableVec;
import musescript.evo.nma.NmaBool;   // secondary types for the roots
import musescript.evo.nma.NmaScalar;

/** Column bundle from `evalColumns` — null roots are sim-coupled (operands warmed). */
private typedef SignalCols = {
	var eL:Null<GrowableVec<Float>>;
	var eS:Null<GrowableVec<Float>>;
	var xL:Null<GrowableVec<Float>>;
	var xS:Null<GrowableVec<Float>>;
	var sz:Null<GrowableVec<Float>>;
	var tCols:Float;
	var tPack:Float;
	/** Avalanched signal-memo words from the first `wordsOf` this eval — store reuses them. */
	var memoA:Int;
	var memoB:Int;
	var memoReady:Bool;
};

/**
 * NMA-native fitness: evaluate a genome by (1) computing its five signal COLUMNS via the memoized
 * `NmaEval` kind-switch (entry/exit bools + size scalar) and (2) driving the REAL `OrderSim` /
 * `Metrics` through the exact per-bar loop `BacktestEngine.run` + `Expand` define. The whole point
 * is bit-exact parity with `Fitness.evaluate` while making the expensive part -- signal evaluation
 * -- memoizable and shareable, which the compiled-source path can't be.
 *
 * Parity is preserved by REUSE, not reimplementation:
 *  - Indicator math: the engine (`EngineIndicatorProvider` -> `TradeBuiltins`).
 *  - Cross/trend/arith/logic: `NmaEval`, differential-tested vs `TradeBuiltins`.
 *  - Order execution + accounting + metrics: the actual `OrderSim`/`Metrics`, driven identically to
 *    `BacktestEngine.run` (`beginBar` -> onBar -> `mark`), with the onBar body copied verbatim from
 *    `Expand.expand`'s three `when` clauses (entryLong guarded by `position()<=0`, entryShort by
 *    `position()>=0`, exit on `exitLong || exitShort`), same-close execution, same submit verbs.
 *
 * The only NEW code is that per-bar orchestration; everything numeric is shared with the genome
 * path, which is what makes the A/B (`TestNmaFitness`) come out identical.
 *
 * «Γῆς παῖς εἰμι καὶ Οὐρανοῦ ἀστερόεντος.»
 */
class NmaFitness {
	/**
	 * Everything `prepare` derives from the TAPE alone — the per-field price arrays, the tape
	 * signature, and the `SInd` column share (spec §6b content-addressed leaf memo). Split out of
	 * `prepare` because all of it was being rebuilt per *evaluation*: five `Array<Float>` of length
	 * B (boxed on JVM, guide §3.1) plus a full FNV pass over `close` for the tape key, on every
	 * genome. That is per-tape work running at per-genome cadence — the cost-cadence mistake §26
	 * warns about — and at P=1000 it is millions of throwaway allocations a generation.
	 *
	 * Thread contract (§27): the record is immutable and published by a single reference
	 * assignment, so a worker either sees the whole thing or the previous one; it never sees a
	 * half-built tape paired with the wrong key. Two workers racing a cold tape both build and one
	 * assignment wins — wasted work, never wrong work. The one mutable member, `columns`, carries
	 * its own lock (`NmaColumnCache`).
	 *
	 * «λίκνον φέρει Δημήτηρ· Ἴακχος ὑπὸ κόλπῳ.»
	 */
	static var tape:Null<NmaTapeState> = null;
	/** Second tape slot — full IS vs attribution prefix (see `tapeStateFor`). */
	static var tapeAlt:Null<NmaTapeState> = null;

	/**
	 * Fresh `OrderSim` per sim. Thread-local recycle was measured under the corpus pool and did not
	 * beat `new` once `reset` + `fills.copy` (required for safe reuse) were paid; revisit with a
	 * pool-owned scratch sim if attribution volume climbs further.
	 *
	 * «κύλιξ μία, πολλοὶ πότοι· οὐ κενὴ πάλιν.»
	 */
	static inline function borrowSim():OrderSim {
		return new OrderSim();
	}

	/** Drop shared indicator columns (tests / tape switch / `Fitness.clearFnCache`).
	 *
	 * «ἅλαδε μύσται· θάλασσα καθαίρει μιασμόν.»
	 */
	public static function clearColumnCache():Void {
		tape = null;
		tapeAlt = null;
	}

	/**
	 * The tape state for `bars`, built once and reused.
	 *
	 * The fast path is REFERENCE equality on the bars array: `CorpusEvoRun` hands the same
	 * `Array<Bar>` object to every genome in a generation (and the same attribution prefix to
	 * every ablation), so the common case costs one pointer compare instead of O(B). Content
	 * hashing still runs when the identity check fails, which is what keeps a caller that builds
	 * an equal-but-distinct array correct rather than merely lucky.
	 *
	 * Two slots: fitness uses the full IS tape; attribution uses a short prefix (`--attr-bars`).
	 * A single static slot thrashed between them every generation and rebuilt tens of times/gen.
	 */
	static function tapeStateFor(bars:Array<Bar>):NmaTapeState {
		var snap = tape;
		if (snap != null && snap.bars == bars) return snap;
		var alt = tapeAlt;
		if (alt != null && alt.bars == bars) return alt;

		var n = bars.length;
		var open = new Array<Float>(), high = new Array<Float>(), low = new Array<Float>();
		var close = new Array<Float>(), volume = new Array<Float>(), times = new Array<Float>();
		// Aux / fund columns from pre-joined `Bar.data` (PIT: missing bars → NaN). Discovered
		// on the fly so OHLCV-only tapes pay nothing beyond the null check.
		var auxCols = new Map<String, Array<Float>>();
		// The same pass fills the unboxed OHLC + index columns the sim loop reads, so each bar's
		// fields are pulled through `Jvm.readField` once here rather than once per genome per bar
		// (see `NmaBarColumns`). Indexed, and each field read into a local first, because on the
		// JVM target every one of these is a boxing dynamic lookup.
		var openV = new haxe.ds.Vector<Float>(n), highV = new haxe.ds.Vector<Float>(n);
		var lowV = new haxe.ds.Vector<Float>(n), closeV = new haxe.ds.Vector<Float>(n);
		var indexV = new haxe.ds.Vector<Int>(n);
		var bi = 0;
		while (bi < n) {
			var b = bars[bi];
			var bo = b.open, bh = b.high, bl = b.low, bc = b.close;
			open.push(bo); high.push(bh); low.push(bl); close.push(bc);
			volume.push(b.volume); times.push(b.time);
			openV[bi] = bo; highV[bi] = bh; lowV[bi] = bl; closeV[bi] = bc;
			indexV[bi] = b.index;
			if (b.data != null) {
				for (k => v in b.data) {
					var col = auxCols.get(k);
					if (col == null) {
						col = [for (_ in 0...n) Math.NaN];
						auxCols.set(k, col);
					}
					col[bi] = v;
				}
			}
			bi++;
		}
		var barCols = new NmaBarColumns(bars, n, openV, highV, lowV, closeV, indexV);
		var fields:Map<String, Array<Float>> = [
			"open" => open, "high" => high, "low" => low, "close" => close, "volume" => volume
		];
		var auxNames:Array<String> = [for (k in auxCols.keys()) k];
		auxNames.sort(Reflect.compare);
		for (k in auxNames) fields.set(k, auxCols.get(k));
		var key = tapeDigest(close, auxNames, auxCols);

		// A distinct array object holding an identical tape keeps its columns: the signature, not
		// the pointer, is what a memo is valid under. Check both slots.
		var shareFrom:Null<NmaTapeState> = null;
		if (snap != null && snap.key == key.hex && snap.n == n) shareFrom = snap;
		else if (alt != null && alt.key == key.hex && alt.n == n) shareFrom = alt;
		if (shareFrom != null) {
			var rebound = new NmaTapeState(bars, n, key.hex, key.a, key.b, fields,
				times, barCols, shareFrom.columns);
			publishTape(rebound, snap);
			return rebound;
		}

		var fresh = new NmaTapeState(bars, n, key.hex, key.a, key.b, fields,
			times, barCols, new NmaColumnCache());
		publishTape(fresh, snap);
		return fresh;
	}

	/** Install `built` as the primary slot; demote the previous primary to alt when it is a
	 * different bars identity (so full-tape ↔ attr-prefix thrash stays warm in both slots). */
	static function publishTape(built:NmaTapeState, prev:Null<NmaTapeState>):Void {
		if (prev != null && prev.bars != built.bars) tapeAlt = prev;
		tape = built;
	}

	/**
	 * True when every root of `g` has a standalone signal column — i.e. nothing in it reads
	 * simulator state.
	 *
	 * This is NOT an evaluability test: `prepare` accepts sim-coupled genomes too, and
	 * `NmaPositionEval` walks their coupled spine per bar. It is what column-swap attribution
	 * asks, because that technique works by replacing one boolean column in a prepared session
	 * and rescanning — and a coupled root has no column to replace.
	 *
	 * «Σίβυλλα μαίνεται· θεὸς ἐν αὐτῇ λαλεῖ.»
	 */
	public static function columnSwappable(g:StrategyGenome):Bool {
		return !musescript.evo.GenomeFeatures.isSimCoupled(g);
	}

	public static function evaluate(g:StrategyGenome, bars:Array<Bar>,
			?costBps:Float = 0.0, ?initialCash:Float = 100000, ?equityFloor:Float = 0.0):FitnessResult {
		try {
			var built = prepare(g, bars);
			if (built == null)
				return new FitnessResult(false, -999, 0, 0, "nma-unsupported",
					"genome uses position-state KFeature (unrealized_pnl_pct / bars_in_trade) "
					+ "-- not hostable as a signal column");
			return evaluatePrepared(built.nma, built.ctx, bars, costBps, initialCash, equityFloor);
		} catch (e:Dynamic) {
			return new FitnessResult(false, -999, 0, 0, "nma-error", Std.string(e));
		}
	}

	/**
	 * Columnar panel fitness (cliff 3): `PanelInline` genome + packed `field@SYM` columns from
	 * `PanelFeed`, signals via `NmaEval`, apply via real `PortfolioSim` matching Expand's
	 * closed `PABuy` / `PARebalance` / `PATargetWeight` / `PABagScanTop` / `PABagRankWeights`
	 * templates (entryLong / exitLong only). Open bags, KPd, and sim-coupled roots stay Expand
	 * (`nma-unsupported`).
	 *
	 * «πολλαὶ νῆες, εἷς στόλος· κορυφαῖος Πορτοφόλιον.»
	 */
	public static function evaluatePanel(g:StrategyGenome, bars:Array<Bar>, panel:PanelFeed,
			action:PanelAction, pack:Map<String, Array<Float>>,
			?costBps:Float = 0.0, ?initialCash:Float = 100000):FitnessResult {
		try {
			if (panel == null)
				return new FitnessResult(false, -999, 0, 0, "nma-unsupported",
					"panel NMA requires Fitness.configurePanel / PanelFeed");
			if (!PanelInline.isNmaPanelAction(action))
				return new FitnessResult(false, -999, 0, 0, "nma-unsupported",
					"panel NMA supports PABuy/PARebalance/PATargetWeight/"
					+ "PABagScanTop/PABagRankWeights (open bag_rank_* stay Expand)");
			var built = prepare(g, bars, pack);
			if (built == null)
				return new FitnessResult(false, -999, 0, 0, "nma-unsupported",
					"panel NMA prepare failed");
			var nma = built.nma;
			var ctx = built.ctx;
			// Panel Expand templates ignore short + position() — refuse sim-coupled roots so we
			// never invent PortfolioSim-coupled KFeature semantics under OrderSim helpers.
			if (NmaPositionEval.isCoupled(nma.entryLong) || NmaPositionEval.isCoupled(nma.exitLong)
					|| NmaPositionEval.isCoupled(nma.size))
				return new FitnessResult(false, -999, 0, 0, "nma-unsupported",
					"panel NMA refuses sim-coupled roots (no PortfolioSim position features yet)");
			var cols = evalColumns(nma, ctx);
			musescript.evo.Fitness.addNmaPopMemoHits(ctx.popMemoHits);
			ctx.popMemoHits = 0;
			var eL = cols.eL, xL = cols.xL, sz = cols.sz;
			if (eL == null || xL == null || sz == null)
				return new FitnessResult(false, -999, 0, 0, "nma-unsupported",
					"panel NMA needs columnar entryLong/exitLong/size");
			var bagScores:Null<Map<String, GrowableVec<Float>>> = null;
			switch (action) {
				case PABagScanTop(kind, window, _, syms) | PABagRankWeights(kind, window, syms):
					bagScores = bagScanScoreColumns(ctx, kind, window, syms);
					if (bagScores == null)
						return new FitnessResult(false, -999, 0, 0, "nma-unsupported",
							'bag panelAction kind "$kind" not columnar on NMA');
				default:
			}
			var keepCurve = musescript.evo.Fitness.equityCurveNeeded;
			var port = panelSimFromColumns(panel, action, eL, xL, sz, costBps, initialCash, keepCurve,
				bagScores);
			var eqArr = keepCurve ? port.equity.toArray() : null;
			var finalEq = keepCurve
				? (eqArr != null && eqArr.length > 0 ? eqArr[eqArr.length - 1] : port.cash)
				: (port.equity.length > 0 ? port.equity[port.equity.length - 1] : port.cash);
			var sharpe = eqArr != null
				? Metrics.sharpe(Metrics.returnsFromEquity(eqArr), 0)
				: sharpeOfEquity(port.equity);
			var fr = new FitnessResult(true, sharpe, port.trades, finalEq, "nma");
			fr.fills = port.fills;
			fr.bankrupt = false;
			fr.equity = eqArr;
			return fr;
		} catch (e:Dynamic) {
			return new FitnessResult(false, -999, 0, 0, "nma-error", Std.string(e));
		}
	}

	/**
	 * Build NMA working copy + eval context (shared SInd cache). Null if `KFeature` present.
	 * Used by `NmaAttr` to keep one session across ablations.
	 * Optional `panelPack` merges calendar-aligned `field@SYM` columns into the tape fields
	 * (cliff 3 — SPanel via PanelInline).
	 *
	 * «ῥεῦμα μέλιτος ῥεῖ· ἀθάνατοι πίνουσιν ἐκεῖ.»
	 */
	public static function prepare(g:StrategyGenome, bars:Array<Bar>,
			?panelPack:Map<String, Array<Float>>):Null<{nma:NmaGenome, ctx:NmaEvalContext}> {
		// Feed-cadence vs Expand short-circuit (genericIndsAlwaysFed) deliberately NOT gated:
		// under --nma the columnar every-bar feed IS the search oracle. Refusing those genomes
		// forced ~40% of the pop through Expand→parse→compile (measured). Bit-parity with JVM
		// interp is parked; Node/JS already matched NMA on palette genomes.
		//
		// Position-state features are no longer refused either: `NmaPositionEval` evaluates the
		// coupled spine per bar inside the sim loop over columns for everything else. Refusing
		// them was the single largest cost in the engine -- ~10% of evaluations taking more CPU
		// than the entire columnar path, because each one fell through to the tree-walking
		// interpreter at 17-30 ms against ~0.24 ms.
		var tEnter = NmaSignalProbe.stamp();
		var nma = NmaBijection.genomeFromEnum(g);
		var tConverted = NmaSignalProbe.stamp();

		var t = tapeStateFor(bars);
		var fields = t.fields;
		var key = t.key;
		var keyA = t.keyA;
		var keyB = t.keyB;
		var columns = t.columns;
		if (panelPack != null && panelPack.keys().hasNext()) {
			fields = new Map();
			for (k => v in t.fields) fields.set(k, v);
			NmaPanelPack.mergeInto(fields, panelPack);
			var dig = NmaPanelPack.digest(panelPack);
			key = t.key + "|pnl|" + dig.hex;
			keyA = t.keyA ^ dig.a;
			keyB = t.keyB ^ dig.b;
			// Fresh share so panel-key columns don't collide with OHLCV-only peers on the same bars.
			columns = new NmaColumnCache();
		}
		var params = [for (p in g.params) p.defaultValue];
		var ctx = new NmaEvalContext(t.n, NmaEpoch.of(key, g.params, keyA, keyB), fields, null, params,
			new EngineIndicatorProvider(fields, columns, t.times), musescript.evo.Fitness.nmaPopMemo);
		ctx.sharedPriceColumns = columns;
		ctx.barColumns = t.barCols;
		if (NmaSignalProbe.on)
			NmaSignalProbe.observePrepare(tConverted - tEnter, NmaSignalProbe.wall() - tConverted);
		return { nma: nma, ctx: ctx };
	}

	/**
	 * Drive `PortfolioSim` from columnar entryLong / exitLong / size — mirrors Expand
	 * `emitPanelActionBody` + `HarnessContext.runPanelBacktest` ordering (beginBar → apply → mark).
	 * Optional `bagScores` supplies per-symbol score columns for closed bag templates
	 * (`PABagScanTop` → equal bag; `PABagRankWeights` → percentile xs_rank → `bag_norm`).
	 */
	static function panelSimFromColumns(panel:PanelFeed, action:PanelAction,
			eL:GrowableVec<Float>, xL:GrowableVec<Float>, sz:GrowableVec<Float>,
			costBps:Float, initialCash:Float, keepCurve:Bool,
			?bagScores:Map<String, GrowableVec<Float>>):PortfolioSim {
		var n = panel.length();
		var port = new PortfolioSim();
		if (costBps != 0) port.tradingCostBps = costBps;
		if (initialCash != 100000) port.reset(initialCash);
		var emptyPx = new Map<String, Float>();
		var i = 0;
		while (i < n) {
			var opens = i < panel.opens.length ? panel.opens[i] : emptyPx;
			var highs = i < panel.highs.length ? panel.highs[i] : emptyPx;
			var lows = i < panel.lows.length ? panel.lows[i] : emptyPx;
			var prices = panel.pricesAt(i);
			var idx = i < panel.all().length ? panel.all()[i].index : i;
			port.beginBar(opens, highs, lows, idx);
			if (eL.at(i) >= 0.5)
				applyPanelEntry(port, action, prices, sz.at(i), idx, i, bagScores);
			if (xL.at(i) >= 0.5)
				applyPanelExit(port, action, prices, idx);
			port.mark(prices);
			i++;
		}
		if (!keepCurve) {
			// Equity already streamed into GrowableVec for sharpeOfEquity; callers that skip
			// the array still read the last mark via port.equity.
		}
		return port;
	}

	/**
	 * Per-symbol score columns matching Expand `panelScoreDict` / `*_of` for closed bag templates.
	 * Null when `kind` is outside the packed OHLCV/ind/fund subset.
	 */
	static function bagScanScoreColumns(ctx:NmaEvalContext, kind:String, window:Int,
			syms:Array<String>):Null<Map<String, GrowableVec<Float>>> {
		if (!PanelInline.bagScoreKindSupported(kind) || syms == null) return null;
		var out = new Map<String, GrowableVec<Float>>();
		var w = window > 0 ? window : 14;
		for (sym in syms) {
			if (sym == null || sym.length == 0) continue;
			var leaf:SeriesNode = if (kind == "fund") {
				SPrice(PortfolioBuiltins.seriesKey("revenue", sym));
			} else if (Palette.PANEL_OF_INDS.indexOf(kind) >= 0) {
				SInd(kind, PortfolioBuiltins.seriesKey("close", sym), w, null);
			} else {
				SPrice(PortfolioBuiltins.seriesKey(kind, sym));
			};
			out.set(sym, NmaEval.evalSeries(NmaBijection.seriesFromEnum(leaf), ctx));
		}
		return out;
	}

	/**
	 * Percentile xs_rank (ascending, average ties) in `syms` order → `bag_norm` weight map.
	 * Matches Expand `bag_norm(bag_from_dict({SYM: pd_rank1d|pd_xs_rank…}))` when scores
	 * pack in the same order (tie-break by universe index).
	 */
	static function bagRankNormWeights(bagScores:Null<Map<String, GrowableVec<Float>>>,
			syms:Array<String>, barI:Int):Map<String, Float> {
		if (bagScores == null || syms == null || syms.length == 0) return new Map();
		var packed:Array<Float> = [];
		for (s in syms) {
			var col = bagScores.get(s);
			packed.push(col != null ? col.at(barI) : Math.NaN);
		}
		var ranks = GroupBy.rank1d(NdArrayF64.asarray1d(packed), true, true);
		var dict = new Map<String, Float>();
		for (i in 0...syms.length) {
			var r = ranks.getFlat(i);
			if (!Math.isNaN(r) && Math.isFinite(r) && r != 0)
				dict.set(syms[i], r);
		}
		return BagBuiltins.bagNorm(BagBuiltins.bagFromDict(dict)).weights;
	}

	static function applyPanelEntry(port:PortfolioSim, action:PanelAction,
			prices:Map<String, Float>, size:Float, barIndex:Int, barI:Int,
			bagScores:Null<Map<String, GrowableVec<Float>>>):Void {
		switch (action) {
			case PABuy(sym):
				var px = prices != null && prices.exists(sym) ? prices.get(sym) : Math.NaN;
				port.buy(sym, px, size, barIndex);
			case PARebalance(syms):
				port.rebalanceEqual(syms, prices, barIndex);
			case PATargetWeight(sym):
				port.targetWeight(sym, size, prices, barIndex);
			case PABagScanTop(_, _, topK, syms):
				var scores = new Map<String, Float>();
				if (bagScores != null && syms != null) {
					for (s in syms) {
						var col = bagScores.get(s);
						if (col == null) continue;
						scores.set(s, col.at(barI));
					}
				}
				var k = Expand.clampBagTopK(topK, syms);
				var picks = PortfolioBuiltins.rankPick(scores, k, false);
				port.applyBag(BagBuiltins.bagEqual(picks).weights, prices, barIndex, true);
			case PABagRankWeights(_, _, syms):
				port.applyBag(bagRankNormWeights(bagScores, syms, barI), prices, barIndex, true);
		}
	}

	static function applyPanelExit(port:PortfolioSim, action:PanelAction,
			prices:Map<String, Float>, barIndex:Int):Void {
		switch (action) {
			case PABuy(sym) | PATargetWeight(sym):
				var px = prices != null && prices.exists(sym) ? prices.get(sym) : Math.NaN;
				port.sellAll(sym, px, barIndex);
			case PARebalance(syms):
				if (syms != null) for (s in syms) {
					var p = prices != null && prices.exists(s) ? prices.get(s) : Math.NaN;
					port.sellAll(s, p, barIndex);
				}
			case PABagScanTop(_, _, _, syms) | PABagRankWeights(_, _, syms):
				if (syms != null) for (s in syms) {
					var p = prices != null && prices.exists(s) ? prices.get(s) : Math.NaN;
					port.sellAll(s, p, barIndex);
				}
		}
	}

	/** Content signature used by dirty-spine working-copy guards. */
	public static function tapeSignature(bars:Array<Bar>):String {
		return tapeStateFor(bars).key;
	}

	/**
	 * Columnar signal eval + OrderSim for an already-prepared NMA tree/context. Safe to call
	 * repeatedly after spine surgery — unchanged subtrees hit `lastSeries` memos.
	 *
	 * «παννυχὶς ἄγρυπνος· ἠὼς μύστας εὑρίσκει.»
	 */
	public static function evaluatePrepared(nma:NmaGenome, ctx:NmaEvalContext, bars:Array<Bar>,
			?costBps:Float = 0.0, ?initialCash:Float = 100000, ?equityFloor:Float = 0.0):FitnessResult {
		var claimedA = 0;
		var claimedB = 0;
		var claimed = false;
		try {
			var cols = evalColumns(nma, ctx);
			musescript.evo.Fitness.addNmaPopMemoHits(ctx.popMemoHits);
			ctx.popMemoHits = 0;
			var memoHit = signalMemoClaim(ctx, cols, costBps, initialCash, equityFloor, true,
				musescript.evo.Fitness.equityCurveNeeded);
			if (memoHit != null) {
				var frHit = new FitnessResult(true, memoHit.sharpe, memoHit.trades, memoHit.finalEquity, "nma");
				frHit.fills = memoHit.fills;
				frHit.bankrupt = memoHit.bankrupt;
				frHit.equity = memoHit.equity;
				return frHit;
			}
			// `claim` returned null with memoReady ⇒ this thread owns the flight.
			if (cols.memoReady) {
				claimedA = cols.memoA;
				claimedB = cols.memoB;
				claimed = true;
			}
			var keepCurve = musescript.evo.Fitness.equityCurveNeeded;
			var orders = simFromColumns(nma, ctx, bars, cols, costBps, initialCash, equityFloor, true,
				keepCurve);
			var finalEq = keepCurve
				? (orders.equity.length > 0 ? orders.equity[orders.equity.length - 1] : orders.cash)
				: (bars.length > 0 ? orders.lastMark : orders.cash);
			var eqArr = keepCurve ? orders.equity.toArray() : null;
			var sharpe = eqArr != null
				? Metrics.sharpe(Metrics.returnsFromEquity(eqArr), 0)
				: (keepCurve ? sharpeOfEquity(orders.equity) : orders.sharpeOnline());
			signalMemoStore(ctx, cols, costBps, initialCash, equityFloor,
				orders.trades, sharpe, finalEq, orders.bankrupt, orders.fills, eqArr);
			claimed = false;
			var fr = new FitnessResult(true, sharpe, orders.trades, finalEq, "nma");
			fr.fills = orders.fills;
			fr.bankrupt = orders.bankrupt;
			fr.equity = eqArr;
			return fr;
		} catch (e:Dynamic) {
			if (claimed) NmaSignalMemo.fail(claimedA, claimedB);
			return new FitnessResult(false, -999, 0, 0, "nma-error", Std.string(e));
		}
	}

	/**
	 * Score-only sibling of `evaluatePrepared`, for attribution column swaps.
	 *
	 * An ablation asks one question -- "what is this genome worth?" -- and then throws the
	 * `FitnessResult` away. Building one costs three array allocations of length B that nothing
	 * reads: `equity.toArray`, the returns array under it, and the retained fills. At ~15 swaps
	 * per child and P=1000 that is the dominant allocation source in `step.xo`, so this path
	 * reduces the equity curve to a Sharpe in place and returns the float directly.
	 *
	 * Parity is by construction, not by copy: the signal columns and the OrderSim loop come from
	 * the same `runPrepared` that `evaluatePrepared` uses, and the reduction reproduces
	 * `Metrics.returnsFromEquity` -> `Metrics.sharpe(_, 0)` -> `Fitness.score(_, minTrades)`
	 * exactly (`TestNmaAttrColumnSwap` pins the two against each other).
	 *
	 * «ἓν σῶμα, δύο πρόσωπα· ὁ αὐτὸς ἀριθμός.»
	 */
	public static function scorePrepared(nma:NmaGenome, ctx:NmaEvalContext, bars:Array<Bar>,
			?costBps:Float = 0.0, ?initialCash:Float = 100000, ?equityFloor:Float = 0.0,
			?minTrades:Int = 1):Float {
		var claimedA = 0;
		var claimedB = 0;
		var claimed = false;
		try {
			var cols = evalColumns(nma, ctx);
			musescript.evo.Fitness.addNmaPopMemoHits(ctx.popMemoHits);
			ctx.popMemoHits = 0;
			var memoHit = signalMemoClaim(ctx, cols, costBps, initialCash, equityFloor, false, false);
			if (memoHit != null) {
				return musescript.evo.Fitness.scoreFacts(
					memoHit.trades, memoHit.sharpe, memoHit.bankrupt, minTrades);
			}
			if (cols.memoReady) {
				claimedA = cols.memoA;
				claimedB = cols.memoB;
				claimed = true;
			}
			// No fills / no equity curve: return stream during mark → exact Metrics.sharpe.
			var orders = simFromColumns(nma, ctx, bars, cols, costBps, initialCash, equityFloor, false,
				false);
			var sharpe = orders.sharpeOnline();
			var finalEq = bars.length > 0 ? orders.lastMark : orders.cash;
			signalMemoStore(ctx, cols, costBps, initialCash, equityFloor,
				orders.trades, sharpe, finalEq, orders.bankrupt, null, null);
			claimed = false;
			return musescript.evo.Fitness.scoreFacts(
				orders.trades, sharpe, orders.bankrupt, minTrades);
		} catch (e:Dynamic) {
			if (claimed) NmaSignalMemo.fail(claimedA, claimedB);
			// `evaluatePrepared` would have returned ok=false here, which `Fitness.score` maps
			// to NEG_INF; a throwing ablation must not read as a profitable one.
			return musescript.evo.Fitness.NEG_INF;
		}
	}

	/** The shared body of `evaluatePrepared` / `scorePrepared`: columns, then the verbatim
	 * `BacktestEngine.run` per-bar loop. Single-sourced so the two cannot drift apart. */
	static function runPrepared(nma:NmaGenome, ctx:NmaEvalContext, bars:Array<Bar>,
			costBps:Float, initialCash:Float, equityFloor:Float, recordFills:Bool):OrderSim {
		var cols = evalColumns(nma, ctx);
		musescript.evo.Fitness.addNmaPopMemoHits(ctx.popMemoHits);
		ctx.popMemoHits = 0;
		return simFromColumns(nma, ctx, bars, cols, costBps, initialCash, equityFloor, recordFills,
			true);
	}

	/** Five signal columns (null = sim-coupled root, operands already warmed). */
	static function evalColumns(nma:NmaGenome, ctx:NmaEvalContext):SignalCols {
		var tCols = NmaSignalProbe.stamp();
		var eL = column(nma.entryLong, ctx);
		var eS = column(nma.entryShort, ctx);
		var xL = column(nma.exitLong, ctx);
		var xS = column(nma.exitShort, ctx);
		var sz = NmaPositionEval.isCoupled(nma.size) ? null : NmaEval.evalScalar(nma.size, ctx);
		if (sz == null) NmaPositionEval.warmScalar(nma.size, ctx);
		var tPack = NmaSignalProbe.stamp();
		return {
			eL: eL, eS: eS, xL: xL, xS: xS, sz: sz, tCols: tCols, tPack: tPack,
			memoA: 0, memoB: 0, memoReady: false
		};
	}

	/**
	 * Claim or await the signal memo. On `null` with `cols.memoReady`, this thread owns the flight
	 * and must `put`/`fail`. Coupled roots leave `memoReady` false and skip the memo entirely.
	 * `needFills` / `needEquity` must match what the subsequent sim will actually store.
	 */
	static function signalMemoClaim(ctx:NmaEvalContext, cols:SignalCols,
			costBps:Float, initialCash:Float, equityFloor:Float,
			needFills:Bool, needEquity:Bool):Null<NmaSignalMemoEntry> {
		if (!NmaSignalMemo.enabled) return null;
		if (cols.eL == null || cols.eS == null || cols.xL == null || cols.xS == null || cols.sz == null)
			return null;
		var d = ctx.scratchDigest;
		NmaSignalMemo.wordsOf(ctx, cols.eL, cols.eS, cols.xL, cols.xS, cols.sz,
			costBps, initialCash, equityFloor, d);
		cols.memoA = d.outA;
		cols.memoB = d.outB;
		cols.memoReady = true;
		return NmaSignalMemo.claim(d.outA, d.outB, needFills, needEquity);
	}

	static function signalMemoStore(ctx:NmaEvalContext, cols:SignalCols,
			costBps:Float, initialCash:Float, equityFloor:Float,
			trades:Int, sharpe:Float, finalEquity:Float, bankrupt:Bool,
			fills:Null<Array<musescript.harness.Fill>>, equity:Null<Array<Float>>):Void {
		if (!NmaSignalMemo.enabled) return;
		if (cols.eL == null || cols.eS == null || cols.xL == null || cols.xS == null || cols.sz == null)
			return;
		var a:Int, b:Int;
		if (cols.memoReady) {
			a = cols.memoA;
			b = cols.memoB;
		} else {
			var d = ctx.scratchDigest;
			NmaSignalMemo.wordsOf(ctx, cols.eL, cols.eS, cols.xL, cols.xS, cols.sz,
				costBps, initialCash, equityFloor, d);
			a = d.outA;
			b = d.outB;
		}
		NmaSignalMemo.put(a, b,
			NmaSignalMemo.entryOf(trades, sharpe, finalEquity, bankrupt, fills, equity));
	}

	static function simFromColumns(nma:NmaGenome, ctx:NmaEvalContext, bars:Array<Bar>, cols:SignalCols,
			costBps:Float, initialCash:Float, equityFloor:Float, recordFills:Bool,
			keepCurve:Bool):OrderSim {
		var n = bars.length;
		var eL = cols.eL, eS = cols.eS, xL = cols.xL, xS = cols.xS, sz = cols.sz;
		// The probe's semantic signature is defined over the signal columns, which a coupled
		// genome does not have until it has been simulated. Those are simply not sampled.
		var tSim = NmaSignalProbe.stamp();
		var sig = NmaSignalProbe.on && eL != null && eS != null && xL != null && xS != null && sz != null
			? NmaSignalPack.signature(NmaSignalPack.packBool(eL, n), NmaSignalPack.packBool(eS, n),
				NmaSignalPack.packOr(xL, xS, n), sz, n)
			: null;

		var orders = borrowSim();
		orders.recordFills = recordFills;
		orders.trackCurve = keepCurve;
		if (costBps != 0) orders.book.slippageBps = costBps;
		if (initialCash != 100000) {
			orders.cash = initialCash;
		}
		if (equityFloor > 0) orders.equityFloor = equityFloor;
		orders.reserveEquity(n);

		// `beginBar` does two things and this loop can trigger neither. It replays a queued
		// next-open order, and this sim is `same-close`; and it fills pending BOOK orders, which
		// only arrive via `submit` with an order-spec object, which the calls below never make. So
		// for a fresh OrderSim both guards inside it are false on every bar and the call is a
		// no-op -- one that boxes two `java.lang.Double` for its optional `high`/`low` on the JVM,
		// every bar of every evaluation (guide §3.1). Hoisting the condition keeps the semantics
		// exactly (any future caller that arrives here in another mode still gets its beginBars)
		// while spending nothing in the case that actually runs.
		var needsBeginBar = orders.executionMode != "same-close" || orders.book.pendingCount() > 0;

		// Unboxed OHLC + index for this tape. `Bar` is a structural typedef, so on the JVM every
		// `bar.close` here was a `Jvm.readField` string lookup minting a `java.lang.Double`, four
		// or five times a bar, for every genome and every attribution column swap. The columns
		// are per-TAPE state (guide §31): `prepare` hands over the ones `tapeStateFor` already
		// built, and the reference guard only re-derives for a caller that reuses a context
		// against a different `Array<Bar>` -- which is also the only case where reading the
		// context's copy would have been wrong.
		var barCols = ctx.barColumns;
		if (barCols == null || barCols.bars != bars) {
			barCols = NmaBarColumns.of(bars);
			ctx.barColumns = barCols;
		}
		var opens = barCols.open, highs = barCols.high, lows = barCols.low, closes = barCols.close;
		var barIdx = barCols.index;

		// Columnar fast path: all five roots are pure columns — no null checks / coupled
		// position-feature eval per bar. Attribution and most NMA genomes land here.
		if (eL != null && eS != null && xL != null && xS != null && sz != null && !needsBeginBar) {
			var i = 0;
			while (i < n) {
				var close = closes.at(i);
				var idx = barIdx[i];
				if (eL.at(i) >= 0.5 && orders.position <= 0)
					orders.long(close, sz.at(i), idx);
				if (eS.at(i) >= 0.5 && orders.position >= 0)
					orders.short(close, sz.at(i), idx);
				if (xL.at(i) >= 0.5 || xS.at(i) >= 0.5)
					orders.flat(close, idx);
				orders.mark(close);
				i++;
			}
		} else {
			// Coupled roots: each condition is read at exactly the point the compiled render
			// evaluates its `when` head, so a coupled root sees the same OrderSim state the
			// interpreter would: the entry heads before this bar's submits, the exit head after.
			var i = 0;
			while (i < n) {
				var close = closes.at(i);
				var idx = barIdx[i];
				if (needsBeginBar) orders.beginBar(opens.at(i), idx, highs.at(i), lows.at(i));
				if ((eL != null ? eL.at(i) >= 0.5 : NmaPositionEval.boolAt(nma.entryLong, ctx, i, orders, close, idx))
					&& orders.position <= 0)
					orders.long(close, sizeAt(nma, ctx, sz, i, orders, close, idx), idx);
				if ((eS != null ? eS.at(i) >= 0.5 : NmaPositionEval.boolAt(nma.entryShort, ctx, i, orders, close, idx))
					&& orders.position >= 0)
					orders.short(close, sizeAt(nma, ctx, sz, i, orders, close, idx), idx);
				if ((xL != null ? xL.at(i) >= 0.5 : NmaPositionEval.boolAt(nma.exitLong, ctx, i, orders, close, idx))
					|| (xS != null ? xS.at(i) >= 0.5 : NmaPositionEval.boolAt(nma.exitShort, ctx, i, orders, close, idx)))
					orders.flat(close, idx);
				orders.mark(close);
				i++;
			}
		}
		if (NmaSignalProbe.on)
			NmaSignalProbe.observe(sig, cols.tPack - cols.tCols, tSim - cols.tPack, NmaSignalProbe.wall() - tSim);
		return orders;
	}

	/** `Metrics.sharpe(Metrics.returnsFromEquity(eq.toArray()), 0)` without materializing either
	 * array. Two streaming passes over the curve; same guards, same annualization. */
	static function sharpeOfEquity(eq:GrowableVec<Float>,
			periodsPerYear:Float = musescript.harness.Metrics.DAILY_PERIODS_PER_YEAR):Float {
		var n = eq.length;
		var cnt = n - 1;
		if (cnt < 2) return 0;
		var mean = 0.0;
		var i = 1;
		while (i < n) {
			var prev = eq[i - 1];
			mean += prev > 0 ? (eq[i] - prev) / prev : 0.0;
			i++;
		}
		mean /= cnt;
		var var_ = 0.0;
		i = 1;
		while (i < n) {
			var prev = eq[i - 1];
			var d = (prev > 0 ? (eq[i] - prev) / prev : 0.0) - mean;
			var_ += d * d;
			i++;
		}
		var_ /= cnt - 1;
		var std = Math.sqrt(var_);
		if (std == 0) return 0;
		return (mean / std) * Math.sqrt(periodsPerYear);
	}

	/** A bool root's column, or `null` when it reads simulator state — warming its pure operands. */
	static function column(root:NmaBool, ctx:NmaEvalContext):Null<GrowableVec<Float>> {
		if (!NmaPositionEval.isCoupled(root)) return NmaEval.evalBool(root, ctx);
		NmaPositionEval.warmBool(root, ctx);
		return null;
	}

	static inline function sizeAt(nma:NmaGenome, ctx:NmaEvalContext, sz:Null<GrowableVec<Float>>,
			i:Int, orders:OrderSim, barClose:Float, barIndex:Int):Float {
		return sz != null ? sz.at(i) : NmaPositionEval.scalarAt(nma.size, ctx, i, orders, barClose, barIndex);
	}

	static inline function eL_exit(xL:GrowableVec<Float>, xS:GrowableVec<Float>, i:Int):Bool {
		return xL.at(i) >= 0.5 || xS.at(i) >= 0.5;
	}

	/** True if any node is a position-state `KFeature` (OrderSim-coupled — not columnar). */
	static function containsPositionFeature(g:NmaGenome):Bool {
		var r = 0;
		while (r < g.rootCount()) {
			if (hasPositionFeature(g.rootAt(r))) return true;
			r++;
		}
		return false;
	}

	static function hasPositionFeature(n:NmaNode):Bool {
		if (n.kind == NmaKind.KFeature) {
			return NmaFeatureHost.isPositionFeature((cast n : NmaKFeature).name);
		}
		var c = n.childCount();
		var i = 0;
		while (i < c) {
			if (hasPositionFeature(n.childAt(i))) return true;
			i++;
		}
		return false;
	}

	/** Stable content signature of the tape. Close carries the OHLCV shape; sorted aux names +
	 * columns (when present) keep fund-aware tapes from sharing a memo with OHLCV-only peers.
	 * Two avalanched FNV lanes so the pop-memo can key without a String; the hex form is
	 * kept for epoch interning and dirty-spine tape guards. Indexed scan — `for..in` over
	 * `Array<Float>` boxes on the JVM target (JIT_AUTHORING_GUIDE.md §3.3).
	 *
	 * «ἄναξ ταυρόκερως, εὐαστήρ, πυρίσπορε.»
	 */
	static function tapeDigest(close:Array<Float>, ?auxNames:Array<String>,
			?auxCols:Map<String, Array<Float>>):{hex:String, a:Int, b:Int} {
		var d = new musescript.evo.StructuralDigest();
		d.tag("T".code);
		d.int(close.length);
		var i = 0;
		while (i < close.length) {
			d.float(close[i]);
			i++;
		}
		if (auxNames != null && auxNames.length > 0 && auxCols != null) {
			d.tag("A".code);
			d.int(auxNames.length);
			for (name in auxNames) {
				d.str(name);
				var col = auxCols.get(name);
				if (col == null) continue;
				var j = 0;
				while (j < col.length) {
					d.float(col[j]);
					j++;
				}
			}
		}
		d.finishWords();
		return { hex: musescript.evo.StructuralDigest.hexWords(d.outA, d.outB), a: d.outA, b: d.outB };
	}

	// ---------- projection scoring support (ProjectionScore) ----------

	/** Per-bar column of a plain (non-`SProj`) `SeriesNode` over `bars`, via the same columnar
	 * indicator tier the strangler uses — so a projection's forecast series is evaluated identically
	 * to how the strategy would. For leakage-free forecast-skill scoring (`ProjectionScore`). */
	public static function seriesColumnOf(node:musescript.evo.SeriesNode, bars:Array<Bar>,
			params:Array<musescript.evo.EvoParam>):Array<Float> {
		var ctx = scoringContext(bars, params);
		return NmaEval.evalSeries(NmaBijection.seriesFromEnum(node), ctx).toArray();
	}

	/** Per-bar column of a plain (non-`SProj`) `ScalarNode` over `bars`. */
	public static function scalarColumnOf(node:musescript.evo.ScalarNode, bars:Array<Bar>,
			params:Array<musescript.evo.EvoParam>):Array<Float> {
		var ctx = scoringContext(bars, params);
		return NmaEval.evalScalar(NmaBijection.scalarFromEnum(node), ctx).toArray();
	}

	/** Standalone eval context for scoring — mirrors `prepare`'s construction; no pop-memo. */
	static function scoringContext(bars:Array<Bar>, params:Array<musescript.evo.EvoParam>):NmaEvalContext {
		var t = tapeStateFor(bars);
		var pv = [for (p in params) p.defaultValue];
		var ctx = new NmaEvalContext(t.n, NmaEpoch.of(t.key, params, t.keyA, t.keyB), t.fields, null, pv,
			new EngineIndicatorProvider(t.fields, t.columns, t.times), null);
		ctx.sharedPriceColumns = t.columns;
		ctx.barColumns = t.barCols;
		return ctx;
	}
}

/**
 * Immutable per-tape derivation shared by every evaluation on that tape (see
 * `NmaFitness.tapeStateFor`). `columns` is the one mutable member and guards itself.
 *
 * «μία ἄμπελος, πολλοὶ βότρυες.»
 */
private class NmaTapeState {
	public final bars:Array<Bar>;
	public final n:Int;
	public final key:String;
	public final keyA:Int;
	public final keyB:Int;
	public final fields:Map<String, Array<Float>>;
	/** Real bar timestamps — the generic indicator tier needs them (session/time-of-day
	 * indicators read `bar.time`; synthetic times would be a silent parity break). */
	public final times:Array<Float>;
	/** Unboxed OHLC + index for the sim loop; `fields` above stays `Array<Float>` because the
	 * indicator tier's public surface is typed that way. */
	public final barCols:NmaBarColumns;
	public final columns:NmaColumnCache;

	public function new(bars:Array<Bar>, n:Int, key:String, keyA:Int, keyB:Int,
			fields:Map<String, Array<Float>>, times:Array<Float>, barCols:NmaBarColumns,
			columns:NmaColumnCache) {
		this.bars = bars;
		this.n = n;
		this.key = key;
		this.keyA = keyA;
		this.keyB = keyB;
		this.fields = fields;
		this.times = times;
		this.barCols = barCols;
		this.columns = columns;
	}
}
