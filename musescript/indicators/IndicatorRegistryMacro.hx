package musescript.indicators;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

/**
 * Compile-time collector for the indicator registry (ROADMAP.md epic 9).
 * Scans `musescript/indicators/lib/` at build time, and for every class there
 * exposing a `static function spec():IndicatorSpec`, emits a call to it into
 * one array literal. Result: adding an indicator is literally "drop a file in
 * lib/" — nothing hand-maintained enumerates them, so parallel porting of the
 * remaining ~450 never produces a merge conflict on a shared list.
 *
 * Same technique as BuiltinDocsMacro, but directory-scanned rather than an
 * explicit class list (the whole point here is that the list is never written
 * by hand).
 */
class IndicatorRegistryMacro {
	static inline var LIB_DIR = "musescript/indicators/lib";
	static inline var LIB_PACK = "musescript.indicators.lib.";

	public static macro function collect():Expr {
		var calls:Array<Expr> = [];
		var dir = resolveLibDir();
		if (dir == null) {
			Context.warning("IndicatorRegistryMacro: lib/ dir not found on classpath; registry will be empty", Context.currentPos());
			return macro [];
		}
		var files = sys.FileSystem.readDirectory(dir);
		files.sort(Reflect.compare); // deterministic registration order
		for (f in files) {
			if (!StringTools.endsWith(f, ".hx")) continue;
			var typeName = f.substr(0, f.length - 3);
			var path = LIB_PACK + typeName;
			var t = try Context.getType(path) catch (e:Dynamic) null;
			if (t == null) continue;
			switch (t) {
				case TInst(clsRef, _):
					var cls = clsRef.get();
					var hasSpec = false;
					for (s in cls.statics.get()) if (s.name == "spec") { hasSpec = true; break; }
					if (!hasSpec) continue;
					// musescript.indicators.lib.Foo.spec()
					calls.push(macro $p{path.split(".").concat(["spec"])}());
				default:
			}
		}
		return macro $a{calls};
	}

	#if macro
	static function resolveLibDir():Null<String> {
		// Try each classpath root + the known relative path.
		for (cp in Context.getClassPath()) {
			var candidate = (cp == "" ? "" : cp) + LIB_DIR;
			if (sys.FileSystem.exists(candidate) && sys.FileSystem.isDirectory(candidate))
				return candidate;
		}
		if (sys.FileSystem.exists(LIB_DIR) && sys.FileSystem.isDirectory(LIB_DIR)) return LIB_DIR;
		return null;
	}
	#end
}
