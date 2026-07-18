package musescript.plan;

import musescript.ast.Expr;

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
}
