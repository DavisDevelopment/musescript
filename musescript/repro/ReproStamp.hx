package musescript.repro;

/**
 * Seed-stamped run metadata (Initiative 4.2).
 *
 * Every backtest / optimization / Truth Report share should carry a stamp so a
 * later consumer can re-run to the bit. Defaults match CorpusEvoRun / GeneRunner
 * (`--seed 42`). Honesty Backtest (Initiative 1) can embed this under
 * `truthReport.repro` without inventing a parallel seed field.
 */
@:structInit
class ReproStamp {
	public static inline var SCHEMA = 1;
	public static inline var DEFAULT_SEED = 42;

	/** Primary experiment seed (evo / synth tape / DetRng hosts). */
	public var seed:Int;
	/** Block-bootstrap / rigor CI seed (defaults to `seed`). */
	public var bootSeed:Int;
	/** Execution profile label (`studio`, `ProductionRepro`, …). */
	public var profile:String;
	/** Engine that produced the curve: interp | js | wasm. */
	public var backend:String;
	public var schemaVersion:Int;

	public static function make(?opts:{
		?seed:Int,
		?bootSeed:Int,
		?profile:String,
		?backend:String
	}):ReproStamp {
		var seed = opts != null && opts.seed != null ? opts.seed : DEFAULT_SEED;
		var boot = opts != null && opts.bootSeed != null ? opts.bootSeed : seed;
		return {
			seed: seed,
			bootSeed: boot,
			profile: opts != null && opts.profile != null ? opts.profile : "studio",
			backend: opts != null && opts.backend != null ? opts.backend : "js",
			schemaVersion: SCHEMA
		};
	}

	/** Plain object for MuseRuntime / JSON / shareable Truth Reports. */
	public function toJson():Dynamic {
		return {
			schemaVersion: schemaVersion,
			seed: seed,
			bootSeed: bootSeed,
			profile: profile,
			backend: backend
		};
	}

	public function describe():String {
		return 'repro: seed=$seed bootSeed=$bootSeed profile=$profile backend=$backend v$schemaVersion';
	}
}
