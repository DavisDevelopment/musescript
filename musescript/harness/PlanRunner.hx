package musescript.harness;

import musescript.ast.MuseProgram;
import musescript.interp.MuseInterp;
import musescript.plan.ExecutionPlan;
import musescript.plan.PlanStep;

/**
 * Execute ExecutionPlan steps against IHarness.
 *
 * Optimization requires a strategy callback or bound program before run()/optimize():
 *   runner.setStrategy(onBar, feed)     — raw bar handler
 *   runner.bindProgram(prog, feed)      — MuseInterp backtest per trial
 *   runner.bindCompiled(prog, feed)     — MuseCompiler once; reuse per trial
 */
class PlanRunner {
	static inline var MAX_TRIALS = 500;

	var harness:HarnessContext;
	var onBar:Null<Bar->Void>;
	var feed:Null<BarFeed>;
	var prog:Null<MuseProgram>;
	var interp:Null<MuseInterp>;
	var compiled:Null<musescript.BarStrategyFn>;

	public function new(harness:HarnessContext) {
		this.harness = harness;
	}

	/** Wire a raw onBar handler + feed for optimize backtests. */
	public function setStrategy(onBar:Bar->Void, feed:BarFeed):PlanRunner {
		this.onBar = onBar;
		this.feed = feed;
		this.prog = null;
		this.interp = null;
		this.compiled = null;
		return this;
	}

	/** Bind a parsed MuseProgram; each trial re-runs via MuseInterp (params preserved). */
	public function bindProgram(prog:MuseProgram, ?feed:BarFeed):PlanRunner {
		this.prog = prog;
		this.feed = feed != null ? feed : BarFeed.synthetic(300, 1);
		this.interp = new MuseInterp(harness);
		this.onBar = null;
		this.compiled = null;
		return this;
	}

	/**
	 * Compile once with MuseCompiler (js/wasm), reuse the BarStrategyFn every trial.
	 * Falls back to bindProgram behavior when emission fails (unless strict).
	 */
	public function bindCompiled(prog:MuseProgram, ?feed:BarFeed, ?opts:{?target:String, ?strict:Bool}):PlanRunner {
		this.prog = prog;
		this.feed = feed != null ? feed : BarFeed.synthetic(300, 1);
		this.interp = null;
		this.onBar = null;
		var target = opts != null && opts.target != null ? opts.target : "js";
		var strict = opts != null && opts.strict == true;
		var ex = musescript.compile.MuseCompiler.compileEx(prog, { target: target, strict: strict });
		this.compiled = ex.fn;
		return this;
	}

	public function run(plan:ExecutionPlan):Map<String, Dynamic> {
		var results = new Map<String, Dynamic>();
		var lastModel:Dynamic = null;
		for (step in plan.steps) {
			switch (step) {
				case SymbolSetStep(id, count, seed):
					var syms = harness.universe.sample(count, seed);
					results.set(id, syms);
				case FeatureSearchStep(id, candidates, scorer):
					var feats = candidates.length > 0
						? candidates
						: harness.llmSuggestEncodings(["close", "volume", "rsi"], 5);
					var best = feats[0];
					var bestScore = Math.NEGATIVE_INFINITY;
					for (f in feats) {
						var score = scoreEncoding(f, scorer);
						if (score > bestScore) {
							bestScore = score;
							best = f;
						}
					}
					results.set(id, best);
				case OptimizeStep(id, target, paramNames, method):
					var opt = optimizeStep(target, paramNames, method, plan);
					results.set(id, opt);
					for (k => v in opt.bestParams) harness.params.set(k, v);
				case TrainStep(id, model, features, trees):
					lastModel = harness.ensemble(features, trees);
					results.set(id, lastModel);
				case DistillStep(id, fromId, into, params):
					var model = results.exists(fromId) ? results.get(fromId) : lastModel;
					results.set(id, harness.distill(model, params));
				case StrategyStep(id, ref):
					results.set(id, { strategy: ref });
			}
		}
		return results;
	}

	public function optimize(plan:ExecutionPlan, metric:String):OptimizeResult {
		var paramNames:Array<String> = [];
		var method = "grid";
		for (step in plan.steps) {
			switch (step) {
				case OptimizeStep(_, target, ps, m):
					paramNames = ps;
					method = m;
				default:
			}
		}
		return optimizeStep(metric, paramNames, method, plan);
	}

	function optimizeStep(metric:String, paramNames:Array<String>, method:String, plan:ExecutionPlan):OptimizeResult {
		var names = resolveParamNames(paramNames, plan);
		var bestMetric = Math.NEGATIVE_INFINITY;
		var bestParams = snapshotParams(names);
		var trials = 0;

		if (names.length == 0 || !canEvaluate()) {
			return { bestParams: bestParams, bestMetric: 0, trials: 0 };
		}

		var baseline = snapshotParams(names);
		var combos = buildTrials(names, baseline, method);

		for (combo in combos) {
			applyParams(combo);
			var result = evaluateCandidate();
			var score = scoreMetric(result, metric);
			trials++;
			if (score > bestMetric) {
				bestMetric = score;
				bestParams = snapshotParams(names);
			}
		}

		applyParams(bestParams);
		return { bestParams: bestParams, bestMetric: bestMetric, trials: trials };
	}

	function canEvaluate():Bool {
		return (onBar != null && feed != null)
			|| (compiled != null && feed != null)
			|| (prog != null && interp != null && feed != null);
	}

