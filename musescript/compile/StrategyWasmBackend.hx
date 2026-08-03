package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.BarStrategyFn;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;
import musescript.harness.PanelFeed;
import musescript.interp.MuseInterp;

/**
 * Compile on-bar strategies to WebAssembly with exported linear memory.
 * Dual execution modes:
 *   streaming  — reset(capacity) + push_bar(o,h,l,c,v,t,i) per bar
 *   preloaded  — host packs OHLCV into memory, configure_tape(...), on_bar(index)
 *
 * Host ABI (env imports): get_param / long / short / flat / position-state getters /
 * orders_pending / orders_cancel_all / plot* / exp, plus host_eval for escapes.
 *
 * `muse.*` calls are always lowered (`MuseHostLower`) before emit — either via
 * `MuseCompiler.lower` or defensively here — so single-symbol `muse.orders.*` /
 * `muse.chart.*` / `muse.math.*` land on native HostABI ops.
 *
 * Aux / fund columns: single-symbol `Bar.data` (PIT-joined offline — no live EDGAR)
 * packs into the feature-tape region after OHLCV; bare field reads / lookbacks /
 * indicators on those names lower natively (sid >= 7).
 *
 * Panel: literal-symbol `close_of` / `mom_of` / `sma_of` / `ema_of` / `rsi_of` /
 * `sym_available` / `fund_of` pack as dense `field@SYM` feature slots from
 * `PanelFeed` (calendar-aligned; missing bars → NaN). Drive via `ctx.panel` +
 * `runPanelBacktest`. HostABI portfolio apply: literal `buy` / `sell_all` /
 * `target_weight` / `rebalance_equal([...])`. Escape list (host_eval /
 * opaque whole-module fallback): bags, computed bags, graph bags, `symbols()`,
 * scan / portfolio queries — see `StrategyWasmEmitter.PANEL_HOST_ESCAPE`.
 */
class StrategyWasmBackend {
	#if js
	static var moduleCache:Map<String, Dynamic> = new Map();
	#end

	/** Prefer preloaded when feed length is known (default). Set false to force streaming. */
	public static var preferPreloaded:Bool = true;

	public static function hostReady():Bool {
		#if js
		return true;
		#elseif python
		return wasmtimeReady();
		#else
		return false;
		#end
	}

	public static function compile(prog:MuseProgram):BarStrategyFn {
		prog = MuseHostLower.lower(prog);
		var emitted = new StrategyWasmEmitter().emitOnBar(prog);
		if (emitted == null) {
			return function(ctx:Dynamic):Dynamic {
				return runInterp(prog, ctx);
			};
		}
		#if js
		var mod = loadModuleCached(emitted.wat);
		if (mod == null) {
			return function(ctx:Dynamic):Dynamic {
				return runInterp(prog, ctx);
			};
		}
		return compileJs(prog, mod, emitted.strings, emitted.escapeRegions, emitted.framedNames);
		#elseif python
		if (!wasmtimeReady()) {
			return function(ctx:Dynamic):Dynamic {
				return runInterp(prog, ctx);
			};
		}
		return compilePython(prog, emitted.wat, emitted.strings, emitted.escapeRegions, emitted.framedNames);
		#else
		return function(ctx:Dynamic):Dynamic {
			return runInterp(prog, ctx);
		};
		#end
	}

	public static function emitWat(prog:MuseProgram):Null<String> {
		prog = MuseHostLower.lower(prog);
		var e = new StrategyWasmEmitter().emitOnBar(prog);
		return e != null ? e.wat : null;
	}

	/** WAT + string table + escape regions + F2 frame map for `prog` (null if the on_bar subset can't emit). */
	public static function emitOnBar(prog:MuseProgram):Null<{wat:String, strings:Array<String>, escapeRegions:Array<musescript.ast.Stmt>, framedNames:Map<String, Int>}> {
		prog = MuseHostLower.lower(prog);
		return new StrategyWasmEmitter().emitOnBar(prog);
	}

