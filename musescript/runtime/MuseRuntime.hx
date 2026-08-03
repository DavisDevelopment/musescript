package musescript.runtime;

import musescript.ast.MuseProgram;
import musescript.parse.MuseParser;
import musescript.compile.ModuleExpand;
import musescript.compile.TemplateExpand;
import musescript.compile.MuseCompiler;
import musescript.checker.MuseChecker;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;
import musescript.interp.MuseInterp;
import musescript.builtins.TradeBuiltins;

// Execution realism (order-book sim, limit/market/stop kinds, slippage,
// latency, market impact) is a scoped epic — see ROADMAP.md ("Execution
// realism"). Today's honest model: close-fill (or fillNextOpen) + per-side
// bps costs; see OrderKind.hx for why richer order types compose as rules
// on the sim side rather than new AST verbs.

/**
 * Client-side MuseScript execution engine for the Strategy Studio IDE.
 *
 * A pure Haxe→JS module (`@:expose`, no hxnodejs / no Sys deps) that runs a
 * full backtest IN THE BROWSER over bars passed as data — the interactivity
 * spine: edit → re-run client-side in <ms → charts/console/inspector update,
 * with no backend round-trip. Reuses the exact same parse/compile/harness
 * stack the CLI uses; only the file/subprocess I/O of GeneRunner is left out.
 *
 * Three execution tiers, selectable per call:
 *   - "interp": MuseInterp tree-walker — the steppable/debuggable path.
 *   - "js":     JsBackend + eval — the optimized ~1M bars/sec fast path (default).
 *   - "wasm":   StrategyWasmBackend — native WebAssembly (bare-metal). Requires
 *               in-browser WAT→WASM assembly (wired separately); until then this
 *               tier reports an honest error rather than silently falling back.
 *   - "auto":   js, letting MuseCompiler fall back to interp if emission fails.
 *
 * JS API (after `haxe build-runtime.hxml`):
 *   MuseRuntime.run(sourceString, barsArray, { tier, instrument, initialCash, seed })
 *   MuseRuntime.check(sourceString)   // structured diagnostics, no run
 *   MuseRuntime.checkWidget(source, { kind }) / MuseRuntime.runWidget(source, bars, { kind })
 *   MuseRuntime.pluginKinds()         // capability table JSON (widget/plugin gate)
 *   MuseRuntime.proveDeterminism(source, bars, { seed, engines })  // Initiative 4.1
 *   MuseRuntime.equityDigest(equity) / foundationDigest()           // proof helpers
 *
 * Successful runs attach `repro: { schemaVersion, seed, bootSeed, profile, backend }`
 * plus `equityDigest` / `fillDigest` when instrumented (Initiative 4.2 seed stamp).
 *
 * Instrumented runs also attach `truthReport` (Initiative 1 — Honest Backtest) unless
 * `opts.skipTruthReport` is true. Pass `nTrials` / `nullSharpe` / `purgeEmbargoApplied` /
 * `oosHeld` / `pbo` from the IDE; omit `nTrials` to use `TrialsSession.effectiveTrials()`.
 *
 * When `opts.honestOos` is true, Truth Report is scored on a purge/embargo OOS slice
 * (`oosFrac` default 0.25, `embargoBars` default 20) — full-tape metrics/chart stay
 * unchanged. Nested OOS re-run sets `honestOos=false` to avoid recursion.
 *
 * Initiative 3 — honesty-gated optimizer:
 *   MuseRuntime.optimize(source, bars, opts) / MuseRuntime.evolve(...)  // alias
 *   MuseRuntime.forecastFields()  // SProj / forecast reduction vocabulary (3.3)
 *
 * Initiative 5 — Report Card / Honest Ledger:
 *   Instrumented runs also attach `reportCard` (from Truth Report; seed/universe slots pending).
 *   MuseRuntime.buildReportCard(truthReport|payload) / seedRobustnessSweep(source, bars, opts)
 *   MuseRuntime.ledgerEntryFromTruth(truthReport) — serializable Honest Ledger entry
 *
 * Honest Leaderboard:
 *   MuseRuntime.evaluateLeaderboardEntry(entry, ctx) / rankLeaderboard(entries, ctx)
 */
@:expose("MuseRuntime")
class MuseRuntime {

	//TODO: document this, literally line-by-line, so I can always follow along c:

	/** No-op entry point; this module exists to `@:expose` its static API to JS. */
	static function main() {}

	/**
	 * Backtest `source` over `bars` (array of {open,high,low,close,volume,?time}).
	 * Returns a plain object: { ok, backend, execution, emitted, bars, trades,
	 * sharpe, maxDrawdown, winRate, finalEquity, equity, fills, chart, logs } —
	 * or { ok:false, error } on failure (never throws across the JS boundary).
	 */
	public static function run(source:String, ?bars:Array<Dynamic>, ?opts:Dynamic):Dynamic {
		try {
			var tier = optStr(opts, "tier", "js");
			var instrument = optBool(opts, "instrument", true);
			var initialCash = optFloat(opts, "initialCash", 100000);

			var prog = parse(source);
			var feed = new BarFeed(toBars(bars));

			var harness = new HarnessContext();
			harness.orders.reset(initialCash);
			// Per-fill slippage (bps, against the trader) for pending-book fills
			// (limit/stop/market spec orders). Legacy close-fills are unaffected.
			harness.orders.book.slippageBps = optFloat(opts, "slippageBps", 0);

			harness.feed = feed;
			TradeBuiltins.resetCrossState();

			var backend:String;
			var emitted:Bool;
			var result:Dynamic;

			if (tier == "interp") {
				var seed = new MuseInterp(harness);
				for (d in prog.decls) 
					seed.registerDeclPublic(d);
				applyParamOverrides(harness, opts);
				result = new MuseInterp(harness).runBacktest(prog, feed);
				backend = "interp";
				emitted = false;
			} 
			else if (tier == "wasm") {
				// In-browser WAT→WASM assembly (ROADMAP "In-browser WASM tier"):
				// musescript.compile.WatAssembler encodes the module directly —
				// no wabt.js dependency. Falls back to an honest error for
				// strategies outside the WASM on_bar subset (same as before).
				var emittedWat = musescript.compile.StrategyWasmBackend.emitOnBar(prog);
				if (emittedWat == null)
					return err('strategy is outside the WASM on_bar subset; use tier "js" or "interp"');
				var wasmBytes:Dynamic;
				try {
					wasmBytes = musescript.compile.WatAssembler.assemble(emittedWat.wat).getData();
				} catch (ex:Dynamic) {
					return err('wasm assembly failed: ${Std.string(ex)}');
				}
				var seed = new MuseInterp(harness);
				for (d in prog.decls)
					seed.registerDeclPublic(d);
				applyParamOverrides(harness, opts);
				var fn = musescript.compile.StrategyWasmBackend.compileFromBytes(prog, wasmBytes, emittedWat.strings);
				result = fn(harness);
				backend = "wasm";
				emitted = true;
			}
			else {
				// "js" / "auto": compile + run; MuseCompiler reports the real backend.
				var seed = new MuseInterp(harness);
				for (d in prog.decls) 
					seed.registerDeclPublic(d);
				applyParamOverrides(harness, opts);
				var ex = MuseCompiler.compileEx(prog, { target: "js", strict: false });
				result = ex.fn(harness);
				backend = ex.backend;
				emitted = ex.emitted;
			}

			var out = baseResult(backend, emitted, feed.length(), result);
			if (instrument) attachOrdersInstrumentation(out, harness);
			attachParams(out, harness);
			attachRepro(out, opts, backend,
				instrument ? Reflect.field(out, "equity") : null,
				instrument ? Reflect.field(out, "fills") : null);
			if (instrument) {
				var barsForOos:Array<Dynamic> = bars != null ? bars : barsToDyn(feed.all());
				finalizeTruthReport(out, opts, closesOf(feed.all()), {
					kind: "single", source: source, bars: barsForOos, bySym: null
				});
			}
			return out;
		} 
		catch (e:Dynamic) {
			return err(Std.string(e));
		}
	}