	function evaluateCandidate():BacktestResult {
		harness.resetForTrial();
		if (onBar != null && feed != null) return harness.runBacktest(onBar, feed);
		if (compiled != null && feed != null) {
			Reflect.setField(harness, "feed", feed);
			return cast compiled(harness);
		}
		if (prog != null && interp != null && feed != null) return interp.runBacktest(prog, feed);
		throw "PlanRunner: call setStrategy / bindProgram / bindCompiled before optimize()";
	}

	function resolveParamNames(explicit:Array<String>, plan:ExecutionPlan):Array<String> {
		if (explicit.length > 0) return explicit;
		var fromPlan:Array<String> = [];
		for (step in plan.steps) {
			switch (step) {
				case OptimizeStep(_, _, ps, _):
					if (ps.length > 0) fromPlan = ps;
				default:
			}
		}
		if (fromPlan.length > 0) return fromPlan;
		var out:Array<String> = [];
		for (name in harness.params.names()) {
			var o = harness.params.getOpts(name);
			if (o != null && o.min != null && o.max != null) out.push(name);
		}
		return out;
	}

	function gridValues(name:String):Array<Float> {
		var o = harness.params.getOpts(name);
		var cur = harness.params.get(name);
		var min = o != null && o.min != null ? o.min : asFloat(cur) - 5;
		var max = o != null && o.max != null ? o.max : asFloat(cur) + 5;
		var step = o != null && o.step != null && o.step > 0 ? o.step : 1;
		var out:Array<Float> = [];
		var v = min;
		while (v <= max + 1e-9) {
			out.push(v);
			v += step;
		}
		return out.length > 0 ? out : [asFloat(cur)];
	}

	/**
	 * Full cartesian grid when product <= MAX_TRIALS; otherwise coordinate-wise sweeps
	 * (one param varied at a time from baseline) capped at MAX_TRIALS.
	 */
	function buildTrials(names:Array<String>, baseline:Map<String, Dynamic>, method:String):Array<Map<String, Dynamic>> {
		var grids:Array<{name:String, values:Array<Float>}> = [];
		for (name in names) grids.push({ name: name, values: gridValues(name) });

		var product = 1;
		for (g in grids) product *= g.values.length;

		if (method != "grid") {
			return coordinateTrials(grids, baseline);
		}
		if (product <= MAX_TRIALS) {
			return cartesianTrials(grids, 0, baseline, new Map());
		}
		return coordinateTrials(grids, baseline);
	}

	function cartesianTrials(
		grids:Array<{name:String, values:Array<Float>}>,
		idx:Int,
		baseline:Map<String, Dynamic>,
		partial:Map<String, Dynamic>
	):Array<Map<String, Dynamic>> {
		if (idx >= grids.length) return [mergeParams(baseline, partial)];
		var out:Array<Map<String, Dynamic>> = [];
		var g = grids[idx];
		for (v in g.values) {
			partial.set(g.name, v);
			out = out.concat(cartesianTrials(grids, idx + 1, baseline, partial));
		}
		partial.remove(g.name);
		return out;
	}

	function coordinateTrials(grids:Array<{name:String, values:Array<Float>}>, baseline:Map<String, Dynamic>):Array<Map<String, Dynamic>> {
		var out:Array<Map<String, Dynamic>> = [];
		out.push(copyMap(baseline));
		for (g in grids) {
			for (v in g.values) {
				var t = copyMap(baseline);
				t.set(g.name, v);
				out.push(t);
				if (out.length >= MAX_TRIALS) return out;
			}
		}
		return out;
	}

	function scoreMetric(result:BacktestResult, metric:String):Float {
		return switch (metric) {
			case "sharpe": result.sharpe;
			case "maxDrawdown": -result.maxDrawdown;
			case "winRate": result.winRate;
			case "finalEquity": result.finalEquity;
			default: result.sharpe;
		};
	}

	function scoreEncoding(enc:Dynamic, _scorer:String):Float {
		if (Reflect.hasField(enc, "score")) return asFloat(Reflect.field(enc, "score"));
		var featCount = 1.0;
		if (Reflect.hasField(enc, "features") && enc.features != null) {
			featCount = (cast enc.features : Array<Dynamic>).length;
		}
		var methodBonus = 0.0;
		if (Reflect.hasField(enc, "method")) {
			methodBonus = switch (Std.string(Reflect.field(enc, "method"))) {
				case "zscore": 0.05;
				case "rank": 0.04;
				case "returns": 0.045;
				case "diff": 0.035;
				case "rolling_mean": 0.03;
				default: 0.02;
			};
		}
		var tag = Reflect.hasField(enc, "name") ? Std.string(Reflect.field(enc, "name")) : "";
		var hash = 0.0;
		for (i in 0...tag.length) hash += tag.charCodeAt(i);
		return featCount + methodBonus + hash * 1e-6;
	}

	function snapshotParams(names:Array<String>):Map<String, Dynamic> {
		var m = new Map<String, Dynamic>();
		for (n in names) m.set(n, harness.params.get(n));
		return m;
	}

	function applyParams(combo:Map<String, Dynamic>):Void {
		for (k => v in combo) harness.params.set(k, v);
	}

	function mergeParams(base:Map<String, Dynamic>, overlay:Map<String, Dynamic>):Map<String, Dynamic> {
		var m = copyMap(base);
		for (k => v in overlay) m.set(k, v);
		return m;
	}

	function copyMap(src:Map<String, Dynamic>):Map<String, Dynamic> {
		var m = new Map<String, Dynamic>();
		for (k => v in src) m.set(k, v);
		return m;
	}

	function asFloat(v:Dynamic):Float {
		if (v == null) return 0;
		if (Std.isOfType(v, Int)) return cast v;
		if (Std.isOfType(v, Float)) return cast v;
		return Std.parseFloat(Std.string(v));
	}
}
