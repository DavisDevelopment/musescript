package musescript.evo;

import musescript.parse.MuseParser;
import musescript.compile.MuseCompiler;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;
import musescript.interp.MuseInterp;
import musescript.builtins.TradeBuiltins;

/**
 * Typed fitness evaluation for genomes.
 * Prefer WASM when available; fall back to interp while keeping backend label honest.
 */
class Fitness {
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
	public static function evaluate(g:StrategyGenome, bars:Array<Bar>, ?target:String = "js", ?strict:Bool = false, ?costBps:Float = 0):FitnessResult {
		var source = Expand.expand(g);
		try {
			var prog = new MuseParser().parse(source, "<evo>");
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
			var harness = new HarnessContext();
			if (costBps != 0) harness.orders.book.slippageBps = costBps;
			var seed = new MuseInterp(harness);
			for (d in prog.decls) seed.registerDeclPublic(d);
			harness.feed = new BarFeed(bars);
			TradeBuiltins.resetCrossState();
			var ex = MuseCompiler.compileEx(prog, { target: target, strict: strict });
			var result:Dynamic = ex.fn(harness);
			var fr = new FitnessResult(
				true,
				fieldF(result, "sharpe"),
				fieldI(result, "trades"),
				fieldF(result, "finalEquity"),
				ex.backend
			);
			fr.fills = Reflect.field(result, "fills");
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
