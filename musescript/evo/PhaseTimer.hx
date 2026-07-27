package musescript.evo;

/**
 * Wall-clock accounting for a generation, by phase.
 *
 * Every speed claim about this evolution loop so far has been an argument about asymptotics —
 * which phase *should* dominate at a given population size. That is exactly the folklore the JIT
 * guide's §9 tells us not to optimize against. A generation has a small, fixed set of phases and
 * they are separated by real barriers, so the honest version is cheap: time them.
 *
 * Deliberately coarse. This measures the SERIAL structure of a generation — how much of the wall
 * clock is the parallel evaluation barrier versus the single-threaded tail (keying, speciation,
 * novelty, variation) that no amount of `--threads` can shrink. That ratio, not the eval rate, is
 * what decides whether a population size is reachable at a target generations-per-second.
 *
 * Not thread-safe and not meant to be: only the orchestrating thread calls it, and it brackets the
 * worker barriers rather than reaching inside them.
 *
 * «ὥρα μετρεῖται· χορὸς οὐ μένει.»
 */
class PhaseTimer {
	public static inline var KEYS = "keys";
	public static inline var EVAL = "eval";
	public static inline var ARCHIVE = "archive";
	public static inline var SPECIES = "species";
	public static inline var NOVELTY = "novelty";
	public static inline var LEXICASE = "lexicase";
	public static inline var STEP = "step";
	/**
	 * Sub-phases of `EVAL`, measured on the orchestrating thread. `EVAL` is the phase `--threads`
	 * is supposed to shrink, but it brackets more than the worker barrier: the score/offer loop
	 * after it runs single-threaded over the whole population. Splitting them is the only way to
	 * see which half sets the floor.
	 */
	public static inline var EVAL_TRIAGE = "eval.triage";
	public static inline var EVAL_BARRIER = "eval.barrier";
	public static inline var EVAL_OFFER = "eval.offer";
	/** Sub-phases of `EvolutionEngine.step` (parallel children may call `stop` concurrently). */
	public static inline var STEP_PLAN = "step.plan";
	public static inline var STEP_XO = "step.xo";
	public static inline var STEP_MUT = "step.mut";
	public static inline var STEP_SIMP = "step.simp";

	/** Print order; anything else a caller names is appended after these. */
	static final ORDER = [
		KEYS, EVAL, EVAL_TRIAGE, EVAL_BARRIER, EVAL_OFFER, ARCHIVE, SPECIES, NOVELTY, LEXICASE, STEP,
		STEP_PLAN, STEP_XO, STEP_MUT, STEP_SIMP
	];

	public var enabled(default, null):Bool;

	final totals:Map<String, Float> = new Map();
	final names:Array<String> = [];
	final lock = new EvoLock();
	var genStart:Float = 0;
	var genTotal:Float = 0;
	var gens:Int = 0;

	/** Process-wide timer armed by CorpusEvoRun so Variation/Engine can record without threading a ref. */
	public static var current:Null<PhaseTimer> = null;

	public function new(enabled:Bool) {
		this.enabled = enabled;
	}

	/** Start of a generation's wall clock. */
	public function beginGeneration():Void {
		if (!enabled) return;
		genStart = Sys.time();
	}

	/** End of a generation's wall clock. */
	public function endGeneration():Void {
		if (!enabled) return;
		genTotal += Sys.time() - genStart;
		gens++;
	}

	/** Open a phase; returns the start stamp to hand back to `stop`. */
	public inline function start():Float {
		return enabled ? Sys.time() : 0.0;
	}

	/** Close a phase opened with `start`. Thread-safe: parallel child production records here. */
	public function stop(phase:String, startedAt:Float):Void {
		if (!enabled) return;
		var dt = Sys.time() - startedAt;
		lock.acquire();
		var prev = totals.get(phase);
		if (prev == null) {
			prev = 0.0;
			names.push(phase);
		}
		totals.set(phase, prev + dt);
		lock.release();
	}

	public function generations():Int return gens;

	/** Mean seconds per generation across everything timed so far. */
	public function secondsPerGeneration():Float {
		return gens > 0 ? genTotal / gens : 0.0;
	}

	/**
	 * Per-phase mean milliseconds and share of the generation, plus the residual the phases don't
	 * account for — reported rather than hidden, because an unexplained remainder is a finding.
	 */
	public function report():Array<String> {
		if (!enabled || gens == 0) return [];
		var out:Array<String> = [];
		var perGen = secondsPerGeneration();
		out.push('phase-profile: $gens gens, mean ${fmtMs(perGen)} ms/gen'
			+ (perGen > 0 ? ' (${fmt(1.0 / perGen)} gen/s)' : ''));
		var ordered:Array<String> = [];
		for (p in ORDER) if (totals.exists(p)) ordered.push(p);
		for (p in names) if (ORDER.indexOf(p) < 0) ordered.push(p);
		var accounted = 0.0;
		for (p in ordered) {
			var mean = totals.get(p) / gens;
			// Any dotted name is a breakdown of the phase above it, never counted toward the
			// residual. `step.*` are summed CPU across AttrPool workers and can exceed the wall
			// `step` bracket under parallelism; `eval.*` are wall slices of `eval` and sum to it.
			var detail = p.indexOf(".") >= 0;
			if (!detail) accounted += mean;
			out.push('  ${pad(p)} ${fmtMs(mean)} ms  ${pct(mean, perGen)}'
				+ (detail ? (StringTools.startsWith(p, "step.") ? " cpu" : " of eval") : ""));
		}
		var residual = perGen - accounted;
		out.push('  ${pad("unaccounted")} ${fmtMs(residual)} ms  ${pct(residual, perGen)}');
		if (keyHits() + keyMisses() > 0)
			out.push('  keyCache: hits=${keyHits()} misses=${keyMisses()}'
				+ ' (${pct(keyHits(), keyHits() + keyMisses())})');
		return out;
	}

	static function keyHits():Int return Canonical.keyHits;
	static function keyMisses():Int return Canonical.keyMisses;

	static function pad(s:String):String {
		var out = s;
		while (out.length < 12) out += " ";
		return out;
	}

	static function pct(part:Float, whole:Float):String {
		if (whole <= 0) return "";
		return fmt(100.0 * part / whole) + "%";
	}

	static function fmtMs(seconds:Float):String return fmt(seconds * 1000.0);

	static function fmt(v:Float):String {
		var r = Math.round(v * 100) / 100;
		return Std.string(r);
	}
}
