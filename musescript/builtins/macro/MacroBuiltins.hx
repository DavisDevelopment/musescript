package musescript.builtins.macro;

import musescript.harness.IHarness;
import musescript.plan.MuseIR;

/**
 * Macro-phase builtins for PlannerInterp / discovery macros.
 *
 * Two roles:
 * - **AST markers** (`tune`, `optimize`, `plan`): return `{ __macro: ... }` objects so macro
 *   bodies can be inspected or replayed without running PlanRunner. MusePlanner extracts the
 *   real ExecutionPlan from the parsed AST, not from these runtime values.
 * - **Execution helpers** (`sample`, `pickBest`, `llm`, `ensemble`, `distill`): perform work
 *   when a macro block is interpreted directly. PlanRunner executes the richer plan produced
 *   by MusePlanner via `bindProgram` / `optimize` / `run`.
 */
class MacroBuiltins {
	public static function install(vars:Map<String, Dynamic>, harness:IHarness):Void {
		vars.set("tune", function(params:Array<Dynamic>) {
			return { __macro: "tune", params: params };
		});
		vars.set("sample", function(universe:Dynamic, n:Int, ?seed:Int) {
			if (Std.isOfType(universe, musescript.harness.SymbolUniverse)) {
				return cast(universe, musescript.harness.SymbolUniverse).sample(n, seed);
			}
			return harness.universe.sample(n, seed);
		});
		vars.set("optimize", function(metric:Dynamic, ?over:Dynamic) {
			return { __macro: "optimize", metric: metric, over: over };
		});
		vars.set("pickBest", function(candidates:Array<Dynamic>, fn:Dynamic->Dynamic) {
			var best = null;
			var bestScore = Math.NEGATIVE_INFINITY;
			for (c in candidates) {
				var r = fn(c);
				var score = Reflect.hasField(r, "score") ? Reflect.field(r, "score") : 0;
				if (score > bestScore) {
					bestScore = score;
					best = r;
				}
			}
			if (best != null && Reflect.isObject(best)) {
				Reflect.setField(best, "__pickBestScore", bestScore);
			}
			return best;
		});
		vars.set("llm", {
			suggestEncodings: function(features:Array<String>, n:Int) {
				return harness.llmSuggestEncodings(features, n);
			}
		});
		vars.set("distill", function(model:Dynamic, ?into:Dynamic, ?params:Array<String>) {
			return harness.distill(model, params != null ? params : []);
		});
		vars.set("ensemble", function(?features:Dynamic, ?trees:Int) {
			return harness.ensemble(features, trees != null ? trees : 100);
		});
		vars.set("DecisionTreeEnsemble", function(?features:Dynamic, ?trees:Int) {
			return harness.ensemble(features, trees != null ? trees : 100);
		});
		vars.set("plan", function(body:Dynamic) {
			return { __macro: "plan", body: body };
		});
	}
}
