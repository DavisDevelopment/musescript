package musescript.runtime;

import musescript.harness.HarnessContext;

/**
 * Adapt Muse `FnClosure` values into host callables for HOF builtins
 * (`map` / `filter` / `zipWith` / …) that expect `Reflect.isFunction`.
 */
class Callables {
	public static function asHost1(f:Dynamic, harness:HarnessContext):Dynamic->Dynamic {
		if (Reflect.isFunction(f)) return cast f;
		if (Std.isOfType(f, FnClosure)) {
			return function(x:Dynamic):Dynamic {
				return invoke(harness, f, [x]);
			};
		}
		throw "Callables.asHost1: expected function";
	}

	public static function asHostPred(f:Dynamic, harness:HarnessContext):Dynamic->Bool {
		var host = asHost1(f, harness);
		return function(x:Dynamic):Bool {
			return host(x) == true;
		};
	}

	public static function asHost2(f:Dynamic, harness:HarnessContext):Dynamic->Dynamic->Dynamic {
		if (Reflect.isFunction(f)) return cast f;
		if (Std.isOfType(f, FnClosure)) {
			return function(a:Dynamic, b:Dynamic):Dynamic {
				return invoke(harness, f, [a, b]);
			};
		}
		throw "Callables.asHost2: expected function";
	}

	static function invoke(harness:HarnessContext, f:Dynamic, args:Array<Dynamic>):Dynamic {
		if (harness == null || harness.invokeUserFn == null)
			throw "Callables: no invokeUserFn (FnClosure outside strategy run)";
		return harness.invokeUserFn(f, args);
	}
}
