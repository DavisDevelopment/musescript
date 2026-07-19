package musescript.evo.graal;

import musescript.evo.Canonical;
import musescript.evo.EvolutionEngine;
import musescript.evo.Expand;
import musescript.evo.StrategyGenome;
import musescript.evo.graal.Polyglot;
import musescript.harness.Bar;
import musescript.harness.BacktestResult;
import musescript.harness.OhlcvCsv;
import musescript.parse.MuseParser;
import musescript.compile.ModuleExpand;
import musescript.compile.TemplateExpand;
import musescript.compile.SeriesLowering;
import musescript.compile.StrategyWasmEmitter;
import musescript.evo.graal.GraalWasmHost;
import sys.thread.Thread;
import sys.thread.Deque;

typedef ModuleEntry = {
	var strings:Array<String>;
	var wasmPath:String;
}

typedef EvalJob = {
	var idx:Int;
	var wasmPath:String;
	var strings:Array<String>;
}

typedef EvalResult = {
	var idx:Int;
	var trades:Int;
	var sharpe:Float;
	var finalEquity:Float;
	var ms:Float;
}

typedef GenStat = {
	var gen:Int;
	var newModules:Int;
	var unsupported:Int;
	var emitMs:Float;
	var asmMs:Float;
	var loadMs:Float;
	var evalMs:Float;
	var evals:Int;
	var msPerEval:Float;
	var cpuMsPerEval:Float;
	var barsPerSec:Float;
	var best:Float;
	var mean:Float;
}

/**
 * GraalWasm evolutionary benchmark with periodic speed captures.
 *
 * Per generation: genome -> MuseScript -> WAT (in-process Haxe emitter) -> WASM
 * (batched wasmtime assembly) -> GraalWasm preloaded backtest on the real SPY tape.
 * Compile artifacts are cached by structural key; every genome is re-evaluated each
 * generation so eval throughput honestly reflects Truffle warmup.
 *
 * Usage: EvoBench [--pop N] [--gens N] [--seed N] [--depth N] [--warm N] [--threads N]
 */
class EvoBench {
	static var watDir = "build/graal/evo";
	static var engineOpts:Null<Map<String, String>> = null;

