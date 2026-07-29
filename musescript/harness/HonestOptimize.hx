package musescript.harness;

import musescript.ast.MuseProgram;
import musescript.evo.rigor.TruthReport;
import musescript.evo.rigor.TruthVerdict;
import musescript.evo.rigor.TrialsSession;
import musescript.interp.MuseInterp;
import musescript.plan.ExecutionPlan;
import musescript.plan.MusePlanner;
import musescript.plan.PlanStep;
import musescript.repro.ReproStamp;

/**
 * Initiative 3 — honesty-gated strategy optimizer.
 *
 * Searches `@param` / `tune`/`optimize` holes via PlanRunner trial sweeps, then
 * surfaces ONLY candidates that pass TruthReport (non-overfit). An empty result
 * ("no robust strategy found" / "nothing beat the null") is a feature.
 */
class HonestOptimize {
	/** Default: non-overfit survivors (Robust + Fragile). Overfit / Coin-flip never ship. */
	public static var DEFAULT_ACCEPT:Array<String> = [
		TruthVerdict.Robust,
		TruthVerdict.Fragile
	];

	/**
	 * Search tunable params on `source` over `bars`.
	 * Returns a plain JS-safe object (never throws):
	 *   { ok, found, reason?, trials, survivors, rejected, anyBeatsNull,
	 *     best?: { params, metric, sharpe, trades, truthReport },
	 *     acceptVerdicts, seed, repro, message }
	 */
	public static function search(source:String, bars:Array<Bar>, ?opts:Dynamic):Dynamic {
		var seed = optInt(opts, "seed", ReproStamp.DEFAULT_SEED);
		var initialCash = optFloat(opts, "initialCash", 100000);
		var metric = optStr(opts, "metric", "sharpe");
		var method = optStr(opts, "method", "grid");
		var accept = parseAccept(opts);
		var profile = optStr(opts, "profile", "honest-optimize");

		try {
			var prog = parseSource(source);
			var feed = new BarFeed(bars);
			var closes = [for (b in bars) b.close];
			var bh = buyHold(closes, initialCash);

			var harness = new HarnessContext();
			harness.orders.reset(initialCash);
			harness.feed = feed;
			musescript.builtins.TradeBuiltins.resetCrossState();

			// Register @param defaults so PlanRunner can see min/max ranges.
			var seedInterp = new MuseInterp(harness);
			for (d in prog.decls) seedInterp.registerDeclPublic(d);
			applyParamOverrides(harness, opts);

			var plan = buildPlan(prog, harness, method, opts);
			if (!hasOptimizeStep(plan)) {
				return emptyResult(seed, profile, 0, 0, 0, false, accept,
					"no tunable params",
					"No @param ranges / tune()/optimize() holes found — nothing to evolve.");
			}

			var runner = new PlanRunner(harness);
			runner.seed = seed;
			var tier = optStr(opts, "tier", "js");
			if (tier == "interp")
				runner.bindProgram(prog, feed);
			else
				runner.bindCompiled(prog, feed, { target: "js", strict: false });

			var trials = runner.trialSweep(plan, metric);
			var nTrialsSearch = trials.length;
			// DSR deflates by search size (and any IDE trials count if larger).
			var nTrials = nTrialsSearch;
			if (opts != null && Reflect.hasField(opts, "nTrials") && Reflect.field(opts, "nTrials") != null) {
				var n = Std.int((Reflect.field(opts, "nTrials") : Float));
				if (n > nTrials) nTrials = n;
			}
			if (nTrials < 1) nTrials = 1;
			TrialsSession.setCount(nTrials);

			var survivors:Array<Dynamic> = [];
			var rejected = 0;
			var anyBeatsNull = false;
			var bestScore = Math.NEGATIVE_INFINITY;
			var best:Null<Dynamic> = null;

			for (t in trials) {
				var equity = t.result.equity;
				var rets = equity != null && equity.length > 1
					? Metrics.returnsFromEquity(equity)
					: (t.result.returns != null ? t.result.returns : []);
				var strategyReturn:Null<Float> = null;
				if (Math.isFinite(t.result.finalEquity) && initialCash > 0)
					strategyReturn = t.result.finalEquity / initialCash - 1.0;

				var reportOpts:Dynamic = {
					nTrials: nTrials,
					bootSeed: seed,
					seed: seed,
					nullReturn: bh.ret,
					strategyReturn: strategyReturn,
					oosHeld: optBool(opts, "oosHeld", false),
					purgeEmbargoApplied: optBool(opts, "purgeEmbargoApplied", false),
					embargoBars: optInt(opts, "embargoBars", 0),
					pbo: optFloatNullable(opts, "pbo"),
					profile: profile,
					backend: tier == "interp" ? "interp" : "js",
					equityDigest: musescript.repro.EquityDigest.of(equity)
				};
				var mt = optIntNullable(opts, "minTrades");
				if (mt != null) Reflect.setField(reportOpts, "minTrades", mt);

				var report = TruthReport.evaluate(rets, t.result.trades, bh.sharpe, reportOpts);

				if (report.beatsNull) anyBeatsNull = true;

				var verdict = (report.verdict : String);
				if (!accepts(accept, verdict)) {
					rejected++;
					continue;
				}

				var cand = {
					params: mapToObj(t.params),
					metric: t.score,
					sharpe: t.result.sharpe,
					trades: t.result.trades,
					finalEquity: t.result.finalEquity,
					maxDrawdown: t.result.maxDrawdown,
					winRate: t.result.winRate,
					truthReport: report.toDyn()
				};
				survivors.push(cand);
				if (t.score > bestScore) {
					bestScore = t.score;
					best = cand;
				}
			}

			var found = best != null;
			var reason:Null<String> = null;
			var message:String;
			if (found) {
				message = 'Found ${survivors.length} non-overfit candidate(s) of $nTrialsSearch trials'
					+ ' (best verdict=${Reflect.field(Reflect.field(best, "truthReport"), "verdict")}).';
			} else if (nTrialsSearch == 0) {
				reason = "no tunable params";
				message = "Search produced zero trials.";
			} else if (!anyBeatsNull) {
				reason = "nothing beat the null";
				message = 'Searched $nTrialsSearch variants — nothing beat the null baseline. That is a feature.';
			} else {
				reason = "no robust strategy found";
				message = 'Searched $nTrialsSearch variants — some beat null, but none cleared the Truth Report gate (non-overfit).';
			}

			var out:Dynamic = {
				ok: true,
				found: found,
				reason: reason,
				message: message,
				trials: nTrialsSearch,
				survivors: survivors.length,
				rejected: rejected,
				anyBeatsNull: anyBeatsNull,
				acceptVerdicts: accept,
				metric: metric,
				seed: seed,
				best: best,
				repro: ReproStamp.make({
					seed: seed, bootSeed: seed, profile: profile,
					backend: tier == "interp" ? "interp" : "js"
				}).toJson()
			};
			return out;
		} catch (e:Dynamic) {
			return {
				ok: false,
				found: false,
				error: Std.string(e),
				seed: seed
			};
		}
	}