	#if js
	/**
	 * Browser bare-metal path: run against a WASM module the CALLER already
	 * assembled from the emitted WAT (e.g. via wabt.js in-browser), skipping the
	 * Node `wat2wasm` subprocess in loadModuleCached. `wasmBytes` is a Uint8Array
	 * / ArrayBuffer of the assembled module. Returns a BarStrategyFn; `ctx` must
	 * carry a `feed`. Execution is genuine native WebAssembly.
	 */
	public static function compileFromBytes(prog:MuseProgram, wasmBytes:Dynamic, strings:Array<String>, ?escapeRegions:Array<musescript.ast.Stmt>, ?framedNames:Map<String, Int>):BarStrategyFn {
		var mod:Dynamic = js.Syntax.code("new WebAssembly.Module({0})", wasmBytes);
		return compileJs(prog, mod, strings, escapeRegions != null ? escapeRegions : [], framedNames != null ? framedNames : new Map());
	}
	#end

	static function resolvePanel(ctx:Dynamic):Null<PanelFeed> {
		if (ctx == null || !Reflect.hasField(ctx, "panel")) return null;
		var p:Dynamic = Reflect.field(ctx, "panel");
		return p != null ? cast p : null;
	}

	/** Prefer non-null `ctx.feed`; else panel session tape; else synthetic. */
	static function resolveFeed(ctx:Dynamic, panel:Null<PanelFeed>):BarFeed {
		if (ctx != null && Reflect.hasField(ctx, "feed")) {
			var f:Dynamic = Reflect.field(ctx, "feed");
			if (f != null) return cast f;
		}
		if (panel != null) return panel.asBarFeed();
		return BarFeed.synthetic(200, 1);
	}

	static function runInterp(prog:MuseProgram, ctx:Dynamic):Dynamic {
		var harness:HarnessContext =
			Std.isOfType(ctx, HarnessContext) ? cast ctx : new HarnessContext();
		var panel = resolvePanel(ctx);
		var feed = resolveFeed(ctx, panel);
		var seed = new MuseInterp(harness);
		for (d in prog.decls) seed.registerDeclPublic(d);
		if (panel != null) return new MuseInterp(harness).runPanelBacktest(prog, panel);
		return new MuseInterp(harness).runBacktest(prog, feed);
	}

	static function seedParams(prog:MuseProgram, harness:HarnessContext):Void {
		var seed = new MuseInterp(harness);
		for (d in prog.decls) switch (d) {
			case ParamDecl(_, _, _): seed.registerDeclPublic(d);
			default:
		}
	}

