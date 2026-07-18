package musescript.harness;

/** One walk-forward fold: params picked on TRAIN, metrics measured on TEST (out-of-sample). */
typedef WalkForwardFoldResult = {
	var trainBars:Int;
	var testBars:Int;
	var bestParams:Map<String, Dynamic>;
	var oosSharpe:Float;
	var oosMaxDrawdown:Float;
	var oosWinRate:Float;
	var oosFinalEquity:Float;
	var oosTrades:Int;
}

/**
 * Result of a `pipeline`'s `walkforward(...)`-gated `tune`/`optimize` — the
 * language-level walk-forward primitive (ROADMAP.md pipeline construct).
 * `promoted` is null when no `promote(...)` gate was declared (search ran,
 * nobody asked for a verdict); true/false when one was, and is evaluated
 * against the AGGREGATE out-of-sample metrics, never in-sample ones.
 */
typedef WalkForwardResult = {
	var folds:Array<WalkForwardFoldResult>;
	var aggregateSharpe:Float;
	var aggregateMaxDrawdown:Float;
	var aggregateWinRate:Float;
	var aggregateFinalEquity:Float;
	var promoted:Null<Bool>;
}
