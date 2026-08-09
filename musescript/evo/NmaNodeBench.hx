package musescript.evo;

import musescript.harness.Bar;
import musescript.harness.OhlcvCsv;

/**
 * Node/V8 NMA evolution throughput bench — the JS twin of CorpusEvoRun's `--nma` lightspeed
 * measurement without Graal/Swing.
 *
 * CorpusEvoRun is JVM-only (`build-corpus-evo.hxml`). This entry drives the same hot stack
 * (`Fitness.preferNma` → `NmaFitness` / `NmaEval` / `OrderSim` + `EvolutionEngine.step`) under
 * hxnodejs so V8 opts can be A/B'd against the JVM floor on the same smoke tape.
 *
 * Usage:
 *   haxe build-nma-node-bench.hxml
 *   node build/js/nma-node-bench.js --pop 1000 --gens 6 --tape build/graal/smoke_spy_320.csv
 *   node build/js/nma-node-bench.js --pop 1000 --gens 6 --threads 4 --tape build/graal/smoke_spy_320.csv
 *   node build/js/nma-node-bench.js --pop 1000 --gens 6 --threads 4 --clone-prob 0.4
 *   node build/js/nma-node-bench.js --det-probe --pop 64 --threads 4 --reps 3
 *
 * Reports mean wallMs/gen (full generation including step) and scoreMs (fitness barrier only).
 * `--threads N` fans the population score barrier (and AttrPool attribution batches) across Node
 * `worker_threads` via `NmaNodeEvalPool` resident genome ids. `EvolutionEngine.step` child
 * production stays serial on the main isolate (§33 — Variation memos are not cross-isolate).
 *
 * `--det-probe` (JIT guide §27 owed gate): seed N genomes once, score serial (`threads=1`), then
 * for each M in `--threads-list` (default: `--threads` if >1 else `2,4`) run K independent
 * multi-worker `scoreAll`s and require the fitness vector be identical to serial. `popMemoHits`
 * is partition-dependent and is **not** compared. Dirty-spine is refused for the probe.
 *
 * «Βάκχος καὶ Φοῖβος· δύο λύραι, ἓν μέλος.»
 */
