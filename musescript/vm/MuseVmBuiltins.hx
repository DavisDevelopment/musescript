package musescript.vm;

import musescript.harness.HarnessContext;
import musescript.builtins.TradeBuiltins;
import musescript.builtins.macro.MacroBuiltins;
import musescript.builtins.WickraBuiltins;
import musescript.builtins.TaToolbelt;
import musescript.interp.MuseExtensions;

/**
 * The builtin/stdlib global environment for the Tier-A VM — a **verbatim mirror**
 * of `MuseInterp.installBuiltins` so `CALL_BUILTIN` resolves the exact same
 * functions the interp's `calleeValue`/`resolve` would (parity crux, §V3). Same
 * install order, same functions, bound to the same `HarnessContext`. Kept a
 * standalone helper (not a method on either MuseVm or the compiler) so both the
 * runtime globals and the compiler's capability check share one impl and can't
 * drift. The V2 parity gate polices any drift from the interp's copy.
 */
class MuseVmBuiltins {
	public static function install(globals:Map<String, Dynamic>, harness:HarnessContext):Void {
		globals.set("null", null);
		globals.set("true", true);
		globals.set("false", false);
		globals.set("trace", function(v:Dynamic) {
			harness.pushLog(Std.string(v));
			#if js
			untyped console.log(v);
			#else
			Sys.println(Std.string(v));
			#end
		});
		TradeBuiltins.install(globals, harness);
		MacroBuiltins.install(globals, harness);
		WickraBuiltins.install(globals, harness);
		TaToolbelt.install(globals, harness);
		MuseExtensions.installAll(globals, harness);
		globals.set("Math", {
			abs: Math.abs, min: Math.min, max: Math.max, sqrt: Math.sqrt, pow: Math.pow,
			floor: Math.floor, ceil: Math.ceil, round: Math.round, sin: Math.sin, cos: Math.cos,
			log: Math.log, exp: Math.exp, NaN: Math.NaN, PI: Math.PI
		});
	}

	/** A fresh globals bound to a scratch harness — for compile-time capability
	 * checks (is `name` a plain-function builtin?) where no real harness exists. */
	public static function scratch():Map<String, Dynamic> {
		var g = new Map<String, Dynamic>();
		install(g, new HarnessContext());
		return g;
	}
}
