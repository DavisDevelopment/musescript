package musescript.evo.nma;

/**
 * Process-wide P2 credit bank keyed by `Canonical.boolStructuralKey` — credit survives enum
 * round-trips and travels with a subtree's *shape* across crossover/mutation (paths change;
 * structural keys do not).
 *
 * «τιμὴ ψυχῆς· ἀριθμὸς μένει.»
 */
class NmaCreditBank {
	/**
	 * Thread contract (JIT guide §27): process-global and written from every `CorpusEvoRun`
	 * fallback worker under `--nma`. A lost `totalN++` would only blur the UCB exploration term,
	 * but a concurrent `StringMap` resize can corrupt the table outright — so reads take the lock
	 * too. Sections are get/set only; nothing calls back into NMA while holding it.
	 */
	static var sumByKey:Map<String, Float> = new Map();
	static var nByKey:Map<String, Int> = new Map();
	static var totalN:Int = 0;
	static final lock = new musescript.evo.EvoLock();

	public static function deposit(key:String, delta:Float):Void {
		if (key == null || key.length == 0) return;
		if (delta != delta || delta == Math.NEGATIVE_INFINITY || delta == Math.POSITIVE_INFINITY) return;
		lock.acquire();
		var s = sumByKey.exists(key) ? sumByKey.get(key) : 0.0;
		var n = nByKey.exists(key) ? nByKey.get(key) : 0;
		sumByKey.set(key, s + delta);
		nByKey.set(key, n + 1);
		totalN++;
		lock.release();
	}

	public static function mean(key:String):Float {
		lock.acquire();
		var n = nByKey.get(key);
		var s = n == null || n == 0 ? 0.0 : sumByKey.get(key);
		lock.release();
		if (n == null || n == 0) return 0.0;
		return s / n;
	}

	/** Batch `mean` under one lock — attribution ranking loops hit many keys per child. */
	public static function means(keys:Array<String>):Array<Float> {
		var out = new Array<Float>();
		lock.acquire();
		for (key in keys) {
			var n = nByKey.get(key);
			if (n == null || n == 0) out.push(0.0);
			else out.push(sumByKey.get(key) / n);
		}
		lock.release();
		return out;
	}

	public static function observations(key:String):Int {
		lock.acquire();
		var n = nByKey.get(key);
		lock.release();
		return n == null ? 0 : n;
	}

	public static function totalObservations():Int {
		lock.acquire();
		var t = totalN;
		lock.release();
		return t;
	}

	/**
	 * UCB1-style score: mean + c·√(ln T / n). Cold keys (`n < minN`) score +∞ (always ablate).
	 *
	 * «τύχη καὶ τέχνη· ζυγὸν ἴσον.»
	 */
	public static function ucb(key:String, ?c:Float = 1.4, ?minN:Int = 2):Float {
		var n = observations(key);
		if (n < minN) return Math.POSITIVE_INFINITY;
		var total = totalObservations();
		var t = total < 1 ? 1 : total;
		return mean(key) + c * Math.sqrt(Math.log(t) / n);
	}

	/**
	 * Whether to spend an ablation eval on this site. Ablate when cold, or when UCB overlaps the
	 * best site's UCB band; otherwise reuse bank mean (budget save).
	 *
	 * «φείδου πόνου· καιρὸς δαπανᾷ.»
	 */
	public static function shouldAblate(key:String, bestUcb:Float, ?c:Float = 1.4, ?minN:Int = 2):Bool {
		var n = observations(key);
		if (n < minN) return true;
		var u = ucb(key, c, minN);
		// Overlap / competitive with best → keep measuring.
		if (u >= bestUcb - c * Math.sqrt(Math.log(Math.max(1, totalObservations())) / n)) return true;
		return false;
	}

	public static function clear():Void {
		lock.acquire();
		sumByKey = new Map();
		nByKey = new Map();
		totalN = 0;
		lock.release();
	}

	/** True when at least `minFrac` of `keys` have ≥ `minN` observations (credit-cuts gate). */
	public static function warmEnough(keys:Array<String>, ?minN:Int = 2, ?minFrac:Float = 0.5):Bool {
		if (keys.length == 0) return false;
		var warm = 0;
		for (k in keys) if (observations(k) >= minN) warm++;
		return warm / keys.length >= minFrac;
	}

	/**
	 * Indices of keys that still need a live ablation/donor oracle under hybrid credit-cuts
	 * (`observations < minN`). Warm keys are ranked from the bank alone.
	 */
	public static function coldIndices(keys:Array<String>, ?minN:Int = 2):Array<Int> {
		var out = new Array<Int>();
		lock.acquire();
		for (i in 0...keys.length) {
			var n = nByKey.get(keys[i]);
			if (n == null || n < minN) out.push(i);
		}
		lock.release();
		return out;
	}

	/**
	 * Seed an NMA node's local credit fields from the durable bank (shape prior).
	 * Spec §6b lineage/shape priors — bank is already shape-keyed; this closes cold-start on
	 * freshly minted working copies so node-local readers see history immediately.
	 */
	public static function seedNodeFromBank(node:NmaNode, key:String):Void {
		var n = observations(key);
		if (n <= 0) return;
		var m = mean(key);
		node.creditSum = m * n;
		node.creditN = n;
	}

	/**
	 * Absolute mean credits for every distinct bool structural key present in `g` that has bank
	 * observations. Used by `MapElites.creditConcentration` (HHI). Empty when bank is cold /
	 * genome has no credited keys. Dedupes by key so repeated shapes (same leaf in many roots)
	 * count once.
	 */
	public static function meansForGenome(g:musescript.evo.StrategyGenome):Array<Float> {
		return profileForGenome(g).means;
	}

	/**
	 * Distinct-site credit profile for MAP descriptor reliability. `totalObs` is summed only over
	 * keys present in the genome; `totalSites` includes cold keys.
	 */
	public static function profileForGenome(g:musescript.evo.StrategyGenome):
			{means:Array<Float>, totalObs:Int, creditedSites:Int, totalSites:Int} {
		var seen:Map<String, Bool> = new Map();
		var out:Array<Float> = [];
		var totalObs = 0;
		var totalSites = 0;
		function walk(n:musescript.evo.BoolNode):Void {
			var key = musescript.evo.Canonical.boolStructuralKey(n);
			if (!seen.exists(key)) {
				seen.set(key, true);
				totalSites++;
				var nObs = observations(key);
				if (nObs > 0) {
					var m = mean(key);
					out.push(m < 0 ? -m : m);
					totalObs += nObs;
				}
			}
			switch (n) {
				case BAnd(a, b) | BOr(a, b): walk(a); walk(b);
				case BNot(a) | BHole(a): walk(a);
				default:
			}
		}
		walk(g.entryLong); walk(g.entryShort); walk(g.exitLong); walk(g.exitShort);
		return {
			means: out,
			totalObs: totalObs,
			creditedSites: out.length,
			totalSites: totalSites
		};
	}
}
