package musescript.compile;

import musescript.ast.MuseProgram;

/**
 * Compile math-only Muse functions via Python interp or numba.njit.
 * Relies on tools/muse_math_runtime.py on sys.path (project tools/).
 */
class NumbaBackend {
	public static function compileFn(prog:MuseProgram, name:String, useNumba:Bool):Null<Dynamic> {
		var fn = MathOnly.find(prog, name);
		if (fn == null) return null;
		#if python
		return loadPython(fn, useNumba);
		#else
		return null;
		#end
	}

	public static function emitSource(prog:MuseProgram, name:String, useNumba:Bool):Null<String> {
		var fn = MathOnly.find(prog, name);
		if (fn == null) return null;
		return new PyEmitter().emitFn(fn, useNumba);
	}

	#if python
	static var pathReady:Bool = false;

	public static function ensurePathPublic():Void {
		if (pathReady) return;
		python.Syntax.code("import sys, os");
		python.Syntax.code("p = os.path.join(os.getcwd(), 'tools')");
		python.Syntax.code("(sys.path.insert(0, p) if os.path.isdir(p) and p not in sys.path else None)");
		python.Syntax.code("p2 = os.path.abspath('tools')");
		python.Syntax.code("(sys.path.insert(0, p2) if os.path.isdir(p2) and p2 not in sys.path else None)");
		pathReady = true;
	}

	static function loadPython(fn:MathFnDecl, useNumba:Bool):Dynamic {
		ensurePathPublic();
		var src = new PyEmitter().emitFn(fn, useNumba);
		python.Syntax.code("import muse_math_runtime as _mmr");
		var loader:Dynamic = useNumba
			? python.Syntax.code("_mmr.load_numba")
			: python.Syntax.code("_mmr.load_python");
		var pyFn:Dynamic = Reflect.callMethod(null, loader, [src, fn.name]);
		return function(args:Array<Dynamic>):Dynamic {
			return Reflect.callMethod(null, pyFn, args);
		};
	}
	#end
}