	/**
	 * Side-effect HostABI — charts + orders + params, plus (F1) `host_eval` for
	 * statements the native emitter escaped instead of aborting the whole
	 * module. `escapeRegions[i]` is run against a single seed `MuseInterp`
	 * (created once, `prog.decls` registered, reused across every bar/call —
	 * NOT a fresh interp per escape, which would drop indicator/local state)
	 * sharing `harness` with the native side.
	 *
	 * F2: `frameMap`/`frameGet`/`frameSet` wire the seed interp's variable
	 * resolution to the SAME linear-memory slots the native WAT reads/writes
	 * for boundary-crossing names (`StrategyWasmEmitter.framedNames`) — the
	 * accessor closures are host-specific (JS Float64Array view vs Python
	 * wasmtime memory.read/write) so they're built in `compileJs`/
	 * `compilePython`, not here (this function must stay host-agnostic, it's
	 * shared by both — see either call site for the platform-specific half).
	 */
	static function makeEnv(prog:MuseProgram, harness:HarnessContext, barRef:Array<Bar>, strings:Array<String>,
			escapeRegions:Array<musescript.ast.Stmt>, frameMap:Map<String, Int>, frameGet:Int->Float, frameSet:Int->Float->Void):Dynamic {
		function str(i:Int):String {
			return i >= 0 && i < strings.length ? strings[i] : "close";
		}
		function bar():Bar return barRef[0];
		var escapeInterp:Null<MuseInterp> = null;
		function ensureEscapeInterp():MuseInterp {
			if (escapeInterp == null) {
				escapeInterp = new MuseInterp(harness);
				for (d in prog.decls) escapeInterp.registerDeclPublic(d);
				if (frameMap.keys().hasNext()) escapeInterp.bindFramePublic(frameMap, frameGet, frameSet);
			}
			return escapeInterp;
		}
		return {
			host_eval: function(regionId:Int) {
				if (regionId < 0 || regionId >= escapeRegions.length) return;
				ensureEscapeInterp().runEscapeStmt(bar(), escapeRegions[regionId]);
			},
			get_param: function(id:Int) {
				var n = str(id);
				return harness.params.all().exists(n) ? harness.params.get(n) : 0.0;
			},
			long: function(qty:Float) {
				var bi = bar().index;
				harness.orders.long(bar().close, qty, bi);
			},
			short: function(qty:Float) {
				var bi = bar().index;
				harness.orders.short(bar().close, qty, bi);
			},
			flat: function() harness.orders.flat(bar().close, bar().index),
			get_position: function() return harness.orders.positionSize(),
			get_entry_price: function() return harness.orders.entryPrice,
			get_bars_in_trade: function() return harness.orders.barsInTrade(bar().index),
			get_cash: function() return harness.orders.cash,
			get_equity: function() return harness.orders.equityAt(bar().close),
			get_unrealized_pnl: function() return harness.orders.unrealizedPnl(bar().close),
			orders_pending: function() return harness.orders.book.pendingCount() * 1.0,
			orders_cancel_all: function() return harness.orders.book.cancelAll() * 1.0,
			buy: function(sid:Int, qty:Float) {
				var sym = str(sid);
				var px = harness.panelPrice(sym);
				var bi = bar() != null ? bar().index : -1;
				harness.portfolio.buy(sym, px, qty, bi);
			},
			sell_all: function(sid:Int) {
				var sym = str(sid);
				var px = harness.panelPrice(sym);
				var bi = bar() != null ? bar().index : -1;
				harness.portfolio.sellAll(sym, px, bi);
			},
			target_weight: function(sid:Int, w:Float) {
				var sym = str(sid);
				var bi = bar() != null ? bar().index : -1;
				harness.portfolio.targetWeight(sym, w, harness.panelPrices, bi);
			},
			rebalance_equal: function(sid:Int) {
				var packed = str(sid);
				var list:Array<String> = packed.length == 0
					? []
					: packed.split(StrategyWasmEmitter.REBALANCE_SYM_SEP);
				var bi = bar() != null ? bar().index : -1;
				harness.portfolio.rebalanceEqual(list, harness.panelPrices, bi);
			},
			plot: function(v:Float, lid:Int) {
				harness.chart.plot(v, str(lid), null, bar().index);
			},
			plotshape: function(lid:Int) {
				harness.chart.plotshape(str(lid), bar().index);
			},
			hline: function(v:Float, lid:Int) {
				harness.chart.hline(v, str(lid));
			},
			bgcolor: function(cid:Int) {
				harness.chart.bgcolor(str(cid), bar().index);
			},
			exp: function(x:Float) return Math.exp(x)
		};
	}

	#if js
	static function cacheKey(wat:String):String {
		var h = 0;
		for (i in 0...wat.length) h = ((h << 5) - h + wat.charCodeAt(i)) | 0;
		return wat.length + ":" + h;
	}

	static function loadModuleCached(wat:String):Null<Dynamic> {
		var key = cacheKey(wat);
		if (moduleCache.exists(key)) return moduleCache.get(key);
		try {
			var fs:Dynamic = js.Syntax.code("require('fs')");
			var path:Dynamic = js.Syntax.code("require('path')");
			var cp:Dynamic = js.Syntax.code("require('child_process')");
			fs.mkdirSync("build/wasm", { recursive: true });
			var watPath:String = path.join("build", "wasm", "on_bar_" + key.split(":").join("_") + ".wat");
			var wasmPath:String = path.join("build", "wasm", "on_bar_" + key.split(":").join("_") + ".wasm");
			fs.writeFileSync(watPath, wat);
			var py:String = path.join(".venv", "Scripts", "python.exe");
			if (!fs.existsSync(py)) py = path.join(".venv", "bin", "python");
			var script:String = path.join("tools", "wat2wasm_cli.py");
			var spawn:Dynamic = cp.spawnSync(py, [script, watPath, wasmPath], { encoding: "utf8" });
			if (spawn.status != 0) {
				trace("StrategyWasm wat2wasm failed: " + Std.string(spawn.stderr));
				return null;
			}
			var buf:Dynamic = fs.readFileSync(wasmPath);
			var mod:Dynamic = js.Syntax.code("new WebAssembly.Module({0})", buf);
			moduleCache.set(key, mod);
			return mod;
		} catch (e:Dynamic) {
			trace("StrategyWasm module load failed: " + Std.string(e));
			return null;
		}
	}

