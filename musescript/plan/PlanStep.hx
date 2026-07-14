package musescript.plan;

enum PlanStep {
	SymbolSetStep(id:String, count:Int, seed:Null<Int>);
	FeatureSearchStep(id:String, candidates:Array<Dynamic>, scorer:String);
	OptimizeStep(id:String, target:String, params:Array<String>, method:String);
	TrainStep(id:String, model:String, features:Dynamic, trees:Int);
	DistillStep(id:String, fromId:String, into:String, params:Array<String>);
	StrategyStep(id:String, strategyRef:String);
}
