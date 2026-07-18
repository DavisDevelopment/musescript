package musescript.plan;

class MuseIR {
	public static function empty(?origin:String):ExecutionPlan {
		return { steps: [], sourceOrigin: origin };
	}

	public static function toJson(plan:ExecutionPlan):String {
		var steps:Array<Dynamic> = [];
		for (s in plan.steps) {
			var obj:Dynamic = switch (s) {
				case SymbolSetStep(id, count, seed):
					{ kind: "SymbolSet", id: id, count: count, seed: seed };
				case FeatureSearchStep(id, candidates, scorer):
					{ kind: "FeatureSearch", id: id, candidates: candidates, scorer: scorer };
				case OptimizeStep(id, target, params, method):
					{ kind: "Optimize", id: id, target: target, params: params, method: method };
				case TrainStep(id, model, features, trees):
					{ kind: "Train", id: id, model: model, features: features, trees: trees };
				case DistillStep(id, fromId, into, params):
					{ kind: "Distill", id: id, from: fromId, into: into, params: params };
				case StrategyStep(id, ref):
					{ kind: "Strategy", id: id, ref: ref };
				case WalkForwardStep(id, folds, embargo):
					{ kind: "WalkForward", id: id, folds: folds, embargo: embargo };
				case PromotionGateStep(id, cond):
					{ kind: "PromotionGate", id: id, cond: musescript.ast.MuseAstJson.exprToJson(cond) };
			};
			steps.push(obj);
		}
		return haxe.Json.stringify({ origin: plan.sourceOrigin, steps: steps });
	}
}