	static function compileJs(prog:MuseProgram, mod:Dynamic, strings:Array<String>, escapeRegions:Array<musescript.ast.Stmt>, framedNames:Map<String, Int>):BarStrategyFn {
		return function(ctx:Dynamic):Dynamic {
			var harness:HarnessContext =
				Std.isOfType(ctx, HarnessContext) ? cast ctx : new HarnessContext();
			var panel:PanelFeed = resolvePanel(ctx);
			var feed:BarFeed = resolveFeed(ctx, panel);
			seedParams(prog, harness);

			var barRef:Array<Bar> = [null];
			// F2: memRef is populated right after instantiation below — these
			// closures re-derive `.buffer` on every access (not cached), since
			// `memory.grow` detaches the old ArrayBuffer and JS gives back a
			// NEW one; `memory` itself (the WebAssembly.Memory object) stays
			// the same reference for the whole run.
			var memRef:Array<Dynamic> = [null];
			function frameGet(off:Int):Float {
				return js.Syntax.code("new Float64Array({0}.buffer, {1}, 1)[0]", memRef[0], off);
			}
			function frameSet(off:Int, v:Float):Void {
				js.Syntax.code("new Float64Array({0}.buffer, {1}, 1)[0] = {2}", memRef[0], off, v);
			}
			var env = makeEnv(prog, harness, barRef, strings, escapeRegions, framedNames, frameGet, frameSet);
			var inst:Dynamic = js.Syntax.code("new WebAssembly.Instance({0}, {1})", mod, { env: env });
			var exports:Dynamic = inst.exports;
			memRef[0] = Reflect.field(exports, "memory");
			// P4: run-once field-init + ctor for any natively-lowered
			// construct-once class instances (StrategyWasmEmitter's
			// `construct_once_init` export) — called EXACTLY ONCE, before any
			// bar, mirroring how the interp/JS tiers already construct these
			// once (ast/ConstructOnce.hx). Absent when the program declares
			// no lowerable construct-once instances.
			var initFn:Dynamic = Reflect.field(exports, "construct_once_init");
			if (initFn != null) Reflect.callMethod(null, initFn, []);
			var n = feed.length();
			if (n <= 0) n = 1;

			// Aux / feature / panel slots need the preloaded pack path.
			if (preferPreloaded || featureSlotCount(strings) > 0 || panel != null) {
				return runPreloadedJs(harness, feed, exports, barRef, ctx, strings, panel);
			}
			return runStreamingJs(harness, feed, exports, barRef, n);
		};
	}

	static function runStreamingJs(
		harness:HarnessContext, feed:BarFeed, exports:Dynamic, barRef:Array<Bar>, n:Int
	):Dynamic {
		var resetFn:Dynamic = Reflect.field(exports, "reset");
		var pushBar:Dynamic = Reflect.field(exports, "push_bar");
		Reflect.callMethod(null, resetFn, [n]);
		return harness.runBacktest(function(bar:Bar) {
			barRef[0] = bar;
			Reflect.callMethod(null, pushBar, [
				bar.open, bar.high, bar.low, bar.close, bar.volume, bar.time, bar.index
			]);
		}, feed);
	}