	/**
	 * Multi-symbol panel backtest. `bySym` is `{ SYM: [ {open,high,low,close,volume,?time}, ... ], ... }`.
	 * Strategies use `symbols` / `scan_top` / `rebalance_equal` / `portfolio_*`.
	 * Returns the usual metrics object, with equity/fills taken from `portfolio`.
	 */
	public static function runPanel(source:String, ?bySym:Dynamic, ?opts:Dynamic):Dynamic {
		try {
			var tier = optStr(opts, "tier", "js");
			var instrument = optBool(opts, "instrument", true);
			var initialCash = optFloat(opts, "initialCash", 100000);
			var prog = parse(source);
			var panel = toPanel(bySym);
			if (panel == null) return err("runPanel requires bySym: { SYM: bars[], ... }");

			var harness = new HarnessContext();
			harness.orders.reset(initialCash);
			harness.portfolio.reset(initialCash);
			// Honest execution: `fillNextOpen` decides at close[t] but fills at open[t+1], removing
			// the same-bar close→close lookahead (default false keeps legacy close-fill behavior).
			harness.panelFillNextOpen = optBool(opts, "fillNextOpen", false);
			// Per-side transaction cost (bps of traded notional) — commission + spread/slippage proxy.
			harness.portfolio.tradingCostBps = optFloat(opts, "costBps", 0);
			harness.panel = panel;
			harness.feed = panel.asBarFeed();
			TradeBuiltins.resetCrossState();

			var backend:String;
			var emitted:Bool;
			var result:Dynamic;
			if (tier == "interp") {
				var seed = new MuseInterp(harness);
				for (d in prog.decls) seed.registerDeclPublic(d);
				applyParamOverrides(harness, opts);
				result = new MuseInterp(harness).runPanelBacktest(prog, panel);
				backend = "interp";
				emitted = false;
			} else if (tier == "wasm") {
				return err("wasm tier does not support panel/portfolio strategies yet; use js or interp");
			} else {
				var seed2 = new MuseInterp(harness);
				for (d in prog.decls) seed2.registerDeclPublic(d);
				applyParamOverrides(harness, opts);
				var ex = MuseCompiler.compileEx(prog, { target: "js", strict: false });
				result = ex.fn(harness);
				backend = ex.backend;
				emitted = ex.emitted;
			}

			var out = baseResult(backend, emitted, panel.length(), result);
			Reflect.setField(out, "panel", true);
			Reflect.setField(out, "symbols", panel.symbols);
			if (instrument) {
				// See GeneRunner.hx's identical comment -- must be a real Array, not the
				// GrowableVec abstract's underlying impl object.
				Reflect.setField(out, "equity", harness.portfolio.equity.toArray());
				Reflect.setField(out, "fills", harness.portfolio.fills);
				Reflect.setField(out, "holdings", harness.portfolio.holdings());
				Reflect.setField(out, "chart", harness.chart.commands);
				Reflect.setField(out, "logs", harness.logs);
			}
			attachParams(out, harness);
			attachRepro(out, opts, backend,
				instrument ? Reflect.field(out, "equity") : null,
				instrument ? Reflect.field(out, "fills") : null);
			if (instrument) {
				// Panel null baseline: equal-weight buy-and-hold of the panel's primary feed closes.
				var feedBars = harness.feed != null ? harness.feed.all() : [];
				finalizeTruthReport(out, opts, closesOf(feedBars), {
					kind: "panel", source: source, bars: null, bySym: bySym
				});
			}
			return out;
		} catch (e:Dynamic) {
			return err(Std.string(e));
		}
	}

	/**
	 * Build a `PanelFeed` from in-memory `{ SYM: bars[], ... }` (same shape as
	 * `runPanel` / offline `PanelLoader` JSON). Browser-safe — no file I/O.
	 * File/CSV/DB panel loading lives in `PanelLoader` (CLI / Node / JVM).
	 */
	public static function panelFromBySym(bySym:Dynamic):Null<musescript.harness.PanelFeed> {
		return toPanel(bySym);
	}

	static function toPanel(bySym:Dynamic):Null<musescript.harness.PanelFeed> {
		if (bySym == null) return null;
		var map = new Map<String, Array<Bar>>();
		for (sym in Reflect.fields(bySym)) {
			var raw:Dynamic = Reflect.field(bySym, sym);
			if (!Std.isOfType(raw, Array)) continue;
			map.set(sym, toBars(cast raw));
		}
		if (!map.keys().hasNext()) return null;
		return musescript.harness.PanelFeed.fromSymbolBars(map);
	}

	/**
	 * Emit the WASM WAT + string table for `source` (the bare-metal tier's
	 * assembly input). The app assembles the returned `wat` via wabt.js, then
	 * calls `runWasm(source, bars, bytes)`. Returns { ok, wat, strings } or
	 * { ok:false, error } when the strategy is outside the numeric on_bar
	 * subset the WASM backend supports (use the js tier for those).
	 */
	public static function emitWat(source:String):Dynamic {
		try {
			var prog = parse(source);
			var e = musescript.compile.StrategyWasmBackend.emitOnBar(prog);
			if (e == null) return err("strategy is outside the WASM on_bar subset (use tier 'js')");
			return { ok: true, wat: e.wat, strings: e.strings };
		} catch (e:Dynamic) {
			return err(Std.string(e));
		}
	}

	/**
	 * Bare-metal tier: run `source` over `bars` against a WASM module the caller
	 * already assembled (`wasmBytes`, from `emitWat` + wabt.js). Native
	 * WebAssembly execution, fully client-side. Same instrumented result shape
	 * as `run`. Only available in the browser/JS build.
	 */
	public static function runWasm(source:String, bars:Array<Dynamic>, wasmBytes:Dynamic, ?opts:Dynamic):Dynamic {
		#if js
		try {
			var instrument = optBool(opts, "instrument", true);
			var initialCash = optFloat(opts, "initialCash", 100000);
			var prog = parse(source);
			var e = musescript.compile.StrategyWasmBackend.emitOnBar(prog);
			if (e == null) return err("strategy is outside the WASM on_bar subset (use tier 'js')");

			var feed = new BarFeed(toBars(bars));
			var harness = new HarnessContext();
			harness.orders.reset(initialCash);
			harness.feed = feed;
			TradeBuiltins.resetCrossState();

			// Register decls so @param defaults land, then apply UI overrides.
			var seed = new MuseInterp(harness);
			for (d in prog.decls) seed.registerDeclPublic(d);
			applyParamOverrides(harness, opts);

			var fn = musescript.compile.StrategyWasmBackend.compileFromBytes(prog, wasmBytes, e.strings);
			var result:Dynamic = fn(harness);

			var out = baseResult("wasm", true, feed.length(), result);
			if (instrument) attachOrdersInstrumentation(out, harness);
			attachParams(out, harness);
			attachRepro(out, opts, "wasm",
				instrument ? Reflect.field(out, "equity") : null,
				instrument ? Reflect.field(out, "fills") : null);
			if (instrument) {
				var barsForOos:Array<Dynamic> = bars != null ? bars : barsToDyn(feed.all());
				finalizeTruthReport(out, opts, closesOf(feed.all()), {
					kind: "wasm", source: source, bars: barsForOos, bySym: null, wasmBytes: wasmBytes
				});
			}
			return out;
		} catch (e:Dynamic) {
			return err(Std.string(e));
		}
		#else
		return err("runWasm is only available in the JS build");
		#end
	}

	/**
	 * Initiative 4.1 — callable determinism proof for Studio / Truth Report.
	 * See `musescript.repro.DeterminismProof.prove`.
	 */
	public static function proveDeterminism(source:String, ?bars:Array<Dynamic>, ?opts:Dynamic):Dynamic {
		return musescript.repro.DeterminismProof.prove(source, bars, opts);
	}

