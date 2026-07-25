package musescript.evo;

import musescript.ast.Decl;
import musescript.parse.MuseParser;
import musescript.compile.MuseCompiler;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;
import musescript.interp.MuseInterp;
import musescript.builtins.TradeBuiltins;
import musescript.BarStrategyFn;

/**
 * Typed fitness evaluation for genomes.
 * Prefer WASM when available; fall back to interp while keeping backend label honest.
 */
class Fitness {
	/**
	 * Compiled-program cache keyed on `(structural key, target, strict)` -- `Expand.expand(g)`
	 * is a pure function of the genome, and structurally-identical genomes (same
	 * `Canonical.structuralKey`) always produce byte-identical source, so the ENTIRE
	 * parse+TemplateExpand+ModuleExpand+...+CallsiteIds pipeline inside `MuseCompiler.compileEx`
	 * is redundant work on a repeat. This matters enormously for the evo package specifically:
	 * `Variation.attributedSubtreeCrossover`/`attributedPointMutate` call `Fitness.evaluate` as an
	 * ablation ORACLE hundreds of times per generation (baseline + per-site ablations + donor
	 * candidates), on the SAME handful of recurring parent/ablated shapes -- re-parsing and
	 * re-compiling every one of those calls was measured as the dominant cost of a whole
	 * corpus-evo generation (see PLAN_EVO_SPEED.md), dwarfing the actual WASM-accelerated fitness
	 * pass. Only the compiled `fn` + its `decls` (still needed per-call for
	 * `registerDeclPublic` -- see below) are cached; a fresh `HarnessContext`/`MuseInterp`/
	 * `BarFeed`/cross-state reset still happens on EVERY call, so this is a pure compile-cache,
	 * not a memoized RESULT (a genome run on a different tape or cost still gets a correct fresh
	 * execution through the same cached `fn`).
	 */
	static var fnCache:Map<String, {fn:BarStrategyFn, decls:Array<Decl>, backend:String}> = new Map();
	static inline var FN_CACHE_MAX = 4096;

	/** Clears the compiled-program cache -- exposed for tests that care about compile counts,
	 * and for a caller switching to a genuinely different program universe (a fresh corpus-evo
	 * process naturally starts with an empty cache; this is for long-lived processes/tests). */
	public static function clearFnCache():Void fnCache = new Map();

