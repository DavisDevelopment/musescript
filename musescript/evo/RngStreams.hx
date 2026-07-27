package musescript.evo;

/**
 * Named registry of RNG-stream seed offsets -- the fix for a real confound found this session
 * (the P1 `--attr-cross-prob`/`--donor-cap` A/B): `EvolutionEngine.step` used to draw tournament
 * picks AND the crossover/mutate-choice rolls from ONE shared `rng`, so changing how often a
 * branch fires shifted how many draws it consumed, which shifted every SUBSEQUENT draw for the
 * rest of the run -- "same seed" stopped meaning "same experiment" almost immediately.
 *
 * Principle: only decision axes an independent feature FLAG can toggle need their own stream.
 * `Variation`'s internal growth/site-selection recursion stays on one shared `rng` -- it's one
 * cohesive "grow/pick a random thing" concern, not independently toggled, and splitting every
 * individual `rng.float()` call inside it would be noise, not hygiene.
 *
 * Every offset below is a fixed, DOCUMENTED, NEVER-REUSED `seed + N` -- the same lightweight
 * stream-splitting convention this codebase already used ad hoc (`CorpusEvoRun.immigrantRng` =
 * `seed + 991`, `HumanLoopWindow`'s own `Variation` = `seed + 5000`), just centralized here so a
 * future addition has an obvious place to reserve its own offset instead of picking a number that
 * might collide.
 */
class RngStreams {
	// --- EvolutionEngine.step's three top-level decision axes (Part A) ---
	public static inline var SELECTION = 7; // EvolutionEngine's own pre-existing offset, preserved
	public static inline var CROSSOVER_CHOICE = 17;
	public static inline var MUTATE_CHOICE = 27;

	// --- pre-existing scattered offsets, formalized here under a name (values unchanged) ---
	public static inline var IMMIGRANT = 991; // CorpusEvoRun's MAP-Elites immigrant injection
	public static inline var HUMAN_LOOP_VARIATION = 5000; // HumanLoopWindow's own candidate-gen Variation

	// --- reserved for this session's 4 neuroevolution-inspired additions (Parts B-E) ---
	public static inline var SPECIES = 2001;
	public static inline var NOVELTY = 3001;
	public static inline var ES_NUDGE = 4001;
	public static inline var ES_CHOICE = 4011;
	public static inline var CURRICULUM = 5001;
	/** ε-lexicase case-order shuffle (`EvolutionEngine.lexicaseSelect` / `--lexicase`). */
	public static inline var LEXICASE = 6001;
	/** CVT centroid jitter reserved (Sobol centroids are deterministic; kept for future soft assign). */
	public static inline var CVT = 6101;
	/**
	 * Per-slot Variation stream for parallel child production (`Variation.forkForSlot`).
	 * Selection / crossover-choice / mutate-choice stay on their own streams (drawn serially in
	 * the planning phase); only growBool / site-pick / donor-sample draws move here, so enabling
	 * the AttrPool cannot perturb tournament order under `--seed`.
	 */
	public static inline var VARIATION_PARALLEL = 7001;
	/** Archipelago migration stream (`--deme-size`). */
	public static inline var DEME_MIGRATE = 7101;
	/** Rivalry arena cohort sampling / mid-arena retune choice (`--rivalry` / `--arena-every`). */
	public static inline var RIVALRY_ARENA = 7201;
	/** Foundry fork/consensus RNG (`--foundry-every`). */
	public static inline var FOUNDRY = 7301;
	/** Clone-vs-vary choice (`EvolutionEngine` / `--clone-prob`); only drawn when cloneProb > 0. */
	public static inline var CLONE_CHOICE = 7401;

	public static inline function stream(seed:Int, offset:Int):Rand return new Rand(seed + offset);
}
