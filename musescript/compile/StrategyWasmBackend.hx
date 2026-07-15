package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.BarStrategyFn;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;
import musescript.interp.MuseInterp;

/**
 * Compile on-bar strategies to WebAssembly with exported linear memory.
 * Dual execution modes:
 *   streaming  — reset(capacity) + push_bar(o,h,l,c,v,t,i) per bar
 *   preloaded  — host packs OHLCV into memory, configure_tape(...), on_bar(index)
 * Host ABI is side-effects only: get_param / long / short / flat / plot*.
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

	static function seedParams(prog:MuseProgram, harness:HarnessContext):Void {
		var seed = new MuseInterp(harness);
		for (d in prog.decls) switch (d) {
			case ParamDecl(_, _, _): seed.registerDeclPublic(d);
			default:
		}
	}

	/** Side-effect HostABI only — charts + orders + params. */
	static function makeEnv(harness:HarnessContext, barRef:Array<Bar>, strings:Array<String>):Dynamic {
		function str(i:Int):String {
			return i >= 0 && i < strings.length ? strings[i] : "close";
		}
		function bar():Bar return barRef[0];
		return {
			get_param: function(id:Int) {
				var n = str(id);
				return harness.params.all().exists(n) ? harness.params.get(n) : 0.0;
			},
			long: function(qty:Float) harness.orders.long(bar().close, Math.isNaN(qty) ? null : qty),
			short: function(qty:Float) harness.orders.short(bar().close, Math.isNaN(qty) ? null : qty),
			flat: function() harness.orders.flat(bar().close),
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
			seedParams(prog, harness);

			var barRef:Array<Bar> = [null];
			var env = makeEnv(harness, barRef, strings);
			var inst:Dynamic = js.Syntax.code("new WebAssembly.Instance({0}, {1})", mod, { env: env });
			var exports:Dynamic = inst.exports;
			var n = feed.length();
			if (n <= 0) n = 1;

			if (preferPreloaded) {
				return runPreloadedJs(harness, feed, exports, barRef, ctx, strings);
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
		ctx:Dynamic, strings:Array<String>
	):Dynamic {
		var bars = feed.all();
		var n = bars.length;
		if (n <= 0) n = 1;
		var featureTapes = featureTapesFromCtx(ctx, strings);
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
		// Drive through harness so equity marks / series keep working for charts
		var idx = 0;
		return harness.runBacktest(function(bar:Bar) {
			barRef[0] = bar;
			Reflect.callMethod(null, onBar, [idx]);
			idx++;
		}, feed);
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
			seedParams(prog, harness);

			try {
				NumbaBackend.ensurePathPublic();
				python.Syntax.code("import muse_math_runtime as _mmr");
				var barRef:Array<Bar> = [null];
				var env = makeEnv(harness, barRef, strings);
				var loader:Dynamic = python.Syntax.code("_mmr.load_strategy_module");
				var mod:Dynamic = Reflect.callMethod(null, loader, [wat, env]);
				var n = feed.length();
				if (n <= 0) n = 1;
				if (preferPreloaded) {
					return runPreloadedPy(harness, feed, mod, barRef, ctx, strings);
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
		ctx:Dynamic, strings:Array<String>
	):Dynamic {
		var bars = feed.all();
		var pack:Dynamic = Reflect.field(mod, "pack_and_configure");
		Reflect.callMethod(null, pack, [bars, featureTapesFromCtx(ctx, strings)]);
		var onBar:Dynamic = Reflect.field(mod, "on_bar");
		var idx = 0;
		return harness.runBacktest(function(bar:Bar) {
			barRef[0] = bar;
			Reflect.callMethod(null, onBar, [idx]);
			idx++;
		}, feed);
	}
	#end

	static function featureTapesFromCtx(ctx:Dynamic, strings:Array<String>):Array<Array<Float>> {
		var count = musescript.kestrel.KestrelWasmArtifact.featureCount(strings);
		if (count == 0) return [];
		if (ctx != null && Reflect.hasField(ctx, "kestrelFeatureTapes")) {
			var supplied:Dynamic = Reflect.field(ctx, "kestrelFeatureTapes");
			if (Std.isOfType(supplied, Array)) return cast supplied;
		}
		return [for (_ in 0...count) []];
	}
}
