package musescript.evo;

/**
 * Population lifecycle, tournament selection, and elitism.
 * Production deployments may swap this for Jenetics Engine via `jenetics.Externs`
 * while keeping Variation + Fitness in Haxe.
 */
class EvolutionEngine {
	public var popSize:Int;
	public var elite:Int;
	public var tournament:Int;
	var variation:Variation;
	var rng:Rand;

	public function new(seed:Int, ?popSize:Int = 8, ?elite:Int = 2, ?tournament:Int = 3, ?indicatorPool:Array<String>) {
		this.popSize = popSize;
		this.elite = elite;
		this.tournament = tournament;
		this.variation = new Variation(seed, indicatorPool);
		this.rng = new Rand(seed + 7);
	}

	public function seedPopulation(depth:Int = 3):Array<StrategyGenome> {
		return [for (_ in 0...popSize) variation.randomGenome(depth)];
	}

	public function step(
		pop:Array<StrategyGenome>,
		fitness:Array<Float>
	):Array<StrategyGenome> {
		// Parsimony tiebreak (smaller node count wins a fitness tie) — matches musegene/
		// evolve.py's `scored.sort(key=lambda t: (t[0], -node_count(t[1])), reverse=True)`
		// exactly. Kept as a genuine TIEBREAK in the comparator, not folded into the fitness
		// value itself (see Fitness.score's doc comment for why that's the wrong place for it).
		var ranked = [for (i in 0...pop.length) { g: pop[i], f: fitness[i], n: Canonical.nodeCount(pop[i]) }];
		ranked.sort(function(a, b) {
			if (a.f != b.f) return a.f < b.f ? 1 : -1;
			return a.n < b.n ? -1 : a.n > b.n ? 1 : 0;
		});
		var next:Array<StrategyGenome> = [];
		for (i in 0...Std.int(Math.min(elite, ranked.length)))
			next.push(ranked[i].g);
		while (next.length < popSize) {
			var p1 = tournamentSelect(ranked);
			var p2 = tournamentSelect(ranked);
			var child = variation.crossover(p1, p2);
			if (rng.float() < 0.3) child = variation.mutate(child);
			next.push(child);
		}
		return next;
	}

	function tournamentSelect(ranked:Array<{g:StrategyGenome, f:Float}>):StrategyGenome {
		var best = ranked[rng.int(ranked.length)];
		for (_ in 1...tournament) {
			var cand = ranked[rng.int(ranked.length)];
			if (cand.f > best.f) best = cand;
		}
		return best.g;
	}
}
