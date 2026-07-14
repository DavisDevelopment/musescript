package musescript.compile;

import musescript.ast.MuseProgram;

/**
 * Compile math-only Muse functions to target callables.
 * Targets: "js" | "python" | "numba" | "wasm"
 */
class MathCompiler {
	public static function compile(prog:MuseProgram, name:String, ?opts:{?target:String}):Null<Dynamic> {
		var target = opts != null && opts.target != null ? opts.target : defaultTarget();
		return switch (target) {
			case "js": JsMathBackend.compileFn(prog, name);
			case "python": NumbaBackend.compileFn(prog, name, false);
			case "numba": NumbaBackend.compileFn(prog, name, true);
			case "wasm": WasmBackend.compileFn(prog, name);
			default: null;
		};
	}

	public static function emit(prog:MuseProgram, name:String, ?opts:{?target:String}):Null<String> {
		var target = opts != null && opts.target != null ? opts.target : defaultTarget();
		return switch (target) {
			case "js": JsMathBackend.emitSource(prog, name);
			case "python": NumbaBackend.emitSource(prog, name, false);
			case "numba": NumbaBackend.emitSource(prog, name, true);
			case "wasm": WasmBackend.emitWat(prog, name);
			default: null;
		};
	}

	static function defaultTarget():String {
		#if js
		return "js";
		#elseif python
		return "python";
		#else
		return "js";
		#end
	}
}
