package musescript.harness;

typedef OptimizeResult = {
	var bestParams:Map<String, Dynamic>;
	var bestMetric:Float;
	var trials:Int;
	/** Set when a `walkforward(...)` step gated this optimize — see WalkForwardResult.hx. */
	var ?walkForward:WalkForwardResult;
}