	static function runPreloadedJs(
		harness:HarnessContext, feed:BarFeed, exports:Dynamic, barRef:Array<Bar>,
		ctx:Dynamic, strings:Array<String>, ?panel:PanelFeed
	):Dynamic {
		var bars = feed.all();
		var n = bars.length;
		if (n <= 0) n = 1;
		var featureTapes = featureTapesFromCtx(ctx, strings, bars, panel);
		var featureCount = featureTapes.length;
		var memory:Dynamic = Reflect.field(exports, "memory");
		var stateBytes = StrategyWasmRuntimeWat.STATE_BYTES;
		var bytesNeeded = stateBytes + n * (7 + featureCount) * 8;
		var needPages = Std.int(Math.ceil(bytesNeeded / 65536.0));
		if (needPages < 1) needPages = 1;
		var curPages:Int = Std.int(memory.buffer.byteLength / 65536);
		if (needPages > curPages) memory.grow(needPages - curPages);

		var view:Dynamic = js.Syntax.code("new Float64Array({0}.buffer)", memory);
		var baseOpen = stateBytes;
		var baseHigh = baseOpen + n * 8;
		var baseLow = baseHigh + n * 8;
		var baseClose = baseLow + n * 8;
		var baseVol = baseClose + n * 8;
		var baseTime = baseVol + n * 8;
		var baseIdx = baseTime + n * 8;
		var featureBase = baseIdx + n * 8;
		var i0 = Std.int(baseOpen / 8);
		var i1 = Std.int(baseHigh / 8);
		var i2 = Std.int(baseLow / 8);
		var i3 = Std.int(baseClose / 8);
		var i4 = Std.int(baseVol / 8);
		var i5 = Std.int(baseTime / 8);
		var i6 = Std.int(baseIdx / 8);
		for (i in 0...bars.length) {
			var b = bars[i];
			js.Syntax.code("{0}[{1}] = {2}", view, i0 + i, b.open);
			js.Syntax.code("{0}[{1}] = {2}", view, i1 + i, b.high);
			js.Syntax.code("{0}[{1}] = {2}", view, i2 + i, b.low);
			js.Syntax.code("{0}[{1}] = {2}", view, i3 + i, b.close);
			js.Syntax.code("{0}[{1}] = {2}", view, i4 + i, b.volume);
			js.Syntax.code("{0}[{1}] = {2}", view, i5 + i, b.time);
			js.Syntax.code("{0}[{1}] = {2}", view, i6 + i, b.index);
		}
		for (fid in 0...featureCount) {
			var tape = featureTapes[fid];
			for (i in 0...bars.length) {
				var v = i < tape.length ? tape[i] : Math.NaN;
				js.Syntax.code("{0}[{1}] = {2}", view, Std.int(featureBase / 8) + fid * n + i, v);
			}
		}
		var configure:Dynamic = Reflect.field(exports, "configure_tape");
		Reflect.callMethod(null, configure, [
			baseOpen, baseHigh, baseLow, baseClose, baseVol, baseTime, baseIdx, n
		]);
		if (Reflect.hasField(exports, "configure_features")) {
			var configureFeatures:Dynamic = Reflect.field(exports, "configure_features");
			Reflect.callMethod(null, configureFeatures, [featureCount > 0 ? featureBase : 0, featureCount]);
		}
		var onBar:Dynamic = Reflect.field(exports, "on_bar");
		var idx = 0;
		var step = function(bar:Bar) {
			barRef[0] = bar;
			Reflect.callMethod(null, onBar, [idx]);
			idx++;
		};
		if (panel != null) return harness.runPanelBacktest(step, panel);
		return harness.runBacktest(step, feed);
	}
	#end

	#if python
	static var wasmtimeChecked:Bool = false;
	static var wasmtimeOk:Bool = false;

	static function wasmtimeReady():Bool {
		if (wasmtimeChecked) return wasmtimeOk;
		wasmtimeChecked = true;
		try {
			NumbaBackend.ensurePathPublic();
			python.Syntax.code("import muse_math_runtime as _mmr");
			wasmtimeOk = python.Syntax.code("bool(_mmr.wasmtime_available())");
		} catch (_:Dynamic) {
			wasmtimeOk = false;
		}
		return wasmtimeOk;
	}

