package musescript.evo;

/**
 * Online linear regression (Widrow-Hoff / LMS rule) predicting a genome's fitness from
 * `Canonical.shapeFeatures` alone -- zero backtest cost, just a dot product. For CorpusEvoRun's
 * opt-in `--surrogate` pre-filter, an even-cheaper stage ahead of the existing triage-prefix eval
 * (see this session's surrogate-model plan). Deliberately the smallest thing that could work,
 * matching this codebase's existing hand-rolled-numerics style (`Rand.hx`'s LCG, `Metrics.hx`'s
 * plain-loop sharpe/sortino, `GrowthWeights.hx`'s roulette-wheel bandit) rather than pulling in an
 * external ML library for something this size -- researched two (`neureka`, `sklearn-java`) and
 * neither was a good fit (see the plan's Context section).
 *
 * `save`/`load` mirror `GrowthWeights`'s exact convention (plain TSV, tolerant load, warm-start
 * across runs via `--surrogate-path`) so a surrogate that's learned something useful on one
 * corpus/basket carries forward instead of restarting cold every run.
 */
class SurrogateModel {
	var weights:Array<Float>;
	var bias:Float = 0.0;
	var lr:Float;
	public var nFeatures(default, null):Int;
	/** How many `update()` calls this instance has ever seen -- purely informational (end-of-run
	 * reporting), never consulted by `predict`/`update` themselves. */
	public var samplesSeen(default, null):Int = 0;

	public function new(?nFeatures:Int = 18, ?lr:Float = 0.01) {
		this.nFeatures = nFeatures;
		this.lr = lr;
		weights = [for (_ in 0...nFeatures) 0.0];
	}

	public function predict(features:Array<Float>):Float {
		var s = bias;
		for (i in 0...weights.length) s += weights[i] * (i < features.length ? features[i] : 0.0);
		return s;
	}

	/**
	 * `weights += lr * (target - predict(features)) * features; bias += lr * (target - predict)`
	 * -- the plain LMS update, same "nudge toward the observed signal" spirit as
	 * `GrowthWeights.reward`'s EMA nudge, just for a continuous target instead of a discrete tag
	 * weight. Silently ignores a non-finite target (NaN/Infinity) rather than letting it corrupt
	 * the weights -- callers should already be clamping an invalid genome's target to a bounded
	 * sentinel (CorpusEvoRun does; see the plan's `validOrSentinel` note), but this is a defensive
	 * backstop, not the primary contract.
	 */
	public function update(features:Array<Float>, target:Float):Void {
		if (Math.isNaN(target) || !Math.isFinite(target)) return;
		var err = target - predict(features);
		for (i in 0...weights.length) {
			var f = i < features.length ? features[i] : 0.0;
			weights[i] += lr * err * f;
		}
		bias += lr * err;
		samplesSeen++;
	}

	/** `w0\tw1\t...\twN\tbias` on a single line. */
	public function save(path:String):Void {
		sys.io.File.saveContent(path, weights.join("\t") + "\t" + bias);
	}

	/** Tolerant load: a missing file, a malformed line, or a saved vector of the WRONG length
	 * (e.g. `SHAPE_KINDS` grew since the file was written) are all silently ignored -- this
	 * instance just keeps its freshly-constructed zero weights, exactly the "cold start" a caller
	 * gets by not passing `--surrogate-path` at all. Never a fatal error. */
	public function load(path:String):Void {
		if (!sys.FileSystem.exists(path)) return;
		var content = StringTools.trim(sys.io.File.getContent(path));
		if (content == "") return;
		var parts = content.split("\t");
		if (parts.length != weights.length + 1) return;
		var parsed = [for (p in parts) Std.parseFloat(p)];
		for (v in parsed) if (Math.isNaN(v)) return;
		for (i in 0...weights.length) weights[i] = parsed[i];
		bias = parsed[parsed.length - 1];
	}
}