	static function main() {
		var pop = argInt("--pop", 32);
		var gens = argInt("--gens", 10);
		var seed = argInt("--seed", 42);
		var depth = argInt("--depth", 3);
		var warm = argInt("--warm", 30);
		var threads = argInt("--threads", Std.int(Math.max(1,
			java.lang.Runtime.getRuntime().availableProcessors() / 2)));

		Sys.println("=== MuseScript evo benchmark on GraalWasm ===");
		Sys.println('jvm:  ${java.lang.System.getProperty("java.vm.name")} ${java.lang.System.getProperty("java.vm.version")}');
		Sys.println('pop=$pop gens=$gens seed=$seed depth=$depth warm=$warm threads=$threads');

		var bars = loadBars();
		Sys.println('tape: ${bars.length} bars (SPY daily)');
		if (!sys.FileSystem.exists(watDir)) sys.FileSystem.createDirectory(watDir);

		// Second-tier (deopt-prone) compilation of the hot per-bar loops has shown
		// pathological plans for this workload; Tier 1 alone is stable and ~6x faster
		// steady-state, so pin it unless --tier2 is passed.
		if (argStr("--tier2", null) == null)
			engineOpts = ["engine.LastTierCompilationThreshold" => "2000000000"];

		var host = new GraalWasmHost(null, engineOpts);
		sanityParity(host, bars);

		var m0Cycles = argInt("--m0", 0);
		var modKey = argStr("--mod", null);
		if (m0Cycles > 0) {
			var strings:Array<String> = modKey != null
				? []
				: haxe.Json.parse(sys.io.File.getContent("build/graal/on_bar.strings.json"));
			var module = host.loadModuleFile(modKey != null
				? '$watDir/$modKey.wasm'
				: "build/graal/on_bar.wasm");
			var params:Map<String, Float> = modKey != null ? new Map() : ["fast" => 10.0, "slow" => 30.0];
			var inst = host.instantiate(module, strings);
			for (c in 0...m0Cycles) {
				var t0 = haxe.Timer.stamp();
				inst.run(bars, params);
				var ms = (haxe.Timer.stamp() - t0) * 1000;
				Sys.println('m0 cycle ${pad(Std.string(c), 3)}: ${fmt(ms, 2)} ms (${fmt(bars.length / ms, 0)}k bars/s)');
			}
			host.close();
			return;
		}

		var engine = new EvolutionEngine(seed, pop, Std.int(Math.max(2, pop / 16)), 3);
		var popG = engine.seedPopulation(depth);

		var moduleCache = new Map<String, ModuleEntry>();
		var stringsPending = new Map<String, Array<String>>();
		var unsupportedKeys = new Map<String, Bool>();
		var stats:Array<GenStat> = [];
		var best = -1e99;
		var bestGenome:StrategyGenome = null;
		var totalT0 = haxe.Timer.stamp();

		// Persistent worker pool: per-thread Context on the shared Engine, warm
		// StrategyInstance caches carried across generations.
		var jobQueue = new Deque<EvalJob>();
		var resultQueue = new Deque<EvalResult>();
		var ackQueue = new Deque<Int>();
		for (_ in 0...threads) {
			var sharedEngine = host.engine;
			Thread.create(function() evalWorker(sharedEngine, bars, jobQueue, resultQueue, ackQueue));
		}

		for (gen in 0...gens) {
			// --- compile phase: emit WAT for cache misses, batch-assemble, load ---
			var tEmit0 = haxe.Timer.stamp();
			var pendingKeys:Array<String> = [];
			var unsupported = 0;
			for (g in popG) {
				var key = Canonical.structuralKey(g);
				if (moduleCache.exists(key) || unsupportedKeys.exists(key) || stringsPending.exists(key))
					continue;
				var emitted = emitGenome(g);
				if (emitted == null) {
					unsupportedKeys.set(key, true);
					unsupported++;
					continue;
				}
				sys.io.File.saveContent('$watDir/$key.wat', emitted.wat);
				stringsPending.set(key, emitted.strings);
				pendingKeys.push(key);
			}
			var emitMs = (haxe.Timer.stamp() - tEmit0) * 1000;

			var tAsm0 = haxe.Timer.stamp();
			if (pendingKeys.length > 0) {
				var py = Sys.systemName() == "Windows" ? ".venv/Scripts/python.exe" : ".venv/bin/python";
				var code = Sys.command(py, ["tools/wat2wasm_batch.py", watDir]);
				if (code != 0) throw "wat2wasm batch failed";
			}
			var asmMs = (haxe.Timer.stamp() - tAsm0) * 1000;

			var tLoad0 = haxe.Timer.stamp();
			for (key in pendingKeys) {
				moduleCache.set(key, {
					strings: stringsPending.get(key),
					wasmPath: '$watDir/$key.wasm'
				});
				stringsPending.remove(key);
			}
			var loadMs = (haxe.Timer.stamp() - tLoad0) * 1000;

			// --- eval phase: every genome, every generation (honest throughput) ---
			var fitness:Array<Float> = [for (_ in popG) -999.0001];
			var evals = 0;
			var tEval0 = haxe.Timer.stamp();
			for (i in 0...popG.length) {
				var key = Canonical.structuralKey(popG[i]);
				if (unsupportedKeys.exists(key)) continue;
				var entry = moduleCache.get(key);
				jobQueue.add({ idx: i, wasmPath: entry.wasmPath, strings: entry.strings });
				evals++;
			}
			var sumEvalMs = 0.0;
			for (_ in 0...evals) {
				var r = resultQueue.pop(true);
				var f = r.trades >= 1 ? r.sharpe : -100.0;
				fitness[r.idx] = f - Canonical.nodeCount(popG[r.idx]) * 0.0001;
				sumEvalMs += r.ms;
			}
			var evalMs = (haxe.Timer.stamp() - tEval0) * 1000;

			var genBest = -1e99;
			var mean = 0.0;
			var bestIdx = 0;
			for (i in 0...fitness.length) {
				mean += fitness[i];
				if (fitness[i] > genBest) { genBest = fitness[i]; bestIdx = i; }
			}
			mean /= fitness.length;
			if (genBest > best) { best = genBest; bestGenome = popG[bestIdx]; }

			var msPerEval = evals > 0 ? evalMs / evals : 0;
			var cpuMsPerEval = evals > 0 ? sumEvalMs / evals : 0;
			var barsPerSec = msPerEval > 0 ? bars.length / (msPerEval / 1000.0) : 0;
			stats.push({
				gen: gen, newModules: pendingKeys.length, unsupported: unsupported,
				emitMs: emitMs, asmMs: asmMs, loadMs: loadMs,
				evalMs: evalMs, evals: evals, msPerEval: msPerEval, cpuMsPerEval: cpuMsPerEval,
				barsPerSec: barsPerSec, best: genBest, mean: mean
			});
			Sys.println('gen ${pad(Std.string(gen), 3)} | new ${pad(Std.string(pendingKeys.length), 3)}'
				+ ' | emit ${fmt(emitMs, 0)}ms asm ${fmt(asmMs, 0)}ms'
				+ ' | eval ${fmt(evalMs, 0)}ms wall (${fmt(msPerEval, 2)} ms/eval, cpu ${fmt(cpuMsPerEval, 2)} ms, ${fmt(barsPerSec / 1000, 0)}k bars/s)'
				+ ' | best ${fmt(genBest, 4)} mean ${fmt(mean, 4)}');

			if (gen < gens - 1) popG = engine.step(popG, fitness);
		}
		var totalS = haxe.Timer.stamp() - totalT0;

		// Shut the worker pool down before the isolated warmup measurement,
		// and wait for the contexts to actually close.
		for (_ in 0...threads) jobQueue.add({ idx: -2, wasmPath: "", strings: [] });
		for (_ in 0...threads) ackQueue.pop(true);

		// --- determinism guard on the champion ---
		var champKey = Canonical.structuralKey(bestGenome);
		var champEntry = moduleCache.get(champKey);
		var champInst = host.instantiate(host.loadModuleFile(champEntry.wasmPath), champEntry.strings);
		var a = champInst.run(bars, new Map());
		var b = champInst.run(bars, new Map());
		if (a.trades != b.trades || Math.abs(a.finalEquity - b.finalEquity) > 1e-9)
			throw "champion non-deterministic";
		Sys.println('\nchampion: trades=${a.trades} equity=${fmt(a.finalEquity, 2)} sharpe=${fmt(a.sharpe, 4)} key=$champKey');

		// --- cold-engine warmup curve: fresh Engine/Context, repeated champion evals ---
		Sys.println('\n--- champion warmup curve (fresh Engine, $warm cycles) ---');
		var host2 = new GraalWasmHost(null, engineOpts);
		var inst2 = host2.instantiate(host2.loadModuleFile(champEntry.wasmPath), champEntry.strings);
		var cycles:Array<Float> = [];
		for (c in 0...warm) {
			var t0 = haxe.Timer.stamp();
			var r = inst2.run(bars, new Map());
			var ms = (haxe.Timer.stamp() - t0) * 1000;
			cycles.push(ms);
			if (r.trades != a.trades) throw "warmup eval diverged";
			if (c < 5 || c % 5 == 4)
				Sys.println('cycle ${pad(Std.string(c), 3)}: ${fmt(ms, 2)} ms (${fmt(bars.length / ms, 0)}k bars/s)');
		}
		host2.close();
		var first = cycles[0];
		var lastAvg = avg(cycles.slice(cycles.length - 5));
		Sys.println('warmup: first=${fmt(first, 2)}ms  last5avg=${fmt(lastAvg, 2)}ms  speedup=${fmt(first / lastAvg, 1)}x');

		// --- fixed-population sweeps: same workload each cycle on a fresh Engine,
		// so the curve isolates Truffle warmup instead of evolution drift ---
		var sweepsN = argInt("--sweeps", 8);
		var uniq = new Map<String, ModuleEntry>();
		for (g in popG) {
			var k = Canonical.structuralKey(g);
			if (moduleCache.exists(k)) uniq.set(k, moduleCache.get(k));
		}
		var uniqN = 0;
		for (_ in uniq.keys()) uniqN++;
		Sys.println('\n--- fixed final population sweeps (fresh Engine, $uniqN modules x $sweepsN sweeps) ---');
		var host3 = new GraalWasmHost(null, engineOpts);
		var sweepInstances:Array<StrategyInstance> = [];
		for (k in uniq.keys()) {
			var e = uniq.get(k);
			sweepInstances.push(host3.instantiate(host3.loadModuleFile(e.wasmPath), e.strings));
		}
		var sweeps:Array<Float> = [];
		for (s in 0...sweepsN) {
			var t0 = haxe.Timer.stamp();
			for (inst in sweepInstances) inst.run(bars, new Map());
			var ms = (haxe.Timer.stamp() - t0) * 1000;
			sweeps.push(ms);
			Sys.println('sweep ${pad(Std.string(s), 2)}: ${fmt(ms, 0)}ms total, ${fmt(ms / uniqN, 2)} ms/eval, ${fmt(uniqN * bars.length / ms, 0)}k bars/s');
		}
		host3.close();
		if (sweeps.length > 1)
			Sys.println('sweep warmup: first=${fmt(sweeps[0], 0)}ms  last=${fmt(sweeps[sweeps.length - 1], 0)}ms  speedup=${fmt(sweeps[0] / sweeps[sweeps.length - 1], 2)}x');

		var firstEval = stats[0].msPerEval;
		var lastEval = stats[stats.length - 1].msPerEval;
		Sys.println('evolution eval speed: gen0=${fmt(firstEval, 2)} ms/eval -> gen${gens - 1}=${fmt(lastEval, 2)} ms/eval (${fmt(firstEval / lastEval, 1)}x)');
		Sys.println('total wall: ${fmt(totalS, 1)}s  modules compiled: ${count(moduleCache)}');

		saveReport(stats, cycles, sweeps, bars.length, pop, gens, seed, totalS);
		host.close();
		Sys.println("\nEVO_BENCH_OK");
	}

