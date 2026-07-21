package musescript.builtins;

import musescript.harness.HarnessContext;
import musescript.indicators.IndicatorRegistry;

/**
 * The MuseScript `ta` toolbelt: one namespaced global object carrying every
 * ported Wickra indicator plus its generated MuseScript source (TaSources).
 * Installed alongside the flat builtins by MuseInterp/JsBackend exactly the
 * way the `Math` global already is — a plain object whose fields are
 * callables, which both execution paths dispatch through their existing
 * `obj.field(...)` machinery, so this adds NO new language surface.
 *
 * In-language use:
 *
 *   var m = ta.cmo(close, 14);        // same builtin the flat `cmo` is
 *   ta.names()                        // StringArray of every ta indicator
 *   ta.has("stoch_rsi")               // Bool
 *   ta.source("stoch_rsi")            // generated MuseScript demo source
 *   ta.sig("stoch_rsi")               // "stoch_rsi(Series, Window, ...) -> Scalar"
 *   ta.doc("stoch_rsi")               // one-line description
 *
 * Wholly registry-driven: no per-indicator edit ever lands here (same
 * discipline as WickraBuiltins — see IndicatorSpec.hx).
 */
class TaToolbelt {
	public static function install(vars:Map<String, Dynamic>, harness:HarnessContext):Void {
		vars.set("ta", build(harness));
	}

	/** The `ta` object itself — shared by MuseInterp globals and JsBackend frame installs. */
	public static function build(harness:HarnessContext):Dynamic {
		var ta:Dynamic = {};
		for (name => spec in IndicatorRegistry.all()) {
			var s = spec;
			Reflect.setField(ta, name,
				Reflect.makeVarArgs(function(args:Array<Dynamic>) return s.eval(harness, args)));
		}
		Reflect.setField(ta, "names", function():Array<String> return TaSources.names());
		Reflect.setField(ta, "has", function(name:Dynamic):Bool return TaSources.has(Std.string(name)));
		Reflect.setField(ta, "source", function(name:Dynamic):String {
			var e = TaSources.get(Std.string(name));
			return e == null ? null : e.source;
		});
		Reflect.setField(ta, "sig", function(name:Dynamic):String {
			var e = TaSources.get(Std.string(name));
			return e == null ? null : e.sig;
		});
		Reflect.setField(ta, "doc", function(name:Dynamic):String {
			var e = TaSources.get(Std.string(name));
			return e == null ? null : e.doc;
		});
		// Null when this indicator has no hand-authored native MuseScript reimplementation
		// yet (the current majority) -- see TaSourceEntry.nativeSource's doc comment.
		Reflect.setField(ta, "nativeSource", function(name:Dynamic):String {
			var e = TaSources.get(Std.string(name));
			return e == null ? null : e.nativeSource;
		});
		return ta;
	}
}
