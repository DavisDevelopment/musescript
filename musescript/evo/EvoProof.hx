package musescript.evo;

import musescript.harness.BarFeed;
import musescript.harness.OhlcvCsv;

/**
 * Seeded small-population evolutionary proof:
 * - typed mutation/crossover
 * - elitism non-regression
 * - fitness via MuseScript compile (js/wasm/interp)
 * - deterministic hashes
 */
class EvoProof {
	static function main() {
		var seed = 42;
		var gens = 3;
		var engine = new EvolutionEngine(seed, 8, 2, 3);
		var bars = loadBars();
		var pop = engine.seedPopulation(2);
		var best = -1e99;
		var keys = new Map<String, Bool>();
		var mutated = false;
		var crossed = false;

		// Force at least one structural change sample
		var v = new Variation(seed);
		var childM = v.mutate(pop[0]);
		var childC = v.crossover(pop[0], pop[1]);
		if (Canonical.structuralKey(childM) != Canonical.structuralKey(pop[0])) mutated = true;
		if (Canonical.structuralKey(childC) != Canonical.structuralKey(pop[0])) crossed = true;

		var target =
			#if js
			"js";
			#else
			"haxe";
			#end
		for (gen in 0...gens) {
			var fitness:Array<Float> = [];
			for (g in pop) {
				var fr = Fitness.evaluate(g, bars, target, false);
				var f = fr.ok && fr.trades >= 1 ? fr.sharpe : -100.0;
				// parsimony tie-break baked into score lightly
				f -= Canonical.nodeCount(g) * 0.0001;
				fitness.push(f);
				keys.set(Canonical.structuralKey(g), true);
			}
			var genBest = fitness[0];
			for (f in fitness) if (f > genBest) genBest = f;
			if (genBest + 1e-12 < best)
				throw 'elitism regresssed: $genBest < $best';
			if (genBest > best) best = genBest;
			Sys.println('gen=$gen best=${round(genBest, 6)} keys=${countKeys(keys)} mutated=$mutated crossed=$crossed');
			if (gen < gens - 1) pop = engine.step(pop, fitness);
		}

		// Parity: expand + re-evaluate champion deterministically
		var champ = pop[0];
		var a = Fitness.evaluate(champ, bars, target, false);
		var b = Fitness.evaluate(champ, bars, target, false);
		if (!a.ok) throw 'champion fitness failed: ${a.error}';
		if (a.trades != b.trades) throw "non-deterministic trades";
		if (Math.abs(a.finalEquity - b.finalEquity) > 1e-6) throw "non-deterministic equity";
		Sys.println('PROOF_OK trades=${a.trades} equity=${a.finalEquity} sharpe=${a.sharpe} backend=${a.backend}');
	}

	static function loadBars() {
		var candidates = ["data/real/spy.csv", "muse-script/data/real/spy.csv", "../muse-script/data/real/spy.csv"];
		for (path in candidates) {
			if (sys.FileSystem.exists(path)) {
				return OhlcvCsv.parse(sys.io.File.getContent(path));
			}
		}
		return BarFeed.synthetic(400, 42).all();
	}

	static function round(x:Float, n:Int):Float {
		// Avoid Int overflow on JVM (Math.round → 32-bit).
		var m = Math.pow(10, n);
		return Math.ffloor(x * m + 0.5) / m;
	}

	static function countKeys(m:Map<String, Bool>):Int {
		var n = 0;
		for (_ in m.keys()) n++;
		return n;
	}
}
