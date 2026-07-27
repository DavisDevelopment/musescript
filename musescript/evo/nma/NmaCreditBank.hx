package musescript.evo.nma;

import musescript.evo.IntPairList;
import musescript.evo.IntPairMap;
import musescript.evo.StructuralDigest;

typedef CreditStats = {
	var sum:Float;
	var n:Int;
}

/**
 * Process-wide P2 credit bank keyed by bool structural digest lanes `(structA, structB)` — credit
 * survives enum round-trips and travels with a subtree's *shape* across crossover/mutation (paths
 * change; structural keys do not). String keys from `Canonical.boolStructuralKey` parse to the same
 * lanes on deposit/lookup (cold attribution paths); `fromEnum` seeds via words directly.
 *
 * «τιμὴ ψυχῆς· ἀριθμὸς μένει.»
 */
class NmaCreditBank {
	/**
	 * Thread contract (JIT guide §27): process-global and written from every `CorpusEvoRun`
	 * fallback worker under `--nma`. A lost `totalN++` would only blur the UCB exploration term,
	 * but a concurrent table resize can corrupt the table outright — so reads take the lock too.
	 * Sections are get/set only; nothing calls back into NMA while holding it.
	 */
	static var statsByWords:IntPairMap<CreditStats> = new IntPairMap();
	static var totalN:Int = 0;
	static final lock = new musescript.evo.EvoLock();

	static function wordsFromStringKey(key:String):Null<{a:Int, b:Int}> {
		if (key == null || key.length == 0) return null;
		if (StructuralDigest.isHexKey(key))
			return StructuralDigest.wordsFromHexKey(key);
		var d = new StructuralDigest();
		d.str(key);
		d.finishWords();
		return { a: d.outA, b: d.outB };
	}

	static function getStats(a:Int, b:Int):Null<CreditStats> {
		return statsByWords.get(a, b);
	}

	public static function depositWords(a:Int, b:Int, delta:Float):Void {
		if (delta != delta || delta == Math.NEGATIVE_INFINITY || delta == Math.POSITIVE_INFINITY) return;
		lock.acquire();
		var st = statsByWords.get(a, b);
		if (st == null) {
			st = { sum: 0.0, n: 0 };
			statsByWords.set(a, b, st);
		}
		st.sum += delta;
		st.n++;
		totalN++;
		lock.release();
	}

	public static function deposit(key:String, delta:Float):Void {
		var w = wordsFromStringKey(key);
		if (w == null) return;
		depositWords(w.a, w.b, delta);
	}

	public static function meanWords(a:Int, b:Int):Float {
		lock.acquire();
		var st = statsByWords.get(a, b);
		lock.release();
		if (st == null || st.n == 0) return 0.0;
		return st.sum / st.n;
	}

	public static function mean(key:String):Float {
		var w = wordsFromStringKey(key);
		if (w == null) return 0.0;
		return meanWords(w.a, w.b);
	}

	/**
	 * Batch `mean` over digest lanes under one lock — the shape every attribution ranking loop
	 * actually wants. The `Array<String>` overloads below exist for cold callers that still hold
	 * hex; on the hot path the hex never gets built (see `Canonical.boolStructuralInto`).
	 */
	public static function meansPairs(keys:IntPairList):Array<Float> {
		var out = new Array<Float>();
		lock.acquire();
		var i = 0;
		while (i < keys.length) {
			var st = statsByWords.get(keys.a(i), keys.b(i));
			out.push(st == null || st.n == 0 ? 0.0 : st.sum / st.n);
			i++;
		}
		lock.release();
		return out;
	}

	/** `warmEnough` over digest lanes — one lock for the whole set. */
	public static function warmEnoughPairs(keys:IntPairList, ?minN:Int = 2, ?minFrac:Float = 0.5):Bool {
		if (keys.length == 0) return false;
		var warm = 0;
		lock.acquire();
		var i = 0;
		while (i < keys.length) {
			var st = statsByWords.get(keys.a(i), keys.b(i));
			if (st != null && st.n >= minN) warm++;
			i++;
		}
		lock.release();
		return warm / keys.length >= minFrac;
	}