	/**
	 * Initiative 1 — evaluate a Truth Report from equity / trades / nullSharpe without a full run.
	 * `payload`: { equity:[], trades, nullSharpe?, closes?[], nTrials?, …TruthReportOpts }.
	 * When `nullSharpe` is omitted, buy-and-hold Sharpe is derived from `closes` (or equity itself).
	 */
	public static function evaluateTruthReport(payload:Dynamic):Dynamic {
		try {
			if (payload == null) return err("evaluateTruthReport requires a payload object");
			var equity:Array<Float> = Reflect.hasField(payload, "equity")
				? cast Reflect.field(payload, "equity") : null;
			if (equity == null) return err("evaluateTruthReport requires equity:[]");
			var trades = intField(payload, "trades");
			var closes:Array<Float> = Reflect.hasField(payload, "closes")
				? cast Reflect.field(payload, "closes") : null;
			var out:Dynamic = {
				ok: true,
				trades: trades,
				equity: equity,
				finalEquity: equity.length > 0 ? equity[equity.length - 1] : null,
				backend: Reflect.hasField(payload, "backend") ? Reflect.field(payload, "backend") : "js",
				equityDigest: Reflect.field(payload, "equityDigest"),
				fillDigest: Reflect.field(payload, "fillDigest")
			};
			attachTruthReport(out, payload, closes != null ? closes : []);
			return {
				ok: true,
				truthReport: Reflect.field(out, "truthReport"),
				reportCard: Reflect.field(out, "reportCard")
			};
		} catch (e:Dynamic) {
			return err(Std.string(e));
		}
	}

	/** Initiative 1.3 — reset / record / set / get session trial count (DSR deflation). */
	public static function trialsReset():Void {
		musescript.evo.rigor.TrialsSession.reset();
	}
	public static function trialsRecord():Int {
		return musescript.evo.rigor.TrialsSession.recordTrial();
	}
	public static function trialsSetCount(n:Int):Int {
		musescript.evo.rigor.TrialsSession.setCount(n);
		return musescript.evo.rigor.TrialsSession.getCount();
	}
	public static function trialsGetCount():Int {
		return musescript.evo.rigor.TrialsSession.getCount();
	}

	/**
	 * Initiative 3 — honesty-gated param search ("Evolve this strategy").
	 * Enumerates `@param` / `tune`/`optimize` holes, Truth-Report-gates every candidate,
	 * and returns only non-overfit survivors — or an honest empty result
	 * (`reason: "no robust strategy found"` / `"nothing beat the null"`).
	 *
	 * `opts`: { metric, method, seed, initialCash, params, paramNames, acceptVerdicts,
	 *   nTrials, tier, oosHeld, purgeEmbargoApplied, pbo, minTrades }
	 * Default acceptVerdicts: ["Robust","Fragile"] (Overfit / Coin-flip never ship).
	 */
	public static function optimize(source:String, ?bars:Array<Dynamic>, ?opts:Dynamic):Dynamic {
		try {
			var typed = toBars(bars);
			return musescript.harness.HonestOptimize.search(source, typed, opts);
		} catch (e:Dynamic) {
			return err(Std.string(e));
		}
	}

	/** Alias for `optimize` — Studio "Evolve this strategy" entry point. */
	public static function evolve(source:String, ?bars:Array<Dynamic>, ?opts:Dynamic):Dynamic {
		return optimize(source, bars, opts);
	}

	/**
	 * Initiative 5.1 — build a Report Card from a Truth Report dyn (or evaluateTruthReport payload).
	 * Does not invent metrics — skill/profit come from the Truth Report; seed/universe
	 * slots stay pending unless `seedMetrics` / `instruments` are supplied.
	 */
	public static function buildReportCard(payload:Dynamic):Dynamic {
		try {
			if (payload == null) return err("buildReportCard requires a truthReport or payload");
			var trDyn:Dynamic = Reflect.hasField(payload, "verdict")
				? payload
				: (Reflect.hasField(payload, "truthReport") ? Reflect.field(payload, "truthReport") : null);
			if (trDyn == null) return err("buildReportCard requires truthReport with verdict");
			var tr = musescript.evo.rigor.TruthReport.fromDyn(trDyn);
			var seedMetrics:Null<Array<Float>> = null;
			var seedThreshold:Null<Float> = null;
			var instruments:Null<Array<{name:String, metric:Float, go:Bool}>> = null;
			var strategyLabel:Null<String> = null;
			var tape:Null<String> = null;
			if (Reflect.hasField(payload, "seedMetrics"))
				seedMetrics = cast Reflect.field(payload, "seedMetrics");
			if (Reflect.hasField(payload, "seedThreshold") && Reflect.field(payload, "seedThreshold") != null)
				seedThreshold = (Reflect.field(payload, "seedThreshold") : Float);
			if (Reflect.hasField(payload, "instruments"))
				instruments = cast Reflect.field(payload, "instruments");
			if (Reflect.hasField(payload, "strategyLabel"))
				strategyLabel = Std.string(Reflect.field(payload, "strategyLabel"));
			if (Reflect.hasField(payload, "tape"))
				tape = Std.string(Reflect.field(payload, "tape"));
			var card = musescript.evo.rigor.ReportCard.fromTruthReport(tr, {
				seedMetrics: seedMetrics,
				seedThreshold: seedThreshold,
				instruments: instruments,
				strategyLabel: strategyLabel,
				tape: tape
			});
			return { ok: true, reportCard: card.toDyn() };
		} catch (e:Dynamic) {
			return err(Std.string(e));
		}
	}

	/**
	 * Initiative 5.1 — light seed-robustness sweep: re-run the strategy at each seed,
	 * collect Sharpes, aggregate with SeedRobustness (median, not max). Returns an
	 * updated reportCard when `truthReport` is also supplied in opts.
	 *
	 * `opts.seeds` default [42, 43, 44]; nested runs use skipTruthReport for speed
	 * then score skill vs the primary nullSharpe from opts / first run.
	 */
	public static function seedRobustnessSweep(source:String, ?bars:Array<Dynamic>, ?opts:Dynamic):Dynamic {
		try {
			var seeds:Array<Int> = [42, 43, 44];
			if (opts != null && Reflect.hasField(opts, "seeds") && Reflect.field(opts, "seeds") != null) {
				var raw:Dynamic = Reflect.field(opts, "seeds");
				if (Std.isOfType(raw, Array)) {
					seeds = [];
					for (x in (raw : Array<Dynamic>)) seeds.push(Std.int((x : Float)));
				}
			}
			if (seeds.length < 1) return err("seedRobustnessSweep requires at least one seed");

			var metrics:Array<Float> = [];
			var perSeed:Array<Dynamic> = [];
			var nullSharpe = Math.NaN;
			if (opts != null && Reflect.hasField(opts, "nullSharpe") && Reflect.field(opts, "nullSharpe") != null)
				nullSharpe = (Reflect.field(opts, "nullSharpe") : Float);

			for (s in seeds) {
				var nested = cloneRunOpts(opts);
				Reflect.setField(nested, "seed", s);
				Reflect.setField(nested, "skipTruthReport", true);
				Reflect.setField(nested, "honestOos", false);
				var r = run(source, bars, nested);
				if (r == null || Reflect.field(r, "ok") != true) {
					perSeed.push({ seed: s, ok: false, error: Reflect.field(r, "error") });
					continue;
				}
				var sharpe = Reflect.field(r, "sharpe");
				var sr = sharpe != null ? (sharpe : Float) : Math.NaN;
				if (Math.isFinite(sr)) metrics.push(sr);
				perSeed.push({
					seed: s, ok: true, sharpe: Math.isFinite(sr) ? sr : null,
					trades: Reflect.field(r, "trades")
				});
				if (!Math.isFinite(nullSharpe)) {
					var closes = closesOf(toBars(bars));
					var bh = buyHoldFromCloses(closes, optFloat(opts, "initialCash", 100000));
					nullSharpe = bh.sharpe;
				}
			}

			var thr = Math.isFinite(nullSharpe) ? nullSharpe : 0.0;
			if (opts != null && Reflect.hasField(opts, "seedThreshold") && Reflect.field(opts, "seedThreshold") != null)
				thr = (Reflect.field(opts, "seedThreshold") : Float);
			var verdict = musescript.evo.rigor.SeedRobustness.verdict(metrics, thr);
			var slot = musescript.evo.rigor.ReportCard.fromSeedVerdict(verdict);

			var out:Dynamic = {
				ok: true,
				seedRobustness: slot,
				metrics: metrics,
				perSeed: perSeed,
				threshold: thr,
				nullSharpe: Math.isFinite(nullSharpe) ? nullSharpe : null
			};

			var trDyn:Dynamic = null;
			if (opts != null && Reflect.hasField(opts, "truthReport"))
				trDyn = Reflect.field(opts, "truthReport");
			if (trDyn != null) {
				var card = musescript.evo.rigor.ReportCard.fromTruthReport(
					musescript.evo.rigor.TruthReport.fromDyn(trDyn),
					{ seedMetrics: metrics, seedThreshold: thr }
				);
				Reflect.setField(out, "reportCard", card.toDyn());
			}
			return out;
		} catch (e:Dynamic) {
			return err(Std.string(e));
		}
	}

