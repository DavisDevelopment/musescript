package musescript.harness;

import musescript.ast.MuseProgram;
import musescript.ast.Expr;
import musescript.interp.MuseInterp;
import musescript.plan.ExecutionPlan;
import musescript.plan.ExecutionProfile;
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
	/** Initiative 4.2 — stamped onto every OptimizeResult (default matches CLI `--seed`). */
	public var seed:Int = musescript.repro.ReproStamp.DEFAULT_SEED;

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
					var opt = optimize(plan, target);
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
				case WalkForwardStep(id, folds, embargo):
					results.set(id, { folds: folds, embargo: embargo });
				case PromotionGateStep(id, _):
					// Consumed by optimize()/walkForwardOptimize() when it scans the plan for a
					// preceding WalkForwardStep — nothing to do standalone here.
				case ExecProfileStep(id, profile):
					plan.profile = ExecutionProfile.resolve(profile);
					plan.profile.applyToFitness();
					#if sys
					Sys.println('exec-profile: ${plan.profile.label} backend=${plan.profile.backend} (step $id)');
					#end
					// Rebind compiled strategy to the profile backend when we already have a program.
					if (prog != null && feed != null) {
						var be = plan.profile.backend;
						if (be == "js" || be == "wasm")
							bindCompiled(prog, feed, { target: be, strict: false });
						else if (be == "interp")
							bindProgram(prog, feed);
					}
			}
		}
		return results;
	}

	public function optimize(plan:ExecutionPlan, metric:String):OptimizeResult {
		var paramNames:Array<String> = [];
		var method = "grid";
		var wfFolds:Null<Int> = null;
		var wfEmbargo = 0;
		var promoteCond:Null<Expr> = null;
		for (step in plan.steps) {
			switch (step) {
				case OptimizeStep(_, target, ps, m):
					paramNames = ps;
					method = m;
				case WalkForwardStep(_, folds, embargo):
					wfFolds = folds;
					wfEmbargo = embargo;
				case PromotionGateStep(_, cond):
					promoteCond = cond;
				default:
			}
		}
		if (wfFolds != null)
			return walkForwardOptimize(metric, paramNames, method, wfFolds, wfEmbargo, promoteCond, plan);
		return optimizeStep(metric, paramNames, method, plan);
	}

	/**
	 * Initiative 3 — enumerate every optimize trial (params + backtest) without picking a winner.
	 * Used by `HonestOptimize` so each candidate can be Truth-Report-gated.
	 */
	public function trialSweep(plan:ExecutionPlan, metric:String):Array<OptimizeTrial> {
		var paramNames:Array<String> = [];
		var method = "grid";
		for (step in plan.steps) {
			switch (step) {
				case OptimizeStep(_, _, ps, m):
					paramNames = ps;
					method = m;
				default:
			}
		}
		return evaluateTrials(metric, paramNames, method, plan);
	}

	/**
	 * The `pipeline` walk-forward primitive's real execution: split the bound
	 * feed into `folds` expanding-window train/test splits (an `embargo`-bar
	 * gap purged between each split's train end and test start, guarding
	 * against indicator-lookback leakage across the boundary — same
	 * discipline as OrderBook's next-bar-only fills, applied to search
	 * instead of fills). Each fold's grid/coordinate search runs ONLY against
	 * TRAIN; the winning params are then measured ONCE against TEST
	 * (out-of-sample) — the search never sees its own scoring data. Folds
	 * with too little data on either side are skipped honestly rather than
	 * padded or faked; if every fold is skipped, returns NaN/null the same
	 * way `optimizeStep`'s "could not search" path does.
	 *
	 * `promoteCond`, if given, is evaluated exactly once against the
	 * AGGREGATE (mean-across-folds) out-of-sample metrics — never against
	 * any single fold, and never against the in-sample numbers.
	 */
	function walkForwardOptimize(
		metric:String, explicitParams:Array<String>, method:String,
		folds:Int, embargo:Int, promoteCond:Null<Expr>, plan:ExecutionPlan
	):OptimizeResult {
		var names = resolveParamNames(explicitParams, plan);
		if (names.length == 0 || !canEvaluate() || feed == null || folds < 1)
			return stampOpt({ bestParams: snapshotParams(names), bestMetric: Math.NaN, trials: 0 });

		var allBars = feed.all();
		var n = allBars.length;
		var segSize = Std.int(n / (folds + 1));
		var foldResults:Array<musescript.harness.WalkForwardResult.WalkForwardFoldResult> = [];
		var lastBestParams = snapshotParams(names);

		for (i in 0...folds) {
			var testStart = (i + 1) * segSize;
			var testEnd = (i == folds - 1) ? n : testStart + segSize;
			var trainEnd = testStart - embargo;
			// Honest skip, not a padded/fabricated fold: too little data on either side.
			if (trainEnd < 20 || testEnd - testStart < 5) continue;

			var trainFeed = new BarFeed(allBars.slice(0, trainEnd));
			var testFeed = new BarFeed(allBars.slice(testStart, testEnd));

			var baseline = snapshotParams(names);
			var combos = buildTrials(names, baseline, method);
			var bestMetric = Math.NEGATIVE_INFINITY;
			var bestParams = baseline;
			for (combo in combos) {
				applyParams(combo);
				var score = scoreMetric(evaluateCandidateAgainst(trainFeed), metric);
				if (score > bestMetric) {
					bestMetric = score;
					bestParams = snapshotParams(names);
				}
			}

			applyParams(bestParams);
			var oos = evaluateCandidateAgainst(testFeed);
			lastBestParams = bestParams;

			foldResults.push({
				trainBars: trainEnd, testBars: testEnd - testStart, bestParams: bestParams,
				oosSharpe: oos.sharpe, oosMaxDrawdown: oos.maxDrawdown,
				oosWinRate: oos.winRate, oosFinalEquity: oos.finalEquity, oosTrades: oos.trades
			});
		}

		applyParams(lastBestParams);
		if (foldResults.length == 0)
			return stampOpt({ bestParams: lastBestParams, bestMetric: Math.NaN, trials: 0 });

		var aggSharpe = meanOf([for (f in foldResults) f.oosSharpe]);
		var aggDD = meanOf([for (f in foldResults) f.oosMaxDrawdown]);
		var aggWin = meanOf([for (f in foldResults) f.oosWinRate]);
		var aggEq = meanOf([for (f in foldResults) f.oosFinalEquity]);

		var promoted:Null<Bool> = promoteCond != null
			? evalPromotionGate(promoteCond, {
				sharpe: aggSharpe, maxDrawdown: aggDD, winRate: aggWin,
				finalEquity: aggEq, trades: foldResults.length
			})
			: null;

		return stampOpt({
			bestParams: lastBestParams,
			bestMetric: aggSharpe,
			trials: foldResults.length,
			walkForward: {
				folds: foldResults, aggregateSharpe: aggSharpe, aggregateMaxDrawdown: aggDD,
				aggregateWinRate: aggWin, aggregateFinalEquity: aggEq, promoted: promoted
			}
		});
	}

	/** Materializes and calls `cond` (a `fn(r) => ...` lambda AST) against `metrics`. */
	function evalPromotionGate(cond:Expr, metrics:Dynamic):Bool {
		var pi = new MuseInterp(harness);
		if (prog != null) for (d in prog.decls) pi.registerDeclPublic(d);
		var closure = pi.evalExpr(cond);
		return pi.callValue(closure, [metrics]) == true;
	}

	function meanOf(xs:Array<Float>):Float {
		if (xs.length == 0) return Math.NaN;
		var s = 0.0;
		for (x in xs) s += x;
		return s / xs.length;
	}

	function optimizeStep(metric:String, paramNames:Array<String>, method:String, plan:ExecutionPlan):OptimizeResult {
		var names = resolveParamNames(paramNames, plan);
		var bestParams = snapshotParams(names);
		if (names.length == 0 || !canEvaluate()) {
			// Honest "could not search" — not a zero-sharpe result.
			return stampOpt({ bestParams: bestParams, bestMetric: Math.NaN, trials: 0 });
		}
		var trials = evaluateTrials(metric, paramNames, method, plan);
		var bestMetric = Math.NEGATIVE_INFINITY;
		for (t in trials) {
			if (t.score > bestMetric) {
				bestMetric = t.score;
				bestParams = t.params;
			}
		}
		applyParams(bestParams);
		return stampOpt({ bestParams: bestParams, bestMetric: bestMetric, trials: trials.length });
	}

	function evaluateTrials(metric:String, paramNames:Array<String>, method:String, plan:ExecutionPlan):Array<OptimizeTrial> {
		var out:Array<OptimizeTrial> = [];
		var names = resolveParamNames(paramNames, plan);
		if (names.length == 0 || !canEvaluate()) return out;
		var baseline = snapshotParams(names);
		var combos = buildTrials(names, baseline, method);
		for (combo in combos) {
			applyParams(combo);
			var result = evaluateCandidate();
			out.push({
				params: snapshotParams(names),
				result: result,
				score: scoreMetric(result, metric)
			});
		}
		return out;
	}

	function canEvaluate():Bool {
		return (onBar != null && feed != null)
			|| (compiled != null && feed != null)
			|| (prog != null && interp != null && feed != null);
	}

	function evaluateCandidate():BacktestResult {
		if (feed == null) throw "PlanRunner: call setStrategy / bindProgram / bindCompiled before optimize()";
		return evaluateCandidateAgainst(feed);
	}

	/** Same as evaluateCandidate() but against an arbitrary feed — the walk-forward
	    train/test splits are never the feed this instance was bound with. */
	function evaluateCandidateAgainst(f:BarFeed):BacktestResult {
		harness.resetForTrial();
		if (onBar != null) return harness.runBacktest(onBar, f);
		if (compiled != null) {
			harness.feed = f;
			return cast compiled(harness);
		}
		if (prog != null && interp != null) return interp.runBacktest(prog, f);
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
		// Explicit discrete list wins over any min/max/step -- the only way to sweep a NON-uniform
		// set (e.g. Fibonacci window lengths 8,13,21,34) that no fixed step can express.
		if (o != null && o.values != null && o.values.length > 0) return o.values.copy();
		var cur = asFloat(harness.params.get(name));
		var curInt = Std.int(Math.round(cur));
		var windowish = musescript.types.MuseTypes.isWindow(curInt)
			|| name == "fast" || name == "slow" || name == "look"
			|| (o != null && o.tune != null && musescript.types.MuseTypes.isWindow(curInt));

		// Window params: stay on the Fib ladder (checker rejects off-ladder literals).
		if (windowish) {
			var lo = o != null && o.min != null ? o.min : 5;
			var hi = o != null && o.max != null ? o.max : 55;
			var out:Array<Float> = [];
			for (w in musescript.types.MuseTypes.WINDOW_LADDER) {
				if (w >= lo - 1e-9 && w <= hi + 1e-9) out.push(w);
			}
			if (out.length > 0) return out;
		}

		var min = o != null && o.min != null ? o.min : cur - 5;
		var max = o != null && o.max != null ? o.max : cur + 5;
		var step = o != null && o.step != null && o.step > 0 ? o.step : 1;
		var out:Array<Float> = [];
		var v = min;
		while (v <= max + 1e-9) {
			out.push(v);
			v += step;
		}
		return out.length > 0 ? out : [cur];
	}

	/**
	 * Full cartesian grid when product <= MAX_TRIALS; otherwise coordinate-wise sweeps
	 * (one param varied at a time from baseline) capped at MAX_TRIALS.
	 */
	function buildTrials(names:Array<String>, baseline:Map<String, Dynamic>, method:String):Array<Map<String, Dynamic>> {
		if (method != "grid" && method != "coordinate")
			throw 'PlanRunner: unknown search method "$method" (expected grid/coordinate)';
		var grids:Array<{name:String, values:Array<Float>}> = [];
		for (name in names) grids.push({ name: name, values: gridValues(name) });

		var product = 1;
		for (g in grids) product *= g.values.length;

		if (method == "coordinate") {
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
			default:
				throw 'PlanRunner: unknown optimize metric "$metric" (expected sharpe/maxDrawdown/winRate/finalEquity)';
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

	/** Attach Initiative 4.2 seed stamp without changing search semantics. */
	function stampOpt(r:OptimizeResult):OptimizeResult {
		r.seed = seed;
		r.repro = musescript.repro.ReproStamp.make({
			seed: seed,
			bootSeed: seed,
			profile: "plan",
			backend: compiled != null ? "js" : (interp != null ? "interp" : "harness")
		}).toJson();
		return r;
	}
}
