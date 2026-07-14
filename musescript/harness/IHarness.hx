package musescript.harness;

import musescript.plan.ExecutionPlan;

interface IHarness {
	var universe:SymbolUniverse;
	var params:ParamRegistry;
	var indicators:IndicatorRegistry;
	var chart:ChartSink;
	function runBacktest(onBar:Bar->Void, feed:BarFeed):BacktestResult;
	function optimize(plan:ExecutionPlan, metric:String):OptimizeResult;
	function llmSuggestEncodings(features:Array<String>, n:Int):Array<Dynamic>;
	function distill(model:Dynamic, params:Array<String>):Dynamic;
	function ensemble(features:Dynamic, trees:Int):Dynamic;
}
