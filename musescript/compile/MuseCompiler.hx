package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.BarStrategyFn;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.interp.MuseInterp;

/**
 * Compile MuseAST → callable strategy.
 *
 * Strategy compile targets (MuseCompiler.compile):
 * - "js" (default) — JsEmitter hot path + eval on JS; MuseInterp elsewhere
 * - "haxe"         — HaxeEmitter source; MuseInterp execution (AOT pending)
 * - "wasm"         — StrategyWasmBackend on-bar WAT (subset) on JS/Python(wasmtime); MuseInterp fallback
 * - "native"       — not implemented; MuseInterp fallback with trace
 *
 * Math-only wasm lives in MathCompiler / WasmBackend (unrelated to strategy targets).
 */
class MuseCompiler {
	/** Backend used by the last compile() / compileEx() call. */
	public static var lastBackend:String = "interp";

	public static function compile(prog:MuseProgram, ?opts:{?target:String, ?strict:Bool}):BarStrategyFn {
		return compileEx(prog, opts).fn;
	}

	public static function compileEx(prog:MuseProgram, ?opts:{?target:String, ?strict:Bool}):CompileEx {
		var target = opts != null && opts.target != null ? opts.target : "js";
		var strict = opts != null && opts.strict == true;
		prog = GeneratorLower.lower(prog);
		prog = TailCallPass.transform(prog);
		var result = switch (target) {
			case "haxe":
				var fn = HaxeBackend.compile(prog);
				var emitted = HaxeBackend.emitSource(prog) != null;
				{ fn: fn, backend: emitted ? "haxe" : "interp", emitted: emitted };
			case "wasm":
				var wat = StrategyWasmBackend.emitWat(prog);
				var fn = StrategyWasmBackend.compile(prog);
				{ fn: fn, backend: wat != null ? "wasm" : "interp", emitted: wat != null };
			case "native":
				trace('MuseCompiler: target "native" not implemented — MuseInterp fallback');
				{ fn: interpOnly(prog), backend: "interp", emitted: false };
			default:
				var fn = JsBackend.compile(prog);
				#if js
				var backend = JsBackend.lastBackend;
				{ fn: fn, backend: backend, emitted: backend == "js" };
				#else
				// JS emission can't execute on this host — report interp.
				{ fn: fn, backend: "interp", emitted: false };
				#end
		};
		lastBackend = result.backend;
		if (strict && !result.emitted)
			throw 'MuseCompiler: strict compile failed for target "$target" (fell back to MuseInterp)';
		return result;
	}

	static function interpOnly(prog:MuseProgram):BarStrategyFn {
		return function(ctx:Dynamic):Dynamic {
			var harness:HarnessContext =
				Std.isOfType(ctx, HarnessContext) ? cast ctx : new HarnessContext();
			var feed:BarFeed = Reflect.hasField(ctx, "feed")
				? Reflect.field(ctx, "feed")
				: BarFeed.synthetic(200, 1);
			var seed = new MuseInterp(harness);
			for (d in prog.decls) seed.registerDeclPublic(d);
			return new MuseInterp(harness).runBacktest(prog, feed);
		};
	}
}
