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
@:structInit
class FillDescriptor {
	public var avgHold:Float;
	public var longFrac:Float;
}

class MapElites {
	/** Raw (unbinned) behavioral stats, cheap to derive from `fills` in one pass. Kept separate
	 * from the binned `BehaviorDescriptor` below so `EvoCache` can persist just these two floats
	 * per genome (see CachedEval) without needing to know this run's bin boundaries -- a later run
	 * can re-bin warm-started genomes with different thresholds for free. */
	public static function describeFills(fills:Null<Array<Fill>>, nBars:Int):FillDescriptor {
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
 *
 * `tradesPerBar`/`avgHold`/`longFrac` -- the SAME raw behavioral descriptor `cellKey` was already
 * binned from (see `offer`'s caller in CorpusEvoRun.hx) -- are carried alongside the genome now,
 * for `noveltyDistance` below (CorpusEvoRun's opt-in `--novelty-weight`): a k-nearest-archived-
 * exemplar novelty bonus needs the UNBINNED descriptor to compute a real distance, not just which
 * of the 48 coarse cells a genome landed in.
 */
@:structInit
class EliteCell {
	public var genome:StrategyGenome;
	public var fitness:Float;
	public var tradesPerBar:Float;
	public var avgHold:Float;
	public var longFrac:Float;
}

@:structInit
class CellSummary {
	public var key:String;
	public var fitness:Float;
}

class EliteArchive {
	var cells:Map<String, EliteCell> = new Map();

	public function new() {}

	/** Returns true if this offer changed the archive (new cell or improved incumbent). */
	public function offer(genome:StrategyGenome, fitness:Float, cellKey:String,
			?tradesPerBar:Float = 0.0, ?avgHold:Float = 0.0, ?longFrac:Float = 0.5):Bool {
		if (fitness == Fitness.NEG_INF || Math.isNaN(fitness)) return false;
		var cur = cells.get(cellKey);
		if (cur == null || fitness > cur.fitness) {
			cells.set(cellKey, {genome: genome, fitness: fitness, tradesPerBar: tradesPerBar, avgHold: avgHold, longFrac: longFrac});
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

	/**
	 * Novelty score for a query descriptor -- mean Euclidean distance (each axis independently
	 * normalized by a rough expected scale, so trade-frequency/hold-length/direction-bias
	 * contribute comparably) to its `k` nearest archived exemplars. `0.0` when the archive is
	 * empty (nothing to be novel RELATIVE TO yet) -- CorpusEvoRun's `--novelty-weight` multiplies
	 * this, so an empty-archive generation-0 call is a harmless no-op, not a crash.
	 */
	public function noveltyDistance(tradesPerBar:Float, avgHold:Float, longFrac:Float, k:Int = 3):Float {
		var dists:Array<Float> = [];
		for (c in cells) {
			var dTrade = (tradesPerBar - c.tradesPerBar) / 0.1; // rough "frequent" scale
			var dHold = (avgHold - c.avgHold) / 20.0; // rough "position" hold-length scale
			var dBias = (longFrac - c.longFrac); // already 0..1
			dists.push(Math.sqrt(dTrade * dTrade + dHold * dHold + dBias * dBias));
		}
		if (dists.length == 0) return 0.0;
		dists.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		var n = Std.int(Math.min(k, dists.length));
		var sum = 0.0;
		for (i in 0...n) sum += dists[i];
		return sum / n;
	}

	/** Cell key + fitness, for reporting a diversity summary at end of run. */
	public function summary():Array<CellSummary> {
		var out:Array<CellSummary> = [for (key => c in cells) {key: key, fitness: c.fitness}];
		out.sort((a, b) -> a.key < b.key ? -1 : (a.key > b.key ? 1 : 0));
		return out;
	}

	/** Full `(key, cell)` pairs, sorted the same way `summary()` is -- for a caller (CorpusEvoRun's
	 * `--save-elites`) that wants the actual GENOME per cell, not just its fitness. */
	public function entries():Array<{key:String, cell:EliteCell}> {
		var out:Array<{key:String, cell:EliteCell}> = [for (key => c in cells) {key: key, cell: c}];
		out.sort((a, b) -> a.key < b.key ? -1 : (a.key > b.key ? 1 : 0));
		return out;
	}
}