	/**
	 * `costBps` (default 0 -- zero behavior change for any existing caller) sets `OrderSim.book.
	 * slippageBps` before running, so a genome's entries AND exits pay a realistic spread instead
	 * of trading for free. Was silently 0 for EVERY genome this whole evo package ever scored,
	 * because `long(qty)`/`short(qty)`/`flat()` (what Expand.hx renders and what every genome
	 * actually calls) go through OrderSim's legacy immediate-fill path, which -- until fixed
	 * alongside this parameter -- never called `slip()` at all (only the spec-object order-book
	 * path did). A free-trading backtest systematically favors high-frequency genomes (every
	 * MAP-Elites "scalper" niche), since real transaction cost is exactly what punishes overtrading
	 * -- see OrderSim.hx's executeLong/executeShort/executeFlat doc comment for the full story.
	 */
	public static function evaluate(g:StrategyGenome, bars:Array<Bar>, ?target:String = "js", ?strict:Bool = false, ?costBps:Float = 0, ?initialCash:Float = 100000, ?equityFloor:Float = 0.0):FitnessResult {
		try {
			// NOTE: this used to branch on `#if (java || jvm)` into a checker-only fast path
			// that never touched `bars` at all -- it returned trades=max(1,40-nodeCount),
			// finalEquity=100000+trades*10, sharpe=1-nodeCount*0.001, a value derived PURELY
			// from the genome's node count, completely independent of the actual strategy
			// logic or the data passed in. Found via a corpus-evo walk-forward run reporting
			// byte-identical champion stats (trades=31, equity=100310, sharpe=0.991) across
			// unrelated genomes on unrelated tapes -- traced to two DIFFERENT genomes both
			// having nodeCount=9, which is ALL this branch's output actually depended on.
			// Confirmed by re-evaluating the same genome against a 50-bar slice instead of
			// the real 5161-bar tape and getting the identical result. Every JVM-target
			// caller (EvoProof.hx's `build-evo-jvm.hxml` build, and this session's
			// CorpusEvoRun.hx) wanted REAL fitness, not a parsimony-flavored placeholder, so
			// the branch is removed -- JVM now runs the exact same real execution path as
			// every other target, matching MuseCompiler's own documented "js (default) --
			// JsEmitter hot path + eval on JS; MuseInterp elsewhere" fallback contract.
			var cacheKey = Canonical.structuralKey(g) + ":" + target + ":" + strict;
			var cached = fnCache.get(cacheKey);
			var decls:Array<Decl>;
			var fn:BarStrategyFn;
			var backend:String;
			if (cached != null) {
				decls = cached.decls;
				fn = cached.fn;
				backend = cached.backend;
			} else {
				var source = Expand.expand(g);
				var prog = new MuseParser().parse(source, "<evo>");
				var ex = MuseCompiler.compileEx(prog, { target: target, strict: strict });
				decls = prog.decls;
				fn = ex.fn;
				backend = ex.backend;
				if (count(fnCache) >= FN_CACHE_MAX) fnCache = new Map(); // simple full-clear, not an LRU -- see clearFnCache
				fnCache.set(cacheKey, { fn: fn, decls: decls, backend: backend });
			}
			var harness = new HarnessContext();
			if (costBps != 0) harness.orders.book.slippageBps = costBps;
			// `--equity-floor`/bankruptcy crank (see OrderSim.hx's doc comment): both are no-ops at
			// their defaults (100000/0.0), so an existing caller that doesn't pass them sees the
			// exact same OrderSim state a bare `new HarnessContext()` already produced.
			if (initialCash != 100000) harness.orders.reset(initialCash);
			if (equityFloor > 0) harness.orders.equityFloor = equityFloor;
			var seed = new MuseInterp(harness);
			for (d in decls) seed.registerDeclPublic(d);
			harness.feed = new BarFeed(bars);
			TradeBuiltins.resetCrossState();
			var result:Dynamic = fn(harness);
			var fr = new FitnessResult(
				true,
				fieldF(result, "sharpe"),
				fieldI(result, "trades"),
				fieldF(result, "finalEquity"),
				backend
			);
			fr.fills = Reflect.field(result, "fills");
			fr.bankrupt = harness.orders.bankrupt;
			fr.equity = harness.orders.equity.toArray();
			return fr;
		} catch (e:Dynamic) {
			return new FitnessResult(false, -999, 0, 0, "error", Std.string(e));
		}
	}

	public static inline var NEG_INF = -1.0 / 0.0;

	/** `-inf` on a failed run, a missing sharpe, or too few trades — otherwise the raw sharpe,
	 * optionally soft-capped by genome complexity. Matches musegene/evolve.py's `fitness()`
	 * exactly (same NEG_INF-on-invalid contract, same `trades < min_trades` filter to reject
	 * degenerate buy-and-hold genomes).
	 *
	 * `nodeCount`/`parsimonyThreshold`/`parsimonyLambda` are ALL optional and default to no
	 * penalty at all — every existing caller that doesn't pass `nodeCount` sees byte-identical
	 * behavior to before. When a caller DOES opt in, genomes at or below `parsimonyThreshold`
	 * nodes are charged nothing (complexity up to a reasonable size is free — this isn't a
	 * "smaller is always better" bias); only the nodes PAST the threshold are penalized, at
	 * `parsimonyLambda` sharpe per excess node. This used to be explicitly a tiebreak-only
	 * signal (see EvolutionEngine.step's sort, which still exists and still matters for
	 * genomes UNDER the threshold, where no penalty ever applies and exact-fitness ties are
	 * more likely) — a straight `sharpe - nodeCount*k` fudge from node 1 was rejected earlier
	 * for silently reshuffling near-ties, not just true ties. A SOFT CAP keeps that same
	 * "don't quietly override real performance differences on ordinary genomes" property while
	 * still pushing back on unbounded bloat once a genome is genuinely large. */
	public static function score(r:FitnessResult, minTrades:Int = 1,
			?nodeCount:Int, ?parsimonyThreshold:Int = 20, ?parsimonyLambda:Float = 0.01):Float {
		if (!r.ok) return NEG_INF;
		if (Math.isNaN(r.sharpe)) return NEG_INF;
		if (r.trades < minTrades) return NEG_INF;
		var s = r.sharpe;
		if (nodeCount != null && nodeCount > parsimonyThreshold)
			s -= parsimonyLambda * (nodeCount - parsimonyThreshold);
		return s;
	}

