package musescript.compile;

import musescript.ast.MuseProgram;

/**
 * Compile math-only Muse functions to WebAssembly.
 *
 * Series params are packed into exported linear memory; the wasm function takes
 * (base, len) i32 pairs per series, then scalar args.
 */
class WasmBackend {
	public static function emitWat(prog:MuseProgram, name:String):Null<String> {
		var fn = MathOnly.find(prog, name);
		if (fn == null) return null;
		return new WasmEmitter().emitFn(fn);
	}

	public static function seriesArgs(prog:MuseProgram, name:String):Array<String> {
		var fn = MathOnly.find(prog, name);
		if (fn == null) return [];
		return new WasmEmitter().seriesArgNames(fn);
	}

	public static function compileFn(prog:MuseProgram, name:String):Null<Dynamic> {
		var fn = MathOnly.find(prog, name);
		if (fn == null) return null;
		var emitter = new WasmEmitter();
		var series = emitter.seriesArgNames(fn);
		var wat = emitter.emitFn(fn);
		if (wat == null) return null;
		#if python
		return loadPython(wat, name, fn.args, series);
		#elseif js
		return loadJs(wat, name, fn.args, series);
		#else
		return null;
		#end
	}

	#if python
	static function loadPython(wat:String, name:String, args:Array<String>, series:Array<String>):Dynamic {
		try {
			NumbaBackend.ensurePathPublic();
			python.Syntax.code("import muse_math_runtime as _mmr");
			var loader:Dynamic = python.Syntax.code("_mmr.load_wasm_fn");
			var pyFn:Dynamic = Reflect.callMethod(null, loader, [wat, name, args, series]);
			return function(callArgs:Array<Dynamic>):Dynamic {
				return Reflect.callMethod(null, pyFn, callArgs);
			};
		} catch (e:Dynamic) {
			trace("WasmBackend Python load failed: " + Std.string(e));
			return null;
		}
	}
	#end

	#if js
	static function loadJs(wat:String, name:String, argNames:Array<String>, series:Array<String>):Dynamic {
		try {
			var fs:Dynamic = js.Syntax.code("require('fs')");
			var path:Dynamic = js.Syntax.code("require('path')");
			var cp:Dynamic = js.Syntax.code("require('child_process')");
			fs.mkdirSync("build/wasm", { recursive: true });
			var watPath:String = path.join("build", "wasm", name + ".wat");
			var wasmPath:String = path.join("build", "wasm", name + ".wasm");
			fs.writeFileSync(watPath, wat);
			var py:String = path.join(".venv", "Scripts", "python.exe");
			if (!fs.existsSync(py)) py = path.join(".venv", "bin", "python");
			var script:String = path.join("tools", "wat2wasm_cli.py");
			var spawn:Dynamic = cp.spawnSync(py, [script, watPath, wasmPath], { encoding: "utf8" });
			if (spawn.status != 0) {
				trace("wat2wasm failed: " + Std.string(spawn.stderr));
				return null;
			}
			var buf:Dynamic = fs.readFileSync(wasmPath);
			var mod:Dynamic = js.Syntax.code("new WebAssembly.Module({0})", buf);
			var hasSeries = series.length > 0;
			var env:Dynamic = {
				sin: Math.sin, cos: Math.cos, sqrt: Math.sqrt, abs: Math.abs,
				exp: Math.exp, log: Math.log, floor: Math.floor, ceil: Math.ceil,
				tan: Math.tan, round: Math.round
			};
			var inst:Dynamic = js.Syntax.code("new WebAssembly.Instance({0}, {1})", mod, { env: env });
			var func:Dynamic = Reflect.field(inst.exports, name);
			var memory:Dynamic = hasSeries ? Reflect.field(inst.exports, "memory") : null;

			return function(callArgs:Array<Dynamic>):Dynamic {
				var arrays:Map<String, Array<Float>> = new Map();
				var scalars:Array<Dynamic> = [];
				for (i in 0...argNames.length) {
					var an = argNames[i];
					if (series.indexOf(an) >= 0) {
						arrays.set(an, cast callArgs[i]);
					} else {
						scalars.push(callArgs[i]);
					}
				}

				if (!hasSeries) {
					return Reflect.callMethod(null, func, scalars);
				}

				var totalBytes = 0;
				var layout:Array<{name:String, offset:Int, arr:Array<Float>}> = [];
				for (sn in series) {
					var arr:Array<Float> = arrays.get(sn);
					layout.push({ name: sn, offset: totalBytes, arr: arr });
					totalBytes += arr.length * 8;
				}
				var needPages = Std.int(Math.ceil(totalBytes / 65536.0));
				if (needPages < 1) needPages = 1;
				var curPages:Int = Std.int(memory.buffer.byteLength / 65536);
				if (needPages > curPages) memory.grow(needPages - curPages);

				var view:Dynamic = js.Syntax.code("new Float64Array({0}.buffer)", memory);
				for (slot in layout) {
					var baseIdx = Std.int(slot.offset / 8);
					js.Syntax.code("({0}).set({1}, {2})", view, slot.arr, baseIdx);
				}

				var wasmArgs:Array<Dynamic> = [];
				for (slot in layout) {
					wasmArgs.push(slot.offset);
					wasmArgs.push(slot.arr.length);
				}
				for (s in scalars) wasmArgs.push(s);
				return Reflect.callMethod(null, func, wasmArgs);
			};
		} catch (e:Dynamic) {
			trace("WasmBackend JS load failed: " + Std.string(e));
			return null;
		}
	}
	#end
}
