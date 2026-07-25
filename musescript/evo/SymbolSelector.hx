package musescript.evo;

/**
 * A genome's co-evolved preference for WHICH synthetic market/regime to trade this generation
 * (Part A of the MurmurationSim x corpus-evo symbol-selection plan) -- a small, independently
 * evolved, PARALLEL structure alongside a `StrategyGenome`, not a field ON it. Deliberately a
 * flat linear scoring function (weights over a fixed feature vector, dot product) rather than a
 * tree-based genome: matches this codebase's established hand-rolled-numerics style
 * (`SurrogateModel.hx`, `GrowthWeights.hx`, `Rand.hx`'s own LCG) and needs none of
 * `Variation.hx`'s BoolNode/ScalarNode crossover/mutation machinery -- a real-valued vector gets
 * ordinary real-valued GA operators (uniform crossover, Gaussian mutation) in a few lines.
 *
 * v1 feature vector (see `CorpusEvoRun.hx`'s multi-market compete wiring): a synthetic market's
 * OWN `MurmurationConfig` knobs (`fundamentalVol`, `marketFactorVol`, `impact`, `mixMarketMaker`)
 * -- deterministic and known before any ticks run, so `score()` can rank every candidate market
 * BEFORE the generation's sim(s) even start. Always `nFeatures = 4` in practice; kept general
 * here so the feature set can grow without touching this class.
 */
class SymbolSelector {

	/* [TODO] `weights`, `features`, etc should all be of a datatype crafted specifically for hyper-optimization on GraalVM & (separately) JavaScript, which we should employ throughout the codebase for such use cases */
	/* Also, some kind of reusable object-pooling infrastucture, written in such a way as to actually buy us some perf gains, rather than just costing us even more potential GraalVM optimizations. */
	
	public var weights:Array<Float>;

	public function new(nFeatures:Int, rng:Rand) {
		weights = [for (_ in 0...nFeatures) gaussian(rng) * 0.5];
	}

	public function score(features:Array<Float>):Float {
		var s = 0.0;
		for (i in 0...weights.length) s += weights[i] * (i < features.length ? features[i] : 0.0);
		return s;
	}

	/** Uniform per-gene crossover: each weight independently comes from `a` or `b` with equal
	 * probability -- the simplest correct real-valued crossover, no blending/averaging (which
	 * would bias every child toward the population mean over many generations). */
	public static function crossover(a:SymbolSelector, b:SymbolSelector, rng:Rand):SymbolSelector {
		var child = new SymbolSelector(0, rng); // nFeatures=0 -- weights overwritten immediately below
		child.weights = [for (i in 0...a.weights.length) rng.bool() ? a.weights[i] : b.weights[i]];
		return child;
	}

	/** Gaussian nudge per gene, each independently at probability `rate` -- mirrors
	 * `Variation.esNudgeParam`'s "perturb one thing, not the whole vector at once" spirit, just
	 * applied per-gene instead of per-genome since there's no tree structure to pick a single
	 * mutation site from. */
	public function mutate(rng:Rand, ?rate:Float = 0.2):SymbolSelector {
		var child = new SymbolSelector(0, rng);
		child.weights = [for (w in weights) rng.float() < rate ? w + gaussian(rng) * 0.3 : w];
		return child;
	}

	/** `w0\tw1\t...\twN` on a single line -- same tolerant TSV convention as `SurrogateModel`/
	 * `GrowthWeights`. */
	public function save(path:String):Void {
		sys.io.File.saveContent(path, weights.join("\t"));
	}

	public static function load(path:String):Null<SymbolSelector> {
		if (!sys.FileSystem.exists(path)) return null;
		var content = StringTools.trim(sys.io.File.getContent(path));
		if (content == "") return null;
		var parsed = [for (p in content.split("\t")) Std.parseFloat(p)];
		for (v in parsed) if (Math.isNaN(v)) return null;
		var s = new SymbolSelector(0, new Rand(0));
		s.weights = parsed;
		return s;
	}

	/** Box-Muller, uniform-from-`Rand` -- this codebase's `Rand.hx` only exposes `float()`/
	 * `int()`/`bool()`, no Gaussian primitive (unlike the kestrel-only `MurmurationRng`, not
	 * usable here since this class lives in the shared, non-kestrel `musescript.evo` package). */
	static function gaussian(rng:Rand):Float {
		var u1 = Math.max(1e-9, rng.float());
		var u2 = rng.float();
		return Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math.PI * u2);
	}
}
