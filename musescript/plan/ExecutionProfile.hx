package musescript.plan;

/**
 * Execution-Profile Planner (spec §4): named bundles of backend × caching × attribution
 * fidelity. Resolved onto `ExecutionPlan.profile` and applied by CorpusEvoRun / PlanRunner.
 *
 * When `preferNma` is true the effective fitness backend is always JS (NMA strangler + OrderSim
 * floor live there) — profile `backend` is therefore `"js"` for those profiles, not `"wasm"`.
 *
 * «τέσσαρες ὁδοί· μία ψυχὴ βακχεύει.»
 */
@:structInit
class ExecutionProfile {
	public var id:ExecutionProfileId;
	/** Prefer NMA columnar fitness when genome is pure market-data. */
	public var preferNma:Bool;
	/** Disable Fitness.fnCache / EvoCache for reproducibility. */
	public var cachesOff:Bool;
	/** Attribution / triage on a prefix rather than full IS tape. */
	public var prefixAttribution:Bool;
	/** Backend hint for PlanRunner bindCompiled / non-NMA paths: "wasm" | "js" | "interp". */
	public var backend:String;
	/** Human label for logs. */
	public var label:String;

	public static function resolve(id:ExecutionProfileId):ExecutionProfile {
		return switch (id) {
			case SingleStrategyMaxThroughput: {
				// Prefer NMA when possible; JS is the honest backend for that strangler.
				id: id, preferNma: true, cachesOff: false, prefixAttribution: false,
				backend: "js", label: "SingleStrategyMaxThroughput"
			};
			case EvoMinWallclock: {
				id: id, preferNma: true, cachesOff: false, prefixAttribution: true,
				backend: "js", label: "EvoMinWallclock"
			};
			case ProductionRepro: {
				id: id, preferNma: false, cachesOff: true, prefixAttribution: false,
				backend: "interp", label: "ProductionRepro"
			};
			case MobileWeb: {
				id: id, preferNma: false, cachesOff: false, prefixAttribution: true,
				backend: "js", label: "MobileWeb"
			};
		};
	}

	public static function parse(name:String):Null<ExecutionProfileId> {
		if (name == null) return null;
		return switch (name.toLowerCase()) {
			case "single" | "throughput" | "singlestrategymaxthroughput": SingleStrategyMaxThroughput;
			case "evo" | "evominwallclock" | "search": EvoMinWallclock;
			case "prod" | "production" | "productionrepro" | "repro": ProductionRepro;
			case "mobile" | "web" | "mobileweb": MobileWeb;
			default: null;
		};
	}

	/** Apply Fitness / NMA control-plane knobs from this profile (idempotent OR into flags). */
	public function applyToFitness():Void {
		if (preferNma) musescript.evo.Fitness.preferNma = true;
	}
}