	/**
	 * Initiative 5.2 — build one Honest Ledger entry from a Truth Report dyn.
	 * IDE persists the list; this only shapes the entry (GO / CAUTION / NO-GO).
	 */
	public static function ledgerEntryFromTruth(payload:Dynamic):Dynamic {
		try {
			if (payload == null) return err("ledgerEntryFromTruth requires a truthReport");
			var trDyn:Dynamic = Reflect.hasField(payload, "verdict")
				? payload
				: (Reflect.hasField(payload, "truthReport") ? Reflect.field(payload, "truthReport") : null);
			if (trDyn == null) return err("ledgerEntryFromTruth requires truthReport with verdict");
			var tr = musescript.evo.rigor.TruthReport.fromDyn(trDyn);
			var meta:{
				?at:String, ?id:String, ?strategyLabel:String, ?tape:String,
				?skillVsNull:Float, ?profitVsBaseline:Float
			} = {};
			if (Reflect.hasField(payload, "at")) meta.at = Std.string(Reflect.field(payload, "at"));
			if (Reflect.hasField(payload, "id")) meta.id = Std.string(Reflect.field(payload, "id"));
			if (Reflect.hasField(payload, "strategyLabel"))
				meta.strategyLabel = Std.string(Reflect.field(payload, "strategyLabel"));
			if (Reflect.hasField(payload, "tape")) meta.tape = Std.string(Reflect.field(payload, "tape"));
			var entry = musescript.evo.rigor.HonestLedger.entryFromTruth(tr, meta);
			return { ok: true, entry: musescript.evo.rigor.HonestLedger.entryToDyn(entry) };
		} catch (e:Dynamic) {
			return err(Std.string(e));
		}
	}

	/**
	 * Honest Leaderboard — evaluate one entry (field-N-deflated DSR, lower-CI, gates).
	 * `entry`: { returns:[], trades, pbo?, seedCiLos?, accountTrials?, id?, label?, verdict?, author? }
	 * `ctx`: { fieldN, minTrades?, accountTrials?, nBoot?, bootSeed?, nullValue? }
	 */
	public static function evaluateLeaderboardEntry(entry:Dynamic, ?ctx:Dynamic):Dynamic {
		try {
			if (entry == null) return err("evaluateLeaderboardEntry requires entry");
			var parsed = parseLeaderboardEntry(entry);
			if (parsed == null) return err("evaluateLeaderboardEntry requires returns:[] and trades");
			var c = parseLeaderboardCtx(ctx);
			var score = musescript.evo.rigor.LeaderboardScore.evaluate(parsed, c);
			return { ok: true, score: musescript.evo.rigor.LeaderboardScore.scoreToDyn(score) };
		} catch (e:Dynamic) {
			return err(Std.string(e));
		}
	}

	/**
	 * Honest Leaderboard — rank a field. Eligible → wall by rankStat desc;
	 * ineligible → failed (never vanity-ranked).
	 * `entries`: array of entry objects (see evaluateLeaderboardEntry).
	 * `ctx.fieldN` defaults to entries.length when omitted/≤0.
	 */
	public static function rankLeaderboard(entries:Dynamic, ?ctx:Dynamic):Dynamic {
		try {
			var list:Array<Dynamic> = [];
			if (entries != null && Std.isOfType(entries, Array)) {
				for (raw in (entries : Array<Dynamic>)) {
					var e = parseLeaderboardEntry(raw);
					if (e != null) list.push(e);
				}
			}
			var c = parseLeaderboardCtx(ctx);
			var fieldN:Int = Reflect.field(c, "fieldN");
			if (fieldN < 1) {
				fieldN = list.length > 0 ? list.length : 1;
				Reflect.setField(c, "fieldN", fieldN);
			}
			var ranked = musescript.evo.rigor.LeaderboardScore.rank(cast list, cast c);
			return { ok: true, ranked: musescript.evo.rigor.LeaderboardScore.rankToDyn(ranked) };
		} catch (e:Dynamic) {
			return err(Std.string(e));
		}
	}

	static function parseLeaderboardCtx(ctx:Dynamic):Dynamic {
		var fieldN = 1;
		if (ctx != null && Reflect.hasField(ctx, "fieldN") && Reflect.field(ctx, "fieldN") != null)
			fieldN = Std.int((Reflect.field(ctx, "fieldN") : Float));
		if (fieldN < 1) fieldN = 1;
		var out:Dynamic = { fieldN: fieldN };
		if (ctx == null) return out;
		if (Reflect.hasField(ctx, "minTrades") && Reflect.field(ctx, "minTrades") != null)
			Reflect.setField(out, "minTrades", Std.int((Reflect.field(ctx, "minTrades") : Float)));
		if (Reflect.hasField(ctx, "accountTrials") && Reflect.field(ctx, "accountTrials") != null)
			Reflect.setField(out, "accountTrials", Std.int((Reflect.field(ctx, "accountTrials") : Float)));
		if (Reflect.hasField(ctx, "nBoot") && Reflect.field(ctx, "nBoot") != null)
			Reflect.setField(out, "nBoot", Std.int((Reflect.field(ctx, "nBoot") : Float)));
		if (Reflect.hasField(ctx, "bootSeed") && Reflect.field(ctx, "bootSeed") != null)
			Reflect.setField(out, "bootSeed", Std.int((Reflect.field(ctx, "bootSeed") : Float)));
		if (Reflect.hasField(ctx, "nullValue") && Reflect.field(ctx, "nullValue") != null)
			Reflect.setField(out, "nullValue", (Reflect.field(ctx, "nullValue") : Float));
		if (Reflect.hasField(ctx, "seedSet") && Reflect.field(ctx, "seedSet") != null
			&& Std.isOfType(Reflect.field(ctx, "seedSet"), Array)) {
			var seeds:Array<Int> = [];
			for (x in (Reflect.field(ctx, "seedSet") : Array<Dynamic>))
				seeds.push(Std.int((x : Float)));
			Reflect.setField(out, "seedSet", seeds);
		}
		return out;
	}