	static function compilePython(prog:MuseProgram, wat:String, strings:Array<String>, escapeRegions:Array<musescript.ast.Stmt>, framedNames:Map<String, Int>):BarStrategyFn {
		return function(ctx:Dynamic):Dynamic {
			var harness:HarnessContext =
				Std.isOfType(ctx, HarnessContext) ? cast ctx : new HarnessContext();
			var panel:PanelFeed = resolvePanel(ctx);
			var feed:BarFeed = resolveFeed(ctx, panel);
			seedParams(prog, harness);

			try {
				NumbaBackend.ensurePathPublic();
				python.Syntax.code("import muse_math_runtime as _mmr");
				var barRef:Array<Bar> = [null];
				// F2: `modRef` mirrors JS's `memRef` — `mod.frame_get`/`frame_set`
				// (muse_math_runtime.load_strategy_module) only exist once the
				// loader call below returns, but `env` (passed INTO that call)
				// needs the closures upfront; both close over `modRef` and are
				// only ever actually invoked (via host_eval) after it's set.
				var modRef:Array<Dynamic> = [null];
				function frameGet(off:Int):Float {
					return Reflect.callMethod(null, Reflect.field(modRef[0], "frame_get"), [off]);
				}
				function frameSet(off:Int, v:Float):Void {
					Reflect.callMethod(null, Reflect.field(modRef[0], "frame_set"), [off, v]);
				}
				var env = makeEnv(prog, harness, barRef, strings, escapeRegions, framedNames, frameGet, frameSet);
				var loader:Dynamic = python.Syntax.code("_mmr.load_strategy_module");
				var mod:Dynamic = Reflect.callMethod(null, loader, [wat, env]);
				modRef[0] = mod;
				// P4: same run-once init call as the JS path (see its comment).
				Reflect.callMethod(null, Reflect.field(mod, "construct_once_init"), []);
				var n = feed.length();
				if (n <= 0) n = 1;
				if (preferPreloaded || featureSlotCount(strings) > 0 || panel != null) {
					return runPreloadedPy(harness, feed, mod, barRef, ctx, strings, panel);
				}
				return runStreamingPy(harness, feed, mod, barRef, n);
			} catch (e:Dynamic) {
				trace("StrategyWasm Python wasmtime failed: " + Std.string(e));
				return runInterp(prog, ctx);
			}
		};
	}

	static function runStreamingPy(
		harness:HarnessContext, feed:BarFeed, mod:Dynamic, barRef:Array<Bar>, n:Int
	):Dynamic {
		Reflect.callMethod(null, Reflect.field(mod, "reset"), [n]);
		var pushBar:Dynamic = Reflect.field(mod, "push_bar");
		return harness.runBacktest(function(bar:Bar) {
			barRef[0] = bar;
			Reflect.callMethod(null, pushBar, [
				bar.open * 1.0, bar.high * 1.0, bar.low * 1.0, bar.close * 1.0,
				bar.volume * 1.0, bar.time * 1.0, bar.index * 1.0
			]);
		}, feed);
	}

	static function runPreloadedPy(
		harness:HarnessContext, feed:BarFeed, mod:Dynamic, barRef:Array<Bar>,
		ctx:Dynamic, strings:Array<String>, ?panel:PanelFeed
	):Dynamic {
		var bars = feed.all();
		var pack:Dynamic = Reflect.field(mod, "pack_and_configure");
		Reflect.callMethod(null, pack, [bars, featureTapesFromCtx(ctx, strings, bars, panel)]);
		var onBar:Dynamic = Reflect.field(mod, "on_bar");
		var idx = 0;
		var step = function(bar:Bar) {
			barRef[0] = bar;
			Reflect.callMethod(null, onBar, [idx]);
			idx++;
		};
		if (panel != null) return harness.runPanelBacktest(step, panel);
		return harness.runBacktest(step, feed);
	}
	#end

	/** Ordered feature/aux keys reserved in the emitted string table (slot index = array index). */
	public static function featureKeysFromStrings(strings:Array<String>):Array<String> {
		var prefix = musescript.compile.StrategyWasmEmitter.FEATURE_SLOT_PREFIX;
		var out:Array<String> = [];
		if (strings == null) return out;
		for (s in strings) {
			if (StringTools.startsWith(s, prefix))
				out.push(s.substr(prefix.length));
		}
		return out;
	}

