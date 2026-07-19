package musescript.cli;

import musescript.MuseScript;
import musescript.parse.MuseParser;
import musescript.compile.MuseCompiler;
import musescript.checker.MuseChecker;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;
import musescript.harness.OhlcvCsv;
import musescript.interp.MuseInterp;
import musescript.builtins.TradeBuiltins;
import musescript.ast.ExprJson;
import musescript.ast.MuseAstJson;

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
		// Native front end soak switch (ROADMAP "Native front end" Stage B):
		// MUSE_NATIVE_PARSER=1 routes legacy-dialect parses through
		// NativeParser (counted hscript fallback on unsupported constructs).
		if (Sys.getEnv("MUSE_NATIVE_PARSER") == "1")
			musescript.parse.MuseParser.native = true;
		var sourcePath = argVal("--source", "");
		var tapePath = argVal("--tape", "");
		var symbol = argVal("--symbol", "");
		var target = argVal("--target", "js");
		var synthN = intArg("--synth", 400);
		var seed = intArg("--seed", 42);
		var checkOnly = argFlag("--check");
		var extractCond = argFlag("--extract-cond");
		var astJson = argFlag("--ast-json");
		var emitWatFlag = argFlag("--emit-wat");
		var emitWasmFilePath = argVal("--emit-wasm-file", "");
		var docsMdFlag = argFlag("--docs-md");
		var strict = argFlag("--strict");
		var instrument = argFlag("--instrument");
		var artifactDir = argVal("--artifact", "");
		var executionMode = argVal("--execution", "same-close");
		if (executionMode != "same-close" && executionMode != "next-open") {
			emit({ ok: false, error: 'unknown --execution mode: $executionMode' });
			return;
		}

		var batchPath = argVal("--batch", "");

		// --extract-cond: Forge's reverse projection (MuseAST -> Forge graph). Parses only -- no
		// tape/backtest needed -- and returns the JSON-serialized condition expression of the
		// `if (cond) long();` shape inside @on(bar), or an honest rejection if the source isn't
		// exactly that shape. See musescript/ast/ExprJson.hx for the scope/rationale.
		if (extractCond) {
			var source0 = sourcePath != "" ? readFile(sourcePath) : readStdin();
			try {
				var prog0 = new MuseParser().parse(source0, "<gene>");
				emit(ExprJson.extractLongCondition(prog0));
			} catch (e:Dynamic) {
				emit({ ok: false, reason: Std.string(e) });
			}
			return;
		}

		// --ast-json: full-program AST export (any valid MuseScript computation is a legal
		// "tradelogic tree" node now, not just the boolean subset --extract-cond covers). Every
		// node is type-tagged via the real MuseChecker's typeOf(), not reimplemented inference.
		// Parses + type-checks only, no tape/backtest needed.
		if (astJson) {
			var source1 = sourcePath != "" ? readFile(sourcePath) : readStdin();
			try {
				var prog1 = new MuseParser().parse(source1, "<gene>");
				var checker1 = new musescript.checker.MuseChecker();
				checker1.checkEx(prog1);
				emit({ ok: true, program: MuseAstJson.programToJson(prog1, checker1) });
			} catch (e:Dynamic) {
				emit({ ok: false, reason: Std.string(e) });
			}
			return;
		}

		// --docs-md: print the builtin reference manual as Markdown (ROADMAP.md
		// "Docstring introspection pipeline") — no source/tape needed. CI-friendly:
		// `node gene-runner.js --docs-md > BUILTINS.md`.
		if (docsMdFlag) {
			Sys.println(MuseScript.docsMarkdown());
			return;
		}

		// --emit-wasm-file <path>: assemble `source`'s on_bar WASM (via WatAssembler,
		// same path MuseRuntime's in-browser wasm tier uses) and write real .wasm
		// bytes to <path>, plus <path>.strings.json alongside — the artifact shape
		// KestrGraalServer's Backtest RPC expects (wasm_path/strings_path). Built
		// for cross-validating KestrGraal against the same modules the JS tiers run,
		// with no wat2wasm/Python dependency in the loop.
		if (emitWasmFilePath != "") {
			var sourceE = sourcePath != "" ? readFile(sourcePath) : readStdin();
			try {
				var progE = new MuseParser().parse(sourceE, "<gene>");
				progE = musescript.compile.TemplateExpand.expand(progE);
				var e = musescript.compile.StrategyWasmBackend.emitOnBar(progE);
				if (e == null) {
					emit({ ok: false, reason: "strategy is outside the WASM on_bar subset" });
					return;
				}
				var bytes = musescript.compile.WatAssembler.assemble(e.wat);
				sys.io.File.saveBytes(emitWasmFilePath, bytes);
				sys.io.File.saveContent(emitWasmFilePath + ".strings.json", haxe.Json.stringify(e.strings));
				emit({ ok: true, wasmBytes: bytes.length, strings: e.strings.length });
			} catch (ex:Dynamic) {
				emit({ ok: false, reason: Std.string(ex) });
			}
			return;
		}

		// --emit-wat: dump the StrategyWasmBackend WAT for `source`'s on_bar subset
		// (debugging / the WatAssembler cross-check tooling — no tape needed).
		if (emitWatFlag) {
			var sourceW = sourcePath != "" ? readFile(sourcePath) : readStdin();
			try {
				var progW = new MuseParser().parse(sourceW, "<gene>");
				progW = musescript.compile.TemplateExpand.expand(progW);
				var e = musescript.compile.StrategyWasmBackend.emitOnBar(progW);
				if (e == null)
					emit({ ok: false, reason: "strategy is outside the WASM on_bar subset" });
				else
					emit({ ok: true, wat: e.wat, strings: e.strings });
			} catch (ex:Dynamic) {
				emit({ ok: false, reason: Std.string(ex) });
			}
			return;
		}

		// Batch mode: load the tape ONCE, then compile+run each JSONL {id, source}.
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
					// Distinct output subdirectory per genome -- runOne() writes to a single fixed
					// path, so passing the same artifactDir through for every genome in the batch
					// loop would silently overwrite each one's compiled files with the next
					// genome's, leaving only the LAST genome's artifact on disk (a real gap found
					// while wiring MuseGene's fitness loop through KestrGraal's WASM-artifact RPC).
					var perGenomeDir = artifactDir != "" ? artifactDir + "/" + id : "";
					var res = runOne(Std.string(obj.source), bars, target, checkOnly, strict, perGenomeDir, executionMode);
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
			emit(runOne(source, bars, target, checkOnly, strict, artifactDir, executionMode, instrument));
		} catch (e:Dynamic) {
			emit({ ok: false, error: Std.string(e) });
		}
	}

	/** Compile+backtest one source against pre-loaded bars; returns a metrics struct. */
	static function runOne(
		source:String, bars:Array<Bar>, target:String, checkOnly:Bool,
		strict:Bool, artifactDir:String, executionMode:String, ?instrument:Bool = false
	):Dynamic {
		// Expand statement templates before any interpreter seeding. Seeding the
		// raw AST left bare `TrailingStop(0.05)` calls unresolved ("Cannot call null").
		var prog = new MuseParser().parse(source, "<gene>");
		// TemplateExpand before ModuleExpand — see MuseCompiler.compileEx's
		// comment: TemplateExpand can see into ModuleDecl bodies, ModuleExpand
		// can't see into TemplateDecl bodies, so this order is required for a
		// `use` call written inside a template to ever get expanded.
		prog = musescript.compile.TemplateExpand.expand(prog);
		prog = musescript.compile.ModuleExpand.expand(prog);

		if (checkOnly) {
			var warnings = new MuseChecker().check(prog);
			return { ok: true, decls: prog.decls.length, warnings: warnings };
		}

		var harness = new HarnessContext();
		harness.orders.executionMode = executionMode;
		var seedInterp = new MuseInterp(harness);
		for (d in prog.decls) seedInterp.registerDeclPublic(d);

		var feed = new BarFeed(bars);
		harness.feed = feed;
		TradeBuiltins.resetCrossState();

		var ex = MuseCompiler.compileEx(prog, { target: target, strict: strict });
		// StrategyWasmEmitter works from `prog` (the parsed AST) directly -- it has no
		// dependency on `ex`/`target` at all, so artifact emission doesn't need target=="wasm".
		// Gating it on target was accidental coupling: it forced callers who want a WASM artifact
		// PLUS a fast score to pay Node's own (slower, ~2x the JS-interp path when measured)
		// WASM execution for `ex.fn` just to unlock emission, when they could score via the fast
		// JS-interp path and still get the artifact. (Found while wiring MuseGene's batch
		// evaluation through KestrGraal -- batch-compiling N genomes to WASM artifacts should run
		// at JS-interp speed, not pay N Node-side WASM executions nobody asked for.)
		if (artifactDir != "") {
			var emitted = new musescript.compile.StrategyWasmEmitter().emitOnBar(prog);
			if (emitted == null && strict)
				throw "GeneRunner: strict wasm artifact emission failed";
			if (emitted != null) {
				var dir = artifactDir;
				if (!sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
				sys.io.File.saveContent(dir + "/on_bar.wat", emitted.wat);
				sys.io.File.saveContent(dir + "/on_bar.strings.json", haxe.Json.stringify(emitted.strings));
				sys.io.File.saveContent(dir + "/manifest.json", haxe.Json.stringify({
					schema: "musescript.strategy-wasm/1",
					abi: "musescript.on-bar-memory/1",
					strings: emitted.strings,
					exports: ["memory", "ensure_capacity", "configure_tape", "on_bar", "push_bar", "reset"],
					imports: ["get_param", "long", "short", "flat"]
				}));
			}
		}
		var t0 = haxe.Timer.stamp();
		var result:Dynamic = ex.fn(harness);
		var runMs = (haxe.Timer.stamp() - t0) * 1000.0;

		var out:Dynamic = {
			ok: true,
			backend: ex.backend,
			execution: executionMode,
			emitted: ex.emitted,
			runMs: Math.fround(runMs * 1000) / 1000,
			barsPerSec: runMs > 0 ? Math.fround(bars.length / (runMs / 1000.0)) : null,
			bars: bars.length,
			trades: intField(result, "trades"),
			sharpe: finField(result, "sharpe"),
			maxDrawdown: finField(result, "maxDrawdown"),
			winRate: finField(result, "winRate"),
			finalEquity: finField(result, "finalEquity")
		};
		// Honesty flag: the requested target couldn't be emitted and the run fell
		// back to another backend. Callers scoring fitness should treat a
		// fallback verdict as suspect (or pass --strict to hard-fail instead).
		if (ex.backend != target)
			Reflect.setField(out, "fallback", true);
		// IDE instrumentation payload (--instrument): the chart commands, per-bar
		// console log, executed fills, and equity curve — all already collected
		// during the run, returned only on demand so the fitness/batch path stays
		// lean and the golden-parity output is byte-identical without the flag.
		if (instrument) {
			Reflect.setField(out, "equity", harness.orders.equity);
			Reflect.setField(out, "fills", harness.orders.fills);
			Reflect.setField(out, "chart", harness.chart.commands);
			Reflect.setField(out, "logs", harness.logs);
		}
		return out;
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
