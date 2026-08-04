package musescript.cli;

import musescript.MuseScript;
import musescript.parse.MuseParser;
import musescript.compile.MuseCompiler;
import musescript.vm.MuseVm;
import musescript.checker.MuseChecker;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;
import musescript.harness.OhlcvCsv;
import musescript.harness.PanelFeed;
import musescript.harness.PanelLoader;
import musescript.interp.MuseInterp;
import musescript.builtins.TradeBuiltins;
import musescript.runtime.MuseRuntime;
import musescript.ast.ExprJson;
import musescript.ast.MuseAstJson;
// Murmuration (proprietary market simulator, private classpath addition like Kestrel — see
// build-kestrel.hxml / the #if kestrel guard on KestrelBootstrap.register() below): the public
// build must compile cleanly WITHOUT musescript/murmuration/ present at all, so these imports
// (and every use of them below) are gated the same way core code gates musescript.kestrel.
#if kestrel
import musescript.murmuration.MurmurationConfig;
import musescript.murmuration.MurmurationSim;
import musescript.murmuration.MurmurationTape;
#end

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
 *   node build/js/gene-runner.js --optimize --source strat.ms --tape tape.csv
 *   node build/js/gene-runner.js --source scan.ms --panel data/fund_panel.json
 *   node build/js/gene-runner.js --source scan.ms --tapes AAPL=a.csv,MSFT=b.csv
 *   node build/js/gene-runner.js --ingest --source ingest.ms --fs-root ./sandbox \
 *     --fixture-dir ./fixtures --http replay --allow-hosts api.example.com
 *   echo "<src>" | node build/js/gene-runner.js --target wasm
 *
 * Panel mode (`--panel` / `--tapes`): portfolio `runPanelBacktest` via MuseRuntime.runPanel.
 * Offline only — JSON bySym (fund_panel_loader), long CSV with symbol column, dir of CSVs,
 * or SYM=path tapes. Attach the same PanelFeed in evo with EvolutionEngine.configureForPanel.
 *
 * Ingest mode (`--ingest`): FsGrant+NetGrant IO loop via `MuseRuntime.runIngest` — never the
 * default fitness path. Write PIT CSVs under `--fs-root`, then re-run offline with grants null.
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
		// Only present in a private build that adds the musescript-kestrel package to the
		// classpath with -D kestrel (see build-kestrel.hxml); compiles to nothing in the public
		// build. Registers Kestrel's builtins/palette/typed-sigs via musescript.interp.
		// MuseExtensions — core never imports musescript.kestrel itself either way.
		#if kestrel
		musescript.kestrel.KestrelBootstrap.register();
		#end
		// Native front end soak switch (ROADMAP "Native front end" Stage B):
		// MUSE_NATIVE_PARSER=1 routes legacy-dialect parses through
		// NativeParser (counted hscript fallback on unsupported constructs).
		if (Sys.getEnv("MUSE_NATIVE_PARSER") == "1")
			musescript.parse.MuseParser.native = true;
		var sourcePath = argVal("--source", "");
		var tapePath = argVal("--tape", "");
		var panelPath = argVal("--panel", "");
		var tapesArg = argVal("--tapes", "");
		var symbol = argVal("--symbol", "");
		var target = argVal("--target", "js");
		var synthN = intArg("--synth", 400);
		var seed = intArg("--seed", 42);
		var fillNextOpen = argBool("--fill-next-open", true);
		#if kestrel
		var murmurationConfigPath = argVal("--murmuration-config", "");
		var murmurationSteps = intArg("--murmuration-synth", 0);
		#else
		var murmurationConfigPath = "";
		var murmurationSteps = 0;
		#end
		var costBps = Std.parseFloat(argVal("--cost-bps", "0"));
		if (Math.isNaN(costBps)) costBps = 0;
		var startCapital = Std.parseFloat(argVal("--start-capital", "100000"));
		if (Math.isNaN(startCapital)) startCapital = 100000;
		var equityFloor = Std.parseFloat(argVal("--equity-floor", "0"));
		if (Math.isNaN(equityFloor)) equityFloor = 0;
		var checkOnly = argFlag("--check");
		var optimizeFlag = argFlag("--optimize");
		var extractCond = argFlag("--extract-cond");
		var astJson = argFlag("--ast-json");
		var emitWatFlag = argFlag("--emit-wat");
		var emitWasmFilePath = argVal("--emit-wasm-file", "");
		var docsMdFlag = argFlag("--docs-md");
		var strict = argFlag("--strict");
		var instrument = argFlag("--instrument");
		// --vm (Graoptimization / .exe-forward): backtest on the native-image-clean Tier-A bytecode
		// VM (musescript.vm.MuseVm), interp fallback for out-of-subset. See RECURSIVE_SELF_IMPROVEMENT.
		var useVm = argFlag("--vm");
		var artifactDir = argVal("--artifact", "");
		var executionMode = argVal("--execution", "same-close");
		if (executionMode != "same-close" && executionMode != "next-open") {
			emit({ ok: false, error: 'unknown --execution mode: $executionMode' });
			return;
		}
		var metric = argVal("--metric", "sharpe");
		var method = argVal("--method", "grid");
		var minTrades = intArg("--min-trades", 1);

		var batchPath = argVal("--batch", "");
		var panelMode = panelPath != "" || tapesArg != "";
		var ingestMode = argFlag("--ingest");
		var httpMode = argVal("--http", "");
		var fsRoot = argVal("--fs-root", "");
		var fixtureDir = argVal("--fixture-dir", "");
		var allowHosts = argVal("--allow-hosts", "");
		var grantsPath = argVal("--grants", "");

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
			if (panelMode) {
				emit({ ok: false, error: "GeneRunner: --batch does not support --panel/--tapes yet" });
				return;
			}
			var bars = loadBars(tapePath, symbol, synthN, seed, murmurationConfigPath, murmurationSteps);
			var batchMeta = tapeMeta(tapePath, symbol);
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
					var res = runOne(Std.string(obj.source), bars, target, checkOnly, strict, perGenomeDir, executionMode, false, costBps, startCapital, equityFloor, useVm, batchMeta.symbol, batchMeta.assetClass);
					Reflect.setField(res, "id", id);
					emit(res);
				} catch (e:Dynamic) {
					emit({ ok: false, id: id, error: Std.string(e) });
				}
			}
			return;
		}

		var source = sourcePath != "" ? readFile(sourcePath) : readStdin();
		try {
			if (ingestMode) {
				emit(runIngestCli(source, grantsPath, fsRoot, fixtureDir, allowHosts, httpMode));
				return;
			}
			if (panelMode) {
				if (optimizeFlag) {
					emit({ ok: false, error: "GeneRunner: --optimize with --panel/--tapes is not supported yet" });
					return;
				}
				if (checkOnly) {
					var progP = new MuseParser().parse(source, "<gene>");
					progP = musescript.compile.ClassStrategyLower.expand(progP);
					progP = musescript.compile.MuseHostLower.lower(progP);
					progP = musescript.compile.TemplateExpand.expand(progP);
					progP = musescript.compile.ModuleExpand.expand(progP);
					var warningsP = new MuseChecker().check(progP);
					emit({ ok: true, decls: progP.decls.length, warnings: warningsP, panel: true });
					return;
				}
				emit(runPanel(source, panelPath, tapesArg, target, costBps, startCapital, fillNextOpen, seed, instrument));
				return;
			}
			var bars = (checkOnly && !optimizeFlag)
				? []
				: loadBars(tapePath, symbol, synthN, seed, murmurationConfigPath, murmurationSteps);
			if (optimizeFlag) {
				// Honesty-gated param search over @param / pipeline tune+optimize holes
				// (and synthesized ranges from param { min, max, step, tune }).
				var optRes = musescript.harness.HonestOptimize.search(source, bars, {
					seed: seed,
					metric: metric,
					method: method,
					tier: target == "interp" ? "interp" : "js",
					initialCash: startCapital,
					minTrades: minTrades,
					profile: "gene-runner-optimize"
				});
				Reflect.setField(optRes, "execution", executionMode);
				Reflect.setField(optRes, "costBps", costBps);
				Reflect.setField(optRes, "bars", bars.length);
				if (symbol != "") Reflect.setField(optRes, "symbol", symbol);
				emit(optRes);
				return;
			}
			var meta = tapeMeta(tapePath, symbol);
			emit(runOne(source, bars, target, checkOnly, strict, artifactDir, executionMode, instrument, costBps, startCapital, equityFloor, useVm, meta.symbol, meta.assetClass));
		} catch (e:Dynamic) {
			emit({ ok: false, error: Std.string(e) });
		}
	}

	/**
	 * Portfolio / panel backtest. `--panel` path auto-detects JSON bySym, long CSV, or
	 * directory of CSVs; `--tapes SYM=path,...` is the multi-file sibling of PanelRunner.
	 */
	static function runPanel(
		source:String, panelPath:String, tapesArg:String, target:String,
		costBps:Float, startCapital:Float, fillNextOpen:Bool, seed:Int, instrument:Bool
	):Dynamic {
		var bySymMap:Map<String, Array<Bar>>;
		if (tapesArg != "") bySymMap = PanelLoader.fromTapesSpecMap(tapesArg);
		else bySymMap = PanelLoader.loadMap(panelPath);
		var panel:PanelFeed = PanelFeed.fromSymbolBars(bySymMap);
		var tier = target == "interp" ? "interp" : "js";
		if (target == "wasm")
			return { ok: false, error: "GeneRunner panel: wasm tier not supported yet; use js or interp" };
		var res:Dynamic = MuseRuntime.runPanel(source, PanelLoader.toBySymDyn(bySymMap), {
			tier: tier,
			costBps: costBps,
			fillNextOpen: fillNextOpen,
			initialCash: startCapital,
			instrument: instrument,
			seed: seed,
			fitness: true
		});
		Reflect.setField(res, "costBps", costBps);
		Reflect.setField(res, "fillNextOpen", fillNextOpen);
		Reflect.setField(res, "seed", seed);
		Reflect.setField(res, "panelSymbols", panel.symbols);
		return res;
	}

	/** `--ingest` → MuseRuntime.runIngest with CLI-built grants. */
	static function runIngestCli(
		source:String, grantsPath:String, fsRoot:String, fixtureDir:String,
		allowHosts:String, httpMode:String
	):Dynamic {
		if (StringTools.trim(source) == "")
			return { ok: false, error: "GeneRunner --ingest: empty source" };
		var grantOpts:Dynamic = {};
		if (grantsPath != "") {
			try {
				Reflect.setField(grantOpts, "grants", musescript.io.CliIoGrants.parseJson(readFile(grantsPath)));
			} catch (e:Dynamic) {
				return { ok: false, error: "GeneRunner --grants: " + Std.string(e) };
			}
		}
		if (fsRoot != "") Reflect.setField(grantOpts, "fsRoot", sys.FileSystem.absolutePath(fsRoot));
		if (fixtureDir != "") Reflect.setField(grantOpts, "fixtureDir", sys.FileSystem.absolutePath(fixtureDir));
		if (allowHosts != "") Reflect.setField(grantOpts, "allowHosts", allowHosts);
		if (httpMode != "") Reflect.setField(grantOpts, "http", httpMode);
		var grants = musescript.io.CliIoGrants.fromOpts(grantOpts);
		if (grants == null)
			return {
				ok: false,
				error: "GeneRunner --ingest requires --grants JSON and/or --fs-root / --fixture-dir"
			};
		var opts:Dynamic = {
			grants: grants,
			kind: "ingest",
			isBacktest: false,
			fitness: false
		};
		if (httpMode != "") Reflect.setField(opts, "http", httpMode);
		return MuseRuntime.runIngest(source, opts);
	}

	/** Default-true boolean flag: absent → def; bare `--flag` → true; `--flag false` → false. */
	static function argBool(name:String, def:Bool):Bool {
		var a = Sys.args();
		for (i in 0...a.length) {
			if (a[i] != name) continue;
			if (i + 1 < a.length) {
				var v = a[i + 1].toLowerCase();
				if (v == "false" || v == "0") return false;
				if (v == "true" || v == "1") return true;
			}
			return true;
		}
		return def;
	}

	/** Compile+backtest one source against pre-loaded bars; returns a metrics struct. */
	static function runOne(
		source:String, bars:Array<Bar>, target:String, checkOnly:Bool,
		strict:Bool, artifactDir:String, executionMode:String, ?instrument:Bool = false,
		?costBps:Float = 0.0, ?startCapital:Float = 100000, ?equityFloor:Float = 0.0,
		?useVm:Bool = false, ?symbol:String = "", ?assetClass:String = ""
	):Dynamic {
		// Expand statement templates before any interpreter seeding. Seeding the
		// raw AST left bare `TrailingStop(0.05)` calls unresolved ("Cannot call null").
		var prog = new MuseParser().parse(source, "<gene>");
		// TemplateExpand before ModuleExpand — see MuseCompiler.compileEx's
		// comment: TemplateExpand can see into ModuleDecl bodies, ModuleExpand
		// can't see into TemplateDecl bodies, so this order is required for a
		// `use` call written inside a template to ever get expanded.
		prog = musescript.compile.ClassStrategyLower.expand(prog); // class X extends muse.Strat -> StrategyDecl (no-op otherwise)
		prog = musescript.compile.MuseHostLower.lower(prog);
			prog = musescript.compile.TemplateExpand.expand(prog);
		prog = musescript.compile.ModuleExpand.expand(prog);

		if (checkOnly) {
			var warnings = new MuseChecker().check(prog);
			return { ok: true, decls: prog.decls.length, warnings: warnings };
		}

		var harness = new HarnessContext();
		// Fitness / GeneRunner scoring path: never carry IO grants.
		MuseRuntime.applyIoGrants(harness, { fitness: true });
		harness.symbol = symbol;
		harness.assetClass = assetClass;
		harness.orders.executionMode = executionMode;
		if (startCapital != 100000) harness.orders.reset(startCapital);
		if (equityFloor > 0) harness.orders.equityFloor = equityFloor;
		if (costBps != 0) harness.orders.book.slippageBps = costBps;
		var seedInterp = new MuseInterp(harness);
		for (d in prog.decls) seedInterp.registerDeclPublic(d);

		var feed = new BarFeed(bars);
		harness.feed = feed;
		TradeBuiltins.resetCrossState();

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
		// --vm: run the backtest on the Tier-A bytecode VM (native-image-clean; no Truffle/GraalWasm),
		// falling back to the compiled/interp path for anything outside the VM's P0 subset. The
		// resulting metrics struct is byte-identical to the interp's (the VM parity gates guarantee it).
		var result:Dynamic = null;
		var backendName:String = target;
		var emittedFlag:Bool = false;
		var t0 = haxe.Timer.stamp();
		if (useVm) {
			var chunk:Null<musescript.vm.MuseChunk> = null;
			try { chunk = MuseVm.compileProgram(MuseCompiler.lower(prog)); }
			catch (_:musescript.vm.MuseBytecodeCompiler.VmUnsupported) {}
			if (chunk != null) { result = MuseVm.runChunk(harness, chunk, feed); backendName = "vm"; }
		}
		if (result == null) {
			var ex = MuseCompiler.compileEx(prog, { target: target, strict: strict });
			result = ex.fn(harness);
			backendName = ex.backend;
			emittedFlag = ex.emitted;
		}
		var runMs = (haxe.Timer.stamp() - t0) * 1000.0;

		var out:Dynamic = {
			ok: true,
			backend: backendName,
			execution: executionMode,
			emitted: emittedFlag,
			runMs: Math.fround(runMs * 1000) / 1000,
			barsPerSec: runMs > 0 ? Math.fround(bars.length / (runMs / 1000.0)) : null,
			bars: bars.length,
			trades: intField(result, "trades"),
			sharpe: finField(result, "sharpe"),
			maxDrawdown: finField(result, "maxDrawdown"),
			winRate: finField(result, "winRate"),
			finalEquity: finField(result, "finalEquity"),
			bankrupt: harness.orders.bankrupt
		};
		// Honesty flag: the requested target couldn't be emitted and the run fell
		// back to another backend. Callers scoring fitness should treat a
		// fallback verdict as suspect (or pass --strict to hard-fail instead).
		if (useVm && backendName != "vm")
			Reflect.setField(out, "fallback", true); // VM requested but the strategy fell to interp
		else if (!useVm && backendName != target)
			Reflect.setField(out, "fallback", true);
		// Per-tag fire counts from labelled order calls (`flat("profit_lock")`) -- surfaced only
		// when the strategy used any, so untagged runs stay byte-identical (silent no-op diagnostics).
		if (harness.orders.tagFires.keys().hasNext()) {
			var tagObj:Dynamic = {};
			for (k in harness.orders.tagFires.keys()) Reflect.setField(tagObj, k, harness.orders.tagFires.get(k));
			Reflect.setField(out, "exitTags", tagObj);
		}
		// IDE instrumentation payload (--instrument): the chart commands, per-bar
		// console log, executed fills, and equity curve — all already collected
		// during the run, returned only on demand so the fitness/batch path stays
		// lean and the golden-parity output is byte-identical without the flag.
		if (instrument) {
			// `.toArray()`: harness.orders.equity is a `GrowableVec<Float>` now (see
			// OrderSim.equity's doc comment) -- this field must be a real JSON-serializable
			// Array, not the abstract's underlying impl object.
			Reflect.setField(out, "equity", harness.orders.equity.toArray());
			Reflect.setField(out, "fills", harness.orders.fills);
			Reflect.setField(out, "chart", harness.chart.commands);
			Reflect.setField(out, "logs", harness.logs);
		}
		return out;
	}

	static function loadBars(tapePath:String, symbol:String, synthN:Int, seed:Int,
			murmurationConfigPath:String, murmurationSteps:Int):Array<Bar> {
		// Murmuration takes priority over --tape/--synth when requested: a genome/strategy gets
		// backtested against a freshly-simulated endogenous-price tape whose aux columns (ret,
		// mom, value_gap, vol, imb, spread, g, infl, inv_norm, unreal_pnl, capital_norm) are real
		// bound MuseScript identifiers (musescript.harness.HarnessContext's generic aux-series
		// mechanism), not a JS-side mock — this is what actually closes the loop for
		// distillation/derivation machinery pointed at this vocabulary.
		// #if kestrel-gated (see the import block at the top of this file): murmurationSteps is
		// hardcoded 0 in the public build (its only assignment site, the CLI flag parse above,
		// is also gated), so this branch is simply unreachable dead code there, not a runtime
		// difference — but the compile-time gate is what lets the public build skip needing
		// musescript/murmuration/ present at all.
		#if kestrel
		if (murmurationSteps > 0) {
			var cfg = MurmurationConfigs.withOverrides(
				murmurationConfigPath != "" ? haxe.Json.parse(readFile(murmurationConfigPath)) : null);
			if (murmurationConfigPath == "") cfg.seed = seed; // --seed still applies to the synthetic default
			var sim = new MurmurationSim(cfg);
			return MurmurationTape.toBars(sim.run(murmurationSteps));
		}
		#end
		if (tapePath == "") return BarFeed.synthetic(synthN, seed).all();
		var text = readFile(tapePath);
		if (symbol != "") text = filterSymbol(text, symbol);
		return OhlcvCsv.parse(text);
	}

	/**
	 * Run-constant instrument identity from the tape's `symbol`/`asset` columns (crypto/FX harness
	 * tapes carry both; plain OHLCV tapes carry neither → empty, and `asset_is`/`symbol_is` just
	 * return false). Reads the header + first data row (respecting an optional `--symbol` filter);
	 * the `--symbol` CLI value is the fallback/override for the symbol when no column exists.
	 */
	static function tapeMeta(tapePath:String, symbolArg:String):{symbol:String, assetClass:String} {
		if (tapePath == "") return {symbol: symbolArg, assetClass: ""};
		var text = try readFile(tapePath) catch (_:Dynamic) return {symbol: symbolArg, assetClass: ""};
		var lines = text.split("\r\n").join("\n").split("\r").join("\n").split("\n");
		if (lines.length < 2) return {symbol: symbolArg, assetClass: ""};
		var header = lines[0].split(",");
		var symIdx = -1, assetIdx = -1;
		for (i in 0...header.length) {
			switch (StringTools.trim(header[i]).toLowerCase()) {
				case "symbol": symIdx = i;
				case "asset" | "asset_class" | "assetclass" | "class": assetIdx = i;
				default:
			}
		}
		if (symIdx < 0 && assetIdx < 0) return {symbol: symbolArg, assetClass: ""};
		var sym = symbolArg, asset = "";
		for (i in 1...lines.length) {
			if (StringTools.trim(lines[i]) == "") continue;
			var cols = lines[i].split(",");
			var rowSym = symIdx >= 0 && symIdx < cols.length ? StringTools.trim(cols[symIdx]) : "";
			if (symbolArg != "" && rowSym != "" && rowSym != symbolArg) continue; // honor --symbol filter
			if (symbolArg == "" && rowSym != "") sym = rowSym;
			if (assetIdx >= 0 && assetIdx < cols.length) asset = StringTools.trim(cols[assetIdx]);
			break;
		}
		return {symbol: sym, assetClass: asset};
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