	/** Build ExecutionPlan from @macro tune/optimize, or synthesize from @param min/max. */
	static function buildPlan(prog:MuseProgram, harness:HarnessContext, method:String, opts:Dynamic):ExecutionPlan {
		var plan = new MusePlanner().plan(prog);
		if (hasOptimizeStep(plan)) return plan;

		var names:Array<String> = [];
		if (opts != null && Reflect.hasField(opts, "paramNames") && Reflect.field(opts, "paramNames") != null) {
			var arr:Array<Dynamic> = cast Reflect.field(opts, "paramNames");
			for (x in arr) names.push(Std.string(x));
		} else {
			for (n in harness.params.names()) {
				var o = harness.params.getOpts(n);
				if (o != null && o.min != null && o.max != null) names.push(n);
			}
		}
		if (names.length == 0) return plan;
		plan.steps.push(OptimizeStep("honest_opt_0", "sharpe", names, method));
		return plan;
	}

	static function hasOptimizeStep(plan:ExecutionPlan):Bool {
		for (s in plan.steps) {
			switch (s) {
				case OptimizeStep(_, _, _, _): return true;
				default:
			}
		}
		return false;
	}

	static function parseAccept(opts:Dynamic):Array<String> {
		if (opts != null && Reflect.hasField(opts, "acceptVerdicts") && Reflect.field(opts, "acceptVerdicts") != null) {
			var arr:Array<Dynamic> = cast Reflect.field(opts, "acceptVerdicts");
			var out = [for (x in arr) Std.string(x)];
			if (out.length > 0) return out;
		}
		return DEFAULT_ACCEPT.copy();
	}

