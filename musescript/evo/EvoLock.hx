package musescript.evo;

/**
 * The thread contract for `evo/`'s process-global caches (JIT guide §27).
 *
 * `CorpusEvoRun` runs a real worker pool (`fbJobQueue`, `--threads` defaults to cores-1) and every
 * worker calls `Fitness.evaluate`. Under `--nma` / `--exec-profile` that routes straight into the
 * columnar path, whose caches are `static var` — shared by construction, not by choice. Two of
 * those are actively dangerous:
 *
 *  - `NmaEpoch.nextId++` is a non-atomic read-modify-write. Losing that race hands two DIFFERENT
 *    tape/param signatures the same epoch id, so a node memoized under tape A reads as valid for
 *    tape B (`node.evalEpoch == ctx.epoch.id` passes) and serves the wrong column. Silent wrong
 *    numbers — the exact stale-cache class spec §7 exists to prevent.
 *  - `haxe.ds.StringMap` is not thread-safe. Concurrent mutation during a resize can corrupt the
 *    table outright.
 *
 * This is the "make the shared mutability safe" half of §27's remedy. It is deliberately a lock
 * and not a lock-free structure: the critical sections are single map get/set pairs, so the
 * uncontended acquire dominates and there is nothing to win from cleverness. Callers must keep
 * them that way — **never** compute a column, hash a tape, or call back into NMA while holding a
 * lock, and never nest two of them (the locks below have no ordering discipline because nothing
 * takes two).
 *
 * On non-threaded targets (js, where the test suite runs) every method compiles to nothing.
 *
 * «εἷς οἶνος, πολλοὶ κρατῆρες· μία μοῖρα νέμει.»
 */
class EvoLock {
	#if target.threaded
	final m:sys.thread.Mutex;

	public function new() {
		m = new sys.thread.Mutex();
	}

	public inline function acquire():Void m.acquire();

	public inline function release():Void m.release();
	#else
	public function new() {}

	public inline function acquire():Void {}

	public inline function release():Void {}
	#end
}
