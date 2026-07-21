package musescript.evo.graal;

import musescript.evo.Canonical;
import musescript.evo.CorpusSeed;
import musescript.evo.EvolutionEngine;
import musescript.evo.Expand;
import musescript.evo.Fitness;
import musescript.evo.RegistryPalette;
import musescript.evo.StrategyGenome;
import musescript.evo.graal.Polyglot;
import musescript.evo.graal.GraalWasmHost;
import musescript.harness.Bar;
import musescript.harness.OhlcvCsv;
import musescript.parse.MuseParser;
import musescript.compile.ModuleExpand;
import musescript.compile.TemplateExpand;
import musescript.compile.SeriesLowering;
import musescript.compile.StrategyWasmEmitter;
import sys.thread.Thread;
import sys.thread.Deque;

typedef ModuleEntry = {var strings:Array<String>; var wasmPath:String;}
typedef EvalJob = {var idx:Int; var wasmPath:String; var strings:Array<String>;}
typedef EvalResult = {var idx:Int; var trades:Int; var sharpe:Float; var finalEquity:Float;}

/**
 * Evolution run seeded with the ENTIRE reverse-compilable strategy corpus (the tournament
 * agents' hand-written strategies + one genome per compatible `ta` indicator, see
 * CorpusSeed.hx), fitness-evaluated on the real GraalWasm host (same compile-and-run pipeline
 * as EvoBench.hx, reused directly -- WAT emission via StrategyWasmEmitter, batched wat2wasm
 * assembly, a persistent multi-threaded GraalWasmHost worker pool with warm per-thread
 * instance caches).
 *
 * Generation 0 evaluates the FULL seeded population (however large the corpus makes it) so
 * every seed genuinely gets a fitness-ranked shot at survival; `--pop` caps how large
 * subsequent generations regrow to (elites + tournament-selected offspring), matching
 * EvolutionEngine's own step() semantics -- the corpus is a one-time diversity injection into
 * gen 0, not a population size the run keeps paying to re-evaluate every generation.
 *
 * Usage: CorpusEvoRun [--pop N] [--gens N] [--seed N] [--threads N] [--corpus DIR]
 */
class CorpusEvoRun {
	static var watDir = "build/graal/evo-corpus";