	static function accepts(accept:Array<String>, verdict:String):Bool {
		for (a in accept) if (a == verdict) return true;
		return false;
	}

	static function emptyResult(
		seed:Int, profile:String, trials:Int, survivors:Int, rejected:Int,
		anyBeatsNull:Bool, accept:Array<String>, reason:String, message:String
	):Dynamic {
		return {
			ok: true,
			found: false,
			reason: reason,
			message: message,
			trials: trials,
			survivors: survivors,
			rejected: rejected,
			anyBeatsNull: anyBeatsNull,
			acceptVerdicts: accept,
			seed: seed,
			best: null,
			repro: ReproStamp.make({
				seed: seed, bootSeed: seed, profile: profile, backend: "js"
			}).toJson()
		};
	}

	static function buyHold(closes:Array<Float>, initialCash:Float):{sharpe:Float, ret:Null<Float>} {
		if (closes == null || closes.length < 2 || !(closes[0] > 0) || !(initialCash > 0))
			return { sharpe: Math.NaN, ret: null };
		var eq:Array<Float> = [];
		var c0 = closes[0];
		for (c in closes) eq.push(initialCash * (c / c0));
		var rets = Metrics.returnsFromEquity(eq);
		var last = eq[eq.length - 1];
		return {
			sharpe: Metrics.sharpe(rets, 0.0),
			ret: last / initialCash - 1.0
		};
	}

	static function applyParamOverrides(harness:HarnessContext, opts:Dynamic):Void {
		if (opts == null || !Reflect.hasField(opts, "params")) return;
		var p:Dynamic = Reflect.field(opts, "params");
		if (p == null) return;
		if (Std.isOfType(p, Array)) {
			var arr:Array<Dynamic> = cast p;
			for (item in arr) {
				if (item == null) continue;
				var n = Reflect.field(item, "name");
				if (n == null) continue;
				harness.params.set(Std.string(n), Reflect.field(item, "value"));
			}
			return;
		}
		for (k in Reflect.fields(p))
			harness.params.set(k, Reflect.field(p, k));
	}

	static function mapToObj(m:Map<String, Dynamic>):Dynamic {
		var o:Dynamic = {};
		for (k => v in m) Reflect.setField(o, k, v);
		return o;
	}

	static function optStr(opts:Dynamic, key:String, def:String):String {
		if (opts == null || !Reflect.hasField(opts, key) || Reflect.field(opts, key) == null) return def;
		return Std.string(Reflect.field(opts, key));
	}

	static function optBool(opts:Dynamic, key:String, def:Bool):Bool {
		if (opts == null || !Reflect.hasField(opts, key) || Reflect.field(opts, key) == null) return def;
		return Reflect.field(opts, key) == true;
	}

	static function optInt(opts:Dynamic, key:String, def:Int):Int {
		if (opts == null || !Reflect.hasField(opts, key) || Reflect.field(opts, key) == null) return def;
		return Std.int((Reflect.field(opts, key) : Float));
	}

	static function optIntNullable(opts:Dynamic, key:String):Null<Int> {
		if (opts == null || !Reflect.hasField(opts, key) || Reflect.field(opts, key) == null) return null;
		return Std.int((Reflect.field(opts, key) : Float));
	}

	static function optFloat(opts:Dynamic, key:String, def:Float):Float {
		if (opts == null || !Reflect.hasField(opts, key) || Reflect.field(opts, key) == null) return def;
		return (Reflect.field(opts, key) : Float);
	}

	static function optFloatNullable(opts:Dynamic, key:String):Null<Float> {
		if (opts == null || !Reflect.hasField(opts, key) || Reflect.field(opts, key) == null) return null;
		return (Reflect.field(opts, key) : Float);
	}

	/** Same front-end pipeline as MuseRuntime.parse — kept local to avoid circular imports. */
	static function parseSource(source:String):MuseProgram {
		var prog = new musescript.parse.MuseParser().parse(source, "<optimize>");
		prog = musescript.compile.ClassStrategyLower.expand(prog);
		prog = musescript.compile.TemplateExpand.expand(prog);
		prog = musescript.compile.ModuleExpand.expand(prog);
		return prog;
	}
}
