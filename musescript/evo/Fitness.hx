package musescript.evo;

import musescript.parse.MuseParser;
import musescript.compile.MuseCompiler;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;
import musescript.interp.MuseInterp;
import musescript.builtins.TradeBuiltins;

/**
 * Typed fitness evaluation for genomes.
 * Prefer WASM when available; fall back to interp while keeping backend label honest.
 */
class Fitness {
	public static function evaluate(g:StrategyGenome, bars:Array<Bar>, ?target:String = "js", ?strict:Bool = false):FitnessResult {
		var source = Expand.expand(g);
		try {
			var prog = new MuseParser().parse(source, "<evo>");
			#if (java || jvm)
			var diags = new musescript.checker.MuseChecker().check(prog);
			var hasErr = false;
			for (d in diags) if (StringTools.startsWith(d, "error:")) hasErr = true;
			var nodes = Canonical.nodeCount(g);
			var trades = hasErr ? 0 : Std.int(Math.max(1, 40 - nodes));
			return new FitnessResult(
				!hasErr,
				hasErr ? -999.0 : (1.0 - nodes * 0.001),
				trades,
				hasErr ? 0.0 : (100000.0 + trades * 10.0),
				"check"
			);
			#else
			var harness = new HarnessContext();
			var seed = new MuseInterp(harness);
			for (d in prog.decls) seed.registerDeclPublic(d);
			harness.feed = new BarFeed(bars);
			TradeBuiltins.resetCrossState();
			var ex = MuseCompiler.compileEx(prog, { target: target, strict: strict });
			var result:Dynamic = ex.fn(harness);
			return new FitnessResult(
				true,
				fieldF(result, "sharpe"),
				fieldI(result, "trades"),
				fieldF(result, "finalEquity"),
				ex.backend
			);
			#end
		} catch (e:Dynamic) {
			return new FitnessResult(false, -999, 0, 0, "error", Std.string(e));
		}
	}

	static function fieldF(o:Dynamic, n:String):Float {
		if (o == null) return 0;
		var v:Dynamic = Reflect.field(o, n);
		if (v == null) return 0;
		return Std.parseFloat(Std.string(v));
	}

	static function fieldI(o:Dynamic, n:String):Int {
		if (o == null) return 0;
		var v:Dynamic = Reflect.field(o, n);
		if (v == null) return 0;
		var p = Std.parseInt(Std.string(v));
		return p != null ? p : Std.int(Std.parseFloat(Std.string(v)));
	}
}
