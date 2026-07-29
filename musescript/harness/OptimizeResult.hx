package musescript.harness;

typedef OptimizeResult = {
	var bestParams:Map<String, Dynamic>;
	var bestMetric:Float;
	var trials:Int;
	/** Set when a `walkforward(...)` step gated this optimize — see WalkForwardResult.hx. */
	var ?walkForward:WalkForwardResult;
	/** Initiative 4.2 — seed that stamped this search (PlanRunner.seed; default 42). */
	var ?seed:Int;
	/** Initiative 4.2 — `ReproStamp.toJson()` for shareable / re-runnable reports. */
	var ?repro:Dynamic;
}
