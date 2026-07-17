package musescript.examples;

import musescript.MuseScript;
import musescript.parse.MuseParser;
import musescript.compile.MuseCompiler;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.PlanRunner;
import musescript.plan.MusePlanner;
import musescript.builtins.TradeBuiltins;
import musescript.interp.MuseInterp;
import musescript.types.MuseTypes;
import sys.FileSystem;
import sys.io.File;

/**
 * Example 10 — catalog of distinct strategy *kinds* on the hardened type lattice.
 * Auto-discovers `examples/strategy-kinds/*.ms` (sorted).
 * When a kind declares a pipeline/macro with tune/optimize, also runs PlanRunner.
 */
class StrategyKinds {
	static function listKinds(dir:String):Array<String> {
		var names = FileSystem.readDirectory(dir);
		names = [for (n in names) if (StringTools.endsWith(n, ".ms")) n];
		names.sort(function(a, b) return Reflect.compare(a, b));
		return names;
	}

	static function hasMacro(prog:musescript.ast.MuseProgram):Bool {
		for (d in prog.decls) switch (d) {
			case MacroDecl(_, _): return true;
			default:
		}
		return false;
	}

	/** Fib-ish grid for Window params that lack min/max (typed-surface pipelines). */
	static function ensureTuneRanges(harness:HarnessContext, prog:musescript.ast.MuseProgram):Void {
		var seed = new MuseInterp(harness);
		for (d in prog.decls) seed.registerDeclPublic(d);
		var plan = new MusePlanner().plan(prog);
		var names:Array<String> = [];
		for (step in plan.steps) switch (step) {
			case OptimizeStep(_, _, ps, _):
				for (p in ps) if (names.indexOf(p) < 0) names.push(p);
			default:
		}
		for (name in names) {
			var o = harness.params.getOpts(name);
			if (o != null && o.min != null && o.max != null) continue;
			var cur = harness.params.get(name);
			var n = Std.isOfType(cur, Float) || Std.isOfType(cur, Int) ? Std.int(cur) : 13;
			if (MuseTypes.isWindow(n) || name == "fast" || name == "slow" || name == "look") {
				harness.params.register(name, n, 5, 34, 8, "grid");
			} else {
				var base = asFloat(cur);
				harness.params.register(name, base, base * 0.8, base * 1.2, Math.max(0.05, Math.abs(base) * 0.1), "grid");
			}
		}
	}

	static function asFloat(v:Dynamic):Float {
		if (Std.isOfType(v, Float)) return (v : Float);
		if (Std.isOfType(v, Int)) return (v : Int);
		return Std.parseFloat(Std.string(v));
	}

	static function main() {
		var dir = "examples/strategy-kinds";
		Sys.println("=== MuseScript 10-strategy-kinds ===");
		if (!FileSystem.exists(dir)) {
			Sys.println('MISSING $dir');
			Sys.exit(1);
		}
		var kinds = listKinds(dir);
		var failed = 0;
		for (name in kinds) {
			var path = dir + "/" + name;
			var source = File.getContent(path);
			var checkErrs = MuseScript.check(source, path);
			var hard = [for (e in checkErrs) if (StringTools.startsWith(e, "error:")) e];
			if (hard.length > 0) {
				Sys.println('TYPEFAIL $name');
				for (e in hard) Sys.println("  " + e);
				failed++;
				continue;
			}
			var prog = new MuseParser().parse(source, path);
			var feed = BarFeed.synthetic(400, 42);
			try {
				if (hasMacro(prog)) {
					var oh = new HarnessContext();
					ensureTuneRanges(oh, prog);
					TradeBuiltins.resetCrossState();
					var plan = new MusePlanner().plan(prog);
					var opt = new PlanRunner(oh).bindCompiled(prog, feed, { target: "js", strict: true }).optimize(plan, "sharpe");
					Sys.println(
						'OPT $name trials=${opt.trials} bestSharpe=${opt.bestMetric} best=${opt.bestParams}'
					);
				}
				var harness = new HarnessContext();
				Reflect.setField(harness, "feed", feed);
				TradeBuiltins.resetCrossState();
				var ex = MuseCompiler.compileEx(prog, { target: "js", strict: true });
				var result:Dynamic = ex.fn(harness);
				Sys.println(
					'OK $name backend=${ex.backend} trades=${result.trades} sharpe=${result.sharpe} equity=${result.finalEquity}'
				);
			} catch (e:Dynamic) {
				Sys.println('RUNFAIL $name: $e');
				failed++;
			}
		}
		if (failed > 0) {
			Sys.println('FAIL $failed/${kinds.length} kinds');
			Sys.exit(1);
		}
		Sys.println('PASS ${kinds.length}/${kinds.length} kinds');
	}
}
