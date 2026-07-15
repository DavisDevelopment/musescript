package musescript.evo;

/** Typed grow / mutate / crossover — closed under MuseGene types (no repair). */
class Variation {
	var rng:Rand;

	public function new(seed:Int) {
		rng = new Rand(seed);
	}

	public function randomGenome(depth:Int = 3):StrategyGenome {
		return {
			entryLong: growBool(depth),
			entryShort: growBool(depth),
			exitLong: growBool(depth),
			exitShort: growBool(depth),
			size: KConst(1),
			params: [],
			name: "musegene",
			lineage: [],
			seedOrigin: rng.seed
		};
	}

	public function mutate(g:StrategyGenome):StrategyGenome {
		var which = rng.int(5);
		return {
			entryLong: which == 0 ? growBool(2) : g.entryLong,
			entryShort: which == 1 ? growBool(2) : g.entryShort,
			exitLong: which == 2 ? growBool(2) : g.exitLong,
			exitShort: which == 3 ? growBool(2) : g.exitShort,
			size: which == 4 ? growScalar(1) : g.size,
			params: g.params.copy(),
			name: g.name,
			lineage: (g.lineage != null ? g.lineage.copy() : []).concat([Canonical.structuralKey(g)]),
			seedOrigin: g.seedOrigin
		};
	}

	public function crossover(a:StrategyGenome, b:StrategyGenome):StrategyGenome {
		return {
			entryLong: rng.bool() ? a.entryLong : b.entryLong,
			entryShort: rng.bool() ? a.entryShort : b.entryShort,
			exitLong: rng.bool() ? a.exitLong : b.exitLong,
			exitShort: rng.bool() ? a.exitShort : b.exitShort,
			size: rng.bool() ? a.size : b.size,
			params: a.params.copy(),
			name: a.name,
			lineage: [Canonical.structuralKey(a), Canonical.structuralKey(b)],
			seedOrigin: a.seedOrigin
		};
	}

	function growSeries(depth:Int):SeriesNode {
		if (depth <= 0 || rng.float() < 0.4)
			return SPrice(rng.pick(Palette.FIELDS));
		return SInd(rng.pick(Palette.INDS), rng.pick(Palette.FIELDS), rng.pick(Palette.WINDOWS), null);
	}

	function growScalar(depth:Int):ScalarNode {
		if (depth <= 0 || rng.float() < 0.5) return KSeries(growSeries(0));
		if (rng.float() < 0.5) return KConst(rng.float() * 4 - 2);
		return KArith(rng.pick(Palette.ARITH), growScalar(depth - 1), growScalar(depth - 1));
	}

	function growBool(depth:Int):BoolNode {
		if (depth <= 0 || rng.float() < 0.5) {
			if (rng.bool())
				return BCross(rng.pick(Palette.CROSS), growSeries(1), growSeries(1));
			return BCmp(rng.pick(Palette.CMP), growScalar(1), growScalar(1));
		}
		if (rng.float() < 0.5)
			return BAnd(growBool(depth - 1), growBool(depth - 1));
		return BOr(growBool(depth - 1), growBool(depth - 1));
	}
}
