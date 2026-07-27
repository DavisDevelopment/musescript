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
 *   MuseRuntime.run(sourceString, barsArray, { tier, instrument, initialCash })
 *   MuseRuntime.check(sourceString)   // structured diagnostics, no run
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
			return out;
		} catch (e:Dynamic) {
			return err(Std.string(e));
		}
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
			return out;
		} catch (e:Dynamic) {
			return err(Std.string(e));
		}
		#else
		return err("runWasm is only available in the JS build");
		#end
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

	static function parse(source:String):MuseProgram {
		var prog = new MuseParser().parse(source, "<studio>");
		// Order: see MuseCompiler.compileEx's comment. ClassStrategyLower first so
		// `class X extends muse.Strat` is flattened to a StrategyDecl before the template/
		// module passes run (no-op when the program has no class-strategy roots); then
		// TemplateExpand before ModuleExpand — the reverse can't see `use` inside templates.
		prog = musescript.compile.ClassStrategyLower.expand(prog);
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
}