	static function parseLeaderboardEntry(raw:Dynamic):Null<Dynamic> {
		if (raw == null) return null;
		var returns:Array<Float> = null;
		if (Reflect.hasField(raw, "returns") && Reflect.field(raw, "returns") != null)
			returns = cast Reflect.field(raw, "returns");
		else if (Reflect.hasField(raw, "equity") && Reflect.field(raw, "equity") != null) {
			var eq:Array<Float> = cast Reflect.field(raw, "equity");
			returns = musescript.harness.Metrics.returnsFromEquity(eq);
		} else if (Reflect.hasField(raw, "oosEquity") && Reflect.field(raw, "oosEquity") != null) {
			var oos:Array<Float> = cast Reflect.field(raw, "oosEquity");
			returns = musescript.harness.Metrics.returnsFromEquity(oos);
		}
		if (returns == null) return null;
		var trades = Reflect.hasField(raw, "trades") ? Std.int((Reflect.field(raw, "trades") : Float)) : 0;
		var e:Dynamic = { returns: returns, trades: trades };
		if (Reflect.hasField(raw, "pbo")) {
			var p = Reflect.field(raw, "pbo");
			Reflect.setField(e, "pbo", p == null ? null : (p : Float));
		}
		if (Reflect.hasField(raw, "seedCiLos") && Reflect.field(raw, "seedCiLos") != null
			&& Std.isOfType(Reflect.field(raw, "seedCiLos"), Array))
			Reflect.setField(e, "seedCiLos", Reflect.field(raw, "seedCiLos"));
		if (Reflect.hasField(raw, "accountTrials") && Reflect.field(raw, "accountTrials") != null)
			Reflect.setField(e, "accountTrials", Std.int((Reflect.field(raw, "accountTrials") : Float)));
		if (Reflect.hasField(raw, "id") && Reflect.field(raw, "id") != null)
			Reflect.setField(e, "id", Std.string(Reflect.field(raw, "id")));
		if (Reflect.hasField(raw, "label") && Reflect.field(raw, "label") != null)
			Reflect.setField(e, "label", Std.string(Reflect.field(raw, "label")));
		else if (Reflect.hasField(raw, "strategyLabel") && Reflect.field(raw, "strategyLabel") != null)
			Reflect.setField(e, "label", Std.string(Reflect.field(raw, "strategyLabel")));
		if (Reflect.hasField(raw, "verdict") && Reflect.field(raw, "verdict") != null)
			Reflect.setField(e, "verdict", Std.string(Reflect.field(raw, "verdict")));
		if (Reflect.hasField(raw, "author") && Reflect.field(raw, "author") != null)
			Reflect.setField(e, "author", Std.string(Reflect.field(raw, "author")));
		if (Reflect.hasField(raw, "category") && Reflect.field(raw, "category") != null)
			Reflect.setField(e, "category", Std.string(Reflect.field(raw, "category")));
		return e;
	}

	/**
	 * Initiative 3.3 — forecast reduction vocabulary for `SProj(name, field)` /
	 * host-decorated aux series. Studio/docs: `forecast("regime").entropy` maps to
	 * field `"entropy"` on a regime/lattice/auction host projection.
	 */
	public static function forecastFields():Dynamic {
		return {
			ok: true,
			schema: "mederos.forecastFields.v1",
			fields: [
				{ field: "p50", aliases: ["mean", "poc"], note: "price mid / auction POC" },
				{ field: "p05", aliases: [], note: "lower price band" },
				{ field: "p95", aliases: [], note: "upper price band" },
				{ field: "spread", aliases: [], note: "band width (p95−p05)" },
				{ field: "prob_up", aliases: ["breakout_prob"], note: "P(up) / auction breakout-up mass" },
				{ field: "entropy", aliases: [], note: "count / regime ambiguity (high = uncertain)" },
				{ field: "inv", aliases: [], note: "invalidation price (lattice; often NaN on regime/auction)" },
				{ field: "dist_inv", aliases: [], note: "distance to invalidation" },
				{ field: "top_mass", aliases: [], note: "posterior mass on preferred count" },
				{ field: "nest", aliases: [], note: "soft nest score across degrees" },
				{ field: "label", aliases: [], note: "opaque label code for viz" }
			],
			hosts: ["lattice", "regime", "auction", "mcmc"],
			usage: {
				evo: 'SProj("ew_0", "entropy")',
				studioNote: "Co-evolution Boundary X decorates bars with Expand.projRef columns; authored MuseScript can read the same reductions as aux series once a forecast host is bound.",
				doc: "musescript/ew/FORECAST_STRATEGY_INPUTS.md"
			}
		};
	}

	/**
	 * Initiative 1 — CSCV PBO from a trial cloud.
	 * `perf` is `[[sliceScore…], …]` (strategies × even #slices ≥ 2).
	 * Returns `{ ok, pbo }` or `{ ok:false, error, pbo:null }` — never invents a number.
	 */
	public static function estimatePbo(perf:Array<Array<Float>>, ?maxCombos:Int):Dynamic {
		try {
			if (perf == null || perf.length < 1)
				return { ok: false, error: "estimatePbo requires perf[strategy][slice]", pbo: null };
			var pbo = musescript.evo.rigor.Pbo.estimate(perf, maxCombos != null ? maxCombos : 2000);
			if (!Math.isFinite(pbo))
				return { ok: false, error: "PBO undefined — need ≥1 strategy and even #slices ≥ 2", pbo: null };
			return { ok: true, pbo: pbo };
		} catch (e:Dynamic) {
			return { ok: false, error: Std.string(e), pbo: null };
		}
	}

	/** Purge/embargo split helper for IDE (same as hardened instrument). */
	public static function purgeEmbargoSplit(n:Int, ?oosFrac:Float, ?embargoBars:Int):Dynamic {
		var frac = oosFrac != null ? oosFrac : 0.25;
		var emb = embargoBars != null ? embargoBars : 20;
		var s = musescript.evo.rigor.PurgeEmbargo.split(n, frac, emb);
		return {
			ok: true,
			isEnd: s.isEnd,
			oosStart: s.oosStart,
			embargo: s.embargo,
			purged: s.purged,
			oosFrac: frac,
			n: n
		};
	}

	/** Equity-curve bit digest (16-hex). Same as `result.equityDigest` after a run. */
	public static function equityDigest(equity:Array<Float>):String {
		return musescript.repro.EquityDigest.of(equity);
	}

	/** DetParityDump foundation digest — CI/golden parity substrate fingerprint. */
	public static function foundationDigest():String {
		return musescript.repro.DeterminismProof.foundationDigest();
	}

	/**
	 * Open a bar-stepping debug session over the interp tier (see
	 * MuseDebugSession). Also ensures the debugger class is retained in the
	 * build. JS may equivalently use `new MuseDebugSession(source, bars)`.
	 */
	public static function debug(source:String, ?bars:Array<Dynamic>):MuseDebugSession {
		return new MuseDebugSession(source, bars);
	}

	/** Structured diagnostics for `source` (no run). { ok, diagnostics:[...] }. */
	public static function check(source:String, ?opts:Dynamic):Dynamic {
		try {
			var prog = parse(source);
			var strict = optBool(opts, "strict", false);
			var checker = new MuseChecker({ strict: strict });
			var diags = checker.checkEx(prog);
			return { ok: true, diagnostics: [for (d in diags) musescript.checker.Diagnostics.toJson(d)] };
		} catch (e:Dynamic) {
			return err(Std.string(e));
		}
	}

	/**
	 * Plugin/widget capability table (kinds × builtin classes). Hosts should
	 * call this instead of maintaining a regex denylist for order verbs.
	 */
	public static function pluginKinds():Dynamic {
		return musescript.types.PluginCapabilities.tableJson();
	}

	/**
	 * Parse + MuseHost-lower + audit `source` under plugin kind
	 * (`opts.kind`, default `"panel"` — FlexLayout widgets need plot + log).
	 * Never throws across the JS boundary.
	 */
	public static function checkWidget(source:String, ?opts:Dynamic):Dynamic {
		try {
			var kind = resolvePluginKind(opts);
			var prog = parse(source);
			var audit = musescript.types.PluginCapabilities.audit(prog, kind);
			if (audit.ok == true)
				return { ok: true, kind: kind.label(), violations: [] };
			return {
				ok: false,
				kind: kind.label(),
				error: Reflect.field(audit, "error"),
				violations: Reflect.field(audit, "violations")
			};
		} catch (e:Dynamic) {
			return err(Std.string(e));
		}
	}