	static function main() {
		var pop = argInt("--pop", 64);
		var gens = argInt("--gens", 12);
		var seed = argInt("--seed", 42);
		var threads = argInt("--threads", Std.int(Math.max(1,
			java.lang.Runtime.getRuntime().availableProcessors() / 2)));
		var corpusDir = argStr("--corpus", "examples/strategy-tournament");
		var tapePath = argStr("--tape", null);
		var oosFrac = argFloat("--oos-frac", 0.25);
		var embargo = argInt("--embargo", 21);

		Sys.println("=== MuseScript CORPUS-SEEDED evolution on GraalWasm ===");
		Sys.println('jvm:  ${java.lang.System.getProperty("java.vm.name")} ${java.lang.System.getProperty("java.vm.version")}');

		var allBars = loadBars(tapePath);
		// Walk-forward IS/OOS split: evolution only ever sees `isBars` -- fitness, selection,
		// and every generation's ranking are computed exclusively on the in-sample segment.
		// `oosBars` (the last `oosFrac` of the tape, with an `embargo`-bar gap dropped between
		// them so no indicator's warmup window on the OOS side can reach back across the split)
		// is held out completely until the very end, where it's used ONLY to re-score the final
		// population -- same discipline as the project's own walk-forward validation elsewhere
		// (README/aril page): past and future kept strictly apart, re-scored honestly, not
		// re-tuned to pass.
		var oosLen = Std.int(allBars.length * oosFrac);
		var isLen = allBars.length - oosLen - embargo;
		if (isLen < 200) throw 'tape too short for a ${oosFrac}-fraction OOS split with ${embargo}-bar embargo (${allBars.length} bars total)';
		var bars = allBars.slice(0, isLen);
		var oosBars = allBars.slice(isLen + embargo, allBars.length);
		Sys.println('tape: ${allBars.length} bars total -> IS ${bars.length} / embargo $embargo / OOS ${oosBars.length}');
		if (!sys.FileSystem.exists(watDir)) sys.FileSystem.createDirectory(watDir);

		// --- build the seed population --------------------------------------------------
		var allowed = new Map<String, Bool>();
		for (n in RegistryPalette.compatibleNames()) allowed.set(n, true);

		var tournament = CorpusSeed.seedFromDirectory(corpusDir, allowed);
		Sys.println('tournament corpus: ${tournament.total} files, ${tournament.genomes.length} translated to genomes, ${tournament.skipped.length} skipped (outside the closed GP grammar -- onPosition exits, multi-output field access, etc.)');

		var indicatorNames = [for (n in allowed.keys()) n];
		var indicatorSeeds = CorpusSeed.seedFromIndicators(indicatorNames);
		Sys.println('indicator seeds: ${indicatorNames.length} compatible indicators x 3 windows = ${indicatorSeeds.length} genomes');

		var seedPop = tournament.genomes.concat(indicatorSeeds);
		Sys.println('seeded generation 0: ${seedPop.length} real genomes (${tournament.genomes.length} corpus-derived + ${indicatorSeeds.length} indicator-derived)');

		var engineOpts = ["engine.LastTierCompilationThreshold" => "2000000000"];
		var host = new GraalWasmHost(null, engineOpts);

		var engine = new EvolutionEngine(seed, pop, Std.int(Math.max(2, pop / 16)), 3);
		var popG = seedPop;
		var lastFitness:Array<Float> = null; // final generation's IS fitness, for the OOS re-score below

		var moduleCache = new Map<String, ModuleEntry>();
		var unsupportedKeys = new Map<String, Bool>();
		var best = Fitness.NEG_INF;
		var bestGenome:StrategyGenome = null;
		var totalT0 = haxe.Timer.stamp();

		var jobQueue = new Deque<EvalJob>();
		var resultQueue = new Deque<EvalResult>();
		var ackQueue = new Deque<Int>();
		for (_ in 0...threads) {
			var sharedEngine = host.engine;
			Thread.create(function() evalWorker(sharedEngine, bars, jobQueue, resultQueue, ackQueue));
		}

		for (gen in 0...gens) {
			var tGen0 = haxe.Timer.stamp();
			var pendingKeys:Array<String> = [];
			var unsupported = 0;
			// Genomes whose expanded source can't be natively WASM-compiled at all (emitGenome
			// null) OR needs the `host_eval` interp-escape hatch (StrategyWasmEmitter.hx's
			// hybrid fallback for statements it can't natively lower -- e.g. any of the 400+
			// `ta` registry indicators beyond the dozen StrategyWasmEmitter has native opcodes
			// for) aren't representable on THIS host: GraalWasmHost has no interp callback wired
			// for host_eval. Rather than drop them from fitness evaluation entirely (which would
			// silently bias selection against every genome using a newer Wickra-ported
			// indicator), they fall back to the ordinary JS/interp Fitness path -- still a real,
			// correct evaluation, just not GraalWasm-accelerated.
			var jsFallback:Array<Int> = [];
			var stringsPending = new Map<String, Array<String>>();
			for (i in 0...popG.length) {
				var g = popG[i];
				var key = Canonical.structuralKey(g);
				if (moduleCache.exists(key)) continue;
				if (unsupportedKeys.exists(key)) { jsFallback.push(i); continue; }
				if (stringsPending.exists(key)) continue;
				var emitted = emitGenome(g);
				if (emitted == null || StringTools.contains(emitted.wat, "call $host_eval")) {
					unsupportedKeys.set(key, true);
					unsupported++;
					jsFallback.push(i);
					continue;
				}
				sys.io.File.saveContent('$watDir/$key.wat', emitted.wat);
				stringsPending.set(key, emitted.strings);
				pendingKeys.push(key);
			}
			if (pendingKeys.length > 0) {
				var py = Sys.systemName() == "Windows" ? ".venv/Scripts/python.exe" : ".venv/bin/python";
				var code = Sys.command(py, ["tools/wat2wasm_batch.py", watDir]);
				if (code != 0) throw "wat2wasm batch failed";
			}
			for (key in pendingKeys) moduleCache.set(key, {strings: stringsPending.get(key), wasmPath: '$watDir/$key.wasm'});
			// A genome already known unsupported (from a PRIOR generation) needs re-adding to
			// jsFallback here too, since the loop above only pushes it once per structural key
			// via unsupportedKeys -- but every INDEX sharing that key across this generation's
			// population still needs its own fitness entry.
			for (i in 0...popG.length) {
				var key = Canonical.structuralKey(popG[i]);
				if (unsupportedKeys.exists(key) && jsFallback.indexOf(i) < 0) jsFallback.push(i);
			}

			var fitness:Array<Float> = [for (_ in popG) Fitness.NEG_INF];
			var evals = 0;
			for (i in 0...popG.length) {
				var key = Canonical.structuralKey(popG[i]);
				if (unsupportedKeys.exists(key)) continue;
				var entry = moduleCache.get(key);
				jobQueue.add({idx: i, wasmPath: entry.wasmPath, strings: entry.strings});
				evals++;
			}
			for (_ in 0...evals) {
				var r = resultQueue.pop(true);
				fitness[r.idx] = r.trades >= 1 && !Math.isNaN(r.sharpe) ? r.sharpe : Fitness.NEG_INF;
			}
			for (i in jsFallback) {
				var fr = Fitness.evaluate(popG[i], bars, "js", false);
				fitness[i] = Fitness.score(fr, 1);
			}

			var genBest = Fitness.NEG_INF;
			var bestIdx = 0;
			var validN = 0;
			var sum = 0.0;
			for (i in 0...fitness.length) {
				if (fitness[i] == Fitness.NEG_INF) continue;
				validN++;
				sum += fitness[i];
				if (fitness[i] > genBest) { genBest = fitness[i]; bestIdx = i; }
			}
			if (genBest > best) { best = genBest; bestGenome = popG[bestIdx]; }
			var mean = validN > 0 ? sum / validN : 0.0;
			var genMs = (haxe.Timer.stamp() - tGen0) * 1000;
			Sys.println('gen ${pad(Std.string(gen), 2)} | popSize=${popG.length} new=${pendingKeys.length} unsupported=$unsupported valid=$validN'
				+ ' | best=${fmt(genBest, 4)} mean=${fmt(mean, 4)} champion="${bestGenome != null ? bestGenome.name : "?"}"'
				+ ' | ${fmt(genMs, 0)}ms');

			lastFitness = fitness;
			if (gen < gens - 1) popG = engine.step(popG, fitness);
		}
		var totalS = haxe.Timer.stamp() - totalT0;

		for (_ in 0...threads) jobQueue.add({idx: -2, wasmPath: "", strings: []});
		for (_ in 0...threads) ackQueue.pop(true);

		Sys.println('\n=== CHAMPION (fitness=${fmt(best, 4)}, lineage=${bestGenome != null ? bestGenome.lineage.join(" <- ") : "?"}) ===');
		if (bestGenome != null) {
			var champKey = Canonical.structuralKey(bestGenome);
			if (moduleCache.exists(champKey)) {
				var champEntry = moduleCache.get(champKey);
				var champInst = host.instantiate(host.loadModuleFile(champEntry.wasmPath), champEntry.strings);
				var a = champInst.run(bars, new Map());
				var b = champInst.run(bars, new Map());
				if (a.trades != b.trades || Math.abs(a.finalEquity - b.finalEquity) > 1e-9)
					throw "champion non-deterministic";
				Sys.println('backend=wasm trades=${a.trades} equity=${fmt(a.finalEquity, 2)} sharpe=${fmt(a.sharpe, 4)} nodeCount=${Canonical.nodeCount(bestGenome)}');
			} else {
				// Champion needed the JS/interp fallback (see jsFallback above) -- no WASM
				// module exists for it, so verify determinism the same way, on that backend.
				var a = Fitness.evaluate(bestGenome, bars, "js", false);
				var b = Fitness.evaluate(bestGenome, bars, "js", false);
				if (a.trades != b.trades || Math.abs(a.finalEquity - b.finalEquity) > 1e-9)
					throw "champion non-deterministic";
				Sys.println('backend=js(fallback) trades=${a.trades} equity=${fmt(a.finalEquity, 2)} sharpe=${fmt(a.sharpe, 4)} nodeCount=${Canonical.nodeCount(bestGenome)}');
			}
			Sys.println(Expand.expand(bestGenome));
		}
		Sys.println('total wall: ${fmt(totalS, 1)}s  modules compiled: ${count(moduleCache)}');

		// --- walk-forward OOS re-score: the top-K genomes by IS fitness, re-scored on the
		// held-out tail the evolution loop never saw. "Held" = still trading with a positive
		// Sharpe out of sample; "did NOT hold" is reported just as plainly, matching the
		// project's own walk-forward evidence discipline -- not everything IS-strong survives
		// contact with data it was never fit on, and that's the whole point of checking.
		Sys.println('\n=== OOS RE-SCORE (top 10 by IS fitness, held-out ${oosBars.length}-bar tail) ===');
		var ranked = [for (i in 0...popG.length) {g: popG[i], isFit: lastFitness[i]}];
		ranked.sort((a, b) -> a.isFit != b.isFit ? (a.isFit < b.isFit ? 1 : -1) : 0);
		var seen = new Map<String, Bool>();
		var shown = 0;
		var held = 0, checked = 0;
		for (r in ranked) {
			if (shown >= 10) break;
			if (r.isFit == Fitness.NEG_INF) break;
			var key = Canonical.structuralKey(r.g);
			if (seen.exists(key)) continue; // elitism duplicates the same genome across slots
			seen.set(key, true);
			shown++;
			var oos = Fitness.evaluate(r.g, oosBars, "js", false);
			var oosScore = Fitness.score(oos, 1);
			checked++;
			var holdMark = oosScore > 0 ? "HELD" : "did not hold";
			if (oosScore > 0) held++;
			Sys.println('  ${pad(Std.string(shown), 2)}. IS=${fmt(r.isFit, 4)}  OOS=${oos.ok ? fmt(oosScore, 4) : "n/a"} (trades=${oos.trades})  [$holdMark]  ${r.g.name}');
		}
		Sys.println('OOS summary: ${held}/${checked} of the top IS performers held a positive Sharpe out of sample.');

		host.close();
		Sys.println("\nCORPUS_EVO_OK");
	}

