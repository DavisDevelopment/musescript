package musescript.evo;

/**
 * Adaptive category -> tag weight tracker for GP growth decisions -- turns what used to be
 * hardcoded `rng.float() < 0.4` cascades in Variation.hx's growBool/growScalar/growRiskExit/
 * growMultiOutputField into an explicit, nameable, REWARDABLE distribution. Each "category" (the
 * growBool terminal-kind choice, the growBool and/or/not recurse choice, the growRiskExit
 * stopLoss/takeProfit/timeStop choice, ...) gets its own independent roulette-wheel weight table;
 * `pick` draws a tag proportional to its current weight, `reward` nudges a tag's weight toward a
 * fitness-delta signal fed back from evolution itself (see Variation.attributedPointMutate, the
 * one caller with a real evalFn to measure "did introducing THIS kind of node actually help").
 *
 * `seedDefaults()` reproduces Variation.hx's ORIGINAL literal probabilities exactly, so a fresh
 * `GrowthWeights()` that never has `reward()` called on it behaves identically to the pre-tuning
 * hardcoded cascades -- zero behavior change for any caller that doesn't opt into the feedback
 * loop, same discipline as every other addition this session (EvoCache, MAP-Elites, parsimony).
 *
 * Deliberately generic/reusable rather than hand-rolled per category -- a future growth choice
 * (a new BoolNode terminal kind, say) just needs one `setCategory` call and a `pick`/`reward`
 * pair at its call site, not a bespoke cascade.
 */
class GrowthWeights {
	var w:Map<String, Map<String, Float>> = new Map();
	var lr:Float;
	var minWeight:Float;
	/** When false, `reward()` is a no-op -- `pick()` still works, using whatever weights this
	 * instance currently holds (its seeded defaults if reward() was never allowed to run), which
	 * makes "disabled" behave EXACTLY like the original hardcoded literal cascades. Lets a caller
	 * (CorpusEvoRun's `--no-tuner`) turn off the adaptive feedback loop without needing to avoid
	 * constructing a GrowthWeights at all. */
	public var enabled:Bool = true;

	/**
	 * Thread contract: `EvolutionEngine.step` may call `pick`/`reward` from AttrPool workers during
	 * parallel child production. The weight tables are a plain StringMap (§27) — guard every
	 * read-modify-write. Sections stay get/set only; never call back into Variation while held.
	 */
	final lock = new EvoLock();

	/** `lr` is the EMA nudge rate applied on each `reward()` call; `minWeight` is a floor so no
	 * tag's probability can be driven to zero by a run of unlucky draws -- explore pressure never
	 * fully collapses, mirroring `attributedPointMutate`'s own 20% uniform-fallback rationale. */
	public function new(?lr:Float = 0.15, ?minWeight:Float = 0.02) {
		this.lr = lr;
		this.minWeight = minWeight;
		seedDefaults();
	}

	function seedDefaults():Void {
		// growBool's terminal branch (Variation.hx): cross 0.35, cmp 0.25 (0.6-0.35), trend 0.2
		// (0.8-0.6), riskExit 0.2 (1-0.8) -- see growBool's post-riskExit thresholds.
		setCategory("boolTerm", ["cross" => 0.35, "cmp" => 0.25, "trend" => 0.2, "riskExit" => 0.2]);
		// growBool's recurse branch: and 0.4, or 0.4 (0.8-0.4), not 0.2 (1-0.8).
		setCategory("boolRecurse", ["and" => 0.4, "or" => 0.4, "not" => 0.2]);
		// growRiskExit: stopLoss 0.4, takeProfit 0.35 (0.75-0.4), timeStop 0.25 (1-0.75).
		setCategory("riskExit", ["stopLoss" => 0.4, "takeProfit" => 0.35, "timeStop" => 0.25]);
		// growMultiOutputField's indicator-kind choice: macd 0.4, bbands 0.35, stoch 0.25.
		setCategory("multiOutput", ["macd" => 0.4, "bbands" => 0.35, "stoch" => 0.25]);
		// growScalar's depth<=0 terminal branch, conditioned on a param pool being available:
		// param 0.15, multiOutput 0.12*(1-0.15)~=0.102, series the remainder.
		setCategory("scalarTerm", ["param" => 0.15, "multiOutput" => 0.102, "series" => 0.748]);
		// growScalar's depth>0 recurse branch: series 0.35, param 0.2*(0.65)=0.13, const
		// 0.5*(0.52)=0.26, arith the remainder.
		setCategory("scalarRecurse", ["series" => 0.35, "param" => 0.13, "const" => 0.26, "arith" => 0.26]);
	}

