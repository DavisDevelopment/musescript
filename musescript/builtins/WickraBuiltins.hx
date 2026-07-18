package musescript.builtins;

import musescript.harness.HarnessContext;
import musescript.indicators.IndicatorRegistry;

/**
 * Installs every registered indicator port (musescript/indicators/lib/, via
 * IndicatorRegistry) as a MuseScript builtin. Wholly data-driven: this file
 * gains NO per-indicator edit — adding an indicator means dropping a file in
 * lib/ with a `spec()`, and it shows up here, in BuiltinSigs, and in
 * JsBackend dispatch automatically (all three read the same registry). See
 * ROADMAP.md epic 9 and IndicatorSpec.hx.
 */
class WickraBuiltins {
	public static function install(vars:Map<String, Dynamic>, harness:HarnessContext):Void {
		for (name => spec in IndicatorRegistry.all()) {
			var s = spec;
			vars.set(name, Reflect.makeVarArgs(function(args:Array<Dynamic>) return s.eval(harness, args)));
		}
	}
}
