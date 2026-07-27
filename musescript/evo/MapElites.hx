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
 *
 * Classic mode: fixed 4×4×3 = 48 cadence bins (`cellKey`). CVT mode (`--cvt-cells N`): nearest
 * of N Sobol centroids over descriptor-v2 axes (trades/hold/bias/dutyCycle) — archive size is a
 * knob, not an accidental 48. Optional 5th axis (`creditConc`) via `--credit-map-axis` (HHI of
 * |NmaCreditBank| means over bool sites) — orthogonal to cadence; classic 48 keys unchanged.
 */
@:structInit
class FillDescriptor {
	public var avgHold:Float;
	public var longFrac:Float;
	/** Fraction of bars spent in a position (descriptor v2). Neutral default 0 when no fills. */
	public var dutyCycle:Float;
}

class MapElites {
	/** Raw (unbinned) behavioral stats, cheap to derive from `fills` in one pass. Kept separate
	 * from the binned `BehaviorDescriptor` below so `EvoCache` can persist just these floats
	 * per genome (see CachedEval) without needing to know this run's bin boundaries -- a later run
	 * can re-bin warm-started genomes with different thresholds for free. */
	public static function describeFills(fills:Null<Array<Fill>>, nBars:Int):FillDescriptor {
		if (fills == null || fills.length == 0) return {avgHold: 0.0, longFrac: 0.5, dutyCycle: 0.0};
		var longCount = 0, shortCount = 0;
		var holdSum = 0.0, holdN = 0;
		var barsInPos = 0.0;
		var openBar = -1;
		for (f in fills) {
			if (f.kind == "long" || f.kind == "short") {
				// executeLong/executeShort always emits its own "flat" fill FIRST when reversing a
				// position (see OrderSim.executeLong/executeShort), so an open-while-open here would
				// mean a same-bar reversal's flat hasn't been seen yet -- close out the stale open
				// against THIS bar rather than let a stray open leak an unbounded holding period.
				if (openBar >= 0) {
					var h = (f.bar - openBar);
					holdSum += h; holdN++; barsInPos += h;
				}
				openBar = f.bar;
				if (f.kind == "long") longCount++ else shortCount++;
			} else if (f.kind == "flat" && openBar >= 0) {
				var h2 = (f.bar - openBar);
				holdSum += h2; holdN++; barsInPos += h2;
				openBar = -1;
			}
		}
		if (openBar >= 0 && nBars > openBar) {
			barsInPos += (nBars - 1 - openBar);
		}
		var directional = longCount + shortCount;
		return {
			avgHold: holdN > 0 ? holdSum / holdN : 0.0,
			longFrac: directional > 0 ? longCount / directional : 0.5,
			dutyCycle: nBars > 0 ? Math.min(1.0, barsInPos / nBars) : 0.0
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

	/** Unit-cube descriptor for CVT (descriptor v2). Scales match noveltyDistance axes.
	 * When `creditConc` is non-null, appends a 5th axis (credit concentration HHI in [0,1]).
	 * Omit / pass null to keep 4-D (callers that don't opt into `--credit-map-axis`). */
	public static function behaviorVec(tradesPerBar:Float, avgHold:Float, longFrac:Float, dutyCycle:Float,
			?creditConc:Null<Float> = null):Array<Float> {
		var v = [
			clamp01(tradesPerBar / 0.2),
			clamp01(avgHold / 40.0),
			clamp01(longFrac),
			clamp01(dutyCycle)
		];
		if (creditConc != null) v.push(clamp01(creditConc));
		return v;
	}

	/**
	 * Classic grid when `centroids` is null/empty; otherwise nearest Sobol centroid (`cvt_i`).
	 * Pass `creditConc` only when centroids were built with dims=5 (`--credit-map-axis`).
	 */
	public static function assignCell(
		tradesPerBar:Float, avgHold:Float, longFrac:Float,
		?dutyCycle:Float = 0.0,
		?centroids:Array<Array<Float>> = null,
		?creditConc:Null<Float> = null
	):String {
		if (centroids != null && centroids.length > 0) {
			var useCredit = centroids[0].length >= 5 && creditConc != null;
			var v = behaviorVec(tradesPerBar, avgHold, longFrac, dutyCycle, useCredit ? creditConc : null);
			// Missing credit means unknown, not maximally diffuse. Keep it at the axis center.
			if (centroids[0].length >= 5 && v.length < 5) v.push(0.5);
			return 'cvt_${nearestCentroid(v, centroids)}';
		}
		return cellKey(tradesPerBar, avgHold, longFrac);
	}

	/**
	 * Evidence-shrunk HHI of |credit means| over distinct bool structural keys in `g`.
	 *
	 * Raw HHI says whether credit is concentrated, but the original axis mapped a cold bank to
	 * `0.0`, indistinguishable from strongly evidenced diffuse credit. V2 maps cold/weak evidence
	 * to neutral `0.5`, then moves toward raw HHI as observations accumulate.
	 */
	public static function creditConcentration(g:StrategyGenome):Float {
		var profile = musescript.evo.nma.NmaCreditBank.profileForGenome(g);
		var means = profile.means;
		if (means.length == 0 || profile.totalSites <= 0) return 0.5;
		var total = 0.0;
		for (m in means) total += m;
		if (total <= 0) return 0.5;
		var hhi = 0.0;
		for (m in means) {
			var s = m / total;
			hhi += s * s;
		}
		// About 95% confidence after ~9 observations per distinct site.
		var confidence = 1.0 - Math.exp(-profile.totalObs / (profile.totalSites * 3.0));
		return clamp01(0.5 + confidence * (hhi - 0.5));
	}

	/** Scrambled-Sobol-ish deterministic centroids in the unit hypercube (no external deps). */
	public static function sobolCentroids(n:Int, dims:Int = 4):Array<Array<Float>> {
		var out:Array<Array<Float>> = [];
		if (n <= 0) return out;
		for (i in 0...n) {
			var pt:Array<Float> = [];
			for (d in 0...dims) {
				// Radical-inverse style: van der Corput in base (d+2), scrambled by i.
				pt.push(vanDerCorput(i + 1, d + 2));
			}
			out.push(pt);
		}
		return out;
	}

	public static function nearestCentroid(v:Array<Float>, centroids:Array<Array<Float>>):Int {
		var bestI = 0;
		var bestD = 1e300;
		for (i in 0...centroids.length) {
			var c = centroids[i];
			var d = 0.0;
			var m = Std.int(Math.min(v.length, c.length));
			for (j in 0...m) {
				var diff = v[j] - c[j];
				d += diff * diff;
			}
			if (d < bestD) { bestD = d; bestI = i; }
		}
		return bestI;
	}

	static function vanDerCorput(n:Int, base:Int):Float {
		var x = 0.0;
		var f = 1.0 / base;
		var i = n;
		while (i > 0) {
			x += (i % base) * f;
			i = Std.int(i / base);
			f /= base;
		}
		return x;
	}

	static inline function clamp01(x:Float):Float {
		return x < 0 ? 0 : (x > 1 ? 1 : x);
	}

	// ---------- forecast-skill niching axis (projections, plan §7) ----------

	/**
	 * Normalize a projection forecast skill (rank-IC / directional accuracy in [-1,1], or `NaN` when
	 * the genome has no scoreable forecast) to a [0,1] descriptor axis. `NaN` → 0.5 (neutral/unknown),
	 * the same convention a missing credit axis uses.
	 */
	public static function normSkill(projSkill:Float):Float {
		if (Math.isNaN(projSkill))
			return 0.5;
		return clamp01((projSkill + 1.0) / 2.0);
	}

	/**
	 * Descriptor-v2 vector with FORECAST SKILL as a 5th axis — so MAP-Elites niches genomes by how
	 * well they FORECAST as well as how they trade, co-evolving forecaster/manager pairs across the
	 * skill spectrum (the locked §7 selection story). Parallel to the `creditConc` axis; a build that
	 * wants both behaviour+credit+skill (6-D) is a caller concern, out of scope here.
	 */
	public static function behaviorVecWithSkill(tradesPerBar:Float, avgHold:Float, longFrac:Float,
			dutyCycle:Float, projSkill:Float):Array<Float> {
		var v = behaviorVec(tradesPerBar, avgHold, longFrac, dutyCycle);
		v.push(normSkill(projSkill));
		return v;
	}

	/**
	 * Nearest 5-D (behaviour + forecast-skill) centroid — build centroids with `sobolCentroids(n, 5)`.
	 * Classic mode (null/empty centroids) keeps the plain cadence `cellKey`: the skill axis is
	 * CVT-only, exactly like `creditConc`, so classic 48-bin runs are unchanged.
	 */
	public static function assignCellWithSkill(tradesPerBar:Float, avgHold:Float, longFrac:Float,
			dutyCycle:Float, projSkill:Float, ?centroids:Array<Array<Float>> = null):String {
		if (centroids == null || centroids.length == 0)
			return cellKey(tradesPerBar, avgHold, longFrac);
		return 'cvt_${nearestCentroid(behaviorVecWithSkill(tradesPerBar, avgHold, longFrac, dutyCycle, projSkill), centroids)}';
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
	public var dutyCycle:Float;
	public var creditConc:Float;
}

@:structInit
class CellSummary {
	public var key:String;
	public var fitness:Float;
}

class EliteArchive {
	var cells:Map<String, EliteCell> = new Map();
	/** Lifetime count of offers that created a new cell or improved an incumbent (QD telemetry). */
	public var discoveryCount(default, null):Int = 0;

	public function new() {}

	/** Returns true if this offer changed the archive (new cell or improved incumbent). */
	public function offer(genome:StrategyGenome, fitness:Float, cellKey:String,
			?tradesPerBar:Float = 0.0, ?avgHold:Float = 0.0, ?longFrac:Float = 0.5,
			?dutyCycle:Float = 0.0, ?creditConc:Float = 0.0):Bool {
		if (fitness == Fitness.NEG_INF || Math.isNaN(fitness)) return false;
		var cur = cells.get(cellKey);
		if (cur == null || fitness > cur.fitness) {
			cells.set(cellKey, {
				genome: genome, fitness: fitness,
				tradesPerBar: tradesPerBar, avgHold: avgHold, longFrac: longFrac, dutyCycle: dutyCycle,
				creditConc: creditConc
			});
			discoveryCount++;
			return true;
		}
		return false;
	}

	public function size():Int {
		var n = 0;
		for (_ in cells.keys()) n++;
		return n;
	}

	/** QD-score: Σ max(0, elite fitness) over occupied cells. */
	public function qdScore():Float {
		var s = 0.0;
		for (c in cells) if (c.fitness > 0) s += c.fitness;
		return s;
	}

	/** Occupied / totalCells (pass classic 48 or `--cvt-cells N`). */
	public function coverage(totalCells:Int):Float {
		if (totalCells <= 0) return 0.0;
		return size() / totalCells;
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
	public function noveltyDistance(tradesPerBar:Float, avgHold:Float, longFrac:Float, k:Int = 3,
			?dutyCycle:Float = 0.0, ?creditConc:Float = 0.0):Float {
		if (k < 1) return 0.0;
		// Bounded k-selection instead of collect-all-then-sort. The old shape allocated one boxed
		// `Array<Float>` entry per archive cell and sorted the lot through a comparator closure to
		// read three values off the front -- O(A log A) with A boxed allocations, per genome, per
		// generation, on the serial path. With `--cvt-cells` making A a knob in the hundreds and
		// the population heading for four digits, that is the wrong asymptotics in the wrong place
		// (guide §3.1 boxing, §20 escape analysis).
		//
		// Selection runs on SQUARED distance -- monotonic in distance over non-negatives, so the
		// chosen k and their order are identical -- which leaves exactly k square roots to take
		// instead of A.
		var best = new haxe.ds.Vector<Float>(k);
		for (i in 0...k) best[i] = Math.POSITIVE_INFINITY;
		var filled = 0;
		for (c in cells) {
			var dTrade = (tradesPerBar - c.tradesPerBar) / 0.1; // rough "frequent" scale
			var dHold = (avgHold - c.avgHold) / 20.0; // rough "position" hold-length scale
			var dBias = (longFrac - c.longFrac); // already 0..1
			var dDuty = (dutyCycle - c.dutyCycle);
			var dCred = (creditConc - c.creditConc);
			var d2 = dTrade * dTrade + dHold * dHold + dBias * dBias + dDuty * dDuty + dCred * dCred;
			if (filled < k) filled++;
			else if (d2 >= best[k - 1]) continue;
			// Insertion into a k-slot ordered window; k is 3 in every caller, so the shift is
			// cheaper than any heap would be.
			var i = k - 1;
			while (i > 0 && best[i - 1] > d2) {
				best[i] = best[i - 1];
				i--;
			}
			best[i] = d2;
		}
		if (filled == 0) return 0.0;
		var sum = 0.0;
		for (i in 0...filled) sum += Math.sqrt(best[i]);
		return sum / filled;
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
