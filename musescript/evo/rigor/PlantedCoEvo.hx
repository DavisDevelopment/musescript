package musescript.evo.rigor;

import musescript.evo.BoolNode;
import musescript.evo.EvolutionEngine;
import musescript.evo.Fitness;
import musescript.evo.FitnessResult;
import musescript.evo.ProjectionProvider;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
import musescript.ew.NullForecastHost;
import musescript.ew.OracleForecastHost;
import musescript.harness.Bar;
import musescript.harness.Metrics;

/**
 * Bounded multi-gen planted-edge co-evolution for pipeline hardening (J2 live path).
 * Uses OracleForecastHost as the forecast substrate; EvolutionEngine varies genomes
 * across `--seed`-stamped restarts. OOS is scored through {@link OosVerdict}.
 */
class PlantedCoEvo {
	public static function plantedGenome(name:String, horizon:Int = 3, hostSeed:Int = 1):StrategyGenome {
		return {
			entryLong: BCmp(">", KSeries(SProj("ew_0", "p50")), KSeries(SPrice("close"))),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp("<", KSeries(SProj("ew_0", "p50")), KSeries(SPrice("close"))),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			params: [],
			name: name,
			lineage: ["planted-coevo"],
			seedOrigin: null,
			projections: [ProjectionProvider.ewDecl("ew_0", horizon, "oracle", hostSeed)]
		};
	}

