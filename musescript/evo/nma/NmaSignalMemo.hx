package musescript.evo.nma;

import musescript.evo.EvoLock;
import musescript.evo.IntPairMap;
import musescript.evo.StructuralDigest;
import musescript.harness.Fill;
import musescript.indicators.GrowableVec;

/**
 * Generation-scoped memo from bit-packed trading signals → already-simulated fitness facts.
 *
 * Exact identity (see `NmaSignalPack`): genomes that agree on the five columns `OrderSim` reads
 * cannot diverge on fills, equity, or Sharpe on the same tape and cost settings. Structural keys
 * miss that — `x > y` and `!(x <= y)` are different trees and the same strategy — so ~850–990
 * structural uniques/gen still collapse onto far fewer signal signatures. Measured under
 * `--signal-probe`: once pop-memo warms columns, `OrderSim` is a large share of eval CPU; skipping
 * it on a signature hit is free correctness.
 *
 * Parallel workers racing the same miss used to *all* OrderSim and only the last `put` landed —
 * probe dup rates of 70–85% against `sigMemoHits` of ~30–60/gen. Single-flight claims convert
 * those lost races into waits: one owner sims, waiters take the published entry.
 *
 * Keyed by avalanched `(a,b)` words (no `String`, no `Map<Int>` boxing). Cleared each generation
 * with the pop memo — cross-gen reuse belongs to `EvoCache`, not here.
 *
 * «πολλαὶ μορφαί, μία σφραγίς· ἅπαξ ἔδραμεν.»
 */
class NmaSignalMemo {
	public static var enabled:Bool = true;

	static final lock = new EvoLock();
	static var byWords:Null<IntPairMap<NmaSignalMemoEntry>> = null;
	/** In-flight sims keyed by the same words — waiters block on the owner's publish/fail. */
	static var flights:Null<IntPairMap<SignalFlight>> = null;
	public static var hits:Int = 0;
	public static var puts:Int = 0;
	/** Times a worker blocked on another thread's in-flight sim for the same signature. */
	public static var waits:Int = 0;

	/** Start / wipe the gen-scoped table (call beside `Fitness.beginNmaPopMemo`). */
	public static function begin():Void {
		lock.acquire();
		byWords = enabled ? new IntPairMap(1024) : null;
		flights = enabled ? new IntPairMap(256) : null;
		hits = 0;
		puts = 0;
		waits = 0;
		lock.release();
	}

	public static function clear():Void {
		lock.acquire();
		byWords = null;
		flights = null;
		hits = 0;
		puts = 0;
		waits = 0;
		lock.release();
	}

	/**
	 * Mix tape + cost settings + the five sim-visible columns into `d.outA`/`d.outB`.
	 * Returns false when any root is sim-coupled (no stable pre-sim columns).
	 */
	public static function wordsOf(ctx:NmaEvalContext, eL:GrowableVec<Float>, eS:GrowableVec<Float>,
			xL:GrowableVec<Float>, xS:GrowableVec<Float>, sz:GrowableVec<Float>,
			costBps:Float, initialCash:Float, equityFloor:Float, d:StructuralDigest):Bool {
		d.reset();
		d.word(ctx.epoch.tapeA);
		d.word(ctx.epoch.tapeB);
		d.float(costBps);
		d.float(initialCash);
		d.float(equityFloor);
		NmaSignalPack.mixColumns(d, eL, eS, xL, xS, sz, ctx.n);
		d.finishWords();
		return true;
	}

	/** Lookup without bumping `hits` — caller notes a hit only after accepting the entry. */
	public static function get(a:Int, b:Int):Null<NmaSignalMemoEntry> {
		lock.acquire();
		var table = byWords;
		var hit = table != null ? table.get(a, b) : null;
		lock.release();
		return hit;
	}

	public static function noteHit():Void {
		lock.acquire();
		hits++;
		lock.release();
	}

	static inline function acceptable(e:NmaSignalMemoEntry, needFills:Bool, needEquity:Bool):Bool {
		if (needFills && e.fills == null) return false;
		if (needEquity && e.equity == null) return false;
		return true;
	}