	/** `coldIndices` over digest lanes — one lock for the whole set. */
	public static function coldIndicesPairs(keys:IntPairList, ?minN:Int = 2):Array<Int> {
		var out = new Array<Int>();
		lock.acquire();
		var i = 0;
		while (i < keys.length) {
			var st = statsByWords.get(keys.a(i), keys.b(i));
			if (st == null || st.n < minN) out.push(i);
			i++;
		}
		lock.release();
		return out;
	}

	/**
	 * UCB1 over digest lanes. The string `ucb` reaches for the lock three times (observations,
	 * totalObservations, mean); attribution calls it once per site per child, so this takes it
	 * once.
	 */
	public static function ucbWords(a:Int, b:Int, ?c:Float = 1.4, ?minN:Int = 2):Float {
		lock.acquire();
		var st = statsByWords.get(a, b);
		var total = totalN;
		lock.release();
		var n = st == null ? 0 : st.n;
		if (n < minN) return Math.POSITIVE_INFINITY;
		var t = total < 1 ? 1 : total;
		return (st.sum / n) + c * Math.sqrt(Math.log(t) / n);
	}

	/** `shouldAblate` over digest lanes — one lock instead of five. */
	public static function shouldAblateWords(a:Int, b:Int, bestUcb:Float, ?c:Float = 1.4,
			?minN:Int = 2):Bool {
		lock.acquire();
		var st = statsByWords.get(a, b);
		var total = totalN;
		lock.release();
		var n = st == null ? 0 : st.n;
		if (n < minN) return true;
		var band = c * Math.sqrt(Math.log(total < 1 ? 1 : total) / n);
		return (st.sum / n) + band >= bestUcb - band;
	}

	/** Batch `mean` under one lock — attribution ranking loops hit many keys per child. */
	public static function means(keys:Array<String>):Array<Float> {
		var out = new Array<Float>();
		lock.acquire();
		for (key in keys) {
			var w = wordsFromStringKey(key);
			if (w == null) {
				out.push(0.0);
				continue;
			}
			var st = statsByWords.get(w.a, w.b);
			if (st == null || st.n == 0) out.push(0.0);
			else out.push(st.sum / st.n);
		}
		lock.release();
		return out;
	}

	public static function observationsWords(a:Int, b:Int):Int {
		lock.acquire();
		var st = statsByWords.get(a, b);
		lock.release();
		return st == null ? 0 : st.n;
	}

	public static function observations(key:String):Int {
		var w = wordsFromStringKey(key);
		if (w == null) return 0;
		return observationsWords(w.a, w.b);
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
		statsByWords = new IntPairMap();
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
			var w = wordsFromStringKey(keys[i]);
			if (w == null) {
				out.push(i);
				continue;
			}
			var st = statsByWords.get(w.a, w.b);
			if (st == null || st.n < minN) out.push(i);
		}
		lock.release();
		return out;
	}

	/**
	 * Seed an NMA node's local credit fields from the durable bank (shape prior).
	 * Spec §6b lineage/shape priors — bank is already shape-keyed; this closes cold-start on
	 * freshly minted working copies so node-local readers see history immediately.
	 */
	public static function seedNodeFromBankWords(node:NmaNode, a:Int, b:Int):Void {
		lock.acquire();
		var st = statsByWords.get(a, b);
		lock.release();
		if (st == null || st.n <= 0) return;
		node.creditSum = st.sum;
		node.creditN = st.n;
	}

	public static function seedNodeFromBank(node:NmaNode, key:String):Void {
		var w = wordsFromStringKey(key);
		if (w == null) return;
		seedNodeFromBankWords(node, w.a, w.b);
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
		var seen = new IntPairMap<Bool>();
		var out:Array<Float> = [];
		var totalObs = 0;
		var totalSites = 0;
		function walk(n:musescript.evo.BoolNode):Void {
			var w = musescript.evo.Canonical.boolStructuralWords(n);
			if (!seen.exists(w.a, w.b)) {
				seen.set(w.a, w.b, true);
				totalSites++;
				var nObs = observationsWords(w.a, w.b);
				if (nObs > 0) {
					var m = meanWords(w.a, w.b);
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