	/**
	 * Robustness-adjusted variant of `score()`: splits the backtest's OWN equity curve (`r.
	 * equity`, populated by `evaluate` from `harness.orders.equity` -- already computed for free,
	 * no extra simulator runs needed) into `windows` contiguous segments, scores each segment's
	 * OWN Sharpe independently, and combines them as mean-minus-`windowLambda`*std instead of one
	 * whole-tape Sharpe. A genome that's excellent in one stretch of the tape and mediocre or
	 * harmful elsewhere gets exactly the same single-scalar Sharpe as one that's modestly good
	 * throughout -- windowing is what lets the fitness function actually tell them apart, directly
	 * rewarding robustness instead of a single lucky curve-fit.
	 *
	 * Falls back to plain `score()` (today's exact behavior) whenever windowing wouldn't be
	 * meaningful: `windows <= 1`, no equity curve attached, or too few bars to give every window
	 * at least 2 points to compute a return from. Never a crash, never a NEG_INF where `score()`
	 * would have returned a real number.
	 */
	public static function robustScore(r:FitnessResult, windows:Int, windowLambda:Float, minTrades:Int = 1,
			?nodeCount:Int, ?parsimonyThreshold:Int = 20, ?parsimonyLambda:Float = 0.01):Float {
		if (!r.ok) return NEG_INF;
		if (Math.isNaN(r.sharpe)) return NEG_INF;
		if (r.trades < minTrades) return NEG_INF;
		if (windows <= 1 || r.equity == null || r.equity.length < windows * 2)
			return score(r, minTrades, nodeCount, parsimonyThreshold, parsimonyLambda);
		var segLen = Std.int(r.equity.length / windows);
		var segSharpes:Array<Float> = [];
		for (w in 0...windows) {
			var startI = w * segLen;
			var endI = (w == windows - 1) ? r.equity.length : startI + segLen;
			if (endI - startI < 2) continue;
			var seg = r.equity.slice(startI, endI);
			var rets = musescript.harness.Metrics.returnsFromEquity(seg);
			if (rets.length < 2) continue;
			var sh = musescript.harness.Metrics.sharpe(rets, 0.0);
			if (!Math.isNaN(sh)) segSharpes.push(sh);
		}
		if (segSharpes.length == 0) return score(r, minTrades, nodeCount, parsimonyThreshold, parsimonyLambda);
		var mean = 0.0;
		for (s in segSharpes) mean += s;
		mean /= segSharpes.length;
		var variance = 0.0;
		for (s in segSharpes) variance += (s - mean) * (s - mean);
		variance /= segSharpes.length;
		var std = Math.sqrt(variance);
		var s = mean - windowLambda * std;
		if (nodeCount != null && nodeCount > parsimonyThreshold)
			s -= parsimonyLambda * (nodeCount - parsimonyThreshold);
		return s;
	}

	static function count<T>(m:Map<String, T>):Int {
		var n = 0;
		for (_ in m.keys()) n++;
		return n;
	}

	static function fieldF(o:Dynamic, n:String):Float {
		if (o == null) return 0;
		var v:Dynamic = Reflect.field(o, n);
		if (v == null) return 0;
		return Std.parseFloat(Std.string(v));
	}

	static function fieldI(o:Dynamic, n:String):Int {
		if (o == null) return 0;
		var v:Dynamic = Reflect.field(o, n);
		if (v == null) return 0;
		var p = Std.parseInt(Std.string(v));
		return p != null ? p : Std.int(Std.parseFloat(Std.string(v)));
	}
}
