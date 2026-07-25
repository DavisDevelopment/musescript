package musescript.evo;

#if target.threaded
import sys.thread.Deque;
import sys.thread.Thread;
#end

/**
 * Parallel work pool for attribution oracles and (separately) child production.
 *
 * `EvolutionEngine.step` is ~75–84% of generation wall at pop=1000 (measured). Most of that is
 * either independent `Fitness.evaluate` calls on ablation/donor genomes, or independent child
 * production after the serial planning phase has fixed selection/crossover/mutate RNG draws.
 * Both are pool work that historically ran on the main thread.
 *
 * API:
 *  - `score` / `scoreAll` — genome oracle, same contract as today's `evalFn`
 *  - `parallelIndexMap` — run `fn(i)` for i in 0…n-1 across workers; results by index
 *
 * Nesting guard: Phase B child production and nested `scoreAll` share one queue. Nested fan-out
 * would deadlock, so it falls back to sequential — and NmaAttr prefers openSession surgery over
 * that sequential full-eval path (measured: cheaper than independent prepares).
 *
 * Armed by `CorpusEvoRun` for the run; tests leave `current` null and every caller falls back to
 * sequential execution.
 *
 * «πολλοὶ θύρσοι· εἷς χορός κινεῖται.»
 */
class AttrPool {
	public static var current:Null<AttrPool> = null;

	public final scoreFn:StrategyGenome->Float;
	public final workers:Int;

	#if target.threaded
	final nestDepth = new sys.thread.Tls<Int>();
	final tasks:Deque<AttrTask>;
	final dones:Deque<Int>;
	var alive:Bool = false;
	#end

	public function new(scoreFn:StrategyGenome->Float, workers:Int) {
		this.scoreFn = scoreFn;
		this.workers = workers < 1 ? 1 : workers;
		#if target.threaded
		tasks = new Deque();
		dones = new Deque();
		#end
	}

	public function start():Void {
		#if target.threaded
		if (alive || workers <= 1) return;
		alive = true;
		for (_ in 0...workers) {
			Thread.create(function() {
				nestDepth.value = 0;
				while (true) {
					var task = tasks.pop(true);
					if (task.stop) return;
					nestDepth.value = nestDepth.value + 1;
					try task.run() catch (e:Dynamic) {
						nestDepth.value = nestDepth.value - 1;
						dones.add(task.id);
						throw e;
					}
					nestDepth.value = nestDepth.value - 1;
					dones.add(task.id);
				}
			});
		}
		#end
	}

	public function stop():Void {
		#if target.threaded
		if (!alive) return;
		for (_ in 0...workers) tasks.add({id: -1, run: function() {}, stop: true});
		alive = false;
		#end
	}

	public inline function score(g:StrategyGenome):Float return scoreFn(g);

	public function scoreAll(gs:Array<StrategyGenome>):Array<Float> {
		if (gs.length == 0) return [];
		if (gs.length == 1 || workers <= 1 || isNestedHere()) {
			var out = new Array<Float>();
			for (g in gs) out.push(scoreFn(g));
			return out;
		}
		var out = new Array<Float>();
		for (_ in gs) out.push(0.0);
		parallelIndexMap(gs.length, function(i) {
			out[i] = scoreFn(gs[i]);
			return i;
		});
		return out;
	}

	/**
	 * Run `fn(0)…fn(n-1)` across the pool. Selection/crossover-choice/mutate-choice RNG must
	 * already have been drawn on the main thread — this only parallelizes work that no longer
	 * touches those streams. Variation-internal RNG becomes per-slot via
	 * `RngStreams.VARIATION_PARALLEL` when used for child production.
	 */
	public function parallelIndexMap<T>(n:Int, fn:Int->T):Array<T> {
		if (n <= 0) return [];
		if (n == 1 || workers <= 1 || isNestedHere()) {
			var seq = new Array<T>();
			for (i in 0...n) seq.push(fn(i));
			return seq;
		}
		#if target.threaded
		if (!alive) start();
		var held:Array<Null<T>> = [for (_ in 0...n) null];
		var chunk = Std.int(Math.max(1, Math.ceil(n / workers)));
		var nJobs = 0;
		var startIdx = 0;
		var id = 0;
		while (startIdx < n) {
			var endIdx = Std.int(Math.min(n, startIdx + chunk));
			var lo = startIdx;
			var hi = endIdx;
			var jobId = id;
			tasks.add({
				id: jobId,
				run: function() {
					var i = lo;
					while (i < hi) {
						held[i] = fn(i);
						i++;
					}
				},
				stop: false
			});
			nJobs++;
			id++;
			startIdx = endIdx;
		}
		for (_ in 0...nJobs) dones.pop(true);
		return [for (v in held) v];
		#else
		var seq = new Array<T>();
		for (i in 0...n) seq.push(fn(i));
		return seq;
		#end
	}

	/** Convenience: current pool's scoreAll, or a sequential map when none is armed. */
	public static function map(scoreFn:StrategyGenome->Float, gs:Array<StrategyGenome>):Array<Float> {
		var pool = current;
		if (pool != null) return pool.scoreAll(gs);
		var out = new Array<Float>();
		for (g in gs) out.push(scoreFn(g));
		return out;
	}

	/**
	 * True when the calling thread is already inside an AttrPool worker task. Nested
	 * `scoreAll` would enqueue onto the same queue and deadlock (falls back to sequential);
	 * NmaAttr should prefer openSession surgery in that case.
	 */
	public static function isNested():Bool {
		var p = current;
		return p != null && p.isNestedHere();
	}

	public function isNestedHere():Bool {
		#if target.threaded
		return nestDepth.value > 0;
		#else
		return false;
		#end
	}
}

#if target.threaded
@:structInit
class AttrTask {
	public var id:Int;
	public var run:()->Void;
	public var stop:Bool;
}
#end