	static function evalWorker(engine:Engine, bars:Array<Bar>, jobs:Deque<EvalJob>, results:Deque<EvalResult>, acks:Deque<Int>):Void {
		var host = new GraalWasmHost(engine);
		var instances = new Map<String, StrategyInstance>();
		while (true) {
			var job = jobs.pop(true);
			if (job.idx == -2) { host.close(); acks.add(1); return; }
			var inst = instances.get(job.wasmPath);
			if (inst == null) {
				inst = host.instantiate(host.loadModuleFile(job.wasmPath), job.strings);
				instances.set(job.wasmPath, inst);
			}
			var r = inst.run(bars, new Map());
			results.add({idx: job.idx, trades: r.trades, sharpe: r.sharpe, finalEquity: r.finalEquity});
		}
	}

	static function emitGenome(g:StrategyGenome):Null<{wat:String, strings:Array<String>}> {
		try {
			var source = Expand.expand(g);
			var prog = new MuseParser().parse(source, "<evo>");
			prog = TemplateExpand.expand(prog);
			prog = ModuleExpand.expand(prog);
			prog = SeriesLowering.lower(prog);
			return new StrategyWasmEmitter().emitOnBar(prog);
		} catch (e:Dynamic) {
			return null;
		}
	}

	static function loadBars(explicitPath:Null<String>):Array<Bar> {
		var candidates = explicitPath != null
			? [explicitPath]
			: ["data/real/spy.csv", "muse-script/data/real/spy.csv", "../muse-script/data/real/spy.csv"];
		for (path in candidates)
			if (sys.FileSystem.exists(path)) return OhlcvCsv.parse(sys.io.File.getContent(path));
		throw '${explicitPath != null ? explicitPath : "spy.csv"} not found -- run from muse-lab/muse-script';
	}

	static function argStr(name:String, dflt:Null<String>):Null<String> {
		var args = Sys.args();
		for (i in 0...args.length - 1) if (args[i] == name) return args[i + 1];
		return dflt;
	}

	static function argFloat(name:String, dflt:Float):Float {
		var args = Sys.args();
		for (i in 0...args.length - 1) {
			if (args[i] == name) {
				var v = Std.parseFloat(args[i + 1]);
				if (!Math.isNaN(v)) return v;
			}
		}
		return dflt;
	}

	static function argInt(name:String, dflt:Int):Int {
		var args = Sys.args();
		for (i in 0...args.length - 1) {
			if (args[i] == name) {
				var v = Std.parseInt(args[i + 1]);
				if (v != null) return v;
			}
		}
		return dflt;
	}

	static function fmt(x:Float, digits:Int):String {
		var m = Math.pow(10, digits);
		var r = Math.ffloor(x * m + 0.5) / m;
		return Std.string(r);
	}

	static function pad(s:String, n:Int):String {
		while (s.length < n) s = " " + s;
		return s;
	}

	static function count(m:Map<String, ModuleEntry>):Int {
		var n = 0;
		for (_ in m.keys()) n++;
		return n;
	}
}