	/** Worker: own Context on the shared Engine, warm instance cache across generations. */
	static function evalWorker(
		engine:Engine, bars:Array<musescript.harness.Bar>,
		jobs:Deque<EvalJob>, results:Deque<EvalResult>, acks:Deque<Int>
	):Void {
		var host = new GraalWasmHost(engine);
		var instances = new Map<String, StrategyInstance>();
		while (true) {
			var job = jobs.pop(true);
			if (job.idx == -2) {
				host.close();
				acks.add(1);
				return;
			}
			var inst = instances.get(job.wasmPath);
			if (inst == null) {
				inst = host.instantiate(host.loadModuleFile(job.wasmPath), job.strings);
				instances.set(job.wasmPath, inst);
			}
			var t0 = haxe.Timer.stamp();
			var r = inst.run(bars, new Map());
			var ms = (haxe.Timer.stamp() - t0) * 1000;
			results.add({ idx: job.idx, trades: r.trades, sharpe: r.sharpe, finalEquity: r.finalEquity, ms: ms });
		}
	}

	/** Mirror MuseCompiler.compileEx front-half, then emit WAT directly. */
	static function emitGenome(g:StrategyGenome):Null<{wat:String, strings:Array<String>}> {
		try {
			var source = Expand.expand(g);
			var prog = new MuseParser().parse(source, "<evo>");
			// Order: see MuseCompiler.compileEx's comment (TemplateExpand
			// before ModuleExpand — the reverse can't see `use` inside templates).
			prog = TemplateExpand.expand(prog);
			prog = ModuleExpand.expand(prog);
			prog = SeriesLowering.lower(prog);
			return new StrategyWasmEmitter().emitOnBar(prog);
		} catch (e:Dynamic) {
			return null;
		}
	}

