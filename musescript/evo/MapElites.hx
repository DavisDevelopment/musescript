package musescript.evo;

import musescript.harness.Fill;

/**
 * Behavioral-descriptor archive for diversity preservation -- the direct fix for the corpus-evo
 * runs' real failure mode: the population collapsing to clones of ONE behavioral basin (every
 * OOS top-10 slot being a variant of the same price-crosses-its-own-average family) by generation
 * 3, wasting the rest of the run re-selecting near-duplicates instead of exploring. Raw-fitness
 * selection (EvolutionEngine.step's tournament + elitism) is exactly what CAUSES this: a fitter
 * basin outcompetes every other basin for every tournament, every generation, forever.
 *
 * MAP-Elites keeps the best genome PER behavioral cell instead of best-overall, so a
 * low-turnover mean-reverter and a high-frequency scalper and a long-only trend-follower can all
 * survive at once even if one of them currently has the highest raw fitness -- each is the best
 * genome *of its kind*, not competing against the others for a single slot.
 *
 * The descriptor is derived from `BacktestResult.fills` -- state every backend (interp, JS, native
 * WASM) already produces identically via the SHARED `OrderSim` (see BacktestResult.hx's doc
 * comment), so this needed zero new bookkeeping paths that could drift from what the simulator
 * actually did.
 */
class MapElites {
	/** Raw (unbinned) behavioral stats, cheap to derive from `fills` in one pass. Kept separate
	 * from the binned `BehaviorDescriptor` below so `EvoCache` can persist just these two floats
	 * per genome (see CachedEval) without needing to know this run's bin boundaries -- a later run
	 * can re-bin warm-started genomes with different thresholds for free. */
	public static function describeFills(fills:Null<Array<Fill>>, nBars:Int):{avgHold:Float, longFrac:Float} {
		if (fills == null || fills.length == 0) return {avgHold: 0.0, longFrac: 0.5};
		var longCount = 0, shortCount = 0;
		var holdSum = 0.0, holdN = 0;
		var openBar = -1;
		for (f in fills) {
			if (f.kind == "long" || f.kind == "short") {
				// executeLong/executeShort always emits its own "flat" fill FIRST when reversing a
				// position (see OrderSim.executeLong/executeShort), so an open-while-open here would
				// mean a same-bar reversal's flat hasn't been seen yet -- close out the stale open
				// against THIS bar rather than let a stray open leak an unbounded holding period.
				if (openBar >= 0) { holdSum += (f.bar - openBar); holdN++; }
				openBar = f.bar;
				if (f.kind == "long") longCount++ else shortCount++;
			} else if (f.kind == "flat" && openBar >= 0) {
				holdSum += (f.bar - openBar);
				holdN++;
				openBar = -1;
			}
		}
		var directional = longCount + shortCount;
		return {
			avgHold: holdN > 0 ? holdSum / holdN : 0.0,
			longFrac: directional > 0 ? longCount / directional : 0.5
		};
	}

	public static function binTradeFreq(tradesPerBar:Float):Int {
		if (tradesPerBar < 0.01) return 0; // rare
		if (tradesPerBar < 0.05) return 1; // occasional
		if (tradesPerBar < 0.15) return 2; // frequent
		return 3; // scalper
	}

	public static function binHold(avgHold:Float):Int {
		if (avgHold < 3) return 0; // very short hold
		if (avgHold < 10) return 1; // swing
		if (avgHold < 40) return 2; // position
		return 3; // long-hold
	}

	public static function binBias(longFrac:Float):Int {
		if (longFrac < 0.35) return 0; // short-dominant
		if (longFrac > 0.65) return 2; // long-dominant
		return 1; // mixed / both directions
	}

	public static function cellKey(tradesPerBar:Float, avgHold:Float, longFrac:Float):String {
		return '${binTradeFreq(tradesPerBar)}_${binHold(avgHold)}_${binBias(longFrac)}';
	}
}

/**
 * One champion genome per occupied behavioral cell. `offer` is idempotent-safe to call every
 * generation for every evaluated genome — a cell only updates when a STRICTLY better fitness
 * arrives, so a worse re-offering (e.g. the same structural key recurring with a penalty-adjusted
 * score) never evicts a stronger incumbent.
 */
class EliteArchive {
	var cells:Map<String, {genome:StrategyGenome, fitness:Float}> = new Map();

	public function new() {}

	/** Returns true if this offer changed the archive (new cell or improved incumbent). */
	public function offer(genome:StrategyGenome, fitness:Float, cellKey:String):Bool {
		if (fitness == Fitness.NEG_INF || Math.isNaN(fitness)) return false;
		var cur = cells.get(cellKey);
		if (cur == null || fitness > cur.fitness) {
			cells.set(cellKey, {genome: genome, fitness: fitness});
			return true;
		}
		return false;
	}

	public function size():Int {
		var n = 0;
		for (_ in cells.keys()) n++;
		return n;
	}

	public function elites():Array<StrategyGenome> {
		return [for (c in cells) c.genome];
	}

	/** Cell key + fitness, for reporting a diversity summary at end of run. */
	public function summary():Array<{key:String, fitness:Float}> {
		var out = [for (key => c in cells) {key: key, fitness: c.fitness}];
		out.sort((a, b) -> a.key < b.key ? -1 : (a.key > b.key ? 1 : 0));
		return out;
	}
}
