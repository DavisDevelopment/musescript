package musescript.evo.nma;

import musescript.evo.StrategyGenome;
import musescript.evo.FitnessResult;
import musescript.harness.Bar;
import musescript.harness.OrderSim;
import musescript.harness.Metrics;
import musescript.indicators.GrowableVec;
import musescript.evo.nma.NmaBool;   // secondary types for the roots
import musescript.evo.nma.NmaScalar;

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

	/** Drop shared indicator columns (tests / tape switch / `Fitness.clearFnCache`).
	 *
	 * «ἅλαδε μύσται· θάλασσα καθαίρει μιασμόν.»
	 */
	public static function clearColumnCache():Void {
		tape = null;
	}

	/**
	 * The tape state for `bars`, built once and reused.
	 *
	 * The fast path is REFERENCE equality on the bars array: `CorpusEvoRun` hands the same
	 * `Array<Bar>` object to every genome in a generation (and the same attribution prefix to
	 * every ablation), so the common case costs one pointer compare instead of O(B). Content
	 * hashing still runs when the identity check fails, which is what keeps a caller that builds
	 * an equal-but-distinct array correct rather than merely lucky.
	 */
	static function tapeStateFor(bars:Array<Bar>):NmaTapeState {
		var snap = tape;
		if (snap != null && snap.bars == bars) return snap;

		var n = bars.length;
		var open = new Array<Float>(), high = new Array<Float>(), low = new Array<Float>();
		var close = new Array<Float>(), volume = new Array<Float>(), times = new Array<Float>();
		for (b in bars) { open.push(b.open); high.push(b.high); low.push(b.low); close.push(b.close); volume.push(b.volume); times.push(b.time); }
		var key = tapeKey(close);

		// A distinct array object holding an identical tape keeps its columns: the signature, not
		// the pointer, is what a memo is valid under.
		if (snap != null && snap.key == key && snap.n == n) {
			var rebound = new NmaTapeState(bars, n, key,
				["open" => open, "high" => high, "low" => low, "close" => close, "volume" => volume],
				times, snap.columns);
			tape = rebound;
			return rebound;
		}

		var fresh = new NmaTapeState(bars, n, key,
			["open" => open, "high" => high, "low" => low, "close" => close, "volume" => volume],
			times, new NmaColumnCache());
		tape = fresh;
		return fresh;
	}

	/** True when columnar NMA can evaluate `g` (no position-state `KFeature`).
	 *
	 * «Σίβυλλα μαίνεται· θεὸς ἐν αὐτῇ λαλεῖ.»
	 */
	public static function supportsColumnar(g:StrategyGenome):Bool {
		return !musescript.evo.GenomeFeatures.genomeBlocksColumnar(g);
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
	 * Build NMA working copy + eval context (shared SInd cache). Null if `KFeature` present.
	 * Used by `NmaAttr` to keep one session across ablations.
	 *
	 * «ῥεῦμα μέλιτος ῥεῖ· ἀθάνατοι πίνουσιν ἐκεῖ.»
	 */
	public static function prepare(g:StrategyGenome, bars:Array<Bar>):Null<{nma:NmaGenome, ctx:NmaEvalContext}> {
		if (musescript.evo.GenomeFeatures.genomeBlocksColumnar(g)) return null;
		// Feed-cadence vs Expand short-circuit (genericIndsAlwaysFed) deliberately NOT gated:
		// under --nma the columnar every-bar feed IS the search oracle. Refusing those genomes
		// forced ~40% of the pop through Expand→parse→compile (measured). Bit-parity with JVM
		// interp is parked; Node/JS already matched NMA on palette genomes.
		var nma = NmaBijection.genomeFromEnum(g);
		if (containsPositionFeature(nma)) return null;

		var t = tapeStateFor(bars);
		var params = [for (p in g.params) p.defaultValue];
		var ctx = new NmaEvalContext(t.n, NmaEpoch.of(t.key, g.params), t.fields, null, params,
			new EngineIndicatorProvider(t.fields, t.columns, t.times), musescript.evo.Fitness.nmaPopMemo);
		ctx.sharedPriceColumns = t.columns;
		return { nma: nma, ctx: ctx };
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
		try {
			var orders = runPrepared(nma, ctx, bars, costBps, initialCash, equityFloor, true);
			var eqArr = orders.equity.toArray();
			var rets = Metrics.returnsFromEquity(eqArr);
			var finalEq = orders.equity.length > 0 ? orders.equity[orders.equity.length - 1] : orders.cash;
			var fr = new FitnessResult(true, Metrics.sharpe(rets, 0), orders.trades, finalEq, "nma");
			fr.fills = orders.fills;
			fr.bankrupt = orders.bankrupt;
			fr.equity = eqArr;
			return fr;
		} catch (e:Dynamic) {
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
		try {
			// No fills: this path reads only trades, equity and bankruptcy.
			var orders = runPrepared(nma, ctx, bars, costBps, initialCash, equityFloor, false);
			return musescript.evo.Fitness.scoreFacts(
				orders.trades, sharpeOfEquity(orders.equity), orders.bankrupt, minTrades);
		} catch (e:Dynamic) {
			// `evaluatePrepared` would have returned ok=false here, which `Fitness.score` maps
			// to NEG_INF; a throwing ablation must not read as a profitable one.
			return musescript.evo.Fitness.NEG_INF;
		}
	}

	/** The shared body of `evaluatePrepared` / `scorePrepared`: columns, then the verbatim
	 * `BacktestEngine.run` per-bar loop. Single-sourced so the two cannot drift apart. */
	static function runPrepared(nma:NmaGenome, ctx:NmaEvalContext, bars:Array<Bar>,
			costBps:Float, initialCash:Float, equityFloor:Float, recordFills:Bool):OrderSim {
		var n = bars.length;
		var tCols = NmaSignalProbe.stamp();
		var eL = NmaEval.evalBool(nma.entryLong, ctx);
		var eS = NmaEval.evalBool(nma.entryShort, ctx);
		var xL = NmaEval.evalBool(nma.exitLong, ctx);
		var xS = NmaEval.evalBool(nma.exitShort, ctx);
		var sz = NmaEval.evalScalar(nma.size, ctx);
		musescript.evo.Fitness.addNmaPopMemoHits(ctx.popMemoHits);
		ctx.popMemoHits = 0;
		var tPack = NmaSignalProbe.stamp();
		var sig = NmaSignalProbe.on
			? NmaSignalPack.signature(NmaSignalPack.packBool(eL, n), NmaSignalPack.packBool(eS, n),
				NmaSignalPack.packOr(xL, xS, n), sz, n)
			: null;
		var tSim = NmaSignalProbe.stamp();

		var orders = new OrderSim();
		orders.recordFills = recordFills;
		if (costBps != 0) orders.book.slippageBps = costBps;
		if (initialCash != 100000) orders.reset(initialCash);
		if (equityFloor > 0) orders.equityFloor = equityFloor;

		// `beginBar` does two things and this loop can trigger neither. It replays a queued
		// next-open order, and this sim is `same-close`; and it fills pending BOOK orders, which
		// only arrive via `submit` with an order-spec object, which the calls below never make. So
		// for a fresh OrderSim both guards inside it are false on every bar and the call is a
		// no-op -- one that boxes two `java.lang.Double` for its optional `high`/`low` on the JVM,
		// every bar of every evaluation (guide §3.1). Hoisting the condition keeps the semantics
		// exactly (any future caller that arrives here in another mode still gets its beginBars)
		// while spending nothing in the case that actually runs.
		var needsBeginBar = orders.executionMode != "same-close" || orders.book.pendingCount() > 0;

		for (i in 0...n) {
			var bar = bars[i];
			if (needsBeginBar) orders.beginBar(bar.open, bar.index, bar.high, bar.low);
			// `long`/`short`/`flat` rather than `submit`: with a Float qty, submit's whole body is
			// a `Reflect.hasField` probe that always fails, a Dynamic unbox and a string switch
			// that always lands here. Same execution, without the reflection.
			if (eL.at(i) >= 0.5 && orders.positionSize() <= 0)
				orders.long(bar.close, sz.at(i), bar.index);
			if (eS.at(i) >= 0.5 && orders.positionSize() >= 0)
				orders.short(bar.close, sz.at(i), bar.index);
			if (eL_exit(xL, xS, i))
				orders.flat(bar.close, bar.index);
			orders.mark(bar.close);
		}
		if (NmaSignalProbe.on)
			NmaSignalProbe.observe(sig, tPack - tCols, tSim - tPack, Sys.time() - tSim);
		return orders;
	}

	/** `Metrics.sharpe(Metrics.returnsFromEquity(eq.toArray()), 0)` without materializing either
	 * array. Two streaming passes over the curve; same guards, same annualization. */
	static function sharpeOfEquity(eq:GrowableVec<Float>):Float {
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
		return (mean / std) * Math.sqrt(252);
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

	/** Stable content signature of the tape (all signal columns derive from OHLCV; close carries the
	 * shape). Cheap FNV-1a over the close values so the SAME tape interns one epoch across genomes
	 * (future cross-genome memo sharing), different tapes never collide. Indexed scan — `for..in`
	 * over `Array<Float>` boxes on the JVM target (JIT_AUTHORING_GUIDE.md §3.3).
	 *
	 * «ἄναξ ταυρόκερως, εὐαστήρ, πυρίσπορε.»
	 */
	static function tapeKey(close:Array<Float>):String {
		var h:Int = 0x811c9dc5;
		var i = 0;
		while (i < close.length) {
			var bits = haxe.io.FPHelper.doubleToI64(close[i]);
			h = (h ^ bits.low) * 0x01000193;
			h = (h ^ bits.high) * 0x01000193;
			i++;
		}
		return "nmafit:" + close.length + ":" + h;
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
	public final fields:Map<String, Array<Float>>;
	/** Real bar timestamps — the generic indicator tier needs them (session/time-of-day
	 * indicators read `bar.time`; synthetic times would be a silent parity break). */
	public final times:Array<Float>;
	public final columns:NmaColumnCache;

	public function new(bars:Array<Bar>, n:Int, key:String, fields:Map<String, Array<Float>>,
			times:Array<Float>, columns:NmaColumnCache) {
		this.bars = bars;
		this.n = n;
		this.key = key;
		this.fields = fields;
		this.times = times;
		this.columns = columns;
	}
}
