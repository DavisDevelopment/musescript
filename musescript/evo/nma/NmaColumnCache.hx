package musescript.evo.nma;

import musescript.evo.IntPairMap;
import musescript.indicators.GrowableVec;

/**
 * A content-addressed column share that is safe to hand to `CorpusEvoRun`'s worker pool.
 *
 * Both NMA column caches — the tape-scoped `SInd`/price share and the generation-scoped pop memo —
 * are process-global maps reachable from every fallback worker under `--nma` (JIT guide §27). They
 * hold the same shape of value and are used through the same two operations, so they share one
 * guarded type rather than each growing its own ad-hoc locking.
 *
 * Two key spaces live here:
 *   - **Words** (`getWords`/`putWords`): the hot path. A `(a,b)` pair of avalanched FNV lanes from
 *     `StructuralDigest` — no `String`, no `byte[]`, no `Std.string(Float)`. Measured as ~62% of
 *     JVM allocation under `--nma` before this existed, which is why the evaluation barrier did not
 *     shrink with `--threads`.
 *   - **Strings** (`get`/`put`): the cold path. Price-field and feature-expression keys, a handful
 *     per tape. Left as strings because they are few and not on the barrier's critical path.
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
	final byStr:Map<String, GrowableVec<Float>>;
	final byWord:IntPairMap<GrowableVec<Float>>;
	final lock:musescript.evo.EvoLock;
	/** Total Float cells held across all columns — the memory-budget signal for keep-vs-reset
	 * decisions at generation boundaries (`Fitness.beginNmaPopMemo`). Guarded by `lock`. */
	var heldCells:Float = 0;

	public function new() {
		byStr = new Map();
		byWord = new IntPairMap();
		lock = new musescript.evo.EvoLock();
	}

	public inline function get(key:String):Null<GrowableVec<Float>> {
		lock.acquire();
		var hit = byStr.get(key);
		lock.release();
		return hit;
	}

	public inline function put(key:String, col:GrowableVec<Float>):Void {
		lock.acquire();
		if (!byStr.exists(key)) heldCells += col.length;
		byStr.set(key, col);
		lock.release();
	}

	public inline function getWords(a:Int, b:Int):Null<GrowableVec<Float>> {
		lock.acquire();
		var hit = byWord.get(a, b);
		lock.release();
		return hit;
	}

	public inline function putWords(a:Int, b:Int, col:GrowableVec<Float>):Void {
		lock.acquire();
		if (!byWord.exists(a, b)) heldCells += col.length;
		byWord.set(a, b, col);
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
		for (_ in byStr.keys()) n++;
		n += byWord.size();
		lock.release();
		return n;
	}
}