	/**
	 * Run a widget / plugin program under a declared kind. Audits capabilities
	 * first, then delegates to `run` with Truth Report skipped by default
	 * (widgets are display compute, not honest-backtest entries).
	 *
	 * `opts.kind`: `"compute"` | `"chart"` | `"panel"` (default) | `"scanner"`.
	 * Pass the same bars/params shape as `run`. Mobile should replace its
	 * host-side order-verb regex with `checkWidget` / `runWidget`.
	 */
	public static function runWidget(source:String, ?bars:Array<Dynamic>, ?opts:Dynamic):Dynamic {
		var gate = checkWidget(source, opts);
		if (gate.ok != true) return gate;
		var runOpts:Dynamic = {};
		if (opts != null) {
			for (k in Reflect.fields(opts))
				Reflect.setField(runOpts, k, Reflect.field(opts, k));
		}
		if (!Reflect.hasField(runOpts, "skipTruthReport"))
			Reflect.setField(runOpts, "skipTruthReport", true);
		if (!Reflect.hasField(runOpts, "instrument"))
			Reflect.setField(runOpts, "instrument", true);
		var out = run(source, bars, runOpts);
		if (out != null && Reflect.hasField(out, "ok") && out.ok == true)
			Reflect.setField(out, "kind", Reflect.field(gate, "kind"));
		return out;
	}

	static function resolvePluginKind(opts:Dynamic):musescript.types.PluginKind {
		var raw = optStr(opts, "kind", "panel");
		return musescript.types.PluginKind.parse(raw);
	}

	// --- internals ------------------------------------------------------------

	/**
	 * The shared success-result envelope every tier returns across the JS
	 * boundary: { ok, backend, emitted, bars } + the finite-or-null metric
	 * quintet pulled off a BacktestResult-shaped `result`.
	 */
	static function baseResult(backend:String, emitted:Bool, bars:Int, result:Dynamic):Dynamic {
		return {
			ok: true,
			backend: backend,
			emitted: emitted,
			bars: bars,
			trades: intField(result, "trades"),
			sharpe: finF(fieldF(result, "sharpe")),
			maxDrawdown: finF(fieldF(result, "maxDrawdown")),
			winRate: finF(fieldF(result, "winRate")),
			finalEquity: finF(fieldF(result, "finalEquity"))
		};
	}

	/** Single-symbol instrumentation payload (equity/fills from `orders`). */
	static function attachOrdersInstrumentation(out:Dynamic, harness:HarnessContext):Void {
		// See GeneRunner.hx's identical comment -- must be a real Array, not the
		// GrowableVec abstract's underlying impl object.
		Reflect.setField(out, "equity", harness.orders.equity.toArray());
		Reflect.setField(out, "fills", harness.orders.fills);
		Reflect.setField(out, "chart", harness.chart.commands);
		Reflect.setField(out, "logs", harness.logs);
	}

	/** Apply Studio/UI param overrides after @param registration. Accepts a
	 * plain object `{ name: value, … }` or an array of `{ name, value }`. */
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

	/** Serialize ParamRegistry into the run result for Studio sliders. */
	static function attachParams(out:Dynamic, harness:HarnessContext):Void {
		var arr:Array<Dynamic> = [];
		for (n in harness.params.names()) {
			var o = harness.params.getOpts(n);
			arr.push({
				name: n,
				value: harness.params.get(n),
				min: o != null ? o.min : null,
				max: o != null ? o.max : null,
				step: o != null ? o.step : null,
				tune: o != null ? o.tune : null
			});
		}
		Reflect.setField(out, "params", arr);
	}

	/**
	 * Initiative 4.2 — stamp every successful run with seed + digests so a
	 * shareable Truth Report can be re-verified later.
	 */
	static function attachRepro(out:Dynamic, opts:Dynamic, backend:String,
			equity:Null<Array<Float>>, fills:Dynamic):Void {
		var seed = optInt(opts, "seed", musescript.repro.ReproStamp.DEFAULT_SEED);
		var boot = optInt(opts, "bootSeed", seed);
		var profile = optStr(opts, "profile", "studio");
		var stamp = musescript.repro.ReproStamp.make({
			seed: seed, bootSeed: boot, profile: profile, backend: backend
		});
		Reflect.setField(out, "repro", stamp.toJson());
		if (equity != null)
			Reflect.setField(out, "equityDigest", musescript.repro.EquityDigest.of(equity));
		if (fills != null)
			Reflect.setField(out, "fillDigest", musescript.evo.FillHash.of(fills));
	}

