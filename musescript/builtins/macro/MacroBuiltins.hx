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
		vars.set("tune", function(params:Array<Dynamic>) return tune(params));
		vars.set("sample", function(universe:Dynamic, n:Int, ?seed:Int) return sample(harness, universe, n, seed));
		vars.set("optimize", function(metric:Dynamic, ?over:Dynamic) return optimize(metric, over));
		vars.set("pickBest", function(candidates:Array<Dynamic>, fn:Dynamic->Dynamic) return pickBest(candidates, fn));
		vars.set("llm", {
			suggestEncodings: function(features:Array<String>, n:Int)
				return harness.llmSuggestEncodings(features, n)
		});
		vars.set("distill", function(model:Dynamic, ?into:Dynamic, ?params:Array<String>)
			return harness.distill(model, params != null ? params : []));
		vars.set("ensemble", function(?features:Dynamic, ?trees:Int) return ensemble(harness, features, trees));
		vars.set("DecisionTreeEnsemble", function(?features:Dynamic, ?trees:Int) return ensemble(harness, features, trees));
		vars.set("plan", function(body:Dynamic) return plan(body));
		vars.set("walkforward", function(folds:Int, ?embargo:Int) return walkforward(folds, embargo));
		vars.set("promote", function(fn:Dynamic) return promote(fn));
	}

	/**
	 * `walkforward(folds, ?embargo)` — AST marker declaring the discovery
	 * process's validation protocol: a `pipeline`'s `tune`/`optimize` runs
	 * per-fold on TRAIN only and is scored on TEST (out-of-sample), never
	 * the reverse. `embargo` bars are purged between train and test to
	 * avoid indicator-lookback leakage across the split. MusePlanner reads
	 * the real fold count/embargo off the parsed AST; PlanRunner does the
	 * actual splitting and per-fold search.
	 */
	public static function walkforward(folds:Int, ?embargo:Int):Dynamic {
		return { __macro: "walkforward", folds: folds, embargo: embargo != null ? embargo : 0 };
	}

	/**
	 * `promote(fn(r) => ...)` — AST marker declaring the promotion gate: a
	 * boolean predicate over the walk-forward's AGGREGATE out-of-sample
	 * metrics (`r.sharpe`, `r.maxDrawdown`, `r.winRate`, `r.finalEquity`,
	 * `r.trades`). PlanRunner evaluates it once folds are known — never
	 * against in-sample numbers, and never before every fold has run.
	 */
	public static function promote(fn:Dynamic):Dynamic {
		return { __macro: "promote", fn: fn };
	}

	/** `tune(params)` — AST marker; MusePlanner reads the real tune spec off the parsed AST. */
	public static function tune(params:Array<Dynamic>):Dynamic {
		return { __macro: "tune", params: params };
	}

	/** `optimize(metric, ?over)` — AST marker; the plan's optimize stage comes from MusePlanner. */
	public static function optimize(metric:Dynamic, ?over:Dynamic):Dynamic {
		return { __macro: "optimize", metric: metric, over: over };
	}

	/** `plan(body)` — AST marker wrapping a macro body for inspection/replay. */
	public static function plan(body:Dynamic):Dynamic {
		return { __macro: "plan", body: body };
	}

	/**
	 * `sample(universe, n, ?seed)` — n symbols from an explicit SymbolUniverse
	 * or the harness's ambient universe. Errors clearly when neither exists
	 * (previously: null-pointer deep inside universe.sample).
	 */
	public static function sample(harness:IHarness, universe:Dynamic, n:Int, ?seed:Int):Dynamic {
		if (Std.isOfType(universe, musescript.harness.SymbolUniverse))
			return cast(universe, musescript.harness.SymbolUniverse).sample(n, seed);
		if (harness.universe == null)
			throw "sample: no symbol universe attached to this harness (pass one explicitly)";
		return harness.universe.sample(n, seed);
	}

	/**
	 * `pickBest(candidates, fn)` — run `fn` over each candidate, return the
	 * result with the highest numeric `score` field (annotated with
	 * `__pickBestScore`). Null/empty candidate lists return null instead of
	 * crashing; a result without a `score` field counts as 0.
	 */
	public static function pickBest(candidates:Array<Dynamic>, fn:Dynamic->Dynamic):Dynamic {
		if (candidates == null || fn == null) return null;
		var best:Dynamic = null;
		var bestScore = Math.NEGATIVE_INFINITY;
		for (c in candidates) {
			var r = fn(c);
			if (r == null) continue;
			var raw:Dynamic = Reflect.hasField(r, "score") ? Reflect.field(r, "score") : 0;
			var score:Float = Std.isOfType(raw, Float) || Std.isOfType(raw, Int) ? (raw : Float) : 0;
			if (Math.isNaN(score)) continue;
			if (score > bestScore) {
				bestScore = score;
				best = r;
			}
		}
		if (best != null && Reflect.isObject(best))
			Reflect.setField(best, "__pickBestScore", bestScore);
		return best;
	}

	/** `ensemble(?features, ?trees)` — decision-tree ensemble via the harness (default 100 trees). */
	public static function ensemble(harness:IHarness, ?features:Dynamic, ?trees:Int):Dynamic {
		return harness.ensemble(features, trees != null ? trees : 100);
	}
}
