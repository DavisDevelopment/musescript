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
		// builtin name (from the `name:` literal in each spec()) -> declaring class, for the
		// duplicate check below.
		var claimed = new Map<String, String>();
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
					checkDuplicateName(dir, f, typeName, claimed);
					// musescript.indicators.lib.Foo.spec()
					calls.push(macro $p{path.split(".").concat(["spec"])}());
				default:
			}
		}
		return macro $a{calls};
	}

	#if macro
	/** `name: "..."` as it appears in a `spec()` object literal. */
	static var NAME_RE = ~/name\s*:\s*"([A-Za-z0-9_.]+)"\s*,\s*args\s*:/;

	/**
	 * Fail the BUILD when two lib/ classes claim the same builtin `name:`.
	 *
	 * `IndicatorRegistry.ensure` also throws on this, which is the authoritative check (it
	 * sees the real evaluated specs). This one exists purely for feedback latency: a
	 * directory-scanned registry filled by large parallel port batches is exactly the setup
	 * where a name collision is easy to introduce and invisible in review, and catching it at
	 * compile time beats catching it on first run.
	 *
	 * Reads the `name:` literal out of the source text rather than evaluating `spec()` —
	 * `spec()` bodies close over `IndicatorCache` and a live harness, so they cannot be run
	 * at macro time. A source scan can only MISS a name (non-literal / unusual formatting),
	 * never invent one, so a miss degrades to "the runtime check catches it" and never to a
	 * false build failure. All 452 current specs match the pattern.
	 */
	static function checkDuplicateName(dir:String, file:String, typeName:String, claimed:Map<String, String>):Void {
		var src = try sys.io.File.getContent(dir + "/" + file) catch (e:Dynamic) null;
		if (src == null || !NAME_RE.match(src)) return; // unreadable / non-literal — runtime check owns it
		var name = NAME_RE.matched(1);
		var prior = claimed.get(name);
		if (prior != null) {
			Context.error('IndicatorRegistryMacro: duplicate indicator name "$name" — declared by '
				+ 'both $prior and $typeName in musescript/indicators/lib/. The registry is a '
				+ 'Map keyed by name, so one of them would be silently unreachable. Rename one.',
				Context.currentPos());
		}
		claimed.set(name, typeName);
	}

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