	function setCategory(cat:String, tags:Map<String, Float>):Void w.set(cat, tags);

	public function hasCategory(cat:String):Bool return w.exists(cat);

	/** Ensure `cat`/`tag` exist (library learning / mid-run motif promote). Idempotent. */
	public function ensureTag(cat:String, tag:String, ?weight:Float = 0.1):Void {
		lock.acquire();
		var tags = w.get(cat);
		if (tags == null) {
			tags = new Map();
			w.set(cat, tags);
		}
		if (!tags.exists(tag)) tags.set(tag, weight);
		lock.release();
	}

	/** Roulette-wheel draw proportional to current weight. Throws on an unknown category (a
	 * programming error, not a runtime condition to recover from -- every category is registered
	 * up front in seedDefaults). */
	public function pick(cat:String, rng:Rand):String {
		lock.acquire();
		var tags = w.get(cat);
		if (tags == null) {
			lock.release();
			throw 'GrowthWeights: unknown category "$cat"';
		}
		var total = 0.0;
		for (v in tags) total += v;
		var r = rng.float() * total;
		var acc = 0.0;
		var last:String = null;
		var chosen:String = null;
		for (k => v in tags) {
			acc += v;
			last = k;
			if (r <= acc) { chosen = k; break; }
		}
		if (chosen == null) chosen = last;
		lock.release();
		return chosen;
	}

	/** `delta` is childFitness - baselineFitness from the SAME evaluation the mutation that
	 * introduced this tag was judged by. A positive delta (the mutation actually helped) nudges
	 * the tag's weight up proportionally (capped at +1.0 per call so one huge outlier can't
	 * dominate); a non-positive delta applies a small flat decay rather than a harsh punishment --
	 * one bad draw shouldn't starve a node kind that might still be valuable elsewhere in the
	 * search, matching this codebase's established explore-preserving bias. */
	public function reward(cat:String, tag:String, delta:Float):Void {
		if (!enabled) return;
		if (Math.isNaN(delta) || !Math.isFinite(delta)) return;
		lock.acquire();
		var tags = w.get(cat);
		if (tags == null || !tags.exists(tag)) {
			lock.release();
			return;
		}
		var signal = delta > 0 ? Math.min(1.0, delta) : -0.1;
		var cur = tags.get(tag);
		var next = cur + lr * signal * cur;
		if (next < minWeight) next = minWeight;
		tags.set(tag, next);
		lock.release();
	}

	/** Normalized weights (sum to 1 within a category), highest first -- for end-of-run reporting. */
	public function summary(cat:String):Array<{tag:String, weight:Float}> {
		var tags = w.get(cat);
		if (tags == null) return [];
		var total = 0.0;
		for (v in tags) total += v;
		var out = [for (k => v in tags) {tag: k, weight: total > 0 ? v / total : 0.0}];
		out.sort((a, b) -> a.weight > b.weight ? -1 : (a.weight < b.weight ? 1 : 0));
		return out;
	}

	public function categories():Array<String> return [for (k in w.keys()) k];

	/** Persist current weights as `category\ttag\tweight` lines -- same plain-TSV convention as
	 * EvoCache, so a re-run on the same corpus warm-starts with whatever the tuning loop already
	 * learned rather than restarting from `seedDefaults()` every time. Only meaningful across runs
	 * with the SAME category/tag vocabulary (a category/tag this file no longer defines is written
	 * but simply ignored by a future `load()` against a version that dropped it). */
	public function save(path:String):Void {
		var lines = [];
		for (cat => tags in w) for (tag => weight in tags) lines.push('$cat\t$tag\t$weight');
		sys.io.File.saveContent(path, lines.join("\n"));
	}

	/** Loads weights for any (category, tag) pair this instance already knows about (from
	 * `seedDefaults`); unknown categories/tags in the file are skipped rather than treated as an
	 * error -- tolerant of a file saved by an older/newer version with a different vocabulary. */
	public function load(path:String):Void {
		if (!sys.FileSystem.exists(path)) return;
		for (line in sys.io.File.getContent(path).split("\n")) {
			if (line.length == 0) continue;
			var parts = line.split("\t");
			if (parts.length < 3) continue;
			var cat = parts[0], tag = parts[1];
			var v = Std.parseFloat(parts[2]);
			if (Math.isNaN(v) || v <= 0) continue;
			var tags = w.get(cat);
			if (tags == null || !tags.exists(tag)) continue;
			tags.set(tag, v);
		}
	}
}