	public static function buyHold():StrategyGenome {
		return {
			entryLong: BCmp(">", KConst(1.0), KConst(0.0)),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0), params: [], name: "buy_and_hold", lineage: [], seedOrigin: null
		};
	}

	static function evalWithHost(g:StrategyGenome, tape:Array<Bar>, host:musescript.ew.EwForecastHost):FitnessResult {
		var provider = new ProjectionProvider(host);
		provider.autoBindGenomeHost = false;
		var prev = Fitness.projectionProvider;
		Fitness.projectionProvider = provider;
		var fr = Fitness.evaluate(g, tape, "js", false, 0.0);
		Fitness.projectionProvider = prev;
		return fr;
	}

	/**
	 * One multi-gen planted run on a fixed IS/OOS split.
	 * Returns champion OOS Sharpe + hardened verdict (and null-host control verdict).
	 */
	public static function runOnce(
		all:Array<Bar>,
		?opts:{
			?seed:Int,
			?pop:Int,
			?gens:Int,
			?oosFrac:Float,
			?embargo:Int,
			?horizon:Int,
			?minTrades:Int,
			?nTrials:Int,
			?signal:Float,
			?nBoot:Int,
			?psrGate:Float
		}
	):{
		seed:Int,
		gens:Int,
		championIs:Float,
		championOosSharpe:Float,
		championTrades:Int,
		bhSharpe:Float,
		oos:Dynamic,
		nullOos:Dynamic,
		go:Bool
	} {
		var seed = opts != null && opts.seed != null ? opts.seed : 42;
		var pop = opts != null && opts.pop != null ? opts.pop : 8;
		var gens = opts != null && opts.gens != null ? opts.gens : 3;
		var oosFrac = opts != null && opts.oosFrac != null ? opts.oosFrac : 0.30;
		var embargo = opts != null && opts.embargo != null ? opts.embargo : 8;
		var horizon = opts != null && opts.horizon != null ? opts.horizon : 3;
		var minTrades = opts != null && opts.minTrades != null ? opts.minTrades : 20;
		var nTrials = opts != null && opts.nTrials != null ? opts.nTrials : 5;
		var signal = opts != null && opts.signal != null ? opts.signal : 1.0;
		var nBoot = opts != null && opts.nBoot != null ? opts.nBoot : 80;
		var psrGate = opts != null && opts.psrGate != null ? opts.psrGate : 0.90;

		Fitness.defaultMinTrades = minTrades;
		Fitness.equityCurveNeeded = true;

		var split = PurgeEmbargo.split(all.length, oosFrac, embargo);
		var isBars = all.slice(0, split.isEnd);
		var oosBars = all.slice(split.oosStart, all.length);

		var oracleIs = OracleForecastHost.fromBars(isBars, signal, horizon, seed);
		var base = plantedGenome('planted_s${seed}', horizon, seed);
		// Seed pop: planted edge + a few mutated clones via EvolutionEngine.
		var engine = new EvolutionEngine(seed, pop, Std.int(Math.max(1, Std.int(pop / 4))), 3, null, null);
		var popG:Array<StrategyGenome> = [base];
		while (popG.length < pop) {
			var clone:StrategyGenome = {
				entryLong: base.entryLong, entryShort: base.entryShort,
				exitLong: base.exitLong, exitShort: base.exitShort,
				size: base.size, params: base.params != null ? base.params.copy() : [],
				name: base.name + "_c" + popG.length,
				lineage: ["planted-coevo", "clone"],
				seedOrigin: null,
				projections: base.projections,
				panelAction: base.panelAction
			};
			popG.push(clone);
		}

		function scoreIs(g:StrategyGenome):Float {
			var fr = evalWithHost(g, isBars, oracleIs);
			if (!fr.ok) return Fitness.NEG_INF;
			return Fitness.rankScore(fr, minTrades, nTrials);
		}

		var lastFit:Array<Float> = [for (g in popG) scoreIs(g)];
		var gen = 0;
		while (gen < gens) {
			popG = engine.step(popG, lastFit);
			lastFit = [for (g in popG) scoreIs(g)];
			gen++;
		}

		var bestIx = 0;
		var bestFit = Fitness.NEG_INF;
		for (i in 0...popG.length) {
			if (lastFit[i] > bestFit) {
				bestFit = lastFit[i];
				bestIx = i;
			}
		}
		var champ = popG[bestIx];

		var bh = Fitness.evaluate(buyHold(), oosBars, "js", false, 0.0);
		var bhSr = bh.ok ? bh.sharpe : 0.0;

		var oracleOos = OracleForecastHost.fromBars(oosBars, signal, horizon, seed);
		var frChamp = evalWithHost(champ, oosBars, oracleOos);
		var champSr = frChamp.ok ? frChamp.sharpe : Math.NaN;
		var champTrades = frChamp.ok ? frChamp.trades : 0;
		var rets = (frChamp.ok && frChamp.equity != null) ? Metrics.returnsFromEquity(frChamp.equity) : [];
		var oos = OosVerdict.evaluate(rets, champTrades, bhSr, {
			minTrades: minTrades, nTrials: nTrials, nBoot: nBoot, psrGate: psrGate, bootSeed: seed
		});

		var nullOosHost = new NullForecastHost(seed ^ 0x0011, horizon);
		for (i in 0...oosBars.length) nullOosHost.onBar(oosBars[i], i);
		var frNull = evalWithHost(champ, oosBars, nullOosHost);
		var retsN = (frNull.ok && frNull.equity != null) ? Metrics.returnsFromEquity(frNull.equity) : [];
		var nullOos = OosVerdict.evaluate(retsN, frNull.ok ? frNull.trades : 0, bhSr, {
			minTrades: minTrades, nTrials: nTrials, nBoot: nBoot, psrGate: psrGate, bootSeed: seed
		});

		return {
			seed: seed,
			gens: gens,
			championIs: bestFit,
			championOosSharpe: champSr,
			championTrades: champTrades,
			bhSharpe: bhSr,
			oos: oos,
			nullOos: nullOos,
			go: oos.go
		};
	}

	/**
	 * N independent CLI-style `--seed` restarts → {@link SeedRobustness.verdict}.
	 * Metric = champion OOS Sharpe (finite only).
	 */
	public static function seedMatrix(
		all:Array<Bar>,
		seeds:Array<Int>,
		?opts:{
			?pop:Int,
			?gens:Int,
			?oosFrac:Float,
			?embargo:Int,
			?horizon:Int,
			?minTrades:Int,
			?nTrials:Int,
			?signal:Float,
			?threshold:Float
		}
	):{
		runs:Array<{
			seed:Int, gens:Int, championIs:Float, championOosSharpe:Float,
			championTrades:Int, bhSharpe:Float, oos:Dynamic, nullOos:Dynamic, go:Bool
		}>,
		metrics:Array<Float>,
		verdict:{go:Bool, median:Float, max:Float, threshold:Float, n:Int}
	} {
		var threshold = opts != null && opts.threshold != null ? opts.threshold : 0.0;
		var runs:Array<{
			seed:Int, gens:Int, championIs:Float, championOosSharpe:Float,
			championTrades:Int, bhSharpe:Float, oos:Dynamic, nullOos:Dynamic, go:Bool
		}> = [];
		var metrics:Array<Float> = [];
		for (s in seeds) {
			var r = runOnce(all, {
				seed: s,
				pop: opts != null ? opts.pop : null,
				gens: opts != null ? opts.gens : null,
				oosFrac: opts != null ? opts.oosFrac : null,
				embargo: opts != null ? opts.embargo : null,
				horizon: opts != null ? opts.horizon : null,
				minTrades: opts != null ? opts.minTrades : null,
				nTrials: opts != null ? opts.nTrials : null,
				signal: opts != null ? opts.signal : null
			});
			runs.push(r);
			if (Math.isFinite(r.championOosSharpe)) metrics.push(r.championOosSharpe);
		}
		return {
			runs: runs,
			metrics: metrics,
			verdict: SeedRobustness.verdict(metrics, threshold)
		};
	}
}