class NmaNodeBench {
	static function main() {
		#if (js && nodejs)
		if (NmaNodeEvalPool.isWorkerThread()) {
			NmaNodeEvalPool.runWorker();
			return;
		}
		#end

		if (argFlag("--det-probe")) {
			runDetProbe();
			return;
		}

		var pop = argInt("--pop", 256);
		var gens = argInt("--gens", 6);
		var seed = argInt("--seed", 42);
		var warm = argInt("--warm", 1);
		var threads = argInt("--threads", 1);
		if (threads < 1) threads = 1;
		var attrBars = argInt("--attr-bars", 128);
		var attrCross = argFloat("--attr-cross-prob", 0.5);
		var cloneProb = argFloat("--clone-prob", 0.0);
		if (cloneProb < 0) cloneProb = 0;
		if (cloneProb > 1) cloneProb = 1;
		var depth = argInt("--depth", 3);
		var dirtySpine = !argFlag("--no-nma-dirty-spine") && argFlag("--nma-dirty-spine");
		if (dirtySpine && threads > 1) {
			Sys.println('NMA dirty-spine: DISABLED -- unsound across $threads worker isolates (use --threads 1 to keep it)');
			dirtySpine = false;
		}

		var tapePath = argStr("--tape", "build/graal/smoke_spy_320.csv");
		var bars = loadBars(tapePath);
		if (bars.length < 60)
			throw 'tape too short: ${bars.length} bars from $tapePath';

		// IS slice mirrors CorpusEvoRun's typical smoke split (keep ~2/3 for IS).
		var isN = Std.int(bars.length * 0.7);
		if (isN < 60) isN = bars.length;
		var isBars = bars.slice(0, isN);
		var attrTape = attrBars <= 0 ? isBars : isBars.slice(0, Std.int(Math.min(attrBars, isBars.length)));

		Fitness.preferNma = true;
		Fitness.nmaPopMemoEnabled = !argFlag("--no-nma-pop-memo");
		Fitness.nmaDirtySpine = dirtySpine;
		Fitness.nmaTape = attrTape;
		Fitness.nmaCostBps = 0;
		Fitness.nmaInitialCash = 100000;
		Fitness.nmaEquityFloor = 0;
		Fitness.attrBandit = !argFlag("--no-attr-bandit");
		Fitness.creditCuts = !argFlag("--no-credit-cuts");
		if (dirtySpine) Fitness.nmaWorking = new Map();

		var opts:FitnessOpts = {
			popMemo: Fitness.nmaPopMemoEnabled,
			costBps: Fitness.nmaCostBps,
			initialCash: Fitness.nmaInitialCash,
			equityFloor: Fitness.nmaEquityFloor,
			attrBandit: Fitness.attrBandit,
			creditCuts: Fitness.creditCuts,
			periodsPerYear: Fitness.periodsPerYear()
		};
		var evalPool = NmaNodeEvalPool.create(threads, isBars, opts, attrTape);
		NmaNodeEvalPool.current = evalPool;

		var evalFn = function(g:StrategyGenome):Float {
			var fr = Fitness.evaluate(g, attrTape, "js", false);
			return Fitness.score(fr, 1);
		};
		// AttrPool.workers must stay 1 on Node: `EvolutionEngine` gates Phase-B `forkForSlot`
		// on `pool.workers > 1`, but JS has no `target.threaded` workers — arming workers=N
		// would silently switch Variation onto VARIATION_PARALLEL streams (champion drift vs
		// `--threads 1`) without any real parallelism. Population scoring still fans via
		// `NmaNodeEvalPool` above.
		var attrPool = new AttrPool(evalFn, 1);
		AttrPool.current = attrPool;

		Sys.println("=== MuseScript NMA Node/V8 bench ===");
		Sys.println('node target  pop=$pop gens=$gens seed=$seed warm=$warm threads=$threads');
		Sys.println('tape: $tapePath  full=${bars.length}  IS=${isBars.length}  attr=${attrTape.length}');
		Sys.println('preferNma=true  popMemo=${Fitness.nmaPopMemoEnabled}  dirtySpine=$dirtySpine  attrCross=$attrCross  cloneProb=$cloneProb');
		if (threads > 1)
			Sys.println('eval fan-out: worker_threads x$threads (scoreMs); resident genome ids; step child-prod serial on main (§33)');

		var engine = new EvolutionEngine(seed, pop, Std.int(Math.max(2, Std.int(pop / 16))), 3);
		var popG = engine.seedPopulation(depth);

		// Warm V8 / TurboFan before timed gens (each worker isolate warms independently).
		// Warm scoreAll also primes the resident genome store so timed gen-0 put ≈ 0.
		for (_ in 0...warm) {
			if (dirtySpine) Fitness.nmaWorking = new Map();
			evalPool.scoreAll(popG, true);
			Fitness.beginNmaPopMemo();
			for (g in popG) Fitness.evaluate(g, attrTape, "js", false);
		}

		var wallSum = 0.0;
		var scoreSum = 0.0;
		var stepSum = 0.0;
		var best = Fitness.NEG_INF;
		for (gen in 0...gens) {
			var t0 = haxe.Timer.stamp();
			if (dirtySpine) {
				if (Fitness.nmaWorking == null) Fitness.nmaWorking = new Map();
			}

			var fitness = evalPool.scoreAll(popG, true);
			var scoreMs = (haxe.Timer.stamp() - t0) * 1000;

			var genBest = fitness[0];
			for (f in fitness) if (f > genBest) genBest = f;
			if (genBest > best) best = genBest;

			var tStep0 = haxe.Timer.stamp();
			if (gen < gens - 1)
				popG = engine.step(popG, fitness, evalFn, attrCross, 2, 0.0, null, cloneProb);
			var stepMs = (haxe.Timer.stamp() - tStep0) * 1000;

			var wallMs = (haxe.Timer.stamp() - t0) * 1000;
			wallSum += wallMs;
			scoreSum += scoreMs;
			stepSum += stepMs;
			Sys.println('gen=${pad(gen)} best=${fmt(genBest, 4)} nmaOk=${Fitness.nmaOkCount}'
				+ ' nmaFall=${Fitness.nmaFallCount} popMemoHits=${Fitness.nmaPopMemoHits}'
				+ ' uniq=${evalPool.lastUnique}'
				+ ' | ${fmt(scoreMs, 0)}ms scoreMs'
				+ (threads > 1
					? ' (put=${fmt(evalPool.lastSerMs, 0)} n=${evalPool.lastPutCount} wait=${fmt(evalPool.lastWaitMs, 0)})'
					: '')
				+ ' | ${fmt(stepMs, 0)}ms stepMs'
				+ ' | ${fmt(wallMs, 0)}ms wallMs');
		}

		evalPool.stop();
		AttrPool.current = null;

		var meanWall = wallSum / gens;
		var meanScore = scoreSum / gens;
		var meanStep = stepSum / gens;
		Sys.println('SUMMARY meanWallMs=${fmt(meanWall, 1)} meanScoreMs=${fmt(meanScore, 1)}'
			+ ' meanStepMs=${fmt(meanStep, 1)}'
			+ ' gensPerSec=${fmt(1000.0 / meanWall, 2)} best=${fmt(best, 4)}'
			+ ' threads=$threads nmaOk=${Fitness.nmaOkCount} nmaFall=${Fitness.nmaFallCount}');
		Sys.println("NMA_NODE_BENCH_OK");
	}