	/**
	 * Initiative 1 — attach Honest Backtest Truth Report onto an instrumented run result.
	 * When `opts.honestOos` is true, re-runs on a purge/embargo OOS slice and marks
	 * `oosHeld` / `purgeEmbargoApplied` honestly (full-tape chart/metrics unchanged).
	 * If OOS is too short or the nested run fails, falls back without faking the flags.
	 */
	static function finalizeTruthReport(
		out:Dynamic, opts:Dynamic, fullCloses:Array<Float>,
		ctx:{kind:String, source:String, bars:Null<Array<Dynamic>>, bySym:Null<Dynamic>, ?wasmBytes:Dynamic}
	):Void {
		if (optBool(opts, "skipTruthReport", false)) return;

		// Caller already applied a real OOS hold — trust their flags; no nested re-run.
		var callerHeld = optBool(opts, "oosHeld", false) || optBool(opts, "purgeEmbargoApplied", false);
		if (!optBool(opts, "honestOos", false) || callerHeld) {
			attachTruthReport(out, opts, fullCloses);
			return;
		}

		var n = tapeLength(ctx);
		if (n < 80) {
			Reflect.setField(out, "oosSplit", {
				applied: false, reason: "tape too short for purge/embargo OOS (need ≥80 bars)", n: n
			});
			attachTruthReport(out, opts, fullCloses);
			return;
		}

		var oosFrac = optFloat(opts, "oosFrac", 0.25);
		var embargo = optInt(opts, "embargoBars", 20);
		// Keep a usable OOS window on short Studio tapes — shrink embargo before giving up.
		var minOos = 40;
		var rawOos = Std.int(n * oosFrac);
		if (rawOos < 1) rawOos = 1;
		if (rawOos - embargo < minOos && embargo > 0) {
			var shrink = rawOos - minOos;
			embargo = shrink > 0 ? shrink : 0;
		}
		var split = musescript.evo.rigor.PurgeEmbargo.split(n, oosFrac, embargo);
		var oosLen = n - split.oosStart;
		if (oosLen < minOos || split.isEnd < 40) {
			Reflect.setField(out, "oosSplit", {
				applied: false,
				reason: 'OOS/IS too short after purge (IS=${split.isEnd} OOS=$oosLen embargo=${split.embargo})',
				isEnd: split.isEnd, oosStart: split.oosStart, embargo: split.embargo, n: n
			});
			attachTruthReport(out, opts, fullCloses);
			return;
		}

		var nestedOpts = cloneRunOpts(opts);
		Reflect.setField(nestedOpts, "honestOos", false);
		Reflect.setField(nestedOpts, "skipTruthReport", true);
		Reflect.setField(nestedOpts, "instrument", true);
		Reflect.setField(nestedOpts, "oosHeld", false);
		Reflect.setField(nestedOpts, "purgeEmbargoApplied", false);

		var oosRun:Dynamic = null;
		if (ctx.kind == "panel") {
			var sliced = slicePanel(ctx.bySym, split.oosStart, n);
			if (sliced == null) {
				Reflect.setField(out, "oosSplit", { applied: false, reason: "panel slice failed", n: n });
				attachTruthReport(out, opts, fullCloses);
				return;
			}
			oosRun = runPanel(ctx.source, sliced, nestedOpts);
		} else if (ctx.kind == "wasm") {
			#if js
			var oosBars = ctx.bars != null ? ctx.bars.slice(split.oosStart, n) : null;
			if (oosBars == null || oosBars.length < 40) {
				Reflect.setField(out, "oosSplit", { applied: false, reason: "wasm OOS bars missing", n: n });
				attachTruthReport(out, opts, fullCloses);
				return;
			}
			oosRun = runWasm(ctx.source, oosBars, ctx.wasmBytes, nestedOpts);
			#else
			Reflect.setField(out, "oosSplit", { applied: false, reason: "wasm OOS unavailable", n: n });
			attachTruthReport(out, opts, fullCloses);
			return;
			#end
		} else {
			var oosBars2 = ctx.bars != null ? ctx.bars.slice(split.oosStart, n) : null;
			if (oosBars2 == null) {
				// Synthetic path — rebuild from typed closes length via fresh synthetic slice not available;
				// fall back honestly.
				Reflect.setField(out, "oosSplit", {
					applied: false, reason: "bars array required for honestOos", n: n
				});
				attachTruthReport(out, opts, fullCloses);
				return;
			}
			oosRun = run(ctx.source, oosBars2, nestedOpts);
		}

		if (oosRun == null || Reflect.field(oosRun, "ok") != true) {
			Reflect.setField(out, "oosSplit", {
				applied: false,
				reason: "OOS re-run failed"
					+ (oosRun != null && Reflect.hasField(oosRun, "error")
						? ': ${Std.string(Reflect.field(oosRun, "error"))}' : ""),
				isEnd: split.isEnd, oosStart: split.oosStart, embargo: split.embargo, n: n
			});
			attachTruthReport(out, opts, fullCloses);
			return;
		}

		var oosCloses:Array<Float> = [];
		if (ctx.kind == "panel") {
			oosCloses = fullCloses.length > split.oosStart ? fullCloses.slice(split.oosStart) : fullCloses;
		} else if (ctx.bars != null) {
			var sliceBars = ctx.bars.slice(split.oosStart, n);
			for (b in sliceBars) oosCloses.push(num(b, "close"));
		} else {
			oosCloses = fullCloses.length > split.oosStart ? fullCloses.slice(split.oosStart) : fullCloses;
		}

		var trOpts = cloneRunOpts(opts);
		Reflect.setField(trOpts, "honestOos", false);
		Reflect.setField(trOpts, "purgeEmbargoApplied", true);
		Reflect.setField(trOpts, "oosHeld", true);
		Reflect.setField(trOpts, "embargoBars", split.embargo);
		// Prefer OOS digests for the Truth Report stamp (re-verifiable on OOS slice).
		var trCarrier:Dynamic = {
			ok: true,
			trades: Reflect.field(oosRun, "trades"),
			equity: Reflect.field(oosRun, "equity"),
			finalEquity: Reflect.field(oosRun, "finalEquity"),
			backend: Reflect.hasField(out, "backend") ? Reflect.field(out, "backend") : Reflect.field(oosRun, "backend"),
			equityDigest: Reflect.field(oosRun, "equityDigest"),
			fillDigest: Reflect.field(oosRun, "fillDigest")
		};
		attachTruthReport(trCarrier, trOpts, oosCloses);
		Reflect.setField(out, "truthReport", Reflect.field(trCarrier, "truthReport"));
		if (Reflect.hasField(trCarrier, "reportCard"))
			Reflect.setField(out, "reportCard", Reflect.field(trCarrier, "reportCard"));
		Reflect.setField(out, "oosSplit", {
			applied: true,
			isEnd: split.isEnd,
			oosStart: split.oosStart,
			embargo: split.embargo,
			purged: split.purged,
			oosFrac: oosFrac,
			oosBars: oosLen,
			isBars: split.isEnd,
			n: n,
			oosTrades: Reflect.field(oosRun, "trades"),
			oosSharpe: Reflect.field(oosRun, "sharpe")
		});
		// Expose OOS equity for PBO cloud / Studio without replacing full-tape chart.
		Reflect.setField(out, "oosEquity", Reflect.field(oosRun, "equity"));
		Reflect.setField(out, "oosTrades", Reflect.field(oosRun, "trades"));
	}

	static function tapeLength(ctx:{kind:String, source:String, bars:Null<Array<Dynamic>>, bySym:Null<Dynamic>, ?wasmBytes:Dynamic}):Int {
		if (ctx.kind == "panel" && ctx.bySym != null) {
			for (sym in Reflect.fields(ctx.bySym)) {
				var raw:Dynamic = Reflect.field(ctx.bySym, sym);
				if (Std.isOfType(raw, Array)) return (raw : Array<Dynamic>).length;
			}
			return 0;
		}
		return ctx.bars != null ? ctx.bars.length : 0;
	}

	static function slicePanel(bySym:Dynamic, from:Int, to:Int):Null<Dynamic> {
		if (bySym == null) return null;
		var out:Dynamic = {};
		var any = false;
		for (sym in Reflect.fields(bySym)) {
			var raw:Dynamic = Reflect.field(bySym, sym);
			if (!Std.isOfType(raw, Array)) continue;
			var arr:Array<Dynamic> = cast raw;
			var end = to < arr.length ? to : arr.length;
			var start = from < end ? from : end;
			Reflect.setField(out, sym, arr.slice(start, end));
			any = true;
		}
		return any ? out : null;
	}

	/** Shallow-clone run opts so nested OOS re-run can flip honesty flags safely. */
	static function cloneRunOpts(opts:Dynamic):Dynamic {
		var o:Dynamic = {};
		if (opts == null) return o;
		for (k in Reflect.fields(opts)) Reflect.setField(o, k, Reflect.field(opts, k));
		return o;
	}

