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
import musescript.evo.graal.EvoCache.CachedEval;
import musescript.evo.MapElites;
import musescript.evo.MapElites.EliteArchive;
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
typedef EvalJob = {var key:String; var wasmPath:String; var strings:Array<String>; var stop:Bool;}
typedef EvalResult = {var key:String; var trades:Int; var sharpe:Float; var finalEquity:Float; var avgHold:Float; var longFrac:Float;}

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
		// Soft-cap parsimony: free below the threshold, `parsimonyLambda` sharpe per node past
		// it. See Fitness.score's doc comment. Threshold=20 is roughly "typical" genome size
		// observed across this run's own champions so far; tune both from the command line
		// rather than re-editing source to experiment.
		var parsimonyThreshold = argInt("--parsimony-threshold", 20);
		var parsimonyLambda = argFloat("--parsimony-lambda", 0.01);
		// Fitness memo (see EvoCache): on by default, `--no-cache` disables it (e.g. to force a
		// cold re-measure of eval throughput). Scoped to the IS tape signature so the on-disk
		// file only ever warm-starts a re-run on the identical bars.
		var noCache = argFlag("--no-cache");
		// Prefix triage (successive-halving gate) for the EXPENSIVE serial JS-fallback path only
		// -- the native-WASM path is already cheap and parallel, so triaging it would only add
		// prefix-eval overhead for no saving. A new fallback genome is first scored on a cheap
		// `triageBars`-length prefix; only the top `triageKeep` fraction earns a full-tape eval,
		// the rest are killed for the generation (NEG_INF, and NOT written to the full memo, so a
		// genome the prefix under-rates can still be promoted if it recurs via a cheaper backend).
		// `--triage-bars 0` disables it; -1 (default) auto-sizes to a fifth of the IS tape.
		var triageBars = argInt("--triage-bars", -1);
		var triageKeep = argFloat("--triage-keep", 0.5);
		// MAP-Elites diversity preservation (see MapElites.hx): on by default. `--no-map-elites`
		// disables both the archive bookkeeping and the immigrant injection below, restoring plain
		// raw-fitness-only selection for an A/B comparison. `--immigrant-rate` is the fraction of
		// EACH generation's non-elite slots eligible to be replaced by a distinct-cell archive
		// champion not already present in the population -- 0 disables injection while leaving the
		// archive itself running (so `--immigrant-rate 0` still reports the diversity summary).
		var mapElitesOn = !argFlag("--no-map-elites");
		var immigrantRate = argFloat("--immigrant-rate", 0.2);
		// Auto-tuned growth-node-type weights (see GrowthWeights.hx / Variation.attributedPointMutate's
		// reward call). On by default with in-memory-only learning; `--tuner-path` opts into disk
		// persistence (warm-started + saved at the end, same convention as EvoCache) so tuning
		// compounds across repeated runs on the same corpus instead of restarting from
		// GrowthWeights' literal defaults every time.
		var tunerOn = !argFlag("--no-tuner");
		var tunerPath = argStr("--tuner-path", null);
		// Transaction cost (see OrderSim.executeLong/executeShort/executeFlat's doc comment): every
		// genome traded for FREE until this existed -- Expand.hx renders `long(size)`/`short(size)`/
		// `flat()`, the legacy immediate-fill verbs, which never applied slippage before the OrderSim
		// fix landed alongside this flag. 20bps default matches this project's own established
		// "realistic cost" convention elsewhere (see synth/marketsim's walk-forward gates, e.g.
		// "S&P100 Sharpe +2.99@20bps"). `--cost-bps 0` restores the old free-trading behavior for an
		// A/B comparison.
		var costBps = argFloat("--cost-bps", 20);
		// Live Swing dashboard (see EvoDashboardWindow.hx): off by default, zero impact on every
		// existing headless run. A real native window the JVM's own GUI thread repaints once per
		// generation -- no artifact-polling/republish workaround needed.
		var guiOn = argFlag("--gui");
		var dashboard = guiOn ? new EvoDashboardWindow("MuseGene Evolution -- " + (tapePath != null ? tapePath : "default tape")) : null;

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

		var cacheDir = "build/graal/evo-cache";
		if (!noCache && !sys.FileSystem.exists(cacheDir)) sys.FileSystem.createDirectory(cacheDir);
		// Cache filename includes costBps -- a fitness memo keyed on tape content ALONE would
		// silently reuse stale zero-cost (or different-cost) fitness numbers the moment `--cost-bps`
		// changes between runs on the SAME tape, which is exactly the kind of silent staleness this
		// whole cache existed to avoid causing (see EvoCache.hx's doc comment). `costBps` is now
		// part of what "the same evaluation" means, same as the bars themselves.
		var cachePath = noCache ? null : '$cacheDir/${EvoCache.tapeSignature(bars)}_cost${Std.int(costBps * 10)}.tsv';
		var cache = new EvoCache(cachePath);
		if (cachePath != null) Sys.println('fitness cache: $cachePath (warm-started ${cache.size()} entries)');

		// Auto-size the triage prefix to a fifth of the IS tape; keep it long enough for the
		// slower indicators to warm up (a too-short prefix would score every genome as a
		// no-warmup no-op and triage on noise), and never triage if the prefix would be the whole
		// tape anyway (short tapes -- then full eval IS the prefix eval, no point paying twice).
		if (triageBars < 0) triageBars = Std.int(bars.length / 5);
		if (triageBars > bars.length) triageBars = bars.length;
		var triageOn = triageBars >= 60 && triageBars < bars.length && triageKeep < 0.999;
		var prefixBars = triageOn ? bars.slice(0, triageBars) : null;
		var triageCache = (triageOn && !noCache) ? new EvoCache('$cacheDir/${EvoCache.tapeSignature(prefixBars)}_cost${Std.int(costBps * 10)}.tsv') : new EvoCache(null);
		if (triageOn)
			Sys.println('fallback triage: prefix ${triageBars} bars, keep top ${Std.int(triageKeep * 100)}% (warm-started ${triageCache.size()} prefix evals)');

		var archive = new EliteArchive();
		var immigrantRng = new musescript.evo.Rand(seed + 991);
		if (mapElitesOn) Sys.println('MAP-Elites: on (immigrant rate ${Std.int(immigrantRate * 100)}% of non-elite slots/gen)');

		var tuner = new musescript.evo.GrowthWeights();
		tuner.enabled = tunerOn;
		if (tunerOn && tunerPath != null) { tuner.load(tunerPath); Sys.println('growth tuner: warm-started from $tunerPath'); }
		Sys.println(tunerOn ? 'growth tuner: on (reward loop closed via attributedPointMutate)' : 'growth tuner: off (--no-tuner, using literal defaults)');

		// --- build the seed population --------------------------------------------------
		var allowed = new Map<String, Bool>();
		for (n in RegistryPalette.compatibleNames()) allowed.set(n, true);

		var tournament = CorpusSeed.seedFromDirectory(corpusDir, allowed);
		Sys.println('tournament corpus: ${tournament.total} files, ${tournament.genomes.length} translated to genomes, ${tournament.skipped.length} skipped (outside the closed GP grammar -- onPosition exits, multi-output field access, etc.)');

		// fourier_projection is excluded from the generic indicator list here -- seedFromIndicators'
		// 2-arg SInd-based crossover leaves k/horizon at spec defaults (horizon=1), which was
		// confirmed catastrophic (thousands of trades, sharpe -3 to -5). seedFromFourierProjection
		// below gives it a proper custom-parameterized, edge-triggered seed instead.
		var indicatorNames = [for (n in allowed.keys()) if (n != "fourier_projection") n];
		var indicatorSeeds = CorpusSeed.seedFromIndicators(indicatorNames);
		Sys.println('indicator seeds: ${indicatorNames.length} compatible indicators x 3 windows = ${indicatorSeeds.length} genomes');

		// fib_retracement/fourier_projection don't fit the generic seedFromIndicators path at all
		// (see seedFromFibRetracement's/seedFromFourierProjection's own doc comments) -- both use
		// edge-triggered crossings against a KFeature bare-expression leaf instead of a bare level
		// condition, after the first (level-condition) attempt at these seeds proved catastrophic
		// on a real tape (IS sharpe -2.3 to -4.8, hundreds to thousands of trades).
		var fibSeeds = CorpusSeed.seedFromFibRetracement();
		var fourierSeeds = CorpusSeed.seedFromFourierProjection();
		Sys.println('fib_retracement seeds: ${fibSeeds.length} genomes (3 windows x breakout/reclaim)');
		Sys.println('fourier_projection seeds: ${fourierSeeds.length} genomes (2 custom smoothed configs)');

		var seedPop = tournament.genomes.concat(indicatorSeeds).concat(fibSeeds).concat(fourierSeeds);
		Sys.println('seeded generation 0: ${seedPop.length} real genomes (${tournament.genomes.length} corpus-derived + ${indicatorSeeds.length} indicator-derived + ${fibSeeds.length} fib-retracement + ${fourierSeeds.length} fourier-projection)');

		var engineOpts = ["engine.LastTierCompilationThreshold" => "2000000000"];
		var host = new GraalWasmHost(null, engineOpts);
		host.costBps = costBps;
		Sys.println('transaction cost: ${costBps}bps slippage on every entry+exit (--cost-bps 0 to disable)');

		var engine = new EvolutionEngine(seed, pop, Std.int(Math.max(2, pop / 16)), 3, null, tuner);
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
			Thread.create(function() evalWorker(sharedEngine, bars, jobQueue, resultQueue, ackQueue, costBps));
		}

		// Soft-cap parsimony scoring from a raw eval (see Fitness.score's doc comment for the
		// threshold/lambda semantics) -- one definition used everywhere a CachedEval becomes a
		// selectable fitness, so the WASM path and the JS-fallback path can never drift apart the
		// way they did before this was a shared function.
		var scoreOf = function(e:CachedEval, nodes:Int):Float {
			if (e == null || e.trades < 1 || Math.isNaN(e.sharpe)) return Fitness.NEG_INF;
			var s = e.sharpe;
			if (nodes > parsimonyThreshold) s -= parsimonyLambda * (nodes - parsimonyThreshold);
			return s;
		};

		for (gen in 0...gens) {
			var tGen0 = haxe.Timer.stamp();

			// Group population indices by structural key so every clone shares ONE evaluation.
			// Elitism + premature convergence mean a handful of unique programs routinely back a
			// whole generation (the corpus-evo runs collapse to clones of one champion by gen 3);
			// keying the work here -- not per index -- is what lets the memo pay off within a
			// single generation, not merely across generations.
			var keyToIdx = new Map<String, Array<Int>>();
			var order:Array<String> = [];
			for (i in 0...popG.length) {
				var key = Canonical.structuralKey(popG[i]);
				if (!keyToIdx.exists(key)) { keyToIdx.set(key, []); order.push(key); }
				keyToIdx.get(key).push(i);
			}

			// Raw eval (trades/sharpe/equity) per UNIQUE key: memo hit, native WASM, or JS fallback.
			var evalByKey = new Map<String, CachedEval>();
			var missKeys:Array<String> = [];
			for (key in order) {
				var c = cache.get(key);
				if (c != null) evalByKey.set(key, c);
				else missKeys.push(key);
			}

			// Classify each miss key: emit WAT and go native if it compiles without the host_eval
			// escape hatch, else fall back to the JS/interp path. Genomes needing host_eval (any of
			// the 400+ `ta` registry indicators beyond the ~14 StrategyWasmEmitter lowers natively)
			// aren't representable on GraalWasmHost, which has no interp callback wired for it --
			// they still get a REAL, correct evaluation, just not GraalWasm-accelerated, so
			// selection is never silently biased against a newer Wickra-ported indicator.
			var pendingKeys:Array<String> = [];
			var stringsPending = new Map<String, Array<String>>();
			var wasmMiss:Array<String> = [];
			var fallbackMiss:Array<String> = [];
			var unsupported = 0;
			for (key in missKeys) {
				var g = popG[keyToIdx.get(key)[0]];
				if (moduleCache.exists(key)) { wasmMiss.push(key); continue; }
				if (unsupportedKeys.exists(key)) { fallbackMiss.push(key); unsupported++; continue; }
				var emitted = emitGenome(g);
				if (emitted == null || StringTools.contains(emitted.wat, "call $host_eval")) {
					unsupportedKeys.set(key, true);
					unsupported++;
					fallbackMiss.push(key);
					continue;
				}
				sys.io.File.saveContent('$watDir/$key.wat', emitted.wat);
				stringsPending.set(key, emitted.strings);
				pendingKeys.push(key);
				wasmMiss.push(key);
			}
			if (pendingKeys.length > 0) {
				var py = Sys.systemName() == "Windows" ? ".venv/Scripts/python.exe" : ".venv/bin/python";
				var code = Sys.command(py, ["tools/wat2wasm_batch.py", watDir]);
				if (code != 0) throw "wat2wasm batch failed";
			}
			for (key in pendingKeys) moduleCache.set(key, {strings: stringsPending.get(key), wasmPath: '$watDir/$key.wasm'});

			// Dispatch native-WASM miss keys to the worker pool -- one job per UNIQUE key.
			var dispatched = 0;
			for (key in wasmMiss) {
				var entry = moduleCache.get(key);
				jobQueue.add({key: key, wasmPath: entry.wasmPath, strings: entry.strings, stop: false});
				dispatched++;
			}
			for (_ in 0...dispatched) {
				var r = resultQueue.pop(true);
				var e:CachedEval = {trades: r.trades, sharpe: r.sharpe, finalEquity: r.finalEquity,
					avgHold: r.avgHold, longFrac: r.longFrac};
				evalByKey.set(r.key, e);
				cache.put(r.key, e);
			}
			// JS/interp fallback -- sequential, the real serial bottleneck (the memo already means
			// each unique program is paid once per run, not once per generation). Prefix triage
			// gates it further: score every NEW fallback genome on a cheap prefix first, promote
			// only the top fraction to the full-tape eval, kill the rest for this generation.
			var promoted = fallbackMiss;
			var triagedOut = 0;
			if (triageOn && fallbackMiss.length > 1) {
				var scored:Array<{key:String, s:Float}> = [];
				for (key in fallbackMiss) {
					var pc = triageCache.get(key);
					if (pc == null) {
						var g = popG[keyToIdx.get(key)[0]];
						var pr = Fitness.evaluate(g, prefixBars, "js", false, costBps);
						pc = pr.ok
							? {trades: pr.trades, sharpe: pr.sharpe, finalEquity: pr.finalEquity}
							: {trades: 0, sharpe: Math.NaN, finalEquity: 0};
						triageCache.put(key, pc);
					}
					var ps = (pc.trades >= 1 && !Math.isNaN(pc.sharpe)) ? pc.sharpe : Fitness.NEG_INF;
					scored.push({key: key, s: ps});
				}
				scored.sort((a, b) -> a.s < b.s ? 1 : (a.s > b.s ? -1 : 0));
				var keep = Std.int(Math.ceil(scored.length * triageKeep));
				if (keep < 1) keep = 1;
				promoted = [for (i in 0...keep) scored[i].key];
				// Killed keys: gen-local NEG_INF via a dead eval record, deliberately NOT written
				// to the full memo -- triage is a proxy, so a genome it under-rates must stay
				// eligible for a real full eval if it ever reaches a backend that doesn't triage.
				for (i in keep...scored.length) evalByKey.set(scored[i].key, {trades: 0, sharpe: Math.NaN, finalEquity: 0});
				triagedOut = scored.length - keep;
			}
			for (key in promoted) {
				var g = popG[keyToIdx.get(key)[0]];
				var fr = Fitness.evaluate(g, bars, "js", false, costBps);
				var e:CachedEval;
				if (fr.ok) {
					var desc = MapElites.describeFills(fr.fills, bars.length);
					e = {trades: fr.trades, sharpe: fr.sharpe, finalEquity: fr.finalEquity,
						avgHold: desc.avgHold, longFrac: desc.longFrac};
				} else {
					e = {trades: 0, sharpe: Math.NaN, finalEquity: 0};
				}
				evalByKey.set(key, e);
				cache.put(key, e);
			}

			// Score: fan each key's raw eval out to every index sharing it, applying the soft-cap
			// parsimony penalty per genome. nodeCount is identical across a shared key, but reading
			// it per index keeps this robust if that invariant ever changes.
			var fitness:Array<Float> = [for (_ in popG) Fitness.NEG_INF];
			for (key in order) {
				var e = evalByKey.get(key);
				var idxs = keyToIdx.get(key);
				for (idx in idxs) fitness[idx] = scoreOf(e, Canonical.nodeCount(popG[idx]));
				// MAP-Elites: offer this genome into its behavioral cell -- BEFORE parsimony, using
				// the raw eval directly (same reasoning as the OOS re-score / attribution evalFn:
				// niching should be driven by what the strategy actually did, not deflated by a
				// complexity penalty that would make a legitimately larger-but-still-novel genome
				// lose its niche slot to a smaller one that behaves identically). The
				// parsimony-adjusted `fitness` is deliberately NOT what's compared here.
				if (mapElitesOn && e != null && e.trades >= 1 && !Math.isNaN(e.sharpe)) {
					var tradesPerBar = e.trades / bars.length;
					var ck = MapElites.cellKey(tradesPerBar, e.avgHold != null ? e.avgHold : 0.0, e.longFrac != null ? e.longFrac : 0.5);
					archive.offer(popG[idxs[0]], e.sharpe, ck);
				}
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
			Sys.println('gen ${pad(Std.string(gen), 2)} | popSize=${popG.length} uniq=${order.length} new=${pendingKeys.length} fallback=${fallbackMiss.length} triaged=$triagedOut valid=$validN niches=${archive.size()}'
				+ ' | best=${fmt(genBest, 4)} mean=${fmt(mean, 4)} champion="${bestGenome != null ? bestGenome.name : "?"}"'
				+ ' | ${fmt(genMs, 0)}ms');

			if (dashboard != null) {
				var validFitness = [for (f in fitness) if (f != Fitness.NEG_INF) f];
				var nicheSummary = archive.summary();
				dashboard.update(gen, genBest, mean, archive.size(), bestGenome != null ? bestGenome.name : "?",
					validFitness, [for (c in nicheSummary) c.key], [for (c in nicheSummary) c.fitness]);
			}

			lastFitness = fitness;
			// Node-ablation-guided mutation (see Variation.attributedPointMutate): a real "js"
			// backtest oracle on the SAME in-sample bars evolution is scored against, so the
			// extra evaluations it costs stay honest to the same fitness definition, not a
			// cheaper proxy that could bias mutation toward something evolution isn't actually
			// selecting on.
			var evalFn = (g:StrategyGenome) -> Fitness.score(Fitness.evaluate(g, bars, "js", false, costBps), 1);
			if (gen < gens - 1) {
				popG = engine.step(popG, fitness, evalFn);
				if (mapElitesOn && immigrantRate > 0)
					popG = injectArchiveDiversity(popG, archive, engine.elite, immigrantRate, immigrantRng);
			}
		}
		var totalS = haxe.Timer.stamp() - totalT0;

		for (_ in 0...threads) jobQueue.add({key: "", wasmPath: "", strings: [], stop: true});
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
				var a = Fitness.evaluate(bestGenome, bars, "js", false, costBps);
				var b = Fitness.evaluate(bestGenome, bars, "js", false, costBps);
				if (a.trades != b.trades || Math.abs(a.finalEquity - b.finalEquity) > 1e-9)
					throw "champion non-deterministic";
				Sys.println('backend=js(fallback) trades=${a.trades} equity=${fmt(a.finalEquity, 2)} sharpe=${fmt(a.sharpe, 4)} nodeCount=${Canonical.nodeCount(bestGenome)}');
			}
			Sys.println(Expand.expand(bestGenome));
		}
		Sys.println('total wall: ${fmt(totalS, 1)}s  modules compiled: ${count(moduleCache)}');
		if (cachePath != null)
			Sys.println('cache: ${cache.hits} hits / ${cache.misses} misses across the run, ${cache.size()} unique programs memoized');
		if (mapElitesOn) {
			var cells = archive.summary();
			Sys.println('\n=== MAP-Elites diversity: ${cells.length}/48 behavioral cells occupied (tradeFreq_hold_bias) ===');
			for (c in cells) Sys.println('  ${c.key}: fitness=${fmt(c.fitness, 4)}');
		}
		if (tunerOn) {
			Sys.println('\n=== growth tuner: learned node-type weights ===');
			for (cat in ["boolTerm", "boolRecurse", "riskExit", "multiOutput", "scalarTerm", "scalarRecurse"]) {
				var s = tuner.summary(cat);
				Sys.println('  $cat: ' + [for (e in s) '${e.tag}=${fmt(e.weight * 100, 1)}%'].join(" "));
			}
			if (tunerPath != null) { tuner.save(tunerPath); Sys.println('  saved to $tunerPath'); }
		}

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
			var oos = Fitness.evaluate(r.g, oosBars, "js", false, costBps);
			var oosScore = Fitness.score(oos, 1);
			checked++;
			var holdMark = oosScore > 0 ? "HELD" : "did not hold";
			if (oosScore > 0) held++;
			Sys.println('  ${pad(Std.string(shown), 2)}. IS=${fmt(r.isFit, 4)}  OOS=${oos.ok ? fmt(oosScore, 4) : "n/a"} (trades=${oos.trades})  [$holdMark]  ${r.g.name}');
		}
		Sys.println('OOS summary: ${held}/${checked} of the top IS performers held a positive Sharpe out of sample.');

		cache.close();
		triageCache.close();
		host.close();
		Sys.println("\nCORPUS_EVO_OK");
	}

	static function evalWorker(engine:Engine, bars:Array<Bar>, jobs:Deque<EvalJob>, results:Deque<EvalResult>, acks:Deque<Int>, costBps:Float):Void {
		var host = new GraalWasmHost(engine);
		host.costBps = costBps;
		var instances = new Map<String, StrategyInstance>();
		while (true) {
			var job = jobs.pop(true);
			if (job.stop) { host.close(); acks.add(1); return; }
			var inst = instances.get(job.wasmPath);
			if (inst == null) {
				inst = host.instantiate(host.loadModuleFile(job.wasmPath), job.strings);
				instances.set(job.wasmPath, inst);
			}
			var r = inst.run(bars, new Map());
			// Behavioral-descriptor inputs (see MapElites.hx) computed HERE, on the worker thread,
			// from the fills this run just produced -- extracting two floats instead of shipping
			// the whole `fills` array back across the Deque to the main thread.
			var desc = MapElites.describeFills(r.fills, bars.length);
			results.add({key: job.key, trades: r.trades, sharpe: r.sharpe, finalEquity: r.finalEquity,
				avgHold: desc.avgHold, longFrac: desc.longFrac});
		}
	}

	/**
	 * MAP-Elites immigrant injection: after EvolutionEngine.step()'s raw-fitness-driven selection
	 * has already run, splice in archive champions from behavioral cells the fresh population
	 * DOESN'T currently contain. This is what actually prevents the collapse-to-one-basin failure
	 * mode observed in the corpus runs -- the archive alone (offer-only, no injection) would just
	 * be a passive report; a basin that raw-fitness selection has already crowded out would never
	 * get back INTO the population without this step, since tournament selection only ever draws
	 * from what's already there.
	 *
	 * Never touches the top `eliteCount` slots (EvolutionEngine.step already put its own raw-
	 * fitness elites there — immigrants compete for FUTURE generations via selection, they don't
	 * bypass it by force-replacing a proven performer). Replaces a random subset of the remaining
	 * (crossover/mutation-produced) slots, sized by `rate`, and only with archive genomes whose
	 * structural key isn't already present in this generation (no point re-injecting a niche
	 * champion the population already carries).
	 */
	static function injectArchiveDiversity(pop:Array<StrategyGenome>, archive:EliteArchive, eliteCount:Int, rate:Float, rng:musescript.evo.Rand):Array<StrategyGenome> {
		if (pop.length <= eliteCount) return pop;
		var present = new Map<String, Bool>();
		for (g in pop) present.set(Canonical.structuralKey(g), true);
		var candidates = [for (g in archive.elites()) if (!present.exists(Canonical.structuralKey(g))) g];
		if (candidates.length == 0) return pop;
		// Fisher-Yates shuffle candidates so repeated calls don't always inject the same niches
		// first when there are more candidates than slots.
		for (i in 0...candidates.length - 1) {
			var j = i + rng.int(candidates.length - i);
			var t = candidates[i]; candidates[i] = candidates[j]; candidates[j] = t;
		}
		var replaceableSlots = [for (i in eliteCount...pop.length) i];
		for (i in 0...replaceableSlots.length - 1) {
			var j = i + rng.int(replaceableSlots.length - i);
			var t = replaceableSlots[i]; replaceableSlots[i] = replaceableSlots[j]; replaceableSlots[j] = t;
		}
		var maxInject = Std.int(Math.max(0, Math.round(replaceableSlots.length * rate)));
		var n = Std.int(Math.min(maxInject, candidates.length));
		for (i in 0...n) pop[replaceableSlots[i]] = candidates[i];
		return pop;
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

	static function argFlag(name:String):Bool {
		for (a in Sys.args()) if (a == name) return true;
		return false;
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