	/**
	 * Multi-thread NMA score determinism gate: N genomes × M threads × K reps must match serial.
	 * Exit 0 + `NMA_DET_PROBE_OK` on success; throw (nonzero) on the first fitness-vector drift.
	 */
	static function runDetProbe():Void {
		var n = argInt("--pop", 64);
		if (n < 1) n = 1;
		var seed = argInt("--seed", 42);
		var reps = argInt("--reps", 3);
		if (reps < 1) reps = 1;
		var depth = argInt("--depth", 3);
		var attrBars = argInt("--attr-bars", 128);
		var threadMs = parseThreadList();
		if (threadMs.length == 0)
			throw "--det-probe needs at least one M>1 (pass --threads N or --threads-list 2,4)";

		var tapePath = argStr("--tape", "build/graal/smoke_spy_320.csv");
		var bars = loadBars(tapePath);
		if (bars.length < 60)
			throw 'tape too short: ${bars.length} bars from $tapePath';
		var isN = Std.int(bars.length * 0.7);
		if (isN < 60) isN = bars.length;
		var isBars = bars.slice(0, isN);
		var attrTape = attrBars <= 0 ? isBars : isBars.slice(0, Std.int(Math.min(attrBars, isBars.length)));

		armFitnessForProbe(attrTape);

		var opts:FitnessOpts = {
			popMemo: Fitness.nmaPopMemoEnabled,
			costBps: Fitness.nmaCostBps,
			initialCash: Fitness.nmaInitialCash,
			equityFloor: Fitness.nmaEquityFloor,
			attrBandit: Fitness.attrBandit,
			creditCuts: Fitness.creditCuts,
			periodsPerYear: Fitness.periodsPerYear()
		};

		var engine = new EvolutionEngine(seed, n, Std.int(Math.max(2, Std.int(n / 16))), 3);
		var genomes = engine.seedPopulation(depth);
		NmaNodeEvalPool.assertWorkerJsonSafe(genomes);

		Sys.println("=== MuseScript NMA multi-thread determinism probe ===");
		Sys.println('N=$n M=${threadMs.join(",")} K=$reps seed=$seed depth=$depth');
		Sys.println('tape: $tapePath  full=${bars.length}  IS=${isBars.length}  attr=${attrTape.length}');
		Sys.println('compare: fitness vector only (popMemoHits intentionally excluded)');

		// Serial baseline + K serial self-reps (catches single-thread nondeterminism first).
		var serialPool = NmaNodeEvalPool.create(1, isBars, opts, attrTape);
		NmaNodeEvalPool.current = serialPool;
		var baseline = serialPool.scoreAll(genomes, true);
		Sys.println('serial baseline: uniq=${serialPool.lastUnique} n=${baseline.length}');
		for (k in 0...reps) {
			var again = serialPool.scoreAll(genomes, true);
			var drift = fitnessDrift(baseline, again);
			if (drift != null)
				throw 'serial nondeterministic at rep=${k + 1}: $drift';
		}
		Sys.println('serial self-check: $reps/$reps identical');
		serialPool.stop();

		for (m in threadMs) {
			for (k in 0...reps) {
				var pool = NmaNodeEvalPool.create(m, isBars, opts, attrTape);
				NmaNodeEvalPool.current = pool;
				var t0 = haxe.Timer.stamp();
				var scores = pool.scoreAll(genomes, true);
				var ms = (haxe.Timer.stamp() - t0) * 1000;
				var drift = fitnessDrift(baseline, scores);
				pool.stop();
				if (drift != null)
					throw 'threads=$m rep=${k + 1} drifted vs serial: $drift';
				Sys.println('threads=$m rep=${k + 1}/$reps OK (${fmt(ms, 0)}ms scoreMs uniq=${pool.lastUnique})');
			}
		}

		Sys.println('SUMMARY N=$n M=[${threadMs.join(",")}] K=$reps — all fitness vectors identical to serial');
		Sys.println("NMA_DET_PROBE_OK");
	}