	/** Verify the Haxe->Graal host against the M0 ground truth before benchmarking. */
	static function sanityParity(host:GraalWasmHost, bars:Array<Bar>):Void {
		var wasmPath = "build/graal/on_bar.wasm";
		if (!sys.FileSystem.exists(wasmPath)) {
			Sys.println("sanity: build/graal/on_bar.wasm missing, skipping parity check");
			return;
		}
		var strings:Array<String> = haxe.Json.parse(sys.io.File.getContent("build/graal/on_bar.strings.json"));
		var expected:Dynamic = haxe.Json.parse(sys.io.File.getContent("build/graal/expected.json"));
		var module = host.loadModuleFile(wasmPath);
		var params = ["fast" => 10.0, "slow" => 30.0];
		var r = host.runPreloaded(module, strings, bars, params);
		var expTrades = Std.parseInt(Std.string(expected.trades));
		var expEquity = Std.parseFloat(Std.string(expected.finalEquity));
		if (r.trades != expTrades || Math.abs(r.finalEquity - expEquity) > 1e-6)
			throw 'sanity parity FAILED: trades=${r.trades}/$expTrades equity=${r.finalEquity}/$expEquity';
		Sys.println('sanity: M0 parity OK (trades=${r.trades} equity=${r.finalEquity})');
	}