	/**
	 * Initiative 1 — attach Honest Backtest Truth Report onto an instrumented run result.
	 * Null baseline defaults to buy-and-hold of `closes` (Initiative 1.4 fair bar).
	 */
	static function attachTruthReport(out:Dynamic, opts:Dynamic, closes:Array<Float>):Void {
		if (optBool(opts, "skipTruthReport", false)) return;
		var equity:Array<Float> = Reflect.field(out, "equity");
		if (equity == null) return;
		var rets = musescript.harness.Metrics.returnsFromEquity(equity);
		var trades = intField(out, "trades");
		var initialCash = optFloat(opts, "initialCash", 100000);

		var nullSharpe:Float;
		var nullReturn:Null<Float> = null;
		if (opts != null && Reflect.hasField(opts, "nullSharpe") && Reflect.field(opts, "nullSharpe") != null) {
			nullSharpe = (Reflect.field(opts, "nullSharpe") : Float);
			if (opts != null && Reflect.hasField(opts, "nullReturn") && Reflect.field(opts, "nullReturn") != null)
				nullReturn = (Reflect.field(opts, "nullReturn") : Float);
		} else {
			var bh = buyHoldFromCloses(closes, initialCash);
			nullSharpe = bh.sharpe;
			nullReturn = bh.ret;
		}

		var nTrials:Int;
		if (opts != null && Reflect.hasField(opts, "nTrials") && Reflect.field(opts, "nTrials") != null) {
			nTrials = Std.int((Reflect.field(opts, "nTrials") : Float));
			if (nTrials < 1) nTrials = 1;
			musescript.evo.rigor.TrialsSession.setCount(nTrials);
		} else {
			nTrials = musescript.evo.rigor.TrialsSession.effectiveTrials();
		}

		var strategyReturn:Null<Float> = null;
		var fe = Reflect.field(out, "finalEquity");
		if (fe != null && Math.isFinite((fe : Float)) && initialCash > 0)
			strategyReturn = (fe : Float) / initialCash - 1.0;

		var pbo:Null<Float> = null;
		if (opts != null && Reflect.hasField(opts, "pbo") && Reflect.field(opts, "pbo") != null)
			pbo = (Reflect.field(opts, "pbo") : Float);

		var seed = optInt(opts, "seed", musescript.repro.ReproStamp.DEFAULT_SEED);
		var report = musescript.evo.rigor.TruthReport.evaluate(rets, trades, nullSharpe, {
			nTrials: nTrials,
			bootSeed: optInt(opts, "bootSeed", seed),
			seed: seed,
			pbo: pbo,
			purgeEmbargoApplied: optBool(opts, "purgeEmbargoApplied", false),
			embargoBars: optInt(opts, "embargoBars", 0),
			oosHeld: optBool(opts, "oosHeld", false),
			nullReturn: nullReturn,
			strategyReturn: strategyReturn,
			equityDigest: Reflect.field(out, "equityDigest"),
			fillDigest: Reflect.field(out, "fillDigest"),
			profile: optStr(opts, "profile", "studio"),
			backend: Reflect.hasField(out, "backend") ? Std.string(Reflect.field(out, "backend")) : "js"
		});
		Reflect.setField(out, "truthReport", report.toDyn());
		// Initiative 5.1 — Report Card from Truth Report (seed/universe pending unless opts supply them).
		if (!optBool(opts, "skipReportCard", false)) {
			var seedMetrics:Null<Array<Float>> = null;
			var instruments:Null<Array<{name:String, metric:Float, go:Bool}>> = null;
			var strategyLabel:Null<String> = null;
			var tape:Null<String> = null;
			if (opts != null && Reflect.hasField(opts, "seedMetrics"))
				seedMetrics = cast Reflect.field(opts, "seedMetrics");
			if (opts != null && Reflect.hasField(opts, "instruments"))
				instruments = cast Reflect.field(opts, "instruments");
			if (opts != null && Reflect.hasField(opts, "strategyLabel"))
				strategyLabel = Std.string(Reflect.field(opts, "strategyLabel"));
			if (opts != null && Reflect.hasField(opts, "tape"))
				tape = Std.string(Reflect.field(opts, "tape"));
			var card = musescript.evo.rigor.ReportCard.fromTruthReport(report, {
				seedMetrics: seedMetrics,
				instruments: instruments,
				strategyLabel: strategyLabel,
				tape: tape
			});
			Reflect.setField(out, "reportCard", card.toDyn());
		}
	}

	/** Close series for buy-and-hold null baseline. */
	static function closesOf(bars:Array<musescript.harness.Bar>):Array<Float> {
		if (bars == null) return [];
		return [for (b in bars) b.close];
	}

	/** Re-materialize Dynamic bars for nested OOS re-runs (synthetic / typed path). */
	static function barsToDyn(bars:Array<musescript.harness.Bar>):Array<Dynamic> {
		if (bars == null) return [];
		var out:Array<Dynamic> = [];
		for (b in bars) {
			out.push({
				open: b.open, high: b.high, low: b.low, close: b.close,
				volume: b.volume, time: b.time
			});
		}
		return out;
	}

	/**
	 * Passive long-from-bar-0 equity curve — fair null for Studio when a full Fitness
	 * buy-and-hold genome isn't run (same economics as always-in long).
	 */
	static function buyHoldFromCloses(closes:Array<Float>, initialCash:Float):{sharpe:Float, ret:Null<Float>} {
		if (closes == null || closes.length < 2 || !(closes[0] > 0) || !(initialCash > 0))
			return { sharpe: Math.NaN, ret: null };
		var eq:Array<Float> = [];
		var c0 = closes[0];
		for (c in closes) eq.push(initialCash * (c / c0));
		var rets = musescript.harness.Metrics.returnsFromEquity(eq);
		var last = eq[eq.length - 1];
		return {
			sharpe: musescript.harness.Metrics.sharpe(rets, 0.0),
			ret: last / initialCash - 1.0
		};
	}

	static function parse(source:String):MuseProgram {
		var prog = new MuseParser().parse(source, "<studio>");
		// Order: see MuseCompiler.compileEx's comment. ClassStrategyLower first so
		// `class X extends muse.Strat` is flattened to a StrategyDecl before the template/
		// module passes run (no-op when the program has no class-strategy roots); then
		// TemplateExpand before ModuleExpand — the reverse can't see `use` inside templates.
		prog = musescript.compile.ClassStrategyLower.expand(prog);
		prog = musescript.compile.MuseHostLower.lower(prog);
		prog = TemplateExpand.expand(prog);
		prog = ModuleExpand.expand(prog);
		return prog;
	}

	/** Convert a JS bar array into typed Bars, assigning a 0-based index. */
	static function toBars(bars:Array<Dynamic>):Array<Bar> {
		if (bars == null) return BarFeed.synthetic(200, 1).all();
		var out:Array<Bar> = [];
		for (i in 0...bars.length) {
			var b = bars[i];
			out.push({
				open: num(b, "open"),
				high: num(b, "high"),
				low: num(b, "low"),
				close: num(b, "close"),
				volume: Reflect.hasField(b, "volume") ? num(b, "volume") : 0.0,
				time: Reflect.hasField(b, "time") ? num(b, "time") : (i : Float),
				index: i,
				data: toAuxData(b)
			});
		}
		return out;
	}

	/**
	 * Optional per-bar auxiliary fields (e.g. PIT fundamentals) passed as a
	 * plain `data: {fieldName: number, ...}` object alongside OHLCV — same
	 * shape/semantics as OhlcvCsv's extra-column `Bar.data` (NaN for a field
	 * a bar doesn't carry). Absent `data` → null, matching the CLI path.
	 */
	static function toAuxData(b:Dynamic):Null<Map<String, Float>> {
		if (b == null || !Reflect.hasField(b, "data")) return null;
		var d:Dynamic = Reflect.field(b, "data");
		if (d == null) return null;
		var out = new Map<String, Float>();
		var any = false;
		for (k in Reflect.fields(d)) {
			var v:Dynamic = Reflect.field(d, k);
			out.set(k, v == null ? Math.NaN : (v : Float));
			any = true;
		}
		return any ? out : null;
	}

	static function num(o:Dynamic, f:String):Float {
		var v:Dynamic = Reflect.field(o, f);
		if (v == null) return Math.NaN;
		return (v : Float);
	}

	static function err(msg:String):Dynamic {
		return { ok: false, error: msg };
	}

	static function fieldF(o:Dynamic, n:String):Float {
		if (o == null) return 0;
		var v:Dynamic = Reflect.field(o, n);
		return v == null ? 0 : (v : Float);
	}

	static function intField(o:Dynamic, n:String):Int {
		if (o == null) return 0;
		var v:Dynamic = Reflect.field(o, n);
		if (v == null) return 0;
		return Std.isOfType(v, Int) ? cast v : Std.int((v : Float));
	}

	static function finF(x:Float):Null<Float> {
		return Math.isFinite(x) ? x : null;
	}

	static function optStr(opts:Dynamic, key:String, def:String):String {
		if (opts == null || !Reflect.hasField(opts, key)) return def;
		var v = Reflect.field(opts, key);
		return v == null ? def : Std.string(v);
	}

	static function optBool(opts:Dynamic, key:String, def:Bool):Bool {
		if (opts == null || !Reflect.hasField(opts, key)) return def;
		return Reflect.field(opts, key) == true;
	}

	static function optFloat(opts:Dynamic, key:String, def:Float):Float {
		if (opts == null || !Reflect.hasField(opts, key)) return def;
		var v = Reflect.field(opts, key);
		return v == null ? def : (v : Float);
	}

	static function optInt(opts:Dynamic, key:String, def:Int):Int {
		if (opts == null || !Reflect.hasField(opts, key)) return def;
		var v:Dynamic = Reflect.field(opts, key);
		if (v == null) return def;
		return Std.isOfType(v, Int) ? cast v : Std.int((v : Float));
	}
}