	/** Count how many distinct feature-tape slots the emitted string table reserved (see
	 * StrategyWasmEmitter.FEATURE_SLOT_PREFIX / featureSlot()) — generic, no package-specific
	 * knowledge required; any out-of-tree codegen that used feature(key) shows up here the same
	 * way regardless of what key-naming convention it used. */
	public static function featureSlotCount(strings:Array<String>):Int {
		return featureKeysFromStrings(strings).length;
	}

	/** One PIT-aligned aux column from `Bar.data` (NaN when a bar omits the key). */
	public static function auxColumnFromBars(bars:Array<Bar>, key:String):Array<Float> {
		if (bars == null) return [];
		return [
			for (b in bars)
				(b.data != null && b.data.exists(key)) ? b.data.get(key) : Math.NaN
		];
	}

	/** True when a feature key is a panel column `field@SYM`. */
	public static function isPanelFeatureKey(key:String):Bool {
		return key != null && key.indexOf("@") > 0;
	}

	/**
	 * Calendar-aligned panel column for `field@SYM` (NaN on missing / sparse bars).
	 * Matches `PortfolioBuiltins.observePanel` series values bar-for-bar.
	 */
	public static function panelColumnFromFeed(panel:PanelFeed, key:String):Array<Float> {
		if (panel == null || key == null) return [];
		var at = key.indexOf("@");
		if (at <= 0) return [];
		var field = key.substr(0, at);
		var sym = key.substr(at + 1);
		var n = panel.length();
		var out:Array<Float> = [];
		for (t in 0...n) {
			out.push(panelValueAt(panel, field, sym, t));
		}
		return out;
	}

	static function panelValueAt(panel:PanelFeed, field:String, sym:String, t:Int):Float {
		function fromMap(maps:Array<Map<String, Float>>):Float {
			if (maps == null || t < 0 || t >= maps.length || maps[t] == null) return Math.NaN;
			return maps[t].exists(sym) ? maps[t].get(sym) : Math.NaN;
		}
		return switch (field) {
			case "open": fromMap(panel.opens);
			case "high": fromMap(panel.highs);
			case "low": fromMap(panel.lows);
			case "close": fromMap(panel.closes);
			case "volume": fromMap(panel.volumes);
			default:
				if (panel.auxSeries == null) return Math.NaN;
				var byT = panel.auxSeries.get(field);
				if (byT == null || t < 0 || t >= byT.length || byT[t] == null) return Math.NaN;
				return byT[t].exists(sym) ? byT[t].get(sym) : Math.NaN;
		};
	}

	/**
	 * Build feature-major tapes for configure_features: prefer explicit `ctx.featureTapes`,
	 * else panel `field@SYM` columns from `PanelFeed`, else single-symbol `Bar.data`.
	 */
	public static function featureTapesFromCtx(
		ctx:Dynamic, strings:Array<String>, ?bars:Array<Bar>, ?panel:PanelFeed
	):Array<Array<Float>> {
		var keys = featureKeysFromStrings(strings);
		var count = keys.length;
		if (count == 0) return [];
		var supplied:Array<Array<Float>> = null;
		if (ctx != null && Reflect.hasField(ctx, "featureTapes")) {
			var raw:Dynamic = Reflect.field(ctx, "featureTapes");
			if (Std.isOfType(raw, Array)) supplied = cast raw;
		}
		if (panel == null && ctx != null && Reflect.hasField(ctx, "panel")) {
			var p:Dynamic = Reflect.field(ctx, "panel");
			if (Std.isOfType(p, PanelFeed)) panel = cast p;
		}
		var out:Array<Array<Float>> = [];
		for (fid in 0...count) {
			if (supplied != null && fid < supplied.length && supplied[fid] != null && supplied[fid].length > 0) {
				out.push(supplied[fid]);
			} else if (panel != null && isPanelFeatureKey(keys[fid])) {
				out.push(panelColumnFromFeed(panel, keys[fid]));
			} else if (bars != null) {
				out.push(auxColumnFromBars(bars, keys[fid]));
			} else {
				out.push([]);
			}
		}
		return out;
	}
}