	static function saveReport(
		stats:Array<GenStat>, cycles:Array<Float>, sweeps:Array<Float>, barCount:Int,
		pop:Int, gens:Int, seed:Int, totalS:Float
	):Void {
		// Avoid nested Haxe anon objects on JVM (missing AnonN class stubs).
		var gensJson:Array<Dynamic> = [];
		for (s in stats) {
			var g:Dynamic = {};
			Reflect.setField(g, "gen", s.gen);
			Reflect.setField(g, "newModules", s.newModules);
			Reflect.setField(g, "unsupported", s.unsupported);
			Reflect.setField(g, "emitMs", s.emitMs);
			Reflect.setField(g, "asmMs", s.asmMs);
			Reflect.setField(g, "loadMs", s.loadMs);
			Reflect.setField(g, "evalMs", s.evalMs);
			Reflect.setField(g, "evals", s.evals);
			Reflect.setField(g, "msPerEval", s.msPerEval);
			Reflect.setField(g, "cpuMsPerEval", s.cpuMsPerEval);
			Reflect.setField(g, "barsPerSec", s.barsPerSec);
			Reflect.setField(g, "best", s.best);
			Reflect.setField(g, "mean", s.mean);
			gensJson.push(g);
		}
		var cfg:Dynamic = {};
		Reflect.setField(cfg, "pop", pop);
		Reflect.setField(cfg, "gens", gens);
		Reflect.setField(cfg, "seed", seed);
		Reflect.setField(cfg, "bars", barCount);
		var report:Dynamic = {};
		Reflect.setField(report, "schema", "musescript.evo-bench/1");
		Reflect.setField(report, "jvm",
			java.lang.System.getProperty("java.vm.name") + " " + java.lang.System.getProperty("java.vm.version"));
		Reflect.setField(report, "config", cfg);
		Reflect.setField(report, "generations", gensJson);
		Reflect.setField(report, "championWarmupMs", cycles);
		Reflect.setField(report, "fixedPopulationSweepMs", sweeps);
		Reflect.setField(report, "totalWallSec", totalS);
		sys.io.File.saveContent("build/graal/evo_bench_report.json", haxe.Json.stringify(report, null, "  "));
		Sys.println("report: build/graal/evo_bench_report.json");
	}

	static function loadBars():Array<Bar> {
		for (path in ["data/real/spy.csv", "muse-script/data/real/spy.csv", "../muse-script/data/real/spy.csv"])
			if (sys.FileSystem.exists(path))
				return OhlcvCsv.parse(sys.io.File.getContent(path));
		throw "spy.csv not found — run from muse-lab/muse-script";
	}

	static function argStr(name:String, dflt:Null<String>):Null<String> {
		var args = Sys.args();
		for (i in 0...args.length - 1)
			if (args[i] == name) return args[i + 1];
		return dflt;
	}

	static function argInt(name:String, dflt:Int):Int {
		var args = Sys.args();
		for (i in 0...args.length - 1)
			if (args[i] == name) {
				var v = Std.parseInt(args[i + 1]);
				if (v != null) return v;
			}
		return dflt;
	}

	static function fmt(x:Float, digits:Int):String {
		var m = Math.pow(10, digits);
		var r = Math.ffloor(x * m + 0.5) / m;
		var s = Std.string(r);
		if (digits == 0 && StringTools.endsWith(s, ".0")) s = s.substr(0, s.length - 2);
		return s;
	}

	static function pad(s:String, n:Int):String {
		while (s.length < n) s = " " + s;
		return s;
	}

	static function avg(a:Array<Float>):Float {
		var s = 0.0;
		for (x in a) s += x;
		return a.length > 0 ? s / a.length : 0;
	}

	static function count(m:Map<String, ModuleEntry>):Int {
		var n = 0;
		for (_ in m.keys()) n++;
		return n;
	}
}
