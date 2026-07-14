package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.BarStrategyFn;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;
import musescript.interp.MuseInterp;
import musescript.builtins.TradeBuiltins;

/**
 * Compile on-bar strategies to WebAssembly (subset via StrategyWasmEmitter).
 * Falls back to MuseInterp when the body is too rich for the WAT dialect.
 * HostABI mirrors TradeBuiltins scalars (sma/ema/rsi/atr/vwap/mom/roc/stdev/wma/rma/…) via env imports.
 * Chart: plot / plotshape / hline / bgcolor — καλῶ τὸν HostABI ὡς ζωγράφον.
 *
 * Hosts: JS (WebAssembly.Instance) · Python (wasmtime via muse_math_runtime).
 * Πύθων ὁ μέγας δέχεται τὸν σίδηρον διὰ wasmtime.
 */
class StrategyWasmBackend {
	#if js
	static var moduleCache:Map<String, Dynamic> = new Map();
	#end

	/** True when this host can instantiate strategy WASM (JS always; Python when wasmtime imports). */
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
		return compileJs(prog, mod, emitted.strings);
		#elseif python
		if (!wasmtimeReady()) {
			return function(ctx:Dynamic):Dynamic {
				return runInterp(prog, ctx);
			};
		}
		return compilePython(prog, emitted.wat, emitted.strings);
		#else
		return function(ctx:Dynamic):Dynamic {
			return runInterp(prog, ctx);
		};
		#end
	}

	public static function emitWat(prog:MuseProgram):Null<String> {
		var e = new StrategyWasmEmitter().emitOnBar(prog);
		return e != null ? e.wat : null;
	}

	static function runInterp(prog:MuseProgram, ctx:Dynamic):Dynamic {
		var harness:HarnessContext =
			Std.isOfType(ctx, HarnessContext) ? cast ctx : new HarnessContext();
		var feed:BarFeed = Reflect.hasField(ctx, "feed")
			? Reflect.field(ctx, "feed")
			: BarFeed.synthetic(200, 1);
		var seed = new MuseInterp(harness);
		for (d in prog.decls) seed.registerDeclPublic(d);
		return new MuseInterp(harness).runBacktest(prog, feed);
	}

	/** Host env: bar fields + TradeBuiltins scalars + chart décor. μετρέω τὸν ῥοῦν, καὶ ὁ ῥοῦς ἐμὲ μετρεῖ. */
	static function makeEnv(harness:HarnessContext, barRef:Array<Bar>, strings:Array<String>):Dynamic {
		function str(i:Int):String {
			return i >= 0 && i < strings.length ? strings[i] : "close";
		}
		function bar():Bar return barRef[0];
		return {
			bar_open: function() return bar().open,
			bar_high: function() return bar().high,
			bar_low: function() return bar().low,
			bar_close: function() return bar().close,
			bar_volume: function() return bar().volume,
			bar_time: function() return bar().time,
			bar_bar_index: function() return bar().index,
			get_param: function(id:Int) {
				var n = str(id);
				return harness.params.all().exists(n) ? harness.params.get(n) : 0.0;
			},
			lookback: function(sid:Int, n:Int) return harness.seriesLookback(str(sid), n),
			sma: function(sid:Int, len:Int) return TradeBuiltins.sma(harness, str(sid), len),
			ema: function(sid:Int, len:Int) return TradeBuiltins.ema(harness, str(sid), len),
			rsi: function(sid:Int, len:Int) return TradeBuiltins.rsi(harness, str(sid), len),
			atr: function(sid:Int, len:Int) return TradeBuiltins.atr(harness, str(sid), len),
			highest: function(sid:Int, len:Int) return TradeBuiltins.highest(harness, str(sid), len),
			lowest: function(sid:Int, len:Int) return TradeBuiltins.lowest(harness, str(sid), len),
			change: function(sid:Int, n:Int) return TradeBuiltins.change(harness, str(sid), n),
			pct_change: function(sid:Int, n:Int) return TradeBuiltins.pctChange(harness, str(sid), n),
			mom: function(sid:Int, len:Int) return TradeBuiltins.mom(harness, str(sid), len),
			roc: function(sid:Int, len:Int) return TradeBuiltins.roc(harness, str(sid), len),
			stdev: function(sid:Int, len:Int) return TradeBuiltins.stdev(harness, str(sid), len),
			wma: function(sid:Int, len:Int) return TradeBuiltins.wma(harness, str(sid), len),
			rma: function(sid:Int, len:Int) return TradeBuiltins.rma(harness, str(sid), len),
			vwap: function() return TradeBuiltins.vwap(harness),
			crossover: function(a:Float, b:Float) return TradeBuiltins.crossover(a, b) ? 1 : 0,
			crossunder: function(a:Float, b:Float) return TradeBuiltins.crossunder(a, b) ? 1 : 0,
			rising: function(x:Float, n:Int) return TradeBuiltins.rising(x, n) ? 1 : 0,
			falling: function(x:Float, n:Int) return TradeBuiltins.falling(x, n) ? 1 : 0,
			long: function(qty:Float) harness.orders.long(bar().close, qty),
			short: function(qty:Float) harness.orders.short(bar().close, qty),
			flat: function() harness.orders.flat(bar().close),
			plot: function(v:Float, lid:Int) {
				harness.chart.plot(v, str(lid), null, bar().index);
			},
			/** hline ὁρίζουσα, bgcolor ὁ ἀὴρ, plotshape τὸ σῆμα. */
			plotshape: function(lid:Int) {
				harness.chart.plotshape(str(lid), bar().index);
			},
			hline: function(v:Float, lid:Int) {
				harness.chart.hline(v, str(lid));
			},
			bgcolor: function(cid:Int) {
				harness.chart.bgcolor(str(cid), bar().index);
			}
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

	static function compileJs(prog:MuseProgram, mod:Dynamic, strings:Array<String>):BarStrategyFn {
		return function(ctx:Dynamic):Dynamic {
			var harness:HarnessContext =
				Std.isOfType(ctx, HarnessContext) ? cast ctx : new HarnessContext();
			var feed:BarFeed = Reflect.hasField(ctx, "feed")
				? Reflect.field(ctx, "feed")
				: BarFeed.synthetic(200, 1);
			var seed = new MuseInterp(harness);
			for (d in prog.decls) seed.registerDeclPublic(d);

			var barRef:Array<Bar> = [null];
			var env = makeEnv(harness, barRef, strings);
			var inst:Dynamic = js.Syntax.code("new WebAssembly.Instance({0}, {1})", mod, { env: env });
			var onBarFn:Dynamic = Reflect.field(inst.exports, "on_bar");

			return harness.runBacktest(function(bar:Bar) {
				TradeBuiltins.beginBar();
				barRef[0] = bar;
				onBarFn();
			}, feed);
		};
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

	static function compilePython(prog:MuseProgram, wat:String, strings:Array<String>):BarStrategyFn {
		return function(ctx:Dynamic):Dynamic {
			var harness:HarnessContext =
				Std.isOfType(ctx, HarnessContext) ? cast ctx : new HarnessContext();
			var feed:BarFeed = Reflect.hasField(ctx, "feed")
				? Reflect.field(ctx, "feed")
				: BarFeed.synthetic(200, 1);
			var seed = new MuseInterp(harness);
			for (d in prog.decls) seed.registerDeclPublic(d);

			try {
				NumbaBackend.ensurePathPublic();
				python.Syntax.code("import muse_math_runtime as _mmr");
				var barRef:Array<Bar> = [null];
				var env = makeEnv(harness, barRef, strings);
				var loader:Dynamic = python.Syntax.code("_mmr.load_strategy_on_bar");
				var onBarFn:Dynamic = Reflect.callMethod(null, loader, [wat, env]);
				return harness.runBacktest(function(bar:Bar) {
					TradeBuiltins.beginBar();
					barRef[0] = bar;
					Reflect.callMethod(null, onBarFn, []);
				}, feed);
			} catch (e:Dynamic) {
				trace("StrategyWasm Python wasmtime failed: " + Std.string(e));
				return runInterp(prog, ctx);
			}
		};
	}
	#end
}
