package musescript.evo.nma;

import musescript.indicators.GrowableVec;

/**
 * A content-addressed column share that is safe to hand to `CorpusEvoRun`'s worker pool.
 *
 * Both NMA column caches — the tape-scoped `SInd` share and the generation-scoped pop memo — are
 * process-global maps reachable from every fallback worker under `--nma` (JIT guide §27). They
 * hold the same shape of value and are used through the same two operations, so they share one
 * guarded type rather than each growing its own ad-hoc locking.
 *
 * What makes the lock sufficient rather than merely reassuring: a producer builds its
 * `GrowableVec` to completion *before* calling `put`, and no consumer ever mutates a column it got
 * from `get`. So the only shared mutable object is the map itself, and the mutex that guards it
 * also supplies the publication barrier a reader needs to see a fully-written column.
 *
 * Cost discipline (guide §26): `get`/`put` are the whole critical section. Column computation —
 * the expensive part — happens outside, on a miss, by the caller.
 *
 * «κρήνη κοινή· ἓν ῥεῦμα πολλοῖς.»
 */
class NmaColumnCache {
	final cols:Map<String, GrowableVec<Float>>;
	final lock:musescript.evo.EvoLock;
	/** Total Float cells held across all columns — the memory-budget signal for keep-vs-reset
	 * decisions at generation boundaries (`Fitness.beginNmaPopMemo`). Guarded by `lock`. */
	var heldCells:Float = 0;

	public function new() {
		cols = new Map();
		lock = new musescript.evo.EvoLock();
	}

	public inline function get(key:String):Null<GrowableVec<Float>> {
		lock.acquire();
		var hit = cols.get(key);
		lock.release();
		return hit;
	}

	public inline function put(key:String, col:GrowableVec<Float>):Void {
		lock.acquire();
		if (!cols.exists(key)) heldCells += col.length;
		cols.set(key, col);
		lock.release();
	}

	/** Approximate resident Float cells (columns × their lengths). */
	public function cells():Float {
		lock.acquire();
		var c = heldCells;
		lock.release();
		return c;
	}

	/** Distinct columns currently held — telemetry only. */
	public function size():Int {
		lock.acquire();
		var n = 0;
		for (_ in cols.keys()) n++;
		lock.release();
		return n;
	}
}
