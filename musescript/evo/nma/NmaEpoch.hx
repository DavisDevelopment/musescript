package musescript.evo.nma;

import musescript.evo.EvoParam;

/**
 * The partial-eval memo SIGNATURE -- the correctness backbone of every `NmaNode.lastSeries` cache
 * (spec §7's explicit warning). A node's memo is valid iff `node.evalEpoch == epoch.id`; get the
 * key wrong and a node silently serves a series computed for a DIFFERENT tape/params (exactly the
 * stale-fast-path bug class the enum `Fitness` JVM branch already suffered).
 *
 * An epoch is interned from everything a per-bar SIGNAL series depends on:
 *   - the bar tape identity (`tapeKey` -- caller-supplied; reuse the same signature `EvoCache` keys
 *     its tape files by, so two evaluations on the same tape share memo),
 *   - the genome's PARAM VALUES (a `KParam` leaf reads `params[idx]`, so changing a param value
 *     must invalidate every scalar/bool node above it).
 *
 * Cost/slippage is deliberately NOT in the signature: it affects `OrderSim`/fitness, never the
 * signal series a node produces, so folding it in would needlessly bust the signal memo. A separate
 * fitness-level memo (P1 proper) keys on cost too.
 *
 * Interning: identical signatures return the SAME `id` (so a re-evaluation -- an attribution
 * ablation re-running the parent, next generation re-picking an elite -- hits warm memo), distinct
 * signatures get fresh monotonic ids. `-1` is reserved by `NmaNode.evalEpoch` as "never evaluated",
 * so ids start at 0.
 *
 * «ταῦρος δράκων τε καὶ πάλι δράκων ταῦρος.»
 */
class NmaEpoch {
	public final id:Int;
	public final tapeKey:String;

	function new(id:Int, tapeKey:String) {
		this.id = id;
		this.tapeKey = tapeKey;
	}

	/**
	 * Thread contract (JIT guide §27): `registry`/`nextId` are process-global and reachable from
	 * every `CorpusEvoRun` fallback worker under `--nma`. `nextId++` losing a race would alias two
	 * distinct signatures onto one id — silent wrong columns — so both are only ever touched
	 * inside `lock`. Signature construction stays outside it; the critical section is a get/set.
	 */
	static var registry:Map<String, Int> = new Map();
	static var nextId:Int = 0;
	static final lock = new musescript.evo.EvoLock();

	/** Interns `(tapeKey, params)` into a stable epoch. Same signature -> same `id` (warm memo);
	 * new signature -> fresh `id`. Param values are folded in at full precision.
	 *
	 * «στεφάνους πλέκει κισσός· μέθη σοφίαν δίδωσι.»
	 */
	public static function of(tapeKey:String, params:Array<EvoParam>):NmaEpoch {
		var sig = new StringBuf();
		sig.add(tapeKey);
		sig.add("|");
		for (p in params) {
			sig.add(p.defaultValue);
			sig.add(",");
		}
		var s = sig.toString();
		lock.acquire();
		var id:Int;
		try {
			var existing = registry.get(s);
			if (existing != null) {
				id = existing;
			} else {
				id = nextId++;
				registry.set(s, id);
			}
		} catch (e:Dynamic) {
			lock.release();
			throw e;
		}
		lock.release();
		return new NmaEpoch(id, tapeKey);
	}

	/** Test hook: drop all interned signatures (and rewind the id counter). Never call mid-run --
	 * it would let a fresh id collide with a stamp already sitting on a live node's `evalEpoch`.
	 *
	 * «Σεμέλης γόνος ἦλθεν· ἀμπέλου αἷμα ῥεῖ.»
	 */
	public static function resetRegistry():Void {
		lock.acquire();
		registry = new Map();
		nextId = 0;
		lock.release();
	}
}
