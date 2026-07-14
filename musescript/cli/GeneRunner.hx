package musescript.cli;

import musescript.parse.MuseParser;
import musescript.compile.MuseCompiler;
import musescript.checker.MuseChecker;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;
import musescript.harness.OhlcvCsv;
import musescript.interp.MuseInterp;
import musescript.builtins.TradeBuiltins;

/**
 * GeneRunner — headless fitness bridge for the MuseGene evolvable IR.
 *
 * Reads a MuseScript strategy (file or stdin), backtests it against a CSV tape
 * (optionally filtered to one symbol) or synthetic bars, and prints ONE line of
 * JSON metrics to stdout. Designed to be shelled out to from the Python DEAP driver.
 *
 * On any failure it still prints valid JSON (`{"ok":false,"error":...}`) and exits 0,
 * so the caller always parses a result instead of catching a crash.
 *
 *   node build/js/gene-runner.js --source strat.ms --tape data/real/tape.csv --symbol SPY
 *   node build/js/gene-runner.js --check --source strat.ms
 *   echo "<src>" | node build/js/gene-runner.js --target wasm
 */
class GeneRunner {
	static function argVal(name:String, def:String):String {
		var a = Sys.args();
		for (i in 0...a.length) if (a[i] == name && i + 1 < a.length) return a[i + 1];
		return def;
	}

	static function argFlag(name:String):Bool {
		for (a in Sys.args()) if (a == name) return true;
		return false;
	}

	static function main() {
		var sourcePath = argVal("--source", "");
		var tapePath = argVal("--tape", "");
		var symbol = argVal("--symbol", "");
		var target = argVal("--target", "js");
		var synthN = intArg("--synth", 400);
		var seed = intArg("--seed", 42);
		var checkOnly = argFlag("--check");

		var batchPath = argVal("--batch", "");

		// Batch mode: load the tape ONCE, then compile+run each JSONL {id, source}.
		// Amortizes node startup + warms MuseScript's module cache across genomes.
		if (batchPath != "") {
			var bars = loadBars(tapePath, symbol, synthN, seed);
			var lines = readFile(batchPath).split("\r\n").join("\n").split("\r").join("\n").split("\n");
			for (ln in lines) {
				var t = StringTools.trim(ln);
				if (t == "") continue;
				var id = "";
				try {
					var obj:Dynamic = haxe.Json.parse(t);
					id = obj.id != null ? Std.string(obj.id) : "";
					var res = runOne(Std.string(obj.source), bars, target, checkOnly);
					Reflect.setField(res, "id", id);
					emit(res);
				} catch (e:Dynamic) {
					emit({ ok: false, id: id, error: Std.string(e) });
				}
			}
			return;
		}

		var source = sourcePath != "" ? readFile(sourcePath) : readStdin();
		var bars = checkOnly ? [] : loadBars(tapePath, symbol, synthN, seed);
		try {
			emit(runOne(source, bars, target, checkOnly));
		} catch (e:Dynamic) {
			emit({ ok: false, error: Std.string(e) });
		}
	}

	/** Compile+backtest one source against pre-loaded bars; returns a metrics struct. */
	static function runOne(source:String, bars:Array<Bar>, target:String, checkOnly:Bool):Dynamic {
		var prog = new MuseParser().parse(source, "<gene>");

		if (checkOnly) {
			var warnings = new MuseChecker().check(prog);
			return { ok: true, decls: prog.decls.length, warnings: warnings };
		}

		var harness = new HarnessContext();
		// Seed @param defaults / @indicator / functions the way the backends do internally,
		// so params resolve regardless of which backend compileEx picks.
		var seedInterp = new MuseInterp(harness);
		for (d in prog.decls) seedInterp.registerDeclPublic(d);

		var feed = new BarFeed(bars);
		Reflect.setField(harness, "feed", feed);
		TradeBuiltins.resetCrossState();

		var ex = MuseCompiler.compileEx(prog, { target: target, strict: false });
		var result:Dynamic = ex.fn(harness);

		return {
			ok: true,
			backend: ex.backend,
			bars: bars.length,
			trades: intField(result, "trades"),
			sharpe: finField(result, "sharpe"),
			maxDrawdown: finField(result, "maxDrawdown"),
			winRate: finField(result, "winRate"),
			finalEquity: finField(result, "finalEquity")
		};
	}

	static function loadBars(tapePath:String, symbol:String, synthN:Int, seed:Int):Array<Bar> {
		if (tapePath == "") return BarFeed.synthetic(synthN, seed).all();
		var text = readFile(tapePath);
		if (symbol != "") text = filterSymbol(text, symbol);
		return OhlcvCsv.parse(text);
	}

	/** Keep the header row + only rows whose first CSV field equals `sym`. */
	static function filterSymbol(text:String, sym:String):String {
		var lines = text.split("\r\n").join("\n").split("\r").join("\n").split("\n");
		if (lines.length == 0) return text;
		var out = [lines[0]];
		for (i in 1...lines.length) {
			var ln = lines[i];
			if (StringTools.trim(ln) == "") continue;
			var comma = ln.indexOf(",");
			var first = comma >= 0 ? ln.substr(0, comma) : ln;
			if (StringTools.trim(first) == sym) out.push(ln);
		}
		return out.join("\n");
	}

	static function intArg(name:String, def:Int):Int {
		var v = Std.parseInt(argVal(name, Std.string(def)));
		return v != null ? v : def;
	}

	static function intField(o:Dynamic, f:String):Int {
		var v = Reflect.field(o, f);
		if (v == null) return 0;
		return Std.isOfType(v, Int) ? cast v : Std.int(cast(v, Float));
	}

	/** Finite float or null (so the JSON never contains NaN/Infinity). */
	static function finField(o:Dynamic, f:String):Null<Float> {
		var v = Reflect.field(o, f);
		if (v == null) return null;
		var x:Float = cast v;
		return Math.isFinite(x) ? x : null;
	}

	static function emit(o:Dynamic):Void {
		Sys.println(haxe.Json.stringify(o));
	}

	static function readFile(path:String):String {
		return js.Syntax.code("require('fs').readFileSync({0}, 'utf8')", path);
	}

	static function readStdin():String {
		try {
			return js.Syntax.code("require('fs').readFileSync(0, 'utf8')");
		} catch (_:Dynamic) {
			return "";
		}
	}
}