	static function armFitnessForProbe(attrTape:Array<Bar>):Void {
		Fitness.preferNma = true;
		Fitness.nmaPopMemoEnabled = !argFlag("--no-nma-pop-memo");
		Fitness.nmaDirtySpine = false; // probe refuses dirty-spine (unsound / auto-disabled at M>1)
		Fitness.nmaWorking = null;
		Fitness.nmaTape = attrTape;
		Fitness.nmaCostBps = 0;
		Fitness.nmaInitialCash = 100000;
		Fitness.nmaEquityFloor = 0;
		Fitness.attrBandit = !argFlag("--no-attr-bandit");
		Fitness.creditCuts = !argFlag("--no-credit-cuts");
		Fitness.beginNmaPopMemo();
	}

	/** `--threads-list 2,4,8` wins; else `--threads N` if N>1; else default `2,4`. */
	static function parseThreadList():Array<Int> {
		var raw = argStr("--threads-list", null);
		var out:Array<Int> = [];
		if (raw != null && raw.length > 0) {
			for (part in raw.split(",")) {
				var t = Std.parseInt(StringTools.trim(part));
				if (t != null && t > 1 && out.indexOf(t) < 0) out.push(t);
			}
			return out;
		}
		var threads = argInt("--threads", 0);
		if (threads > 1) return [threads];
		return [2, 4];
	}

	/** Null when identical (NaN≈NaN); else a short mismatch description. */
	static function fitnessDrift(a:Array<Float>, b:Array<Float>):Null<String> {
		if (a.length != b.length) return 'len ${a.length} vs ${b.length}';
		for (i in 0...a.length) {
			if (!sameScore(a[i], b[i]))
				return 'i=$i serial=${a[i]} got=${b[i]}';
		}
		return null;
	}

	static inline function sameScore(a:Float, b:Float):Bool {
		if (Math.isNaN(a) && Math.isNaN(b)) return true;
		return a == b;
	}

	static function loadBars(path:String):Array<Bar> {
		var candidates = [path, "corpus/tapes/spy_oos_2022_2026.csv", "data/real/spy.csv"];
		for (p in candidates) {
			if (sys.FileSystem.exists(p))
				return OhlcvCsv.parse(sys.io.File.getContent(p));
		}
		throw 'no tape found (tried $path and corpus fallbacks)';
	}

	static function argInt(name:String, def:Int):Int {
		var v = argStr(name, null);
		return v == null ? def : Std.parseInt(v);
	}

	static function argFloat(name:String, def:Float):Float {
		var v = argStr(name, null);
		return v == null ? def : Std.parseFloat(v);
	}

	static function argStr(name:String, def:Null<String>):Null<String> {
		var args = Sys.args();
		var i = 0;
		while (i < args.length - 1) {
			if (args[i] == name) return args[i + 1];
			i++;
		}
		return def;
	}

	static function argFlag(name:String):Bool {
		for (a in Sys.args()) if (a == name) return true;
		return false;
	}

	static function fmt(x:Float, n:Int):String {
		var m = Math.pow(10, n);
		var r = Math.ffloor(x * m + 0.5) / m;
		return Std.string(r);
	}

	static function pad(g:Int):String {
		var s = Std.string(g);
		return s.length >= 2 ? s : "0" + s;
	}
}