	/**
	 * Hit, wait-for-owner, or claim ownership. Returns an entry when this thread should not sim;
	 * `null` means this thread owns the flight and must `put` or `fail` the same `(a,b)`.
	 *
	 * A waiter only joins a flight whose owner promised enough payload (`needFills` /
	 * `needEquity`); a weaker in-flight score-only sim does not block a fills-needing caller.
	 */
	public static function claim(a:Int, b:Int, needFills:Bool, needEquity:Bool):Null<NmaSignalMemoEntry> {
		while (true) {
			lock.acquire();
			var table = byWords;
			var fl = flights;
			if (table == null || fl == null) {
				lock.release();
				return null;
			}
			var hit = table.get(a, b);
			if (hit != null && acceptable(hit, needFills, needEquity)) {
				hits++;
				lock.release();
				return hit;
			}
			var f = fl.get(a, b);
			if (f != null) {
				if (f.entry != null && acceptable(f.entry, needFills, needEquity)) {
					hits++;
					lock.release();
					return f.entry;
				}
				if (f.entry == null && !f.failed) {
					var canJoin = (!needFills || f.ownerNeedsFills)
						&& (!needEquity || f.ownerNeedsEquity);
					// Join a compatible owner, or wait out a weaker in-flight sim before retrying
					// (never overwrite an active flight — that would strand its waiters).
					f.waiters++;
					waits++;
					lock.release();
					var waited = f.await();
					if (canJoin && waited != null && acceptable(waited, needFills, needEquity)) {
						noteHit();
						return waited;
					}
					continue;
				}
				// Finished/failed flight we cannot use: fall through and claim a stronger one.
			}
			fl.set(a, b, new SignalFlight(needFills, needEquity));
			lock.release();
			return null;
		}
	}

	/**
	 * Insert, or upgrade a fills-less entry when a full eval arrives. Never shadow a fills-bearing
	 * entry with a score-only put (attribution can race ahead of a second full eval).
	 * Always completes any in-flight claim for `(a,b)` so waiters unblock.
	 */
	public static function put(a:Int, b:Int, e:NmaSignalMemoEntry):Void {
		var wake:Null<SignalFlight> = null;
		var nWake = 0;
		lock.acquire();
		var table = byWords;
		if (table != null) {
			var prior = table.get(a, b);
			if (prior == null) {
				table.set(a, b, e);
				puts++;
			} else if (prior.fills == null && e.fills != null) {
				table.set(a, b, e);
			} else if (prior.equity == null && e.equity != null) {
				table.set(a, b, e);
			}
		}
		var fl = flights;
		if (fl != null) {
			wake = fl.get(a, b);
			if (wake != null && wake.entry == null && !wake.failed) {
				wake.entry = e;
				nWake = wake.waiters;
			}
		}
		lock.release();
		if (wake != null) wake.publish(nWake);
	}

	/** Owner aborted before `put` — wake waiters so they can claim/re-sim. */
	public static function fail(a:Int, b:Int):Void {
		var wake:Null<SignalFlight> = null;
		var nWake = 0;
		lock.acquire();
		var fl = flights;
		if (fl != null) {
			wake = fl.get(a, b);
			if (wake != null && wake.entry == null && !wake.failed) {
				wake.failed = true;
				nWake = wake.waiters;
			}
		}
		lock.release();
		if (wake != null) wake.publish(nWake);
	}

	/** Immutable sim facts safe to share across workers (fills/equity are never mutated). */
	public static function entryOf(trades:Int, sharpe:Float, finalEquity:Float, bankrupt:Bool,
			fills:Null<Array<Fill>>, equity:Null<Array<Float>>):NmaSignalMemoEntry {
		return new NmaSignalMemoEntry(trades, sharpe, finalEquity, bankrupt, fills, equity);
	}
}

/**
 * One in-flight `OrderSim` for a signal signature. Waiters increment `waiters` under the memo
 * lock, then block on `await`; the owner calls `publish` after `put`/`fail`.
 */
private class SignalFlight {
	public var entry:Null<NmaSignalMemoEntry> = null;
	public var failed:Bool = false;
	public var waiters:Int = 0;
	public final ownerNeedsFills:Bool;
	public final ownerNeedsEquity:Bool;
	#if target.threaded
	final gate = new sys.thread.Lock();
	#end

	public function new(needFills:Bool, needEquity:Bool) {
		ownerNeedsFills = needFills;
		ownerNeedsEquity = needEquity;
	}

	public function await():Null<NmaSignalMemoEntry> {
		#if target.threaded
		gate.wait();
		#end
		return entry;
	}

	public function publish(n:Int):Void {
		#if target.threaded
		var i = 0;
		while (i < n) {
			gate.release();
			i++;
		}
		#end
	}
}
