package musescript.plan;

import musescript.ast.Expr;

/**
 * Muse discovery-process steps. P3 adds `ExecProfileStep` — the PlanStep TODO's execution-context
 * profiles, landed as a first-class step that PlanRunner/CorpusEvoRun can apply before work.
 *
 * «τέσσαρες ὁδοί· μία ψυχὴ βακχεύει.»
 */
enum PlanStep {
	SymbolSetStep(id:String, count:Int, seed:Null<Int>);
	FeatureSearchStep(id:String, candidates:Array<Dynamic>, scorer:String);
	OptimizeStep(id:String, target:String, params:Array<String>, method:String);
	TrainStep(id:String, model:String, features:Dynamic, trees:Int);
	DistillStep(id:String, fromId:String, into:String, params:Array<String>);
	StrategyStep(id:String, strategyRef:String);
	/** `walkforward(folds, ?embargo)` — the discovery-process gate, not a strategy backtest param. */
	WalkForwardStep(id:String, folds:Int, embargo:Int);
	/** `promote(fn(r) => ...)` — `cond` is the raw lambda AST; PlanRunner evaluates it against
	    the walk-forward's AGGREGATE out-of-sample metrics once folds are known, never earlier. */
	PromotionGateStep(id:String, cond:Expr);
	/** P3: pin the rest of the plan to an execution profile (backend × cache × attribution). */
	ExecProfileStep(id:String, profile:ExecutionProfileId);
}
